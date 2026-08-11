--[[
	Infinity Islands - MobXPConfig V2

	XP value calculation remains the same as V1.

	New delivery policy:
	- killing a managed combat mob does NOT immediately increase XP;
	- only the last hitter receives the physical XP fragments;
	- fragments scatter, then magnet toward that player;
	- PlayerLevelService receives XP only as fragments are collected.
]]

local MobXPConfig = {}

MobXPConfig.Version = "MobXPV2Collectibles"
MobXPConfig.AwardPolicy = "LastHitPhysicalXPCollectiblesV1"

MobXPConfig.LevelRewardPerLevel = 0.12

MobXPConfig.RiskBonusPerLevel = 0.10
MobXPConfig.MaximumRiskBonus = 0.50

MobXPConfig.MinimumReward = 1
MobXPConfig.MaximumRewardPerMob = 10000

MobXPConfig.BaseXPByVariant = table.freeze({
	Green = 12,
	Blue = 16,
	Red = 20,
	Fire = 22,
	Ice = 22,
	Lightning = 26,
})

MobXPConfig.DefaultBaseXP = 12

local function cleanLevel(value)
	return math.max(
		1,
		math.floor(tonumber(value) or 1)
	)
end

function MobXPConfig.GetBaseXP(variant)
	return math.max(
		MobXPConfig.MinimumReward,
		math.floor(
			tonumber(
				MobXPConfig.BaseXPByVariant[
					tostring(variant or "")
				]
			)
				or MobXPConfig.DefaultBaseXP
		)
	)
end

function MobXPConfig.GetLevelMultiplier(mobLevel)
	local level = cleanLevel(mobLevel)

	return 1
		+ MobXPConfig.LevelRewardPerLevel
			* (level - 1)
end

function MobXPConfig.GetMobXPReward(
	variant,
	mobLevel
)
	local reward =
		MobXPConfig.GetBaseXP(variant)
			* MobXPConfig.GetLevelMultiplier(
				mobLevel
			)

	return math.clamp(
		math.floor(reward + 0.5),
		MobXPConfig.MinimumReward,
		MobXPConfig.MaximumRewardPerMob
	)
end

function MobXPConfig.GetRiskBonus(
	mobLevel,
	playerLevel
)
	local difference =
		cleanLevel(mobLevel)
			- cleanLevel(playerLevel)

	if difference <= 0 then
		return 0
	end

	return math.min(
		MobXPConfig.MaximumRiskBonus,
		difference
			* MobXPConfig.RiskBonusPerLevel
	)
end

function MobXPConfig.GetAwardForPlayer(
	mobXPReward,
	mobLevel,
	playerLevel
)
	local base =
		math.clamp(
			math.floor(
				tonumber(mobXPReward)
					or MobXPConfig.MinimumReward
			),
			MobXPConfig.MinimumReward,
			MobXPConfig.MaximumRewardPerMob
		)

	local riskBonus =
		MobXPConfig.GetRiskBonus(
			mobLevel,
			playerLevel
		)

	local amount =
		math.floor(
			base * (1 + riskBonus) + 0.5
		)

	return math.clamp(
		amount,
		MobXPConfig.MinimumReward,
		MobXPConfig.MaximumRewardPerMob
	),
		riskBonus
end

function MobXPConfig.Validate()
	assert(
		MobXPConfig.GetMobXPReward(
			"Green",
			1
		) == 12,
		"Green L1 precisa valer 12 XP"
	)

	assert(
		MobXPConfig.GetMobXPReward(
			"Blue",
			1
		) == 16,
		"Blue L1 precisa valer 16 XP"
	)

	assert(
		math.abs(
			MobXPConfig.GetRiskBonus(6, 3)
				- 0.30
		) < 0.0001,
		"3 niveis acima precisa dar +30%"
	)

	assert(
		math.abs(
			MobXPConfig.GetRiskBonus(20, 1)
				- 0.50
		) < 0.0001,
		"Risk bonus precisa respeitar cap +50%"
	)

	return true
end

MobXPConfig.Validate()

return table.freeze(MobXPConfig)
