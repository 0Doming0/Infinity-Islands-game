--[[
	Task 12 compatibility ObjectiveService.

	No legacy Objective is created or progressed.
	GetSnapshot mirrors the new CombatRouteProgression Workspace contract so
	old result/analytics readers receive coherent information.
]]

local ObjectiveService = {}

local started = false

local function snapshot()
	return {
		Id =
			workspace:GetAttribute(
				"DungeonObjectiveId"
			),
		Type =
			workspace:GetAttribute(
				"DungeonObjectiveType"
			),
		Title =
			workspace:GetAttribute(
				"DungeonObjectiveTitle"
			),
		Description =
			workspace:GetAttribute(
				"DungeonObjectiveDescription"
			),
		Progress =
			workspace:GetAttribute(
				"DungeonObjectiveProgress"
			),
		Target =
			workspace:GetAttribute(
				"DungeonObjectiveTarget"
			),
		State =
			workspace:GetAttribute(
				"DungeonObjectiveState"
			),
		GlobalIslandIndex =
			workspace:GetAttribute(
				"DungeonCurrentObjectiveIsland"
			),
		Completed =
			workspace:GetAttribute(
				"DungeonObjectiveState"
			) == "Completed",
		LegacyDisabled = true,
	}
end

function ObjectiveService.Start(_options)
	started = true

	workspace:SetAttribute(
		"DungeonObjectiveServiceReady",
		false
	)
	workspace:SetAttribute(
		"DungeonLegacyObjectiveServiceDisabled",
		true
	)

	return true,
		"CompatibilityMirrorOnly"
end

function ObjectiveService.Stop()
	started = false

	workspace:SetAttribute(
		"DungeonObjectiveServiceReady",
		false
	)

	return true
end

function ObjectiveService.SetParticipantConnected(...)
	return true
end

function ObjectiveService.SetObjective(...)
	return false,
		"CombatRouteProgressionOwnsObjective"
end

function ObjectiveService.AddProgress(...)
	return false,
		"IslandCombatServiceOwnsProgress"
end

function ObjectiveService.GetSnapshot()
	return snapshot()
end

function ObjectiveService.IsStarted()
	return started
end

return ObjectiveService
