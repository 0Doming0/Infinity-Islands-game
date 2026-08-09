--[[
	Task 19 compatibility config.

	The old InstantOnboarding naming remains only because its bootstrap already
	exists in src/server. There is no tutorial/guide presentation anymore.
]]

local Config = {}

Config.Version = "DirectIslandStartV1"
Config.Policy = "DirectIslandStart"
Config.TargetTimeToControlSeconds = 2.5

return table.freeze(Config)
