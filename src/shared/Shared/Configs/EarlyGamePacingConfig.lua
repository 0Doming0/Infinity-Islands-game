--[[
	Infinity Islands - Task 17
	EarlyGamePacingConfig V4

	First 60-90 second retention calibration.

	The core loop itself stays unchanged. These are explicit early-route
	overrides layered on top of the normal IslandLevel systems.

	Why:
		- Initial Island: demonstracao pacifica de todas as variantes;
		- todas as variantes iniciais usam vida e XP do Green L1;
		- Numbered Island 1: 3 Green L1;
		- Numbered Islands 2-6 apresentam cada variante avancada separadamente;
		- Numbered Island 7 inicia as combinacoes de slimes.

	This produces:
	first kill -> visible XP
	Initial Island -> demonstracao segura com recompensa reduzida
	Numbered Island 1 -> primeiro combate real somente com Green
	Numbered Island 2 -> primeiro inimigo avancado, somente Blue
	Numbered Island 7 -> primeira arena com os tipos avancados juntos
]]

local Config = {}

Config.Version = "InitialAllSlimesThenGreenIslandOneV4"
Config.Policy = "InitialTutorialThenGrowingNumberedCycle"

Config.CalibrationWindowSeconds = 90

-- A ilha inicial e um tutorial fora da numeracao normal.
Config.InitialIslandXPRewardMultiplier = 0.50
Config.InitialIslandModelScale = 0.60

Config.IslandOverrides = table.freeze({
	[1] = table.freeze({
		TargetCount = 7,
		MaximumAlive = 7,
		SpawnStaggerSeconds = 0.40,
		ExpectedRoster = "AllSlimeVariantsPassiveGreenStats",
		ExpectedMobLevel = 1,
		ExpectedXPPerMob = 6,
		ExpectedTotalXP = 42,
		ExpectedModelScale = 0.60,
		ExpectedOutcome = "TutorialPracticeNoGuaranteedLevelUp",
	}),
	[2] = table.freeze({
		MaximumAlive = 3,
		SpawnStaggerSeconds = 0.30,
		ExpectedVariant = "Green",
		ExpectedMobLevel = 1,
		ExpectedTargetCount = 3,
		ExpectedTotalBaseXP = 36,
		ExpectedOutcome = "FirstNumberedIslandStartsCycleAtThreeMobs",
	}),
	[3] = table.freeze({
		MaximumAlive = 4,
		SpawnStaggerSeconds = 0.25,
		ExpectedRoster = "BlueOnlyNoGreen",
		ExpectedMobLevel = 2,
		ExpectedTargetCount = 4,
		ExpectedOutcome = "FirstAdvancedSlimeMechanicIntroduced",
	}),
})

Config.TelemetryTargets = table.freeze({
	FirstXPSeconds = 15,
	FirstLevelUpSeconds = 40,
	Island2EntrySeconds = 50,
	Island3EntrySeconds = 90,
})

function Config.GetOverride(globalIslandIndex)
	local index =
		math.floor(
			tonumber(globalIslandIndex) or 0
		)

	return Config.IslandOverrides[index]
end

function Config.GetTargetCount(
	globalIslandIndex,
	defaultCount
)
	local override =
		Config.GetOverride(
			globalIslandIndex
		)

	if override
		and override.TargetCount
	then
		return math.max(
			1,
			math.floor(
				override.TargetCount
			)
		)
	end

	return math.max(
		1,
		math.floor(
			tonumber(defaultCount) or 1
		)
	)
end

function Config.GetMaximumAlive(
	globalIslandIndex,
	defaultMaximumAlive,
	targetCount
)
	local override =
		Config.GetOverride(
			globalIslandIndex
		)

	local maximum =
		override
			and override.MaximumAlive
			or defaultMaximumAlive

	maximum =
		math.max(
			1,
			math.floor(
				tonumber(maximum) or 1
			)
		)

	return math.min(
		maximum,
		math.max(
			1,
			math.floor(
				tonumber(targetCount) or 1
			)
		)
	)
end

function Config.GetSpawnStaggerSeconds(
	globalIslandIndex,
	defaultSeconds
)
	local override =
		Config.GetOverride(
			globalIslandIndex
		)

	return math.max(
		0.05,
		tonumber(
			override
				and override.SpawnStaggerSeconds
				or defaultSeconds
		) or 0.25
	)
end

function Config.Validate()
	assert(
		Config.InitialIslandXPRewardMultiplier == 0.50,
		"Ilha inicial precisa entregar 50% do XP normal"
	)

	assert(
		Config.InitialIslandModelScale == 0.60,
		"Mobs iniciais precisam ser 40% menores"
	)

	assert(
		Config.GetTargetCount(1, 3) == 7,
		"Ilha Inicial precisa demonstrar as 7 variantes"
	)

	assert(
		Config.GetTargetCount(2, 3) == 3,
		"Ilha numerada 1 precisa preservar os 3 mobs da curva"
	)

	assert(
		Config.GetTargetCount(3, 3) == 3,
		"Ilha numerada 2 nao deve sobrescrever a curva normal"
	)

	assert(
		Config.GetMaximumAlive(
			1,
			7,
			7
		) == 7,
		"Ilha Inicial precisa manter as 7 variantes visiveis"
	)

	assert(
		math.abs(
			Config.GetSpawnStaggerSeconds(
				1,
				0.25
			) - 0.40
		) < 0.0001,
		"Ilha Inicial precisa usar stagger 0.40"
	)

	return true
end

Config.Validate()

return table.freeze(Config)
