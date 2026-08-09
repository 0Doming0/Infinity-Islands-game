--[[
	Infinity Islands - Task 24
	EarlyCombatTTKConfig V1

	Goal:
	make the first enemies die quickly enough to communicate power, then let the
	first PlayerLevel increases produce a perceptible combat improvement.

	No mob HP formula is changed here.
	No PlayerLevel formula is changed here.

	Only the starter ClassicSword receives a minimum BaseDamage floor.
]]

local Config = {}

Config.Version = "EarlyCombatTTKV1"
Config.Policy = "FastFirstKillsVisibleLevelPower"

Config.StarterSwordBaseDamage = 24

Config.StarterSwordNames = table.freeze({
	ClassicSword = true,
})

Config.StarterSwordIds = table.freeze({
	ClassicSword = true,
})

-- Existing combo multipliers, mirrored only for validation/documentation.
Config.ExpectedCombo1Multiplier = 1.00
Config.ExpectedCombo2Multiplier = 1.12

-- Existing progression values, mirrored for deterministic acceptance checks.
Config.ExpectedGreenBaseHealth = 50
Config.ExpectedMobHealthPerLevel = 0.16
Config.ExpectedPlayerDamagePerLevel = 0.08

Config.TelemetryWindowSeconds = 90

-- TTK is measured from first accepted Player damage on a managed mob until
-- Humanoid death. Travel/search time is intentionally excluded.
Config.EarlyKillTargetSeconds = 3.0

local function playerDamageMultiplier(level)
	return 1
		+ Config.ExpectedPlayerDamagePerLevel
			* (math.max(1, level) - 1)
end

local function mobHealth(level)
	return Config.ExpectedGreenBaseHealth
		* (
			1
				+ Config.ExpectedMobHealthPerLevel
					* (math.max(1, level) - 1)
		)
end

local function twoHitDamage(playerLevel)
	local base =
		Config.StarterSwordBaseDamage
			* playerDamageMultiplier(
				playerLevel
			)

	return base
		* (
			Config.ExpectedCombo1Multiplier
				+ Config.ExpectedCombo2Multiplier
		)
end

function Config.Validate()
	local level1Health = mobHealth(1)
	local level2Health = mobHealth(2)

	local level1TwoHit =
		twoHitDamage(1)

	local level2TwoHit =
		twoHitDamage(2)

	local level3TwoHit =
		twoHitDamage(3)

	assert(
		level1TwoHit >= level1Health,
		"Player L1 precisa derrotar Green L1 em 2 hits"
	)

	assert(
		level2TwoHit < level2Health,
		"Primeiro Green L2 deve exigir o terceiro hit enquanto Player ainda e L2"
	)

	assert(
		level3TwoHit >= level2Health,
		"Depois do Level 3, Green L2 precisa voltar a 2 hits"
	)

	return true
end

Config.Validate()

return table.freeze(Config)
