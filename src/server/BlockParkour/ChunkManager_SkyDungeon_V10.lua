--[[
	Sky Dungeon - fronteira vertical reativa em rounds de ilhas.

	Cada ilha continua sendo um no compartilhado da malha, mas uma geracao cria
	dois niveis inteiros de escolhas. O round seguinte comeca por proximidade,
	antes de o jogador pisar na ilha de fronteira, mas somente quando movimento,
	direcao e progresso confirmam a intencao. Assim o horizonte permanece cheio
	sem gerar camadas enquanto o jogador esta parado.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config_SkyDungeon_V10)
local Generator = require(script.Parent.Generator_SkyDungeon_V10_Deterministic)
local IslandGraphPlanner = require(script.Parent.IslandGraphPlanner)
local CollectiveProgressService = require(script.Parent.CollectiveProgressService)
local SpatialHash = require(script.Parent.SpatialHash)

local ChunkManager = {}

local running = false
local worldModel
local nodesFolder
local connectionsFolder
local baseSeed = 0
local nodeSerial = 0
local totalNodeCount = 0
local totalEdgeCount = 0
local activeNodeCount = 0
local activeEdgeCount = 0
local removedNodeCount = 0
local removedEdgeCount = 0
local highestGeneratedY = Config.CENTER_WORLD.Y
local highestLogicalLevel = 0
local levelWorldY = {}
local latestWaterY = Config.CENTER_WORLD.Y - 100000
local physicalWorldOffsetY = 0
local logicalAltitudeOffset = 0
local worldRebaseSerial = 0
local generationRoundSerial = 0
local completedGenerationRounds = 0
local nodesByKey = {}
local edgesByKey = {}
local outgoingEdgesBySource = {}
local expansionQueue = {}
local queuedForExpansion = {}
local detailQueue = {}
local queuedForDetail = {}
local detailWorkerRunning = false
local detailOperationActive = false
local geometryOperationActive = false
local lastGeometryOperationAt = -math.huge
local enqueueDetail
local spatialIndex = SpatialHash.new(Config.FRONTIER_SPATIAL_HASH_CELL_STUDS)
local activeSimulationRecords = {}
local lastWorldAttributeUpdateAt = -math.huge
local playerVisitedNodes = setmetatable({}, { __mode = "k" })
local playerApproachIntents = setmetatable({}, { __mode = "k" })
local latestCollectiveSnapshot = {
	Count = 0,
	MeanY = nil,
	MedianY = nil,
	LowerGroupY = nil,
}

local function countRecords(records)
	local count = 0
	for _ in pairs(records) do
		count += 1
	end
	return count
end

local function getAlivePlayerRoots()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			table.insert(result, { Player = player, Root = root, Humanoid = humanoid })
		end
	end
	return result
end

local function validateConfig()
	assert(Config.ENABLE_ISLAND_FRONTIER_WORLD, "[SkyDungeon] A fronteira por ilha esta desativada.")
	assert(Config.FRONTIER_DISCOVERY_POLL_SECONDS >= 0.1, "Intervalo de descoberta muito baixo.")
	assert(Config.FRONTIER_ROUND_DEPTH_LEVELS >= 1, "Um round precisa gerar pelo menos um nivel.")
	assert(Config.FRONTIER_APPROACH_DISTANCE_STUDS > 0, "Distancia de aproximacao invalida.")
	assert(Config.FRONTIER_APPROACH_VERTICAL_MARGIN_STUDS > 0, "Margem vertical de aproximacao invalida.")
	assert(Config.FRONTIER_INTENT_SUSTAIN_SECONDS > 0, "Tempo de intencao invalido.")
	assert(Config.FRONTIER_INTENT_MIN_PROGRESS_STUDS > 0, "Progresso minimo de intencao invalido.")
	assert(Config.FRONTIER_INTENT_MIN_MOVE_SPEED_STUDS >= 0, "Velocidade minima de intencao invalida.")
	assert(Config.FRONTIER_INTENT_MIN_ALIGNMENT >= -1 and Config.FRONTIER_INTENT_MIN_ALIGNMENT <= 1)
	assert(Config.FRONTIER_MAX_GEOMETRY_OPERATIONS_PER_FRAME >= 1)
	assert(Config.FRONTIER_GEOMETRY_PARTS_PER_FRAME >= 1)
	assert(Config.FRONTIER_GENERATION_TIME_BUDGET_SECONDS > 0)
	assert(Config.FRONTIER_DETAIL_YIELD_EVERY_CLONES >= 1)
	assert(Config.FRONTIER_DETAIL_TIME_BUDGET_SECONDS > 0)
	assert(Config.FRONTIER_SPATIAL_HASH_CELL_STUDS > 0)
	assert(Config.FRONTIER_SPATIAL_QUERY_PADDING_STUDS > 0)
	assert(Config.FRONTIER_DIAGNOSTIC_UPDATE_SECONDS >= 0.1)
	assert(Config.FRONTIER_MAX_ACTIVE_ISLANDS >= 32)
	assert(Config.FRONTIER_SIMULATION_UPDATE_SECONDS >= 0.1)
	assert(Config.FRONTIER_SIMULATION_ACTIVATION_DISTANCE_STUDS > 0)
	assert(
		Config.FRONTIER_SIMULATION_DEACTIVATION_DISTANCE_STUDS
			>= Config.FRONTIER_SIMULATION_ACTIVATION_DISTANCE_STUDS,
		"O raio de desativacao da simulacao precisa ser maior ou igual ao de ativacao."
	)
	assert(Config.WORLD_REBASE_TRIGGER_Y > Config.WORLD_REBASE_SHIFT_STUDS)
	assert(Config.WORLD_REBASE_SHIFT_STUDS % Config.GRID_SIZE == 0)
	IslandGraphPlanner.ValidateConfig()
end

local function countFrontierNodes()
	local count = 0
	for _, record in pairs(nodesByKey) do
		if not record.Expanded and record.Model and record.Model.Parent then
			count += 1
		end
	end
	return count
end

local function countConvergences()
	local count = 0
	for _, record in pairs(nodesByKey) do
		if record.InboundCount >= 2 then
			count += 1
		end
	end
	return count
end

local function countSanctuaries()
	local count = 0
	for _, record in pairs(nodesByKey) do
		if record.Spec.IsSanctuary then
			count += 1
		end
	end
	return count
end

local function countActiveSimulations()
	local count = 0
	for _, record in pairs(nodesByKey) do
		if record.SimulationActive then
			count += 1
		end
	end
	return count
end

local function updateWorldAttributes(force)
	if not worldModel then
		return
	end
	local now = os.clock()
	if not force and now - lastWorldAttributeUpdateAt < Config.FRONTIER_DIAGNOSTIC_UPDATE_SECONDS then
		return
	end
	lastWorldAttributeUpdateAt = now
	worldModel:SetAttribute("BaseSeed", baseSeed)
	worldModel:SetAttribute("GenerationUnit", "IslandRound")
	worldModel:SetAttribute("GenerationMode", "IntentTriggeredIslandRounds")
	worldModel:SetAttribute("GenerationRoundDepth", Config.FRONTIER_ROUND_DEPTH_LEVELS)
	worldModel:SetAttribute("GeneratedIslandRoundCount", completedGenerationRounds)
	worldModel:SetAttribute("ChunkCount", totalNodeCount)
	worldModel:SetAttribute("RoundCount", highestLogicalLevel)
	worldModel:SetAttribute("ActiveChunkCount", activeNodeCount)
	worldModel:SetAttribute("ActiveRoundCount", activeNodeCount)
	worldModel:SetAttribute("ActiveIslandCount", activeNodeCount)
	worldModel:SetAttribute("ActiveConnectionCount", activeEdgeCount)
	worldModel:SetAttribute("TotalIslandCount", totalNodeCount)
	worldModel:SetAttribute("TotalConnectionCount", totalEdgeCount)
	worldModel:SetAttribute("RemovedChunkCount", removedNodeCount)
	worldModel:SetAttribute("RemovedIslandCount", removedNodeCount)
	worldModel:SetAttribute("RemovedConnectionCount", removedEdgeCount)
	worldModel:SetAttribute("FrontierIslandCount", countFrontierNodes())
	worldModel:SetAttribute("ConvergenceIslandCount", countConvergences())
	worldModel:SetAttribute("SanctuaryCount", countSanctuaries())
	worldModel:SetAttribute("ActiveSimulationIslandCount", countActiveSimulations())
	worldModel:SetAttribute("HighestLogicalLevel", highestLogicalLevel)
	worldModel:SetAttribute("HighestGeneratedY", highestGeneratedY)
	worldModel:SetAttribute("LogicalHighestGeneratedY", highestGeneratedY + logicalAltitudeOffset)
	worldModel:SetAttribute("LatestWaterY", latestWaterY)
	worldModel:SetAttribute("CollectivePlayerCount", latestCollectiveSnapshot.Count or 0)
	worldModel:SetAttribute("CollectiveMeanY", latestCollectiveSnapshot.MeanY or 0)
	worldModel:SetAttribute("CollectiveLowerGroupY", latestCollectiveSnapshot.LowerGroupY or 0)
	worldModel:SetAttribute("WorldPhysicalYOffsetStuds", physicalWorldOffsetY)
	worldModel:SetAttribute("LogicalAltitudeOffsetStuds", logicalAltitudeOffset)
	worldModel:SetAttribute("WorldRebaseSerial", worldRebaseSerial)
	worldModel:SetAttribute("ExpansionQueueLength", #expansionQueue)
	worldModel:SetAttribute("DetailQueueLength", #detailQueue)
	worldModel:SetAttribute("SpatialIndexMode", "HorizontalHash")
	worldModel:SetAttribute("SpatialIndexedIslandCount", countRecords(spatialIndex.Entries))
	worldModel:SetAttribute("EffectCullingEnabled", Config.FRONTIER_EFFECT_CULLING_ENABLED)
	worldModel:SetAttribute("EffectCullingUpdateSeconds", Config.FRONTIER_EFFECT_CULLING_UPDATE_SECONDS)
	worldModel:SetAttribute("EffectCullingMaxDistanceStuds", Config.FRONTIER_EFFECT_CULLING_MAX_DISTANCE_STUDS)
	worldModel:SetAttribute(
		"EffectCullingForceActiveDistanceStuds",
		Config.FRONTIER_EFFECT_CULLING_FORCE_ACTIVE_DISTANCE_STUDS
	)
	worldModel:SetAttribute("EffectCullingScreenMarginPixels", Config.FRONTIER_EFFECT_CULLING_SCREEN_MARGIN_PIXELS)
	worldModel:SetAttribute("MysteryDistanceEnabled", Config.FRONTIER_MYSTERY_DISTANCE_ENABLED)
	worldModel:SetAttribute("MysteryFocusDistanceStuds", Config.FRONTIER_MYSTERY_FOCUS_DISTANCE_STUDS)
	worldModel:SetAttribute("MysteryInFocusRadiusStuds", Config.FRONTIER_MYSTERY_IN_FOCUS_RADIUS_STUDS)
	worldModel:SetAttribute("MysteryFarIntensity", Config.FRONTIER_MYSTERY_FAR_INTENSITY)
end

local function prepareWorld()
	local oldWorld = workspace:FindFirstChild(Config.WORLD_MODEL_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end
	local oldSingleMap = workspace:FindFirstChild(Config.MODEL_NAME)
	if oldSingleMap then
		oldSingleMap:Destroy()
	end

	physicalWorldOffsetY = 0
	logicalAltitudeOffset = 0
	worldRebaseSerial = 0
	workspace:SetAttribute("WorldPhysicalYOffsetStuds", 0)
	workspace:SetAttribute("LogicalAltitudeOffsetStuds", 0)
	workspace:SetAttribute("WorldRebaseSerial", 0)
	workspace:SetAttribute("LastWorldRebaseShiftStuds", 0)

	worldModel = Instance.new("Model")
	worldModel.Name = Config.WORLD_MODEL_NAME
	worldModel:SetAttribute("DynamicChunksEnabled", true)
	worldModel:SetAttribute("GridSize", Config.GRID_SIZE)
	worldModel.Parent = workspace

	nodesFolder = Instance.new("Folder")
	nodesFolder.Name = "IslandNodes"
	nodesFolder.Parent = worldModel
	connectionsFolder = Instance.new("Folder")
	connectionsFolder.Name = "IslandConnections"
	connectionsFolder.Parent = worldModel
end

local function createNode(spec, reason)
	local existing = nodesByKey[spec.Key]
	if existing then
		return existing, false
	end
	if activeNodeCount >= Config.FRONTIER_MAX_ACTIVE_ISLANDS then
		return nil, false, "limite de ilhas ativas atingido"
	end

	nodeSerial += 1
	local model, metadata = Generator.CreateFrontierNode(nodesFolder, spec, {
		NodeSerial = nodeSerial,
		DeferRuntimeContent = true,
		DeferVisualContent = true,
	})
	model:SetAttribute("GenerationReason", reason or "Unknown")
	model:SetAttribute("NodeSerial", nodeSerial)
	CollectionService:AddTag(model, "BlockParkourChunk")
	CollectionService:AddTag(model, "SkyDungeonIslandNode")
	local record = {
		Key = spec.Key,
		Spec = spec,
		Model = model,
		IslandModel = metadata.IslandModel,
		Floor = metadata.IslandModel.PrimaryPart,
		BoundsCFrame = metadata.BoundsCFrame,
		BoundsSize = metadata.BoundsSize,
		BottomWorldY = metadata.BottomWorldY,
		TopWorldY = metadata.TopWorldY,
		Discovered = false,
		Expanded = false,
		Expanding = false,
		ContentActivated = false,
		VisualContentPopulated = false,
		SimulationActive = false,
		InboundCount = 0,
		OutboundCount = 0,
		CreatedAt = os.clock(),
	}
	nodesByKey[spec.Key] = record
	spatialIndex:Insert(spec.Key, record.Floor.Position, record)
	activeNodeCount += 1
	totalNodeCount += 1
	highestGeneratedY = math.max(highestGeneratedY, record.TopWorldY)
	highestLogicalLevel = math.max(highestLogicalLevel, spec.Level)
	levelWorldY[spec.Level] = levelWorldY[spec.Level] or record.Floor.Position.Y
	if spec.IsSanctuary then
		CollectionService:AddTag(model, "SkyDungeonSanctuary")
	end
	updateWorldAttributes()
	return record, true
end

local function destroyOrphanNode(record)
	if not record or record.InboundCount > 0 or record.Spec.IsStart then
		return
	end
	if record.Model and record.Model.Parent then
		record.Model:Destroy()
	end
	nodesByKey[record.Key] = nil
	spatialIndex:Remove(record.Key)
	activeSimulationRecords[record.Key] = nil
	activeNodeCount -= 1
	removedNodeCount += 1
end

local function createEdge(source, target, directionId)
	local plan = IslandGraphPlanner.PlanConnection(source.Spec, target.Spec, directionId)
	local existing = edgesByKey[plan.Key]
	if existing then
		return existing, false
	end
	local publishedParts = 0
	local sliceStartedAt = os.clock()
	local function yieldGeometrySlice()
		publishedParts += 1
		if publishedParts >= Config.FRONTIER_GEOMETRY_PARTS_PER_FRAME
			or os.clock() - sliceStartedAt >= Config.FRONTIER_GENERATION_TIME_BUDGET_SECONDS
		then
			lastGeometryOperationAt = os.clock()
			RunService.Heartbeat:Wait()
			publishedParts = 0
			sliceStartedAt = os.clock()
		end
	end
	geometryOperationActive = true
	local success, modelOrError, metadata = pcall(Generator.CreateFrontierConnection, connectionsFolder, plan, {
		LogicalLevel = target.Spec.Level,
		PathId = source.OutboundCount + 1,
		ReservationParent = worldModel,
		SkipExternalReservationScan = true,
		DeferVisualContent = true,
		Seed = target.Spec.Seed,
		YieldCallback = yieldGeometrySlice,
	})
	geometryOperationActive = false
	if not success then
		error(modelOrError, 0)
	end
	local model = modelOrError
	model:SetAttribute("Seed", target.Spec.Seed)
	CollectionService:AddTag(model, "SkyDungeonFrontierConnection")
	CollectionService:AddTag(model, "SkyDungeonRound")
	local record = {
		Key = plan.Key,
		Plan = plan,
		Model = model,
		SourceKey = source.Key,
		TargetKey = target.Key,
		BottomWorldY = metadata.BottomWorldY,
		TopWorldY = metadata.TopWorldY,
		BoundsCFrame = metadata.BoundsCFrame,
		BoundsSize = metadata.BoundsSize,
	}
	edgesByKey[plan.Key] = record
	local outgoing = outgoingEdgesBySource[source.Key]
	if not outgoing then
		outgoing = {}
		outgoingEdgesBySource[source.Key] = outgoing
	end
	outgoing[plan.Key] = record
	source.OutboundCount += 1
	target.InboundCount += 1
	source.Model:SetAttribute("OutboundConnectionCount", source.OutboundCount)
	target.Model:SetAttribute("InboundConnectionCount", target.InboundCount)
	if target.InboundCount >= 2 then
		target.Model:SetAttribute("IsConvergence", true)
		CollectionService:AddTag(target.Model, "SkyDungeonConvergence")
	end
	activeEdgeCount += 1
	totalEdgeCount += 1
	return record, true
end

local function activateContent(record, yieldCallback)
	if record.ContentActivated or not record.Model or not record.Model.Parent then
		return false
	end
	record.ContentActivated = true
	record.Model:SetAttribute("SectorActivated", true)
	local success, errorMessage = pcall(Generator.PopulateRuntimeContent, record.Model, yieldCallback)
	if not success then
		record.ContentActivated = false
		warn(string.format("[SkyDungeon] Conteudo de %s falhou: %s", record.Key, tostring(errorMessage)))
		return false
	end
	CollectionService:AddTag(record.Model, "SkyDungeonRound")
	return true
end

local function chooseBestDetailJob()
	local bestIndex
	local bestJob
	for index, job in ipairs(detailQueue) do
		if not bestJob
			or job.Priority > bestJob.Priority
			or (job.Priority == bestJob.Priority and job.CreatedAt < bestJob.CreatedAt)
		then
			bestIndex = index
			bestJob = job
		end
	end
	if not bestIndex then
		return nil
	end
	table.remove(detailQueue, bestIndex)
	queuedForDetail[bestJob.Key] = nil
	return bestJob
end

local function getBestDetailPriority()
	local priority = -math.huge
	for _, job in ipairs(detailQueue) do
		priority = math.max(priority, job.Priority)
	end
	return priority
end

enqueueDetail = function(record, needsRuntime, priority)
	if not record or not record.Model or not record.Model.Parent then
		return false
	end
	if record.VisualContentPopulated and (not needsRuntime or record.ContentActivated) then
		return false
	end
	local existing = queuedForDetail[record.Key]
	if existing then
		existing.NeedsRuntime = existing.NeedsRuntime or needsRuntime == true
		existing.Priority = math.max(existing.Priority, priority or 0)
		return false
	end
	local job = {
		Key = record.Key,
		NeedsRuntime = needsRuntime == true,
		Priority = priority or 0,
		CreatedAt = os.clock(),
	}
	queuedForDetail[record.Key] = job
	table.insert(detailQueue, job)
	updateWorldAttributes()
	return true
end

local function processDetailJob(job)
	local record = nodesByKey[job.Key]
	if not record or not record.Model or not record.Model.Parent then
		return
	end
	local clonesSinceYield = 0
	local sliceStartedAt = os.clock()
	local function yieldBetweenClones()
		clonesSinceYield += 1
		if clonesSinceYield >= Config.FRONTIER_DETAIL_YIELD_EVERY_CLONES
			or os.clock() - sliceStartedAt >= Config.FRONTIER_DETAIL_TIME_BUDGET_SECONDS
		then
			clonesSinceYield = 0
			RunService.Heartbeat:Wait()
			sliceStartedAt = os.clock()
		end
	end
	if not record.VisualContentPopulated then
		local success, resultOrError = pcall(
			Generator.PopulateDeferredVisualContent,
			record.Model,
			yieldBetweenClones
		)
		if not success then
			record.Model:SetAttribute("VisualContentPopulating", false)
			warn(string.format("[SkyDungeon] Detalhes visuais de %s falharam: %s", record.Key, tostring(resultOrError)))
			task.delay(1, function()
				if running and nodesByKey[record.Key] == record then
					enqueueDetail(record, job.NeedsRuntime, job.Priority)
				end
			end)
			return
		end
		record.VisualContentPopulated = resultOrError == true
	end
	if job.NeedsRuntime and not record.ContentActivated then
		activateContent(record, yieldBetweenClones)
	end
end

local function startDetailWorker()
	if detailWorkerRunning then
		return
	end
	detailWorkerRunning = true
	task.spawn(function()
		while running do
			-- Geometria vital vence detalhes distantes. Conteudo de uma ilha ja
			-- tocada recebe prioridade alta e pausa brevemente a geometria; os dois
			-- workers nunca publicam Instances pesadas no mesmo frame.
			if geometryOperationActive or (#expansionQueue > 0 and getBestDetailPriority() < 40000) then
				RunService.Heartbeat:Wait()
			else
				local job = chooseBestDetailJob()
				if job then
					detailOperationActive = true
					if os.clock() - lastGeometryOperationAt < 0.012 then
						RunService.Heartbeat:Wait()
					end
					local success, errorMessage = pcall(processDetailJob, job)
					detailOperationActive = false
					if not success then
						warn(string.format("[SkyDungeon] Worker de detalhes falhou em %s: %s", job.Key, tostring(errorMessage)))
					end
					updateWorldAttributes()
				else
					task.wait(Config.FRONTIER_DETAIL_IDLE_SECONDS)
				end
			end
		end
		detailWorkerRunning = false
		detailOperationActive = false
	end)
end

local function enqueueExpansion(record, reason, priority)
	local existingJob = queuedForExpansion[record.Key]
	if existingJob then
		existingJob.Priority = math.max(existingJob.Priority, priority or 0)
		return false
	end
	if record.Expanded or record.Expanding or record.ScheduledExpansionRoundId then
		return false
	end
	if record.NextExpansionRetryAt and os.clock() < record.NextExpansionRetryAt then
		return false
	end
	generationRoundSerial += 1
	local roundId = generationRoundSerial
	record.ScheduledExpansionRoundId = roundId
	record.Model:SetAttribute("ScheduledGenerationRoundId", roundId)
	local job = {
		Id = roundId,
		RootKey = record.Key,
		Reason = reason or "Unknown",
		Priority = priority or 0,
		TargetDepth = Config.FRONTIER_ROUND_DEPTH_LEVELS,
		CurrentDepth = 1,
		CurrentKeys = { record.Key },
		CurrentIndex = 1,
		NextKeys = {},
		NextKeySet = {},
		ScheduledKeys = { [record.Key] = true },
		ExpandedSourceCount = 0,
		FailedSourceCount = 0,
		CreatedAt = os.clock(),
	}
	queuedForExpansion[record.Key] = job
	table.insert(expansionQueue, job)
	updateWorldAttributes()
	return true
end

local function getOutgoingTargets(record)
	local result = {}
	local seen = {}
	for _, edge in pairs(outgoingEdgesBySource[record.Key] or {}) do
		if not seen[edge.TargetKey] then
			local target = nodesByKey[edge.TargetKey]
			if target and target.Model and target.Model.Parent then
				seen[edge.TargetKey] = true
				table.insert(result, target)
			end
		end
	end
	table.sort(result, function(a, b)
		return a.Key < b.Key
	end)
	return result
end

local function finishNodeExpansion(record, work)
	record.Expanding = false
	record.ExpansionWork = nil
	record.Expanded = work.SuccessfulConnections >= Config.FRONTIER_MIN_OUTGOING_CONNECTIONS
	record.Model:SetAttribute("Expanded", record.Expanded)
	record.Model:SetAttribute("ExpansionState", record.Expanded and "Expanded" or "RetryPending")
	record.Model:SetAttribute("ExpansionChoiceCount", work.SuccessfulConnections)
	if not record.Expanded then
		record.NextExpansionRetryAt = os.clock() + 5
		warn(string.format(
			"[SkyDungeon] %s gerou apenas %d conexao(oes): %s",
			record.Key,
			work.SuccessfulConnections,
			table.concat(work.Errors, " | ")
		))
	end
	return record.Expanded and "Done" or "Failed", work.ChildRecords, false
end

local function beginNodeExpansion(record)
	local planned = IslandGraphPlanner.GetExpansionDirections(baseSeed, record.Spec)
	local directions = {}
	local seen = {}
	for _, direction in ipairs(planned) do
		seen[direction.Id] = true
		table.insert(directions, direction)
	end
	local plannedCount = #directions
	-- Direcoes restantes sao fallback e so serao usadas se alguma escolha
	-- planejada falhar. A ordem continua deterministica.
	for _, direction in ipairs(IslandGraphPlanner.GetDirections()) do
		if not seen[direction.Id] then
			seen[direction.Id] = true
			table.insert(directions, direction)
		end
	end
	record.Expanding = true
	record.Model:SetAttribute("ExpansionState", "Expanding")
	record.ExpansionWork = {
		Directions = directions,
		PlannedCount = plannedCount,
		DirectionIndex = 1,
		PendingChild = nil,
		SuccessfulConnections = 0,
		ChildRecords = {},
		ChildRecordSet = {},
		Errors = {},
	}
	return record.ExpansionWork
end

-- Executa somente uma operacao pesada: criar uma ilha OU criar sua conexao.
-- O estado fica no record para continuar no Heartbeat seguinte.
local function stepNodeExpansion(record)
	if not record or not record.Model or not record.Model.Parent then
		return "Failed", {}, false
	end
	if record.Expanded then
		return "Done", getOutgoingTargets(record), false
	end
	local work = record.ExpansionWork or beginNodeExpansion(record)
	if work.PendingChild then
		local pending = work.PendingChild
		work.PendingChild = nil
		local success, edgeOrError = pcall(createEdge, record, pending.Record, pending.Direction.Id)
		if success then
			work.SuccessfulConnections += 1
			if not work.ChildRecordSet[pending.Record.Key] then
				work.ChildRecordSet[pending.Record.Key] = true
				table.insert(work.ChildRecords, pending.Record)
			end
			enqueueDetail(pending.Record, false, math.max(1, 1000 - pending.Record.Spec.Level))
		else
			table.insert(work.Errors, pending.Direction.Id .. ": " .. tostring(edgeOrError))
			if pending.Created then
				destroyOrphanNode(pending.Record)
			end
		end
		if work.DirectionIndex > work.PlannedCount
			and work.SuccessfulConnections >= Config.FRONTIER_MIN_OUTGOING_CONNECTIONS
		then
			return finishNodeExpansion(record, work)
		end
		return "Working", {}, true
	end

	if work.DirectionIndex > #work.Directions
		or (work.DirectionIndex > work.PlannedCount
			and work.SuccessfulConnections >= Config.FRONTIER_MIN_OUTGOING_CONNECTIONS)
	then
		return finishNodeExpansion(record, work)
	end
	local direction = work.Directions[work.DirectionIndex]
	work.DirectionIndex += 1
	local childSpec = IslandGraphPlanner.GetChildSpec(baseSeed, record.Spec, direction.Id)
	local child, created, creationError = createNode(childSpec, "DiscoveredFrom:" .. record.Key)
	if not child then
		table.insert(work.Errors, direction.Id .. ": " .. tostring(creationError))
		return "Working", {}, true
	end
	work.PendingChild = {
		Record = child,
		Created = created,
		Direction = direction,
	}
	return "Working", {}, true
end

local function releaseGenerationRound(job, completed)
	for key in pairs(job.ScheduledKeys) do
		local record = nodesByKey[key]
		if record and record.ScheduledExpansionRoundId == job.Id then
			record.ScheduledExpansionRoundId = nil
			if record.Model and record.Model.Parent then
				record.Model:SetAttribute("ScheduledGenerationRoundId", nil)
			end
		end
	end
	queuedForExpansion[job.RootKey] = nil
	local root = nodesByKey[job.RootKey]
	if root and root.Model and root.Model.Parent then
		root.Model:SetAttribute("LastGenerationRoundId", job.Id)
		root.Model:SetAttribute("LastGenerationRoundComplete", completed)
		root.Model:SetAttribute("LastGenerationRoundReason", job.Reason)
		root.Model:SetAttribute("LastGenerationRoundSourceCount", job.ExpandedSourceCount)
	end
	if completed then
		completedGenerationRounds += 1
	end
end

local function addNextRoundNode(job, child)
	if job.NextKeySet[child.Key] then
		return
	end
	job.NextKeySet[child.Key] = true
	table.insert(job.NextKeys, child.Key)
	-- Inclusive as ilhas da borda final ficam reservadas ate o round terminar.
	-- Isso impede outro round de abrir enquanto os caminhos deste horizonte ainda
	-- estao sendo materializados.
	if not child.Expanded and not child.ScheduledExpansionRoundId then
		child.ScheduledExpansionRoundId = job.Id
		child.Model:SetAttribute("ScheduledGenerationRoundId", job.Id)
		job.ScheduledKeys[child.Key] = true
	end
	if child.Model:GetAttribute("FirstGenerationRoundId") == nil then
		child.Model:SetAttribute("FirstGenerationRoundId", job.Id)
		child.Model:SetAttribute("GenerationRoundRootKey", job.RootKey)
		child.Model:SetAttribute("GenerationRoundDepth", job.CurrentDepth)
	end
end

local function chooseBestExpansionJob()
	local bestIndex
	local bestJob
	for index, job in ipairs(expansionQueue) do
		if not bestJob
			or job.Priority > bestJob.Priority
			or (job.Priority == bestJob.Priority and job.CreatedAt < bestJob.CreatedAt)
		then
			bestIndex = index
			bestJob = job
		end
	end
	return bestIndex, bestJob
end

local function processExpansionQueue()
	local processed = 0
	local startedAt = os.clock()
	while processed < Config.FRONTIER_MAX_GEOMETRY_OPERATIONS_PER_FRAME and #expansionQueue > 0 do
		local jobIndex, job = chooseBestExpansionJob()
		if not job then
			break
		end
		local key = job.CurrentKeys[job.CurrentIndex]
		if key then
			local record = nodesByKey[key]
			if record then
				local state, children, performedOperation = stepNodeExpansion(record)
				if performedOperation then
					processed += 1
				end
				if state == "Done" then
					job.CurrentIndex += 1
					job.ExpandedSourceCount += 1
					for _, child in ipairs(children) do
						addNextRoundNode(job, child)
					end
				elseif state == "Failed" then
					job.CurrentIndex += 1
					job.FailedSourceCount += 1
				end
			else
				job.CurrentIndex += 1
				job.FailedSourceCount += 1
			end
		else
			if job.CurrentDepth < job.TargetDepth and #job.NextKeys > 0 then
				table.sort(job.NextKeys)
				job.CurrentDepth += 1
				job.CurrentKeys = job.NextKeys
				job.CurrentIndex = 1
				job.NextKeys = {}
				job.NextKeySet = {}
			else
				releaseGenerationRound(job, job.FailedSourceCount == 0)
				table.remove(expansionQueue, jobIndex)
			end
		end
		if processed > 0 and os.clock() - startedAt >= Config.FRONTIER_GENERATION_TIME_BUDGET_SECONDS then
			break
		end
	end
	updateWorldAttributes()
	return processed
end

local function pointInsideIsland(record, position, horizontalPadding, verticalPadding)
	local floor = record.Floor
	if not floor or not floor.Parent then
		return false
	end
	local localPoint = floor.CFrame:PointToObjectSpace(position)
	local surfaceY = floor.Size.Y / 2
	return math.abs(localPoint.X) <= floor.Size.X / 2 + horizontalPadding
		and math.abs(localPoint.Z) <= floor.Size.Z / 2 + horizontalPadding
		and localPoint.Y >= surfaceY - verticalPadding
		and localPoint.Y <= surfaceY + verticalPadding + 5
end

local function horizontalDistanceToFloor(record, position)
	local floor = record.Floor
	if not floor or not floor.Parent then
		return math.huge
	end
	local localPoint = floor.CFrame:PointToObjectSpace(position)
	local dx = math.max(0, math.abs(localPoint.X) - floor.Size.X / 2)
	local dz = math.max(0, math.abs(localPoint.Z) - floor.Size.Z / 2)
	return math.sqrt(dx * dx + dz * dz)
end

local function queryNearbyRecords(position, radius)
	return spatialIndex:QueryRadius(
		position,
		radius + Config.FRONTIER_SPATIAL_QUERY_PADDING_STUDS
	)
end

local function setRecordSimulationActive(record, isActive)
	if record.SimulationActive == isActive then
		return false
	end
	record.SimulationActive = isActive
	if isActive then
		activeSimulationRecords[record.Key] = record
	else
		activeSimulationRecords[record.Key] = nil
	end
	record.Model:SetAttribute("SimulationActive", isActive)
	record.IslandModel:SetAttribute("SimulationActive", isActive)
	for _, descendant in ipairs(record.IslandModel:GetDescendants()) do
		if descendant:IsA("Model") and (
			descendant:GetAttribute("RuntimeMonster") == true
				or CollectionService:HasTag(descendant, "CombatTarget")
		) then
			descendant:SetAttribute("SimulationActive", isActive)
			if not isActive then
				local humanoid = descendant:FindFirstChildWhichIsA("Humanoid", true)
				local root = descendant:FindFirstChild("HumanoidRootPart", true)
					or descendant.PrimaryPart
				if humanoid and root and root:IsA("BasePart") then
					humanoid:MoveTo(root.Position)
					humanoid:Move(Vector3.zero)
				end
			end
		end
	end
	return true
end

local function updateSimulationActivity(playerRoots)
	local changed = false
	local shouldRemainActive = {}
	for _, entry in ipairs(playerRoots) do
		for _, record in ipairs(queryNearbyRecords(
			entry.Root.Position,
			Config.FRONTIER_SIMULATION_DEACTIVATION_DISTANCE_STUDS
		)) do
			if record.ContentActivated and record.Model and record.Model.Parent then
				local radius = record.SimulationActive
					and Config.FRONTIER_SIMULATION_DEACTIVATION_DISTANCE_STUDS
					or Config.FRONTIER_SIMULATION_ACTIVATION_DISTANCE_STUDS
				if math.abs(entry.Root.Position.Y - record.Floor.Position.Y)
						<= Config.FRONTIER_SIMULATION_VERTICAL_MARGIN_STUDS
					and horizontalDistanceToFloor(record, entry.Root.Position) <= radius
				then
					shouldRemainActive[record.Key] = record
				end
			end
		end
	end
	for key, record in pairs(activeSimulationRecords) do
		if not shouldRemainActive[key] and setRecordSimulationActive(record, false) then
			changed = true
		end
	end
	for key, record in pairs(shouldRemainActive) do
		if not activeSimulationRecords[key] and setRecordSimulationActive(record, true) then
			changed = true
		end
	end
	if changed then
		updateWorldAttributes()
	end
end

local function visitNode(player, record)
	if not record.Discovered then
		record.Discovered = true
		record.Model:SetAttribute("Discovered", true)
		record.Model:SetAttribute("DiscoveredAt", os.clock())
		record.Model:SetAttribute("DiscoveredByUserId", player.UserId)
		CollectionService:AddTag(record.Model, "SkyDungeonDiscoveredIsland")
	end
		-- A intencao de movimento e o gatilho normal. Este fallback cobre teleporte, lag ou
	-- spawn direto sobre uma ilha de fronteira sem deixar o mundo terminar nela.
	if not record.Expanded then
		enqueueExpansion(record, "TouchFallback:" .. tostring(player.UserId), 50000)
	end
	enqueueDetail(record, true, 50000)

	local visited = playerVisitedNodes[player]
	if not visited then
		visited = {}
		playerVisitedNodes[player] = visited
	end
	if not visited[record.Key] then
		visited[record.Key] = true
		player:SetAttribute("UniqueIslandsVisited", (player:GetAttribute("UniqueIslandsVisited") or 0) + 1)
	end
	player:SetAttribute("CurrentIslandKey", record.Key)
	player:SetAttribute("CurrentLogicalLevel", record.Spec.Level)
	player:SetAttribute("CurrentLaneX", record.Spec.LaneX)
	player:SetAttribute("CurrentLaneZ", record.Spec.LaneZ)
	player:SetAttribute("InSocialSanctuary", record.Spec.IsSanctuary)
	player:SetAttribute("HighestLogicalLevel", math.max(
		player:GetAttribute("HighestLogicalLevel") or 0,
		record.Spec.Level
	))
end

local function prepareApproachedFrontiers(playerRoots)
	local now = os.clock()
	for _, entry in ipairs(playerRoots) do
		local currentIslandKey = entry.Player:GetAttribute("CurrentIslandKey")
		local currentLevel = entry.Player:GetAttribute("CurrentLogicalLevel")
		local best
		local bestScore = math.huge
		if typeof(currentIslandKey) == "string" and typeof(currentLevel) == "number" then
			local outgoing = outgoingEdgesBySource[currentIslandKey]
			for _, record in ipairs(queryNearbyRecords(
				entry.Root.Position,
				Config.FRONTIER_APPROACH_DISTANCE_STUDS
			)) do
				local isDirectChoice = false
				for _, edge in pairs(outgoing or {}) do
					if edge.TargetKey == record.Key then
						isDirectChoice = true
						break
					end
				end
				if isDirectChoice
					and record.Spec.Level == currentLevel + 1
					and not record.Expanded
					and not record.Expanding
					and not record.ScheduledExpansionRoundId
					and record.Model
					and record.Model.Parent
					and not pointInsideIsland(
						record,
						entry.Root.Position,
						Config.FRONTIER_DISCOVERY_HORIZONTAL_PADDING_STUDS,
						Config.FRONTIER_DISCOVERY_VERTICAL_PADDING_STUDS
					)
				then
					local vertical = math.abs(entry.Root.Position.Y - record.Floor.Position.Y)
					local horizontal = horizontalDistanceToFloor(record, entry.Root.Position)
					if vertical <= Config.FRONTIER_APPROACH_VERTICAL_MARGIN_STUDS
						and horizontal <= Config.FRONTIER_APPROACH_DISTANCE_STUDS
					then
						local score = horizontal + vertical * 0.25
						if score < bestScore then
							best = record
							bestScore = score
						end
					end
				end
			end
		end

		if not best then
			playerApproachIntents[entry.Player] = nil
			continue
		end

		local toTarget = Vector3.new(
			best.Floor.Position.X - entry.Root.Position.X,
			0,
			best.Floor.Position.Z - entry.Root.Position.Z
		)
		local moveDirection = Vector3.new(entry.Humanoid.MoveDirection.X, 0, entry.Humanoid.MoveDirection.Z)
		local horizontalVelocity = Vector3.new(
			entry.Root.AssemblyLinearVelocity.X,
			0,
			entry.Root.AssemblyLinearVelocity.Z
		)
		if moveDirection.Magnitude < 0.05 and horizontalVelocity.Magnitude > 0.05 then
			moveDirection = horizontalVelocity.Unit
		end
		local alignment = -1
		if moveDirection.Magnitude > 0.05 and toTarget.Magnitude > 0.05 then
			alignment = moveDirection.Unit:Dot(toTarget.Unit)
		end
		local movingSpeed = horizontalVelocity.Magnitude
		local intent = playerApproachIntents[entry.Player]
		if not intent or intent.TargetKey ~= best.Key then
			intent = {
				TargetKey = best.Key,
				LastScore = bestScore,
				Progress = 0,
				Sustain = 0,
				LastSampleAt = now,
				CooldownUntil = intent and intent.CooldownUntil or 0,
			}
			playerApproachIntents[entry.Player] = intent
		else
			local elapsed = math.clamp(now - intent.LastSampleAt, 0, 0.5)
			local improvement = intent.LastScore - bestScore
			local movingToward = movingSpeed >= Config.FRONTIER_INTENT_MIN_MOVE_SPEED_STUDS
				and alignment >= Config.FRONTIER_INTENT_MIN_ALIGNMENT
				and improvement >= -Config.FRONTIER_INTENT_DISTANCE_REGRESSION_TOLERANCE_STUDS
			if movingToward then
				intent.Sustain += elapsed
				intent.Progress += math.max(0, improvement)
			else
				intent.Sustain = math.max(0, intent.Sustain - elapsed * 2)
			end
			intent.LastScore = bestScore
			intent.LastSampleAt = now
		end

		if now >= intent.CooldownUntil
			and intent.Sustain >= Config.FRONTIER_INTENT_SUSTAIN_SECONDS
			and intent.Progress >= Config.FRONTIER_INTENT_MIN_PROGRESS_STUDS
		then
			if enqueueExpansion(
				best,
				"PlayerIntent:" .. tostring(entry.Player.UserId),
				math.max(1000, 20000 - bestScore * 10)
			) then
				intent.CooldownUntil = now + Config.FRONTIER_INTENT_TRIGGER_COOLDOWN_SECONDS
			end
			intent.Sustain = 0
			intent.Progress = 0
		end
	end
end

local function discoverTouchedIslands(playerRoots)
	for _, entry in ipairs(playerRoots) do
		local best
		local bestDistance = math.huge
		for _, record in ipairs(queryNearbyRecords(
			entry.Root.Position,
			Config.FRONTIER_SPATIAL_QUERY_PADDING_STUDS
		)) do
			if pointInsideIsland(
				record,
				entry.Root.Position,
				Config.FRONTIER_DISCOVERY_HORIZONTAL_PADDING_STUDS,
				Config.FRONTIER_DISCOVERY_VERTICAL_PADDING_STUDS
			) then
				local distance = (entry.Root.Position - record.Floor.Position).Magnitude
				if distance < bestDistance then
					best = record
					bestDistance = distance
				end
			end
		end
		if best then
			visitNode(entry.Player, best)
		end
	end
end

local function queueNearbyContent(playerRoots)
	local candidatesByKey = {}
	for _, entry in ipairs(playerRoots) do
		for _, record in ipairs(queryNearbyRecords(
			entry.Root.Position,
			Config.FRONTIER_CONTENT_ACTIVATION_DISTANCE_STUDS
		)) do
			if not record.ContentActivated and record.Model and record.Model.Parent then
				local vertical = math.abs(entry.Root.Position.Y - record.Floor.Position.Y)
				local horizontal = horizontalDistanceToFloor(record, entry.Root.Position)
				if vertical <= Config.FRONTIER_CONTENT_VERTICAL_MARGIN_STUDS
					and horizontal <= Config.FRONTIER_CONTENT_ACTIVATION_DISTANCE_STUDS
				then
					local score = horizontal + vertical * 0.4
					local current = candidatesByKey[record.Key]
					if not current or score < current.Score then
						candidatesByKey[record.Key] = { Record = record, Score = score }
					end
				end
			end
		end
	end
	local candidates = {}
	for _, candidate in pairs(candidatesByKey) do
		table.insert(candidates, candidate)
	end
	table.sort(candidates, function(a, b)
		if a.Score == b.Score then
			return a.Record.Key < b.Record.Key
		end
		return a.Score < b.Score
	end)
	local queued = 0
	for _, candidate in ipairs(candidates) do
		if queued >= Config.FRONTIER_MAX_CONTENT_ACTIVATIONS_PER_UPDATE then
			break
		end
		if enqueueDetail(
			candidate.Record,
			true,
			math.max(1000, 15000 - candidate.Score * 10)
		) then
			queued += 1
		end
	end
end

local function shiftLooseRuntimeFolder(folder, displacement)
	if not folder then
		return
	end
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Position += displacement
		end
	end
end

local function tryRebaseWorld()
	if not worldModel or highestGeneratedY < Config.WORLD_REBASE_TRIGGER_Y then
		return false
	end
	local shiftStuds = Config.WORLD_REBASE_SHIFT_STUDS
	local displacement = Vector3.new(0, -shiftStuds, 0)
	physicalWorldOffsetY -= shiftStuds
	logicalAltitudeOffset += shiftStuds
	worldRebaseSerial += 1
	worldModel:PivotTo(worldModel:GetPivot() + displacement)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character.Parent then
			character:PivotTo(character:GetPivot() + displacement)
		end
	end
	local water = workspace:FindFirstChild("Water")
	if water and water:IsA("BasePart") then
		water.Position += displacement
	end
	local waterTiles = workspace:FindFirstChild("WaterTiles")
	if waterTiles then
		shiftLooseRuntimeFolder(waterTiles, displacement)
	end
	shiftLooseRuntimeFolder(workspace:FindFirstChild("TutorialRuntime"), displacement)

	for _, record in pairs(nodesByKey) do
		record.BottomWorldY -= shiftStuds
		record.TopWorldY -= shiftStuds
		record.BoundsCFrame += displacement
	end
	for _, record in pairs(edgesByKey) do
		record.BottomWorldY -= shiftStuds
		record.TopWorldY -= shiftStuds
		record.BoundsCFrame += displacement
	end
	for level, worldY in pairs(levelWorldY) do
		levelWorldY[level] = worldY - shiftStuds
	end
	for key, value in pairs(latestCollectiveSnapshot) do
		if key ~= "Count" and key ~= "TrimmedCount" and value then
			latestCollectiveSnapshot[key] = value - shiftStuds
		end
	end
	highestGeneratedY -= shiftStuds
	latestWaterY -= shiftStuds
	workspace:SetAttribute("WorldPhysicalYOffsetStuds", physicalWorldOffsetY)
	workspace:SetAttribute("LogicalAltitudeOffsetStuds", logicalAltitudeOffset)
	workspace:SetAttribute("LastWorldRebaseShiftStuds", shiftStuds)
	workspace:SetAttribute("WorldRebaseSerial", worldRebaseSerial)
	updateWorldAttributes()
	print(string.format(
		"[SkyDungeon] Mundo reposicionado %.0f studs; nivel logico %d preservado.",
		shiftStuds,
		highestLogicalLevel
	))
	return true
end

local function hasAlivePlayerNear(record)
	for _, entry in ipairs(getAlivePlayerRoots()) do
		if entry.Root.Position.Y >= record.BottomWorldY - Config.GRID_SIZE
			and entry.Root.Position.Y <= record.TopWorldY + Config.GRID_SIZE * 2
			and horizontalDistanceToFloor(record, entry.Root.Position) <= Config.GRID_SIZE * 3
		then
			return true
		end
	end
	return false
end

local function removeEdge(record)
	local source = nodesByKey[record.SourceKey]
	local target = nodesByKey[record.TargetKey]
	if source then
		source.OutboundCount = math.max(0, source.OutboundCount - 1)
		if source.Model and source.Model.Parent then
			source.Model:SetAttribute("OutboundConnectionCount", source.OutboundCount)
		end
	end
	if target then
		target.InboundCount = math.max(0, target.InboundCount - 1)
		if target.Model and target.Model.Parent then
			target.Model:SetAttribute("InboundConnectionCount", target.InboundCount)
			if target.InboundCount < 2 then
				target.Model:SetAttribute("IsConvergence", false)
				if CollectionService:HasTag(target.Model, "SkyDungeonConvergence") then
					CollectionService:RemoveTag(target.Model, "SkyDungeonConvergence")
				end
			end
		end
	end
	if record.Model and record.Model.Parent then
		record.Model:Destroy()
	end
	edgesByKey[record.Key] = nil
	local outgoing = outgoingEdgesBySource[record.SourceKey]
	if outgoing then
		outgoing[record.Key] = nil
		if next(outgoing) == nil then
			outgoingEdgesBySource[record.SourceKey] = nil
		end
	end
	activeEdgeCount -= 1
	removedEdgeCount += 1
end

local function removeNode(record)
	if record.Model and record.Model.Parent then
		record.Model:Destroy()
	end
	nodesByKey[record.Key] = nil
	spatialIndex:Remove(record.Key)
	activeSimulationRecords[record.Key] = nil
	queuedForExpansion[record.Key] = nil
	activeNodeCount -= 1
	removedNodeCount += 1
end

function ChunkManager.GetPlayerWorldContext(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end
	local best
	local bestDistance = math.huge
	for _, record in ipairs(queryNearbyRecords(position, 48)) do
		local vertical = math.abs(position.Y - record.Floor.Position.Y)
		local horizontal = horizontalDistanceToFloor(record, position)
		if vertical <= 32 and horizontal <= 48 and horizontal + vertical < bestDistance then
			bestDistance = horizontal + vertical
			best = {
				CycleIndex = 0,
				LogicalLevel = record.Spec.Level,
				RouteId = nil,
				RouteProfile = nil,
				IsSanctuary = record.Spec.IsSanctuary,
				IslandKey = record.Key,
				LaneX = record.Spec.LaneX,
				LaneZ = record.Spec.LaneZ,
				IsConvergence = record.InboundCount >= 2,
			}
		end
	end
	return best
end

function ChunkManager.Start()
	if running then
		return
	end
	validateConfig()
	running = true
	baseSeed = Config.SEED or (os.time() % 2147483647)
	nodeSerial = 0
	totalNodeCount = 0
	totalEdgeCount = 0
	activeNodeCount = 0
	activeEdgeCount = 0
	removedNodeCount = 0
	removedEdgeCount = 0
	highestGeneratedY = Config.CENTER_WORLD.Y
	highestLogicalLevel = 0
	levelWorldY = {}
	latestWaterY = Config.CENTER_WORLD.Y - 100000
	generationRoundSerial = 0
	completedGenerationRounds = 0
	nodesByKey = {}
	edgesByKey = {}
	outgoingEdgesBySource = {}
	expansionQueue = {}
	queuedForExpansion = {}
	detailQueue = {}
	queuedForDetail = {}
	detailWorkerRunning = false
	detailOperationActive = false
	geometryOperationActive = false
	lastGeometryOperationAt = -math.huge
	spatialIndex = SpatialHash.new(Config.FRONTIER_SPATIAL_HASH_CELL_STUDS)
	activeSimulationRecords = {}
	lastWorldAttributeUpdateAt = -math.huge
	playerVisitedNodes = setmetatable({}, { __mode = "k" })
	playerApproachIntents = setmetatable({}, { __mode = "k" })
	latestCollectiveSnapshot = CollectiveProgressService.GetSnapshot()
	prepareWorld()
	local startSpec = IslandGraphPlanner.GetNodeSpec(baseSeed, 0, 0, 0)
	local startNode = assert(createNode(startSpec, "WorldStart"))
	startNode.Model:SetAttribute("Discovered", false)
	enqueueDetail(startNode, false, 2000)
	-- O mapa inicial ja nasce com um round inteiro. O primeiro jogador nunca ve
	-- apenas a ilha de spawn isolada no horizonte.
	enqueueExpansion(startNode, "WorldBootstrap", 100000)
	startDetailWorker()
	updateWorldAttributes(true)

	-- Geometria usa um unico worker global. Mesmo com muitos jogadores somente
	-- uma pequena operacao e publicada por frame, escolhendo primeiro a fronteira
	-- mais proxima ou um fallback de toque.
	task.spawn(function()
		while running do
			RunService.Heartbeat:Wait()
			if not detailOperationActive then
				if processExpansionQueue() > 0 then
					lastGeometryOperationAt = os.clock()
				end
			end
		end
	end)

	task.spawn(function()
		local lastCollectiveUpdate = 0
		local lastSimulationUpdate = 0
		while running do
			local cycleStartedAt = os.clock()
			local roots = getAlivePlayerRoots()
			discoverTouchedIslands(roots)
			prepareApproachedFrontiers(roots)
			queueNearbyContent(roots)
			if cycleStartedAt - lastSimulationUpdate >= Config.FRONTIER_SIMULATION_UPDATE_SECONDS then
				updateSimulationActivity(roots)
				lastSimulationUpdate = cycleStartedAt
			end
			if cycleStartedAt - lastCollectiveUpdate >= Config.COLLECTIVE_UPDATE_INTERVAL_SECONDS then
				latestCollectiveSnapshot = CollectiveProgressService.GetSnapshot()
				lastCollectiveUpdate = cycleStartedAt
				tryRebaseWorld()
				updateWorldAttributes()
			end
			local elapsed = os.clock() - cycleStartedAt
			task.wait(math.max(0.03, Config.FRONTIER_DISCOVERY_POLL_SECONDS - elapsed))
		end
	end)

	print(string.format("[SkyDungeon] Rounds reativos por intencao iniciados | Seed %d", baseSeed))
end

-- A agua consulta o buffer, mas nao cria ilhas sem aproximacao dos jogadores.
function ChunkManager.EnsureRoundsAheadOfWater(waterSurfaceY, desiredRounds, _maximumRounds)
	latestWaterY = waterSurfaceY
	local levels = {}
	for _, record in pairs(nodesByKey) do
		if record.TopWorldY > waterSurfaceY + Config.FRONTIER_CLEANUP_MARGIN_STUDS then
			levels[record.Spec.Level] = true
		end
	end
	local safeLevels = countRecords(levels)
	updateWorldAttributes()
	return safeLevels >= math.max(1, desiredRounds or 1), safeLevels, highestGeneratedY, totalNodeCount
end

function ChunkManager.EnsureGeneratedThrough(targetWorldY, _maximumChunks)
	return highestGeneratedY >= targetWorldY, highestGeneratedY, totalNodeCount
end

function ChunkManager.GetRoundStatus(referenceY)
	local low = 0
	local high = highestLogicalLevel
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local worldY = levelWorldY[middle] or Config.CENTER_WORLD.Y
		if worldY <= referenceY then
			low = middle + 1
		else
			high = middle - 1
		end
	end
	local lowerLevel = math.clamp(high, 0, highestLogicalLevel)
	local upperLevel = math.clamp(low, 0, highestLogicalLevel)
	local lowerDistance = math.abs(referenceY - (levelWorldY[lowerLevel] or referenceY))
	local upperDistance = math.abs(referenceY - (levelWorldY[upperLevel] or referenceY))
	local currentLevel = upperDistance < lowerDistance and upperLevel or lowerLevel
	local safeLevelCount = math.max(0, highestLogicalLevel - low + 1)
	return {
		CurrentRound = currentLevel,
		CurrentCycle = 0,
		GeneratedRounds = highestLogicalLevel,
		GeneratedCycles = 0,
		ActiveRounds = activeNodeCount,
		ActiveCycles = 0,
		SafeRoundsAhead = safeLevelCount,
		HighestGeneratedY = highestGeneratedY,
		GroupProgressY = latestCollectiveSnapshot.MeanY,
		LowerGroupY = latestCollectiveSnapshot.LowerGroupY,
		CollectivePlayerCount = latestCollectiveSnapshot.Count,
	}
end

function ChunkManager.GetFrontierStatus()
	return {
		ActiveIslands = activeNodeCount,
		ActiveConnections = activeEdgeCount,
		FrontierIslands = countFrontierNodes(),
		CompletedGenerationRounds = completedGenerationRounds,
		GenerationRoundDepth = Config.FRONTIER_ROUND_DEPTH_LEVELS,
		ActiveSimulationIslands = countActiveSimulations(),
		HighestLogicalLevel = highestLogicalLevel,
		HighestGeneratedY = highestGeneratedY,
		QueueLength = #expansionQueue,
		DetailQueueLength = #detailQueue,
	}
end

function ChunkManager.GetHighestGeneratedY()
	return highestGeneratedY
end

function ChunkManager.GetGroupProgressY()
	return latestCollectiveSnapshot.MeanY
end

function ChunkManager.GetCollectiveProgress()
	return table.clone(latestCollectiveSnapshot)
end

function ChunkManager.GetSafeRespawnCFrame(waterSurfaceY, clearanceStuds, rootOffsetStuds)
	local minimumY = waterSurfaceY + math.max(0, clearanceStuds or 0)
	local targetY = latestCollectiveSnapshot.MeanY or minimumY
	local best
	local bestScore = math.huge
	for _, sanctuaryOnly in ipairs({ true, false }) do
		for _, record in pairs(nodesByKey) do
			local surfaceY = record.Floor.Position.Y + record.Floor.Size.Y / 2
			if surfaceY >= minimumY and (not sanctuaryOnly or record.Spec.IsSanctuary) then
				local undiscoveredPenalty = record.Discovered and 0 or 5000
				local score = math.abs(surfaceY - targetY) + undiscoveredPenalty
				if score < bestScore then
					best = record
					bestScore = score
				end
			end
		end
		if best then
			break
		end
	end
	if not best then
		return nil
	end
	local surfacePosition = best.Floor.Position + Vector3.new(0, best.Floor.Size.Y / 2 + (rootOffsetStuds or 3), 0)
	return CFrame.new(surfacePosition)
end

function ChunkManager.CleanupBelowWater(waterSurfaceY, marginStuds, minimumActiveIslands)
	if not running or not worldModel then
		return 0, activeNodeCount
	end
	latestWaterY = waterSurfaceY
	local margin = math.max(0, marginStuds or Config.FRONTIER_CLEANUP_MARGIN_STUDS)
	local minimumToKeep = math.max(
		Config.FRONTIER_MIN_ACTIVE_ISLANDS,
		math.floor(minimumActiveIslands or Config.FRONTIER_MIN_ACTIVE_ISLANDS)
	)
	local removable = {}
	for _, record in pairs(nodesByKey) do
		if not record.Spec.IsStart
			and record.TopWorldY + margin < waterSurfaceY
			and not hasAlivePlayerNear(record)
		then
			table.insert(removable, record)
		end
	end
	table.sort(removable, function(a, b)
		return a.Spec.Level < b.Spec.Level
	end)
	local removedNow = 0
	for _, record in ipairs(removable) do
		if activeNodeCount <= minimumToKeep then
			break
		end
		removeNode(record)
		removedNow += 1
	end

	local edgeRemovals = {}
	for _, edge in pairs(edgesByKey) do
		if edge.TopWorldY + margin < waterSurfaceY
			or not nodesByKey[edge.SourceKey]
			or not nodesByKey[edge.TargetKey]
		then
			table.insert(edgeRemovals, edge)
		end
	end
	for _, edge in ipairs(edgeRemovals) do
		removeEdge(edge)
	end
	if removedNow > 0 then
		print(string.format("[SkyDungeon] Agua removeu %d ilha(s); %d continuam ativas.", removedNow, activeNodeCount))
	end
	updateWorldAttributes()
	return removedNow, activeNodeCount
end

function ChunkManager.GetWorldModel()
	return worldModel
end

function ChunkManager.IsRunning()
	return running
end

function ChunkManager.Stop()
	running = false
end

return ChunkManager
