--[[
	Infinity Islands - Task 30
	IslandMobSpawnConfig V2 - Infinite Sky Refill

	MobTargetCount is a kill quota, not a lifetime spawn cap.
	Active islands continuously refill open MaxAlive slots from the sky.
]]

local IslandMobSpawnConfig = {}

IslandMobSpawnConfig.Version = "InfiniteSkyRefillV2"

IslandMobSpawnConfig.DefaultMaximumAlive = 7
IslandMobSpawnConfig.MinimumMaximumAlive = 1

IslandMobSpawnConfig.SpawnStaggerSeconds = 0.25
IslandMobSpawnConfig.SkyDropHeightStuds = 18
IslandMobSpawnConfig.AirborneVisualSeconds = 0.85
IslandMobSpawnConfig.RefillCheckSeconds = 0.15
IslandMobSpawnConfig.InfiniteRespawnEnabled = true

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

function IslandMobSpawnConfig.Validate()
	assert(IslandMobSpawnConfig.GetMaximumAlive(3) == 3)
	assert(IslandMobSpawnConfig.GetMaximumAlive(7) == 7)
	assert(IslandMobSpawnConfig.GetMaximumAlive(12) == 7)
	assert(IslandMobSpawnConfig.SpawnStaggerSeconds >= 0.20)
	assert(IslandMobSpawnConfig.InfiniteRespawnEnabled == true)
	return true
end

IslandMobSpawnConfig.Validate()

return table.freeze(IslandMobSpawnConfig)
