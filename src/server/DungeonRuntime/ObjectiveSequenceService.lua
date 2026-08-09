--[[
	Infinity Islands - Task 09

	Compatibility facade.

	The old ObjectiveSequence / DungeonProgressionService no longer owns route
	progression. The linear MVP is now controlled by CombatRouteProgressionService.

	This module intentionally preserves the public API used by the existing
	DungeonRuntime, DungeonPacingService, RewardIslandService and analytics glue
	while preventing the old 12-objective/reward/boss flow from starting.
]]

local CombatRouteProgressionService = require(
	script.Parent.CombatRouteProgressionService
)

local ObjectiveSequenceService = {}

function ObjectiveSequenceService.Start(options)
	return CombatRouteProgressionService.Start(
		options
	)
end

function ObjectiveSequenceService.Stop()
	return CombatRouteProgressionService.Stop()
end

function ObjectiveSequenceService
	.HandleIslandEntered(
		player,
		context
	)
	return CombatRouteProgressionService
		.HandleIslandEntered(
			player,
			context
		)
end

function ObjectiveSequenceService
	.HandleObjectiveCompleted(snapshot)
	-- Legacy ObjectiveService completions are presentation-only during
	-- migration. IslandCombatService is the progression authority.
	return snapshot
end

function ObjectiveSequenceService
	.CommitRoundReward(
		roundIndex,
		metadata
	)
	workspace:SetAttribute(
		"DungeonLegacyRoundRewardCommitIgnored",
		true
	)
	workspace:SetAttribute(
		"DungeonLegacyRoundRewardCommitIgnoredRound",
		tonumber(roundIndex)
	)
	workspace:SetAttribute(
		"DungeonLegacyRoundRewardCommitIgnoredAt",
		workspace:GetServerTimeNow()
	)

	return true,
		"LegacyRewardBypassedLinearRoute"
end

function ObjectiveSequenceService
	.EscalateWaypoint()
	return CombatRouteProgressionService
		.EscalateWaypoint()
end

function ObjectiveSequenceService
	.RecoverCurrentObjective()
	return CombatRouteProgressionService
		.RecoverCurrentIsland()
end

function ObjectiveSequenceService.Report(
	eventName,
	payload
)
	workspace:SetAttribute(
		"DungeonLegacyObjectiveSignalIgnored",
		tostring(eventName or "Unknown")
	)

	return false,
		"IslandCombatServiceOwnsProgress"
end

function ObjectiveSequenceService
	.GetSnapshot()
	return CombatRouteProgressionService
		.GetSnapshot()
end

function ObjectiveSequenceService
	.GetCurrentDefinition()
	return CombatRouteProgressionService
		.GetCurrentDefinition()
end

function ObjectiveSequenceService
	.GetCurrentContext()
	return CombatRouteProgressionService
		.GetCurrentContext()
end

return ObjectiveSequenceService
