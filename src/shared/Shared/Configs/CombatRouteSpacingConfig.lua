--[[
	Infinity Islands - Task 27
	CombatRouteSpacingConfig V1

	Compact spacing for the standalone linear Combat Route.

	The old frontier generator used 14-17 cells between logical lane centers.
	That spacing was useful for a branching world, but creates unnecessary
	traversal time in a simple linear MVP.

	The linear route can calculate center spacing from the REAL sizes of the two
	connected islands:

	source half extent
	+ connector horizontal cells
	+ target half extent

	Vertical rise remains a safe 3 cells (15 studs with the current 5-stud grid).
]]

local Config = {}

Config.Version = "CombatRouteSpacingV1"
Config.Policy = "SizeAwareCompactLinearRoute"

-- Combat Islands 1-6 should move very quickly.
Config.EarlyRouteThroughIsland = 6
Config.EarlyConnectorHorizontalCells = 4

-- After the initial retention window, preserve a little more sky separation.
Config.StandardConnectorHorizontalCells = 5

-- Existing IslandGraphPlanner accepts 3-4 vertical cells.
Config.VerticalRiseCells = 3

-- Diagnostic target only. This is not a gameplay gate.
Config.AssumedWalkSpeedStudsPerSecond = 16
Config.TargetMaximumConnectorSeconds = 2.5

function Config.GetConnectorHorizontalCells(targetGlobalIslandIndex)
	local index =
		math.max(
			1,
			math.floor(
				tonumber(targetGlobalIslandIndex) or 1
			)
		)

	if index <= Config.EarlyRouteThroughIsland then
		return Config.EarlyConnectorHorizontalCells
	end

	return Config.StandardConnectorHorizontalCells
end

function Config.EstimatedTraversalSeconds(
	horizontalCells,
	gridSize
)
	local studs =
		math.max(
			0,
			tonumber(horizontalCells) or 0
		)
			* math.max(
				0.01,
				tonumber(gridSize) or 5
			)

	return studs
		/ Config.AssumedWalkSpeedStudsPerSecond
end

return table.freeze(Config)
