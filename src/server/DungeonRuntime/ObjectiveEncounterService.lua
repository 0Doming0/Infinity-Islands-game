-- Task 12: ObjectiveEncounterService is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("ObjectiveEncounterService", "DungeonObjectiveEncounterReady")
