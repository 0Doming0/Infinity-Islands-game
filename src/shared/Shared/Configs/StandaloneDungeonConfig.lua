--[[
	Infinity Islands - Task 19
	StandaloneDungeonConfig V2

	The Dungeon is now the experience entry point for the MVP.

	No lobby session is required.
	No TeleportData is required.
	No first-match guide is required.

	A server owns one shared Combat Route.
]]

local Config = {}

Config.Version = "StandaloneDungeonInitialIslandV2"
Config.EntryPolicy = "DirectToInitialIsland"
Config.LobbyEnabled = false
Config.TeleportDataRequired = false
Config.GuideEnabled = false

Config.RouteIslandCount = 24
Config.MaximumPlayers = 4

Config.RespawnDelaySeconds = 1.5
Config.SpawnProtectionSeconds = 4

Config.DefaultCurrentIsland = 1

return table.freeze(Config)
