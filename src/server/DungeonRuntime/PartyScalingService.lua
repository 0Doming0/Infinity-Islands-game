local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage.Shared.Configs.PartyScalingConfig)

local PartyScalingService = {}

function PartyScalingService.GetMultipliers(partySize, isBoss)
	local size = math.clamp(math.floor(tonumber(partySize) or 1), 1, config.MaximumPartySize)
	local additional = size - 1
	return {
		Health = 1 + additional * (
			isBoss and config.BossHealthPerAdditionalPlayer
				or config.EnemyHealthPerAdditionalPlayer
		),
		Damage = 1 + additional * (
			isBoss and config.BossDamagePerAdditionalPlayer
				or config.EnemyDamagePerAdditionalPlayer
		),
	}
end

function PartyScalingService.ScaleValues(health, damage, partySize, isBoss)
	local multipliers = PartyScalingService.GetMultipliers(partySize, isBoss)
	return math.max(1, math.floor(health * multipliers.Health + 0.5)),
		math.max(0, math.floor(damage * multipliers.Damage + 0.5)),
		multipliers
end

function PartyScalingService.MarkApplied(model, partySize, multipliers)
	if model:GetAttribute("PartyScalingApplied") == true then
		return false
	end
	model:SetAttribute("PartyScalingApplied", true)
	model:SetAttribute("InitialPartySize", partySize)
	model:SetAttribute("PartyHealthMultiplier", multipliers.Health)
	model:SetAttribute("PartyDamageMultiplier", multipliers.Damage)
	return true
end

return PartyScalingService
