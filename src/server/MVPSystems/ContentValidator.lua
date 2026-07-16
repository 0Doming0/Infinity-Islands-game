--[[
	BlockParkour MVP - ContentValidator

	Valida os contratos de assets descritos em ROTEIRO_MVP_4_SISTEMAS.md.
	Um template invalido e ignorado isoladamente; os demais continuam disponiveis.
]]

local CollectionService = game:GetService("CollectionService")

local ContentValidator = {}

local SIZE_ORDER = {
	Small = 1,
	Medium = 2,
	Large = 3,
}

local ITEM_TYPES = {
	Armor = true,
	Clothing = true,
	Accessory = true,
	Material = true,
}

local EQUIP_SLOTS = {
	Head = true,
	Torso = true,
	Legs = true,
	Back = true,
	Outfit = true,
	None = true,
}

local function addError(errors, message)
	table.insert(errors, message)
end

local function requireClass(instance, classNames, errors)
	for _, className in ipairs(classNames) do
		if instance:IsA(className) then
			return true
		end
	end

	addError(errors, string.format("classe %s nao permitida", instance.ClassName))
	return false
end

local function requireAttribute(instance, name, expectedType, errors, options)
	options = options or {}
	local value = instance:GetAttribute(name)
	if value == nil then
		if options.Optional then
			return options.Default
		end
		addError(errors, string.format("atributo %s ausente", name))
		return nil
	end

	if typeof(value) ~= expectedType then
		addError(errors, string.format("atributo %s deve ser %s, recebeu %s", name, expectedType, typeof(value)))
		return nil
	end

	if expectedType == "string" and options.NonEmpty and value == "" then
		addError(errors, string.format("atributo %s nao pode ser vazio", name))
	end
	if expectedType == "number" then
		if options.Integer and value ~= math.floor(value) then
			addError(errors, string.format("atributo %s deve ser inteiro", name))
		end
		if options.Min ~= nil and value < options.Min then
			addError(errors, string.format("atributo %s deve ser >= %s", name, tostring(options.Min)))
		end
		if options.Max ~= nil and value > options.Max then
			addError(errors, string.format("atributo %s deve ser <= %s", name, tostring(options.Max)))
		end
	end

	return value
end

local function requireMinimumIslandSize(instance, errors)
	local value = requireAttribute(instance, "MinimumIslandSize", "string", errors, { NonEmpty = true })
	if value and not SIZE_ORDER[value] then
		addError(errors, "MinimumIslandSize deve ser Small, Medium ou Large")
	end
end

local function requirePrimaryPart(model, errors)
	if model:IsA("Model") and not model.PrimaryPart then
		addError(errors, "PrimaryPart nao definida")
	end
end

local function requireHumanoidRig(model, errors)
	if not model:FindFirstChildOfClass("Humanoid") then
		addError(errors, "Humanoid ausente")
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if not root or not root:IsA("BasePart") then
		addError(errors, "HumanoidRootPart ausente")
	end
end

local function validateEnabled(instance, errors)
	requireAttribute(instance, "Enabled", "boolean", errors, { Optional = true, Default = true })
end

local validators = {}

function validators.Collectibles(template, errors)
	if requireClass(template, { "BasePart", "Model" }, errors) then
		requirePrimaryPart(template, errors)
	end
	requireAttribute(template, "CollectibleId", "string", errors, { NonEmpty = true })
	requireAttribute(template, "DisplayName", "string", errors, { NonEmpty = true })
	requireAttribute(template, "ScoreValue", "number", errors, { Integer = true, Min = 0 })
	requireAttribute(template, "CoinValue", "number", errors, { Integer = true, Min = 0 })
	requireAttribute(template, "SpawnWeight", "number", errors, { Min = 0.0001 })
	requireAttribute(template, "BreakRadius", "number", errors, { Min = 1 })
	requireAttribute(template, "MaxPerIsland", "number", errors, { Integer = true, Min = 1 })
	requireAttribute(template, "ParticleColor", "Color3", errors)
	requireAttribute(template, "CollectSoundId", "string", errors, { Optional = true, Default = "" })
	requireMinimumIslandSize(template, errors)
	validateEnabled(template, errors)
end

function validators.Houses(template, errors)
	if requireClass(template, { "Model" }, errors) then
		requirePrimaryPart(template, errors)
	end
	requireAttribute(template, "HouseId", "string", errors, { NonEmpty = true })
	requireAttribute(template, "SpawnWeight", "number", errors, { Min = 0.0001 })
	requireAttribute(template, "SpawnChance", "number", errors, { Min = 0, Max = 1 })
	requireMinimumIslandSize(template, errors)
	requireAttribute(template, "FootprintXCells", "number", errors, { Integer = true, Min = 1 })
	requireAttribute(template, "FootprintZCells", "number", errors, { Integer = true, Min = 1 })
	requireAttribute(template, "ClearanceCells", "number", errors, { Integer = true, Min = 0 })
	local entrance = template:FindFirstChild("Entrance", true)
	if not entrance or not entrance:IsA("Attachment") then
		addError(errors, "Attachment Entrance ausente")
	end
	local villagerSpawnCount = 0
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("Attachment") and string.match(descendant.Name, "^VillagerSpawn_") then
			villagerSpawnCount += 1
			requireAttribute(descendant, "VillagerId", "string", errors, { NonEmpty = true })
		end
	end
	if villagerSpawnCount == 0 then
		addError(errors, "ao menos um Attachment VillagerSpawn_* e obrigatorio")
	end
	validateEnabled(template, errors)
end

function validators.Villagers(template, errors)
	if requireClass(template, { "Model" }, errors) then
		requirePrimaryPart(template, errors)
		requireHumanoidRig(template, errors)
	end
	requireAttribute(template, "VillagerId", "string", errors, { NonEmpty = true })
	requireAttribute(template, "DisplayName", "string", errors, { NonEmpty = true })
	requireAttribute(template, "ShopId", "string", errors, { NonEmpty = true })
	requireAttribute(template, "PromptText", "string", errors, { NonEmpty = true })
	validateEnabled(template, errors)
end

function validators.Monsters(template, errors)
	if requireClass(template, { "Model" }, errors) then
		requirePrimaryPart(template, errors)
		requireHumanoidRig(template, errors)
	end
	requireAttribute(template, "MonsterId", "string", errors, { NonEmpty = true })
	requireAttribute(template, "DisplayName", "string", errors, { NonEmpty = true })
	requireAttribute(template, "MaxHealth", "number", errors, { Min = 1 })
	requireAttribute(template, "WalkSpeed", "number", errors, { Min = 0 })
	requireAttribute(template, "RoamRadius", "number", errors, { Min = 1 })
	requireAttribute(template, "SpawnWeight", "number", errors, { Min = 0.0001 })
	requireAttribute(template, "IslandSpawnChance", "number", errors, { Min = 0, Max = 1 })
	local groupMin = requireAttribute(template, "GroupMin", "number", errors, { Integer = true, Min = 1 })
	local groupMax = requireAttribute(template, "GroupMax", "number", errors, { Integer = true, Min = 1 })
	if groupMin and groupMax and groupMax < groupMin then
		addError(errors, "GroupMax deve ser >= GroupMin")
	end
	requireAttribute(template, "DropChance", "number", errors, { Min = 0, Max = 1 })
	requireAttribute(template, "DeathParticleColor", "Color3", errors)
	requireMinimumIslandSize(template, errors)

	local lootTable = template:FindFirstChild("LootTable")
	if not lootTable or not lootTable:IsA("Folder") then
		addError(errors, "Folder LootTable ausente")
	else
		if #lootTable:GetChildren() == 0 then
			addError(errors, "LootTable precisa de ao menos uma entrada")
		end
		for _, entry in ipairs(lootTable:GetChildren()) do
			if not entry:IsA("Configuration") then
				addError(errors, string.format("LootTable/%s deve ser Configuration", entry.Name))
			else
				requireAttribute(entry, "ItemId", "string", errors, { NonEmpty = true })
				requireAttribute(entry, "Weight", "number", errors, { Min = 0.0001 })
				local minimum = requireAttribute(entry, "MinAmount", "number", errors, { Integer = true, Min = 1 })
				local maximum = requireAttribute(entry, "MaxAmount", "number", errors, { Integer = true, Min = 1 })
				if minimum and maximum and maximum < minimum then
					addError(errors, string.format("LootTable/%s: MaxAmount deve ser >= MinAmount", entry.Name))
				end
			end
		end
	end
	validateEnabled(template, errors)
end

function validators.Items(template, errors)
	requireClass(template, { "Folder", "Model", "Accessory" }, errors)
	requireAttribute(template, "ItemId", "string", errors, { NonEmpty = true })
	requireAttribute(template, "DisplayName", "string", errors, { NonEmpty = true })
	local itemType = requireAttribute(template, "ItemType", "string", errors, { NonEmpty = true })
	if itemType and not ITEM_TYPES[itemType] then
		addError(errors, "ItemType invalido")
	end
	local equipSlot = requireAttribute(template, "EquipSlot", "string", errors, { NonEmpty = true })
	if equipSlot and not EQUIP_SLOTS[equipSlot] then
		addError(errors, "EquipSlot invalido")
	end
	requireAttribute(template, "BuyPrice", "number", errors, { Min = 0 })
	requireAttribute(template, "Stackable", "boolean", errors)
	requireAttribute(template, "MaxHealthBonus", "number", errors, { Min = 0 })
	requireAttribute(template, "WaterResistance", "number", errors, { Min = 0, Max = 0.5 })
	requireAttribute(template, "IconAssetId", "string", errors, { Optional = true, Default = "" })
	validateEnabled(template, errors)
end

function validators.Shops(template, errors)
	if not template:IsA("Folder") then
		addError(errors, "loja deve ser Folder")
	end
	if template.Name == "" then
		addError(errors, "ShopId (nome do Folder) nao pode ser vazio")
	end
	for _, product in ipairs(template:GetChildren()) do
		if not product:IsA("Configuration") then
			addError(errors, string.format("produto %s deve ser Configuration", product.Name))
		else
			requireAttribute(product, "ItemId", "string", errors, { NonEmpty = true })
			requireAttribute(product, "PriceOverride", "number", errors, { Min = 0 })
			requireAttribute(product, "Enabled", "boolean", errors)
		end
	end
end

function validators.Tools(template, errors)
	if not template:IsA("Tool") then
		addError(errors, "ferramenta deve ser Tool")
		return
	end
	requireAttribute(template, "Damage", "number", errors, { Min = 0.01 })
	requireAttribute(template, "AttackRange", "number", errors, { Min = 1 })
	requireAttribute(template, "AttackCooldown", "number", errors, { Min = 0.05 })
	if not CollectionService:HasTag(template, "DamageTool") then
		addError(errors, "tag DamageTool ausente")
	end
end

function ContentValidator.GetIdAttribute(category)
	return ({
		Collectibles = "CollectibleId",
		Houses = "HouseId",
		Villagers = "VillagerId",
		Monsters = "MonsterId",
		Items = "ItemId",
	})[category]
end

function ContentValidator.GetContentId(category, template)
	local attributeName = ContentValidator.GetIdAttribute(category)
	if attributeName then
		return template:GetAttribute(attributeName)
	end
	if category == "Shops" or category == "Tools" then
		return template.Name
	end
	return nil
end

function ContentValidator.Validate(category, template)
	local validator = validators[category]
	if not validator then
		return false, { "categoria desconhecida: " .. tostring(category) }
	end

	local errors = {}
	validator(template, errors)
	return #errors == 0, errors
end

function ContentValidator.Warn(category, template, errors)
	local path = template:GetFullName()
	for _, message in ipairs(errors) do
		warn(string.format("[MVP ContentValidator] %s/%s: %s", category, path, message))
	end
end

return ContentValidator
