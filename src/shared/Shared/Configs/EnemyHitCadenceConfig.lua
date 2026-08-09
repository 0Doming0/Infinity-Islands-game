--[[
	Infinity Islands - Task 23
	EnemyHitCadenceConfig V1

	Central fairness layer for enemy -> player damage.

	The SlimeController already owns attack wind-up.
	This config prevents unfair multi-hit burst AFTER those attack wind-ups.

	Important:
	- first valid hit is not delayed;
	- damage amount is not reduced;
	- mob HP/damage scaling is unchanged;
	- this only limits how densely accepted hits can stack.
]]

local Config = {}

Config.Version = "EnemyHitCadenceV1"
Config.Policy = "CentralPlayerDamageCadence"

-- Different enemies/sources cannot all damage the same player in the exact
-- same instant. 0.35s still allows combat to feel active.
Config.GlobalHitIFrameSeconds = 0.35

-- Repeated hits of the same source need at least this interval.
Config.SourceIntervals = table.freeze({
	SlimeMelee = 0.75,
	SlimeProjectile = 0.55,
	SlimeArea = 0.90,
	FireSlimeGround = 0.65,
	LightningSlimeDash = 0.85,
	GoldenSlime = 0.75,
})

Config.DefaultSourceIntervalSeconds = 0.55

Config.MinimumIntervalSeconds = 0.15
Config.MaximumIntervalSeconds = 1.50

-- Keep diagnostics focused on the same early retention window used by Tasks
-- 17 and 22.
Config.TelemetryWindowSeconds = 90

function Config.GetSourceInterval(source)
	local sourceName =
		tostring(source or "Enemy")

	local requested =
		Config.SourceIntervals[sourceName]
			or Config.DefaultSourceIntervalSeconds

	return math.clamp(
		tonumber(requested)
			or Config.DefaultSourceIntervalSeconds,
		Config.MinimumIntervalSeconds,
		Config.MaximumIntervalSeconds
	)
end

return table.freeze(Config)
