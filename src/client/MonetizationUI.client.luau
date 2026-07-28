-- Apresentacao narrativa do Mercador do Ceu.
--
-- Nao existe botao global de "Ofertas especiais": esta interface abre
-- diretamente quando o jogador conversa com o Mercador do Ceu. Cada pagina
-- apresenta um unico produto com imagem hero, historia e CTA especifico.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local villagerEvent = ReplicatedStorage:WaitForChild("VillagerEvent")
local monetizationEvent = ReplicatedStorage:WaitForChild("MonetizationEvent")
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")

local COLORS = {
	Backdrop = Color3.fromRGB(5, 9, 16),
	Panel = Color3.fromRGB(17, 27, 41),
	Hero = Color3.fromRGB(23, 42, 61),
	Card = Color3.fromRGB(29, 43, 61),
	Primary = Color3.fromRGB(83, 205, 255),
	PrimaryDark = Color3.fromRGB(10, 48, 66),
	Gold = Color3.fromRGB(255, 210, 91),
	Text = Color3.fromRGB(244, 249, 255),
	Muted = Color3.fromRGB(173, 194, 211),
	Good = Color3.fromRGB(100, 231, 158),
	Bad = Color3.fromRGB(247, 119, 126),
	Warning = Color3.fromRGB(255, 177, 79),
}

local oldGui = playerGui:FindFirstChild("MonetizationUI")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MonetizationUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 45
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLORS.Backdrop
backdrop.BackgroundTransparency = 0.22
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Modal = true
backdrop.Visible = false
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "SkyMerchantOffer"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.91, 0.88)
panel.BackgroundColor3 = COLORS.Panel
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 22)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(300, 260)
sizeConstraint.MaxSize = Vector2.new(1040, 700)
sizeConstraint.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Primary
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.22
panelStroke.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Position = UDim2.fromScale(0.025, 0.025)
header.Size = UDim2.fromScale(0.95, 0.105)
header.BackgroundTransparency = 1
header.Parent = panel

local merchantTitle = Instance.new("TextLabel")
merchantTitle.Name = "MerchantTitle"
merchantTitle.Size = UDim2.new(1, -62, 0.55, 0)
merchantTitle.BackgroundTransparency = 1
merchantTitle.Text = "MERCADOR DO CEU"
merchantTitle.TextColor3 = COLORS.Gold
merchantTitle.TextXAlignment = Enum.TextXAlignment.Left
merchantTitle.Font = Enum.Font.GothamBold
merchantTitle.TextScaled = true
merchantTitle.Parent = header
local merchantTitleConstraint = Instance.new("UITextSizeConstraint")
merchantTitleConstraint.MinTextSize = 15
merchantTitleConstraint.MaxTextSize = 25
merchantTitleConstraint.Parent = merchantTitle

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromScale(0, 0.57)
subtitle.Size = UDim2.new(1, -62, 0.36, 0)
subtitle.BackgroundTransparency = 1
subtitle.Text = "A OFERTA TERMINA QUANDO A ÁGUA CHEGAR À ILHA"
subtitle.TextColor3 = COLORS.Warning
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Font = Enum.Font.GothamBold
subtitle.TextScaled = true
subtitle.Parent = header
local subtitleConstraint = Instance.new("UITextSizeConstraint")
subtitleConstraint.MinTextSize = 9
subtitleConstraint.MaxTextSize = 13
subtitleConstraint.Parent = subtitle

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0)
closeButton.Size = UDim2.fromOffset(46, 42)
closeButton.BackgroundColor3 = Color3.fromRGB(69, 49, 60)
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.Text
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.Parent = header
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 11)

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromScale(0.025, 0.145)
content.Size = UDim2.fromScale(0.95, 0.69)
content.BackgroundTransparency = 1
content.Parent = panel

local hero = Instance.new("Frame")
hero.Name = "Hero"
hero.BackgroundColor3 = COLORS.Hero
hero.BorderSizePixel = 0
hero.ClipsDescendants = true
hero.Parent = content
Instance.new("UICorner", hero).CornerRadius = UDim.new(0, 18)
local heroStroke = Instance.new("UIStroke")
heroStroke.Color = COLORS.Primary
heroStroke.Transparency = 0.55
heroStroke.Parent = hero

local heroGradient = Instance.new("UIGradient")
heroGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 68, 92)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 24, 39)),
})
heroGradient.Rotation = 125
heroGradient.Parent = hero

local heroImage = Instance.new("ImageLabel")
heroImage.Name = "ProductHero"
heroImage.Position = UDim2.fromScale(0.06, 0.08)
heroImage.Size = UDim2.fromScale(0.88, 0.76)
heroImage.BackgroundTransparency = 1
heroImage.Image = ""
heroImage.ScaleType = Enum.ScaleType.Fit
heroImage.Parent = hero

local heroFallback = Instance.new("TextLabel")
heroFallback.Name = "HeroFallback"
heroFallback.AnchorPoint = Vector2.new(0.5, 0.5)
heroFallback.Position = UDim2.fromScale(0.5, 0.46)
heroFallback.Size = UDim2.fromScale(0.84, 0.44)
heroFallback.BackgroundTransparency = 1
heroFallback.Text = "ITEM DO CEU"
heroFallback.TextColor3 = COLORS.Primary
heroFallback.TextTransparency = 0.12
heroFallback.TextWrapped = true
heroFallback.Font = Enum.Font.GothamBlack
heroFallback.TextScaled = true
heroFallback.Parent = hero
local heroFallbackConstraint = Instance.new("UITextSizeConstraint")
heroFallbackConstraint.MinTextSize = 18
heroFallbackConstraint.MaxTextSize = 48
heroFallbackConstraint.Parent = heroFallback

local featuredBadge = Instance.new("TextLabel")
featuredBadge.Name = "FeaturedBadge"
featuredBadge.Position = UDim2.fromScale(0.045, 0.04)
featuredBadge.Size = UDim2.fromScale(0.61, 0.09)
featuredBadge.BackgroundColor3 = COLORS.Gold
featuredBadge.Text = "ESCOLHIDO PARA VOCE"
featuredBadge.TextColor3 = Color3.fromRGB(38, 30, 8)
featuredBadge.Font = Enum.Font.GothamBold
featuredBadge.TextScaled = true
featuredBadge.Visible = false
featuredBadge.Parent = hero
Instance.new("UICorner", featuredBadge).CornerRadius = UDim.new(1, 0)
local badgeConstraint = Instance.new("UITextSizeConstraint")
badgeConstraint.MinTextSize = 8
badgeConstraint.MaxTextSize = 12
badgeConstraint.Parent = featuredBadge

local heroCaption = Instance.new("TextLabel")
heroCaption.AnchorPoint = Vector2.new(0, 1)
heroCaption.Position = UDim2.fromScale(0.055, 0.965)
heroCaption.Size = UDim2.fromScale(0.89, 0.12)
heroCaption.BackgroundTransparency = 1
heroCaption.Text = ""
heroCaption.TextColor3 = COLORS.Text
heroCaption.TextXAlignment = Enum.TextXAlignment.Left
heroCaption.TextYAlignment = Enum.TextYAlignment.Center
heroCaption.Font = Enum.Font.GothamBold
heroCaption.TextScaled = true
heroCaption.Parent = hero
local captionConstraint = Instance.new("UITextSizeConstraint")
captionConstraint.MinTextSize = 10
captionConstraint.MaxTextSize = 18
captionConstraint.Parent = heroCaption

local details = Instance.new("Frame")
details.Name = "Details"
details.BackgroundTransparency = 1
details.Parent = content

local productName = Instance.new("TextLabel")
productName.Name = "ProductName"
productName.Size = UDim2.fromScale(1, 0.105)
productName.BackgroundTransparency = 1
productName.Text = ""
productName.TextColor3 = COLORS.Text
productName.TextXAlignment = Enum.TextXAlignment.Left
productName.Font = Enum.Font.GothamBold
productName.TextScaled = true
productName.Parent = details
local productNameConstraint = Instance.new("UITextSizeConstraint")
productNameConstraint.MinTextSize = 14
productNameConstraint.MaxTextSize = 25
productNameConstraint.Parent = productName

local reason = Instance.new("TextLabel")
reason.Name = "RecommendationReason"
reason.Position = UDim2.fromScale(0, 0.105)
reason.Size = UDim2.fromScale(1, 0.09)
reason.BackgroundTransparency = 1
reason.Text = ""
reason.TextColor3 = COLORS.Gold
reason.TextWrapped = true
reason.TextXAlignment = Enum.TextXAlignment.Left
reason.TextYAlignment = Enum.TextYAlignment.Top
reason.Font = Enum.Font.GothamMedium
reason.TextScaled = true
reason.Visible = false
reason.Parent = details
local reasonConstraint = Instance.new("UITextSizeConstraint")
reasonConstraint.MinTextSize = 9
reasonConstraint.MaxTextSize = 12
reasonConstraint.Parent = reason

local dialogue = Instance.new("TextLabel")
dialogue.Name = "Dialogue"
dialogue.Position = UDim2.fromScale(0, 0.205)
dialogue.Size = UDim2.fromScale(1, 0.145)
dialogue.BackgroundColor3 = COLORS.Card
dialogue.BackgroundTransparency = 0.08
dialogue.Text = ""
dialogue.TextColor3 = COLORS.Primary
dialogue.TextWrapped = true
dialogue.TextXAlignment = Enum.TextXAlignment.Left
dialogue.TextYAlignment = Enum.TextYAlignment.Center
dialogue.Font = Enum.Font.GothamMedium
dialogue.TextScaled = true
dialogue.Parent = details
Instance.new("UICorner", dialogue).CornerRadius = UDim.new(0, 12)
local dialoguePadding = Instance.new("UIPadding")
dialoguePadding.PaddingLeft = UDim.new(0.035, 0)
dialoguePadding.PaddingRight = UDim.new(0.035, 0)
dialoguePadding.Parent = dialogue
local dialogueConstraint = Instance.new("UITextSizeConstraint")
dialogueConstraint.MinTextSize = 9
dialogueConstraint.MaxTextSize = 14
dialogueConstraint.Parent = dialogue

local story = Instance.new("TextLabel")
story.Name = "Story"
story.Position = UDim2.fromScale(0, 0.37)
story.Size = UDim2.fromScale(1, 0.275)
story.BackgroundTransparency = 1
story.Text = ""
story.TextColor3 = COLORS.Muted
story.TextWrapped = true
story.TextXAlignment = Enum.TextXAlignment.Left
story.TextYAlignment = Enum.TextYAlignment.Top
story.Font = Enum.Font.Gotham
story.TextScaled = true
story.Parent = details
local storyConstraint = Instance.new("UITextSizeConstraint")
storyConstraint.MinTextSize = 9
storyConstraint.MaxTextSize = 13
storyConstraint.Parent = story

local salesLine = Instance.new("TextLabel")
salesLine.Name = "SalesLine"
salesLine.Position = UDim2.fromScale(0, 0.65)
salesLine.Size = UDim2.fromScale(1, 0.105)
salesLine.BackgroundTransparency = 1
salesLine.Text = ""
salesLine.TextColor3 = COLORS.Gold
salesLine.TextWrapped = true
salesLine.TextXAlignment = Enum.TextXAlignment.Left
salesLine.TextYAlignment = Enum.TextYAlignment.Top
salesLine.Font = Enum.Font.GothamMedium
salesLine.TextScaled = true
salesLine.Parent = details
local salesConstraint = Instance.new("UITextSizeConstraint")
salesConstraint.MinTextSize = 8
salesConstraint.MaxTextSize = 12
salesConstraint.Parent = salesLine

local buyButton = Instance.new("TextButton")
buyButton.Name = "ProductCTA"
buyButton.Position = UDim2.fromScale(0, 0.775)
buyButton.Size = UDim2.fromScale(1, 0.14)
buyButton.BackgroundColor3 = COLORS.Primary
buyButton.Text = "VER OFERTA"
buyButton.TextColor3 = COLORS.PrimaryDark
buyButton.TextWrapped = true
buyButton.Font = Enum.Font.GothamBold
buyButton.TextScaled = true
buyButton.Parent = details
Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 13)
local buyConstraint = Instance.new("UITextSizeConstraint")
buyConstraint.MinTextSize = 10
buyConstraint.MaxTextSize = 15
buyConstraint.Parent = buyButton

local odds = Instance.new("TextLabel")
odds.Name = "Odds"
odds.Position = UDim2.fromScale(0, 0.925)
odds.Size = UDim2.fromScale(1, 0.07)
odds.BackgroundTransparency = 1
odds.Text = ""
odds.TextColor3 = COLORS.Muted
odds.TextWrapped = true
odds.TextXAlignment = Enum.TextXAlignment.Left
odds.Font = Enum.Font.Gotham
odds.TextScaled = true
odds.Visible = false
odds.Parent = details
local oddsConstraint = Instance.new("UITextSizeConstraint")
oddsConstraint.MinTextSize = 8
oddsConstraint.MaxTextSize = 10
oddsConstraint.Parent = odds

local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.Position = UDim2.fromScale(0.025, 0.85)
footer.Size = UDim2.fromScale(0.95, 0.125)
footer.BackgroundTransparency = 1
footer.Parent = panel

local previousButton = Instance.new("TextButton")
previousButton.Name = "Previous"
previousButton.AnchorPoint = Vector2.new(0, 0.5)
previousButton.Position = UDim2.fromScale(0, 0.43)
previousButton.Size = UDim2.fromScale(0.155, 0.68)
previousButton.BackgroundColor3 = COLORS.Card
previousButton.Text = "<  ANTERIOR"
previousButton.TextColor3 = COLORS.Text
previousButton.Font = Enum.Font.GothamBold
previousButton.TextScaled = true
previousButton.Parent = footer
Instance.new("UICorner", previousButton).CornerRadius = UDim.new(0, 11)
local previousConstraint = Instance.new("UITextSizeConstraint")
previousConstraint.MinTextSize = 8
previousConstraint.MaxTextSize = 12
previousConstraint.Parent = previousButton

local pageLabel = Instance.new("TextLabel")
pageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
pageLabel.Position = UDim2.fromScale(0.5, 0.43)
pageLabel.Size = UDim2.fromScale(0.29, 0.68)
pageLabel.BackgroundTransparency = 1
pageLabel.Text = "1 / 1"
pageLabel.TextColor3 = COLORS.Muted
pageLabel.Font = Enum.Font.GothamMedium
pageLabel.TextScaled = true
pageLabel.Parent = footer
local pageConstraint = Instance.new("UITextSizeConstraint")
pageConstraint.MinTextSize = 9
pageConstraint.MaxTextSize = 13
pageConstraint.Parent = pageLabel

local nextButton = Instance.new("TextButton")
nextButton.Name = "Next"
nextButton.AnchorPoint = Vector2.new(1, 0.5)
nextButton.Position = UDim2.fromScale(1, 0.43)
nextButton.Size = UDim2.fromScale(0.155, 0.68)
nextButton.BackgroundColor3 = COLORS.Card
nextButton.Text = "PROXIMO  >"
nextButton.TextColor3 = COLORS.Text
nextButton.Font = Enum.Font.GothamBold
nextButton.TextScaled = true
nextButton.Parent = footer
Instance.new("UICorner", nextButton).CornerRadius = UDim.new(0, 11)
local nextConstraint = Instance.new("UITextSizeConstraint")
nextConstraint.MinTextSize = 8
nextConstraint.MaxTextSize = 12
nextConstraint.Parent = nextButton

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.fromScale(0.5, 1)
status.Size = UDim2.fromScale(0.64, 0.3)
status.BackgroundTransparency = 1
status.Text = "A compra so abre depois que voce tocar no produto."
status.TextColor3 = COLORS.Muted
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.TextScaled = true
status.Parent = footer
local statusConstraint = Instance.new("UITextSizeConstraint")
statusConstraint.MinTextSize = 7
statusConstraint.MaxTextSize = 10
statusConstraint.Parent = status

local expirationToast = Instance.new("TextLabel")
expirationToast.Name = "OfferExpiredToast"
expirationToast.AnchorPoint = Vector2.new(0.5, 0)
expirationToast.Position = UDim2.fromScale(0.5, 0.06)
expirationToast.Size = UDim2.new(0.86, 0, 0, 58)
expirationToast.BackgroundColor3 = Color3.fromRGB(77, 39, 24)
expirationToast.BackgroundTransparency = 0.05
expirationToast.BorderSizePixel = 0
expirationToast.Text = "A ÁGUA CHEGOU À ILHA — O MERCADOR PARTIU E A OFERTA TERMINOU."
expirationToast.TextColor3 = Color3.fromRGB(255, 232, 194)
expirationToast.TextWrapped = true
expirationToast.Font = Enum.Font.GothamBold
expirationToast.TextScaled = true
expirationToast.Visible = false
expirationToast.ZIndex = 20
expirationToast.Parent = gui
Instance.new("UICorner", expirationToast).CornerRadius = UDim.new(0, 14)
local expirationStroke = Instance.new("UIStroke")
expirationStroke.Color = COLORS.Warning
expirationStroke.Thickness = 1.5
expirationStroke.Transparency = 0.15
expirationStroke.Parent = expirationToast
local expirationPadding = Instance.new("UIPadding")
expirationPadding.PaddingLeft = UDim.new(0, 18)
expirationPadding.PaddingRight = UDim.new(0, 18)
expirationPadding.PaddingTop = UDim.new(0, 8)
expirationPadding.PaddingBottom = UDim.new(0, 8)
expirationPadding.Parent = expirationToast
local expirationConstraint = Instance.new("UITextSizeConstraint")
expirationConstraint.MinTextSize = 10
expirationConstraint.MaxTextSize = 16
expirationConstraint.Parent = expirationToast

local entries = {}
local currentIndex = 1
local renderSerial = 0
local productInfoCache = {}
local merchantOpen = false
local cameraState
local expirationToastSerial = 0

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
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	task.defer(function()
		RunService.RenderStepped:Wait()
		if not merchantOpen then
			UserInputService.MouseBehavior = state.MouseBehavior
			UserInputService.MouseIconEnabled = state.MouseIconEnabled
		end
	end)
end

local function applyLayout()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local stacked = viewport.X / math.max(1, viewport.Y) < 1.08
	if stacked then
		content.Position = UDim2.fromScale(0.04, 0.13)
		content.Size = UDim2.fromScale(0.92, 0.72)
		hero.Position = UDim2.fromScale(0, 0)
		hero.Size = UDim2.fromScale(1, 0.38)
		details.Position = UDim2.fromScale(0, 0.405)
		details.Size = UDim2.fromScale(1, 0.595)
		story.Size = UDim2.fromScale(1, 0.245)
	else
		content.Position = UDim2.fromScale(0.025, 0.145)
		content.Size = UDim2.fromScale(0.95, 0.69)
		hero.Position = UDim2.fromScale(0, 0)
		hero.Size = UDim2.fromScale(0.43, 1)
		details.Position = UDim2.fromScale(0.46, 0)
		details.Size = UDim2.fromScale(0.54, 1)
		story.Size = UDim2.fromScale(1, 0.275)
	end
end
applyLayout()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	applyLayout()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
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
	local success, info = pcall(
		MarketplaceService.GetProductInfo,
		MarketplaceService,
		entry.AssetId,
		infoTypeFor(entry)
	)
	productInfoCache[key] = success and info or false
	return success and info or nil
end

local function coinPrice(entry)
	return string.format("%d MOEDAS", math.floor(tonumber(entry.CoinPrice) or 0))
end

local function assetPrice(info)
	return info and tonumber(info.PriceInRobux)
end

local function priceText(entry, info)
	if entry.ProductType == "Coins" then
		return coinPrice(entry)
	end
	local price = assetPrice(info)
	return price and (tostring(price) .. " ROBUX") or "VER PRECO"
end

local function pitchFor(entry)
	return type(entry.MerchantPitch) == "table" and entry.MerchantPitch or {}
end

local function setStatus(text, color)
	status.Text = text or ""
	status.TextColor3 = color or COLORS.Muted
end

local function invoke(action, productId)
	local success, result = pcall(request.InvokeServer, request, action, productId)
	if not success or type(result) ~= "table" then
		setStatus("Nao foi possivel concluir o pedido.", COLORS.Bad)
		return nil
	end
	setStatus(result.Message or "", result.Success == false and COLORS.Bad or COLORS.Good)
	return result
end

local function setHero(entry, info, serial)
	if serial ~= renderSerial then
		return
	end
	local imageId = entry.HeroImageId
	if type(imageId) == "number" and imageId > 0 then
		imageId = "rbxassetid://" .. tostring(math.floor(imageId))
	elseif type(imageId) ~= "string" then
		imageId = ""
	end
	if imageId == "" and info and tonumber(info.IconImageAssetId) then
		imageId = "rbxassetid://" .. tostring(math.floor(info.IconImageAssetId))
	end
	heroImage.Image = imageId
	heroImage.Visible = imageId ~= ""
	heroFallback.Visible = imageId == ""
end

local function renderCurrent()
	local entry = entries[currentIndex]
	if not entry then
		return
	end
	renderSerial += 1
	local serial = renderSerial
	local pitch = pitchFor(entry)
	productName.Text = string.upper(entry.DisplayName or "OFERTA")
	reason.Text = entry.Recommended and ("POR QUE ESCOLHI ISTO: " .. tostring(entry.RecommendationReason or "")) or ""
	reason.Visible = entry.Recommended == true
	dialogue.Text = '"' .. tostring(pitch.Opening or "Tenho algo que pode mudar sua proxima expedicao.") .. '"'
	story.Text = tostring(pitch.Story or entry.Description or "")
	salesLine.Text = tostring(pitch.Offer or "Separei esta mercadoria para a sua jornada.")
	odds.Text = tostring(entry.OddsText or "")
	odds.Visible = entry.OddsText ~= nil and entry.OddsText ~= ""
	heroFallback.Text = tostring(pitch.HeroFallback or entry.DisplayName or "ITEM DO CEU")
	heroCaption.Text = entry.DisplayName or ""
	featuredBadge.Visible = entry.Recommended == true
	pageLabel.Text = string.format("%d / %d", currentIndex, #entries)
	previousButton.Active = #entries > 1
	nextButton.Active = #entries > 1
	previousButton.AutoButtonColor = #entries > 1
	nextButton.AutoButtonColor = #entries > 1
	heroImage.Image = ""
	heroImage.Visible = false
	heroFallback.Visible = true

	local initialPrice = entry.ProductType == "Coins"
		and coinPrice(entry)
		or (entry.Configured and "CARREGANDO PRECO..." or "NAO CONFIGURADO")
	buyButton.Text = string.format("%s\n%s", tostring(pitch.CTA or "VER OFERTA"), initialPrice)
	buyButton.Active = entry.Available == true
	buyButton.AutoButtonColor = entry.Available == true
	buyButton.BackgroundColor3 = entry.Available and COLORS.Primary or Color3.fromRGB(72, 83, 94)
	buyButton.TextColor3 = entry.Available and COLORS.PrimaryDark or COLORS.Muted
	setStatus(
		entry.Available and "A compra so abre depois que voce tocar no produto."
			or tostring(entry.UnavailableReason or "Oferta ainda nao configurada."),
		entry.Available and COLORS.Muted or COLORS.Bad
	)

	task.spawn(function()
		local info = productInfo(entry)
		if serial ~= renderSerial then
			return
		end
		setHero(entry, info, serial)
		local price = priceText(entry, info)
		buyButton.Text = string.format("%s\n%s", tostring(pitch.CTA or "VER OFERTA"), price)
		local previous = tonumber(entry.PreviousRobux)
		local current = assetPrice(info)
		if previous and current and previous > current then
			salesLine.Text = string.format(
				"Eu costumava vender por %d Robux, mas para voce a oferta e especial: %d Robux.",
				math.floor(previous),
				math.floor(current)
			)
		end
	end)
end

local function orderedEntries(store)
	local result = {}
	for index, entry in ipairs(store.Entries or {}) do
		entry._CatalogOrder = index
		table.insert(result, entry)
	end
	table.sort(result, function(left, right)
		if left.Recommended ~= right.Recommended then
			return left.Recommended == true
		end
		if left.Available ~= right.Available then
			return left.Available == true
		end
		return left._CatalogOrder < right._CatalogOrder
	end)
	return result
end

local function renderStore(store, preserveProductId)
	entries = orderedEntries(store)
	currentIndex = 1
	if preserveProductId then
		for index, entry in ipairs(entries) do
			if entry.Id == preserveProductId then
				currentIndex = index
				break
			end
		end
	end
	if #entries == 0 then
		setStatus("O Mercador ainda nao possui mercadorias disponiveis.", COLORS.Bad)
		return
	end
	renderCurrent()
end

local function closeMerchant(notifyServer)
	local wasOpen = merchantOpen
	merchantOpen = false
	panel.Visible = false
	backdrop.Visible = false
	restoreCamera()
	if wasOpen and notifyServer ~= false then
		villagerEvent:FireServer({ action = "closeShop" })
	end
end

local function showExpirationToast(message)
	expirationToastSerial += 1
	local serial = expirationToastSerial
	expirationToast.Text = string.upper(
		tostring(message or "A água chegou à ilha — o Mercador partiu e a oferta terminou.")
	)
	expirationToast.Visible = true
	task.delay(3.5, function()
		if expirationToastSerial == serial then
			expirationToast.Visible = false
		end
	end)
end

local function openMerchant()
	local success, store = pcall(request.InvokeServer, request, "OpenStore")
	if not success or type(store) ~= "table" then
		closeMerchant()
		return
	end
	merchantOpen = true
	releaseFirstPerson()
	backdrop.Visible = true
	panel.Visible = true
	renderStore(store)
end

buyButton.Activated:Connect(function()
	local entry = entries[currentIndex]
	if not entry then
		return
	end
	if not entry.Available then
		setStatus(entry.UnavailableReason or "Oferta indisponivel.", COLORS.Bad)
		return
	end
	buyButton.Active = false
	local result = invoke("Prompt", entry.Id)
	buyButton.Active = true
	if result and result.Store then
		renderStore(result.Store, entry.Id)
	end
end)

previousButton.Activated:Connect(function()
	if #entries <= 1 then
		return
	end
	currentIndex = ((currentIndex - 2) % #entries) + 1
	renderCurrent()
end)

nextButton.Activated:Connect(function()
	if #entries <= 1 then
		return
	end
	currentIndex = (currentIndex % #entries) + 1
	renderCurrent()
end)

local function requestClose()
	local entry = entries[currentIndex]
	if entry and entry.Recommended then
		invoke("DismissOffer", entry.Id)
	end
	closeMerchant()
end

closeButton.Activated:Connect(requestClose)
backdrop.Activated:Connect(requestClose)

player.CharacterAdded:Connect(function()
	if merchantOpen then
		closeMerchant()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and merchantOpen
		and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB)
	then
		requestClose()
	end
end)

villagerEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.action == "showSkyMerchant" then
		openMerchant()
	elseif data.action == "showShop" then
		if merchantOpen then
			closeMerchant(false)
		end
	elseif data.action == "merchantOfferExpired" then
		if merchantOpen then
			closeMerchant(false)
		end
		showExpirationToast(data.message)
	elseif data.action == "closeShop" then
		closeMerchant(false)
	end
end)

monetizationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "OfferReady" and merchantOpen then
		task.defer(openMerchant)
	elseif data.Action == "PurchaseGranted" or data.Action == "Entitlements" then
		setStatus(data.Message or "Compra concluida.", COLORS.Good)
		if merchantOpen then
			local current = entries[currentIndex]
			task.defer(function()
				local success, store = pcall(request.InvokeServer, request, "GetStore")
				if success and type(store) == "table" then
					renderStore(store, current and current.Id)
				end
			end)
		end
	end
end)
