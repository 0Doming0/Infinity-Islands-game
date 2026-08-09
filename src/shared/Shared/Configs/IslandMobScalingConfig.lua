--[[
	Infinity Islands - Task 05
	IslandMobScalingConfig V1

	Difficulty belongs to the island.

	PlayerLevel MUST NOT be read when creating/scaling enemies.

	Task 05 scope:
	- planned mob amount by island size + IslandLevel;
	- MobLevel = IslandLevel;
	- HP scaling by MobLevel;
	- damage scaling by MobLevel;
	- regular Combat Islands always have combat;
	- regular composition stays deliberately simple (Green) until Task 06.
]]

local IslandMobScalingConfig = {}

IslandMobScalingConfig.Version = "IslandLevelMobScalingV1"

IslandMobScalingConfig.HealthPerLevel = 0.16
IslandMobScalingConfig.DamagePerLevel = 0.10

IslandMobScalingConfig.RegularVariant = "Green"
IslandMobScalingConfig.MinimumSpawnSpacingStuds = 6.5
IslandMobScalingConfig.SpawnRetrySeconds = 0.20
IslandMobScalingConfig.DefaultMaximumActiveMonsters = 45

IslandMobScalingConfig.SizeProfiles = table.freeze({
	Small = table.freeze({
		BaseCount = 3,
		LevelsPerExtraMob = 4,
		MaximumCount = 6,
	}),
	Medium = table.freeze({
		BaseCount = 5,
		LevelsPerExtraMob = 3,
		MaximumCount = 9,
	}),
	Large = table.freeze({
		BaseCount = 7,
		LevelsPerExtraMob = 3,
		MaximumCount = 12,
	}),
})

local function cleanLevel(value)
	return math.max(
		1,
		math.floor(tonumber(value) or 1)
	)
end

function IslandMobScalingConfig.GetHealthMultiplier(mobLevel)
	local level = cleanLevel(mobLevel)

	return 1
		+ IslandMobScalingConfig.HealthPerLevel
			* (level - 1)
end

function IslandMobScalingConfig.GetDamageMultiplier(mobLevel)
	local level = cleanLevel(mobLevel)

	return 1
		+ IslandMobScalingConfig.DamagePerLevel
			* (level - 1)
end

function IslandMobScalingConfig.GetPlannedMobCount(
	islandSize,
	islandLevel
)
	local profile =
		IslandMobScalingConfig.SizeProfiles[
			tostring(islandSize or "")
		]

	if not profile then
		profile =
			IslandMobScalingConfig.SizeProfiles.Small
	end

	local level = cleanLevel(islandLevel)

	local extra =
		math.floor(
			(level - 1)
				/ profile.LevelsPerExtraMob
		)

	return math.clamp(
		profile.BaseCount + extra,
		profile.BaseCount,
		profile.MaximumCount
	)
end

function IslandMobScalingConfig.GetProfile(islandSize)
	return IslandMobScalingConfig.SizeProfiles[
		tostring(islandSize or "")
	] or IslandMobScalingConfig.SizeProfiles.Small
end

function IslandMobScalingConfig.Validate()
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Small", 1) == 3,
		"Small L1 precisa de 3 mobs"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Medium", 1) == 5,
		"Medium L1 precisa de 5 mobs"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Large", 1) == 7,
		"Large L1 precisa de 7 mobs"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Small", 100) == 6,
		"Small precisa respeitar cap 6"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Medium", 100) == 9,
		"Medium precisa respeitar cap 9"
	)
	assert(
		IslandMobScalingConfig.GetPlannedMobCount("Large", 100) == 12,
		"Large precisa respeitar cap 12"
	)

	return true
end

IslandMobScalingConfig.Validate()

return table.freeze(IslandMobScalingConfig)
