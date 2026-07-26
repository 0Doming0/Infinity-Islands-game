-- Contrato central dos monstros. Todos os controladores leem os mesmos nomes,
-- limites e valores padrao para evitar comportamentos diferentes por sistema.

local MonsterConfig = {}

MonsterConfig.Defaults = table.freeze({
	MonsterType = "Generic",
	MaxHealth = 50,
	WalkSpeed = 12,
	DetectionRange = 55,
	LoseTargetRange = 75,
	LeashRange = 55,
	RoamRadius = 14,
	CanMove = true,
	CanRoam = true,
	CanChase = true,
	ReturnToSpawn = true,
	UsePathfinding = false,
	PathRecomputeInterval = 1,
	StopDistance = 3.5,
	AttackType = "Melee",
	AttackDamage = 8,
	AttackRange = 5,
	AttackCooldown = 1.15,
	AttackWindup = 0.35,
	AttackRecovery = 0.35,
	AttackHitboxSize = Vector3.new(6, 5, 7),
	AttackOffset = Vector3.new(0, 0, -3),
	Defense = 0,
	DamageMultiplier = 1,
	KnockbackResistance = 0,
	StunResistance = 0,
	CanBeStunned = true,
	CanBeKnockedBack = true,
	Peaceful = false,
	AggroOnDamage = true,
})

MonsterConfig.Enums = table.freeze({
	AttackType = table.freeze({ Melee = true, Contact = true, Ranged = true, None = true }),
	SpawnMode = table.freeze({ Solo = true, Group = true, Boss = true }),
	MinimumIslandSize = table.freeze({ Small = true, Medium = true, Large = true }),
})

local function value(model, name)
	local current = model:GetAttribute(name)
	if current ~= nil then
		return current
	end
	if name == "DetectionRange" then
		return model:GetAttribute("AggroRange")
	elseif name == "LoseTargetRange" then
		return model:GetAttribute("LoseAggroRange")
	end
	return MonsterConfig.Defaults[name]
end

function MonsterConfig.GetRoot(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function MonsterConfig.GetHumanoid(model)
	return model and model:FindFirstChildWhichIsA("Humanoid", true) or nil
end

function MonsterConfig.Read(model)
	local config = {}
	for name in pairs(MonsterConfig.Defaults) do
		config[name] = value(model, name)
	end
	config.MonsterId = model:GetAttribute("MonsterId") or model.Name
	config.MonsterType = model:GetAttribute("MonsterType")
		or model:GetAttribute("MonsterFamily")
		or MonsterConfig.Defaults.MonsterType
	config.DisplayName = model:GetAttribute("DisplayName") or config.MonsterId
	config.DetectionRange = math.max(0, tonumber(config.DetectionRange) or MonsterConfig.Defaults.DetectionRange)
	config.LoseTargetRange = math.max(
		config.DetectionRange,
		tonumber(config.LoseTargetRange) or MonsterConfig.Defaults.LoseTargetRange
	)
	config.LeashRange = math.max(0, tonumber(config.LeashRange) or MonsterConfig.Defaults.LeashRange)
	config.RoamRadius = math.max(0, tonumber(config.RoamRadius) or MonsterConfig.Defaults.RoamRadius)
	config.PathRecomputeInterval = math.max(
		0.25,
		tonumber(config.PathRecomputeInterval) or MonsterConfig.Defaults.PathRecomputeInterval
	)
	config.StopDistance = math.max(0, tonumber(config.StopDistance) or MonsterConfig.Defaults.StopDistance)
	config.AttackDamage = math.max(0, tonumber(config.AttackDamage) or MonsterConfig.Defaults.AttackDamage)
	config.AttackRange = math.max(0, tonumber(config.AttackRange) or MonsterConfig.Defaults.AttackRange)
	config.AttackCooldown = math.max(0.1, tonumber(config.AttackCooldown) or MonsterConfig.Defaults.AttackCooldown)
	config.AttackWindup = math.max(0, tonumber(config.AttackWindup) or MonsterConfig.Defaults.AttackWindup)
	config.AttackRecovery = math.max(0, tonumber(config.AttackRecovery) or MonsterConfig.Defaults.AttackRecovery)
	config.Defense = math.max(0, tonumber(config.Defense) or MonsterConfig.Defaults.Defense)
	config.DamageMultiplier = math.max(0, tonumber(config.DamageMultiplier) or MonsterConfig.Defaults.DamageMultiplier)
	config.KnockbackResistance = math.clamp(
		tonumber(config.KnockbackResistance) or MonsterConfig.Defaults.KnockbackResistance,
		0,
		1
	)
	config.StunResistance = math.clamp(
		tonumber(config.StunResistance) or MonsterConfig.Defaults.StunResistance,
		0,
		1
	)
	return config
end

function MonsterConfig.ApplyRuntimeDefaults(model)
	for name, defaultValue in pairs(MonsterConfig.Defaults) do
		if model:GetAttribute(name) == nil then
			if name == "DetectionRange" and model:GetAttribute("AggroRange") ~= nil then
				model:SetAttribute(name, model:GetAttribute("AggroRange"))
			elseif name == "LoseTargetRange" and model:GetAttribute("LoseAggroRange") ~= nil then
				model:SetAttribute(name, model:GetAttribute("LoseAggroRange"))
			else
				model:SetAttribute(name, defaultValue)
			end
		end
	end
	if model:GetAttribute("MonsterType") == nil then
		model:SetAttribute("MonsterType", model:GetAttribute("MonsterFamily") or "Generic")
	end
end

return table.freeze(MonsterConfig)
