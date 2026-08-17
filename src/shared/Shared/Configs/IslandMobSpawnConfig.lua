--[[
	Infinity Islands - Fixed finite island population

	MVP rule:
	- every island has one fixed mob quota;
	- all mobs required by that quota belong to the same encounter;
	- killing a mob NEVER creates a replacement;
	- dying/returning to the island NEVER increases the quota;
	- multiplayer shares the same quota instead of adding more mobs.

	Party difficulty can still scale HP/damage elsewhere. Quantity stays simple.
]]

local IslandMobSpawnConfig = {}

IslandMobSpawnConfig.Version = "FixedFiniteIslandPopulationV6"

IslandMobSpawnConfig.DefaultMaximumAlive = 14
IslandMobSpawnConfig.MinimumMaximumAlive = 1

IslandMobSpawnConfig.SpawnStaggerSeconds = 0.25
IslandMobSpawnConfig.SkyDropHeightStuds = 18
IslandMobSpawnConfig.AirborneVisualSeconds = 0.85

-- Compatibility fields. Infinite refill/waves are intentionally disabled.
IslandMobSpawnConfig.RefillCheckSeconds = 0.15
IslandMobSpawnConfig.InfiniteRespawnEnabled = false
IslandMobSpawnConfig.WaveRespawnCooldownSeconds = 0

-- The MVP uses one shared deterministic quota. A second player must not make
-- the island suddenly require extra mobs, especially after a death/rejoin.
IslandMobSpawnConfig.CoopPopulationEnabled = false
IslandMobSpawnConfig.CoopScaleInitialIsland = false
IslandMobSpawnConfig.CoopAdditionalTargetPerPlayer = 0
IslandMobSpawnConfig.CoopAdditionalAlivePerPlayer = 0
IslandMobSpawnConfig.CoopMaximumTargetCount = 14
IslandMobSpawnConfig.CoopMaximumAlive = 14

function IslandMobSpawnConfig.GetMaximumAlive(targetCount)
	targetCount = math.max(
		1,
		math.floor(tonumber(targetCount) or 1)
	)

	return math.clamp(
		targetCount,
		IslandMobSpawnConfig.MinimumMaximumAlive,
		IslandMobSpawnConfig.DefaultMaximumAlive
	)
end

function IslandMobSpawnConfig.GetCoopPopulation(
	baseTargetCount,
	baseMaximumAlive,
	_activePlayerCount,
	_isInitialIsland
)
	local target = math.clamp(
		math.floor(tonumber(baseTargetCount) or 1),
		1,
		IslandMobSpawnConfig.CoopMaximumTargetCount
	)

	-- Keep the complete encounter inside the finite initial population.
	local maximumAlive = math.clamp(
		math.floor(tonumber(baseMaximumAlive) or target),
		1,
		IslandMobSpawnConfig.CoopMaximumAlive
	)
	maximumAlive = math.min(target, math.max(maximumAlive, target))

	return target, maximumAlive
end

function IslandMobSpawnConfig.Validate()
	assert(IslandMobSpawnConfig.GetMaximumAlive(3) == 3)
	assert(IslandMobSpawnConfig.GetMaximumAlive(7) == 7)
	assert(IslandMobSpawnConfig.GetMaximumAlive(12) == 12)
	assert(IslandMobSpawnConfig.GetMaximumAlive(14) == 14)
	assert(IslandMobSpawnConfig.GetMaximumAlive(20) == 14)
	assert(IslandMobSpawnConfig.SpawnStaggerSeconds >= 0.20)
	assert(IslandMobSpawnConfig.InfiniteRespawnEnabled == false)
	assert(IslandMobSpawnConfig.CoopPopulationEnabled == false)

	local coopTarget, coopAlive = IslandMobSpawnConfig.GetCoopPopulation(8, 8, 4, false)
	assert(coopTarget == 8 and coopAlive == 8)

	local cappedTarget, cappedAlive = IslandMobSpawnConfig.GetCoopPopulation(50, 14, 4, false)
	assert(cappedTarget == 14 and cappedAlive == 14)

	return true
end

IslandMobSpawnConfig.Validate()

return table.freeze(IslandMobSpawnConfig)
