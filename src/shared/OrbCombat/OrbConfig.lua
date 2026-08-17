local OrbConfig = {
	Version = "OrbProgressionV5_RareAdditionalOrbs",
	ChoiceLevels = (function()
		local levels = {}
		for level = 3, 100 do
			table.insert(levels, level)
		end
		return levels
	end)(),
	OrbOrder = { "Fire", "Ice", "Shadow" },
	MaxOrbLevel = 4,
	OrbLevelXPBase = 100,
	OrbLevelXPGrowth = 1.75,
	MaxEquippedOrbs = 2,
	-- O primeiro Orb e garantido. Depois disso, cada recompensa de nivel tem
	-- apenas esta chance de oferecer um segundo Orb ainda nao possuido.
	AdditionalOrbChancePerMilestone = 0.015,
	MaxRange = 90,
	AttackCooldown = 0.65,
	DamageLimits = {
		Min = 1,
		Max = 100,
	},
	Orbs = {
		Fire = {
			AssetName = "FireOrb",
			DisplayName = "Fire Orb",
			Description = "Queima inimigos e causa dano continuo.",
			Damage = 10,
			Range = 13,
			Cooldown = 0.9,
			LaserColor = Color3.fromRGB(255, 92, 35),
			LaserWidth = 0.22,
			LaserMaterial = Enum.Material.Neon,
			StatusEffect = "Burn",
			StatusDuration = 3,
			BurnTickInterval = 0.75,
			BurnDamage = 2,
			EffectSoundIds = {
				AreaImpact = "",
				Burn = "",
				Spread = "",
				Nebula = "",
				Execute = "",
			},
			Upgrade = {
				Damage = 2,
				BurnDamage = 1,
				StatusDuration = 0.5,
			},
			SpecializedUpgrades = {
				{ Id = "Fire_AOE", Name = "Anel Incendiario", AttributeLabel = "AREA DE IMPACTO", Description = "O ataque atinge inimigos proximos ao alvo.", Stat = "AOERadius", Value = 4, MaxValue = 12 },
				{ Id = "Fire_Rapid", Name = "Brasa Veloz", AttributeLabel = "ATAQUE MAIS RAPIDO", Description = "Reduz o intervalo entre disparos.", Stat = "CooldownMultiplier", Value = -0.1, MaxValue = -0.3 },
				{ Id = "Fire_Burn", Name = "Chama Profunda", AttributeLabel = "QUEIMADURA MAIS FORTE", Description = "Cada ataque aplica uma queimadura mais dolorosa.", Stat = "BurnDamageBonus", Value = 2, MaxValue = 6 },
				{ Id = "Fire_Range", Name = "Faísca Longa", AttributeLabel = "ALCANCE", Description = "Aumenta a distancia segura dos disparos.", Stat = "RangeBonus", Value = 3, MaxValue = 9 },
				{ Id = "Fire_Nebula", Name = "Nébulas Voláteis", AttributeLabel = "PROC: NEBULA EXPLOSIVA", Description = "Cada ataque tem chance de criar uma nébula que explode e causa muito dano em área.", Stat = "NebulaChance", Value = 0.12, MaxValue = 0.36 },
				{ Id = "Fire_Execution", Name = "Sol Negro", AttributeLabel = "EXECUÇÃO", Description = "Inimigos muito feridos recebem uma explosão final de dano.", Stat = "ExecuteThreshold", Value = 0.08, MaxValue = 0.24 },
				{ Id = "Fire_Spread", Name = "Incêndio em Cadeia", AttributeLabel = "FOGO ESPALHADO", Description = "A queimadura pode saltar para inimigos próximos.", Stat = "BurnSpreadChance", Value = 0.2, MaxValue = 0.6 },
			},
		},
		Ice = {
			AssetName = "IceOrb",
			DisplayName = "Ice Orb",
			Description = "Congela inimigos e ataca mais rapido.",
			Damage = 8,
			Range = 13,
			Cooldown = 0.72,
			LaserColor = Color3.fromRGB(75, 205, 255),
			LaserWidth = 0.22,
			LaserMaterial = Enum.Material.Neon,
			StatusEffect = "Freeze",
			StatusDuration = 1.15,
			EffectSoundIds = {
				AreaImpact = "",
				Freeze = "",
				Bounce = "",
				FreezeBurst = "",
				Shatter = "",
				SlowField = "",
			},
			Upgrade = {
				Damage = 2,
				StatusDuration = 0.2,
				Cooldown = -0.06,
			},
			SpecializedUpgrades = {
				{ Id = "Ice_SlowField", Name = "Campo Congelante", AttributeLabel = "AREA LENTA", Description = "O impacto cria uma zona que desacelera inimigos proximos.", Stat = "SlowFieldRadius", Value = 4, MaxValue = 12 },
				{ Id = "Ice_Rapid", Name = "Cristal Veloz", AttributeLabel = "ATAQUE MAIS RAPIDO", Description = "O Ice Orb dispara com muito mais frequencia.", Stat = "CooldownMultiplier", Value = -0.1, MaxValue = -0.3 },
				{ Id = "Ice_Freeze", Name = "Geada Eterna", AttributeLabel = "CONGELAMENTO", Description = "Aumenta a duracao do congelamento aplicado.", Stat = "StatusDurationBonus", Value = 0.35, MaxValue = 1.05 },
				{ Id = "Ice_Bounce", Name = "Estilhaço Saltitante", AttributeLabel = "RICOCHEte", Description = "O disparo pode saltar para outro inimigo proximo.", Stat = "BounceCount", Value = 1, MaxValue = 3 },
				{ Id = "Ice_Prison", Name = "Prisão de Cristal", AttributeLabel = "PRISÃO AO CONGELAR", Description = "Ao congelar um inimigo, estilhaços atingem os inimigos ao redor.", Stat = "FreezeBurstRadius", Value = 3, MaxValue = 9 },
				{ Id = "Ice_Shatter", Name = "Quebra-Gelo", AttributeLabel = "DANO AO DESCONGELAR", Description = "Alvos que saem do congelamento explodem em fragmentos.", Stat = "ShatterDamage", Value = 6, MaxValue = 18 },
				{ Id = "Ice_Comet", Name = "Cometa Azul", AttributeLabel = "IMPACTO PERFURANTE", Description = "Ataques contra alvos congelados causam dano adicional.", Stat = "FrozenTargetBonus", Value = 0.35, MaxValue = 1.05 },
			},
		},
		Shadow = {
			AssetName = "ShadowOrb",
			DisplayName = "Shadow Orb",
			Description = "Desorienta e deixa inimigos mais lentos.",
			Damage = 9,
			Range = 13,
			Cooldown = 0.68,
			LaserColor = Color3.fromRGB(170, 75, 255),
			LaserWidth = 0.22,
			LaserMaterial = Enum.Material.Neon,
			StatusEffect = "Slow",
			SecondaryStatusEffect = "Disorient",
			StatusDuration = 2.5,
			SlowMultiplier = 0.45,
			EffectSoundIds = {
				AreaImpact = "",
				Slow = "",
				Disorient = "",
				Mark = "",
				Echo = "",
				Portal = "",
			},
			Upgrade = {
				Damage = 2,
				StatusDuration = 0.35,
				SlowMultiplier = -0.05,
			},
			SpecializedUpgrades = {
				{ Id = "Shadow_AOE", Name = "Eclipse", AttributeLabel = "AREA SOMBRIA", Description = "O impacto espalha lentidao para inimigos proximos.", Stat = "AOERadius", Value = 4, MaxValue = 12 },
				{ Id = "Shadow_Rapid", Name = "Passo Fantasma", AttributeLabel = "ATAQUE MAIS RAPIDO", Description = "Reduz o intervalo entre ataques sombrios.", Stat = "CooldownMultiplier", Value = -0.1, MaxValue = -0.3 },
				{ Id = "Shadow_Mark", Name = "Marca do Vazio", AttributeLabel = "DANO SOMBRIO", Description = "Inimigos marcados recebem dano extra dos proximos golpes.", Stat = "ShadowDamageBonus", Value = 3, MaxValue = 9 },
				{ Id = "Shadow_Control", Name = "Correntes do Vazio", AttributeLabel = "CONTROLE", Description = "A lentidao fica mais intensa e dura mais tempo.", Stat = "SlowBonus", Value = -0.08, MaxValue = -0.24 },
				{ Id = "Shadow_Dagger", Name = "Adagas do Eco", AttributeLabel = "DISPAROS EXTRAS", Description = "Cada ataque pode lançar ecos sombrios contra outros alvos.", Stat = "EchoChance", Value = 0.18, MaxValue = 0.54 },
				{ Id = "Shadow_Portal", Name = "Portal do Abismo", AttributeLabel = "PORTAL DE PUXÃO", Description = "Impactos criam uma área que reúne inimigos para o próximo ataque.", Stat = "PullRadius", Value = 3, MaxValue = 9 },
				{ Id = "Shadow_Reaper", Name = "Ceifador de Almas", AttributeLabel = "DANO POR MARCA", Description = "Cada marca acumulada aumenta o dano recebido do Shadow Orb.", Stat = "MarkDamageMultiplier", Value = 0.15, MaxValue = 0.45 },
			},
		},
	},
}

-- The Lemonade HUD presents one card for each Orb, not a separate technical
-- upgrade picker. These are the existing, already functional combat abilities
-- unlocked automatically as that Orb reaches levels 2–4.
OrbConfig.LevelAbilities = table.freeze({
	Fire = table.freeze({
		[2] = "Fire_Spread",
		[3] = "Fire_Nebula",
		[4] = "Fire_Burn",
	}),
	Ice = table.freeze({
		[2] = "Ice_SlowField",
		[3] = "Ice_Shatter",
		[4] = "Ice_Freeze",
	}),
	Shadow = table.freeze({
		[2] = "Shadow_Control",
		[3] = "Shadow_Rapid",
		[4] = "Shadow_Control",
	}),
})

function OrbConfig.GetOrb(name)
	if typeof(name) ~= "string" then
		return nil
	end
	return OrbConfig.Orbs[name]
end

function OrbConfig.NormalizeOrb(name)
	return OrbConfig.GetOrb(name) and name or nil
end

function OrbConfig.GetLevelAttribute(name)
	return OrbConfig.GetOrb(name) and (name .. "OrbLevel") or nil
end

function OrbConfig.CleanLevel(level)
	return math.clamp(math.floor(tonumber(level) or 0), 0, OrbConfig.MaxOrbLevel)
end

function OrbConfig.GetOrbLevelXPCost(currentLevel)
	currentLevel = OrbConfig.CleanLevel(currentLevel)
	if currentLevel >= OrbConfig.MaxOrbLevel then
		return 0
	end
	return math.max(1, math.floor(OrbConfig.OrbLevelXPBase * (OrbConfig.OrbLevelXPGrowth ^ currentLevel) + 0.5))
end

function OrbConfig.GetOrbLevelXPAttribute(name)
	return OrbConfig.GetLevelAttribute(name) and (name .. "OrbXP") or nil
end

function OrbConfig.GetOrbAtLevel(name, level, player)
	local base = OrbConfig.GetOrb(name)
	level = OrbConfig.CleanLevel(level)
	if not base or level <= 0 then
		return nil
	end

	local result = table.clone(base)
	local upgradeCount = level - 1
	for statName, perLevel in pairs(base.Upgrade or {}) do
		local baseValue = tonumber(base[statName]) or 0
		result[statName] = baseValue + perLevel * upgradeCount
	end

	result.Level = level
	result.AOERadius = 0
	result.SlowFieldRadius = 0
	result.BounceCount = 0
	result.RangeBonus = 0
	result.BurnDamageBonus = 0
	result.StatusDurationBonus = 0
	result.CooldownMultiplier = 0
	result.ShadowDamageBonus = 0
	result.SlowBonus = 0
	result.NebulaChance = 0
	result.NebulaDamage = 0
	result.NebulaRadius = 0
	result.ExecuteThreshold = 0
	result.BurnSpreadChance = 0
	result.FreezeBurstRadius = 0
	result.ShatterDamage = 0
	result.FrozenTargetBonus = 0
	result.EchoChance = 0
	result.PullRadius = 0
	result.MarkDamageMultiplier = 0

	if player then
		for _, upgrade in ipairs(base.SpecializedUpgrades or {}) do
			local attribute = "OrbUpgrade_" .. upgrade.Id
			local count = math.clamp(math.floor(tonumber(player:GetAttribute(attribute)) or 0), 0, level - 1)
			local value = (tonumber(upgrade.Value) or 0) * count
			result[upgrade.Stat] = (tonumber(result[upgrade.Stat]) or 0) + value
		end
	end

	result.Range = math.clamp((tonumber(result.Range) or 0) + (tonumber(result.RangeBonus) or 0), 1, OrbConfig.MaxRange)
	result.Cooldown = math.max(0.12, (tonumber(result.Cooldown) or 0.65) * (1 + (tonumber(result.CooldownMultiplier) or 0)))
	result.BurnDamage = math.max(0, (tonumber(result.BurnDamage) or 0) + (tonumber(result.BurnDamageBonus) or 0))
	result.StatusDuration = math.max(0.1, (tonumber(result.StatusDuration) or 0.1) + (tonumber(result.StatusDurationBonus) or 0))
	result.SlowMultiplier = math.clamp((tonumber(result.SlowMultiplier) or 0.45) + (tonumber(result.SlowBonus) or 0), 0.1, 1)
	result.NebulaDamage = math.max(0, result.Damage * 3.5)
	result.NebulaRadius = math.max(0, result.AOERadius + 3)
	result.ShatterDamage = math.max(0, tonumber(result.ShatterDamage) or 0)
	return result
end

function OrbConfig.GetSpecializedUpgrade(name, upgradeId)
	local orb = OrbConfig.GetOrb(name)
	if not orb or typeof(upgradeId) ~= "string" then
		return nil
	end
	for _, upgrade in ipairs(orb.SpecializedUpgrades or {}) do
		if upgrade.Id == upgradeId then
			return upgrade
		end
	end
	return nil
end

function OrbConfig.GetMilestoneAbility(name, orbLevel)
	orbLevel = OrbConfig.CleanLevel(orbLevel)
	local abilityId = OrbConfig.LevelAbilities[name] and OrbConfig.LevelAbilities[name][orbLevel]
	local ability = OrbConfig.GetSpecializedUpgrade(name, abilityId)
	if not ability then
		return nil, 0
	end

	-- A repeated entry means the same ability improves again. Its rank is
	-- deterministic, so old saves cannot receive more than intended.
	local rank = 0
	for scheduledLevel, scheduledId in pairs(OrbConfig.LevelAbilities[name]) do
		if scheduledLevel <= orbLevel and scheduledId == abilityId then
			rank += 1
		end
	end
	return ability, rank
end

function OrbConfig.GetUpgradeOptions(name, currentLevel, player)
	local orb = OrbConfig.GetOrb(name)
	currentLevel = OrbConfig.CleanLevel(currentLevel)
	if not orb or currentLevel <= 0 or currentLevel >= OrbConfig.MaxOrbLevel then
		return {}
	end
	local result = {}
	for _, upgrade in ipairs(orb.SpecializedUpgrades or {}) do
		local count = math.floor(tonumber(player and player:GetAttribute("OrbUpgrade_" .. upgrade.Id)) or 0)
		if count < currentLevel then
			local current = (tonumber(upgrade.Value) or 0) * count
			local nextValue = (tonumber(upgrade.Value) or 0) * (count + 1)
			table.insert(result, {
				UpgradeId = upgrade.Id,
				Name = upgrade.Name,
				AttributeLabel = upgrade.AttributeLabel,
				Description = upgrade.Description,
				Stat = upgrade.Stat,
				CurrentValue = current,
				NextValue = nextValue,
				Color = orb.LaserColor,
			})
		end
	end
	return result
end

function OrbConfig.IsChoiceLevel(level)
	level = math.floor(tonumber(level) or 0)
	for _, choiceLevel in ipairs(OrbConfig.ChoiceLevels) do
		if choiceLevel == level then
			return true
		end
	end
	return false
end

function OrbConfig.GetUpgradeSummary(name, currentLevel)
	local base = OrbConfig.GetOrb(name)
	if not base then
		return ""
	end
	currentLevel = OrbConfig.CleanLevel(currentLevel)
	if currentLevel <= 0 then
		return string.format("NEW  |  Level 1")
	end
	if currentLevel >= OrbConfig.MaxOrbLevel then
		return string.format("Level %d  |  MAX", currentLevel)
	end

	local current = OrbConfig.GetOrbAtLevel(name, currentLevel)
	local next = OrbConfig.GetOrbAtLevel(name, currentLevel + 1)
	local details = {}
	local damageGain = (tonumber(next.Damage) or 0) - (tonumber(current.Damage) or 0)
	if damageGain > 0 then
		table.insert(details, string.format("Dano +%g", damageGain))
	end
	local burnGain = (tonumber(next.BurnDamage) or 0) - (tonumber(current.BurnDamage) or 0)
	if burnGain > 0 then
		table.insert(details, string.format("Queimadura +%g", burnGain))
	end
	local durationGain = (tonumber(next.StatusDuration) or 0) - (tonumber(current.StatusDuration) or 0)
	if durationGain > 0 then
		table.insert(details, string.format("Efeito +%.1fs", durationGain))
	end
	local cooldownGain = (tonumber(current.Cooldown) or 0) - (tonumber(next.Cooldown) or 0)
	if cooldownGain > 0.001 then
		table.insert(details, string.format("Ataque +%.0f%%", cooldownGain / math.max(0.01, tonumber(current.Cooldown) or 1) * 100))
	end
	if #details == 0 then
		table.insert(details, "Mais poder")
	end
	return string.format("Level %d → %d  |  %s", currentLevel, currentLevel + 1, table.concat(details, " • "))
end

return table.freeze(OrbConfig)
