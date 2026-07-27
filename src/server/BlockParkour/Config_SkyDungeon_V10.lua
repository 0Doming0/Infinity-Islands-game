-- VERSION: V15_NORMAL_ISLAND_TOP_FACE_GRASS
-- Sky Dungeon - configuracao da fronteira vertical gerada por ilha.

local Config = {
	-- BASE DO GRID
	GRID_SIZE = 5,
	CENTER_WORLD = Vector3.new(0, 0, 0),
	START_GRID = Vector3.new(0, 0, 0),
	SEED = nil, -- Inteiro para repetir exatamente a mesma torre.
	-- 0 desativa o antigo limite circular. A malha cresce somente onde jogadores
	-- chegam e as regioes submersas sao removidas.
	MAX_RADIUS_STUDS = 0,
	HEADROOM_CELLS = 2,
	REPLACE_EXISTING = true,
	MODEL_NAME = "GeneratedSkyDungeonRound",

	-- GERACAO CONTINUA POR ROUNDS
	ENABLE_DYNAMIC_CHUNKS = true,
	WORLD_MODEL_NAME = "GeneratedBlockWorld",
	INITIAL_CHUNK_COUNT = 1,
	MAX_TOTAL_CHUNKS = 0, -- 0 = infinito; a agua remove os rounds antigos.
	CHUNK_SEED_STEP = 7919,
	CHUNK_CHECK_INTERVAL_SECONDS = 1,
	MAX_CHUNKS_PER_CHECK = 1,
	MIN_ACTIVE_CHUNKS = 3,
	ROUND_GENERATION_RETRIES = 4,

	-- FRONTEIRA VERTICAL REATIVA POR ROUNDS
	-- Cada ilha continua sendo um no, mas a unidade visual de geracao e um round
	-- completo com dois niveis da malha. O proximo round comeca quando um jogador
	-- se aproxima de uma ilha de fronteira, antes de colocar os pes nela.
	ENABLE_ISLAND_FRONTIER_WORLD = true,
	-- A posicao fisica continua presa ao grid seguro, mas cada faixa usa uma
	-- distancia sorteada pela seed. Isso quebra o aspecto de tabuleiro sem perder
	-- convergencias: o mesmo (LaneX, LaneZ, Level) ainda resolve para um unico ponto.
	FRONTIER_LANE_SPACING_CELLS = 15, -- fallback/compatibilidade: 75 studs.
	FRONTIER_HORIZONTAL_SPACING_MIN_CELLS = 14, -- 70 studs.
	FRONTIER_HORIZONTAL_SPACING_MAX_CELLS = 17, -- 85 studs.
	FRONTIER_LEVEL_RISE_CELLS = 4, -- fallback/compatibilidade: 20 studs.
	FRONTIER_VERTICAL_RISE_MIN_CELLS = 3, -- 15 studs.
	FRONTIER_VERTICAL_RISE_MAX_CELLS = 4, -- 20 studs.
	FRONTIER_CONNECTION_LANE_OFFSET_CELLS = 1,
	FRONTIER_ROUND_DEPTH_LEVELS = 2,
	-- A preparacao comeca na rota anterior, mas somente depois de o jogador
	-- demonstrar intencao real de seguir ate aquela ilha. Distancia sozinha nao
	-- abre mais rounds e, portanto, um jogador parado nao gera o mundo inteiro.
	FRONTIER_APPROACH_DISTANCE_STUDS = 68,
	FRONTIER_APPROACH_VERTICAL_MARGIN_STUDS = 48,
	FRONTIER_INTENT_SUSTAIN_SECONDS = 0.55,
	FRONTIER_INTENT_MIN_PROGRESS_STUDS = 3.5,
	FRONTIER_INTENT_MIN_MOVE_SPEED_STUDS = 2,
	FRONTIER_INTENT_MIN_ALIGNMENT = 0.18,
	FRONTIER_INTENT_DISTANCE_REGRESSION_TOLERANCE_STUDS = 1.25,
	FRONTIER_INTENT_TRIGGER_COOLDOWN_SECONDS = 1.5,
	FRONTIER_MIN_OUTGOING_CONNECTIONS = 2,
	FRONTIER_MAX_OUTGOING_CONNECTIONS = 3,
	FRONTIER_EXTRA_CONNECTION_CHANCE = 0.24,
	FRONTIER_SANCTUARY_CHANCE = 0.075,
	FRONTIER_SANCTUARY_MIN_LEVEL = 5,
	FRONTIER_SANCTUARY_SIZE = "Large",
	FRONTIER_SANCTUARY_MIN_CONNECTIONS = 3,
	FRONTIER_DISCOVERY_POLL_SECONDS = 0.16,
	FRONTIER_DISCOVERY_HORIZONTAL_PADDING_STUDS = 2,
	FRONTIER_DISCOVERY_VERTICAL_PADDING_STUDS = 7,
	-- Uma operacao cria no maximo uma ilha OU uma conexao. O worker roda no
	-- Heartbeat e respeita tambem um pequeno orcamento de tempo por frame.
	FRONTIER_MAX_EXPANSIONS_PER_UPDATE = 1, -- contrato antigo
	FRONTIER_MAX_GEOMETRY_OPERATIONS_PER_FRAME = 1,
	FRONTIER_GEOMETRY_PARTS_PER_FRAME = 2,
	FRONTIER_GENERATION_TIME_BUDGET_SECONDS = 0.002,
	-- Detalhes visuais e conteudo jogavel usam uma fila global separada. Cada
	-- clone pode ceder o frame para impedir rajadas de Instances.
	FRONTIER_DETAIL_YIELD_EVERY_CLONES = 1,
	FRONTIER_DETAIL_TIME_BUDGET_SECONDS = 0.0015,
	FRONTIER_DETAIL_IDLE_SECONDS = 0.03,
	-- A remocao de regioes submersas tambem e parcelada. Isso evita que a agua
	-- desreplique varias ilhas, conexoes, mobs e decoracoes no mesmo frame.
	FRONTIER_CLEANUP_OPERATIONS_PER_FRAME = 1,
	FRONTIER_CLEANUP_TIME_BUDGET_SECONDS = 0.001,
	FRONTIER_MAX_ACTIVE_ISLANDS = 650,
	FRONTIER_MIN_ACTIVE_ISLANDS = 12,
	FRONTIER_CONTENT_ACTIVATION_DISTANCE_STUDS = 135,
	FRONTIER_CONTENT_VERTICAL_MARGIN_STUDS = 55,
	FRONTIER_MAX_CONTENT_ACTIVATIONS_PER_UPDATE = 2,
	-- Conteudo ja descoberto permanece no mundo, mas a IA so simula perto de
	-- jogadores. Os dois raios formam uma histerese e evitam liga/desliga na borda.
	FRONTIER_SIMULATION_ACTIVATION_DISTANCE_STUDS = 155,
	FRONTIER_SIMULATION_DEACTIVATION_DISTANCE_STUDS = 210,
	FRONTIER_SIMULATION_VERTICAL_MARGIN_STUDS = 75,
	FRONTIER_SIMULATION_UPDATE_SECONDS = 0.5,
	-- Consultas de proximidade usam buckets X/Z em vez de varrer todas as ilhas.
	FRONTIER_SPATIAL_HASH_CELL_STUDS = 96,
	FRONTIER_SPATIAL_QUERY_PADDING_STUDS = 42,
	FRONTIER_DIAGNOSTIC_UPDATE_SECONDS = 0.25,
	-- O cliente deixa o culling de Parts para o motor do Roblox e pausa somente
	-- efeitos caros de ilhas fora da camera/distantes.
	FRONTIER_EFFECT_CULLING_ENABLED = true,
	FRONTIER_EFFECT_CULLING_UPDATE_SECONDS = 0.2,
	FRONTIER_EFFECT_CULLING_MAX_DISTANCE_STUDS = 230,
	FRONTIER_EFFECT_CULLING_FORCE_ACTIVE_DISTANCE_STUDS = 45,
	FRONTIER_EFFECT_CULLING_SCREEN_MARGIN_PIXELS = 96,
	-- Misterio a longa distancia sem FogStart/FogEnd e sem cortina de particulas.
	-- O cliente aplica apenas profundidade de campo ao horizonte; objetos proximos
	-- continuam nitidos e o culling real permanece por conta do motor/streaming.
	FRONTIER_MYSTERY_DISTANCE_ENABLED = true,
	FRONTIER_MYSTERY_FOCUS_DISTANCE_STUDS = 90,
	FRONTIER_MYSTERY_IN_FOCUS_RADIUS_STUDS = 105,
	FRONTIER_MYSTERY_FAR_INTENSITY = 0.72,
	FRONTIER_WATER_SAFETY_LEVELS = 2,
	FRONTIER_CLEANUP_MARGIN_STUDS = 15,
	-- Geometria submersa volta para um estoque fora do Workspace. O estoque e
	-- limitado para reduzir criacao/GC sem crescer indefinidamente na memoria.
	FRONTIER_GEOMETRY_POOL_ENABLED = true,
	FRONTIER_MAX_POOLED_ISLANDS = 12,
	FRONTIER_MAX_POOLED_CONNECTIONS = 20,
	-- Compatibilidade temporaria com o script da agua anterior.
	MIN_ACTIVE_CYCLES = 12,
	MAX_SECTOR_ACTIVATIONS_PER_UPDATE = 2,
	COLLECTIVE_UPDATE_INTERVAL_SECONDS = 0.5,
	COLLECTIVE_TRIM_FRACTION = 0.10,
	COLLECTIVE_LOWER_PERCENTILE = 0.20,
	COLLECTIVE_MERCY_MULTIPLIER = 0.72,
	WORLD_REBASE_TRIGGER_Y = 8000,
	WORLD_REBASE_SHIFT_STUDS = 5000,

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
	-- Roblox nao mede objetos 3D em pixels. Este pequeno deslocamento equivale
	-- visualmente a cerca de 2 px e impede os modelos decorativos de afundarem.
	GRASS_MODEL_SURFACE_LIFT_STUDS = 0.125,
	GRASS_ON_CONNECTORS = true,
	GRASS_MAX_PER_ISLAND = {
		Small = 8,
		Medium = 14,
		Large = 20,
	},

	-- CAMADA PLANA: terra embaixo e material Grass somente no topo.
	-- A camada e visual, fica quase toda embutida na terra e nao altera a colisao.
	CREATE_FLAT_GRASS_LAYER = true,
	-- Cada bloco das pontes decide pela seed se recebe ou nao o topo de grama.
	-- 0.5 produz aproximadamente metade terra nua e metade terra com grama.
	CONNECTOR_FLAT_GRASS_CHANCE = 0.5,
	FLAT_GRASS_LAYER_THICKNESS_STUDS = 0.35,
	-- Eleva tambem a cobertura plana visivel sobre a terra. A versao anterior
	-- elevava apenas os modelos decorativos e nao esta camada.
	FLAT_GRASS_SURFACE_OFFSET_STUDS = 0.125,
	FLAT_GRASS_COLOR = Color3.fromRGB(88, 142, 72),
	-- Imagem repetida sobre a face superior. A imagem e opcional visualmente:
	-- a SurfaceGui criada no servidor tambem possui um fundo verde permanente,
	-- portanto a terra nunca fica exposta se o asset demorar ou falhar.
	DISTANT_GRASS_TEXTURE_ID = "rbxassetid://7568838452",
	DISTANT_GRASS_TEXTURE_TILE_STUDS = 8,
	-- Este objeto fica como filho do proprio IslandFloor e desenha somente a
	-- face Top. Nao e uma nova Part e nao altera colisao, fisica ou Streaming.
	NORMAL_BIOME_GRASS_FACE_NAME = "NormalBiomeGrassTopFace",
	NORMAL_BIOME_GRASS_PIXELS_PER_STUD = 16,

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
