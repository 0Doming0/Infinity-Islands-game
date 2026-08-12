--[[
	Infinity Islands - progressao acelerada por ilha.

	Este modulo e a fonte unica para converter a posicao logica da ilha em
	IslandLevel/RecommendedLevel. Ele NAO le PlayerLevel e NAO escala inimigos.
	Isso e intencional: a dificuldade pertence a ilha, nao ao jogador.

	V5:
	- a primeira posicao da rota e a Ilha Inicial, fora da numeracao;
	- a Ilha Inicial continua level 1 e nao recebe placa;
	- a primeira ilha numerada usa a segunda posicao da curva;
	- os saltos crescem em pares: +2, +2, +3, +3, +4, +4...;
	- niveis da rota: Inicial 1; Ilha 1 = 3; Ilha 2 = 5; Ilha 3 = 8...;
	- 12 ilhas NUMERADAS formam um ciclo completo de mobs;
	- a Ilha Inicial nao ocupa uma posicao do ciclo;
	- CycleIndex avanca depois de cada 12 ilhas numeradas;
	- LevelInCycle reinicia em 1 no inicio do proximo ciclo;
	- XP de mobs acumula 3x por ciclo para acompanhar a vida dos inimigos;
	- LevelInCycle e o nivel de stats dos mobs e repete a curva de 1 a 12;
	- o desbloqueio do roster usa o indice global e nunca volta ao Green;
	- IslandLevel continua global para recomendacao e bonus de risco;
	- os multiplicadores de combate sao consumidos pelo MobScaling, nao aqui.
]]

local IslandProgressionConfig = {}

IslandProgressionConfig.Version = "NumberedIslandCyclesV5"
IslandProgressionConfig.StartingLevel = 1
IslandProgressionConfig.IslandsPerLevel = 1
IslandProgressionConfig.LevelsPerCycle = 12
IslandProgressionConfig.IslandsPerCycle =
	IslandProgressionConfig.IslandsPerLevel
		* IslandProgressionConfig.LevelsPerCycle
IslandProgressionConfig.XPRewardPerCycle = 3
IslandProgressionConfig.MaximumLevel = 999

local function cleanIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

function IslandProgressionConfig.GetIslandLevel(progressionIslandIndex)
	local index = cleanIndex(progressionIslandIndex)
	local transitions = index - 1
	local completePairs = math.floor(transitions / 2)
	local remainingTransition = transitions % 2

	-- Soma dos saltos +2,+2,+3,+3... sem precisar iterar pelas ilhas.
	local accumulatedGap =
		completePairs * (completePairs + 3)
			+ remainingTransition * (completePairs + 2)

	local level = IslandProgressionConfig.StartingLevel
		+ accumulatedGap

	return math.clamp(
		level,
		IslandProgressionConfig.StartingLevel,
		IslandProgressionConfig.MaximumLevel
	)
end

function IslandProgressionConfig.GetRecommendedLevel(progressionIslandIndex)
	return IslandProgressionConfig.GetIslandLevel(progressionIslandIndex)
end

function IslandProgressionConfig.GetNumberedIslandIndex(progressionIslandIndex)
	return math.max(
		0,
		cleanIndex(progressionIslandIndex) - 1
	)
end

function IslandProgressionConfig.GetCycleIndex(progressionIslandIndex)
	local numberedIndex =
		IslandProgressionConfig.GetNumberedIslandIndex(
			progressionIslandIndex
		)

	if numberedIndex == 0 then
		return 1
	end

	return 1
		+ math.floor(
			(numberedIndex - 1)
				/ IslandProgressionConfig.IslandsPerCycle
		)
end

function IslandProgressionConfig.GetIslandIndexInCycle(progressionIslandIndex)
	local numberedIndex =
		IslandProgressionConfig.GetNumberedIslandIndex(
			progressionIslandIndex
		)

	if numberedIndex == 0 then
		return 0
	end

	return 1
		+ (
			(numberedIndex - 1)
				% IslandProgressionConfig.IslandsPerCycle
		)
end

function IslandProgressionConfig.GetLevelInCycle(progressionIslandIndex)
	local islandIndexInCycle =
		IslandProgressionConfig.GetIslandIndexInCycle(
			progressionIslandIndex
		)

	return math.max(1, islandIndexInCycle)
end

function IslandProgressionConfig.GetXPRewardMultiplier(cycleIndex)
	local cleanCycleIndex = cleanIndex(cycleIndex)
	local completedCycles = cleanCycleIndex - 1

	return IslandProgressionConfig.XPRewardPerCycle
		^ completedCycles
end

function IslandProgressionConfig.GetSnapshot(progressionIslandIndex)
	local index = cleanIndex(progressionIslandIndex)
	local level = IslandProgressionConfig.GetIslandLevel(index)
	local cycleIndex = IslandProgressionConfig.GetCycleIndex(index)
	local islandIndexInCycle =
		IslandProgressionConfig.GetIslandIndexInCycle(index)
	local levelInCycle =
		IslandProgressionConfig.GetLevelInCycle(index)
	local numberedIslandIndex =
		IslandProgressionConfig.GetNumberedIslandIndex(index)

	return {
		Version = IslandProgressionConfig.Version,
		ProgressionIslandIndex = index,
		NumberedIslandIndex = numberedIslandIndex,
		IslandLevel = level,
		RecommendedLevel = level,
		CycleIndex = cycleIndex,
		IslandIndexInCycle = islandIndexInCycle,
		LevelInCycle = levelInCycle,

		XPRewardMultiplier =
			IslandProgressionConfig.GetXPRewardMultiplier(
				cycleIndex
			),
	}
end

function IslandProgressionConfig.Validate()
	assert(
		IslandProgressionConfig.IslandsPerLevel >= 1,
		"IslandsPerLevel precisa ser >= 1"
	)
	assert(
		IslandProgressionConfig.LevelsPerCycle >= 1,
		"LevelsPerCycle precisa ser >= 1"
	)
	assert(
		IslandProgressionConfig.IslandsPerCycle
			== IslandProgressionConfig.IslandsPerLevel
				* IslandProgressionConfig.LevelsPerCycle,
		"IslandsPerCycle precisa acompanhar niveis e ilhas por nivel"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(1) == 1,
		"Ilha Inicial precisa ser level 1"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(2) == 3,
		"Ilha numerada 1 precisa ser level 3"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(3) == 5,
		"Ilha numerada 2 precisa ser level 5"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(4) == 8,
		"Ilha numerada 3 precisa ampliar o salto para level 8"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(12) == 48,
		"Ilha numerada 11 precisa chegar ao level 48"
	)
	assert(
		IslandProgressionConfig.GetNumberedIslandIndex(1) == 0
			and IslandProgressionConfig.GetNumberedIslandIndex(2) == 1,
		"Ilha Inicial precisa ficar fora da numeracao"
	)
	assert(
		IslandProgressionConfig.GetCycleIndex(2) == 1
			and IslandProgressionConfig.GetCycleIndex(13) == 1,
		"Ilhas numeradas 1-12 precisam pertencer ao Cycle 1"
	)
	assert(
		IslandProgressionConfig.GetCycleIndex(14) == 2,
		"Ilha numerada 13 precisa iniciar o Cycle 2"
	)
	assert(
		IslandProgressionConfig.GetIslandIndexInCycle(1) == 0
			and IslandProgressionConfig.GetIslandIndexInCycle(13) == 12
			and IslandProgressionConfig.GetIslandIndexInCycle(14) == 1,
		"IslandIndexInCycle precisa reiniciar no novo ciclo"
	)
	assert(
		IslandProgressionConfig.GetLevelInCycle(13) == 12
			and IslandProgressionConfig.GetLevelInCycle(14) == 1,
		"LevelInCycle precisa reiniciar no novo ciclo"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(13) == 55,
		"IslandLevel global precisa continuar no novo ciclo"
	)
	assert(
		IslandProgressionConfig.GetXPRewardMultiplier(1) == 1
			and IslandProgressionConfig.GetXPRewardMultiplier(2) == 3
			and IslandProgressionConfig.GetXPRewardMultiplier(3) == 9,
		"XP precisa acumular 3x por ciclo"
	)
	assert(
		IslandProgressionConfig.GetSnapshot(14).XPRewardMultiplier == 3,
		"Ilha numerada 13 precisa iniciar com 3x XP"
	)

	return true
end

IslandProgressionConfig.Validate()

return table.freeze(IslandProgressionConfig)
