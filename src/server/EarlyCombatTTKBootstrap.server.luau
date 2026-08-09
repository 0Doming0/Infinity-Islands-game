-- Infinity Islands - Task 24

local EarlyCombatTTKService = require(
	script.Parent.DungeonRuntime.EarlyCombatTTKService
)

local ok, result, detail =
	pcall(
		EarlyCombatTTKService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonEarlyCombatTTKReady",
		false
	)

	workspace:SetAttribute(
		"DungeonEarlyCombatTTKError",
		tostring(result)
	)

	warn(
		"[EarlyCombatTTKBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonEarlyCombatTTKReady",
		false
	)

	workspace:SetAttribute(
		"DungeonEarlyCombatTTKError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonEarlyCombatTTKError",
		nil
	)
end
