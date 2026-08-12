--[[
	Infinity Islands - Linear Combat Route V8
	Fix: HorizontalLaneReused

	Problem in the previous planner:
	- it preferred an unvisited horizontal lane;
	- when no preferred neighbor was available, its fallback ignored visitedLanes;
	- the safety validator correctly rejected the resulting route with
	  HorizontalLaneReused before the map could materialize.

	V8 uses a deterministic square spiral:
	- segment lengths: 1, 1, 2, 2, 3, 3, ...
	- seed chooses initial cardinal direction;
	- seed chooses clockwise/counter-clockwise turns;
	- every logical X/Z coordinate is unique by construction;
	- every step is still cardinal and increases LogicalLevel by exactly 1.

	The validator is intentionally NOT weakened.
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

local IslandProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.IslandProgressionConfig
)

local DungeonRoutePlanner = {}

local MAXIMUM_SEED = 2147483647
local DEFAULT_COMBAT_ISLAND_COUNT = 24

-- Clockwise order in the logical X/Z plane.
local DIRECTION_IDS = table.freeze({
	"East",
	"South",
	"West",
	"North",
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
	return tostring(x)
		.. ":"
		.. tostring(z)
end

---------------------------------------------------------------------
-- Guaranteed self-avoiding route
---------------------------------------------------------------------

local function createSpiralState(baseSeed)
	local random =
		Random.new(
			mixedSeed(
				baseSeed,
				1,
				0,
				0,
				0,
				86028157
			)
		)

	return {
		DirectionIndex =
			random:NextInteger(
				1,
				#DIRECTION_IDS
			),

		-- +1 = clockwise in DIRECTION_IDS,
		-- -1 = counter-clockwise.
		TurnStep =
			random:NextInteger(0, 1) == 0
				and 1
				or -1,

		SegmentLength = 1,
		StepsRemaining = 1,
		SegmentsAtCurrentLength = 0,
	}
end

local function nextSpiralDirection(state)
	local directionId =
		DIRECTION_IDS[
			state.DirectionIndex
		]

	state.StepsRemaining -= 1

	if state.StepsRemaining <= 0 then
		state.DirectionIndex =
			(
				(
					state.DirectionIndex
					- 1
					+ state.TurnStep
				) % #DIRECTION_IDS
			) + 1

		state.SegmentsAtCurrentLength += 1

		-- Spiral contract:
		-- 1,1,2,2,3,3,...
		if state.SegmentsAtCurrentLength >= 2 then
			state.SegmentsAtCurrentLength = 0
			state.SegmentLength += 1
		end

		state.StepsRemaining =
			state.SegmentLength
	end

	return directionId
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
	-- Legacy metadata only.
	if globalIndex <= 3 then
		return 1, globalIndex
	elseif globalIndex <= 7 then
		return 2, globalIndex - 3
	elseif globalIndex <= 12 then
		return 3, globalIndex - 7
	end

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
	spec.IsInitialIsland =
		globalIndex == 1
	spec.NumberedIslandIndex =
		math.max(0, globalIndex - 1)
	spec.IslandDisplayLabel =
		globalIndex == 1
			and "Inicial"
			or string.format(
				"Ilha %d",
				globalIndex - 1
			)

	local progressionSnapshot =
		IslandProgressionConfig.GetSnapshot(
			globalIndex
		)

	spec.CycleIndex =
		progressionSnapshot.CycleIndex
	spec.IslandIndexInCycle =
		progressionSnapshot.IslandIndexInCycle
	spec.LevelInCycle =
		progressionSnapshot.LevelInCycle
	spec.XPRewardMultiplier =
		progressionSnapshot.XPRewardMultiplier

	spec.IsMandatoryRoute = true
	spec.IsOptionalRoute = false
	spec.IsRewardIsland = false
	spec.IsRoundExit = false
	spec.RoundExitIndex = nil
	spec.IsBossSanctuary = false

	spec.IsStart = spec.IsInitialIsland
	spec.IsSanctuary = false
	spec.Role =
		spec.IsInitialIsland
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

	spec.CombatRoute = true
	spec.CombatIsland = true
	spec.LinearRoute = true
	spec.RouteArchitecture =
		"LinearCombatRouteV1"

	spec.HorizontalLanePolicy =
		"SeededSquareSpiralV1"

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

	materializationIndexByGlobalIndex[1] =
		1

	visitedLanes[laneKey(0, 0)] =
		true

	local spiral =
		createSpiralState(baseSeed)

	local totalConnectorHorizontalCells = 0
	local maximumConnectorHorizontalCells = 0
	local minimumConnectorHorizontalCells = math.huge

	for globalIndex = 2, totalIslandCount do
		local directionId =
			nextSpiralDirection(
				spiral
			)

		local dx, dz =
			directionDelta(
				directionId
			)

		local nextLaneX =
			current.LaneX + dx

		local nextLaneZ =
			current.LaneZ + dz

		local nextLaneKey =
			laneKey(
				nextLaneX,
				nextLaneZ
			)

		-- This should be impossible with the spiral.
		-- Keep the invariant explicit so a future edit cannot silently
		-- reintroduce HorizontalLaneReused.
		assert(
			not visitedLanes[nextLaneKey],
			string.format(
				"SeededSquareSpiral invariant failed at island %d: %s",
				globalIndex,
				nextLaneKey
			)
		)

		local nextSpec =
			createCombatSpec(
				baseSeed,
				nextLaneX,
				nextLaneZ,
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

		visitedLanes[nextLaneKey] =
			true

		current = nextSpec
	end

	-- Last Combat Island is terminal.
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
		Version = 9,
		MarkerContractVersion = 2,

		CompactSpacingVersion =
			CombatRouteSpacingConfig.Version,

		CompactSpacingPolicy =
			CombatRouteSpacingConfig.Policy,

		HorizontalLanePolicy =
			"SeededSquareSpiralV1",

		HorizontalLaneReuseAllowed =
			false,

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

		-- Legacy metadata is intentionally empty.
		RoundLengths = {},
		RewardGlobalIndices = {},
		RoundExitGlobalIndices = {},

		TotalIslandCount =
			totalIslandCount,

		MobCycleLevels =
			IslandProgressionConfig.LevelsPerCycle,

		MobCycleIslandCount =
			IslandProgressionConfig.IslandsPerCycle,

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
