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
		MerchantPitch = table.freeze({
			Opening = "Antes de comprar asas de verdade, experimente o vento.",
			Story = "Encontrei estas penas nas bordas das ilhas mais altas. Elas ainda guardam tres impulsos de voo, o bastante para sentir como e atravessar o vazio sem depender apenas de um salto.",
			Offer = "Normalmente guardo essas cargas para viajantes experientes, mas deixei este teste separado para voce.",
			CTA = "EXPERIMENTAR 3 VOOS",
			HeroFallback = "ASAS",
		}),
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
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Eu vi ate onde voce conseguiu chegar.",
			Story = "As Asas Azure foram tecidas com penas encontradas acima das nuvens baixas. Elas nao vencem a subida por voce, mas transformam saltos impossiveis em novas rotas.",
			Offer = "Eu costumava reservar estas asas para exploradores veteranos, mas esta oferta foi escolhida para a sua jornada.",
			CTA = "DESBLOQUEAR ASAS AZURE",
			HeroFallback = "AZURE",
		}),
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
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Poucos viajantes chegam prontos para carregar estas asas.",
			Story = "Dizem que as Asas Reais pertenciam aos guardioes das primeiras ilhas. Seu voo mais longo permite corrigir uma rota no ar e alcancar plataformas que parecem distantes demais.",
			Offer = "Eu costumava mostra-las apenas aos campeoes do ceu. Para voce, preparei uma oferta especial.",
			CTA = "DESBLOQUEAR ASAS REAIS",
			HeroFallback = "REAIS",
		}),
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
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Estas nao sao asas comuns. Elas lembram o caminho das estrelas.",
			Story = "As Asas Celestiais sao a joia mais rara da minha caravana. Nove segundos de voo horizontal fazem delas uma ferramenta para quem pretende dominar as rotas mais altas do Sky Dungeon.",
			Offer = "Eu costumava guarda-las para o fim de uma grande expedicao, mas reconheci em voce um viajante digno desta oferta.",
			CTA = "OBTER ASAS CELESTIAIS",
			HeroFallback = "CELESTIAIS",
		}),
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
		DisplayName = "Cacada de Elites",
		Description = "Por 20 minutos, a chance base de ilha Elite sobe de 12% para 21%. Cada Elite derrotado por voce tem 35% de recompensa extra de Bau Raro.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
		SuggestedRobux = 49,
		Context = "Elites",
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Ouvi dizer que um Elite ja caiu diante da sua espada.",
			Story = "Este selo provoca os guardioes mais perigosos do ceu. Por vinte minutos, mais ilhas Elite podem surgir e cada Elite derrotado por voce pode revelar uma recompensa rara adicional.",
			Offer = "Eu costumava entregar este selo apenas a cacadores juramentados. Hoje, a cacada pode ser sua.",
			CTA = "INICIAR CACADA DE ELITES",
			HeroFallback = "ELITES",
		}),
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
		PreviousRobux = nil,
		MerchantPitch = table.freeze({
			Opening = "Nem toda batalha precisa terminar com o ultimo golpe.",
			Story = "Esta capa foi costurada com fios retirados da sombra das ilhas. Quando ativada, os inimigos perdem seu rastro por oito segundos: tempo suficiente para escapar, curar ou escolher outro caminho.",
			Offer = "Eu costumava esconder esta peca dos viajantes impulsivos, mas ela pode ser exatamente a protecao que faltou a voce.",
			CTA = "DESBLOQUEAR A CAPA",
			HeroFallback = "CAPA",
		}),
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
		DisplayName = "Slot de Companheiro",
		Description = "Desbloqueia o proximo slot de companheiro, ate o limite de 4.",
		ProductType = "DeveloperProduct",
		ProductId = 0,
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
		ProductId = 0,
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
