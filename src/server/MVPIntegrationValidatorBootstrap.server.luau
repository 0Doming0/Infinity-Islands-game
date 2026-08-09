-- Infinity Islands - Task 13

local MVPIntegrationValidator = require(
	script.Parent.DungeonRuntime.MVPIntegrationValidator
)

local ok,
	result,
	detail =
		pcall(
			MVPIntegrationValidator.Start
		)

if not ok then
	workspace:SetAttribute(
		"DungeonMVPIntegrationValidatorRunning",
		false
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationValidatorError",
		tostring(result)
	)

	warn(
		"[MVPIntegrationValidatorBootstrap] "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonMVPIntegrationValidatorError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonMVPIntegrationValidatorError",
		nil
	)
end
