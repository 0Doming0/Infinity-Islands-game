--[[
	SkyDungeon - SlimeVariants

	Transforma um unico modelo-base nas variantes de slime do MVP.
	Somente a BasePart chamada SlimeInside recebe cor/material/transparencia.

	O modelo-base pode forcar uma variante com o atributo SlimeVariant. Use
	"Random" (ou deixe ausente) para sortear usando os pesos abaixo.
]]

local SlimeVariants = {}

local VARIANT_ORDER = { "Green", "Blue", "Red", "Fire", "Ice", "Lightning", "Golden" }

local DEFINITIONS = {
	Green = {
		MonsterId = "GreenSlime",
		DisplayName = "Slime Verde",
		Behavior = "NeutralMelee",
		InitiallyPeaceful = true,
		Color = Color3.fromRGB(89, 171, 84),
		OutSideColor = Color3.fromRGB(114, 255, 98),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		Reflectance = 0,
		Weight = 49.5,
		HealthMultiplier = 1,
		ScoreMultiplier = 1,
		CoinMultiplier = 1,
		AggroRange = 80,
		CalmAfter = 10,
		AttackRange = 5,
		AttackDamage = 10,
		AttackCooldown = 1.3,
		PassiveSpeedMultiplier = 0.55,
		CombatSpeedMultiplier = 1,
		WanderPauseMin = 0.7,
		WanderPauseMax = 2.2,
	},
	Blue = {
		MonsterId = "BlueSlime",
		DisplayName = "Slime Azul",
		Behavior = "NeutralRanged",
		InitiallyPeaceful = true,
		Color = Color3.fromRGB(55, 102, 255),
		OutSideColor = Color3.fromRGB(55, 175, 255),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		Reflectance = 0,
		Weight = 17,
		HealthMultiplier = 1.1,
		ScoreMultiplier = 1.4,
		CoinMultiplier = 1.4,
		AggroRange = 80,
		CalmAfter = 10,
		AttackRange = 45,
		AttackDamage = 15,
		AttackCooldown = 2.5,
		ProjectileSpeed = 55,
		PassiveSpeedMultiplier = 0.55,
		CombatSpeedMultiplier = 0.82,
		PreferredDistance = 28,
		RetreatDistance = 16,
		RepositionInterval = 2.2,
		WanderPauseMin = 0.8,
		WanderPauseMax = 2.4,
	},
	Red = {
		MonsterId = "RedSlime",
		DisplayName = "Slime Vermelho",
		Behavior = "HostileMortar",
		InitiallyPeaceful = false,
		Color = Color3.fromRGB(170, 29, 29),
		OutSideColor = Color3.fromRGB(255, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.1,
		Reflectance = 0,
		Weight = 12,
		HealthMultiplier = 1.25,
		ScoreMultiplier = 1.8,
		CoinMultiplier = 1.8,
		AttackRange = 55,
		AttackDamage = 15,
		AttackCooldown = 4,
		ImpactRadius = 7,
		MortarWarningTime = 1.2,
		MortarArcHeight = 24,
		DetectionRange = 70,
		CombatSpeedMultiplier = 0.78,
		PreferredDistance = 34,
		RetreatDistance = 20,
		RepositionInterval = 2.8,
		WanderPauseMin = 0.45,
		WanderPauseMax = 1.4,
	},
	Fire = {
		MonsterId = "FireSlime",
		DisplayName = "Slime de Fogo",
		Behavior = "FireMortar",
		InitiallyPeaceful = false,
		MinimumTier = 2,
		Color = Color3.fromRGB(255, 112, 31),
		OutSideColor = Color3.fromRGB(255, 171, 59),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.1,
		Reflectance = 0,
		Weight = 12,
		HealthMultiplier = 1.3,
		ScoreMultiplier = 2,
		CoinMultiplier = 2,
		AttackRange = 55,
		AttackDamage = 8,
		AttackCooldown = 4.2,
		ImpactRadius = 6,
		MortarWarningTime = 1.15,
		MortarArcHeight = 25,
		GroundEffectRadius = 5,
		GroundEffectDuration = 5,
		GroundEffectDamage = 2,
		GroundEffectInterval = 0.75,
		DetectionRange = 72,
		CombatSpeedMultiplier = 0.8,
		PreferredDistance = 35,
		RetreatDistance = 20,
		RepositionInterval = 2.8,
		WanderPauseMin = 0.45,
		WanderPauseMax = 1.35,
	},
	Ice = {
		MonsterId = "IceSlime",
		DisplayName = "Slime de Gelo",
		Behavior = "IceRanged",
		InitiallyPeaceful = false,
		MinimumTier = 3,
		Color = Color3.fromRGB(100, 239, 255),
		OutSideColor = Color3.fromRGB(215, 251, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.12,
		Reflectance = 0.08,
		Weight = 7,
		HealthMultiplier = 1.2,
		ScoreMultiplier = 2,
		CoinMultiplier = 2,
		AggroRange = 78,
		CalmAfter = 10,
		AttackRange = 48,
		AttackDamage = 6,
		AttackCooldown = 2.8,
		ProjectileSpeed = 62,
		FreezeDuration = 1.25,
		FreezeImmunity = 4,
		PassiveSpeedMultiplier = 0.62,
		CombatSpeedMultiplier = 0.88,
		PreferredDistance = 30,
		RetreatDistance = 17,
		RepositionInterval = 2.1,
		WanderPauseMin = 0.7,
		WanderPauseMax = 2,
	},
	Lightning = {
		MonsterId = "LightningSlime",
		DisplayName = "Slime do Raio",
		Behavior = "LightningDash",
		InitiallyPeaceful = false,
		MinimumTier = 4,
		Color = Color3.fromRGB(248, 248, 255),
		OutSideColor = Color3.fromRGB(255, 231, 68),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.08,
		Reflectance = 0.04,
		Weight = 7,
		HealthMultiplier = 1.15,
		ScoreMultiplier = 2.2,
		CoinMultiplier = 2.2,
		DetectionRange = 68,
		AttackRange = 5,
		AttackDamage = 12,
		AttackCooldown = 2.2,
		DashTriggerRange = 15,
		DashWindup = 0.45,
		DashDuration = 0.48,
		DashSpeedMultiplier = 1.8,
		MissVulnerability = 0.75,
		PassiveSpeedMultiplier = 0.9,
		CombatSpeedMultiplier = 1.8,
		WanderPauseMin = 0.25,
		WanderPauseMax = 0.9,
	},
	Golden = {
		MonsterId = "GoldenSlime",
		DisplayName = "Slime Dourado",
		Behavior = "GoldenEscape",
		InitiallyPeaceful = true,
		Color = Color3.fromRGB(232, 177, 48),
		OutSideColor = Color3.fromRGB(255, 255, 0),
		Material = Enum.Material.Neon,
		Transparency = 0.05,
		Reflectance = 0.15,
		Weight = 0.5,
		HealthMultiplier = 3,
		ScoreMultiplier = 8,
		CoinMultiplier = 20,
		Lifetime = 45,
		TeleportInterval = 8,
		TeleportWarningTime = 1,
		PassiveSpeedMultiplier = 0.9,
		FleeDistance = 28,
		WanderPauseMin = 0.25,
		WanderPauseMax = 0.9,
	},
}

local function findSlimeInside(model)
	local inside = model and model:FindFirstChild("SlimeInside", true)
	return inside and inside:IsA("BasePart") and inside or nil
end
local function findSlimeOutside(model)
	local outside = model and model:FindFirstChild("SlimeOutside", true)
	return outside and outside:IsA("BasePart") and outside or nil
end

local function getWeight(template, variantName, definition)
	local override = template:GetAttribute("Slime" .. variantName .. "Weight")
	if typeof(override) == "number" then
		return math.max(0, override)
	end
	return definition.Weight
end

local function chooseVariant(template, random, options)
	options = options or {}
	local difficultyTier = math.max(1, math.floor(tonumber(options.DifficultyTier) or 1))
	local forced = template:GetAttribute("SlimeVariant")
	if typeof(forced) == "string" and forced ~= "" and forced ~= "Random" and DEFINITIONS[forced] then
		local definition = DEFINITIONS[forced]
		if (definition.MinimumTier or 1) <= difficultyTier then
			return options.DisallowGolden and forced == "Golden" and "Red" or forced
		end
		return "Green"
	end

	local totalWeight = 0
	local lockedWeight = 0
	for _, variantName in ipairs(VARIANT_ORDER) do
		local definition = DEFINITIONS[variantName]
		if (definition.MinimumTier or 1) <= difficultyTier then
			totalWeight += getWeight(template, variantName, definition)
		else
			lockedWeight += getWeight(template, variantName, definition)
		end
	end
	totalWeight += lockedWeight
	if totalWeight <= 0 then
		return "Green"
	end

	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, variantName in ipairs(VARIANT_ORDER) do
		local definition = DEFINITIONS[variantName]
		if (definition.MinimumTier or 1) > difficultyTier then
			continue
		end
		accumulated += getWeight(template, variantName, definition)
		if variantName == "Green" then
			accumulated += lockedWeight
		end
		if roll <= accumulated then
			return options.DisallowGolden and variantName == "Golden" and "Red" or variantName
		end
	end
	return "Green"
end

local function disableEmbeddedAI(model, template)
	if template:GetAttribute("KeepEmbeddedAIScripts") == true then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if
			descendant:IsA("Script")
			and descendant.Name ~= "Animate"
			and descendant:GetAttribute("AllowWithSlimeController") ~= true
		then
			descendant.Disabled = true
		end
	end
end

local function addGoldenEffects(inside)
	local light = Instance.new("PointLight")
	light.Name = "GoldenSlimeLight"
	light.Color = Color3.fromRGB(255, 255, 0)
	light.Brightness = 1.8
	light.Range = 12
	light.Shadows = false
	light.Parent = inside

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "GoldenSlimeSparkles"
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 165)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 155, 25)),
	})
	sparkles.LightEmission = 1
	sparkles.Lifetime = NumberRange.new(0.45, 0.9)
	sparkles.Speed = NumberRange.new(0.8, 2.2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 9
	sparkles.Parent = inside
end

function SlimeVariants.IsSlime(model)
	return model ~= nil
		and (model:GetAttribute("MonsterFamily") == "Slime" or (findSlimeInside(model) ~= nil and findSlimeOutside(model) ~= nil)) 
end

function SlimeVariants.SelectVariant(template, random, options)
	return chooseVariant(template, random, options)
end

function SlimeVariants.ConfigureClone(clone, template, random, forcedVariant)
	local inside = findSlimeInside(clone)
	local outside = findSlimeOutside(clone)
	if not inside or not outside then
		return nil
	end

	local variantName = DEFINITIONS[forcedVariant] and forcedVariant or chooseVariant(template, random)
	local definition = DEFINITIONS[variantName]

	inside.Color = definition.Color
	if variantName == "Golden" then
		outside.Material = Enum.Material.Neon
	else
		inside.Material = definition.Material
	end 
	inside.Transparency = definition.Transparency
	inside.Reflectance = definition.Reflectance

	outside.Color = definition.OutSideColor
	outside.Material = definition.Material

	clone:SetAttribute("MonsterFamily", "Slime")
	clone:SetAttribute("SlimeVariant", variantName)
	clone:SetAttribute("SlimeBehavior", definition.Behavior)
	clone:SetAttribute("Peaceful", definition.InitiallyPeaceful)
	clone:SetAttribute("AggroUserId", nil)
	clone:SetAttribute("DeathParticleColor", definition.Color)

	if variantName == "Golden" then
		addGoldenEffects(inside)
	end
	disableEmbeddedAI(clone, template)

	return definition, variantName
end

function SlimeVariants.GetDefinition(variantName)
	return DEFINITIONS[variantName]
end

return table.freeze(SlimeVariants)
