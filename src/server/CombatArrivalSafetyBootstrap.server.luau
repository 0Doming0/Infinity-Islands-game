-- Infinity Islands - Task 22

local CombatArrivalSafetyService = require(
	script.Parent.DungeonRuntime.CombatArrivalSafetyService
)

local ok, result, detail =
	pcall(
		CombatArrivalSafetyService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonArrivalSafetyReady",
		false
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyError",
		tostring(result)
	)

	warn(
		"[CombatArrivalSafetyBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonArrivalSafetyReady",
		false
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonArrivalSafetyError",
		nil
	)
end
