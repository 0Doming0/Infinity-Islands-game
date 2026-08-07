-- Compatibilidade: a politica de propriedade das interfaces agora vive no
-- DungeonUIRouter. Este guardiao permanece com o mesmo nome para substituir a
-- versao antiga sem manter duas listas divergentes de scripts bloqueados.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local playerGui = player:WaitForChild("PlayerGui")
local uiFolder = playerScripts:WaitForChild("UI")
local DungeonUIRouter = require(uiFolder:WaitForChild("DungeonUIRouter"))

local disabledCount, suppressedCount = DungeonUIRouter.Bind(playerScripts, playerGui)

player:SetAttribute("DungeonClientLegacyGuardReady", true)
player:SetAttribute("DungeonUIRouterReady", true)
player:SetAttribute("DungeonUIRouterVersion", DungeonUIRouter.Version)
player:SetAttribute("DungeonUIRouterPolicy", DungeonUIRouter.Policy)
player:SetAttribute("DungeonClientLegacyScriptsDisabled", disabledCount)
player:SetAttribute("DungeonClientLegacyGuisSuppressed", suppressedCount)
