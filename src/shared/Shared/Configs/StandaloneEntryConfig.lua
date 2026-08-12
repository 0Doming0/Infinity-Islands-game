--[[
	Infinity Islands - Task 20
	StandaloneEntryConfig V1

	Stability rules for direct-to-Dungeon entry.
]]

local Config = {}

Config.Version = "StandaloneEntryV1"

-- A server run always begins from the unnumbered Initial Island.
-- Value 1 is the internal route index, not the user-facing island number.
Config.ServerStartIsland = 1

-- Players joining after the server has progressed join the CURRENT checkpoint,
-- not a recreated personal Initial Island.
Config.LateJoinPolicy = "CurrentServerCheckpoint"

-- Do not position/load the same player twice for one join/character generation.
Config.PositionRequestCooldownSeconds = 0.35

-- If the route is already completed, late joiners remain in the completed server
-- and are not teleported elsewhere.
Config.CompletedRunLateJoinPolicy = "StayInCompletedDungeon"

return table.freeze(Config)
