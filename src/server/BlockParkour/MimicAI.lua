-- V12: IA exclusiva do bau Mimico com navegacao segura contra blocos e quedas.
-- Movimento, combate e animacao esqueletica em loop
-- ficam todos neste unico ModuleScript. Nenhum Script interno e necessario.
-- O Model pode usar o MeshPart MimicRoot, a PrimaryPart ou seu unico BasePart.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local MobEventModifiers = require(script.Parent.MobEventModifiers)
local InventoryService = require(script.Parent.Parent.MVPSystems:WaitForChild("InventoryService"))
local AnimeOutline = require(ServerScriptService.MVPSystems:WaitForChild("AnimeOutline"))
ScoreService.Start()
InventoryService.Start()

local MimicAI = {}
local states = setmetatable({}, { __mode = "k" })
local heartbeatConnected = false

local STATE_AWAKE = "Awake"
local STATE_RETURNING = "Returning"
local STATE_DORMANT = "Dormant"
local HOME_SNAP_DISTANCE = 1.75
local MOVEMENT_STEP_INTERVAL = 1 / 30

local ATTACK_WINDUP_DEFAULT = 0.28
local ATTACK_LUNGE_DURATION_DEFAULT = 0.12
local ATTACK_RECOVERY_DEFAULT = 0.30
local ATTACK_LUNGE_DISTANCE_DEFAULT = 1.15

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
	-- o servidor precisa ser a autoridade de todas as assemblies do Mimico.
	local claimedAssemblies = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			local assemblyRoot = descendant.AssemblyRootPart or descendant
			if not claimedAssemblies[assemblyRoot] then
				claimedAssemblies[assemblyRoot] = true
				local canSet, reason = assemblyRoot:CanSetNetworkOwnership()
				if canSet then
					assemblyRoot:SetNetworkOwner(nil)
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
		CFrame.lookAt(pivot.Position, pivot.Position + direction.Unit, Vector3.yAxis)
			* CFrame.Angles(0, yawOffset, 0)
	)
end

local function belongsToOriginIsland(state, instance)
	return instance ~= nil
		and (not state.Island or not state.Island.Parent or instance:IsDescendantOf(state.Island))
end

local function hasSafeGround(state, position)
	local probeHeight = state.GroundProbeHeight
	local result = workspace:Raycast(
		position + Vector3.new(0, probeHeight, 0),
		Vector3.new(0, -(probeHeight + state.GroundProbeDepth), 0),
		buildNavigationFilter(state, false)
	)
	if not result or not result.Instance:IsA("BasePart") then
		return false
	end
	return result.Instance.Anchored
		and result.Instance.CanCollide
		and belongsToOriginIsland(state, result.Instance)
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
	local result = workspace:Raycast(
		origin,
		destination - origin,
		buildNavigationFilter(state, true)
	)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

local function moveModelTowards(state, destination, speed, dt, stopDistance)
	local offset = horizontalOffset(state.Position, destination)
	local distance = offset.Magnitude
	stopDistance = math.max(0, stopDistance or 0)
	faceHorizontal(state, destination)
	if distance <= stopDistance + 0.001 then
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
	state.Model:PivotTo(state.Model:GetPivot() + delta)
	state.Position += delta
	return stepDistance, nil
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
	local distance = maximumDistance
	local originIslandOccupied = false
	for _, player in ipairs(Players:GetPlayers()) do
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
			end
		end
	end
	return nearestHumanoid, nearestRoot, distance, originIslandOccupied
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
	state.Model:SetAttribute("MimicAttacking", false)
	state.Model:SetAttribute("MimicState", newState)
	state.Model:SetAttribute("MimicAwake", newState ~= STATE_DORMANT)

	if newState == STATE_AWAKE then
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
	state.AttackSerial += 1
	state.AttackPhase = nil
	state.AttackTargetHumanoid = nil
	state.AttackTargetRoot = nil
	state.Model:SetAttribute("MimicAttacking", false)
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
	if not player or not playerIsOnOriginIsland(player, state) then
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

local function updateAttack(state, now, dt)
	if not state.AttackPhase then
		return false
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
				state.AttackTargetHumanoid:TakeDamage(state.AttackDamage)
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
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < MOVEMENT_STEP_INTERVAL then
			return
		end
		local step = accumulated
		accumulated = 0
		for model, state in pairs(states) do
			if not model.Parent or state.Humanoid.Health <= 0 or not state.Root.Parent then
				states[model] = nil
				continue
			end
			refreshHomeFromIsland(state)
			if model:GetAttribute("SimulationActive") == false then
				-- Once the origin island sleeps there cannot be an active player on it.
				-- Reset immediately instead of keeping an off-screen Humanoid walking.
				if state.State ~= STATE_DORMANT then
					setMimicState(state, STATE_DORMANT)
				end
				continue
			end
			if updateAttack(state, os.clock(), step) then
				continue
			end
			if model:GetAttribute("CombatStunned") == true then
				if state.AttackPhase then
					cancelAttack(state)
				end
				continue
			end
			local aggroRange = MobEventModifiers.GetAggroRange(model, state.AggroRange)
			local targetHumanoid, targetRoot, distance, originIslandOccupied =
				nearestPlayer(state.Position, aggroRange, state)

			if not originIslandOccupied and state.State == STATE_AWAKE then
				setMimicState(state, STATE_RETURNING)
			end
			if state.State == STATE_RETURNING then
				if originIslandOccupied and targetRoot then
					setMimicState(state, STATE_AWAKE)
				else
					returnHomeSafely(state, step)
					if (state.Position - state.Home).Magnitude <= HOME_SNAP_DISTANCE then
						setMimicState(state, STATE_DORMANT)
					end
					continue
				end
			end
			if state.State == STATE_DORMANT then
				-- Voltar para a ilha nao desperta o Mimico. Ele so acorda quando o
				-- jogador tenta abrir o NormalChest criado pelo ChestService.
				continue
			end

			state.TargetHumanoid = targetHumanoid
			state.TargetRoot = targetRoot
			if (state.Position - state.Home).Magnitude > state.LeashRange then
				returnHomeSafely(state, step)
			elseif targetRoot then
				-- O mimico anda no plano da ilha; nao tenta subir ate o centro do player.
				local destination = Vector3.new(targetRoot.Position.X, state.Position.Y, targetRoot.Position.Z)
				local horizontalDistance = horizontalOffset(state.Position, destination).Magnitude
				local verticalDistance = math.abs(targetRoot.Position.Y - state.Position.Y)
				local targetReachable = verticalDistance <= state.MaxChaseVerticalDifference
					and targetHasLineOfSight(state, targetRoot)
					and not pathIsBlocked(
						state,
						destination,
						math.min(horizontalDistance, state.ObstacleLookAhead)
					)

				if not targetReachable then
					cancelAttack(state)
					state.TargetHumanoid = nil
					state.TargetRoot = nil
					if (state.Position - state.Home).Magnitude > HOME_SNAP_DISTANCE then
						returnHomeSafely(state, step)
					end
				elseif horizontalDistance <= state.AttackRange then
					faceHorizontal(state, destination)
					beginAttack(state)
				else
					local moved, blockedReason = moveModelTowards(
						state,
						destination,
						state.OriginalWalkSpeed,
						step,
						state.AttackRange * 0.82
					)
					if moved <= 0 and blockedReason then
						cancelAttack(state)
						state.TargetHumanoid = nil
						state.TargetRoot = nil
					end
				end
			else
				returnHomeSafely(state, step)
			end
		end
	end)
end

function MimicAI.Activate(model, options)
	options = options or {}
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = getRoot(model)
	if not humanoid or not root or not root:IsA("BasePart") then
		return false, "MimicChest precisa de Humanoid e pelo menos um MeshPart/BasePart"
	end
	local animationTrack, animationReason = loadLoopTrack(model, humanoid)
	if not animationTrack then
		return false, animationReason
	end
	removeLegacyMovementRoot(model)
	claimServerNetworkOwnership(model)
	-- A IA usa PivotTo e, portanto, e cinemática. Manter o unico MeshPart
	-- ancorado evita que colisoes acumulem impulso e lancem o Mimico da ilha.
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	model.PrimaryPart = root
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("MonsterId", "MimicChest")
	model:SetAttribute("DisplayName", "Bau Mimico")
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("AIController", "Mimic")
	local island = model:FindFirstAncestorWhichIsA("Model")
	while island and island:GetAttribute("IsSkyIsland") ~= true do
		island = island:FindFirstAncestorWhichIsA("Model")
	end
	local islandKey = island and island:GetAttribute("IslandNodeKey") or nil
	model:SetAttribute("SimulationActive", not island or island:GetAttribute("SimulationActive") ~= false)
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("IsMimic", true)
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

	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Position = root.Position,
		Home = root.Position,
		HomePivot = homePivot,
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
		OriginalWalkSpeed = humanoid.WalkSpeed,
		ReturnWalkSpeed = tonumber(model:GetAttribute("ReturnWalkSpeed")) or math.max(10, humanoid.WalkSpeed),
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
		MaxChaseVerticalDifference = tonumber(model:GetAttribute("MaxChaseVerticalDifference")) or 3.5,
		ObstacleLookAhead = tonumber(model:GetAttribute("ObstacleLookAhead")) or 4,
		ObstaclePadding = tonumber(model:GetAttribute("ObstaclePadding")) or 0.75,
		GroundProbeHeight = tonumber(model:GetAttribute("GroundProbeHeight"))
			or math.max(4, root.Size.Y + 1),
		GroundProbeDepth = tonumber(model:GetAttribute("GroundProbeDepth")) or 10,
		BlockedRecoveryDelay = tonumber(model:GetAttribute("BlockedRecoveryDelay")) or 0.75,
		NavigationBlockedSince = nil,
		NextAttackAt = os.clock() + 0.75,
		AttackSerial = 0,
		AttackPhase = nil,
		OnDormant = type(options.OnDormant) == "function" and options.OnDormant or nil,
		OnAwake = type(options.OnAwake) == "function" and options.OnAwake or nil,
		DormantDisguise = nil,
		AnimationTrack = animationTrack,
		RestartingAnimation = false,
	}
	states[model] = state
	model:SetAttribute("MimicState", STATE_AWAKE)
	model:SetAttribute("MimicAwake", true)
	model:SetAttribute("MimicAttacking", false)
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
	model:GetAttributeChangedSignal("CombatStunned"):Connect(function()
		if states[model] and model:GetAttribute("CombatStunned") == true then
			cancelAttack(state)
		end
	end)
	synchronizeAnimation(state)
	connectHeartbeat()

	humanoid.Died:Connect(function()
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
		local damager = getDamager(model, humanoid)
		if damager then
			local deathPosition = model:GetPivot().Position
			ScoreService.AwardRewards(
				damager,
				math.max(8, tonumber(options.ScoreReward) or 15),
				math.max(1, tonumber(options.CoinReward) or 50),
				"MimicChest",
				deathPosition
			)
			if math.random() <= 0.15 then
				InventoryService.GrantItem(damager, "GreaterHealthPotion", 1)
			end
		end
		Debris:AddItem(model, 0.8)
	end)
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
	return true
end

return MimicAI