--[[
	Block Parkour MVP - edificios e villagers em um unico Script

	Instale como Script normal em ServerScriptService.
	Os modelos sao clonados destas pastas:
	- ServerStorage/MVPBuildings
	- ServerStorage/MVPVillagers

	Deixe os atributos SelectedBuilding e SelectedVillager vazios (ou "Random")
	para sortear modelos. Use o nome exato de um Model para forcar uma escolha.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local HOUSE_CHANCE = 0.30
local RANDOM_SALT = 73428767
local CAPE_PRICE = 15

local processedIslands = setmetatable({}, { __mode = "k" })

local warned = {}

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function isTerrainIsland(instance)
	return instance:IsA("Model")
		and string.match(instance.Name, "^Terrain_") ~= nil
		and instance.Parent ~= nil
		and instance.Parent.Name == "TerrainAreas"
end

local function getFreeTerrainParts(island)
	local parts = {}
	for _, descendant in ipairs(island:GetDescendants()) do
		if
			descendant:IsA("BasePart")
			and descendant:GetAttribute("BlockType") == "Terrain"
			and descendant:GetAttribute("MVPReserved") == nil
		then
			table.insert(parts, descendant)
		end
	end
	table.sort(parts, function(left, right)
		local leftKey = string.format(
			"%s,%s,%s",
			tostring(left:GetAttribute("GridX")),
			tostring(left:GetAttribute("GridY")),
			tostring(left:GetAttribute("GridZ"))
		)
		local rightKey = string.format(
			"%s,%s,%s",
			tostring(right:GetAttribute("GridX")),
			tostring(right:GetAttribute("GridY")),
			tostring(right:GetAttribute("GridZ"))
		)
		return leftKey < rightKey
	end)
	return parts
end

local function removeCollectibleAbove(island, basePart)
	local gridX = basePart:GetAttribute("GridX")
	local gridY = basePart:GetAttribute("GridY")
	local gridZ = basePart:GetAttribute("GridZ")
	for _, descendant in ipairs(island:GetDescendants()) do
		if
			descendant:IsA("BasePart")
			and descendant:GetAttribute("BaseGridX") == gridX
			and descendant:GetAttribute("BaseGridY") == gridY
			and descendant:GetAttribute("BaseGridZ") == gridZ
		then
			descendant:Destroy()
		end
	end
end

local function showMessage(player, text)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local old = playerGui:FindFirstChild("MVPVillagerMessage")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MVPVillagerMessage"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.9)
	label.Size = UDim2.fromOffset(440, 72)
	label.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
	label.BackgroundTransparency = 0.12
	label.TextColor3 = Color3.fromRGB(255, 239, 184)
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	Debris:AddItem(gui, 3.5)
end

local function ensureOwnedCape(player)
	local folder = player:FindFirstChild("OwnedItems")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "OwnedItems"
		folder.Parent = player
	end
	local owned = folder:FindFirstChild("GreenCape")
	if not owned then
		owned = Instance.new("BoolValue")
		owned.Name = "GreenCape"
		owned.Parent = folder
	end
	return owned
end

local function equipCape(player)
	local character = player.Character
	if not character or not ensureOwnedCape(player).Value then
		return false
	end
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then
		return false
	end

	local old = character:FindFirstChild("MVPEquipped_GreenCape")
	if old then
		old:Destroy()
	end
	local cape = Instance.new("Part")
	cape.Name = "MVPEquipped_GreenCape"
	cape.Size = Vector3.new(2.8, 3.5, 0.22)
	cape.Color = Color3.fromRGB(52, 145, 73)
	cape.Material = Enum.Material.Fabric
	cape.CanCollide = false
	cape.CanTouch = false
	cape.Massless = true
	cape.Anchored = false
	cape.CFrame = torso.CFrame * CFrame.new(0, -0.45, 0.7)
	cape.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = cape
	weld.Parent = cape
	return true
end

local function purchaseOrEquipCape(player)
	local owned = ensureOwnedCape(player)
	if not owned.Value then
		local leaderstats = player:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins or not coins:IsA("IntValue") then
			showMessage(player, "Alfaiate: Nao encontrei suas moedas.")
			return
		end
		if coins.Value < CAPE_PRICE then
			showMessage(
				player,
				string.format("Alfaiate: A capa custa %d moedas. Voce tem %d.", CAPE_PRICE, coins.Value)
			)
			return
		end
		coins.Value -= CAPE_PRICE
		owned.Value = true
		if equipCape(player) then
			showMessage(player, "Compra concluida! Capa verde equipada.")
		else
			showMessage(player, "Capa comprada. Ela sera equipada no respawn.")
		end
		return
	end

	equipCape(player)
	showMessage(player, "Capa verde equipada novamente.")
end

local function setupPlayer(player)
	ensureOwnedCape(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.25)
		equipCape(player)
	end)
end

local function getTemplates(folderName)
	local templates = {}
	local folder = ServerStorage:FindFirstChild(folderName)
	if not folder or not folder:IsA("Folder") then
		warnOnce(folderName, string.format("[MVP Village] Crie uma Folder chamada ServerStorage/%s.", folderName))
		return templates
	end
	for _, child in ipairs(folder:GetChildren()) do
		if
			child:IsA("Model")
			and child:GetAttribute("Enabled") ~= false
			and child:FindFirstChildWhichIsA("BasePart", true)
		then
			table.insert(templates, child)
		end
	end
	table.sort(templates, function(left, right)
		return left.Name < right.Name
	end)
	return templates
end

local function chooseTemplate(templates, attributeName, random)
	if #templates == 0 then
		return nil
	end

	local selectedName = script:GetAttribute(attributeName)
	if typeof(selectedName) == "string" and selectedName ~= "" and selectedName ~= "Random" then
		for _, template in ipairs(templates) do
			if template.Name == selectedName then
				return template
			end
		end
		warnOnce(
			attributeName .. selectedName,
			string.format("[MVP Village] O Model '%s' definido em %s nao foi encontrado.", selectedName, attributeName)
		)
	end

	return templates[random:NextInteger(1, #templates)]
end

local function cloneAsset(parent, basePart, template, partsCanCollide)
	local model = template:Clone()
	model.Name = template.Name

	-- O MVP usa somente a parte visual dos assets da Toolbox.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = partsCanCollide
			descendant.CanTouch = false
		end
	end

	local root = model.PrimaryPart
	if not root or not root:IsA("BasePart") then
		root = model:FindFirstChild("HumanoidRootPart", true)
	end
	if not root or not root:IsA("BasePart") then
		root = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	if not model.PrimaryPart then
		model.PrimaryPart = root
	end

	local surfaceY = basePart.Position.Y + basePart.Size.Y / 2
	local origin = Vector3.new(basePart.Position.X, surfaceY, basePart.Position.Z)
	local originalPivot = model:GetPivot()
	local originalRotation = originalPivot - originalPivot.Position
	model:PivotTo(CFrame.new(origin) * originalRotation)
	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local adjustment =
		Vector3.new(origin.X - boundingCFrame.Position.X, surfaceY - bottomY, origin.Z - boundingCFrame.Position.Z)
	model:PivotTo(model:GetPivot() + adjustment)
	model:SetAttribute("SourceAsset", template.Name)
	model.Parent = parent
	return model, root
end

local function createBuilding(parent, basePart, random)
	local templates = getTemplates("MVPBuildings")
	local template = chooseTemplate(templates, "SelectedBuilding", random)
	if not template then
		warnOnce("NoBuildings", "[MVP Village] Adicione pelo menos um Model em ServerStorage/MVPBuildings.")
		return nil
	end

	local model = cloneAsset(parent, basePart, template, true)
	if model then
		model.Name = "Building_" .. template.Name
		model:SetAttribute("BuildingId", template.Name)
	end
	return model
end

local function createVillagerFromAsset(parent, basePart, template)
	local model, root = cloneAsset(parent, basePart, template, false)
	if not model then
		return nil
	end
	model.Name = "Villager_" .. template.Name

	local displayName = template:GetAttribute("DisplayName")
	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = template.Name
	end
	local villagerId = template:GetAttribute("VillagerId")
	if typeof(villagerId) ~= "string" or villagerId == "" then
		villagerId = template.Name
	end
	model:SetAttribute("VillagerId", villagerId)
	model:SetAttribute("ShopId", "BasicClothes")
	local head = model:FindFirstChild("Head", true)
	if not head or not head:IsA("BasePart") then
		head = root
	end
	return model, root, head, displayName, villagerId
end

local function createVillager(parent, basePart, random)
	local templates = getTemplates("MVPVillagers")
	local template = chooseTemplate(templates, "SelectedVillager", random)
	if not template then
		warnOnce("NoVillagers", "[MVP Village] Adicione pelo menos um Model em ServerStorage/MVPVillagers.")
		return nil
	end
	local model, root, head, displayName, villagerId = createVillagerFromAsset(parent, basePart, template)
	if not model then
		return nil
	end

	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "NameGui"
	nameGui.Size = UDim2.fromOffset(180, 38)
	nameGui.StudsOffset = Vector3.new(0, 1.4, 0)
	nameGui.AlwaysOnTop = true
	nameGui.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = nameGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Comprar/Equipar capa"
	prompt.ObjectText = displayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		player:SetAttribute("LastVillagerId", villagerId)
		purchaseOrEquipCape(player)
	end)
	return model
end

local function chooseNearestOtherPart(parts, selected)
	local closest = nil
	local closestDistance = math.huge
	for _, part in ipairs(parts) do
		if part ~= selected then
			local distance = (part.Position - selected.Position).Magnitude
			if distance < closestDistance then
				closest = part
				closestDistance = distance
			end
		end
	end
	return closest
end

local function populateIsland(island)
	if processedIslands[island] or not island.Parent then
		return
	end
	processedIslands[island] = true

	local size = island:GetAttribute("TerrainSize")
	if size ~= "Medium" and size ~= "Large" then
		return
	end
	local chunk = island.Parent and island.Parent.Parent
	local chunkSeed = chunk and chunk:GetAttribute("Seed") or 1
	local terrainId = island:GetAttribute("TerrainId") or 1
	local seed = (chunkSeed + terrainId * 17389 + RANDOM_SALT) % 2147483647
	local random = Random.new(seed == 0 and 1 or seed)
	if random:NextNumber() > HOUSE_CHANCE then
		return
	end

	local parts = getFreeTerrainParts(island)
	local deadline = os.clock() + 2
	while #parts < 2 and island.Parent and os.clock() < deadline do
		task.wait(0.05)
		parts = getFreeTerrainParts(island)
	end
	if #parts < 2 or not island.Parent then
		return
	end
	if #getTemplates("MVPBuildings") == 0 or #getTemplates("MVPVillagers") == 0 then
		warnOnce(
			"MissingVillageAssets",
			"[MVP Village] A geracao precisa de Models nas pastas MVPBuildings e MVPVillagers do ServerStorage."
		)
		return
	end

	local houseBase = parts[random:NextInteger(1, #parts)]
	local villagerBase = chooseNearestOtherPart(parts, houseBase)
	if not villagerBase then
		return
	end
	houseBase:SetAttribute("MVPReserved", "House")
	villagerBase:SetAttribute("MVPReserved", "Villager")
	removeCollectibleAbove(island, houseBase)
	removeCollectibleAbove(island, villagerBase)

	local village = Instance.new("Folder")
	village.Name = "MVPVillage"
	village.Parent = island
	createBuilding(village, houseBase, random)
	createVillager(village, villagerBase, random)
	print("[MVP Village] Casa e alfaiate criados em " .. island:GetFullName())
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

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

print("[MVP Village] Sistema simples iniciado")