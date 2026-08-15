-- Linha de visao autoritativa para inimigos de longo alcance.
--
-- Slimes de projeteis e morteiros so podem entrar no estado de ataque quando
-- um raycast confirma que pelo menos uma parte central do personagem esta
-- visivel. Paredes, terreno e partes visiveis bloqueiam; somente superficies
-- praticamente invisiveis sao ignoradas. O bloqueio usa CombatStunned sem
-- alterar WalkSpeed, preservando o sistema de stun real do combate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local VERSION = "RaycastVisibilityGateV1"
local COMBAT_TARGET_TAG = "CombatTarget"
local CHECK_INTERVAL = 0.08
local ATTACK_RANGE_MARGIN = 2
local MAX_TRANSPARENT_SKIPS = 8
local TRANSPARENCY_IGNORE_THRESHOLD = 0.95

local PROFILES = table.freeze({
	NeutralRanged = table.freeze({ AttackRange = 45, DetectionRange = 80, RequiresAggro = true }),
	IceRanged = table.freeze({ AttackRange = 48, DetectionRange = 78, RequiresAggro = false }),
	HostileMortar = table.freeze({ AttackRange = 55, DetectionRange = 70, RequiresAggro = false }),
	FireMortar = table.freeze({ AttackRange = 55, DetectionRange = 72, RequiresAggro = false }),
	GenericRanged = table.freeze({ AttackRange = 45, DetectionRange = 65, RequiresAggro = false }),
})

local states = setmetatable({}, { __mode = "k" })

workspace:SetAttribute("RangedLineOfSightSystemVersion", VERSION)
workspace:SetAttribute("RangedLineOfSightCheckInterval", CHECK_INTERVAL)

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function profileFor(model)
	local behavior = tostring(model:GetAttribute("SlimeBehavior") or "")
	if PROFILES[behavior] then
		return PROFILES[behavior], behavior
	end
	if tostring(model:GetAttribute("AttackType") or "") == "Ranged" then
		return PROFILES.GenericRanged, "GenericRanged"
	end
	return nil, nil
end

local function getRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function livingTarget(player)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("InvisibleToEnemies") == true
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return character, humanoid, root
end

local function targetIsProtected(player, character)
	local untilTime = tonumber(player:GetAttribute("RespawnProtectionUntil")) or 0
	if player:GetAttribute("RespawnProtectionActive") == true and untilTime > serverTime() then
		return true
	end
	return character and character:FindFirstChildOfClass("ForceField") ~= nil
end

local function nearestPlayer(position, maximumDistance)
	local selectedPlayer
	local selectedCharacter
	local selectedRoot
	local selectedDistance = maximumDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local character, _, root = livingTarget(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance <= selectedDistance then
				selectedPlayer = player
				selectedCharacter = character
				selectedRoot = root
				selectedDistance = distance
			end
		end
	end
	return selectedPlayer, selectedCharacter, selectedRoot, selectedDistance
end

local function resolveTarget(model, root, profile)
	local targetUserId = tonumber(model:GetAttribute("TargetUserId"))
		or tonumber(model:GetAttribute("AggroUserId"))
	if targetUserId then
		local player = Players:GetPlayerByUserId(targetUserId)
		local character, _, targetRoot = livingTarget(player)
		if targetRoot then
			return player, character, targetRoot, (targetRoot.Position - root.Position).Magnitude
		end
	end
	if profile.RequiresAggro then
		return nil
	end
	local detectionRange = math.max(
		1,
		tonumber(model:GetAttribute("DetectionRange"))
			or tonumber(model:GetAttribute("AggroRange"))
			or profile.DetectionRange
	)
	return nearestPlayer(root.Position, detectionRange)
end

local function addSample(samples, instance, offset)
	if instance and instance:IsA("BasePart") then
		table.insert(samples, instance.Position + (offset or Vector3.zero))
	end
end

local function targetSamples(character, root)
	local samples = {}
	addSample(samples, character:FindFirstChild("Head"), Vector3.new(0, -0.15, 0))
	addSample(samples, character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	addSample(samples, root, Vector3.new(0, 0.45, 0))
	return samples
end

local function rayCanReach(origin, targetPosition, attackerModel, targetCharacter)
	local exclusions = { attackerModel }
	local currentOrigin = origin
	local lastBlocker
	for _ = 1, MAX_TRANSPARENT_SKIPS do
		local direction = targetPosition - currentOrigin
		if direction.Magnitude <= 0.08 then
			return true, nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclusions
		params.IgnoreWater = true
		local result = workspace:Raycast(currentOrigin, direction, params)
		if not result then
			return true, nil
		end
		local hit = result.Instance
		if hit and hit:IsDescendantOf(targetCharacter) then
			return true, nil
		end
		lastBlocker = hit
		if hit
			and hit:IsA("BasePart")
			and hit.Transparency >= TRANSPARENCY_IGNORE_THRESHOLD
		then
			table.insert(exclusions, hit)
			local remaining = targetPosition - result.Position
			if remaining.Magnitude <= 0.08 then
				return true, nil
			end
			currentOrigin = result.Position + remaining.Unit * 0.06
		else
			return false, lastBlocker
		end
	end
	return false, lastBlocker
end

local function hasLineOfSight(model, root, targetCharacter, targetRoot)
	local origin = root.Position + Vector3.new(0, math.clamp(root.Size.Y * 0.35, 1, 3), 0)
	local lastBlocker
	for _, sample in ipairs(targetSamples(targetCharacter, targetRoot)) do
		local visible, blocker = rayCanReach(origin, sample, model, targetCharacter)
		if visible then
			return true, nil
		end
		lastBlocker = blocker or lastBlocker
	end
	return false, lastBlocker
end

local function realCombatStunActive(model)
	local now = serverTime()
	return model:GetAttribute("CombatStunTokenId") ~= nil
		or (tonumber(model:GetAttribute("CombatStunnedUntil")) or 0) > now
		or (tonumber(model:GetAttribute("RelicFrozenUntil")) or 0) > now
end

local function applySightGuard(model, state, reason)
	if not state.GuardActive then
		state.GuardActive = true
		state.BlockedCount += 1
		model:SetAttribute(
			"CombatInterruptSerial",
			math.max(0, math.floor(tonumber(model:GetAttribute("CombatInterruptSerial")) or 0)) + 1
		)
		model:SetAttribute("RangedSightGuardBlockedCount", state.BlockedCount)
		model:SetAttribute("RangedSightGuardStartedAt", serverTime())
	end
	model:SetAttribute("RangedSightGuardActive", true)
	model:SetAttribute("RangedSightGuardReason", reason)
	model:SetAttribute("CombatStunned", true)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid.Health > 0 then
		humanoid:Move(Vector3.zero)
	end
end

local function releaseSightGuard(model, state)
	if not state.GuardActive then
		return
	end
	state.GuardActive = false
	model:SetAttribute("RangedSightGuardActive", nil)
	model:SetAttribute("RangedSightGuardReason", nil)
	model:SetAttribute("RangedSightGuardEndedAt", serverTime())
	if not realCombatStunActive(model) then
		model:SetAttribute("CombatStunned", nil)
	end
end

local function blockerName(blocker)
	if not blocker then
		return nil
	end
	local ok, fullName = pcall(blocker.GetFullName, blocker)
	return ok and fullName or blocker.Name
end

local function evaluate(model)
	local profile, behavior = profileFor(model)
	local state = states[model]
	if not profile then
		if state then
			releaseSightGuard(model, state)
			states[model] = nil
		end
		return
	end
	if not model:IsDescendantOf(workspace) then
		states[model] = nil
		return
	end
	state = state or { GuardActive = false, BlockedCount = 0 }
	states[model] = state

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = getRoot(model)
	if not humanoid or humanoid.Health <= 0 or not root then
		releaseSightGuard(model, state)
		return
	end

	local player, character, targetRoot, distance = resolveTarget(model, root, profile)
	if not player or not character or not targetRoot then
		releaseSightGuard(model, state)
		model:SetAttribute("RangedLineOfSight", nil)
		model:SetAttribute("RangedLineOfSightTargetUserId", nil)
		model:SetAttribute("RangedLineOfSightBlockedBy", nil)
		return
	end

	local attackRange = math.max(
		1,
		tonumber(model:GetAttribute("AttackRange")) or profile.AttackRange
	)
	model:SetAttribute("RangedLineOfSightVersion", VERSION)
	model:SetAttribute("RangedLineOfSightBehavior", behavior)
	model:SetAttribute("RangedLineOfSightTargetUserId", player.UserId)
	model:SetAttribute("RangedLineOfSightDistance", math.floor(distance * 10 + 0.5) / 10)
	model:SetAttribute("RangedLineOfSightLastCheckedAt", serverTime())

	if distance > attackRange + ATTACK_RANGE_MARGIN then
		releaseSightGuard(model, state)
		model:SetAttribute("RangedLineOfSight", nil)
		model:SetAttribute("RangedLineOfSightState", "OutsideAttackRange")
		model:SetAttribute("RangedLineOfSightBlockedBy", nil)
		return
	end

	if targetIsProtected(player, character) then
		model:SetAttribute("RangedLineOfSight", false)
		model:SetAttribute("RangedLineOfSightState", "TargetProtected")
		model:SetAttribute("RangedLineOfSightBlockedBy", "RespawnProtection")
		applySightGuard(model, state, "TargetProtected")
		return
	end

	local visible, blocker = hasLineOfSight(model, root, character, targetRoot)
	model:SetAttribute("RangedLineOfSight", visible)
	model:SetAttribute("RangedLineOfSightBlockedBy", visible and nil or blockerName(blocker))
	model:SetAttribute("RangedLineOfSightState", visible and "Visible" or "Blocked")
	if visible then
		releaseSightGuard(model, state)
	else
		applySightGuard(model, state, "RaycastBlocked")
	end
end

local function evaluateSoon(instance)
	if instance:IsA("Model") then
		task.defer(evaluate, instance)
	end
end

CollectionService:GetInstanceAddedSignal(COMBAT_TARGET_TAG):Connect(evaluateSoon)
for _, model in ipairs(CollectionService:GetTagged(COMBAT_TARGET_TAG)) do
	evaluateSoon(model)
end

local elapsed = 0
while true do
	elapsed += task.wait()
	if elapsed < CHECK_INTERVAL then
		continue
	end
	elapsed = 0
	local visibleThreats = {}
	for _, model in ipairs(CollectionService:GetTagged(COMBAT_TARGET_TAG)) do
		if model:IsA("Model") then
			evaluate(model)
			local profile, behavior = profileFor(model)
			if profile and (behavior == "HostileMortar" or behavior == "FireMortar") then
				local root = getRoot(model)
				local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
				if root and humanoid and humanoid.Health > 0 then
					local attackRange = math.max(1, tonumber(model:GetAttribute("AttackRange")) or profile.AttackRange)
					local splashMargin = math.max(2, tonumber(model:GetAttribute("ImpactRadius")) or 7)
					for _, player in ipairs(Players:GetPlayers()) do
						local character, _, targetRoot = livingTarget(player)
						if character and targetRoot
							and not targetIsProtected(player, character)
							and (targetRoot.Position - root.Position).Magnitude <= attackRange + splashMargin
						then
							local visible = hasLineOfSight(model, root, character, targetRoot)
							if visible then
								visibleThreats[player.UserId] = (visibleThreats[player.UserId] or 0) + 1
							end
						end
					end
				end
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local count = visibleThreats[player.UserId] or 0
		player:SetAttribute("RangedVisibleThreatCount", count)
		player:SetAttribute("RangedVisibleThreatActive", count > 0)
		player:SetAttribute("RangedVisibleThreatVersion", VERSION)
	end
	for model, state in pairs(states) do
		if not model:IsDescendantOf(workspace) then
			releaseSightGuard(model, state)
			states[model] = nil
		end
	end
end
