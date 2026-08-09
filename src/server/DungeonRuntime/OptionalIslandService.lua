-- Task 12: OptionalIslandService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("OptionalIslandService", "DungeonOptionalIslandServiceReady")
