-- Compatibilidade: o HUD do chefe foi incorporado ao DungeonUnifiedHUD.
-- Este arquivo permanece para substituir instalações anteriores sem criar uma segunda interface.
local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local legacy = playerGui:FindFirstChild("DungeonBossHUD")
if legacy and legacy:IsA("ScreenGui") then
	legacy.Enabled = false
end
