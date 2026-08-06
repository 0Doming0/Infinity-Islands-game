local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)

local PhaseRegistry = {}

local REQUIRED_FOLDERS = {
	"Islands",
	"Enemies",
	"Bosses",
	"Decorations",
}

local MATERIALS = {}
for _, material in ipairs(Enum.Material:GetEnumItems()) do
	MATERIALS[material.Name] = material
end

local function addError(errors, message)
	table.insert(errors, message)
end

local function numberAttribute(folder, name, defaultValue, minimum, maximum, errors)
	local value = folder:GetAttribute(name)
	if value == nil then
		return defaultValue
	end
	if typeof(value) ~= "number" then
		addError(errors, name .. " precisa ser Number")
		return defaultValue
	end
	if minimum and value < minimum or maximum and value > maximum then
		addError(errors, name .. " esta fora do intervalo permitido")
		return defaultValue
	end
	return value
end

local function stringAttribute(folder, name, defaultValue, required, errors)
	local value = folder:GetAttribute(name)
	if value == nil then
		value = defaultValue
	end
	if typeof(value) ~= "string" then
		addError(errors, name .. " precisa ser String")
		return defaultValue
	end
	if required and value == "" then
		addError(errors, name .. " nao pode ficar vazio")
	end
	return value
end

local function findBoss(bosses, bossId)
	local exact = bosses and bosses:FindFirstChild(bossId, true)
	if exact and exact:IsA("Model") then
		return exact
	end
	if bosses then
		for _, candidate in ipairs(bosses:GetDescendants()) do
			if candidate:IsA("Model") and candidate:GetAttribute("BossId") == bossId then
				return candidate
			end
		end
	end
	return nil
end

local function hasArena(islands)
	local arenaFolder = islands and islands:FindFirstChild("BossArena")
	return arenaFolder
		and (arenaFolder:FindFirstChildWhichIsA("Model") or arenaFolder:FindFirstChildWhichIsA("BasePart"))
		or nil
end

local function validateEnemyFolder(enemies, errors)
	local usable = 0
	if not enemies then
		return 0
	end
	for _, model in ipairs(enemies:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Enabled") ~= false then
			local monsterId = model:GetAttribute("MonsterId")
			if typeof(monsterId) ~= "string" or monsterId == "" then
				addError(errors, model.Name .. " precisa do Attribute MonsterId")
			elseif not model:FindFirstChildWhichIsA("Humanoid", true) then
				addError(errors, model.Name .. " nao possui Humanoid")
			elseif not (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart", true)) then
				addError(errors, model.Name .. " nao possui PrimaryPart ou HumanoidRootPart")
			else
				usable += 1
			end
		end
	end
	if usable == 0 then
		addError(errors, "Enemies nao possui nenhum mob valido e habilitado")
	end
	return usable
end

local function validatePhaseFolder(folder)
	local errors = {}
	if folder:GetAttribute("Enabled") == false or string.sub(folder.Name, 1, 1) == "_" then
		return nil, errors, true
	end

	local phaseId = stringAttribute(folder, "PhaseId", folder.Name, true, errors)
	if not string.match(phaseId, "^[%w_-]+$") then
		addError(errors, "PhaseId aceita apenas letras, numeros, _ e -")
	end
	local categories = {}
	for _, name in ipairs(REQUIRED_FOLDERS) do
		local category = folder:FindFirstChild(name)
		if not category or not category:IsA("Folder") then
			addError(errors, "pasta obrigatoria ausente: " .. name)
		else
			categories[name] = category
		end
	end
	local islands = categories.Islands
	if islands then
		for _, name in ipairs({ "Common", "Special", "BossArena" }) do
			if not islands:FindFirstChild(name) then
				addError(errors, "Islands/" .. name .. " esta ausente")
			end
		end
	end

	validateEnemyFolder(categories.Enemies, errors)
	local allowPrototype = folder:GetAttribute("AllowPrototypeContent") == true
	local bossId = stringAttribute(folder, "BossId", "GiantBoss", true, errors)
	local boss = findBoss(categories.Bosses, bossId)
	if not boss and not allowPrototype then
		addError(errors, "Bosses nao possui o BossId " .. bossId)
	elseif boss and (not boss:FindFirstChildWhichIsA("Humanoid", true)
		or not (boss.PrimaryPart or boss:FindFirstChild("HumanoidRootPart", true))) then
		addError(errors, "boss " .. boss.Name .. " precisa de Humanoid e PrimaryPart/HumanoidRootPart")
	end
	if islands and not hasArena(islands) and not allowPrototype then
		addError(errors, "Islands/BossArena nao possui Model ou BasePart")
	end

	local materialName = stringAttribute(folder, "IslandBlockMaterial", "Ground", true, errors)
	if not MATERIALS[materialName] then
		addError(errors, "IslandBlockMaterial invalido: " .. materialName)
		materialName = "Ground"
	end
	local color = folder:GetAttribute("IslandBlockColor")
	if color == nil then
		color = Color3.fromRGB(112, 78, 48)
	elseif typeof(color) ~= "Color3" then
		addError(errors, "IslandBlockColor precisa ser Color3")
		color = Color3.fromRGB(112, 78, 48)
	end
	local textureId = stringAttribute(folder, "IslandBlockTextureId", "", false, errors)
	if textureId ~= "" and not string.match(textureId, "^rbxassetid://%d+$") then
		addError(errors, "IslandBlockTextureId precisa usar rbxassetid://NUMERO ou ficar vazio")
	end
	local imageId = stringAttribute(folder, "ImageId", "", false, errors)
	if imageId ~= "" and not string.match(imageId, "^rbxassetid://%d+$") then
		addError(errors, "ImageId precisa usar rbxassetid://NUMERO ou ficar vazio")
	end

	local definition = {
		PhaseId = phaseId,
		DisplayName = stringAttribute(folder, "DisplayName", phaseId, true, errors),
		RequiredLevel = math.floor(numberAttribute(folder, "RequiredLevel", 1, 1, nil, errors)),
		MaxPlayers = math.floor(numberAttribute(folder, "MaxPlayers", 4, 1, 4, errors)),
		AssetFolder = folder.Name,
		BossId = bossId,
		BaseIslandCount = math.floor(numberAttribute(folder, "MaximumIslandCount", 10, 1, 100, errors)),
		VictoryCoins = math.floor(numberAttribute(folder, "VictoryCoins", 0, 0, nil, errors)),
		ImageId = imageId,
		SortOrder = math.floor(numberAttribute(folder, "SortOrder", 0, nil, nil, errors)),
		Enabled = true,
		IslandBlockColor = color,
		IslandBlockMaterial = materialName,
		IslandBlockTextureId = textureId,
		TextureStudsPerTileU = numberAttribute(folder, "TextureStudsPerTileU", 4, 0.1, 128, errors),
		TextureStudsPerTileV = numberAttribute(folder, "TextureStudsPerTileV", 4, 0.1, 128, errors),
		MaximumActiveMonsters = math.floor(numberAttribute(folder, "MaximumActiveMonsters", 45, 1, 200, errors)),
		EliteReservedMonsterSlots = math.floor(numberAttribute(folder, "EliteReservedMonsterSlots", 3, 0, 20, errors)),
		DefaultMonsterSpawnChance = numberAttribute(folder, "DefaultMonsterSpawnChance", 0.72, 0, 1, errors),
		DecorationSpawnChance = numberAttribute(folder, "DecorationSpawnChance", 0.7, 0, 1, errors),
		AllowPrototypeContent = allowPrototype,
	}
	if definition.EliteReservedMonsterSlots >= definition.MaximumActiveMonsters then
		addError(errors, "EliteReservedMonsterSlots precisa ser menor que MaximumActiveMonsters")
	end
	return #errors == 0 and definition or nil, errors, false
end

local function publicCatalog()
	local result = {}
	for _, entry in ipairs(PhaseConfig.GetAllSorted()) do
		table.insert(result, PhaseConfig.ToPublicSnapshot(entry.PhaseId))
	end
	return result
end

function PhaseRegistry.PublishCatalog()
	local phases = publicCatalog()
	if #phases == 0 then
		return false, "nenhuma fase valida para publicar"
	end
	local serialized = HttpService:JSONEncode(phases)
	local store = DataStoreService:GetDataStore(PhaseConfig.CatalogDataStoreName)
	local ok, errorMessage = pcall(function()
		store:UpdateAsync(PhaseConfig.CatalogDataStoreKey, function(previous)
			if type(previous) == "table"
				and previous.Version == PhaseConfig.CatalogVersion
				and previous.Content == serialized
			then
				return previous
			end
			return {
				Version = PhaseConfig.CatalogVersion,
				UpdatedAt = os.time(),
				Content = serialized,
				Phases = phases,
			}
		end)
	end)
	workspace:SetAttribute("DungeonPhaseCatalogPublished", ok)
	if not ok then
		warn("[PhaseRegistry] Catalogo do Lobby nao publicado: " .. tostring(errorMessage))
	end
	return ok, errorMessage
end

function PhaseRegistry.Refresh(options)
	options = options or {}
	local root = ServerStorage:FindFirstChild("GameContent")
	local phasesFolder = root and root:FindFirstChild("Phases")
	local definitions = {}
	local seen = {}
	local duplicateIds = {}
	if not phasesFolder then
		warn("[PhaseRegistry] ServerStorage/GameContent/Phases nao existe.")
		PhaseConfig.Install({}, "DungeonFolders")
		return false, 0
	end
	for _, folder in ipairs(phasesFolder:GetChildren()) do
		if folder:IsA("Folder") then
			local definition, errors, skipped = validatePhaseFolder(folder)
			if definition then
				if seen[definition.PhaseId] or duplicateIds[definition.PhaseId] then
					warn("[PhaseRegistry] PhaseId duplicado: " .. definition.PhaseId)
					definitions[definition.PhaseId] = nil
					duplicateIds[definition.PhaseId] = true
				else
					seen[definition.PhaseId] = true
					definitions[definition.PhaseId] = definition
				end
			elseif not skipped then
				warn(string.format(
					"[PhaseRegistry] Fase %s desativada: %s",
					folder.Name,
					table.concat(errors, "; ")
				))
			end
		end
	end
	local count = PhaseConfig.Install(definitions, "DungeonFolders")
	workspace:SetAttribute("DungeonRegisteredPhaseCount", count)
	workspace:SetAttribute("DungeonPhaseRegistryReady", count > 0)
	if count > 0 and options.Publish ~= false then
		task.spawn(PhaseRegistry.PublishCatalog)
	end
	return count > 0, count
end

return PhaseRegistry
