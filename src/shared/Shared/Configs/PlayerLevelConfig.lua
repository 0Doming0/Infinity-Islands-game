--[[
	Infinity Islands - PlayerLevelConfig

	Player progression is persistent for the MVP.

	Early retention curve:
	- Level 1 starts at 0 XP.
	- Level 1 -> 2 requires 54 XP so the first level-up lands exactly after
	  the Initial Island (18 XP) + Numbered Island 1 (36 XP).
	- From Level 2 onward the original curve is preserved:
	  60 + 25 * (level - 1), therefore L2->3 = 85, L3->4 = 110, etc.
	- +8% outgoing combat damage per level after Level 1.
	- +4% maximum health per level after Level 1.

	MobXPConfig and IslandProgressionConfig own mob and cycle XP rewards.
]]

local PlayerLevelConfig = {}

PlayerLevelConfig.Version = "PlayerLevelV3_FirstLevel54"
PlayerLevelConfig.PersistencePolicy = "PersistentProfileV2"

PlayerLevelConfig.StartingLevel = 1
PlayerLevelConfig.MaximumLevel = 100

PlayerLevelConfig.FirstLevelXPToNextLevel = 54
PlayerLevelConfig.BaseXPToNextLevel = 60
PlayerLevelConfig.XPIncreasePerLevel = 25

PlayerLevelConfig.DamagePerLevel = 0.08
PlayerLevelConfig.HealthPerLevel = 0.04

PlayerLevelConfig.MaximumSingleXPGrant = 100000

local function cleanLevel(value)
	return math.clamp(
		math.floor(
			tonumber(value)
				or PlayerLevelConfig.StartingLevel
		),
		PlayerLevelConfig.StartingLevel,
		PlayerLevelConfig.MaximumLevel
	)
end

function PlayerLevelConfig.GetXPToNextLevel(level)
	level = cleanLevel(level)

	if level >= PlayerLevelConfig.MaximumLevel then
		return 0
	end

	if level == PlayerLevelConfig.StartingLevel then
		return PlayerLevelConfig.FirstLevelXPToNextLevel
	end

	return math.max(
		1,
		math.floor(
			PlayerLevelConfig.BaseXPToNextLevel
				+ PlayerLevelConfig.XPIncreasePerLevel
					* (level - 1)
		)
	)
end

function PlayerLevelConfig.GetDamageMultiplier(level)
	level = cleanLevel(level)

	return 1
		+ PlayerLevelConfig.DamagePerLevel
			* (level - 1)
end

function PlayerLevelConfig.GetHealthMultiplier(level)
	level = cleanLevel(level)

	return 1
		+ PlayerLevelConfig.HealthPerLevel
			* (level - 1)
end

function PlayerLevelConfig.GetProgressRatio(
	level,
	currentXP
)
	local needed =
		PlayerLevelConfig.GetXPToNextLevel(level)

	if needed <= 0 then
		return 1
	end

	return math.clamp(
		(tonumber(currentXP) or 0) / needed,
		0,
		1
	)
end

function PlayerLevelConfig.Validate()
	assert(
		PlayerLevelConfig.GetXPToNextLevel(1) == 54,
		"Level 1 precisa pedir 54 XP para coincidir com o primeiro pacing"
	)

	assert(
		PlayerLevelConfig.GetXPToNextLevel(2) == 85,
		"Level 2 precisa preservar os 85 XP originais"
	)

	assert(
		PlayerLevelConfig.GetXPToNextLevel(3) == 110,
		"Level 3 precisa preservar os 110 XP originais"
	)

	assert(
		math.abs(
			PlayerLevelConfig.GetDamageMultiplier(10)
				- 1.72
		) < 0.0001,
		"Level 10 precisa ter 1.72x damage"
	)

	assert(
		math.abs(
			PlayerLevelConfig.GetHealthMultiplier(10)
				- 1.36
		) < 0.0001,
		"Level 10 precisa ter 1.36x health"
	)

	return true
end

PlayerLevelConfig.Validate()

return table.freeze(PlayerLevelConfig)
