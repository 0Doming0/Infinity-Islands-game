-- Infinity Islands - Task 17

local EarlyGamePacingTelemetryService = require(
	script.Parent.DungeonRuntime.EarlyGamePacingTelemetryService
)

local ok, result, detail =
	pcall(
		EarlyGamePacingTelemetryService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonEarlyGamePacingTelemetryReady",
		false
	)
	workspace:SetAttribute(
		"DungeonEarlyGamePacingTelemetryError",
		tostring(result)
	)

	warn(
		"[EarlyGamePacingTelemetryBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonEarlyGamePacingTelemetryError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonEarlyGamePacingTelemetryError",
		nil
	)
end
