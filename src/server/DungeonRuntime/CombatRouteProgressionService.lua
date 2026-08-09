--[[
	Infinity Islands - Task 09
	CombatRouteProgressionService V1

	New progression authority for the linear MVP:

		current island
			-> kill all planned mobs
			-> IslandCombatService publishes Cleared=true
			-> current exit unlocks
			-> next GlobalIslandIndex becomes allowed
			-> entering the next island advances the party checkpoint
			-> that island locks its own exit until cleared

	No:
	- old objective sequence;
	- Reward Island commits;
	- Round gates;
	- Boss requirement;
	- hard PlayerLevel gate.

	RecommendedLevel stays informational only.

	This service publishes compatibility DungeonObjective* attributes so old
	presentation/analytics code can remain alive during migration without owning
	progression.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRouteProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.CombatRouteProgressionConfig
)

local IslandAdvanceFeedbackConfig = require(
	ReplicatedStorage.Shared.Configs.IslandAdvanceFeedbackConfig
)

local CombatGateService = require(
	script.Parent.CombatGateService
)

local DungeonSpawnService = require(
	script.Parent.DungeonSpawnService
)

local CombatRouteProgressionService = {}

local started = false
local generation = 0
local options = {}

local currentIsland = 1
local highestUnlockedIsland = 1
local currentContext

local completed = {}
local watchedContexts = {}
local contextConnections = {}

local rejectedAt =
	setmetatable({}, { __mode = "k" })

local routeComplete = false
local clearSerial = 0
local entrySerial = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	local number = tonumber(value)

	if not number then
		return nil
	end

	number = math.floor(number)

	return number >= 1 and number or nil
end

local function totalIslandCount()
	return math.max(
		2,
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonPlannedCombatIslandCount"
				)
			)
				or CombatRouteProgressionConfig
					.DefaultTotalIslandCount
		)
	)
end

local function safeCallback(name, ...)
	local callback = options[name]

	if type(callback) ~= "function" then
		return true
	end

	local ok, result =
		pcall(callback, ...)

	if not ok then
		workspace:SetAttribute(
			"DungeonCombatRouteCallbackError",
			name .. ": " .. tostring(result)
		)

		warn(
			"[CombatRouteProgressionService] "
				.. name
				.. " falhou: "
				.. tostring(result)
		)

		return false
	end

	return result ~= false
end

local function getContext(index)
	if type(options.GetIslandContext)
		~= "function"
	then
		return nil
	end

	local ok, result =
		pcall(
			options.GetIslandContext,
			index
		)

	if not ok then
		return nil
	end

	return result
end

local function requestThrough(index)
	if type(options.RequestRouteThrough)
		~= "function"
	then
		return false
	end

	local total = totalIslandCount()

	index = math.clamp(
		math.floor(tonumber(index) or 1),
		1,
		total
	)

	local ok =
		pcall(
			options.RequestRouteThrough,
			index
		)

	return ok
end

local function objectiveNumbers()
	local context =
		currentContext
			or getContext(currentIsland)

	local island =
		context
			and context.IslandModel

	if not island then
		return 0, 0, 0, false, "Dormant"
	end

	local target =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute(
						"MobTargetCount"
					)
				) or 0
			)
		)

	local spawned =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute(
						"MobSpawnedCount"
					)
				) or 0
			)
		)

	local alive =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute(
						"MobAliveCount"
					)
				) or 0
			)
		)

	local defeated =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute("MobDefeatedCount")
				) or math.max(0, spawned - alive)
			)
		)

	local progress =
		math.clamp(
			defeated,
			0,
			target
		)

	local cleared =
		island:GetAttribute("Cleared") == true
			or island:GetAttribute(
				"CombatState"
			) == "Cleared"

	local combatState =
		tostring(
			island:GetAttribute(
				"CombatState"
			) or "Dormant"
		)

	if cleared and target > 0 then
		progress = target
	end

	return progress,
		target,
		alive,
		cleared,
		combatState
end

local function publish()
	local progress,
		target,
		alive,
		cleared,
		combatState =
			objectiveNumbers()

	local total =
		totalIslandCount()

	workspace:SetAttribute(
		"DungeonCombatRouteProgressionReady",
		started
	)
	workspace:SetAttribute(
		"DungeonCombatRouteProgressionVersion",
		CombatRouteProgressionConfig.Version
	)
	workspace:SetAttribute(
		"DungeonProgressionReady",
		started
	)
	workspace:SetAttribute(
		"DungeonProgressionVersion",
		CombatRouteProgressionConfig.Version
	)

	workspace:SetAttribute(
		"DungeonProgressionState",
		routeComplete
			and "RouteCompleted"
			or cleared
				and "TravelUnlocked"
				or combatState == "Active"
					and "CombatActive"
					or "WaitingForCombat"
	)

	workspace:SetAttribute(
		"DungeonObjectiveSequenceState",
		workspace:GetAttribute(
			"DungeonProgressionState"
		)
	)
	workspace:SetAttribute(
		"DungeonRoundProgressState",
		workspace:GetAttribute(
			"DungeonProgressionState"
		)
	)

	workspace:SetAttribute(
		"DungeonCurrentObjectiveIsland",
		currentIsland
	)
	workspace:SetAttribute(
		"DungeonHighestUnlockedCombatIsland",
		highestUnlockedIsland
	)
	workspace:SetAttribute(
		"DungeonCombatRouteTotalIslands",
		total
	)

	workspace:SetAttribute(
		"DungeonObjectiveId",
		CombatRouteProgressionConfig.ObjectiveId
	)
	workspace:SetAttribute(
		"DungeonObjectiveType",
		"ClearCombatIsland"
	)
	local advanceActive =
		cleared
			and not routeComplete
			and currentIsland < total

	local nextIsland =
		advanceActive
			and currentIsland + 1
			or nil

	workspace:SetAttribute(
		"DungeonObjectiveTitle",
		routeComplete
			and IslandAdvanceFeedbackConfig.RouteCompleteTitle
			or cleared
				and IslandAdvanceFeedbackConfig.ClearTitle
				or CombatRouteProgressionConfig.ObjectiveTitle
	)
	workspace:SetAttribute(
		"DungeonObjectiveDescription",
		routeComplete
			and IslandAdvanceFeedbackConfig.RouteCompleteDescription
			or advanceActive
				and string.format(
					IslandAdvanceFeedbackConfig.AdvanceDescriptionFormat,
					nextIsland
				)
				or CombatRouteProgressionConfig.ObjectiveDescription
	)

	workspace:SetAttribute(
		"DungeonIslandAdvanceFeedbackVersion",
		IslandAdvanceFeedbackConfig.Version
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceActive",
		advanceActive
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceFromIsland",
		advanceActive and currentIsland or nil
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceToIsland",
		nextIsland
	)
	workspace:SetAttribute(
		"DungeonObjectiveGlobalIslandIndex",
		currentIsland
	)
	workspace:SetAttribute(
		"DungeonObjectiveIslandIndex",
		currentIsland
	)
	workspace:SetAttribute(
		"DungeonObjectiveRoundIndex",
		nil
	)

	workspace:SetAttribute(
		"DungeonObjectiveProgress",
		progress
	)
	workspace:SetAttribute(
		"DungeonObjectiveTarget",
		target
	)
	workspace:SetAttribute(
		"DungeonObjectiveMobAliveCount",
		alive
	)
	workspace:SetAttribute(
		"DungeonObjectiveState",
		cleared
			and "Completed"
			or combatState == "Active"
				and "Active"
				or "Inactive"
	)

	workspace:SetAttribute(
		"DungeonObjectiveExitLocked",
		not cleared
			and currentIsland < total
	)
	workspace:SetAttribute(
		"DungeonCurrentIslandIsRoundExit",
		false
	)
	workspace:SetAttribute(
		"DungeonCurrentRoundExitCommitted",
		false
	)
	workspace:SetAttribute(
		"DungeonRoundRewardPending",
		false
	)
	workspace:SetAttribute(
		"DungeonRewardPendingRound",
		nil
	)
	workspace:SetAttribute(
		"DungeonFinalRewardCommitted",
		false
	)

	workspace:SetAttribute(
		"DungeonLegacyObjectiveSystemDisabled",
		true
	)
	workspace:SetAttribute(
		"DungeonLegacyRewardProgressionDisabled",
		true
	)
	workspace:SetAttribute(
		"DungeonLegacyBossProgressionDisabled",
		true
	)

	workspace:SetAttribute(
		"DungeonLinearRouteComplete",
		routeComplete
	)
	workspace:SetAttribute(
		"DungeonCombatRouteClearSerial",
		clearSerial
	)
	workspace:SetAttribute(
		"DungeonCombatRouteEntrySerial",
		entrySerial
	)
end

local function applyGate(
	index,
	locked,
	reason
)
	if index >= totalIslandCount() then
		return true
	end

	local context =
		watchedContexts[index]
			or getContext(index)

	if not context
		or not context.IslandModel
		or not context.IslandModel.Parent
	then
		return false, "IslandContextUnavailable"
	end

	watchedContexts[index] = context

	local ok,
		success,
		firstGate,
		gates =
			pcall(
				CombatGateService.Apply,
				context,
				locked == true,
				reason
			)

	if not ok then
		workspace:SetAttribute(
			"DungeonCombatGateError",
			tostring(success)
		)

		return false, tostring(success)
	end

	if success == false then
		workspace:SetAttribute(
			"DungeonCombatGateError",
			tostring(firstGate)
		)

		return false, firstGate
	end


	context.IslandModel:SetAttribute(
		"CombatExitLocked",
		locked == true
	)
	context.IslandModel:SetAttribute(
		"CombatExitLockReason",
		locked
			and tostring(
				reason or "CombatActive"
			)
			or nil
	)
	context.IslandModel:SetAttribute(
		"CombatRouteProgressionVersion",
		CombatRouteProgressionConfig.Version
	)

	workspace:SetAttribute(
		"DungeonCombatGateError",
		nil
	)

	return true, firstGate, gates
end

local function currentDefinition()
	local progress,
		target,
		alive,
		cleared,
		combatState =
			objectiveNumbers()

	return {
		Id =
			CombatRouteProgressionConfig
				.ObjectiveId,
		Type = "ClearCombatIsland",
		Title =
			CombatRouteProgressionConfig
				.ObjectiveTitle,
		Description =
			CombatRouteProgressionConfig
				.ObjectiveDescription,

		GlobalIslandIndex =
			currentIsland,
		IslandIndex =
			currentIsland,
		RoundIndex = nil,

		Target = target,
		Progress = progress,
		MobAliveCount = alive,
		Completed = cleared,
		CombatState = combatState,

		ObjectiveKind =
			"ClearCombatIsland",
		SpawnProfile =
			"IslandCombatManaged",
	}
end

local function snapshot()
	local definition =
		currentDefinition()

	local completedCount = 0

	for _, isCleared in pairs(
		completed
	) do
		if isCleared == true then
			completedCount += 1
		end
	end

	return {
		Started = started,
		Version =
			CombatRouteProgressionConfig
				.Version,

		State =
			workspace:GetAttribute(
				"DungeonProgressionState"
			),

		Id = definition.Id,
		Type = definition.Type,
		Title = definition.Title,
		Description =
			definition.Description,

		CurrentObjective = definition,

		CurrentGlobalIslandIndex =
			currentIsland,
		GlobalIslandIndex =
			currentIsland,
		IslandIndex =
			currentIsland,
		RoundIndex = nil,

		Progress =
			definition.Progress,
		Target =
			definition.Target,
		Completed =
			definition.Completed,
		MobAliveCount =
			definition.MobAliveCount,
		CombatState =
			definition.CombatState,

		HighestUnlockedIsland =
			highestUnlockedIsland,
		TotalIslandCount =
			totalIslandCount(),
		CompletedCount =
			completedCount,

		ExitLocked =
			workspace:GetAttribute(
				"DungeonObjectiveExitLocked"
			) == true,

		IslandContext =
			currentContext
				or getContext(
					currentIsland
				),

		RouteComplete =
			routeComplete,

		RewardPendingRound = nil,
		HighestCompletedRound = 0,
		CompletedRounds = {},
		CurrentIslandIsRoundExit =
			false,
		RoundCompleted = false,
		FinalRewardCommitted = false,
	}
end

local function commitCheckpoint(
	context,
	reason
)
	local ok,
		success,
		detail =
			pcall(
				DungeonSpawnService
					.CommitLinearRouteCheckpoint,
				context,
				reason,
				false
			)

	if not ok then
		workspace:SetAttribute(
			"DungeonLinearRouteCheckpointHealthy",
			false
		)
		workspace:SetAttribute(
			"DungeonLinearRouteCheckpointError",
			tostring(success)
		)

		return false
	end

	workspace:SetAttribute(
		"DungeonLinearRouteCheckpointHealthy",
		success == true
	)
	workspace:SetAttribute(
		"DungeonLinearRouteCheckpointError",
		success
			and nil
			or tostring(detail)
	)

	return success == true
end

local function reject(
	player,
	requestedIndex,
	reason
)
	if not player
		or player.Parent ~= Players
	then
		return false, reason
	end

	local timestamp = now()

	if timestamp
			- (rejectedAt[player] or 0)
		>= 0.35
	then
		rejectedAt[player] = timestamp

		player:SetAttribute(
			"DungeonRouteRejectedReason",
			reason
		)
		player:SetAttribute(
			"DungeonRouteRejectedIsland",
			requestedIndex
		)
		player:SetAttribute(
			"DungeonRouteRejectedAt",
			timestamp
		)

		safeCallback(
			"OnRouteRejected",
			player,
			requestedIndex,
			reason,
			highestUnlockedIsland
		)

		task.defer(function()
			DungeonSpawnService.PositionPlayer(
				player,
				"RouteRejected:"
					.. tostring(reason)
			)
		end)
	end

	return false, reason
end

local handleIslandCleared

local function watchContext(index, context)
	if not context
		or not context.IslandModel
	then
		return false
	end

	local island =
		context.IslandModel

	if watchedContexts[index]
		and watchedContexts[index].IslandModel
			== island
	then
		return true
	end

	local old =
		contextConnections[index]

	if old then
		for _, connection in ipairs(old) do
			connection:Disconnect()
		end
	end

	watchedContexts[index] = context
	contextConnections[index] = {}

	local function bindAttribute(name)
		table.insert(
			contextConnections[index],
			island
				:GetAttributeChangedSignal(
					name
				)
				:Connect(function()
					if not started then
						return
					end

					if name == "Cleared"
						or name
							== "CombatState"
					then
						if island:GetAttribute(
							"Cleared"
						) == true
							or island:GetAttribute(
								"CombatState"
							) == "Cleared"
						then
							handleIslandCleared(
								index,
								context
							)
						end
					end

					if index == currentIsland then
						publish()
					end
				end)
		)
	end

	for _, name in ipairs({
		"Cleared",
		"CombatState",
		"MobTargetCount",
		"MobKillQuota",
		"MobDefeatedCount",
		"MobSpawnedCount",
		"MobAliveCount",
	}) do
		bindAttribute(name)
	end

	if island:GetAttribute("Cleared")
			== true
		or island:GetAttribute(
			"CombatState"
		) == "Cleared"
	then
		task.defer(
			handleIslandCleared,
			index,
			context
		)
	end

	return true
end

handleIslandCleared = function(
	index,
	context
)
	if not started
		or completed[index] == true
	then
		return false
	end

	completed[index] = true
	clearSerial += 1

	local island =
		context
			and context.IslandModel

	if island then
		island:SetAttribute(
			"CombatRouteCleared",
			true
		)
		island:SetAttribute(
			"CombatRouteClearedAt",
			now()
		)
		island:SetAttribute(
			"CombatRouteClearSerial",
			clearSerial
		)
	end

	applyGate(
		index,
		false,
		"CombatIslandCleared"
	)

	local total =
		totalIslandCount()

	workspace:SetAttribute(
		"DungeonIslandClearFeedbackSerial",
		clearSerial
	)
	workspace:SetAttribute(
		"DungeonIslandClearFeedbackAt",
		now()
	)
	workspace:SetAttribute(
		"DungeonIslandClearFeedbackIsland",
		index
	)

	if index >= total then
		workspace:SetAttribute(
			"DungeonIslandClearFeedbackNextIsland",
			nil
		)

		routeComplete = true
		highestUnlockedIsland =
			math.max(
				highestUnlockedIsland,
				total
			)

		workspace:SetAttribute(
			"DungeonLinearRouteComplete",
			true
		)
		workspace:SetAttribute(
			"DungeonLinearRouteCompletedAt",
			now()
		)
		workspace:SetAttribute(
			"DungeonLinearRouteCompletedIsland",
			index
		)
	else
		local nextIndex = index + 1

		workspace:SetAttribute(
			"DungeonIslandClearFeedbackNextIsland",
			nextIndex
		)

		highestUnlockedIsland =
			math.max(
				highestUnlockedIsland,
				nextIndex
			)

		workspace:SetAttribute(
			"DungeonNextCombatIslandUnlocked",
			nextIndex
		)
		workspace:SetAttribute(
			"DungeonNextCombatIslandUnlockedAt",
			now()
		)

		requestThrough(
			math.min(
				total,
				index
					+ CombatRouteProgressionConfig
						.FutureLookahead
			)
		)
	end

	if index == currentIsland then
		workspace:SetAttribute(
			"DungeonObjectiveCompletedAt",
			now()
		)
		workspace:SetAttribute(
			"DungeonObjectiveCompletionReason",
			"KillQuotaReached"
		)
	end

	publish()

	return true
end

local function prepareCurrentIsland(
	index,
	context
)
	watchContext(index, context)

	if completed[index] == true
		or (
			context.IslandModel
			and context.IslandModel:GetAttribute(
				"Cleared"
			) == true
		)
	then
		applyGate(
			index,
			false,
			"AlreadyCleared"
		)
		return
	end

	applyGate(
		index,
		true,
		"CombatIslandActive"
	)
end

local function setCurrentIsland(
	index,
	context,
	player
)
	currentIsland = index
	currentContext = context

	entrySerial += 1

	workspace:SetAttribute(
		"DungeonIslandAdvanceEnteredIsland",
		index
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceEnteredAt",
		now()
	)

	prepareCurrentIsland(
		index,
		context
	)

	requestThrough(
		math.min(
			totalIslandCount(),
			index
				+ CombatRouteProgressionConfig
					.FutureLookahead
		)
	)

	commitCheckpoint(
		context,
		"LinearCombatIslandEntered:"
			.. tostring(index)
	)

	if player then
		player:SetAttribute(
			"DungeonCombatRouteEntryAccepted",
			true
		)
		player:SetAttribute(
			"DungeonCombatRouteEntryIndex",
			index
		)
		player:SetAttribute(
			"DungeonCombatRouteEntryAt",
			now()
		)
	end

	workspace:SetAttribute(
		"DungeonLastAcceptedCombatIsland",
		index
	)
	workspace:SetAttribute(
		"DungeonLastAcceptedCombatIslandAt",
		now()
	)

	publish()
end

local function discoverContexts()
	local total =
		totalIslandCount()

	local maximum =
		math.min(
			total,
			math.max(
				highestUnlockedIsland
					+ CombatRouteProgressionConfig
						.FutureLookahead,
				currentIsland
					+ CombatRouteProgressionConfig
						.FutureLookahead
			)
		)

	for index = 1, maximum do
		local context =
			getContext(index)

		if context
			and context.IslandModel
			and context.IslandModel.Parent
		then
			watchContext(
				index,
				context
			)

			if index == currentIsland
				and not currentContext
			then
				currentContext = context
				prepareCurrentIsland(
					index,
					context
				)
			end
		end
	end
end

function CombatRouteProgressionService.Start(
	startOptions
)
	if started then
		return false, "AlreadyStarted"
	end

	started = true
	generation += 1

	options =
		type(startOptions) == "table"
			and startOptions
			or {}

	currentIsland = 1
	highestUnlockedIsland = 1
	currentContext = nil
	completed = {}
	watchedContexts = {}
	contextConnections = {}
	rejectedAt =
		setmetatable({}, { __mode = "k" })

	routeComplete = false
	clearSerial = 0
	entrySerial = 0

	local token = generation

	workspace:SetAttribute(
		"DungeonRouteProgressionAuthority",
		"CombatRouteProgressionService"
	)
	workspace:SetAttribute(
		"DungeonRouteEntryPolicy",
		"PreviousClearedThenNextV1"
	)
	workspace:SetAttribute(
		"DungeonCombatRouteProgressionPolicy",
		"KillQuotaUnlocksNextIsland"
	)
	workspace:SetAttribute(
		"DungeonCombatRouteMobsRemainAfterClear",
		true
	)
	workspace:SetAttribute(
		"DungeonRecommendedLevelIsHardGate",
		false
	)
	workspace:SetAttribute(
		"DungeonRoundRewardPending",
		false
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceFeedbackVersion",
		IslandAdvanceFeedbackConfig.Version
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceActive",
		false
	)
	workspace:SetAttribute(
		"DungeonIslandClearFeedbackSerial",
		0
	)

	publish()

	task.spawn(function()
		while started
			and generation == token
		do
			discoverContexts()
			publish()

			task.wait(
				CombatRouteProgressionConfig
					.ReconcileSeconds
			)
		end
	end)

	return true
end

function CombatRouteProgressionService.Stop()
	if not started then
		return false
	end

	started = false
	generation += 1

	for _, connections in pairs(
		contextConnections
	) do
		for _, connection in ipairs(
			connections
		) do
			connection:Disconnect()
		end
	end

	contextConnections = {}
	watchedContexts = {}
	options = {}

	publish()

	return true
end

function CombatRouteProgressionService
	.HandleIslandEntered(
		player,
		context
	)
	if not started
		or not player
		or player.Parent ~= Players
		or type(context) ~= "table"
	then
		return false, "InvalidRouteEntry"
	end

	if context.IsOptionalRoute == true then
		return reject(
			player,
			cleanIndex(
				context.GlobalIslandIndex
			) or 0,
			"OptionalRoutesDisabled"
		)
	end

	if context.IsBossSanctuary == true then
		return reject(
			player,
			totalIslandCount() + 1,
			"BossProgressionDisabled"
		)
	end

	local requestedIndex =
		cleanIndex(
			context.GlobalIslandIndex
		)

	if not requestedIndex then
		return false, "InvalidGlobalIslandIndex"
	end

	local total =
		totalIslandCount()

	if requestedIndex > total then
		return reject(
			player,
			requestedIndex,
			routeComplete
				and "RouteAlreadyCompleted"
				or "OutsideCombatRoute"
		)
	end

	watchContext(
		requestedIndex,
		context
	)

	if requestedIndex
		> highestUnlockedIsland
	then
		return reject(
			player,
			requestedIndex,
			"PreviousIslandNotCleared"
		)
	end

	-- Backtracking never moves global progression or the checkpoint backwards.
	if requestedIndex < currentIsland then
		return true, "BacktrackingAllowed"
	end

	if requestedIndex == currentIsland then
		currentContext = context
		prepareCurrentIsland(
			requestedIndex,
			context
		)
		publish()

		return true,
			completed[requestedIndex]
				and "CombatIslandCleared"
				or "CombatIslandActive"
	end

	-- Since HighestUnlocked is advanced only by clearing N, the only legal
	-- forward move is N -> N+1.
	if requestedIndex
		~= currentIsland + 1
	then
		return reject(
			player,
			requestedIndex,
			"CombatRouteSequenceSkipped"
		)
	end

	if completed[currentIsland]
		~= true
	then
		return reject(
			player,
			requestedIndex,
			"PreviousIslandNotCleared"
		)
	end

	setCurrentIsland(
		requestedIndex,
		context,
		player
	)

	return true, "CombatIslandEntered"
end

function CombatRouteProgressionService
	.GetSnapshot()
	return snapshot()
end

function CombatRouteProgressionService
	.GetCurrentDefinition()
	return currentDefinition()
end

function CombatRouteProgressionService
	.GetCurrentContext()
	return currentContext
		or getContext(currentIsland)
end

function CombatRouteProgressionService
	.GetHighestUnlockedIsland()
	return highestUnlockedIsland
end

function CombatRouteProgressionService
	.IsRouteComplete()
	return routeComplete
end

function CombatRouteProgressionService
	.EscalateWaypoint()
	local context =
		currentContext
			or getContext(currentIsland)

	if not context then
		return false, "ContextUnavailable"
	end

	local marker

	if completed[currentIsland] == true then
		marker = context.Exit
	else
		marker =
			context.ObjectiveAnchor
				or context.SafeSpawn
	end

	if not marker
		or not marker.Parent
	then
		return false, "WaypointUnavailable"
	end

	local position

	if marker:IsA("BasePart") then
		position = marker.Position
	elseif marker:IsA("Model") then
		position =
			marker:GetPivot().Position
	end

	if not position then
		return false, "WaypointPositionUnavailable"
	end

	workspace:SetAttribute(
		"DungeonObjectiveWaypointPosition",
		position
	)
	workspace:SetAttribute(
		"DungeonObjectiveWaypointTarget",
		marker:GetFullName()
	)
	workspace:SetAttribute(
		"DungeonObjectiveWaypointEscalated",
		true
	)
	workspace:SetAttribute(
		"DungeonObjectiveWaypointSerial",
		(
			tonumber(
				workspace:GetAttribute(
					"DungeonObjectiveWaypointSerial"
				)
			) or 0
		) + 1
	)

	return true
end

function CombatRouteProgressionService
	.RecoverCurrentIsland()
	local context =
		currentContext
			or getContext(currentIsland)

	if not context then
		requestThrough(
			math.min(
				totalIslandCount(),
				currentIsland
					+ CombatRouteProgressionConfig
						.FutureLookahead
			)
		)

		return true,
			"RouteMaterializationRequested"
	end

	prepareCurrentIsland(
		currentIsland,
		context
	)

	return true,
		"CombatIslandRefreshed"
end

return CombatRouteProgressionService
