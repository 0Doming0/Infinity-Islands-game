--[[
	Task 12 compatibility path.

	The old 12-objective DungeonProgressionService implementation is gone.
	CombatRouteProgressionService owns the route.
]]

local CombatRouteProgressionService = require(
	script.Parent.CombatRouteProgressionService
)

local DungeonProgressionService = {}

function DungeonProgressionService.Start(options)
	return CombatRouteProgressionService.Start(
		options
	)
end

function DungeonProgressionService.Stop()
	return CombatRouteProgressionService.Stop()
end

function DungeonProgressionService.HandleIslandEntered(
	player,
	context
)
	return CombatRouteProgressionService.HandleIslandEntered(
		player,
		context
	)
end

function DungeonProgressionService.GetSnapshot()
	return CombatRouteProgressionService.GetSnapshot()
end

function DungeonProgressionService.GetCurrentDefinition()
	return CombatRouteProgressionService.GetCurrentDefinition()
end

function DungeonProgressionService.GetCurrentContext()
	return CombatRouteProgressionService.GetCurrentContext()
end

function DungeonProgressionService.EscalateWaypoint()
	return CombatRouteProgressionService.EscalateWaypoint()
end

function DungeonProgressionService.RecoverCurrentObjective()
	return CombatRouteProgressionService.RecoverCurrentIsland()
end

function DungeonProgressionService.CommitRoundReward(...)
	return true,
		"LegacyRewardBypassedLinearRoute"
end

function DungeonProgressionService.ReportEnemyDefeated(...)
	return false,
		"IslandCombatServiceOwnsProgress"
end

function DungeonProgressionService.ReportNestDestroyed(...)
	return false,
		"LegacyObjectiveDisabled"
end

function DungeonProgressionService.ReportBeaconHoldSeconds(...)
	return false,
		"LegacyObjectiveDisabled"
end

return DungeonProgressionService
