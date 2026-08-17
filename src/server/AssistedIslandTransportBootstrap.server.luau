-- Transporte automatico legado desativado.
-- ManualIslandAdvance.server.luau e a unica autoridade de progressao e voo.
-- Nao iniciar DungeonRuntime.AssistedIslandTransportService evita conflito com
-- RecommendedLevel, auto-flight antigo, guidance e estados duplicados.

workspace:SetAttribute("DungeonAssistedTransportReady", false)
workspace:SetAttribute("DungeonAssistedTransportLegacyDisabled", true)
workspace:SetAttribute("DungeonAssistedTransportBootstrapError", nil)
workspace:SetAttribute("DungeonAssistedTransportAuthority", "ManualIslandAdvance")
