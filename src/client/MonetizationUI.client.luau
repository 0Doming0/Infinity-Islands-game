-- Loja premium acessivel apenas durante a conversa com o Mercador do Ceu.
-- Precos em Robux sao consultados no cliente para respeitar precos regionais
-- e testes de otimizacao configurados no Creator Hub.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local villagerEvent = ReplicatedStorage:WaitForChild("VillagerEvent")
local monetizationEvent = ReplicatedStorage:WaitForChild("MonetizationEvent")
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")

local COLORS = {
	Background = Color3.fromRGB(12, 18, 28),
	Panel = Color3.fromRGB(24, 34, 49),
	Card = Color3.fromRGB(34, 47, 65),
	Primary = Color3.fromRGB(84, 204, 255),
	Gold = Color3.fromRGB(255, 210, 82),
	Text = Color3.fromRGB(242, 248, 255),
	Muted = Color3.fromRGB(168, 188, 208),
	Good = Color3.fromRGB(99, 229, 151),
	Bad = Color3.fromRGB(246, 118, 118),
}

local gui = Instance.new("ScreenGui")
gui.Name = "MonetizationUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 45
gui.Parent = playerGui

local merchantButton = Instance.new("TextButton")
merchantButton.Name = "SpecialOffersButton"
merchantButton.AnchorPoint = Vector2.new(1, 1)
merchantButton.Position = UDim2.new(1, -22, 1, -118)
merchantButton.Size = UDim2.fromOffset(190, 46)
merchantButton.BackgroundColor3 = COLORS.Panel
merchantButton.TextColor3 = COLORS.Text
merchantButton.Text = "OFERTAS ESPECIAIS"
merchantButton.TextSize = 13
merchantButton.Font = Enum.Font.GothamBold
merchantButton.Visible = false
merchantButton.Parent = gui
Instance.new("UICorner", merchantButton).CornerRadius = UDim.new(0, 12)
local merchantStroke = Instance.new("UIStroke")
merchantStroke.Color = COLORS.Primary
merchantStroke.Thickness = 1.5
merchantStroke.Parent = merchantButton

local badge = Instance.new("TextLabel")
badge.Name = "Badge"
badge.AnchorPoint = Vector2.new(0.5, 0.5)
badge.Position = UDim2.new(1, -4, 0, 4)
badge.Size = UDim2.fromOffset(24, 24)
badge.BackgroundColor3 = COLORS.Gold
badge.TextColor3 = Color3.fromRGB(30, 24, 8)
badge.Text = "1"
badge.TextSize = 13
badge.Font = Enum.Font.GothamBold
badge.Visible = false
badge.Parent = merchantButton
Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new()
backdrop.BackgroundTransparency = 0.35
backdrop.Text = ""
backdrop.Visible = false
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Store"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.88, 0, 0.82, 0)
panel.SizeConstraint = Enum.SizeConstraint.RelativeYY
panel.BackgroundColor3 = COLORS.Background
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Primary
panelStroke.Transparency = 0.25
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(22, 14)
title.Size = UDim2.new(1, -90, 0, 34)
title.BackgroundTransparency = 1
title.Text = "MERCADOR DO CEU"
title.TextColor3 = COLORS.Text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 14)
close.Size = UDim2.fromOffset(38, 34)
close.BackgroundColor3 = COLORS.Card
close.Text = "X"
close.TextColor3 = COLORS.Text
close.Font = Enum.Font.GothamBold
close.TextSize = 15
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 9)

local notice = Instance.new("TextLabel")
notice.Position = UDim2.fromOffset(22, 50)
notice.Size = UDim2.new(1, -44, 0, 42)
notice.BackgroundTransparency = 1
notice.Text = "Compras sao opcionais. Nenhuma oferta inicia uma compra automaticamente."
notice.TextColor3 = COLORS.Muted
notice.TextWrapped = true
notice.TextXAlignment = Enum.TextXAlignment.Left
notice.TextYAlignment = Enum.TextYAlignment.Top
notice.Font = Enum.Font.Gotham
notice.TextSize = 12
notice.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(18, 94)
scroll.Size = UDim2.new(1, -36, 1, -142)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.Parent = scroll

local message = Instance.new("TextLabel")
message.AnchorPoint = Vector2.new(0, 1)
message.Position = UDim2.new(0, 22, 1, -10)
message.Size = UDim2.new(1, -44, 0, 30)
message.BackgroundTransparency = 1
message.TextColor3 = COLORS.Muted
message.TextXAlignment = Enum.TextXAlignment.Left
message.TextWrapped = true
message.Font = Enum.Font.GothamMedium
message.TextSize = 12
message.Parent = panel

local currentStore
local priceCache = {}
local openStore

local function robuxPrice(entry)
	if not entry.Configured or entry.AssetId <= 0 then
		return "NAO CONFIGURADO"
	end
	local cacheKey = entry.ProductType .. ":" .. entry.AssetId
	if priceCache[cacheKey] then
		return priceCache[cacheKey]
	end
	local infoType = entry.ProductType == "GamePass"
		and Enum.InfoType.GamePass or Enum.InfoType.Product
	local success, info = pcall(
		MarketplaceService.GetProductInfo,
		MarketplaceService,
		entry.AssetId,
		infoType
	)
	local text = success and info and info.PriceInRobux
		and (tostring(info.PriceInRobux) .. " ROBUX") or "VER PRECO"
	priceCache[cacheKey] = text
	return text
end

local function clearCards()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function invoke(action, productId)
	local success, result = pcall(request.InvokeServer, request, action, productId)
	if not success or type(result) ~= "table" then
		message.Text = "Nao foi possivel concluir o pedido."
		message.TextColor3 = COLORS.Bad
		return nil
	end
	message.Text = result.Message or ""
	message.TextColor3 = result.Success == false and COLORS.Bad or COLORS.Good
	return result
end

local function render(store)
	currentStore = store
	clearCards()
	for _, entry in ipairs(store.Entries or {}) do
		local card = Instance.new("Frame")
		card.Name = entry.Id
		card.Size = UDim2.new(1, -6, 0, entry.Recommended and 154 or 132)
		card.BackgroundColor3 = entry.Recommended and Color3.fromRGB(50, 49, 62) or COLORS.Card
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 13)
		local stroke = Instance.new("UIStroke")
		stroke.Color = entry.Recommended and COLORS.Gold or COLORS.Primary
		stroke.Transparency = entry.Recommended and 0.05 or 0.7
		stroke.Parent = card

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(14, 10)
		name.Size = UDim2.new(1, -160, 0, 24)
		name.BackgroundTransparency = 1
		name.Text = entry.DisplayName
		name.TextColor3 = COLORS.Text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.Parent = card

		local description = Instance.new("TextLabel")
		description.Position = UDim2.fromOffset(14, 36)
		description.Size = UDim2.new(1, -160, 0, 70)
		description.BackgroundTransparency = 1
		description.Text = entry.Description .. (entry.OddsText and ("\n" .. entry.OddsText) or "")
		description.TextColor3 = COLORS.Muted
		description.TextWrapped = true
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.Font = Enum.Font.Gotham
		description.TextSize = 11
		description.Parent = card

		if entry.Recommended then
			local reason = Instance.new("TextLabel")
			reason.Position = UDim2.new(0, 14, 1, -37)
			reason.Size = UDim2.new(1, -170, 0, 28)
			reason.BackgroundTransparency = 1
			reason.Text = "RECOMENDADO: " .. tostring(entry.RecommendationReason or "")
			reason.TextColor3 = COLORS.Gold
			reason.TextWrapped = true
			reason.TextXAlignment = Enum.TextXAlignment.Left
			reason.Font = Enum.Font.GothamMedium
			reason.TextSize = 10
			reason.Parent = card
		end

		local buy = Instance.new("TextButton")
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -12, 0.5, 0)
		buy.Size = UDim2.fromOffset(132, 46)
		buy.BackgroundColor3 = entry.Available and COLORS.Primary or Color3.fromRGB(75, 84, 96)
		buy.TextColor3 = entry.Available and Color3.fromRGB(10, 25, 35) or COLORS.Muted
		buy.TextWrapped = true
		buy.Text = entry.ProductType == "Coins"
			and (tostring(entry.CoinPrice) .. " MOEDAS")
			or robuxPrice(entry)
		buy.Font = Enum.Font.GothamBold
		buy.TextSize = 11
		buy.Active = entry.Available == true
		buy.AutoButtonColor = entry.Available == true
		buy.Parent = card
		Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 10)
		buy.Activated:Connect(function()
			if entry.Available then
				local result = invoke("Prompt", entry.Id)
				if result and result.Store then
					render(result.Store)
				end
			elseif entry.UnavailableReason then
				message.Text = entry.UnavailableReason
				message.TextColor3 = COLORS.Muted
			end
		end)
		if entry.Recommended then
			local later = Instance.new("TextButton")
			later.AnchorPoint = Vector2.new(1, 0)
			later.Position = UDim2.new(1, -12, 0.5, 28)
			later.Size = UDim2.fromOffset(132, 26)
			later.BackgroundTransparency = 1
			later.Text = "AGORA NAO"
			later.TextColor3 = COLORS.Muted
			later.Font = Enum.Font.GothamMedium
			later.TextSize = 10
			later.Parent = card
			later.Activated:Connect(function()
				local result = invoke("DismissOffer", entry.Id)
				if result and result.Success then
					badge.Visible = false
					if result.Store then
						render(result.Store)
					end
				end
			end)
		end
	end
end

openStore = function()
	local success, store = pcall(request.InvokeServer, request, "OpenStore")
	if not success or type(store) ~= "table" then
		return
	end
	backdrop.Visible = true
	panel.Visible = true
	badge.Visible = false
	render(store)
end

local function closeStore()
	backdrop.Visible = false
	panel.Visible = false
end

merchantButton.Activated:Connect(openStore)
close.Activated:Connect(closeStore)
backdrop.Activated:Connect(closeStore)

villagerEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.action == "showShop" then
		merchantButton.Visible = data.includesPremiumStore == true
		badge.Visible = merchantButton.Visible and player:GetAttribute("MerchantOfferReady") == true
	elseif data.action == "closeShop" then
		merchantButton.Visible = false
		closeStore()
	end
end)

monetizationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "OfferReady" then
		badge.Visible = merchantButton.Visible
	elseif data.Action == "PurchaseGranted" or data.Action == "Entitlements" then
		message.Text = data.Message or message.Text
		message.TextColor3 = COLORS.Good
		if panel.Visible then
			task.defer(openStore)
		end
	end
end)
