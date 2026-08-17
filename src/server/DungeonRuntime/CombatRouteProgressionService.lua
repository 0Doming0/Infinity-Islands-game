-- CombatRouteProgressionService: publicador simples da rota linear.
--
-- Responsabilidades restantes:
-- - saber qual e a ilha atual;
-- - publicar progresso da SITUAÇÃO ATUAL para HUD/telemetria;
-- - emitir um unico sinal quando a ilha fica Cleared;
-- - registrar checkpoint/entrada.
--
-- O avanco e o voo pertencem exclusivamente a ManualIslandAdvance.server.luau.
-- RecommendedLevel, free-route gates, rounds e caminhos alternativos nao fazem
-- parte desta autoridade.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.CombatRouteProgressionConfig)
local DungeonSpawnService = require(script.Parent.DungeonSpawnService)

local Service = {}

local VERSION = "LinearCombatRouteProgressionV1"
local started = false
local generation = 0
local options = {}
local currentIsland = 1
local currentContext
local currentConnections = {}
local completed = {}
local clearSerial = 0
local entrySerial = 0
local routeComplete = false

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
		1,
		math.floor(
			tonumber(workspace:GetAttribute("DungeonPlannedCombatIslandCount"))
				or tonumber(workspace:GetAttribute("DungeonRouteIslandCount"))
				or tonumber(workspace:GetAttribute("DungeonCombatRouteTotalIslands"))
				or Config.DefaultTotalIslandCount
				or 1
		)
	)
end

local function getContext(index)
	if type(options.GetIslandContext) ~= "function" then
		return nil
	end
	local ok, context = pcall(options.GetIslandContext, index)
	return ok and type(context) == "table" and context or nil
end

local function requestThrough(index)
	if type(options.RequestRouteThrough) ~= "function" then
		return false
	end
	index = math.clamp(math.floor(tonumber(index) or 1), 1, totalIslandCount())
	local ok = pcall(options.RequestRouteThrough, index)
	return ok
end

local function islandFor(context)
	if type(context) ~= "table" then
		return nil
	end
	local island = context.IslandModel or context.Model
	return typeof(island) == "Instance" and island:IsA("Model") and island or nil
end

local function objectiveNumbers(context)
	local island = islandFor(context)
	if not island then
		return 0, 0, 0, false, "Dormant"
	end

	local target = math.max(0, math.floor(tonumber(
		island:GetAttribute("MobTargetCount")
			or island:GetAttribute("MobKillQuota")
	) or 0))
	local spawned = math.max(0, math.floor(tonumber(island:GetAttribute("MobSpawnedCount")) or 0))
	local alive = math.max(0, math.floor(tonumber(island:GetAttribute("MobAliveCount")) or 0))
	local defeated = math.max(0, math.floor(tonumber(island:GetAttribute("MobDefeatedCount"))
		or math.max(0, spawned - alive)))
	local cleared = island:GetAttribute("Cleared") == true
		or island:GetAttribute("CombatRouteCleared") == true
		or island:GetAttribute("LinearObjectiveComplete") == true
	local combatState = tostring(island:GetAttribute("CombatState") or "Dormant")

	return math.clamp(defeated, 0, math.max(target, defeated)), target, alive, cleared, combatState
end

local function combatActive(state)
	return state == "Active"
		or state == "WaveActive"
		or state == "RespawnCooldown"
end

local function disconnectCurrent()
	for _, connection in ipairs(currentConnections) do
		connection:Disconnect()
	end
	table.clear(currentConnections)
end

local function publish()
	local context = currentContext
	if not islandFor(context) then
		context = getContext(currentIsland)
		if context then
			currentContext = context
		end
	end

	local progress, target, alive, cleared, combatState = objectiveNumbers(context)
	local total = totalIslandCount()
	routeComplete = currentIsland >= total and cleared

	local state
	if routeComplete then
		state = "RouteCompleted"
	elseif cleared then
		state = "ReadyToAdvance"
	elseif combatActive(combatState) then
		state = "CombatActive"
	else
		state = "WaitingForCombat"
	end

	workspace:SetAttribute("DungeonCombatRouteProgressionReady", started)
	workspace:SetAttribute("DungeonCombatRouteProgressionVersion", VERSION)
	workspace:SetAttribute("DungeonProgressionReady", started)
	workspace:SetAttribute("DungeonProgressionVersion", VERSION)
	workspace:SetAttribute("DungeonProgressionState", state)
	workspace:SetAttribute("DungeonRouteProgressionAuthority", "CombatRouteProgressionService")
	workspace:SetAttribute("DungeonRouteEntryPolicy", "LinearClearThenAdvance")
	workspace:SetAttribute("DungeonCombatRouteProgressionPolicy", "LinearClearThenAdvance")

	workspace:SetAttribute("DungeonCurrentObjectiveIsland", currentIsland)
	workspace:SetAttribute("DungeonHighestUnlockedCombatIsland", total)
	workspace:SetAttribute("DungeonCombatRouteTotalIslands", total)
	workspace:SetAttribute("DungeonObjectiveId", Config.ObjectiveId)
	workspace:SetAttribute("DungeonObjectiveType", "ClearCombatIsland")
	workspace:SetAttribute(
		"DungeonObjectiveTitle",
		routeComplete and "ROTA CONCLUÍDA"
			or cleared and "ILHA CONCLUÍDA"
			or Config.ObjectiveTitle
	)
	workspace:SetAttribute(
		"DungeonObjectiveDescription",
		routeComplete and "ROTA CONCLUÍDA"
			or cleared and "TOQUE EM AVANÇAR"
			or Config.ObjectiveDescription
	)
	workspace:SetAttribute("DungeonObjectiveGlobalIslandIndex", currentIsland)
	workspace:SetAttribute("DungeonObjectiveIslandIndex", currentIsland)
	workspace:SetAttribute("DungeonObjectiveRoundIndex", nil)
	workspace:SetAttribute("DungeonObjectiveProgress", progress)
	workspace:SetAttribute("DungeonObjectiveTarget", target)
	workspace:SetAttribute("DungeonObjectiveMobAliveCount", alive)
	workspace:SetAttribute(
		"DungeonObjectiveState",
		cleared and "Completed"
			or combatActive(combatState) and "Active"
			or "Inactive"
	)
	workspace:SetAttribute("DungeonObjectiveExitLocked", false)
	workspace:SetAttribute("DungeonCombatGateError", nil)

	-- Conceito removido da experiencia do jogador.
	workspace:SetAttribute("DungeonCurrentIslandRecommendedLevel", nil)
	workspace:SetAttribute("DungeonRecommendedLevelIsHardGate", false)
	workspace:SetAttribute("DungeonRecommendedLevelWarningActive", false)

	workspace:SetAttribute("DungeonLinearRouteComplete", routeComplete)
	workspace:SetAttribute("DungeonCombatRouteClearSerial", clearSerial)
	workspace:SetAttribute("DungeonCombatRouteEntrySerial", entrySerial)
end

local function emitClear(index, context)
	if completed[index] then
		return
	end
	local island = islandFor(context)
	if not island then
		return
	end
	local _, _, _, cleared = objectiveNumbers(context)
	if not cleared then
		return
	end

	completed[index] = true
	clearSerial += 1

	workspace:SetAttribute("DungeonIslandClearFeedbackSerial", clearSerial)
	workspace:SetAttribute("DungeonIslandClearFeedbackAt", now())
	workspace:SetAttribute("DungeonIslandClearFeedbackIsland", index)
	workspace:SetAttribute("DungeonIslandClearFeedbackNumberedIsland", math.max(0, index - 1))
	workspace:SetAttribute(
		"DungeonIslandClearFeedbackNextIsland",
		index < totalIslandCount() and index + 1 or nil
	)
	workspace:SetAttribute(
		"DungeonIslandClearFeedbackNextNumberedIsland",
		index < totalIslandCount() and index or nil
	)

	island:SetAttribute("Cleared", true)
	island:SetAttribute("CombatRouteCleared", true)
	island:SetAttribute("CombatExitLocked", false)
	island:SetAttribute("RecommendedLevelIsHardGate", false)
	publish()
end

local function bindCurrentContext(context)
	disconnectCurrent()
	currentContext = context
	local island = islandFor(context)
	if not island then
		return false
	end

	island:SetAttribute("CombatExitLocked", false)
	island:SetAttribute("RecommendedLevelIsHardGate", false)

	for _, name in ipairs({
		"Cleared",
		"CombatRouteCleared",
		"LinearObjectiveComplete",
		"CombatState",
		"MobTargetCount",
		"MobKillQuota",
		"MobDefeatedCount",
		"MobSpawnedCount",
		"MobAliveCount",
	}) do
		table.insert(
			currentConnections,
			island:GetAttributeChangedSignal(name):Connect(function()
				if not started then
					return
				end
				emitClear(currentIsland, currentContext)
				publish()
			end)
		)
	end

	task.defer(emitClear, currentIsland, context)
	return true
end

local function commitCheckpoint(context, index)
	local checkpoint = DungeonSpawnService.GetCheckpoint
		and DungeonSpawnService.GetCheckpoint()
		or nil
	local checkpointIndex = type(checkpoint) == "table"
		and cleanIndex(checkpoint.GlobalIslandIndex)
		or nil
	if checkpointIndex and index <= checkpointIndex then
		return
	end
	pcall(
		DungeonSpawnService.CommitLinearRouteCheckpoint,
		context,
		"LinearIslandEntered:" .. tostring(index),
		false
	)
end

local function setCurrentIsland(index, context, player)
	currentIsland = index
	entrySerial += 1
	bindCurrentContext(context)

	local lookahead = math.max(0, math.floor(tonumber(Config.FutureLookahead) or 1))
	requestThrough(math.min(totalIslandCount(), index + lookahead))
	commitCheckpoint(context, index)

	workspace:SetAttribute("DungeonIslandAdvanceEnteredIsland", index)
	workspace:SetAttribute("DungeonIslandAdvanceEnteredAt", now())
	workspace:SetAttribute("DungeonLastAcceptedCombatIsland", index)
	workspace:SetAttribute("DungeonLastAcceptedCombatIslandAt", now())

	if player then
		player:SetAttribute("DungeonCombatRouteEntryAccepted", true)
		player:SetAttribute("DungeonCombatRouteEntryIndex", index)
		player:SetAttribute("DungeonCombatRouteEntryAt", now())
		player:SetAttribute("DungeonRouteRejectedReason", nil)
	end

	emitClear(index, context)
	publish()
end

function Service.Start(startOptions)
	if started then
		return false, "AlreadyStarted"
	end

	started = true
	generation += 1
	options = type(startOptions) == "table" and startOptions or {}
	currentIsland = 1
	currentContext = nil
	completed = {}
	clearSerial = 0
	entrySerial = 0
	routeComplete = false

	workspace:SetAttribute("DungeonRouteEntryPolicy", "LinearClearThenAdvance")
	workspace:SetAttribute("DungeonRecommendedLevelIsHardGate", false)
	workspace:SetAttribute("DungeonRecommendedLevelWarningActive", false)
	workspace:SetAttribute("DungeonObjectiveExitLocked", false)

	local lookahead = math.max(0, math.floor(tonumber(Config.FutureLookahead) or 1))
	requestThrough(math.min(totalIslandCount(), 1 + lookahead))
	local initial = getContext(1)
	if initial then
		bindCurrentContext(initial)
	end
	publish()

	local token = generation
	task.spawn(function()
		while started and generation == token do
			local latest = getContext(currentIsland)
			if latest and islandFor(latest) ~= islandFor(currentContext) then
				bindCurrentContext(latest)
			end
			emitClear(currentIsland, currentContext)
			publish()
			task.wait(math.max(0.15, tonumber(Config.ReconcileSeconds) or 0.5))
		end
	end)

	return true
end

function Service.Stop()
	if not started then
		return false
	end
	started = false
	generation += 1
	disconnectCurrent()
	options = {}
	publish()
	return true
end

function Service.HandleIslandEntered(player, context)
	if not started
		or not player
		or player.Parent ~= Players
		or type(context) ~= "table"
	then
		return false, "InvalidRouteEntry"
	end

	local index = cleanIndex(context.GlobalIslandIndex)
	if not index or index > totalIslandCount() then
		return false, "InvalidGlobalIslandIndex"
	end
	if context.IsOptionalRoute == true or context.IsBossSanctuary == true then
		return false, "OutsideLinearCombatRoute"
	end

	setCurrentIsland(index, context, player)
	return true, "LinearCombatIslandEntered"
end

function Service.GetSnapshot()
	local context = currentContext or getContext(currentIsland)
	local progress, target, alive, cleared, combatState = objectiveNumbers(context)
	return {
		Started = started,
		Version = VERSION,
		State = workspace:GetAttribute("DungeonProgressionState"),
		Id = Config.ObjectiveId,
		Type = "ClearCombatIsland",
		Title = workspace:GetAttribute("DungeonObjectiveTitle"),
		Description = workspace:GetAttribute("DungeonObjectiveDescription"),
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

function Service.GetCurrentDefinition()
	local snapshot = Service.GetSnapshot()
	return {
		Id = snapshot.Id,
		Type = snapshot.Type,
		Title = snapshot.Title,
		Description = snapshot.Description,
		GlobalIslandIndex = snapshot.GlobalIslandIndex,
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

function Service.GetCurrentContext()
	return currentContext or getContext(currentIsland)
end

function Service.GetHighestUnlockedIsland()
	return totalIslandCount()
end

function Service.IsRouteComplete()
	return routeComplete
end

function Service.EscalateWaypoint()
	local context = Service.GetCurrentContext()
	if not context then
		return false, "ContextUnavailable"
	end
	local marker = context.ObjectiveAnchor or context.SafeSpawn or context.Exit
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
	workspace:SetAttribute("DungeonObjectiveWaypointPosition", position)
	workspace:SetAttribute("DungeonObjectiveWaypointTarget", marker:GetFullName())
	workspace:SetAttribute("DungeonObjectiveWaypointEscalated", true)
	workspace:SetAttribute(
		"DungeonObjectiveWaypointSerial",
		(tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
	)
	return true
end

function Service.RecoverCurrentIsland()
	local lookahead = math.max(0, math.floor(tonumber(Config.FutureLookahead) or 1))
	requestThrough(math.min(totalIslandCount(), currentIsland + lookahead))
	local context = getContext(currentIsland)
	if not context then
		return true, "RouteMaterializationRequested"
	end
	bindCurrentContext(context)
	emitClear(currentIsland, context)
	publish()
	return true, "CombatIslandRefreshed"
end

return Service
