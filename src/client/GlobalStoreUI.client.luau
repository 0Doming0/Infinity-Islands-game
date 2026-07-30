-- Loja global de produtos premium.
--
-- Esta interface e independente do Mercador do Ceu. O servidor continua
-- validando o produto, a politica regional, a propriedade dos passes e o
-- contexto de cada compra antes de abrir o Marketplace.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")
local monetizationEvent = ReplicatedStorage:WaitForChild("MonetizationEvent")

local COLORS = {
	Backdrop = Color3.fromRGB(4, 8, 15),
	Panel = Color3.fromRGB(15, 25, 39),
	Card = Color3.fromRGB(25, 39, 57),
	CardDisabled = Color3.fromRGB(38, 45, 54),
	Primary = Color3.fromRGB(76, 205, 255),
	PrimaryDark = Color3.fromRGB(7, 44, 62),
	Gold = Color3.fromRGB(255, 208, 85),
	Text = Color3.fromRGB(244, 249, 255),
	Muted = Color3.fromRGB(169, 190, 207),
	Good = Color3.fromRGB(101, 230, 158),
	Bad = Color3.fromRGB(247, 119, 126),
}

local oldGui = playerGui:FindFirstChild("GlobalStoreUI")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GlobalStoreUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 44
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui:SetAttribute("Version", "GlobalStoreV1")
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenStore"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -18, 0, 64)
openButton.Size = UDim2.fromOffset(126, 50)
openButton.BackgroundColor3 = COLORS.Gold
openButton.BorderSizePixel = 0
openButton.Text = "LOJA"
openButton.TextColor3 = Color3.fromRGB(39, 30, 7)
openButton.Font = Enum.Font.GothamBlack
openButton.TextSize = 18
openButton.Parent = gui
Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 14)
local openStroke = Instance.new("UIStroke")
openStroke.Color = Color3.fromRGB(255, 238, 164)
openStroke.Thickness = 1.5
openStroke.Transparency = 0.1
openStroke.Parent = openButton

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLORS.Backdrop
backdrop.BackgroundTransparency = 0.18
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Modal = true
backdrop.Visible = false
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "StorePanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.9, 0.86)
panel.BackgroundColor3 = COLORS.Panel
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 22)
local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(300, 320)
panelSize.MaxSize = Vector2.new(820, 700)
panelSize.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Primary
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.22
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.new(0, 24, 0, 18)
title.Size = UDim2.new(1, -92, 0, 32)
title.BackgroundTransparency = 1
title.Text = "LOJA DO SKY DUNGEON"
title.TextColor3 = COLORS.Gold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBlack
title.TextSize = 23
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.new(0, 24, 0, 52)
subtitle.Size = UDim2.new(1, -48, 0, 22)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Game Passes permanentes e produtos para sua expedicao"
subtitle.TextColor3 = COLORS.Muted
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 13
subtitle.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -18, 0, 18)
closeButton.Size = UDim2.fromOffset(44, 40)
closeButton.BackgroundColor3 = Color3.fromRGB(68, 47, 59)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.Text
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.Parent = panel
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 11)

local list = Instance.new("ScrollingFrame")
list.Name = "Products"
list.Position = UDim2.new(0, 20, 0, 88)
list.Size = UDim2.new(1, -40, 1, -142)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 7
list.ScrollBarImageColor3 = COLORS.Primary
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 12)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list
local listPadding = Instance.new("UIPadding")
listPadding.PaddingRight = UDim.new(0, 7)
listPadding.PaddingBottom = UDim.new(0, 8)
listPadding.Parent = list

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -12)
status.Size = UDim2.new(1, -48, 0, 34)
status.BackgroundTransparency = 1
status.Text = "Selecione um produto para abrir a compra oficial do Roblox."
status.TextColor3 = COLORS.Muted
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.Parent = panel

local storeOpen = false
local renderSerial = 0
local productInfoCache = {}
local cardsByProductId = {}

local function setStatus(message, color)
	status.Text = tostring(message or "")
	status.TextColor3 = color or COLORS.Muted
end

local function infoTypeFor(entry)
	return entry.ProductType == "GamePass" and Enum.InfoType.GamePass or Enum.InfoType.Product
end

local function productInfo(entry)
	if not entry.Configured or (tonumber(entry.AssetId) or 0) <= 0 then
		return nil
	end
	local key = entry.ProductType .. ":" .. tostring(entry.AssetId)
	if productInfoCache[key] ~= nil then
		return productInfoCache[key] or nil
	end
	local success, info =
		pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.AssetId, infoTypeFor(entry))
	productInfoCache[key] = success and info or false
	return success and info or nil
end

local function clearCards()
	cardsByProductId = {}
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function useCompactCards()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return viewport.X < 620
end

local function applyCardLayout(parts)
	local compact = useCompactCards()
	parts.Icon.Visible = not compact
	if compact then
		parts.Name.Position = UDim2.new(0, 12, 0, 10)
		parts.Name.Size = UDim2.new(1, -158, 0, 23)
		parts.Type.Position = UDim2.new(0, 12, 0, 35)
		parts.Type.Size = UDim2.new(1, -158, 0, 17)
		parts.Description.Position = UDim2.new(0, 12, 0, 56)
		parts.Description.Size = UDim2.new(1, -158, 0, 64)
		parts.Buy.Size = UDim2.fromOffset(124, 56)
	else
		parts.Name.Position = UDim2.new(0, 100, 0, 12)
		parts.Name.Size = UDim2.new(1, -258, 0, 25)
		parts.Type.Position = UDim2.new(0, 100, 0, 38)
		parts.Type.Size = UDim2.new(1, -258, 0, 18)
		parts.Description.Position = UDim2.new(0, 100, 0, 59)
		parts.Description.Size = UDim2.new(1, -258, 0, 59)
		parts.Buy.Size = UDim2.fromOffset(138, 56)
	end
end

local function applyResponsiveLayout()
	local compact = useCompactCards()
	openButton.Position = UDim2.new(1, compact and -12 or -18, 0, compact and 54 or 64)
	openButton.Size = compact and UDim2.fromOffset(104, 46) or UDim2.fromOffset(126, 50)
	title.TextSize = compact and 18 or 23
	subtitle.TextSize = compact and 11 or 13
	for _, parts in pairs(cardsByProductId) do
		applyCardLayout(parts)
	end
end

local function createProductCard(entry, layoutOrder, serial)
	local card = Instance.new("Frame")
	card.Name = "Product_" .. tostring(entry.Id)
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(1, 0, 0, 132)
	card.BackgroundColor3 = entry.Available and COLORS.Card or COLORS.CardDisabled
	card.BorderSizePixel = 0
	card.Parent = list
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 15)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = entry.Recommended and COLORS.Gold or COLORS.Primary
	cardStroke.Thickness = entry.Recommended and 1.8 or 1
	cardStroke.Transparency = entry.Recommended and 0.15 or 0.62
	cardStroke.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Position = UDim2.new(0, 12, 0, 12)
	icon.Size = UDim2.fromOffset(76, 76)
	icon.BackgroundColor3 = Color3.fromRGB(18, 31, 47)
	icon.BorderSizePixel = 0
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = card
	Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 12)

	local iconFallback = Instance.new("TextLabel")
	iconFallback.Name = "Fallback"
	iconFallback.Size = UDim2.fromScale(1, 1)
	iconFallback.BackgroundTransparency = 1
	iconFallback.Text = string.sub(string.upper(tostring(entry.DisplayName or "ITEM")), 1, 3)
	iconFallback.TextColor3 = COLORS.Primary
	iconFallback.Font = Enum.Font.GothamBlack
	iconFallback.TextSize = 20
	iconFallback.Parent = icon

	local name = Instance.new("TextLabel")
	name.Name = "ProductName"
	name.Position = UDim2.new(0, 100, 0, 12)
	name.Size = UDim2.new(1, -258, 0, 25)
	name.BackgroundTransparency = 1
	name.Text = tostring(entry.DisplayName or "Produto")
	name.TextColor3 = COLORS.Text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Font = Enum.Font.GothamBold
	name.TextSize = 16
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = card

	local typeLabel = Instance.new("TextLabel")
	typeLabel.Position = UDim2.new(0, 100, 0, 38)
	typeLabel.Size = UDim2.new(1, -258, 0, 18)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Text = entry.ProductType == "GamePass" and "BENEFICIO PERMANENTE" or "PRODUTO CONSUMIVEL"
	typeLabel.TextColor3 = entry.ProductType == "GamePass" and COLORS.Gold or COLORS.Primary
	typeLabel.TextXAlignment = Enum.TextXAlignment.Left
	typeLabel.Font = Enum.Font.GothamBold
	typeLabel.TextSize = 10
	typeLabel.Parent = card

	local description = Instance.new("TextLabel")
	description.Position = UDim2.new(0, 100, 0, 59)
	description.Size = UDim2.new(1, -258, 0, 59)
	description.BackgroundTransparency = 1
	description.Text = tostring(entry.Description or "")
	description.TextColor3 = COLORS.Muted
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Font = Enum.Font.Gotham
	description.TextSize = 11
	description.Parent = card

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -12, 0.5, 0)
	buy.Size = UDim2.fromOffset(138, 56)
	buy.BackgroundColor3 = entry.Available and COLORS.Primary or Color3.fromRGB(75, 84, 94)
	buy.BorderSizePixel = 0
	buy.Text = entry.Available and (entry.Configured and "CARREGANDO..." or "INDISPONIVEL")
		or tostring(entry.UnavailableReason or "INDISPONIVEL")
	buy.TextColor3 = entry.Available and COLORS.PrimaryDark or COLORS.Muted
	buy.TextWrapped = true
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 12
	buy.AutoButtonColor = entry.Available == true
	buy.Active = entry.Available == true
	buy.Parent = card
	Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 12)

	buy.Activated:Connect(function()
		if not entry.Available then
			setStatus(entry.UnavailableReason or "Produto indisponivel.", COLORS.Bad)
			return
		end
		buy.Active = false
		buy.Text = "ABRINDO..."
		local success, result = pcall(request.InvokeServer, request, "PromptGlobal", entry.Id)
		if not success or type(result) ~= "table" then
			setStatus("Nao foi possivel abrir a compra.", COLORS.Bad)
			buy.Active = true
			buy.Text = "TENTAR NOVAMENTE"
			return
		end
		setStatus(result.Message, result.Success and COLORS.Good or COLORS.Bad)
		buy.Active = entry.Available == true
		local info = productInfo(entry)
		local price = info and tonumber(info.PriceInRobux)
		buy.Text = price and (tostring(price) .. " ROBUX") or "VER PRECO"
	end)

	local cardParts = {
		Card = card,
		Icon = icon,
		Name = name,
		Type = typeLabel,
		Description = description,
		Buy = buy,
	}
	cardsByProductId[entry.Id] = cardParts
	applyCardLayout(cardParts)
	task.spawn(function()
		local info = productInfo(entry)
		if renderSerial ~= serial or not card.Parent then
			return
		end
		local imageId = info and tonumber(info.IconImageAssetId)
		if imageId and imageId > 0 then
			icon.Image = "rbxassetid://" .. tostring(math.floor(imageId))
			iconFallback.Visible = false
		end
		local price = info and tonumber(info.PriceInRobux)
		if entry.Available then
			buy.Text = price and (tostring(price) .. " ROBUX") or "VER PRECO"
		end
	end)
end

local function renderStore(store)
	renderSerial += 1
	local serial = renderSerial
	clearCards()
	local entries = type(store) == "table" and store.Entries or {}
	if #entries == 0 then
		setStatus("Nenhum produto pago esta configurado no catalogo.", COLORS.Bad)
		return
	end
	for index, entry in ipairs(entries) do
		createProductCard(entry, index, serial)
	end
	setStatus("Selecione um produto para abrir a compra oficial do Roblox.", COLORS.Muted)
end

local function closeStore()
	storeOpen = false
	panel.Visible = false
	backdrop.Visible = false
end

local function openStore()
	if storeOpen then
		return
	end
	storeOpen = true
	setStatus("Carregando produtos...", COLORS.Muted)
	backdrop.Visible = true
	panel.Visible = true
	local success, store = pcall(request.InvokeServer, request, "OpenGlobalStore")
	if not storeOpen then
		return
	end
	if not success or type(store) ~= "table" then
		setStatus("A loja nao conseguiu carregar. Tente novamente.", COLORS.Bad)
		return
	end
	renderStore(store)
end

applyResponsiveLayout()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	applyResponsiveLayout()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
	end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
end

openButton.Activated:Connect(openStore)
closeButton.Activated:Connect(closeStore)
backdrop.Activated:Connect(closeStore)

UserInputService.InputBegan:Connect(function(input, processed)
	if
		not processed
		and storeOpen
		and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB)
	then
		closeStore()
	end
end)

player.CharacterAdded:Connect(function()
	if storeOpen then
		closeStore()
	end
end)

monetizationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or not storeOpen then
		return
	end
	if data.Action == "PurchaseGranted" or data.Action == "Entitlements" then
		setStatus(data.Message or "Compra concluida.", COLORS.Good)
		task.defer(function()
			local success, store = pcall(request.InvokeServer, request, "OpenGlobalStore")
			if success and type(store) == "table" and storeOpen then
				renderStore(store)
			end
		end)
	end
end)
