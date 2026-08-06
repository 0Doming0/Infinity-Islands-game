local EncounterCatalog = {}

local PROFILE_BUILDERS = {}

local function copyEnemy(role, count, options)
	options = type(options) == "table" and options or {}
	return {
		Role = role,
		Count = math.max(0, math.floor(tonumber(count) or 0)),
		SlimeVariant = options.SlimeVariant,
		IsElite = options.IsElite == true,
		HealthMultiplier = options.HealthMultiplier,
		DamageMultiplier = options.DamageMultiplier,
		SpeedMultiplier = options.SpeedMultiplier,
	}
end

local function distribute(total, waveCount)
	total = math.max(0, math.floor(tonumber(total) or 0))
	waveCount = math.max(1, math.floor(tonumber(waveCount) or 1))
	local result = table.create(waveCount, 0)
	for index = 1, total do
		result[((index - 1) % waveCount) + 1] += 1
	end
	return result
end

local function wave(delaySeconds, enemies, waitForClear)
	return {
		DelaySeconds = math.max(0, tonumber(delaySeconds) or 0),
		Enemies = enemies,
		WaitForClear = waitForClear ~= false,
	}
end

local function mixedWave(amount, rangedRatio, guardCount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	guardCount = math.clamp(math.floor(tonumber(guardCount) or 0), 0, amount)
	local remaining = amount - guardCount
	local rangedCount = math.clamp(math.floor(remaining * (tonumber(rangedRatio) or 0) + 0.5), 0, remaining)
	local commonCount = remaining - rangedCount
	local enemies = {}
	if commonCount > 0 then
		table.insert(enemies, copyEnemy("Common", commonCount, { SlimeVariant = "Green" }))
	end
	if rangedCount > 0 then
		table.insert(enemies, copyEnemy("Ranged", rangedCount, { SlimeVariant = "Blue" }))
	end
	if guardCount > 0 then
		table.insert(enemies, copyEnemy("Guard", guardCount, { SlimeVariant = "Green" }))
	end
	return enemies
end

local function buildDefeatWaves(target, waveCount, rangedRatio, guardsPerWave)
	local amounts = distribute(target, waveCount)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(index == 1 and 0.25 or 0.8, mixedWave(
			amount,
			rangedRatio,
			math.min(amount, guardsPerWave or 0)
		), true))
	end
	return waves
end

PROFILE_BUILDERS.FirstStrike = function(target, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(2 + partySize, 3, 6),
		Waves = {
			wave(0.15, {
				copyEnemy("Common", math.max(2, partySize + 1), { SlimeVariant = "Green" }),
			}, false),
		},
	}
end

PROFILE_BUILDERS.CommonWave = function(target, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(4 + partySize, 5, 8),
		Waves = buildDefeatWaves(target, partySize >= 3 and 2 or 1, 0, 0),
	}
end

PROFILE_BUILDERS.RewardWave01 = function(target, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(5 + partySize, 6, 9),
		Waves = buildDefeatWaves(target, 2, 0.2, 0),
	}
end

PROFILE_BUILDERS.SkyAmbush = function(target, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(5 + partySize, 6, 9),
		SpawnFromPerimeter = true,
		Waves = buildDefeatWaves(target, 2, 0.25, 0),
	}
end

PROFILE_BUILDERS.RangedThreat = function(target, partySize)
	local amounts = distribute(target, partySize >= 3 and 2 or 1)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(index == 1 and 0.2 or 0.75, {
			copyEnemy("Ranged", amount, { SlimeVariant = "Blue" }),
		}, true))
	end
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(3 + partySize, 4, 7),
		Waves = waves,
	}
end

PROFILE_BUILDERS.NestPair = function(target, partySize)
	return {
		Mode = "Nests",
		NestCount = target,
		NestHealth = 70 + partySize * 20,
		NestSpawnInterval = math.max(6, 9 - partySize * 0.5),
		NestMonsterRole = "Common",
		NestMonsterVariant = "Green",
		MaxAlive = math.clamp(3 + partySize, 4, 7),
		OpeningWave = {
			copyEnemy("Common", math.max(1, partySize), { SlimeVariant = "Green" }),
		},
	}
end

PROFILE_BUILDERS.RewardWave02 = function(target, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(6 + partySize, 7, 10),
		Waves = buildDefeatWaves(target, 2, 0.25, 1),
	}
end

PROFILE_BUILDERS.GuardLine = function(target, partySize)
	local amounts = distribute(target, partySize >= 3 and 2 or 1)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(index == 1 and 0.2 or 0.75, {
			copyEnemy("Guard", amount, {
				SlimeVariant = "Green",
				HealthMultiplier = 1.45,
				DamageMultiplier = 0.9,
			}),
		}, true))
	end
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(2 + partySize, 3, 6),
		Waves = waves,
	}
end

PROFILE_BUILDERS.BeaconDefense = function(_, partySize)
	return {
		Mode = "Beacon",
		BeaconRadius = 13,
		MaxAlive = math.clamp(4 + partySize, 5, 8),
		ContinuousInterval = math.max(5, 7.5 - partySize * 0.5),
		ContinuousWave = mixedWave(math.clamp(2 + partySize, 3, 6), 0.35, partySize >= 3 and 1 or 0),
		OpeningWave = mixedWave(math.clamp(2 + partySize, 3, 6), 0.25, 0),
	}
end

PROFILE_BUILDERS.NestCluster = function(target, partySize)
	return {
		Mode = "Nests",
		NestCount = target,
		NestHealth = 90 + partySize * 24,
		NestSpawnInterval = math.max(5.5, 8.5 - partySize * 0.5),
		NestMonsterRole = "Common",
		NestMonsterVariant = partySize >= 3 and "Red" or "Green",
		MaxAlive = math.clamp(4 + partySize, 5, 8),
		OpeningWave = mixedWave(math.max(2, partySize), 0.25, 0),
	}
end

PROFILE_BUILDERS.EliteHunt = function(_, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(3 + partySize, 4, 7),
		Waves = {
			wave(0.3, {
				copyEnemy("Elite", 1, {
					SlimeVariant = partySize >= 3 and "Lightning" or "Red",
					IsElite = true,
					HealthMultiplier = 1.25,
					DamageMultiplier = 0.95,
				}),
				copyEnemy("Common", math.max(0, partySize - 1), { SlimeVariant = "Green" }),
			}, false),
		},
	}
end

PROFILE_BUILDERS.FinalRewardWave = function(target, partySize)
	return {
		Mode = "Waves",
		MaxAlive = math.clamp(7 + partySize, 8, 11),
		Waves = buildDefeatWaves(target, 3, 0.3, 1),
	}
end

function EncounterCatalog.Build(definition, partySize, remainingTarget)
	assert(type(definition) == "table", "EncounterCatalog.Build requer definicao")
	partySize = math.clamp(math.floor(tonumber(partySize) or 1), 1, 4)
	local target = math.max(1, math.floor(tonumber(remainingTarget or definition.Target) or 1))
	local profileName = tostring(definition.SpawnProfile or "")
	local builder = PROFILE_BUILDERS[profileName]
	assert(builder, "SpawnProfile desconhecido: " .. profileName)
	local plan = builder(target, partySize)
	plan.ProfileName = profileName
	plan.ObjectiveId = definition.Id
	plan.GlobalIslandIndex = definition.GlobalIslandIndex
	plan.RoundIndex = definition.RoundIndex
	plan.PartySize = partySize
	plan.RequiredProgressTarget = target
	plan.MaxAlive = math.max(1, math.floor(tonumber(plan.MaxAlive) or 6))
	return plan
end

function EncounterCatalog.Validate()
	for _, profileName in ipairs({
		"FirstStrike",
		"CommonWave",
		"RewardWave01",
		"SkyAmbush",
		"RangedThreat",
		"NestPair",
		"RewardWave02",
		"GuardLine",
		"BeaconDefense",
		"NestCluster",
		"EliteHunt",
		"FinalRewardWave",
	}) do
		assert(type(PROFILE_BUILDERS[profileName]) == "function", "Perfil ausente: " .. profileName)
	end
	return true
end

EncounterCatalog.Validate()

return table.freeze(EncounterCatalog)
