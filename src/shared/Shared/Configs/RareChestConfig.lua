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

Config.Version = "RareChestV1PhysicalXP"

Config.MinimumGlobalIslandIndex = 2

-- Roughly 2 rare chests across a normal 5-island active window.
Config.IslandsPerActiveChest = 3
Config.MinimumActiveChests = 1
Config.MaximumActiveChests = 4

Config.MaximumChestsPerIsland = 2
Config.ReconcileInterval = 1.5

Config.MinimumChestSpacing = 12
Config.EdgeInsetRatio = 0.26
Config.PlacementAttempts = 24

Config.PromptActionText = "Abrir"
Config.PromptObjectText = "Baú Raro"
Config.PromptDistance = 9
Config.PromptHoldDuration = 0.15

-- A rare chest should feel meaningful, but remains secondary to combat.
Config.BaseXP = 45
Config.XPPerIslandLevel = 8
Config.MaximumXP = 180

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

function Config.GetDesiredActiveChestCount(
	materializedIslandCount
)
	local count =
		math.max(
			0,
			math.floor(
				tonumber(
					materializedIslandCount
				) or 0
			)
		)

	if count <= 0 then
		return 0
	end

	return math.clamp(
		math.ceil(
			count
				/ Config.IslandsPerActiveChest
		),
		Config.MinimumActiveChests,
		Config.MaximumActiveChests
	)
end

return table.freeze(Config)
