-- Controlador generico autoritativo. Mobs comuns usam este controlador por
-- padrao; somente UseCustomAI=true ou AIController diferente de Generic desliga.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MobEventModifiers = require(script.Parent.BlockParkour:WaitForChild("MobEventModifiers"))
local PlayerDamageService = require(script.Parent.MVPSystems:WaitForChild("PlayerDamageService"))
local MonsterSystem = script.Parent:WaitForChild("MonsterSystem")
local AbilityRegistry = require(MonsterSystem.AbilityRegistry)
local MonsterAnimationLoader = require(MonsterSystem.MonsterAnimationLoader)
local MonsterConfig = require(MonsterSystem.MonsterConfig)

local CLOSE_THINK_INTERVAL = 0.15
local MEDIUM_THINK_INTERVAL = 0.35
local FAR_THINK_INTERVAL = 0.75
local SLEEP_THINK_INTERVAL = 1.5
local CLOSE_PLAYER_DISTANCE = 80
local MEDIUM_PLAYER_DISTANCE = 150
local MAX_ACTIVE_PLAYER_DISTANCE = 240
local MAX_AI_DECISIONS_PER_HEARTBEAT = 8
local MAX_AI_SCANS_PER_HEARTBEAT = 32
local AI_TIME_BUDGET_SECONDS = 0.0018

local states = setmetatable({}, { __mode = "k" })
local scheduledStates = {}
local schedulerCursor = 1
local inactiveScheduleEntries = 0

local function livingCharacter(player)
	if
		not player
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("InvisibleToEnemies") == true
	then
		return nil
	end
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil
end

local function nearestPlayer(position, range)
	local selected
	local bestDistance = range
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root = livingCharacter(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance <= bestDistance then
				selected = player
				bestDistance = distance
			end
		end
	end
	return selected, bestDistance
end

local function distanceToNearestPlayer(position)
	local _, distance = nearestPlayer(position, math.huge)
	return distance
end

local function isGeneric(model)
	if model:GetAttribute("UseCustomAI") == true then
		return false
	end
	local controller = model:GetAttribute("AIController")
	return controller == nil or controller == "Generic"
end

local function setState(state, name)
	if state.State == name then
		return
	end
	state.State = name
	state.Model:SetAttribute("MonsterState", name)
	if name == "Chase" or name == "Return" or name == "Roam" then
		MonsterAnimationLoader.Play(state.Model, state.Humanoid, "Walk")
	elseif name ~= "Attack" and name ~= "Ability" then
		MonsterAnimationLoader.Play(state.Model, state.Humanoid, "Idle")
	end
end

local function unregister(state)
	if not state or not state.Scheduled then
		return
	end
	state.Scheduled = false
	inactiveScheduleEntries += 1
	states[state.Model] = nil
	state.Model:SetAttribute("AggroUserId", nil)
	state.Model:SetAttribute("TargetUserId", nil)
	MonsterAnimationLoader.Stop(state.Model)
end

local function register(model)
	if not model:IsA("Model") or states[model] or not isGeneric(model) then
		return
	end
	local humanoid = MonsterConfig.GetHumanoid(model)
	local root = MonsterConfig.GetRoot(model)
	if not humanoid or not root then
		return
	end
	MonsterConfig.ApplyRuntimeDefaults(model)
	model:SetAttribute("AIController", "Generic")
	model:SetAttribute("UseCentralAI", true)
	local home = model:GetAttribute("HomePosition")
	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Home = typeof(home) == "Vector3" and home or root.Position,
		Target = nil,
		State = nil,
		NextAttackAt = 0,
		NextJumpAt = 0,
		NextPathAt = 0,
		NextRoamAt = os.clock() + math.random(2, 5),
		AttackSerial = 0,
		ActionLockedUntil = 0,
		LastPosition = root.Position,
		LastThinkAt = os.clock(),
		StuckTime = 0,
		NextThinkAt = os.clock() + math.random() * CLOSE_THINK_INTERVAL,
		Scheduled = true,
		SchedulerTier = nil,
		SchedulerStopped = false,
		Random = Random.new(math.floor(math.abs(root.Position.X * 37 + root.Position.Z * 101)) + 1),
	}
	states[model] = state
	table.insert(scheduledStates, state)
	MonsterAnimationLoader.Bind(model, humanoid)
	setState(state, "Idle")
	humanoid.Died:Connect(function()
		state.AttackSerial += 1
		MonsterAnimationLoader.Play(model, humanoid, "Death", 0.05)
		task.delay(0.5, function()
			unregister(state)
		end)
	end)
	model.Destroying:Connect(function()
		unregister(state)
	end)
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function(model)
	task.defer(register, model)
end)
for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
	task.defer(register, model)
end

local function setSchedulerTier(state, tier)
	if state.SchedulerTier ~= tier then
		state.SchedulerTier = tier
		state.Model:SetAttribute("AIUpdateTier", tier)
	end
end

local function stopForScheduler(state, tier)
	setSchedulerTier(state, tier)
	if not state.SchedulerStopped then
		state.SchedulerStopped = true
		state.Humanoid:MoveTo(state.Root.Position)
		setState(state, "Idle")
	end
end

local function hasLineOfSight(state, targetCharacter, targetRoot)
	local direction = targetRoot.Position - state.Root.Position
	if direction.Magnitude < 0.1 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.Model }
	params.IgnoreWater = true
	local result = workspace:Raycast(state.Root.Position, direction, params)
	return not result or result.Instance:IsDescendantOf(targetCharacter)
end

local function selectTarget(state, config)
	if state.Target then
		local _, _, targetRoot = livingCharacter(state.Target)
		if targetRoot and (targetRoot.Position - state.Root.Position).Magnitude <= config.LoseTargetRange then
			state.Model:SetAttribute("AggroUserId", state.Target.UserId)
			state.Model:SetAttribute("TargetUserId", state.Target.UserId)
			return state.Target
		end
		state.Target = nil
	end

	local peaceful = config.Peaceful == true and not MobEventModifiers.IsForcedAggressive(state.Model)
	if peaceful and config.AggroOnDamage == true then
		local userId = state.Model:GetAttribute("LastDamagedByUserId")
		if typeof(userId) == "number" then
			local attacker = Players:GetPlayerByUserId(userId)
			local _, _, targetRoot = livingCharacter(attacker)
			if targetRoot and (targetRoot.Position - state.Root.Position).Magnitude <= config.LoseTargetRange then
				state.Target = attacker
			end
		end
	elseif not peaceful then
		local aggroRange = MobEventModifiers.GetAggroRange(state.Model, config.DetectionRange)
		state.Target = nearestPlayer(state.Root.Position, aggroRange)
	end
	local targetUserId = state.Target and state.Target.UserId or nil
	state.Model:SetAttribute("AggroUserId", targetUserId)
	state.Model:SetAttribute("TargetUserId", targetUserId)
	return state.Target
end

local function moveToward(state, destination, config, now)
	if config.CanMove ~= true then
		state.Humanoid:MoveTo(state.Root.Position)
		return
	end
	if not config.UsePathfinding or now < state.NextPathAt then
		state.Humanoid:MoveTo(destination)
		return
	end
	state.NextPathAt = now + config.PathRecomputeInterval
	local path = PathfindingService:CreatePath({
		AgentRadius = math.max(1, state.Root.Size.X * 0.45),
		AgentHeight = math.max(3, state.Model:GetExtentsSize().Y),
		AgentCanJump = true,
	})
	local ok = pcall(path.ComputeAsync, path, state.Root.Position, destination)
	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		local waypoint = waypoints[math.min(2, #waypoints)]
		if waypoint then
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				state.Humanoid.Jump = true
			end
			state.Humanoid:MoveTo(waypoint.Position)
			return
		end
	end
	state.Humanoid:MoveTo(destination)
end

local function targetInsideMeleeHitbox(state, targetCharacter, config)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.Model }
	params.MaxParts = 32
	local cframe = state.Root.CFrame * CFrame.new(config.AttackOffset)
	for _, part in ipairs(workspace:GetPartBoundsInBox(cframe, config.AttackHitboxSize, params)) do
		if part:IsDescendantOf(targetCharacter) then
			return true
		end
	end
	return false
end

local function beginAttack(state, config, targetPlayer, now)
	local targetCharacter, targetHumanoid, targetRoot = livingCharacter(targetPlayer)
	if not targetCharacter then
		return
	end
	state.AttackSerial += 1
	local serial = state.AttackSerial
	local interruptSerial = state.Model:GetAttribute("CombatInterruptSerial") or 0
	state.NextAttackAt = now + config.AttackCooldown + config.AttackWindup + config.AttackRecovery
	state.ActionLockedUntil = now + config.AttackWindup + config.AttackRecovery
	local flatTarget = Vector3.new(targetRoot.Position.X, state.Root.Position.Y, targetRoot.Position.Z)
	if (flatTarget - state.Root.Position).Magnitude > 0.05 then
		state.Model:PivotTo(CFrame.lookAt(state.Model:GetPivot().Position, flatTarget))
	end
	state.Humanoid:MoveTo(state.Root.Position)
	setState(state, "Attack")
	MonsterAnimationLoader.Play(state.Model, state.Humanoid, "Attack", 0.06)

	task.delay(config.AttackWindup, function()
		if
			not state.Model.Parent
			or state.Humanoid.Health <= 0
			or state.AttackSerial ~= serial
			or state.Model:GetAttribute("CombatStunned") == true
			or (state.Model:GetAttribute("CombatInterruptSerial") or 0) ~= interruptSerial
		then
			return
		end
		targetCharacter, targetHumanoid, targetRoot = livingCharacter(targetPlayer)
		if not targetCharacter then
			return
		end
		local distance = (targetRoot.Position - state.Root.Position).Magnitude
		local hits = false
		if config.AttackType == "Melee" then
			hits = distance <= config.AttackRange + 3
				and targetInsideMeleeHitbox(state, targetCharacter, config)
				and hasLineOfSight(state, targetCharacter, targetRoot)
		elseif config.AttackType == "Contact" then
			hits = distance <= config.AttackRange
		elseif config.AttackType == "Ranged" then
			hits = distance <= config.AttackRange and hasLineOfSight(state, targetCharacter, targetRoot)
		end
		if hits then
			local damageSource = state.Model:GetAttribute("IsElite") == true
				and "EliteEnemy"
				or "Monster"
			PlayerDamageService.ApplyToHumanoid(targetHumanoid, config.AttackDamage, damageSource)
		end
	end)
	task.delay(config.AttackWindup + config.AttackRecovery, function()
		if state.Model.Parent and state.Humanoid.Health > 0 and state.AttackSerial == serial then
			setState(state, state.Target and "Chase" or "Idle")
		end
	end)
end

local function roam(state, config, now)
	if config.CanMove ~= true or config.CanRoam ~= true or config.RoamRadius <= 0 then
		setState(state, "Idle")
		state.Humanoid:MoveTo(state.Root.Position)
		return
	end
	if now >= state.NextRoamAt then
		local angle = state.Random:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(state.Random:NextNumber()) * config.RoamRadius
		local destination = state.Home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		moveToward(state, destination, config, now)
		state.NextRoamAt = now + state.Random:NextNumber(2.5, 5.5)
		setState(state, "Roam")
	elseif (state.Root.Position - state.Home).Magnitude < 1.5 then
		setState(state, "Idle")
	end
end

local function updateStuck(state, targetRoot, now)
	local elapsed = math.max(CLOSE_THINK_INTERVAL, now - state.LastThinkAt)
	state.LastThinkAt = now
	local moved = (state.Root.Position - state.LastPosition).Magnitude
	state.LastPosition = state.Root.Position
	state.StuckTime = moved < 0.12 and state.StuckTime + elapsed or 0
	if targetRoot and state.StuckTime >= 0.8 and now >= state.NextJumpAt then
		state.NextJumpAt = now + 1.2
		state.StuckTime = 0
		state.Humanoid.Jump = true
	end
end

local function updateState(state, now)
	if state.Model:GetAttribute("SimulationActive") == false then
		stopForScheduler(state, "DormantIsland")
		return SLEEP_THINK_INTERVAL
	end
	local playerDistance = distanceToNearestPlayer(state.Root.Position)
	local interval
	if playerDistance > MAX_ACTIVE_PLAYER_DISTANCE then
		stopForScheduler(state, "Sleeping")
		return SLEEP_THINK_INTERVAL
	elseif playerDistance <= CLOSE_PLAYER_DISTANCE then
		interval = CLOSE_THINK_INTERVAL
		setSchedulerTier(state, "Close")
	elseif playerDistance <= MEDIUM_PLAYER_DISTANCE then
		interval = MEDIUM_THINK_INTERVAL
		setSchedulerTier(state, "Medium")
	else
		interval = FAR_THINK_INTERVAL
		setSchedulerTier(state, "Far")
	end
	state.SchedulerStopped = false
	if state.Model:GetAttribute("CombatStunned") == true then
		state.AttackSerial += 1
		setState(state, "Stunned")
		return interval
	end
	if now < state.ActionLockedUntil then
		state.Humanoid:MoveTo(state.Root.Position)
		return interval
	end
	if not isGeneric(state.Model) then
		unregister(state)
		return interval
	end

	local config = MonsterConfig.Read(state.Model)
	local targetPlayer = selectTarget(state, config)
	local _, targetHumanoid, targetRoot = livingCharacter(targetPlayer)
	local homeDistance = (state.Root.Position - state.Home).Magnitude
	if config.ReturnToSpawn == true and homeDistance > config.LeashRange then
		state.Target = nil
		state.Model:SetAttribute("AggroUserId", nil)
		state.Model:SetAttribute("TargetUserId", nil)
		moveToward(state, state.Home, config, now)
		setState(state, "Return")
	elseif targetRoot then
		local distance = (targetRoot.Position - state.Root.Position).Magnitude
		if config.CanChase == true and distance > math.max(config.StopDistance, config.AttackRange * 0.75) then
			moveToward(state, targetRoot.Position, config, now)
			setState(state, "Chase")
		else
			state.Humanoid:MoveTo(state.Root.Position)
		end
		if now >= state.NextAttackAt then
			local usedAbility = AbilityRegistry.TryUse(state, config, targetHumanoid, targetRoot, distance, now)
			if not usedAbility and config.AttackType ~= "None" and distance <= config.AttackRange then
				beginAttack(state, config, targetPlayer, now)
			end
		end
	elseif config.ReturnToSpawn == true and homeDistance > math.max(2, config.RoamRadius) then
		moveToward(state, state.Home, config, now)
		setState(state, "Return")
	else
		roam(state, config, now)
	end
	updateStuck(state, targetRoot, now)
	return interval
end

local function compactSchedule()
	if inactiveScheduleEntries < 32 then
		return
	end
	local compacted = {}
	for _, state in ipairs(scheduledStates) do
		if state.Scheduled and states[state.Model] == state then
			table.insert(compacted, state)
		end
	end
	scheduledStates = compacted
	schedulerCursor = math.clamp(schedulerCursor, 1, math.max(1, #scheduledStates))
	inactiveScheduleEntries = 0
end

RunService.Heartbeat:Connect(function()
	local stateCount = #scheduledStates
	if stateCount == 0 then
		return
	end
	local startedAt = os.clock()
	local now = os.clock()
	local decisions = 0
	local scans = 0
	while
		scans < math.min(MAX_AI_SCANS_PER_HEARTBEAT, stateCount)
		and decisions < MAX_AI_DECISIONS_PER_HEARTBEAT
		and os.clock() - startedAt < AI_TIME_BUDGET_SECONDS
	do
		if schedulerCursor > stateCount then
			schedulerCursor = 1
		end
		local state = scheduledStates[schedulerCursor]
		schedulerCursor += 1
		scans += 1
		if
			state
			and state.Scheduled
			and states[state.Model] == state
			and state.Model.Parent
			and state.Root.Parent
			and state.Humanoid.Health > 0
		then
			if now >= state.NextThinkAt then
				state.NextThinkAt = now + updateState(state, now)
				decisions += 1
			end
		elseif state and state.Scheduled then
			unregister(state)
		end
	end
	compactSchedule()
end)
