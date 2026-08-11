-- Infinity Islands - Mob XP collectible bootstrap.

local ServerScriptService =
	game:GetService("ServerScriptService")

local service =
	require(
		ServerScriptService
			:WaitForChild("DungeonRuntime")
			:WaitForChild(
				"MobXPCollectibleService"
			)
	)

local callOk, startResult, startError =
	pcall(service.Start)

if not callOk then
	workspace:SetAttribute(
		"DungeonXPCollectibleServiceReady",
		false
	)
	workspace:SetAttribute(
		"DungeonXPCollectibleServiceError",
		tostring(startResult)
	)

	warn(
		"[MobXPCollectibleBootstrap] "
			.. tostring(startResult)
	)

	return
end

if startResult == false
	and startError ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonXPCollectibleServiceReady",
		false
	)
	workspace:SetAttribute(
		"DungeonXPCollectibleServiceError",
		tostring(
			startError
				or "StartRejected"
		)
	)

	warn(
		"[MobXPCollectibleBootstrap] "
			.. tostring(
				startError
					or "StartRejected"
			)
	)
end
