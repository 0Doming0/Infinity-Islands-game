-- SkyDungeon - HUD minimalista para computador, controle e celular.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local waterEvent = ReplicatedStorage:WaitForChild("WaterEvent")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))
local CURRENCY_SYMBOL = MVPConfig.Currency.Symbol

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Position = UDim2.fromOffset(12, 12)
hud.Size = UDim2.fromOffset(230, 72)
hud.BackgroundColor3 = Color3.fromRGB(12, 18, 29)
hud.BackgroundTransparency = 0.28
hud.BorderSizePixel = 0
hud.Parent = screenGui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 11)
hudCorner.Parent = hud

local hudStroke = Instance.new("UIStroke")
hudStroke.Color = Color3.fromRGB(118, 151, 184)
hudStroke.Transparency = 0.68
hudStroke.Thickness = 1
hudStroke.Parent = hud

local function createLabel(name, position, size, text, color, font, textSize, alignment)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Position = position
	item.Size = size
	item.BackgroundTransparency = 1
	item.Text = text
	item.TextColor3 = color
	item.Font = font
	item.TextSize = textSize
	item.TextXAlignment = alignment or Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = hud
	return item
end

local scoreLabel = createLabel(
	"Score",
	UDim2.fromOffset(12, 7),
	UDim2.fromOffset(112, 25),
	"⭐ 0",
	Color3.fromRGB(255, 220, 102),
	Enum.Font.GothamMedium,
	16
)

local coinLabel = createLabel(
	"Coins",
	UDim2.fromOffset(122, 7),
	UDim2.fromOffset(96, 25),
	CURRENCY_SYMBOL .. " 0",
	Color3.fromRGB(255, 196, 66),
	Enum.Font.GothamMedium,
	13,
	Enum.TextXAlignment.Right
)

local waterLabel = createLabel(
	"WaterDistance",
	UDim2.fromOffset(12, 34),
	UDim2.fromOffset(206, 22),
	"🌊  --m abaixo",
	Color3.fromRGB(139, 207, 255),
	Enum.Font.GothamMedium,
	13
)

local barBackground = Instance.new("Frame")
barBackground.Name = "WaterDanger"
barBackground.Position = UDim2.fromOffset(12, 61)
barBackground.Size = UDim2.fromOffset(206, 3)
barBackground.BackgroundColor3 = Color3.fromRGB(54, 68, 88)
barBackground.BackgroundTransparency = 0.25
barBackground.BorderSizePixel = 0
barBackground.ClipsDescendants = true
barBackground.Parent = hud

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBackground

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(72, 177, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

local PROGRESS_PANEL_WIDTH = 188
local PROGRESS_PANEL_HEIGHT = 286
local TRACK_X = 170
local TRACK_TOP = 50
local TRACK_HEIGHT = 174
local TRACK_BOTTOM = TRACK_TOP + TRACK_HEIGHT
local MARKER_SIZE = 34
local MARKER_SPACING = MARKER_SIZE + 4
local MARKER_LANE_X = { 132, 94, 56, 18 }
local RUN_LEVEL_CONFIG = MVPConfig.Progression.RunLevel

local progressPanel = Instance.new("Frame")
progressPanel.Name = "RunLevelRace"
progressPanel.AnchorPoint = Vector2.new(1, 0.5)
progressPanel.Position = UDim2.new(1, 0, 0.52, 0)
progressPanel.Size = UDim2.fromOffset(PROGRESS_PANEL_WIDTH, PROGRESS_PANEL_HEIGHT)
progressPanel.BackgroundColor3 = Color3.fromRGB(12, 18, 29)
progressPanel.BackgroundTransparency = 1
progressPanel.BorderSizePixel = 0
progressPanel.Parent = screenGui
Instance.new("UICorner", progressPanel).CornerRadius = UDim.new(0, 13)

local progressStroke = Instance.new("UIStroke")
progressStroke.Color = Color3.fromRGB(148, 113, 218)
progressStroke.Transparency = 0.62
progressStroke.Thickness = 1
progressStroke.Enabled = false
progressStroke.Parent = progressPanel

local progressScale = Instance.new("UIScale")
progressScale.Parent = progressPanel

local progressTitle = Instance.new("TextLabel")
progressTitle.Name = "Level"
progressTitle.Position = UDim2.fromOffset(8, 7)
progressTitle.Size = UDim2.fromOffset(PROGRESS_PANEL_WIDTH - 16, 22)
progressTitle.BackgroundTransparency = 1
progressTitle.Text = "NÍVEL 1"
progressTitle.TextColor3 = Color3.fromRGB(231, 214, 255)
progressTitle.Font = Enum.Font.GothamBold
progressTitle.TextSize = 15
progressTitle.TextXAlignment = Enum.TextXAlignment.Right
progressTitle.Parent = progressPanel

local progressRange = Instance.new("TextLabel")
progressRange.Name = "Range"
progressRange.Position = UDim2.fromOffset(8, 28)
progressRange.Size = UDim2.fromOffset(PROGRESS_PANEL_WIDTH - 16, 18)
progressRange.BackgroundTransparency = 1
progressRange.Text = "0m — 150m"
progressRange.TextColor3 = Color3.fromRGB(178, 185, 207)
progressRange.Font = Enum.Font.GothamMedium
progressRange.TextSize = 11
progressRange.TextXAlignment = Enum.TextXAlignment.Right
progressRange.Parent = progressPanel

local verticalTrack = Instance.new("Frame")
verticalTrack.Name = "Track"
verticalTrack.Position = UDim2.fromOffset(TRACK_X, TRACK_TOP)
verticalTrack.Size = UDim2.fromOffset(7, TRACK_HEIGHT)
verticalTrack.BackgroundColor3 = Color3.fromRGB(61, 54, 79)
verticalTrack.BackgroundTransparency = 0.16
verticalTrack.BorderSizePixel = 0
verticalTrack.ClipsDescendants = true
verticalTrack.Parent = progressPanel
Instance.new("UICorner", verticalTrack).CornerRadius = UDim.new(1, 0)

local verticalFill = Instance.new("Frame")
verticalFill.Name = "LocalProgress"
verticalFill.AnchorPoint = Vector2.new(0, 1)
verticalFill.Position = UDim2.fromScale(0, 1)
verticalFill.Size = UDim2.fromScale(1, 0)
verticalFill.BackgroundColor3 = Color3.fromRGB(173, 96, 255)
verticalFill.BorderSizePixel = 0
verticalFill.Parent = verticalTrack
Instance.new("UICorner", verticalFill).CornerRadius = UDim.new(1, 0)

for tickIndex = 0, 6 do
	local tickProgress = tickIndex / 6
	local tick = Instance.new("Frame")
	tick.Name = "Tick" .. tickIndex
	tick.AnchorPoint = Vector2.new(1, 0.5)
	tick.Position = UDim2.fromOffset(TRACK_X, TRACK_BOTTOM - TRACK_HEIGHT * tickProgress)
	tick.Size = UDim2.fromOffset(tickIndex % 2 == 0 and 13 or 8, 1)
	tick.BackgroundColor3 = Color3.fromRGB(177, 164, 205)
	tick.BackgroundTransparency = tickIndex % 2 == 0 and 0.28 or 0.55
	tick.BorderSizePixel = 0
	tick.Parent = progressPanel
end

local topDistanceLabel = Instance.new("TextLabel")
topDistanceLabel.Name = "TopDistance"
topDistanceLabel.AnchorPoint = Vector2.new(1, 0.5)
topDistanceLabel.Position = UDim2.fromOffset(TRACK_X - 5, TRACK_TOP)
topDistanceLabel.Size = UDim2.fromOffset(48, 16)
topDistanceLabel.BackgroundTransparency = 1
topDistanceLabel.Text = "150m"
topDistanceLabel.TextColor3 = Color3.fromRGB(218, 207, 235)
topDistanceLabel.Font = Enum.Font.GothamBold
topDistanceLabel.TextSize = 10
topDistanceLabel.TextXAlignment = Enum.TextXAlignment.Right
topDistanceLabel.Parent = progressPanel

local bottomDistanceLabel = topDistanceLabel:Clone()
bottomDistanceLabel.Name = "BottomDistance"
bottomDistanceLabel.Position = UDim2.fromOffset(TRACK_X - 5, TRACK_BOTTOM)
bottomDistanceLabel.Text = "0m"
bottomDistanceLabel.Parent = progressPanel

local remainingLabel = Instance.new("TextLabel")
remainingLabel.Name = "Remaining"
remainingLabel.Position = UDim2.fromOffset(8, 256)
remainingLabel.Size = UDim2.fromOffset(PROGRESS_PANEL_WIDTH - 16, 24)
remainingLabel.BackgroundTransparency = 1
remainingLabel.Text = "FALTAM 150m"
remainingLabel.TextColor3 = Color3.fromRGB(213, 190, 255)
remainingLabel.Font = Enum.Font.GothamBold
remainingLabel.TextSize = 11
remainingLabel.TextXAlignment = Enum.TextXAlignment.Right
remainingLabel.Parent = progressPanel

local relicHud = Instance.new("Frame")
relicHud.Name = "EquippedRelic"
relicHud.AnchorPoint = Vector2.new(0, 1)
relicHud.Position = UDim2.new(0, 12, 1, -72)
relicHud.Size = UDim2.fromOffset(220, 58)
relicHud.BackgroundTransparency = 1
relicHud.BorderSizePixel = 0
relicHud.Parent = screenGui

local relicImageSlot = Instance.new("Frame")
relicImageSlot.Name = "ImageSlot"
relicImageSlot.Position = UDim2.fromOffset(4, 4)
relicImageSlot.Size = UDim2.fromOffset(50, 50)
relicImageSlot.BackgroundColor3 = Color3.fromRGB(30, 27, 40)
relicImageSlot.BackgroundTransparency = 0.16
relicImageSlot.BorderSizePixel = 0
relicImageSlot.Parent = relicHud
Instance.new("UICorner", relicImageSlot).CornerRadius = UDim.new(0, 11)

local relicImageStroke = Instance.new("UIStroke")
relicImageStroke.Color = Color3.fromRGB(142, 92, 235)
relicImageStroke.Transparency = 0.18
relicImageStroke.Thickness = 2
relicImageStroke.Parent = relicImageSlot

local relicImage = Instance.new("ImageLabel")
relicImage.Name = "Image"
relicImage.Position = UDim2.fromOffset(3, 3)
relicImage.Size = UDim2.new(1, -6, 1, -6)
relicImage.BackgroundTransparency = 1
relicImage.Image = ""
relicImage.ScaleType = Enum.ScaleType.Fit
relicImage.Parent = relicImageSlot

local relicIcon = Instance.new("TextLabel")
relicIcon.Name = "Placeholder"
relicIcon.Size = UDim2.fromScale(1, 1)
relicIcon.BackgroundTransparency = 1
relicIcon.Text = "◇"
relicIcon.TextColor3 = Color3.fromRGB(174, 157, 198)
relicIcon.Font = Enum.Font.GothamBold
relicIcon.TextSize = 27
relicIcon.Parent = relicImageSlot

local relicStatus = Instance.new("TextLabel")
relicStatus.Name = "Status"
relicStatus.Position = UDim2.fromOffset(63, 6)
relicStatus.Size = UDim2.fromOffset(145, 16)
relicStatus.BackgroundTransparency = 1
relicStatus.Text = "SEM RELÍQUIA"
relicStatus.TextColor3 = Color3.fromRGB(178, 185, 207)
relicStatus.Font = Enum.Font.GothamBold
relicStatus.TextSize = 10
relicStatus.TextXAlignment = Enum.TextXAlignment.Left
relicStatus.Parent = relicHud

local relicName = Instance.new("TextLabel")
relicName.Name = "Name"
relicName.Position = UDim2.fromOffset(63, 23)
relicName.Size = UDim2.fromOffset(153, 29)
relicName.BackgroundTransparency = 1
relicName.Text = "Visite o vendedor"
relicName.TextColor3 = Color3.fromRGB(218, 207, 235)
relicName.Font = Enum.Font.GothamMedium
relicName.TextSize = 12
relicName.TextWrapped = true
relicName.TextXAlignment = Enum.TextXAlignment.Left
relicName.TextYAlignment = Enum.TextYAlignment.Top
relicName.Parent = relicHud

local relicPulseSerial = 0
local function updateEquippedRelic()
	local relicId = player:GetAttribute("EquippedRelic")
	local definition = type(relicId) == "string" and RelicCatalog.Get(relicId) or nil
	if not definition then
		relicStatus.Text = "SEM RELÍQUIA"
		relicStatus.TextColor3 = Color3.fromRGB(178, 185, 207)
		relicName.Text = "Visite o vendedor"
		relicImage.Image = ""
		relicImage.Visible = false
		relicIcon.Text = "◇"
		relicIcon.TextColor3 = Color3.fromRGB(174, 157, 198)
		relicIcon.Visible = true
		relicImageStroke.Color = Color3.fromRGB(142, 92, 235)
		return
	end
	relicStatus.Text = "EQUIPADA"
	relicStatus.TextColor3 = Color3.fromRGB(105, 255, 145)
	relicName.Text = definition.DisplayName
	relicImage.Image = definition.ImageId or ""
	relicImage.Visible = relicImage.Image ~= ""
	relicIcon.Text = definition.Icon or "✨"
	relicIcon.TextColor3 = definition.Color
	relicIcon.Visible = not relicImage.Visible
	relicImageStroke.Color = definition.Color
end

player:GetAttributeChangedSignal("EquippedRelic"):Connect(updateEquippedRelic)
player:GetAttributeChangedSignal("LastRelicProcSerial"):Connect(function()
	relicPulseSerial += 1
	local serial = relicPulseSerial
	TweenService:Create(
		relicImageSlot,
		TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(57, 57) }
	):Play()
	task.delay(0.14, function()
		if serial == relicPulseSerial and relicImageSlot.Parent then
			TweenService:Create(
				relicImageSlot,
				TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(50, 50) }
			):Play()
		end
	end)
end)
updateEquippedRelic()

local warning = Instance.new("TextLabel")
warning.Name = "Warning"
warning.Position = UDim2.fromOffset(12, 79)
warning.Size = UDim2.fromOffset(230, 34)
warning.BackgroundColor3 = Color3.fromRGB(138, 44, 42)
warning.BackgroundTransparency = 0.18
warning.BorderSizePixel = 0
warning.Text = ""
warning.TextColor3 = Color3.fromRGB(255, 243, 238)
warning.Font = Enum.Font.GothamBold
warning.TextSize = 13
warning.TextWrapped = true
warning.Visible = false
warning.Parent = screenGui

local warningCorner = Instance.new("UICorner")
warningCorner.CornerRadius = UDim.new(0, 9)
warningCorner.Parent = warning

local levelUpNotice = Instance.new("TextLabel")
levelUpNotice.Name = "LevelUpNotice"
levelUpNotice.AnchorPoint = Vector2.new(0.5, 0)
levelUpNotice.Position = UDim2.new(0.5, 0, 0, 76)
levelUpNotice.Size = UDim2.fromOffset(330, 52)
levelUpNotice.BackgroundColor3 = Color3.fromRGB(55, 33, 86)
levelUpNotice.BackgroundTransparency = 0.12
levelUpNotice.BorderSizePixel = 0
levelUpNotice.TextColor3 = Color3.fromRGB(245, 224, 255)
levelUpNotice.Font = Enum.Font.GothamBold
levelUpNotice.TextSize = 15
levelUpNotice.TextWrapped = true
levelUpNotice.Visible = false
levelUpNotice.Parent = screenGui
Instance.new("UICorner", levelUpNotice).CornerRadius = UDim.new(0, 11)

local resultCard = Instance.new("Frame")
resultCard.Name = "ResultCard"
resultCard.Position = UDim2.fromOffset(12, 120)
resultCard.Size = UDim2.fromOffset(230, 58)
resultCard.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
resultCard.BackgroundTransparency = 0.12
resultCard.BorderSizePixel = 0
resultCard.Visible = false
resultCard.Parent = screenGui

local resultCorner = Instance.new("UICorner")
resultCorner.CornerRadius = UDim.new(0, 10)
resultCorner.Parent = resultCard

local resultStroke = Instance.new("UIStroke")
resultStroke.Color = Color3.fromRGB(255, 104, 104)
resultStroke.Transparency = 0.38
resultStroke.Parent = resultCard

local resultText = Instance.new("TextLabel")
resultText.Name = "Text"
resultText.Position = UDim2.fromOffset(10, 5)
resultText.Size = UDim2.new(1, -20, 1, -10)
resultText.BackgroundTransparency = 1
resultText.Text = ""
resultText.TextColor3 = Color3.fromRGB(255, 225, 225)
resultText.Font = Enum.Font.GothamBold
resultText.TextSize = 14
resultText.TextWrapped = true
resultText.TextXAlignment = Enum.TextXAlignment.Left
resultText.TextYAlignment = Enum.TextYAlignment.Center
resultText.Parent = resultCard

local currentBarTween
local currentLevelTween
local wasAlive = true
local progressMarkers = {}
local progressUpdateQueued = false

local function updateProgressScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if viewport.X < 700 or viewport.Y < 560 then
		progressScale.Scale = 0.78
	elseif viewport.Y < 700 then
		progressScale.Scale = 0.9
	else
		progressScale.Scale = 1
	end
end

local function getRunLevel(targetPlayer)
	return math.max(1, tonumber(targetPlayer:GetAttribute("RunLevel")) or 1)
end

local function getRunDistance(targetPlayer)
	return math.max(0, tonumber(targetPlayer:GetAttribute("RunDistance")) or 0)
end

local updateProgressBoard

local function requestProgressUpdate()
	if progressUpdateQueued then
		return
	end
	progressUpdateQueued = true
	task.delay(0.08, function()
		progressUpdateQueued = false
		if updateProgressBoard then
			updateProgressBoard()
		end
	end)
end

local function createProgressMarker(targetPlayer)
	if progressMarkers[targetPlayer] then
		return
	end

	local connector = Instance.new("Frame")
	connector.Name = "Connector_" .. targetPlayer.UserId
	connector.AnchorPoint = Vector2.new(0, 0.5)
	connector.Size = UDim2.fromOffset(1, 1)
	connector.BackgroundColor3 = Color3.fromRGB(172, 146, 222)
	connector.BackgroundTransparency = 0.48
	connector.BorderSizePixel = 0
	connector.Visible = false
	connector.ZIndex = 2
	connector.Parent = progressPanel

	local marker = Instance.new("Frame")
	marker.Name = "Player_" .. targetPlayer.UserId
	marker.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
	marker.BackgroundColor3 = targetPlayer == player and Color3.fromRGB(255, 202, 72) or Color3.fromRGB(139, 94, 210)
	marker.BorderSizePixel = 0
	marker.Visible = false
	marker.ZIndex = 4
	marker.Parent = progressPanel
	Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)

	local markerStroke = Instance.new("UIStroke")
	markerStroke.Color = targetPlayer == player and Color3.fromRGB(255, 232, 153) or Color3.fromRGB(212, 191, 244)
	markerStroke.Thickness = targetPlayer == player and 3 or 2
	markerStroke.Transparency = targetPlayer == player and 0 or 0.22
	markerStroke.Parent = marker

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.Position = UDim2.fromOffset(2, 2)
	portrait.Size = UDim2.new(1, -4, 1, -4)
	portrait.BackgroundTransparency = 1
	portrait.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.ZIndex = 5
	portrait.Parent = marker
	Instance.new("UICorner", portrait).CornerRadius = UDim.new(1, 0)

	if targetPlayer == player then
		local localBadge = Instance.new("TextLabel")
		localBadge.Name = "LocalBadge"
		localBadge.AnchorPoint = Vector2.new(0.5, 0)
		localBadge.Position = UDim2.new(0.5, 0, 1, 1)
		localBadge.Size = UDim2.fromOffset(39, 13)
		localBadge.BackgroundColor3 = Color3.fromRGB(78, 49, 17)
		localBadge.BackgroundTransparency = 0.08
		localBadge.BorderSizePixel = 0
		localBadge.Text = "VOCÊ"
		localBadge.TextColor3 = Color3.fromRGB(255, 235, 169)
		localBadge.Font = Enum.Font.GothamBold
		localBadge.TextSize = 8
		localBadge.ZIndex = 6
		localBadge.Parent = marker
		Instance.new("UICorner", localBadge).CornerRadius = UDim.new(1, 0)
	end

	local connections = {
		targetPlayer:GetAttributeChangedSignal("RunLevel"):Connect(requestProgressUpdate),
		targetPlayer:GetAttributeChangedSignal("RunDistance"):Connect(requestProgressUpdate),
	}
	progressMarkers[targetPlayer] = {
		Connector = connector,
		Marker = marker,
		Connections = connections,
	}

	task.spawn(function()
		local success, image = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			targetPlayer.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
		if success and portrait.Parent then
			portrait.Image = image
		end
	end)

	requestProgressUpdate()
end

local function removeProgressMarker(targetPlayer)
	local record = progressMarkers[targetPlayer]
	if not record then
		return
	end
	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	record.Marker:Destroy()
	record.Connector:Destroy()
	progressMarkers[targetPlayer] = nil
	requestProgressUpdate()
end

updateProgressBoard = function()
	local localLevel = getRunLevel(player)
	local localDistance = getRunDistance(player)
	local rangeStart, rangeEnd = RUN_LEVEL_CONFIG.GetLevelBounds(localLevel)
	local rangeLength = math.max(1, rangeEnd - rangeStart)
	local localProgress = math.clamp((localDistance - rangeStart) / rangeLength, 0, 1)
	local remaining = math.max(0, rangeEnd - localDistance)

	progressTitle.Text = string.format("NÍVEL %d", localLevel)
	progressRange.Text = string.format("%dm — %dm", math.floor(rangeStart + 0.5), math.floor(rangeEnd + 0.5))
	topDistanceLabel.Text = string.format("%dm", math.floor(rangeEnd + 0.5))
	bottomDistanceLabel.Text = string.format("%dm", math.floor(rangeStart + 0.5))
	remainingLabel.Text = string.format("FALTAM %dm", math.ceil(remaining))

	if currentLevelTween then
		currentLevelTween:Cancel()
	end
	currentLevelTween = TweenService:Create(
		verticalFill,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, localProgress) }
	)
	currentLevelTween:Play()

	local visiblePlayers = {}
	for targetPlayer, record in pairs(progressMarkers) do
		local visible = targetPlayer.Parent == Players and getRunLevel(targetPlayer) == localLevel
		record.Marker.Visible = visible
		record.Connector.Visible = visible
		if visible then
			local targetDistance = getRunDistance(targetPlayer)
			local targetProgress = math.clamp((targetDistance - rangeStart) / rangeLength, 0, 1)
			table.insert(visiblePlayers, {
				Player = targetPlayer,
				DesiredY = TRACK_BOTTOM - TRACK_HEIGHT * targetProgress,
			})
		end
	end

	table.sort(visiblePlayers, function(left, right)
		if left.DesiredY == right.DesiredY then
			if left.Player == player then
				return true
			elseif right.Player == player then
				return false
			end
			return left.Player.UserId < right.Player.UserId
		end
		return left.DesiredY < right.DesiredY
	end)

	local laneEntries = {}
	for laneIndex = 1, #MARKER_LANE_X do
		laneEntries[laneIndex] = {}
	end

	for _, entry in ipairs(visiblePlayers) do
		local selectedLane
		for laneIndex, entries in ipairs(laneEntries) do
			local overlaps = false
			for _, placed in ipairs(entries) do
				if math.abs(placed.DesiredY - entry.DesiredY) < MARKER_SPACING then
					overlaps = true
					break
				end
			end
			if not overlaps then
				selectedLane = laneIndex
				break
			end
		end
		if not selectedLane then
			selectedLane = 1
			for laneIndex = 2, #laneEntries do
				if #laneEntries[laneIndex] < #laneEntries[selectedLane] then
					selectedLane = laneIndex
				end
			end
		end
		entry.Lane = selectedLane
		table.insert(laneEntries[selectedLane], entry)
	end

	for laneIndex, entries in ipairs(laneEntries) do
		table.sort(entries, function(left, right)
			return left.DesiredY < right.DesiredY
		end)
		local previousY
		for _, entry in ipairs(entries) do
			entry.DisplayY = previousY and math.max(entry.DesiredY, previousY + MARKER_SPACING) or entry.DesiredY
			previousY = entry.DisplayY
		end
		local overflow = previousY and math.max(0, previousY - TRACK_BOTTOM) or 0
		if overflow > 0 then
			for _, entry in ipairs(entries) do
				entry.DisplayY -= overflow
			end
		end
		local underflow = entries[1] and math.max(0, TRACK_TOP - entries[1].DisplayY) or 0
		if underflow > 0 then
			for _, entry in ipairs(entries) do
				entry.DisplayY += underflow
			end
		end

		for _, entry in ipairs(entries) do
			local record = progressMarkers[entry.Player]
			local markerX = MARKER_LANE_X[laneIndex]
			local markerY = entry.DisplayY - MARKER_SIZE / 2
			local connectorStartX = markerX + MARKER_SIZE
			local connectorWidth = math.max(1, TRACK_X - connectorStartX)
			TweenService:Create(
				record.Marker,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(markerX, markerY) }
			):Play()
			record.Connector.Position = UDim2.fromOffset(connectorStartX, entry.DisplayY)
			record.Connector.Size = UDim2.fromOffset(connectorWidth, 1)
		end
	end
end

for _, targetPlayer in ipairs(Players:GetPlayers()) do
	createProgressMarker(targetPlayer)
end
Players.PlayerAdded:Connect(createProgressMarker)
Players.PlayerRemoving:Connect(removeProgressMarker)

local cameraConnection
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateProgressScale)
	end
	updateProgressScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

local function updateWaterDisplay(gap)
	local roundedGap = math.floor(gap)
	if gap <= 0 then
		waterLabel.Text = "🌊 SUBA!"
	elseif gap < 18 then
		waterLabel.Text = string.format("🌊 %dm", roundedGap)
	else
		waterLabel.Text = string.format("🌊 %dm abaixo", roundedGap)
	end

	local danger = 1 - math.clamp(gap / 80, 0, 1)
	barFill.BackgroundColor3 =
		Color3.fromRGB(72 + math.floor(183 * danger), 177 - math.floor(105 * danger), 255 - math.floor(165 * danger))

	if currentBarTween then
		currentBarTween:Cancel()
	end
	currentBarTween = TweenService:Create(
		barFill,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(danger, 0, 1, 0) }
	)
	currentBarTween:Play()
end

local levelNoticeSerial = 0
player:GetAttributeChangedSignal("RunLevelUpSerial"):Connect(function()
	levelNoticeSerial += 1
	local serial = levelNoticeSerial
	local level = tonumber(player:GetAttribute("RunLevel")) or 1
	local upgrade = tostring(player:GetAttribute("RunLastUpgrade") or "")
	levelUpNotice.Text =
		string.format("NÍVEL %d\nAprimoramento: %s", level, upgrade ~= "" and upgrade or "novo bônus")
	levelUpNotice.TextTransparency = 0
	levelUpNotice.BackgroundTransparency = 0.12
	levelUpNotice.Visible = true
	task.delay(3, function()
		if serial ~= levelNoticeSerial then
			return
		end
		local tween = TweenService:Create(levelUpNotice, TweenInfo.new(0.35), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if serial == levelNoticeSerial then
				levelUpNotice.Visible = false
			end
		end)
	end)
end)

waterEvent.OnClientEvent:Connect(function(data)
	local waterY = tonumber(data.waterY) or 0
	local height = tonumber(data.height) or 0
	local gap = height - waterY
	local alive = data.alive ~= false

	scoreLabel.Text = "⭐ " .. tostring(data.runScore or data.score or 0)
	coinLabel.Text = CURRENCY_SYMBOL .. " " .. tostring(data.coins or 0)
	updateWaterDisplay(gap)

	if alive and gap <= 0 then
		warning.Visible = true
		warning.Text = "🌊 VOCE ESTA NA AGUA! SUBA!"
	elseif alive and gap < 18 then
		warning.Visible = true
		warning.Text = "🌊 A AGUA ESTA CHEGANDO"
	else
		warning.Visible = false
	end

	if not alive and wasAlive then
		wasAlive = false
		warning.Visible = false
		local cause = data.inWater and "VOCE SE AFOGOU" or "VOCE MORREU"
		resultText.Text = string.format(
			"%s\n⭐ %d perdidos  •  %s %d perdidas",
			cause,
			tonumber(data.lastDeathRunScore) or 0,
			CURRENCY_SYMBOL,
			tonumber(data.lastDeathCoinsLost) or 0
		)
		resultCard.BackgroundTransparency = 1
		resultCard.Visible = true
		TweenService:Create(resultCard, TweenInfo.new(0.2), { BackgroundTransparency = 0.12 }):Play()
	elseif alive and not wasAlive then
		wasAlive = true
		resultCard.Visible = false
	end
end)
