--[[
	Infinity Islands - Task 30
	IslandCombatConfig V2 - Continuous Combat

	Cleared now means the kill quota was completed.
	It no longer means the island has no living enemies.

	CombatState remains Active while a player occupies the island, allowing
	MonsterSpawner to keep refilling open MaxAlive slots after progression.
]]

local IslandCombatConfig = {}

IslandCombatConfig.Version = "IslandCombatV2Continuous"

IslandCombatConfig.States = table.freeze({
	Dormant = "Dormant",
	Ready = "Ready",
	Active = "Active",
	Cleared = "Cleared", -- compatibility only
})

IslandCombatConfig.ReconcileSeconds = 0.20
IslandCombatConfig.RequireTargetCountBeforeClear = true
IslandCombatConfig.ReadyLookahead = 1

IslandCombatConfig.ProgressionPolicy =
	"KillQuotaDoesNotStopCombat"

IslandCombatConfig.ContinuousRespawn = true

return table.freeze(IslandCombatConfig)
