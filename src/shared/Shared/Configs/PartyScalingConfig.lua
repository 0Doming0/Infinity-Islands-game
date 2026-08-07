local enemyProfiles = table.freeze({
	[1] = table.freeze({
		Health = 0.82,
		Damage = 0.72,
		MaxAlive = 0.78,
		WaveDelay = 1.15,
		NestHealth = 0.78,
		NestSpawnInterval = 1.20,
		ContinuousInterval = 1.18,
	}),
	[2] = table.freeze({
		Health = 1.00,
		Damage = 0.82,
		MaxAlive = 0.92,
		WaveDelay = 1.05,
		NestHealth = 1.00,
		NestSpawnInterval = 1.08,
		ContinuousInterval = 1.08,
	}),
	[3] = table.freeze({
		Health = 1.18,
		Damage = 0.90,
		MaxAlive = 1.00,
		WaveDelay = 0.97,
		NestHealth = 1.15,
		NestSpawnInterval = 0.97,
		ContinuousInterval = 0.96,
	}),
	[4] = table.freeze({
		Health = 1.34,
		Damage = 0.98,
		MaxAlive = 1.08,
		WaveDelay = 0.90,
		NestHealth = 1.28,
		NestSpawnInterval = 0.90,
		ContinuousInterval = 0.88,
	}),
})

return table.freeze({
	Version = 2,
	MaximumPartySize = 4,

	-- Mantidos para compatibilidade com consumidores antigos.
	EnemyHealthPerAdditionalPlayer = 0.18,
	EnemyDamagePerAdditionalPlayer = 0.06,
	BossHealthPerAdditionalPlayer = 0.50,
	BossDamagePerAdditionalPlayer = 0.10,

	EnemyProfiles = enemyProfiles,
})
