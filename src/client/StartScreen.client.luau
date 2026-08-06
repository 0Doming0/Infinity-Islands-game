-- Tela inicial do Sky Dungeon.
-- O personagem real continua sendo criado apenas depois do clique em INICIAR.
-- A vitrine usa um avatar local com enquadramento dinâmico e fallback 2D.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "StartScreen"
local CLIENT_GUARD_ATTRIBUTE = "StartScreenClientActive"
local DESKTOP_SIZE = Vector2.new(1080, 620)
local PORTRAIT_SIZE = Vector2.new(720, 1120)

local COLORS = {
	Background = Color3.fromRGB(5, 10, 18),
	BackgroundDeep = Color3.fromRGB(8, 7, 22),
	Surface = Color3.fromRGB(13, 22, 31),
	SurfaceRaised = Color3.fromRGB(20, 32, 42),
	SurfaceSoft = Color3.fromRGB(23, 39, 48),
	Border = Color3.fromRGB(83, 118, 126),
	Primary = Color3.fromRGB(74, 226, 157),
	PrimaryDark = Color3.fromRGB(28, 144, 91),
	PrimarySoft = Color3.fromRGB(143, 244, 195),
	Gold = Color3.fromRGB(255, 205, 92),
	Text = Color3.fromRGB(244, 249, 250),
	TextMuted = Color3.fromRGB(154, 174, 183),
	TextDim = Color3.fromRGB(103, 126, 137),
	Error = Color3.fromRGB(255, 132, 119),
}

local function destroyExistingStartScreens()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name == GUI_NAME then
			child:Destroy()
		end
	end
end

local function usesDungeonAutoStart()
	return workspace:GetAttribute("DungeonRuntimeManaged") == true
		or player:GetAttribute("DungeonRuntimeAutoStart") == true
end

if usesDungeonAutoStart() then
	destroyExistingStartScreens()
	return
end

if
	player:GetAttribute("InitialGameStarted") == true
	and player:GetAttribute("PlayerLifecycleState") == "Playing"
then
	destroyExistingStartScreens()
	return
end

-- Evita duas telas empilhadas caso um arquivo renomeado seja instalado ao lado
-- do script original.
if player:GetAttribute(CLIENT_GUARD_ATTRIBUTE) == true then
	return
end
player:SetAttribute(CLIENT_GUARD_ATTRIBUTE, true)
destroyExistingStartScreens()

local request = ReplicatedStorage:FindFirstChild("StartGameRequest")
local connections = {}
local guiAlive = true

local function track(connection)
	table.insert(connections, connection)
	return connection
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 5000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local duplicateConnection = track(playerGui.ChildAdded:Connect(function(child)
	if child ~= gui and child:IsA("ScreenGui") and child.Name == GUI_NAME then
		child:Destroy()
	end
end))

local function releaseResources()
	if not guiAlive then
		return
	end
	guiAlive = false
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(connections)
	if duplicateConnection.Connected then
		duplicateConnection:Disconnect()
	end
	if player:GetAttribute(CLIENT_GUARD_ATTRIBUTE) == true then
		player:SetAttribute(CLIENT_GUARD_ATTRIBUTE, nil)
	end
end

track(gui.Destroying:Connect(releaseResources))

local function closeForDungeonRuntime()
	if usesDungeonAutoStart() and gui.Parent then
		gui:Destroy()
	end
end

track(workspace:GetAttributeChangedSignal("DungeonRuntimeManaged"):Connect(closeForDungeonRuntime))
track(player:GetAttributeChangedSignal("DungeonRuntimeAutoStart"):Connect(closeForDungeonRuntime))
closeForDungeonRuntime()

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

local function addTextConstraint(parent, minSize, maxSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = parent
	return constraint
end

local function makeText(parent, settings)
	local item = Instance.new("TextLabel")
	item.Name = settings.Name or "Text"
	item.BackgroundTransparency = 1
	item.Position = settings.Position or UDim2.new()
	item.Size = settings.Size or UDim2.fromScale(1, 1)
	item.Text = settings.Text or ""
	item.TextColor3 = settings.Color or COLORS.Text
	item.TextTransparency = settings.Transparency or 0
	item.Font = settings.Font or Enum.Font.Gotham
	item.TextSize = settings.TextSize or 16
	item.TextScaled = settings.TextScaled or false
	item.TextWrapped = settings.Wrapped or false
	item.TextXAlignment = settings.XAlignment or Enum.TextXAlignment.Left
	item.TextYAlignment = settings.YAlignment or Enum.TextYAlignment.Center
	item.ZIndex = settings.ZIndex or 1
	item.Parent = parent
	if item.TextScaled then
		addTextConstraint(item, settings.MinTextSize or 10, settings.MaxTextSize or settings.TextSize or 16)
	end
	return item
end

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLORS.Background
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local backdropGradient = Instance.new("UIGradient")
backdropGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 28, 38)),
	ColorSequenceKeypoint.new(0.48, COLORS.Background),
	ColorSequenceKeypoint.new(1, COLORS.BackgroundDeep),
})
backdropGradient.Rotation = 24
backdropGradient.Parent = backdrop

-- Pontos discretos ajudam a comunicar altura sem depender de uma imagem externa.
for index = 1, 26 do
	local star = Instance.new("Frame")
	star.Name = "SkyPoint"
	local size = index % 5 == 0 and 3 or 2
	star.Size = UDim2.fromOffset(size, size)
	star.Position = UDim2.fromScale(
		((index * 37) % 101) / 100,
		((index * 61) % 97) / 100
	)
	star.BackgroundColor3 = index % 4 == 0 and COLORS.PrimarySoft or Color3.fromRGB(210, 231, 238)
	star.BackgroundTransparency = 0.58 + ((index % 4) * 0.08)
	star.BorderSizePixel = 0
	star.Parent = backdrop
	addCorner(star, 10)
end

local topGlow = Instance.new("Frame")
topGlow.Name = "TopGlow"
topGlow.AnchorPoint = Vector2.new(0.5, 0.5)
topGlow.Position = UDim2.fromScale(0.2, 0.08)
topGlow.Size = UDim2.fromScale(0.55, 0.42)
topGlow.BackgroundColor3 = Color3.fromRGB(24, 119, 105)
topGlow.BackgroundTransparency = 0.78
topGlow.BorderSizePixel = 0
topGlow.Parent = backdrop
addCorner(topGlow, 999)

local bottomGlow = Instance.new("Frame")
bottomGlow.Name = "BottomGlow"
bottomGlow.AnchorPoint = Vector2.new(0.5, 0.5)
bottomGlow.Position = UDim2.fromScale(0.88, 0.94)
bottomGlow.Size = UDim2.fromScale(0.48, 0.45)
bottomGlow.BackgroundColor3 = Color3.fromRGB(73, 36, 121)
bottomGlow.BackgroundTransparency = 0.82
bottomGlow.BorderSizePixel = 0
bottomGlow.Parent = backdrop
addCorner(bottomGlow, 999)

local panel = Instance.new("Frame")
panel.Name = "Main"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(DESKTOP_SIZE.X, DESKTOP_SIZE.Y)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.Parent = backdrop

local panelScale = Instance.new("UIScale")
panelScale.Name = "ResponsiveScale"
panelScale.Parent = panel

local previewCard = Instance.new("Frame")
previewCard.Name = "AdventurePreview"
previewCard.Position = UDim2.fromOffset(0, 0)
previewCard.Size = UDim2.fromOffset(620, 620)
previewCard.BackgroundColor3 = Color3.fromRGB(10, 30, 38)
previewCard.BorderSizePixel = 0
previewCard.ClipsDescendants = true
previewCard.Parent = panel
addCorner(previewCard, 26)
addStroke(previewCard, Color3.fromRGB(76, 141, 134), 0.48, 1.5)

local previewGradient = Instance.new("UIGradient")
previewGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 67, 67)),
	ColorSequenceKeypoint.new(0.56, Color3.fromRGB(10, 34, 44)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 19, 34)),
})
previewGradient.Rotation = 112
previewGradient.Parent = previewCard

local horizonGlow = Instance.new("Frame")
horizonGlow.Name = "HorizonGlow"
horizonGlow.AnchorPoint = Vector2.new(0.5, 0.5)
horizonGlow.Position = UDim2.fromScale(0.5, 0.7)
horizonGlow.Size = UDim2.fromScale(0.85, 0.5)
horizonGlow.BackgroundColor3 = Color3.fromRGB(56, 195, 145)
horizonGlow.BackgroundTransparency = 0.87
horizonGlow.BorderSizePixel = 0
horizonGlow.ZIndex = 1
horizonGlow.Parent = previewCard
addCorner(horizonGlow, 999)

local eyebrow = makeText(previewCard, {
	Name = "Eyebrow",
	Position = UDim2.fromOffset(36, 28),
	Size = UDim2.new(1, -72, 0, 22),
	Text = "AVENTURA NAS ALTURAS",
	Color = COLORS.PrimarySoft,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	ZIndex = 8,
})

local title = makeText(previewCard, {
	Name = "Title",
	Position = UDim2.fromOffset(34, 48),
	Size = UDim2.new(1, -68, 0, 58),
	Text = "SKY DUNGEON",
	Color = COLORS.Text,
	Font = Enum.Font.GothamBlack,
	TextSize = 42,
	TextScaled = true,
	MinTextSize = 24,
	MaxTextSize = 42,
	ZIndex = 8,
})

local subtitle = makeText(previewCard, {
	Name = "Subtitle",
	Position = UDim2.fromOffset(36, 101),
	Size = UDim2.new(1, -72, 0, 42),
	Text = "Suba. Enfrente as ilhas. Não deixe a água alcançar você.",
	Color = COLORS.TextMuted,
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	Wrapped = true,
	ZIndex = 8,
})

local viewport = Instance.new("ViewportFrame")
viewport.Name = "CharacterViewport"
viewport.Position = UDim2.fromOffset(0, 126)
viewport.Size = UDim2.new(1, 0, 1, -176)
viewport.BackgroundTransparency = 1
viewport.BorderSizePixel = 0
viewport.Ambient = Color3.fromRGB(154, 177, 182)
viewport.LightColor = Color3.fromRGB(255, 244, 216)
viewport.LightDirection = Vector3.new(-1, -0.65, -1)
viewport.ZIndex = 3
viewport.Parent = previewCard

local worldModel = Instance.new("WorldModel")
worldModel.Name = "PreviewWorld"
worldModel.Parent = viewport

local previewCamera = Instance.new("Camera")
previewCamera.Name = "PreviewCamera"
previewCamera.FieldOfView = 32
previewCamera.Parent = viewport
viewport.CurrentCamera = previewCamera

local avatarFallback = Instance.new("ImageLabel")
avatarFallback.Name = "AvatarFallback"
avatarFallback.AnchorPoint = Vector2.new(0.5, 0.5)
avatarFallback.Position = UDim2.fromScale(0.5, 0.59)
avatarFallback.Size = UDim2.fromScale(0.68, 0.68)
avatarFallback.BackgroundTransparency = 1
avatarFallback.ImageTransparency = 1
avatarFallback.ScaleType = Enum.ScaleType.Fit
avatarFallback.ZIndex = 4
avatarFallback.Parent = previewCard

local avatarLoading = makeText(previewCard, {
	Name = "AvatarLoading",
	Position = UDim2.new(0.5, -130, 0.58, -18),
	Size = UDim2.fromOffset(260, 36),
	Text = "PREPARANDO SEU AVENTUREIRO...",
	Color = COLORS.TextMuted,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	XAlignment = Enum.TextXAlignment.Center,
	ZIndex = 5,
})

local adventurePill = Instance.new("Frame")
adventurePill.Name = "AdventurePill"
adventurePill.AnchorPoint = Vector2.new(0.5, 1)
adventurePill.Position = UDim2.new(0.5, 0, 1, -28)
adventurePill.Size = UDim2.fromOffset(330, 38)
adventurePill.BackgroundColor3 = Color3.fromRGB(8, 20, 27)
adventurePill.BackgroundTransparency = 0.12
adventurePill.BorderSizePixel = 0
adventurePill.ZIndex = 8
adventurePill.Parent = previewCard
addCorner(adventurePill, 18)
addStroke(adventurePill, Color3.fromRGB(84, 163, 137), 0.5, 1)
makeText(adventurePill, {
	Size = UDim2.fromScale(1, 1),
	Text = "EXPLORE  •  LUTE  •  SOBREVIVA",
	Color = COLORS.PrimarySoft,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	XAlignment = Enum.TextXAlignment.Center,
	ZIndex = 9,
})

local infoCard = Instance.new("Frame")
infoCard.Name = "PlayerInfo"
infoCard.Position = UDim2.fromOffset(644, 0)
infoCard.Size = UDim2.fromOffset(436, 620)
infoCard.BackgroundColor3 = COLORS.Surface
infoCard.BackgroundTransparency = 0.03
infoCard.BorderSizePixel = 0
infoCard.ClipsDescendants = true
infoCard.Parent = panel
addCorner(infoCard, 26)
addStroke(infoCard, COLORS.Border, 0.54, 1.5)

local infoGradient = Instance.new("UIGradient")
infoGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 31, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 18, 27)),
})
infoGradient.Rotation = 90
infoGradient.Parent = infoCard

local playerCaption = makeText(infoCard, {
	Position = UDim2.fromOffset(30, 25),
	Size = UDim2.new(1, -60, 0, 20),
	Text = "SEU AVENTUREIRO",
	Color = COLORS.PrimarySoft,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
})

local displayName = makeText(infoCard, {
	Name = "DisplayName",
	Position = UDim2.fromOffset(28, 44),
	Size = UDim2.new(1, -56, 0, 40),
	Text = player.DisplayName,
	Color = COLORS.Text,
	Font = Enum.Font.GothamBlack,
	TextSize = 28,
	TextScaled = true,
	MinTextSize = 18,
	MaxTextSize = 28,
})

local username = makeText(infoCard, {
	Name = "Username",
	Position = UDim2.fromOffset(30, 80),
	Size = UDim2.new(1, -60, 0, 20),
	Text = "@" .. player.Name,
	Color = COLORS.TextDim,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
})

local statsRow = Instance.new("Frame")
statsRow.Name = "Stats"
statsRow.Position = UDim2.fromOffset(28, 112)
statsRow.Size = UDim2.new(1, -56, 0, 78)
statsRow.BackgroundTransparency = 1
statsRow.Parent = infoCard

local function makeStatCard(name, position, heading, color)
	local card = Instance.new("Frame")
	card.Name = name
	card.Position = position
	card.Size = UDim2.new(0.5, -6, 1, 0)
	card.BackgroundColor3 = COLORS.SurfaceRaised
	card.BorderSizePixel = 0
	card.Parent = statsRow
	addCorner(card, 15)
	addStroke(card, color, 0.72, 1)
	makeText(card, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 18),
		Text = heading,
		Color = COLORS.TextDim,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
	})
	return makeText(card, {
		Position = UDim2.fromOffset(14, 27),
		Size = UDim2.new(1, -28, 0, 38),
		Text = "—",
		Color = color,
		Font = Enum.Font.GothamBlack,
		TextSize = 25,
		TextScaled = true,
		MinTextSize = 15,
		MaxTextSize = 25,
	})
end

local recordValue = makeStatCard(
	"Record",
	UDim2.fromOffset(0, 0),
	"MELHOR ALTURA",
	COLORS.Gold
)
local coinsValue = makeStatCard(
	"Coins",
	UDim2.new(0.5, 6, 0, 0),
	"MOEDAS",
	COLORS.PrimarySoft
)

local equipmentTitle = makeText(infoCard, {
	Position = UDim2.fromOffset(30, 207),
	Size = UDim2.new(1, -60, 0, 20),
	Text = "EQUIPAMENTOS",
	Color = COLORS.TextMuted,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
})

local equipmentCards = {}

local function makeEquipmentCard(name, y, iconText, heading)
	local card = Instance.new("Frame")
	card.Name = name
	card.Position = UDim2.fromOffset(28, y)
	card.Size = UDim2.new(1, -56, 0, 62)
	card.BackgroundColor3 = COLORS.SurfaceRaised
	card.BorderSizePixel = 0
	card.Parent = infoCard
	addCorner(card, 14)
	addStroke(card, COLORS.Border, 0.72, 1)

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Size = UDim2.fromOffset(42, 42)
	icon.BackgroundColor3 = COLORS.SurfaceSoft
	icon.BorderSizePixel = 0
	icon.Parent = card
	addCorner(icon, 11)
	makeText(icon, {
		Size = UDim2.fromScale(1, 1),
		Text = iconText,
		Color = COLORS.PrimarySoft,
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		XAlignment = Enum.TextXAlignment.Center,
	})

	local headingLabel = makeText(card, {
		Position = UDim2.fromOffset(64, 7),
		Size = UDim2.new(1, -76, 0, 17),
		Text = heading,
		Color = COLORS.TextDim,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
	})

	local value = makeText(card, {
		Position = UDim2.fromOffset(64, 23),
		Size = UDim2.new(1, -76, 0, 31),
		Text = "—",
		Color = COLORS.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextScaled = true,
		MinTextSize = 9,
		MaxTextSize = 13,
		Wrapped = true,
	})

	table.insert(equipmentCards, {
		Card = card,
		Icon = icon,
		Heading = headingLabel,
		Value = value,
	})
	return value
end

local swordValue = makeEquipmentCard("Sword", 235, "⚔", "ESPADA")
local relicValue = makeEquipmentCard("Relic", 305, "✦", "RELÍQUIA")
local companionsValue = makeEquipmentCard("Companions", 375, "●", "COMPANHEIROS")

local loadingBox = Instance.new("Frame")
loadingBox.Name = "LoadingStatus"
loadingBox.Position = UDim2.fromOffset(28, 453)
loadingBox.Size = UDim2.new(1, -56, 0, 45)
loadingBox.BackgroundColor3 = COLORS.SurfaceRaised
loadingBox.BackgroundTransparency = 0.36
loadingBox.BorderSizePixel = 0
loadingBox.Parent = infoCard
addCorner(loadingBox, 12)

local statusDot = Instance.new("Frame")
statusDot.Name = "StatusDot"
statusDot.AnchorPoint = Vector2.new(0, 0.5)
statusDot.Position = UDim2.new(0, 15, 0.5, 0)
statusDot.Size = UDim2.fromOffset(9, 9)
statusDot.BackgroundColor3 = COLORS.TextMuted
statusDot.BorderSizePixel = 0
statusDot.Parent = loadingBox
addCorner(statusDot, 10)

local status = makeText(loadingBox, {
	Name = "Status",
	Position = UDim2.fromOffset(34, 0),
	Size = UDim2.new(1, -48, 1, 0),
	Text = "CONECTANDO AO SERVIDOR...",
	Color = COLORS.TextMuted,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextScaled = true,
	MinTextSize = 8,
	MaxTextSize = 10,
})

local progressTrack = Instance.new("Frame")
progressTrack.Name = "ProgressTrack"
progressTrack.Position = UDim2.fromOffset(28, 507)
progressTrack.Size = UDim2.new(1, -56, 0, 4)
progressTrack.BackgroundColor3 = Color3.fromRGB(43, 60, 68)
progressTrack.BorderSizePixel = 0
progressTrack.ClipsDescendants = true
progressTrack.Parent = infoCard
addCorner(progressTrack, 4)

local progressFill = Instance.new("Frame")
progressFill.Name = "ProgressFill"
progressFill.Size = UDim2.fromScale(0.12, 1)
progressFill.BackgroundColor3 = COLORS.Primary
progressFill.BorderSizePixel = 0
progressFill.Parent = progressTrack
addCorner(progressFill, 4)

local startButton = Instance.new("TextButton")
startButton.Name = "StartButton"
startButton.AnchorPoint = Vector2.new(0.5, 0)
startButton.Position = UDim2.new(0.5, 0, 0, 526)
startButton.Size = UDim2.new(1, -56, 0, 64)
startButton.BackgroundColor3 = Color3.fromRGB(39, 67, 61)
startButton.BorderSizePixel = 0
startButton.Text = "AGUARDE..."
startButton.TextColor3 = COLORS.TextMuted
startButton.Font = Enum.Font.GothamBlack
startButton.TextSize = 18
startButton.AutoButtonColor = false
startButton.Active = false
startButton.Parent = infoCard
addCorner(startButton, 16)
local buttonStroke = addStroke(startButton, COLORS.PrimarySoft, 0.78, 1.5)
local buttonScale = Instance.new("UIScale")
buttonScale.Parent = startButton

local hint = makeText(infoCard, {
	Position = UDim2.fromOffset(28, 593),
	Size = UDim2.new(1, -56, 0, 18),
	Text = "Seu personagem entra protegido em uma ilha segura.",
	Color = COLORS.TextDim,
	Font = Enum.Font.Gotham,
	TextSize = 9,
	XAlignment = Enum.TextXAlignment.Center,
})

local currentPortrait = false
local previewCharacter
local avatarBounds
local previewBounds
local previewCenter
local previewBasePivot
local previewCompanions = {}
local previewCompanionFolder
local previewSword
local previewSwordParts = {}
local previewSwordGrip = CFrame.new()
local previewSwordId
local previewEquipmentFingerprint
local latestSnapshot

local function fitPreviewCamera()
	if not previewBounds then
		previewCamera.CFrame = CFrame.lookAt(Vector3.new(0, 3.5, -12), Vector3.new(0, 2.7, 0))
		return
	end

	local size = previewBounds
	local viewportSize = viewport.AbsoluteSize
	local aspect = math.max(0.6, viewportSize.X / math.max(1, viewportSize.Y))
	local verticalFov = math.rad(previewCamera.FieldOfView)
	local horizontalFov = 2 * math.atan(math.tan(verticalFov * 0.5) * aspect)
	local verticalDistance = (size.Y * 0.53) / math.tan(verticalFov * 0.5)
	local horizontalDistance = (math.max(size.X, size.Z) * 0.56) / math.tan(horizontalFov * 0.5)
	local distance = math.max(verticalDistance, horizontalDistance) + size.Z * 0.45
	local target = previewCenter or Vector3.new(0, size.Y * 0.5, 0)
	-- O avatar Roblox olha para -Z. A câmera também precisa ficar em -Z para
	-- mostrar o rosto; em +Z ela enquadrava exatamente as costas.
	local direction = Vector3.new(0, 0.055, -1).Unit
	previewCamera.CFrame = CFrame.lookAt(target + direction * distance, target)
end

local function applyResponsiveLayout()
	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
	-- A orientação decide o layout. Um celular deitado usa a composição
	-- horizontal; usar apenas a largura deixaria a interface minúscula.
	local portrait = screen.X / math.max(1, screen.Y) < 1.12
	currentPortrait = portrait

	if portrait then
		panel.Size = UDim2.fromOffset(PORTRAIT_SIZE.X, PORTRAIT_SIZE.Y)
		previewCard.Position = UDim2.fromOffset(0, 0)
		previewCard.Size = UDim2.fromOffset(720, 480)
		infoCard.Position = UDim2.fromOffset(0, 500)
		infoCard.Size = UDim2.fromOffset(720, 620)
		viewport.Position = UDim2.fromOffset(0, 108)
		viewport.Size = UDim2.new(1, 0, 1, -142)
		avatarFallback.Position = UDim2.fromScale(0.5, 0.62)
		avatarFallback.Size = UDim2.fromScale(0.58, 0.58)
		adventurePill.Position = UDim2.new(0.5, 0, 1, -18)
		infoCard.ClipsDescendants = true

		local cardWidth = 208
		local gap = 12
		for index, equipment in ipairs(equipmentCards) do
			equipment.Card.Position = UDim2.fromOffset(28 + (index - 1) * (cardWidth + gap), 235)
			equipment.Card.Size = UDim2.fromOffset(cardWidth, 132)
			equipment.Icon.Position = UDim2.new(0.5, -21, 0, 12)
			equipment.Heading.Position = UDim2.fromOffset(12, 58)
			equipment.Heading.Size = UDim2.new(1, -24, 0, 16)
			equipment.Heading.TextXAlignment = Enum.TextXAlignment.Center
			equipment.Value.Position = UDim2.fromOffset(12, 74)
			equipment.Value.Size = UDim2.new(1, -24, 0, 48)
			equipment.Value.TextXAlignment = Enum.TextXAlignment.Center
		end
		loadingBox.Position = UDim2.fromOffset(28, 389)
		progressTrack.Position = UDim2.fromOffset(28, 443)
		startButton.Position = UDim2.new(0.5, 0, 0, 462)
		startButton.Size = UDim2.new(1, -56, 0, 84)
		startButton.TextSize = 23
		hint.Position = UDim2.fromOffset(28, 558)
		hint.Size = UDim2.new(1, -56, 0, 30)
		hint.TextSize = 12
	else
		panel.Size = UDim2.fromOffset(DESKTOP_SIZE.X, DESKTOP_SIZE.Y)
		previewCard.Position = UDim2.fromOffset(0, 0)
		previewCard.Size = UDim2.fromOffset(620, 620)
		infoCard.Position = UDim2.fromOffset(644, 0)
		infoCard.Size = UDim2.fromOffset(436, 620)
		viewport.Position = UDim2.fromOffset(0, 126)
		viewport.Size = UDim2.new(1, 0, 1, -176)
		avatarFallback.Position = UDim2.fromScale(0.5, 0.59)
		avatarFallback.Size = UDim2.fromScale(0.68, 0.68)
		adventurePill.Position = UDim2.new(0.5, 0, 1, -28)

		for index, equipment in ipairs(equipmentCards) do
			equipment.Card.Position = UDim2.fromOffset(28, 235 + (index - 1) * 70)
			equipment.Card.Size = UDim2.new(1, -56, 0, 62)
			equipment.Icon.Position = UDim2.fromOffset(10, 10)
			equipment.Heading.Position = UDim2.fromOffset(64, 7)
			equipment.Heading.Size = UDim2.new(1, -76, 0, 17)
			equipment.Heading.TextXAlignment = Enum.TextXAlignment.Left
			equipment.Value.Position = UDim2.fromOffset(64, 23)
			equipment.Value.Size = UDim2.new(1, -76, 0, 31)
			equipment.Value.TextXAlignment = Enum.TextXAlignment.Left
		end
		loadingBox.Position = UDim2.fromOffset(28, 453)
		progressTrack.Position = UDim2.fromOffset(28, 507)
		startButton.Position = UDim2.new(0.5, 0, 0, 526)
		startButton.Size = UDim2.new(1, -56, 0, 64)
		startButton.TextSize = 18
		hint.Position = UDim2.fromOffset(28, 593)
		hint.Size = UDim2.new(1, -56, 0, 18)
		hint.TextSize = 9
	end

	local base = portrait and PORTRAIT_SIZE or DESKTOP_SIZE
	local sidePadding = portrait and 18 or 28
	local verticalPadding = 22
	panelScale.Scale = math.min(
		1,
		(screen.X - sidePadding * 2) / base.X,
		(screen.Y - verticalPadding * 2) / base.Y
	)
	task.defer(fitPreviewCamera)
end

local cameraViewportConnection
local function bindCurrentCamera()
	if cameraViewportConnection and cameraViewportConnection.Connected then
		cameraViewportConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(
			applyResponsiveLayout
		))
	end
	applyResponsiveLayout()
end

track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera))
bindCurrentCamera()

local function sanitizePreviewModel(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = true
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

local function previewTemplate(category, assetId, attributeName)
	if type(assetId) ~= "string" or assetId == "" then
		return nil
	end
	local root = ReplicatedStorage:FindFirstChild("StartScreenPreviewAssets")
	local folder = root and root:FindFirstChild(category)
	if not folder then
		return nil
	end
	local exact = folder:FindFirstChild(assetId)
	if exact then
		return exact
	end
	for _, candidate in ipairs(folder:GetChildren()) do
		if candidate:GetAttribute(attributeName) == assetId then
			return candidate
		end
	end
	return nil
end

local function getBodyBounds(model)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundBodyPart = false

	for _, descendant in ipairs(model:GetDescendants()) do
		if
			descendant:IsA("BasePart")
			and not descendant:FindFirstAncestorWhichIsA("Accessory")
		then
			local half = descendant.Size * 0.5
			local frame = descendant.CFrame
			local extent = Vector3.new(
				math.abs(frame.RightVector.X) * half.X
					+ math.abs(frame.UpVector.X) * half.Y
					+ math.abs(frame.LookVector.X) * half.Z,
				math.abs(frame.RightVector.Y) * half.X
					+ math.abs(frame.UpVector.Y) * half.Y
					+ math.abs(frame.LookVector.Y) * half.Z,
				math.abs(frame.RightVector.Z) * half.X
					+ math.abs(frame.UpVector.Z) * half.Y
					+ math.abs(frame.LookVector.Z) * half.Z
			)
			local position = frame.Position
			minimum = Vector3.new(
				math.min(minimum.X, position.X - extent.X),
				math.min(minimum.Y, position.Y - extent.Y),
				math.min(minimum.Z, position.Z - extent.Z)
			)
			maximum = Vector3.new(
				math.max(maximum.X, position.X + extent.X),
				math.max(maximum.Y, position.Y + extent.Y),
				math.max(maximum.Z, position.Z + extent.Z)
			)
			foundBodyPart = true
		end
	end

	if not foundBodyPart then
		return model:GetBoundingBox()
	end
	return CFrame.new((minimum + maximum) * 0.5), maximum - minimum
end

local function centerPreviewModel(model)
	model:PivotTo(CFrame.new())
	-- Acessórios UGC podem ser muito maiores que o corpo. Enquadrar somente as
	-- partes do corpo impede que o avatar pareça um ponto distante.
	local boundsCFrame, boundsSize = getBodyBounds(model)
	local offset = Vector3.new(
		-boundsCFrame.Position.X,
		-boundsCFrame.Position.Y + boundsSize.Y * 0.5,
		-boundsCFrame.Position.Z
	)
	model:PivotTo(model:GetPivot() + offset)
	local _, centeredSize = getBodyBounds(model)
	return centeredSize
end

local MAX_PREVIEW_COMPANIONS = 4

local function moveModelBoundsTo(model, targetCenter, previewYaw)
	model:PivotTo(CFrame.new() * CFrame.Angles(0, math.rad(previewYaw or 0), 0))
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + (targetCenter - boundsCFrame.Position))
	return boundsSize
end

local function createCompanionPreview(companion, index, leftCursor, rightCursor)
	local speciesId = tostring(companion.SpeciesId or "")
	local template = previewTemplate("Companions", speciesId, "MonsterId")
	if not template or not template:IsA("Model") then
		return nil, leftCursor, rightCursor
	end

	local model = template:Clone()
	model.Name = string.format("EquippedCompanion_%d_%s", index, speciesId)
	sanitizePreviewModel(model)
	model.Parent = previewCompanionFolder
	model:PivotTo(CFrame.new())
	local _, initialSize = model:GetBoundingBox()
	if initialSize.Magnitude <= 0 or initialSize.Y > 30 then
		model:Destroy()
		return nil, leftCursor, rightCursor
	end

	local halfWidth = initialSize.X * 0.5
	local x
	if index % 2 == 1 then
		x = leftCursor - halfWidth
		leftCursor = x - halfWidth - 0.35
	else
		x = rightCursor + halfWidth
		rightCursor = x + halfWidth + 0.35
	end
	local targetCenter = Vector3.new(x, initialSize.Y * 0.5, index > 2 and 0.28 or 0)
	local previewYaw = tonumber(model:GetAttribute("StartScreenPreviewYaw")) or 0
	local size = moveModelBoundsTo(model, targetCenter, previewYaw)
	return {
		Model = model,
		Center = targetCenter,
		Size = size,
	}, leftCursor, rightCursor
end

local function updateSwordPosition()
	if not previewSword or not previewCharacter or #previewSwordParts == 0 then
		return
	end
	local hand = previewCharacter:FindFirstChild("RightHand", true)
		or previewCharacter:FindFirstChild("Right Arm", true)
	if not hand or not hand:IsA("BasePart") then
		previewSword.Parent = nil
		return
	end
	if previewSword.Parent ~= worldModel then
		previewSword.Parent = worldModel
	end

	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local handGrip = gripAttachment and gripAttachment:IsA("Attachment")
		and gripAttachment.CFrame
		or CFrame.new(0, -hand.Size.Y * 0.5, 0)
	local desiredHandle = hand.CFrame * handGrip * previewSwordGrip:Inverse()
	for _, entry in ipairs(previewSwordParts) do
		if entry.Part.Parent then
			entry.Part.CFrame = desiredHandle * entry.Offset
		end
	end
end

local function createSwordPreview(sword)
	if previewSword then
		previewSword:Destroy()
		previewSword = nil
	end
	table.clear(previewSwordParts)
	previewSwordGrip = CFrame.new()
	previewSwordId = sword and tostring(sword.Id or "") or nil
	if not sword or not previewCharacter then
		return
	end

	local template = previewTemplate("Swords", previewSwordId, "SwordId")
	if not template or not template:IsA("Tool") then
		return
	end
	local tool = template:Clone()
	sanitizePreviewModel(tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		tool:Destroy()
		return
	end

	local container = Instance.new("Model")
	container.Name = "EquippedSwordPreview"
	tool.Parent = container
	container.Parent = worldModel
	previewSword = container
	previewSwordGrip = tool.Grip
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(previewSwordParts, {
				Part = descendant,
				Offset = handle.CFrame:ToObjectSpace(descendant.CFrame),
			})
		end
	end
	updateSwordPosition()
end

local function refreshCompositionBounds()
	if not avatarBounds then
		return
	end
	local minimumX = -avatarBounds.X * 0.5
	local maximumX = avatarBounds.X * 0.5
	local minimumY = 0
	local maximumY = avatarBounds.Y
	local maximumZ = avatarBounds.Z * 0.5
	for _, companion in ipairs(previewCompanions) do
		minimumX = math.min(minimumX, companion.Center.X - companion.Size.X * 0.5)
		maximumX = math.max(maximumX, companion.Center.X + companion.Size.X * 0.5)
		maximumY = math.max(maximumY, companion.Center.Y + companion.Size.Y * 0.5)
		maximumZ = math.max(maximumZ, math.abs(companion.Center.Z) + companion.Size.Z * 0.5)
	end
	if previewSword then
		updateSwordPosition()
		local swordBounds, swordSize = previewSword:GetBoundingBox()
		minimumX = math.min(minimumX, swordBounds.Position.X - swordSize.X * 0.5)
		maximumX = math.max(maximumX, swordBounds.Position.X + swordSize.X * 0.5)
		minimumY = math.min(minimumY, swordBounds.Position.Y - swordSize.Y * 0.5)
		maximumY = math.max(maximumY, swordBounds.Position.Y + swordSize.Y * 0.5)
		maximumZ = math.max(
			maximumZ,
			math.abs(swordBounds.Position.Z) + swordSize.Z * 0.5
		)
	end
	previewBounds = Vector3.new(
		math.max(avatarBounds.X, maximumX - minimumX),
		math.max(avatarBounds.Y, maximumY - minimumY),
		math.max(avatarBounds.Z, maximumZ * 2)
	)
	previewCenter = Vector3.new(
		(minimumX + maximumX) * 0.5,
		(minimumY + maximumY) * 0.5,
		0
	)
	fitPreviewCamera()
end

local function rebuildEquipmentPreview(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	latestSnapshot = snapshot
	if not previewCharacter or not avatarBounds then
		return
	end
	local previewRoot = ReplicatedStorage:FindFirstChild("StartScreenPreviewAssets")
	local revision = previewRoot and tonumber(previewRoot:GetAttribute("Revision")) or 0
	local fingerprintParts = {
		snapshot.Sword and tostring(snapshot.Sword.Id or "") or "NoSword",
		tostring(revision),
	}
	for index, companion in ipairs(snapshot.Companions or {}) do
		if index > MAX_PREVIEW_COMPANIONS then
			break
		end
		table.insert(
			fingerprintParts,
			string.format(
				"%d:%s:%s",
				index,
				tostring(companion.InstanceId or ""),
				tostring(companion.SpeciesId or "")
			)
		)
	end
	local fingerprint = table.concat(fingerprintParts, "|")
	if fingerprint == previewEquipmentFingerprint then
		refreshCompositionBounds()
		return
	end
	previewEquipmentFingerprint = fingerprint

	if not previewCompanionFolder then
		previewCompanionFolder = Instance.new("Folder")
		previewCompanionFolder.Name = "EquippedCompanions"
		previewCompanionFolder.Parent = worldModel
	end
	previewCompanionFolder:ClearAllChildren()
	table.clear(previewCompanions)

	local avatarHalfWidth = (avatarBounds and avatarBounds.X or 3) * 0.5
	local leftCursor = -avatarHalfWidth - 0.45
	local rightCursor = avatarHalfWidth + 0.45
	for index, companion in ipairs(snapshot.Companions or {}) do
		if index > MAX_PREVIEW_COMPANIONS then
			break
		end
		local state
		state, leftCursor, rightCursor = createCompanionPreview(
			companion,
			index,
			leftCursor,
			rightCursor
		)
		if state then
			table.insert(previewCompanions, state)
		end
	end

	createSwordPreview(snapshot.Sword)
	refreshCompositionBounds()
end

task.spawn(function()
	local previewRoot = ReplicatedStorage:WaitForChild("StartScreenPreviewAssets", 20)
	if not guiAlive or not previewRoot then
		return
	end
	local function refreshRealAssets()
		previewEquipmentFingerprint = nil
		if latestSnapshot and previewCharacter then
			rebuildEquipmentPreview(latestSnapshot)
		end
	end
	track(previewRoot:GetAttributeChangedSignal("Revision"):Connect(refreshRealAssets))
	refreshRealAssets()
end)

task.spawn(function()
	local ok, image = pcall(
		Players.GetUserThumbnailAsync,
		Players,
		player.UserId,
		Enum.ThumbnailType.AvatarThumbnail,
		Enum.ThumbnailSize.Size420x420
	)
	if guiAlive and ok and image then
		avatarFallback.Image = image
		TweenService:Create(avatarFallback, TweenInfo.new(0.3), {
			ImageTransparency = 0.08,
		}):Play()
	end
end)

task.spawn(function()
	local ok, model = pcall(function()
		local description = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		-- Replica o ClassicR15Character do servidor para a vitrine mostrar
		-- exatamente o corpo que o jogador usara dentro da partida.
		description.Head = 0
		description.Torso = 0
		description.LeftArm = 0
		description.RightArm = 0
		description.LeftLeg = 0
		description.RightLeg = 0
		description.BodyTypeScale = 0
		description.ProportionScale = 0
		description.HeightScale = 1
		description.WidthScale = 1
		description.HeadScale = 1
		description.DepthScale = 1
		return Players:CreateHumanoidModelFromDescription(
			description,
			Enum.HumanoidRigType.R15
		)
	end)
	if not guiAlive then
		if ok and model then
			model:Destroy()
		end
		return
	end
	if not ok or not model then
		avatarLoading.Text = "AVATAR 2D CARREGADO"
		return
	end

	sanitizePreviewModel(model)
	model.Name = "PreviewCharacter"
	model.Parent = worldModel
	local size = centerPreviewModel(model)
	if size.Magnitude <= 0 or size.Y > 40 then
		model:Destroy()
		avatarLoading.Text = "AVATAR 2D CARREGADO"
		return
	end

	previewCharacter = model
	avatarBounds = size
	previewBounds = size
	previewCenter = Vector3.new(0, size.Y * 0.5, 0)
	previewBasePivot = model:GetPivot()
	if latestSnapshot then
		rebuildEquipmentPreview(latestSnapshot)
	else
		fitPreviewCamera()
	end
	updateSwordPosition()
	avatarLoading.Visible = false
	TweenService:Create(avatarFallback, TweenInfo.new(0.3), {
		ImageTransparency = 1,
	}):Play()
end)

local ready = false
local starting = false
local loadFailed = false
local retryingLoad = false
local loadingPulse = 0

local function hasUsableCharacter()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character ~= nil
		and character.Parent ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
end

local function initialSpawnIsReady()
	if not hasUsableCharacter() then
		return false
	end
	if player:GetAttribute("RespawnState") == "Ready" then
		return true
	end
	return player:GetAttribute("InitialSpawnPositioned") == true
		and player:GetAttribute("PlayerLifecycleState") == "Playing"
end

local function setStatus(text, color)
	status.Text = text
	status.TextColor3 = color
	statusDot.BackgroundColor3 = color
end

local function applySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	rebuildEquipmentPreview(snapshot)
	recordValue.Text = string.format("%d m", math.max(0, tonumber(snapshot.BestScore) or 0))
	coinsValue.Text = string.format("%d", math.max(0, tonumber(snapshot.Coins) or 0))
	swordValue.Text = snapshot.Sword and snapshot.Sword.DisplayName or "Espada inicial"
	relicValue.Text = snapshot.Relic and snapshot.Relic.DisplayName or "Nenhuma equipada"

	local names = {}
	for _, companion in ipairs(snapshot.Companions or {}) do
		local name = tostring(companion.DisplayName or companion.SpeciesName or "Companheiro")
		local level = math.max(1, tonumber(companion.Level) or 1)
		table.insert(names, string.format("%s Nv.%d", name, level))
	end
	companionsValue.Text = #names > 0 and table.concat(names, " • ") or "Nenhum equipado"
end

local function setReady(message)
	ready = true
	loadFailed = false
	retryingLoad = false
	setStatus(message or "MUNDO PRONTO PARA EXPLORAR", COLORS.PrimarySoft)
	progressFill.Size = UDim2.fromScale(1, 1)
	startButton.Text = "INICIAR AVENTURA"
	startButton.BackgroundColor3 = COLORS.PrimaryDark
	startButton.TextColor3 = COLORS.Text
	startButton.AutoButtonColor = true
	startButton.Active = true
	buttonStroke.Transparency = 0.22
end

local function setLoadFailure(state)
	loadFailed = true
	retryingLoad = false
	local dataFailure = state == "DataLoadFailed"
	setStatus(
		dataFailure and "NÃO FOI POSSÍVEL CARREGAR SEUS DADOS" or "O MUNDO NÃO RESPONDEU",
		COLORS.Error
	)
	progressFill.Size = UDim2.fromScale(1, 1)
	progressFill.BackgroundColor3 = COLORS.Error
	startButton.Text = "TENTAR NOVAMENTE"
	startButton.BackgroundColor3 = Color3.fromRGB(130, 58, 55)
	startButton.TextColor3 = COLORS.Text
	startButton.Active = true
	startButton.AutoButtonColor = true
	buttonStroke.Color = COLORS.Error
	buttonStroke.Transparency = 0.3
end

track(startButton.MouseEnter:Connect(function()
	if startButton.Active then
		TweenService:Create(buttonScale, TweenInfo.new(0.12), { Scale = 1.018 }):Play()
	end
end))

track(startButton.MouseLeave:Connect(function()
	TweenService:Create(buttonScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
end))

track(RunService.RenderStepped:Connect(function(deltaTime)
	loadingPulse += deltaTime
	if not ready and not loadFailed then
		local wave = (math.sin(loadingPulse * 2.8) + 1) * 0.5
		statusDot.BackgroundTransparency = 0.15 + wave * 0.55
		progressFill.Size = UDim2.fromScale(0.14 + wave * 0.36, 1)
	else
		statusDot.BackgroundTransparency = 0
	end

	if previewCharacter and previewBasePivot then
		-- Mantém o rosto para a câmera, com apenas um movimento mínimo de vida.
		local yaw = math.rad(math.sin(loadingPulse * 0.42) * 2)
		previewCharacter:PivotTo(
			CFrame.new(previewBasePivot.Position)
				* CFrame.Angles(0, yaw, 0)
				* previewBasePivot.Rotation
		)
	end

	updateSwordPosition()
end))

task.spawn(function()
	while guiAlive and not ready and not starting do
		request = request or ReplicatedStorage:FindFirstChild("StartGameRequest")
		if not request or not request:IsA("RemoteFunction") then
			setStatus("CONECTANDO AO SERVIDOR...", COLORS.TextMuted)
			task.wait(0.4)
			continue
		end

		local success, response = pcall(request.InvokeServer, request, "Get")
		if success and type(response) == "table" then
			applySnapshot(response.Snapshot)
			if response.Ready then
				setReady()
				return
			end
			if response.State == "WorldLoadFailed" or response.State == "DataLoadFailed" then
				setLoadFailure(response.State)
			elseif response.State == "PreparingWorld" then
				loadFailed = false
				setStatus("GERANDO AS ILHAS DO MUNDO...", COLORS.TextMuted)
			else
				loadFailed = false
				setStatus("CARREGANDO SEU PROGRESSO...", COLORS.TextMuted)
			end
		elseif not success then
			setStatus("RECONECTANDO AO SERVIDOR...", COLORS.TextMuted)
		end
		task.wait(0.4)
	end
end)

local function fadeAndDestroy()
	startButton.Active = false
	local duration = 0.38
	for _, descendant in ipairs(backdrop:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif descendant:IsA("ImageLabel") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				ImageTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif descendant:IsA("GuiObject") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				BackgroundTransparency = 1,
			}):Play()
		end
	end
	TweenService:Create(panelScale, TweenInfo.new(0.42, Enum.EasingStyle.Quad), {
		Scale = panelScale.Scale * 1.025,
	}):Play()
	task.wait(0.44)
	if gui.Parent then
		gui:Destroy()
	end
end

track(startButton.Activated:Connect(function()
	TweenService:Create(buttonScale, TweenInfo.new(0.08), { Scale = 0.98 }):Play()
	task.delay(0.09, function()
		if guiAlive then
			TweenService:Create(buttonScale, TweenInfo.new(0.1), { Scale = 1 }):Play()
		end
	end)

	if loadFailed and not retryingLoad then
		if not request or not request:IsA("RemoteFunction") then
			setStatus("AINDA SEM CONEXÃO COM O SERVIDOR", COLORS.Error)
			return
		end
		retryingLoad = true
		loadFailed = false
		startButton.Active = false
		startButton.AutoButtonColor = false
		startButton.Text = "TENTANDO NOVAMENTE..."
		setStatus("REINICIANDO O CARREGAMENTO...", COLORS.TextMuted)
		progressFill.BackgroundColor3 = COLORS.Primary
		buttonStroke.Color = COLORS.PrimarySoft

		local retryOk, retryResponse = pcall(request.InvokeServer, request, "RetryLoading")
		if not retryOk or type(retryResponse) ~= "table" or retryResponse.Success ~= true then
			setLoadFailure("WorldLoadFailed")
		end
		return
	end

	if not ready or starting or not request or not request:IsA("RemoteFunction") then
		return
	end

	starting = true
	startButton.Active = false
	startButton.AutoButtonColor = false
	startButton.Text = "ENTRANDO NO MUNDO..."
	setStatus("POSICIONANDO VOCÊ EM UMA ILHA SEGURA...", COLORS.PrimarySoft)
	progressFill.Size = UDim2.fromScale(0.62, 1)

	local success, response = pcall(request.InvokeServer, request, "Start")
	if not success or type(response) ~= "table" or response.Success ~= true then
		starting = false
		setReady(response and response.Message or "NÃO FOI POSSÍVEL INICIAR")
		return
	end

	local deadline = os.clock() + 30
	while guiAlive and os.clock() < deadline and not initialSpawnIsReady() do
		RunService.Heartbeat:Wait()
	end

	if initialSpawnIsReady() then
		setStatus("BOA SUBIDA!", COLORS.PrimarySoft)
		progressFill.Size = UDim2.fromScale(1, 1)
		task.wait(0.15)
		fadeAndDestroy()
	else
		starting = false
		setReady("O MAPA DEMOROU PARA RESPONDER. TENTE NOVAMENTE.")
	end
end))
