--[[
	Infinity Islands - CombatRouteProgressionService V2 Free Recommended Route

	MVP policy:
	- player may enter any materialized Combat Island;
	- RecommendedLevel is a warning, never a hard gate;
	- no physical CombatGateBarrier;
	- no teleport/reposition because previous island was not cleared;
	- clearing an island still updates progression/HUD feedback;
	- current island remains the active HUD objective.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRouteProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.CombatRouteProgressionConfig
)

local DungeonSpawnService = require(
	script.Parent.DungeonSpawnService
)

local CombatRouteProgressionService = {}

local started = false
local generation = 0
local options = {}

local currentIsland = 1
local currentContext = nil
local completed = {}
local watchedContexts = {}
local contextConnections = {}

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
			or CombatRouteProgressionConfig.DefaultTotalIslandCount
		)
	)
end

local function getContext(index)
	if type(options.GetIslandContext) ~= "function" then
		return nil
	end

	local ok, result =
		pcall(options.GetIslandContext, index)

	return ok and result or nil
end

local function requestThrough(index)
	if type(options.RequestRouteThrough) ~= "function" then
		return false
	end

	index = math.clamp(
		math.floor(tonumber(index) or 1),
		1,
		totalIslandCount()
	)

	return pcall(options.RequestRouteThrough, index)
end

local function islandFor(context)
	return context and context.IslandModel
end

local function objectiveNumbers(context)
	local island = islandFor(context)

	if not island then
		return 0, 0, 0, false, "Dormant"
	end

	local target =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute("MobTargetCount")
				) or 0
			)
		)

	local spawned =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute("MobSpawnedCount")
				) or 0
			)
		)

	local alive =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute("MobAliveCount")
				) or 0
			)
		)

	local defeated =
		math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute("MobDefeatedCount")
				)
				or math.max(0, spawned - alive)
			)
		)

	local cleared =
		island:GetAttribute("Cleared") == true

	local combatState =
		tostring(
			island:GetAttribute("CombatState")
			or "Dormant"
		)

	return math.clamp(defeated, 0, math.max(target, defeated)),
		target,
		alive,
		cleared,
		combatState
end

local function currentRecommendedLevel(context)
	local island = islandFor(context)

	return math.max(
		1,
		math.floor(
			tonumber(
				island
				and (
					island:GetAttribute("RecommendedLevel")
					or island:GetAttribute("IslandLevel")
				)
			) or currentIsland
		)
	)
end

local function isCombatRunningState(state)
	return state == "Active"
		or state == "WaveActive"
		or state == "RespawnCooldown"
end

local function publish()
	local context =
		currentContext
		or getContext(currentIsland)

	if context then
		currentContext = context
	end

	local progress, target, alive, cleared, combatState =
		objectiveNumbers(context)

	local total = totalIslandCount()
	local recommended =
		currentRecommendedLevel(context)

	local completedCount = 0
	for _, done in pairs(completed) do
		if done == true then
			completedCount += 1
		end
	end

	routeComplete =
		completedCount >= total

	local state
	if routeComplete then
		state = "RouteCompleted"
	elseif cleared then
		state = "TravelOpen"
	elseif isCombatRunningState(combatState) then
		state = "CombatActive"
	else
		state = "WaitingForCombat"
	end

	workspace:SetAttribute(
		"DungeonCombatRouteProgressionReady",
		started
	)
	workspace:SetAttribute(
		"DungeonCombatRouteProgressionVersion",
		"CombatRouteProgressionFreeV2"
	)
	workspace:SetAttribute(
		"DungeonProgressionReady",
		started
	)
	workspace:SetAttribute(
		"DungeonProgressionVersion",
		"CombatRouteProgressionFreeV2"
	)
	workspace:SetAttribute(
		"DungeonProgressionState",
		state
	)

	workspace:SetAttribute(
		"DungeonRouteProgressionAuthority",
		"CombatRouteProgressionService"
	)
	workspace:SetAttribute(
		"DungeonRouteEntryPolicy",
		"FreeRecommendedLevelV2"
	)
	workspace:SetAttribute(
		"DungeonCombatRouteProgressionPolicy",
		"FreeTraversalKillForXP"
	)
	workspace:SetAttribute(
		"DungeonRecommendedLevelIsHardGate",
		false
	)

	workspace:SetAttribute(
		"DungeonCurrentObjectiveIsland",
		currentIsland
	)
	workspace:SetAttribute(
		"DungeonHighestUnlockedCombatIsland",
		total
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
	workspace:SetAttribute(
		"DungeonObjectiveTitle",
		cleared
			and "ILHA CONCLUIDA"
			or CombatRouteProgressionConfig.ObjectiveTitle
	)
	workspace:SetAttribute(
		"DungeonObjectiveDescription",
		cleared
			and "Continue ou arrisque uma ilha mais forte."
			or CombatRouteProgressionConfig.ObjectiveDescription
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
			or isCombatRunningState(combatState)
				and "Active"
				or "Inactive"
	)

	-- HARD GATE REMOVED.
	workspace:SetAttribute(
		"DungeonObjectiveExitLocked",
		false
	)
	workspace:SetAttribute(
		"DungeonCombatGateError",
		nil
	)

	workspace:SetAttribute(
		"DungeonCurrentIslandRecommendedLevel",
		recommended
	)
	workspace:SetAttribute(
		"DungeonRecommendedLevelWarningActive",
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

local function markCleared(index, context)
	if completed[index] == true then
		return
	end

	local island = islandFor(context)
	if not island
		or island:GetAttribute("Cleared") ~= true
	then
		return
	end

	completed[index] = true
	clearSerial += 1

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
	workspace:SetAttribute(
		"DungeonIslandClearFeedbackNextIsland",
		index < totalIslandCount()
			and index + 1
			or nil
	)

	island:SetAttribute(
		"CombatRouteCleared",
		true
	)
	island:SetAttribute(
		"CombatExitLocked",
		false
	)
	island:SetAttribute(
		"RecommendedLevelIsHardGate",
		false
	)

	publish()
end

local function disconnectContext(index)
	local list = contextConnections[index]
	if not list then
		return
	end

	for _, connection in ipairs(list) do
		connection:Disconnect()
	end

	contextConnections[index] = nil
end

local function watchContext(index, context)
	local island = islandFor(context)

	if not island then
		return false
	end

	if watchedContexts[index]
		and watchedContexts[index].IslandModel == island
	then
		return true
	end

	disconnectContext(index)

	watchedContexts[index] = context
	contextConnections[index] = {}

	island:SetAttribute("CombatExitLocked", false)
	island:SetAttribute(
		"RecommendedLevelIsHardGate",
		false
	)

	for _, name in ipairs({
		"Cleared",
		"CombatState",
		"MobTargetCount",
		"MobKillQuota",
		"MobDefeatedCount",
		"MobSpawnedCount",
		"MobAliveCount",
		"RecommendedLevel",
		"IslandLevel",
	}) do
		table.insert(
			contextConnections[index],
			island:GetAttributeChangedSignal(name)
				:Connect(function()
					if not started then
						return
					end

					if name == "Cleared" then
						markCleared(index, context)
					end

					if index == currentIsland then
						publish()
					end
				end)
		)
	end

	if island:GetAttribute("Cleared") == true then
		task.defer(markCleared, index, context)
	end

	return true
end

local function commitForwardCheckpoint(context, index)
	local checkpoint =
		DungeonSpawnService.GetCheckpoint
			and DungeonSpawnService.GetCheckpoint()
			or nil

	local checkpointIndex =
		type(checkpoint) == "table"
			and cleanIndex(checkpoint.GlobalIslandIndex)
			or nil

	if checkpointIndex
		and index <= checkpointIndex
	then
		return
	end

	pcall(
		DungeonSpawnService.CommitLinearRouteCheckpoint,
		context,
		"FreeRouteIslandEntered:" .. tostring(index),
		false
	)
end

local function setCurrentIsland(index, context, player)
	currentIsland = index
	currentContext = context
	entrySerial += 1

	watchContext(index, context)

	requestThrough(
		math.min(
			totalIslandCount(),
			index
				+ CombatRouteProgressionConfig.FutureLookahead
		)
	)

	commitForwardCheckpoint(context, index)

	workspace:SetAttribute(
		"DungeonIslandAdvanceEnteredIsland",
		index
	)
	workspace:SetAttribute(
		"DungeonIslandAdvanceEnteredAt",
		now()
	)
	workspace:SetAttribute(
		"DungeonLastAcceptedCombatIsland",
		index
	)
	workspace:SetAttribute(
		"DungeonLastAcceptedCombatIslandAt",
		now()
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
		player:SetAttribute(
			"DungeonRouteRejectedReason",
			nil
		)
	end

	publish()
end

local function discoverContexts()
	local total = totalIslandCount()

	local maximum =
		math.min(
			total,
			currentIsland
				+ CombatRouteProgressionConfig.FutureLookahead
		)

	for index = 1, maximum do
		local context = getContext(index)

		if context
			and context.IslandModel
			and context.IslandModel.Parent
		then
			watchContext(index, context)

			if index == currentIsland
				and not currentContext
			then
				currentContext = context
			end
		end
	end
end

function CombatRouteProgressionService.Start(startOptions)
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
	currentContext = nil
	completed = {}
	watchedContexts = {}
	contextConnections = {}
	routeComplete = false
	clearSerial = 0
	entrySerial = 0

	local token = generation

	workspace:SetAttribute(
		"DungeonRouteEntryPolicy",
		"FreeRecommendedLevelV2"
	)
	workspace:SetAttribute(
		"DungeonRecommendedLevelIsHardGate",
		false
	)
	workspace:SetAttribute(
		"DungeonObjectiveExitLocked",
		false
	)

	requestThrough(
		math.min(
			totalIslandCount(),
			1
				+ CombatRouteProgressionConfig.FutureLookahead
		)
	)

	publish()

	task.spawn(function()
		while started
			and generation == token
		do
			discoverContexts()
			publish()

			task.wait(
				CombatRouteProgressionConfig.ReconcileSeconds
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

	for index in pairs(contextConnections) do
		disconnectContext(index)
	end

	watchedContexts = {}
	options = {}

	publish()

	return true
end

function CombatRouteProgressionService.HandleIslandEntered(
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
		return false, "OptionalRoutesDisabled"
	end

	if context.IsBossSanctuary == true then
		return false, "BossProgressionDisabled"
	end

	local requestedIndex =
		cleanIndex(context.GlobalIslandIndex)

	if not requestedIndex then
		return false, "InvalidGlobalIslandIndex"
	end

	if requestedIndex > totalIslandCount() then
		return false, "OutsideCombatRoute"
	end

	-- FREE ROUTE: no PreviousIslandNotCleared rejection.
	setCurrentIsland(
		requestedIndex,
		context,
		player
	)

	return true, "CombatIslandEnteredFreeRoute"
end

function CombatRouteProgressionService.GetSnapshot()
	local context =
		currentContext
		or getContext(currentIsland)

	local progress, target, alive, cleared, combatState =
		objectiveNumbers(context)

	return {
		Started = started,
		Version = "CombatRouteProgressionFreeV2",
		State = workspace:GetAttribute(
			"DungeonProgressionState"
		),
		Id = CombatRouteProgressionConfig.ObjectiveId,
		Type = "ClearCombatIsland",
		Title = workspace:GetAttribute(
			"DungeonObjectiveTitle"
		),
		Description = workspace:GetAttribute(
			"DungeonObjectiveDescription"
		),
		CurrentGlobalIslandIndex = currentIsland,
		GlobalIslandIndex = currentIsland,
		IslandIndex = currentIsland,
		RoundIndex = nil,
		Progress = progress,
		Target = target,
		Completed = cleared,
		MobAliveCount = alive,
		CombatState = combatState,
		HighestUnlockedIsland = totalIslandCount(),
		TotalIslandCount = totalIslandCount(),
		ExitLocked = false,
		IslandContext = context,
		RouteComplete = routeComplete,
		RewardPendingRound = nil,
		HighestCompletedRound = 0,
		CompletedRounds = {},
		CurrentIslandIsRoundExit = false,
		RoundCompleted = false,
		FinalRewardCommitted = false,
	}
end

function CombatRouteProgressionService.GetCurrentDefinition()
	local snapshot =
		CombatRouteProgressionService.GetSnapshot()

	return {
		Id = snapshot.Id,
		Type = snapshot.Type,
		Title = snapshot.Title,
		Description = snapshot.Description,
		GlobalIslandIndex =
			snapshot.GlobalIslandIndex,
		IslandIndex = snapshot.IslandIndex,
		RoundIndex = nil,
		Target = snapshot.Target,
		Progress = snapshot.Progress,
		MobAliveCount = snapshot.MobAliveCount,
		Completed = snapshot.Completed,
		CombatState = snapshot.CombatState,
		ObjectiveKind = "ClearCombatIsland",
		SpawnProfile = "IslandCombatManaged",
	}
end

function CombatRouteProgressionService.GetCurrentContext()
	return currentContext
		or getContext(currentIsland)
end

function CombatRouteProgressionService.GetHighestUnlockedIsland()
	return totalIslandCount()
end

function CombatRouteProgressionService.IsRouteComplete()
	return routeComplete
end

function CombatRouteProgressionService.EscalateWaypoint()
	local context =
		currentContext
		or getContext(currentIsland)

	if not context then
		return false, "ContextUnavailable"
	end

	local marker =
		context.ObjectiveAnchor
		or context.SafeSpawn
		or context.Exit

	if not marker or not marker.Parent then
		return false, "WaypointUnavailable"
	end

	local position

	if marker:IsA("BasePart") then
		position = marker.Position
	elseif marker:IsA("Model") then
		position = marker:GetPivot().Position
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

function CombatRouteProgressionService.RecoverCurrentIsland()
	local context =
		currentContext
		or getContext(currentIsland)

	requestThrough(
		math.min(
			totalIslandCount(),
			currentIsland
				+ CombatRouteProgressionConfig.FutureLookahead
		)
	)

	if not context then
		return true, "RouteMaterializationRequested"
	end

	watchContext(currentIsland, context)
	publish()

	return true, "CombatIslandRefreshed"
end

return CombatRouteProgressionService
