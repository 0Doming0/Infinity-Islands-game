-- Task 12: RewardIslandService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("RewardIslandService", "DungeonRewardIslandServiceReady")
