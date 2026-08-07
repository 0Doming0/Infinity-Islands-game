-- Inicializador canonico e primeiro guard do Place de Dungeon.
-- O carregamento automatico precisa ser desativado antes de qualquer require.
-- Assim, uma falha de modulo nunca cria o ciclo de nascer, cair e morrer.
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

workspace:SetAttribute("GamePlaceType", "Dungeon")
workspace:SetAttribute("DungeonRuntimeManaged", true)
workspace:SetAttribute("DungeonCanonicalBootstrap", script:GetFullName())
workspace:SetAttribute("DungeonBootstrapVersion", "RuntimeRecoveryV1")
workspace:SetAttribute("DungeonBootstrapReady", false)
workspace:SetAttribute("DungeonBootstrapError", nil)

local runtimeLoaded, runtimeOrError = pcall(function()
	return require(script.Parent.Parent.DungeonRuntime.DungeonRuntimeService)
end)

if not runtimeLoaded then
	local message = "Falha ao carregar DungeonRuntimeService: " .. tostring(runtimeOrError)
	workspace:SetAttribute("DungeonBootstrapError", message)
	warn("[DungeonBootstrap] " .. message)
else
	local started, startError = pcall(runtimeOrError.Start)
	if not started then
		local message = "Falha ao iniciar DungeonRuntimeService: " .. tostring(startError)
		workspace:SetAttribute("DungeonBootstrapError", message)
		warn("[DungeonBootstrap] " .. message)
	else
		workspace:SetAttribute("DungeonBootstrapReady", true)
		workspace:SetAttribute("DungeonBootstrapStartedAt", workspace:GetServerTimeNow())
	end
end
