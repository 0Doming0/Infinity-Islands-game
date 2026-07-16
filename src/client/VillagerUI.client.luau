-- SkyDungeon - interface responsiva da loja de espadas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local villagerEvent = ReplicatedStorage:WaitForChild("VillagerEvent")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local gui = Instance.new("ScreenGui")
gui.Name = "SwordShopUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20
gui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(5, 7, 12)
backdrop.BackgroundTransparency = 0.30
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Visible = false
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(720, 540)
panel.BackgroundColor3 = Color3.fromRGB(22, 25, 36)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local scale = Instance.new("UIScale")
scale.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(142, 92, 235)
stroke.Thickness = 2
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -150, 0, 52)
title.Position = UDim2.fromOffset(22, 12)
title.BackgroundTransparency = 1
title.Text = "⚔ LOJA DE ESPADAS"
title.TextColor3 = Color3.fromRGB(255, 226, 120)
title.Font = Enum.Font.GothamBlack
title.TextSize = 26
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local scoreLabel = Instance.new("TextLabel")
scoreLabel.AnchorPoint = Vector2.new(1, 0)
scoreLabel.Position = UDim2.new(1, -74, 0, 18)
scoreLabel.Size = UDim2.fromOffset(190, 36)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Text = "Pontos: 0"
scoreLabel.TextColor3 = Color3.fromRGB(115, 225, 255)
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.TextSize = 19
scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
scoreLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.Size = UDim2.fromOffset(46, 42)
closeButton.BackgroundColor3 = Color3.fromRGB(142, 55, 70)
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 22
closeButton.Parent = panel
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 10)
closeCorner.Parent = closeButton

local feedback = Instance.new("TextLabel")
feedback.Position = UDim2.fromOffset(22, 65)
feedback.Size = UDim2.new(1, -44, 0, 30)
feedback.BackgroundTransparency = 1
feedback.Text = "Escolha uma espada para comprar ou equipar."
feedback.TextColor3 = Color3.fromRGB(185, 190, 205)
feedback.Font = Enum.Font.Gotham
feedback.TextSize = 16
feedback.TextXAlignment = Enum.TextXAlignment.Left
feedback.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Items"
scroll.Position = UDim2.fromOffset(18, 104)
scroll.Size = UDim2.new(1, -36, 1, -122)
scroll.BackgroundColor3 = Color3.fromRGB(14, 17, 25)
scroll.BackgroundTransparency = 0.20
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 8
scroll.ScrollBarImageColor3 = Color3.fromRGB(142, 92, 235)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel
local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 12)
scrollCorner.Parent = scroll
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = scroll
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 9)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local shopOpen = false

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / 820, viewport.Y / 630), 0.58, 1)
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local function playPurchaseSound()
	local sound = Instance.new("Sound")
	sound.SoundId = MVPConfig.ExampleAssets.Sounds.Purchase
	sound.Volume = 0.45
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(3, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function closeShop()
	if not shopOpen then
		return
	end
	shopOpen = false
	panel.Visible = false
	backdrop.Visible = false
	villagerEvent:FireServer({ action = "closeShop" })
end

local function clearRows()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createRow(item, index)
	local row = Instance.new("Frame")
	row.Name = item.SwordId or ("Sword_" .. index)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 112)
	row.BackgroundColor3 = item.Color or Color3.fromRGB(65, 70, 88)
	row.BackgroundTransparency = 0.78
	row.BorderSizePixel = 0
	row.Parent = scroll
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 12)
	rowCorner.Parent = row
	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = item.Equipped and Color3.fromRGB(105, 255, 145) or (item.Color or Color3.fromRGB(100, 100, 115))
	rowStroke.Thickness = item.Equipped and 3 or 1
	rowStroke.Parent = row

	local swatch = Instance.new("Frame")
	swatch.Position = UDim2.fromOffset(12, 12)
	swatch.Size = UDim2.fromOffset(12, 88)
	swatch.BackgroundColor3 = item.Color or Color3.new(1, 1, 1)
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(1, 0)
	swatchCorner.Parent = swatch

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(36, 9)
	name.Size = UDim2.new(1, -250, 0, 30)
	name.BackgroundTransparency = 1
	name.Text = item.DisplayName or item.SwordId
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 20
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local description = Instance.new("TextLabel")
	description.Position = UDim2.fromOffset(36, 38)
	description.Size = UDim2.new(1, -250, 0, 24)
	description.BackgroundTransparency = 1
	description.Text = item.Description or ""
	description.TextColor3 = Color3.fromRGB(188, 193, 207)
	description.Font = Enum.Font.Gotham
	description.TextSize = 14
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.Parent = row

	local stats = Instance.new("TextLabel")
	stats.Position = UDim2.fromOffset(36, 66)
	stats.Size = UDim2.new(1, -250, 0, 32)
	stats.BackgroundTransparency = 1
	stats.Text = string.format(
		"Dano %d  •  Velocidade %.2fx  •  Pontos %.2fx",
		item.BaseDamage or 0,
		item.AttackSpeed or 1,
		item.ScoreMultiplier or 1
	)
	stats.TextColor3 = Color3.fromRGB(115, 225, 255)
	stats.Font = Enum.Font.GothamMedium
	stats.TextSize = 14
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.Parent = row

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -14, 0.5, 0)
	button.Size = UDim2.fromOffset(190, 64)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	button.Parent = row
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 11)
	buttonCorner.Parent = button

	if item.Equipped then
		button.Text = "EQUIPADA"
		button.BackgroundColor3 = Color3.fromRGB(50, 135, 83)
		button.Active = false
		button.AutoButtonColor = false
	elseif item.Owned then
		button.Text = "EQUIPAR"
		button.BackgroundColor3 = Color3.fromRGB(77, 105, 185)
		button.MouseButton1Click:Connect(function()
			button.Active = false
			villagerEvent:FireServer({ action = "equipSword", swordId = item.SwordId })
		end)
	else
		button.Text = string.format("COMPRAR\n%d pontos", item.Price or 0)
		button.BackgroundColor3 = Color3.fromRGB(135, 82, 170)
		button.MouseButton1Click:Connect(function()
			button.Active = false
			villagerEvent:FireServer({ action = "purchaseSword", swordId = item.SwordId })
		end)
	end
end

local function showShop(data)
	shopOpen = true
	panel.Visible = true
	backdrop.Visible = true
	scoreLabel.Text = "Pontos: " .. tostring(data.score or 0)
	if data.message then
		feedback.Text = data.message
		feedback.TextColor3 = data.success and Color3.fromRGB(105, 255, 145) or Color3.fromRGB(255, 120, 120)
		if data.success then
			playPurchaseSound()
		end
	else
		feedback.Text = "Escolha uma espada para comprar ou equipar."
		feedback.TextColor3 = Color3.fromRGB(185, 190, 205)
	end
	clearRows()
	for index, item in ipairs(data.inventory or {}) do
		createRow(item, index)
	end
end

closeButton.MouseButton1Click:Connect(closeShop)
backdrop.MouseButton1Click:Connect(closeShop)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and shopOpen and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
		closeShop()
	end
end)

villagerEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.action == "showShop" then
		showShop(data)
	elseif data.action == "closeShop" then
		closeShop()
	elseif data.action == "shopError" then
		feedback.Text = data.message or "Loja indisponivel."
		feedback.TextColor3 = Color3.fromRGB(255, 120, 120)
	end
end)
