--[[
	Infinity Islands - Task 30
	IslandAdvanceFeedbackConfig V2

	The island can still contain enemies after its progression quota is complete,
	so the UI must not claim that the arena is physically empty.
]]

local Config = {}

Config.Version = "IslandAdvanceFeedbackV2ContinuousCombat"

Config.ClearTitle = "ILHA CONCLUÍDA"
Config.RouteCompleteTitle = "ROTA CONCLUÍDA"

Config.AdvanceDescriptionFormat =
	"PRÓXIMA ILHA LIBERADA • ILHA %d"

Config.RouteCompleteDescription =
	"ROTA CONCLUÍDA • CONTINUE LUTANDO PARA EVOLUIR"

Config.MarkerPulseMinimumScale = 1.00
Config.MarkerPulseMaximumScale = 1.22
Config.MarkerPulseCyclesPerSecond = 1.8

Config.ClearPulseScale = 1.16
Config.ClearPulseUpSeconds = 0.11
Config.ClearPulseDownSeconds = 0.22

return table.freeze(Config)
