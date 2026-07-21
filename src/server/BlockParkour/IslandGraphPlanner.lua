--[[
	Planejador puro da fronteira vertical por ilha.

	Cada ilha ocupa uma coordenada logica (LaneX, LaneZ, Level). Um caminho
	sempre move uma casa horizontal e sobe um nivel. Por isso duas sequencias
	diferentes podem chegar exatamente ao mesmo NodeKey sem criar duas ilhas:

		Norte -> Leste == Leste -> Norte

	O modulo nao cria Instances. Toda decisao depende somente da seed do mundo e
	da coordenada logica, portanto a ordem em que jogadores exploram nao altera o
	resultado.
]]

local Config = require(script.Parent.Config_SkyDungeon_V10)

local IslandGraphPlanner = {}

local MAXIMUM_SEED = 2147483647
local layoutCaches = {}

local DIRECTIONS = {
	{ Id = "East", DeltaX = 1, DeltaZ = 0, Vector = Vector3.new(1, 0, 0) },
	{ Id = "West", DeltaX = -1, DeltaZ = 0, Vector = Vector3.new(-1, 0, 0) },
	{ Id = "South", DeltaX = 0, DeltaZ = 1, Vector = Vector3.new(0, 0, 1) },
	{ Id = "North", DeltaX = 0, DeltaZ = -1, Vector = Vector3.new(0, 0, -1) },
}

local DIRECTION_BY_ID = {}
for _, direction in ipairs(DIRECTIONS) do
	DIRECTION_BY_ID[direction.Id] = direction
end

local function isInteger(value)
	return value == math.floor(value)
end

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % MAXIMUM_SEED
	return seed == 0 and 1 or seed
end

-- Hash inteiro estavel. Nao usa tostring(Vector3), evitando diferencas de
-- formatacao entre ferramentas e versoes do runtime.
local function coordinateSeed(baseSeed, laneX, laneZ, level, salt)
	local value = normalizedSeed(baseSeed)
	value = (value * 48271 + (laneX + 1048576) * 69621) % MAXIMUM_SEED
	value = (value * 48271 + (laneZ + 1048576) * 90787) % MAXIMUM_SEED
	value = (value * 48271 + level * 104729 + (salt or 0)) % MAXIMUM_SEED
	return normalizedSeed(value)
end

local function getLayoutCache(baseSeed)
	local seed = normalizedSeed(baseSeed)
	local cache = layoutCaches[seed]
	if cache then
		return cache
	end
	cache = {
		X = { [0] = 0 },
		Z = { [0] = 0 },
		Y = { [0] = 0 },
		XMinimum = 0,
		XMaximum = 0,
		ZMinimum = 0,
		ZMaximum = 0,
		YMaximum = 0,
	}
	layoutCaches[seed] = cache
	return cache
end

local function horizontalSpacing(baseSeed, axis, segment)
	local salt = axis == "X" and 86028121 or 104395303
	local seed = axis == "X"
		and coordinateSeed(baseSeed, segment, 0, 0, salt)
		or coordinateSeed(baseSeed, 0, segment, 0, salt)
	return Random.new(seed):NextInteger(
		Config.FRONTIER_HORIZONTAL_SPACING_MIN_CELLS,
		Config.FRONTIER_HORIZONTAL_SPACING_MAX_CELLS
	)
end

local function axisCoordinate(baseSeed, axis, lane)
	local cache = getLayoutCache(baseSeed)
	local values = cache[axis]
	local minimumKey = axis .. "Minimum"
	local maximumKey = axis .. "Maximum"
	while cache[maximumKey] < lane do
		local current = cache[maximumKey]
		values[current + 1] = values[current] + horizontalSpacing(baseSeed, axis, current)
		cache[maximumKey] = current + 1
	end
	while cache[minimumKey] > lane do
		local current = cache[minimumKey]
		local previous = current - 1
		values[previous] = values[current] - horizontalSpacing(baseSeed, axis, previous)
		cache[minimumKey] = previous
	end
	return values[lane]
end

local function levelCoordinate(baseSeed, level)
	local cache = getLayoutCache(baseSeed)
	while cache.YMaximum < level do
		local current = cache.YMaximum
		local riseSeed = coordinateSeed(baseSeed, 0, 0, current, 122949829)
		local rise = Random.new(riseSeed):NextInteger(
			Config.FRONTIER_VERTICAL_RISE_MIN_CELLS,
			Config.FRONTIER_VERTICAL_RISE_MAX_CELLS
		)
		cache.Y[current + 1] = cache.Y[current] + rise
		cache.YMaximum = current + 1
	end
	return cache.Y[level]
end

local function shuffle(random, values)
	local result = table.clone(values)
	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

local function chooseWeightedSize(random)
	local names = {}
	local totalWeight = 0
	for name, definition in pairs(Config.TERRAIN_TYPES) do
		local weight = math.max(0, tonumber(definition.Weight) or 0)
		if weight > 0 then
			table.insert(names, name)
			totalWeight += weight
		end
	end
	table.sort(names)
	assert(totalWeight > 0, "[IslandGraphPlanner] TERRAIN_TYPES precisa ter peso positivo.")
	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, name in ipairs(names) do
		accumulated += Config.TERRAIN_TYPES[name].Weight
		if roll <= accumulated then
			return name
		end
	end
	return names[#names]
end

local function assertCoordinate(laneX, laneZ, level)
	assert(isInteger(laneX), "LaneX precisa ser inteiro.")
	assert(isInteger(laneZ), "LaneZ precisa ser inteiro.")
	assert(isInteger(level) and level >= 0, "Level precisa ser inteiro nao negativo.")
	-- Cada passo muda a paridade. Esta propriedade impede duas escadarias em
	-- sentidos opostos de cruzarem o mesmo corredor fisico.
	assert((math.abs(laneX + laneZ - level) % 2) == 0, "Coordenada fora da paridade da malha vertical.")
end

function IslandGraphPlanner.NodeKey(laneX, laneZ, level)
	assertCoordinate(laneX, laneZ, level)
	return string.format("L%d_X%d_Z%d", level, laneX, laneZ)
end

function IslandGraphPlanner.EdgeKey(sourceKey, targetKey)
	return sourceKey .. "__TO__" .. targetKey
end

function IslandGraphPlanner.GetDirections()
	local result = {}
	for index, direction in ipairs(DIRECTIONS) do
		result[index] = table.clone(direction)
	end
	return result
end

function IslandGraphPlanner.GetDirection(directionId)
	local direction = DIRECTION_BY_ID[directionId]
	return direction and table.clone(direction) or nil
end

function IslandGraphPlanner.GetNodeSpec(baseSeed, laneX, laneZ, level)
	assertCoordinate(laneX, laneZ, level)
	local seed = coordinateSeed(baseSeed, laneX, laneZ, level, 32452843)
	local random = Random.new(seed)
	local isStart = level == 0 and laneX == 0 and laneZ == 0
	local isSanctuary = isStart
	if not isStart and level >= Config.FRONTIER_SANCTUARY_MIN_LEVEL then
		isSanctuary = random:NextNumber() <= Config.FRONTIER_SANCTUARY_CHANCE
	end
	local sizeName = isSanctuary and Config.FRONTIER_SANCTUARY_SIZE or chooseWeightedSize(random)
	local role = isStart and "EntrySanctuary" or (isSanctuary and "SocialSanctuary" or "FrontierIsland")
	local center = Config.START_GRID + Vector3.new(
		axisCoordinate(baseSeed, "X", laneX),
		levelCoordinate(baseSeed, level),
		axisCoordinate(baseSeed, "Z", laneZ)
	)
	return {
		Key = IslandGraphPlanner.NodeKey(laneX, laneZ, level),
		LaneX = laneX,
		LaneZ = laneZ,
		Level = level,
		Seed = seed,
		Center = center,
		SizeName = sizeName,
		Role = role,
		IsSanctuary = isSanctuary,
		IsStart = isStart,
	}
end

function IslandGraphPlanner.GetExpansionDirections(baseSeed, nodeSpec)
	local random = Random.new(coordinateSeed(
		baseSeed,
		nodeSpec.LaneX,
		nodeSpec.LaneZ,
		nodeSpec.Level,
		49979687
	))
	local amount = Config.FRONTIER_MIN_OUTGOING_CONNECTIONS
	if random:NextNumber() <= Config.FRONTIER_EXTRA_CONNECTION_CHANCE then
		amount += 1
	end
	if nodeSpec.IsSanctuary then
		amount = math.max(amount, Config.FRONTIER_SANCTUARY_MIN_CONNECTIONS)
	end
	amount = math.clamp(amount, 1, math.min(Config.FRONTIER_MAX_OUTGOING_CONNECTIONS, #DIRECTIONS))
	local shuffled = shuffle(random, DIRECTIONS)
	local result = {}
	for index = 1, amount do
		result[index] = table.clone(shuffled[index])
	end
	return result
end

function IslandGraphPlanner.GetChildSpec(baseSeed, sourceSpec, directionId)
	local direction = assert(DIRECTION_BY_ID[directionId], "Direcao desconhecida: " .. tostring(directionId))
	return IslandGraphPlanner.GetNodeSpec(
		baseSeed,
		sourceSpec.LaneX + direction.DeltaX,
		sourceSpec.LaneZ + direction.DeltaZ,
		sourceSpec.Level + 1
	)
end

local function halfExtent(spec, direction)
	local size = assert(Config.TERRAIN_TYPES[spec.SizeName], "Tamanho de ilha desconhecido.")
	if direction.X ~= 0 then
		return math.floor(size.Width / 2)
	end
	return math.floor(size.Depth / 2)
end

local function connectionLaneOffset(sourceLevel, direction)
	local sign = sourceLevel % 2 == 0 and 1 or -1
	local perpendicular = direction.X ~= 0 and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	return perpendicular * sign * Config.FRONTIER_CONNECTION_LANE_OFFSET_CELLS
end

-- Cria uma escadaria reta e legivel. Quando ha mais distancia horizontal do
-- que subida, os degraus sao distribuidos uniformemente entre blocos planos.
function IslandGraphPlanner.PlanConnection(sourceSpec, targetSpec, directionId)
	assert(targetSpec.Level == sourceSpec.Level + 1, "Uma conexao precisa subir exatamente um nivel.")
	local direction = assert(DIRECTION_BY_ID[directionId], "Direcao desconhecida: " .. tostring(directionId))
	assert(
		targetSpec.LaneX == sourceSpec.LaneX + direction.DeltaX
			and targetSpec.LaneZ == sourceSpec.LaneZ + direction.DeltaZ,
		"Destino nao corresponde a direcao da conexao."
	)
	-- A faixa alterna de lado a cada nivel. Se o jogador voltar na direcao
	-- horizontal de onde veio, a nova escada passa paralela a anterior.
	local laneOffset = connectionLaneOffset(sourceSpec.Level, direction.Vector)
	local startCell = sourceSpec.Center
		+ direction.Vector * halfExtent(sourceSpec, direction.Vector)
		+ laneOffset
	local endCell = targetSpec.Center
		- direction.Vector * halfExtent(targetSpec, direction.Vector)
		+ laneOffset
	local difference = endCell - startCell
	local horizontalSteps = math.abs(difference.X) + math.abs(difference.Z)
	local rise = difference.Y
	assert(
		rise >= Config.FRONTIER_VERTICAL_RISE_MIN_CELLS
			and rise <= Config.FRONTIER_VERTICAL_RISE_MAX_CELLS,
		"Subida divergente da configuracao."
	)
	assert(horizontalSteps >= rise, "Espacamento horizontal insuficiente para a escadaria.")
	assert(difference.X == 0 or difference.Z == 0, "Conexao precisa estar alinhada a um eixo.")

	local path = table.create(horizontalSteps + 1)
	path[1] = startCell
	for step = 1, horizontalSteps do
		local achievedRise = math.floor(step * rise / horizontalSteps + 0.00001)
		path[step + 1] = startCell
			+ direction.Vector * step
			+ Vector3.new(0, achievedRise, 0)
	end
	assert(path[#path] == endCell, "A escadaria nao terminou na ilha de destino.")
	return {
		Key = IslandGraphPlanner.EdgeKey(sourceSpec.Key, targetSpec.Key),
		SourceKey = sourceSpec.Key,
		TargetKey = targetSpec.Key,
		DirectionId = directionId,
		Cells = path,
		StartCell = startCell,
		EndCell = endCell,
		LaneOffsetCells = laneOffset,
		LaneParity = sourceSpec.Level % 2,
		RiseCells = rise,
		HorizontalSteps = horizontalSteps,
	}
end

function IslandGraphPlanner.ValidateConfig()
	assert(Config.FRONTIER_LANE_SPACING_CELLS >= 3, "FRONTIER_LANE_SPACING_CELLS invalido.")
	assert(Config.FRONTIER_LEVEL_RISE_CELLS >= 1, "FRONTIER_LEVEL_RISE_CELLS invalido.")
	assert(Config.FRONTIER_HORIZONTAL_SPACING_MIN_CELLS >= 3, "Espacamento horizontal minimo invalido.")
	assert(
		Config.FRONTIER_HORIZONTAL_SPACING_MAX_CELLS
			>= Config.FRONTIER_HORIZONTAL_SPACING_MIN_CELLS,
		"Intervalo de espacamento horizontal invalido."
	)
	assert(Config.FRONTIER_VERTICAL_RISE_MIN_CELLS >= 1, "Subida vertical minima invalida.")
	assert(
		Config.FRONTIER_VERTICAL_RISE_MAX_CELLS
			>= Config.FRONTIER_VERTICAL_RISE_MIN_CELLS,
		"Intervalo de subida vertical invalido."
	)
	assert(Config.FRONTIER_CONNECTION_LANE_OFFSET_CELLS >= 1, "Offset lateral invalido.")
	assert(Config.FRONTIER_MIN_OUTGOING_CONNECTIONS >= 2, "Cada ilha precisa oferecer pelo menos duas escolhas.")
	assert(Config.FRONTIER_MAX_OUTGOING_CONNECTIONS <= #DIRECTIONS, "Ha somente quatro direcoes cardeais.")
	assert(Config.FRONTIER_MAX_OUTGOING_CONNECTIONS >= Config.FRONTIER_MIN_OUTGOING_CONNECTIONS)
	assert(Config.FRONTIER_EXTRA_CONNECTION_CHANCE >= 0 and Config.FRONTIER_EXTRA_CONNECTION_CHANCE <= 1)
	assert(Config.FRONTIER_SANCTUARY_CHANCE >= 0 and Config.FRONTIER_SANCTUARY_CHANCE <= 1)
	assert(Config.TERRAIN_TYPES[Config.FRONTIER_SANCTUARY_SIZE], "FRONTIER_SANCTUARY_SIZE desconhecido.")
	local maximumHalfExtent = 0
	for _, size in pairs(Config.TERRAIN_TYPES) do
		maximumHalfExtent = math.max(maximumHalfExtent, math.floor(size.Width / 2), math.floor(size.Depth / 2))
		assert(
			math.floor(math.min(size.Width, size.Depth) / 2) > Config.FRONTIER_CONNECTION_LANE_OFFSET_CELLS,
			"Uma ilha e estreita demais para as faixas paralelas."
		)
	end
	local minimumHorizontalSteps = Config.FRONTIER_HORIZONTAL_SPACING_MIN_CELLS - maximumHalfExtent * 2
	assert(
		minimumHorizontalSteps >= Config.FRONTIER_VERTICAL_RISE_MAX_CELLS,
		"O espacamento entre ilhas nao comporta a subida configurada."
	)
	return true
end

return table.freeze(IslandGraphPlanner)
