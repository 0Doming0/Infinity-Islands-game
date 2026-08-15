-- V18: IA exclusiva do bau Mimico com knockback cinematico estavel
-- e bote longo, imediato e rasante em direcao ao jogador.
-- Movimento, combate e animacao esqueletica em loop
-- ficam todos neste unico ModuleScript. Nenhum Script interno e necessario.
-- O Model atual usa o MeshPart skinned Cube.002 como raiz; os fallbacks antigos
-- continuam aceitos para nao quebrar templates de desenvolvimento.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local MobEventModifiers = require(script.Parent.MobEventModifiers)
local InventoryService = require(script.Parent.Parent.MVPSystems:WaitForChild("InventoryService"))
local PlayerDamageService = require(script.Parent.Parent.MVPSystems:WaitForChild("PlayerDamageService"))
local CompanionService = require(script.Parent.Parent.MVPSystems:WaitForChild("CompanionService"))
local AnimeOutline = require(ServerScriptService.MVPSystems:WaitForChild("AnimeOutline"))
local GameplayAnalytics = require(ServerScriptService:WaitForChild("GameplayAnalyticsService"))
ScoreService.Start()
InventoryService.Start()
CompanionService.Start()

local MimicAI = {}
local states = setmetatable({}, { __mode = "k" })
local heartbeatConnected = false

local STATE_AWAKE = "Awake"
local STATE_RETURNING = "Returning"
local STATE_DORMANT = "Dormant"
local HOME_SNAP_DISTANCE = 1.75
local MAX_MOVEMENT_DELTA_TIME = 1 / 20
local UNREACHABLE_RETURN_DELAY_DEFAULT = 1.1
local KINEMATIC_KNOCKBACK_DURATION_DEFAULT = 0.16
local KINEMATIC_KNOCKBACK_MAX_DISTANCE_DEFAULT = 2.8
local MOVEMENT_SPEED_MULTIPLIER = 1.25
local ROOT_DESYNC_TOLERANCE = 0.35

local ATTACK_WINDUP_DEFAULT = 0.28
local ATTACK_LUNGE_DURATION_DEFAULT = 0.12
local ATTACK_RECOVERY_DEFAULT = 0.30
local ATTACK_LUNGE_DISTANCE_DEFAULT = 1.15
local JUMP_ATTACK_RANGE_DEFAULT = 20
local JUMP_ATTACK_MIN_RANGE_DEFAULT = 6
local JUMP_ATTACK_COOLDOWN_DEFAULT = 5
local JUMP_ATTACK_WINDUP_DEFAULT = 0
local JUMP_ATTACK_DURATION_DEFAULT = 0.40
local JUMP_ATTACK_HEIGHT_DEFAULT = 3
local JUMP_ATTACK_MAX_DISTANCE_DEFAULT = 18
local JUMP_ATTACK_FORWARD_BIAS_DEFAULT = 1.35
local JUMP_ATTACK_IMPACT_RADIUS_DEFAULT = 4.5
local JUMP_ATTACK_RECOVERY_DEFAULT = 0.35

local function buildNavigationFilter(state, includeCharacters)
	local excluded = { state.Model }
	if not includeCharacters then
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(excluded, player.Character)
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function findLoopAnimation(model)
	local namedAnimation = model:FindFirstChild("MimicLoopAnimation", true)
	if namedAnimation and namedAnimation:IsA("Animation") and namedAnimation.AnimationId ~= "" then
		return namedAnimation
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Animation") and descendant.AnimationId ~= "" then
			return descendant
		end
	end

	local animationId = model:GetAttribute("MimicAnimationId")
	if typeof(animationId) == "number" then
		animationId = tostring(math.floor(animationId))
	end
	if typeof(animationId) ~= "string" or animationId == "" then
		return nil,
			"MimicChest precisa de um Animation chamado MimicLoopAnimation " .. "ou do atributo MimicAnimationId"
	end
	if not string.find(animationId, "rbxassetid://", 1, true) then
		animationId = "rbxassetid://" .. animationId
	end

	local animation = Instance.new("Animation")
	animation.Name = "MimicLoopAnimation"
	animation.AnimationId = animationId
	animation.Parent = model
	return animation
end

local function loadLoopTrack(model, humanoid)
	local animation, reason = findLoopAnimation(model)
	if not animation then
		return nil, reason
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local ok, trackOrReason = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil, "Falha ao carregar a animacao do Mimico: " .. tostring(trackOrReason)
	end

	local track = trackOrReason
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	return track
end

local function shouldAnimate(state)
	return state.Model.Parent ~= nil
		and state.Humanoid.Health > 0
		and state.Model:GetAttribute("Enabled") ~= false
		and state.State ~= STATE_DORMANT
end

local function synchronizeAnimation(state)
	local track = state.AnimationTrack
	if not track then
		return
	end

	if shouldAnimate(state) then
		local speed = math.max(0.05, tonumber(state.Model:GetAttribute("AnimationSpeed")) or 1)
		track.Looped = true
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		else
			track:Play(0.08, 1, speed)
		end
	elseif track.IsPlaying then
		track:Stop(0.08)
	end
end

local function getRoot(model)
	local skinnedRoot = model:FindFirstChild("Cube.002", true)
	if skinnedRoot and skinnedRoot:IsA("BasePart") then
		return skinnedRoot
	end
	return model:FindFirstChild("MimicRoot", true)
		or model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function removeLegacyMovementRoot(model)
	-- Versoes anteriores criavam uma HumanoidRootPart soldada ao MimicRoot.
	-- Essa montagem disputa CFrame com a animacao procedural do bau.
	local legacyWeld = model:FindFirstChild("MimicMovementRootWeld", true)
	if not legacyWeld or not legacyWeld:IsA("WeldConstraint") then
		return
	end
	local movementRoot = legacyWeld.Parent
	legacyWeld:Destroy()
	if movementRoot and movementRoot:IsA("BasePart") and movementRoot.Name == "HumanoidRootPart" then
		movementRoot:Destroy()
	end
end

local function claimServerNetworkOwnership(model)
	-- Pecas desancoradas recebem ownership automatico do cliente mais proximo.
	-- Como a animacao procedural escreve CFrame a partir de um Script do servidor,
	-- o servidor precisa ser a autoridade apenas das assemblies fisicas. Assemblies
	-- ancoradas (ou soldadas a uma peca ancorada) nao possuem network owner.
	local claimedAssemblies = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local assemblyRoot = descendant.AssemblyRootPart or descendant
			if not claimedAssemblies[assemblyRoot] then
				claimedAssemblies[assemblyRoot] = true

				local anchoredAssembly = assemblyRoot.Anchored
				if not anchoredAssembly then
					for _, connectedPart in ipairs(assemblyRoot:GetConnectedParts(true)) do
						if connectedPart.Anchored then
							anchoredAssembly = true
							break
						end
					end
				end

				if not anchoredAssembly then
					local canSet, reason = assemblyRoot:CanSetNetworkOwnership()
					if canSet then
						local setOk, setReason = pcall(function()
							assemblyRoot:SetNetworkOwner(nil)
						end)
						if not setOk then
							warn(
								string.format(
									"[MimicAI] Falha inesperada ao atribuir ownership de %s: %s",
									assemblyRoot:GetFullName(),
									tostring(setReason)
								)
							)
						end
					else
						warn(
							string.format(
								"[MimicAI] Nao foi possivel atribuir ao servidor o ownership de %s: %s",
								assemblyRoot:GetFullName(),
								tostring(reason)
							)
						)
					end
				end
			end
		end
	end
end

local function zeroAssemblyVelocity(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function stabilizeKinematicAssembly(state)
	local root = state.Root
	if not root or not root.Parent then
		return
	end

	if not root.Anchored then
		root.Anchored = true
		zeroAssemblyVelocity(state.Model)
	end

	-- Se algum script antigo ou uma forca externa moveu a raiz, sincronize a
	-- posicao logica antes do proximo passo. Durante o salto, a propria IA e a
	-- unica autoridade e nao deve ter sua trajetoria sobrescrita.
	if state.AttackPhase ~= "SpecialJump" then
		local pivotPosition = state.Model:GetPivot().Position
		if (pivotPosition - state.Position).Magnitude > ROOT_DESYNC_TOLERANCE then
			state.Position = pivotPosition
		end
	end
end

local function horizontalOffset(fromPosition, toPosition)
	return Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
end

local function faceHorizontal(state, destination)
	local direction = horizontalOffset(state.Position, destination)
	if direction.Magnitude <= 0.001 then
		return
	end

	local pivot = state.Model:GetPivot()
	local yawOffset = math.rad(tonumber(state.Model:GetAttribute("FacingYawOffset")) or 0)
	state.Model:PivotTo(
		CFrame.lookAt(pivot.Position, pivot.Position + direction.Unit, Vector3.yAxis) * CFrame.Angles(math.rad(90), yawOffset, 0)
	)
end

local function belongsToOriginIsland(state, instance)
	return instance ~= nil and (not state.Island or not state.Island.Parent or instance:IsDescendantOf(state.Island))
end

local function belongsToAnotherCombatTarget(state, instance)
	local current = instance
	while current and current ~= workspace do
		if current ~= state.Model and CollectionService:HasTag(current, "CombatTarget") then
			return true
		end
		if current == state.Island then
			break
		end
		current = current.Parent
	end
	return false
end

local function findSafeGround(state, position)
	local probeHeight = state.GroundProbeHeight
	local result = workspace:Raycast(
		position + Vector3.new(0, probeHeight, 0),
		Vector3.new(0, -(probeHeight + state.GroundProbeDepth), 0),
		buildNavigationFilter(state, false)
	)
	if not result or not result.Instance:IsA("BasePart") then
		return nil
	end
	if
		not result.Instance.Anchored
		or not result.Instance.CanCollide
		or not belongsToOriginIsland(state, result.Instance)
		or belongsToAnotherCombatTarget(state, result.Instance)
	then
		return nil
	end
	return result
end

local function hasSafeGround(state, position)
	return findSafeGround(state, position) ~= nil
end

local function getGroundedPosition(state, position)
	local result = findSafeGround(state, position)
	if not result then
		return nil
	end
	return Vector3.new(position.X, result.Position.Y + state.GroundOffset, position.Z)
end

local function pathIsBlocked(state, destination, extraDistance)
	local offset = horizontalOffset(state.Position, destination)
	local distance = offset.Magnitude
	if distance <= 0.05 then
		return false
	end

	local castDistance = math.min(distance, math.max(0, extraDistance or distance))
	local direction = offset.Unit * castDistance
	local rootHeight = math.max(1, state.Root.Size.Y)
	local params = buildNavigationFilter(state, false)
	local lowerOrigin = state.Position + Vector3.new(0, math.max(0.65, rootHeight * 0.18), 0)
	local upperOrigin = state.Position + Vector3.new(0, math.max(1.4, rootHeight * 0.55), 0)

	for _, origin in ipairs({ lowerOrigin, upperOrigin }) do
		local hit = workspace:Raycast(origin, direction, params)
		if hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
			return true
		end
	end
	return false
end

local function targetHasLineOfSight(state, targetRoot)
	if not targetRoot or not targetRoot.Parent then
		return false
	end
	local targetCharacter = targetRoot.Parent
	local origin = state.Position + Vector3.new(0, math.max(1, state.Root.Size.Y * 0.45), 0)
	local destination = targetRoot.Position
	local result = workspace:Raycast(origin, destination - origin, buildNavigationFilter(state, true))
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

local function moveModelTowards(state, destination, speed, dt, stopDistance)
	local offset = horizontalOffset(state.Position, destination)
	local distance = offset.Magnitude
	stopDistance = math.max(0, stopDistance or 0)
	if distance <= stopDistance + 0.001 then
		faceHorizontal(state, destination)
		return 0
	end
	local stepDistance = math.min(distance - stopDistance, math.max(0, speed) * dt)
	local delta = offset.Unit * stepDistance

	if pathIsBlocked(state, destination, stepDistance + state.ObstaclePadding) then
		state.NavigationBlockedSince = state.NavigationBlockedSince or os.clock()
		return 0, "Blocked"
	end
	if not hasSafeGround(state, state.Position + delta) then
		state.NavigationBlockedSince = state.NavigationBlockedSince or os.clock()
		return 0, "NoGround"
	end

	state.NavigationBlockedSince = nil
	-- Uma unica escrita de PivotTo por frame evita a microtravada causada pela
	-- antiga sequencia "girar e depois mover" em dois pivots consecutivos.
	local pivot = state.Model:GetPivot()
	local newPosition = pivot.Position + delta
	local yawOffset = math.rad(tonumber(state.Model:GetAttribute("FacingYawOffset")) or 0)
	state.Model:PivotTo(
		CFrame.lookAt(newPosition, newPosition + offset.Unit, Vector3.yAxis) * CFrame.Angles(math.rad(90), yawOffset, 0)
	)
	state.Position += delta
	return stepDistance, nil
end

local function updateKinematicKnockback(state, dt)
	local remaining = state.KnockbackRemaining
	if typeof(remaining) ~= "Vector3" or remaining.Magnitude <= 0.001 then
		state.KnockbackRemaining = Vector3.zero
		state.KnockbackTimeRemaining = 0
		return false
	end

	local timeRemaining = math.max(dt, state.KnockbackTimeRemaining)
	-- Ease-out curto: o impacto comeca forte e termina sem um tranco seco.
	local progress = math.clamp(dt / timeRemaining, 0, 1)
	local alpha = 1 - (1 - progress) * (1 - progress)
	local delta = remaining * alpha
	local destination = state.Position + delta
	if
		pathIsBlocked(state, destination, delta.Magnitude + state.ObstaclePadding)
		or not hasSafeGround(state, destination)
	then
		state.KnockbackRemaining = Vector3.zero
		state.KnockbackTimeRemaining = 0
		return false
	end

	state.Model:PivotTo(state.Model:GetPivot() + delta)
	state.Position += delta
	state.KnockbackRemaining -= delta
	state.KnockbackTimeRemaining = math.max(0, state.KnockbackTimeRemaining - dt)
	if state.KnockbackTimeRemaining <= 0.001 then
		state.KnockbackRemaining = Vector3.zero
	end
	return true
end

local function getDamager(model, humanoid)
	local creator = humanoid:FindFirstChild("creator")
	if creator and creator:IsA("ObjectValue") and creator.Value and creator.Value:IsA("Player") then
		return creator.Value
	end
	local userId = model:GetAttribute("LastDamagedByUserId")
	return typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
end

local function playerIsOnOriginIsland(player, state)
	if state.IslandKey then
		local currentIslandKey = player:GetAttribute("CurrentIslandKey")
		if currentIslandKey ~= nil then
			return currentIslandKey == state.IslandKey
		end
	end

	-- Compatibility for old/static islands and for the brief moment before the
	-- chunk manager publishes CurrentIslandKey on a newly entered island.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - state.Home).Magnitude <= state.IslandFallbackRadius
end

local function nearestPlayer(position, maximumDistance, state)
	local nearestHumanoid
	local nearestRoot
	local nearestPlayer
	local distance = maximumDistance
	local originIslandOccupied = false
	for _, player in ipairs(Players:GetPlayers()) do
		if
			player:GetAttribute("IsDowned") == true
			or player:GetAttribute("InvisibleToEnemies") == true
		then
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and playerIsOnOriginIsland(player, state) then
			originIslandOccupied = true
			local current = (root.Position - position).Magnitude
			if current < distance then
				distance = current
				nearestHumanoid = humanoid
				nearestRoot = root
				nearestPlayer = player
			end
		end
	end
	return nearestHumanoid, nearestRoot, distance, originIslandOccupied, nearestPlayer
end

local function setProceduralScriptsEnabled(state, enabled)
	for scriptInstance, wasEnabled in pairs(state.ProceduralScripts) do
		if scriptInstance.Parent then
			scriptInstance.Disabled = not (enabled and wasEnabled)
		end
	end
end

local function setModelEnabled(state, enabled)
	state.Model:SetAttribute("Enabled", enabled)
	for part, properties in pairs(state.PartProperties) do
		if part.Parent then
			if enabled then
				part.Transparency = properties.Transparency
				part.CanCollide = properties.CanCollide
				part.CanTouch = properties.CanTouch
				part.CanQuery = properties.CanQuery
			else
				part.Transparency = 1
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
	end
	for effect, wasEnabled in pairs(state.EffectProperties) do
		if effect.Parent then
			effect.Enabled = enabled and wasEnabled
		end
	end
end

local function refreshHomeFromIsland(state)
	if not state.Island or not state.Island.Parent or not state.HomeRelativeToIsland then
		return
	end
	local previousHome = state.Home
	state.HomePivot = state.Island:GetPivot() * state.HomeRelativeToIsland
	state.Home = state.HomePivot.Position
	if previousHome then
		state.Position += state.Home - previousHome
	end
	if state.NormalChestRelativeToIsland then
		state.NormalChestPivot = state.Island:GetPivot() * state.NormalChestRelativeToIsland
	end
	state.Model:SetAttribute("HomePosition", state.Home)
end

local function setMimicState(state, newState)
	if state.State == newState then
		return
	end
	state.State = newState
	state.AttackSerial = (state.AttackSerial or 0) + 1
	state.AttackPhase = nil
	state.AttackTargetHumanoid = nil
	state.AttackTargetRoot = nil
	state.JumpStartPosition = nil
	state.JumpLandingPosition = nil
	state.Model:SetAttribute("MimicAttacking", false)
	state.Model:SetAttribute("MimicSpecialAttacking", false)
	state.Model:SetAttribute("MimicState", newState)
	state.Model:SetAttribute("MimicAwake", newState ~= STATE_DORMANT)

	if newState == STATE_AWAKE then
		state.ForceDormantOnReturn = false
		state.UnreachableSince = nil
		if state.OnAwake then
			local ok, reason = pcall(state.OnAwake, state.Model, state.DormantDisguise)
			if not ok then
				warn("[MimicAI] Falha ao remover disfarce NormalChest: " .. tostring(reason))
			end
		end
		state.DormantDisguise = nil
		setModelEnabled(state, true)
		state.Model:SetAttribute("Peaceful", false)
		if not CollectionService:HasTag(state.Model, "CombatTarget") then
			CollectionService:AddTag(state.Model, "CombatTarget")
			MobEventModifiers.Apply(state.Model)
		end
		state.Humanoid.AutoRotate = false
		state.Humanoid.WalkSpeed = state.OriginalWalkSpeed
		state.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
		state.Humanoid.HealthDisplayDistance = 18
		state.Humanoid.NameDisplayDistance = 18
		setProceduralScriptsEnabled(state, true)
		synchronizeAnimation(state)
	elseif newState == STATE_RETURNING then
		state.TargetHumanoid = nil
		state.TargetRoot = nil
		state.Humanoid.AutoRotate = false
		state.Humanoid.WalkSpeed = state.ReturnWalkSpeed
		state.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		synchronizeAnimation(state)
	else
		state.TargetHumanoid = nil
		state.TargetRoot = nil
		state.ForceDormantOnReturn = false
		state.UnreachableSince = nil
		state.KnockbackRemaining = Vector3.zero
		state.KnockbackTimeRemaining = 0
		state.Humanoid.AutoRotate = false
		state.Humanoid.WalkSpeed = 0
		state.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		setProceduralScriptsEnabled(state, false)
		state.Humanoid.Health = state.Humanoid.MaxHealth
		state.Model:SetAttribute("Peaceful", true)
		if CollectionService:HasTag(state.Model, "CombatTarget") then
			CollectionService:RemoveTag(state.Model, "CombatTarget")
		end
		state.Model:PivotTo(state.HomePivot)
		state.Position = state.Home
		for part, relativeCFrame in pairs(state.HomePose) do
			if part.Parent and part.Anchored then
				part.CFrame = state.HomePivot * relativeCFrame
			end
		end
		for _, descendant in ipairs(state.Model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
		setModelEnabled(state, false)
		synchronizeAnimation(state)
		if state.OnDormant then
			local ok, disguiseOrReason = pcall(state.OnDormant, state.Model, state.NormalChestPivot)
			if ok then
				state.DormantDisguise = disguiseOrReason
			else
				warn("[MimicAI] Falha ao criar disfarce NormalChest: " .. tostring(disguiseOrReason))
			end
		end
	end
end

local function cancelAttack(state)
	if state.AttackPhase == "SpecialJump" and state.JumpStartPosition then
		-- Interrupcoes nunca podem deixar o modelo cinemático suspenso no ar.
		local landingPosition = getGroundedPosition(state, state.Position)
			or getGroundedPosition(state, state.JumpStartPosition)
			or state.JumpStartPosition
		local pivot = state.Model:GetPivot()
		state.Model:PivotTo(CFrame.new(landingPosition) * pivot.Rotation)
		state.Position = landingPosition
	end
	state.AttackSerial += 1
	state.AttackPhase = nil
	state.AttackTargetHumanoid = nil
	state.AttackTargetRoot = nil
	state.JumpStartPosition = nil
	state.JumpLandingPosition = nil
	state.Model:SetAttribute("MimicAttacking", false)
	state.Model:SetAttribute("MimicSpecialAttacking", false)
end

local function returnHomeSafely(state, dt)
	local moved, blockedReason = moveModelTowards(state, state.Home, state.ReturnWalkSpeed, dt)
	if
		moved <= 0
		and blockedReason
		and state.NavigationBlockedSince
		and os.clock() - state.NavigationBlockedSince >= state.BlockedRecoveryDelay
		and hasSafeGround(state, state.Home)
	then
		cancelAttack(state)
		state.Model:PivotTo(state.HomePivot)
		state.Position = state.Home
		state.NavigationBlockedSince = nil
		for _, descendant in ipairs(state.Model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	return moved, blockedReason
end

local function targetIsValidForAttack(state, extraRange)
	local humanoid = state.AttackTargetHumanoid
	local root = state.AttackTargetRoot
	if
		state.State ~= STATE_AWAKE
		or state.Model:GetAttribute("CombatStunned") == true
		or not humanoid
		or humanoid.Health <= 0
		or not humanoid.Parent
		or not root
		or not root.Parent
	then
		return false
	end

	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	if
		not player
		or player:GetAttribute("IsDowned") == true
		or not playerIsOnOriginIsland(player, state)
	then
		return false
	end

	local horizontalDistance = horizontalOffset(state.Position, root.Position).Magnitude
	local verticalDistance = math.abs(root.Position.Y - state.Position.Y)
	return horizontalDistance <= state.AttackRange + (extraRange or 0)
		and verticalDistance <= state.AttackVerticalTolerance
		and targetHasLineOfSight(state, root)
end

local function beginAttack(state)
	local now = os.clock()
	if
		state.Model:GetAttribute("CombatStunned") == true
		or now < state.NextAttackAt
		or state.AttackPhase ~= nil
		or not state.TargetHumanoid
		or state.TargetHumanoid.Health <= 0
		or not state.TargetRoot
		or not state.TargetRoot.Parent
	then
		return
	end

	local horizontalDistance = horizontalOffset(state.Position, state.TargetRoot.Position).Magnitude
	local verticalDistance = math.abs(state.TargetRoot.Position.Y - state.Position.Y)
	if
		horizontalDistance > state.AttackRange
		or verticalDistance > state.AttackVerticalTolerance
		or not targetHasLineOfSight(state, state.TargetRoot)
	then
		return
	end

	state.AttackSerial += 1
	state.AttackPhase = "Windup"
	state.AttackPhaseStartedAt = now
	state.AttackTargetHumanoid = state.TargetHumanoid
	state.AttackTargetRoot = state.TargetRoot
	state.NextAttackAt = now + state.AttackCooldown
	state.Model:SetAttribute("MimicAttacking", true)
	faceHorizontal(state, state.AttackTargetRoot.Position)
end

local function targetIsValidForSpecialJump(state)
	local humanoid = state.AttackTargetHumanoid
	local root = state.AttackTargetRoot
	if
		state.State ~= STATE_AWAKE
		or state.Model:GetAttribute("CombatStunned") == true
		or not humanoid
		or humanoid.Health <= 0
		or not humanoid.Parent
		or not root
		or not root.Parent
	then
		return false
	end

	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	if
		not player
		or player:GetAttribute("IsDowned") == true
		or not playerIsOnOriginIsland(player, state)
	then
		return false
	end

	local referencePosition = state.JumpStartPosition or state.Position
	local horizontalDistance = horizontalOffset(referencePosition, root.Position).Magnitude
	local verticalDistance = math.abs(root.Position.Y - referencePosition.Y)
	return horizontalDistance <= state.JumpAttackRange + state.JumpAttackImpactRadius
		and verticalDistance <= state.JumpAttackVerticalTolerance
end

local function prepareSpecialJumpDestination(state, targetPosition)
	local direction = horizontalOffset(state.Position, targetPosition)
	if direction.Magnitude <= 0.001 then
		return nil
	end

	local travelDistance =
		math.min(state.JumpAttackMaxDistance, math.max(0, direction.Magnitude - state.JumpAttackLandingOffset))
	if travelDistance <= 0.05 then
		return nil
	end

	local destination = state.Position + direction.Unit * travelDistance
	if pathIsBlocked(state, destination, travelDistance + state.ObstaclePadding) then
		return nil
	end
	local groundedDestination = getGroundedPosition(state, destination)
	if
		not groundedDestination
		or math.abs(groundedDestination.Y - state.Position.Y) > state.JumpAttackLandingVerticalTolerance
	then
		return nil
	end
	return groundedDestination
end

local function beginSpecialJump(state)
	local now = os.clock()
	if
		state.Model:GetAttribute("CombatStunned") == true
		or now < state.NextSpecialJumpAt
		or state.AttackPhase ~= nil
		or not state.TargetHumanoid
		or state.TargetHumanoid.Health <= 0
		or not state.TargetRoot
		or not state.TargetRoot.Parent
	then
		return false
	end

	local horizontalDistance = horizontalOffset(state.Position, state.TargetRoot.Position).Magnitude
	local verticalDistance = math.abs(state.TargetRoot.Position.Y - state.Position.Y)
	local destination = prepareSpecialJumpDestination(state, state.TargetRoot.Position)
	if
		horizontalDistance < state.JumpAttackMinRange
		or horizontalDistance > state.JumpAttackRange
		or verticalDistance > state.JumpAttackVerticalTolerance
		or not targetHasLineOfSight(state, state.TargetRoot)
		or not destination
	then
		return false
	end

	state.AttackSerial += 1
	-- O bote comeca no mesmo frame em que e escolhido. A pausa antiga dava
	-- tempo demais para o jogador sair da trajetoria antes do Mimico avancar.
	state.AttackPhase = "SpecialJump"
	state.AttackPhaseStartedAt = now
	state.AttackTargetHumanoid = state.TargetHumanoid
	state.AttackTargetRoot = state.TargetRoot
	state.JumpStartPosition = state.Position
	state.JumpLandingPosition = destination
	state.NextSpecialJumpAt = now + state.JumpAttackCooldown
	state.NextAttackAt = math.max(state.NextAttackAt, now + state.JumpAttackDuration)
	state.Model:SetAttribute("MimicAttacking", true)
	state.Model:SetAttribute("MimicSpecialAttacking", true)
	faceHorizontal(state, state.AttackTargetRoot.Position)
	return true
end

local function updateAttack(state, now, dt)
	if not state.AttackPhase then
		return false
	end

	if state.AttackPhase == "SpecialJump" then
		local alpha = math.clamp((now - state.AttackPhaseStartedAt) / math.max(0.01, state.JumpAttackDuration), 0, 1)
		-- O salto do Mimico e um bote, nao um pulo vertical. O avanco usa
		-- ease-out para ganhar distancia logo no inicio, enquanto o arco baixo
		-- preserva a leitura visual do ataque sem deixa-lo suspenso no ar.
		local horizontalAlpha = 1 - math.pow(1 - alpha, state.JumpAttackForwardBias)
		local horizontalPosition = state.JumpStartPosition:Lerp(state.JumpLandingPosition, horizontalAlpha)
		local jumpHeight = math.sin(math.pi * alpha) * state.JumpAttackHeight
		local newPosition = horizontalPosition + Vector3.new(0, jumpHeight, 0)
		local direction = horizontalOffset(state.JumpStartPosition, state.JumpLandingPosition)
		local yawOffset = math.rad(tonumber(state.Model:GetAttribute("FacingYawOffset")) or 0)
		state.Model:PivotTo(
			CFrame.lookAt(newPosition, newPosition + direction.Unit, Vector3.yAxis) * CFrame.Angles(math.rad(90), yawOffset, 0)
		)
		state.Position = newPosition

		if alpha >= 1 then
			state.Position = state.JumpLandingPosition
			if
				targetIsValidForSpecialJump(state)
				and (state.AttackTargetRoot.Position - state.Position).Magnitude <= state.JumpAttackImpactRadius
				and targetHasLineOfSight(state, state.AttackTargetRoot)
			then
				PlayerDamageService.ApplyToHumanoid(
					state.AttackTargetHumanoid,
					state.JumpAttackDamage,
					"MimicChestSpecialJump"
				)
				state.Model:SetAttribute(
					"MimicSpecialImpactSerial",
					(state.Model:GetAttribute("MimicSpecialImpactSerial") or 0) + 1
				)
			end
			state.AttackPhase = "SpecialRecovery"
			state.AttackPhaseStartedAt = now
			state.JumpStartPosition = nil
			state.JumpLandingPosition = nil
		end
		return true
	end

	if state.AttackPhase == "SpecialRecovery" then
		if now - state.AttackPhaseStartedAt >= state.JumpAttackRecovery then
			cancelAttack(state)
		end
		return true
	end

	if not targetIsValidForAttack(state, state.AttackHitExtraRange) then
		cancelAttack(state)
		return false
	end

	local targetPosition = state.AttackTargetRoot.Position
	faceHorizontal(state, targetPosition)

	if state.AttackPhase == "Windup" then
		if now - state.AttackPhaseStartedAt >= state.AttackWindup then
			state.AttackPhase = "Lunge"
			state.AttackPhaseStartedAt = now
			local direction = horizontalOffset(state.Position, targetPosition)
			if direction.Magnitude > 0.001 then
				local distanceToTravel = math.min(state.AttackLungeDistance, math.max(0, direction.Magnitude - 2.25))
				state.AttackLungeDestination = state.Position + direction.Unit * distanceToTravel
			else
				state.AttackLungeDestination = state.Position
			end
		end
		return true
	end

	if state.AttackPhase == "Lunge" then
		local lungeSpeed = state.AttackLungeDistance / math.max(0.01, state.AttackLungeDuration)
		local _, blockedReason = moveModelTowards(state, state.AttackLungeDestination, lungeSpeed, dt)
		if blockedReason then
			cancelAttack(state)
			return false
		end
		if now - state.AttackPhaseStartedAt >= state.AttackLungeDuration then
			if targetIsValidForAttack(state, state.AttackHitExtraRange) then
				PlayerDamageService.ApplyToHumanoid(state.AttackTargetHumanoid, state.AttackDamage, "MimicChest")
			end
			state.AttackPhase = "Recovery"
			state.AttackPhaseStartedAt = now
		end
		return true
	end

	if now - state.AttackPhaseStartedAt >= state.AttackRecovery then
		cancelAttack(state)
	end
	return true
end

local function connectHeartbeat()
	if heartbeatConnected then
		return
	end
	heartbeatConnected = true
	RunService.Heartbeat:Connect(function(dt)
		local step = math.min(dt, MAX_MOVEMENT_DELTA_TIME)
		local now = os.clock()
		for model, state in pairs(states) do
			if not model.Parent or state.Humanoid.Health <= 0 or not state.Root.Parent then
				states[model] = nil
				continue
			end
			stabilizeKinematicAssembly(state)
			refreshHomeFromIsland(state)
			if model:GetAttribute("SimulationActive") == false then
				model:SetAttribute("AggroUserId", nil)
				model:SetAttribute("TargetUserId", nil)
				-- Once the origin island sleeps there cannot be an active player on it.
				-- Reset immediately instead of keeping an off-screen Humanoid walking.
				if state.State ~= STATE_DORMANT then
					setMimicState(state, STATE_DORMANT)
				end
				continue
			end
			if updateKinematicKnockback(state, step) then
				if state.AttackPhase then
					cancelAttack(state)
				end
				continue
			end
			if updateAttack(state, now, step) then
				continue
			end
			if model:GetAttribute("CombatStunned") == true then
				if state.AttackPhase then
					cancelAttack(state)
				end
				continue
			end
			local aggroRange = MobEventModifiers.GetAggroRange(model, state.AggroRange)
			local targetHumanoid, targetRoot, _, originIslandOccupied, targetPlayer =
				nearestPlayer(state.Position, aggroRange, state)

			if not originIslandOccupied and state.State == STATE_AWAKE then
				state.ForceDormantOnReturn = false
				setMimicState(state, STATE_RETURNING)
			end
			if state.State == STATE_RETURNING then
				if not state.ForceDormantOnReturn and originIslandOccupied and targetRoot then
					setMimicState(state, STATE_AWAKE)
					else
						model:SetAttribute("AggroUserId", nil)
						model:SetAttribute("TargetUserId", nil)
						returnHomeSafely(state, step)
					if (state.Position - state.Home).Magnitude <= HOME_SNAP_DISTANCE then
						setMimicState(state, STATE_DORMANT)
					end
					continue
				end
			end
			if state.State == STATE_DORMANT then
				model:SetAttribute("AggroUserId", nil)
				model:SetAttribute("TargetUserId", nil)
				-- Voltar para a ilha nao desperta o Mimico. Ele so acorda quando o
				-- jogador tenta abrir o NormalChest criado pelo ChestService.
				continue
			end

			state.TargetHumanoid = targetHumanoid
			state.TargetRoot = targetRoot
			model:SetAttribute("AggroUserId", targetPlayer and targetPlayer.UserId or nil)
			model:SetAttribute("TargetUserId", targetPlayer and targetPlayer.UserId or nil)
			if (state.Position - state.Home).Magnitude > state.LeashRange then
				returnHomeSafely(state, step)
			elseif targetRoot then
				-- O mimico anda no plano da ilha; nao tenta subir ate o centro do player.
				local destination = Vector3.new(targetRoot.Position.X, state.Position.Y, targetRoot.Position.Z)
				local horizontalDistance = horizontalOffset(state.Position, destination).Magnitude
				local verticalDistance = math.abs(targetRoot.Position.Y - state.Position.Y)
				local targetReachable = verticalDistance <= state.MaxChaseVerticalDifference
					and targetHasLineOfSight(state, targetRoot)
					and not pathIsBlocked(state, destination, math.min(horizontalDistance, state.ObstacleLookAhead))

				if not targetReachable then
					cancelAttack(state)
					state.TargetHumanoid = nil
					state.TargetRoot = nil
					state.UnreachableSince = state.UnreachableSince or now
					if now - state.UnreachableSince >= state.UnreachableReturnDelay then
						state.ForceDormantOnReturn = true
						if (state.Position - state.Home).Magnitude <= HOME_SNAP_DISTANCE then
							setMimicState(state, STATE_DORMANT)
						else
							setMimicState(state, STATE_RETURNING)
						end
					elseif (state.Position - state.Home).Magnitude > HOME_SNAP_DISTANCE then
						returnHomeSafely(state, step)
					end
				else
					state.UnreachableSince = nil
				end

				if
					targetReachable
					and horizontalDistance >= state.JumpAttackMinRange
					and horizontalDistance <= state.JumpAttackRange
					and now >= state.NextSpecialJumpAt
					and beginSpecialJump(state)
				then
					-- O ataque especial assume o controle do movimento ate a aterrissagem.
				elseif targetReachable and horizontalDistance <= state.AttackRange then
					faceHorizontal(state, destination)
					beginAttack(state)
				elseif targetReachable then
					local moved, blockedReason =
						moveModelTowards(state, destination, state.OriginalWalkSpeed, step, state.AttackRange * 0.82)
					if moved <= 0 and blockedReason then
						cancelAttack(state)
						state.TargetHumanoid = nil
						state.TargetRoot = nil
					end
				end
			else
				state.UnreachableSince = nil
				returnHomeSafely(state, step)
			end
		end
	end)
end

function MimicAI.Activate(model, options)
	options = options or {}
	if states[model] then
		return true
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = getRoot(model)
	if not humanoid or not root or not root:IsA("BasePart") then
		return false, "MimicChest precisa de Humanoid e do MeshPart Cube.002 (ou uma PrimaryPart valida)"
	end
	local animationTrack, animationReason = loadLoopTrack(model, humanoid)
	if not animationTrack then
		return false, animationReason
	end
	removeLegacyMovementRoot(model)
	-- A IA usa PivotTo e, portanto, e cinemática. Manter o unico MeshPart
	-- ancorado evita que colisoes acumulem impulso e lancem o Mimico da ilha.
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	claimServerNetworkOwnership(model)
	model.PrimaryPart = root
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("MonsterId", "MimicChest")
	model:SetAttribute("DisplayName", "Bau Mimico")
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("AIController", "Mimic")
	model:SetAttribute("KinematicMovement", true)
	local island = model:FindFirstAncestorWhichIsA("Model")
	while island and island:GetAttribute("IsSkyIsland") ~= true do
		island = island:FindFirstAncestorWhichIsA("Model")
	end
	local islandKey = island and island:GetAttribute("IslandNodeKey") or nil
	model:SetAttribute("SimulationActive", not island or island:GetAttribute("SimulationActive") ~= false)
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("IsMimic", true)
	model:SetAttribute("CanBecomeCompanion", false)
	model:SetAttribute("HomePosition", root.Position)
	CollectionService:AddTag(model, "CombatTarget")
	MobEventModifiers.Apply(model)
	AnimeOutline.Apply(model)

	local tier = math.max(1, math.floor(tonumber(options.DifficultyTier) or 1))
	humanoid.MaxHealth = math.floor((tonumber(model:GetAttribute("MaxHealth")) or 90) * (1 + (tier - 1) * 0.20))
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayName = "Bau Mimico"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 18
	humanoid.HealthDisplayDistance = 16
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false

	local proceduralScripts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			proceduralScripts[descendant] = not descendant.Disabled
		end
	end
	local homePivot = model:GetPivot()
	local boundingBox, boundingSize = model:GetBoundingBox()
	local groundOffset = math.max(0, homePivot.Position.Y - (boundingBox.Position.Y - boundingSize.Y * 0.5))
	local homeRelativeToIsland = island and island:GetPivot():ToObjectSpace(homePivot) or nil
	local normalChestPivot = typeof(options.NormalChestPivot) == "CFrame" and options.NormalChestPivot or homePivot
	local normalChestRelativeToIsland = island and island:GetPivot():ToObjectSpace(normalChestPivot) or nil
	local homePose = {}
	local partProperties = {}
	local effectProperties = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partProperties[descendant] = {
				Transparency = descendant.Transparency,
				CanCollide = descendant.CanCollide,
				CanTouch = descendant.CanTouch,
				CanQuery = descendant.CanQuery,
			}
		end
		if descendant:IsA("BasePart") and descendant ~= root then
			homePose[descendant] = homePivot:ToObjectSpace(descendant.CFrame)
		end
		if
			descendant:IsA("Highlight")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
		then
			effectProperties[descendant] = descendant.Enabled
		end
	end

	local configuredWalkSpeed = tonumber(model:GetAttribute("WalkSpeed"))
	local baseWalkSpeed = configuredWalkSpeed or humanoid.WalkSpeed
	if baseWalkSpeed <= 0 then
		baseWalkSpeed = 9
	end
	local originalWalkSpeed = baseWalkSpeed * MOVEMENT_SPEED_MULTIPLIER
	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Position = root.Position,
		Home = root.Position,
		HomePivot = homePivot,
		GroundOffset = groundOffset,
		HomeRelativeToIsland = homeRelativeToIsland,
		NormalChestPivot = normalChestPivot,
		NormalChestRelativeToIsland = normalChestRelativeToIsland,
		HomePose = homePose,
		PartProperties = partProperties,
		EffectProperties = effectProperties,
		Island = island,
		IslandKey = typeof(islandKey) == "string" and islandKey or nil,
		IslandFallbackRadius = tonumber(model:GetAttribute("IslandFallbackRadius")) or 52,
		State = STATE_AWAKE,
		ProceduralScripts = proceduralScripts,
		OriginalWalkSpeed = originalWalkSpeed,
		ReturnWalkSpeed = tonumber(model:GetAttribute("ReturnWalkSpeed")) or math.max(10, originalWalkSpeed),
		AggroRange = tonumber(model:GetAttribute("AggroRange")) or 58,
		LeashRange = tonumber(model:GetAttribute("LeashRange")) or 46,
		AttackRange = tonumber(model:GetAttribute("AttackRange")) or 5.5,
		AttackCooldown = tonumber(model:GetAttribute("AttackCooldown")) or 1.15,
		AttackDamage = math.floor((tonumber(model:GetAttribute("AttackDamage")) or 12) * (1 + (tier - 1) * 0.12)),
		AttackWindup = tonumber(model:GetAttribute("AttackWindup")) or ATTACK_WINDUP_DEFAULT,
		AttackLungeDuration = tonumber(model:GetAttribute("AttackLungeDuration")) or ATTACK_LUNGE_DURATION_DEFAULT,
		AttackRecovery = tonumber(model:GetAttribute("AttackRecovery")) or ATTACK_RECOVERY_DEFAULT,
		AttackLungeDistance = tonumber(model:GetAttribute("AttackLungeDistance")) or ATTACK_LUNGE_DISTANCE_DEFAULT,
		AttackHitExtraRange = tonumber(model:GetAttribute("AttackHitExtraRange")) or 0.75,
		AttackVerticalTolerance = tonumber(model:GetAttribute("AttackVerticalTolerance")) or 4,
		JumpAttackRange = tonumber(model:GetAttribute("JumpAttackRange")) or JUMP_ATTACK_RANGE_DEFAULT,
		JumpAttackMinRange = tonumber(model:GetAttribute("JumpAttackMinRange")) or JUMP_ATTACK_MIN_RANGE_DEFAULT,
		JumpAttackCooldown = tonumber(model:GetAttribute("JumpAttackCooldown")) or JUMP_ATTACK_COOLDOWN_DEFAULT,
		JumpAttackWindup = tonumber(model:GetAttribute("JumpAttackWindup")) or JUMP_ATTACK_WINDUP_DEFAULT,
		JumpAttackDuration = tonumber(model:GetAttribute("JumpAttackDuration")) or JUMP_ATTACK_DURATION_DEFAULT,
		JumpAttackHeight = tonumber(model:GetAttribute("JumpAttackHeight")) or JUMP_ATTACK_HEIGHT_DEFAULT,
		JumpAttackMaxDistance = tonumber(model:GetAttribute("JumpAttackMaxDistance"))
			or JUMP_ATTACK_MAX_DISTANCE_DEFAULT,
		JumpAttackForwardBias = math.max(
			1,
			tonumber(model:GetAttribute("JumpAttackForwardBias")) or JUMP_ATTACK_FORWARD_BIAS_DEFAULT
		),
		JumpAttackImpactRadius = tonumber(model:GetAttribute("JumpAttackImpactRadius"))
			or JUMP_ATTACK_IMPACT_RADIUS_DEFAULT,
		JumpAttackRecovery = tonumber(model:GetAttribute("JumpAttackRecovery")) or JUMP_ATTACK_RECOVERY_DEFAULT,
		JumpAttackLandingOffset = tonumber(model:GetAttribute("JumpAttackLandingOffset")) or 1.75,
		JumpAttackVerticalTolerance = tonumber(model:GetAttribute("JumpAttackVerticalTolerance")) or 4,
		JumpAttackLandingVerticalTolerance = tonumber(model:GetAttribute("JumpAttackLandingVerticalTolerance")) or 2.5,
		JumpAttackDamage = math.floor(
			(tonumber(model:GetAttribute("JumpAttackDamage")) or 18) * (1 + (tier - 1) * 0.12)
		),
		MaxChaseVerticalDifference = tonumber(model:GetAttribute("MaxChaseVerticalDifference")) or 3.5,
		UnreachableReturnDelay = tonumber(model:GetAttribute("UnreachableReturnDelay"))
			or UNREACHABLE_RETURN_DELAY_DEFAULT,
		ObstacleLookAhead = tonumber(model:GetAttribute("ObstacleLookAhead")) or 4,
		ObstaclePadding = tonumber(model:GetAttribute("ObstaclePadding")) or 0.75,
		GroundProbeHeight = tonumber(model:GetAttribute("GroundProbeHeight")) or math.max(4, root.Size.Y + 1),
		GroundProbeDepth = tonumber(model:GetAttribute("GroundProbeDepth")) or 10,
		BlockedRecoveryDelay = tonumber(model:GetAttribute("BlockedRecoveryDelay")) or 0.75,
		NavigationBlockedSince = nil,
		UnreachableSince = nil,
		ForceDormantOnReturn = false,
		KnockbackRemaining = Vector3.zero,
		KnockbackTimeRemaining = 0,
		KinematicKnockbackDuration = tonumber(model:GetAttribute("KinematicKnockbackDuration"))
				and math.clamp(tonumber(model:GetAttribute("KinematicKnockbackDuration")), 0.08, 0.4)
			or KINEMATIC_KNOCKBACK_DURATION_DEFAULT,
		KinematicKnockbackMaxDistance = tonumber(model:GetAttribute("KinematicKnockbackMaxDistance"))
				and math.clamp(tonumber(model:GetAttribute("KinematicKnockbackMaxDistance")), 0.5, 5)
			or KINEMATIC_KNOCKBACK_MAX_DISTANCE_DEFAULT,
		NextAttackAt = os.clock() + 0.75,
		NextSpecialJumpAt = os.clock() + 2,
		AttackSerial = 0,
		AttackPhase = nil,
		OnDormant = type(options.OnDormant) == "function" and options.OnDormant or nil,
		OnAwake = type(options.OnAwake) == "function" and options.OnAwake or nil,
		DormantDisguise = nil,
		AnimationTrack = animationTrack,
		RestartingAnimation = false,
	}
	states[model] = state
	humanoid.WalkSpeed = originalWalkSpeed
	model:SetAttribute("MimicState", STATE_AWAKE)
	model:SetAttribute("MimicAwake", true)
	model:SetAttribute("MimicAttacking", false)
	model:SetAttribute("MimicSpecialAttacking", false)
	model:SetAttribute("EffectiveWalkSpeed", originalWalkSpeed)
	model:SetAttribute("Enabled", true)
	model:SetAttribute("OriginIslandKey", state.IslandKey)

	animationTrack.Stopped:Connect(function()
		if state.RestartingAnimation or not states[model] or not shouldAnimate(state) then
			return
		end
		state.RestartingAnimation = true
		task.defer(function()
			state.RestartingAnimation = false
			if states[model] and shouldAnimate(state) then
				synchronizeAnimation(state)
			end
		end)
	end)
	model:GetAttributeChangedSignal("AnimationSpeed"):Connect(function()
		if states[model] then
			synchronizeAnimation(state)
		end
	end)
	model:GetAttributeChangedSignal("Enabled"):Connect(function()
		if states[model] then
			synchronizeAnimation(state)
		end
	end)
	model:GetAttributeChangedSignal("KinematicKnockbackSerial"):Connect(function()
		if not states[model] then
			return
		end
		local request = model:GetAttribute("KinematicKnockbackRequest")
		if typeof(request) ~= "Vector3" then
			return
		end
		request = Vector3.new(request.X, 0, request.Z)
		if request.Magnitude <= 0.001 then
			return
		end
		local combined = state.KnockbackRemaining + request
		if combined.Magnitude > state.KinematicKnockbackMaxDistance then
			combined = combined.Unit * state.KinematicKnockbackMaxDistance
		end
		state.KnockbackRemaining = combined
		state.KnockbackTimeRemaining = state.KinematicKnockbackDuration
		cancelAttack(state)
	end)
	model:GetAttributeChangedSignal("CombatStunned"):Connect(function()
		if not states[model] then
			return
		end
		if model:GetAttribute("CombatStunned") == true then
			cancelAttack(state)
		end
		-- Protecao para forcas externas e CombatDamageService antigos.
		stabilizeKinematicAssembly(state)
		zeroAssemblyVelocity(state.Model)
	end)
	root:GetPropertyChangedSignal("Anchored"):Connect(function()
		if states[model] and not root.Anchored then
			task.defer(function()
				if states[model] then
					stabilizeKinematicAssembly(state)
				end
			end)
		end
	end)
	synchronizeAnimation(state)
	connectHeartbeat()

	local deathHandled = false
	local function finalizeDeath()
		if deathHandled then
			return
		end
		deathHandled = true
		cancelAttack(state)
		if animationTrack.IsPlaying then
			animationTrack:Stop(0.08)
		end
		if state.OnAwake then
			pcall(state.OnAwake, model, state.DormantDisguise)
		end
		states[model] = nil
		if CollectionService:HasTag(model, "CombatTarget") then
			CollectionService:RemoveTag(model, "CombatTarget")
		end
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end

		-- A remocao precisa ser garantida antes de chamar servicos externos.
		-- Se recompensa, inventario ou efeitos falharem, o Mimico ainda deve
		-- desaparecer. O Destroy atrasado tambem serve como fallback do Debris.
		Debris:AddItem(model, 0.8)
		task.delay(1, function()
			if model.Parent then
				model:Destroy()
			end
		end)

		local damager = getDamager(model, humanoid)
			if damager then
			local deathPosition = model:GetPivot().Position
			local rewarded, rewardReason = pcall(
				ScoreService.AwardRewards,
				damager,
				math.max(8, tonumber(options.ScoreReward) or 15),
				math.max(1, tonumber(options.CoinReward) or 50),
				"MimicChest",
				deathPosition
			)
			if not rewarded then
				warn("[MimicAI] Falha ao entregar recompensa: " .. tostring(rewardReason))
			else
				GameplayAnalytics.RecordChestRewardCollected(damager, "Coins")
			end
				if math.random() <= 0.15 then
				local granted, grantReason = pcall(InventoryService.GrantItem, damager, "GreaterHealthPotion", 1)
				if not granted then
					warn("[MimicAI] Falha ao entregar item: " .. tostring(grantReason))
					end
				end
				CompanionService.RecordDefeat(damager, model)
			end
	end

	-- Alguns rigs esqueleticos/customizados podem chegar a zero sem transicionar
	-- corretamente para o estado Dead. O fallback preserva o mesmo fluxo sem
	-- duplicar recompensas, pois finalizeDeath e idempotente.
	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			task.defer(finalizeDeath)
		end
	end)
	humanoid.Died:Connect(finalizeDeath)
	return true
end

function MimicAI.Wake(model)
	local state = states[model]
	if not state or not model.Parent or state.Humanoid.Health <= 0 then
		return false, "Mimico inexistente ou derrotado"
	end
	if state.State ~= STATE_DORMANT then
		return false, "Mimico nao esta disfarçado"
	end
	refreshHomeFromIsland(state)
	claimServerNetworkOwnership(model)
	state.Model:PivotTo(state.HomePivot)
	state.Position = state.Home
	setMimicState(state, STATE_AWAKE)
	state.NextAttackAt = os.clock() + 0.75
	state.NextSpecialJumpAt = os.clock() + 1.5
	return true
end

return MimicAI
