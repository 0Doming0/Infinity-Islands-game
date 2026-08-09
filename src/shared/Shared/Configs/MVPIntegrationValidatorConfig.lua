--[[
	Infinity Islands - Task 13
	MVPIntegrationValidatorConfig V1
]]

local Config = {}

Config.Version = "MVPIntegrationValidatorV1"

Config.InitialDelaySeconds = 4
Config.StudioIntervalSeconds = 4
Config.LiveIntervalSeconds = 20

Config.MaximumPublishedIssues = 12
Config.MaximumIssueTextLength = 180

Config.RequiredWorkspaceAttributes = table.freeze({
	"DungeonRouteArchitecture",
	"DungeonIslandProgressionReady",
	"DungeonIslandCombatReady",
	"DungeonPlayerLevelReady",
	"DungeonRouteProgressionAuthority",
})

Config.ExpectedRouteArchitecture = "LinearCombatRouteV1"
Config.ExpectedProgressionAuthority = "CombatRouteProgressionService"

Config.MaximumAlivePerIsland = 7

return table.freeze(Config)
