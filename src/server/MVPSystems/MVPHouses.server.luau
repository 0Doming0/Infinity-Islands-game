--[[
	SkyDungeon - Vila procedural do MVP

	Cria uma pequena vila deterministica em MainHalls medias/grandes. Aceita
	modelos reais em ServerStorage/MVPAssets/Village e usa modelos de exemplo
	por codigo quando as pastas estiverem vazias.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local VillageShopCatalog = require(ReplicatedStorage:WaitForChild("VillageShopCatalog"))
local VILLAGE_CONFIG = MVPConfig.Village
local processedIslands = setmetatable({}, { __mode = "k" })
local warnedMissingVillagerTemplates = {}
local loggedVillagerTemplateResolution = {}
local warnedInvalidVillagerTemplates = {}
local SKY_MERCHANT_SPAWNER_VERSION = "PersonalOnlyThematicStandV4"
local PERSONAL_MERCHANT_ASSET_FOLDER = "PersonalSkyMerchantAssets"

workspace:SetAttribute("SkyMerchantSpawnerVersion", SKY_MERCHANT_SPAWNER_VERSION)
workspace:SetAttribute("SkyMerchantSpawnerScriptName", script.Name)
local spawnerScriptCount = 0
for _, descendant in ipairs(ServerScriptService:GetDescendants()) do
	if descendant:IsA("BaseScript")
		and string.find(string.lower(descendant.Name), "mvphouses", 1, true)
	then
		spawnerScriptCount += 1
	end
end
workspace:SetAttribute("SkyMerchantSpawnerScriptCount", spawnerScriptCount)
if spawnerScriptCount > 1 then
	warn(string.format(
		"[MVP Village][SkyMerchant] Existem %d scripts MVPHouses ativos. Mantenha somente MVPHouses.server.luau.",
		spawnerScriptCount
	))
end
if script.Name ~= "MVPHouses" then
	warn(string.format(
		"[MVP Village][SkyMerchant] Script carregado como '%s'. No projeto ele deve se chamar MVPHouses.server.luau.",
		script.Name
	))
end

local function isTerrainIsland(instance)
	return instance:IsA("Model")
		and instance:GetAttribute("IsSkyIsland") == true
end

local function getIslandGenerationKey(island)
	return string.format(
		"%s:%s:%s",
		tostring(island:GetAttribute("IslandNodeKey") or ""),
		tostring(island:GetAttribute("IslandSeed") or ""),
		tostring(island:GetAttribute("RoundIndex") or "")
	)
end

local function getTemplateFolders(category)
	local folders = {}
	local seen = {}
	local function append(folder)
		if folder
			and not seen[folder]
			and #folder:GetChildren() > 0
		then
			seen[folder] = true
			table.insert(folders, folder)
		end
	end

	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local village = assets and assets:FindFirstChild("Village")
	local preferred = village and village:FindFirstChild(category)
	local preferredHasChildren = preferred and #preferred:GetChildren() > 0
	if preferredHasChildren then
		append(preferred)
	end
	-- ContentRegistry e o README usam MVPAssets/<Categoria>. A versao anterior
	-- do gerador ignorava especificamente MVPAssets/Villagers, mesmo sendo o
	-- local oficial dos modelos validados do projeto.
	if assets then
		append(assets:FindFirstChild(category))
	end
	local legacyName = category == "Buildings" and "MVPBuildings" or "MVPVillagers"
	local legacy = ServerStorage:FindFirstChild(legacyName)
	if legacy
		and legacy ~= preferred
		and (category == "Villagers" or not preferredHasChildren)
	then
		append(legacy)
	end
	return folders
end

local function isUsableVisualTemplate(instance)
	if not instance.Archivable then
		return false
	end
	if instance:IsA("BasePart") then
		return instance.Transparency < 1 and instance.Size.Magnitude > 0.1
	end
	if not instance:IsA("Model") then
		return false
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Transparency < 1
			and descendant.Size.Magnitude > 0.1
		then
			return true
		end
	end
	return false
end

local function isReservedSkyMerchantTemplate(instance)
	local lowerName = string.lower(instance.Name)
	return lowerName == "skymechant"
		or lowerName == "skymerchant"
		or instance:GetAttribute("ReservedForSkyMerchant") == true
		or instance:GetAttribute("ShopId") == VillageShopCatalog.GetSkyMerchantShopId()
end

local function merchantTemplatePriority(instance)
	if instance.Name == "SkyMerchant" then
		return 1
	end
	if instance.Name == "SkyMechant" then
		return 2
	end
	if string.lower(instance.Name) == "skymerchant" then
		return 3
	end
	if string.lower(instance.Name) == "skymechant" then
		return 4
	end
	if instance:GetAttribute("ReservedForSkyMerchant") == true then
		return 5
	end
	if instance:GetAttribute("ShopId") == VillageShopCatalog.GetSkyMerchantShopId() then
		return 6
	end
	return math.huge
end

local function findReservedSkyMerchantTemplate()
	local candidates = {}
	local seen = {}
	local function append(candidate)
		if candidate:IsA("Model")
			and not seen[candidate]
			and isReservedSkyMerchantTemplate(candidate)
			and isUsableVisualTemplate(candidate)
		then
			seen[candidate] = true
			table.insert(candidates, candidate)
		end
	end
	for _, folder in ipairs(getTemplateFolders("Villagers")) do
		for _, child in ipairs(folder:GetChildren()) do
			append(child)
		end
	end
	-- Compatibilidade com projetos que guardaram o modelo em outro ponto de
	-- ServerStorage. O nome exato continua sendo suficiente para reserva-lo.
	for _, descendant in ipairs(ServerStorage:GetDescendants()) do
		append(descendant)
	end
	table.sort(candidates, function(left, right)
		local leftPriority = merchantTemplatePriority(left)
		local rightPriority = merchantTemplatePriority(right)
		if leftPriority ~= rightPriority then
			return leftPriority < rightPriority
		end
		return left:GetFullName() < right:GetFullName()
	end)
	return candidates[1]
end

local function publishReservedSkyMerchantTemplate()
	local assets = ReplicatedStorage:FindFirstChild(PERSONAL_MERCHANT_ASSET_FOLDER)
	if assets and not assets:IsA("Folder") then
		assets:Destroy()
		assets = nil
	end
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = PERSONAL_MERCHANT_ASSET_FOLDER
		assets.Parent = ReplicatedStorage
	end
	assets:ClearAllChildren()
	local template = findReservedSkyMerchantTemplate()
	if not template then
		assets:SetAttribute("TemplateState", "NotFound")
		workspace:SetAttribute("PersonalSkyMerchantTemplateState", "FallbackVillager")
		workspace:SetAttribute("PersonalSkyMerchantTemplatePath", nil)
		return
	end
	local success, cloneOrError = pcall(template.Clone, template)
	if not success or not cloneOrError or not cloneOrError:IsA("Model") then
		assets:SetAttribute("TemplateState", "CloneFailed")
		workspace:SetAttribute("PersonalSkyMerchantTemplateState", "CloneFailed")
		warn(string.format(
			"[MVP Village][SkyMerchant] Nao foi possivel publicar '%s': %s",
			template:GetFullName(),
			tostring(cloneOrError)
		))
		return
	end
	local clone = cloneOrError
	clone:SetAttribute("ReservedForSkyMerchant", true)
	clone:SetAttribute("SourceVillagerTemplatePath", template:GetFullName())
	clone.Parent = assets
	assets:SetAttribute("TemplateState", "Published")
	assets:SetAttribute("PreferredTemplateName", clone.Name)
	workspace:SetAttribute("PersonalSkyMerchantTemplateState", "Published")
	workspace:SetAttribute("PersonalSkyMerchantTemplatePath", template:GetFullName())
end

local function getTemplates(category)
	local result = {}
	for _, folder in ipairs(getTemplateFolders(category)) do
		for _, child in ipairs(folder:GetChildren()) do
			if isUsableVisualTemplate(child)
				and (
					category ~= "Villagers"
					or not isReservedSkyMerchantTemplate(child)
				)
			then
				table.insert(result, child)
			end
		end
	end
	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)
	return result
end

local function prepareStatic(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("ProximityPrompt") then
			-- O visual sorteado nao pode trazer uma loja ou interacao antiga.
			-- O VillagerSystem cria um prompt novo usando o ShopId sorteado.
			descendant:Destroy()
		elseif descendant:IsA("BillboardGui") and descendant.Name == "VillageShopLabel" then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
		end
	end
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanTouch = false
	end
end

local function alignToSurface(instance, position, yaw)
	local model
	if instance:IsA("Model") then
		model = instance
	else
		model = Instance.new("Model")
		instance.Parent = model
		model.PrimaryPart = instance
	end
	prepareStatic(model)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	local bottom = math.huge
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Transparency < 1
			and descendant.Size.Magnitude > 0.1
		then
			local cframe = descendant.CFrame
			local size = descendant.Size
			local halfHeight = (
				math.abs(cframe.XVector.Y) * size.X
				+ math.abs(cframe.YVector.Y) * size.Y
				+ math.abs(cframe.ZVector.Y) * size.Z
			) / 2
			bottom = math.min(bottom, descendant.Position.Y - halfHeight)
		end
	end
	if bottom == math.huge then
		local boxCFrame, boxSize = model:GetBoundingBox()
		bottom = boxCFrame.Position.Y - boxSize.Y / 2
	end
	model:PivotTo(model:GetPivot() + Vector3.new(0, position.Y - bottom, 0))
	return model
end

local function makePart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createExampleBuilding(index, surfacePosition, yaw)
	local model = Instance.new("Model")
	model.Name = index == 1 and "ExampleSwordShop" or "ExampleVillageHouse"
	local base = CFrame.new(surfacePosition) * CFrame.Angles(0, yaw, 0)
	local wallColor = index == 1 and Color3.fromRGB(182, 132, 78) or Color3.fromRGB(151, 112, 72)
	local floor = makePart(model, "Floor", Vector3.new(9, 0.8, 8), base * CFrame.new(0, 0.4, 0), Color3.fromRGB(100, 75, 52), Enum.Material.WoodPlanks)
	makePart(model, "BackWall", Vector3.new(9, 5.5, 0.6), base * CFrame.new(0, 3.15, 3.7), wallColor, Enum.Material.WoodPlanks)
	makePart(model, "LeftWall", Vector3.new(0.6, 5.5, 7.4), base * CFrame.new(-4.2, 3.15, 0), wallColor, Enum.Material.WoodPlanks)
	makePart(model, "RightWall", Vector3.new(0.6, 5.5, 7.4), base * CFrame.new(4.2, 3.15, 0), wallColor, Enum.Material.WoodPlanks)
	local roof = makePart(model, "Roof", Vector3.new(10, 0.75, 9), base * CFrame.new(0, 6.1, 0), Color3.fromRGB(78, 45, 38), Enum.Material.Slate)
	roof.CFrame *= CFrame.Angles(0, 0, math.rad(index == 1 and 5 or -5))
	local sign = makePart(model, "Sign", Vector3.new(4.6, 1.25, 0.3), base * CFrame.new(0, 4.7, -3.9), Color3.fromRGB(63, 42, 28), Enum.Material.Wood)
	if index == 1 then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "ESPADAS"
		label.TextColor3 = Color3.fromRGB(255, 225, 115)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
	end
	model.PrimaryPart = floor
	model:SetAttribute("ExampleModel", true)
	return model
end

local function createExampleVillager(surfacePosition, yaw, shop)
	local model = Instance.new("Model")
	model.Name = "Example" .. shop.ShopId
	local root = makePart(model, "HumanoidRootPart", Vector3.new(1.6, 2.2, 1.2), CFrame.new(surfacePosition + Vector3.new(0, 1.1, 0)), Color3.fromRGB(65, 48, 38), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.CanCollide = false
	local base = CFrame.new(surfacePosition) * CFrame.Angles(0, yaw, 0)
	makePart(model, "Body", Vector3.new(2.5, 3.2, 1.4), base * CFrame.new(0, 2.2, 0), shop.Color, Enum.Material.Fabric).CanCollide = false
	local head = makePart(model, "Head", Vector3.new(1.8, 1.8, 1.8), base * CFrame.new(0, 4.7, 0), Color3.fromRGB(231, 190, 145), Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	head.CanCollide = false
	makePart(model, "Hat", Vector3.new(2.5, 0.45, 2.5), base * CFrame.new(0, 5.65, 0), Color3.fromRGB(95, 50, 125), Enum.Material.Fabric).CanCollide = false
	model.PrimaryPart = root
	model:SetAttribute("ExampleModel", true)
	return model
end

local function clearVillageArea(island, positions)
	local content = island:FindFirstChild("MVPContent")
	if not content then
		return
	end
	for _, descendant in ipairs(content:GetDescendants()) do
		if descendant:IsA("BasePart") then
			for _, position in ipairs(positions) do
				local flatDistance = (Vector2.new(descendant.Position.X, descendant.Position.Z) - Vector2.new(position.X, position.Z)).Magnitude
				if flatDistance < 7 then
					descendant:Destroy()
					break
				end
			end
		end
	end
end

local function chooseTemplate(templates, random)
	if #templates == 0 then
		return nil
	end
	return templates[random:NextInteger(1, #templates)]
end

local function chooseVillagerTemplate(templates, random, usedTemplates)
	if #templates == 0 then
		return nil
	end
	local available = {}
	for _, template in ipairs(templates) do
		if not usedTemplates or not usedTemplates[template] then
			table.insert(available, template)
		end
	end
	if #available == 0 then
		available = templates
	end
	local template = chooseTemplate(available, random)
	if template and usedTemplates then
		usedTemplates[template] = true
	end
	return template
end

local function spawnBuilding(parent, templates, index, position, yaw, random)
	local template = chooseTemplate(templates, random)
	local model
	if template then
		model = alignToSurface(template:Clone(), position, yaw)
	else
		model = createExampleBuilding(index, position, yaw)
	end
	model.Name = string.format("Building_%02d_%s", index, model.Name)
	model.Parent = parent
	return model
end

local function spawnVillager(parent, templates, position, yaw, random, shop, index, usedTemplates)
	local availableTemplates = table.clone(templates)
	local template
	local model

	while #availableTemplates > 0 and not model do
		template = chooseVillagerTemplate(availableTemplates, random, usedTemplates)
		local templateIndex = template and table.find(availableTemplates, template)
		if not templateIndex then
			break
		end
		table.remove(availableTemplates, templateIndex)
		local clone
		local success, cloneOrError = pcall(function()
			clone = template:Clone()
			assert(clone, "Clone retornou nil; confira Archivable")
			return alignToSurface(clone, position, yaw)
		end)
		if success then
			model = cloneOrError
		else
			if clone then
				clone:Destroy()
			end
			if not warnedInvalidVillagerTemplates[template] then
				warn(string.format(
					"[MVP Village] Modelo de villager '%s' foi ignorado: %s",
					template:GetFullName(),
					tostring(cloneOrError)
				))
				warnedInvalidVillagerTemplates[template] = true
			end
		end
	end

	if model and template then
		CollectionService:RemoveTag(model, VILLAGE_CONFIG.ShopTag)
		model:SetAttribute("SourceVillagerTemplate", template.Name)
		model:SetAttribute("SourceVillagerTemplatePath", template:GetFullName())
		model:SetAttribute(
			"TemplateResolution",
			template:IsDescendantOf(ServerStorage) and "RandomStoredVillager" or "RandomRuntimeVillager"
		)
		local resolutionKey = shop.ShopId .. ":" .. template:GetFullName()
		if not loggedVillagerTemplateResolution[resolutionKey] then
			print(string.format(
				"[MVP Village] Modelo aleatorio '%s' aplicado a %s (ShopId=%s).",
				template:GetFullName(),
				shop.DisplayName,
				shop.ShopId
			))
			loggedVillagerTemplateResolution[resolutionKey] = true
		end
	else
		if not warnedMissingVillagerTemplates[shop.ShopId] then
			warn(string.format(
				"[MVP Village] Nenhum modelo encontrado para %s (ShopId=%s); usando modelo de exemplo.",
				shop.DisplayName,
				shop.ShopId
			))
			warnedMissingVillagerTemplates[shop.ShopId] = true
		end
		model = createExampleVillager(position, yaw, shop)
		model:SetAttribute("TemplateResolution", "GeneratedFallback")
	end
	model.Name = string.format("Villager_%02d_%s", index, shop.ShopId)
	model:SetAttribute("IsVillager", true)
	model:SetAttribute("ShopId", shop.ShopId)
	model:SetAttribute("MerchantDisplayName", shop.DisplayName)
	model:SetAttribute("NoSwordDamage", true)
	model:SetAttribute("Invulnerable", true)
	model.Parent = parent
	CollectionService:AddTag(model, VILLAGE_CONFIG.ShopTag)
	return model
end

local function shuffle(values, random)
	for index = #values, 2, -1 do
		local other = random:NextInteger(1, index)
		values[index], values[other] = values[other], values[index]
	end
	return values
end

local function shouldSpawnVillage(island, random)
	local roundIndex = tonumber(island:GetAttribute("RoundIndex")) or 0
	local size = island:GetAttribute("TerrainSize")
	local role = island:GetAttribute("IslandRole")
	if island:GetAttribute("IsSocialSanctuary") == true then
		return true
	end
	if island:GetAttribute("IslandType") ~= "Normal"
		or roundIndex < VILLAGE_CONFIG.MinimumRound
		or role ~= "MainHall"
	then
		return false
	end
	if size ~= "Medium" and size ~= "Large" then
		return false
	end
	if roundIndex % VILLAGE_CONFIG.GuaranteedEveryRounds == 0 then
		return true
	end
	local chance = size == "Large" and VILLAGE_CONFIG.LargeChance or VILLAGE_CONFIG.MediumChance
	return random:NextNumber() <= chance
end

local function removeRuntimeMonsters(island)
	for _, descendant in ipairs(island:GetDescendants()) do
		if descendant:IsA("Model") and (
			descendant:GetAttribute("RuntimeMonster") == true
			or CollectionService:HasTag(descendant, "CombatTarget")
		) then
			descendant:Destroy()
		end
	end
end

local function removeLegacySharedSkyMerchant(instance)
	if not instance or not instance.Parent then
		return false
	end
	local isLegacyFolder = instance:IsA("Folder")
		and (
			instance.Name == "MVPRandomSkyMerchant"
			or instance.Name == "MVPSoloMerchant"
			or instance:GetAttribute("RandomMapMerchant") == true
			or instance:GetAttribute("ProceduralSoloMerchant") == true
		)
	local isLegacyModel = instance:IsA("Model")
		and instance:GetAttribute("ShopId") == VillageShopCatalog.GetSkyMerchantShopId()
	if not isLegacyFolder and not isLegacyModel then
		return false
	end
	instance:Destroy()
	return true
end

local function clearLegacyMerchantReservation(island)
	island:SetAttribute("SoloMerchantReserved", false)
	island:SetAttribute("SoloMerchantRoll", nil)
	island:SetAttribute("SoloMerchantChance", nil)
end

local function populateIsland(island)
	if not island:IsDescendantOf(workspace) then
		return
	end
	local generationKey = getIslandGenerationKey(island)
	if processedIslands[island] == generationKey then
		return
	end
	local floor = island:FindFirstChild("IslandFloor")
	local deadline = os.clock() + 2
	while not floor and island:IsDescendantOf(workspace) and os.clock() < deadline do
		task.wait()
		floor = island:FindFirstChild("IslandFloor")
	end
	if not island:IsDescendantOf(workspace) or not floor or not floor:IsA("BasePart") then
		return
	end
	generationKey = getIslandGenerationKey(island)
	if processedIslands[island] == generationKey then
		return
	end
	processedIslands[island] = generationKey

	local seed = (tonumber(island:GetAttribute("IslandSeed")) or 1) + VILLAGE_CONFIG.RandomSalt
	seed = math.floor(math.abs(seed)) % 2147483647
	local random = Random.new(seed == 0 and 1 or seed)
	-- O layout e as profissoes continuam deterministas pela seed da ilha, mas
	-- os visuais mudam entre novas geracoes/sessoes.
	local visualRandom = Random.new()
	local createVillage = shouldSpawnVillage(island, random)
	-- O Mercador do Ceu e exclusivamente local e pessoal. O gerador do mapa
	-- nunca reserva uma ilha, nunca remove mobs por causa dele e nunca cria um
	-- NPC compartilhado.
	if not createVillage then
		return
	end

	island:SetAttribute("VillageSpawned", true)
	island:SetAttribute("SoloMerchantSpawned", false)
	island:SetAttribute("CanSpawnMonster", false)
	island:SetAttribute("CanSpawnItem", false)
	removeRuntimeMonsters(island)

	local surfaceY = floor.Position.Y + floor.Size.Y / 2 + 0.05
	local radius = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.25, 8, 13)
	local center = Vector3.new(floor.Position.X, surfaceY, floor.Position.Z)
	local angle = random:NextNumber(0, math.pi * 2)
	local buildingCount = random:NextInteger(VILLAGE_CONFIG.MinimumBuildingCount, VILLAGE_CONFIG.MaximumBuildingCount)
	local shopIds = VillageShopCatalog.GetShopIds()
	-- Toda vila mantém o ferreiro para não bloquear a progressão principal.
	-- As demais profissões continuam aleatórias e nunca se repetem.
	for index, shopId in ipairs(shopIds) do
		if shopId == "Blacksmith" then
			table.remove(shopIds, index)
			break
		end
	end
	shuffle(shopIds, random)
	table.insert(shopIds, 1, "Blacksmith")
	local villagerCount = math.min(
		random:NextInteger(VILLAGE_CONFIG.MinimumVillagerCount, VILLAGE_CONFIG.MaximumVillagerCount),
		#shopIds
	)
	local positions = { center }
	for index = 1, buildingCount do
		local theta = angle + ((index - 1) / buildingCount) * math.pi * 2
		table.insert(positions, center + Vector3.new(math.cos(theta) * radius, 0, math.sin(theta) * radius))
	end
	local villagerPositions = {}
	local villagerRadius = math.clamp(radius * 0.32, 2.8, 4.2)
	for index = 1, villagerCount do
		local theta = angle + math.pi / 4 + ((index - 1) / villagerCount) * math.pi * 2
		local position = center + Vector3.new(math.cos(theta) * villagerRadius, 0, math.sin(theta) * villagerRadius)
		table.insert(villagerPositions, position)
		table.insert(positions, position)
	end
	clearVillageArea(island, positions)

	local village = Instance.new("Folder")
	village.Name = "MVPVillage"
	village:SetAttribute("ProceduralVillage", true)
	village:SetAttribute("VillageSeed", seed)
	village.Parent = island

	local buildings = getTemplates("Buildings")
	local villagers = getTemplates("Villagers")
	local usedVillagerTemplates = {}
	for index = 1, buildingCount do
		local position = positions[index + 1]
		local yaw = math.atan2(center.X - position.X, center.Z - position.Z)
		spawnBuilding(village, buildings, index, position, yaw, random)
	end
	for index = 1, villagerCount do
		local shop = VillageShopCatalog.GetShop(shopIds[index])
		local position = villagerPositions[index]
		local yaw = math.atan2(center.X - position.X, center.Z - position.Z)
		spawnVillager(village, villagers, position, yaw, visualRandom, shop, index, usedVillagerTemplates)
	end

	local pad = makePart(
		village,
		"VillageSquare",
		Vector3.new(math.min(12, radius), 0.35, math.min(12, radius)),
		CFrame.new(center + Vector3.new(0, 0.175, 0)),
		Color3.fromRGB(118, 118, 112),
		Enum.Material.Cobblestone
	)
	pad.CanCollide = true
	print(string.format(
		"[MVP Village] Vila procedural criada em %s com %d aldeoes.",
		island:GetFullName(),
		villagerCount
	))
end

workspace.DescendantAdded:Connect(function(instance)
	if removeLegacySharedSkyMerchant(instance) then
		return
	end
	if isTerrainIsland(instance) then
		clearLegacyMerchantReservation(instance)
		task.defer(populateIsland, instance)
	end
end)

workspace.DescendantRemoving:Connect(function(instance)
	if processedIslands[instance] ~= nil then
		-- O pool de geometria preserva a mesma instancia Terrain_* e remove todo
		-- o conteudo dinamico. Liberar o estado permite popular a proxima vida.
		processedIslands[instance] = nil
	end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if removeLegacySharedSkyMerchant(descendant) then
		continue
	elseif isTerrainIsland(descendant) then
		clearLegacyMerchantReservation(descendant)
		task.spawn(populateIsland, descendant)
	end
end

publishReservedSkyMerchantTemplate()
local merchantTemplateRefreshQueued = false
local function hasReservedMerchantAncestor(instance)
	local current = instance and instance.Parent
	while current and current ~= ServerStorage do
		if isReservedSkyMerchantTemplate(current) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function queueMerchantTemplateRefresh(instance)
	if merchantTemplateRefreshQueued
		or not instance
		or (
			not isReservedSkyMerchantTemplate(instance)
			and not hasReservedMerchantAncestor(instance)
			and not instance:FindFirstAncestor("Villagers")
		)
	then
		return
	end
	merchantTemplateRefreshQueued = true
	task.defer(function()
		merchantTemplateRefreshQueued = false
		publishReservedSkyMerchantTemplate()
	end)
end
ServerStorage.DescendantAdded:Connect(queueMerchantTemplateRefresh)
ServerStorage.DescendantRemoving:Connect(queueMerchantTemplateRefresh)

workspace:SetAttribute("SkyMerchantSpawnState", "PersonalOnly")
workspace:SetAttribute(
	"SkyMerchantSpawnDetail",
	"mercador pessoal segue a intencao de rota; nenhum mercador e criado pelo mapa"
)

print("[MVP Village] Gerador procedural iniciado; modelos de exemplo habilitados.")
