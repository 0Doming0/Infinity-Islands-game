--[[
	Infinity Islands - Task 19
	Standalone route completion.

	No lobby return.
]]

local Config = {}

Config.Version =
	"StandaloneCombatRouteCompletionV1"

Config.Policy =
	"VictoryStayInDungeon"

Config.LobbyReturnEnabled = false
Config.FreezePlayersOnVictory = false
Config.AutoRestartEnabled = false

return table.freeze(Config)
