-- Infinity Islands - Task 07
-- Dungeon-only PlayerLevel bootstrap.

local PlayerLevelService = require(
	script.Parent.DungeonRuntime.PlayerLevelService
)

local ok, result, detail = pcall(
	PlayerLevelService.Start,
	{}
)

if not ok then
	workspace:SetAttribute(
		"DungeonPlayerLevelReady",
		false
	)
	workspace:SetAttribute(
		"DungeonPlayerLevelBootstrapError",
		tostring(result)
	)
	warn(
		"[PlayerLevelBootstrap] Start falhou: "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonPlayerLevelBootstrapError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonPlayerLevelBootstrapError",
		nil
	)
end
