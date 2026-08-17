--[[
	Infinity Islands - RareChestConfig V1

	Rare chest rules:
	- random distribution across currently materialized Combat Islands;
	- never more than 2 spawned chests per island;
	- if a selected island already has 2, another island is selected;
	- no coin/score reward;
	- opening spills physical XP collectibles through MobXPCollectibleService.
]]

local Config = {}

Config.Version = "RareChestV3SparseIslandRoll"

Config.MinimumGlobalIslandIndex = 3

-- Cada ilha de combate recebe uma rolagem determinística. Assim, abrir um
-- raro não faz o serviço colocar outro imediatamente na mesma janela do
-- mundo. Em média há um raro a cada quatorze ilhas elegíveis.
Config.RareChestIslandChance = 0.07
Config.IslandRollSalt = 9137
Config.MaximumActiveChests = 1

Config.MaximumChestsPerIsland = 1
Config.ReconcileInterval = 1.5

Config.MinimumChestSpacing = 12
Config.EdgeInsetRatio = 0.26
Config.PlacementAttempts = 24

Config.PromptActionText = "Abrir"
Config.PromptObjectText = "Baú Raro"
Config.PromptDistance = 9
Config.PromptHoldDuration = 0.15

-- Um raro precisa ser um momento de recompensa perceptível: cerca de 4x o
-- valor anterior, sem substituir o XP principal vindo dos mobs.
Config.BaseXP = 180
Config.XPPerIslandLevel = 30
Config.MaximumXP = 720

Config.OpenDestroyDelay = 0.65

Config.TemplateNames = table.freeze({
	"RareChest",
	"RareTreasureChest",
	"TreasureChestRare",
	"TreasureChest",
	"Chest",
})

function Config.GetXPReward(islandLevel)
	local level =
		math.max(
			1,
			math.floor(
				tonumber(islandLevel) or 1
			)
		)

	return math.clamp(
		Config.BaseXP
			+ Config.XPPerIslandLevel
				* (level - 1),
		Config.BaseXP,
		Config.MaximumXP
	)
end

function Config.IsIslandEligible(
	globalIslandIndex
)
	local index =
		math.max(
			0,
			math.floor(
				tonumber(
					globalIslandIndex
				) or 0
			)
		)

	if index < Config.MinimumGlobalIslandIndex then
		return false
	end

	local random = Random.new(index * Config.IslandRollSalt)
	return random:NextNumber() <= Config.RareChestIslandChance
end

function Config.GetDesiredActiveChestCount(
	eligibleIslandCount
)
	local count =
		math.max(
			0,
			math.floor(
				tonumber(
					eligibleIslandCount
				) or 0
			)
		)

	return math.clamp(
		count,
		0,
		Config.MaximumActiveChests
	)
end

return table.freeze(Config)
