local HttpService = game:GetService("HttpService")

local MonsterConfig = require(script.Parent.MonsterConfig)
local AbilityRegistry = require(script.Parent.AbilityRegistry)

local MonsterValidator = {}

local NUMBER_RULES = {
	MaxHealth = { 1 },
	WalkSpeed = { 0 },
	DetectionRange = { 0 },
	LoseTargetRange = { 0 },
	LeashRange = { 0 },
	RoamRadius = { 0 },
	PathRecomputeInterval = { 0.1 },
	StopDistance = { 0 },
	AttackDamage = { 0 },
	AttackRange = { 0 },
	AttackCooldown = { 0.1 },
	AttackWindup = { 0 },
	AttackRecovery = { 0 },
	Defense = { 0 },
	DamageMultiplier = { 0 },
	KnockbackResistance = { 0, 1 },
	StunResistance = { 0, 1 },
	SpawnChance = { 0, 1 },
	SpawnWeight = { 0 },
	MinimumRound = { 1 },
	MaximumRound = { 1 },
	GroupMin = { 1 },
	GroupMax = { 1 },
	GroupSpacing = { 0 },
	DropChance = { 0, 1 },
	LootRolls = { 1 },
	CompanionUnlockChance = { 0, 1 },
	CompanionXPValue = { 0 },
	CompanionDamage = { 0 },
	CompanionScale = { 0.3, 1.5 },
}

local BOOLEAN_ATTRIBUTES = {
	"Enabled",
	"CanMove",
	"CanRoam",
	"CanChase",
	"ReturnToSpawn",
	"UsePathfinding",
	"CanBeStunned",
	"CanBeKnockedBack",
	"Peaceful",
	"AggroOnDamage",
	"UseCustomAI",
	"CanBecomeCompanion",
}

local function add(errors, message)
	table.insert(errors, message)
end

local function validateLootTable(template, errors)
	local encoded = template:GetAttribute("LootTable")
	if encoded ~= nil then
		if typeof(encoded) ~= "string" then
			add(errors, "LootTable precisa ser JSON string")
		else
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
			if not ok or type(decoded) ~= "table" then
				add(errors, "LootTable contem JSON invalido")
			end
		end
	end
	local folder = template:FindFirstChild("LootTable")
	if folder and not folder:IsA("Folder") then
		add(errors, "LootTable filho precisa ser Folder")
	end
end

function MonsterValidator.Validate(template)
	local errors = {}
	if not template:IsA("Model") then
		return false, { "nao e Model" }
	end
	if template:GetAttribute("Enabled") == false then
		return false, { "desativado" }
	end
	if not MonsterConfig.GetHumanoid(template) then
		add(errors, "Humanoid ausente")
	end
	if not MonsterConfig.GetRoot(template) then
		add(errors, "HumanoidRootPart, PrimaryPart ou BasePart ausente")
	end

	for name, limits in pairs(NUMBER_RULES) do
		local attribute = template:GetAttribute(name)
		if attribute ~= nil then
			if typeof(attribute) ~= "number" then
				add(errors, name .. " precisa ser number")
			elseif attribute < limits[1] or (limits[2] and attribute > limits[2]) then
				add(errors, string.format("%s fora do intervalo permitido", name))
			end
		end
	end
	for _, name in ipairs(BOOLEAN_ATTRIBUTES) do
		local attribute = template:GetAttribute(name)
		if attribute ~= nil and typeof(attribute) ~= "boolean" then
			add(errors, name .. " precisa ser boolean")
		end
	end

	local monsterType = template:GetAttribute("MonsterType")
	if monsterType ~= nil and (typeof(monsterType) ~= "string" or monsterType == "") then
		add(errors, "MonsterType precisa ser string nao vazia")
	end
	local companionImageId = template:GetAttribute("CompanionImageId")
	if companionImageId ~= nil and typeof(companionImageId) ~= "string" then
		add(errors, "CompanionImageId precisa ser string")
	end
	for attribute, allowed in pairs(MonsterConfig.Enums) do
		local current = template:GetAttribute(attribute)
		if current ~= nil and not allowed[current] then
			add(errors, attribute .. " invalido: " .. tostring(current))
		end
	end
	local groupMin = tonumber(template:GetAttribute("GroupMin"))
	local groupMax = tonumber(template:GetAttribute("GroupMax"))
	if groupMin and groupMax and groupMin > groupMax then
		add(errors, "GroupMin nao pode ser maior que GroupMax")
	end
	local minimumRound = tonumber(template:GetAttribute("MinimumRound"))
	local maximumRound = tonumber(template:GetAttribute("MaximumRound"))
	if minimumRound and maximumRound and minimumRound > maximumRound then
		add(errors, "MinimumRound nao pode ser maior que MaximumRound")
	end
	local detection = tonumber(template:GetAttribute("DetectionRange") or template:GetAttribute("AggroRange"))
	local lose = tonumber(template:GetAttribute("LoseTargetRange") or template:GetAttribute("LoseAggroRange"))
	if detection and lose and lose < detection then
		add(errors, "LoseTargetRange precisa ser maior ou igual a DetectionRange")
	end
	local hitbox = template:GetAttribute("AttackHitboxSize")
	if hitbox ~= nil and (typeof(hitbox) ~= "Vector3" or hitbox.X <= 0 or hitbox.Y <= 0 or hitbox.Z <= 0) then
		add(errors, "AttackHitboxSize precisa ser Vector3 positivo")
	end
	local offset = template:GetAttribute("AttackOffset")
	if offset ~= nil and typeof(offset) ~= "Vector3" then
		add(errors, "AttackOffset precisa ser Vector3")
	end
	for _, animationName in ipairs({ "Idle", "Walk", "Attack", "Death", "GroundSlam" }) do
		local animationId = template:GetAttribute(animationName .. "AnimationId")
		if
			animationId ~= nil
			and typeof(animationId) ~= "string"
			and typeof(animationId) ~= "number"
		then
			add(errors, animationName .. "AnimationId precisa ser string ou number")
		elseif typeof(animationId) == "number" and animationId <= 0 then
			add(errors, animationName .. "AnimationId precisa ser positivo")
		end
	end
	validateLootTable(template, errors)
	local abilitiesValid, unknownAbilities = AbilityRegistry.Validate(template)
	if not abilitiesValid then
		add(errors, "habilidades desconhecidas: " .. table.concat(unknownAbilities, ", "))
	end
	return #errors == 0, errors
end

function MonsterValidator.Format(errors)
	return table.concat(errors, "; ")
end

return table.freeze(MonsterValidator)
