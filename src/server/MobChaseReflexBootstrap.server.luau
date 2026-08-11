-- Infinity Islands - Mob Chase Reflex bootstrap.

local ServerScriptService =
	game:GetService("ServerScriptService")

local service =
	require(
		ServerScriptService
			:WaitForChild("DungeonRuntime")
			:WaitForChild(
				"MobChaseReflexService"
			)
	)

local callOk, startResult, startError =
	pcall(service.Start)

if not callOk then
	workspace:SetAttribute(
		"DungeonMobChaseReflexReady",
		false
	)
	workspace:SetAttribute(
		"DungeonMobChaseReflexError",
		tostring(startResult)
	)

	warn(
		"[MobChaseReflexBootstrap] "
			.. tostring(startResult)
	)

	return
end

if startResult == false
	and startError ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonMobChaseReflexReady",
		false
	)
	workspace:SetAttribute(
		"DungeonMobChaseReflexError",
		tostring(
			startError
				or "StartRejected"
		)
	)
end
