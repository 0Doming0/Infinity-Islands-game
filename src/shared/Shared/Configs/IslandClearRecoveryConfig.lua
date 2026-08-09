--[[
	Infinity Islands - Task 28
	IslandClearRecoveryConfig V1

	No shop / potions / merchant are required for the current MVP.

	To avoid inevitable attrition across a long linear run, clearing a Combat
	Island restores a fraction of MISSING health.

	This keeps damage meaningful:
	- it is not a full heal;
	- it does not raise MaxHealth;
	- dead/downed players are not revived;
	- only players who are actually on the cleared island receive it.
]]

local Config = {}

Config.Version = "IslandClearRecoveryV1"
Config.Policy = "RecoverMissingHealthOnClear"

Config.MissingHealthRecoveryFraction = 0.35

-- If enough health is missing, guarantee a small perceptible recovery.
Config.MinimumRecoveryFractionOfMaxHealth = 0.08

Config.MinimumHealthToRecover = 1

Config.TelemetryWindowSeconds = 90

function Config.GetRecoveryAmount(
	currentHealth,
	maxHealth
)
	currentHealth =
		math.max(
			0,
			tonumber(currentHealth) or 0
		)

	maxHealth =
		math.max(
			1,
			tonumber(maxHealth) or 1
		)

	local missing =
		math.max(
			0,
			maxHealth - currentHealth
		)

	if missing <= 0 then
		return 0
	end

	local desired =
		missing
			* Config
				.MissingHealthRecoveryFraction

	local minimum =
		maxHealth
			* Config
				.MinimumRecoveryFractionOfMaxHealth

	return math.min(
		missing,
		math.max(
			desired,
			minimum
		)
	)
end

return table.freeze(Config)
