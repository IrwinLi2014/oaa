-- Custom Hero: Sohei
-- Author: Firetoad
-- Date: 21/01/2018

-- This version is mostly for playtesting. There are still some things missing.

-- TODO: implement cooldown reduction detection for Dash charges (didn't do it so you guys can use the OAA method)
-- TODO: fix Dash charges' interaction with Refresher Orb/Shard when the ability is on cooldown
-- TODO: implement momentum stuns talent
-- TODO: remove comments on talent-related lines
-- TODO: momentum collision detection

Debug:EnableDebugging()

--------------------------------------
--  Common usage functions
--------------------------------------

sohei_functions = class({})

-- Performs a dash, automatically triggering momentum
function sohei_functions:Dash(caster, distance, speed, tree_radius)
  caster:RemoveModifierByName("modifier_sohei_dash_movement")
  local duration = distance / speed
  -- caster:EmitSound("DOTA_Item.ForceStaff.Activate")
  caster:EmitSound("Sohei.Dash")
  caster:StartGesture(ACT_DOTA_RUN)
  caster:AddNewModifier(nil, nil, "modifier_sohei_dash_movement", {duration = duration, distance = distance, tree_radius = tree_radius})
  self:TriggerMomentum(caster)
end


-- Triggers momentum on your next attack, if the ability was learned
function sohei_functions:TriggerMomentum(caster)
  if caster:FindAbilityByName("sohei_momentum") and caster:FindAbilityByName("sohei_momentum"):GetLevel() > 0 then
    local ability = caster:FindAbilityByName("sohei_momentum")
    caster:AddNewModifier(caster, ability, "modifier_sohei_momentum_buff", {})
  end
end

--------------------------------------
--  DASH
--------------------------------------

sohei_dash = class(AbilityBaseClass)

LinkLuaModifier("modifier_sohei_dash_free_turning", "abilities/hero_sohei", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_dash_movement", "abilities/hero_sohei", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_dash_charges", "abilities/hero_sohei", LUA_MODIFIER_MOTION_NONE)

function sohei_dash:GetIntrinsicModifierName()
  return "modifier_sohei_dash_free_turning"
end

function sohei_dash:OnUpgrade()
  if IsServer() then
    local modifier_charges = self:GetCaster():AddNewModifier(self:GetCaster(), self, "modifier_sohei_dash_charges", {})
    modifier_charges:SetStackCount(self:GetSpecialValueFor("max_charges"))
  end
end

function sohei_dash:OnSpellStart(ignore_dash)
  if IsServer() then
    local caster = self:GetCaster()

    if caster:FindModifierByName("modifier_sohei_dash_charges") then
      local modifier_charges = caster:FindModifierByName("modifier_sohei_dash_charges")

      -- Perform the dash if there is at least one charge remaining
      if modifier_charges:GetStackCount() >= 1 then
        if not ignore_dash then
          sohei_functions:Dash(caster, self:GetSpecialValueFor("dash_distance"), self:GetSpecialValueFor("dash_speed"), self:GetSpecialValueFor("tree_radius"))
        end
        modifier_charges:SetStackCount(modifier_charges:GetStackCount() - 2)
        modifier_charges:OnExpire()

        -- If this was not the last charge, put the ability on a short cooldown
        if modifier_charges:GetStackCount() > 0 then
          Timers:CreateTimer(0.03, function()
            self:EndCooldown()
            self:StartCooldown(0.25)
          end)

        -- Else, put it on cooldown until a charge comes back
        else
          Timers:CreateTimer(0.03, function()
            self:EndCooldown()
            self:StartCooldown(modifier_charges:GetRemainingTime())
          end)
        end

      -- Else, refund costs
      else
        self:RefundManaCost()
        Timers:CreateTimer(0.03, function()
          self:EndCooldown()
        end)
      end
    else
      -- Reduce the charge recovery time if the appropriate talent is learned
      if caster:FindAbilityByName("special_bonus_sohei_dash_recharge"):GetLevel() > 0 then
        local cooldown_reduction = caster:FindAbilityByName("special_bonus_sohei_dash_recharge"):GetSpecialValueFor("value")
        caster:AddNewModifier(caster, self, "modifier_sohei_dash_charges", {
          duration = math.max(self:GetSpecialValueFor("charge_restore_time") - cooldown_reduction, 1)
        })
      else
        caster:AddNewModifier(caster, self, "modifier_sohei_dash_charges", {
          duration = self:GetSpecialValueFor("charge_restore_time")
        })
      end
    end
  end
end

function sohei_dash:OnRefresh()
  if IsServer() then
    local modifier_charges = self:GetCaster():FindModifierByName("modifier_sohei_dash_charges")
    modifier_charges:SetStackCount(math.min(modifier_charges:GetStackCount() + 1, self:GetSpecialValueFor("max_charges")))
  end
end


-- Dash free turning modifier
modifier_sohei_dash_free_turning = class(ModifierBaseClass)

function modifier_sohei_dash_free_turning:IsDebuff() return false end
function modifier_sohei_dash_free_turning:IsHidden() return true end
function modifier_sohei_dash_free_turning:IsPurgable() return false end
function modifier_sohei_dash_free_turning:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function modifier_sohei_dash_free_turning:DeclareFunctions()
  local funcs = {
    MODIFIER_PROPERTY_IGNORE_CAST_ANGLE
  }
  return funcs
end

function modifier_sohei_dash_free_turning:GetModifierIgnoreCastAngle()
  return 1
end


-- Dash charges modifier
modifier_sohei_dash_charges = class(ModifierBaseClass)

function modifier_sohei_dash_charges:IsDebuff() return false end
function modifier_sohei_dash_charges:IsDebuff() return false end
function modifier_sohei_dash_charges:IsHidden() return false end
function modifier_sohei_dash_charges:IsPurgable() return false end
function modifier_sohei_dash_charges:RemoveOnDeath() return false end
function modifier_sohei_dash_charges:DestroyOnExpire() return false end
function modifier_sohei_dash_charges:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function modifier_sohei_dash_charges:OnCreated()
  if IsServer() then
    self:StartIntervalThink(0.1)
  end
end
function modifier_sohei_dash_charges:OnRefresh()
  if IsServer() then
    self:StartIntervalThink(0.1)
  end
end

function modifier_sohei_dash_charges:OnIntervalThink()
  if IsServer() then
    if self:GetRemainingTime() <= 0 then
      self:OnExpire()
    end
  end
end

function modifier_sohei_dash_charges:OnExpire()
  if IsServer() then
    local caster = self:GetCaster()

    -- If the maximum charges are reached, stop the modifier's timer
    local max_charges = self:GetAbility():GetSpecialValueFor("max_charges")
    if self:GetStackCount() >= (max_charges - 1) then
      self:SetStackCount(max_charges)
      self:SetDuration(-1, true)
      self:StartIntervalThink(-1)
    else
      -- Reduce the charge recovery time if the appropriate talent is learned
      local duration = self:GetAbility():GetSpecialValueFor("charge_restore_time")
      if caster:FindAbilityByName("special_bonus_sohei_dash_recharge"):GetLevel() > 0 then
        local cooldown_reduction = caster:FindAbilityByName("special_bonus_sohei_dash_recharge"):GetSpecialValueFor("value")
        duration = math.max(duration - cooldown_reduction, 1)
      end
      self:SetStackCount(self:GetStackCount() + 1)
      self:SetDuration(duration, true)
      self:StartIntervalThink(0.1)
    end
  end
end

-- Dash movement modifier
modifier_sohei_dash_movement = class(ModifierBaseClass)

function modifier_sohei_dash_movement:IsDebuff() return false end
function modifier_sohei_dash_movement:IsHidden() return true end
function modifier_sohei_dash_movement:IsPurgable() return false end
function modifier_sohei_dash_movement:IsStunDebuff() return false end
function modifier_sohei_dash_movement:IsMotionController() return true end
function modifier_sohei_dash_movement:GetMotionControllerPriority() return DOTA_MOTION_CONTROLLER_PRIORITY_HIGHEST end

function modifier_sohei_dash_movement:CheckState()
  local state = {
    [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
    [MODIFIER_STATE_ROOTED] = true,
    [MODIFIER_STATE_INVULNERABLE] = true,
    [MODIFIER_STATE_NO_HEALTH_BAR] = true,
    [MODIFIER_STATE_MAGIC_IMMUNE] = true
  }
  return state
end

function modifier_sohei_dash_movement:OnCreated(keys)
  if IsServer() then

    -- Movement parameters
    self:StartIntervalThink(0.03)
    self.direction = self:GetParent():GetForwardVector()
    self.movement_tick = self.direction * keys.distance / ( self:GetDuration() / 0.03 )
    self.tree_radius = keys.tree_radius

    -- Trail particle
    local caster = self:GetParent()
    local trail_pfx = ParticleManager:CreateParticle("particles/econ/items/juggernaut/bladekeeper_omnislash/_dc_juggernaut_omni_slash_trail.vpcf", PATTACH_CUSTOMORIGIN, caster)
    ParticleManager:SetParticleControl(trail_pfx, 0, caster:GetAbsOrigin())
    ParticleManager:SetParticleControl(trail_pfx, 1, caster:GetAbsOrigin() + caster:GetForwardVector() * 300)
    ParticleManager:ReleaseParticleIndex(trail_pfx)
  end
end

function modifier_sohei_dash_movement:OnDestroy()
  if IsServer() then
    self:GetParent():FadeGesture(ACT_DOTA_RUN)
    ResolveNPCPositions(self:GetParent():GetAbsOrigin(), 128)
  end
end

function modifier_sohei_dash_movement:OnIntervalThink()
  if IsServer() then
    local unit = self:GetParent()
    local position = unit:GetAbsOrigin()
    GridNav:DestroyTreesAroundPoint(position, self.tree_radius, false)
    unit:SetAbsOrigin(GetGroundPosition(position + self.movement_tick, unit))
  end
end

--------------------------------------
--  GUARD
--------------------------------------

sohei_guard = class(AbilityBaseClass)
LinkLuaModifier("modifier_sohei_guard_reflect", "abilities/hero_sohei", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_guard_knockback", "abilities/hero_sohei", LUA_MODIFIER_MOTION_NONE)

function sohei_guard:OnToggle()
  if IsServer() then
    if self:GetToggleState() then
      self:ToggleAbility()
    else
      return
    end

    local caster = self:GetCaster()

    -- Check if there are enough charges to cast the ability, if the caster is stunned
    if caster:IsStunned() then
      if caster:FindModifierByName("modifier_sohei_dash_charges") then
        local modifier_charges = caster:FindModifierByName("modifier_sohei_dash_charges")
        if modifier_charges:GetStackCount() < 2 then
          self:RefundManaCost()
          Timers:CreateTimer(0.03, function()
            self:EndCooldown()
          end)
          return nil
        else
          modifier_charges:SetStackCount(modifier_charges:GetStackCount() - 1)
          caster:FindAbilityByName("sohei_dash"):OnSpellStart(true)
        end
      else
        self:RefundManaCost()
        Timers:CreateTimer(0.03, function()
          self:EndCooldown()
        end)
        return nil
      end
    end

    -- Hard Dispel
    caster:Purge(false, true, false, true, true)

    -- Start spinning animation
    caster:StartGesture(ACT_DOTA_OVERRIDE_ABILITY_1)

    -- Play guard sound
    caster:EmitSound("Sohei.Guard")

    --Apply Linken's + Lotus Orb + Attack reflect modifier for 2 seconds
    local duration = self:GetSpecialValueFor("guard_duration")
    caster:AddNewModifier(caster, self, "modifier_item_sphere_target", {duration = duration})
    caster:AddNewModifier(caster, self, "modifier_item_lotus_orb_active", {duration = duration})
    caster:AddNewModifier(caster, self, "modifier_sohei_guard_reflect", {duration = duration})

    -- Stop the animation after one spin
    Timers:CreateTimer(0.21, function()
      caster:FadeGesture(ACT_DOTA_OVERRIDE_ABILITY_1)
    end)

    -- Reduce the charge recovery time if the appropriate talent is learned
    if caster:FindAbilityByName("special_bonus_sohei_guard_knockback"):GetLevel() > 0 then
      -- If there is at least one target to attack, hit it
      local radius = caster:FindAbilityByName("special_bonus_sohei_guard_knockback"):GetSpecialValueFor("value")
      local targets = FindUnitsInRadius(caster:GetTeamNumber(),
        caster:GetAbsOrigin(),
        nil,
        radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE + DOTA_UNIT_TARGET_FLAG_NO_INVIS + DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE,
        FIND_ANY_ORDER,
        false)

      for _,target in ipairs(targets) do
        self:PushAwayEnemy(target)
      end
    end
  end
end

function sohei_guard:PushAwayEnemy (target)
  local caster = self:GetCaster()
  local casterposition = caster:GetAbsOrigin()
  local targetposition = target:GetAbsOrigin()
  local radius = caster:FindAbilityByName("special_bonus_sohei_guard_knockback"):GetSpecialValueFor("value")

  local vVelocity = casterposition - targetposition
  vVelocity.z = 0.0

  local distance = radius - vVelocity:Length2D() + caster:GetPaddedCollisionRadius()
  local duration = distance / self:GetSpecialValueFor("knockback_speed")

  target:AddNewModifier(caster, self, "modifier_sohei_guard_knockback", {
    duration = duration,
    distance = distance,

    tree_radius = target:GetPaddedCollisionRadius()
  })
end

function sohei_guard:OnProjectileHit_ExtraData(target, location, extra_data)
  if IsServer() and target then
    target:EmitSound("Sohei.GuardHit")
    ApplyDamage({victim = target, attacker = self:GetCaster(), damage = extra_data.damage, damage_type = DAMAGE_TYPE_PHYSICAL, ability = self})
  end
end


-- Guard projectile reflect modifier
modifier_sohei_guard_reflect = class(ModifierBaseClass)

function modifier_sohei_guard_reflect:IsDebuff() return false end
function modifier_sohei_guard_reflect:IsHidden() return false end
function modifier_sohei_guard_reflect:IsPurgable() return false end

function modifier_sohei_guard_reflect:DeclareFunctions()
  local funcs = {
    MODIFIER_PROPERTY_MIN_HEALTH,
    MODIFIER_EVENT_ON_ATTACK_LANDED
  }
  return funcs
end

function modifier_sohei_guard_reflect:GetMinHealth()
  return 1
end

function modifier_sohei_guard_reflect:OnAttackLanded(keys)
  if IsServer() then
    if keys.target == self:GetParent() then
      if keys.attacker:IsRangedAttacker() then

        -- Pre-heal for the damage done
        local parent = self:GetParent()
        local parent_armor = parent:GetPhysicalArmorValue()
        parent:Heal(keys.damage * (1 - parent_armor / (parent_armor + 20)), parent)

        -- Send the target's projectile back to them
        local attack_projectile = {
          Target        = keys.attacker,
          Source        = parent,
          Ability       = self:GetAbility(),
          EffectName      = keys.attacker:GetRangedProjectileName(),
          iMoveSpeed      = keys.attacker:GetProjectileSpeed(),
          vSpawnOrigin    = parent:GetAbsOrigin(),
          bDrawsOnMinimap   = false,
          bDodgeable      = true,
          bIsAttack       = false,
          bVisibleToEnemies   = true,
          bReplaceExisting  = false,
          flExpireTime    = GameRules:GetGameTime() + 30,
          bProvidesVision   = false,
          iSourceAttachment   = DOTA_PROJECTILE_ATTACHMENT_HITLOCATION,
          iVisionRadius     = 0,
          iVisionTeamNumber   = parent:GetTeamNumber(),
          ExtraData     = {damage = keys.damage}
        }
        ProjectileManager:CreateTrackingProjectile(attack_projectile)
        parent:EmitSound("Sohei.GuardProc")
      end
    end
  end
end

-- Dash movement modifier
modifier_sohei_guard_knockback = class(ModifierBaseClass)

function modifier_sohei_guard_knockback:IsDebuff() return false end
function modifier_sohei_guard_knockback:IsHidden() return true end
function modifier_sohei_guard_knockback:IsPurgable() return false end
function modifier_sohei_guard_knockback:IsStunDebuff() return false end
function modifier_sohei_guard_knockback:IsMotionController() return true end
function modifier_sohei_guard_knockback:GetMotionControllerPriority() return DOTA_MOTION_CONTROLLER_PRIORITY_HIGHEST end

function modifier_sohei_guard_knockback:CheckState()
  local state = {
    [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
    [MODIFIER_STATE_ROOTED] = true
  }
  return state
end

function modifier_sohei_guard_knockback:OnCreated(keys)
  if IsServer() then
    local unit = self:GetParent()
    local caster = self:GetCaster()

    local difference = unit:GetAbsOrigin() - caster:GetAbsOrigin()

    -- Movement parameters
    self:StartIntervalThink(0.03)
    self.direction = difference:Normalized()
    self.distance = keys.distance
    self.movement_tick = self.direction * self.distance / ( self:GetDuration() / 0.03 )
    self.tree_radius = keys.tree_radius

    -- Trail particle
    -- local trail_pfx = ParticleManager:CreateParticle("particles/econ/items/juggernaut/bladekeeper_omnislash/_dc_juggernaut_omni_slash_trail.vpcf", PATTACH_CUSTOMORIGIN, caster)
    -- ParticleManager:SetParticleControl(trail_pfx, 0, unit:GetAbsOrigin())
    -- ParticleManager:SetParticleControl(trail_pfx, 1, unit:GetAbsOrigin() + unit:GetForwardVector() * 300)
    -- ParticleManager:ReleaseParticleIndex(trail_pfx)
  end
end

function modifier_sohei_guard_knockback:OnDestroy()
  if IsServer() then
    ResolveNPCPositions(self:GetParent():GetAbsOrigin(), 128)
  end
end

function modifier_sohei_guard_knockback:OnIntervalThink()
  if IsServer() then
    local unit = self:GetParent()
    local position = unit:GetAbsOrigin() + self.movement_tick
    unit:SetAbsOrigin(GetGroundPosition(position, unit))
    GridNav:DestroyTreesAroundPoint(position, unit:GetPaddedCollisionRadius(), false)
  end
end

--------------------------------------
--  MOMENTUM
--------------------------------------

sohei_momentum = class(AbilityBaseClass)
LinkLuaModifier("modifier_sohei_momentum_passive", "abilities/hero_sohei.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_momentum_buff", "abilities/hero_sohei.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_momentum_knockback", "abilities/hero_sohei.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_momentum_stun", "abilities/hero_sohei.lua", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_sohei_momentum_slow", "abilities/hero_sohei.lua", LUA_MODIFIER_MOTION_NONE)

function sohei_momentum:GetIntrinsicModifierName()
  return "modifier_sohei_momentum_passive"
end

-- Momentum's passive modifier
modifier_sohei_momentum_passive = class(ModifierBaseClass)

function modifier_sohei_momentum_passive:IsHidden() return true end
function modifier_sohei_momentum_passive:IsPurgable() return false end
function modifier_sohei_momentum_passive:IsDebuff() return false end
function modifier_sohei_momentum_passive:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function modifier_sohei_momentum_passive:OnCreated(keys)
  if IsServer() then
    self:StartIntervalThink(0.03)
    self.distance_moved = 0
    self.position = self:GetParent():GetAbsOrigin()
  end
end

function modifier_sohei_momentum_passive:OnIntervalThink()
  if IsServer() then

    -- Update position
    local caster = self:GetParent()
    local old_position = self.position
    self.position = caster:GetAbsOrigin()

    -- If the active buff is not already present, check for its trigger condition
    if not self:GetParent():HasModifier("modifier_sohei_momentum_buff") then

      -- Update moved distance tally
      self.distance_moved = self.distance_moved + (self.position - old_position):Length2D()

      -- If enough distance has been covered, grant the buff
      if self.distance_moved >= self:GetAbility():GetSpecialValueFor("trigger_distance") then
        sohei_functions:TriggerMomentum(caster)
        self.distance_moved = 0
      end
    end
  end
end


-- Momentum's attack buff
modifier_sohei_momentum_buff = class(ModifierBaseClass)

function modifier_sohei_momentum_buff:IsHidden() return false end
function modifier_sohei_momentum_buff:IsPurgable() return false end
function modifier_sohei_momentum_buff:IsDebuff() return false end

function modifier_sohei_momentum_buff:DeclareFunctions()
  local funcs = {
    MODIFIER_EVENT_ON_ATTACK_LANDED,
    MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE
  }
  return funcs
end

function modifier_sohei_momentum_buff:OnAttackLanded(keys)
  if IsServer() then
    if keys.attacker == self:GetParent() and (not keys.target:IsBuilding()) then

      -- Consume the buff
      self:Destroy()

      -- Knock the enemy back
      local attacker = self:GetParent()
      local target = keys.target
      local ability = self:GetAbility()
      local distance = ability:GetSpecialValueFor("knockback_distance")
      local duration = distance / ability:GetSpecialValueFor("knockback_speed")
      local collision_radius = ability:GetSpecialValueFor("collision_radius")
      target:RemoveModifierByName("modifier_sohei_momentum_knockback")
      target:AddNewModifier(attacker, ability, "modifier_sohei_momentum_knockback", {
        duration = duration,
        distance = distance,
        collision_radius = collision_radius
      })

      -- Play the impact sound
      target:EmitSound("Sohei.Momentum")

      -- Play the impact particle
      local momentum_pfx = ParticleManager:CreateParticle("particles/hero/sohei/momentum.vpcf", PATTACH_ABSORIGIN_FOLLOW, target)
      ParticleManager:SetParticleControl(momentum_pfx, 0, target:GetAbsOrigin())
      ParticleManager:ReleaseParticleIndex(momentum_pfx)

      -- Reduce guard cd if they skilled the talent
      local guard = attacker:FindAbilityByName("sohei_guard")
      if attacker:FindAbilityByName("special_bonus_sohei_momentum_guard_cooldown"):GetLevel() > 0 then
        local cooldown_reduction = attacker:FindAbilityByName("special_bonus_sohei_momentum_guard_cooldown"):GetSpecialValueFor("value")
        if not guard:IsCooldownReady() then
          local newCooldown = guard:GetCooldownTimeRemaining() - cooldown_reduction
          guard:EndCooldown()
          guard:StartCooldown(newCooldown)
        end
      end
    end
  end
end

function modifier_sohei_momentum_buff:GetModifierPreAttack_CriticalStrike()
  if IsServer() then
    return self:GetAbility():GetSpecialValueFor("crit_damage")
  end
end


-- Momentum's knockback modifier
modifier_sohei_momentum_knockback = class(ModifierBaseClass)

function modifier_sohei_momentum_knockback:IsDebuff() return true end
function modifier_sohei_momentum_knockback:IsHidden() return true end
function modifier_sohei_momentum_knockback:IsPurgable() return false end
function modifier_sohei_momentum_knockback:IsStunDebuff() return false end
function modifier_sohei_momentum_knockback:IsMotionController() return true end
function modifier_sohei_momentum_knockback:GetMotionControllerPriority() return DOTA_MOTION_CONTROLLER_PRIORITY_HIGHEST end

function modifier_sohei_momentum_knockback:GetEffectName()
  return "particles/hero/sohei/knockback.vpcf"
end

function modifier_sohei_momentum_knockback:GetEffectAttachType()
  return PATTACH_ABSORIGIN_FOLLOW
end

function modifier_sohei_momentum_knockback:CheckState()
  if IsServer() then
    local state = {
      [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
      [MODIFIER_STATE_ROOTED] = true
    }
    return state
  end
end

function modifier_sohei_momentum_knockback:OnCreated(keys)
  if IsServer() then

    -- Movement parameters
    local caster = self:GetCaster()
    local target = self:GetParent()
    self:StartIntervalThink(0.03)
    self.direction = (target:GetAbsOrigin() - caster:GetAbsOrigin()):Normalized()
    self.movement_tick = self.direction * keys.distance / ( self:GetDuration() / 0.03 )
    self.collision_radius = keys.collision_radius

    -- Flail animation
    target:StartGesture(ACT_DOTA_FLAIL)
  end
end

function modifier_sohei_momentum_knockback:OnDestroy()
  if IsServer() then
    self:GetParent():FadeGesture(ACT_DOTA_FLAIL)
    ResolveNPCPositions(self:GetParent():GetAbsOrigin(), 128)
  end
end

function modifier_sohei_momentum_knockback:OnIntervalThink()
  if IsServer() then
    local unit = self:GetParent()
    local caster = self:GetCaster()
    local originalPosition = unit:GetAbsOrigin()
    local position = originalPosition + self.movement_tick
    local ability = self:GetAbility()
    local collision_radius = ability:GetSpecialValueFor('collision_radius')

    unit:SetAbsOrigin(GetGroundPosition(position, unit))

    -- If there is at least one target to attack, hit it
    local targets = FindUnitsInRadius(caster:GetTeamNumber(),
      position,
      nil,
      collision_radius,
      DOTA_UNIT_TARGET_TEAM_ENEMY,
      DOTA_UNIT_TARGET_HERO,
      DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE + DOTA_UNIT_TARGET_FLAG_NO_INVIS + DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE,
      FIND_CLOSEST,
      false)

    local nonHeroTarget = targets[1]
    if nonHeroTarget == unit then
      nonHeroTarget = targets[2]
    end
    local groundDiff = GetGroundPosition(originalPosition, unit).z - GetGroundPosition(position, unit).z
    groundDiff = math.abs(groundDiff)

    if nonHeroTarget then
      self:SlowAndStun(unit, caster, ability)
      self:SlowAndStun(nonHeroTarget, caster, ability)
      self:Destroy()

    elseif groundDiff > 100 or GridNav:IsNearbyTree(position, collision_radius, false) then
      self:SlowAndStun(unit, caster, ability)
      GridNav:DestroyTreesAroundPoint(position, collision_radius, false)
      self:Destroy()
    end
  end
end
function modifier_sohei_momentum_knockback:SlowAndStun(unit, caster, ability)
  unit:RemoveModifierByName("modifier_sohei_momentum_slow")
  unit:AddNewModifier(caster, ability, "modifier_sohei_momentum_slow", {
    duration = ability:GetSpecialValueFor("slow_duration"),
    movement_slow = ability:GetSpecialValueFor("movement_slow")
  })

  unit:EmitSound("Sohei.Momentum.Collision")

  if caster:FindAbilityByName("special_bonus_sohei_stun"):GetLevel() > 0 then
    local stunDuration = caster:FindAbilityByName("special_bonus_sohei_stun"):GetSpecialValueFor("value")

    unit:Stop()
    unit:RemoveModifierByName("modifier_sohei_momentum_stun")
    unit:AddNewModifier(caster, ability, "modifier_sohei_momentum_stun", {
      duration = stunDuration
    })
  end

end

-- Momentum's knockback modifier
modifier_sohei_momentum_slow = class(ModifierBaseClass)

function modifier_sohei_momentum_slow:IsDebuff() return true end
function modifier_sohei_momentum_slow:IsHidden() return false end
function modifier_sohei_momentum_slow:IsPurgable() return false end
function modifier_sohei_momentum_slow:IsStunDebuff() return false end

if IsServer() then
  function modifier_sohei_momentum_slow:DeclareFunctions()
    return {
      MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE
    }
  end

  function modifier_sohei_momentum_slow:GetModifierMoveSpeedBonus_Percentage()
    local ability = self:GetAbility()
    return ability:GetSpecialValueFor("movement_slow")
  end
end

-- Momentum's knockback modifier
modifier_sohei_momentum_stun = class(ModifierBaseClass)

function modifier_sohei_momentum_stun:IsDebuff() return true end
function modifier_sohei_momentum_stun:IsHidden() return false end
function modifier_sohei_momentum_stun:IsPurgable() return false end
function modifier_sohei_momentum_stun:IsStunDebuff() return true end

function modifier_sohei_momentum_stun:CheckState()
  return {
    [MODIFIER_STATE_STUNNED] = true
  }
end
function modifier_sohei_momentum_stun:GetEffectName()
  return "particles/generic_gameplay/generic_stunned.vpcf"
end
function modifier_sohei_momentum_stun:GetEffectAttachType()
  return PATTACH_OVERHEAD_FOLLOW
end
function modifier_sohei_momentum_stun:DeclareFunctions()
  return {
    MODIFIER_PROPERTY_OVERRIDE_ANIMATION,
  }
end
function modifier_sohei_momentum_stun:GetOverrideAnimation( params )
  return ACT_DOTA_DISABLED
end

--------------------------------------
--  FLURRY OF BLOWS
--------------------------------------

sohei_flurry_of_blows = class(AbilityBaseClass)
LinkLuaModifier("modifier_sohei_flurry_self", "abilities/hero_sohei.lua", LUA_MODIFIER_MOTION_NONE)

-- Cast animation + playback rate
function sohei_flurry_of_blows:GetCastAnimation()
  return ACT_DOTA_CAST_ABILITY_2
end

function sohei_flurry_of_blows:GetPlaybackRateOverride()
  return 0.35
end

function sohei_flurry_of_blows:OnAbilityPhaseStart()
  if IsServer() then
    self:GetCaster():EmitSound("Hero_EmberSpirit.FireRemnant.Stop")
    return true
  end
end

function sohei_flurry_of_blows:OnAbilityPhaseInterrupted()
  if IsServer() then
    self:GetCaster():StopSound("Hero_EmberSpirit.FireRemnant.Stop")
  end
end

function sohei_flurry_of_blows:OnSpellStart()
  if IsServer() then
    local caster = self:GetCaster()
    local target_loc = self:GetCursorPosition()
    local flurry_radius = self:GetAOERadius()
    local max_attacks = self:GetSpecialValueFor("max_attacks")
    local max_duration = self:GetSpecialValueFor("max_duration")
    local attack_interval = self:GetSpecialValueFor("attack_interval")

    -- Emit sound
    caster:EmitSound("Hero_EmberSpirit.FireRemnant.Cast")

    -- Draw the particle
    if caster.flurry_ground_pfx then
      ParticleManager:DestroyParticle(caster.flurry_ground_pfx, false)
      ParticleManager:ReleaseParticleIndex(caster.flurry_ground_pfx)
    end
    caster.flurry_ground_pfx = ParticleManager:CreateParticle("particles/hero/sohei/flurry_of_blows_ground.vpcf", PATTACH_CUSTOMORIGIN, nil)
    ParticleManager:SetParticleControl(caster.flurry_ground_pfx, 0, target_loc)

    -- Start the spell
    caster:SetAbsOrigin(target_loc + Vector(0, 0, 200))
    caster:AddNewModifier(caster, self, "modifier_sohei_flurry_self", {duration = max_duration, max_attacks = max_attacks, flurry_radius = flurry_radius, attack_interval = attack_interval})
  end
end

function sohei_flurry_of_blows:GetAOERadius()
  local caster = self:GetCaster()

  if IsServer() and caster:FindAbilityByName("special_bonus_sohei_fob_radius"):GetLevel() > 0 then
    local additionalRadius = caster:FindAbilityByName("special_bonus_sohei_fob_radius"):GetSpecialValueFor("value")
    return self:GetSpecialValueFor("flurry_radius") + additionalRadius
  else
    return self:GetSpecialValueFor("flurry_radius")
  end
end

-- Flurry of Blows' self buff
modifier_sohei_flurry_self = class(ModifierBaseClass)

function modifier_sohei_flurry_self:IsDebuff() return false end
function modifier_sohei_flurry_self:IsHidden() return true end
function modifier_sohei_flurry_self:IsPurgable() return false end
function modifier_sohei_flurry_self:IsStunDebuff() return false end

function modifier_sohei_flurry_self:StatusEffectPriority()
  return 20
end

function modifier_sohei_flurry_self:GetStatusEffectName()
  return "particles/status_fx/status_effect_omnislash.vpcf"
end

function modifier_sohei_flurry_self:CheckState()
  if IsServer() then
    local state = {
      [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
      [MODIFIER_STATE_INVULNERABLE] = true,
      [MODIFIER_STATE_NO_HEALTH_BAR] = true,
      [MODIFIER_STATE_MAGIC_IMMUNE] = true,
      [MODIFIER_STATE_SILENCED] = true,
      [MODIFIER_STATE_MUTED] = true,
      [MODIFIER_STATE_ROOTED] = true
    }
    return state
  end
end

function modifier_sohei_flurry_self:OnDestroy()
  if IsServer() then
    local caster = self:GetCaster()
    ParticleManager:DestroyParticle(caster.flurry_ground_pfx, false)
    ParticleManager:ReleaseParticleIndex(caster.flurry_ground_pfx)
    caster.flurry_ground_pfx = nil
    caster:FadeGesture(ACT_DOTA_VICTORY)
  end
end

function modifier_sohei_flurry_self:OnCreated(keys)
  if IsServer() then
    self.remaining_attacks = keys.max_attacks
    self.radius = keys.flurry_radius
    self.attack_interval = keys.attack_interval
    self.position = self:GetCaster():GetAbsOrigin()
    self:StartIntervalThink(self.attack_interval)
    if sohei_functions:FlurryThink(self:GetCaster(), self.position, self.radius, self.attack_interval) then
      self.remaining_attacks = self.remaining_attacks - 1
    end
  end
end

function modifier_sohei_flurry_self:OnIntervalThink()
  if IsServer() then

    -- Attempt a strike
    if sohei_functions:FlurryThink(self:GetCaster(), self.position, self.radius, self.attack_interval) then
      self.remaining_attacks = self.remaining_attacks - 1

      if self:GetParent():HasScepter() then
        self:SetDuration(self:GetRemainingTime() + self.attack_interval, true)
      end
    end

    -- If there are no strikes left, end
    if self.remaining_attacks <= 0 then
      self:GetCaster():RemoveModifierByName("modifier_sohei_flurry_self")
    end
  end
end

function sohei_functions:FlurryThink(attacker, position, radius, attack_interval)

  -- If there is at least one target to attack, hit it
  local targets = FindUnitsInRadius(attacker:GetTeamNumber(),
    position,
    nil,
    radius,
    DOTA_UNIT_TARGET_TEAM_ENEMY,
    DOTA_UNIT_TARGET_HERO,
    DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE + DOTA_UNIT_TARGET_FLAG_NO_INVIS + DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE,
    FIND_ANY_ORDER,
    false)

  if targets[1] then
    local distance = 50
    local speed = 900
    local tree_radius = 0
    local ability_dash = attacker:FindAbilityByName("sohei_dash")
    if ability_dash then
      distance = ability_dash:GetSpecialValueFor("dash_distance")
      speed = ability_dash:GetSpecialValueFor("dash_speed")
      tree_radius = ability_dash:GetSpecialValueFor("tree_radius")
    end

    local dash_start_loc = targets[1]:GetAbsOrigin() + (targets[1]:GetAbsOrigin() - (position - Vector(0, 0, 200))):Normalized() * distance + 50
    attacker:SetAbsOrigin(dash_start_loc)
    attacker:SetForwardVector(((position - Vector(0, 0, 200)) - dash_start_loc):Normalized())
    attacker:FaceTowards(targets[1]:GetAbsOrigin())
    self:Dash(attacker, distance, speed, tree_radius)
    attacker:PerformAttack(targets[1], true, true, true, false, false, false, false)
    return true

  -- Else, return false and keep meditating
  else
    attacker:SetAbsOrigin(position)
    attacker:StartGesture(ACT_DOTA_VICTORY)
  end
end
