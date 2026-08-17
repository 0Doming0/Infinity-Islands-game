-- Camera especial de boss desativada no MVP linear.
-- DungeonCameraController.client.luau e a unica autoridade de camera mobile.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

workspace:SetAttribute("DungeonMobileCameraForwardOverride", nil)
workspace:SetAttribute("DungeonMobileCameraFocusWorldOverride", nil)
player:SetAttribute("DungeonBossPortraitCameraActive", false)
player:SetAttribute("DungeonBossPortraitCameraPolicy", "OwnedByDungeonCameraController")
player:SetAttribute("DungeonBossPortraitCameraVersion", "DisabledByLinearMobileCameraV1")
