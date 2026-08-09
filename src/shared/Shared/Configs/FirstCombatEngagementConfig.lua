--[[
	Infinity Islands - Task 26
	FirstCombatEngagementConfig V1

	Combat Island mobs are already hostile through the existing
	IslandCombatManaged / ForceHostile path.

	This config only makes the first enemy of Islands 1-3 spawn at a readable
	distance from the island Entry/SafeSpawn.
]]

local Config = {}

Config.Version = "FirstCombatEngagementV1"
Config.Policy = "ReadableFirstEnemySpawn"

Config.AppliesThroughIsland = 3

Config.PreferredFirstEnemyDistance = 13
Config.MinimumFirstEnemyDistance = 8
Config.MaximumFirstEnemyDistance = 18

Config.ReferenceNames = table.freeze({
	"SafeSpawn",
	"Entry",
	"Checkpoint",
	"Spawn",
	"ObjectiveAnchor",
})

function Config.AppliesToIsland(globalIslandIndex)
	local index =
		math.floor(
			tonumber(globalIslandIndex) or 0
		)

	return index >= 1
		and index <= Config.AppliesThroughIsland
end

function Config.ScoreDistance(distance)
	distance =
		math.max(
			0,
			tonumber(distance) or math.huge
		)

	local score =
		math.abs(
			distance
				- Config.PreferredFirstEnemyDistance
		)

	if distance < Config.MinimumFirstEnemyDistance then
		score +=
			(
				Config.MinimumFirstEnemyDistance
					- distance
			) * 4
	elseif distance > Config.MaximumFirstEnemyDistance then
		score +=
			(
				distance
					- Config.MaximumFirstEnemyDistance
			) * 4
	end

	return score
end

function Config.IsInPreferredBand(distance)
	distance = tonumber(distance)

	return distance ~= nil
		and distance >= Config.MinimumFirstEnemyDistance
		and distance <= Config.MaximumFirstEnemyDistance
end

return table.freeze(Config)
