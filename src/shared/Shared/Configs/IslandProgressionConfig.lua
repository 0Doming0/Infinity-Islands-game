--[[
	Infinity Islands - progressao simples por ilha.

	Este modulo e a fonte unica para converter a posicao logica da ilha em
	IslandLevel/RecommendedLevel. Ele NAO le PlayerLevel e NAO escala inimigos.
	Isso e intencional: a dificuldade pertence a ilha, nao ao jogador.

	V1:
	- duas ilhas por nivel;
	- ilha 1-2 = level 1;
	- ilha 3-4 = level 2;
	- ilha 5-6 = level 3; etc.
]]

local IslandProgressionConfig = {}

IslandProgressionConfig.Version = "IslandLevelV1"
IslandProgressionConfig.StartingLevel = 1
IslandProgressionConfig.IslandsPerLevel = 2
IslandProgressionConfig.MaximumLevel = 999

local function cleanIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

function IslandProgressionConfig.GetIslandLevel(progressionIslandIndex)
	local index = cleanIndex(progressionIslandIndex)
	local level = IslandProgressionConfig.StartingLevel
		+ math.floor((index - 1) / IslandProgressionConfig.IslandsPerLevel)

	return math.clamp(
		level,
		IslandProgressionConfig.StartingLevel,
		IslandProgressionConfig.MaximumLevel
	)
end

function IslandProgressionConfig.GetRecommendedLevel(progressionIslandIndex)
	return IslandProgressionConfig.GetIslandLevel(progressionIslandIndex)
end

function IslandProgressionConfig.GetSnapshot(progressionIslandIndex)
	local index = cleanIndex(progressionIslandIndex)
	local level = IslandProgressionConfig.GetIslandLevel(index)

	return {
		Version = IslandProgressionConfig.Version,
		ProgressionIslandIndex = index,
		IslandLevel = level,
		RecommendedLevel = level,

		-- Reservado para a futura tarefa de XP.
		-- V1 permanece neutro e nao altera gameplay.
		XPRewardMultiplier = 1,
	}
end

function IslandProgressionConfig.Validate()
	assert(
		IslandProgressionConfig.IslandsPerLevel >= 1,
		"IslandsPerLevel precisa ser >= 1"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(1) == 1,
		"Ilha 1 precisa ser level 1"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(2) == 1,
		"Ilha 2 precisa ser level 1"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(3) == 2,
		"Ilha 3 precisa ser level 2"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(4) == 2,
		"Ilha 4 precisa ser level 2"
	)
	assert(
		IslandProgressionConfig.GetIslandLevel(5) == 3,
		"Ilha 5 precisa ser level 3"
	)

	return true
end

IslandProgressionConfig.Validate()

return table.freeze(IslandProgressionConfig)
