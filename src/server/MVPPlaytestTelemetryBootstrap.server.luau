-- Infinity Islands - Task 29

local MVPPlaytestTelemetryService = require(
	script.Parent.DungeonRuntime.MVPPlaytestTelemetryService
)

local ok, result, detail =
	pcall(
		MVPPlaytestTelemetryService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonPlaytestTelemetryReady",
		false
	)

	workspace:SetAttribute(
		"DungeonPlaytestTelemetryError",
		tostring(result)
	)

	warn(
		"[MVPPlaytestTelemetryBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonPlaytestTelemetryReady",
		false
	)

	workspace:SetAttribute(
		"DungeonPlaytestTelemetryError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonPlaytestTelemetryError",
		nil
	)
end
