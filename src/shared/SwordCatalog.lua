-- ReplicatedStorage/SwordCatalog
-- Catalogo pequeno para o MVP. Se um modelo com o mesmo SwordId existir em
-- ServerStorage/MVPAssets/Swords, ele sera usado; caso contrario o servidor
-- cria uma Tool visual de exemplo por codigo.

local Catalog = {}

local ORDER = {
	"ClassicSword",
	"BronzeSword",
	"CrystalSword",
	"VoidSword",
	"RoyalSword",
	"DragonSword",
}

local DEFINITIONS = {
	ClassicSword = {
		SwordId = "ClassicSword",
		DisplayName = "Espada Classica",
		Description = "Espada inicial equilibrada.",
		Price = 0,
		BaseDamage = 20,
		AttackSpeed = 1.00,
		ScoreMultiplier = 1.00,
		KnockbackMultiplier = 1.00,
		Color = Color3.fromRGB(195, 205, 215),
		AccentColor = Color3.fromRGB(95, 65, 40),
		Material = Enum.Material.Metal,
	},
	BronzeSword = {
		SwordId = "BronzeSword",
		DisplayName = "Espada de Bronze",
		Description = "Mais dano sem sacrificar velocidade.",
		Price = 180,
		BaseDamage = 28,
		AttackSpeed = 1.06,
		ScoreMultiplier = 1.00,
		KnockbackMultiplier = 1.05,
		Color = Color3.fromRGB(185, 105, 55),
		AccentColor = Color3.fromRGB(92, 55, 30),
		Material = Enum.Material.Metal,
	},
	CrystalSword = {
		SwordId = "CrystalSword",
		DisplayName = "Espada de Cristal",
		Description = "Ataque rapido para inimigos resistentes.",
		Price = 650,
		BaseDamage = 42,
		AttackSpeed = 1.16,
		ScoreMultiplier = 1.00,
		KnockbackMultiplier = 1.18,
		Color = Color3.fromRGB(70, 205, 255),
		AccentColor = Color3.fromRGB(225, 250, 255),
		Material = Enum.Material.Neon,
	},
	VoidSword = {
		SwordId = "VoidSword",
		DisplayName = "Espada do Vazio",
		Description = "Arma rara encontrada nos comerciantes de reliquias.",
		Price = 1800,
		BaseDamage = 65,
		AttackSpeed = 1.25,
		ScoreMultiplier = 1.00,
		KnockbackMultiplier = 1.35,
		Color = Color3.fromRGB(115, 55, 205),
		AccentColor = Color3.fromRGB(235, 95, 255),
		Material = Enum.Material.Neon,
	},
	RoyalSword = {
		SwordId = "RoyalSword",
		DisplayName = "Espada Real",
		Description = "Equipamento caro para as partes altas da torre.",
		Price = 5000,
		BaseDamage = 82,
		AttackSpeed = 1.30,
		ScoreMultiplier = 1.00,
		KnockbackMultiplier = 1.42,
		Color = Color3.fromRGB(255, 218, 88),
		AccentColor = Color3.fromRGB(116, 70, 35),
		Material = Enum.Material.Metal,
	},
	DragonSword = {
		SwordId = "DragonSword",
		DisplayName = "Espada do Dragao",
		Description = "Objetivo de longo prazo do MVP.",
		Price = 12000,
		BaseDamage = 110,
		AttackSpeed = 1.36,
		ScoreMultiplier = 1.00,
		KnockbackMultiplier = 1.55,
		Color = Color3.fromRGB(245, 73, 44),
		AccentColor = Color3.fromRGB(62, 24, 22),
		Material = Enum.Material.Neon,
	},
}

function Catalog.Get(swordId)
	return DEFINITIONS[swordId]
end

function Catalog.GetStarterId()
	return ORDER[1]
end

function Catalog.GetOrderedIds()
	return table.clone(ORDER)
end

function Catalog.GetAll()
	local result = {}
	for _, swordId in ipairs(ORDER) do
		table.insert(result, DEFINITIONS[swordId])
	end
	return result
end

return table.freeze(Catalog)
