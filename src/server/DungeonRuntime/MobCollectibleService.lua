-- Task 12: MobCollectibleService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("MobCollectibleService", "DungeonMobCollectibleServiceReady")
