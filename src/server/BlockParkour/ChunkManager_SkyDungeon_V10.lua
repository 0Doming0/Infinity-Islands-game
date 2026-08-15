--[[
	VERSION: V12_PROGRESSIVE_REPLICATION

	Sky Dungeon - fronteira vertical reativa em rounds de ilhas.

	Cada ilha continua sendo um no compartilhado da malha, mas uma geracao cria
	dois niveis inteiros de escolhas. O round seguinte comeca por proximidade,
	antes de o jogador pisar na ilha de fronteira, mas somente quando movimento,
	direcao e progresso confirmam a intencao. Assim o horizonte permanece cheio
	sem gerar camadas enquanto o jogador esta parado.
]]

-- TASK_14_BRANCHED_ROUND_GRAPH_V1
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(script.Parent.Config_SkyDungeon_V10)
local Generator = require(script.Parent.Generator_SkyDungeon_V10_Deterministic)
local IslandGraphPlanner = require(script.Parent.IslandGraphPlanner)
local PartyService = require(script.Parent.PartyService)
local CollectiveProgressService = require(script.Parent.CollectiveProgressService)
local SpatialHash = require(script.Parent.SpatialHash)
local GameplayAnalytics = require(ServerScriptService:WaitForChild("GameplayAnalyticsService"))
local RuntimeFolders = require(script.Parent.Parent.DungeonRuntime.RuntimeFolders)
local IslandVariationService = require(script.Parent.Parent.DungeonRuntime.IslandVariationService)

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
local cleanupOperationActive = false
local cleanupQueue = {}
local cleanupQueueHead = 1
local cleanupQueueTail = 0
local queuedCleanupNodes = {}
local queuedCleanupEdges = {}
local cleanupGetsNextSharedFrame = true
local lastGeometryOperationAt = -math.huge
local enqueueDetail
local spatialIndex = SpatialHash.new(Config.FRONTIER_SPATIAL_HASH_CELL_STUDS)
local activeSimulationRecords = {}
local geometryPoolFolder
local nodePoolBySignature = {}
local edgePoolBySignature = {}
local pooledNodeCount = 0
local pooledEdgeCount = 0
local reusedNodeCount = 0
local reusedEdgeCount = 0
local lastWorldAttributeUpdateAt = -math.huge
local playerVisitedNodes = setmetatable({}, { __mode = "k" })
local playerApproachIntents = setmetatable({}, { __mode = "k" })
local PLAYER_INTENT_VALUE_NAME = "WorldIntentTargetIsland"
local latestCollectiveSnapshot = {
	Count = 0,
	MeanY = nil,
	MedianY = nil,
	LowerGroupY = nil,
}
local emergencyGenerationInProgress = false
local runtimeOptions = {}
local maximumIslandCount = math.huge
local phaseReadySignaled = false
local routePlan
local fixedRouteState
local routeNodeByGlobalIndex = {}
local bossSanctuaryRecord
local fixedRouteLastMaterializedAt = 0
local fixedRouteLastProgressRefreshAt = 0

local function countRecords(records)
	local count = 0
	for _ in pairs(records) do
		count += 1
	end
	return count
end

local function getCleanupQueueLength()
	return math.max(0, cleanupQueueTail - cleanupQueueHead + 1)
end

local function enqueueCleanupJob(job)
	cleanupQueueTail += 1
	cleanupQueue[cleanupQueueTail] = job
end

local function dequeueCleanupJob()
	if cleanupQueueHead > cleanupQueueTail then
		return nil
	end
	local job = cleanupQueue[cleanupQueueHead]
	cleanupQueue[cleanupQueueHead] = nil
	cleanupQueueHead += 1
	if cleanupQueueHead > cleanupQueueTail then
		cleanupQueue = {}
		cleanupQueueHead = 1
		cleanupQueueTail = 0
	end
	return job
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

local function getIntentTargetValue(player)
	local existing = player:FindFirstChild(PLAYER_INTENT_VALUE_NAME)
	if existing and not existing:IsA("ObjectValue") then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new("ObjectValue")
		existing.Name = PLAYER_INTENT_VALUE_NAME
		existing.Parent = player
	end
	return existing
end

local function clearPublishedApproachTarget(player)
	local targetValue = player:FindFirstChild(PLAYER_INTENT_VALUE_NAME)
	if targetValue and targetValue:IsA("ObjectValue") then
		targetValue.Value = nil
	end
	player:SetAttribute("WorldIntentTargetIslandKey", nil)
	player:SetAttribute("WorldIntentTargetConfidence", nil)
	player:SetAttribute("WorldIntentTargetUpdatedAt", nil)
	player:SetAttribute("WorldIntentState", "WaitingForTravelDirection")
end

local function publishApproachTarget(player, record, intent)
	if not record
		or not record.IslandModel
		or not record.IslandModel.Parent
	then
		return false
	end
	local targetValue = getIntentTargetValue(player)
	targetValue.Value = record.IslandModel
	local sustainConfidence = intent.Sustain
		/ math.max(0.001, Config.FRONTIER_INTENT_SUSTAIN_SECONDS)
	local progressConfidence = intent.Progress
		/ math.max(0.001, Config.FRONTIER_INTENT_MIN_PROGRESS_STUDS)
	player:SetAttribute("WorldIntentTargetIslandKey", record.Key)
	player:SetAttribute(
		"WorldIntentTargetConfidence",
		math.floor(math.clamp(math.min(sustainConfidence, progressConfidence), 0, 1) * 100 + 0.5)
			/ 100
	)
	player:SetAttribute("WorldIntentTargetUpdatedAt", workspace:GetServerTimeNow())
	player:SetAttribute("WorldIntentState", "TravelIntentConfirmed")
	player:SetAttribute("WorldIntentAlgorithmVersion", "FrontierApproachSharedV1")
	intent.Published = true
	return true
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
	assert(Config.FRONTIER_INTENT_PUBLISH_SUSTAIN_SECONDS >= 0)
	assert(Config.FRONTIER_INTENT_PUBLISH_MIN_PROGRESS_STUDS >= 0)
	assert(Config.FRONTIER_INTENT_PUBLISH_STALE_SECONDS > 0)
	assert(Config.FRONTIER_MAX_GEOMETRY_OPERATIONS_PER_FRAME >= 1)
	assert(Config.FRONTIER_GEOMETRY_PARTS_PER_FRAME >= 1)
	assert(Config.FRONTIER_GENERATION_TIME_BUDGET_SECONDS > 0)
	assert(Config.FRONTIER_DETAIL_YIELD_EVERY_CLONES >= 1)
	assert(Config.FRONTIER_DETAIL_TIME_BUDGET_SECONDS > 0)
	assert(Config.FRONTIER_CLEANUP_OPERATIONS_PER_FRAME >= 1)
	assert(Config.FRONTIER_CLEANUP_TIME_BUDGET_SECONDS > 0)
	assert(Config.FRONTIER_SPATIAL_HASH_CELL_STUDS > 0)
	assert(Config.FRONTIER_SPATIAL_QUERY_PADDING_STUDS > 0)
	assert(Config.FRONTIER_DIAGNOSTIC_UPDATE_SECONDS >= 0.1)
	assert(Config.FRONTIER_MAX_ACTIVE_ISLANDS >= 32)
	assert(Config.FRONTIER_MAX_POOLED_ISLANDS >= 0)
	assert(Config.FRONTIER_MAX_POOLED_CONNECTIONS >= 0)
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

local function cycleIndexForRecord(record)
	if not record then
		return 1
	end

	return math.max(
		1,
		math.floor(
			tonumber(record.Spec.CycleIndex)
				or tonumber(record.Model:GetAttribute("CycleIndex"))
				or 1
		)
	)
end

local function getCycleStats()
	local generated = {}
	local active = {}
	local highest = 1

	for _, record in pairs(nodesByKey) do
		local cycleIndex = cycleIndexForRecord(record)
		generated[cycleIndex] = true
		highest = math.max(highest, cycleIndex)

		if record.SimulationActive then
			active[cycleIndex] = true
		end
	end

	return countRecords(generated), countRecords(active), highest
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
	local generatedCycleCount,
		activeCycleCount,
		highestGeneratedCycleIndex =
			getCycleStats()
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
	worldModel:SetAttribute("GeometryPoolEnabled", Config.FRONTIER_GEOMETRY_POOL_ENABLED == true)
	worldModel:SetAttribute("PooledIslandCount", pooledNodeCount)
	worldModel:SetAttribute("PooledConnectionCount", pooledEdgeCount)
	worldModel:SetAttribute("ReusedIslandCount", reusedNodeCount)
	worldModel:SetAttribute("ReusedConnectionCount", reusedEdgeCount)
	worldModel:SetAttribute("FrontierIslandCount", countFrontierNodes())
	worldModel:SetAttribute("ConvergenceIslandCount", countConvergences())
	worldModel:SetAttribute("SanctuaryCount", countSanctuaries())
	worldModel:SetAttribute("ActiveSimulationIslandCount", countActiveSimulations())
	worldModel:SetAttribute("GeneratedCycleCount", generatedCycleCount)
	worldModel:SetAttribute("ActiveCycleCount", activeCycleCount)
	worldModel:SetAttribute("HighestGeneratedCycleIndex", highestGeneratedCycleIndex)
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
	worldModel:SetAttribute("CleanupQueueLength", getCleanupQueueLength())
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
	worldModel:SetAttribute("PhaseId", runtimeOptions.PhaseId or "Phase01")
	worldModel:SetAttribute("InitialPartySize", math.max(1, math.floor(tonumber(runtimeOptions.PartySize) or 1)))
	worldModel:SetAttribute("MaximumPhaseIslandCount", maximumIslandCount < math.huge and maximumIslandCount or 0)
end

local function prepareWorld()
	local generatedRoot = RuntimeFolders.Get("GeneratedIslands")
	local oldWorld = generatedRoot:FindFirstChild(Config.WORLD_MODEL_NAME)
		or workspace:FindFirstChild(Config.WORLD_MODEL_NAME)
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
	worldModel:SetAttribute("InitialGenerationComplete", false)
	worldModel:SetAttribute("InitialGenerationSuccessful", false)
	worldModel.Parent = generatedRoot

	nodesFolder = Instance.new("Folder")
	nodesFolder.Name = "IslandNodes"
	nodesFolder.Parent = worldModel
	connectionsFolder = Instance.new("Folder")
	connectionsFolder.Name = "IslandConnections"
	connectionsFolder.Parent = worldModel

	local oldPool = ServerStorage:FindFirstChild("SkyDungeonGeometryPool")
	if oldPool then
		oldPool:Destroy()
	end
	geometryPoolFolder = Instance.new("Folder")
	geometryPoolFolder.Name = "SkyDungeonGeometryPool"
	geometryPoolFolder.Parent = ServerStorage
end

local function removeAllTags(instance)
	for _, tag in ipairs(CollectionService:GetTags(instance)) do
		CollectionService:RemoveTag(instance, tag)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(descendant)) do
			CollectionService:RemoveTag(descendant, tag)
		end
	end
end

local function takePooledNode(sizeName)
	if Config.FRONTIER_GEOMETRY_POOL_ENABLED ~= true then
		return nil
	end
	local bucket = nodePoolBySignature[sizeName]
	local model = bucket and table.remove(bucket)
	if not model then
		return nil
	end
	pooledNodeCount = math.max(0, pooledNodeCount - 1)
	reusedNodeCount += 1
	return model
end

local function takePooledEdge(blockCount)
	if Config.FRONTIER_GEOMETRY_POOL_ENABLED ~= true then
		return nil
	end
	local signature = tostring(blockCount)
	local bucket = edgePoolBySignature[signature]
	local model = bucket and table.remove(bucket)
	if not model then
		return nil
	end
	pooledEdgeCount = math.max(0, pooledEdgeCount - 1)
	reusedEdgeCount += 1
	return model
end

local function recycleNodeModel(model)
	if not model then
		return false
	end
	if Config.FRONTIER_GEOMETRY_POOL_ENABLED ~= true
		or not geometryPoolFolder
		or pooledNodeCount >= Config.FRONTIER_MAX_POOLED_ISLANDS
	then
		model:Destroy()
		return false
	end
	-- Retira a arvore inteira do Workspace antes de destruir filhos dinamicos.
	-- Assim o cliente recebe uma unica desreplicacao, sem uma cascata de deletes
	-- individuais de grama, decoracoes, baus e mobs.
	model.Parent = geometryPoolFolder
	removeAllTags(model)
	local signature = Generator.PrepareFrontierNodeForPool(model)
	if not signature then
		model:Destroy()
		return false
	end
	local bucket = nodePoolBySignature[signature]
	if not bucket then
		bucket = {}
		nodePoolBySignature[signature] = bucket
	end
	table.insert(bucket, model)
	pooledNodeCount += 1
	return true
end

local function recycleEdgeModel(model)
	if not model then
		return false
	end
	if Config.FRONTIER_GEOMETRY_POOL_ENABLED ~= true
		or not geometryPoolFolder
		or pooledEdgeCount >= Config.FRONTIER_MAX_POOLED_CONNECTIONS
	then
		model:Destroy()
		return false
	end
	model.Parent = geometryPoolFolder
	removeAllTags(model)
	local signature = Generator.PrepareFrontierConnectionForPool(model)
	if not signature then
		model:Destroy()
		return false
	end
	local bucket = edgePoolBySignature[signature]
	if not bucket then
		bucket = {}
		edgePoolBySignature[signature] = bucket
	end
	table.insert(bucket, model)
	pooledEdgeCount += 1
	return true
end

local ROUTE_SPEC_ATTRIBUTES = {
	"RouteSeed",
	"RoundIndex",
	"IslandIndex",
	"GlobalIslandIndex",
	"IsInitialIsland",
	"NumberedIslandIndex",
	"IslandDisplayLabel",
	"CycleIndex",
	"IslandIndexInCycle",
	"LevelInCycle",
	"XPRewardMultiplier",
	"IncomingDirectionId",
	"NextDirectionId",
	"IsMandatoryRoute",
	"IsRewardIsland",
	"IsBossSanctuary",
	"RouteExitLeadsToBoss",
	"RouteExitLeadsToNextRound",
	"IsOptionalRoute",
	"IsRoundExit",
	"RoundExitIndex",
	"ProtectionGlobalIslandIndex",
	"RouteNodeOrder",
	"RouteBranchId",
	"AlternateNextDirectionId",
	"RouteChoiceCount",
	"RouteEntryCount",
	"RouteExitCount",
	"IsRouteConvergence",
	"IsRouteBranchPoint",
}

local function applyRouteSpecAttributes(instance, spec)
	if not instance or not spec then
		return
	end
	for _, attributeName in ipairs(ROUTE_SPEC_ATTRIBUTES) do
		local value = spec[attributeName]
		if value ~= nil then
			instance:SetAttribute(attributeName, value)
		end
	end
	if spec.IsMandatoryRoute == true then
		instance:SetAttribute("SpecialIslandChanceMultiplier", 0)
	end
end

local function createNode(spec, reason, generationOwnerUserId)
	local existing = nodesByKey[spec.Key]
	if existing then
		return existing, false
	end
	if totalNodeCount >= maximumIslandCount then
		return nil, false, "limite de ilhas da fase atingido"
	end
	if activeNodeCount >= Config.FRONTIER_MAX_ACTIVE_ISLANDS then
		return nil, false, "limite de ilhas ativas atingido"
	end

	nodeSerial += 1
	local recycledModel = takePooledNode(spec.SizeName)
	local model, metadata = Generator.CreateFrontierNode(nodesFolder, spec, {
		NodeSerial = nodeSerial,
		DeferRuntimeContent = true,
		DeferVisualContent = true,
		RecycledModel = recycledModel,
		GenerationOwnerUserId = generationOwnerUserId,
		PhaseId = runtimeOptions.PhaseId or "Phase01",
	})
	applyRouteSpecAttributes(model, spec)
	model:SetAttribute("GenerationReason", reason or "Unknown")
	model:SetAttribute("GenerationOwnerUserId", generationOwnerUserId)
	model:SetAttribute("NodeSerial", nodeSerial)
	model:SetAttribute("SanctuarySubmerged", false)
	model:SetAttribute("SanctuaryValid", spec.IsSanctuary == true)
	model:SetAttribute("IsEmergencySanctuary", spec.IsEmergency == true)
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
	applyRouteSpecAttributes(record.IslandModel, spec)
	applyRouteSpecAttributes(record.Floor, spec)
	record.IslandModel:SetAttribute("SanctuarySubmerged", false)
	record.IslandModel:SetAttribute("SanctuaryValid", spec.IsSanctuary == true)
	record.IslandModel:SetAttribute("IsEmergencySanctuary", spec.IsEmergency == true)
	nodesByKey[spec.Key] = record
	if spec.GlobalIslandIndex then
		routeNodeByGlobalIndex[spec.GlobalIslandIndex] = record
	end
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
	if not routePlan and totalNodeCount >= maximumIslandCount and not phaseReadySignaled then
		phaseReadySignaled = true
		worldModel:SetAttribute("PhaseIslandLimitReached", true)
		local callback = runtimeOptions.OnPhaseReady
		if type(callback) == "function" then
			task.defer(callback, {
				Key = record.Key,
				Model = record.Model,
				IslandModel = record.IslandModel,
				Floor = record.Floor,
				LogicalLevel = record.Spec.Level,
			})
		end
	end
	return record, true
end

local function destroyOrphanNode(record)
	if not record or record.InboundCount > 0 or record.Spec.IsStart then
		return
	end
	if record.Model then
		recycleNodeModel(record.Model)
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
	local function yieldGeometrySlice(publishedPartCost)
		publishedParts += math.max(1, tonumber(publishedPartCost) or 1)
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
	local recycledModel = takePooledEdge(#plan.Cells - 2)
	local success, modelOrError, metadata = pcall(Generator.CreateFrontierConnection, connectionsFolder, plan, {
		LogicalLevel = target.Spec.Level,
		PathId = source.OutboundCount + 1,
		ReservationParent = worldModel,
		SkipExternalReservationScan = true,
		DeferVisualContent = true,
		Seed = target.Spec.Seed,
		YieldCallback = yieldGeometrySlice,
		RecycledModel = recycledModel,
		PhaseId = runtimeOptions.PhaseId or "Phase01",
	})
	geometryOperationActive = false
	if not success then
		local partialModel = connectionsFolder:FindFirstChild("Connection_" .. plan.Key)
		if partialModel then
			partialModel:Destroy()
		end
		if recycledModel then
			recycledModel:Destroy()
		end
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

local function routeRecordContext(record)
	if not record then
		return nil
	end
	local markers = record.IslandModel and record.IslandModel:FindFirstChild("GameplayMarkers")
	return {
		Key = record.Key,
		Model = record.Model,
		IslandModel = record.IslandModel,
		Floor = record.Floor,
		LogicalLevel = record.Spec.Level,
		RoundIndex = record.Spec.RoundIndex,
		IslandIndex = record.Spec.IslandIndex,
		GlobalIslandIndex = record.Spec.GlobalIslandIndex,
		IsInitialIsland = record.Spec.IsInitialIsland == true,
		NumberedIslandIndex = record.Spec.NumberedIslandIndex,
		IslandDisplayLabel = record.Spec.IslandDisplayLabel,
		CycleIndex = record.Spec.CycleIndex,
		IslandIndexInCycle = record.Spec.IslandIndexInCycle,
		LevelInCycle = record.Spec.LevelInCycle,
		XPRewardMultiplier = record.Spec.XPRewardMultiplier,
		IsRewardIsland = record.Spec.IsRewardIsland == true,
		IsBossSanctuary = record.Spec.IsBossSanctuary == true,
		IsOptionalRoute = record.Spec.IsOptionalRoute == true,
		IsRoundExit = record.Spec.IsRoundExit == true,
		RoundExitIndex = record.Spec.RoundExitIndex,
		RouteBranchId = record.Spec.RouteBranchId,
		IncomingDirectionId = record.Spec.IncomingDirectionId,
		NextDirectionId = record.Spec.NextDirectionId,
		Spec = record.Spec,
		GameplayMarkers = markers,
		SafeSpawn = markers and markers:FindFirstChild("SafeSpawn"),
		ObjectiveAnchor = markers and markers:FindFirstChild("ObjectiveAnchor"),
		EnemySpawns = markers and markers:FindFirstChild("EnemySpawns"),
		ChestSpawns = markers and markers:FindFirstChild("ChestSpawns"),
		Entry = markers and markers:FindFirstChild("Entry"),
		Exit = markers and markers:FindFirstChild("Exit"),
		Entries = markers and markers:FindFirstChild("Entries"),
		Exits = markers and markers:FindFirstChild("Exits"),
		RouteEntryCount = markers and markers:GetAttribute("EntryCount") or 1,
		RouteExitCount = markers and markers:GetAttribute("ExitCount") or 1,
		IsRouteConvergence = markers and markers:GetAttribute("IsRouteConvergence") == true or false,
		IsRouteBranchPoint = markers and markers:GetAttribute("IsRouteBranchPoint") == true or false,
	}
end

local function markInitialFixedRouteReady()
	if not fixedRouteState or fixedRouteState.InitialReady then
		return
	end
	if fixedRouteState.MaterializedNodeCount < fixedRouteState.InitialTargetNodeIndex then
		return
	end
	fixedRouteState.InitialReady = true
	worldModel:SetAttribute("FixedRouteInitialWindowReady", true)
	worldModel:SetAttribute("InitialGenerationSuccessful", true)
	worldModel:SetAttribute("InitialGenerationComplete", true)
end

local function routePhysicalIslandCount()
	if not routePlan then
		return 0
	end
	return math.max(
		math.floor(tonumber(routePlan.PhysicalIslandCount) or 0),
		#(routePlan.Nodes or {}),
		math.floor(tonumber(routePlan.TotalIslandCount) or 0)
	)
end

local function routeMaterializationIndex(globalIslandIndex)
	if not routePlan then
		return nil
	end
	local index = math.floor(tonumber(globalIslandIndex) or 0)
	local mapping = routePlan.MaterializationIndexByGlobalIndex
	local materializationIndex = type(mapping) == "table" and tonumber(mapping[index]) or nil
	if materializationIndex then
		return math.clamp(math.floor(materializationIndex), 1, routePhysicalIslandCount())
	end
	return math.clamp(index, 1, routePhysicalIslandCount())
end

local function currentObjectiveProgressIndex()
	if not routePlan then
		return 1
	end
	local current = math.max(
		1,
		math.floor(tonumber(workspace:GetAttribute("DungeonCurrentObjectiveIsland")) or 1)
	)
	for _, player in ipairs(Players:GetPlayers()) do
		current = math.max(
			current,
			math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0)
		)
	end
	return math.clamp(current, 1, routePlan.TotalIslandCount)
end

local function refreshFixedRouteTargetFromProgress(reason)
	if not routePlan or not fixedRouteState or fixedRouteState.FullRouteReady then
		return false
	end
	local currentObjective = currentObjectiveProgressIndex()
	local futureWindow = math.max(1, math.floor(tonumber(routePlan.FutureWindowSize) or 3))
	local desiredObjective = math.min(routePlan.TotalIslandCount, currentObjective + futureWindow)
	local targetNodeIndex = routeMaterializationIndex(desiredObjective)
	if not targetNodeIndex then
		return false
	end
	local previousTarget = fixedRouteState.TargetNodeIndex
	fixedRouteState.TargetNodeIndex = math.max(previousTarget, targetNodeIndex)
	fixedRouteLastProgressRefreshAt = os.clock()

	workspace:SetAttribute("DungeonRouteRequestedThroughObjective", desiredObjective)
	workspace:SetAttribute("DungeonRouteMaterializationTargetNode", fixedRouteState.TargetNodeIndex)
	workspace:SetAttribute("DungeonRouteMaterializedNodeCount", fixedRouteState.MaterializedNodeCount)
	workspace:SetAttribute("DungeonRouteProgressWatchdogReason", tostring(reason or "ProgressRefresh"))
	workspace:SetAttribute("DungeonRouteProgressWatchdogPolicy", "ObjectiveLookaheadV1")
	if worldModel and worldModel.Parent then
		worldModel:SetAttribute("FixedRouteTargetNodeIndex", fixedRouteState.TargetNodeIndex)
		worldModel:SetAttribute("FixedRouteLookaheadObjective", desiredObjective)
	end
	return fixedRouteState.TargetNodeIndex > previousTarget
end

local function signalFixedRouteReady(record)
	if phaseReadySignaled then
		return
	end
	phaseReadySignaled = true
	local physicalCount = routePhysicalIslandCount()
	worldModel:SetAttribute("FixedRouteReady", true)
	worldModel:SetAttribute("FixedRouteMaterializedThrough", physicalCount)
	worldModel:SetAttribute("FixedRoutePhysicalIslandCount", physicalCount)
	worldModel:SetAttribute("FixedRouteObjectiveIslandCount", routePlan.TotalIslandCount)
	workspace:SetAttribute("DungeonRouteReady", true)
	workspace:SetAttribute("DungeonPhysicalIslandCount", physicalCount)
	local callback = runtimeOptions.OnPhaseReady
	if type(callback) == "function" then
		task.defer(callback, routeRecordContext(record))
	end
end

local function incomingConnectionsFor(spec)
	if type(spec.IncomingConnections) == "table" then
		return spec.IncomingConnections
	end
	if type(spec.ParentKey) == "string" and type(spec.IncomingDirectionId) == "string" then
		return {
			{
				SourceKey = spec.ParentKey,
				DirectionId = spec.IncomingDirectionId,
			},
		}
	end
	return {}
end

local function markFixedRouteSourceLinked(source)
	if not source or not source.Model or not source.Model.Parent then
		return
	end
	source.Expanded = true
	source.Model:SetAttribute("Expanded", true)
	source.Model:SetAttribute("ExpansionState", "FixedRouteGraphLinked")
end

local function finalizePendingFixedRouteNode()
	local pending = fixedRouteState.PendingRecord
	local pendingNodeIndex = fixedRouteState.PendingNodeIndex
	fixedRouteState.MaterializedNodeCount = pendingNodeIndex
	fixedRouteLastMaterializedAt = os.clock()
	workspace:SetAttribute("DungeonRouteMaterializedNodeCount", fixedRouteState.MaterializedNodeCount)
	workspace:SetAttribute("DungeonRouteMaterializationStalled", false)
	fixedRouteState.NextNodeIndex = pendingNodeIndex + 1
	fixedRouteState.PendingRecord = nil
	fixedRouteState.PendingNodeIndex = nil
	fixedRouteState.PendingEdgeIndex = nil
	fixedRouteState.RetryAt = nil
	local order = math.floor(tonumber(pending.Spec.RouteNodeOrder) or pendingNodeIndex)
	enqueueDetail(pending, false, math.max(1000, 12000 - order * 80))
	worldModel:SetAttribute("FixedRouteMaterializedThrough", fixedRouteState.MaterializedNodeCount)
	markInitialFixedRouteReady()
	if fixedRouteState.MaterializedNodeCount >= routePhysicalIslandCount() then
		fixedRouteState.FullRouteReady = true
		signalFixedRouteReady(pending)
	end
end

local function processFixedRoute()
	if not routePlan or not fixedRouteState or fixedRouteState.FullRouteReady then
		return 0
	end
	if fixedRouteState.RetryAt and os.clock() < fixedRouteState.RetryAt then
		return 0
	end
	if fixedRouteState.PendingRecord then
		local pending = fixedRouteState.PendingRecord
		local incomingConnections = incomingConnectionsFor(pending.Spec)
		local edgeIndex = fixedRouteState.PendingEdgeIndex or 1
		local connection = incomingConnections[edgeIndex]
		if connection then
			local source = nodesByKey[connection.SourceKey]
			if not source then
				warn("[SkyDungeon] Origem da aresta ramificada ainda nao existe: " .. tostring(connection.SourceKey))
				fixedRouteState.RetryAt = os.clock() + 0.5
				return 0
			end
			local success, edgeOrError = pcall(
				createEdge,
				source,
				pending,
				connection.DirectionId
			)
			if not success then
				warn("[SkyDungeon] Falha na aresta da rota ramificada: " .. tostring(edgeOrError))
				fixedRouteState.RetryAt = os.clock() + 1
				return 0
			end
			fixedRouteState.RetryAt = nil
			fixedRouteState.PendingEdgeIndex = edgeIndex + 1
			markFixedRouteSourceLinked(source)
			return 1
		end
		finalizePendingFixedRouteNode()
		return 1
	end
	local physicalCount = routePhysicalIslandCount()
	if fixedRouteState.NextNodeIndex > fixedRouteState.TargetNodeIndex
		or fixedRouteState.NextNodeIndex > physicalCount
	then
		return 0
	end
	local spec = routePlan.Nodes[fixedRouteState.NextNodeIndex]
	if not spec then
		fixedRouteState.RetryAt = os.clock() + 1
		warn("[SkyDungeon] RoutePlan sem Node na ordem " .. tostring(fixedRouteState.NextNodeIndex))
		return 0
	end
	local record, _, errorMessage = createNode(spec, "FixedRouteGraph", nil)
	if not record then
		warn("[SkyDungeon] Falha ao criar ilha da rota ramificada: " .. tostring(errorMessage))
		fixedRouteState.RetryAt = os.clock() + 1
		return 0
	end
	fixedRouteState.RetryAt = nil
	fixedRouteState.PendingRecord = record
	fixedRouteState.PendingNodeIndex = fixedRouteState.NextNodeIndex
	fixedRouteState.PendingEdgeIndex = 1
	return 1
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
	if record.IslandModel:GetAttribute("StructuralVariationApplied") ~= true then
		local variationOk, applied, profileOrError = pcall(
			IslandVariationService.Apply,
			routeRecordContext(record)
		)
		if not variationOk or applied == false then
			warn(string.format(
				"[SkyDungeon] Fallback de variação falhou em %s: %s",
				record.Key,
				tostring(profileOrError or applied)
			))
		end
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
		if record.VisualContentPopulated then
			local variationOk, applied, profileOrError = pcall(
				IslandVariationService.Apply,
				routeRecordContext(record)
			)
			if not variationOk or applied == false then
				warn(string.format(
					"[SkyDungeon] Variação estrutural falhou em %s: %s",
					record.Key,
					tostring(profileOrError or applied)
				))
			end
		end
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
			if cleanupOperationActive
				or geometryOperationActive
				or (#expansionQueue > 0 and getBestDetailPriority() < 40000)
			then
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

local function enqueueExpansion(record, reason, priority, generationOwnerUserId)
	local existingJob = queuedForExpansion[record.Key]
	if existingJob then
		existingJob.Priority = math.max(existingJob.Priority, priority or 0)
		if not existingJob.GenerationOwnerUserId and generationOwnerUserId then
			existingJob.GenerationOwnerUserId = generationOwnerUserId
		end
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
		GenerationOwnerUserId = generationOwnerUserId,
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
local function stepNodeExpansion(record, generationOwnerUserId)
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
	local child, created, creationError = createNode(
		childSpec,
		"DiscoveredFrom:" .. record.Key,
		generationOwnerUserId
	)
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
	if
		job.Reason == "WorldBootstrap"
		and worldModel
		and worldModel.Parent
		and worldModel:GetAttribute("InitialGenerationComplete") ~= true
	then
		worldModel:SetAttribute("InitialGenerationSuccessful", completed == true)
		worldModel:SetAttribute("InitialGenerationComplete", true)
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
				local state, children, performedOperation = stepNodeExpansion(
					record,
					job.GenerationOwnerUserId
				)
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
	if routePlan
		and record.Spec.IsOptionalRoute == true
		and type(runtimeOptions.OnOptionalIslandEntered) == "function"
	then
		local callbackSuccess, callbackError = pcall(
			runtimeOptions.OnOptionalIslandEntered,
			player,
			routeRecordContext(record)
		)
		if not callbackSuccess then
			warn("[SkyDungeon] OnOptionalIslandEntered falhou: " .. tostring(callbackError))
		end
	end
	if routePlan
		and (record.Spec.IsMandatoryRoute == true or record.Spec.IsBossSanctuary == true)
		and type(runtimeOptions.OnRouteIslandEntered) == "function"
	then
		local callbackSuccess, allowed, rejectReason = pcall(
			runtimeOptions.OnRouteIslandEntered,
			player,
			routeRecordContext(record)
		)
		if not callbackSuccess then
			warn("[SkyDungeon] OnRouteIslandEntered falhou: " .. tostring(allowed))
		elseif allowed == false then
			record.Model:SetAttribute(
				"LastRejectedEntryReason",
				tostring(rejectReason or "ObjectiveLocked")
			)
			return
		end
	end
	local rescueDestinationKey = player:GetAttribute("SanctuaryRescueDestinationKey")
	local rescueSuppressed = typeof(rescueDestinationKey) == "string"
		and rescueDestinationKey == record.Key
	if not rescueSuppressed and not record.Discovered then
		record.Discovered = true
		record.Model:SetAttribute("Discovered", true)
		record.Model:SetAttribute("DiscoveredAt", os.clock())
		record.Model:SetAttribute("DiscoveredByUserId", player.UserId)
		CollectionService:AddTag(record.Model, "SkyDungeonDiscoveredIsland")
	end
		-- A intencao de movimento e o gatilho normal. Este fallback cobre teleporte, lag ou
	-- spawn direto sobre uma ilha de fronteira sem deixar o mundo terminar nela.
	if not rescueSuppressed and not routePlan and not record.Expanded then
		enqueueExpansion(
			record,
			"TouchFallback:" .. tostring(player.UserId),
			50000,
			player.UserId
		)
	end
	if not rescueSuppressed then
		enqueueDetail(record, true, 50000)
	end

	local visited = playerVisitedNodes[player]
	if not visited then
		visited = {}
		playerVisitedNodes[player] = visited
	end
	if not rescueSuppressed and not visited[record.Key] then
		visited[record.Key] = true
		player:SetAttribute("UniqueIslandsVisited", (player:GetAttribute("UniqueIslandsVisited") or 0) + 1)
		PartyService.RecordMissionProgress(player, "IslandVisited", 1, record.Key)
	end
	player:SetAttribute("CurrentIslandKey", record.Key)
	player:SetAttribute("CurrentRoundIndex", record.Spec.RoundIndex)
	player:SetAttribute("CurrentIslandIsOptional", record.Spec.IsOptionalRoute == true)
	if record.Spec.IsOptionalRoute == true then
		player:SetAttribute("CurrentOptionalIslandKey", record.Key)
		player:SetAttribute("CurrentOptionalRouteBranch", record.Spec.RouteBranchId)
	elseif record.Spec.GlobalIslandIndex then
		player:SetAttribute("CurrentOptionalIslandKey", nil)
		player:SetAttribute("CurrentOptionalRouteBranch", nil)
		player:SetAttribute("CurrentRouteIslandIndex", record.Spec.IslandIndex)
		player:SetAttribute("CurrentGlobalIslandIndex", record.Spec.GlobalIslandIndex)
		if fixedRouteState and routePlan and record.Spec.IsMandatoryRoute == true then
			local currentObjective = math.max(1, math.floor(tonumber(record.Spec.GlobalIslandIndex) or 1))
			local futureObjective = math.min(
				routePlan.TotalIslandCount,
				currentObjective + math.max(1, math.floor(tonumber(routePlan.FutureWindowSize) or 3))
			)
			local targetNodeIndex = routeMaterializationIndex(futureObjective)
			if targetNodeIndex then
				fixedRouteState.TargetNodeIndex = math.max(fixedRouteState.TargetNodeIndex, targetNodeIndex)
				fixedRouteLastProgressRefreshAt = os.clock()
				workspace:SetAttribute("DungeonRouteMaterializationTargetNode", fixedRouteState.TargetNodeIndex)
			end
		end
		player:SetAttribute(
			"CurrentIsInitialIsland",
			record.Spec.IsInitialIsland == true
		)
		player:SetAttribute(
			"CurrentNumberedIslandIndex",
			record.Spec.NumberedIslandIndex
		)
		player:SetAttribute(
			"CurrentIslandDisplayLabel",
			record.Spec.IslandDisplayLabel
		)
		player:SetAttribute(
			"CurrentCycleIndex",
			record.Spec.CycleIndex
				or record.Model:GetAttribute("CycleIndex")
				or 1
		)
		player:SetAttribute(
			"CurrentIslandIndexInCycle",
			record.Spec.IslandIndexInCycle
				or record.Model:GetAttribute("IslandIndexInCycle")
				or 1
		)
		player:SetAttribute(
			"CurrentLevelInCycle",
			record.Spec.LevelInCycle
				or record.Model:GetAttribute("LevelInCycle")
				or 1
		)
		player:SetAttribute("CurrentIslandIsReward", record.Spec.IsRewardIsland == true)
		player:SetAttribute("CurrentIslandIsRoundExit", record.Spec.IsRoundExit == true)
		if fixedRouteState and record.Spec.IsMandatoryRoute == true then
			local futureObjectiveIndex = math.min(
				routePlan.TotalIslandCount,
				record.Spec.GlobalIslandIndex + math.max(1, math.floor(tonumber(routePlan.FutureWindowSize) or 3))
			)
			local targetNodeIndex = routeMaterializationIndex(futureObjectiveIndex)
			if targetNodeIndex then
				fixedRouteState.TargetNodeIndex = math.max(
					fixedRouteState.TargetNodeIndex,
					targetNodeIndex
				)
				fixedRouteLastProgressRefreshAt = os.clock()
				workspace:SetAttribute("DungeonRouteMaterializationTargetNode", fixedRouteState.TargetNodeIndex)
			end
		end
	end
	player:SetAttribute("CurrentIslandIndex", record.Spec.Level)
	player:SetAttribute("CurrentLogicalLevel", record.Spec.Level)
	player:SetAttribute("CurrentLaneX", record.Spec.LaneX)
	player:SetAttribute("CurrentLaneZ", record.Spec.LaneZ)
	player:SetAttribute("InSocialSanctuary", record.Spec.IsSanctuary)
	if record.Spec.IsSanctuary then
		player:SetAttribute("CurrentSanctuaryIndex", record.Spec.Level)
	end
	if not rescueSuppressed then
		local previousHighest = math.max(
			0,
			tonumber(player:GetAttribute("HighestLogicalLevel")) or 0
		)
		player:SetAttribute("HighestLogicalLevel", math.max(previousHighest, record.Spec.Level))
		if record.Spec.Level > previousHighest and record.Spec.Level > 0 then
			player:SetAttribute("LastObjectiveCompleted", "IslandExploration")
		end
		player:SetAttribute(
			"HighestCompletedIslandIndex",
			math.max(
				tonumber(player:GetAttribute("HighestCompletedIslandIndex")) or 0,
				math.max(0, record.Spec.Level - 1)
			)
		)
		GameplayAnalytics.RecordIslandReached(
			player,
			record.Spec.Level,
			record.Spec.IsSanctuary,
			false
		)
	end
end

local function prepareApproachedFrontiers(playerRoots)
	local now = os.clock()
	for _, entry in ipairs(playerRoots) do
		local currentIslandKey = entry.Player:GetAttribute("CurrentIslandKey")
		local currentLevel = entry.Player:GetAttribute("CurrentLogicalLevel")
		local best
		local bestScore = math.huge
		local bestCanExpand = false
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
							bestCanExpand = not record.Expanded
								and not record.Expanding
								and not record.ScheduledExpansionRoundId
						end
					end
				end
			end
		end

		if not best then
			local previousIntent = playerApproachIntents[entry.Player]
			if not previousIntent
				or not previousIntent.LastConfirmedAt
				or now - previousIntent.LastConfirmedAt
					> Config.FRONTIER_INTENT_PUBLISH_STALE_SECONDS
			then
				clearPublishedApproachTarget(entry.Player)
				playerApproachIntents[entry.Player] = nil
			end
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
		local movingToward = false
		if not intent or intent.TargetKey ~= best.Key then
			if intent and intent.TargetKey ~= best.Key then
				clearPublishedApproachTarget(entry.Player)
			end
			intent = {
				TargetKey = best.Key,
				LastScore = bestScore,
				Progress = 0,
				Sustain = 0,
				LastSampleAt = now,
				LastConfirmedAt = nil,
				Published = false,
				CooldownUntil = intent and intent.CooldownUntil or 0,
			}
			playerApproachIntents[entry.Player] = intent
		else
			local elapsed = math.clamp(now - intent.LastSampleAt, 0, 0.5)
			local improvement = intent.LastScore - bestScore
			movingToward = movingSpeed >= Config.FRONTIER_INTENT_MIN_MOVE_SPEED_STUDS
				and alignment >= Config.FRONTIER_INTENT_MIN_ALIGNMENT
				and improvement >= -Config.FRONTIER_INTENT_DISTANCE_REGRESSION_TOLERANCE_STUDS
			if movingToward then
				intent.Sustain += elapsed
				intent.Progress += math.max(0, improvement)
				intent.LastConfirmedAt = now
			else
				intent.Sustain = math.max(0, intent.Sustain - elapsed * 2)
			end
			intent.LastScore = bestScore
			intent.LastSampleAt = now
		end

		if movingToward
			and intent.Sustain >= Config.FRONTIER_INTENT_PUBLISH_SUSTAIN_SECONDS
			and intent.Progress >= Config.FRONTIER_INTENT_PUBLISH_MIN_PROGRESS_STUDS
		then
			publishApproachTarget(entry.Player, best, intent)
		elseif intent.Published
			and intent.LastConfirmedAt
			and now - intent.LastConfirmedAt > Config.FRONTIER_INTENT_PUBLISH_STALE_SECONDS
		then
			clearPublishedApproachTarget(entry.Player)
			intent.Published = false
		end

		if bestCanExpand
			and now >= intent.CooldownUntil
			and intent.Sustain >= Config.FRONTIER_INTENT_SUSTAIN_SECONDS
			and intent.Progress >= Config.FRONTIER_INTENT_MIN_PROGRESS_STUDS
		then
			if enqueueExpansion(
				best,
				"PlayerIntent:" .. tostring(entry.Player.UserId),
				math.max(1000, 20000 - bestScore * 10),
				entry.Player.UserId
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

local function isProtectedByFixedRouteWindow(record)
	if not routePlan then
		return false
	end
	if record.Spec.IsBossSanctuary then
		return true
	end
	local protectionIndex = tonumber(
		record.Spec.ProtectionGlobalIslandIndex or record.Spec.GlobalIslandIndex
	)
	if not protectionIndex then
		return false
	end
	local minimumCurrent = math.huge
	local maximumCurrent = -math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local current = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
		if current then
			minimumCurrent = math.min(minimumCurrent, current)
			maximumCurrent = math.max(maximumCurrent, current)
		end
	end
	if minimumCurrent == math.huge then
		minimumCurrent = 1
		maximumCurrent = 1
	end
	local minimumProtected = math.max(1, minimumCurrent - routePlan.PreviousWindowSize)
	local maximumProtected = math.min(routePlan.TotalIslandCount, maximumCurrent + routePlan.FutureWindowSize)
	return protectionIndex >= minimumProtected and protectionIndex <= maximumProtected
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
	if record.Model then
		recycleEdgeModel(record.Model)
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
	if record.Model then
		recycleNodeModel(record.Model)
	end
	nodesByKey[record.Key] = nil
	spatialIndex:Remove(record.Key)
	activeSimulationRecords[record.Key] = nil
	queuedForExpansion[record.Key] = nil
	queuedForDetail[record.Key] = nil
	activeNodeCount -= 1
	removedNodeCount += 1
end

-- Executa no maximo uma pequena quantidade de desreplicacoes por Heartbeat.
-- A agua apenas alimenta esta fila; nunca mais remove varias regioes na mesma
-- chamada. Cada trabalho e revalidado porque um jogador pode ter se aproximado
-- da regiao enquanto ela aguardava.
local function processCleanupQueue()
	if getCleanupQueueLength() == 0 then
		return 0
	end
	cleanupOperationActive = true
	local processed = 0
	local startedAt = os.clock()
	while processed < Config.FRONTIER_CLEANUP_OPERATIONS_PER_FRAME and getCleanupQueueLength() > 0 do
		local job = dequeueCleanupJob()
		if not job then
			break
		end
		processed += 1
		local success, errorMessage = pcall(function()
			if job.Type == "Node" then
				queuedCleanupNodes[job.Key] = nil
				local record = nodesByKey[job.Key]
				if record
					and activeNodeCount > job.MinimumToKeep
					and not record.Spec.IsStart
					and record.TopWorldY + job.Margin < latestWaterY
					and not hasAlivePlayerNear(record)
					and not record.Expanding
					and not record.ScheduledExpansionRoundId
				then
					removeNode(record)
				end
			elseif job.Type == "Edge" then
				queuedCleanupEdges[job.Key] = nil
				local record = edgesByKey[job.Key]
				if record
					and (
						record.TopWorldY + job.Margin < latestWaterY
						or not nodesByKey[record.SourceKey]
						or not nodesByKey[record.TargetKey]
					)
				then
					removeEdge(record)
				end
			end
		end)
		if not success then
			queuedCleanupNodes[job.Key] = nil
			queuedCleanupEdges[job.Key] = nil
			warn(string.format("[SkyDungeon] Cleanup parcelado falhou em %s: %s", job.Key, tostring(errorMessage)))
		end
		if os.clock() - startedAt >= Config.FRONTIER_CLEANUP_TIME_BUDGET_SECONDS then
			break
		end
	end
	cleanupOperationActive = false
	updateWorldAttributes()
	return processed
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
				CycleIndex = tonumber(record.Spec.CycleIndex)
					or tonumber(record.Model:GetAttribute("CycleIndex"))
					or 1,
				IslandIndexInCycle = tonumber(record.Spec.IslandIndexInCycle)
					or tonumber(record.Model:GetAttribute("IslandIndexInCycle"))
					or 1,
				LevelInCycle = tonumber(record.Spec.LevelInCycle)
					or tonumber(record.Model:GetAttribute("LevelInCycle"))
					or 1,
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

function ChunkManager.GetSafeZoneContext(position, horizontalPadding, verticalPadding)
	if typeof(position) ~= "Vector3" then
		return nil
	end
	horizontalPadding = math.max(0, tonumber(horizontalPadding) or 0)
	verticalPadding = math.max(0, tonumber(verticalPadding) or 12)

	local best
	local bestDistance = math.huge
	for _, record in ipairs(queryNearbyRecords(position, horizontalPadding + 8)) do
		local isSanctuary = record.Spec.IsSanctuary == true
			or record.Model:GetAttribute("IsSanctuary") == true
			or record.IslandModel:GetAttribute("IsSanctuary") == true
		local isVillage = record.Model:GetAttribute("VillageSpawned") == true
			or record.IslandModel:GetAttribute("VillageSpawned") == true
		if (isSanctuary or isVillage)
			and pointInsideIsland(record, position, horizontalPadding, verticalPadding)
		then
			local distance = (position - record.Floor.Position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = {
					IslandKey = record.Key,
					IsSanctuary = isSanctuary,
					IsVillage = isVillage,
					ZoneType = isVillage and "Village" or "Sanctuary",
					LogicalLevel = record.Spec.Level,
					IsEmergency = record.Spec.IsEmergency == true
						or record.Model:GetAttribute("IsEmergencySanctuary") == true,
					IsSubmerged = record.Model:GetAttribute("SanctuarySubmerged") == true,
					SurfaceY = record.Floor.Position.Y + record.Floor.Size.Y / 2,
					CFrame = CFrame.new(record.Floor.Position + Vector3.new(
						0,
						record.Floor.Size.Y / 2 + 3,
						0
					)),
					Floor = record.Floor,
					Model = record.Model,
					IslandModel = record.IslandModel,
				}
			end
		end
	end
	return best
end

function ChunkManager.Start(options)
	if running then
		return true
	end
	runtimeOptions = type(options) == "table" and options or {}
	routePlan = type(runtimeOptions.RoutePlan) == "table" and runtimeOptions.RoutePlan or nil
	maximumIslandCount = math.max(1, math.floor(tonumber(runtimeOptions.MaximumIslandCount) or math.huge))
	if routePlan then
		local physicalCount = math.max(
			math.floor(tonumber(routePlan.PhysicalIslandCount) or 0),
			#(routePlan.Nodes or {}),
			math.floor(tonumber(routePlan.TotalIslandCount) or 0)
		)
		maximumIslandCount = math.max(maximumIslandCount, physicalCount + 1)
	end
	phaseReadySignaled = false
	fixedRouteState = nil
	routeNodeByGlobalIndex = {}
	bossSanctuaryRecord = nil
	validateConfig()
	baseSeed = tonumber(runtimeOptions.Seed) or Config.SEED or (os.time() % 2147483647)
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
	cleanupOperationActive = false
	cleanupQueue = {}
	cleanupQueueHead = 1
	cleanupQueueTail = 0
	queuedCleanupNodes = {}
	queuedCleanupEdges = {}
	cleanupGetsNextSharedFrame = true
	lastGeometryOperationAt = -math.huge
	spatialIndex = SpatialHash.new(Config.FRONTIER_SPATIAL_HASH_CELL_STUDS)
	activeSimulationRecords = {}
	nodePoolBySignature = {}
	edgePoolBySignature = {}
	pooledNodeCount = 0
	pooledEdgeCount = 0
	reusedNodeCount = 0
	reusedEdgeCount = 0
	lastWorldAttributeUpdateAt = -math.huge
	playerVisitedNodes = setmetatable({}, { __mode = "k" })
	playerApproachIntents = setmetatable({}, { __mode = "k" })
	emergencyGenerationInProgress = false
	for _, player in ipairs(Players:GetPlayers()) do
		clearPublishedApproachTarget(player)
	end
	latestCollectiveSnapshot = CollectiveProgressService.GetSnapshot()
	prepareWorld()
	local startSpec = routePlan and routePlan.Nodes[1]
		or IslandGraphPlanner.GetNodeSpec(baseSeed, 0, 0, 0)
	local startNode, _, startError = createNode(startSpec, "WorldStart")
	if not startNode then
		if worldModel then
			worldModel:SetAttribute("InitialGenerationSuccessful", false)
			worldModel:SetAttribute("InitialGenerationError", tostring(startError or "WorldStartFailed"))
		end
		running = false
		warn("[SkyDungeon] Falha ao criar a ilha inicial: " .. tostring(startError))
		return false, startError
	end
	-- IsRunning so se torna verdadeiro depois que existe uma ilha inicial
	-- utilizavel. Assim uma falha de bootstrap pode ser tentada novamente.
	running = true
	startNode.Model:SetAttribute("Discovered", false)
	enqueueDetail(startNode, false, 2000)
	if routePlan then
		local physicalCount = routePhysicalIslandCount()
		local initialTargetNodeIndex = math.clamp(
			math.floor(tonumber(routePlan.InitialWindowSize) or 1),
			1,
			physicalCount
		)
		local initialObjectiveLookahead = math.min(
			routePlan.TotalIslandCount,
			1 + math.max(1, math.floor(tonumber(routePlan.FutureWindowSize) or 3))
		)
		local initialLookaheadNodeIndex = routeMaterializationIndex(initialObjectiveLookahead)
		if initialLookaheadNodeIndex then
			initialTargetNodeIndex = math.max(initialTargetNodeIndex, initialLookaheadNodeIndex)
		end
		fixedRouteState = {
			NextNodeIndex = 2,
			MaterializedNodeCount = 1,
			TargetNodeIndex = initialTargetNodeIndex,
			InitialTargetNodeIndex = initialTargetNodeIndex,
			PendingRecord = nil,
			PendingNodeIndex = nil,
			PendingEdgeIndex = nil,
			InitialReady = initialTargetNodeIndex <= 1,
			FullRouteReady = physicalCount <= 1,
		}
		worldModel:SetAttribute("FixedRouteEnabled", true)
		worldModel:SetAttribute("FixedRouteTopology", tostring(routePlan.Topology or "BranchedGraph"))
		worldModel:SetAttribute("FixedRouteId", routePlan.RouteId)
		worldModel:SetAttribute("FixedRouteIslandCount", routePlan.TotalIslandCount)
		worldModel:SetAttribute("FixedRouteObjectiveIslandCount", routePlan.TotalIslandCount)
		worldModel:SetAttribute("FixedRoutePhysicalIslandCount", physicalCount)
		worldModel:SetAttribute("FixedRouteOptionalIslandCount", math.max(0, physicalCount - routePlan.TotalIslandCount))
		worldModel:SetAttribute("FixedRouteMaterializedThrough", 1)
		fixedRouteLastMaterializedAt = os.clock()
		fixedRouteLastProgressRefreshAt = os.clock()
		workspace:SetAttribute("DungeonRouteMaterializedNodeCount", 1)
		workspace:SetAttribute("DungeonRouteMaterializationTargetNode", initialTargetNodeIndex)
		workspace:SetAttribute("DungeonRouteMaterializationStalled", false)
		workspace:SetAttribute("DungeonRouteProgressWatchdogPolicy", "ObjectiveLookaheadV1")
		workspace:SetAttribute("DungeonRouteId", routePlan.RouteId)
		workspace:SetAttribute("DungeonRouteIslandCount", routePlan.TotalIslandCount)
		workspace:SetAttribute("DungeonPhysicalIslandCount", physicalCount)
		if fixedRouteState.InitialReady then
			markInitialFixedRouteReady()
		end
		if fixedRouteState.FullRouteReady then
			signalFixedRouteReady(startNode)
		end
	else
		-- O mapa inicial legado nasce com um round inteiro.
		enqueueExpansion(startNode, "WorldBootstrap", 100000)
	end
	startDetailWorker()
	updateWorldAttributes(true)

	-- Nunca mantenha jogadores presos na tela inicial se o primeiro round ficar
	-- parcialmente bloqueado. A ilha inicial ja possui piso seguro neste ponto;
	-- o restante do mundo continua sendo gerado normalmente em segundo plano.
	task.delay(20, function()
		if
			running
			and worldModel
			and worldModel.Parent
			and worldModel:GetAttribute("InitialGenerationComplete") ~= true
			and startNode.Model
			and startNode.Model.Parent
			and startNode.Floor
			and startNode.Floor.Parent
		then
			worldModel:SetAttribute("InitialGenerationSuccessful", false)
			worldModel:SetAttribute("InitialGenerationFallback", true)
			worldModel:SetAttribute("InitialGenerationComplete", true)
			warn("[SkyDungeon] Geracao inicial liberada pelo fallback apos 20 segundos.")
		end
	end)

	-- Geometria usa um unico worker global. Mesmo com muitos jogadores somente
	-- uma pequena operacao e publicada por frame, escolhendo primeiro a fronteira
	-- mais proxima ou um fallback de toque.
	task.spawn(function()
		while running do
			RunService.Heartbeat:Wait()
			if not detailOperationActive then
				if routePlan then
					refreshFixedRouteTargetFromProgress("Heartbeat")
					local progressed = processFixedRoute()
					if progressed > 0 then
						lastGeometryOperationAt = os.clock()
						workspace:SetAttribute("DungeonRouteMaterializationStalled", false)
					elseif fixedRouteState
						and not fixedRouteState.FullRouteReady
						and fixedRouteState.TargetNodeIndex > fixedRouteState.MaterializedNodeCount
						and os.clock() - fixedRouteLastMaterializedAt >= 6
					then
						fixedRouteState.RetryAt = nil
						workspace:SetAttribute("DungeonRouteMaterializationStalled", true)
						workspace:SetAttribute(
							"DungeonRouteMaterializationStalledAt",
							workspace:GetServerTimeNow()
						)
					end
				else
					local hasCleanup = getCleanupQueueLength() > 0
					local hasExpansion = #expansionQueue > 0
					local shouldClean = hasCleanup and (not hasExpansion or cleanupGetsNextSharedFrame)
					local cleaned = shouldClean and processCleanupQueue() or 0
					if hasCleanup and hasExpansion then
						cleanupGetsNextSharedFrame = not shouldClean
					else
						cleanupGetsNextSharedFrame = true
					end
					if cleaned == 0 and processExpansionQueue() > 0 then
						lastGeometryOperationAt = os.clock()
					end
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
	return true
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
	local currentRecord

	for _, record in pairs(nodesByKey) do
		if record.Spec.Level == currentLevel then
			currentRecord = record
			break
		end
	end

	local generatedCycleCount,
		activeCycleCount =
			getCycleStats()

	return {
		CurrentRound = currentLevel,
		CurrentCycle = cycleIndexForRecord(currentRecord),
		GeneratedRounds = highestLogicalLevel,
		GeneratedCycles = generatedCycleCount,
		ActiveRounds = activeNodeCount,
		ActiveCycles = activeCycleCount,
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
		PooledIslands = pooledNodeCount,
		PooledConnections = pooledEdgeCount,
		ReusedIslands = reusedNodeCount,
		ReusedConnections = reusedEdgeCount,
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

local function sanctuaryContext(record, rootOffsetStuds)
	if not record
		or not record.Spec.IsSanctuary
		or not record.Model
		or not record.Model.Parent
		or not record.Floor
		or not record.Floor.Parent
	then
		return nil
	end
	local surfaceY = record.Floor.Position.Y + record.Floor.Size.Y / 2
	return {
		IslandKey = record.Key,
		LogicalLevel = record.Spec.Level,
		LaneX = record.Spec.LaneX,
		LaneZ = record.Spec.LaneZ,
		IsEmergency = record.Spec.IsEmergency == true
			or record.Model:GetAttribute("IsEmergencySanctuary") == true,
		IsSubmerged = record.Model:GetAttribute("SanctuarySubmerged") == true,
		SurfaceY = surfaceY,
		CFrame = CFrame.new(record.Floor.Position + Vector3.new(
			0,
			record.Floor.Size.Y / 2 + (rootOffsetStuds or 3),
			0
		)),
		Floor = record.Floor,
		Model = record.Model,
		IslandModel = record.IslandModel,
	}
end

function ChunkManager.GetSanctuaryContexts(rootOffsetStuds)
	local result = {}
	for _, record in pairs(nodesByKey) do
		local context = sanctuaryContext(record, rootOffsetStuds)
		if context then
			table.insert(result, context)
		end
	end
	table.sort(result, function(left, right)
		if left.LogicalLevel ~= right.LogicalLevel then
			return left.LogicalLevel < right.LogicalLevel
		end
		return left.IslandKey < right.IslandKey
	end)
	return result
end

function ChunkManager.GetSanctuaryByKey(islandKey, rootOffsetStuds)
	if type(islandKey) ~= "string" then
		return nil
	end
	return sanctuaryContext(nodesByKey[islandKey], rootOffsetStuds)
end

function ChunkManager.SetSanctuarySubmerged(islandKey, submerged, waterSurfaceY)
	local record = type(islandKey) == "string" and nodesByKey[islandKey] or nil
	if not record or not record.Spec.IsSanctuary then
		return false
	end
	local value = submerged == true
	for _, model in ipairs({ record.Model, record.IslandModel }) do
		if model and model.Parent then
			model:SetAttribute("SanctuarySubmerged", value)
			model:SetAttribute("SanctuaryValid", not value)
			if value then
				model:SetAttribute("SanctuarySubmergedAtWaterY", waterSurfaceY)
			end
		end
	end
	return true
end

function ChunkManager.GetNextSafeSanctuary(originIslandKey, waterSurfaceY, clearanceStuds, rootOffsetStuds)
	local minimumY = (tonumber(waterSurfaceY) or latestWaterY)
		+ math.max(0, tonumber(clearanceStuds) or 0)
	local origin = type(originIslandKey) == "string" and nodesByKey[originIslandKey] or nil
	local originLevel = origin and origin.Spec.Level or -1
	local targetY = latestCollectiveSnapshot.MeanY or minimumY
	local best
	local bestScore = math.huge
	for _, record in pairs(nodesByKey) do
		local context = sanctuaryContext(record, rootOffsetStuds)
		if context
			and context.IslandKey ~= originIslandKey
			and not context.IsSubmerged
			and context.SurfaceY >= minimumY
		then
			local isForward = context.LogicalLevel > originLevel
			local forwardPenalty = isForward and 0 or 100000
			local score = forwardPenalty
				+ math.abs(context.SurfaceY - targetY)
				+ math.max(0, context.LogicalLevel - originLevel) * 0.01
			if score < bestScore then
				best = context
				bestScore = score
			end
		end
	end
	return best
end

function ChunkManager.GetSafeRespawnCFrame(waterSurfaceY, clearanceStuds, rootOffsetStuds)
	local context = ChunkManager.GetNextSafeSanctuary(
		nil,
		waterSurfaceY,
		clearanceStuds,
		rootOffsetStuds
	)
	return context and context.CFrame or nil
end

function ChunkManager.RequestEmergencySanctuary(waterSurfaceY, clearanceStuds, generationOwnerUserId)
	if not running or not worldModel then
		return false, "ChunkManagerNotRunning"
	end
	latestWaterY = waterSurfaceY
	if ChunkManager.GetNextSafeSanctuary(nil, waterSurfaceY, clearanceStuds, 3) then
		return true, "AlreadyAvailable"
	end
	if emergencyGenerationInProgress then
		return true, "GenerationInProgress"
	end
	emergencyGenerationInProgress = true
	task.spawn(function()
		local success, errorMessage = xpcall(function()
			local source
			for _, record in pairs(nodesByKey) do
				if record.Model and record.Model.Parent and (
					not source
					or record.Spec.Level > source.Spec.Level
					or (record.Spec.Level == source.Spec.Level and record.TopWorldY > source.TopWorldY)
				) then
					source = record
				end
			end
			assert(source, "NoSourceIsland")
			local requiredSurfaceY = (tonumber(waterSurfaceY) or latestWaterY)
				+ math.max(0, tonumber(clearanceStuds) or 0)
			local selectedSpec
			for levelDelta = 1, 32 do
				local level = source.Spec.Level + levelDelta
				local coordinates = {
					{ source.Spec.LaneX + levelDelta, source.Spec.LaneZ },
					{ source.Spec.LaneX - levelDelta, source.Spec.LaneZ },
					{ source.Spec.LaneX, source.Spec.LaneZ + levelDelta },
					{ source.Spec.LaneX, source.Spec.LaneZ - levelDelta },
				}
				for _, coordinate in ipairs(coordinates) do
					local spec = IslandGraphPlanner.GetNodeSpec(
						baseSeed,
						coordinate[1],
						coordinate[2],
						level
					)
					local estimatedSurfaceY = Config.CENTER_WORLD.Y
						+ physicalWorldOffsetY
						+ spec.Center.Y * Config.GRID_SIZE
						+ Config.ISLAND_FLOOR_THICKNESS_STUDS / 2
					if not nodesByKey[spec.Key] and estimatedSurfaceY >= requiredSurfaceY then
						selectedSpec = table.clone(spec)
						break
					end
				end
				if selectedSpec then
					break
				end
			end
			assert(selectedSpec, "NoEmergencyCoordinate")
			selectedSpec.IsSanctuary = true
			selectedSpec.IsEmergency = true
			selectedSpec.IsStart = false
			selectedSpec.Role = "EmergencySanctuary"
			selectedSpec.SizeName = Config.FRONTIER_SANCTUARY_SIZE
			local record, created, creationError = createNode(
				selectedSpec,
				"EmergencySanctuary",
				generationOwnerUserId
			)
			assert(record and created, creationError or "EmergencyNodeNotCreated")
			record.Model:SetAttribute("EmergencyMinimumWaterY", requiredSurfaceY)
			record.Model:SetAttribute("EmergencyCreatedAt", workspace:GetServerTimeNow())
			record.IslandModel:SetAttribute("EmergencyMinimumWaterY", requiredSurfaceY)
			record.IslandModel:SetAttribute("EmergencyCreatedAt", workspace:GetServerTimeNow())
			enqueueDetail(record, true, 1000000)
			enqueueExpansion(record, "EmergencyContinuation", 900000, generationOwnerUserId)
			worldModel:SetAttribute(
				"EmergencySanctuaryCreatedSerial",
				(tonumber(worldModel:GetAttribute("EmergencySanctuaryCreatedSerial")) or 0) + 1
			)
			worldModel:SetAttribute("LastEmergencySanctuaryKey", record.Key)
			worldModel:SetAttribute("LastEmergencySanctuaryError", nil)
			updateWorldAttributes(true)
		end, debug.traceback)
		emergencyGenerationInProgress = false
		if not success then
			if worldModel and worldModel.Parent then
				worldModel:SetAttribute("LastEmergencySanctuaryError", tostring(errorMessage))
			end
			warn("[SkyDungeon] Falha ao gerar santuario emergencial: " .. tostring(errorMessage))
		end
	end)
	return true, "GenerationRequested"
end

-- Adaptador mantido para o fluxo antigo de respawn. Agora toda geracao de
-- emergencia garante uma ilha que e de fato um santuario.
function ChunkManager.RequestSafeRespawnIsland(waterSurfaceY, clearanceStuds)
	return ChunkManager.RequestEmergencySanctuary(waterSurfaceY, clearanceStuds)
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
			and not isProtectedByFixedRouteWindow(record)
			and record.TopWorldY + margin < waterSurfaceY
			and not hasAlivePlayerNear(record)
			and not record.Expanding
			and not record.ScheduledExpansionRoundId
		then
			table.insert(removable, record)
		end
	end
	table.sort(removable, function(a, b)
		return a.Spec.Level < b.Spec.Level
	end)
	local queuedNodeCount = countRecords(queuedCleanupNodes)
	local availableNodeSlots = math.max(0, activeNodeCount - minimumToKeep - queuedNodeCount)
	local queuedNow = 0
	for _, record in ipairs(removable) do
		if availableNodeSlots <= 0 then
			break
		end
		if not queuedCleanupNodes[record.Key] then
			queuedCleanupNodes[record.Key] = true
			enqueueCleanupJob({
				Type = "Node",
				Key = record.Key,
				Margin = margin,
				MinimumToKeep = minimumToKeep,
			})
			availableNodeSlots -= 1
			queuedNow += 1
		end
	end

	for key, edge in pairs(edgesByKey) do
		if not queuedCleanupEdges[key]
			and (
				edge.TopWorldY + margin < waterSurfaceY
				or queuedCleanupNodes[edge.SourceKey]
				or queuedCleanupNodes[edge.TargetKey]
				or not nodesByKey[edge.SourceKey]
				or not nodesByKey[edge.TargetKey]
			)
		then
			queuedCleanupEdges[key] = true
			enqueueCleanupJob({
				Type = "Edge",
				Key = key,
				Margin = margin,
				MinimumToKeep = minimumToKeep,
			})
			queuedNow += 1
		end
	end
	updateWorldAttributes()
	return queuedNow, activeNodeCount
end

function ChunkManager.GetWorldModel()
	return worldModel
end

function ChunkManager.GetEndContext()
	if routePlan then
		local planned = routeNodeByGlobalIndex[routePlan.TotalIslandCount]
		if planned and planned.Model and planned.Model.Parent then
			return routeRecordContext(planned)
		end
	end
	local selected
	for _, record in pairs(nodesByKey) do
		if record.Model and record.Model.Parent and record.Floor and record.Floor.Parent then
			if not selected
				or record.Spec.Level > selected.Spec.Level
				or (record.Spec.Level == selected.Spec.Level and record.CreatedAt > selected.CreatedAt)
			then
				selected = record
			end
		end
	end
	if not selected then
		return nil
	end
	return {
		Key = selected.Key,
		Model = selected.Model,
		IslandModel = selected.IslandModel,
		Floor = selected.Floor,
		LogicalLevel = selected.Spec.Level,
	}
end

function ChunkManager.GetRoutePlan()
	return routePlan
end

function ChunkManager.GetRouteIslandContext(globalIslandIndex)
	local index = math.floor(tonumber(globalIslandIndex) or 0)
	return routeRecordContext(routeNodeByGlobalIndex[index])
end

function ChunkManager.RequestRouteThrough(globalIslandIndex)
	if not routePlan or not fixedRouteState then
		return false, "FixedRouteUnavailable"
	end
	local objectiveTarget = math.clamp(
		math.floor(tonumber(globalIslandIndex) or 1),
		1,
		routePlan.TotalIslandCount
	)
	local nodeTarget = routeMaterializationIndex(objectiveTarget)
	if not nodeTarget then
		return false, "RouteMaterializationMappingMissing"
	end
	fixedRouteState.TargetNodeIndex = math.max(fixedRouteState.TargetNodeIndex, nodeTarget)
	workspace:SetAttribute("DungeonRouteRequestedThroughObjective", objectiveTarget)
	workspace:SetAttribute("DungeonRouteMaterializationTargetNode", fixedRouteState.TargetNodeIndex)
	workspace:SetAttribute("DungeonRouteProgressWatchdogReason", "ExplicitRequest")
	if worldModel and worldModel.Parent then
		worldModel:SetAttribute("FixedRouteTargetNodeIndex", fixedRouteState.TargetNodeIndex)
	end
	return true, objectiveTarget
end

function ChunkManager.CreateBossSanctuary(options)
	options = type(options) == "table" and options or {}
	if not routePlan or not fixedRouteState or not fixedRouteState.FullRouteReady then
		return false, "FixedRouteNotReady"
	end
	if bossSanctuaryRecord and bossSanctuaryRecord.Model and bossSanctuaryRecord.Model.Parent then
		return true, routeRecordContext(bossSanctuaryRecord)
	end
	local finalRecord = routeNodeByGlobalIndex[routePlan.TotalIslandCount]
	if not finalRecord then
		return false, "FinalRouteIslandMissing"
	end
	local record, created, errorMessage = createNode(
		routePlan.BossSanctuary,
		options.Reason or "FinalRewardCommitted",
		options.GenerationOwnerUserId
	)
	if not record then
		return false, errorMessage or "BossSanctuaryCreationFailed"
	end
	local success, edgeOrError = pcall(
		createEdge,
		finalRecord,
		record,
		routePlan.BossSanctuary.IncomingDirectionId
	)
	if not success then
		return false, tostring(edgeOrError)
	end
	finalRecord.Expanded = true
	finalRecord.Model:SetAttribute("Expanded", true)
	finalRecord.Model:SetAttribute("ExpansionState", "BossSanctuaryLinked")
	bossSanctuaryRecord = record
	enqueueDetail(record, false, 100000)
	worldModel:SetAttribute("BossSanctuaryCreated", true)
	workspace:SetAttribute("DungeonBossSanctuaryReady", true)
	local context = routeRecordContext(record)
	local callback = runtimeOptions.OnBossSanctuaryReady
	if type(callback) == "function" then
		task.defer(callback, context)
	end
	return true, context
end

function ChunkManager.GetTotalIslandCount()
	return totalNodeCount
end

function ChunkManager.IsRunning()
	return running
end

function ChunkManager.IsInitialGenerationComplete()
	return worldModel ~= nil
		and worldModel.Parent ~= nil
		and worldModel:GetAttribute("InitialGenerationComplete") == true
end

function ChunkManager.Stop()
	running = false
	for _, player in ipairs(Players:GetPlayers()) do
		clearPublishedApproachTarget(player)
	end
end

return ChunkManager
