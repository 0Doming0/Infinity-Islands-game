-- Compatibilidade: a camera mobile da ilha inicial deixou de ser um sistema
-- separado. DungeonCameraController agora controla TODA a rota desde o spawn.
-- Mantemos este LocalScript apenas para nao quebrar referencias/atributos de
-- diagnostico existentes enquanto o projeto e simplificado.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local VERSION = "InitialIslandMobileSmartCameraRetiredV3"

player:SetAttribute("DungeonInitialMobileSmartCameraReady", true)
player:SetAttribute("DungeonInitialMobileSmartCameraActive", false)
player:SetAttribute("DungeonInitialMobileSmartCameraVersion", VERSION)
player:SetAttribute("DungeonInitialMobileSmartCameraAuthority", "DungeonCameraController")
