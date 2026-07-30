--[[
	SkyDungeon - Vila procedural do MVP

	Cria uma pequena vila deterministica em MainHalls medias/grandes. Aceita
	modelos reais em ServerStorage/MVPAssets/Village e usa modelos de exemplo
	por codigo quando as pastas estiverem vazias.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MonetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))
local VillageShopCatalog = require(ReplicatedStorage:WaitForChild("VillageShopCatalog"))
local VILLAGE_CONFIG = MVPConfig.Village
local processedIslands = setmetatable({}, { __mode = "k" })
local warnedMissingVillagerTemplates = {}
local loggedVillagerTemplateResolution = {}
local activeRandomMerchantFolder
local warnedNoRandomRobuxOffers = false
local warnedInvalidVillagerTemplates = {}
local randomMerchantState
local randomMerchantRandom = Random.new()
local SKY_MERCHANT_SPAWNER_VERSION = "RandomVillagerVisibleTestV3"

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

local function getTemplates(category)
	local result = {}
	for _, folder in ipairs(getTemplateFolders(category)) do
		for _, child in ipairs(folder:GetChildren()) do
			if isUsableVisualTemplate(child) then
				table.insert(result, child)
			end
		end
	end
	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)
	return result
end

local function getRuntimeVillagerTemplates()
	local result = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("IsVillager") == true
			and descendant:GetAttribute("ShopId") ~= VillageShopCatalog.GetSkyMerchantShopId()
			and isUsableVisualTemplate(descendant)
		then
			table.insert(result, descendant)
		end
	end
	table.sort(result, function(a, b)
		return a:GetFullName() < b:GetFullName()
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

local function isSoloMerchantRole(role)
	return role == "FrontierIsland"
		or string.find(role, "SideRoom", 1, true) ~= nil
end

local function shouldSpawnSoloMerchant(island)
	local reserved = island:GetAttribute("SoloMerchantReserved")
	if reserved ~= nil then
		return reserved == true
	end

	-- Compatibilidade para ilhas criadas por uma versao anterior do
	-- IslandTypeService durante uma sessao de desenvolvimento no Studio.
	local roundIndex = tonumber(island:GetAttribute("RoundIndex")) or 0
	local role = tostring(island:GetAttribute("IslandRole") or "")
	local minimumRound = math.max(
		1,
		math.floor(tonumber(VILLAGE_CONFIG.SoloMerchantMinimumRound) or 2)
	)
	local eligible = island:GetAttribute("IslandType") == "Normal"
		and (tonumber(island:GetAttribute("ChestCount")) or 0) == 0
		and island:GetAttribute("IsSanctuary") ~= true
		and island:GetAttribute("IsSocialSanctuary") ~= true
		and roundIndex >= minimumRound
		and isSoloMerchantRole(role)
	if not eligible then
		island:SetAttribute("SoloMerchantReserved", false)
		return false
	end

	local seed = (tonumber(island:GetAttribute("IslandSeed")) or 1) + VILLAGE_CONFIG.RandomSalt
	seed = math.floor(math.abs(seed)) % 2147483647
	local roll = Random.new(seed == 0 and 1 or seed):NextNumber()
	local chance = math.clamp(tonumber(VILLAGE_CONFIG.SoloMerchantChance) or 0, 0, 1)
	reserved = roll <= chance
	island:SetAttribute("SoloMerchantDecisionVersion", 1)
	island:SetAttribute("SoloMerchantRoll", roll)
	island:SetAttribute("SoloMerchantChance", chance)
	island:SetAttribute("SoloMerchantReserved", reserved)
	if reserved then
		island:SetAttribute("CanSpawnMonster", false)
		island:SetAttribute("CanSpawnItem", false)
	end
	return reserved
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

local function setRandomMerchantDiagnostic(state, detail)
	workspace:SetAttribute("SkyMerchantSpawnState", state)
	workspace:SetAttribute("SkyMerchantSpawnDetail", detail or "")
	if randomMerchantState ~= state then
		print(string.format("[MVP Village][SkyMerchant] Estado: %s - %s", state, detail or ""))
		randomMerchantState = state
	end
end

local function getRandomRobuxOfferIds()
	local productIds = {}
	for _, definition in ipairs(MonetizationCatalog.GetAll()) do
		local productType = definition.ProductType
		if definition.Id ~= "ReviveNoCoinLoss"
			and definition.Enabled ~= false
			and (productType == "DeveloperProduct" or productType == "GamePass")
			and MonetizationCatalog.GetConfiguredAssetId(definition) > 0
		then
			table.insert(productIds, definition.Id)
		end
	end
	workspace:SetAttribute("SkyMerchantRobuxOfferCount", #productIds)
	if #productIds == 0 then
		if not warnedNoRandomRobuxOffers then
			warn("[MVP Village] Nenhum produto em Robux configurado para o mercador aleatorio.")
			warnedNoRandomRobuxOffers = true
		end
	end
	return productIds
end

local function getRandomSurfacePosition(floor, random)
	local padding = math.max(0, tonumber(VILLAGE_CONFIG.RandomMerchantEdgePadding) or 5)
	local halfX = math.max(0, floor.Size.X / 2 - padding)
	local halfZ = math.max(0, floor.Size.Z / 2 - padding)
	local function randomOffset(halfExtent)
		if halfExtent <= 0 then
			return 0
		end
		return random:NextNumber(-halfExtent, halfExtent)
	end
	local localPosition = Vector3.new(
		randomOffset(halfX),
		floor.Size.Y / 2 + 0.05,
		randomOffset(halfZ)
	)
	return floor.CFrame:PointToWorldSpace(localPosition)
end

local function getSkyIsland(instance)
	local current = instance
	while current do
		if isTerrainIsland(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function hasSkyMerchant(island)
	for _, descendant in ipairs(island:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("ShopId") == VillageShopCatalog.GetSkyMerchantShopId()
		then
			return true
		end
	end
	return false
end

local function getPlayerPositions()
	local positions = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		if root
			and root:IsA("BasePart")
			and (not humanoid or humanoid.Health > 0)
		then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function getNearestPlayerDistance(position, playerPositions)
	local nearest = math.huge
	for _, playerPosition in ipairs(playerPositions) do
		nearest = math.min(nearest, (position - playerPosition).Magnitude)
	end
	return nearest
end

local function getRandomMerchantIslands()
	local islands = {}
	local skyIslandCount = 0
	local missingFloorCount = 0
	local playerPositions = getPlayerPositions()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if isTerrainIsland(descendant)
			and descendant:IsDescendantOf(workspace)
		then
			skyIslandCount += 1
			local floor = descendant:FindFirstChild("IslandFloor")
				or descendant:FindFirstChild("IslandFloor", true)
			if floor and floor:IsA("BasePart") then
				table.insert(islands, {
					Island = descendant,
					Floor = floor,
					HasSkyMerchant = hasSkyMerchant(descendant),
					NearestPlayerDistance = getNearestPlayerDistance(floor.Position, playerPositions),
					SimulationActive = descendant:GetAttribute("SimulationActive") == true,
					LogicalLevel = tonumber(descendant:GetAttribute("LogicalLevel"))
						or tonumber(descendant:GetAttribute("RoundIndex"))
						or math.huge,
				})
			else
				missingFloorCount += 1
			end
		end
	end
	workspace:SetAttribute("SkyMerchantSkyIslandCount", skyIslandCount)
	workspace:SetAttribute("SkyMerchantCandidateIslandCount", #islands)
	workspace:SetAttribute("SkyMerchantMissingFloorCount", missingFloorCount)
	return islands, playerPositions
end

local function chooseRandomMerchantIsland(candidates, playerPositions, random)
	if #candidates == 0 then
		return nil, 0
	end

	local preferred = {}
	if #playerPositions > 0 then
		local radius = math.max(
			32,
			tonumber(VILLAGE_CONFIG.RandomMerchantPlayerRadius) or 320
		)
		for _, candidate in ipairs(candidates) do
			if candidate.SimulationActive
				or candidate.NearestPlayerDistance <= radius
			then
				table.insert(preferred, candidate)
			end
		end
		if #preferred == 0 then
			local nearest = math.huge
			for _, candidate in ipairs(candidates) do
				nearest = math.min(nearest, candidate.NearestPlayerDistance)
			end
			for _, candidate in ipairs(candidates) do
				if candidate.NearestPlayerDistance <= nearest + 24 then
					table.insert(preferred, candidate)
				end
			end
		end
	else
		-- Em Studio > Run nao existe Player. Nesse caso o teste usa uma das
		-- ilhas iniciais/mais baixas, em vez de esconder o NPC no fim do mapa.
		local lowestLevel = math.huge
		for _, candidate in ipairs(candidates) do
			lowestLevel = math.min(lowestLevel, candidate.LogicalLevel)
		end
		for _, candidate in ipairs(candidates) do
			if candidate.LogicalLevel == lowestLevel then
				table.insert(preferred, candidate)
			end
		end
	end

	local withoutMerchant = {}
	for _, candidate in ipairs(preferred) do
		if not candidate.HasSkyMerchant then
			table.insert(withoutMerchant, candidate)
		end
	end
	local pool = #withoutMerchant > 0 and withoutMerchant or preferred
	return pool[random:NextInteger(1, #pool)], #preferred
end

local function getRandomMerchantFolders()
	local folders = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Folder")
			and (
				descendant.Name == "MVPRandomSkyMerchant"
				or descendant:GetAttribute("RandomMapMerchant") == true
			)
		then
			table.insert(folders, descendant)
		end
	end
	return folders
end

local function randomMerchantFolderIsUsable(folder, playerPositions)
	if not folder or not folder:IsDescendantOf(workspace) then
		return false, "fora do Workspace"
	end
	local merchant
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model")
			and child:GetAttribute("ShopId") == VillageShopCatalog.GetSkyMerchantShopId()
		then
			merchant = child
			break
		end
	end
	if not merchant or not merchant:FindFirstChildWhichIsA("BasePart", true) then
		return false, "pasta sem modelo visivel"
	end
	local island = getSkyIsland(folder)
	local floor = island and (
		island:FindFirstChild("IslandFloor")
		or island:FindFirstChild("IslandFloor", true)
	)
	if not floor or not floor:IsA("BasePart") then
		return false, "ilha/piso removido"
	end
	local water = workspace:FindFirstChild("Water")
	local waterSurfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	local islandSurfaceY = floor.Position.Y + floor.Size.Y / 2
	if waterSurfaceY and waterSurfaceY >= islandSurfaceY then
		return false, "ilha alcancada pela agua"
	end
	if #playerPositions > 0 then
		local relocateDistance = math.max(
			64,
			tonumber(VILLAGE_CONFIG.RandomMerchantRelocateDistance) or 650
		)
		if getNearestPlayerDistance(floor.Position, playerPositions) > relocateDistance
			and island:GetAttribute("SimulationActive") ~= true
		then
			return false, "longe dos jogadores"
		end
	end
	return true, merchant
end

local function spawnRandomSkyMerchantUnlocked()
	local candidates, playerPositions = getRandomMerchantIslands()
	local existingFolders = getRandomMerchantFolders()
	if activeRandomMerchantFolder
		and not table.find(existingFolders, activeRandomMerchantFolder)
	then
		table.insert(existingFolders, activeRandomMerchantFolder)
	end
	for _, folder in ipairs(existingFolders) do
		local usable, merchantOrReason = randomMerchantFolderIsUsable(folder, playerPositions)
		if usable and not activeRandomMerchantFolder then
			activeRandomMerchantFolder = folder
			setRandomMerchantDiagnostic("Active", "mercador existente localizado")
		else
			if not usable then
				folder:Destroy()
				print("[MVP Village][SkyMerchant] Mercador antigo removido: " .. tostring(merchantOrReason))
			elseif folder ~= activeRandomMerchantFolder then
				folder:Destroy()
				print("[MVP Village][SkyMerchant] Mercador duplicado removido.")
			end
		end
	end
	if activeRandomMerchantFolder then
		local usable, merchantOrReason = randomMerchantFolderIsUsable(
			activeRandomMerchantFolder,
			playerPositions
		)
		if usable then
			local merchant = merchantOrReason
			workspace:SetAttribute(
				"SkyMerchantLastTemplate",
				tostring(merchant:GetAttribute("SourceVillagerTemplate") or "GeneratedFallback")
			)
			setRandomMerchantDiagnostic("Active", activeRandomMerchantFolder:GetFullName())
			return true
		end
		activeRandomMerchantFolder:Destroy()
		activeRandomMerchantFolder = nil
		setRandomMerchantDiagnostic("Relocating", tostring(merchantOrReason))
	end

	if #candidates == 0 then
		setRandomMerchantDiagnostic(
			"WaitingForIsland",
			string.format(
				"IsSkyIsland=%d, sem IslandFloor=%d",
				workspace:GetAttribute("SkyMerchantSkyIslandCount") or 0,
				workspace:GetAttribute("SkyMerchantMissingFloorCount") or 0
			)
		)
		return false
	end

	local offerIds = getRandomRobuxOfferIds()
	if #offerIds == 0 then
		setRandomMerchantDiagnostic("WaitingForRobuxOffer", "nenhum ProductId/PassId valido")
		return false
	end

	local candidate, nearbyCount = chooseRandomMerchantIsland(
		candidates,
		playerPositions,
		randomMerchantRandom
	)
	workspace:SetAttribute("SkyMerchantNearbyCandidateCount", nearbyCount)
	if not candidate then
		setRandomMerchantDiagnostic("WaitingForVisibleIsland", "nenhuma ilha acessivel")
		return false
	end

	local templates = getTemplates("Villagers")
	local templateSource = "ServerStorage"
	if #templates == 0 then
		templates = getRuntimeVillagerTemplates()
		templateSource = "Workspace"
	end
	workspace:SetAttribute("SkyMerchantVillagerTemplateCount", #templates)
	workspace:SetAttribute("SkyMerchantVillagerTemplateSource", templateSource)

	local offerId = offerIds[randomMerchantRandom:NextInteger(1, #offerIds)]
	local position = getRandomSurfacePosition(candidate.Floor, randomMerchantRandom)
	local folder = Instance.new("Folder")
	folder.Name = "MVPRandomSkyMerchant"
	folder:SetAttribute("RandomMapMerchant", true)
	folder:SetAttribute("ProceduralSoloMerchant", true)
	folder:SetAttribute("RobuxOfferProductId", offerId)

	local shop = VillageShopCatalog.GetShop(VillageShopCatalog.GetSkyMerchantShopId())
	assert(shop, "VillageShopCatalog nao possui a loja SkyMerchant")
	local merchant = spawnVillager(
		folder,
		templates,
		position,
		randomMerchantRandom:NextNumber(0, math.pi * 2),
		randomMerchantRandom,
		shop,
		1,
		nil
	)
	merchant:SetAttribute("RandomMapMerchant", true)
	merchant:SetAttribute("RobuxOfferProductId", offerId)
	folder.Parent = candidate.Island
	activeRandomMerchantFolder = folder

	workspace:SetAttribute("SkyMerchantLastIsland", candidate.Island:GetFullName())
	workspace:SetAttribute("SkyMerchantLastOfferId", offerId)
	workspace:SetAttribute(
		"SkyMerchantLastTemplate",
		tostring(merchant:GetAttribute("SourceVillagerTemplate") or "GeneratedFallback")
	)
	setRandomMerchantDiagnostic(
		"Spawned",
		string.format(
			"%s | modelo=%s | oferta=%s",
			candidate.Island:GetFullName(),
			tostring(merchant:GetAttribute("SourceVillagerTemplate") or "GeneratedFallback"),
			offerId
		)
	)
	print(string.format(
		"[MVP Village] Mercador aleatorio criado em %s com modelo %s e oferta %s.",
		candidate.Island:GetFullName(),
		tostring(merchant:GetAttribute("SourceVillagerTemplate") or "GeneratedFallback"),
		offerId
	))
	return true
end

local function spawnRandomSkyMerchant()
	if workspace:GetAttribute("SkyMerchantSpawnLock") == true then
		return false
	end
	workspace:SetAttribute("SkyMerchantSpawnLock", true)
	local success, resultOrError = pcall(spawnRandomSkyMerchantUnlocked)
	workspace:SetAttribute("SkyMerchantSpawnLock", nil)
	if not success then
		workspace:SetAttribute("SkyMerchantLastError", tostring(resultOrError))
		setRandomMerchantDiagnostic("Error", tostring(resultOrError))
		warn("[MVP Village][SkyMerchant] Falha recuperavel no spawn: " .. tostring(resultOrError))
		return false
	end
	workspace:SetAttribute("SkyMerchantLastError", nil)
	return resultOrError
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
	local createSoloMerchant = not createVillage and shouldSpawnSoloMerchant(island)
	if not createVillage and not createSoloMerchant then
		return
	end

	island:SetAttribute("VillageSpawned", createVillage)
	island:SetAttribute("SoloMerchantSpawned", createSoloMerchant)
	island:SetAttribute("CanSpawnMonster", false)
	island:SetAttribute("CanSpawnItem", false)
	removeRuntimeMonsters(island)

	local surfaceY = floor.Position.Y + floor.Size.Y / 2 + 0.05
	local radius = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.25, 8, 13)
	local center = Vector3.new(floor.Position.X, surfaceY, floor.Position.Z)
	local angle = random:NextNumber(0, math.pi * 2)
	if createSoloMerchant then
		clearVillageArea(island, { center })
		local folder = Instance.new("Folder")
		folder.Name = "MVPSoloMerchant"
		folder:SetAttribute("ProceduralSoloMerchant", true)
		folder.Parent = island
		local shop = VillageShopCatalog.GetShop(VillageShopCatalog.GetSkyMerchantShopId())
		local templates = getTemplates("Villagers")
		spawnVillager(folder, templates, center, angle, visualRandom, shop, 1, nil)
		print(string.format("[MVP Village] Mercador do Ceu solitario criado em %s.", island:GetFullName()))
		return
	end
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
	if isTerrainIsland(instance) then
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
	if isTerrainIsland(descendant) then
		task.spawn(populateIsland, descendant)
	end
end

task.spawn(function()
	while true do
		spawnRandomSkyMerchant()
		task.wait(math.max(
			0.5,
			tonumber(VILLAGE_CONFIG.RandomMerchantRespawnCheckSeconds) or 2
		))
	end
end)

print("[MVP Village] Gerador procedural iniciado; modelos de exemplo habilitados.")
