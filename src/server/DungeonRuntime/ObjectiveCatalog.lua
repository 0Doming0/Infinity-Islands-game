local ObjectiveCatalog = {}

local DEFINITIONS = {
	{
		Id = "FirstStrike",
		Title = "Derrote o primeiro slime",
		Description = "Derrote o slime marcado para abrir o caminho.",
		-- A lógica não depende mais do highlight ObjectiveFocusTarget.
		-- ObjectiveSpawned é aplicado autoritativamente pelo MonsterSpawner
		-- antes do inimigo entrar em combate e permanece estável até a morte.
		RequiredTargetAttribute = "ObjectiveSpawned",
		GameplayIdentity = "MarkedOpeningTarget",
		RoundIndex = 1,
		IslandIndex = 1,
		GlobalIslandIndex = 1,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 1,
		ObjectiveKind = "CombatIntro",
		SpawnProfile = "FirstStrike",
	},
	{
		Id = "ClearThePath",
		Title = "Limpe o caminho",
		Description = "Derrote os 3 slimes que bloqueiam a saída.",
		-- Conta somente inimigos criados pelo encontro do objetivo.
		-- Isso impede que um mob antigo/ambiental interfira no 0/3 -> 3/3.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 1,
		IslandIndex = 2,
		GlobalIslandIndex = 2,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 3,
		ObjectiveKind = "DefeatEnemies",
		SpawnProfile = "CommonWave",
		GameplayIdentity = "OpenCombat",
	},
	{
		Id = "FirstRewardBattle",
		Title = "Vença as 2 ondas",
		Description = "Derrote as duas ondas e abra o Core Chest para avançar.",
		-- Somente inimigos criados pelo encontro desta Reward Battle contam.
		-- Evita qualquer kill ambiente/atrasada alterar o contador.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 1,
		IslandIndex = 3,
		GlobalIslandIndex = 3,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 5,
		TargetPerExtraPlayer = 2,
		ObjectiveKind = "RewardBattle",
		SpawnProfile = "RewardWave01",
		GameplayIdentity = "EscalatingRewardWaves",
		IsRewardIsland = true,
	},
	{
		Id = "SkyAmbush",
		Title = "Sobreviva à emboscada",
		Description = "Os slimes estão escondidos. Derrote todos quando aparecerem.",
		-- Só os atacantes criados pelo encontro podem avançar este objetivo.
		-- Isso evita kills atrasadas/ambientais alterarem a emboscada.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 2,
		IslandIndex = 1,
		GlobalIslandIndex = 4,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 5,
		TargetPerExtraPlayer = 2,
		ObjectiveKind = "Ambush",
		SpawnProfile = "SkyAmbush",
		GameplayIdentity = "HiddenPerimeterAmbush",
	},
	{
		Id = "RangedThreat",
		Title = "Elimine os atiradores",
		Description = "Aproxime-se e derrote os slimes de ataque à distância.",
		-- Duplo contrato: precisa ser um atirador E pertencer ao encontro atual.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 2,
		IslandIndex = 2,
		GlobalIslandIndex = 5,
		ProgressEvent = "EnemyDefeated",
		RequiredRole = "Ranged",
		BaseTarget = 3,
		TargetPerExtraPlayer = 1,
		ObjectiveKind = "DefeatRole",
		SpawnProfile = "RangedThreat",
		GameplayIdentity = "PriorityRangedTargets",
	},
	{
		Id = "BreakTheNests",
		Title = "Destrua os 2 ninhos",
		Description = "Ataque os ninhos roxos antes que criem mais slimes.",
		-- ObjectiveActorService marca ObjectiveTargetCompleted=true imediatamente
		-- antes de emitir NestDestroyed. Isso garante que só uma destruição real
		-- do ator do objetivo seja aceita pelo contador.
		RequiredTargetAttribute = "ObjectiveTargetCompleted",
		RoundIndex = 2,
		IslandIndex = 3,
		GlobalIslandIndex = 6,
		ProgressEvent = "NestDestroyed",
		BaseTarget = 2,
		ObjectiveKind = "DestroyNests",
		SpawnProfile = "NestPair",
		GameplayIdentity = "DestroySpawners",
	},
	{
		Id = "SecondRewardBattle",
		Title = "Vença as 2 ondas",
		Description = "Derrote as duas ondas e abra o Core Chest para avançar.",
		-- Só inimigos autoritativos desta Reward Battle contam.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 2,
		IslandIndex = 4,
		GlobalIslandIndex = 7,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 7,
		TargetPerExtraPlayer = 2,
		ObjectiveKind = "RewardBattle",
		SpawnProfile = "RewardWave02",
		GameplayIdentity = "EscalatingRewardWaves",
		IsRewardIsland = true,
	},
	{
		Id = "BreakTheGuard",
		Title = "Quebre os cristais e os Guardas",
		Description = "Destrua os 2 cristais azuis. Depois derrote os Guardas.",
		-- O contador principal registra apenas Guardas derrotados.
		-- Os cristais são a etapa mecânica que remove a invulnerabilidade.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 3,
		IslandIndex = 1,
		GlobalIslandIndex = 8,
		ProgressEvent = "EnemyDefeated",
		RequiredRole = "Guard",
		BaseTarget = 2,
		TargetPerExtraPlayer = 1,
		ObjectiveKind = "DefeatRole",
		SpawnProfile = "GuardLine",
		GameplayIdentity = "BreakWardsThenGuards",
	},
	{
		Id = "HoldTheBeacon",
		Title = "Mantenha o farol por 25 segundos",
		Description = "Fique dentro da área. Sair pausa o progresso, mas não zera.",
		-- CreateBeacon atualiza BeaconActive imediatamente antes de enviar
		-- BeaconHoldSeconds. Assim, segundos só contam com participante válido
		-- realmente dentro da zona.
		RequiredTargetAttribute = "BeaconActive",
		RoundIndex = 3,
		IslandIndex = 2,
		GlobalIslandIndex = 9,
		ProgressEvent = "BeaconHoldSeconds",
		BaseTarget = 25,
		ObjectiveKind = "HoldZone",
		SpawnProfile = "BeaconDefense",
		GameplayIdentity = "HoldContestedZone",
	},
	{
		Id = "NestCluster",
		Title = "Destrua os 3 ninhos",
		Description = "Quebre os três ninhos enquanto controla os slimes da colônia.",
		-- O objetivo planejado é sempre destruir três ninhos. Party scaling
		-- aumenta a pressão/vida, não a quantidade de objetivos obrigatórios.
		RequiredTargetAttribute = "ObjectiveTargetCompleted",
		RoundIndex = 3,
		IslandIndex = 3,
		GlobalIslandIndex = 10,
		ProgressEvent = "NestDestroyed",
		BaseTarget = 3,
		ObjectiveKind = "DestroyNests",
		SpawnProfile = "NestCluster",
		GameplayIdentity = "DestroySpawners",
	},
	{
		Id = "EliteHunt",
		Title = "Derrote o Elite",
		Description = "Encontre e derrote o Elite para abrir a rota final.",
		-- O kill precisa ser do Elite criado autoritativamente pelo encontro.
		-- Isso impede um Elite ambiental/atrasado de concluir a ilha.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 3,
		IslandIndex = 4,
		GlobalIslandIndex = 11,
		ProgressEvent = "EnemyDefeated",
		RequireElite = true,
		BaseTarget = 1,
		ObjectiveKind = "EliteHunt",
		SpawnProfile = "EliteHunt",
		GameplayIdentity = "DefeatSupportsThenElite",
	},
	{
		Id = "FinalRewardBattle",
		Title = "Vença as 3 ondas finais",
		Description = "Derrote as três ondas e abra o Core Chest para liberar o chefe.",
		-- A batalha final só aceita inimigos criados pelo encontro da ilha 12.
		-- Isso impede mobs atrasados/ambientais de encurtarem a última prova.
		RequiredTargetAttribute = "ObjectiveSpawned",
		RoundIndex = 3,
		IslandIndex = 5,
		GlobalIslandIndex = 12,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 8,
		TargetPerExtraPlayer = 3,
		ObjectiveKind = "RewardBattle",
		SpawnProfile = "FinalRewardWave",
		GameplayIdentity = "EscalatingRewardWaves",
		IsRewardIsland = true,
		IsFinalObjective = true,
	},
}

local BY_ID = {}
local BY_GLOBAL_INDEX = {}
for _, definition in ipairs(DEFINITIONS) do
	BY_ID[definition.Id] = definition
	BY_GLOBAL_INDEX[definition.GlobalIslandIndex] = definition
end

local function scaledTarget(definition, partySize)
	partySize = math.clamp(math.floor(tonumber(partySize) or 1), 1, 4)
	return math.max(
		1,
		math.floor(
			definition.BaseTarget
				+ math.max(0, partySize - 1) * (definition.TargetPerExtraPlayer or 0)
		)
	)
end

local function cloneDefinition(definition, partySize)
	if not definition then
		return nil
	end
	local result = table.clone(definition)
	result.Target = scaledTarget(definition, partySize)
	result.Type = definition.ObjectiveKind
	result.CompletionMode = "Collective"
	result.Metadata = {
		ProgressEvent = definition.ProgressEvent,
		RequiredRole = definition.RequiredRole,
		RequireElite = definition.RequireElite == true,
		RequiredTargetAttribute = definition.RequiredTargetAttribute,
		GameplayIdentity = definition.GameplayIdentity,
		SpawnProfile = definition.SpawnProfile,
		ObjectiveKind = definition.ObjectiveKind,
		IsRewardIsland = definition.IsRewardIsland == true,
		IsFinalObjective = definition.IsFinalObjective == true,
		PartyBalanceVersion = 2,
	}
	return result
end

function ObjectiveCatalog.GetByGlobalIndex(globalIslandIndex, partySize)
	local index = math.floor(tonumber(globalIslandIndex) or 0)
	return cloneDefinition(BY_GLOBAL_INDEX[index], partySize)
end

function ObjectiveCatalog.GetById(objectiveId, partySize)
	return cloneDefinition(BY_ID[objectiveId], partySize)
end

function ObjectiveCatalog.GetAll(partySize)
	local result = table.create(#DEFINITIONS)
	for index, definition in ipairs(DEFINITIONS) do
		result[index] = cloneDefinition(definition, partySize)
	end
	return result
end

function ObjectiveCatalog.Count()
	return #DEFINITIONS
end

function ObjectiveCatalog.Validate()
	assert(#DEFINITIONS == 12, "ObjectiveCatalog precisa possuir exatamente 12 objetivos")
	for index, definition in ipairs(DEFINITIONS) do
		assert(definition.GlobalIslandIndex == index, "GlobalIslandIndex fora de sequencia")
		assert(type(definition.Id) == "string" and definition.Id ~= "", "Objetivo sem Id")
		assert(type(definition.ProgressEvent) == "string", "Objetivo sem ProgressEvent")
		assert(definition.BaseTarget >= 1, "Objetivo com BaseTarget invalido")
		assert(type(definition.GameplayIdentity) == "string", "Objetivo sem identidade jogavel")
	end
	return true
end

ObjectiveCatalog.Validate()

return table.freeze(ObjectiveCatalog)
