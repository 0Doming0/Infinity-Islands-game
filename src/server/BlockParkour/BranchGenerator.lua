--[[
	Sky Dungeon V7 - BranchGenerator

	A* compartilhado pelas ligacoes principais e pelas salas opcionais. A busca
	trabalha apenas no grid, respeita headroom, nunca desce e pode ligar pontos
	no mesmo nivel. Nenhuma Part e criada aqui.
]]

local Config = require(script.Parent.Config)

local BranchGenerator = {}

local MOVES = {
	{ Delta = Vector3.new(1, 1, 0), Kind = "Rise" },
	{ Delta = Vector3.new(-1, 1, 0), Kind = "Rise" },
	{ Delta = Vector3.new(0, 1, 1), Kind = "Rise" },
	{ Delta = Vector3.new(0, 1, -1), Kind = "Rise" },
	{ Delta = Vector3.new(1, 0, 0), Kind = "Flat" },
	{ Delta = Vector3.new(-1, 0, 0), Kind = "Flat" },
	{ Delta = Vector3.new(0, 0, 1), Kind = "Flat" },
	{ Delta = Vector3.new(0, 0, -1), Kind = "Flat" },
	{ Delta = Vector3.new(2, 0, 0), Kind = "Gap" },
	{ Delta = Vector3.new(-2, 0, 0), Kind = "Gap" },
	{ Delta = Vector3.new(0, 0, 2), Kind = "Gap" },
	{ Delta = Vector3.new(0, 0, -2), Kind = "Gap" },
}

local function moveCost(kind)
	if kind == "Rise" then
		return Config.BRANCH_VERTICAL_MOVE_COST
	elseif kind == "Gap" then
		return Config.BRANCH_GAP_MOVE_COST
	end
	return Config.BRANCH_FLAT_MOVE_COST
end

local function heuristic(cell, goal)
	local vertical = math.max(0, goal.Y - cell.Y)
	local horizontal = math.abs(goal.X - cell.X) + math.abs(goal.Z - cell.Z)
	return math.max(vertical, horizontal / 2)
end

local function reconstructPath(records, finalKey)
	local reversed = {}
	local currentKey = finalKey
	while currentKey do
		local record = records[currentKey]
		table.insert(reversed, record.Cell)
		currentKey = record.ParentKey
	end

	local path = table.create(#reversed)
	for index = #reversed, 1, -1 do
		table.insert(path, reversed[index])
	end
	return path
end

local function heapPush(heap, item)
	table.insert(heap, item)
	local index = #heap
	while index > 1 do
		local parentIndex = math.floor(index / 2)
		if heap[parentIndex].F <= item.F then
			break
		end
		heap[index] = heap[parentIndex]
		index = parentIndex
	end
	heap[index] = item
end

local function heapPop(heap)
	local root = heap[1]
	local last = table.remove(heap)
	if #heap == 0 then
		return root
	end

	local index = 1
	while true do
		local left = index * 2
		local right = left + 1
		if left > #heap then
			break
		end
		local smaller = left
		if right <= #heap and heap[right].F < heap[left].F then
			smaller = right
		end
		if heap[smaller].F >= last.F then
			break
		end
		heap[index] = heap[smaller]
		index = smaller
	end
	heap[index] = last
	return root
end

local function pathHasLocalHeadroom(path, cellKey)
	local pathCells = {}
	for index = 2, #path - 1 do
		pathCells[cellKey(path[index])] = true
	end
	for index = 2, #path - 1 do
		local cell = path[index]
		for offset = 1, Config.HEADROOM_CELLS do
			if pathCells[cellKey(cell + Vector3.new(0, offset, 0))] then
				return false
			end
		end
	end
	return true
end

function BranchGenerator.FindPath(parameters)
	local startCell = assert(parameters.StartCell, "StartCell ausente")
	local endCell = assert(parameters.EndCell, "EndCell ausente")
	local random = assert(parameters.Random, "Random ausente")
	local occupied = assert(parameters.Occupied, "Occupied ausente")
	local reservedHeadroom = assert(parameters.ReservedHeadroom, "ReservedHeadroom ausente")
	local cellKey = assert(parameters.CellKey, "CellKey ausente")
	local isInsideRadius = assert(parameters.IsInsideRadius, "IsInsideRadius ausente")
	local validateJump = assert(parameters.ValidateJump, "ValidateJump ausente")
	local minimumInterior = parameters.MinimumInteriorBlocks or Config.BRANCH_MIN_INTERIOR_BLOCKS
	local maximumNodes = parameters.MaximumNodes or Config.BRANCH_PATHFIND_MAX_NODES
	local maximumPathBlocks = parameters.MaximumPathBlocks or Config.BRANCH_MAX_PATH_BLOCKS
	local minimumY = parameters.MinimumY or startCell.Y
	local maximumY = parameters.MaximumY or endCell.Y

	if endCell.Y < startCell.Y then
		return nil, "o gerador de ligacoes nao permite caminhos descendentes"
	end
	if maximumY < endCell.Y or minimumY > startCell.Y then
		return nil, "limites verticais nao incluem os pontos da ligacao"
	end

	local startKey = cellKey(startCell)
	local endKey = cellKey(endCell)
	local records = {
		[startKey] = {
			Cell = startCell,
			G = 0,
			F = heuristic(startCell, endCell),
			ParentKey = nil,
		},
	}
	local open = {}
	heapPush(open, { Key = startKey, F = records[startKey].F, G = 0 })
	local closed = {}
	local visitedNodes = 0

	local function isAvailable(cell)
		local key = cellKey(cell)
		if key == endKey then
			return true
		end
		if key == startKey or cell.Y < minimumY or cell.Y > maximumY then
			return false
		end
		if not isInsideRadius(cell) or occupied[key] or reservedHeadroom[key] then
			return false
		end
		for offset = 1, Config.HEADROOM_CELLS do
			if occupied[cellKey(cell + Vector3.new(0, offset, 0))] then
				return false
			end
		end
		return true
	end

	while #open > 0 and visitedNodes < maximumNodes do
		local entry = heapPop(open)
		local currentKey = entry.Key
		local latest = records[currentKey]
		if closed[currentKey] or not latest or entry.G ~= latest.G then
			continue
		end

		closed[currentKey] = true
		visitedNodes += 1
		if currentKey == endKey then
			local path = reconstructPath(records, currentKey)
			local interiorCount = #path - 2
			if interiorCount < minimumInterior then
				return nil, "a ligacao ficou curta demais"
			end
			if #path > maximumPathBlocks then
				return nil, string.format("a ligacao excedeu %d blocos", maximumPathBlocks)
			end
			if not pathHasLocalHeadroom(path, cellKey) then
				return nil, "a ligacao invadiu o proprio headroom"
			end
			return path, nil
		end

		local current = latest.Cell
		local firstMove = random:NextInteger(1, #MOVES)
		for offset = 0, #MOVES - 1 do
			local move = MOVES[((firstMove + offset - 1) % #MOVES) + 1]
			local nextCell = current + move.Delta
			local nextKey = cellKey(nextCell)
			if closed[nextKey] or not isAvailable(nextCell) then
				continue
			end

			local validJump = validateJump(current, nextCell)
			if validJump then
				local tentativeG = latest.G + moveCost(move.Kind)
				local existing = records[nextKey]
				if not existing or tentativeG < existing.G then
					local tieBreaker = random:NextNumber(0, 0.08)
					records[nextKey] = {
						Cell = nextCell,
						G = tentativeG,
						F = tentativeG + heuristic(nextCell, endCell) + tieBreaker,
						ParentKey = currentKey,
					}
					heapPush(open, { Key = nextKey, F = records[nextKey].F, G = tentativeG })
				end
			end
		end
	end

	return nil, string.format("nenhuma ligacao segura encontrada apos %d celulas", visitedNodes)
end

return BranchGenerator
