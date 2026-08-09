--[[
	Infinity Islands - IslandMobSpawnConfig V3

	Nova politica:
	- uma leva nasce pelo SkyDrop;
	- mortes individuais NAO sao repostas;
	- quando a leva inteira chega a 0 vivos, inicia cooldown;
	- apos o cooldown, uma nova leva completa cai do ceu.
]]

local IslandMobSpawnConfig = {}

IslandMobSpawnConfig.Version = "FullWaveCooldownV3"

IslandMobSpawnConfig.DefaultMaximumAlive = 7
IslandMobSpawnConfig.MinimumMaximumAlive = 1

IslandMobSpawnConfig.SpawnStaggerSeconds = 0.25
IslandMobSpawnConfig.SkyDropHeightStuds = 18
IslandMobSpawnConfig.AirborneVisualSeconds = 0.85

-- Mantido por compatibilidade com o MonsterSpawner existente.
IslandMobSpawnConfig.RefillCheckSeconds = 0.15
IslandMobSpawnConfig.InfiniteRespawnEnabled = true

-- Cooldown entre uma leva completamente derrotada e a proxima.
IslandMobSpawnConfig.WaveRespawnCooldownSeconds = 4

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
	assert(IslandMobSpawnConfig.WaveRespawnCooldownSeconds >= 1)
	assert(IslandMobSpawnConfig.InfiniteRespawnEnabled == true)
	return true
end

IslandMobSpawnConfig.Validate()

return table.freeze(IslandMobSpawnConfig)
