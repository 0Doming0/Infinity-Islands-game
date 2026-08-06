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

local function coordinateKey(x, z)
	return string.format("%d:%d", x, z)
end

local function chooseDirection(baseSeed, roundIndex, islandIndex, globalIndex, previousDirection, laneX, laneZ, visited)
	local directions = shuffledDirections(mixedSeed(baseSeed, roundIndex, islandIndex, globalIndex, 49979687))
	local fallback
	for _, directionId in ipairs(directions) do
		local direction = IslandGraphPlanner.GetDirection(directionId)
		local nextX = laneX + direction.DeltaX
		local nextZ = laneZ + direction.DeltaZ
		local reversesImmediately = previousDirection ~= nil
			and OPPOSITE_DIRECTION[previousDirection] == directionId
		local revisitsHorizontalLane = visited[coordinateKey(nextX, nextZ)] == true
		if not fallback and not reversesImmediately then
			fallback = directionId
		end
		if not reversesImmediately and not revisitsHorizontalLane then
			return directionId
		end
	end
	return fallback or directions[1]
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

local function routeNodeSpec(baseSeed, laneX, laneZ, level, roundIndex, islandIndex, globalIndex, incomingDirectionId, roundLength)
	local spec = table.clone(IslandGraphPlanner.GetNodeSpec(baseSeed, laneX, laneZ, level))
	local seed = mixedSeed(baseSeed, roundIndex, islandIndex, globalIndex, 32452843)
	local isReward = islandIndex == roundLength
	spec.Seed = seed
	spec.RouteSeed = seed
	spec.RoundIndex = roundIndex
	spec.IslandIndex = islandIndex
	spec.GlobalIslandIndex = globalIndex
	spec.IncomingDirectionId = incomingDirectionId
	spec.IsMandatoryRoute = true
	spec.IsRewardIsland = isReward
	spec.IsBossSanctuary = false
	spec.IsSanctuary = false
	spec.IsStart = globalIndex == 1
	spec.Role = isReward and "RewardIsland" or (globalIndex == 1 and "RouteEntry" or "ObjectiveIsland")
	return spec
end

function DungeonRoutePlanner.Build(options)
	options = type(options) == "table" and options or {}
	local baseSeed = normalizedSeed(options.Seed)
	local roundLengths = copyRoundLengths(options.RoundLengths)
	local nodes = {}
	local laneX = 0
	local laneZ = 0
	local level = 0
	local globalIndex = 0
	local previousDirection
	local visited = { [coordinateKey(0, 0)] = true }

	for roundIndex, roundLength in ipairs(roundLengths) do
		for islandIndex = 1, roundLength do
			globalIndex += 1
			local incomingDirectionId
			if globalIndex > 1 then
				incomingDirectionId = chooseDirection(
					baseSeed,
					roundIndex,
					islandIndex,
					globalIndex,
					previousDirection,
					laneX,
					laneZ,
					visited
				)
				local direction = IslandGraphPlanner.GetDirection(incomingDirectionId)
				laneX += direction.DeltaX
				laneZ += direction.DeltaZ
				level += 1
				visited[coordinateKey(laneX, laneZ)] = true
				previousDirection = incomingDirectionId
			end
			nodes[globalIndex] = routeNodeSpec(
				baseSeed,
				laneX,
				laneZ,
				level,
				roundIndex,
				islandIndex,
				globalIndex,
				incomingDirectionId,
				roundLength
			)
		end
	end

	for index, spec in ipairs(nodes) do
		local nextSpec = nodes[index + 1]
		spec.NextDirectionId = nextSpec and nextSpec.IncomingDirectionId or nil
	end

	local bossDirectionId = chooseDirection(
		baseSeed,
		#roundLengths + 1,
		1,
		globalIndex + 1,
		previousDirection,
		laneX,
		laneZ,
		visited
	)
	local bossDirection = IslandGraphPlanner.GetDirection(bossDirectionId)
	if nodes[#nodes] then
		nodes[#nodes].NextDirectionId = bossDirectionId
		nodes[#nodes].RouteExitLeadsToBoss = true
	end
	local bossSpec = table.clone(IslandGraphPlanner.GetNodeSpec(
		baseSeed,
		laneX + bossDirection.DeltaX,
		laneZ + bossDirection.DeltaZ,
		level + 1
	))
	bossSpec.Seed = mixedSeed(baseSeed, #roundLengths + 1, 1, globalIndex + 1, 32452843)
	bossSpec.RouteSeed = bossSpec.Seed
	bossSpec.RoundIndex = #roundLengths + 1
	bossSpec.IslandIndex = 1
	bossSpec.GlobalIslandIndex = globalIndex + 1
	bossSpec.IncomingDirectionId = bossDirectionId
	bossSpec.NextDirectionId = nil
	bossSpec.IsMandatoryRoute = false
	bossSpec.IsRewardIsland = false
	bossSpec.IsBossSanctuary = true
	bossSpec.IsSanctuary = true
	bossSpec.IsStart = false
	bossSpec.Role = "BossSanctuary"

	local rewardIndices = {}
	local cursor = 0
	for roundIndex, length in ipairs(roundLengths) do
		cursor += length
		rewardIndices[roundIndex] = cursor
	end

	return {
		Version = 2,
		MarkerContractVersion = 1,
		RouteId = string.format("FixedRoute-%d", baseSeed),
		Seed = baseSeed,
		RoundLengths = roundLengths,
		RewardGlobalIndices = rewardIndices,
		TotalIslandCount = #nodes,
		InitialWindowSize = math.min(4, #nodes),
		FutureWindowSize = 3,
		PreviousWindowSize = 2,
		Nodes = nodes,
		BossSanctuary = bossSpec,
	}
end

return table.freeze(DungeonRoutePlanner)
