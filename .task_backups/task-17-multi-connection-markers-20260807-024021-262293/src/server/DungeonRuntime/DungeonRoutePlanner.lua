local IslandGraphPlanner = require(script.Parent.Parent.BlockParkour.IslandGraphPlanner)

local DungeonRoutePlanner = {}

local MAXIMUM_SEED = 2147483647
local DEFAULT_ROUND_LENGTHS = table.freeze({ 3, 4, 5 })
local DIRECTION_IDS = table.freeze({ "East", "South", "West", "North" })
local OPPOSITE_DIRECTION = table.freeze({
	East = "West",
	West = "East",
	North = "South",
	South = "North",
})

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % MAXIMUM_SEED
	return seed == 0 and 1 or seed
end

local function mixedSeed(baseSeed, roundIndex, islandIndex, globalIndex, salt)
	local value = normalizedSeed(baseSeed)
	value = (value * 48271 + roundIndex * 104729 + (salt or 0)) % MAXIMUM_SEED
	value = (value * 48271 + islandIndex * 130363) % MAXIMUM_SEED
	value = (value * 48271 + globalIndex * 155921) % MAXIMUM_SEED
	return normalizedSeed(value)
end

local function shuffledDirections(seed)
	local result = table.clone(DIRECTION_IDS)
	local random = Random.new(seed)
	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

local function copyRoundLengths(raw)
	local result = {}
	for index, value in ipairs(type(raw) == "table" and raw or DEFAULT_ROUND_LENGTHS) do
		local length = math.max(1, math.floor(tonumber(value) or 0))
		result[index] = length
	end
	assert(#result > 0, "DungeonRoutePlanner requer ao menos uma rodada")
	return result
end

local function connection(sourceKey, directionId)
	return {
		SourceKey = sourceKey,
		DirectionId = directionId,
	}
end

local function baseNodeSpec(baseSeed, laneX, laneZ, level, seed)
	local spec = table.clone(IslandGraphPlanner.GetNodeSpec(baseSeed, laneX, laneZ, level))
	spec.Seed = seed
	spec.RouteSeed = seed
	spec.IsBossSanctuary = false
	spec.IsSanctuary = false
	spec.IsStart = false
	spec.IncomingConnections = {}
	return spec
end

local function mandatoryNodeSpec(
	baseSeed,
	laneX,
	laneZ,
	level,
	roundIndex,
	islandIndex,
	globalIndex,
	roundLength,
	incomingConnections
)
	local seed = mixedSeed(baseSeed, roundIndex, islandIndex, globalIndex, 32452843)
	local spec = baseNodeSpec(baseSeed, laneX, laneZ, level, seed)
	local isRoundExit = islandIndex == roundLength
	spec.RoundIndex = roundIndex
	spec.IslandIndex = islandIndex
	spec.GlobalIslandIndex = globalIndex
	spec.ProtectionGlobalIslandIndex = globalIndex
	spec.IsMandatoryRoute = true
	spec.IsOptionalRoute = false
	spec.IsRewardIsland = isRoundExit
	spec.IsRoundExit = isRoundExit
	spec.RoundExitIndex = isRoundExit and roundIndex or nil
	spec.IsStart = globalIndex == 1
	spec.Role = isRoundExit and "RewardIsland"
		or (globalIndex == 1 and "RouteEntry" or "ObjectiveIsland")
	spec.IncomingConnections = incomingConnections or {}
	spec.IncomingDirectionId = spec.IncomingConnections[1]
		and spec.IncomingConnections[1].DirectionId
		or nil
	return spec
end

local function optionalNodeSpec(
	baseSeed,
	laneX,
	laneZ,
	level,
	roundIndex,
	sourceIslandIndex,
	protectionGlobalIndex,
	branchId,
	incomingConnection,
	nextDirectionId
)
	local branchNumber = branchId == "A" and 1 or 2
	local seed = mixedSeed(
		baseSeed,
		roundIndex,
		sourceIslandIndex,
		protectionGlobalIndex,
		86028121 + branchNumber * 104729
	)
	local spec = baseNodeSpec(baseSeed, laneX, laneZ, level, seed)
	spec.RoundIndex = roundIndex
	spec.IslandIndex = sourceIslandIndex
	spec.GlobalIslandIndex = nil
	spec.ProtectionGlobalIslandIndex = protectionGlobalIndex
	spec.IsMandatoryRoute = false
	spec.IsOptionalRoute = true
	spec.IsRewardIsland = false
	spec.IsRoundExit = false
	spec.RouteBranchId = string.format("R%d_I%d_%s", roundIndex, sourceIslandIndex, branchId)
	spec.Role = "OptionalRouteIsland"
	spec.IncomingConnections = { incomingConnection }
	spec.IncomingDirectionId = incomingConnection.DirectionId
	spec.NextDirectionId = nextDirectionId
	return spec
end

local function choosePerpendicularPair(baseSeed, roundIndex, islandIndex, globalIndex)
	local directions = shuffledDirections(mixedSeed(
		baseSeed,
		roundIndex,
		islandIndex,
		globalIndex,
		49979687
	))
	local first = directions[1]
	local second
	for index = 2, #directions do
		local candidate = directions[index]
		if candidate ~= first and candidate ~= OPPOSITE_DIRECTION[first] then
			second = candidate
			break
		end
	end
	assert(second, "Nao foi possivel escolher direcoes perpendiculares")
	return first, second
end

local function chooseTransitionDirection(baseSeed, roundIndex, globalIndex, previousDirection)
	local directions = shuffledDirections(mixedSeed(
		baseSeed,
		roundIndex,
		1,
		globalIndex,
		122949829
	))
	for _, directionId in ipairs(directions) do
		if not previousDirection or OPPOSITE_DIRECTION[previousDirection] ~= directionId then
			return directionId
		end
	end
	return directions[1]
end

local function addNode(nodes, spec, materializationIndexByGlobalIndex)
	spec.RouteNodeOrder = #nodes + 1
	nodes[spec.RouteNodeOrder] = spec
	if spec.GlobalIslandIndex then
		materializationIndexByGlobalIndex[spec.GlobalIslandIndex] = spec.RouteNodeOrder
	end
	return spec
end

local function directionDelta(directionId)
	local direction = assert(
		IslandGraphPlanner.GetDirection(directionId),
		"Direcao desconhecida: " .. tostring(directionId)
	)
	return direction.DeltaX, direction.DeltaZ
end

function DungeonRoutePlanner.Build(options)
	options = type(options) == "table" and options or {}
	local baseSeed = normalizedSeed(options.Seed)
	local roundLengths = copyRoundLengths(options.RoundLengths)
	local nodes = {}
	local materializationIndexByGlobalIndex = {}
	local rewardIndices = {}
	local roundExitGlobalIndices = {}
	local mandatoryNodes = {}
	local globalIndex = 0
	local currentMandatory
	local previousDirection

	for roundIndex, roundLength in ipairs(roundLengths) do
		if roundIndex == 1 then
			globalIndex += 1
			currentMandatory = mandatoryNodeSpec(
				baseSeed,
				0,
				0,
				0,
				roundIndex,
				1,
				globalIndex,
				roundLength,
				{}
			)
			addNode(nodes, currentMandatory, materializationIndexByGlobalIndex)
			table.insert(mandatoryNodes, currentMandatory)
		else
			local transitionDirection = chooseTransitionDirection(
				baseSeed,
				roundIndex,
				globalIndex + 1,
				previousDirection
			)
			local deltaX, deltaZ = directionDelta(transitionDirection)
			globalIndex += 1
			local nextRoundEntry = mandatoryNodeSpec(
				baseSeed,
				currentMandatory.LaneX + deltaX,
				currentMandatory.LaneZ + deltaZ,
				currentMandatory.Level + 1,
				roundIndex,
				1,
				globalIndex,
				roundLength,
				{ connection(currentMandatory.Key, transitionDirection) }
			)
			currentMandatory.NextDirectionId = transitionDirection
			currentMandatory.RouteExitLeadsToNextRound = true
			addNode(nodes, nextRoundEntry, materializationIndexByGlobalIndex)
			table.insert(mandatoryNodes, nextRoundEntry)
			currentMandatory = nextRoundEntry
			previousDirection = transitionDirection
		end

		for islandIndex = 2, roundLength do
			local directionA, directionB = choosePerpendicularPair(
				baseSeed,
				roundIndex,
				islandIndex,
				globalIndex + 1
			)
			local deltaAX, deltaAZ = directionDelta(directionA)
			local deltaBX, deltaBZ = directionDelta(directionB)
			local optionalLevel = currentMandatory.Level + 1
			local targetLevel = currentMandatory.Level + 2
			local nextGlobalIndex = globalIndex + 1

			local optionalA = optionalNodeSpec(
				baseSeed,
				currentMandatory.LaneX + deltaAX,
				currentMandatory.LaneZ + deltaAZ,
				optionalLevel,
				roundIndex,
				islandIndex - 1,
				globalIndex,
				"A",
				connection(currentMandatory.Key, directionA),
				directionB
			)
			local optionalB = optionalNodeSpec(
				baseSeed,
				currentMandatory.LaneX + deltaBX,
				currentMandatory.LaneZ + deltaBZ,
				optionalLevel,
				roundIndex,
				islandIndex - 1,
				globalIndex,
				"B",
				connection(currentMandatory.Key, directionB),
				directionA
			)
			local target = mandatoryNodeSpec(
				baseSeed,
				currentMandatory.LaneX + deltaAX + deltaBX,
				currentMandatory.LaneZ + deltaAZ + deltaBZ,
				targetLevel,
				roundIndex,
				islandIndex,
				nextGlobalIndex,
				roundLength,
				{
					connection(optionalA.Key, directionB),
					connection(optionalB.Key, directionA),
				}
			)

			currentMandatory.NextDirectionId = directionA
			currentMandatory.AlternateNextDirectionId = directionB
			currentMandatory.OutgoingDirectionIds = { directionA, directionB }
			currentMandatory.RouteChoiceCount = 2
			optionalA.ConvergesToKey = target.Key
			optionalB.ConvergesToKey = target.Key
			target.ConvergenceSourceKeys = { optionalA.Key, optionalB.Key }

			addNode(nodes, optionalA, materializationIndexByGlobalIndex)
			addNode(nodes, optionalB, materializationIndexByGlobalIndex)
			addNode(nodes, target, materializationIndexByGlobalIndex)
			table.insert(mandatoryNodes, target)
			currentMandatory = target
			globalIndex = nextGlobalIndex
			previousDirection = target.IncomingDirectionId
		end

		rewardIndices[roundIndex] = globalIndex
		roundExitGlobalIndices[roundIndex] = globalIndex
	end

	local bossDirectionId = chooseTransitionDirection(
		baseSeed,
		#roundLengths + 1,
		globalIndex + 1,
		previousDirection
	)
	local bossDeltaX, bossDeltaZ = directionDelta(bossDirectionId)
	currentMandatory.NextDirectionId = bossDirectionId
	currentMandatory.RouteExitLeadsToBoss = true

	local bossSpec = table.clone(IslandGraphPlanner.GetNodeSpec(
		baseSeed,
		currentMandatory.LaneX + bossDeltaX,
		currentMandatory.LaneZ + bossDeltaZ,
		currentMandatory.Level + 1
	))
	bossSpec.Seed = mixedSeed(baseSeed, #roundLengths + 1, 1, globalIndex + 1, 32452843)
	bossSpec.RouteSeed = bossSpec.Seed
	bossSpec.RoundIndex = #roundLengths + 1
	bossSpec.IslandIndex = 1
	bossSpec.GlobalIslandIndex = globalIndex + 1
	bossSpec.ProtectionGlobalIslandIndex = globalIndex
	bossSpec.IncomingDirectionId = bossDirectionId
	bossSpec.IncomingConnections = { connection(currentMandatory.Key, bossDirectionId) }
	bossSpec.NextDirectionId = nil
	bossSpec.IsMandatoryRoute = false
	bossSpec.IsOptionalRoute = false
	bossSpec.IsRewardIsland = false
	bossSpec.IsRoundExit = false
	bossSpec.IsBossSanctuary = true
	bossSpec.IsSanctuary = true
	bossSpec.IsStart = false
	bossSpec.Role = "BossSanctuary"

	return {
		Version = 3,
		MarkerContractVersion = 1,
		Topology = "BranchedRoundDiamonds",
		RouteId = string.format("BranchedRoute-%d", baseSeed),
		Seed = baseSeed,
		RoundLengths = roundLengths,
		RewardGlobalIndices = rewardIndices,
		RoundExitGlobalIndices = roundExitGlobalIndices,
		TotalIslandCount = globalIndex,
		ObjectiveIslandCount = globalIndex,
		PhysicalIslandCount = #nodes,
		OptionalIslandCount = #nodes - globalIndex,
		InitialWindowSize = math.min(4, #nodes),
		FutureWindowSize = 3,
		PreviousWindowSize = 2,
		MaterializationIndexByGlobalIndex = materializationIndexByGlobalIndex,
		MandatoryNodes = mandatoryNodes,
		Nodes = nodes,
		BossSanctuary = bossSpec,
	}
end

return table.freeze(DungeonRoutePlanner)
