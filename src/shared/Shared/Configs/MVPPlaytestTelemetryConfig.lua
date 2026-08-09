--[[
	Infinity Islands - Task 29
	MVPPlaytestTelemetryConfig V1

	Observation only.

	This config does not change:
	- combat;
	- movement;
	- XP;
	- spawning;
	- health;
	- HUD.

	It defines the playtest milestones for the first 10 minutes.
]]

local Config = {}

Config.Version = "MVPPlaytestTelemetryV1"
Config.Policy = "ObserveFiveToTenMinuteRun"

Config.FirstXPHealthySeconds = 15
Config.FirstLevelUpHealthySeconds = 40
Config.Island2HealthySeconds = 50
Config.Island3HealthySeconds = 90

Config.FirstKillTTKHealthySeconds = 3.0

Config.StallWarningSeconds = 45
Config.SevereStallSeconds = 75

Config.FiveMinuteSeconds = 300
Config.TenMinuteSeconds = 600

Config.UpdateIntervalSeconds = 2

Config.EarlyDeathWarningCount = 2

return table.freeze(Config)
