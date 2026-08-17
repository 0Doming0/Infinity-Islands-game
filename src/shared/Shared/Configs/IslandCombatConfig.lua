--[[
	Infinity Islands - Task 30
	IslandCombatConfig V4 - Shared Cooperative Arenas

	Cleared means the shared kill quota was completed. All players present in
	the arena cooperate on one limited population; a cleared island becomes safe
	for the group. RecommendedLevel is still not a hard gate.
]]

local IslandCombatConfig = {}

IslandCombatConfig.Version = "IslandCombatV4SharedCoop"

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
	"SharedCoopQuotaStopsIslandCombat"

IslandCombatConfig.ContinuousRespawn = false

return table.freeze(IslandCombatConfig)
