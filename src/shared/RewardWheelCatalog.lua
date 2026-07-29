-- Configuracao compartilhada da roleta de recompensas.
-- Os pesos nao precisam somar 100; o sistema normaliza automaticamente.

local Catalog = {}

Catalog.UiProtocolVersion = 3
Catalog.CompactUiMode = "CompactCorner"
Catalog.AnimationDuration = 3.6
Catalog.WheelSlotCount = 10
Catalog.MinimumFullRotations = 5
Catalog.MaximumFullRotations = 7
-- Todas as moedas concedidas pela roleta, inclusive compensacoes por repetidos.
Catalog.CoinPayoutMultiplier = 0.40
Catalog.DuplicateCompensationRatio = 0.10
Catalog.MinimumDuplicateCompensation = 20
Catalog.SpinAgainSources = table.freeze({
	Boss = true,
	RareChest = true,
})

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
		UiMode = Catalog.CompactUiMode,
		CategoryWeights = table.freeze({
			Coins = 84,
			Relic = 7,
			Sword = 4,
			Companion = 5,
		}),
		CoinMinimum = 20,
		CoinMaximum = 50,
		CoinPerLevel = 5,
	}),
	RareChest = table.freeze({
		DisplayName = "Baú raro",
		CategoryWeights = table.freeze({
			Coins = 72,
			Relic = 11,
			Sword = 7,
			Companion = 10,
		}),
		CoinMinimum = 70,
		CoinMaximum = 160,
		CoinPerLevel = 8,
	}),
	Boss = table.freeze({
		DisplayName = "Boss derrotado",
		CategoryWeights = table.freeze({
			Coins = 60,
			Relic = 15,
			Sword = 10,
			Companion = 15,
		}),
		CoinMinimum = 140,
		CoinMaximum = 300,
		CoinPerLevel = 12,
	}),
	PaidSpin = table.freeze({
		DisplayName = "Giro comprado",
		-- Estas probabilidades precisam permanecer iguais ao texto mostrado
		-- antes da compra em MonetizationCatalog.
		CategoryWeights = table.freeze({
			Coins = 75,
			Relic = 15,
			Sword = 10,
			Companion = 0,
		}),
		CoinMinimum = 80,
		CoinMaximum = 180,
		CoinPerLevel = 6,
	}),
	RewardedAd = table.freeze({
		DisplayName = "Giro por anuncio",
		CategoryWeights = table.freeze({
			Coins = 90,
			Relic = 7,
			Sword = 3,
			Companion = 0,
		}),
		CoinMinimum = 50,
		CoinMaximum = 120,
		CoinPerLevel = 4,
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
	}),
})

function Catalog.GetSource(sourceId)
	return Catalog.Sources[sourceId]
end

function Catalog.GetCategoryInfo(category)
	return Catalog.CategoryInfo[category]
end

function Catalog.IsSpinAgainSource(sourceId)
	return Catalog.SpinAgainSources[sourceId] == true
end

return table.freeze(Catalog)
