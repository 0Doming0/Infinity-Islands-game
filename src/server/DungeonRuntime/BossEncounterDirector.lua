-- Task 12: BossEncounterDirector is disabled in the simplified Combat MVP.
local Factory = require(script.Parent.LegacyDisabledServiceFactory)
return Factory.Create("BossEncounterDirector", "DungeonBossDirectorReady")
