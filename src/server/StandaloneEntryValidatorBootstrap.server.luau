-- Infinity Islands - Task 20

local Validator = require(
	script.Parent.DungeonRuntime.StandaloneEntryValidator
)

local ok, result =
	pcall(
		Validator.Start
	)

if not ok then
	workspace:SetAttribute(
		"DungeonStandaloneEntryHealthy",
		false
	)
	workspace:SetAttribute(
		"DungeonStandaloneEntryIssues",
		tostring(result)
	)

	warn(
		"[StandaloneEntryValidatorBootstrap] "
			.. tostring(result)
	)
end
