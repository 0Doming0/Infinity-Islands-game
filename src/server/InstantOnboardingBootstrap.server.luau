-- Infinity Islands - Task 16

local InstantOnboardingService = require(
	script.Parent.DungeonRuntime.InstantOnboardingService
)

local ok, result, detail =
	pcall(
		InstantOnboardingService.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonInstantOnboardingReady",
		false
	)
	workspace:SetAttribute(
		"DungeonInstantOnboardingError",
		tostring(result)
	)

	warn(
		"[InstantOnboardingBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonInstantOnboardingError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonInstantOnboardingError",
		nil
	)
end
