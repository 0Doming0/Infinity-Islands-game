-- Task 12: DungeonPacingService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("DungeonPacingService", "DungeonPacingServiceReady")
