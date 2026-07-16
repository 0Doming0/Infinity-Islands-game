--[[
	Sky Dungeon V10 - Config

	Um chunk agora representa um round/andar completo: entrada, sala principal,
	rotas opcionais, ponto de reencontro e saida. Todas as coordenadas logicas
	continuam em celulas inteiras para manter seeds reproduziveis.
]]

local Config = {
	-- BASE DO GRID
	GRID_SIZE = 5,
	CENTER_WORLD = Vector3.new(0, 0, 0),
	START_GRID = Vector3.new(0, 0, 0),
	SEED = nil, -- Inteiro para repetir exatamente a mesma torre.
	MAX_RADIUS_STUDS = 300, -- Folga para curvas deterministicas sem prender rounds futuros.
	HEADROOM_CELLS = 2,
	REPLACE_EXISTING = true,
	MODEL_NAME = "GeneratedSkyDungeonRound",

	-- GERACAO CONTINUA POR ROUNDS
	ENABLE_DYNAMIC_CHUNKS = true,
	WORLD_MODEL_NAME = "GeneratedBlockWorld",
	INITIAL_CHUNK_COUNT = 2,
	MAX_TOTAL_CHUNKS = 0, -- 0 = infinito; a agua remove os rounds antigos.
	CHUNK_SEED_STEP = 7919,
	CHUNK_CHECK_INTERVAL_SECONDS = 1,
	MAX_CHUNKS_PER_CHECK = 1,
	MIN_ACTIVE_CHUNKS = 3,
	ROUND_GENERATION_RETRIES = 4,

	-- Contrato antigo mantido para scripts externos que ainda leem esses campos.
	CHUNK_ROUTE_BLOCK_COUNT = 70,
	CHUNK_GENERATE_AHEAD_STUDS = 90,
	ROUTE_BLOCK_COUNT = 120,

	-- CADA ROUND E UM ANDAR DA "MASMORRA NOS CEUS"
	ROUND_MIN_VERTICAL_CELLS = 19, -- 95 studs com GRID_SIZE 5.
	ROUND_MAX_VERTICAL_CELLS = 22, -- 110 studs; aproximadamente 80-95 s de agua.
	ROUND_MAIN_RISE_CELLS = 4,
	ROUND_HUB_RISE_CELLS = 12,
	ROUND_MAIN_FORWARD_CELLS = 8,
	ROUND_HUB_FORWARD_CELLS = 18,
	ROUND_EXIT_FORWARD_CELLS = 27,
	ROUND_SIDE_FORWARD_CELLS = 13,
	ROUND_SIDE_LATERAL_CELLS = 11,
	ROUND_EXIT_LATERAL_VARIATION = 3,
	ROUND_SIDE_RISE_CELLS = 4,
	ROUND_MIN_SIDE_ROOMS = 1,
	ROUND_MAX_SIDE_ROOMS = 2,
	ROUND_EXPLORATION_SECONDS = 75,

	-- Ilhas grandes: 35x35, 45x45 e 55x55 studs.
	TERRAIN_TYPES = {
		Small = { Width = 7, Depth = 7, Weight = 20 },
		Medium = { Width = 9, Depth = 9, Weight = 45 },
		Large = { Width = 11, Depth = 11, Weight = 35 },
	},
	MAIN_ISLAND_TYPES = { "Medium", "Large" },
	HUB_ISLAND_TYPE = "Medium",
	SIDE_ISLAND_TYPE = "Small",
	EXIT_ISLAND_TYPE = "Small",
	ENTRY_ISLAND_TYPE = "Small",
	ISLAND_FLOOR_THICKNESS_STUDS = 5,
	ISLAND_INTERIOR_MARGIN_CELLS = 1,

	-- DECORACAO SIMPLES DO MVP
	-- Coloque Models ou Parts diretamente em ServerStorage > MVPAssets > Decorations.
	-- O gerador usa apenas celulas internas, afastadas das rotas, e sorteia os
	-- mesmos assets de forma deterministica a partir da seed de cada ilha.
	ENABLE_DECORATIONS = true,
	DECORATION_FOLDER_NAME = "Decorations",
	DECORATION_SPAWN_CHANCE = 0.7,
	DECORATION_PATH_PADDING_CELLS = 1,
	DECORATION_MIN_SPACING_CELLS = 2,
	DECORATION_ATTEMPTS_BY_SIZE = {
		Small = 2,
		Medium = 4,
		Large = 6,
	},

	-- GRAMA VISUAL ESCOLHIDA PELO CRIADOR
	-- Coloque um ou mais Models/Parts diretamente em
	-- ServerStorage > MVPAssets > Grass. O noise apenas decide onde clonar.
	ENABLE_GRASS_MODELS = true,
	GRASS_FOLDER_NAME = "Grass",
	GRASS_NOISE_SCALE = 0.065,
	GRASS_NOISE_THRESHOLD = 0.52,
	GRASS_JITTER_STUDS = 1.35,
	GRASS_ON_CONNECTORS = true,
	GRASS_MAX_PER_ISLAND = {
		Small = 8,
		Medium = 14,
		Large = 20,
	},

	-- CAMADA PLANA: terra embaixo e material Grass somente no topo.
	-- A camada e visual, fica quase toda embutida na terra e nao altera a colisao.
	CREATE_FLAT_GRASS_LAYER = true,
	FLAT_GRASS_LAYER_THICKNESS_STUDS = 0.35,
	FLAT_GRASS_SURFACE_OFFSET_STUDS = 0.02,
	FLAT_GRASS_COLOR = Color3.fromRGB(88, 142, 72),

	-- ROTAS PRINCIPAL E ALTERNATIVAS
	-- O V8 usa escadarias deterministicas. Os campos A* abaixo ficam apenas
	-- para compatibilidade com ferramentas antigas e nao controlam a rota vital.
	ENABLE_BRANCH_PATHS = true,
	BRANCH_TARGET_COUNT = 2,
	BRANCH_SEARCH_RETRIES = 3,
	BRANCH_MIN_INTERIOR_BLOCKS = 2,
	BRANCH_PATHFIND_MAX_NODES = 9000,
	BRANCH_MAX_PATH_BLOCKS = 90,
	BRANCH_VERTICAL_MOVE_COST = 1.0,
	BRANCH_FLAT_MOVE_COST = 1.12,
	BRANCH_GAP_MOVE_COST = 1.28,
	BRANCH_FALLBACK_ISLAND_EXTRA_BLOCKS = 2,

	-- Campos antigos preservados para compatibilidade com ferramentas/diagnosticos.
	BRANCH_START_AFTER_ROUTE_BLOCK = 8,
	BRANCH_END_MARGIN = 10,
	BRANCH_MIN_ROUTE_SPAN = 10,
	BRANCH_MAX_ROUTE_SPAN = 24,
	BRANCH_PAIR_SEARCH_ATTEMPTS = 30,
	BRANCH_MIN_JUNCTION_DISTANCE = 4,
	BRANCH_TERRAIN_TYPE = "Small",
	ENABLE_TERRAIN_AREAS = true,
	TERRAIN_START_AFTER_ROUTE_BLOCK = 1,
	TERRAIN_END_MARGIN = 1,
	TERRAIN_MIN_INTERVAL = 1,
	TERRAIN_MAX_INTERVAL = 1,
	TERRAIN_SEARCH_WINDOW = 0,

	-- GERACAO COLETIVA: usa o progresso mediano, nunca apenas o jogador mais alto.
	ENABLE_GROUP_PROGRESS_GENERATION = true,
	GROUP_PROGRESS_PERCENTILE = 0.5,
	GROUP_GENERATE_AHEAD_STUDS = 45,
	MAX_ROUNDS_AHEAD_OF_GROUP = 2,

	-- LIMITES CONSERVADORES PARA O PERSONAGEM ROBLOX PADRAO
	MAX_RISE_STUDS = 5,
	MAX_SAME_LEVEL_GAP_STUDS = 5,
	MAX_RISING_GAP_STUDS = 0,
	WARN_IMPOSSIBLE_JUMPS = true,
	MAX_ATTEMPTS_PER_STEP = 24,
	MIN_SEGMENT_LENGTH = 2,
	MAX_SEGMENT_LENGTH = 4,
	MIN_STRAIGHT_STEPS = 1,
	MAX_STRAIGHT_STEPS = 4,
	MAX_SAME_AXIS_STEPS = 7,
	AVOID_IMMEDIATE_REVERSAL = true,
	SEGMENT_WEIGHTS = { Simple = 45, Stairs = 35, Pillars = 20 },

	-- O bloco estrutural agora tem aparencia de terra. A grama visual vem dos
	-- modelos escolhidos em MVPAssets > Grass, nao de Parts criadas como cobertura.
	BLOCK_COLOR = Color3.fromRGB(112, 78, 48),
	BLOCK_MATERIAL = Enum.Material.Ground,
	GRASS_TOP_COLOR = Color3.fromRGB(88, 142, 72),
	CREATE_GRASS_TOP = false, -- Evita centenas de SurfaceGuis em celular.
	CAN_COLLIDE = true,
}

return table.freeze(Config)
