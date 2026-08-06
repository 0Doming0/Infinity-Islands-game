return table.freeze({
	GiantBoss = table.freeze({
		DisplayName = "Rei Slime Colossal",
		BaseHealth = 3200,
		BaseDamage = 20,
		WalkSpeed = 10,
		AttackRange = 11,
		AttackCooldown = 2.4,
		DetectionRange = 180,
		ActivationDelay = 2.5,
		ArenaRescueDepth = 24,
		ArenaRescueProtection = 3,
		PhaseThresholds = table.freeze({ 0.66, 0.33 }),
		PhaseAttackCooldowns = table.freeze({ 2.4, 2.05, 1.7 }),
		LeapSlam = table.freeze({
			Windup = 0.9,
			Radius = 12,
			DamageMultiplier = 1.15,
		}),
		GroundPulse = table.freeze({
			Windup = 0.75,
			Radius = 14,
			DamageMultiplier = 0.85,
		}),
		Shockwave = table.freeze({
			Windup = 1.05,
			Radius = 24,
			InnerSafeRadius = 7,
			DamageMultiplier = 1,
		}),
		Summon = table.freeze({
			Windup = 0.8,
			BaseCount = 2,
			MaximumAlive = 5,
			HealthMultiplier = 0.75,
			DamageMultiplier = 0.8,
		}),
	}),
})
