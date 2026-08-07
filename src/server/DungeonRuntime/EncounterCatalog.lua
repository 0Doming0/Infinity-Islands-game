local PartyScalingService = require(script.Parent.PartyScalingService)

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

local function scaledDelay(delaySeconds, partySize)
	return PartyScalingService.ScaleWaveDelay(delaySeconds, partySize)
end

local function wave(delaySeconds, enemies, waitForClear, partySize)
	return {
		DelaySeconds = scaledDelay(delaySeconds, partySize),
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

local function buildDefeatWaves(target, waveCount, rangedRatio, guardsPerWave, partySize)
	local amounts = distribute(target, waveCount)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(
			index == 1 and 0.25 or 0.8,
			mixedWave(amount, rangedRatio, math.min(amount, guardsPerWave or 0)),
			true,
			partySize
		))
	end
	return waves
end

local function maxAlive(raw, partySize, minimum, maximum)
	return PartyScalingService.ScaleEncounterMaxAlive(raw, partySize, minimum, maximum)
end

PROFILE_BUILDERS.FirstStrike = function(target, partySize)
	return {
		Mode = "Waves",
		Mechanic = "MarkedOpeningTarget",
		MaxAlive = maxAlive(2 + partySize, partySize, 2, 6),
		Waves = {
			wave(0.15, {
				copyEnemy("Common", math.max(2, partySize + 1), { SlimeVariant = "Green" }),
			}, false, partySize),
		},
	}
end

PROFILE_BUILDERS.CommonWave = function(target, partySize)
	return {
		Mode = "Waves",
		Mechanic = "OpenCombat",
		MaxAlive = maxAlive(4 + partySize, partySize, 3, 8),
		Waves = buildDefeatWaves(target, partySize >= 3 and 2 or 1, 0, 0, partySize),
	}
end

PROFILE_BUILDERS.RewardWave01 = function(target, partySize)
	return {
		Mode = "Waves",
		Mechanic = "EscalatingRewardWaves",
		MaxAlive = maxAlive(5 + partySize, partySize, 4, 9),
		Waves = buildDefeatWaves(target, 2, 0.2, 0, partySize),
	}
end

PROFILE_BUILDERS.SkyAmbush = function(target, partySize)
	return {
		Mode = "Waves",
		Mechanic = "HiddenPerimeterAmbush",
		AmbushRevealDelaySeconds = 0.85,
		MaxAlive = maxAlive(5 + partySize, partySize, 4, 9),
		SpawnFromPerimeter = true,
		Waves = buildDefeatWaves(target, 2, 0.25, 0, partySize),
	}
end

PROFILE_BUILDERS.RangedThreat = function(target, partySize)
	-- Solo recebe duas ondas menores para evitar tres projeteis simultaneos.
	local waveCount = partySize == 1 and 2 or (partySize >= 3 and 2 or 1)
	local amounts = distribute(target, waveCount)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(index == 1 and 0.2 or 0.75, {
			copyEnemy("Ranged", amount, { SlimeVariant = "Blue" }),
		}, true, partySize))
	end
	return {
		Mode = "Waves",
		Mechanic = "PriorityRangedTargets",
		MaxAlive = maxAlive(3 + partySize, partySize, 2, 7),
		Waves = waves,
	}
end

PROFILE_BUILDERS.NestPair = function(target, partySize)
	return {
		Mode = "Nests",
		Mechanic = "DestroySpawners",
		NestCount = target,
		NestHealth = PartyScalingService.ScaleNestHealth(70 + partySize * 20, partySize),
		NestSpawnInterval = PartyScalingService.ScaleNestSpawnInterval(
			math.max(6, 9 - partySize * 0.5),
			partySize
		),
		NestMonsterRole = "Common",
		NestMonsterVariant = "Green",
		MaxAlive = maxAlive(3 + partySize, partySize, 3, 7),
		OpeningWave = {
			copyEnemy("Common", math.max(1, partySize), { SlimeVariant = "Green" }),
		},
	}
end

PROFILE_BUILDERS.RewardWave02 = function(target, partySize)
	return {
		Mode = "Waves",
		Mechanic = "EscalatingRewardWaves",
		MaxAlive = maxAlive(6 + partySize, partySize, 5, 10),
		Waves = buildDefeatWaves(target, 2, 0.25, 1, partySize),
	}
end

PROFILE_BUILDERS.GuardLine = function(target, partySize)
	local amounts = distribute(target, partySize >= 3 and 2 or 1)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(index == 1 and 0.2 or 0.75, {
			copyEnemy("Guard", amount, {
				SlimeVariant = "Green",
				HealthMultiplier = partySize == 1 and 1.20 or 1.35,
				DamageMultiplier = partySize == 1 and 0.78 or 0.88,
			}),
		}, true, partySize))
	end
	return {
		Mode = "Waves",
		Mechanic = "BreakWardsThenGuards",
		GuardWardCount = 2,
		GuardWardHealth = 55 + partySize * 15,
		MaxAlive = maxAlive(2 + partySize, partySize, 2, 6),
		Waves = waves,
	}
end

PROFILE_BUILDERS.BeaconDefense = function(_, partySize)
	local waveAmount = partySize == 1 and 2 or math.clamp(2 + partySize, 3, 6)
	return {
		Mode = "Beacon",
		Mechanic = "HoldContestedZone",
		BeaconRadius = 13,
		MaxAlive = maxAlive(4 + partySize, partySize, 3, 8),
		ContinuousInterval = PartyScalingService.ScaleContinuousInterval(
			math.max(5, 7.5 - partySize * 0.5),
			partySize
		),
		ContinuousWave = mixedWave(waveAmount, 0.35, partySize >= 3 and 1 or 0),
		OpeningWave = mixedWave(waveAmount, 0.25, 0),
	}
end

PROFILE_BUILDERS.NestCluster = function(target, partySize)
	return {
		Mode = "Nests",
		Mechanic = "DestroySpawners",
		NestCount = target,
		NestHealth = PartyScalingService.ScaleNestHealth(90 + partySize * 24, partySize),
		NestSpawnInterval = PartyScalingService.ScaleNestSpawnInterval(
			math.max(5.5, 8.5 - partySize * 0.5),
			partySize
		),
		NestMonsterRole = "Common",
		NestMonsterVariant = partySize >= 3 and "Red" or "Green",
		MaxAlive = maxAlive(4 + partySize, partySize, 3, 8),
		OpeningWave = mixedWave(partySize == 1 and 1 or math.max(2, partySize), 0.25, 0),
	}
end

PROFILE_BUILDERS.EliteHunt = function(_, partySize)
	local supportCount = math.max(2, partySize)
	return {
		Mode = "Waves",
		Mechanic = "DefeatSupportsThenElite",
		EliteSupportCount = supportCount,
		MaxAlive = maxAlive(3 + partySize, partySize, 2, 7),
		Waves = {
			wave(0.3, {
				copyEnemy("Elite", 1, {
					SlimeVariant = partySize >= 3 and "Lightning" or "Red",
					IsElite = true,
					HealthMultiplier = partySize == 1 and 1.05 or 1.18,
					DamageMultiplier = partySize == 1 and 0.78 or 0.90,
				}),
				copyEnemy("Common", supportCount, { SlimeVariant = "Green" }),
			}, false, partySize),
		},
	}
end

PROFILE_BUILDERS.FinalRewardWave = function(target, partySize)
	return {
		Mode = "Waves",
		Mechanic = "EscalatingRewardWaves",
		MaxAlive = maxAlive(7 + partySize, partySize, 5, 11),
		Waves = buildDefeatWaves(target, 3, 0.3, 1, partySize),
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
	local balance = PartyScalingService.GetEncounterMultipliers(partySize)
	plan.ProfileName = profileName
	plan.ObjectiveId = definition.Id
	plan.GlobalIslandIndex = definition.GlobalIslandIndex
	plan.RoundIndex = definition.RoundIndex
	plan.PartySize = partySize
	plan.RequiredProgressTarget = target
	plan.Mechanic = tostring(plan.Mechanic or definition.GameplayIdentity or "StandardCombat")
	plan.MaxAlive = math.max(1, math.floor(tonumber(plan.MaxAlive) or 6))
	plan.PartyBalanceVersion = 2
	plan.Balance = balance

	workspace:SetAttribute("DungeonPartyBalanceVersion", 2)
	workspace:SetAttribute("DungeonEncounterBalancedPartySize", partySize)
	workspace:SetAttribute("DungeonEnemyHealthMultiplier", balance.Health)
	workspace:SetAttribute("DungeonEnemyDamageMultiplier", balance.Damage)
	workspace:SetAttribute("DungeonEncounterMaxAliveMultiplier", balance.MaxAlive)
	workspace:SetAttribute("DungeonEncounterWaveDelayMultiplier", balance.WaveDelay)
	workspace:SetAttribute("DungeonEncounterNestHealthMultiplier", balance.NestHealth)
	workspace:SetAttribute("DungeonEncounterNestIntervalMultiplier", balance.NestSpawnInterval)
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
