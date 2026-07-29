-- ReplicatedStorage/RelicCatalog
-- Relíquias definem efeitos passivos; espadas continuam responsáveis apenas
-- pelos atributos básicos de combate.

local Catalog = {}

local ORDER = {
	"LightningRelic",
	"FireRelic",
	"IceRelic",
	"StoneRelic",
}

local DEFINITIONS = {
	LightningRelic = {
		RelicId = "LightningRelic",
		DisplayName = "Relíquia do Raio",
		Description = "Um acerto descarrega o dano da arma em outro inimigo próximo.",
		Price = 900,
		Color = Color3.fromRGB(255, 226, 72),
		Icon = "⚡",
		-- Cole aqui a imagem publicada no Roblox, por exemplo:
		-- ImageId = "rbxassetid://1234567890",
		ImageId = "rbxassetid://103906439983985",
		Effect = "Lightning",
		ChainRadius = 18,
		IndicatorDuration = 1.25,
	},
	FireRelic = {
		RelicId = "FireRelic",
		DisplayName = "Relíquia do Fogo",
		Description = "Incendeia por 3s. Cada pulso causa 12% do dano do golpe.",
		Price = 1050,
		Color = Color3.fromRGB(255, 92, 45),
		Icon = "🔥",
		ImageId = "rbxassetid://125454564430334",
		Effect = "Fire",
		Duration = 3,
		DamagePerSecondRatio = 0.25,
	},
	IceRelic = {
		RelicId = "IceRelic",
		DisplayName = "Relíquia do Gelo",
		Description = "Três golpes consecutivos congelam o alvo por 3s.",
		Price = 1150,
		Color = Color3.fromRGB(92, 210, 255),
		Icon = "❄️",
		ImageId = "rbxassetid://77356245631001",
		Effect = "Ice",
		HitsRequired = 3,
		ComboWindowSeconds = 4,
		FreezeDuration = 3,
		EliteFreezeDuration = 1.2,
	},
	StoneRelic = {
		RelicId = "StoneRelic",
		DisplayName = "Relíquia da Pedra",
		Description = "Após três golpes, o próximo causa 3x mais knockback.",
		Price = 950,
		Color = Color3.fromRGB(164, 137, 102),
		Icon = "🪨",
		ImageId = "rbxassetid://82052894507012",
		Effect = "Stone",
		HitsToCharge = 3,
		KnockbackMultiplier = 3,
		ComboWindowSeconds = 4,
		IndicatorDuration = 1.25,
	},
}

function Catalog.Get(relicId)
	return DEFINITIONS[relicId]
end

function Catalog.GetOrderedIds()
	return table.clone(ORDER)
end

function Catalog.GetAll()
	local result = {}
	for _, relicId in ipairs(ORDER) do
		table.insert(result, DEFINITIONS[relicId])
	end
	return result
end

return table.freeze(Catalog)
