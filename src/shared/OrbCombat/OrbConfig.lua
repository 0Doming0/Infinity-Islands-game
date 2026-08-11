local OrbConfig = {
	DefaultOrb = "Fire",
	MaxRange = 90,
	AttackCooldown = 0.65,
	DamageLimits = {
		Min = 1,
		Max = 100,
	},
	Orbs = {
		Fire = {
			DisplayName = "Fire Orb",
			Damage = 10,
			Range = 13,
			Cooldown = 0.9,
			LaserColor = Color3.fromRGB(255, 92, 35),
			LaserWidth = 0.22,
			LaserMaterial = Enum.Material.Neon,
			StatusEffect = "Burn",
		},
		Ice = {
			DisplayName = "Ice Orb",
			Damage = 8,
			Range = 13,
			Cooldown = 0.72,
			LaserColor = Color3.fromRGB(75, 205, 255),
			LaserWidth = 0.22,
			LaserMaterial = Enum.Material.Neon,
			StatusEffect = "Freeze",
		},
		Shadow = {
			DisplayName = "Shadow Orb",
			Damage = 9,
			Range = 13,
			Cooldown = 0.68,
			LaserColor = Color3.fromRGB(170, 75, 255),
			LaserWidth = 0.22,
			LaserMaterial = Enum.Material.Neon,
			StatusEffect = "Slow",
			SecondaryStatusEffect = "Disorient",
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
	return OrbConfig.GetOrb(name) and name or OrbConfig.DefaultOrb
end

return table.freeze(OrbConfig)
