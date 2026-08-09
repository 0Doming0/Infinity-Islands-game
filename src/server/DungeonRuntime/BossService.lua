-- Task 12: BossService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("BossService", "DungeonBossServiceReady")
