-- A economia da Dungeon usa coletaveis fisicos no mundo. O feedback discreto de
-- coleta e commit pertence ao DungeonUnifiedHUD; nenhuma moeda deve voar pelo GUI.
local Players = game:GetService("Players")
Players.LocalPlayer:SetAttribute("DungeonCoinFlightGuiDisabled", true)
