--[[
	Infinity Islands - IslandProgressionService

	TAREFA 01 + TAREFA 06 + TAREFA 08:
	Publica IslandLevel, CycleIndex e o multiplicador de XP nas ilhas
	atuais sem alterar:
	- geracao;
	- spawn de mobs;
	- dano;
	- entrega direta de XP;
	- objective flow;
	- gates.

	Esta etapa e deliberadamente somente de dados/contrato.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.IslandProgressionConfig
)

local IslandProgressionService = {}

local TAG = "SkyDungeonIslandNode"
local started = false
local appliedCount = 0
local connection

local function positiveInteger(value)
	local number = tonumber(value)
	if not number then
		return nil
	end

	number = math.floor(number)
	return number >= 1 and number or nil
end

local function resolveProgressionIndex(node)
	-- Rota principal atual: fonte ideal e estavel.
	local globalIndex = positiveInteger(
		node:GetAttribute("GlobalIslandIndex")
	)

	if globalIndex then
		return globalIndex, "GlobalIslandIndex"
	end

	-- Compatibilidade temporaria com as branches antigas.
	-- Elas serao removidas na Tarefa 02. Enquanto isso, uma branch situada
	-- entre a ilha N e N+1 usa a dificuldade da proxima Combat Island.
	if node:GetAttribute("IsOptionalRoute") == true then
		local protectedIndex = positiveInteger(
			node:GetAttribute("ProtectionGlobalIslandIndex")
		)

		if protectedIndex then
			return protectedIndex + 1, "OptionalRouteCompatibility"
		end
	end

	-- Fallback apenas para nos sem contrato de rota.
	local logicalLevel = tonumber(
		node:GetAttribute("LogicalLevel")
	)

	if logicalLevel then
		return math.max(1, math.floor(logicalLevel) + 1), "LogicalLevelFallback"
	end

	return 1, "DefaultFallback"
end

local function applyAttributes(instance, snapshot, source)
	if not instance then
		return
	end

	instance:SetAttribute(
		"ProgressionIslandIndex",
		snapshot.ProgressionIslandIndex
	)
	instance:SetAttribute(
		"NumberedIslandIndex",
		snapshot.NumberedIslandIndex
	)
	instance:SetAttribute(
		"IsInitialIsland",
		snapshot.NumberedIslandIndex == 0
	)
	instance:SetAttribute(
		"IslandDisplayLabel",
		snapshot.NumberedIslandIndex == 0
			and "Inicial"
			or string.format(
				"Ilha %d",
				snapshot.NumberedIslandIndex
			)
	)
	instance:SetAttribute(
		"IslandLevel",
		snapshot.IslandLevel
	)
	instance:SetAttribute(
		"RecommendedLevel",
		snapshot.RecommendedLevel
	)
	instance:SetAttribute(
		"CycleIndex",
		snapshot.CycleIndex
	)
	instance:SetAttribute(
		"IslandIndexInCycle",
		snapshot.IslandIndexInCycle
	)
	instance:SetAttribute(
		"LevelInCycle",
		snapshot.LevelInCycle
	)
	instance:SetAttribute(
		"XPRewardMultiplier",
		snapshot.XPRewardMultiplier
	)
	instance:SetAttribute(
		"IslandProgressionVersion",
		snapshot.Version
	)
	instance:SetAttribute(
		"IslandLevelSource",
		source
	)
end

local function getIslandModel(node)
	local terrainAreas = node:FindFirstChild("TerrainAreas")
	if not terrainAreas then
		return nil
	end

	for _, child in ipairs(terrainAreas:GetChildren()) do
		if child:IsA("Model")
			and child:GetAttribute("IsSkyIsland") == true
		then
			return child
		end
	end

	return terrainAreas:FindFirstChildWhichIsA("Model")
end

local function applyNode(node)
	if not node
		or not node:IsA("Model")
		or not node.Parent
	then
		return false
	end

	local progressionIndex, source =
		resolveProgressionIndex(node)

	local snapshot =
		IslandProgressionConfig.GetSnapshot(
			progressionIndex
		)

	applyAttributes(node, snapshot, source)

	local islandModel = getIslandModel(node)
	if islandModel then
		applyAttributes(
			islandModel,
			snapshot,
			source
		)

		local floor = islandModel.PrimaryPart
			or islandModel:FindFirstChild("IslandFloor")

		if floor and floor:IsA("BasePart") then
			applyAttributes(
				floor,
				snapshot,
				source
			)
		end
	end

	appliedCount += 1

	workspace:SetAttribute(
		"DungeonIslandProgressionAppliedCount",
		appliedCount
	)

	return true
end

local function publishDiagnostics()
	workspace:SetAttribute(
		"DungeonIslandProgressionReady",
		started
	)
	workspace:SetAttribute(
		"DungeonIslandProgressionVersion",
		IslandProgressionConfig.Version
	)
	workspace:SetAttribute(
		"DungeonIslandStartingLevel",
		IslandProgressionConfig.StartingLevel
	)
	workspace:SetAttribute(
		"DungeonIslandsPerLevel",
		IslandProgressionConfig.IslandsPerLevel
	)
	workspace:SetAttribute(
		"DungeonMobCycleLevels",
		IslandProgressionConfig.LevelsPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobCycleIslandCount",
		IslandProgressionConfig.IslandsPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobCycleIndexPolicy",
		"ServerAuthoritativeByProgressionIslandIndex"
	)
	workspace:SetAttribute(
		"DungeonMobXPPerCycle",
		IslandProgressionConfig.XPRewardPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobXPCyclePolicy",
		"CompoundedFromCycleIndex"
	)
	workspace:SetAttribute(
		"DungeonIslandProgressionPolicy",
		"GrowingLevelGapsByIsland"
	)
	workspace:SetAttribute(
		"DungeonIslandLevelGapPattern",
		"+2,+2,+3,+3,+4,+4..."
	)
end

function IslandProgressionService.Start()
	if started then
		return false, "AlreadyStarted"
	end

	IslandProgressionConfig.Validate()

	started = true
	publishDiagnostics()

	-- Aplica em ilhas que ja existiam quando o service iniciou.
	for _, node in ipairs(
		CollectionService:GetTagged(TAG)
	) do
		applyNode(node)
	end

	-- E em toda ilha criada depois.
	connection =
		CollectionService
			:GetInstanceAddedSignal(TAG)
			:Connect(function(node)
				task.defer(applyNode, node)
			end)

	return true
end

function IslandProgressionService.Stop()
	if not started then
		return false
	end

	started = false

	if connection then
		connection:Disconnect()
		connection = nil
	end

	publishDiagnostics()

	return true
end

function IslandProgressionService.Refresh(node)
	return applyNode(node)
end

function IslandProgressionService.GetSnapshotFor(node)
	if not node then
		return nil
	end

	local progressionIndex, source =
		resolveProgressionIndex(node)

	local snapshot =
		IslandProgressionConfig.GetSnapshot(
			progressionIndex
		)

	snapshot.Source = source

	return snapshot
end

function IslandProgressionService.GetDiagnostics()
	return {
		Ready = started,
		AppliedCount = appliedCount,
		Version = IslandProgressionConfig.Version,
		IslandsPerLevel = IslandProgressionConfig.IslandsPerLevel,
		LevelsPerCycle = IslandProgressionConfig.LevelsPerCycle,
		IslandsPerCycle = IslandProgressionConfig.IslandsPerCycle,
		XPRewardPerCycle = IslandProgressionConfig.XPRewardPerCycle,
	}
end

return IslandProgressionService
