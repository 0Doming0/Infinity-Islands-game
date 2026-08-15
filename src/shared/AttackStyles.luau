local AttackStyles = {
	Version = "AttackStylesV1",
	Order = { "FireOrb", "IceOrb", "ShadowOrb" },
	Styles = {
		FireOrb = {
			Id = "FireOrb",
			DisplayName = "Fire Orb",
			Description = "Queima inimigos e causa dano contínuo.",
			AttackType = "Orb",
			OrbName = "Fire",
			Color = Color3.fromRGB(255, 92, 35),
			Icon = "rbxassetid://73214946386499",
		},
		IceOrb = {
			Id = "IceOrb",
			DisplayName = "Ice Orb",
			Description = "Congela inimigos e ataca mais rápido.",
			AttackType = "Orb",
			OrbName = "Ice",
			Color = Color3.fromRGB(75, 205, 255),
			Icon = "rbxassetid://104293709713395",
		},
		ShadowOrb = {
			Id = "ShadowOrb",
			DisplayName = "Shadow Orb",
			Description = "Desorienta e deixa inimigos mais lentos.",
			AttackType = "Orb",
			OrbName = "Shadow",
			Color = Color3.fromRGB(170, 75, 255),
			Icon = "rbxassetid://111585498610164",
		},
	},
}

function AttackStyles.Get(id)
	if typeof(id) ~= "string" then
		return nil
	end
	return AttackStyles.Styles[id]
end

function AttackStyles.GetByOrbName(orbName)
	for _, id in ipairs(AttackStyles.Order) do
		local style = AttackStyles.Styles[id]
		if style.OrbName == orbName then
			return style
		end
	end
	return nil
end

function AttackStyles.Normalize(id)
	return AttackStyles.Get(id) and id or nil
end

return table.freeze(AttackStyles)