--[[
	Infinity Islands - Task 05 + Task 07 + Task 13
	IslandMobScalingConfig V5

	Difficulty belongs to the island.

	PlayerLevel MUST NOT be read when creating/scaling enemies.

	Task 05 scope:
	- planned mob amount grows with the numbered island position in the cycle;
	- MobLevel = LevelInCycle;
	- HP scaling by MobLevel;
	- damage scaling by MobLevel;
	- regular Combat Islands always have combat;
	- regular composition stays deliberately simple (Green) until Task 06.

	Task 07 scope:
	- every completed 12-numbered-island cycle compounds enemy HP by 3x;
	- every completed cycle compounds enemy damage by 3x;
	- every completed cycle compounds enemy movement speed by 2x.

	Task 13 polish:
	- MobLevel uses LevelInCycle so cycles repeat the same 12-level curve;
	- CycleIndex remains the only source of cross-cycle stat escalation.

	V4 mob-count policy:
	- island size no longer makes the count fall unexpectedly;
	- numbered islands 1-12 generate 3-14 mobs respectively;
	- the next cycle returns to 3 mobs;
	- the Initial Island keeps its explicit tutorial override.
]]

local IslandMobScalingConfig = {}

IslandMobScalingConfig.Version = "StrongerPerLevelAndBaseV5"

-- A base reforcada deixa ate o primeiro nivel numerado mais perigoso. A curva
-- de 18% faz o nivel 12 chegar a 4.023x antes do multiplicador de ciclo.
IslandMobScalingConfig.BaseHealthMultiplier = 1.35
IslandMobScalingConfig.BaseDamageMultiplier = 1.35
IslandMobScalingConfig.HealthPerLevel = 0.18
IslandMobScalingConfig.DamagePerLevel = 0.18
IslandMobScalingConfig.HealthPerCycle = 3
IslandMobScalingConfig.DamagePerCycle = 3
IslandMobScalingConfig.SpeedPerCycle = 2

IslandMobScalingConfig.RegularVariant = "Green"
IslandMobScalingConfig.MinimumSpawnSpacingStuds = 6.5
IslandMobScalingConfig.SpawnRetrySeconds = 0.20
IslandMobScalingConfig.DefaultMaximumActiveMonsters = 45

IslandMobScalingConfig.BaseMobsPerCycle = 3
IslandMobScalingConfig.ExtraMobsPerIsland = 1
IslandMobScalingConfig.MaximumMobsPerIsland = 14

-- Kept for compatibility with diagnostics. Count progression is deliberately
-- identical for every terrain size so ascending the route never lowers it.
IslandMobScalingConfig.SizeProfiles = table.freeze({
	Small = table.freeze({
		BaseCount = 3,
		LevelsPerExtraMob = 1,
		MaximumCount = 14,
	}),
	Medium = table.freeze({
		BaseCount = 3,
		LevelsPerExtraMob = 1,
		MaximumCount = 14,
	}),
	Large = table.freeze({
		BaseCount = 3,
		LevelsPerExtraMob = 1,
		MaximumCount = 14,
	}),
})

local function cleanLevel(value)
	return math.max(
		1,
		math.floor(tonumber(value) or 1)
	)
end

local function cleanCycleIndex(value)
	return math.max(
		1,
		math.floor(tonumber(value) or 1)
	)
end

local function compoundedCycleMultiplier(
	cycleIndex,
	perCycleMultiplier
)
	local completedCycles =
		cleanCycleIndex(cycleIndex) - 1

	return perCycleMultiplier ^ completedCycles
end

function IslandMobScalingConfig.GetHealthMultiplier(mobLevel)
	local level = cleanLevel(mobLevel)

	return IslandMobScalingConfig.BaseHealthMultiplier
		* (
			1
				+ IslandMobScalingConfig.HealthPerLevel
					* (level - 1)
		)
end

function IslandMobScalingConfig.GetDamageMultiplier(mobLevel)
	local level = cleanLevel(mobLevel)

	return IslandMobScalingConfig.BaseDamageMultiplier
		* (
			1
				+ IslandMobScalingConfig.DamagePerLevel
					* (level - 1)
		)
end

function IslandMobScalingConfig.GetCycleMultipliers(cycleIndex)
	return {
		Health = compoundedCycleMultiplier(
			cycleIndex,
			IslandMobScalingConfig.HealthPerCycle
		),
		Damage = compoundedCycleMultiplier(
			cycleIndex,
			IslandMobScalingConfig.DamagePerCycle
		),
		Speed = compoundedCycleMultiplier(
			cycleIndex,
			IslandMobScalingConfig.SpeedPerCycle
		),
	}
end

function IslandMobScalingConfig.GetPlannedMobCount(
	_islandSize,
	islandPositionInCycle
)
	local position = cleanLevel(islandPositionInCycle)
	local extra =
		(position - 1)
			* IslandMobScalingConfig.ExtraMobsPerIsland

	return math.clamp(
		IslandMobScalingConfig.BaseMobsPerCycle + extra,
		IslandMobScalingConfig.BaseMobsPerCycle,
		IslandMobScalingConfig.MaximumMobsPerIsland
	)
end

function IslandMobScalingConfig.GetProfile(islandSize)
	return IslandMobScalingConfig.SizeProfiles[
		tostring(islandSize or "")
	] or IslandMobScalingConfig.SizeProfiles.Small
end

function IslandMobScalingConfig.Validate()
	local cycle1 =
		IslandMobScalingConfig.GetCycleMultipliers(1)
	local cycle2 =
		IslandMobScalingConfig.GetCycleMultipliers(2)
	local cycle3 =
		IslandMobScalingConfig.GetCycleMultipliers(3)

	assert(
		math.abs(IslandMobScalingConfig.GetHealthMultiplier(1) - 1.35) < 0.0001
			and math.abs(IslandMobScalingConfig.GetDamageMultiplier(1) - 1.35) < 0.0001,
		"Nivel 1 precisa aplicar o reforco base de 1.35x"
	)
	assert(
		math.abs(IslandMobScalingConfig.GetHealthMultiplier(12) - 4.023) < 0.0001
			and math.abs(IslandMobScalingConfig.GetDamageMultiplier(12) - 4.023) < 0.0001,
		"Nivel 12 precisa chegar a 4.023x de vida e dano"
	)
	assert(
		cycle1.Health == 1
			and cycle1.Damage == 1
			and cycle1.Speed == 1,
		"Cycle 1 precisa manter stats base"
	)
	assert(
		cycle2.Health == 3
			and cycle2.Damage == 3
			and cycle2.Speed == 2,
		"Cycle 2 precisa aplicar 3x HP/dano e 2x velocidade"
	)
	assert(
		cycle3.Health == 9
			and cycle3.Damage == 9
			and cycle3.Speed == 4,
		"Multiplicadores precisam acumular a cada ciclo"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Small", 1) == 3,
		"Primeira ilha do ciclo precisa de 3 mobs"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Medium", 1) == 3
			and IslandMobScalingConfig.GetPlannedMobCount("Large", 1) == 3,
		"Tamanho da ilha nao pode reduzir ou aumentar a curva"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Small", 6) == 8,
		"Sexta ilha do ciclo precisa de 8 mobs"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Large", 12) == 14,
		"Decima segunda ilha do ciclo precisa de 14 mobs"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Small", 100) == 14,
		"Quantidade precisa respeitar cap 14"
	)

	return true
end

IslandMobScalingConfig.Validate()

return table.freeze(IslandMobScalingConfig)
