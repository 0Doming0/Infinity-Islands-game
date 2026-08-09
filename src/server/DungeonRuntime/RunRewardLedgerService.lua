-- Task 12: RunRewardLedgerService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("RunRewardLedgerService", "DungeonRunRewardLedgerReady")
