-- O MVP usa um unico tipo de NPC: o Mercador do Ceu.
-- Ele concentra equipamentos, consumiveis, servicos, recompensas gratuitas
-- e o acesso voluntario a loja premium.

local Catalog = {}

local SHOP_ORDER = table.freeze({ "SkyMerchant" })

local ITEMS = table.freeze({
	table.freeze({ ItemId = "ClassicSword", ItemType = "Sword" }),
	table.freeze({ ItemId = "BronzeSword", ItemType = "Sword" }),
	table.freeze({ ItemId = "CrystalSword", ItemType = "Sword" }),
	table.freeze({ ItemId = "VoidSword", ItemType = "Sword" }),
	table.freeze({ ItemId = "RoyalSword", ItemType = "Sword" }),
	table.freeze({ ItemId = "DragonSword", ItemType = "Sword" }),
	table.freeze({ ItemId = "LightningRelic", ItemType = "Relic" }),
	table.freeze({ ItemId = "FireRelic", ItemType = "Relic" }),
	table.freeze({ ItemId = "IceRelic", ItemType = "Relic" }),
	table.freeze({ ItemId = "StoneRelic", ItemType = "Relic" }),
	table.freeze({ ItemId = "HealthPotion", ItemType = "Item" }),
	table.freeze({ ItemId = "GreaterHealthPotion", ItemType = "Item" }),
	table.freeze({ ItemId = "SpeedTonic", ItemType = "Item" }),
	table.freeze({ ItemId = "JumpTonic", ItemType = "Item" }),
	table.freeze({
		ItemId = "FullHeal",
		ItemType = "Service",
		Effect = "Heal",
		DisplayName = "Cura Restauradora",
		Description = "Recupera ate 60 pontos de vida.",
		StatsText = "+60 de vida nesta tentativa",
		Price = 45,
		Amount = 60,
		Color = Color3.fromRGB(90, 235, 135),
	}),
	table.freeze({
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
	}),
	table.freeze({
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
	}),
	table.freeze({
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
	}),
})

local SKY_MERCHANT = table.freeze({
	ShopId = "SkyMerchant",
	DisplayName = "Mercador do Ceu",
	Label = "MERCADOR DO CEU",
	Color = Color3.fromRGB(104, 205, 255),
	IncludesRewards = true,
	IncludesPremiumStore = true,
	Items = ITEMS,
})

function Catalog.GetShop(shopId)
	-- Modelos antigos no Studio tambem passam a usar o catalogo consolidado.
	return shopId == nil and SKY_MERCHANT or SKY_MERCHANT
end

function Catalog.GetShopIds()
	return table.clone(SHOP_ORDER)
end

function Catalog.FindItem(_, itemId, itemType)
	for _, item in ipairs(ITEMS) do
		if item.ItemId == itemId and (itemType == nil or item.ItemType == itemType) then
			return item
		end
	end
	return nil
end

return table.freeze(Catalog)
