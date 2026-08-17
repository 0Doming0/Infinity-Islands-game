--[[
	Infinity Islands - Task 09
	CombatRouteProgressionConfig V1
]]

local CombatRouteProgressionConfig = {}

CombatRouteProgressionConfig.Version = "CombatRouteProgressionV2ClearPresentation"

CombatRouteProgressionConfig.DefaultTotalIslandCount = 24
CombatRouteProgressionConfig.FutureLookahead = 3
CombatRouteProgressionConfig.ReconcileSeconds = 0.20

CombatRouteProgressionConfig.ObjectiveId = "ClearIsland"
CombatRouteProgressionConfig.ObjectiveTitle = "LIMPE A ILHA"
CombatRouteProgressionConfig.ObjectiveDescription =
	"DERROTE TODOS OS INIMIGOS"

CombatRouteProgressionConfig.GateText = "LIMPE A ILHA"

return table.freeze(CombatRouteProgressionConfig)
