-- Guidance de camera da proxima ilha desativada no MVP linear.
-- DungeonCameraController cuida da camera normal e
-- AssistedIslandTransportController cuida somente da camera durante o voo.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

workspace:SetAttribute("DungeonMobileCameraForwardOverride", nil)
workspace:SetAttribute("DungeonMobileCameraFocusWorldOverride", nil)
player:SetAttribute("DungeonRouteArrowVisible", false)
player:SetAttribute("DungeonNextIslandCameraGuidanceActive", false)
player:SetAttribute("DungeonNextIslandCameraGuidancePolicy", "OwnedByLinearTransport")
player:SetAttribute("DungeonNextIslandCameraGuidanceVersion", "DisabledByLinearTransportClientV1")
