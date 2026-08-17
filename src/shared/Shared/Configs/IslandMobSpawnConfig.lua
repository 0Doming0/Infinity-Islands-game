--[[
	Infinity Islands - IslandMobSpawnConfig V5

	Nova politica:
	- uma leva nasce pelo SkyDrop;
	- mortes individuais NAO sao repostas;
	- quando a leva inteira chega a 0 vivos, inicia cooldown;
	- apos o cooldown, a proxima leva limitada cai do ceu;
	- em servidor compartilhado, a populacao e definida uma unica vez no
	  inicio do combate conforme os jogadores presentes na mesma ilha.
]]

local IslandMobSpawnConfig = {}

IslandMobSpawnConfig.Version = "CoopBoundedIslandPopulationV5"

IslandMobSpawnConfig.DefaultMaximumAlive = 14
IslandMobSpawnConfig.MinimumMaximumAlive = 1

IslandMobSpawnConfig.SpawnStaggerSeconds = 0.25
IslandMobSpawnConfig.SkyDropHeightStuds = 18
IslandMobSpawnConfig.AirborneVisualSeconds = 0.85

-- Mantido como diagnostico de compatibilidade. As levas sao limitadas pelo
-- TargetCount da ilha, portanto nao existe respawn infinito.
IslandMobSpawnConfig.RefillCheckSeconds = 0.15
IslandMobSpawnConfig.InfiniteRespawnEnabled = false

-- Cooldown entre uma leva completamente derrotada e a proxima.
IslandMobSpawnConfig.WaveRespawnCooldownSeconds = 4

-- Arena cooperativa compartilhada: jogadores presentes antes da primeira
-- leva colaboram na mesma meta. O valor e travado no inicio para entradas
-- tardias nunca aumentarem a meta no meio de uma luta.
IslandMobSpawnConfig.CoopPopulationEnabled = true
IslandMobSpawnConfig.CoopScaleInitialIsland = false
IslandMobSpawnConfig.CoopAdditionalTargetPerPlayer = 2
IslandMobSpawnConfig.CoopAdditionalAlivePerPlayer = 1
IslandMobSpawnConfig.CoopMaximumTargetCount = 28
IslandMobSpawnConfig.CoopMaximumAlive = 12

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
	activePlayerCount,
	isInitialIsland
)
	local target = math.max(
		1,
		math.floor(tonumber(baseTargetCount) or 1)
	)
	local maximumAlive = math.max(
		1,
		math.floor(tonumber(baseMaximumAlive) or 1)
	)
	local players = math.max(
		1,
		math.floor(tonumber(activePlayerCount) or 1)
	)

	if IslandMobSpawnConfig.CoopPopulationEnabled ~= true
		or (isInitialIsland == true and IslandMobSpawnConfig.CoopScaleInitialIsland ~= true)
	then
		return target, math.min(maximumAlive, target)
	end

	local extraPlayers = players - 1
	local targetCap = math.max(1, IslandMobSpawnConfig.CoopMaximumTargetCount)
	local aliveCap = math.max(1, IslandMobSpawnConfig.CoopMaximumAlive)
	target = math.min(target, targetCap)
	maximumAlive = math.min(maximumAlive, aliveCap)

	target = math.min(
		targetCap,
		target + extraPlayers * IslandMobSpawnConfig.CoopAdditionalTargetPerPlayer
	)
	maximumAlive = math.min(
		aliveCap,
		maximumAlive + extraPlayers * IslandMobSpawnConfig.CoopAdditionalAlivePerPlayer
	)

	return target, math.min(maximumAlive, target)
end

function IslandMobSpawnConfig.Validate()
	assert(IslandMobSpawnConfig.GetMaximumAlive(3) == 3)
	assert(IslandMobSpawnConfig.GetMaximumAlive(7) == 7)
	assert(IslandMobSpawnConfig.GetMaximumAlive(12) == 12)
	assert(IslandMobSpawnConfig.GetMaximumAlive(14) == 14)
	assert(IslandMobSpawnConfig.GetMaximumAlive(20) == 14)
	assert(IslandMobSpawnConfig.SpawnStaggerSeconds >= 0.20)
	assert(IslandMobSpawnConfig.WaveRespawnCooldownSeconds >= 1)
	assert(IslandMobSpawnConfig.InfiniteRespawnEnabled == false)
	local coopTarget, coopAlive = IslandMobSpawnConfig.GetCoopPopulation(3, 3, 4, false)
	assert(coopTarget == 9 and coopAlive == 6)
	local initialTarget, initialAlive = IslandMobSpawnConfig.GetCoopPopulation(7, 7, 4, true)
	assert(initialTarget == 7 and initialAlive == 7)
	local cappedTarget, cappedAlive = IslandMobSpawnConfig.GetCoopPopulation(50, 14, 1, false)
	assert(cappedTarget == 28 and cappedAlive == 12)
	return true
end

IslandMobSpawnConfig.Validate()

return table.freeze(IslandMobSpawnConfig)
