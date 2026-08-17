-- Compatibilidade desativada.
-- A conclusao do objetivo e a liberacao de AVANCAR agora pertencem somente a
-- ManualIslandAdvance.server.luau. Manter este arquivo como no-op evita que uma
-- copia antiga no Studio continue publicando uma segunda verdade de progressao.

workspace:SetAttribute("DungeonLinearObjectiveBridgeReady", false)
workspace:SetAttribute("DungeonLinearObjectiveBridgeVersion", "DisabledByLinearIslandProgressionV1")
workspace:SetAttribute("DungeonLinearProgressionPolicy", "ClearSituationThenAdvance")
workspace:SetAttribute("DungeonRecommendedLevelIsHardGate", false)
workspace:SetAttribute("DungeonRecommendedLevelWarningActive", false)
