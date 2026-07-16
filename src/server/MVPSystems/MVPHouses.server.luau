--[[
	SkyDungeon - Vila procedural do MVP

	Cria uma pequena vila deterministica em MainHalls medias/grandes. Aceita
	modelos reais em ServerStorage/MVPAssets/Village e usa modelos de exemplo
	por codigo quando as pastas estiverem vazias.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local VILLAGE_CONFIG = MVPConfig.Village
local processedIslands = setmetatable({}, { __mode = "k" })

local function isTerrainIsland(instance)
	return instance:IsA("Model")
		and instance:GetAttribute("IsSkyIsland") == true
end

local function getPreferredFolder(category)
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local village = assets and assets:FindFirstChild("Village")
	local preferred = village and village:FindFirstChild(category)
	if preferred and #preferred:GetChildren() > 0 then
		return preferred
	end
	local legacyName = category == "Buildings" and "MVPBuildings" or "MVPVillagers"
	local legacy = ServerStorage:FindFirstChild(legacyName)
	if legacy and #legacy:GetChildren() > 0 then
		return legacy
	end
	return nil
end

local function getTemplates(category)
	local folder = getPreferredFolder(category)
	local result = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") or child:IsA("BasePart") then
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
	local boxCFrame, boxSize = model:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
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

local function createExampleVillager(surfacePosition, yaw)
	local model = Instance.new("Model")
	model.Name = "ExampleSwordMerchant"
	local root = makePart(model, "HumanoidRootPart", Vector3.new(1.6, 2.2, 1.2), CFrame.new(surfacePosition + Vector3.new(0, 1.1, 0)), Color3.fromRGB(65, 48, 38), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.CanCollide = false
	local base = CFrame.new(surfacePosition) * CFrame.Angles(0, yaw, 0)
	makePart(model, "Body", Vector3.new(2.5, 3.2, 1.4), base * CFrame.new(0, 2.2, 0), Color3.fromRGB(60, 92, 145), Enum.Material.Fabric).CanCollide = false
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

local function spawnVillager(parent, templates, position, yaw, random)
	local template = chooseTemplate(templates, random)
	local model
	if template then
		model = alignToSurface(template:Clone(), position, yaw)
	else
		model = createExampleVillager(position, yaw)
	end
	model.Name = "SwordMerchant"
	model:SetAttribute("IsVillager", true)
	model:SetAttribute("ShopId", "SwordShop")
	model.Parent = parent
	CollectionService:AddTag(model, VILLAGE_CONFIG.ShopTag)
	return model
end

local function shouldSpawnVillage(island, random)
	local roundIndex = tonumber(island:GetAttribute("RoundIndex")) or 0
	local size = island:GetAttribute("TerrainSize")
	local role = island:GetAttribute("IslandRole")
	if roundIndex < VILLAGE_CONFIG.MinimumRound or role ~= "MainHall" then
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

local function populateIsland(island)
	if processedIslands[island] or not island.Parent then
		return
	end
	local floor = island:FindFirstChild("IslandFloor")
	local deadline = os.clock() + 2
	while not floor and island.Parent and os.clock() < deadline do
		task.wait()
		floor = island:FindFirstChild("IslandFloor")
	end
	if not floor or not floor:IsA("BasePart") then
		return
	end
	processedIslands[island] = true

	local seed = (tonumber(island:GetAttribute("IslandSeed")) or 1) + VILLAGE_CONFIG.RandomSalt
	seed = math.floor(math.abs(seed)) % 2147483647
	local random = Random.new(seed == 0 and 1 or seed)
	if not shouldSpawnVillage(island, random) then
		return
	end

	island:SetAttribute("VillageSpawned", true)
	island:SetAttribute("CanSpawnMonster", false)
	island:SetAttribute("CanSpawnItem", false)
	removeRuntimeMonsters(island)

	local surfaceY = floor.Position.Y + floor.Size.Y / 2 + 0.05
	local radius = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.25, 8, 13)
	local center = Vector3.new(floor.Position.X, surfaceY, floor.Position.Z)
	local angle = random:NextNumber(0, math.pi * 2)
	local buildingCount = random:NextInteger(VILLAGE_CONFIG.MinimumBuildingCount, VILLAGE_CONFIG.MaximumBuildingCount)
	local positions = { center }
	for index = 1, buildingCount do
		local theta = angle + ((index - 1) / buildingCount) * math.pi * 2
		table.insert(positions, center + Vector3.new(math.cos(theta) * radius, 0, math.sin(theta) * radius))
	end
	clearVillageArea(island, positions)

	local village = Instance.new("Folder")
	village.Name = "MVPVillage"
	village:SetAttribute("ProceduralVillage", true)
	village:SetAttribute("VillageSeed", seed)
	village.Parent = island

	local buildings = getTemplates("Buildings")
	local villagers = getTemplates("Villagers")
	for index = 1, buildingCount do
		local position = positions[index + 1]
		local yaw = math.atan2(center.X - position.X, center.Z - position.Z)
		spawnBuilding(village, buildings, index, position, yaw, random)
	end
	spawnVillager(village, villagers, center, angle, random)

	local pad = makePart(
		village,
		"VillageSquare",
		Vector3.new(math.min(12, radius), 0.35, math.min(12, radius)),
		CFrame.new(center + Vector3.new(0, 0.175, 0)),
		Color3.fromRGB(118, 118, 112),
		Enum.Material.Cobblestone
	)
	pad.CanCollide = true
	print(string.format("[MVP Village] Vila procedural criada em %s.", island:GetFullName()))
end

workspace.DescendantAdded:Connect(function(instance)
	if isTerrainIsland(instance) then
		task.defer(populateIsland, instance)
	end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if isTerrainIsland(descendant) then
		task.spawn(populateIsland, descendant)
	end
end

print("[MVP Village] Gerador procedural iniciado; modelos de exemplo habilitados.")
