--[[
	SkyDungeon - SlimeController

	IA autoritativa dos slimes. Cada variante possui uma personalidade propria,
	mas todas compartilham navegacao segura, patrulha e recuperacao de travas.

	Estados replicados no atributo AIState ajudam a depurar o comportamento no
	Studio: Idle, Wander, Chase, Melee, Strafe, Retreat, Mortar, Flee e Teleport.
]]

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SlimeAnimator = require(script.Parent.SlimeAnimator)
local MobEventModifiers = require(script.Parent.MobEventModifiers)

local SlimeController = {}

local THINK_INTERVAL = 0.12
local DORMANT_THINK_INTERVAL = 0.6
local PATH_RECOMPUTE_INTERVAL = 0.75
local WAYPOINT_REACHED_DISTANCE = 2.6
local DESTINATION_CHANGED_DISTANCE = 3
local GROUND_CHECK_HEIGHT = 8
local GROUND_CHECK_DEPTH = 22
local DIRECT_PATH_SAMPLE_SPACING = 3.5
local MAX_VALIDATED_PATH_POINTS = 36
local STUCK_CHECK_INTERVAL = 1.1
local STUCK_MINIMUM_PROGRESS = 0.55
local WANDER_MIN_DISTANCE = 6
local WANDER_MAX_DISTANCE = 30
local MELEE_HEIGHT_TOLERANCE = 7
local PROJECTILE_SIZE = 1.1

local active = {}
local islandCells = setmetatable({}, { __mode = "k" })

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function getLivingCharacter(player)
	if not player or player.Parent ~= Players then
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

local function playerFromDescendant(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				return player
			end
		end
		current = current.Parent
	end
	return nil
end

local function horizontalDistance(left, right)
	local dx = left.X - right.X
	local dz = left.Z - right.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function isAlive(state)
	return active[state.Model] == state
		and state.Model.Parent ~= nil
		and state.Root.Parent ~= nil
		and state.Humanoid.Health > 0
end

local function setAIState(state, name)
	if state.AIState == name then
		return
	end
	state.AIState = name
	state.Model:SetAttribute("AIState", name)
end

local function nearestPlayer(position, maximumDistance)
	local closestPlayer = nil
	local closestRoot = nil
	local closestDistance = maximumDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root = getLivingCharacter(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance <= closestDistance then
				closestPlayer = player
				closestRoot = root
				closestDistance = distance
			end
		end
	end
	return closestPlayer, closestRoot, closestDistance
end

local function copyValidCells(cells)
	local result = {}
	for _, record in ipairs(cells or {}) do
		if typeof(record) == "table" and typeof(record.SurfacePosition) == "Vector3" then
			table.insert(result, record.SurfacePosition)
		end
	end
	return result
end

local function getIslandPositions(state)
	return islandCells[state.Island] or {}
end

local function groundAt(state, position, extraExclusions)
	if not state.Island or not state.Island.Parent then
		return nil
	end
	local exclusions = { state.Model }
	for _, folderName in ipairs({ "MVPMonsters", "MVPBoss", "RuntimeSlimes" }) do
		local runtimeFolder = state.Island:FindFirstChild(folderName)
		if runtimeFolder then
			table.insert(exclusions, runtimeFolder)
		end
	end
	for _, instance in ipairs(extraExclusions or {}) do
		table.insert(exclusions, instance)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	local origin = position + Vector3.new(0, GROUND_CHECK_HEIGHT, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -GROUND_CHECK_DEPTH, 0), params)
	if
		result
		and result.Instance:IsA("BasePart")
		and result.Instance.CanCollide
		and result.Instance:IsDescendantOf(state.Island)
		and result.Normal.Y >= 0.55
	then
		return result.Position
	end
	return nil
end

local function isDirectPathSafe(state, destination)
	local offset = destination - state.Root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontal.Magnitude
	if distance < 0.1 then
		return true
	end
	local samples = math.max(1, math.ceil(distance / DIRECT_PATH_SAMPLE_SPACING))
	for index = 1, samples do
		local alpha = index / samples
		local sample = state.Root.Position:Lerp(destination, alpha)
		if not groundAt(state, sample) then
			return false
		end
	end
	return true
end

local function chooseWanderCell(state)
	local positions = getIslandPositions(state)
	if #positions == 0 then
		return state.Model:GetAttribute("SpawnSurfacePosition")
	end

	local best = nil
	local bestScore = -math.huge
	local attempts = math.min(18, #positions)
	for _ = 1, attempts do
		local candidate = positions[state.Random:NextInteger(1, #positions)]
		local distance = horizontalDistance(state.Root.Position, candidate)
		if distance >= WANDER_MIN_DISTANCE then
			local rangePenalty = math.max(0, distance - WANDER_MAX_DISTANCE) * 2
			local score = distance - rangePenalty + state.Random:NextNumber(0, 5)
			if score > bestScore then
				best = candidate
				bestScore = score
			end
		end
	end
	return best or positions[state.Random:NextInteger(1, #positions)]
end

local function chooseCellNearPosition(state, desiredPosition)
	local positions = getIslandPositions(state)
	local closest = nil
	local closestScore = math.huge
	for _, candidate in ipairs(positions) do
		local score = horizontalDistance(candidate, desiredPosition)
			+ horizontalDistance(candidate, state.Root.Position) * 0.08
		if score < closestScore then
			closest = candidate
			closestScore = score
		end
	end
	return closest or state.Model:GetAttribute("SpawnSurfacePosition")
end

local function chooseRingCell(state, targetPosition, preferredDistance, favorFarther)
	local positions = getIslandPositions(state)
	local best = nil
	local bestScore = math.huge
	for _, candidate in ipairs(positions) do
		local targetDistance = horizontalDistance(candidate, targetPosition)
		local ringError = math.abs(targetDistance - preferredDistance)
		local travelCost = horizontalDistance(candidate, state.Root.Position) * 0.1
		local score = ringError + travelCost
		if favorFarther then
			score -= targetDistance * 0.12
		end
		if score < bestScore then
			best = candidate
			bestScore = score
		end
	end
	return best or chooseWanderCell(state)
end

local function chooseFleeCell(state, threatPosition)
	local positions = getIslandPositions(state)
	local best = nil
	local bestScore = -math.huge
	for _, candidate in ipairs(positions) do
		local distanceFromThreat = horizontalDistance(candidate, threatPosition)
		local travelDistance = horizontalDistance(candidate, state.Root.Position)
		local score = distanceFromThreat - travelDistance * 0.18 + state.Random:NextNumber(0, 1.5)
		if score > bestScore then
			best = candidate
			bestScore = score
		end
	end
	return best or chooseWanderCell(state)
end

local function facePosition(state, targetPosition)
	if not state.Root.Parent or state.Root.Anchored then
		return
	end
	local flatTarget = Vector3.new(targetPosition.X, state.Root.Position.Y, targetPosition.Z)
	if (flatTarget - state.Root.Position).Magnitude < 0.05 then
		return
	end
	state.Root.CFrame = CFrame.lookAt(state.Root.Position, flatTarget)
	state.Root.AssemblyAngularVelocity = Vector3.zero
end

local function clearMovement(state)
	state.Destination = nil
	state.PathPoints = nil
	state.PathIndex = 1
	state.NextRepathAt = 0
	state.Moving = false
	state.Model:SetAttribute("IsMoving", false)
end

local function stopMoving(state, nextState)
	if state.Moving and state.Humanoid.Parent and state.Root.Parent then
		state.Humanoid:MoveTo(state.Root.Position)
		state.Humanoid:Move(Vector3.zero)
	end
	clearMovement(state)
	if nextState then
		setAIState(state, nextState)
	end
end

local function setMovementSpeed(state, multiplier)
	if state.Model:GetAttribute("CombatStunned") == true then
		return
	end
	local desired = math.clamp(state.BaseWalkSpeed * (multiplier or 1), 3, 26)
	if math.abs(state.Humanoid.WalkSpeed - desired) > 0.05 then
		state.Humanoid.WalkSpeed = desired
	end
	state.Model:SetAttribute("MoveSpeedScale", multiplier or 1)
end

local function buildSafePath(state, destination)
	local safeDestination = groundAt(state, destination)
	if not safeDestination then
		return nil
	end

	local agentRadius = math.clamp(math.max(state.Root.Size.X, state.Root.Size.Z) * 0.42, 1, 4)
	local agentHeight = math.clamp(state.Root.Size.Y + state.Humanoid.HipHeight + 1, 3, 10)
	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	})
	local success = pcall(function()
		path:ComputeAsync(state.Root.Position, safeDestination)
	end)
	if success and path.Status == Enum.PathStatus.Success then
		local points = {}
		local waypoints = path:GetWaypoints()
		for index, waypoint in ipairs(waypoints) do
			if index > MAX_VALIDATED_PATH_POINTS then
				break
			end
			if not groundAt(state, waypoint.Position) then
				points = {}
				break
			end
			table.insert(points, waypoint.Position)
		end
		if #points > 0 then
			return points
		end
	end

	if isDirectPathSafe(state, safeDestination) then
		return { safeDestination }
	end
	return nil
end

local function movementIsStuck(state, now)
	if not state.Moving then
		return false
	end
	if now - state.LastProgressCheckAt < STUCK_CHECK_INTERVAL then
		return false
	end
	local progress = horizontalDistance(state.Root.Position, state.LastProgressPosition)
	state.LastProgressPosition = state.Root.Position
	state.LastProgressCheckAt = now
	if progress >= STUCK_MINIMUM_PROGRESS then
		state.StuckCount = 0
		return false
	end
	state.StuckCount += 1
	return true
end

local function requestMove(state, destination, speedMultiplier, mode, repathInterval)
	if not destination or state.Model:GetAttribute("CombatStunned") == true then
		return false, false
	end
	local now = serverTime()
	local changed = not state.Destination
		or horizontalDistance(state.Destination, destination) >= DESTINATION_CHANGED_DISTANCE
	local stuck = movementIsStuck(state, now)
	if changed or stuck or now >= state.NextRepathAt or not state.PathPoints then
		state.Destination = destination
		state.NextRepathAt = now + (repathInterval or math.huge)
		state.PathPoints = buildSafePath(state, destination)
		state.PathIndex = 1
		if not state.PathPoints then
			clearMovement(state)
			return false, false
		end
	end

	while state.PathPoints and state.PathIndex <= #state.PathPoints do
		local point = state.PathPoints[state.PathIndex]
		if horizontalDistance(state.Root.Position, point) > WAYPOINT_REACHED_DISTANCE then
			break
		end
		state.PathIndex += 1
	end
	if not state.PathPoints or state.PathIndex > #state.PathPoints then
		stopMoving(state, mode)
		return true, true
	end

	setMovementSpeed(state, speedMultiplier)
	setAIState(state, mode)
	state.Moving = true
	state.Model:SetAttribute("IsMoving", true)
	state.Humanoid.AutoRotate = true
	state.Humanoid:MoveTo(state.PathPoints[state.PathIndex])
	return true, false
end

local function randomPause(state)
	local minimum = state.Definition.WanderPauseMin or 0.8
	local maximum = math.max(minimum, state.Definition.WanderPauseMax or 2.2)
	return state.Random:NextNumber(minimum, maximum)
end

local function thinkWander(state, now)
	-- Protecao defensiva para estados criados por versoes antigas do controlador.
	-- O loop principal sempre envia o relogio atual, mas uma chamada externa nunca
	-- deve conseguir interromper toda a IA por comparar nil com numero.
	now = tonumber(now) or serverTime()
	state.IdleUntil = tonumber(state.IdleUntil) or now
	if now < state.IdleUntil then
		stopMoving(state, "Idle")
		return
	end
	if not state.WanderDestination then
		state.WanderDestination = chooseWanderCell(state)
		if not state.WanderDestination then
			state.IdleUntil = now + randomPause(state)
			return
		end
	end

	local moved, arrived = requestMove(
		state,
		state.WanderDestination,
		state.Definition.PassiveSpeedMultiplier or 0.6,
		"Wander",
		math.huge
	)
	if arrived or not moved then
		state.WanderDestination = nil
		state.IdleUntil = now + randomPause(state)
		if not moved then
			state.IdleUntil = now + 0.35
		end
	end
end

local function createBurst(position, color, size)
	local burst = Instance.new("Part")
	burst.Name = "SlimeImpact"
	burst.Shape = Enum.PartType.Ball
	burst.Size = Vector3.new(size, size, size)
	burst.Position = position
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = color
	burst.Transparency = 0.2
	burst.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.18, 0.4)
	emitter.Speed = NumberRange.new(5, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = burst
	emitter:Emit(18)
	Debris:AddItem(burst, 0.45)
end

local function findGround(position, exclusions)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	local result = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -90, 0), params)
	return result and result.Position or nil
end

local function damagePlayersInRadius(position, radius, damage)
	for _, player in ipairs(Players:GetPlayers()) do
		local _, humanoid, root = getLivingCharacter(player)
		if
			humanoid
			and horizontalDistance(root.Position, position) <= radius
			and math.abs(root.Position.Y - position.Y) <= 10
		then
			humanoid:TakeDamage(damage)
		end
	end
end

local function mortarAttack(state, targetCharacter, targetRoot)
	local definition = state.Definition
	local velocity = targetRoot.AssemblyLinearVelocity
	local prediction = Vector3.new(velocity.X, 0, velocity.Z)
		* math.min(0.45, definition.MortarWarningTime * 0.3)
	local impactPosition = findGround(targetRoot.Position + prediction, { state.Model, targetCharacter })
	if not impactPosition then
		return false
	end

	stopMoving(state, "Mortar")
	facePosition(state, impactPosition)
	state.Busy = true
	state.NextAttackAt = serverTime() + definition.AttackCooldown

	local marker = Instance.new("Part")
	marker.Name = "SlimeMortarWarning"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.12, definition.ImpactRadius * 2, definition.ImpactRadius * 2)
	marker.CFrame = CFrame.new(impactPosition + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 30, 30)
	marker.Transparency = 0.62
	marker.Parent = workspace

	local projectile = Instance.new("Part")
	projectile.Name = "RedSlimeMortar"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.45, 1.45, 1.45)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(255, 65, 45)
	projectile.Position = state.Root.Position + Vector3.new(0, 2, 0)
	projectile.Parent = workspace

	local startPosition = projectile.Position
	local controlPosition = (startPosition + impactPosition) / 2
		+ Vector3.new(0, definition.MortarArcHeight, 0)
	local startedAt = serverTime()

	task.spawn(function()
		while isAlive(state) do
			local alpha = math.clamp((serverTime() - startedAt) / definition.MortarWarningTime, 0, 1)
			local inverse = 1 - alpha
			projectile.Position = inverse * inverse * startPosition
				+ 2 * inverse * alpha * controlPosition
				+ alpha * alpha * impactPosition
			marker.Transparency = 0.62 - alpha * 0.38
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end

		if not isAlive(state) then
			projectile:Destroy()
			marker:Destroy()
			return
		end
		damagePlayersInRadius(impactPosition, definition.ImpactRadius, definition.AttackDamage)
		createBurst(impactPosition + Vector3.new(0, 0.5, 0), Color3.fromRGB(255, 55, 45), 2.2)
		projectile:Destroy()
		marker:Destroy()
		state.Busy = false
		state.IdleUntil = serverTime() + 0.2
	end)
	return true
end

local function straightProjectileAttack(state, targetRoot)
	local definition = state.Definition
	local origin = state.Root.Position + Vector3.new(0, math.max(1, state.Root.Size.Y * 0.35), 0)
	local targetPosition = targetRoot.Position + Vector3.new(0, 0.5, 0)
	local offset = targetPosition - origin
	if offset.Magnitude < 0.1 then
		return false
	end

	state.NextAttackAt = serverTime() + definition.AttackCooldown
	local direction = offset.Unit
	local projectile = Instance.new("Part")
	projectile.Name = "BlueSlimeProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(PROJECTILE_SIZE, PROJECTILE_SIZE, PROJECTILE_SIZE)
	projectile.Position = origin
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(65, 165, 255)
	projectile.Parent = workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.Model }
	params.IgnoreWater = true
	local travelled = 0
	local maximumDistance = definition.AttackRange + 8

	task.spawn(function()
		while isAlive(state) and travelled < maximumDistance do
			local deltaTime = RunService.Heartbeat:Wait()
			local step = math.min(definition.ProjectileSpeed * deltaTime, maximumDistance - travelled)
			local result = workspace:Raycast(projectile.Position, direction * step, params)
			if result then
				projectile.Position = result.Position
				local hitPlayer = playerFromDescendant(result.Instance)
				local _, hitHumanoid = getLivingCharacter(hitPlayer)
				if hitHumanoid then
					hitHumanoid:TakeDamage(definition.AttackDamage)
				end
				createBurst(result.Position, definition.Color, 1.2)
				projectile:Destroy()
				return
			end
			projectile.Position += direction * step
			travelled += step
		end
		if projectile.Parent then
			projectile:Destroy()
		end
	end)
	return true
end

local function setAggro(state, player)
	state.AggroPlayer = player
	if player == nil then
		state.AggroFromWorldEvent = false
	end
	state.LastTargetSeenAt = serverTime()
	state.Model:SetAttribute("AggroUserId", player and player.UserId or nil)
	state.Model:SetAttribute("Peaceful", player == nil and state.BasePeaceful or false)
	state.WanderDestination = nil
	state.CombatDestination = nil
	clearMovement(state)
	if player == nil then
		state.Model:SetAttribute("LastDamagedByUserId", nil)
		state.Model:SetAttribute("LastHitUserId", nil)
	end
end

local function updateNeutralAggro(state)
	if state.AggroPlayer then
		if state.AggroFromWorldEvent and not MobEventModifiers.IsForcedAggressive(state.Model) then
			local lastAttacker = state.Model:GetAttribute("LastDamagedByUserId")
				or state.Model:GetAttribute("LastHitUserId")
			if lastAttacker == state.AggroPlayer.UserId then
				state.AggroFromWorldEvent = false
			else
				setAggro(state, nil)
			end
		end
		return
	end
	local forcedAggressive = MobEventModifiers.IsForcedAggressive(state.Model)
	if forcedAggressive or not state.BasePeaceful then
		local aggroRange = MobEventModifiers.GetAggroRange(state.Model, state.Definition.AggroRange or 55)
		local player = nearestPlayer(state.Root.Position, aggroRange)
		if player then
			setAggro(state, player)
			state.AggroFromWorldEvent = forcedAggressive and state.BasePeaceful
			return
		end
	end
	local userId = state.Model:GetAttribute("LastDamagedByUserId")
	if typeof(userId) ~= "number" then
		userId = state.Model:GetAttribute("LastHitUserId")
	end
	if typeof(userId) == "number" then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			setAggro(state, player)
		end
	end
end

local function targetWasLost(state, now, player, targetRoot)
	if targetRoot then
		return false
	end
	if player and now - state.LastTargetSeenAt >= state.Definition.CalmAfter then
		setAggro(state, nil)
	end
	return true
end

local function beginMeleeAttack(state, targetHumanoid, targetRoot)
	if state.Busy or state.Model:GetAttribute("CombatStunned") == true then
		return
	end
	stopMoving(state, "Melee")
	facePosition(state, targetRoot.Position)
	state.Busy = true
	local interruptSerial = state.Model:GetAttribute("CombatInterruptSerial") or 0
	state.NextAttackAt = serverTime() + state.Definition.AttackCooldown
	task.delay(0.2, function()
		if isAlive(state)
			and (state.Model:GetAttribute("CombatInterruptSerial") or 0) == interruptSerial
			and state.Model:GetAttribute("CombatStunned") ~= true
			and targetHumanoid.Parent
			and targetHumanoid.Health > 0
			and targetRoot.Parent
		then
			local closeEnough = horizontalDistance(state.Root.Position, targetRoot.Position)
				<= state.Definition.AttackRange + 1.3
			if closeEnough and math.abs(state.Root.Position.Y - targetRoot.Position.Y) <= MELEE_HEIGHT_TOLERANCE then
				targetHumanoid:TakeDamage(state.Definition.AttackDamage)
				createBurst(targetRoot.Position, state.Definition.Color, 0.75)
			end
		end
		state.Busy = false
	end)
end

local function thinkGreen(state, now)
	updateNeutralAggro(state)
	local player = state.AggroPlayer
	if not player then
		thinkWander(state, now)
		return
	end
	local _, targetHumanoid, targetRoot = getLivingCharacter(player)
	if targetWasLost(state, now, player, targetRoot) then
		return
	end

	local distance = horizontalDistance(state.Root.Position, targetRoot.Position)
	local aggroRange = MobEventModifiers.GetAggroRange(state.Model, state.Definition.AggroRange)
	if distance > aggroRange then
		if now - state.LastTargetSeenAt >= state.Definition.CalmAfter then
			setAggro(state, nil)
		end
		return
	end
	state.LastTargetSeenAt = now
	if state.Busy then
		return
	end
	if distance <= state.Definition.AttackRange
		and math.abs(state.Root.Position.Y - targetRoot.Position.Y) <= MELEE_HEIGHT_TOLERANCE
	then
		if now >= state.NextAttackAt then
			beginMeleeAttack(state, targetHumanoid, targetRoot)
		else
			stopMoving(state, "Chase")
		end
		return
	end

	local destination = chooseCellNearPosition(state, targetRoot.Position)
	requestMove(
		state,
		destination,
		state.Definition.CombatSpeedMultiplier or 1,
		"Chase",
		PATH_RECOMPUTE_INTERVAL
	)
end

local function beginBlueAttack(state, targetRoot)
	if state.Busy or state.Model:GetAttribute("CombatStunned") == true then
		return
	end
	stopMoving(state, "RangedAttack")
	facePosition(state, targetRoot.Position)
	state.Busy = true
	local interruptSerial = state.Model:GetAttribute("CombatInterruptSerial") or 0
	task.delay(0.16, function()
		if isAlive(state)
			and (state.Model:GetAttribute("CombatInterruptSerial") or 0) == interruptSerial
			and state.Model:GetAttribute("CombatStunned") ~= true
			and targetRoot.Parent
		then
			straightProjectileAttack(state, targetRoot)
		end
		state.Busy = false
		state.NextRepositionAt = serverTime() + 0.25
	end)
end

local function updateRangedMovement(state, now, targetRoot, modePrefix)
	local definition = state.Definition
	local distance = horizontalDistance(state.Root.Position, targetRoot.Position)
	local preferred = definition.PreferredDistance or 28
	local retreat = definition.RetreatDistance or 16
	local destination = state.CombatDestination
	local mode = modePrefix or "Strafe"

	if distance < retreat then
		destination = chooseRingCell(state, targetRoot.Position, preferred + 5, true)
		mode = "Retreat"
		state.NextRepositionAt = now + 1
	elseif distance > preferred + 10 then
		destination = chooseRingCell(state, targetRoot.Position, preferred, false)
		mode = "Approach"
		state.NextRepositionAt = now + 1
	elseif not destination or now >= state.NextRepositionAt then
		destination = chooseRingCell(
			state,
			targetRoot.Position,
			preferred + state.Random:NextNumber(-4, 4),
			false
		)
		mode = modePrefix or "Strafe"
		state.NextRepositionAt = now + (definition.RepositionInterval or 2.2)
	end
	state.CombatDestination = destination
	if destination then
		local moved, arrived = requestMove(
			state,
			destination,
			definition.CombatSpeedMultiplier or 0.8,
			mode,
			1.1
		)
		if arrived or not moved then
			state.CombatDestination = nil
		end
	end
end

local function thinkBlue(state, now)
	updateNeutralAggro(state)
	local player = state.AggroPlayer
	if not player then
		thinkWander(state, now)
		return
	end
	local _, _, targetRoot = getLivingCharacter(player)
	if targetWasLost(state, now, player, targetRoot) then
		return
	end

	local distance = (targetRoot.Position - state.Root.Position).Magnitude
	local aggroRange = MobEventModifiers.GetAggroRange(state.Model, state.Definition.AggroRange)
	if distance > aggroRange then
		if now - state.LastTargetSeenAt >= state.Definition.CalmAfter then
			setAggro(state, nil)
		end
		return
	end
	state.LastTargetSeenAt = now
	if state.Busy then
		return
	end
	if distance <= state.Definition.AttackRange and now >= state.NextAttackAt then
		beginBlueAttack(state, targetRoot)
		return
	end
	updateRangedMovement(state, now, targetRoot, "Strafe")
end

local function thinkRed(state, now)
	local definition = state.Definition
	local detectionRange = MobEventModifiers.GetAggroRange(
		state.Model,
		definition.DetectionRange or definition.AttackRange
	)
	local player, targetRoot = nearestPlayer(state.Root.Position, detectionRange)
	if not targetRoot then
		state.CombatDestination = nil
		thinkWander(state, now)
		return
	end
	if state.Busy then
		return
	end

	local distance = (targetRoot.Position - state.Root.Position).Magnitude
	if distance <= definition.AttackRange and now >= state.NextAttackAt then
		if mortarAttack(state, player.Character, targetRoot) then
			return
		end
	end
	updateRangedMovement(state, now, targetRoot, "Hunt")
end

local function getRuntimeMonsterFolder(island)
	local folder = island:FindFirstChild("MVPMonsters")
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		local fallback = island:FindFirstChild("RuntimeSlimes")
		if fallback and fallback:IsA("Folder") then
			return fallback
		end
		folder = Instance.new("Folder")
		folder.Name = "RuntimeSlimes"
		folder.Parent = island
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "MVPMonsters"
	folder.Parent = island
	return folder
end

local function chooseTeleportDestination(state)
	local candidates = {}
	for island, positions in pairs(islandCells) do
		if island.Parent and island ~= state.Island and #positions > 0 then
			table.insert(candidates, { Island = island, Positions = positions })
		end
	end
	if #candidates == 0 then
		for island, positions in pairs(islandCells) do
			if island.Parent and #positions > 0 then
				table.insert(candidates, { Island = island, Positions = positions })
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local destination = candidates[state.Random:NextInteger(1, #candidates)]
	return destination.Island, destination.Positions[state.Random:NextInteger(1, #destination.Positions)]
end

local function pivotBottomTo(model, surfacePosition)
	local pivot = model:GetPivot()
	local box, size = model:GetBoundingBox()
	local bottomY = box.Position.Y - size.Y / 2
	local offset = Vector3.new(
		surfacePosition.X - pivot.Position.X,
		surfacePosition.Y + 0.15 - bottomY,
		surfacePosition.Z - pivot.Position.Z
	)
	model:PivotTo(pivot + offset)
end

local function goldenTeleport(state)
	local destinationIsland, destinationPosition = chooseTeleportDestination(state)
	if not destinationIsland then
		state.NextTeleportAt = serverTime() + 2
		return
	end

	stopMoving(state, "Teleport")
	state.Busy = true
	state.Model:SetAttribute("Teleporting", true)
	local inside = state.Model:FindFirstChild("SlimeInside", true)
	local light = inside and inside:FindFirstChild("GoldenSlimeLight")
	if light and light:IsA("PointLight") then
		light.Brightness = 4
	end

	task.delay(state.Definition.TeleportWarningTime, function()
		if not isAlive(state) then
			return
		end
		if not destinationIsland.Parent then
			state.Model:SetAttribute("Teleporting", nil)
			state.NextTeleportAt = serverTime() + 1
			state.Busy = false
			return
		end
		createBurst(state.Root.Position, state.Definition.Color, 1.6)
		state.Model.Parent = getRuntimeMonsterFolder(destinationIsland)
		pivotBottomTo(state.Model, destinationPosition)
		state.Root.AssemblyLinearVelocity = Vector3.zero
		state.Root.AssemblyAngularVelocity = Vector3.zero
		state.Island = destinationIsland
		state.Model:SetAttribute("CurrentIslandKey", destinationIsland:GetAttribute("IslandKey"))
		if state.Callbacks.OnTeleported then
			state.Callbacks.OnTeleported(destinationIsland)
		end
		createBurst(state.Root.Position, state.Definition.Color, 1.6)
		if light and light.Parent then
			light.Brightness = 1.8
		end
		state.Model:SetAttribute("Teleporting", nil)
		state.NextTeleportAt = serverTime() + state.Definition.TeleportInterval
		state.Model:SetAttribute("NextTeleportAt", state.NextTeleportAt)
		state.WanderDestination = nil
		state.CombatDestination = nil
		state.IdleUntil = serverTime() + 0.15
		state.Busy = false
	end)
end

local function thinkGoldenFury(state, now)
	local baseAggroRange = tonumber(state.Model:GetAttribute("AggroRange")) or 45
	local aggroRange = MobEventModifiers.GetAggroRange(state.Model, baseAggroRange)
	local player, targetRoot = nearestPlayer(state.Root.Position, aggroRange)
	local _, targetHumanoid = getLivingCharacter(player)
	if not targetRoot or not targetHumanoid then
		state.CombatDestination = nil
		return false
	end

	local attackRange = tonumber(state.Model:GetAttribute("AttackRange")) or 5
	local distance = horizontalDistance(state.Root.Position, targetRoot.Position)
	if distance <= attackRange
		and math.abs(state.Root.Position.Y - targetRoot.Position.Y) <= MELEE_HEIGHT_TOLERANCE
	then
		stopMoving(state, "Melee")
		if now >= state.NextAttackAt and not state.Busy then
			facePosition(state, targetRoot.Position)
			state.Busy = true
			local interruptSerial = state.Model:GetAttribute("CombatInterruptSerial") or 0
			state.NextAttackAt = now + (tonumber(state.Model:GetAttribute("AttackCooldown")) or 1.4)
			task.delay(0.2, function()
				if isAlive(state)
					and (state.Model:GetAttribute("CombatInterruptSerial") or 0) == interruptSerial
					and state.Model:GetAttribute("CombatStunned") ~= true
					and targetHumanoid.Parent
					and targetHumanoid.Health > 0
					and targetRoot.Parent
				then
					local stillClose = horizontalDistance(state.Root.Position, targetRoot.Position) <= attackRange + 1.3
					if stillClose and math.abs(state.Root.Position.Y - targetRoot.Position.Y) <= MELEE_HEIGHT_TOLERANCE then
						targetHumanoid:TakeDamage(math.max(1, tonumber(state.Model:GetAttribute("AttackDamage")) or 8))
						createBurst(targetRoot.Position, state.Definition.Color, 0.75)
					end
				end
				state.Busy = false
			end)
		end
		return true
	end

	local destination = chooseCellNearPosition(state, targetRoot.Position)
	requestMove(state, destination, 1, "Chase", PATH_RECOMPUTE_INTERVAL)
	return true
end

local function thinkGolden(state, now)
	if now >= state.ExpiresAt then
		state.Model:SetAttribute("ExpiredWithoutReward", true)
		createBurst(state.Root.Position, state.Definition.Color, 2)
		state.Callbacks.OnExpired()
		return
	end
	if state.Busy then
		return
	end
	if MobEventModifiers.IsForcedAggressive(state.Model) and thinkGoldenFury(state, now) then
		return
	end
	if now >= state.NextTeleportAt then
		goldenTeleport(state)
		return
	end

	local _, threatRoot = nearestPlayer(state.Root.Position, state.Definition.FleeDistance or 28)
	if threatRoot then
		if not state.CombatDestination or now >= state.NextRepositionAt then
			state.CombatDestination = chooseFleeCell(state, threatRoot.Position)
			state.NextRepositionAt = now + 1.1
		end
		local moved, arrived = requestMove(
			state,
			state.CombatDestination,
			state.Definition.PassiveSpeedMultiplier or 0.9,
			"Flee",
			0.9
		)
		if arrived or not moved then
			state.CombatDestination = nil
		end
		return
	end
	state.CombatDestination = nil
	thinkWander(state, now)
end

function SlimeController.RegisterIsland(island, freeCells)
	if island and island:IsA("Model") then
		islandCells[island] = copyValidCells(freeCells)
	end
end

function SlimeController.Start(entry, definition, random, callbacks)
	assert(entry and entry.Model and entry.Root and entry.Humanoid, "Entrada de slime invalida")
	assert(definition and definition.Behavior, "Definicao de slime invalida")

	local now = serverTime()
	local state = {
		Model = entry.Model,
		Root = entry.Root,
		Humanoid = entry.Humanoid,
		Island = entry.Island,
		Definition = definition,
		Random = Random.new(random:NextInteger(1, 2147483646)),
		Callbacks = callbacks,
		BaseWalkSpeed = math.max(4, entry.Humanoid.WalkSpeed),
		BasePeaceful = entry.Model:GetAttribute("Peaceful") == true,
		AggroPlayer = nil,
		AggroFromWorldEvent = false,
		LastTargetSeenAt = now,
		NextAttackAt = now + 0.75,
		NextTeleportAt = definition.TeleportInterval and (now + definition.TeleportInterval) or math.huge,
		ExpiresAt = definition.Lifetime and (now + definition.Lifetime) or math.huge,
		NextRepositionAt = now,
		IdleUntil = now + random:NextNumber(0.1, 0.8),
		WanderDestination = nil,
		CombatDestination = nil,
		Destination = nil,
		PathPoints = nil,
		PathIndex = 1,
		NextRepathAt = 0,
		LastProgressCheckAt = now,
		LastProgressPosition = entry.Root.Position,
		StuckCount = 0,
		Moving = false,
		Busy = false,
		AIState = nil,
	}
	active[entry.Model] = state
	state.Humanoid.AutoRotate = true
	setAIState(state, "Idle")
	entry.Model:SetAttribute("IsMoving", false)
	SlimeAnimator.Start(entry.Model, entry.Humanoid)

	if definition.Behavior == "GoldenEscape" then
		entry.Model:SetAttribute("ExpiresAt", state.ExpiresAt)
		entry.Model:SetAttribute("NextTeleportAt", state.NextTeleportAt)
	end

	task.spawn(function()
		while isAlive(state) do
			local waitInterval = THINK_INTERVAL
			local currentTime = serverTime()
			if state.Model:GetAttribute("SimulationActive") == false then
				stopMoving(state, "Dormant")
				waitInterval = DORMANT_THINK_INTERVAL
			elseif state.Model:GetAttribute("CombatStunned") == true then
				setAIState(state, "Stunned")
			elseif definition.Behavior == "NeutralMelee" then
				thinkGreen(state, currentTime)
			elseif definition.Behavior == "NeutralRanged" then
				thinkBlue(state, currentTime)
			elseif definition.Behavior == "HostileMortar" then
				thinkRed(state, currentTime)
			elseif definition.Behavior == "GoldenEscape" then
				thinkGolden(state, currentTime)
			end
			task.wait(waitInterval)
		end
	end)
	return state
end

function SlimeController.Stop(model)
	local state = active[model]
	if not state then
		return
	end
	active[model] = nil
	SlimeAnimator.Stop(model)
	stopMoving(state)
end

return table.freeze(SlimeController)
