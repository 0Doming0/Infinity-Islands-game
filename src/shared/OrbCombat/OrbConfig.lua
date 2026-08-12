local OrbConfig = {
	Version = "OrbProgressionV1",
	ChoiceLevels = { 3, 6, 9, 12 },
	OrbOrder = { "Fire", "Ice", "Shadow" },
	MaxOrbLevel = 4,
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
			Upgrade = {
				Damage = 2,
				BurnDamage = 1,
				StatusDuration = 0.5,
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
			Upgrade = {
				Damage = 2,
				StatusDuration = 0.2,
				Cooldown = -0.06,
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
			Upgrade = {
				Damage = 2,
				StatusDuration = 0.35,
				SlowMultiplier = -0.05,
			},
		},
	},
}

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

function OrbConfig.GetOrbAtLevel(name, level)
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

	local before = OrbConfig.GetOrbAtLevel(name, currentLevel)
	local after = OrbConfig.GetOrbAtLevel(name, currentLevel + 1)
	local parts = {}
	if before.Damage ~= after.Damage then
		table.insert(parts, string.format("Damage %g → %g", before.Damage, after.Damage))
	end
	if name == "Fire" then
		table.insert(parts, string.format("Burn %g → %g", before.BurnDamage, after.BurnDamage))
		table.insert(parts, string.format("Duration %.1fs → %.1fs", before.StatusDuration, after.StatusDuration))
	elseif name == "Ice" then
		table.insert(parts, string.format("Freeze %.2fs → %.2fs", before.StatusDuration, after.StatusDuration))
		table.insert(parts, string.format("Cooldown %.2fs → %.2fs", before.Cooldown, after.Cooldown))
	elseif name == "Shadow" then
		table.insert(
			parts,
			string.format(
				"Slow %d%% → %d%%",
				math.floor((1 - before.SlowMultiplier) * 100 + 0.5),
				math.floor((1 - after.SlowMultiplier) * 100 + 0.5)
			)
		)
		table.insert(parts, string.format("Disorient %.2fs → %.2fs", before.StatusDuration, after.StatusDuration))
	end
	return table.concat(parts, "\n")
end

return table.freeze(OrbConfig)
