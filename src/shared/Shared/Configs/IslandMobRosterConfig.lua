--[[
	Infinity Islands - IslandMobRosterConfig V2
	Advanced Slime Variety

	Goals:
	- Levels 1-2 remain simple Green-slime onboarding.
	- From IslandLevel 3 onward, advanced-slime islands strongly favor
	  unlocked non-Green variants.
	- Keep deterministic composition by seed.
	- Keep threat-budget limits.
	- Golden never enters the regular roster.
	- Newest unlocked variant remains guaranteed when possible.

	Advanced policy:
	- minimum Green ratio: 25%;
	- maximum ranged ratio: 65%;
	- maximum special ratio: 55%;
	- Green weight falls sharply;
	- advanced variants receive much higher selection weights.
]]

local IslandMobRosterConfig = {}

IslandMobRosterConfig.Version =
	"IslandMobRosterV2AdvancedVariety"

IslandMobRosterConfig.AdvancedSlimeStartLevel = 3

-- Initial islands: simple/readable.
IslandMobRosterConfig.EarlyMinimumGreenRatio = 0.40
IslandMobRosterConfig.EarlyMaximumRangedRatio = 0.40
IslandMobRosterConfig.EarlyMaximumSpecialRatio = 0.35

-- Advanced slime islands: visibly more varied.
IslandMobRosterConfig.AdvancedMinimumGreenRatio = 0.25
IslandMobRosterConfig.AdvancedMaximumRangedRatio = 0.65
IslandMobRosterConfig.AdvancedMaximumSpecialRatio = 0.55

-- Compatibility aliases for diagnostics/older consumers.
IslandMobRosterConfig.MinimumGreenRatio =
	IslandMobRosterConfig.EarlyMinimumGreenRatio
IslandMobRosterConfig.MaximumRangedRatio =
	IslandMobRosterConfig.EarlyMaximumRangedRatio
IslandMobRosterConfig.MaximumSpecialRatio =
	IslandMobRosterConfig.EarlyMaximumSpecialRatio

local ORDER = {
	"Green",
	"Blue",
	"Red",
	"Fire",
	"Ice",
	"Lightning",
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
		UnlockLevel = 3,
		ThreatCost = 2,
		EarlyWeight = 55,
		AdvancedWeight = 95,
		Ranged = true,
		Special = false,
	}),
	Red = table.freeze({
		Variant = "Red",
		UnlockLevel = 5,
		ThreatCost = 2,
		EarlyWeight = 40,
		AdvancedWeight = 85,
		Ranged = true,
		Special = true,
	}),
	Fire = table.freeze({
		Variant = "Fire",
		UnlockLevel = 7,
		ThreatCost = 3,
		EarlyWeight = 30,
		AdvancedWeight = 76,
		Ranged = true,
		Special = true,
	}),
	Ice = table.freeze({
		Variant = "Ice",
		UnlockLevel = 9,
		ThreatCost = 3,
		EarlyWeight = 26,
		AdvancedWeight = 72,
		Ranged = true,
		Special = true,
	}),
	Lightning = table.freeze({
		Variant = "Lightning",
		UnlockLevel = 11,
		ThreatCost = 3,
		EarlyWeight = 22,
		AdvancedWeight = 68,
		Ranged = false,
		Special = true,
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
		return 0
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

	local newest =
		IslandMobRosterConfig
			.GetNewestUnlockedVariant(level)

	local threatBudget =
		IslandMobRosterConfig
			.GetThreatBudget(
				count,
				level
			)

	local minimumGreen =
		math.clamp(
			math.ceil(
				count
					* policy
						.MinimumGreenRatio
			),
			1,
			count
		)

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

	-- Preserve a small Green baseline for visual readability.
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

	-- Advanced islands should not accidentally become mostly Green.
	-- If at least one advanced type is unlocked and there is room, try to
	-- guarantee a second non-Green slot before random filling.
	if policy.Advanced
		and #roster < count
	then
		local nonGreen =
			advancedCandidates(unlocked)

		local valid = {}

		for _, variantName in ipairs(nonGreen) do
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
					valid,
					variantName
				)
			end
		end

		if #valid > 0 then
			addVariant(
				roster,
				weightedChoice(
					random,
					valid,
					true
				),
				state
			)
		end
	end

	while #roster < count do
		local candidates = {}

		for _, variantName in ipairs(
			unlocked
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
				"Green",
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

		MinimumGreenRatio =
			policy.MinimumGreenRatio,

		MaximumRangedRatio =
			policy.MaximumRangedRatio,

		MaximumSpecialRatio =
			policy.MaximumSpecialRatio,
	}
end

function IslandMobRosterConfig.Validate()
	assert(
		DEFINITIONS.Golden == nil,
		"Golden nao pode entrar no roster normal"
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

	local levelThree =
		IslandMobRosterConfig
			.BuildRoster(
				6,
				3,
				12345
			)

	assert(
		levelThree.AdvancedSlimePolicy == true,
		"Level 3 precisa ativar politica de Advanced Slimes"
	)

	assert(
		(levelThree.CountByVariant.Blue or 0) >= 1,
		"Level 3 precisa incluir Blue"
	)

	assert(
		levelThree.AdvancedCount >= 2,
		"Advanced Slime island precisa tentar incluir pelo menos 2 nao-Green"
	)

	local sample =
		IslandMobRosterConfig
			.BuildRoster(
				10,
				11,
				98765
			)

	assert(
		#sample.Roster == 10,
		"Roster precisa respeitar TargetCount"
	)

	assert(
		sample.GreenCount
			>= math.ceil(
				10
					* IslandMobRosterConfig
						.AdvancedMinimumGreenRatio
			),
		"Roster avancado precisa preservar minimo Green"
	)

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
			variantName ~= "Golden",
			"Golden nao pode aparecer em Combat Island normal"
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

return table.freeze(
	IslandMobRosterConfig
)
