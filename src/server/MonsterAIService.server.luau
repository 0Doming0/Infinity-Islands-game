-- IA basica para prototipos e Elites sem IA propria. Assets com IA especifica
-- podem definir UseCentralAI=false e manter seus scripts internos.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MobEventModifiers = require(script.Parent.BlockParkour:WaitForChild("MobEventModifiers"))

local CLOSE_THINK_INTERVAL = 0.20
local MEDIUM_THINK_INTERVAL = 0.45
local FAR_THINK_INTERVAL = 0.9
local SLEEP_THINK_INTERVAL = 1.5
local CLOSE_PLAYER_DISTANCE = 80
local MEDIUM_PLAYER_DISTANCE = 150
local MAX_ACTIVE_PLAYER_DISTANCE = 240
local MAX_AI_DECISIONS_PER_HEARTBEAT = 8
local MAX_AI_SCANS_PER_HEARTBEAT = 32
local AI_TIME_BUDGET_SECONDS = 0.0015
local DEFAULT_AGGRO_RANGE = 55
local DEFAULT_LEASH_RANGE = 42
local DEFAULT_ATTACK_RANGE = 5
local DEFAULT_ATTACK_COOLDOWN = 1.15

local states = setmetatable({}, { __mode = "k" })
local scheduledStates = {}
local schedulerCursor = 1
local inactiveScheduleEntries = 0

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function nearestPlayer(position, range)
	local selectedHumanoid
	local selectedRoot
	local bestDistance = range
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				selectedHumanoid = humanoid
				selectedRoot = root
			end
		end
	end
	return selectedHumanoid, selectedRoot, bestDistance
end

local function distanceToNearestPlayer(position)
	local bestDistanceSquared = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			local offset = root.Position - position
			local distanceSquared = offset:Dot(offset)
			if distanceSquared < bestDistanceSquared then
				bestDistanceSquared = distanceSquared
			end
		end
	end
	return math.sqrt(bestDistanceSquared)
end

local function register(model)
	if not model:IsA("Model") or states[model] then
		return
	end
	local controller = model:GetAttribute("AIController")
	if controller ~= nil and controller ~= "Generic" then
		return
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = rootOf(model)
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local home = model:GetAttribute("HomePosition")
	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Home = typeof(home) == "Vector3" and home or root.Position,
		NextAttackAt = 0,
		NextJumpAt = 0,
		LastPosition = root.Position,
		StuckTime = 0,
		NextThinkAt = os.clock() + math.random() * CLOSE_THINK_INTERVAL,
		Scheduled = true,
		SchedulerTier = nil,
		SchedulerStopped = false,
	}
	states[model] = state
	table.insert(scheduledStates, state)
	humanoid.Died:Connect(function()
		if state.Scheduled then
			state.Scheduled = false
			inactiveScheduleEntries += 1
		end
		states[model] = nil
	end)
	model.Destroying:Connect(function()
		if state.Scheduled then
			state.Scheduled = false
			inactiveScheduleEntries += 1
		end
		states[model] = nil
	end)
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function(model)
	task.defer(register, model)
end)
for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
	task.defer(register, model)
end

local function setSchedulerTier(state, tier)
	if state.SchedulerTier == tier then
		return
	end
	state.SchedulerTier = tier
	state.Model:SetAttribute("AIUpdateTier", tier)
end

local function stopForScheduler(state, tier)
	setSchedulerTier(state, tier)
	if state.SchedulerStopped then
		return
	end
	state.SchedulerStopped = true
	state.Humanoid:MoveTo(state.Root.Position)
end

local function updateState(state, now)
	local model = state.Model
	local humanoid = state.Humanoid
	local root = state.Root

	if model:GetAttribute("SimulationActive") == false then
		stopForScheduler(state, "DormantIsland")
		return SLEEP_THINK_INTERVAL
	end

	local playerDistance = distanceToNearestPlayer(root.Position)
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

	if model:GetAttribute("CombatStunned") == true then
		return interval
	end
	local forceAggressive = MobEventModifiers.IsForcedAggressive(model)
	local controller = model:GetAttribute("AIController")
	local ownedByGenericAI = controller == "Generic"
		or (controller == nil and model:GetAttribute("UseCentralAI") == true)
	if not ownedByGenericAI then
		return interval
	end

	local baseAggro = tonumber(model:GetAttribute("AggroRange")) or DEFAULT_AGGRO_RANGE
	local aggro = MobEventModifiers.GetAggroRange(model, baseAggro)
	local targetHumanoid, targetRoot, distance
	if forceAggressive or model:GetAttribute("Peaceful") ~= true then
		targetHumanoid, targetRoot, distance = nearestPlayer(root.Position, aggro)
	end
	local leash = tonumber(model:GetAttribute("LeashRange")) or DEFAULT_LEASH_RANGE
	if (root.Position - state.Home).Magnitude > leash then
		humanoid:MoveTo(state.Home)
	elseif targetRoot then
		humanoid:MoveTo(targetRoot.Position)
		local attackRange = tonumber(model:GetAttribute("AttackRange")) or DEFAULT_ATTACK_RANGE
		if distance <= attackRange and now >= state.NextAttackAt then
			state.NextAttackAt = now + (tonumber(model:GetAttribute("AttackCooldown")) or DEFAULT_ATTACK_COOLDOWN)
			targetHumanoid:TakeDamage(math.max(1, tonumber(model:GetAttribute("AttackDamage")) or 8))
		end
	else
		humanoid:MoveTo(state.Home)
	end

	local elapsed = math.max(CLOSE_THINK_INTERVAL, now - (state.LastThinkAt or now))
	state.LastThinkAt = now
	local moved = (root.Position - state.LastPosition).Magnitude
	state.LastPosition = root.Position
	state.StuckTime = moved < 0.15 and state.StuckTime + elapsed or 0
	if targetRoot and state.StuckTime >= 0.8 and now >= state.NextJumpAt then
		state.NextJumpAt = now + 1.2
		state.StuckTime = 0
		humanoid.Jump = true
	end
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
			state.Scheduled = false
			inactiveScheduleEntries += 1
			if state.Model then
				states[state.Model] = nil
			end
		end
	end
	compactSchedule()
end)
