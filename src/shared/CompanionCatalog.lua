-- Configuracao compartilhada do sistema de companheiros.
--
-- Para adicionar a imagem de um mob na interface, preencha ImageId abaixo ou
-- defina o Attribute CompanionImageId diretamente no Model do monstro.

local CompanionCatalog = {}

CompanionCatalog.MaxEquipped = 4
CompanionCatalog.MaxLevel = 50
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
		Description = "+5% de dano por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.05,
	}),
	AttackSpeed = table.freeze({
		DisplayName = "Velocidade de ataque",
		Description = "-3% de recarga por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.03,
	}),
	MoveSpeed = table.freeze({
		DisplayName = "Agilidade",
		Description = "+4% de movimento por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.04,
	}),
	Range = table.freeze({
		DisplayName = "Alcance",
		Description = "+0,6 stud por ponto",
		MaxPoints = 15,
		BonusPerPoint = 0.6,
	}),
})

-- Espaco reservado para todas as variantes atualmente conhecidas.
-- Exemplo: ImageId = "rbxassetid://1234567890"
CompanionCatalog.Entries = table.freeze({
	GreenSlime = table.freeze({ ImageId = "" }),
	BlueSlime = table.freeze({ ImageId = "" }),
	RedSlime = table.freeze({ ImageId = "" }),
	GoldenSlime = table.freeze({ ImageId = "" }),
	PrototypeSlime = table.freeze({ ImageId = "" }),
	Golem = table.freeze({ ImageId = "" }),
	StoneGolem = table.freeze({ ImageId = "" }),
})

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

function CompanionCatalog.SpentPoints(upgrades)
	local total = 0
	for _, statName in ipairs(CompanionCatalog.UpgradeOrder) do
		total += math.max(0, math.floor(tonumber(upgrades and upgrades[statName]) or 0))
	end
	return total
end

return table.freeze(CompanionCatalog)