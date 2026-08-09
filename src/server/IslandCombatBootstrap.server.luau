-- Infinity Islands - Task 04
-- Starts the new arena state machine.
-- It is intentionally independent from the old ObjectiveSequence during migration.

local IslandCombatService = require(
	script.Parent.DungeonRuntime.IslandCombatService
)

local ok, result, detail = pcall(
	IslandCombatService.Start,
	{}
)

if not ok then
	workspace:SetAttribute("DungeonIslandCombatReady", false)
	workspace:SetAttribute(
		"DungeonIslandCombatBootstrapError",
		tostring(result)
	)
	warn(
		"[IslandCombatBootstrap] Start falhou: "
			.. tostring(result)
	)
elseif result == false and detail ~= "AlreadyStarted" then
	workspace:SetAttribute(
		"DungeonIslandCombatBootstrapError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonIslandCombatBootstrapError",
		nil
	)
end
