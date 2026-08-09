-- Infinity Islands - Task 03
-- Starts the additive active-world window only in the Dungeon place.

local ActiveWorldWindowService = require(
	script.Parent.DungeonRuntime.ActiveWorldWindowService
)

local ok, result, detail = pcall(
	ActiveWorldWindowService.Start
)

if not ok then
	workspace:SetAttribute("DungeonActiveRouteWindowReady", false)
	workspace:SetAttribute(
		"DungeonActiveRouteWindowBootstrapError",
		tostring(result)
	)
	warn(
		"[ActiveWorldWindowBootstrap] Start falhou: "
			.. tostring(result)
	)
elseif result == false and detail ~= "AlreadyStarted" then
	workspace:SetAttribute(
		"DungeonActiveRouteWindowBootstrapError",
		tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonActiveRouteWindowBootstrapError",
		nil
	)
end
