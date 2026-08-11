--[[
	Infinity Islands - Task 24
	EarlyCombatTTKConfig V2

	Goal:
	make the first enemies require several deliberate hits at PlayerLevel 1,
	then let PlayerLevel increases produce a perceptible combat improvement.

	No mob HP formula is changed here.
	No PlayerLevel formula is changed here.

	Only the starter ClassicSword receives the tuned BaseDamage value.
]]

local Config = {}

Config.Version = "EarlyCombatTTKV2"
Config.Policy = "DeliberateFirstKillsVisibleLevelPower"

Config.StarterSwordBaseDamage = 2.50 -- 2.50 is the original value

Config.StarterSwordNames = table.freeze({
	ClassicSword = true,
})

Config.StarterSwordIds = table.freeze({
	ClassicSword = true,
})

-- Existing combo multipliers, mirrored only for validation/documentation.
Config.ExpectedCombo1Multiplier = 1.00
Config.ExpectedCombo2Multiplier = 1.12
Config.ExpectedCombo3Multiplier = 1.55

-- Existing progression values, mirrored for deterministic acceptance checks.
Config.ExpectedGreenBaseHealth = 45
Config.ExpectedMobHealthPerLevel = 0.16
Config.ExpectedPlayerDamagePerLevel = 0.08

Config.TelemetryWindowSeconds = 90

-- TTK is measured from first accepted player damage on a managed mob until
-- Humanoid death. Travel/search time is intentionally excluded.
Config.EarlyKillTargetSeconds = 4.0

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

local function threeHitDamage(playerLevel)
	local base =
		Config.StarterSwordBaseDamage
			* playerDamageMultiplier(
				playerLevel
			)

	return base
		* (
			Config.ExpectedCombo1Multiplier
				+ Config.ExpectedCombo2Multiplier
				+ Config.ExpectedCombo3Multiplier
		)
end

return table.freeze(Config)