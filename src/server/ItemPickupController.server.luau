--[[
	ItemPickupController.server.lua

	Coloque este Script em ServerScriptService junto dos outros dois scripts.
	Ele transforma Attachments com a tag "ProceduralItemSpawn" em itens reais.

	Itens atuais:
	- Speed: aumenta WalkSpeed nesta vida;
	- Jump: aumenta JumpPower ou JumpHeight nesta vida;
	- Vitality: aumenta MaxHealth e cura;
	- Shield: adiciona um ForceField temporario.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local TAG_NAME = "ProceduralItemSpawn"
local rng = Random.new()

local CONFIG = {
	SPEED_INCREASE = 2,
	MAX_WALK_SPEED = 24,
	JUMP_POWER_INCREASE = 5,
	MAX_JUMP_POWER = 65,
	JUMP_HEIGHT_INCREASE = 1.25,
	MAX_JUMP_HEIGHT = 10,
	MAX_HEALTH_INCREASE = 15,
	MAX_HEALTH_LIMIT = 175,
	HEAL_AMOUNT = 35,
	SHIELD_DURATION = 11,
}

local ITEM_TYPES = {
	{
		Name = "Speed",
		Label = "SPEED",
		Weight = 30,
		Color = Color3.fromRGB(64, 226, 200),
	},
	{
		Name = "Jump",
		Label = "JUMP",
		Weight = 25,
		Color = Color3.fromRGB(246, 174, 54),
	},
	{
		Name = "Vitality",
		Label = "HEALTH",
		Weight = 25,
		Color = Color3.fromRGB(238, 82, 92),
	},
	{
		Name = "Shield",
		Label = "SHIELD",
		Weight = 20,
		Color = Color3.fromRGB(124, 115, 244),
	},
}

local spawnedByMarker = setmetatable({}, { __mode = "k" })

local activePickups = {}

local function chooseItemType()
	local totalWeight = 0
	for _, itemType in ITEM_TYPES do
		totalWeight += itemType.Weight
	end

	local roll = rng:NextNumber(0, totalWeight)
	local cumulative = 0
	for _, itemType in ITEM_TYPES do
		cumulative += itemType.Weight
		if roll <= cumulative then
			return itemType
		end
	end

	return ITEM_TYPES[1]
end

local function getPlayerFromHit(hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return player, humanoid, character
end

local function applyItem(player, humanoid, character, itemType)
	if itemType.Name == "Speed" then
		humanoid.WalkSpeed = math.min(
			humanoid.WalkSpeed + CONFIG.SPEED_INCREASE,
			CONFIG.MAX_WALK_SPEED
		)
	elseif itemType.Name == "Jump" then
		if humanoid.UseJumpPower then
			humanoid.JumpPower = math.min(
				humanoid.JumpPower + CONFIG.JUMP_POWER_INCREASE,
				CONFIG.MAX_JUMP_POWER
			)
		else
			humanoid.JumpHeight = math.min(
				humanoid.JumpHeight + CONFIG.JUMP_HEIGHT_INCREASE,
				CONFIG.MAX_JUMP_HEIGHT
			)
		end
	elseif itemType.Name == "Vitality" then
		humanoid.MaxHealth = math.min(
			humanoid.MaxHealth + CONFIG.MAX_HEALTH_INCREASE,
			CONFIG.MAX_HEALTH_LIMIT
		)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + CONFIG.HEAL_AMOUNT)
	elseif itemType.Name == "Shield" then
		local forceField = Instance.new("ForceField")
		forceField.Name = "ProceduralItemShield"
		forceField.Visible = true
		forceField.Parent = character

		task.delay(CONFIG.SHIELD_DURATION, function()
			if forceField.Parent then
				forceField:Destroy()
			end
		end)
	end

	player:SetAttribute("ItemsCollected", (player:GetAttribute("ItemsCollected") or 0) + 1)
	player:SetAttribute("LastCollectedItem", itemType.Name)
	humanoid:SetAttribute("LastCollectedItem", itemType.Name)
end

local function createLabel(pickup, itemType)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ItemLabel"
	billboard.Size = UDim2.fromOffset(90, 28)
	billboard.StudsOffset = Vector3.new(0, 1.7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 42
	billboard.Parent = pickup

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 28)
	label.BackgroundTransparency = 0.18
	label.TextColor3 = itemType.Color
	label.Text = itemType.Label
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = itemType.Color
	stroke.Thickness = 1.4
	stroke.Transparency = 0.15
	stroke.Parent = label
end

local function spawnPickup(marker)
	if spawnedByMarker[marker]
		or not marker:IsA("Attachment")
		or not marker:IsDescendantOf(game)
	then
		return
	end

	local itemType = chooseItemType()
	local platformModel = marker:FindFirstAncestorOfClass("Model")
	local parent = platformModel or marker.Parent
	local startPosition = marker.WorldPosition + Vector3.new(0, 1.35, 0)

	local pickup = Instance.new("Part")
	pickup.Name = "Pickup_" .. itemType.Name
	pickup.Shape = Enum.PartType.Ball
	pickup.Size = Vector3.new(1.35, 1.35, 1.35)
	pickup.Position = startPosition
	pickup.Anchored = true
	pickup.CanCollide = false
	pickup.CanTouch = true
	pickup.CanQuery = false
	pickup.CastShadow = false
	pickup.Material = Enum.Material.Neon
	pickup.Color = itemType.Color
	pickup:SetAttribute("ItemType", itemType.Name)
	pickup:SetAttribute("ProceduralPickup", true)
	pickup.Parent = parent

	createLabel(pickup, itemType)
	spawnedByMarker[marker] = pickup
	marker:SetAttribute("PickupSpawned", true)

	local tween = TweenService:Create(
		pickup,
		TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = startPosition + Vector3.new(0, 0.48, 0) }
	)
	tween:Play()

	activePickups[pickup] = {
		itemType = itemType,
		tween = tween,
		collected = false,
	}

	marker.Destroying:Connect(function()
		if pickup.Parent then
			tween:Cancel()
			pickup:Destroy()
		end
		spawnedByMarker[marker] = nil
		activePickups[pickup] = nil
	end)
end

for _, marker in CollectionService:GetTagged(TAG_NAME) do
	task.defer(spawnPickup, marker)
end

CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(function(marker)
	task.defer(spawnPickup, marker)
end)

local COLLECTION_RADIUS = 3.5

task.spawn(function()
	while true do
		for pickup, data in activePickups do
			if not pickup.Parent or data.collected then
				continue
			end

			for _, player in Players:GetPlayers() do
				local character = player.Character
				if not character then
					continue
				end

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 then
					continue
				end

				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if not rootPart then
					continue
				end

				local distance = (pickup.Position - rootPart.Position).Magnitude
				if distance <= COLLECTION_RADIUS then
					data.collected = true
					applyItem(player, humanoid, character, data.itemType)
					if data.tween then
						data.tween:Cancel()
					end
					pickup:Destroy()
					activePickups[pickup] = nil
					break
				end
			end
		end

		task.wait(0.12)
	end
end)
