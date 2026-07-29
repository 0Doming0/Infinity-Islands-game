-- Roleta vertical de recompensas.
-- O servidor decide, concede e informa o slot vencedor. O cliente apenas anima.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local event = ReplicatedStorage:WaitForChild("RewardWheelEvent")
local monetizationRequest = ReplicatedStorage:WaitForChild("MonetizationRequest")
local monetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))
local catalog = require(ReplicatedStorage:WaitForChild("RewardWheelCatalog"))

local UI_PROTOCOL_VERSION = math.max(1, math.floor(tonumber(catalog.UiProtocolVersion) or 3))
local RUNTIME_MARKER_NAME = string.format("_RewardWheelRuntimeV%d", UI_PROTOCOL_VERSION)
local GUI_NAME_PREFIX = "RewardWheelUI"

-- Apenas um controlador atual pode permanecer ativo. Isto também permite
-- substituir o LocalScript via Rojo durante um teste sem preservar uma GUI
-- desconectada da versão nova.
local existingMarker = playerGui:FindFirstChild(RUNTIME_MARKER_NAME)
if existingMarker and existingMarker:IsA("ObjectValue") then
	local owner = existingMarker.Value
	if owner and owner.Parent then
		return
	end
	existingMarker:Destroy()
elseif existingMarker then
	existingMarker:Destroy()
end

local runtimeMarker = Instance.new("ObjectValue")
runtimeMarker.Name = RUNTIME_MARKER_NAME
runtimeMarker.Value = script
runtimeMarker.Parent = playerGui

local function isRewardWheelGui(instance)
	return instance:IsA("ScreenGui")
		and string.sub(instance.Name, 1, #GUI_NAME_PREFIX) == GUI_NAME_PREFIX
end

-- Pacotes antigos entregavam um segundo LocalScript renomeado. Caso ele ainda
-- exista no Studio, sua interface modal não pode competir com a versão atual.
for _, child in ipairs(playerGui:GetChildren()) do
	if isRewardWheelGui(child) then
		child:Destroy()
	end
end

local GOLD = Color3.fromRGB(255, 203, 67)
local GOLD_LIGHT = Color3.fromRGB(255, 239, 167)
local PANEL = Color3.fromRGB(11, 16, 27)
local SURFACE = Color3.fromRGB(20, 28, 43)
local TEXT = Color3.fromRGB(247, 249, 253)
local MUTED = Color3.fromRGB(168, 181, 204)

local PANEL_WIDTH = 500
local PANEL_HEIGHT = 700
local VIEWPORT_WIDTH = 420
local VIEWPORT_HEIGHT = 430
local SLOT_WIDTH = 382
local SLOT_HEIGHT = 142
local SLOT_GAP = 12
local COMPACT_UI_MODE = catalog.CompactUiMode or "CompactCorner"
local COMPACT_SOURCE_IDS = table.freeze({
	HeightLevel = true,
	Height = true,
	LevelUp = true,
	RunLevel = true,
})
local COMPACT_PANEL_WIDTH = 246
local COMPACT_PANEL_HEIGHT = 316
local COMPACT_VIEWPORT_WIDTH = 216
local COMPACT_VIEWPORT_HEIGHT = 160
local COMPACT_SLOT_WIDTH = 196
local COMPACT_SLOT_HEIGHT = 52
local COMPACT_SLOT_GAP = 6
local COMPACT_MARGIN = 16
local COMPACT_TOUCH_RIGHT_MARGIN = 88
local COMPACT_TOUCH_BOTTOM_MARGIN = 92
local COMPACT_RESULT_HOLD_SECONDS = 2

local layoutPanelWidth = PANEL_WIDTH
local layoutPanelHeight = PANEL_HEIGHT
local layoutViewportWidth = VIEWPORT_WIDTH
local layoutViewportHeight = VIEWPORT_HEIGHT
local layoutSlotWidth = SLOT_WIDTH
local layoutSlotHeight = SLOT_HEIGHT
local layoutSlotGap = SLOT_GAP

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function isImageId(value)
	return type(value) == "string"
		and value ~= ""
		and (string.match(value, "^rbxassetid://%d+$") ~= nil or string.match(value, "^rbxasset://") ~= nil)
end

local gui = Instance.new("ScreenGui")
gui.Name = "RewardWheelUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 80
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui:SetAttribute("UiProtocolVersion", UI_PROTOCOL_VERSION)
gui:SetAttribute("SupportsCompactCorner", true)
gui.Parent = playerGui

playerGui.ChildAdded:Connect(function(child)
	if child == gui or not isRewardWheelGui(child) then
		return
	end
	local childVersion = math.floor(tonumber(child:GetAttribute("UiProtocolVersion")) or 0)
	if childVersion < UI_PROTOCOL_VERSION then
		child:Destroy()
	end
end)

local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(2, 5, 10)
shade.BackgroundTransparency = 0.3
shade.BorderSizePixel = 0
shade.Active = false
shade.Selectable = false
shade.ZIndex = 1
shade.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.01
panel.BorderSizePixel = 0
panel.Active = false
panel.Selectable = false
panel.ZIndex = 2
panel.Parent = gui
addCorner(panel, 25)
addStroke(panel, GOLD, 2.5, 0.05)

local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 38, 55)),
	ColorSequenceKeypoint.new(0.52, PANEL),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 10, 18)),
})
panelGradient.Rotation = 110
panelGradient.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(20, 12)
title.Size = UDim2.new(1, -40, 0, 31)
title.BackgroundTransparency = 1
title.Text = "ROLETA DE RECOMPENSAS"
title.TextColor3 = GOLD_LIGHT
title.Font = Enum.Font.GothamBlack
title.TextSize = 22
title.ZIndex = 20
title.Parent = panel

local sourceLabel = Instance.new("TextLabel")
sourceLabel.Name = "Source"
sourceLabel.Position = UDim2.fromOffset(20, 43)
sourceLabel.Size = UDim2.new(1, -40, 0, 20)
sourceLabel.BackgroundTransparency = 1
sourceLabel.Text = ""
sourceLabel.TextColor3 = MUTED
sourceLabel.Font = Enum.Font.GothamMedium
sourceLabel.TextSize = 13
sourceLabel.ZIndex = 20
sourceLabel.Parent = panel

local reelShadow = Instance.new("Frame")
reelShadow.Name = "ReelShadow"
reelShadow.AnchorPoint = Vector2.new(0.5, 0)
reelShadow.Position = UDim2.new(0.5, 4, 0, 78)
reelShadow.Size = UDim2.fromOffset(VIEWPORT_WIDTH + 8, VIEWPORT_HEIGHT + 8)
reelShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
reelShadow.BackgroundTransparency = 0.45
reelShadow.BorderSizePixel = 0
reelShadow.ZIndex = 1
reelShadow.Parent = panel
addCorner(reelShadow, 20)

local reelViewport = Instance.new("Frame")
reelViewport.Name = "VerticalReel"
reelViewport.AnchorPoint = Vector2.new(0.5, 0)
reelViewport.Position = UDim2.new(0.5, 0, 0, 74)
reelViewport.Size = UDim2.fromOffset(VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
reelViewport.BackgroundColor3 = Color3.fromRGB(7, 11, 19)
reelViewport.BorderSizePixel = 0
reelViewport.ClipsDescendants = true
reelViewport.ZIndex = 2
reelViewport.Parent = panel
addCorner(reelViewport, 18)
addStroke(reelViewport, GOLD, 4, 0)

local reelGradient = Instance.new("UIGradient")
reelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 24, 37)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(7, 11, 19)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 24, 37)),
})
reelGradient.Rotation = 90
reelGradient.Parent = reelViewport

local reelContent = Instance.new("Frame")
reelContent.Name = "ReelContent"
reelContent.Position = UDim2.fromOffset(0, 0)
reelContent.Size = UDim2.fromOffset(VIEWPORT_WIDTH, 1)
reelContent.BackgroundTransparency = 1
reelContent.ZIndex = 3
reelContent.Parent = reelViewport

-- Moldura fixa: o item dentro desta faixa e sempre o prêmio realmente entregue.
local selectorGlow = Instance.new("Frame")
selectorGlow.Name = "WinnerSelectorGlow"
selectorGlow.AnchorPoint = Vector2.new(0.5, 0.5)
selectorGlow.Position = UDim2.fromScale(0.5, 0.5)
selectorGlow.Size = UDim2.fromOffset(SLOT_WIDTH + 10, SLOT_HEIGHT + 10)
selectorGlow.BackgroundColor3 = GOLD
selectorGlow.BackgroundTransparency = 0.9
selectorGlow.BorderSizePixel = 0
selectorGlow.ZIndex = 12
selectorGlow.Parent = reelViewport
addCorner(selectorGlow, 18)
addStroke(selectorGlow, GOLD_LIGHT, 3, 0)

local leftPointer = Instance.new("TextLabel")
leftPointer.Name = "LeftPointer"
leftPointer.AnchorPoint = Vector2.new(0.5, 0.5)
leftPointer.Position = UDim2.new(0, 9, 0.5, 0)
leftPointer.Size = UDim2.fromOffset(32, 52)
leftPointer.BackgroundTransparency = 1
leftPointer.Text = "▶"
leftPointer.TextColor3 = GOLD
leftPointer.TextStrokeColor3 = Color3.fromRGB(78, 43, 4)
leftPointer.TextStrokeTransparency = 0
leftPointer.Font = Enum.Font.GothamBlack
leftPointer.TextSize = 28
leftPointer.ZIndex = 15
leftPointer.Parent = reelViewport

local rightPointer = Instance.new("TextLabel")
rightPointer.Name = "RightPointer"
rightPointer.AnchorPoint = Vector2.new(0.5, 0.5)
rightPointer.Position = UDim2.new(1, -9, 0.5, 0)
rightPointer.Size = UDim2.fromOffset(32, 52)
rightPointer.BackgroundTransparency = 1
rightPointer.Text = "◀"
rightPointer.TextColor3 = GOLD
rightPointer.TextStrokeColor3 = Color3.fromRGB(78, 43, 4)
rightPointer.TextStrokeTransparency = 0
rightPointer.Font = Enum.Font.GothamBlack
rightPointer.TextSize = 28
rightPointer.ZIndex = 15
rightPointer.Parent = reelViewport

local topFade = Instance.new("Frame")
topFade.Name = "TopFade"
topFade.Size = UDim2.new(1, 0, 0, 86)
topFade.BackgroundColor3 = Color3.fromRGB(7, 11, 19)
topFade.BackgroundTransparency = 0.15
topFade.BorderSizePixel = 0
topFade.ZIndex = 10
topFade.Parent = reelViewport
local topFadeGradient = Instance.new("UIGradient")
topFadeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(1, 1),
})
topFadeGradient.Rotation = 90
topFadeGradient.Parent = topFade

local bottomFade = Instance.new("Frame")
bottomFade.Name = "BottomFade"
bottomFade.AnchorPoint = Vector2.new(0, 1)
bottomFade.Position = UDim2.fromScale(0, 1)
bottomFade.Size = UDim2.new(1, 0, 0, 86)
bottomFade.BackgroundColor3 = Color3.fromRGB(7, 11, 19)
bottomFade.BackgroundTransparency = 0.15
bottomFade.BorderSizePixel = 0
bottomFade.ZIndex = 10
bottomFade.Parent = reelViewport
local bottomFadeGradient = Instance.new("UIGradient")
bottomFadeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0.05),
})
bottomFadeGradient.Rotation = 90
bottomFadeGradient.Parent = bottomFade

local resultCard = Instance.new("Frame")
resultCard.Name = "ResultCard"
resultCard.Position = UDim2.fromOffset(20, 524)
resultCard.Size = UDim2.new(1, -40, 0, 153)
resultCard.BackgroundColor3 = SURFACE
resultCard.BackgroundTransparency = 0.06
resultCard.BorderSizePixel = 0
resultCard.ZIndex = 20
resultCard.Parent = panel
addCorner(resultCard, 16)
local resultStroke = addStroke(resultCard, GOLD, 1.5, 0.48)

local resultLabel = Instance.new("TextLabel")
resultLabel.Name = "Result"
resultLabel.Position = UDim2.fromOffset(14, 13)
resultLabel.Size = UDim2.new(1, -28, 0, 53)
resultLabel.BackgroundTransparency = 1
resultLabel.Text = "Sorteando..."
resultLabel.TextColor3 = TEXT
resultLabel.Font = Enum.Font.GothamBlack
resultLabel.TextSize = 20
resultLabel.TextWrapped = true
resultLabel.ZIndex = 21
resultLabel.Parent = resultCard

local detailLabel = Instance.new("TextLabel")
detailLabel.Name = "Detail"
detailLabel.Position = UDim2.fromOffset(16, 63)
detailLabel.Size = UDim2.new(1, -32, 0, 35)
detailLabel.BackgroundTransparency = 1
detailLabel.Text = "O servidor está confirmando sua recompensa."
detailLabel.TextColor3 = MUTED
detailLabel.Font = Enum.Font.GothamMedium
detailLabel.TextSize = 13
detailLabel.TextWrapped = true
detailLabel.ZIndex = 21
detailLabel.Parent = resultCard

local spinAgainButton = Instance.new("TextButton")
spinAgainButton.Name = "SpinAgain"
spinAgainButton.Position = UDim2.fromOffset(14, 105)
spinAgainButton.Size = UDim2.new(0.58, -18, 0, 35)
spinAgainButton.BackgroundColor3 = GOLD
spinAgainButton.BorderSizePixel = 0
spinAgainButton.Text = "GIRAR NOVAMENTE"
spinAgainButton.TextColor3 = Color3.fromRGB(22, 16, 5)
spinAgainButton.Font = Enum.Font.GothamBlack
spinAgainButton.TextSize = 13
spinAgainButton.Visible = false
spinAgainButton.ZIndex = 22
spinAgainButton.Parent = resultCard
addCorner(spinAgainButton, 10)

local continueButton = Instance.new("TextButton")
continueButton.Name = "Continue"
continueButton.AnchorPoint = Vector2.new(1, 0)
continueButton.Position = UDim2.new(1, -14, 0, 105)
continueButton.Size = UDim2.new(0.42, -10, 0, 35)
continueButton.BackgroundColor3 = Color3.fromRGB(50, 61, 79)
continueButton.BorderSizePixel = 0
continueButton.Text = "CONTINUAR"
continueButton.TextColor3 = TEXT
continueButton.Font = Enum.Font.GothamBold
continueButton.TextSize = 12
continueButton.Visible = false
continueButton.ZIndex = 22
continueButton.Parent = resultCard
addCorner(continueButton, 10)

local rewardSound = Instance.new("Sound")
rewardSound.Name = "RewardWheelWin"
rewardSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
rewardSound.Volume = 0.6
rewardSound.Parent = panel

local queue = {}
local processing = false
local resultChoiceSerial = 0
local purchasePending = false
local compactLayout = false

continueButton.Activated:Connect(function()
	resultChoiceSerial += 1
	gui.Enabled = false
end)

spinAgainButton.Activated:Connect(function()
	if purchasePending then
		return
	end
	purchasePending = true
	spinAgainButton.Active = false
	spinAgainButton.AutoButtonColor = false
	local ok, response = pcall(monetizationRequest.InvokeServer, monetizationRequest, "PromptSpinAgain")
	if not ok or type(response) ~= "table" or response.Success ~= true then
		detailLabel.Text = type(response) == "table" and tostring(response.Message)
			or "Nao foi possivel abrir a compra."
		purchasePending = false
		spinAgainButton.Active = true
		spinAgainButton.AutoButtonColor = true
		return
	end
	resultChoiceSerial += 1
	gui.Enabled = false
	purchasePending = false
end)

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if compactLayout then
		local rightMargin = if UserInputService.TouchEnabled then COMPACT_TOUCH_RIGHT_MARGIN else COMPACT_MARGIN
		local bottomMargin = if UserInputService.TouchEnabled then COMPACT_TOUCH_BOTTOM_MARGIN else COMPACT_MARGIN
		panel.Position = UDim2.new(1, -rightMargin, 1, -bottomMargin)
		panelScale.Scale = math.min(
			1,
			(viewport.X - rightMargin - COMPACT_MARGIN) / layoutPanelWidth,
			(viewport.Y - bottomMargin - COMPACT_MARGIN) / layoutPanelHeight
		)
	else
		panelScale.Scale =
			math.min(1, (viewport.X - 20) / layoutPanelWidth, (viewport.Y - 20) / layoutPanelHeight)
	end
end

local function setLayout(isCompact)
	compactLayout = isCompact
	if compactLayout then
		layoutPanelWidth = COMPACT_PANEL_WIDTH
		layoutPanelHeight = COMPACT_PANEL_HEIGHT
		layoutViewportWidth = COMPACT_VIEWPORT_WIDTH
		layoutViewportHeight = COMPACT_VIEWPORT_HEIGHT
		layoutSlotWidth = COMPACT_SLOT_WIDTH
		layoutSlotHeight = COMPACT_SLOT_HEIGHT
		layoutSlotGap = COMPACT_SLOT_GAP

		-- No layout de nível a camada modal deixa de ocupar a tela por
		-- completo. Size zero funciona como segunda proteção além de Visible.
		shade.Visible = false
		shade.Size = UDim2.fromOffset(0, 0)
		shade.BackgroundTransparency = 1
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Size = UDim2.fromOffset(layoutPanelWidth, layoutPanelHeight)
		title.Text = "RECOMPENSA DE NÍVEL"
		title.Position = UDim2.fromOffset(12, 5)
		title.Size = UDim2.new(1, -24, 0, 21)
		title.TextSize = 14
		sourceLabel.Position = UDim2.fromOffset(12, 25)
		sourceLabel.Size = UDim2.new(1, -24, 0, 15)
		sourceLabel.TextSize = 10

		reelShadow.Position = UDim2.new(0.5, 3, 0, 47)
		reelShadow.Size = UDim2.fromOffset(layoutViewportWidth + 6, layoutViewportHeight + 6)
		reelViewport.Position = UDim2.new(0.5, 0, 0, 44)
		reelViewport.Size = UDim2.fromOffset(layoutViewportWidth, layoutViewportHeight)
		selectorGlow.Size = UDim2.fromOffset(layoutSlotWidth + 8, layoutSlotHeight + 8)
		leftPointer.Position = UDim2.new(0, 6, 0.5, 0)
		leftPointer.Size = UDim2.fromOffset(20, 34)
		leftPointer.TextSize = 17
		rightPointer.Position = UDim2.new(1, -6, 0.5, 0)
		rightPointer.Size = UDim2.fromOffset(20, 34)
		rightPointer.TextSize = 17
		topFade.Size = UDim2.new(1, 0, 0, 34)
		bottomFade.Size = UDim2.new(1, 0, 0, 34)

		resultCard.Position = UDim2.fromOffset(12, 214)
		resultCard.Size = UDim2.new(1, -24, 0, 88)
		resultLabel.Position = UDim2.fromOffset(9, 6)
		resultLabel.Size = UDim2.new(1, -18, 0, 42)
		resultLabel.TextSize = 13
		detailLabel.Position = UDim2.fromOffset(9, 49)
		detailLabel.Size = UDim2.new(1, -18, 0, 30)
		detailLabel.TextSize = 10
	else
		layoutPanelWidth = PANEL_WIDTH
		layoutPanelHeight = PANEL_HEIGHT
		layoutViewportWidth = VIEWPORT_WIDTH
		layoutViewportHeight = VIEWPORT_HEIGHT
		layoutSlotWidth = SLOT_WIDTH
		layoutSlotHeight = SLOT_HEIGHT
		layoutSlotGap = SLOT_GAP

		shade.Visible = true
		shade.Size = UDim2.fromScale(1, 1)
		shade.BackgroundTransparency = 0.3
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromOffset(layoutPanelWidth, layoutPanelHeight)
		title.Text = "ROLETA DE RECOMPENSAS"
		title.Position = UDim2.fromOffset(20, 12)
		title.Size = UDim2.new(1, -40, 0, 31)
		title.TextSize = 22
		sourceLabel.Position = UDim2.fromOffset(20, 43)
		sourceLabel.Size = UDim2.new(1, -40, 0, 20)
		sourceLabel.TextSize = 13

		reelShadow.Position = UDim2.new(0.5, 4, 0, 78)
		reelShadow.Size = UDim2.fromOffset(layoutViewportWidth + 8, layoutViewportHeight + 8)
		reelViewport.Position = UDim2.new(0.5, 0, 0, 74)
		reelViewport.Size = UDim2.fromOffset(layoutViewportWidth, layoutViewportHeight)
		selectorGlow.Size = UDim2.fromOffset(layoutSlotWidth + 10, layoutSlotHeight + 10)
		leftPointer.Position = UDim2.new(0, 9, 0.5, 0)
		leftPointer.Size = UDim2.fromOffset(32, 52)
		leftPointer.TextSize = 28
		rightPointer.Position = UDim2.new(1, -9, 0.5, 0)
		rightPointer.Size = UDim2.fromOffset(32, 52)
		rightPointer.TextSize = 28
		topFade.Size = UDim2.new(1, 0, 0, 86)
		bottomFade.Size = UDim2.new(1, 0, 0, 86)

		resultCard.Position = UDim2.fromOffset(20, 524)
		resultCard.Size = UDim2.new(1, -40, 0, 153)
		resultLabel.Position = UDim2.fromOffset(14, 13)
		resultLabel.Size = UDim2.new(1, -28, 0, 53)
		resultLabel.TextSize = 20
		detailLabel.Position = UDim2.fromOffset(16, 63)
		detailLabel.Size = UDim2.new(1, -32, 0, 35)
		detailLabel.TextSize = 13
	end
	updateScale()
end

local function isCompactSpin(payload, result)
	if payload.UiMode == COMPACT_UI_MODE then
		return true
	end
	local sourceId = type(result) == "table" and tostring(result.SourceId or "") or ""
	return COMPACT_SOURCE_IDS[sourceId] == true
end

local viewportConnection
local function watchCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

local function clearSlots()
	for _, child in ipairs(reelContent:GetChildren()) do
		child:Destroy()
	end
end

local function fallbackEntries(result)
	local entries = table.create(catalog.WheelSlotCount or 10)
	local categories = { "Coins", "Relic", "Sword", "Companion" }
	for index = 1, catalog.WheelSlotCount or 10 do
		local category = categories[(index - 1) % #categories + 1]
		local info = catalog.GetCategoryInfo(category)
		entries[index] = {
			Category = category,
			RewardId = category,
			DisplayName = info.DisplayName,
			Icon = info.Icon,
			Color = info.Color,
			ImageId = "",
		}
	end
	local winningSlot = math.min(3, #entries)
	entries[winningSlot] = result
	return entries, winningSlot
end

local function createSlot(globalIndex, entry)
	local slotStride = layoutSlotHeight + layoutSlotGap
	local slot = Instance.new("Frame")
	slot.Name = string.format("Slot_%03d", globalIndex)
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.fromOffset(layoutViewportWidth * 0.5, (globalIndex - 1) * slotStride)
	slot.Size = UDim2.fromOffset(layoutSlotWidth, layoutSlotHeight)
	slot.BackgroundColor3 = entry.Color or Color3.fromRGB(82, 91, 111)
	slot.BackgroundTransparency = 0.05
	slot.BorderSizePixel = 0
	slot.ClipsDescendants = true
	slot.ZIndex = 4
	slot.Parent = reelContent
	addCorner(slot, 14)
	local slotStroke = addStroke(slot, GOLD, 2, 0.12)

	local imageId = entry.ImageId
	if isImageId(imageId) then
		local image = Instance.new("ImageLabel")
		image.Name = "ItemImage"
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = imageId
		image.ScaleType = Enum.ScaleType.Crop
		image.ZIndex = 5
		image.Parent = slot

		local imageShade = Instance.new("Frame")
		imageShade.Name = "ImageShade"
		imageShade.Size = UDim2.fromScale(1, 1)
		imageShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		imageShade.BackgroundTransparency = 0.82
		imageShade.BorderSizePixel = 0
		imageShade.ZIndex = 6
		imageShade.Parent = slot
	else
		local icon = Instance.new("TextLabel")
		icon.Name = "ItemIcon"
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.Text = tostring(entry.Icon or "🎁")
		icon.TextColor3 = TEXT
		icon.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		icon.TextStrokeTransparency = 0.55
		icon.Font = Enum.Font.GothamBold
		icon.TextSize = if compactLayout then 38 else 72
		icon.ZIndex = 5
		icon.Parent = slot
	end

	local nameBand = Instance.new("Frame")
	nameBand.Name = "NameBand"
	nameBand.AnchorPoint = Vector2.new(0, 1)
	nameBand.Position = UDim2.fromScale(0, 1)
	nameBand.Size = UDim2.new(1, 0, 0, if compactLayout then 25 else 43)
	nameBand.BackgroundColor3 = Color3.fromRGB(4, 7, 12)
	nameBand.BackgroundTransparency = 0.14
	nameBand.BorderSizePixel = 0
	nameBand.ZIndex = 7
	nameBand.Parent = slot

	local name = Instance.new("TextLabel")
	name.Name = "ItemName"
	name.Position = UDim2.fromOffset(if compactLayout then 8 else 12, 0)
	name.Size = UDim2.new(1, if compactLayout then -16 else -24, 1, 0)
	name.BackgroundTransparency = 1
	name.Text = tostring(entry.DisplayName or "Recompensa")
	name.TextColor3 = TEXT
	name.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	name.TextStrokeTransparency = 0.35
	name.Font = Enum.Font.GothamBlack
	name.TextSize = if compactLayout then 12 else 17
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 8
	name.Parent = nameBand

	return slot, slotStroke
end

local function centeredContentY(globalIndex)
	local slotStride = layoutSlotHeight + layoutSlotGap
	local slotCenter = (globalIndex - 1) * slotStride + layoutSlotHeight * 0.5
	return layoutViewportHeight * 0.5 - slotCenter
end

local function populateReel(entries, winningSlot, fullRotations)
	clearSlots()
	local slotCount = #entries
	local startCycle = 1
	local targetCycle = startCycle + fullRotations
	local totalCycles = targetCycle + 2
	local startIndex = startCycle * slotCount + winningSlot
	local targetIndex = targetCycle * slotCount + winningSlot
	local slotStride = layoutSlotHeight + layoutSlotGap
	local targetCard
	local targetStroke

	for cycle = 0, totalCycles do
		for index, entry in ipairs(entries) do
			local globalIndex = cycle * slotCount + index
			local slot, stroke = createSlot(globalIndex, entry)
			if globalIndex == targetIndex then
				targetCard = slot
				targetStroke = stroke
			end
		end
	end

	reelContent.Size =
		UDim2.fromOffset(layoutViewportWidth, (totalCycles + 1) * slotCount * slotStride)
	reelContent.Position = UDim2.fromOffset(0, centeredContentY(startIndex))
	return targetIndex, targetCard, targetStroke
end

local function animateSpin(payload)
	local result = payload.Result
	if type(result) ~= "table" then
		return
	end
	setLayout(isCompactSpin(payload, result))

	local entries = payload.WheelEntries
	local winningSlot = math.floor(tonumber(payload.WinningSlot) or 0)
	if type(entries) ~= "table" or #entries < 8 or winningSlot < 1 or winningSlot > #entries then
		entries, winningSlot = fallbackEntries(result)
	end

	gui.Enabled = true
	sourceLabel.Text = tostring(result.SourceName or "")
	resultLabel.Text = "SORTEANDO..."
	resultLabel.TextColor3 = TEXT
	detailLabel.Text = if compactLayout
		then "Prêmio definido pelo servidor."
		else "O prêmio já foi definido com segurança pelo servidor."
	resultStroke.Transparency = 0.48
	selectorGlow.BackgroundTransparency = 0.9
	spinAgainButton.Visible = false
	spinAgainButton.Active = true
	spinAgainButton.AutoButtonColor = true
	continueButton.Visible = false

	local duration = math.clamp(tonumber(payload.Duration) or 3.6, 2.2, 6)
	if compactLayout then
		duration = math.clamp(duration * 0.72, 1.8, 3)
	end
	local fullRotations = math.clamp(math.floor(tonumber(payload.FullRotations) or 6), 3, 9)
	local targetIndex, winnerCard, winnerStroke = populateReel(entries, winningSlot, fullRotations)
	local tween = TweenService:Create(
		reelContent,
		TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, centeredContentY(targetIndex)) }
	)
	tween:Play()
	tween.Completed:Wait()

	if winnerCard and winnerStroke then
		winnerStroke.Thickness = 4
		winnerStroke.Transparency = 0
	end
	selectorGlow.BackgroundTransparency = 0.82
	resultLabel.Text = "VOCÊ GANHOU: " .. string.upper(tostring(result.DisplayName or "RECOMPENSA"))
	resultLabel.TextColor3 = result.Color or GOLD_LIGHT
	resultStroke.Color = result.Color or GOLD
	resultStroke.Transparency = 0.08
	if result.IsDuplicate then
		detailLabel.Text = if compactLayout
			then "Item repetido convertido em moedas."
			else string.format(
				"%s já estava na coleção e foi convertido em moedas.",
				tostring(result.OriginalDisplayName or "O item")
			)
	else
		detailLabel.Text = if compactLayout
			then "Recebida e adicionada à sua conta."
			else "Recompensa recebida e adicionada à sua conta."
	end
	rewardSound:Play()

	local selectorPadding = if compactLayout then 8 else 10
	local pulseOut = TweenService:Create(
		selectorGlow,
		TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromOffset(
				layoutSlotWidth + selectorPadding + 10,
				layoutSlotHeight + selectorPadding + 10
			),
			BackgroundTransparency = 0.74,
		}
	)
	pulseOut:Play()
	pulseOut.Completed:Wait()
	TweenService:Create(
		selectorGlow,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromOffset(
				layoutSlotWidth + selectorPadding,
				layoutSlotHeight + selectorPadding
			),
			BackgroundTransparency = 0.82,
		}
	):Play()

	local spinAgain = monetizationCatalog.Get("SpinAgain")
	local spinAgainId = spinAgain and math.max(0, math.floor(tonumber(spinAgain.ProductId) or 0)) or 0
	local eligibleSource = catalog.IsSpinAgainSource(result.SourceId)
	if payload.SpinAgainAvailable == true and eligibleSource and spinAgainId > 0 then
		local priceText = ""
		local infoSuccess, info = pcall(
			MarketplaceService.GetProductInfo,
			MarketplaceService,
			spinAgainId,
			Enum.InfoType.Product
		)
		if infoSuccess and type(info) == "table" and tonumber(info.PriceInRobux) then
			priceText = string.format(" · %d ROBUX", info.PriceInRobux)
		end
		spinAgainButton.Text = "GIRAR NOVAMENTE" .. priceText
		spinAgainButton.Visible = true
	end
	if compactLayout then
		task.wait(COMPACT_RESULT_HOLD_SECONDS)
		gui.Enabled = false
		return
	end

	continueButton.Visible = true
	local choiceSerial = resultChoiceSerial
	local deadline = os.clock() + 15
	while gui.Enabled and resultChoiceSerial == choiceSerial and os.clock() < deadline do
		task.wait(0.1)
	end
	if resultChoiceSerial == choiceSerial then
		gui.Enabled = false
	end
end

local function processQueue()
	if processing then
		return
	end
	processing = true
	while #queue > 0 do
		animateSpin(table.remove(queue, 1))
	end
	processing = false
end

event.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.Action ~= "Spin" then
		return
	end
	table.insert(queue, payload)
	task.spawn(processQueue)
end)
