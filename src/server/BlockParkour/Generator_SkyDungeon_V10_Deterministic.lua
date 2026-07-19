--[[
	Sky Dungeon V10 - Generator Deterministico

	Cada chamada gera um round vertical completo:
	1. sala principal grande;
	2. uma ou duas salas opcionais de ida e volta;
	3. um salao de reencontro;
	4. uma saida alta que sera reutilizada pelo proximo round.

	A geometria e calculada antes de criar Instances. As ilhas usam pisos mesclados
	para reduzir Parts, mas continuam registradas como Terrain_* e preservam todas
	as celulas logicas para o sistema de conteudo.
]]

local ServerStorage = game:GetService("ServerStorage")

local Config = require(script.Parent.Config_SkyDungeon_V10)
local MonsterSpawner = require(script.Parent.MonsterSpawner)
local IslandTypeService = require(script.Parent.IslandTypeService)
local ChestService = require(script.Parent.ChestService)
local Generator = {}
local warnedMissingDecorationAssets = false
local warnedMissingGrassAssets = false
local spawnGrassModel

local CARDINAL_DIRECTIONS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

local function isInteger(value)
	return value == math.floor(value)
end

local function isMultiple(value, multiple)
	local divided = value / multiple
	return math.abs(divided - math.round(divided)) < 0.0001
end

local function cellKey(cell)
	return string.format("%d,%d,%d", cell.X, cell.Y, cell.Z)
end

local function copyMap(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

local function shuffle(random, source)
	local result = table.clone(source)
	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

local function gridToWorld(cell)
	return Config.CENTER_WORLD + cell * Config.GRID_SIZE
end

local function worldToGrid(position)
	local relative = (position - Config.CENTER_WORLD) / Config.GRID_SIZE
	return Vector3.new(math.round(relative.X), math.round(relative.Y), math.round(relative.Z))
end

local function isInsideRadius(cell)
	local horizontalStuds = Vector2.new(cell.X, cell.Z).Magnitude * Config.GRID_SIZE
	return horizontalStuds <= Config.MAX_RADIUS_STUDS + 0.001
end

local function validateConfig()
	assert(isInteger(Config.GRID_SIZE) and Config.GRID_SIZE >= 4, "[SkyDungeon] GRID_SIZE invalido.")
	assert(isMultiple(Config.MAX_RADIUS_STUDS, Config.GRID_SIZE), "[SkyDungeon] Raio deve alinhar ao grid.")
	assert(Config.HEADROOM_CELLS >= 1, "[SkyDungeon] HEADROOM_CELLS deve ser positivo.")
	assert(
		Config.ISLAND_FLOOR_THICKNESS_STUDS == Config.GRID_SIZE,
		"[SkyDungeon] A espessura do piso precisa coincidir com GRID_SIZE."
	)
	assert(
		Config.ROUND_MAX_VERTICAL_CELLS >= Config.ROUND_MIN_VERTICAL_CELLS,
		"[SkyDungeon] Intervalo vertical de round invalido."
	)
	assert(
		Config.ROUND_HUB_RISE_CELLS > Config.ROUND_MAIN_RISE_CELLS,
		"[SkyDungeon] O salao de reencontro precisa ficar acima da sala principal."
	)
	assert(
		Config.ROUND_MIN_VERTICAL_CELLS > Config.ROUND_HUB_RISE_CELLS,
		"[SkyDungeon] A saida precisa ficar acima do salao de reencontro."
	)
	assert(Config.ROUND_SIDE_RISE_CELLS >= 1, "[SkyDungeon] Subida da sala lateral invalida.")
	assert(
		Config.DECORATION_SPAWN_CHANCE >= 0 and Config.DECORATION_SPAWN_CHANCE <= 1,
		"[SkyDungeon] DECORATION_SPAWN_CHANCE deve ficar entre 0 e 1."
	)
	assert(Config.DECORATION_PATH_PADDING_CELLS >= 0, "[SkyDungeon] Padding de decoracao invalido.")
	assert(Config.DECORATION_MIN_SPACING_CELLS >= 0, "[SkyDungeon] Espacamento de decoracao invalido.")
	assert(Config.GRASS_NOISE_SCALE > 0, "[SkyDungeon] GRASS_NOISE_SCALE invalido.")
	assert(
		Config.GRASS_NOISE_THRESHOLD >= 0 and Config.GRASS_NOISE_THRESHOLD <= 1,
		"[SkyDungeon] GRASS_NOISE_THRESHOLD deve ficar entre 0 e 1."
	)
	assert(Config.GRASS_JITTER_STUDS >= 0, "[SkyDungeon] GRASS_JITTER_STUDS invalido.")
	assert(Config.FLAT_GRASS_LAYER_THICKNESS_STUDS > 0, "[SkyDungeon] Espessura da camada de grama invalida.")
	assert(Config.FLAT_GRASS_SURFACE_OFFSET_STUDS >= 0, "[SkyDungeon] Offset da camada de grama invalido.")
	assert(
		Config.FLAT_GRASS_SURFACE_OFFSET_STUDS < Config.FLAT_GRASS_LAYER_THICKNESS_STUDS,
		"[SkyDungeon] O offset da grama precisa ser menor que a espessura da camada."
	)
	assert(Config.ROUND_MIN_SIDE_ROOMS >= 0, "[SkyDungeon] Quantidade de salas laterais invalida.")
	assert(
		Config.ROUND_MAX_SIDE_ROOMS >= Config.ROUND_MIN_SIDE_ROOMS,
		"[SkyDungeon] Intervalo de salas laterais invalido."
	)
	for name, data in pairs(Config.TERRAIN_TYPES) do
		assert(isInteger(data.Width) and data.Width >= 5 and data.Width % 2 == 1, name .. " Width deve ser impar.")
		assert(isInteger(data.Depth) and data.Depth >= 5 and data.Depth % 2 == 1, name .. " Depth deve ser impar.")
	end
	for _, component in ipairs({ Config.CENTER_WORLD.X, Config.CENTER_WORLD.Y, Config.CENTER_WORLD.Z }) do
		assert(isMultiple(component, Config.GRID_SIZE), "[SkyDungeon] CENTER_WORLD fora do grid.")
	end
end

-- Retorna false quando a transicao excede o movimento conservador do avatar.
local function validateJump(fromCell, toCell)
	local difference = (toCell - fromCell) * Config.GRID_SIZE
	local rise = difference.Y
	local horizontalDistance = Vector2.new(difference.X, difference.Z).Magnitude
	local gap = math.max(0, horizontalDistance - Config.GRID_SIZE)
	if rise < 0 then
		return false, "a rota gerada nao pode descer"
	end
	if rise > Config.MAX_RISE_STUDS then
		return false, "subida acima do limite"
	end
	local maximumGap = rise > 0 and Config.MAX_RISING_GAP_STUDS or Config.MAX_SAME_LEVEL_GAP_STUDS
	if gap > maximumGap + 0.001 then
		return false, "gap horizontal acima do limite"
	end
	if horizontalDistance < 0.001 then
		return false, "movimento vertical puro nao e permitido"
	end
	return true, nil
end

local function reserveCell(occupied, headroom, cell, owner)
	occupied[cellKey(cell)] = owner or true
	for offset = 1, Config.HEADROOM_CELLS do
		headroom[cellKey(cell + Vector3.new(0, offset, 0))] = owner or true
	end
end

local function collectExternalReservations(parent)
	local occupied = {}
	local headroom = {}
	if not parent then
		return occupied, headroom
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant:IsA("Model") and descendant:GetAttribute("IsSkyIsland") == true then
			local minX = descendant:GetAttribute("MinGridX")
			local maxX = descendant:GetAttribute("MaxGridX")
			local minZ = descendant:GetAttribute("MinGridZ")
			local maxZ = descendant:GetAttribute("MaxGridZ")
			local gridY = descendant:GetAttribute("GridY")
			if minX and maxX and minZ and maxZ and gridY then
				for x = minX, maxX do
					for z = minZ, maxZ do
						reserveCell(occupied, headroom, Vector3.new(x, gridY, z), "ExternalIsland")
					end
				end
			end
		elseif descendant:IsA("BasePart") then
			local x = descendant:GetAttribute("GridX")
			local y = descendant:GetAttribute("GridY")
			local z = descendant:GetAttribute("GridZ")
			if x and y and z and descendant:GetAttribute("IsRoundConnector") == true then
				reserveCell(occupied, headroom, Vector3.new(x, y, z), "ExternalConnector")
			end
		end
	end
	return occupied, headroom
end

local function makeIsland(id, role, sizeName, center, forward, right, seed)
	local size = assert(Config.TERRAIN_TYPES[sizeName], "Tipo de ilha desconhecido: " .. sizeName)
	local halfWidth = math.floor(size.Width / 2)
	local halfDepth = math.floor(size.Depth / 2)
	local cells = {}
	local perimeter = {}
	local set = {}
	local minX, maxX, minZ, maxZ

	for lateral = -halfWidth, halfWidth do
		for longitudinal = -halfDepth, halfDepth do
			local cell = center + right * lateral + forward * longitudinal
			table.insert(cells, cell)
			set[cellKey(cell)] = true
			minX = minX and math.min(minX, cell.X) or cell.X
			maxX = maxX and math.max(maxX, cell.X) or cell.X
			minZ = minZ and math.min(minZ, cell.Z) or cell.Z
			maxZ = maxZ and math.max(maxZ, cell.Z) or cell.Z
			if math.abs(lateral) == halfWidth or math.abs(longitudinal) == halfDepth then
				table.insert(perimeter, cell)
			end
		end
	end

	return {
		Id = id,
		Role = role,
		SizeName = sizeName,
		Width = size.Width,
		Depth = size.Depth,
		Center = center,
		Forward = forward,
		Right = right,
		Cells = cells,
		CellSet = set,
		Perimeter = perimeter,
		MinX = minX,
		MaxX = maxX,
		MinZ = minZ,
		MaxZ = maxZ,
		Seed = seed,
		RouteReservations = {},
	}
end

local function perimeterToward(island, target)
	local bestCell = island.Perimeter[1]
	local bestDistance = math.huge
	for _, cell in ipairs(island.Perimeter) do
		local dx = cell.X - target.X
		local dz = cell.Z - target.Z
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			bestDistance = distance
			bestCell = cell
		end
	end
	return bestCell
end

local function corridorCells(fromCell, toCell)
	assert(fromCell.Y == toCell.Y, "[SkyDungeon] Corredor interno precisa ser plano.")
	local cells = { fromCell }
	local current = fromCell
	while current.X ~= toCell.X do
		current += Vector3.new(toCell.X > current.X and 1 or -1, 0, 0)
		table.insert(cells, current)
	end
	while current.Z ~= toCell.Z do
		current += Vector3.new(0, 0, toCell.Z > current.Z and 1 or -1)
		table.insert(cells, current)
	end
	return cells
end

local function markIslandCorridor(island, fromCell, toCell, pathType, pathId)
	for _, cell in ipairs(corridorCells(fromCell, toCell)) do
		local key = cellKey(cell)
		if island.CellSet[key] then
			local existing = island.RouteReservations[key]
			if not existing or pathType == "MainRoute" then
				island.RouteReservations[key] = { Cell = cell, PathType = pathType, PathId = pathId }
			end
		end
	end
end

local function layoutFits(candidate, externalOccupied, externalHeadroom)
	local used = {}
	local maximumRadius = 0
	for _, island in ipairs(candidate.Islands) do
		for _, cell in ipairs(island.Cells) do
			local key = cellKey(cell)
			if used[key] or externalOccupied[key] or externalHeadroom[key] or not isInsideRadius(cell) then
				return false, math.huge
			end
			for offset = 1, Config.HEADROOM_CELLS do
				if externalOccupied[cellKey(cell + Vector3.new(0, offset, 0))] then
					return false, math.huge
				end
			end
			used[key] = true
			maximumRadius = math.max(maximumRadius, Vector2.new(cell.X, cell.Z).Magnitude)
		end
	end
	return true, maximumRadius
end

local function buildLayoutCandidates(random, startGrid, roundIndex, actualSeed, externalOccupied, externalHeadroom)
	local roundRise = random:NextInteger(Config.ROUND_MIN_VERTICAL_CELLS, Config.ROUND_MAX_VERTICAL_CELLS)
	local mainType = Config.MAIN_ISLAND_TYPES[random:NextInteger(1, #Config.MAIN_ISLAND_TYPES)]
	local sideCount = random:NextInteger(Config.ROUND_MIN_SIDE_ROOMS, Config.ROUND_MAX_SIDE_ROOMS)
	local candidates = {}
	local mainSize = Config.TERRAIN_TYPES[mainType]
	local hubSize = Config.TERRAIN_TYPES[Config.HUB_ISLAND_TYPE]
	local exitSize = Config.TERRAIN_TYPES[Config.EXIT_ISLAND_TYPE]
	local sideSize = Config.TERRAIN_TYPES[Config.SIDE_ISLAND_TYPE]
	local mainHalfDepth = math.floor(mainSize.Depth / 2)
	local mainHalfWidth = math.floor(mainSize.Width / 2)
	local hubHalfDepth = math.floor(hubSize.Depth / 2)
	local hubHalfWidth = math.floor(hubSize.Width / 2)
	local exitHalfWidth = math.floor(exitSize.Width / 2)
	local sideHalfWidth = math.floor(sideSize.Width / 2)
	local mainToHubRise = Config.ROUND_HUB_RISE_CELLS - Config.ROUND_MAIN_RISE_CELLS
	local hubToExitRise = roundRise - Config.ROUND_HUB_RISE_CELLS

	for _, forward in ipairs(shuffle(random, CARDINAL_DIRECTIONS)) do
		local right = Vector3.new(-forward.Z, 0, forward.X)
		for _, turnSign in ipairs(shuffle(random, { -1, 1 })) do
			local exitDirection = right * turnSign
			local mainCenter = startGrid
				+ forward * (mainHalfDepth + Config.ROUND_MAIN_RISE_CELLS)
				+ Vector3.new(0, Config.ROUND_MAIN_RISE_CELLS, 0)
			local hubCenter = mainCenter
				+ forward * (mainHalfDepth + mainToHubRise + hubHalfDepth)
				+ Vector3.new(0, mainToHubRise, 0)
			local exitCenter = hubCenter
				+ exitDirection * (hubHalfWidth + hubToExitRise + exitHalfWidth)
				+ Vector3.new(0, hubToExitRise, 0)

			local islands = {
				makeIsland(1, "MainHall", mainType, mainCenter, forward, right, actualSeed + 104729),
				makeIsland(2, "RallyHall", Config.HUB_ISLAND_TYPE, hubCenter, forward, right, actualSeed + 209759),
				makeIsland(
					3,
					"ExitSanctuary",
					Config.EXIT_ISLAND_TYPE,
					exitCenter,
					forward,
					right,
					actualSeed + 314159
				),
			}
			for sideIndex = 1, sideCount do
				local sign = sideIndex == 1 and 1 or -1
				local sideDirection = right * sign
				local sideCenter = mainCenter
					+ sideDirection * (mainHalfWidth + Config.ROUND_SIDE_RISE_CELLS + sideHalfWidth)
					+ Vector3.new(0, Config.ROUND_SIDE_RISE_CELLS, 0)
				table.insert(
					islands,
					makeIsland(
						#islands + 1,
						sign > 0 and "SideRoomRight" or "SideRoomLeft",
						Config.SIDE_ISLAND_TYPE,
						sideCenter,
						forward,
						right,
						actualSeed + 400009 + sideIndex * 7919
					)
				)
			end
			if roundIndex == 1 then
				local entryHalfDepth = math.floor(Config.TERRAIN_TYPES[Config.ENTRY_ISLAND_TYPE].Depth / 2)
				local entryCenter = startGrid - forward * entryHalfDepth
				table.insert(
					islands,
					makeIsland(
						#islands + 1,
						"EntrySanctuary",
						Config.ENTRY_ISLAND_TYPE,
						entryCenter,
						forward,
						right,
						actualSeed + 600011
					)
				)
			end

			local candidate = {
				Forward = forward,
				Right = right,
				ExitDirection = exitDirection,
				RoundRise = roundRise,
				SideCount = sideCount,
				Islands = islands,
				Main = islands[1],
				Hub = islands[2],
				Exit = islands[3],
				Sides = {},
				Archetype = turnSign > 0 and "TurningAscentRight" or "TurningAscentLeft",
			}
			for index = 4, #islands do
				local island = islands[index]
				if string.find(island.Role, "SideRoom", 1, true) then
					table.insert(candidate.Sides, island)
				elseif island.Role == "EntrySanctuary" then
					candidate.Entry = island
				end
			end
			local fits, radius = layoutFits(candidate, externalOccupied, externalHeadroom)
			if fits then
				candidate.Score = radius + random:NextNumber(0, 2.5)
				table.insert(candidates, candidate)
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.Score < b.Score
	end)
	return candidates
end

local function reservePath(path, occupied, headroom, owner)
	for index = 2, #path - 1 do
		reserveCell(occupied, headroom, path[index], owner)
	end
end

-- Escadaria monotonicamente ascendente. A geometria das ilhas garante que a
-- distancia horizontal entre as bordas e exatamente igual a subida vertical.
-- Portanto o caminho nao precisa procurar, curvar ou voltar sobre si mesmo.
local function buildDirectStairPath(startCell, endCell, occupied, headroom)
	local difference = endCell - startCell
	local rise = difference.Y
	local horizontalSteps = math.abs(difference.X) + math.abs(difference.Z)
	if rise <= 0 or horizontalSteps ~= rise then
		return nil, string.format("encaixe invalido: subida %d, distancia horizontal %d", rise, horizontalSteps)
	end

	local stepDirection
	if difference.X ~= 0 and difference.Z == 0 then
		stepDirection = Vector3.new(difference.X > 0 and 1 or -1, 0, 0)
	elseif difference.Z ~= 0 and difference.X == 0 then
		stepDirection = Vector3.new(0, 0, difference.Z > 0 and 1 or -1)
	else
		return nil, "a escadaria deterministica precisa estar alinhada a um eixo"
	end

	local path = { startCell }
	local current = startCell
	local endKey = cellKey(endCell)
	for _ = 1, rise do
		local nextCell = current + stepDirection + Vector3.new(0, 1, 0)
		local key = cellKey(nextCell)
		if key ~= endKey then
			if occupied[key] or headroom[key] or not isInsideRadius(nextCell) then
				return nil, "corredor deterministico bloqueado"
			end
			for offset = 1, Config.HEADROOM_CELLS do
				if occupied[cellKey(nextCell + Vector3.new(0, offset, 0))] then
					return nil, "headroom do corredor deterministico bloqueado"
				end
			end
		end
		local valid, reason = validateJump(current, nextCell)
		if not valid then
			return nil, reason
		end
		table.insert(path, nextCell)
		current = nextCell
	end
	if current ~= endCell then
		return nil, "a escadaria deterministica nao alcancou o destino"
	end
	return path, nil
end

-- Usa um canto do lado oposto a entrada. Assim o proximo round sempre possui
-- duas direcoes livres para sair da ilha, sem cruzar a escadaria que acabou de
-- chegar ao ExitSanctuary.
local function chooseExitEndGrid(candidate)
	local exitIsland = candidate.Exit
	local halfTurnAxis = math.floor(Config.TERRAIN_TYPES[Config.EXIT_ISLAND_TYPE].Width / 2)
	local halfForwardAxis = math.floor(Config.TERRAIN_TYPES[Config.EXIT_ISLAND_TYPE].Depth / 2)
	local farEdgeCenter = exitIsland.Center + candidate.ExitDirection * halfTurnAxis
	local cornerA = farEdgeCenter + candidate.Forward * halfForwardAxis
	local cornerB = farEdgeCenter - candidate.Forward * halfForwardAxis
	local radiusA = Vector2.new(cornerA.X, cornerA.Z).Magnitude
	local radiusB = Vector2.new(cornerB.X, cornerB.Z).Magnitude
	return radiusA <= radiusB and cornerA or cornerB
end

local function tryPlanCandidate(_random, candidate, startGrid, externalOccupied, externalHeadroom)
	local occupied = copyMap(externalOccupied)
	local headroom = copyMap(externalHeadroom)
	for _, island in ipairs(candidate.Islands) do
		for _, cell in ipairs(island.Cells) do
			reserveCell(occupied, headroom, cell, island.Role)
		end
	end

	local mainEntry = perimeterToward(candidate.Main, startGrid)
	local mainExit = perimeterToward(candidate.Main, candidate.Hub.Center)
	local hubEntry = perimeterToward(candidate.Hub, candidate.Main.Center)
	local hubExit = perimeterToward(candidate.Hub, candidate.Exit.Center)
	local exitEntry = perimeterToward(candidate.Exit, candidate.Hub.Center)
	local endGrid = chooseExitEndGrid(candidate)

	local definitions = {
		{ Start = startGrid, Finish = mainEntry, Name = "Entrance" },
		{ Start = mainExit, Finish = hubEntry, Name = "MainAscent" },
		{ Start = hubExit, Finish = exitEntry, Name = "FinalAscent" },
	}
	local mainPaths = {}
	for pathId, definition in ipairs(definitions) do
		local path, reason = buildDirectStairPath(definition.Start, definition.Finish, occupied, headroom)
		if not path then
			return nil, string.format("%s: %s", definition.Name, tostring(reason))
		end
		reservePath(path, occupied, headroom, "MainRoute")
		table.insert(mainPaths, { Cells = path, PathId = pathId, Name = definition.Name })
	end

	markIslandCorridor(candidate.Main, mainEntry, mainExit, "MainRoute", 0)
	markIslandCorridor(candidate.Hub, hubEntry, hubExit, "MainRoute", 0)
	markIslandCorridor(candidate.Exit, exitEntry, endGrid, "MainRoute", 0)
	if candidate.Entry then
		candidate.Entry.RouteReservations[cellKey(startGrid)] = {
			Cell = startGrid,
			PathType = "MainRoute",
			PathId = 0,
		}
	end

	local branchPaths = {}
	local successfulBranches = 0
	if Config.ENABLE_BRANCH_PATHS then
		for branchId, side in ipairs(candidate.Sides) do
			local branchStart = perimeterToward(candidate.Main, side.Center)
			local sideEntry = perimeterToward(side, candidate.Main.Center)
			local outward = buildDirectStairPath(branchStart, sideEntry, occupied, headroom)
			if outward then
				reservePath(outward, occupied, headroom, "BranchRoute")
				successfulBranches += 1
				table.insert(branchPaths, { Cells = outward, PathId = branchId, Name = "BranchRoom" })
				markIslandCorridor(side, sideEntry, side.Center, "BranchRoute", branchId)
				candidate.Main.RouteReservations[cellKey(branchStart)] = {
					Cell = branchStart,
					PathType = "BranchRoute",
					PathId = branchId,
				}
			end
		end
	end

	return {
		Candidate = candidate,
		MainPaths = mainPaths,
		BranchPaths = branchPaths,
		SuccessfulBranches = successfulBranches,
		EndGrid = endGrid,
		Occupied = occupied,
		Headroom = headroom,
	},
	nil
end

local function createFlatGrassLayer(parent, sourcePart, name, roundIndex)
	if not Config.CREATE_FLAT_GRASS_LAYER then
		return nil
	end

	local thickness = Config.FLAT_GRASS_LAYER_THICKNESS_STUDS
	local layer = Instance.new("Part")
	layer.Name = name
	layer.Size = Vector3.new(sourcePart.Size.X, thickness, sourcePart.Size.Z)
	layer.CFrame = sourcePart.CFrame
		* CFrame.new(0, sourcePart.Size.Y / 2 - thickness / 2 + Config.FLAT_GRASS_SURFACE_OFFSET_STUDS, 0)
	layer.Anchored = true
	layer.CanCollide = false
	layer.CanTouch = false
	layer.CanQuery = false
	layer.CastShadow = false
	layer.Material = Enum.Material.Grass
	layer.Color = Config.FLAT_GRASS_COLOR
	layer.TopSurface = Enum.SurfaceType.Smooth
	layer.BottomSurface = Enum.SurfaceType.Smooth
	layer:SetAttribute("IsFlatGrassLayer", true)
	layer:SetAttribute("RoundIndex", roundIndex)
	layer.Parent = parent
	return layer
end

local function createConnector(parent, cell, pathType, pathId, pathName, sequence, roundIndex, grassTemplates)
	local part = Instance.new("Part")
	part.Name = string.format("%s_%02d_%03d", pathName, pathId, sequence)
	part.Size = Vector3.new(Config.GRID_SIZE, Config.GRID_SIZE, Config.GRID_SIZE)
	part.Position = gridToWorld(cell)
	part.Anchored = true
	part.CanCollide = Config.CAN_COLLIDE
	part.CanTouch = true
	part.CanQuery = true
	part.Material = Config.BLOCK_MATERIAL
	part.Color = Config.BLOCK_COLOR
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("BlockType", "Route")
	part:SetAttribute("GridX", cell.X)
	part:SetAttribute("GridY", cell.Y)
	part:SetAttribute("GridZ", cell.Z)
	part:SetAttribute("PathType", pathType)
	part:SetAttribute("PathId", pathId)
	part:SetAttribute("IsMainRoute", pathType == "MainRoute")
	part:SetAttribute("IsRoundConnector", true)
	part:SetAttribute("RoundIndex", roundIndex)
	part.Parent = parent
	createFlatGrassLayer(parent, part, part.Name .. "_GrassTop", roundIndex)
	if Config.GRASS_ON_CONNECTORS and #grassTemplates > 0 then
		local grassSeed = math.max(1, (roundIndex * 7919) % 2147483647)
		local randomSeed = math.max(1, (grassSeed + sequence * 101 + pathId * 1009) % 2147483647)
		local grassRandom = Random.new(randomSeed)
		spawnGrassModel(parent, grassTemplates, cell, grassSeed, grassRandom, part.Name .. "_Grass")
	end
	return part
end

local function islandHasMainRoute(island)
	for _, reservation in pairs(island.RouteReservations) do
		if reservation.PathType == "MainRoute" then
			return true
		end
	end
	return false
end

local function getDecorationTemplates()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local folder = assets and assets:FindFirstChild(Config.DECORATION_FOLDER_NAME)
	if not folder then
		if Config.ENABLE_DECORATIONS and not warnedMissingDecorationAssets then
			warn("[SkyDungeon] Decoracao desativada nesta execucao: crie ServerStorage > MVPAssets > Decorations.")
			warnedMissingDecorationAssets = true
		end
		return {}
	end

	local templates = {}
	for _, template in ipairs(folder:GetChildren()) do
		if (template:IsA("Model") or template:IsA("BasePart")) and template:GetAttribute("Enabled") ~= false then
			local hasPart = template:IsA("BasePart") or template:FindFirstChildWhichIsA("BasePart", true) ~= nil
			if hasPart then
				table.insert(templates, template)
			end
		end
	end
	table.sort(templates, function(a, b)
		return a.Name < b.Name
	end)
	return templates
end

local function getGrassTemplates()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local folder = assets and assets:FindFirstChild(Config.GRASS_FOLDER_NAME)
	if not folder then
		if Config.ENABLE_GRASS_MODELS and not warnedMissingGrassAssets then
			warn("[SkyDungeon] Grama visual ausente: crie ServerStorage > MVPAssets > Grass.")
			warnedMissingGrassAssets = true
		end
		return {}
	end

	local templates = {}
	for _, template in ipairs(folder:GetChildren()) do
		if (template:IsA("Model") or template:IsA("BasePart")) and template:GetAttribute("Enabled") ~= false then
			local hasPart = template:IsA("BasePart") or template:FindFirstChildWhichIsA("BasePart", true) ~= nil
			if hasPart then
				table.insert(templates, template)
			end
		end
	end
	table.sort(templates, function(a, b)
		return a.Name < b.Name
	end)
	return templates
end

local function removeEmbeddedScripts(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
end

local function prepareStaticDecoration(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function getDecorationCandidateCells(island, random)
	local reserved = {}
	for _, reservation in pairs(island.RouteReservations) do
		reserved[cellKey(reservation.Cell)] = true
	end

	local margin = Config.ISLAND_INTERIOR_MARGIN_CELLS
	local padding = Config.DECORATION_PATH_PADDING_CELLS
	local candidates = {}
	for x = island.MinX + margin, island.MaxX - margin do
		for z = island.MinZ + margin, island.MaxZ - margin do
			local blockedByRoute = false
			for offsetX = -padding, padding do
				for offsetZ = -padding, padding do
					local nearby = Vector3.new(x + offsetX, island.Center.Y, z + offsetZ)
					if reserved[cellKey(nearby)] then
						blockedByRoute = true
						break
					end
				end
				if blockedByRoute then
					break
				end
			end
			if not blockedByRoute then
				table.insert(candidates, Vector3.new(x, island.Center.Y, z))
			end
		end
	end
	return shuffle(random, candidates)
end

local function isFarEnoughFromSelected(cell, selected)
	for _, other in ipairs(selected) do
		local distance = math.max(math.abs(cell.X - other.X), math.abs(cell.Z - other.Z))
		if distance < Config.DECORATION_MIN_SPACING_CELLS then
			return false
		end
	end
	return true
end

local function getBoundingBox(instance)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end
	return instance.CFrame, instance.Size
end

local function placeDecoration(instance, surfacePosition, random)
	removeEmbeddedScripts(instance)
	prepareStaticDecoration(instance)

	local originalPivot = instance:GetPivot()
	local boundingCFrame, boundingSize = getBoundingBox(instance)
	local pivotHeightFromBottom = originalPivot.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y / 2)
	local quarterTurn = random:NextInteger(0, 3) * math.pi / 2
	local targetPosition = surfacePosition + Vector3.new(0, pivotHeightFromBottom + 0.05, 0)
	instance:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, quarterTurn, 0) * originalPivot.Rotation)
end

local function getGrassNoise(cell, seed)
	local worldPosition = gridToWorld(cell)
	local seedCoordinate = (math.abs(seed) % 100000) * 0.0001
	local rawNoise = math.noise(
		worldPosition.X * Config.GRASS_NOISE_SCALE,
		worldPosition.Z * Config.GRASS_NOISE_SCALE,
		seedCoordinate
	)
	return math.clamp((rawNoise + 1) / 2, 0, 1)
end

local function prepareGrass(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end
end

spawnGrassModel = function(parent, templates, cell, seed, random, name)
	if not Config.ENABLE_GRASS_MODELS or #templates == 0 then
		return false
	end
	if getGrassNoise(cell, seed) < Config.GRASS_NOISE_THRESHOLD then
		return false
	end

	local template = templates[random:NextInteger(1, #templates)]
	local grass = template:Clone()
	grass.Name = name or template.Name
	grass:SetAttribute("IsSkyGrass", true)
	grass:SetAttribute("GrassAssetName", template.Name)
	grass:SetAttribute("GridX", cell.X)
	grass:SetAttribute("GridY", cell.Y)
	grass:SetAttribute("GridZ", cell.Z)
	prepareGrass(grass)
	grass.Parent = parent

	local originalPivot = grass:GetPivot()
	local boundingCFrame, boundingSize = getBoundingBox(grass)
	local pivotHeightFromBottom = originalPivot.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y / 2)
	local jitterLimit = math.min(Config.GRASS_JITTER_STUDS, Config.GRID_SIZE / 2 - 0.25)
	local jitterX = random:NextNumber(-jitterLimit, jitterLimit)
	local jitterZ = random:NextNumber(-jitterLimit, jitterLimit)
	local rotation = random:NextNumber(0, math.pi * 2)
	local surfacePosition = gridToWorld(cell) + Vector3.new(jitterX, Config.ISLAND_FLOOR_THICKNESS_STUDS / 2, jitterZ)
	local targetPosition = surfacePosition + Vector3.new(0, pivotHeightFromBottom + 0.02, 0)
	grass:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, rotation, 0) * originalPivot.Rotation)
	return true
end

local function populateIslandGrass(model, island, content, grassTemplates)
	model:SetAttribute("GrassSpawnCount", 0)
	if not Config.ENABLE_GRASS_MODELS or #grassTemplates == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "GrassModels"
	folder.Parent = content
	local normalizedSeed = math.max(1, island.Seed % 2147483647)
	local random = Random.new(math.max(1, (normalizedSeed + 67867967) % 2147483647))
	local cells = shuffle(random, island.Cells)
	local maximum = Config.GRASS_MAX_PER_ISLAND[island.SizeName] or 8
	local spawnCount = 0
	for _, cell in ipairs(cells) do
		if spawnCount >= maximum then
			break
		end
		if
			spawnGrassModel(
				folder,
				grassTemplates,
				cell,
				normalizedSeed,
				random,
				string.format("Grass_%02d", spawnCount + 1)
			)
		then
			spawnCount += 1
		end
	end
	model:SetAttribute("GrassSpawnCount", spawnCount)
end

local function decorateIsland(model, island, content, roundIndex)
	local points = Instance.new("Folder")
	points.Name = "DecorationPoints"
	points.Parent = model

	if not Config.ENABLE_DECORATIONS then
		model:SetAttribute("DecorationSpawnCount", 0)
		return
	end

	local templates = getDecorationTemplates()
	if #templates == 0 then
		model:SetAttribute("DecorationSpawnCount", 0)
		return
	end

	local decorations = Instance.new("Folder")
	decorations.Name = "Decorations"
	decorations.Parent = content

	local random = Random.new(math.max(1, (island.Seed + 49979687) % 2147483647))
	local candidates = getDecorationCandidateCells(island, random)
	local maximumAttempts = Config.DECORATION_ATTEMPTS_BY_SIZE[island.SizeName] or 2
	local selected = {}
	local spawnCount = 0

	for _, cell in ipairs(candidates) do
		if #selected >= maximumAttempts then
			break
		end
		if isFarEnoughFromSelected(cell, selected) then
			table.insert(selected, cell)
			local surfacePosition = gridToWorld(cell) + Vector3.new(0, Config.ISLAND_FLOOR_THICKNESS_STUDS / 2, 0)
			local marker = Instance.new("CFrameValue")
			marker.Name = string.format("Point_%02d", #selected)
			marker.Value = CFrame.new(surfacePosition)
			marker:SetAttribute("GridX", cell.X)
			marker:SetAttribute("GridY", cell.Y)
			marker:SetAttribute("GridZ", cell.Z)
			marker:SetAttribute("Populated", false)
			marker.Parent = points

			if random:NextNumber() <= Config.DECORATION_SPAWN_CHANCE then
				local template = templates[random:NextInteger(1, #templates)]
				local decoration = template:Clone()
				decoration.Name = template.Name
				decoration:SetAttribute("IsSkyDecoration", true)
				decoration:SetAttribute("GridX", cell.X)
				decoration:SetAttribute("GridY", cell.Y)
				decoration:SetAttribute("GridZ", cell.Z)
				decoration:SetAttribute("RoundIndex", roundIndex)
				decoration.Parent = decorations
				placeDecoration(decoration, surfacePosition, random)
				marker:SetAttribute("Populated", true)
				marker:SetAttribute("AssetName", template.Name)
				spawnCount += 1
			end
		end
	end
	model:SetAttribute("DecorationSpawnCount", spawnCount)
end

local function createIsland(parent, island, roundIndex, previousCenter, grassTemplates)
	local previousY = previousCenter.Y
	local horizontalCenterDistance = Vector2.new(island.Center.X - previousCenter.X, island.Center.Z - previousCenter.Z).Magnitude
		* Config.GRID_SIZE
	local approximateRadius = math.max(island.Width, island.Depth) * Config.GRID_SIZE / 2
	local edgeGap = math.max(0, horizontalCenterDistance - approximateRadius)
	local model = Instance.new("Model")
	model.Name = string.format("Terrain_%02d_%s_%s", island.Id, island.SizeName, island.Role)
	model:SetAttribute("IsSkyIsland", true)
	model:SetAttribute("TerrainId", island.Id)
	model:SetAttribute("IslandId", island.Id)
	model:SetAttribute("IslandSeed", island.Seed % 2147483647)
	model:SetAttribute("RoundIndex", roundIndex)
	model:SetAttribute("TerrainSize", island.SizeName)
	model:SetAttribute("IslandRole", island.Role)
	model:SetAttribute("CenterGrid", island.Center)
	model:SetAttribute("GridY", island.Center.Y)
	model:SetAttribute("MinGridX", island.MinX)
	model:SetAttribute("MaxGridX", island.MaxX)
	model:SetAttribute("MinGridZ", island.MinZ)
	model:SetAttribute("MaxGridZ", island.MaxZ)
	model:SetAttribute("WidthCells", island.MaxX - island.MinX + 1)
	model:SetAttribute("DepthCells", island.MaxZ - island.MinZ + 1)
	model:SetAttribute("TotalBlockCount", #island.Cells)
	model:SetAttribute("VerticalRiseFromPrevious", (island.Center.Y - previousY) * Config.GRID_SIZE)
	model:SetAttribute("EdgeGapFromPrevious", edgeGap)
	local isSanctuary = island.Role == "ExitSanctuary" or island.Role == "EntrySanctuary"
	model:SetAttribute("CanSpawnItem", not isSanctuary)
	model:SetAttribute("CanSpawnMonster", roundIndex > 1 and not isSanctuary)
	model:SetAttribute("TraversalFromPrevious", island.Role == "MainHall" and "Entrance" or "Ascent")
	model:SetAttribute("AnchorPathType", islandHasMainRoute(island) and "MainRoute" or "BranchRoute")
	model:SetAttribute("AnchorPathId", 0)
	model:SetAttribute("AnchorPathIndex", 0)
	model.Parent = parent

	local floor = Instance.new("Part")
	floor.Name = "IslandFloor"
	floor.Size = Vector3.new(
		(island.MaxX - island.MinX + 1) * Config.GRID_SIZE,
		Config.ISLAND_FLOOR_THICKNESS_STUDS,
		(island.MaxZ - island.MinZ + 1) * Config.GRID_SIZE
	)
	floor.Position = gridToWorld(island.Center)
	floor.Anchored = true
	floor.CanCollide = Config.CAN_COLLIDE
	floor.CanTouch = true
	floor.CanQuery = true
	floor.Material = Config.BLOCK_MATERIAL
	floor.Color = Config.BLOCK_COLOR
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor:SetAttribute("BlockType", "Terrain")
	floor:SetAttribute("TerrainId", island.Id)
	floor:SetAttribute("TerrainSize", island.SizeName)
	floor:SetAttribute("IslandRole", island.Role)
	floor:SetAttribute("IsMainRoute", islandHasMainRoute(island))
	floor:SetAttribute("RoundIndex", roundIndex)
	floor:SetAttribute("GridX", island.Center.X)
	floor:SetAttribute("GridY", island.Center.Y)
	floor:SetAttribute("GridZ", island.Center.Z)
	floor.Parent = model
	model.PrimaryPart = floor
	createFlatGrassLayer(model, floor, "IslandGrassTop", roundIndex)

	local reservations = Instance.new("Folder")
	reservations.Name = "RouteReservations"
	reservations.Parent = model
	local reservationIndex = 0
	for _, reservation in pairs(island.RouteReservations) do
		reservationIndex += 1
		local marker = Instance.new("Vector3Value")
		marker.Name = string.format("Cell_%03d", reservationIndex)
		marker.Value = gridToWorld(reservation.Cell)
		marker:SetAttribute("GridX", reservation.Cell.X)
		marker:SetAttribute("GridY", reservation.Cell.Y)
		marker:SetAttribute("GridZ", reservation.Cell.Z)
		marker:SetAttribute("PathType", reservation.PathType)
		marker:SetAttribute("PathId", reservation.PathId)
		marker.Parent = reservations
	end

	local content = Instance.new("Folder")
	content.Name = "MVPContent"
	content.Parent = model
	decorateIsland(model, island, content, roundIndex)
	populateIslandGrass(model, island, content, grassTemplates)
	return model
end

local function assertGeneratedModelIsValid(model)
	local connectorCells = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("IsRoundConnector") == true then
			assert(descendant.Size == Vector3.new(Config.GRID_SIZE, Config.GRID_SIZE, Config.GRID_SIZE))
			local cell = Vector3.new(
				descendant:GetAttribute("GridX"),
				descendant:GetAttribute("GridY"),
				descendant:GetAttribute("GridZ")
			)
			local key = cellKey(cell)
			assert(not connectorCells[key], "[SkyDungeon] Dois conectores ocupam a mesma celula.")
			assert(isInsideRadius(cell), "[SkyDungeon] Conector fora do raio.")
			connectorCells[key] = true
		end
	end
end

function Generator.Generate(parent, options)
	validateConfig()
	parent = parent or workspace
	options = options or {}
	local startGrid = options.StartGrid or Config.START_GRID
	local modelName = options.ModelName or Config.MODEL_NAME
	local chunkIndex = options.ChunkIndex or options.RoundIndex or 1
	local replaceExisting = options.ReplaceExisting
	if replaceExisting == nil then
		replaceExisting = Config.REPLACE_EXISTING
	end
	for _, component in ipairs({ startGrid.X, startGrid.Y, startGrid.Z }) do
		assert(isInteger(component), "[SkyDungeon] StartGrid precisa usar inteiros.")
	end
	assert(isInsideRadius(startGrid), "[SkyDungeon] StartGrid fora do raio.")

	local actualSeed = options.Seed or Config.SEED or (os.time() % 2147483647)
	local random = Random.new(actualSeed)
	local oldModel = parent:FindFirstChild(modelName)
	if oldModel then
		if replaceExisting then
			oldModel:Destroy()
		else
			error("[SkyDungeon] Ja existe um round chamado " .. modelName)
		end
	end

	local externalOccupied, externalHeadroom = collectExternalReservations(parent)
	local candidates =
		buildLayoutCandidates(random, startGrid, chunkIndex, actualSeed, externalOccupied, externalHeadroom)
	assert(#candidates > 0, "[SkyDungeon] Nenhum layout cabe no raio atual; aumente MAX_RADIUS_STUDS.")

	local plan
	local lastReason
	for _, candidate in ipairs(candidates) do
		plan, lastReason = tryPlanCandidate(random, candidate, startGrid, externalOccupied, externalHeadroom)
		if plan then
			break
		end
	end
	assert(plan, "[SkyDungeon] Nao foi possivel conectar o round: " .. tostring(lastReason))

	local candidate = plan.Candidate
	local model = Instance.new("Model")
	model.Name = modelName
	model:SetAttribute("Seed", actualSeed)
	model:SetAttribute("ChunkIndex", chunkIndex)
	model:SetAttribute("RoundIndex", chunkIndex)
	model:SetAttribute("RoundArchetype", candidate.Archetype)
	model:SetAttribute("GeneratorVersion", "SkyDungeonV18IntegratedMonsterSpawner")
	model:SetAttribute("RoutePlanner", "DeterministicStairsV10")
	model:SetAttribute("UsesPathfinding", false)
	model:SetAttribute("DifficultyTier", math.max(1, math.floor((chunkIndex - 1) / 4) + 1))
	model:SetAttribute("StartGrid", startGrid)
	model:SetAttribute("EndGrid", plan.EndGrid)
	model:SetAttribute("ReusesPreviousEnd", options.ReuseStartBlock == true)
	model:SetAttribute("GridSize", Config.GRID_SIZE)
	model:SetAttribute("HeadroomCells", Config.HEADROOM_CELLS)
	model:SetAttribute("TerrainAreaCount", #candidate.Islands)
	model:SetAttribute("BranchCount", plan.SuccessfulBranches)
	model:SetAttribute("RecommendedExplorationSeconds", Config.ROUND_EXPLORATION_SECONDS)

	local bottomWorldY = gridToWorld(startGrid).Y - Config.GRID_SIZE / 2
	local topWorldY = gridToWorld(plan.EndGrid).Y + Config.GRID_SIZE / 2
	model:SetAttribute("BottomWorldY", bottomWorldY)
	model:SetAttribute("TopWorldY", topWorldY)
	model:SetAttribute("RoundBottomWorldY", bottomWorldY)
	model:SetAttribute("RoundTopWorldY", topWorldY)
	model:SetAttribute("VerticalSpanStuds", topWorldY - bottomWorldY)

	local routeFolder = Instance.new("Folder")
	routeFolder.Name = "MainRoute"
	routeFolder.Parent = model
	local branchFolder = Instance.new("Folder")
	branchFolder.Name = "BranchRoutes"
	branchFolder.Parent = model
	local supportFolder = Instance.new("Folder")
	supportFolder.Name = "PillarSupports"
	supportFolder.Parent = model
	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "TerrainAreas"
	terrainFolder.Parent = model
	local grassTemplates = getGrassTemplates()

	local routeBlockCount = 0
	for _, pathData in ipairs(plan.MainPaths) do
		for index = 2, #pathData.Cells - 1 do
			routeBlockCount += 1
			createConnector(
				routeFolder,
				pathData.Cells[index],
				"MainRoute",
				pathData.PathId,
				pathData.Name,
				index - 1,
				chunkIndex,
				grassTemplates
			)
		end
	end
	local branchBlockCount = 0
	for _, pathData in ipairs(plan.BranchPaths) do
		for index = 2, #pathData.Cells - 1 do
			branchBlockCount += 1
			createConnector(
				branchFolder,
				pathData.Cells[index],
				"BranchRoute",
				pathData.PathId,
				pathData.Name,
				index - 1,
				chunkIndex,
				grassTemplates
			)
		end
	end

	local logicalTerrainCells = 0
	for _, island in ipairs(candidate.Islands) do
		local previousCenter = startGrid
		if island.Role == "RallyHall" then
			previousCenter = candidate.Main.Center
		elseif island.Role == "ExitSanctuary" then
			previousCenter = candidate.Hub.Center
		elseif string.find(island.Role, "SideRoom", 1, true) then
			previousCenter = candidate.Main.Center
		end
		createIsland(terrainFolder, island, chunkIndex, previousCenter, grassTemplates)
		logicalTerrainCells += #island.Cells
	end
	model:SetAttribute("RouteBlockCount", routeBlockCount)
	model:SetAttribute("BranchBlockCount", branchBlockCount)
	model:SetAttribute("SupportBlockCount", 0)
	model:SetAttribute("TerrainBlockCount", logicalTerrainCells)
	model:SetAttribute("PhysicalIslandPartCount", #candidate.Islands)

	assertGeneratedModelIsValid(model)

	-- O mapa ja esta completo neste ponto: piso, grama, rotas e decoracoes.
	-- O MonsterSpawner recebe as celulas logicas livres diretamente, sem analisar o Workspace.
	local generatedIslands = terrainFolder:GetChildren()
	table.sort(generatedIslands, function(a, b)
		return (a:GetAttribute("TerrainId") or 0) < (b:GetAttribute("TerrainId") or 0)
	end)
	local monsterSpawnCount = 0
	local chestSpawnCount = 0
	-- Primeiro classifica e reserva o conteudo de todas as ilhas. O segundo
	-- passe prioriza Elites, impedindo que mobs normais do mesmo round consumam
	-- as vagas globais antes do desafio especial.
	for _, islandModel in ipairs(generatedIslands) do
		IslandTypeService.Classify(islandModel, {
			ChunkIndex = chunkIndex,
			RoundIndex = chunkIndex,
			RoundSeed = actualSeed,
		})
		local chestSuccess, chestsOrError = pcall(ChestService.PopulateIsland, islandModel, Generator.GetFreeCells(islandModel), {
			ChunkIndex = chunkIndex,
			RoundIndex = chunkIndex,
			RoundSeed = actualSeed,
		})
		if chestSuccess then
			chestSpawnCount += tonumber(chestsOrError) or 0
		else
			warn(string.format("[SkyDungeon] Falha ao criar baus em %s: %s", islandModel:GetFullName(), tostring(chestsOrError)))
		end
	end

	local monsterIslands = table.clone(generatedIslands)
	table.sort(monsterIslands, function(a, b)
		local aElite = a:GetAttribute("IslandType") == "Elite"
		local bElite = b:GetAttribute("IslandType") == "Elite"
		if aElite ~= bElite then
			return aElite
		end
		return (a:GetAttribute("TerrainId") or 0) < (b:GetAttribute("TerrainId") or 0)
	end)
	for _, islandModel in ipairs(monsterIslands) do
		if islandModel:IsA("Model") and islandModel:GetAttribute("CanSpawnMonster") == true then
			local freeCells = Generator.GetFreeCells(islandModel)
			local success, spawnedOrError = pcall(MonsterSpawner.PopulateIsland, islandModel, freeCells, {
				ChunkIndex = chunkIndex,
				RoundIndex = chunkIndex,
				RoundSeed = actualSeed,
				GridSize = Config.GRID_SIZE,
			})
			if success then
				monsterSpawnCount += tonumber(spawnedOrError) or 0
			else
				warn(
					string.format(
						"[SkyDungeon] Falha ao popular monstros em %s: %s",
						islandModel:GetFullName(),
						tostring(spawnedOrError)
					)
				)
			end
		end
	end
	model:SetAttribute("MonsterSpawnCount", monsterSpawnCount)
	model:SetAttribute("ChestSpawnCount", chestSpawnCount)

	-- Publica o round somente depois de reservar e criar os monstros.
	-- Assim, servicos externos (como coletaveis) ja enxergam MonsterSpawnPoints.
	model.Parent = parent

	print(
		string.format(
			"[SkyDungeon] Round %d | %s | Seed %d | %d ilhas | %d loops | %.0f studs",
			chunkIndex,
			candidate.Archetype,
			actualSeed,
			#candidate.Islands,
			plan.SuccessfulBranches,
			topWorldY - bottomWorldY
		)
	)

	return model,
	{
		ChunkIndex = chunkIndex,
		RoundIndex = chunkIndex,
		Seed = actualSeed,
		StartGrid = startGrid,
		EndGrid = plan.EndGrid,
		BottomWorldY = bottomWorldY,
		TopWorldY = topWorldY,
		RoundArchetype = candidate.Archetype,
		TerrainAreaCount = #candidate.Islands,
		BranchCount = plan.SuccessfulBranches,
		RouteBlockCount = routeBlockCount,
	}
end

-- Retorna apenas celulas internas livres da rota e das decoracoes ja criadas.
-- Nenhuma borda, ponte ou corredor principal e exposto para conteudo ou monstros.
function Generator.GetFreeCells(islandModel)
	assert(islandModel and islandModel:GetAttribute("IsSkyIsland") == true, "Ilha Terrain_* invalida.")
	local minX = islandModel:GetAttribute("MinGridX")
	local maxX = islandModel:GetAttribute("MaxGridX")
	local minZ = islandModel:GetAttribute("MinGridZ")
	local maxZ = islandModel:GetAttribute("MaxGridZ")
	local gridY = islandModel:GetAttribute("GridY")
	local margin = Config.ISLAND_INTERIOR_MARGIN_CELLS
	local reserved = {}
	local reservations = islandModel:FindFirstChild("RouteReservations")
	if reservations then
		for _, marker in ipairs(reservations:GetChildren()) do
			local x = marker:GetAttribute("GridX")
			local y = marker:GetAttribute("GridY")
			local z = marker:GetAttribute("GridZ")
			if x and y and z then
				reserved[cellKey(Vector3.new(x, y, z))] = true
			end
		end
	end
	local decorationPoints = islandModel:FindFirstChild("DecorationPoints")
	if decorationPoints then
		for _, marker in ipairs(decorationPoints:GetChildren()) do
			if marker:GetAttribute("Populated") == true then
				local x = marker:GetAttribute("GridX")
				local y = marker:GetAttribute("GridY")
				local z = marker:GetAttribute("GridZ")
				if x and y and z then
					reserved[cellKey(Vector3.new(x, y, z))] = true
				end
			end
		end
	end
	local collectiblePoints = islandModel:FindFirstChild("CollectiblePoints")
	if collectiblePoints then
		for _, marker in ipairs(collectiblePoints:GetChildren()) do
			local x = marker:GetAttribute("GridX")
			local y = marker:GetAttribute("GridY")
			local z = marker:GetAttribute("GridZ")
			if x and y and z then
				reserved[cellKey(Vector3.new(x, y, z))] = true
			end
		end
	end
	local monsterSpawnPoints = islandModel:FindFirstChild("MonsterSpawnPoints")
	if monsterSpawnPoints then
		for _, marker in ipairs(monsterSpawnPoints:GetChildren()) do
			local x = marker:GetAttribute("GridX")
			local y = marker:GetAttribute("GridY")
			local z = marker:GetAttribute("GridZ")
			if x and y and z then
				reserved[cellKey(Vector3.new(x, y, z))] = true
			end
		end
	end
	local chestSpawnPoints = islandModel:FindFirstChild("ChestSpawnPoints")
	if chestSpawnPoints then
		for _, marker in ipairs(chestSpawnPoints:GetChildren()) do
			local x = marker:GetAttribute("GridX")
			local y = marker:GetAttribute("GridY")
			local z = marker:GetAttribute("GridZ")
			if x and y and z then
				reserved[cellKey(Vector3.new(x, y, z))] = true
			end
		end
	end

	local result = {}
	for x = minX + margin, maxX - margin do
		for z = minZ + margin, maxZ - margin do
			local cell = Vector3.new(x, gridY, z)
			if not reserved[cellKey(cell)] then
				table.insert(result, {
					Cell = cell,
					WorldPosition = gridToWorld(cell),
					SurfacePosition = gridToWorld(cell) + Vector3.new(0, Config.ISLAND_FLOOR_THICKNESS_STUDS / 2, 0),
				})
			end
		end
	end
	return result
end

function Generator.ValidateJump(fromGridCell, toGridCell)
	return validateJump(fromGridCell, toGridCell)
end

function Generator.GridToWorld(cell)
	return gridToWorld(cell)
end

function Generator.WorldToGrid(position)
	return worldToGrid(position)
end

return Generator
