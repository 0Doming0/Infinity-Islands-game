--[[
    Infinity Islands — Rebuild Part 22
    Minimal robust authoritative combat damage service.

    Public API preserved:
    - TagCreator
    - IsFriendly
    - ApplySwordHit
    - ApplyDirectHit
    - ApplyCompanionHit
    - ApplyEffectDamage

    Critical rule:
    damage must never fail because analytics, feedback, objective presentation,
    stun, or knockback failed.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameplayAnalytics = require(
    script.Parent.Parent:WaitForChild("GameplayAnalyticsService")
)
local ObjectiveSignalBridge = require(
    script.Parent.Parent.DungeonRuntime.ObjectiveSignalBridge
)
local RemoteRegistry = require(
    ReplicatedStorage.Shared.Utilities.RemoteRegistry
)

local DamageService = {}

local damageFeedbackEvent = RemoteRegistry.Get(
    "Combat",
    "EnemyDamageFeedback",
    "RemoteEvent"
)

local DEFAULT_STUN_REACTION_WINDOW = 1.1
local MIN_STUN_REACTION_WINDOW = 0.35
local MAX_STUN_REACTION_WINDOW = 3

local function validAttacker(attacker)
    return attacker
        and attacker:IsA("Player")
        and attacker.Parent == Players
end

local function safeCall(callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then
        return false, result
    end
    return true, result
end

local function safeAnalytics(methodName, ...)
    local method = GameplayAnalytics[methodName]
    if type(method) ~= "function" then
        return
    end
    safeCall(method, ...)
end

local function sendDamageFeedback(attacker, model, amount, source, heavy, defeated)
    if not validAttacker(attacker)
        or not model
        or not model.Parent
        or not damageFeedbackEvent
    then
        return
    end

    local cleanAmount = math.max(0, tonumber(amount) or 0)
    if cleanAmount <= 0 then
        return
    end

    safeCall(function()
        damageFeedbackEvent:FireClient(attacker, {
            Target = model,
            Amount = cleanAmount,
            Source = tostring(source or "Damage"),
            Heavy = heavy == true,
            Defeated = defeated == true,
            Policy = "EnemyDamageFeedbackV2",
        })
    end)
end

local function reportObjectiveHit(attacker, model, source)
    if not model or not model.Parent then
        return
    end

    safeCall(ObjectiveSignalBridge.Report, "EnemyHit", {
        Target = model,
        SourceUserId = validAttacker(attacker) and attacker.UserId or nil,
        GlobalIslandIndex = model:GetAttribute("GlobalIslandIndex"),
        MonsterRole = model:GetAttribute("MonsterRole"),
        IsElite = model:GetAttribute("IsElite") == true,
        DamageSource = tostring(source or "Damage"),
        Amount = 1,
    })
end

local function mitigatedDamage(model, rawAmount)
    if not model then
        return 0
    end

    local raw = math.max(0, tonumber(rawAmount) or 0)
    local defense = math.max(
        0,
        tonumber(model:GetAttribute("Defense")) or 0
    )
    local multiplier = math.max(
        0,
        tonumber(model:GetAttribute("DamageMultiplier")) or 1
    )

    if raw <= 0 or multiplier <= 0 then
        return 0
    end

    return math.max(1, (raw - defense) * multiplier)
end

local function runDamageMultiplier(player)
    return math.clamp(
        tonumber(
            player and player:GetAttribute("RunDamageDealtMultiplier")
        ) or 1,
        0.05,
        5
    )
end

local function tagCreator(humanoid, player)
    if not humanoid or not humanoid:IsA("Humanoid") then
        return
    end

    local old = humanoid:FindFirstChild("creator")
    if old then
        old:Destroy()
    end

    if not validAttacker(player) then
        return
    end

    local creator = Instance.new("ObjectValue")
    creator.Name = "creator"
    creator.Value = player
    creator.Parent = humanoid
    Debris:AddItem(creator, 3)
end

DamageService.TagCreator = tagCreator

local function playHitSound(model)
    if not model or not model.Parent then
        return
    end

    local hitSound = model:FindFirstChild("hit", true)
    if not hitSound or not hitSound:IsA("Sound") then
        return
    end

    safeCall(function()
        hitSound:Stop()
        hitSound.TimePosition = 0
        hitSound:Play()
    end)
end

local function createImpact(position, color, heavy)
    if typeof(position) ~= "Vector3" then
        return
    end

    safeCall(function()
        local anchor = Instance.new("Part")
        anchor.Name = "SwordImpact"
        anchor.Shape = Enum.PartType.Ball
        anchor.Size = heavy
            and Vector3.new(0.85, 0.85, 0.85)
            or Vector3.new(0.55, 0.55, 0.55)
        anchor.CFrame = CFrame.new(position)
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Material = Enum.Material.Neon
        anchor.Color = color
        anchor.Transparency = 0.08
        anchor.Parent = workspace
        Debris:AddItem(anchor, 0.30)
    end)
end

local function validateTarget(target, allowNoSwordDamage)
    if typeof(target) ~= "table" then
        return nil
    end

    local model = target.Model
    local humanoid = target.Humanoid
    local root = target.Root

    if not model
        or not model:IsA("Model")
        or not model.Parent
        or not humanoid
        or not humanoid:IsA("Humanoid")
        or humanoid.Health <= 0
    then
        return nil
    end

    if Players:GetPlayerFromCharacter(model) then
        return nil
    end

    if model:GetAttribute("IsSkyIsland") == true
        or model:GetAttribute("Invulnerable") == true
    then
        return nil
    end

    if not allowNoSwordDamage
        and model:GetAttribute("NoSwordDamage") == true
    then
        return nil
    end

    if root and (not root:IsA("BasePart") or not root.Parent) then
        root = nil
    end

    return {
        Model = model,
        Humanoid = humanoid,
        Root = root,
    }
end

local function applyCombatStun(model, humanoid, attack)
    if not model
        or not model.Parent
        or not humanoid
        or humanoid.Health <= 0
        or typeof(attack) ~= "table"
        or model:GetAttribute("CanBeStunned") == false
    then
        return
    end

    local resistance = math.clamp(
        tonumber(model:GetAttribute("StunResistance")) or 0,
        0,
        1
    )
    if resistance >= 1 then
        return
    end

    local now = workspace:GetServerTimeNow()
    local immunityUntil = tonumber(
        model:GetAttribute("CombatStunImmunityUntil")
    ) or 0
    if now < immunityUntil then
        return
    end

    local stunDuration = math.clamp(
        (tonumber(attack.StunDuration) or 0.45) * (1 - resistance),
        0.05,
        1.25
    )
    local reactionWindow = math.clamp(
        tonumber(model:GetAttribute("StunReactionWindow"))
            or DEFAULT_STUN_REACTION_WINDOW,
        MIN_STUN_REACTION_WINDOW,
        MAX_STUN_REACTION_WINDOW
    )

    local token = (model:GetAttribute("CombatStunTokenId") or 0) + 1
    local interruptSerial =
        (model:GetAttribute("CombatInterruptSerial") or 0) + 1

    model:SetAttribute("CombatStunTokenId", token)
    model:SetAttribute("CombatInterruptSerial", interruptSerial)
    model:SetAttribute("CombatStunned", true)
    model:SetAttribute("CombatStunnedUntil", now + stunDuration)
    model:SetAttribute(
        "CombatStunImmunityUntil",
        now + stunDuration + reactionWindow
    )

    if model:GetAttribute("CombatOriginalWalkSpeed") == nil then
        model:SetAttribute(
            "CombatOriginalWalkSpeed",
            humanoid.WalkSpeed
        )
    end
    if model:GetAttribute("CombatOriginalAutoRotate") == nil then
        model:SetAttribute(
            "CombatOriginalAutoRotate",
            humanoid.AutoRotate
        )
    end

    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = false
    humanoid:Move(Vector3.zero)

    task.delay(stunDuration, function()
        if not model.Parent
            or not humanoid.Parent
            or model:GetAttribute("CombatStunTokenId") ~= token
        then
            return
        end

        model:SetAttribute("CombatStunned", nil)
        model:SetAttribute("CombatStunTokenId", nil)
        model:SetAttribute("CombatStunnedUntil", nil)

        if humanoid.Health > 0 then
            local speed = model:GetAttribute("CombatOriginalWalkSpeed")
            local autoRotate =
                model:GetAttribute("CombatOriginalAutoRotate")

            if typeof(speed) == "number" then
                humanoid.WalkSpeed = speed
            end
            if typeof(autoRotate) == "boolean" then
                humanoid.AutoRotate = autoRotate
            end
        end

        model:SetAttribute("CombatOriginalWalkSpeed", nil)
        model:SetAttribute("CombatOriginalAutoRotate", nil)
    end)
end

local function applyKnockback(attacker, attackerRoot, model, root, attack)
    if not model
        or not model.Parent
        or not root
        or not root:IsA("BasePart")
        or not root.Parent
        or not attackerRoot
        or not attackerRoot:IsA("BasePart")
        or not attackerRoot.Parent
        or typeof(attack) ~= "table"
    then
        return
    end

    if model:GetAttribute("NoKnockback") == true
        or model:GetAttribute("CanBeKnockedBack") == false
    then
        return
    end

    local now = os.clock()
    local lastHitAt =
        tonumber(model:GetAttribute("CombatLastHitAt")) or 0
    local hitCount =
        math.max(0, tonumber(model:GetAttribute("CombatHitCount")) or 0)

    if now - lastHitAt > 1.5 then
        hitCount = 0
    end

    hitCount += 1
    model:SetAttribute("CombatLastHitAt", now)
    model:SetAttribute("CombatHitCount", hitCount)

    local comboScale =
        1 + math.min(2, hitCount - 1) * 0.18
    local resistanceScale =
        1 - math.clamp(
            tonumber(model:GetAttribute("KnockbackResistance")) or 0,
            0,
            1
        )

    local runKnockbackMultiplier = 1
    if validAttacker(attacker) then
        runKnockbackMultiplier = math.clamp(
            tonumber(attacker:GetAttribute("RunKnockbackMultiplier")) or 1,
            0.25,
            5
        )
    end

    local horizontalForce =
        math.max(0, tonumber(attack.Knockback) or 12)
        * runKnockbackMultiplier
        * 1.8
        * comboScale
        * resistanceScale

    local upwardForce =
        math.max(0, tonumber(attack.UpwardKnockback) or 2)
        * comboScale
        * resistanceScale

    if resistanceScale <= 0 or horizontalForce <= 0 then
        return
    end

    local direction = Vector3.new(
        root.Position.X - attackerRoot.Position.X,
        0,
        root.Position.Z - attackerRoot.Position.Z
    )

    if direction.Magnitude < 0.05 then
        local look = attackerRoot.CFrame.LookVector
        direction = Vector3.new(look.X, 0, look.Z)
    end

    if direction.Magnitude < 0.05 then
        return
    end

    direction = direction.Unit

    if model:GetAttribute("KinematicMovement") == true then
        local displacement =
            math.clamp(horizontalForce * 0.065, 0.9, 2.4)
        model:SetAttribute(
            "KinematicKnockbackRequest",
            direction * displacement
        )
        model:SetAttribute(
            "KinematicKnockbackSerial",
            (model:GetAttribute("KinematicKnockbackSerial") or 0) + 1
        )
        return
    end

    local velocity =
        direction * horizontalForce
        + Vector3.new(0, upwardForce, 0)

    model:SetAttribute(
        "CombatKnockbackUntil",
        workspace:GetServerTimeNow() + 0.22
    )

    for _, child in ipairs(root:GetChildren()) do
        if child.Name == "SwordKnockback"
            or child.Name == "SwordKnockbackAttachment"
        then
            child:Destroy()
        end
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart")
            and not descendant.Massless
        then
            descendant.Anchored = false
        end
    end

    safeCall(function()
        root:SetNetworkOwner(nil)
    end)

    root.AssemblyLinearVelocity = velocity

    local attachment = Instance.new("Attachment")
    attachment.Name = "SwordKnockbackAttachment"
    attachment.Parent = root

    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Name = "SwordKnockback"
    linearVelocity.Attachment0 = attachment
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    linearVelocity.VectorVelocity = velocity
    linearVelocity.MaxForce = math.clamp(
        root.AssemblyMass * 10000,
        20000,
        300000
    )
    linearVelocity.Parent = root

    Debris:AddItem(linearVelocity, 0.17)
    Debris:AddItem(attachment, 0.19)
end

function DamageService.IsFriendly(attacker, targetModel, friendlyFire)
    return targetModel
        and Players:GetPlayerFromCharacter(targetModel) ~= nil
end

function DamageService.ApplySwordHit(attacker, attackerRoot, target, attack)
    if not validAttacker(attacker)
        or not attackerRoot
        or not attackerRoot:IsA("BasePart")
        or typeof(attack) ~= "table"
    then
        return false, false
    end

    local resolved = validateTarget(target, false)
    if not resolved then
        return false, false
    end

    local model = resolved.Model
    local humanoid = resolved.Humanoid
    local root = resolved.Root

    local damage = mitigatedDamage(
        model,
        math.max(0, tonumber(attack.Damage) or 0)
            * runDamageMultiplier(attacker)
    )
    if damage <= 0 then
        return false, false
    end

    local healthBefore = humanoid.Health

    tagCreator(humanoid, attacker)
    model:SetAttribute("LastDamagedByUserId", attacker.UserId)
    model:SetAttribute("LastSwordDamage", damage)
    model:SetAttribute(
        "LastSwordScoreMultiplier",
        attack.ScoreMultiplier
    )
    model:SetAttribute(
        "LastSwordHitAt",
        workspace:GetServerTimeNow()
    )

    humanoid:TakeDamage(damage)

    local defeated =
        healthBefore > 0 and humanoid.Health <= 0
    local swordId =
        attacker:GetAttribute("EquippedSword") or "Sword"

    reportObjectiveHit(attacker, model, swordId)
    sendDamageFeedback(
        attacker,
        model,
        damage,
        swordId,
        attack.Heavy == true,
        defeated
    )

    safeAnalytics(
        "RecordEnemyAttacked",
        attacker,
        model,
        swordId
    )
    if defeated then
        safeAnalytics(
            "RecordEnemyDefeated",
            attacker,
            model,
            swordId
        )
    end

    if not defeated then
        safeCall(
            applyCombatStun,
            model,
            humanoid,
            attack
        )
        safeCall(
            applyKnockback,
            attacker,
            attackerRoot,
            model,
            root,
            attack
        )
    end

    if root then
        createImpact(
            root.Position
                + Vector3.new(
                    0,
                    math.max(0.5, root.Size.Y * 0.35),
                    0
                ),
            attack.Heavy == true
                and Color3.fromRGB(255, 120, 55)
                or Color3.fromRGB(255, 235, 170),
            attack.Heavy == true
        )
    end

    playHitSound(model)

    workspace:SetAttribute("CombatDamageLastSwordHitAccepted", true)
    workspace:SetAttribute(
        "CombatDamageLastSwordTarget",
        model.Name
    )
    workspace:SetAttribute(
        "CombatDamageLastSwordDefeated",
        defeated
    )

    return true, defeated
end

function DamageService.ApplyDirectHit(
    attacker,
    target,
    amount,
    source,
    alreadyRunScaled
)
    if not validAttacker(attacker) then
        return false, false
    end

    local resolved = validateTarget(target, true)
    if not resolved then
        return false, false
    end

    local model = resolved.Model
    local humanoid = resolved.Humanoid

    local runMultiplier =
        alreadyRunScaled == true
        and 1
        or runDamageMultiplier(attacker)

    local damage = mitigatedDamage(
        model,
        math.max(0, tonumber(amount) or 0) * runMultiplier
    )
    if damage <= 0 then
        return false, false
    end

    local healthBefore = humanoid.Health

    tagCreator(humanoid, attacker)
    model:SetAttribute("LastDamagedByUserId", attacker.UserId)
    model:SetAttribute(
        "LastDamageSource",
        tostring(source or "Direct")
    )

    humanoid:TakeDamage(damage)

    local defeated =
        healthBefore > 0 and humanoid.Health <= 0
    local sourceName = tostring(source or "Direct")

    reportObjectiveHit(attacker, model, sourceName)
    sendDamageFeedback(
        attacker,
        model,
        damage,
        sourceName,
        false,
        defeated
    )

    safeAnalytics(
        "RecordEnemyAttacked",
        attacker,
        model,
        sourceName
    )
    if defeated then
        safeAnalytics(
            "RecordEnemyDefeated",
            attacker,
            model,
            sourceName
        )
    end

    return true, defeated
end

function DamageService.ApplyEffectDamage(
    attacker,
    target,
    amount,
    source
)
    local resolved = validateTarget(target, false)
    if not resolved or not validAttacker(attacker) then
        return false, false
    end

    local model = resolved.Model
    local humanoid = resolved.Humanoid
    local root = resolved.Root

    local damage = mitigatedDamage(
        model,
        math.max(0, tonumber(amount) or 0)
            * runDamageMultiplier(attacker)
    )
    if damage <= 0 then
        return false, false
    end

    local healthBefore = humanoid.Health

    tagCreator(humanoid, attacker)
    model:SetAttribute("LastDamagedByUserId", attacker.UserId)
    model:SetAttribute(
        "LastRelicDamageSource",
        tostring(source or "Relic")
    )
    model:SetAttribute("LastRelicDamage", damage)

    humanoid:TakeDamage(damage)

    local defeated =
        healthBefore > 0 and humanoid.Health <= 0
    local sourceName = tostring(source or "Relic")

    reportObjectiveHit(attacker, model, sourceName)
    sendDamageFeedback(
        attacker,
        model,
        damage,
        sourceName,
        false,
        defeated
    )

    safeAnalytics(
        "RecordEnemyAttacked",
        attacker,
        model,
        sourceName
    )
    if defeated then
        safeAnalytics(
            "RecordEnemyDefeated",
            attacker,
            model,
            sourceName
        )
    end

    if root then
        createImpact(
            root.Position,
            Color3.fromRGB(190, 130, 255),
            false
        )
    end

    return true, defeated
end

function DamageService.ApplyCompanionHit(
    owner,
    target,
    amount,
    source
)
    local success, defeated = DamageService.ApplyDirectHit(
        owner,
        target,
        amount,
        source or "Companion",
        false
    )

    if success
        and typeof(target) == "table"
        and target.Model
    then
        playHitSound(target.Model)
    end

    return success, defeated
end

workspace:SetAttribute(
    "CombatDamageServiceVersion",
    "RebuildMinimalV1"
)
workspace:SetAttribute(
    "CombatDamageServiceKnockbackPolicy",
    "ExplicitAttackerFailSafeV1"
)

return table.freeze(DamageService)
