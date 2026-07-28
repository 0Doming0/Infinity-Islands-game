-- Catalogo unico de monetizacao do MVP.
--
-- Todos os IDs ficam em um unico arquivo. Valores zero mantem a oferta
-- desativada ate que o produto ou passe seja criado no Creator Hub.
-- SuggestedRobux serve apenas como referencia de configuracao: a interface
-- sempre consulta o preco real/personalizado do Roblox no cliente.

local Catalog = {}

Catalog.ProductOrder = table.freeze({
	"ReviveNoCoinLoss",
	"TemporaryWings",
	"AzureWings",
	"RoyalWings",
	"CelestialWings",
	"TreasureExpedition",
	"EliteExpedition",
	"InvisibilityCape",
	"PermanentPotion",
	"CompanionSlot",
	"PaidWheelSpin",
	"RewardedAdWheel",
})

Catalog.Products = table.freeze({
	ReviveNoCoinLoss = table.freeze({
		Id = "ReviveNoCoinLoss",
		DisplayName = "Renascimento seguro",
		Description = "Renasca sem perder as moedas desta derrota. A pontuacao da tentativa e encerrada.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
		SuggestedRobux = 19,
		Context = "Death",
	}),
	TemporaryWings = table.freeze({
		Id = "TemporaryWings",
		DisplayName = "Asas temporarias",
		Description = "Receba 3 voos curtos nesta sessao para experimentar as asas.",
		ProductType = "Coins",
		CoinPrice = 3000,
		Context = "Height",
		Wing = table.freeze({
			FlightSeconds = 3.5,
			CooldownSeconds = 45,
			HorizontalSpeed = 34,
			Color = Color3.fromRGB(230, 239, 255),
		}),
	}),
	AzureWings = table.freeze({
		Id = "AzureWings",
		DisplayName = "Asas Azure",
		Description = "Asas permanentes com voo horizontal de 5 segundos.",
		ProductType = "GamePass",
		PassId = 0,
		SuggestedRobux = 79,
		Context = "Height",
		Wing = table.freeze({
			FlightSeconds = 5,
			CooldownSeconds = 42,
			HorizontalSpeed = 36,
			Color = Color3.fromRGB(92, 205, 255),
		}),
	}),
	RoyalWings = table.freeze({
		Id = "RoyalWings",
		DisplayName = "Asas Reais",
		Description = "Asas permanentes com voo horizontal de 7 segundos.",
		ProductType = "GamePass",
		PassId = 0,
		SuggestedRobux = 149,
		Context = "Height",
		Wing = table.freeze({
			FlightSeconds = 7,
			CooldownSeconds = 38,
			HorizontalSpeed = 38,
			Color = Color3.fromRGB(178, 116, 255),
		}),
	}),
	CelestialWings = table.freeze({
		Id = "CelestialWings",
		DisplayName = "Asas Celestiais",
		Description = "Asas permanentes com voo horizontal de 9 segundos.",
		ProductType = "GamePass",
		PassId = 0,
		SuggestedRobux = 249,
		Context = "Height",
		Wing = table.freeze({
			FlightSeconds = 9,
			CooldownSeconds = 34,
			HorizontalSpeed = 40,
			Color = Color3.fromRGB(255, 219, 92),
		}),
	}),
	TreasureExpedition = table.freeze({
		Id = "TreasureExpedition",
		DisplayName = "Expedicao do Tesouro",
		Description = "Por 20 minutos, a chance base de Ilha do Tesouro sobe de 2% para 6% nas janelas elegiveis desta expedicao.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
		SuggestedRobux = 49,
		Context = "Chests",
		PaidRandomItem = true,
		DurationSeconds = 20 * 60,
		ChanceMultiplier = 3,
	}),
	EliteExpedition = table.freeze({
		Id = "EliteExpedition",
		DisplayName = "Cacada de Elites",
		Description = "Por 20 minutos, a chance base de ilha Elite sobe de 12% para 21%. Cada Elite derrotado por voce tem 35% de recompensa extra de Bau Raro.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
		SuggestedRobux = 49,
		Context = "Elites",
		PaidRandomItem = true,
		DurationSeconds = 20 * 60,
		ChanceMultiplier = 1.75,
		BonusRewardChance = 0.35,
	}),
	InvisibilityCape = table.freeze({
		Id = "InvisibilityCape",
		DisplayName = "Capa de Invisibilidade",
		Description = "Habilidade permanente: inimigos ignoram voce por 8 segundos. Recarga de 90 segundos.",
		ProductType = "GamePass",
		PassId = 0,
		SuggestedRobux = 149,
		Context = "Combat",
		DurationSeconds = 8,
		CooldownSeconds = 90,
	}),
	PermanentPotion = table.freeze({
		Id = "PermanentPotion",
		DisplayName = "Pocao Permanente",
		Description = "Beneficio permanente e nao acumulavel: +15 de vida maxima em cada tentativa.",
		ProductType = "GamePass",
		PassId = 0,
		SuggestedRobux = 129,
		Context = "Healing",
		MaxHealthBonus = 15,
	}),
	CompanionSlot = table.freeze({
		Id = "CompanionSlot",
		DisplayName = "Slot de Companheiro",
		Description = "Desbloqueia o proximo slot de companheiro, ate o limite de 4.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
		SuggestedRobux = 79,
		Context = "Companions",
	}),
	PaidWheelSpin = table.freeze({
		Id = "PaidWheelSpin",
		DisplayName = "Giro da Roleta",
		Description = "Um giro aleatorio. Moedas 75%. Reliquias: Raio 3,846%, Fogo 3,846%, Gelo 3,462%, Pedra 3,846%. Espadas: Bronze 4,167%, Cristal 3,056%, Vazio 1,667%, Real 0,833%, Dragao 0,278%. Repetidos viram moedas.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
		SuggestedRobux = 19,
		Context = "Wheel",
		PaidRandomItem = true,
		OddsText = "Chances totais: moedas 75%, reliquia 15%, espada 10%.",
	}),
	RewardedAdWheel = table.freeze({
		Id = "RewardedAdWheel",
		DisplayName = "Giro por anuncio",
		Description = "Giro opcional apos assistir ao anuncio completo. Disponivel somente quando a experiencia for elegivel.",
		ProductType = "RewardedAd",
		ProductId = 0,
		Context = "Wheel",
		Enabled = false,
		OddsText = "Moedas 90%  |  Reliquia 7%  |  Espada 3%",
	}),
})

function Catalog.Get(productId)
	return Catalog.Products[productId]
end

function Catalog.GetAll()
	local result = {}
	for _, productId in ipairs(Catalog.ProductOrder) do
		table.insert(result, Catalog.Products[productId])
	end
	return result
end

function Catalog.GetConfiguredAssetId(definition)
	if not definition then
		return 0
	end
	if definition.ProductType == "GamePass" then
		return math.max(0, math.floor(tonumber(definition.PassId) or 0))
	end
	if definition.ProductType == "DeveloperProduct" or definition.ProductType == "RewardedAd" then
		return math.max(0, math.floor(tonumber(definition.ProductId) or 0))
	end
	return definition.ProductType == "Coins" and 1 or 0
end

return table.freeze(Catalog)
