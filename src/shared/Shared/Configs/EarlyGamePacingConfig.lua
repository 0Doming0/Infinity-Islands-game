--[[
	Infinity Islands - Task 17
	EarlyGamePacingConfig V1

	First 60-90 second retention calibration.

	The core loop itself stays unchanged. These are explicit early-route
	overrides layered on top of the normal IslandLevel systems.

	Why:
	- Island 1: 5 Green L1 * 12 XP = 60 XP -> exact Level 2 on clear.
	- Island 2: 6 Green L1 * 12 XP = 72 / 85 XP toward Level 3.
	- Island 3 is IslandLevel 2. First Green L2 = 13 XP.
	  72 + 13 = 85 -> Level 3 on the first kill of Island 3.

	This produces:
	first kill -> visible XP
	Island 1 clear -> first level-up
	Island 2 -> short "I am stronger" confirmation
	Island 3 first kill -> second level-up
]]

local Config = {}

Config.Version = "EarlyGamePacingV1"
Config.Policy = "FirstThreeIslandsFastProgress"

Config.CalibrationWindowSeconds = 90

Config.IslandOverrides = table.freeze({
	[1] = table.freeze({
		TargetCount = 5,
		MaximumAlive = 3,
		SpawnStaggerSeconds = 0.40,
		ExpectedVariant = "Green",
		ExpectedMobLevel = 1,
		ExpectedTotalXP = 60,
		ExpectedOutcome = "PlayerLevel2OnClear",
	}),
	[2] = table.freeze({
		TargetCount = 6,
		MaximumAlive = 4,
		SpawnStaggerSeconds = 0.30,
		ExpectedVariant = "Green",
		ExpectedMobLevel = 1,
		ExpectedTotalXP = 72,
		ExpectedOutcome = "PlayerLevel2With72Of85XP",
	}),
	[3] = table.freeze({
		MaximumAlive = 5,
		SpawnStaggerSeconds = 0.25,
		ExpectedVariant = "Green",
		ExpectedMobLevel = 2,
		ExpectedFirstKillXP = 13,
		ExpectedOutcome = "PlayerLevel3OnFirstKill",
	}),
})

Config.TelemetryTargets = table.freeze({
	FirstXPSeconds = 15,
	FirstLevelUpSeconds = 40,
	Island2EntrySeconds = 50,
	Island3EntrySeconds = 90,
})

function Config.GetOverride(globalIslandIndex)
	local index =
		math.floor(
			tonumber(globalIslandIndex) or 0
		)

	return Config.IslandOverrides[index]
end

function Config.GetTargetCount(
	globalIslandIndex,
	defaultCount
)
	local override =
		Config.GetOverride(
			globalIslandIndex
		)

	if override
		and override.TargetCount
	then
		return math.max(
			1,
			math.floor(
				override.TargetCount
			)
		)
	end

	return math.max(
		1,
		math.floor(
			tonumber(defaultCount) or 1
		)
	)
end

function Config.GetMaximumAlive(
	globalIslandIndex,
	defaultMaximumAlive,
	targetCount
)
	local override =
		Config.GetOverride(
			globalIslandIndex
		)

	local maximum =
		override
			and override.MaximumAlive
			or defaultMaximumAlive

	maximum =
		math.max(
			1,
			math.floor(
				tonumber(maximum) or 1
			)
		)

	return math.min(
		maximum,
		math.max(
			1,
			math.floor(
				tonumber(targetCount) or 1
			)
		)
	)
end

function Config.GetSpawnStaggerSeconds(
	globalIslandIndex,
	defaultSeconds
)
	local override =
		Config.GetOverride(
			globalIslandIndex
		)

	return math.max(
		0.05,
		tonumber(
			override
				and override.SpawnStaggerSeconds
				or defaultSeconds
		) or 0.25
	)
end

function Config.Validate()
	assert(
		Config.GetTargetCount(1, 3) == 5,
		"Island 1 precisa de 5 mobs"
	)

	assert(
		Config.GetTargetCount(2, 3) == 6,
		"Island 2 precisa de 6 mobs"
	)

	assert(
		Config.GetTargetCount(3, 3) == 3,
		"Island 3 nao deve sobrescrever o TargetCount normal"
	)

	assert(
		Config.GetMaximumAlive(
			1,
			7,
			5
		) == 3,
		"Island 1 MaxAlive precisa ser 3"
	)

	assert(
		math.abs(
			Config.GetSpawnStaggerSeconds(
				1,
				0.25
			) - 0.40
		) < 0.0001,
		"Island 1 stagger precisa ser 0.40"
	)

	return true
end

Config.Validate()

return table.freeze(Config)
