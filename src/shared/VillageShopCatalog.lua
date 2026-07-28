-- ReplicatedStorage/VillageShopCatalog
-- Profissoes originais das vilas e o Mercador do Ceu das ilhas normais.

local Catalog = {}

-- Somente estes NPCs participam da populacao das vilas/santuarios.
local VILLAGE_SHOP_ORDER = {
	"Blacksmith",
	"RelicDealer",
	"Healer",
	"Explorer",
}

local SHOPS = {
	Blacksmith = {
		ShopId = "Blacksmith",
		DisplayName = "Ferreiro",
		Label = "⚔️ FERREIRO",
		Color = Color3.fromRGB(235, 155, 72),
		Items = {
			{ ItemId = "ClassicSword", ItemType = "Sword" },
			{ ItemId = "BronzeSword", ItemType = "Sword" },
			{ ItemId = "CrystalSword", ItemType = "Sword" },
			{ ItemId = "VoidSword", ItemType = "Sword" },
			{ ItemId = "RoyalSword", ItemType = "Sword" },
			{ ItemId = "DragonSword", ItemType = "Sword" },
		},
	},
	RelicDealer = {
		ShopId = "RelicDealer",
		DisplayName = "Mercador de Reliquias",
		Label = "✨ RELIQUIAS",
		Color = Color3.fromRGB(184, 102, 255),
		Items = {
			{ ItemId = "LightningRelic", ItemType = "Relic" },
			{ ItemId = "FireRelic", ItemType = "Relic" },
			{ ItemId = "IceRelic", ItemType = "Relic" },
			{ ItemId = "StoneRelic", ItemType = "Relic" },
		},
	},
	Healer = {
		ShopId = "Healer",
		DisplayName = "Curandeira",
		Label = "❤️ CURANDEIRA",
		Color = Color3.fromRGB(94, 225, 151),
		Items = {
			{ ItemId = "HealthPotion", ItemType = "Item" },
			{ ItemId = "GreaterHealthPotion", ItemType = "Item" },
			{
				ItemId = "FullHeal",
				ItemType = "Service",
				Effect = "Heal",
				DisplayName = "Cura Restauradora",
				Description = "Recupera ate 60 pontos de vida.",
				StatsText = "+60 de vida nesta tentativa",
				Price = 45,
				Amount = 60,
				Color = Color3.fromRGB(90, 235, 135),
			},
			{
				ItemId = "VitalityTraining",
				ItemType = "Service",
				Effect = "Vitality",
				DisplayName = "Bencao de Vitalidade",
				Description = "Aumenta a vida maxima e tambem cura.",
				StatsText = "+20 de vida maxima (limite 180)",
				Price = 180,
				Amount = 20,
				Maximum = 180,
				Color = Color3.fromRGB(245, 105, 125),
			},
		},
	},
	Explorer = {
		ShopId = "Explorer",
		DisplayName = "Explorador",
		Label = "🧭 EXPLORADOR",
		Color = Color3.fromRGB(83, 196, 240),
		Items = {
			{ ItemId = "SpeedTonic", ItemType = "Item" },
			{ ItemId = "JumpTonic", ItemType = "Item" },
			{
				ItemId = "SpeedTraining",
				ItemType = "Service",
				Effect = "Speed",
				DisplayName = "Treino de Agilidade",
				Description = "Aumenta a velocidade durante esta vida.",
				StatsText = "+2 de velocidade (limite 24)",
				Price = 120,
				Amount = 2,
				Maximum = 24,
				Color = Color3.fromRGB(70, 220, 210),
			},
			{
				ItemId = "JumpTraining",
				ItemType = "Service",
				Effect = "Jump",
				DisplayName = "Treino de Salto",
				Description = "Melhora o salto durante esta vida.",
				StatsText = "+5 JumpPower ou +1.25 JumpHeight",
				Price = 120,
				Amount = 5,
				HeightAmount = 1.25,
				Maximum = 65,
				HeightMaximum = 10,
				Color = Color3.fromRGB(250, 181, 70),
			},
		},
	},
}

-- O Mercador do Ceu fica fora de VILLAGE_SHOP_ORDER de proposito. Ele usa o
-- algoritmo de comerciante solitario nas ilhas normais, nunca substitui a
-- populacao original dos santuarios e apresenta somente o catalogo narrativo
-- de monetizacao. Itens por moedas continuam pertencendo aos NPCs da vila.
SHOPS.SkyMerchant = {
	ShopId = "SkyMerchant",
	DisplayName = "Mercador do Ceu",
	Label = "MERCADOR DO CEU",
	Color = Color3.fromRGB(104, 205, 255),
	IncludesPremiumStore = true,
	Items = {},
}

function Catalog.GetShop(shopId)
	return SHOPS[shopId]
end

function Catalog.GetShopIds()
	return table.clone(VILLAGE_SHOP_ORDER)
end

function Catalog.GetSkyMerchantShopId()
	return "SkyMerchant"
end

function Catalog.FindItem(shopId, itemId, itemType)
	local shop = SHOPS[shopId]
	if not shop then
		return nil
	end
	for _, item in ipairs(shop.Items) do
		if item.ItemId == itemId and (itemType == nil or item.ItemType == itemType) then
			return item
		end
	end
	return nil
end

return table.freeze(Catalog)
