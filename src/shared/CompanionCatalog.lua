-- Configuracao compartilhada do sistema de companheiros.
--
-- Para adicionar a imagem de um mob na interface, preencha ImageId abaixo ou
-- defina o Attribute CompanionImageId diretamente no Model do monstro.

local CompanionCatalog = {}
local MonetizationCatalog = require(script.Parent:WaitForChild("MonetizationCatalog"))

CompanionCatalog.InitialEquippedSlots = 1
CompanionCatalog.MaxEquipped = 4
CompanionCatalog.MaximumStored = 500
CompanionCatalog.EquipSlotDeveloperProductId =
	MonetizationCatalog.Get("CompanionSlot").ProductId
CompanionCatalog.EquipSlotCoinPrices = table.freeze({
	[2] = 20000,
	[3] = 75000,
	[4] = 250000,
})
CompanionCatalog.MaxLevel = 50
-- A escala visual e absoluta em relacao ao modelo original do monstro.
-- Assim, um companheiro no Nv. 50 tem exatamente o dobro do tamanho do mob
-- normal, independentemente de atributos antigos no template.
CompanionCatalog.VisualScaleAtLevelOne = 1
CompanionCatalog.VisualScaleAtMaxLevel = 2
CompanionCatalog.MaxDisplayNameLength = 20
CompanionCatalog.LevelDamageBonus = 0.04
CompanionCatalog.TeleportDistance = 70
CompanionCatalog.OwnerCombatRadius = 60
CompanionCatalog.BaseXP = 5
CompanionCatalog.LinearXPPerLevel = 4
CompanionCatalog.QuadraticXPFactor = 0.2

CompanionCatalog.UpgradeOrder = table.freeze({
	"Damage",
	"AttackSpeed",
	"MoveSpeed",
	"Range",
})

CompanionCatalog.Upgrades = table.freeze({
	Damage = table.freeze({
		DisplayName = "Poder",
		CardKind = "DANO",
		AttributeLabel = "+5% DANO",
		Description = "+5% de dano por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.05,
	}),
	AttackSpeed = table.freeze({
		DisplayName = "Velocidade de ataque",
		CardKind = "ATAQUE",
		AttributeLabel = "-3% RECARGA",
		Description = "-3% de recarga por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.03,
	}),
	MoveSpeed = table.freeze({
		DisplayName = "Agilidade",
		CardKind = "MOVIMENTO",
		AttributeLabel = "+4% MOVIMENTO",
		Description = "+4% de movimento por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.04,
	}),
	Range = table.freeze({
		DisplayName = "Alcance",
		CardKind = "DISTÂNCIA",
		AttributeLabel = "+0,6 STUD",
		Description = "+0,6 stud por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.6,
	}),
})

CompanionCatalog.UpgradeOrder = table.freeze({
	"Damage",
	"AttackSpeed",
	"MoveSpeed",
	"Range",
})

-- Espaco reservado para todas as variantes atualmente conhecidas.
-- Exemplo: ImageId = "rbxassetid://1234567890"
CompanionCatalog.Entries = table.freeze({
	GreenSlime = table.freeze({
		DisplayName = "Slime Verde",
		ImageId = "",
		LevelIconImageId = "rbxassetid://138682212313932",
		Color = Color3.fromRGB(91, 219, 128),
		CaptureChance = 0.06,
		-- O primeiro companheiro de cada especie recebe uma protecao contra azar.
		-- O verde e apresentado logo na primeira ilha de combate; os demais
		-- continuam raros, mas nao ficam inacessiveis durante uma sessao normal.
		FirstCapturePityTarget = 1,
	}),
	BlueSlime = table.freeze({
		DisplayName = "Slime Azul",
		ImageId = "",
		LevelIconImageId = "rbxassetid://72572595647145",
		Color = Color3.fromRGB(70, 170, 255),
		CaptureChance = 0.04,
		FirstCapturePityTarget = 4,
	}),
	RedSlime = table.freeze({
		DisplayName = "Slime Vermelho",
		ImageId = "",
		LevelIconImageId = "rbxassetid://89414760577651",
		Color = Color3.fromRGB(238, 78, 65),
		CaptureChance = 0.03,
		FirstCapturePityTarget = 5,
	}),
	FireSlime = table.freeze({
		DisplayName = "Slime de Fogo",
		ImageId = "",
		LevelIconImageId = "rbxassetid://74097355107260",
		Color = Color3.fromRGB(255, 119, 43),
		CaptureChance = 0.025,
		FirstCapturePityTarget = 6,
	}),
	IceSlime = table.freeze({
		DisplayName = "Slime de Gelo",
		ImageId = "",
		LevelIconImageId = "rbxassetid://78285390878409",
		Color = Color3.fromRGB(92, 238, 255),
		CaptureChance = 0.025,
		FirstCapturePityTarget = 6,
	}),
	LightningSlime = table.freeze({
		DisplayName = "Slime do Raio",
		ImageId = "",
		LevelIconImageId = "rbxassetid://106472082094594",
		Color = Color3.fromRGB(245, 245, 255),
		CaptureChance = 0.02,
		FirstCapturePityTarget = 8,
	}),
	GoldenSlime = table.freeze({
		DisplayName = "Slime Dourado",
		ImageId = "",
		LevelIconImageId = "rbxassetid://122552935180866",
		Color = Color3.fromRGB(255, 210, 65),
		CaptureChance = 0.01,
		FirstCapturePityTarget = 20,
	}),
	PrototypeSlime = table.freeze({
		DisplayName = "Slime",
		ImageId = "",
		LevelIconImageId = "",
		Color = Color3.fromRGB(111, 230, 159),
		CaptureChance = 0.06,
		FirstCapturePityTarget = 4,
	}),
})

function CompanionCatalog.Get(monsterId)
	return CompanionCatalog.Entries[monsterId]
end

function CompanionCatalog.IsSupported(monsterId)
	return CompanionCatalog.Entries[monsterId] ~= nil
end

function CompanionCatalog.GetCaptureChance(monsterId, isElite)
	local entry = CompanionCatalog.Entries[monsterId]
	local chance = entry and math.clamp(tonumber(entry.CaptureChance) or 0, 0, 1) or 0
	if isElite then
		chance = math.min(0.10, chance * 2)
	end
	return chance
end

function CompanionCatalog.GetFirstCapturePityTarget(monsterId)
	local entry = CompanionCatalog.Entries[monsterId]
	return math.max(
		0,
		math.floor(tonumber(entry and entry.FirstCapturePityTarget) or 0)
	)
end

function CompanionCatalog.GetEquipSlotCoinPrice(targetSlot)
	local slot = math.floor(tonumber(targetSlot) or 0)
	return CompanionCatalog.EquipSlotCoinPrices[slot]
end

function CompanionCatalog.GetImageId(monsterId, attributeValue)
	if type(attributeValue) == "string" and attributeValue ~= "" then
		return attributeValue
	end
	local entry = CompanionCatalog.Entries[monsterId]
	return entry and entry.ImageId or ""
end

function CompanionCatalog.EmptyUpgrades()
	return {
		Damage = 0,
		AttackSpeed = 0,
		MoveSpeed = 0,
		Range = 0,
	}
end

function CompanionCatalog.GetXPRequired(level)
	local cleanLevel = math.clamp(
		math.floor(tonumber(level) or 1),
		1,
		CompanionCatalog.MaxLevel
	)
	if cleanLevel >= CompanionCatalog.MaxLevel then
		return 0
	end
	local quadratic = (cleanLevel - 1) ^ 2 * CompanionCatalog.QuadraticXPFactor
	return math.floor(
		CompanionCatalog.BaseXP
			+ cleanLevel * CompanionCatalog.LinearXPPerLevel
			+ quadratic
			+ 0.5
	)
end

function CompanionCatalog.GetVisualScale(level)
	local cleanLevel = math.clamp(
		math.floor(tonumber(level) or 1),
		1,
		CompanionCatalog.MaxLevel
	)
	local minimumScale = CompanionCatalog.VisualScaleAtLevelOne
	local maximumScale = CompanionCatalog.VisualScaleAtMaxLevel
	if CompanionCatalog.MaxLevel <= 1 then
		return maximumScale
	end
	local progress = (cleanLevel - 1) / (CompanionCatalog.MaxLevel - 1)
	return minimumScale + (maximumScale - minimumScale) * progress
end

function CompanionCatalog.SpentPoints(upgrades)
	local total = 0
	for _, statName in ipairs(CompanionCatalog.UpgradeOrder) do
		total += math.max(0, math.floor(tonumber(upgrades and upgrades[statName]) or 0))
	end
	return total
end

return table.freeze(CompanionCatalog)
