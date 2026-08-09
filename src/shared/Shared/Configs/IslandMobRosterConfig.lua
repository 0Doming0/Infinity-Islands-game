--[[
	Infinity Islands - Task 06
	IslandMobRosterConfig V1

	Fonte unica da composicao de mobs das Combat Islands.

	Regras:
	- desbloqueio por IslandLevel;
	- composicao deterministica por seed;
	- pelo menos 40% Green para leitura simples no mobile;
	- limite de ranged e special;
	- variante nova e introduzida quando houver espaco;
	- Golden nunca entra no roster normal.
]]

local IslandMobRosterConfig = {}

IslandMobRosterConfig.Version = "IslandMobRosterV1"

IslandMobRosterConfig.MinimumGreenRatio = 0.40
IslandMobRosterConfig.MaximumRangedRatio = 0.40
IslandMobRosterConfig.MaximumSpecialRatio = 0.35

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
		Weight = 100,
		Ranged = false,
		Special = false,
	}),
	Blue = table.freeze({
		Variant = "Blue",
		UnlockLevel = 3,
		ThreatCost = 2,
		Weight = 55,
		Ranged = true,
		Special = false,
	}),
	Red = table.freeze({
		Variant = "Red",
		UnlockLevel = 5,
		ThreatCost = 2,
		Weight = 40,
		Ranged = true,
		Special = true,
	}),
	Fire = table.freeze({
		Variant = "Fire",
		UnlockLevel = 7,
		ThreatCost = 3,
		Weight = 30,
		Ranged = true,
		Special = true,
	}),
	Ice = table.freeze({
		Variant = "Ice",
		UnlockLevel = 9,
		ThreatCost = 3,
		Weight = 26,
		Ranged = true,
		Special = true,
	}),
	Lightning = table.freeze({
		Variant = "Lightning",
		UnlockLevel = 11,
		ThreatCost = 3,
		Weight = 22,
		Ranged = false,
		Special = true,
	}),
}

local function cleanLevel(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function cleanCount(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % 2147483647
	return seed == 0 and 1 or seed
end

function IslandMobRosterConfig.GetVariant(variantName)
	return DEFINITIONS[tostring(variantName or "")]
end

function IslandMobRosterConfig.GetUnlockedVariants(islandLevel)
	local level = cleanLevel(islandLevel)
	local result = {}

	for _, variantName in ipairs(ORDER) do
		local definition = DEFINITIONS[variantName]
		if definition.UnlockLevel <= level then
			table.insert(result, variantName)
		end
	end

	return result
end

function IslandMobRosterConfig.GetNewestUnlockedVariant(islandLevel)
	local level = cleanLevel(islandLevel)
	local newest = "Green"

	for _, variantName in ipairs(ORDER) do
		local definition = DEFINITIONS[variantName]
		if definition.UnlockLevel <= level then
			newest = variantName
		end
	end

	return newest
end

function IslandMobRosterConfig.GetThreatBudget(targetCount, islandLevel)
	local count = cleanCount(targetCount)
	local level = cleanLevel(islandLevel)

	local extraPerMob = math.clamp((level - 1) * 0.055, 0, 0.60)
	return math.max(
		count,
		math.floor(count * (1 + extraPerMob) + 0.5)
	)
end

local function capCount(total, ratio)
	if total <= 1 then
		return 0
	end

	return math.max(
		1,
		math.floor(total * ratio + 0.0001)
	)
end

local function canAdd(definition, state, maximumRanged, maximumSpecial, threatBudget)
	if not definition then
		return false
	end

	if state.ThreatUsed + definition.ThreatCost > threatBudget then
		return false
	end

	if definition.Ranged and state.RangedCount >= maximumRanged then
		return false
	end

	if definition.Special and state.SpecialCount >= maximumSpecial then
		return false
	end

	return true
end

local function addVariant(roster, variantName, state)
	local definition = DEFINITIONS[variantName]
	if not definition then
		return false
	end

	table.insert(roster, variantName)
	state.ThreatUsed += definition.ThreatCost

	if variantName == "Green" then
		state.GreenCount += 1
	end

	if definition.Ranged then
		state.RangedCount += 1
	end

	if definition.Special then
		state.SpecialCount += 1
	end

	return true
end

local function weightedChoice(random, candidates)
	local totalWeight = 0

	for _, variantName in ipairs(candidates) do
		totalWeight += DEFINITIONS[variantName].Weight
	end

	if totalWeight <= 0 then
		return "Green"
	end

	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0

	for _, variantName in ipairs(candidates) do
		accumulated += DEFINITIONS[variantName].Weight
		if roll <= accumulated then
			return variantName
		end
	end

	return candidates[#candidates] or "Green"
end

local function shuffle(random, source)
	local result = table.clone(source)

	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end

	return result
end

function IslandMobRosterConfig.BuildRoster(targetCount, islandLevel, seed)
	local count = cleanCount(targetCount)
	local level = cleanLevel(islandLevel)
	local random = Random.new(normalizedSeed(seed))

	local unlocked = IslandMobRosterConfig.GetUnlockedVariants(level)
	local newest = IslandMobRosterConfig.GetNewestUnlockedVariant(level)
	local threatBudget = IslandMobRosterConfig.GetThreatBudget(count, level)

	local minimumGreen = math.clamp(
		math.ceil(count * IslandMobRosterConfig.MinimumGreenRatio),
		1,
		count
	)

	local maximumRanged = capCount(
		count,
		IslandMobRosterConfig.MaximumRangedRatio
	)

	local maximumSpecial = capCount(
		count,
		IslandMobRosterConfig.MaximumSpecialRatio
	)

	local roster = {}
	local state = {
		ThreatUsed = 0,
		GreenCount = 0,
		RangedCount = 0,
		SpecialCount = 0,
	}

	for _ = 1, minimumGreen do
		addVariant(roster, "Green", state)
	end

	local newestVariantGuaranteed = false

	if #roster < count and newest ~= "Green" then
		local newestDefinition = DEFINITIONS[newest]

		if canAdd(
			newestDefinition,
			state,
			maximumRanged,
			maximumSpecial,
			threatBudget
		) then
			addVariant(roster, newest, state)
			newestVariantGuaranteed = true
		end
	end

	while #roster < count do
		local candidates = {}

		for _, variantName in ipairs(unlocked) do
			local definition = DEFINITIONS[variantName]

			if canAdd(
				definition,
				state,
				maximumRanged,
				maximumSpecial,
				threatBudget
			) then
				table.insert(candidates, variantName)
			end
		end

		if #candidates == 0 then
			addVariant(roster, "Green", state)
		else
			addVariant(
				roster,
				weightedChoice(random, candidates),
				state
			)
		end
	end

	roster = shuffle(random, roster)

	return {
		Version = IslandMobRosterConfig.Version,
		Roster = roster,
		ThreatBudget = threatBudget,
		ThreatUsed = state.ThreatUsed,
		GreenCount = state.GreenCount,
		RangedCount = state.RangedCount,
		SpecialCount = state.SpecialCount,
		NewestUnlockedVariant = newest,
		NewestVariantGuaranteed = newestVariantGuaranteed,
	}
end

function IslandMobRosterConfig.Validate()
	assert(DEFINITIONS.Golden == nil, "Golden nao pode entrar no roster normal")

	assert(
		IslandMobRosterConfig.GetNewestUnlockedVariant(1) == "Green",
		"Level 1 precisa liberar somente Green"
	)
	assert(
		IslandMobRosterConfig.GetNewestUnlockedVariant(3) == "Blue",
		"Blue precisa desbloquear no level 3"
	)
	assert(
		IslandMobRosterConfig.GetNewestUnlockedVariant(5) == "Red",
		"Red precisa desbloquear no level 5"
	)
	assert(
		IslandMobRosterConfig.GetNewestUnlockedVariant(7) == "Fire",
		"Fire precisa desbloquear no level 7"
	)
	assert(
		IslandMobRosterConfig.GetNewestUnlockedVariant(9) == "Ice",
		"Ice precisa desbloquear no level 9"
	)
	assert(
		IslandMobRosterConfig.GetNewestUnlockedVariant(11) == "Lightning",
		"Lightning precisa desbloquear no level 11"
	)

	local levelOne = IslandMobRosterConfig.BuildRoster(6, 1, 123)
	for _, variantName in ipairs(levelOne.Roster) do
		assert(variantName == "Green", "Level 1 nao pode usar variante avancada")
	end

	local sample = IslandMobRosterConfig.BuildRoster(10, 11, 98765)
	assert(#sample.Roster == 10, "Roster precisa respeitar TargetCount")
	assert(
		sample.GreenCount >= math.ceil(10 * IslandMobRosterConfig.MinimumGreenRatio),
		"Roster precisa preservar quantidade minima de Green"
	)
	assert(
		sample.RangedCount <= capCount(10, IslandMobRosterConfig.MaximumRangedRatio),
		"Roster excedeu limite ranged"
	)
	assert(
		sample.SpecialCount <= capCount(10, IslandMobRosterConfig.MaximumSpecialRatio),
		"Roster excedeu limite special"
	)

	for _, variantName in ipairs(sample.Roster) do
		assert(variantName ~= "Golden", "Golden nao pode aparecer em Combat Island normal")
	end

	return true
end

IslandMobRosterConfig.Validate()

IslandMobRosterConfig.Definitions = table.freeze(DEFINITIONS)
IslandMobRosterConfig.Order = table.freeze(table.clone(ORDER))

return table.freeze(IslandMobRosterConfig)
