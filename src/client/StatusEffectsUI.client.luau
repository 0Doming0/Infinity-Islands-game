-- Mostra efeitos temporarios do jogador e efeitos cumulativos de reliquias
-- sobre inimigos. As expiracoes sao definidas pelo servidor; este script
-- apenas apresenta o estado replicado.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local TARGET_TAG = "CombatTarget"
local UPDATE_INTERVAL = 0.18
local TARGET_GUI_NAME = "__RelicEffectIcons"

local existingGui = playerGui:FindFirstChild("StatusEffectsUI")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StatusEffectsUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 21
screenGui.Parent = playerGui

local playerEffects = Instance.new("Frame")
playerEffects.Name = "TemporaryEffects"
playerEffects.AnchorPoint = Vector2.new(1, 1)
playerEffects.Position = UDim2.new(1, -18, 1, -18)
playerEffects.Size = UDim2.fromOffset(366, 52)
playerEffects.BackgroundTransparency = 1
playerEffects.BorderSizePixel = 0
playerEffects.Parent = screenGui

local function synchronizeUnifiedPlayerEffects()
	playerEffects.Visible = player:GetAttribute("DungeonUnifiedHUDReady") ~= true
end
player:GetAttributeChangedSignal("DungeonUnifiedHUDReady"):Connect(synchronizeUnifiedPlayerEffects)
task.defer(synchronizeUnifiedPlayerEffects)

local playerLayout = Instance.new("UIListLayout")
playerLayout.FillDirection = Enum.FillDirection.Horizontal
playerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
playerLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
playerLayout.Padding = UDim.new(0, 7)
playerLayout.SortOrder = Enum.SortOrder.LayoutOrder
playerLayout.Parent = playerEffects

local playerScale = Instance.new("UIScale")
playerScale.Parent = playerEffects

local EFFECTS = {
	{
		Id = "IceFrozen",
		Name = "Congelado",
		Icon = "❄",
		Color = Color3.fromRGB(92, 210, 255),
		UntilAttribute = "IceFrozenUntil",
	},
	{
		Id = "RescueWeak",
		Name = "Fraqueza",
		Icon = "!",
		Color = Color3.fromRGB(255, 111, 111),
		UntilAttribute = "RescueWeakUntil",
	},
	{
		Id = "Speed",
		Name = "Tonico de velocidade",
		Icon = "»",
		Color = Color3.fromRGB(68, 214, 212),
		UntilAttribute = "SpeedBuffUntil",
	},
	{
		Id = "Jump",
		Name = "Tonico de salto",
		Icon = "↑",
		Color = Color3.fromRGB(246, 178, 65),
		UntilAttribute = "JumpBuffUntil",
	},
	{
		Id = "RunSpeed",
		Name = "Velocidade da tentativa",
		Icon = "»",
		Color = Color3.fromRGB(54, 235, 182),
		StackAttribute = "RunSpeedBuffStacks",
	},
	{
		Id = "RunJump",
		Name = "Salto da tentativa",
		Icon = "↑",
		Color = Color3.fromRGB(255, 202, 83),
		StackAttribute = "RunJumpBuffStacks",
	},
	{
		Id = "RunVitality",
		Name = "Vitalidade da tentativa",
		Icon = "♥",
		Color = Color3.fromRGB(238, 82, 92),
		StackAttribute = "RunVitalityBuffStacks",
	},
	{
		Id = "Shield",
		Name = "Escudo",
		Icon = "◆",
		Color = Color3.fromRGB(124, 115, 244),
		UntilAttribute = "ShieldBuffUntil",
	},
	{
		Id = "Wing",
		Name = "Voo",
		Icon = "✦",
		Color = Color3.fromRGB(190, 224, 255),
		UntilAttribute = "WingActiveUntil",
		ActiveAttribute = "WingActive",
	},
	{
		Id = "Cape",
		Name = "Invisivel",
		Icon = "◐",
		Color = Color3.fromRGB(188, 142, 255),
		UntilAttribute = "CapeActiveUntil",
		ActiveAttribute = "CapeInvisibleToEnemies",
	},
	{
		Id = "Treasure",
		Name = "Tesouro",
		Icon = "★",
		Color = Color3.fromRGB(255, 211, 76),
		UntilAttribute = "TreasureBoostUntil",
		ActiveAttribute = "TreasureBoostActive",
		UnixTime = true,
	},
	{
		Id = "Elite",
		Name = "Elites",
		Icon = "♛",
		Color = Color3.fromRGB(255, 111, 82),
		UntilAttribute = "EliteBoostUntil",
		ActiveAttribute = "EliteBoostActive",
		UnixTime = true,
	},
}

local playerCards = {}

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function createPlayerCard(definition, order)
	local card = Instance.new("Frame")
	card.Name = definition.Id
	card.Size = UDim2.fromOffset(46, 46)
	card.BackgroundColor3 = Color3.fromRGB(15, 21, 32)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Visible = false
	card.Parent = playerEffects
	addCorner(card, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = definition.Color
	stroke.Transparency = 0.22
	stroke.Thickness = 1.4
	stroke.Parent = card

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Position = UDim2.fromOffset(3, 1)
	icon.Size = UDim2.fromOffset(40, 29)
	icon.BackgroundTransparency = 1
	icon.Text = definition.Icon
	icon.TextColor3 = definition.Color
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 22
	icon.Parent = card

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0.5, 1)
	timer.Position = UDim2.new(0.5, 0, 1, -2)
	timer.Size = UDim2.fromOffset(42, 14)
	timer.BackgroundTransparency = 1
	timer.Text = ""
	timer.TextColor3 = Color3.fromRGB(241, 246, 255)
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 10
	timer.Parent = card

	card:SetAttribute("EffectName", definition.Name)
	return {
		Card = card,
		Timer = timer,
	}
end

for order, definition in ipairs(EFFECTS) do
	playerCards[definition.Id] = createPlayerCard(definition, order)
end

local function formatTime(seconds)
	local rounded = math.max(0, math.ceil(seconds))
	if rounded >= 60 then
		return string.format("%d:%02d", math.floor(rounded / 60), rounded % 60)
	end
	return tostring(rounded) .. "s"
end

local function refreshPlayerEffects()
	for _, definition in ipairs(EFFECTS) do
		local record = playerCards[definition.Id]
		local active = false
		local timerText = ""
		if definition.StackAttribute then
			local stacks = math.max(0, math.floor(tonumber(player:GetAttribute(definition.StackAttribute)) or 0))
			active = stacks > 0
			timerText = stacks > 1 and ("x" .. tostring(stacks)) or "RUN"
		else
			local now = definition.UnixTime and os.time() or workspace:GetServerTimeNow()
			local expiration = tonumber(player:GetAttribute(definition.UntilAttribute)) or 0
			active = expiration > now
				and (not definition.ActiveAttribute or player:GetAttribute(definition.ActiveAttribute) == true)
			timerText = active and formatTime(expiration - now) or ""
		end
		record.Card.Visible = active
		record.Timer.Text = active and timerText or ""
	end
end

local function updatePlayerScale()
	local camera = workspace.CurrentCamera
	local width = camera and camera.ViewportSize.X or 1280
	playerScale.Scale = math.clamp(width / 760, 0.72, 1)
end

local RELIC_EFFECTS = {}
for order, relicId in ipairs(RelicCatalog.GetOrderedIds()) do
	local definition = RelicCatalog.Get(relicId)
	table.insert(RELIC_EFFECTS, {
		RelicId = relicId,
		Effect = definition.Effect,
		Icon = definition.Icon or "✦",
		ImageId = definition.ImageId or "",
		Color = definition.Color,
		Order = order,
		UntilAttribute = "RelicEffect" .. definition.Effect .. "Until",
	})
end

local targetRecords = setmetatable({}, { __mode = "k" })

local function findAdornee(model)
	local head = model:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head, Vector3.new(0, 1.35, 0)
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local height = math.max(2, model:GetExtentsSize().Y)
	return root, Vector3.new(0, height * 0.5 + 0.7, 0)
end

local function createTargetIcon(parent, definition)
	local slot = Instance.new("Frame")
	slot.Name = definition.RelicId
	slot.Size = UDim2.fromOffset(27, 27)
	slot.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
	slot.BackgroundTransparency = 0.08
	slot.BorderSizePixel = 0
	slot.LayoutOrder = definition.Order
	slot.Visible = false
	slot.Parent = parent
	addCorner(slot, 7)

	local stroke = Instance.new("UIStroke")
	stroke.Color = definition.Color
	stroke.Transparency = 0.12
	stroke.Thickness = 1.2
	stroke.Parent = slot

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.Position = UDim2.fromOffset(2, 2)
	image.Size = UDim2.new(1, -4, 1, -4)
	image.BackgroundTransparency = 1
	image.Image = definition.ImageId
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = definition.ImageId ~= ""
	image.Parent = slot

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.BackgroundTransparency = 1
	fallback.Text = definition.Icon
	fallback.TextColor3 = definition.Color
	fallback.Font = Enum.Font.GothamBold
	fallback.TextSize = 17
	fallback.Visible = not image.Visible
	fallback.Parent = slot

	return slot
end

local function createTargetRecord(model)
	local adornee, offset = findAdornee(model)
	if not adornee then
		return nil
	end

	local oldGui = model:FindFirstChild(TARGET_GUI_NAME, true)
	if oldGui and oldGui:IsA("BillboardGui") then
		oldGui:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = TARGET_GUI_NAME
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(132, 31)
	billboard.StudsOffsetWorldSpace = offset
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Enabled = false
	billboard.Parent = adornee

	local holder = Instance.new("Frame")
	holder.Name = "Icons"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local icons = {}
	for _, definition in ipairs(RELIC_EFFECTS) do
		icons[definition.Effect] = createTargetIcon(holder, definition)
	end

	return {
		Billboard = billboard,
		Icons = icons,
	}
end

local function targetEffectActive(model, definition, now)
	if (tonumber(model:GetAttribute(definition.UntilAttribute)) or 0) > now then
		return true
	end
	if definition.Effect == "Fire" then
		return model:GetAttribute("RelicBurning") == true
	elseif definition.Effect == "Ice" then
		return model:GetAttribute("RelicFrozen") == true
	elseif definition.Effect == "Stone" then
		return typeof(model:GetAttribute("StoneRelicChargedBy")) == "number"
	end
	return false
end

local function refreshTarget(model)
	if not model.Parent then
		return
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid.Health <= 0 then
		local existing = targetRecords[model]
		if existing then
			existing.Billboard.Enabled = false
		end
		return
	end

	local now = workspace:GetServerTimeNow()
	local activeEffects = {}
	for _, definition in ipairs(RELIC_EFFECTS) do
		activeEffects[definition.Effect] = targetEffectActive(model, definition, now)
	end

	local anyActive = false
	for _, active in pairs(activeEffects) do
		if active then
			anyActive = true
			break
		end
	end
	if not anyActive then
		local existing = targetRecords[model]
		if existing then
			existing.Billboard.Enabled = false
		end
		return
	end

	local record = targetRecords[model]
	if not record or not record.Billboard.Parent then
		record = createTargetRecord(model)
		targetRecords[model] = record
	end
	if not record then
		return
	end

	for effect, icon in pairs(record.Icons) do
		icon.Visible = activeEffects[effect] == true
	end
	record.Billboard.Enabled = true
end

local function removeTarget(model)
	local record = targetRecords[model]
	if record and record.Billboard.Parent then
		record.Billboard:Destroy()
	end
	targetRecords[model] = nil
end

CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(removeTarget)

local cameraConnection
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePlayerScale)
	end
	updatePlayerScale()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()
refreshPlayerEffects()

local elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	refreshPlayerEffects()
	for _, model in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if model:IsA("Model") then
			refreshTarget(model)
		end
	end
end)
