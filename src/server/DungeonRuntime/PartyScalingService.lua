local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage.Shared.Configs.PartyScalingConfig)

local PartyScalingService = {}

local function normalizedPartySize(partySize)
	return math.clamp(
		math.floor(tonumber(partySize) or 1),
		1,
		config.MaximumPartySize
	)
end

local function enemyProfile(partySize)
	local size = normalizedPartySize(partySize)
	local profile = config.EnemyProfiles and config.EnemyProfiles[size]
	if profile then
		return profile, size
	end
	local additional = size - 1
	return {
		Health = 1 + additional * config.EnemyHealthPerAdditionalPlayer,
		Damage = 1 + additional * config.EnemyDamagePerAdditionalPlayer,
		MaxAlive = 1,
		WaveDelay = 1,
		NestHealth = 1,
		NestSpawnInterval = 1,
		ContinuousInterval = 1,
	}, size
end

function PartyScalingService.GetMultipliers(partySize, isBoss)
	local size = normalizedPartySize(partySize)
	if isBoss then
		local additional = size - 1
		return {
			Health = 1 + additional * config.BossHealthPerAdditionalPlayer,
			Damage = 1 + additional * config.BossDamagePerAdditionalPlayer,
		}
	end
	local profile = enemyProfile(size)
	return {
		Health = profile.Health,
		Damage = profile.Damage,
	}
end

function PartyScalingService.GetEncounterMultipliers(partySize)
	local profile, size = enemyProfile(partySize)
	return {
		PartySize = size,
		Health = profile.Health,
		Damage = profile.Damage,
		MaxAlive = profile.MaxAlive,
		WaveDelay = profile.WaveDelay,
		NestHealth = profile.NestHealth,
		NestSpawnInterval = profile.NestSpawnInterval,
		ContinuousInterval = profile.ContinuousInterval,
	}
end

function PartyScalingService.ScaleValues(health, damage, partySize, isBoss)
	local multipliers = PartyScalingService.GetMultipliers(partySize, isBoss)
	return math.max(1, math.floor(health * multipliers.Health + 0.5)),
		math.max(0, math.floor(damage * multipliers.Damage + 0.5)),
		multipliers
end

function PartyScalingService.ScaleEncounterMaxAlive(baseAmount, partySize, minimum, maximum)
	local profile = PartyScalingService.GetEncounterMultipliers(partySize)
	local value = math.floor(math.max(1, tonumber(baseAmount) or 1) * profile.MaxAlive + 0.5)
	return math.clamp(
		value,
		math.max(1, math.floor(tonumber(minimum) or 1)),
		math.max(1, math.floor(tonumber(maximum) or value))
	)
end

function PartyScalingService.ScaleWaveDelay(seconds, partySize)
	local profile = PartyScalingService.GetEncounterMultipliers(partySize)
	return math.max(0, (tonumber(seconds) or 0) * profile.WaveDelay)
end

function PartyScalingService.ScaleNestHealth(health, partySize)
	local profile = PartyScalingService.GetEncounterMultipliers(partySize)
	return math.max(1, math.floor((tonumber(health) or 1) * profile.NestHealth + 0.5))
end

function PartyScalingService.ScaleNestSpawnInterval(seconds, partySize)
	local profile = PartyScalingService.GetEncounterMultipliers(partySize)
	return math.max(2, (tonumber(seconds) or 2) * profile.NestSpawnInterval)
end

function PartyScalingService.ScaleContinuousInterval(seconds, partySize)
	local profile = PartyScalingService.GetEncounterMultipliers(partySize)
	return math.max(3, (tonumber(seconds) or 3) * profile.ContinuousInterval)
end

function PartyScalingService.MarkApplied(model, partySize, multipliers)
	if model:GetAttribute("PartyScalingApplied") == true then
		return false
	end
	model:SetAttribute("PartyScalingApplied", true)
	model:SetAttribute("PartyBalanceVersion", config.Version or 1)
	model:SetAttribute("InitialPartySize", normalizedPartySize(partySize))
	model:SetAttribute("PartyHealthMultiplier", multipliers.Health)
	model:SetAttribute("PartyDamageMultiplier", multipliers.Damage)
	return true
end

return PartyScalingService
