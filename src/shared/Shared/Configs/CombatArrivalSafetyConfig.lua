--[[
	Infinity Islands - Task 22
	CombatArrivalSafetyConfig V1

	Short server-side protection against unfair damage during:
	- first character spawn;
	- respawn;
	- first forward entry into a new Combat Island.

	This is NOT a tutorial and NOT a permanent safe zone.
]]

local Config = {}

Config.Version = "CombatArrivalSafetyV1"
Config.Policy = "ShortArrivalProtection"

Config.InitialSpawnSeconds = 3.0
Config.RespawnSeconds = 2.0
Config.NewIslandSeconds = 1.0

Config.MinimumProtectionSeconds = 0.25
Config.MaximumProtectionSeconds = 4.0

-- Prevents crossing backwards/forwards repeatedly to farm immunity.
Config.NewIslandProtectionOnlyWhenProgressingForward = true

-- 90-second retention diagnostic window.
Config.TelemetryWindowSeconds = 90

Config.ForceFieldName = "_DungeonArrivalSafety"

-- Invisible: gameplay protection only.
Config.ForceFieldVisible = false

return table.freeze(Config)
