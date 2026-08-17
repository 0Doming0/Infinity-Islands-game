--[[
	Infinity Islands - IslandMobRosterConfig V6
	Advanced Slime Variety

	Goals:
	- a Ilha Inicial mostra tres slimes pacificos em ordem legivel;
	- a Ilha 1 numerada usa somente Green Slime;
	- Ilhas 2-6 apresentam Blue, Red, Fire, Ice e Lightning separadamente;
	- a partir da Ilha 7, todas as variantes avancadas podem aparecer juntas;
	- Keep deterministic composition by seed.
	- o budget avancado precisa comportar o elenco sem fallback verde;
	- Golden never enters the regular roster.
	- Newest unlocked variant remains guaranteed when possible.

	Advanced policy:
	- minimum Green ratio: 0%;
	- Blue aparece sozinho na ilha 2;
	- Red, Fire, Ice e Lightning aparecem sozinhos nas ilhas 3-6;
	- a Ilha 7 garante todos os cinco tipos avancados antes do preenchimento aleatorio.
]]

local IslandMobRosterConfig = {}

IslandMobRosterConfig.Version =
	"IslandMobRosterV6ThreeSlimePreviewThenMixed"

IslandMobRosterConfig.AdvancedSlimeStartLevel = 2
IslandMobRosterConfig.SoloIntroductionEndLevel = 6
IslandMobRosterConfig.MixedSlimeStartLevel = 7

-- Initial islands: simple/readable.
IslandMobRosterConfig.EarlyMinimumGreenRatio = 0.40
IslandMobRosterConfig.EarlyMaximumRangedRatio = 0.40
IslandMobRosterConfig.EarlyMaximumSpecialRatio = 0.35

-- Advanced slime islands: visibly more varied.
IslandMobRosterConfig.AdvancedMinimumGreenRatio = 0
IslandMobRosterConfig.AdvancedMaximumRangedRatio = 1
IslandMobRosterConfig.AdvancedMaximumSpecialRatio = 1

-- Compatibility aliases for diagnostics/older consumers.
IslandMobRosterConfig.MinimumGreenRatio =
	IslandMobRosterConfig.AdvancedMinimumGreenRatio
IslandMobRosterConfig.MaximumRangedRatio =
	IslandMobRosterConfig.AdvancedMaximumRangedRatio
IslandMobRosterConfig.MaximumSpecialRatio =
	IslandMobRosterConfig.AdvancedMaximumSpecialRatio

local ORDER = {
	"Green",
	"Blue",
	"Red",
	"Fire",
	"Ice",
	"Lightning",
}

local DEMONSTRATION_ORDER = {
	"Green",
	"Blue",
	"Red",
	"Fire",
	"Ice",
	"Lightning",
	"Golden",
}

local DEFINITIONS = {
	Green = table.freeze({
		Variant = "Green",
		UnlockLevel = 1,
		ThreatCost = 1,
		EarlyWeight = 100,
		AdvancedWeight = 24,
		Ranged = false,
		Special = false,
	}),
	Blue = table.freeze({
		Variant = "Blue",
		UnlockLevel = 2,
		ThreatCost = 2,
		EarlyWeight = 55,
		AdvancedWeight = 95,
		Ranged = true,
		Special = false,
	}),
	Red = table.freeze({
		Variant = "Red",
		UnlockLevel = 3,
		ThreatCost = 2,
		EarlyWeight = 40,
		AdvancedWeight = 85,
		Ranged = true,
		Special = true,
	}),
	Fire = table.freeze({
		Variant = "Fire",
		UnlockLevel = 4,
		ThreatCost = 3,
		EarlyWeight = 30,
		AdvancedWeight = 76,
		Ranged = true,
		Special = true,
	}),
	Ice = table.freeze({
		Variant = "Ice",
		UnlockLevel = 5,
		ThreatCost = 3,
		EarlyWeight = 26,
		AdvancedWeight = 72,
		Ranged = true,
		Special = true,
	}),
	Lightning = table.freeze({
		Variant = "Lightning",
		UnlockLevel = 6,
		ThreatCost = 3,
		EarlyWeight = 22,
		AdvancedWeight = 68,
		Ranged = false,
		Special = true,
	}),
	Golden = table.freeze({
		Variant = "Golden",
		UnlockLevel = 999999,
		ThreatCost = 1,
		EarlyWeight = 0,
		AdvancedWeight = 0,
		Ranged = false,
		Special = true,
		DemoOnly = true,
	}),
}

local function cleanLevel(value)
	return math.max(
		1,
		math.floor(tonumber(value) or 1)
	)
end

local function cleanCount(value)
	return math.max(
		1,
		math.floor(tonumber(value) or 1)
	)
end

local function normalizedSeed(value)
	local seed =
		math.floor(
			math.abs(tonumber(value) or 1)
		) % 2147483647

	return seed == 0 and 1 or seed
end

local function isAdvancedLevel(level)
	return cleanLevel(level)
		>= IslandMobRosterConfig.AdvancedSlimeStartLevel
end

local function policyForLevel(level)
	if isAdvancedLevel(level) then
		return {
			MinimumGreenRatio =
				IslandMobRosterConfig
					.AdvancedMinimumGreenRatio,

			MaximumRangedRatio =
				IslandMobRosterConfig
					.AdvancedMaximumRangedRatio,

			MaximumSpecialRatio =
				IslandMobRosterConfig
					.AdvancedMaximumSpecialRatio,

			Advanced = true,
		}
	end

	return {
		MinimumGreenRatio =
			IslandMobRosterConfig
				.EarlyMinimumGreenRatio,

		MaximumRangedRatio =
			IslandMobRosterConfig
				.EarlyMaximumRangedRatio,

		MaximumSpecialRatio =
			IslandMobRosterConfig
				.EarlyMaximumSpecialRatio,

		Advanced = false,
	}
end

local function weightFor(
	definition,
	advanced
)
	if advanced then
		return definition.AdvancedWeight
			or definition.EarlyWeight
			or 1
	end

	return definition.EarlyWeight
		or definition.AdvancedWeight
		or 1
end

function IslandMobRosterConfig.GetVariant(
	variantName
)
	return DEFINITIONS[
		tostring(variantName or "")
	]
end

function IslandMobRosterConfig.GetUnlockedVariants(
	islandLevel
)
	local level = cleanLevel(islandLevel)
	local result = {}

	for _, variantName in ipairs(ORDER) do
		local definition =
			DEFINITIONS[variantName]

		if definition.UnlockLevel <= level then
			table.insert(
				result,
				variantName
			)
		end
	end

	return result
end

function IslandMobRosterConfig.GetNewestUnlockedVariant(
	islandLevel
)
	local level = cleanLevel(islandLevel)
	local newest = "Green"

	for _, variantName in ipairs(ORDER) do
		local definition =
			DEFINITIONS[variantName]

		if definition.UnlockLevel <= level then
			newest = variantName
		end
	end

	return newest
end

function IslandMobRosterConfig.GetThreatBudget(
	targetCount,
	islandLevel
)
	local count = cleanCount(targetCount)
	local level = cleanLevel(islandLevel)

	if isAdvancedLevel(level) then
		local maximumUnlockedThreat = 1

		for _, variantName in ipairs(ORDER) do
			local definition = DEFINITIONS[variantName]

			if variantName ~= "Green"
				and definition.UnlockLevel <= level
			then
				maximumUnlockedThreat = math.max(
					maximumUnlockedThreat,
					definition.ThreatCost
				)
			end
		end

		return count * maximumUnlockedThreat
	end

	local extraPerMob =
		math.clamp(
			(level - 1) * 0.055,
			0,
			0.60
		)

	return math.max(
		count,
		math.floor(
			count
				* (1 + extraPerMob)
				+ 0.5
		)
	)
end

local function capCount(
	total,
	ratio
)
	if total <= 1 then
		return ratio >= 1 and total or 0
	end

	return math.max(
		1,
		math.floor(
			total * ratio + 0.0001
		)
	)
end

local function canAdd(
	definition,
	state,
	maximumRanged,
	maximumSpecial,
	threatBudget
)
	if not definition then
		return false
	end

	if state.ThreatUsed
		+ definition.ThreatCost
		> threatBudget
	then
		return false
	end

	if definition.Ranged
		and state.RangedCount
			>= maximumRanged
	then
		return false
	end

	if definition.Special
		and state.SpecialCount
			>= maximumSpecial
	then
		return false
	end

	return true
end

local function addVariant(
	roster,
	variantName,
	state
)
	local definition =
		DEFINITIONS[variantName]

	if not definition then
		return false
	end

	table.insert(
		roster,
		variantName
	)

	state.ThreatUsed +=
		definition.ThreatCost

	if variantName == "Green" then
		state.GreenCount += 1
	else
		state.AdvancedCount += 1
	end

	if definition.Ranged then
		state.RangedCount += 1
	end

	if definition.Special then
		state.SpecialCount += 1
	end

	state.CountByVariant[variantName] =
		(state.CountByVariant[variantName] or 0)
		+ 1

	return true
end

local function weightedChoice(
	random,
	candidates,
	advanced
)
	local totalWeight = 0

	for _, variantName in ipairs(candidates) do
		totalWeight +=
			weightFor(
				DEFINITIONS[variantName],
				advanced
			)
	end

	if totalWeight <= 0 then
		return "Green"
	end

	local roll =
		random:NextNumber(
			0,
			totalWeight
		)

	local accumulated = 0

	for _, variantName in ipairs(candidates) do
		accumulated +=
			weightFor(
				DEFINITIONS[variantName],
				advanced
			)

		if roll <= accumulated then
			return variantName
		end
	end

	return candidates[#candidates]
		or "Green"
end

local function shuffle(
	random,
	source
)
	local result =
		table.clone(source)

	for index = #result, 2, -1 do
		local other =
			random:NextInteger(
				1,
				index
			)

		result[index],
			result[other] =
				result[other],
				result[index]
	end

	return result
end

local function advancedCandidates(
	unlocked
)
	local result = {}

	for _, variantName in ipairs(unlocked) do
		if variantName ~= "Green" then
			table.insert(
				result,
				variantName
			)
		end
	end

	return result
end

function IslandMobRosterConfig.BuildRoster(
	targetCount,
	islandLevel,
	seed
)
	local count =
		cleanCount(targetCount)

	local level =
		cleanLevel(islandLevel)

	local random =
		Random.new(
			normalizedSeed(seed)
		)

	local policy =
		policyForLevel(level)

	local unlocked =
		IslandMobRosterConfig
			.GetUnlockedVariants(level)

	local nonGreenUnlocked =
		advancedCandidates(unlocked)

	local advancedOnly =
		policy.Advanced
			and #nonGreenUnlocked > 0

	local newest =
		IslandMobRosterConfig
			.GetNewestUnlockedVariant(level)

	local threatBudget =
		IslandMobRosterConfig
			.GetThreatBudget(
				count,
				level
			)

	local minimumGreen = 0

	if not advancedOnly then
		minimumGreen =
			math.clamp(
				math.ceil(
					count
						* policy
							.MinimumGreenRatio
				),
				1,
				count
			)
	end

	local maximumRanged =
		capCount(
			count,
			policy.MaximumRangedRatio
		)

	local maximumSpecial =
		capCount(
			count,
			policy.MaximumSpecialRatio
		)

	local roster = {}

	local state = {
		ThreatUsed = 0,
		GreenCount = 0,
		AdvancedCount = 0,
		RangedCount = 0,
		SpecialCount = 0,
		CountByVariant = {},
	}

	-- Cada mecanica avancada recebe uma ilha propria antes das combinacoes.
	-- Isso torna a leitura do ataque clara para o jogador no primeiro contato.
	if policy.Advanced
		and level <= IslandMobRosterConfig.SoloIntroductionEndLevel
	then
		for _ = 1, count do
			addVariant(roster, newest, state)
		end

		return {
			Version = IslandMobRosterConfig.Version,
			Roster = roster,
			ThreatBudget = threatBudget,
			ThreatUsed = state.ThreatUsed,
			GreenCount = state.GreenCount,
			AdvancedCount = state.AdvancedCount,
			RangedCount = state.RangedCount,
			SpecialCount = state.SpecialCount,
			CountByVariant = state.CountByVariant,
			NewestUnlockedVariant = newest,
			NewestVariantGuaranteed = true,
			AdvancedSlimePolicy = true,
			AdvancedOnly = true,
			MinimumGreenRatio = 0,
			MaximumRangedRatio = 1,
			MaximumSpecialRatio = 1,
			SoloIntroduction = true,
		}
	end

	-- Green existe somente no onboarding. Ilhas avancadas comecam vazias
	-- para nunca consumirem uma vaga com a variante basica.
	for _ = 1, minimumGreen do
		addVariant(
			roster,
			"Green",
			state
		)
	end

	local newestVariantGuaranteed = false

	-- Always introduce the newest mechanic when budget/caps allow.
	if #roster < count
		and newest ~= "Green"
	then
		local newestDefinition =
			DEFINITIONS[newest]

		if canAdd(
			newestDefinition,
			state,
			maximumRanged,
			maximumSpecial,
			threatBudget
		) then
			addVariant(
				roster,
				newest,
				state
			)

			newestVariantGuaranteed = true
		end
	end

	-- Na primeira ilha mista e nas seguintes, cada variante desbloqueada recebe
	-- ao menos uma vaga antes do preenchimento aleatorio.
	if policy.Advanced
		and #roster < count
	then
		for _, variantName in ipairs(nonGreenUnlocked) do
			if #roster >= count then
				break
			end
			local definition =
				DEFINITIONS[variantName]

			if not state.CountByVariant[variantName]
				and canAdd(
				definition,
				state,
				maximumRanged,
				maximumSpecial,
				threatBudget
			) then
				addVariant(
					roster,
					variantName,
					state
				)
			end
		end
	end

	while #roster < count do
		local candidates = {}
		local sourceCandidates =
			advancedOnly
				and nonGreenUnlocked
				or unlocked

		for _, variantName in ipairs(
			sourceCandidates
		) do
			local definition =
				DEFINITIONS[variantName]

			if canAdd(
				definition,
				state,
				maximumRanged,
				maximumSpecial,
				threatBudget
			) then
				table.insert(
					candidates,
					variantName
				)
			end
		end

		if #candidates == 0 then
			addVariant(
				roster,
				advancedOnly
					and nonGreenUnlocked[1]
					or "Green",
				state
			)
		else
			addVariant(
				roster,
				weightedChoice(
					random,
					candidates,
					policy.Advanced
				),
				state
			)
		end
	end

	roster =
		shuffle(
			random,
			roster
		)

	return {
		Version =
			IslandMobRosterConfig.Version,

		Roster = roster,

		ThreatBudget =
			threatBudget,

		ThreatUsed =
			state.ThreatUsed,

		GreenCount =
			state.GreenCount,

		AdvancedCount =
			state.AdvancedCount,

		RangedCount =
			state.RangedCount,

		SpecialCount =
			state.SpecialCount,

		CountByVariant =
			state.CountByVariant,

		NewestUnlockedVariant =
			newest,

		NewestVariantGuaranteed =
			newestVariantGuaranteed,

		AdvancedSlimePolicy =
			policy.Advanced,

		AdvancedOnly =
			advancedOnly,

		MinimumGreenRatio =
			policy.MinimumGreenRatio,

		MaximumRangedRatio =
			policy.MaximumRangedRatio,

		MaximumSpecialRatio =
			policy.MaximumSpecialRatio,
	}
end

function IslandMobRosterConfig.BuildDemonstrationRoster(
	targetCount,
	seed
)
	local count = cleanCount(targetCount)
	local roster = {}
	local state = {
		ThreatUsed = 0,
		GreenCount = 0,
		AdvancedCount = 0,
		RangedCount = 0,
		SpecialCount = 0,
		CountByVariant = {},
	}

	for index = 1, count do
		local variantName = DEMONSTRATION_ORDER[
			((index - 1) % #DEMONSTRATION_ORDER) + 1
		]
		addVariant(roster, variantName, state)
	end

	-- A Ilha Inicial precisa ensinar visualmente: o primeiro slime sempre e
	-- Verde, seguido de Azul e Vermelho. `seed` permanece na assinatura por
	-- compatibilidade com os chamadores antigos.

	return {
		Version = IslandMobRosterConfig.Version,
		Roster = roster,
		ThreatBudget = state.ThreatUsed,
		ThreatUsed = state.ThreatUsed,
		GreenCount = state.GreenCount,
		AdvancedCount = state.AdvancedCount,
		RangedCount = state.RangedCount,
		SpecialCount = state.SpecialCount,
		CountByVariant = state.CountByVariant,
		NewestUnlockedVariant = "Golden",
		NewestVariantGuaranteed = count >= #DEMONSTRATION_ORDER,
		AdvancedSlimePolicy = false,
		AdvancedOnly = false,
		MinimumGreenRatio = 0,
		MaximumRangedRatio = 1,
		MaximumSpecialRatio = 1,
		Demonstration = true,
	}
end

function IslandMobRosterConfig.Validate()
	assert(
		DEFINITIONS.Golden.DemoOnly == true,
		"Golden precisa permanecer exclusivo da demonstracao"
	)

	local demonstration =
		IslandMobRosterConfig.BuildDemonstrationRoster(
			#DEMONSTRATION_ORDER,
			777
		)

	for _, variantName in ipairs(DEMONSTRATION_ORDER) do
		assert(
			(demonstration.CountByVariant[variantName] or 0) == 1,
			"Demonstracao inicial precisa incluir " .. variantName
		)
	end

	local shortDemonstration =
		IslandMobRosterConfig.BuildDemonstrationRoster(3, 777)
	assert(
		shortDemonstration.Roster[1] == "Green"
			and shortDemonstration.Roster[2] == "Blue"
			and shortDemonstration.Roster[3] == "Red",
		"Demonstracao curta precisa seguir Verde, Azul, Vermelho"
	)

	local levelOne =
		IslandMobRosterConfig
			.BuildRoster(
				6,
				1,
				123
			)

	for _, variantName in ipairs(
		levelOne.Roster
	) do
		assert(
			variantName == "Green",
			"Level 1 precisa continuar apenas Green"
		)
	end

	local levelTwo =
		IslandMobRosterConfig
			.BuildRoster(
				6,
				2,
				12345
			)

	assert(
		levelTwo.AdvancedSlimePolicy == true
			and levelTwo.AdvancedOnly == true,
		"Level 2 precisa ativar a politica somente avancada"
	)

	for _, variantName in ipairs(levelTwo.Roster) do
		assert(
			variantName == "Blue",
			"Level 2 precisa ser uma ilha somente de Blue Slimes"
		)
	end

	for level, expectedVariant in pairs({
		[3] = "Red",
		[4] = "Fire",
		[5] = "Ice",
		[6] = "Lightning",
	}) do
		local introduction =
			IslandMobRosterConfig.BuildRoster(8, level, 1000 + level)
		for _, variantName in ipairs(introduction.Roster) do
			assert(
				variantName == expectedVariant,
				string.format(
					"Level %d precisa apresentar somente %s",
					level,
					expectedVariant
				)
			)
		end
	end

	local sample =
		IslandMobRosterConfig
			.BuildRoster(
				10,
				7,
				98765
			)

	assert(
		#sample.Roster == 10,
		"Roster precisa respeitar TargetCount"
	)

	assert(
		sample.GreenCount == 0,
		"Roster avancado nao pode incluir Green"
	)

	assert(
		(sample.CountByVariant.Lightning or 0) >= 1,
		"Ilha mista precisa manter Lightning"
	)

	for _, variantName in ipairs({ "Blue", "Red", "Fire", "Ice", "Lightning" }) do
		assert(
			(sample.CountByVariant[variantName] or 0) >= 1,
			"Ilha mista precisa incluir " .. variantName
		)
	end

	assert(
		sample.RangedCount
			<= capCount(
				10,
				IslandMobRosterConfig
					.AdvancedMaximumRangedRatio
			),
		"Roster avancado excedeu limite ranged"
	)

	assert(
		sample.SpecialCount
			<= capCount(
				10,
				IslandMobRosterConfig
					.AdvancedMaximumSpecialRatio
			),
		"Roster avancado excedeu limite special"
	)

	for _, variantName in ipairs(
		sample.Roster
	) do
		assert(
			variantName ~= "Green"
				and variantName ~= "Golden",
			"Roster avancado aceita somente variantes nao verdes regulares"
		)
	end

	return true
end

IslandMobRosterConfig.Validate()

IslandMobRosterConfig.Definitions =
	table.freeze(DEFINITIONS)

IslandMobRosterConfig.Order =
	table.freeze(
		table.clone(ORDER)
	)

IslandMobRosterConfig.DemonstrationOrder =
	table.freeze(
		table.clone(DEMONSTRATION_ORDER)
	)

return table.freeze(
	IslandMobRosterConfig
)
