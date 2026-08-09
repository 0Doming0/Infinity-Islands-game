--[[
	Infinity Islands - Task 09
	CombatRouteProgressionConfig V1
]]

local CombatRouteProgressionConfig = {}

CombatRouteProgressionConfig.Version = "CombatRouteProgressionV1"

CombatRouteProgressionConfig.DefaultTotalIslandCount = 24
CombatRouteProgressionConfig.FutureLookahead = 3
CombatRouteProgressionConfig.ReconcileSeconds = 0.20

CombatRouteProgressionConfig.ObjectiveId = "ClearIsland"
CombatRouteProgressionConfig.ObjectiveTitle = "DERROTE OS INIMIGOS"
CombatRouteProgressionConfig.ObjectiveDescription =
	"Elimine todos os inimigos para liberar a próxima ilha."

CombatRouteProgressionConfig.GateText =
	"DERROTE OS INIMIGOS"

return table.freeze(CombatRouteProgressionConfig)
