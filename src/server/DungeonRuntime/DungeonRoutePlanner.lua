--[[
	Infinity Islands - Tarefa 02
	Linear Combat Route V1

	A rota principal deixa de ser baseada em rounds, reward islands, diamonds
	e boss sanctuary.

	Contrato principal:
	- 24 Combat Islands por padrao;
	- 1 predecessor e no maximo 1 sucessor;
	- todas possuem GlobalIslandIndex;
	- nenhuma ilha principal e Optional/Reward/RoundExit/Boss;
	- direcao varia deterministicamente pela seed;
	- cada passo sobe exatamente um LogicalLevel.

	IMPORTANTE:
	RoundIndex/IslandIndex continuam publicados SOMENTE para compatibilidade
	temporaria com sistemas antigos. Eles nao controlam a topologia.

	A rota final do MVP termina na ultima Combat Island.
	Nao existe BossSanctuary, Reward Island ou branch opcional.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandGraphPlanner = require(
	script.Parent.Parent.BlockParkour.IslandGraphPlanner
)

local WorldConfig = require(
	script.Parent.Parent.BlockParkour.Config_SkyDungeon_V10
)

local CombatRouteSpacingConfig = require(
	ReplicatedStorage.Shared.Configs.CombatRouteSpacingConfig
)

local DungeonRoutePlanner = {}

local MAXIMUM_SEED = 2147483647
local DEFAULT_COMBAT_ISLAND_COUNT = 24

local DIRECTION_IDS = table.freeze({
	"East",
	"South",
	"West",
	"North",
})

local OPPOSITE_DIRECTION = table.freeze({
	East = "West",
	West = "East",
	North = "South",
	South = "North",
})

local function normalizedSeed(value)
	local seed =
		math.floor(
			math.abs(
				tonumber(value) or 1
			)
		) % MAXIMUM_SEED

	return seed == 0 and 1 or seed
end

local function mixedSeed(
	baseSeed,
	globalIndex,
	laneX,
	laneZ,
	level,
	salt
)
	local value = normalizedSeed(baseSeed)

	value =
		(
			value * 48271
			+ globalIndex * 104729
			+ (laneX + 4096) * 130363
			+ (laneZ + 4096) * 155921
			+ level * 196613
			+ (salt or 0)
		) % MAXIMUM_SEED

	return normalizedSeed(value)
end

local function shuffledDirections(seed)
	local result = table.clone(DIRECTION_IDS)
	local random = Random.new(seed)

	for index = #result, 2, -1 do
		local other =
			random:NextInteger(1, index)

		result[index], result[other] =
			result[other], result[index]
	end

	return result
end

local function directionDelta(directionId)
	local direction =
		assert(
			IslandGraphPlanner.GetDirection(
				directionId
			),
			"Direcao desconhecida: "
				.. tostring(directionId)
		)

	return direction.DeltaX, direction.DeltaZ
end

local function terrainHalfExtent(
	spec,
	directionId
)
	local definition =
		assert(
			WorldConfig.TERRAIN_TYPES[
				spec.SizeName
			],
			"Tamanho de ilha desconhecido: "
				.. tostring(
					spec.SizeName
				)
		)

	if directionId == "East"
		or directionId == "West"
	then
		return math.floor(
			definition.Width / 2
		)
	end

	return math.floor(
		definition.Depth / 2
	)
end

local function applyCompactPhysicalCenter(
	sourceSpec,
	targetSpec,
	directionId,
	targetGlobalIslandIndex
)
	local direction =
		assert(
			IslandGraphPlanner.GetDirection(
				directionId
			),
			"Direcao desconhecida: "
				.. tostring(directionId)
		)

	local connectorCells =
		CombatRouteSpacingConfig
			.GetConnectorHorizontalCells(
				targetGlobalIslandIndex
			)

	local sourceHalf =
		terrainHalfExtent(
			sourceSpec,
			directionId
		)

	local targetHalf =
		terrainHalfExtent(
			targetSpec,
			directionId
		)

	local centerSpacingCells =
		sourceHalf
			+ connectorCells
			+ targetHalf

	local verticalRiseCells =
		CombatRouteSpacingConfig
			.VerticalRiseCells

	targetSpec.Center =
		sourceSpec.Center
			+ direction.Vector
				* centerSpacingCells
			+ Vector3.new(
				0,
				verticalRiseCells,
				0
			)

	targetSpec.CombatRouteCompactSpacingVersion =
		CombatRouteSpacingConfig.Version

	targetSpec.IncomingConnectorHorizontalCells =
		connectorCells

	targetSpec.IncomingConnectorHorizontalStuds =
		connectorCells
			* WorldConfig.GRID_SIZE

	targetSpec.IncomingConnectorEstimatedWalkSeconds =
		CombatRouteSpacingConfig
			.EstimatedTraversalSeconds(
				connectorCells,
				WorldConfig.GRID_SIZE
			)

	targetSpec.IncomingCenterSpacingCells =
		centerSpacingCells

	targetSpec.IncomingCenterSpacingStuds =
		centerSpacingCells
			* WorldConfig.GRID_SIZE

	targetSpec.IncomingVerticalRiseCells =
		verticalRiseCells

	targetSpec.IncomingVerticalRiseStuds =
		verticalRiseCells
			* WorldConfig.GRID_SIZE

	sourceSpec.OutgoingConnectorHorizontalCells =
		connectorCells

	sourceSpec.OutgoingConnectorHorizontalStuds =
		connectorCells
			* WorldConfig.GRID_SIZE

	sourceSpec.OutgoingConnectorEstimatedWalkSeconds =
		targetSpec
			.IncomingConnectorEstimatedWalkSeconds

	return connectorCells
end

local function laneKey(x, z)
	return tostring(x) .. ":" .. tostring(z)
end

local function chooseNextDirection(
	baseSeed,
	globalIndex,
	current,
	previousDirection,
	visitedLanes
)
	local directions =
		shuffledDirections(
			mixedSeed(
				baseSeed,
				globalIndex,
				current.LaneX,
				current.LaneZ,
				current.Level,
				49979687
			)
		)

	local opposite =
		previousDirection
			and OPPOSITE_DIRECTION[
				previousDirection
			]
			or nil

	-- Preferencia 1:
	-- nao voltar imediatamente e nao reutilizar uma coordenada horizontal.
	for _, directionId in ipairs(directions) do
		if directionId ~= opposite then
			local dx, dz =
				directionDelta(directionId)

			local key =
				laneKey(
					current.LaneX + dx,
					current.LaneZ + dz
				)

			if not visitedLanes[key] then
				return directionId
			end
		end
	end

	-- Preferencia 2:
	-- ainda evita um U-turn imediato.
	for _, directionId in ipairs(directions) do
		if directionId ~= opposite then
			return directionId
		end
	end

	return directions[1]
end

local function incomingConnection(
	sourceKey,
	directionId
)
	return {
		SourceKey = sourceKey,
		DirectionId = directionId,
		RouteBranchId = nil,
	}
end

local function outgoingConnection(
	targetKey,
	directionId
)
	return {
		TargetKey = targetKey,
		DirectionId = directionId,
		RouteBranchId = nil,
	}
end

local function compatibilityRoundIndices(
	globalIndex
)
	-- Mantem as 12 primeiras ilhas alinhadas aos consumidores antigos:
	-- 1-3 / 4-7 / 8-12.
	if globalIndex <= 3 then
		return 1, globalIndex
	elseif globalIndex <= 7 then
		return 2, globalIndex - 3
	elseif globalIndex <= 12 then
		return 3, globalIndex - 7
	end

	-- Depois da ilha 12 os valores continuam apenas como metadata.
	local offset = globalIndex - 13

	return
		4 + math.floor(offset / 4),
		1 + (offset % 4)
end

local function createCombatSpec(
	baseSeed,
	laneX,
	laneZ,
	level,
	globalIndex,
	incoming
)
	local routeSeed =
		mixedSeed(
			baseSeed,
			globalIndex,
			laneX,
			laneZ,
			level,
			32452843
		)

	local spec =
		table.clone(
			IslandGraphPlanner.GetNodeSpec(
				baseSeed,
				laneX,
				laneZ,
				level
			)
		)

	local compatibilityRound,
		compatibilityIsland =
			compatibilityRoundIndices(
				globalIndex
			)

	spec.Seed = routeSeed
	spec.RouteSeed = routeSeed

	spec.RoundIndex =
		compatibilityRound
	spec.IslandIndex =
		compatibilityIsland
	spec.GlobalIslandIndex =
		globalIndex
	spec.ProtectionGlobalIslandIndex =
		globalIndex

	spec.IsMandatoryRoute = true
	spec.IsOptionalRoute = false
	spec.IsRewardIsland = false
	spec.IsRoundExit = false
	spec.RoundExitIndex = nil
	spec.IsBossSanctuary = false

	spec.IsStart = globalIndex == 1
	spec.IsSanctuary = false
	spec.Role =
		globalIndex == 1
			and "CombatEntry"
			or "CombatIsland"

	spec.RouteBranchId = nil
	spec.AlternateNextDirectionId = nil
	spec.RouteChoiceCount = 1

	spec.IncomingConnections =
		incoming and { incoming } or {}

	spec.IncomingDirectionId =
		incoming
			and incoming.DirectionId
			or nil

	spec.OutgoingConnections = {}
	spec.OutgoingDirectionIds = {}

	spec.RouteEntryCount = 1
	spec.RouteExitCount = 1
	spec.IsRouteConvergence = false
	spec.IsRouteBranchPoint = false

	-- Nova metadata explicita.
	spec.CombatRoute = true
	spec.CombatIsland = true
	spec.LinearRoute = true
	spec.RouteArchitecture =
		"LinearCombatRouteV1"

	return spec
end

function DungeonRoutePlanner.Build(options)
	options =
		type(options) == "table"
			and options
			or {}

	local baseSeed =
		normalizedSeed(options.Seed)

	local totalIslandCount =
		math.clamp(
			math.floor(
				tonumber(
					options.TotalIslandCount
				)
					or DEFAULT_COMBAT_ISLAND_COUNT
			),
			2,
			200
		)

	local nodes =
		table.create(totalIslandCount)

	local materializationIndexByGlobalIndex =
		{}

	local visitedLanes = {}

	local current =
		createCombatSpec(
			baseSeed,
			0,
			0,
			0,
			1,
			nil
		)

	current.RouteNodeOrder = 1
	current.CombatRouteCompactSpacingVersion =
		CombatRouteSpacingConfig.Version
	current.IncomingConnectorHorizontalCells = nil
	current.IncomingConnectorHorizontalStuds = nil
	current.IncomingConnectorEstimatedWalkSeconds = nil
	current.IncomingVerticalRiseCells = nil
	current.IncomingVerticalRiseStuds = nil

	nodes[1] = current
	materializationIndexByGlobalIndex[1] = 1
	visitedLanes[laneKey(0, 0)] = true

	local previousDirection

	local totalConnectorHorizontalCells = 0
	local maximumConnectorHorizontalCells = 0
	local minimumConnectorHorizontalCells = math.huge

	for globalIndex = 2, totalIslandCount do
		local directionId =
			chooseNextDirection(
				baseSeed,
				globalIndex,
				current,
				previousDirection,
				visitedLanes
			)

		local dx, dz =
			directionDelta(directionId)

		local nextSpec =
			createCombatSpec(
				baseSeed,
				current.LaneX + dx,
				current.LaneZ + dz,
				current.Level + 1,
				globalIndex,
				incomingConnection(
					current.Key,
					directionId
				)
			)

		local connectorCells =
			applyCompactPhysicalCenter(
				current,
				nextSpec,
				directionId,
				globalIndex
			)

		totalConnectorHorizontalCells +=
			connectorCells

		maximumConnectorHorizontalCells =
			math.max(
				maximumConnectorHorizontalCells,
				connectorCells
			)

		minimumConnectorHorizontalCells =
			math.min(
				minimumConnectorHorizontalCells,
				connectorCells
			)

		nextSpec.RouteNodeOrder =
			globalIndex

		current.NextDirectionId =
			directionId
		current.OutgoingDirectionIds = {
			directionId,
		}
		current.OutgoingConnections = {
			outgoingConnection(
				nextSpec.Key,
				directionId
			),
		}

		nodes[globalIndex] =
			nextSpec

		materializationIndexByGlobalIndex[
			globalIndex
		] = globalIndex

		visitedLanes[
			laneKey(
				nextSpec.LaneX,
				nextSpec.LaneZ
			)
		] = true

		current = nextSpec
		previousDirection = directionId
	end

	-- O ultimo Combat Island e realmente terminal na nova rota.
	current.NextDirectionId = nil
	current.OutgoingDirectionIds = {}
	current.OutgoingConnections = {}
	current.RouteChoiceCount = 0


	local connectionCount =
		math.max(
			0,
			totalIslandCount - 1
		)

	local averageConnectorHorizontalCells =
		connectionCount > 0
			and totalConnectorHorizontalCells
				/ connectionCount
			or 0

	if minimumConnectorHorizontalCells
		== math.huge
	then
		minimumConnectorHorizontalCells = 0
	end

	return {
		Version = 7,
		MarkerContractVersion = 2,

		CompactSpacingVersion =
			CombatRouteSpacingConfig.Version,

		CompactSpacingPolicy =
			CombatRouteSpacingConfig.Policy,

		ConnectorHorizontalCellsMinimum =
			minimumConnectorHorizontalCells,

		ConnectorHorizontalCellsMaximum =
			maximumConnectorHorizontalCells,

		ConnectorHorizontalCellsAverage =
			averageConnectorHorizontalCells,

		ConnectorHorizontalStudsMinimum =
			minimumConnectorHorizontalCells
				* WorldConfig.GRID_SIZE,

		ConnectorHorizontalStudsMaximum =
			maximumConnectorHorizontalCells
				* WorldConfig.GRID_SIZE,

		ConnectorHorizontalStudsAverage =
			averageConnectorHorizontalCells
				* WorldConfig.GRID_SIZE,

		VerticalRiseCells =
			CombatRouteSpacingConfig
				.VerticalRiseCells,

		VerticalRiseStuds =
			CombatRouteSpacingConfig
				.VerticalRiseCells
				* WorldConfig.GRID_SIZE,

		Topology =
			"LinearCombatRouteV1",

		RouteArchitecture =
			"CombatIslands",

		RouteId =
			string.format(
				"LinearCombat-%d-%d",
				baseSeed,
				totalIslandCount
			),

		Seed = baseSeed,

		-- A nova rota nao possui rounds logicos.
		RoundLengths = {},
		RewardGlobalIndices = {},
		RoundExitGlobalIndices = {},

		TotalIslandCount =
			totalIslandCount,
		ObjectiveIslandCount =
			totalIslandCount,
		PhysicalIslandCount =
			totalIslandCount,
		OptionalIslandCount = 0,

		InitialWindowSize =
			math.min(
				4,
				totalIslandCount
			),

		FutureWindowSize = 3,
		PreviousWindowSize = 1,

		MaterializationIndexByGlobalIndex =
			materializationIndexByGlobalIndex,

		MandatoryNodes = nodes,
		Nodes = nodes,

		BossSanctuary = nil,
		LegacyBossCompatibilityOnly = false,
		BossProgressionEnabled = false,
	}
end

return table.freeze(
	DungeonRoutePlanner
)
