-- Catalogo unico de monetizacao do MVP.
--
-- Todos os IDs ficam em um unico arquivo. Valores zero mantem a oferta
-- desativada ate que o produto ou passe seja criado no Creator Hub.
-- SuggestedRobux serve apenas como referencia de configuracao: a interface
-- sempre consulta o preco real/personalizado do Roblox no cliente.
--
-- MerchantPitch controla a apresentacao narrativa do Mercador do Ceu.
-- PreviousRobux deve permanecer nil ate existir um preco anterior verdadeiro
-- para o produto. A interface nunca inventa desconto nem risca um preco que
-- nao tenha sido praticado.

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
		ProductId = 3612123123,
		SuggestedRobux = 19,
		Context = "Death",
	}),
	TemporaryWings = table.freeze({
		Id = "TemporaryWings",
		DisplayName = "Asas temporarias",
		Description = "Receba 3 decolagens: suba rapidamente 8 studs e plane ate tocar o solo.",
		ProductType = "Coins",
		CoinPrice = 3000,
		Context = "Height",
		MerchantPitch = table.freeze({
			Opening = "Antes de comprar asas de verdade, experimente o vento.",
			Story = "Encontrei estas penas nas bordas das ilhas mais altas. Elas ainda guardam tres impulsos de voo, o bastante para sentir como e atravessar o vazio sem depender apenas de um salto.",
			Offer = "Normalmente guardo essas cargas para viajantes experientes, mas deixei este teste separado para voce.",
			CTA = "EXPERIMENTAR 3 VOOS",
			HeroFallback = "ASAS",
		}),
		Wing = table.freeze({
			StaminaSeconds = 3.5,
			StaminaRechargePerSecond = 2,
			HorizontalSpeed = 34,
			RiseHeight = 8,
			RiseVelocity = 26,
			RiseTimeout = 1.15,
			RiseHorizontalMultiplier = 0.68,
			GlideFallSpeed = 5,
			GlideSpeedMultiplier = 0.82,
			ExhaustedGlideFallSpeed = 9,
			ExhaustedGlideSpeedMultiplier = 0.32,
			Color = Color3.fromRGB(230, 239, 255),
		}),
		Asset = table.freeze({
			ModelName = "TemporaryWings",
			Aliases = table.freeze({ "Temporary Wings", "Asas Temporarias" }),
			AttachmentName = "BodyBackAttachment",
			FallbackOffset = CFrame.new(0, 0.25, 0.6),
			ModelOrientationOffset = CFrame.Angles(math.rad(90), 0, 0),
		}),
	}),
	AzureWings = table.freeze({
		Id = "AzureWings",
		DisplayName = "Sky Wings",
		Description = "Suba rapidamente 10 studs e plane devagar com 5 segundos de estamina.",
		ProductType = "GamePass",
		PassId = 1931112580,
		SuggestedRobux = 79,
		Context = "Height",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Eu vi ate onde voce conseguiu chegar.",
			Story = "As Sky Wings foram tecidas com penas encontradas acima das nuvens baixas. Elas nao vencem a subida por voce, mas transformam saltos impossiveis em novas rotas.",
			Offer = "Eu costumava reservar estas asas para exploradores veteranos, mas esta oferta foi escolhida para a sua jornada.",
			CTA = "DESBLOQUEAR SKY WINGS",
			HeroFallback = "SKY",
		}),
		Wing = table.freeze({
			StaminaSeconds = 5,
			StaminaRechargePerSecond = 2,
			HorizontalSpeed = 36,
			RiseHeight = 10,
			RiseVelocity = 28,
			RiseTimeout = 1.2,
			RiseHorizontalMultiplier = 0.7,
			GlideFallSpeed = 4.2,
			GlideSpeedMultiplier = 0.84,
			ExhaustedGlideFallSpeed = 8.5,
			ExhaustedGlideSpeedMultiplier = 0.34,
			Color = Color3.fromRGB(92, 205, 255),
		}),
		Asset = table.freeze({
			ModelName = "SkyWings",
			Aliases = table.freeze({ "Sky Wings" }),
			AttachmentName = "BodyBackAttachment",
			FallbackOffset = CFrame.new(0, 0.25, 0.6),
			ModelOrientationOffset = CFrame.Angles(math.rad(90), 0, 0),
		}),
	}),
	RoyalWings = table.freeze({
		Id = "RoyalWings",
		DisplayName = "Royal Wings",
		Description = "Suba rapidamente 14 studs e plane devagar com 7 segundos de estamina.",
		ProductType = "GamePass",
		PassId = 1931678317,
		SuggestedRobux = 149,
		Context = "Height",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Poucos viajantes chegam prontos para carregar estas asas.",
			Story = "Dizem que as Asas Reais pertenciam aos guardioes das primeiras ilhas. Seu voo mais longo permite corrigir uma rota no ar e alcancar plataformas que parecem distantes demais.",
			Offer = "Eu costumava mostra-las apenas aos campeoes do ceu. Para voce, preparei uma oferta especial.",
			CTA = "DESBLOQUEAR ASAS REAIS",
			HeroFallback = "REAIS",
		}),
		Wing = table.freeze({
			StaminaSeconds = 7,
			StaminaRechargePerSecond = 2,
			HorizontalSpeed = 38,
			RiseHeight = 14,
			RiseVelocity = 32,
			RiseTimeout = 1.3,
			RiseHorizontalMultiplier = 0.72,
			GlideFallSpeed = 3.4,
			GlideSpeedMultiplier = 0.88,
			ExhaustedGlideFallSpeed = 7.7,
			ExhaustedGlideSpeedMultiplier = 0.36,
			Color = Color3.fromRGB(178, 116, 255),
		}),
		Asset = table.freeze({
			ModelName = "RoyalWings",
			Aliases = table.freeze({ "Royal Wings" }),
			AttachmentName = "BodyBackAttachment",
			FallbackOffset = CFrame.new(0, 0.25, 0.6),
			ModelOrientationOffset = CFrame.Angles(math.rad(90), 0, 0),
		}),
	}),
	CelestialWings = table.freeze({
		Id = "CelestialWings",
		DisplayName = "Celestial Wings",
		Description = "Suba rapidamente 18 studs e plane lentamente com 9 segundos de estamina.",
		ProductType = "GamePass",
		PassId = 1927820291,
		SuggestedRobux = 249,
		Context = "Height",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Estas nao sao asas comuns. Elas lembram o caminho das estrelas.",
			Story = "As Asas Celestiais sao a joia mais rara da minha caravana. Sua estamina e seu planeio superior fazem delas uma ferramenta para quem pretende dominar as rotas mais altas do Sky Dungeon.",
			Offer = "Eu costumava guarda-las para o fim de uma grande expedicao, mas reconheci em voce um viajante digno desta oferta.",
			CTA = "OBTER ASAS CELESTIAIS",
			HeroFallback = "CELESTIAIS",
		}),
		Wing = table.freeze({
			StaminaSeconds = 9,
			StaminaRechargePerSecond = 2,
			HorizontalSpeed = 40,
			RiseHeight = 18,
			RiseVelocity = 36,
			RiseTimeout = 1.4,
			RiseHorizontalMultiplier = 0.74,
			GlideFallSpeed = 2.8,
			GlideSpeedMultiplier = 0.92,
			ExhaustedGlideFallSpeed = 7,
			ExhaustedGlideSpeedMultiplier = 0.38,
			Color = Color3.fromRGB(255, 219, 92),
		}),
		Asset = table.freeze({
			ModelName = "CelestialWings",
			Aliases = table.freeze({ "Celestial Wings" }),
			AttachmentName = "BodyBackAttachment",
			FallbackOffset = CFrame.new(0, 0.25, 0.6),
			ModelOrientationOffset = CFrame.Angles(math.rad(90), 0, 0),
		}),
	}),
	TreasureExpedition = table.freeze({
		Id = "TreasureExpedition",
		DisplayName = "Expedicao do Tesouro",
		Description = "Por 20 minutos, a chance base de Ilha do Tesouro sobe de 2% para 6% nas janelas elegiveis desta expedicao.",
		ProductType = "DeveloperProduct",
		ProductId = 3612123839,
		SuggestedRobux = 49,
		Context = "Chests",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Seus baus deixaram um rastro que poucos mercadores percebem.",
			Story = "Este mapa foi desenhado por saqueadores que seguiam o brilho entre as nuvens. Durante vinte minutos, ele triplica a chance base de surgirem Ilhas do Tesouro nas janelas elegiveis.",
			Offer = "Eu costumava vender cada rota a tripulacoes inteiras, mas separei esta expedicao especialmente para voce.",
			CTA = "ATIVAR ROTA DO TESOURO",
			HeroFallback = "TESOURO",
		}),
		PaidRandomItem = true,
		DurationSeconds = 20 * 60,
		ChanceMultiplier = 3,
	}),
	EliteExpedition = table.freeze({
		Id = "EliteExpedition",
		DisplayName = "Recompensa Elite em Dobro",
		Description = "Por 20 minutos, cada Elite derrotado por voce concede o dobro de pontos e moedas.",
		ProductType = "DeveloperProduct",
		ProductId = 3612124588,
		SuggestedRobux = 49,
		Context = "Elites",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Ouvi dizer que um Elite ja caiu diante da sua espada.",
			Story = "Este selo transforma cada vitoria contra um Elite em uma recompensa maior. Por vinte minutos, os pontos e as moedas de cada Elite derrotado por voce sao duplicados.",
			Offer = "Eu costumava entregar este selo apenas a cacadores juramentados. Hoje, a cacada pode ser sua.",
			CTA = "ATIVAR RECOMPENSA EM DOBRO",
			HeroFallback = "ELITES",
		}),
		DurationSeconds = 20 * 60,
		RewardMultiplier = 2,
		ChanceMultiplier = 1,
	}),
	InvisibilityCape = table.freeze({
		Id = "InvisibilityCape",
		DisplayName = "Shadow Cloak",
		Description = "Habilidade permanente: inimigos ignoram voce por 14 segundos. Recarga de 45 segundos.",
		ProductType = "GamePass",
		PassId = 1930770640,
		SuggestedRobux = 149,
		Context = "Combat",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Nem toda batalha precisa terminar com o ultimo golpe.",
			Story = "Esta capa foi costurada com fios retirados da sombra das ilhas. Quando ativada, os inimigos perdem seu rastro por quatorze segundos: tempo suficiente para escapar, curar ou escolher outro caminho.",
			Offer = "Eu costumava esconder esta peca dos viajantes impulsivos, mas ela pode ser exatamente a protecao que faltou a voce.",
			CTA = "DESBLOQUEAR A CAPA",
			HeroFallback = "CAPA",
		}),
		DurationSeconds = 14,
		CooldownSeconds = 45,
		Asset = table.freeze({
			ModelName = "ShadowCloak",
			Aliases = table.freeze({ "Shadow Cloak" }),
			AttachmentName = "BodyBackAttachment",
			FallbackOffset = CFrame.new(0, -0.55, 0.72),
		}),
	}),
	PermanentPotion = table.freeze({
		Id = "PermanentPotion",
		DisplayName = "Pocao Permanente",
		Description = "Beneficio permanente e nao acumulavel: +15 de vida maxima em cada tentativa.",
		ProductType = "GamePass",
		PassId = 0,
		-- Fora do catalogo visivel ate o passe ser criado. Para reativar,
		-- configure PassId e troque Enabled para true.
		Enabled = false,
		SuggestedRobux = 129,
		Context = "Healing",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Cada cicatriz ensina algo, mas algumas podem ser evitadas.",
			Story = "A formula desta pocao fortalece todas as suas proximas expedicoes. O efeito e permanente e concede quinze pontos de vida maxima sempre que uma nova tentativa comeca.",
			Offer = "Eu costumava preparar esta mistura apenas sob encomenda. Para voce, o frasco ja esta pronto.",
			CTA = "OBTER VIDA PERMANENTE",
			HeroFallback = "POCAO",
		}),
		MaxHealthBonus = 15,
	}),
	CompanionSlot = table.freeze({
		Id = "CompanionSlot",
		DisplayName = "Extra Companion Slot",
		Description = "Desbloqueia o proximo slot de companheiro, ate o limite de 4.",
		ProductType = "DeveloperProduct",
		ProductId = 3612136051,
		SuggestedRobux = 79,
		Context = "Companions",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Seus companheiros estao formando uma verdadeira equipe.",
			Story = "Este vinculo permite manter mais um companheiro equipado ao mesmo tempo, ate o limite de quatro. Uma nova vaga pode mudar completamente a formacao da sua expedicao.",
			Offer = "Eu costumava ensinar este vinculo apenas a mestres de criaturas, mas sua equipe ja pede mais espaco.",
			CTA = "LIBERAR MAIS 1 SLOT",
			HeroFallback = "COMPANHEIRO",
		}),
	}),
	PaidWheelSpin = table.freeze({
		Id = "PaidWheelSpin",
		DisplayName = "Giro da Roleta",
		Description = "Um giro aleatorio. Moedas 75%. Reliquias: Raio 3,846%, Fogo 3,846%, Gelo 3,462%, Pedra 3,846%. Espadas: Bronze 4,167%, Cristal 3,056%, Vazio 1,667%, Real 0,833%, Dragao 0,278%. Repetidos viram moedas.",
		ProductType = "DeveloperProduct",
		ProductId = 3612123366,
		SuggestedRobux = 19,
		Context = "Wheel",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "A roleta nunca conta a mesma historia duas vezes.",
			Story = "Este giro pode entregar moedas, reliquias ou espadas. Antes de decidir, confira as probabilidades completas: itens repetidos sao convertidos em moedas.",
			Offer = "Eu costumava guardar a ficha para o fim da feira, mas reservei um giro para voce.",
			CTA = "GIRAR A ROLETA",
			HeroFallback = "ROLETA",
		}),
		PaidRandomItem = true,
		OddsText = "Chances totais: moedas 75%, reliquia 15%, espada 10%.",
	}),
	SpinAgain = table.freeze({
		Id = "SpinAgain",
		DisplayName = "Girar novamente",
		Description = "Repete a roleta de Elite ou de Bau Raro usando as mesmas probabilidades da roleta original.",
		ProductType = "DeveloperProduct",
		ProductId = 3612124780,
		SuggestedRobux = 19,
		Context = "Wheel",
		PaidRandomItem = true,
		OddsText = "As probabilidades sao iguais as da roleta de Elite ou Bau Raro que originou a oferta.",
	}),
	RewardedAdWheel = table.freeze({
		Id = "RewardedAdWheel",
		DisplayName = "Giro por anuncio",
		Description = "Giro opcional apos assistir ao anuncio completo. Disponivel somente quando a experiencia for elegivel.",
		ProductType = "RewardedAd",
		ProductId = 0,
		Context = "Wheel",
		Enabled = false,
		MerchantPitch = table.freeze({
			Opening = "Uma pequena pausa pode render uma nova recompensa.",
			Story = "Quando esta experiencia estiver elegivel, voce podera assistir voluntariamente a um anuncio completo para receber um giro sem gastar Robux.",
			Offer = "Esta opcao aparecera somente quando estiver disponivel para sua conta e regiao.",
			CTA = "ASSISTIR E GIRAR",
			HeroFallback = "GIRO GRATIS",
		}),
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
