-- Infinity Islands - Rare Chest bootstrap.

local ServerScriptService =
	game:GetService("ServerScriptService")

local service =
	require(
		ServerScriptService
			:WaitForChild("DungeonRuntime")
			:WaitForChild(
				"RareChestService"
			)
	)

local callOk,
	startResult,
	startError =
		pcall(
			service.Start
		)

if not callOk then
	workspace:SetAttribute(
		"DungeonRareChestServiceReady",
		false
	)

	workspace:SetAttribute(
		"DungeonRareChestServiceError",
		tostring(startResult)
	)

	warn(
		"[RareChestBootstrap] "
			.. tostring(startResult)
	)

	return
end

if startResult == false
	and startError ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonRareChestServiceReady",
		false
	)

	workspace:SetAttribute(
		"DungeonRareChestServiceError",
		tostring(
			startError
				or "StartRejected"
		)
	)
end
