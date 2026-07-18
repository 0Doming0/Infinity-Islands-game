-- Itens empilhaveis do inventario. Modelos/Tools opcionais podem usar o mesmo
-- ItemId em ServerStorage/MVPAssets/Items; os efeitos continuam no servidor.

local Catalog = {}

local ORDER = {
	"HealthPotion",
	"GreaterHealthPotion",
	"SpeedTonic",
	"JumpTonic",
}

local ITEMS = {
	HealthPotion = {
		ItemId = "HealthPotion",
		DisplayName = "Pocao de Cura",
		Description = "Recupera 40 pontos de vida.",
		Effect = "Heal",
		Amount = 40,
		Price = 35,
		MaximumStack = 12,
		Color = Color3.fromRGB(226, 73, 92),
	},
	GreaterHealthPotion = {
		ItemId = "GreaterHealthPotion",
		DisplayName = "Pocao de Cura Grande",
		Description = "Recupera 80 pontos de vida.",
		Effect = "Heal",
		Amount = 80,
		Price = 80,
		MaximumStack = 8,
		Color = Color3.fromRGB(255, 105, 132),
	},
	SpeedTonic = {
		ItemId = "SpeedTonic",
		DisplayName = "Tonico de Velocidade",
		Description = "+4 de velocidade por 25 segundos.",
		Effect = "Speed",
		Amount = 4,
		Duration = 25,
		Price = 60,
		MaximumStack = 8,
		Color = Color3.fromRGB(68, 214, 212),
	},
	JumpTonic = {
		ItemId = "JumpTonic",
		DisplayName = "Tonico de Salto",
		Description = "Melhora o salto por 25 segundos.",
		Effect = "Jump",
		Amount = 10,
		HeightAmount = 2.5,
		Duration = 25,
		Price = 60,
		MaximumStack = 8,
		Color = Color3.fromRGB(246, 178, 65),
	},
}

function Catalog.Get(itemId)
	return ITEMS[itemId]
end

function Catalog.GetAll()
	local result = {}
	for _, itemId in ipairs(ORDER) do
		table.insert(result, ITEMS[itemId])
	end
	return result
end

return table.freeze(Catalog)
