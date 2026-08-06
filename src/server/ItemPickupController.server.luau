-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

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

local RUN_EFFECT_ATTRIBUTES = {
	"RunSpeedBuffStacks",
	"RunJumpBuffStacks",
	"RunVitalityBuffStacks",
	"ShieldBuffUntil",
}

local function clearRunEffects(player)
	for _, attributeName in ipairs(RUN_EFFECT_ATTRIBUTES) do
		player:SetAttribute(attributeName, nil)
	end
end

local function setupPlayer(player)
	clearRunEffects(player)
	player.CharacterAdded:Connect(function()
		clearRunEffects(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	setupPlayer(existingPlayer)
end

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
		local previousSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = math.min(
			humanoid.WalkSpeed + CONFIG.SPEED_INCREASE,
			CONFIG.MAX_WALK_SPEED
		)
		if humanoid.WalkSpeed > previousSpeed then
			player:SetAttribute(
				"RunSpeedBuffStacks",
				(tonumber(player:GetAttribute("RunSpeedBuffStacks")) or 0) + 1
			)
		end
	elseif itemType.Name == "Jump" then
		if humanoid.UseJumpPower then
			local previousJumpPower = humanoid.JumpPower
			humanoid.JumpPower = math.min(
				humanoid.JumpPower + CONFIG.JUMP_POWER_INCREASE,
				CONFIG.MAX_JUMP_POWER
			)
			if humanoid.JumpPower > previousJumpPower then
				player:SetAttribute(
					"RunJumpBuffStacks",
					(tonumber(player:GetAttribute("RunJumpBuffStacks")) or 0) + 1
				)
			end
		else
			local previousJumpHeight = humanoid.JumpHeight
			humanoid.JumpHeight = math.min(
				humanoid.JumpHeight + CONFIG.JUMP_HEIGHT_INCREASE,
				CONFIG.MAX_JUMP_HEIGHT
			)
			if humanoid.JumpHeight > previousJumpHeight then
				player:SetAttribute(
					"RunJumpBuffStacks",
					(tonumber(player:GetAttribute("RunJumpBuffStacks")) or 0) + 1
				)
			end
		end
	elseif itemType.Name == "Vitality" then
		local previousMaxHealth = humanoid.MaxHealth
		humanoid.MaxHealth = math.min(
			humanoid.MaxHealth + CONFIG.MAX_HEALTH_INCREASE,
			CONFIG.MAX_HEALTH_LIMIT
		)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + CONFIG.HEAL_AMOUNT)
		if humanoid.MaxHealth > previousMaxHealth then
			player:SetAttribute(
				"RunVitalityBuffStacks",
				(tonumber(player:GetAttribute("RunVitalityBuffStacks")) or 0) + 1
			)
		end
	elseif itemType.Name == "Shield" then
		local shieldUntil = workspace:GetServerTimeNow() + CONFIG.SHIELD_DURATION
		local forceField = Instance.new("ForceField")
		forceField.Name = "ProceduralItemShield"
		forceField.Visible = true
		forceField.Parent = character
		player:SetAttribute("ShieldBuffUntil", shieldUntil)

		task.delay(CONFIG.SHIELD_DURATION, function()
			if forceField.Parent then
				forceField:Destroy()
			end
			if
				player.Parent == Players
				and (tonumber(player:GetAttribute("ShieldBuffUntil")) or 0) <= workspace:GetServerTimeNow()
			then
				player:SetAttribute("ShieldBuffUntil", nil)
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
	billboard.Size = UDim2.fromOffset(76, 22)
	billboard.StudsOffset = Vector3.new(0, 1.45, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 16
	billboard.Parent = pickup

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 28)
	label.BackgroundTransparency = 0.42
	label.TextColor3 = itemType.Color
	label.Text = itemType.Label
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = itemType.Color
	stroke.Thickness = 1
	stroke.Transparency = 0.55
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
