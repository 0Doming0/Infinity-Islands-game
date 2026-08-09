-- Infinity Islands - Task 28

local IslandClearRecoveryService = require(
	script.Parent.DungeonRuntime.IslandClearRecoveryService
)

local ok, result, detail =
	pcall(
		IslandClearRecoveryService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonIslandClearRecoveryReady",
		false
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryError",
		tostring(result)
	)

	warn(
		"[IslandClearRecoveryBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonIslandClearRecoveryReady",
		false
	)

	workspace:SetAttribute(
		"DungeonIslandClearRecoveryError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonIslandClearRecoveryError",
		nil
	)
end
