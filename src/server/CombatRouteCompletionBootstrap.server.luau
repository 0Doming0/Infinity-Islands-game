-- Infinity Islands - Task 12

local CombatRouteCompletionService = require(
	script.Parent.DungeonRuntime.CombatRouteCompletionService
)

local ok, result, detail =
	pcall(
		CombatRouteCompletionService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonCombatRouteCompletionReady",
		false
	)
	workspace:SetAttribute(
		"DungeonCombatRouteCompletionError",
		tostring(result)
	)
	warn(
		"[CombatRouteCompletionBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonCombatRouteCompletionError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonCombatRouteCompletionError",
		nil
	)
end
