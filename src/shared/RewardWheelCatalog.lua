-- Configuracao compartilhada da roleta de recompensas.
-- Os pesos nao precisam somar 100; o sistema normaliza automaticamente.

local Catalog = {}

Catalog.AnimationDuration = 3.6
Catalog.WheelSlotCount = 10
Catalog.MinimumFullRotations = 5
Catalog.MaximumFullRotations = 7
Catalog.DuplicateCompensationRatio = 0.35
Catalog.MinimumDuplicateCompensation = 90

Catalog.CategoryInfo = table.freeze({
	Coins = table.freeze({
		DisplayName = "Moedas",
		Icon = "🪙",
		Color = Color3.fromRGB(255, 210, 72),
	}),
	Relic = table.freeze({
		DisplayName = "Relíquia",
		Icon = "🔮",
		Color = Color3.fromRGB(177, 105, 255),
	}),
	Sword = table.freeze({
		DisplayName = "Espada",
		Icon = "⚔",
		Color = Color3.fromRGB(105, 205, 255),
	}),
	Companion = table.freeze({
		DisplayName = "Companheiro",
		Icon = "🐾",
		Color = Color3.fromRGB(101, 232, 151),
	}),
})

Catalog.Sources = table.freeze({
	HeightLevel = table.freeze({
		DisplayName = "Nível de altura",
		CategoryWeights = table.freeze({
			Coins = 72,
			Relic = 14,
			Sword = 9,
			Companion = 5,
		}),
		CoinMinimum = 35,
		CoinMaximum = 90,
		CoinPerLevel = 8,
	}),
	RareChest = table.freeze({
		DisplayName = "Baú raro",
		CategoryWeights = table.freeze({
			Coins = 58,
			Relic = 20,
			Sword = 14,
			Companion = 8,
		}),
		CoinMinimum = 110,
		CoinMaximum = 260,
		CoinPerLevel = 12,
	}),
	Boss = table.freeze({
		DisplayName = "Boss derrotado",
		CategoryWeights = table.freeze({
			Coins = 45,
			Relic = 25,
			Sword = 18,
			Companion = 12,
		}),
		CoinMinimum = 220,
		CoinMaximum = 480,
		CoinPerLevel = 20,
	}),
})

-- Itens mais fortes possuem peso menor. ClassicSword nao participa porque
-- todos os jogadores ja a recebem ao iniciar.
Catalog.RewardPools = table.freeze({
	Relic = table.freeze({
		table.freeze({ Id = "LightningRelic", Weight = 10 }),
		table.freeze({ Id = "FireRelic", Weight = 10 }),
		table.freeze({ Id = "IceRelic", Weight = 9 }),
		table.freeze({ Id = "StoneRelic", Weight = 10 }),
	}),
	Sword = table.freeze({
		table.freeze({ Id = "BronzeSword", Weight = 30 }),
		table.freeze({ Id = "CrystalSword", Weight = 22 }),
		table.freeze({ Id = "VoidSword", Weight = 12 }),
		table.freeze({ Id = "RoyalSword", Weight = 6 }),
		table.freeze({ Id = "DragonSword", Weight = 2 }),
	}),
	Companion = table.freeze({
		table.freeze({ Id = "GreenSlime", DisplayName = "Slime Verde", Weight = 24 }),
		table.freeze({ Id = "BlueSlime", DisplayName = "Slime Azul", Weight = 20 }),
		table.freeze({ Id = "RedSlime", DisplayName = "Slime Vermelho", Weight = 16 }),
		table.freeze({ Id = "GoldenSlime", DisplayName = "Slime Dourado", Weight = 4 }),
		table.freeze({ Id = "Golem", DisplayName = "Golem", Weight = 9 }),
		table.freeze({ Id = "StoneGolem", DisplayName = "Golem de Pedra", Weight = 6 }),
	}),
})

function Catalog.GetSource(sourceId)
	return Catalog.Sources[sourceId]
end

function Catalog.GetCategoryInfo(category)
	return Catalog.CategoryInfo[category]
end

return table.freeze(Catalog)
