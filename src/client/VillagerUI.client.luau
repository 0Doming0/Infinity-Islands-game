-- SkyDungeon - interface responsiva dos comerciantes da vila.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local villagerEvent = ReplicatedStorage:WaitForChild("VillagerEvent")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CURRENCY_SYMBOL = MVPConfig.Currency.Symbol

local gui = Instance.new("ScreenGui")
gui.Name = "VillageShopUI"
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
backdrop.Modal = true
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
stroke.Thickness = 1
stroke.Transparency = 0.28
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -150, 0, 52)
title.Position = UDim2.fromOffset(22, 12)
title.BackgroundTransparency = 1
title.Text = "VILA"
title.TextColor3 = Color3.fromRGB(255, 226, 120)
title.Font = Enum.Font.GothamMedium
title.TextSize = 26
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local coinLabel = Instance.new("TextLabel")
coinLabel.AnchorPoint = Vector2.new(1, 0)
coinLabel.Position = UDim2.new(1, -74, 0, 18)
coinLabel.Size = UDim2.fromOffset(190, 36)
coinLabel.BackgroundTransparency = 1
coinLabel.Text = CURRENCY_SYMBOL .. " 0"
coinLabel.TextColor3 = Color3.fromRGB(255, 220, 93)
coinLabel.Font = Enum.Font.GothamMedium
coinLabel.TextSize = 19
coinLabel.TextXAlignment = Enum.TextXAlignment.Right
coinLabel.Parent = panel

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
feedback.Text = "Escolha uma oferta."
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
local cameraState

local function releaseFirstPerson()
	if cameraState then
		return
	end
	cameraState = {
		CameraMode = player.CameraMode,
		MinimumZoom = player.CameraMinZoomDistance,
		MaximumZoom = player.CameraMaxZoomDistance,
		MouseBehavior = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition
			then Enum.MouseBehavior.Default
			else UserInputService.MouseBehavior,
		MouseIconEnabled = UserInputService.MouseIconEnabled,
	}
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 6
	player.CameraMaxZoomDistance = math.max(8, cameraState.MaximumZoom)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

local function restoreCamera()
	local state = cameraState
	if not state then
		return
	end
	cameraState = nil
	player.CameraMinZoomDistance = state.MinimumZoom
	player.CameraMaxZoomDistance = state.MaximumZoom
	player.CameraMode = state.CameraMode

	-- LockCurrentPosition e um estado transitorio usado pelo controlador da
	-- camera enquanto o jogador arrasta o mouse. Ele e convertido para Default
	-- ao ser salvo, pois restaura-lo depois prende o cursor no ponto antigo.
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	task.defer(function()
		RunService.RenderStepped:Wait()
		if not shopOpen then
			UserInputService.MouseBehavior = state.MouseBehavior
			UserInputService.MouseIconEnabled = state.MouseIconEnabled
		end
	end)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / 820, viewport.Y / 630), 0.38, 1)
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

local function closeShop(notifyServer)
	local wasOpen = shopOpen
	shopOpen = false
	panel.Visible = false
	backdrop.Visible = false
	restoreCamera()
	if wasOpen and notifyServer ~= false then
		villagerEvent:FireServer({ action = "closeShop" })
	end
end

local function clearRows()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function getOfferIcon(item)
	if item.ItemType == "Sword" then
		return "⚔️"
	elseif item.ItemType == "Relic" then
		return "✨"
	elseif item.ItemType == "DailyReward" then
		return "🎁"
	elseif item.ItemType == "TimeReward" then
		return "⏱"
	end
	local itemId = tostring(item.ItemId or "")
	if string.find(itemId, "Heal", 1, true) or string.find(itemId, "Health", 1, true) then
		return "❤️"
	elseif string.find(itemId, "Speed", 1, true) then
		return "💨"
	elseif string.find(itemId, "Jump", 1, true) then
		return "⬆️"
	end
	return "🎒"
end

local function createRow(item, index)
	local row = Instance.new("Frame")
	row.Name = item.ItemId or item.SwordId or ("Offer_" .. index)
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
	rowStroke.Thickness = item.Equipped and 1.5 or 1
	rowStroke.Transparency = item.Equipped and 0.1 or 0.35
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

	local contentX = 36
	if item.ItemType == "Relic" then
		contentX = 126
		local imageSlot = Instance.new("Frame")
		imageSlot.Name = "RelicImageSlot"
		imageSlot.Position = UDim2.fromOffset(32, 14)
		imageSlot.Size = UDim2.fromOffset(84, 84)
		imageSlot.BackgroundColor3 = Color3.fromRGB(24, 27, 39)
		imageSlot.BackgroundTransparency = 0.18
		imageSlot.BorderSizePixel = 0
		imageSlot.Parent = row
		Instance.new("UICorner", imageSlot).CornerRadius = UDim.new(0, 12)

		local imageStroke = Instance.new("UIStroke")
		imageStroke.Color = item.Color or Color3.fromRGB(142, 92, 235)
		imageStroke.Transparency = 0.32
		imageStroke.Thickness = item.Equipped and 2 or 1
		imageStroke.Parent = imageSlot

		local image = Instance.new("ImageLabel")
		image.Name = "RelicImage"
		image.Position = UDim2.fromOffset(4, 4)
		image.Size = UDim2.new(1, -8, 1, -8)
		image.BackgroundTransparency = 1
		image.Image = type(item.ImageId) == "string" and item.ImageId or ""
		image.ScaleType = Enum.ScaleType.Fit
		image.Visible = image.Image ~= ""
		image.Parent = imageSlot

		local placeholder = Instance.new("TextLabel")
		placeholder.Name = "ImagePlaceholder"
		placeholder.Size = UDim2.fromScale(1, 1)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = item.Icon or "✨"
		placeholder.TextColor3 = item.Color or Color3.new(1, 1, 1)
		placeholder.Font = Enum.Font.GothamBold
		placeholder.TextSize = 34
		placeholder.Visible = not image.Visible
		placeholder.Parent = imageSlot

		if item.Equipped then
			local equippedBadge = Instance.new("TextLabel")
			equippedBadge.Name = "EquippedBadge"
			equippedBadge.AnchorPoint = Vector2.new(0.5, 1)
			equippedBadge.Position = UDim2.new(0.5, 0, 1, -3)
			equippedBadge.Size = UDim2.fromOffset(72, 17)
			equippedBadge.BackgroundColor3 = Color3.fromRGB(43, 139, 81)
			equippedBadge.BorderSizePixel = 0
			equippedBadge.Text = "EQUIPADA"
			equippedBadge.TextColor3 = Color3.new(1, 1, 1)
			equippedBadge.Font = Enum.Font.GothamBold
			equippedBadge.TextSize = 9
			equippedBadge.Parent = imageSlot
			Instance.new("UICorner", equippedBadge).CornerRadius = UDim.new(1, 0)
		end
	end

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(contentX, 9)
	name.Size = UDim2.new(1, -(contentX + 214), 0, 30)
	name.BackgroundTransparency = 1
	name.Text = string.format(
		"%s%s",
		item.ItemType == "Relic" and "" or (getOfferIcon(item) .. "  "),
		item.DisplayName or item.SwordId
	)
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Font = Enum.Font.GothamMedium
	name.TextSize = 20
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local description = Instance.new("TextLabel")
	description.Position = UDim2.fromOffset(contentX, 38)
	description.Size = UDim2.new(1, -(contentX + 214), 0, 24)
	description.BackgroundTransparency = 1
	description.Text = item.Description or ""
	description.TextColor3 = Color3.fromRGB(188, 193, 207)
	description.Font = Enum.Font.Gotham
	description.TextSize = 14
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.Parent = row

	local stats = Instance.new("TextLabel")
	stats.Position = UDim2.fromOffset(contentX, 66)
	stats.Size = UDim2.new(1, -(contentX + 214), 0, 32)
	stats.BackgroundTransparency = 1
	stats.Text = item.ItemType == "DailyReward" or item.ItemType == "TimeReward"
		and (item.StatsText or "Recompensa")
		or string.format("%s  •  Estoque: %d", item.StatsText or "Oferta da vila", item.Stock or 0)
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
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 17
	button.Parent = row
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 11)
	buttonCorner.Parent = button

	if item.ItemType == "Sword" and item.Equipped then
		button.Text = "EQUIPADA"
		button.BackgroundColor3 = Color3.fromRGB(50, 135, 83)
		button.Active = false
		button.AutoButtonColor = false
	elseif item.ItemType == "Sword" and item.Owned then
		button.Text = "EQUIPAR"
		button.BackgroundColor3 = Color3.fromRGB(77, 105, 185)
		button.MouseButton1Click:Connect(function()
			button.Active = false
			villagerEvent:FireServer({ action = "equipSword", itemId = item.ItemId })
		end)
	elseif item.ItemType == "Relic" and item.Equipped then
		button.Text = "EQUIPADA"
		button.BackgroundColor3 = Color3.fromRGB(50, 135, 83)
		button.Active = false
		button.AutoButtonColor = false
	elseif item.ItemType == "Relic" and item.Owned then
		button.Text = "EQUIPAR"
		button.BackgroundColor3 = Color3.fromRGB(77, 105, 185)
		button.MouseButton1Click:Connect(function()
			button.Active = false
			villagerEvent:FireServer({ action = "equipRelic", itemId = item.ItemId })
		end)
	elseif item.ItemType == "DailyReward" or item.ItemType == "TimeReward" then
		if item.Claimed then
			button.Text = "COLETADA"
			button.BackgroundColor3 = Color3.fromRGB(64, 64, 72)
			button.Active = false
			button.AutoButtonColor = false
		elseif not item.Claimable then
			button.Text = "BLOQUEADA"
			button.BackgroundColor3 = Color3.fromRGB(64, 64, 72)
			button.Active = false
			button.AutoButtonColor = false
		else
			button.Text = "COLETAR"
			button.BackgroundColor3 = Color3.fromRGB(57, 145, 91)
			button.MouseButton1Click:Connect(function()
				button.Active = false
				if item.ItemType == "DailyReward" then
					villagerEvent:FireServer({ action = "claimDailyReward" })
				else
					villagerEvent:FireServer({ action = "claimTimeReward", minutes = item.Minutes })
				end
			end)
		end
	elseif (item.Stock or 0) <= 0 then
		button.Text = "SEM ESTOQUE"
		button.BackgroundColor3 = Color3.fromRGB(64, 64, 72)
		button.TextColor3 = Color3.fromRGB(165, 165, 175)
		button.Active = false
		button.AutoButtonColor = false
	else
		button.Text = string.format("COMPRAR  %s %d", CURRENCY_SYMBOL, item.Price or 0)
		button.BackgroundColor3 = Color3.fromRGB(135, 82, 170)
		button.MouseButton1Click:Connect(function()
			button.Active = false
			villagerEvent:FireServer({
				action = item.ItemType == "Sword" and "purchaseSword"
					or item.ItemType == "Relic" and "purchaseRelic"
					or item.ItemType == "Item" and "purchaseItem"
					or "purchaseService",
				itemId = item.ItemId,
			})
		end)
	end
end

local function showShop(data)
	shopOpen = true
	releaseFirstPerson()
	panel.Visible = true
	backdrop.Visible = true
	title.Text = string.upper(data.shopTitle or "VILA")
	if typeof(data.shopColor) == "Color3" then
		title.TextColor3 = data.shopColor
		stroke.Color = data.shopColor
	end
	coinLabel.Text = CURRENCY_SYMBOL .. " " .. tostring(data.coins or 0)
	if data.message then
		feedback.Text = data.message
		feedback.TextColor3 = data.success and Color3.fromRGB(105, 255, 145)
			or data.emptyStock and Color3.fromRGB(232, 193, 105)
			or Color3.fromRGB(255, 120, 120)
		if data.success then
			playPurchaseSound()
		end
	else
		feedback.Text = "Escolha uma oferta de " .. (data.shopTitle or "este aldeao") .. "."
		feedback.TextColor3 = Color3.fromRGB(185, 190, 205)
	end
	clearRows()
	for index, item in ipairs(data.inventory or {}) do
		createRow(item, index)
	end
end

closeButton.MouseButton1Click:Connect(closeShop)
backdrop.MouseButton1Click:Connect(closeShop)
player.CharacterAdded:Connect(function()
	if shopOpen then
		closeShop()
	end
end)
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
		closeShop(false)
	elseif data.action == "shopError" then
		feedback.Text = data.message or "Loja indisponivel."
		feedback.TextColor3 = Color3.fromRGB(255, 120, 120)
	end
end)
