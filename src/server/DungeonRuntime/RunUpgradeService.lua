-- Task 12: RunUpgradeService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("RunUpgradeService", "DungeonRunUpgradeServiceReady")
