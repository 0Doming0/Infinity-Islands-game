-- Infinity Islands - Clean Boot diagnostics.
-- Temporary: useful until map generation is stable.

local function printSnapshot(label)
	local names = {
		"DungeonBootstrapReady",
		"DungeonBootstrapError",
		"DungeonGenerationState",
		"DungeonGenerationError",
		"DungeonRouteArchitecture",
		"DungeonInitialRouteReady",
		"DungeonInitialRouteError",
		"DungeonRuntimeReady",
		"DungeonStandaloneWorldReady",
		"DungeonIslandProgressionReady",
		"DungeonIslandCombatReady",
		"DungeonPlayerLevelReady",
	}

	local parts = {}

	for _, name in ipairs(names) do
		table.insert(
			parts,
			name .. "=" .. tostring(
				workspace:GetAttribute(name)
			)
		)
	end

	print(
		"[CleanBootDiagnostics:"
			.. label
			.. "] "
			.. table.concat(parts, " | ")
	)
end

task.delay(5, function()
	printSnapshot("5s")
end)

task.delay(15, function()
	printSnapshot("15s")
end)
