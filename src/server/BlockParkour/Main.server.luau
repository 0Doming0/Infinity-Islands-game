-- Infinity Islands - Canonical Dungeon Bootstrap V2
-- Clean boot for standalone Combat MVP.

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

workspace:SetAttribute("GamePlaceType", "Dungeon")
workspace:SetAttribute("DungeonRuntimeManaged", true)
workspace:SetAttribute("DungeonCanonicalBootstrap", script:GetFullName())
workspace:SetAttribute("DungeonBootstrapVersion", "CleanDungeonBootV2")
workspace:SetAttribute("DungeonBootstrapReady", false)
workspace:SetAttribute("DungeonBootstrapError", nil)

local runtimeLoaded, runtimeOrError = pcall(function()
	return require(
		script.Parent.Parent.DungeonRuntime.DungeonRuntimeService
	)
end)

if not runtimeLoaded then
	local message =
		"Falha ao carregar DungeonRuntimeService: "
		.. tostring(runtimeOrError)

	workspace:SetAttribute("DungeonBootstrapError", message)
	workspace:SetAttribute("DungeonGenerationState", "Failed")

	warn("[DungeonBootstrap] " .. message)
	return
end

local callOk, startResult, startError =
	pcall(runtimeOrError.Start)

if not callOk then
	local message =
		"Excecao ao iniciar DungeonRuntimeService: "
		.. tostring(startResult)

	workspace:SetAttribute("DungeonBootstrapError", message)
	workspace:SetAttribute("DungeonGenerationState", "Failed")

	warn("[DungeonBootstrap] " .. message)
	return
end

if startResult == false
	and startError ~= "AlreadyStarted"
then
	local message =
		"DungeonRuntimeService.Start recusou: "
		.. tostring(startError or "UnknownStartFailure")

	workspace:SetAttribute("DungeonBootstrapError", message)
	workspace:SetAttribute("DungeonGenerationState", "Failed")

	warn("[DungeonBootstrap] " .. message)
	return
end

workspace:SetAttribute("DungeonBootstrapReady", true)
workspace:SetAttribute(
	"DungeonBootstrapStartedAt",
	workspace:GetServerTimeNow()
)

print("[DungeonBootstrap] Clean boot iniciado.")
