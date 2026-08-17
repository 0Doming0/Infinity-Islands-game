-- Soft-aim antigo desativado.
-- MobileControls.client.luau agora e a unica autoridade de selecao de alvo,
-- contorno, auto-walk e hold de ataque no mobile.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("DungeonMobileSoftAimTarget")
if old then
	old:Destroy()
end

player:SetAttribute("DungeonMobileSoftAimActive", false)
player:SetAttribute("DungeonMobileSoftAimReady", false)
player:SetAttribute("DungeonMobileSoftAimPolicy", "OwnedByMobileControls")
player:SetAttribute("DungeonMobileSoftAimVersion", "DisabledByLinearMobileCombatV1")
