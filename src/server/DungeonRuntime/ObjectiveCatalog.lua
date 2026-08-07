local ObjectiveCatalog = {}

local DEFINITIONS = {
	{
		Id = "FirstStrike",
		Title = "Primeiro golpe",
		Description = "Acerte o slime marcado para iniciar a expedicao.",
		RequiredTargetAttribute = "ObjectiveFocusTarget",
		GameplayIdentity = "MarkedOpeningTarget",
		RoundIndex = 1,
		IslandIndex = 1,
		GlobalIslandIndex = 1,
		ProgressEvent = "EnemyHit",
		BaseTarget = 1,
		ObjectiveKind = "CombatIntro",
		SpawnProfile = "FirstStrike",
	},
	{
		Id = "ClearThePath",
		Title = "Limpe o caminho",
		Description = "Derrote os slimes que bloqueiam a saida.",
		RoundIndex = 1,
		IslandIndex = 2,
		GlobalIslandIndex = 2,
		ProgressEvent = "EnemyDefeated",
		BaseTarget = 4,
		TargetPerExtraPlayer = 1,
		ObjectiveKind = "DefeatEnemies",
		SpawnProfile = "CommonWave",
		GameplayIdentity = "OpenCombat",
	},
	{
		Id = "FirstRewardBattle",
		Title = "Proteja a primeira recompensa",
		Description = "Venca a onda e libere os baus da rodada.",
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
		Title = "Emboscada no ceu",
		Description = "Sobreviva a emboscada e derrote todos os atacantes.",
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
		Title = "Ameaca a distancia",
		Description = "Elimine os slimes cuspidores antes que dominem a ilha.",
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
		Title = "Destrua os ninhos",
		Description = "Quebre os ninhos antes que novos slimes aparecam.",
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
		Title = "Defenda a segunda recompensa",
		Description = "Derrote a guarda da recompensa para liberar os baus.",
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
		Title = "Quebre a guarda",
		Description = "Derrote os slimes guardioes que protegem a passagem.",
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
		Title = "Mantenha o farol",
		Description = "Permaneça na area do farol ate completar a carga.",
		RoundIndex = 3,
		IslandIndex = 2,
		GlobalIslandIndex = 9,
		ProgressEvent = "BeaconHoldSeconds",
		BaseTarget = 16,
		TargetPerExtraPlayer = 3,
		ObjectiveKind = "HoldZone",
		SpawnProfile = "BeaconDefense",
		GameplayIdentity = "HoldContestedZone",
	},
	{
		Id = "NestCluster",
		Title = "Colonia de ninhos",
		Description = "Destrua todos os ninhos da colonia.",
		RoundIndex = 3,
		IslandIndex = 3,
		GlobalIslandIndex = 10,
		ProgressEvent = "NestDestroyed",
		BaseTarget = 3,
		TargetPerExtraPlayer = 1,
		ObjectiveKind = "DestroyNests",
		SpawnProfile = "NestCluster",
		GameplayIdentity = "DestroySpawners",
	},
	{
		Id = "EliteHunt",
		Title = "Cace o elite",
		Description = "Derrote o slime elite para abrir a rota final.",
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
		Title = "Batalha da recompensa final",
		Description = "Venca a ultima onda e prepare o caminho para o chefe.",
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
