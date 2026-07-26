-- SkyDungeon - interface de companheiros com navegacao por paginas.
--
-- Camada 1: visao geral da equipe e da colecao.
-- Camada 2: pagina completa do companheiro selecionado.
-- Camada 3: abas de informacoes e upgrades dentro da pagina individual.
--
-- Equipamentos e upgrades continuam validados pelo servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local player = Players.LocalPlayer
local request = ReplicatedStorage:WaitForChild("CompanionRequest")
local event = ReplicatedStorage:WaitForChild("CompanionEvent")

local COLORS = {
	Backdrop = Color3.fromRGB(3, 7, 8),
	Panel = Color3.fromRGB(11, 19, 18),
	Header = Color3.fromRGB(20, 39, 32),
	Surface = Color3.fromRGB(18, 31, 27),
	SurfaceRaised = Color3.fromRGB(25, 43, 36),
	SurfaceSelected = Color3.fromRGB(31, 68, 48),
	SurfaceDisabled = Color3.fromRGB(45, 55, 51),
	Primary = Color3.fromRGB(68, 205, 119),
	PrimaryDark = Color3.fromRGB(35, 124, 75),
	PrimarySoft = Color3.fromRGB(135, 237, 171),
	Danger = Color3.fromRGB(175, 68, 65),
	DangerDark = Color3.fromRGB(119, 47, 47),
	Gold = Color3.fromRGB(255, 216, 104),
	Text = Color3.fromRGB(239, 249, 242),
	TextMuted = Color3.fromRGB(158, 184, 169),
	TextDim = Color3.fromRGB(105, 130, 116),
	Stroke = Color3.fromRGB(74, 139, 100),
	Track = Color3.fromRGB(37, 53, 46),
}

local STYLE_NAMES = {
	Melee = "CORPO A CORPO",
	Contact = "CONTATO",
	Ranged = "DISTÂNCIA",
	Mortar = "MORTEIRO",
	NeutralMelee = "CORPO A CORPO",
	NeutralRanged = "DISTÂNCIA",
	HostileMortar = "MORTEIRO",
	GoldenEscape = "TELEPORTE",
	None = "SUPORTE",
}

local STAT_DEFINITIONS = {
	{
		Key = "Damage",
		Label = "DANO",
		Description = "Dano causado por ataque",
		Format = function(value)
			return string.format("%.1f", value)
		end,
	},
	{
		Key = "AttackCooldown",
		Label = "RECARGA",
		Description = "Intervalo entre ataques",
		Format = function(value)
			return string.format("%.2fs", value)
		end,
	},
	{
		Key = "WalkSpeed",
		Label = "MOVIMENTO",
		Description = "Velocidade de deslocamento",
		Format = function(value)
			return string.format("%.1f", value)
		end,
	},
	{
		Key = "AttackRange",
		Label = "ALCANCE",
		Description = "Distância máxima do ataque",
		Format = function(value)
			return string.format("%.1f", value)
		end,
	},
}

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

local function addPadding(parent, top, right, bottom, left)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.PaddingLeft = UDim.new(0, left)
	padding.Parent = parent
	return padding
end

local function createLabel(parent, name, text, position, size, textSize, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or COLORS.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = font or Enum.Font.Gotham
	label.TextSize = textSize
	label.Parent = parent
	return label
end

local function createButton(parent, name, text, position, size, background, textColor)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = textColor or COLORS.Text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.AutoButtonColor = true
	button.Parent = parent
	addCorner(button, 10)
	return button
end

local function createPortrait(parent, entry, size, position)
	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Position = position
	portrait.Size = UDim2.fromOffset(size, size)
	portrait.BackgroundColor3 = COLORS.Panel
	portrait.BorderSizePixel = 0
	portrait.ClipsDescendants = true
	portrait.Parent = parent
	addCorner(portrait, math.max(9, math.floor(size * 0.16)))
	addStroke(portrait, COLORS.Stroke, 0.42, size >= 120 and 2 or 1)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 66, 48)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 24, 21)),
	})
	gradient.Rotation = 135
	gradient.Parent = portrait

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.Position = UDim2.fromOffset(6, 6)
	image.Size = UDim2.new(1, -12, 1, -12)
	image.BackgroundTransparency = 1
	image.Image = entry and entry.ImageId or ""
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = portrait.ZIndex + 1
	image.Parent = portrait

	local placeholder = Instance.new("TextLabel")
	placeholder.Name = "Placeholder"
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.BackgroundTransparency = 1
	placeholder.Text = entry and string.upper(string.sub(entry.DisplayName, 1, 1)) or "+"
	placeholder.TextColor3 = entry and COLORS.PrimarySoft or COLORS.TextDim
	placeholder.Font = Enum.Font.GothamBlack
	placeholder.TextSize = math.floor(size * 0.4)
	placeholder.Visible = not entry or entry.ImageId == nil or entry.ImageId == ""
	placeholder.ZIndex = portrait.ZIndex + 1
	placeholder.Parent = portrait
	return portrait
end

local function createProgressBar(parent, name, position, size, progress, color)
	local track = Instance.new("Frame")
	track.Name = name
	track.Position = position
	track.Size = size
	track.BackgroundColor3 = COLORS.Track
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent
	addCorner(track, 99)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	fill.BackgroundColor3 = color or COLORS.Primary
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, 99)
	return track
end

local function clearGuiObjects(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function utf8Length(value)
	return utf8.len(value) or 0
end

local function truncateUtf8(value, maxLength)
	local length = utf8Length(value)
	if length <= maxLength then
		return value
	end
	local boundary = utf8.offset(value, maxLength + 1)
	return boundary and string.sub(value, 1, boundary - 1) or value
end

local gui = Instance.new("ScreenGui")
gui.Name = "CompanionUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- O atalho da hotbar usa uma camada separada da janela principal. Assim, a
-- janela de companheiros ainda abre acima da HUD, mas telas críticas como a
-- DeathScreen (DisplayOrder 100) sempre cobrem o botão.
local launcherGui = Instance.new("ScreenGui")
launcherGui.Name = "CompanionLauncherUI"
launcherGui.ResetOnSpawn = false
launcherGui.IgnoreGuiInset = true
launcherGui.DisplayOrder = 30
launcherGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
launcherGui.Parent = player.PlayerGui

local openButton = createButton(
	launcherGui,
	"OpenCompanions",
	"",
	UDim2.new(0.5, 66, 1, -36),
	UDim2.fromOffset(54, 54),
	Color3.fromRGB(30, 38, 49)
)
openButton.AnchorPoint = Vector2.new(0.5, 0.5)
openButton.ZIndex = 5
openButton.BackgroundTransparency = 0.06
addCorner(openButton, 8)
local openStroke = addStroke(openButton, COLORS.PrimarySoft, 0.5, 1.25)

-- Icone vetorial de pata: nao depende de emoji nem de asset externo.
local pawIcon = Instance.new("Frame")
pawIcon.Name = "MascotIcon"
pawIcon.AnchorPoint = Vector2.new(0.5, 0.5)
pawIcon.Position = UDim2.fromScale(0.5, 0.53)
pawIcon.Size = UDim2.fromOffset(34, 32)
pawIcon.BackgroundTransparency = 1
pawIcon.ZIndex = 6
pawIcon.Parent = openButton

local function createPawPart(name, position, size, rotation)
	local part = Instance.new("Frame")
	part.Name = name
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.Position = position
	part.Size = size
	part.Rotation = rotation or 0
	part.BackgroundColor3 = COLORS.PrimarySoft
	part.BorderSizePixel = 0
	part.ZIndex = 6
	part.Parent = pawIcon
	addCorner(part, 99)
	return part
end

createPawPart("Pad", UDim2.fromScale(0.5, 0.66), UDim2.fromOffset(20, 16))
createPawPart("ToeLeft", UDim2.fromScale(0.18, 0.37), UDim2.fromOffset(8, 11), -18)
createPawPart("ToeMiddleLeft", UDim2.fromScale(0.4, 0.2), UDim2.fromOffset(8, 11), -6)
createPawPart("ToeMiddleRight", UDim2.fromScale(0.62, 0.2), UDim2.fromOffset(8, 11), 6)
createPawPart("ToeRight", UDim2.fromScale(0.84, 0.37), UDim2.fromOffset(8, 11), 18)

local openCounter = createLabel(
	openButton,
	"Counter",
	"",
	UDim2.new(1, -14, 0, -5),
	UDim2.fromOffset(20, 20),
	10,
	COLORS.Text,
	Enum.Font.GothamBold
)
openCounter.BackgroundColor3 = COLORS.PrimaryDark
openCounter.BackgroundTransparency = 0
openCounter.TextXAlignment = Enum.TextXAlignment.Center
openCounter.ZIndex = 8
openCounter.Visible = false
addCorner(openCounter, 99)
addStroke(openCounter, COLORS.Text, 0.72, 1)

local openTooltip = createLabel(
	openButton,
	"Tooltip",
	"COMPANHEIROS",
	UDim2.new(0.5, 0, 0, -32),
	UDim2.fromOffset(116, 25),
	10,
	COLORS.Text,
	Enum.Font.GothamBold
)
openTooltip.AnchorPoint = Vector2.new(0.5, 0.5)
openTooltip.BackgroundColor3 = COLORS.Panel
openTooltip.BackgroundTransparency = 0.06
openTooltip.TextXAlignment = Enum.TextXAlignment.Center
openTooltip.ZIndex = 8
openTooltip.Visible = false
addCorner(openTooltip, 7)
addStroke(openTooltip, COLORS.Stroke, 0.45, 1)

openButton.MouseEnter:Connect(function()
	openButton.BackgroundColor3 = Color3.fromRGB(39, 54, 61)
	openStroke.Transparency = 0.18
	openTooltip.Visible = true
end)

openButton.MouseLeave:Connect(function()
	openButton.BackgroundColor3 = Color3.fromRGB(30, 38, 49)
	openStroke.Transparency = 0.5
	openTooltip.Visible = false
end)

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLORS.Backdrop
backdrop.BackgroundTransparency = 0.2
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Modal = true
backdrop.Visible = false
backdrop.ZIndex = 10
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(1000, 650)
panel.BackgroundColor3 = COLORS.Panel
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Visible = false
panel.ZIndex = 20
panel.Parent = gui
addCorner(panel, 18)
addStroke(panel, COLORS.Primary, 0.24, 1.5)

local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 42, 34)),
	ColorSequenceKeypoint.new(0.28, COLORS.Panel),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 15, 15)),
})
panelGradient.Rotation = 90
panelGradient.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local cameraViewportConnection
local function updatePanelScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(
		math.min((viewport.X - 26) / 1000, (viewport.Y - 26) / 650),
		0.46,
		1
	)
end

local function bindCamera()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end
	updatePanelScale()
	if workspace.CurrentCamera then
		cameraViewportConnection = workspace.CurrentCamera
			:GetPropertyChangedSignal("ViewportSize")
			:Connect(updatePanelScale)
	end
end

bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 74)
header.BackgroundColor3 = COLORS.Header
header.BackgroundTransparency = 0.08
header.BorderSizePixel = 0
header.ZIndex = 21
header.Parent = panel

local headerAccent = Instance.new("Frame")
headerAccent.Position = UDim2.fromOffset(20, 18)
headerAccent.Size = UDim2.fromOffset(5, 38)
headerAccent.BackgroundColor3 = COLORS.Primary
headerAccent.BorderSizePixel = 0
headerAccent.Parent = header
addCorner(headerAccent, 99)

local backButton = createButton(
	header,
	"Back",
	"<  VOLTAR",
	UDim2.fromOffset(36, 18),
	UDim2.fromOffset(102, 38),
	COLORS.SurfaceRaised,
	COLORS.Text
)
backButton.Visible = false
backButton.ZIndex = 23
addStroke(backButton, COLORS.Stroke, 0.56, 1)

local headerTitle = createLabel(
	header,
	"Title",
	"EQUIPE DE COMPANHEIROS",
	UDim2.fromOffset(38, 12),
	UDim2.new(1, -150, 0, 27),
	20,
	COLORS.Text,
	Enum.Font.GothamBold
)

local headerSubtitle = createLabel(
	header,
	"Subtitle",
	"Selecione um companheiro para abrir sua página completa.",
	UDim2.fromOffset(38, 40),
	UDim2.new(1, -150, 0, 19),
	11,
	COLORS.TextMuted,
	Enum.Font.Gotham
)

local closeButton = createButton(
	header,
	"Close",
	"X",
	UDim2.new(1, -58, 0, 17),
	UDim2.fromOffset(40, 40),
	Color3.fromRGB(57, 69, 63),
	COLORS.Text
)
closeButton.TextSize = 14
closeButton.ZIndex = 23
addStroke(closeButton, COLORS.TextMuted, 0.72, 1)

local overviewPage = Instance.new("Frame")
overviewPage.Name = "OverviewPage"
overviewPage.Position = UDim2.fromOffset(0, 74)
overviewPage.Size = UDim2.new(1, 0, 1, -74)
overviewPage.BackgroundTransparency = 1
overviewPage.ZIndex = 21
overviewPage.Parent = panel

local teamSection = Instance.new("Frame")
teamSection.Name = "TeamSection"
teamSection.Position = UDim2.fromOffset(18, 14)
teamSection.Size = UDim2.new(1, -36, 0, 130)
teamSection.BackgroundColor3 = COLORS.Surface
teamSection.BackgroundTransparency = 0.04
teamSection.BorderSizePixel = 0
teamSection.ZIndex = 22
teamSection.Parent = overviewPage
addCorner(teamSection, 14)
addStroke(teamSection, COLORS.Stroke, 0.64, 1)

createLabel(
	teamSection,
	"Title",
	"EQUIPE ATIVA",
	UDim2.fromOffset(14, 8),
	UDim2.fromOffset(190, 21),
	11,
	COLORS.PrimarySoft,
	Enum.Font.GothamBold
)

local teamCount = createLabel(
	teamSection,
	"Count",
	"0 DE 4",
	UDim2.new(1, -132, 0, 8),
	UDim2.fromOffset(116, 21),
	10,
	COLORS.TextMuted,
	Enum.Font.GothamBold
)
teamCount.TextXAlignment = Enum.TextXAlignment.Right

local slots = Instance.new("Frame")
slots.Name = "EquippedSlots"
slots.Position = UDim2.fromOffset(12, 36)
slots.Size = UDim2.new(1, -24, 0, 81)
slots.BackgroundTransparency = 1
slots.ZIndex = 23
slots.Parent = teamSection

local slotsLayout = Instance.new("UIGridLayout")
slotsLayout.CellSize = UDim2.new(0.25, -7, 1, 0)
slotsLayout.CellPadding = UDim2.fromOffset(9, 0)
slotsLayout.FillDirectionMaxCells = CompanionCatalog.MaxEquipped
slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotsLayout.Parent = slots

local collectionSection = Instance.new("Frame")
collectionSection.Name = "CollectionSection"
collectionSection.Position = UDim2.fromOffset(18, 156)
collectionSection.Size = UDim2.new(1, -36, 1, -170)
collectionSection.BackgroundColor3 = COLORS.Surface
collectionSection.BackgroundTransparency = 0.04
collectionSection.BorderSizePixel = 0
collectionSection.ZIndex = 22
collectionSection.Parent = overviewPage
addCorner(collectionSection, 14)
addStroke(collectionSection, COLORS.Stroke, 0.68, 1)

createLabel(
	collectionSection,
	"Title",
	"COLEÇÃO",
	UDim2.fromOffset(15, 10),
	UDim2.fromOffset(210, 24),
	12,
	COLORS.Text,
	Enum.Font.GothamBold
)

createLabel(
	collectionSection,
	"Hint",
	"CLIQUE EM UM COMPANHEIRO PARA ABRIR",
	UDim2.fromOffset(15, 31),
	UDim2.fromOffset(300, 16),
	9,
	COLORS.TextMuted,
	Enum.Font.GothamMedium
)

local collectionCount = createLabel(
	collectionSection,
	"Count",
	"0 DESBLOQUEADOS",
	UDim2.new(1, -170, 0, 16),
	UDim2.fromOffset(154, 24),
	10,
	COLORS.PrimarySoft,
	Enum.Font.GothamBold
)
collectionCount.TextXAlignment = Enum.TextXAlignment.Right

local collectionList = Instance.new("ScrollingFrame")
collectionList.Name = "Collection"
collectionList.Position = UDim2.fromOffset(10, 55)
collectionList.Size = UDim2.new(1, -20, 1, -65)
collectionList.BackgroundTransparency = 1
collectionList.BorderSizePixel = 0
collectionList.ScrollBarThickness = 5
collectionList.ScrollBarImageColor3 = COLORS.Primary
collectionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
collectionList.CanvasSize = UDim2.new()
collectionList.ScrollingDirection = Enum.ScrollingDirection.Y
collectionList.ZIndex = 23
collectionList.Parent = collectionSection
addPadding(collectionList, 1, 7, 8, 1)

local collectionLayout = Instance.new("UIGridLayout")
collectionLayout.CellSize = UDim2.new(0.333333, -7, 0, 112)
collectionLayout.CellPadding = UDim2.fromOffset(9, 9)
collectionLayout.FillDirectionMaxCells = 3
collectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
collectionLayout.Parent = collectionList

local collectionEmpty = createLabel(
	collectionSection,
	"Empty",
	"NENHUM COMPANHEIRO DESBLOQUEADO\n\nContinue derrotando monstros para formar sua equipe.",
	UDim2.fromOffset(32, 116),
	UDim2.new(1, -64, 0, 170),
	13,
	COLORS.TextMuted,
	Enum.Font.GothamMedium
)
collectionEmpty.TextXAlignment = Enum.TextXAlignment.Center
collectionEmpty.TextYAlignment = Enum.TextYAlignment.Center
collectionEmpty.TextWrapped = true
collectionEmpty.Visible = false
collectionEmpty.ZIndex = 24

local detailPage = Instance.new("Frame")
detailPage.Name = "CompanionDetailPage"
detailPage.Position = UDim2.fromOffset(0, 74)
detailPage.Size = UDim2.new(1, 0, 1, -74)
detailPage.BackgroundTransparency = 1
detailPage.Visible = false
detailPage.ZIndex = 21
detailPage.Parent = panel

local identityPanel = Instance.new("Frame")
identityPanel.Name = "IdentityPanel"
identityPanel.Position = UDim2.fromOffset(18, 16)
identityPanel.Size = UDim2.fromOffset(286, 542)
identityPanel.BackgroundColor3 = COLORS.Surface
identityPanel.BackgroundTransparency = 0.02
identityPanel.BorderSizePixel = 0
identityPanel.ZIndex = 22
identityPanel.Parent = detailPage
addCorner(identityPanel, 15)
addStroke(identityPanel, COLORS.Stroke, 0.55, 1)

local portraitHost = Instance.new("Frame")
portraitHost.Name = "PortraitHost"
portraitHost.Position = UDim2.fromOffset(43, 25)
portraitHost.Size = UDim2.fromOffset(200, 200)
portraitHost.BackgroundTransparency = 1
portraitHost.ZIndex = 23
portraitHost.Parent = identityPanel

local detailStatus = Instance.new("TextLabel")
detailStatus.Name = "Status"
detailStatus.AnchorPoint = Vector2.new(0.5, 0)
detailStatus.Position = UDim2.new(0.5, 0, 0, 237)
detailStatus.Size = UDim2.fromOffset(126, 25)
detailStatus.BackgroundColor3 = COLORS.PrimaryDark
detailStatus.BorderSizePixel = 0
detailStatus.Text = "NA EQUIPE"
detailStatus.TextColor3 = COLORS.Text
detailStatus.Font = Enum.Font.GothamBold
detailStatus.TextSize = 9
detailStatus.Parent = identityPanel
addCorner(detailStatus, 99)

local detailName = createLabel(
	identityPanel,
	"Name",
	"",
	UDim2.fromOffset(18, 271),
	UDim2.new(1, -36, 0, 29),
	20,
	COLORS.Text,
	Enum.Font.GothamBold
)
detailName.TextXAlignment = Enum.TextXAlignment.Center
detailName.TextTruncate = Enum.TextTruncate.AtEnd

local renameButton = createButton(
	identityPanel,
	"Rename",
	"ALTERAR NOME",
	UDim2.new(0.5, -59, 0, 302),
	UDim2.fromOffset(118, 26),
	COLORS.SurfaceRaised,
	COLORS.PrimarySoft
)
renameButton.TextSize = 9
renameButton.ZIndex = 24
addStroke(renameButton, COLORS.Stroke, 0.58, 1)

local detailStyle = createLabel(
	identityPanel,
	"Style",
	"",
	UDim2.fromOffset(18, 331),
	UDim2.new(1, -36, 0, 19),
	10,
	COLORS.PrimarySoft,
	Enum.Font.GothamBold
)
detailStyle.TextXAlignment = Enum.TextXAlignment.Center

local detailLevel = createLabel(
	identityPanel,
	"Level",
	"",
	UDim2.fromOffset(18, 356),
	UDim2.new(1, -36, 0, 25),
	13,
	COLORS.Text,
	Enum.Font.GothamBold
)

local detailXP = createLabel(
	identityPanel,
	"XP",
	"",
	UDim2.fromOffset(18, 356),
	UDim2.new(1, -36, 0, 25),
	10,
	COLORS.TextMuted,
	Enum.Font.GothamBold
)
detailXP.TextXAlignment = Enum.TextXAlignment.Right

local xpBarHost = Instance.new("Frame")
xpBarHost.Name = "XPBarHost"
xpBarHost.Position = UDim2.fromOffset(18, 386)
xpBarHost.Size = UDim2.new(1, -36, 0, 9)
xpBarHost.BackgroundTransparency = 1
xpBarHost.Parent = identityPanel

local victoriesCard = Instance.new("Frame")
victoriesCard.Name = "Victories"
victoriesCard.Position = UDim2.fromOffset(18, 409)
victoriesCard.Size = UDim2.new(1, -36, 0, 42)
victoriesCard.BackgroundColor3 = COLORS.SurfaceRaised
victoriesCard.BorderSizePixel = 0
victoriesCard.Parent = identityPanel
addCorner(victoriesCard, 10)

createLabel(
	victoriesCard,
	"Label",
	"VITÓRIAS JUNTOS",
	UDim2.fromOffset(12, 0),
	UDim2.new(0.62, -12, 1, 0),
	9,
	COLORS.TextMuted,
	Enum.Font.GothamBold
)

local victoriesValue = createLabel(
	victoriesCard,
	"Value",
	"0",
	UDim2.new(0.62, 0, 0, 0),
	UDim2.new(0.38, -12, 1, 0),
	17,
	COLORS.Gold,
	Enum.Font.GothamBold
)
victoriesValue.TextXAlignment = Enum.TextXAlignment.Right

local equipButton = createButton(
	identityPanel,
	"EquipAction",
	"EQUIPAR",
	UDim2.fromOffset(18, 467),
	UDim2.new(1, -96, 0, 52),
	COLORS.PrimaryDark,
	COLORS.Text
)
equipButton.TextSize = 13
addStroke(equipButton, COLORS.PrimarySoft, 0.58, 1)

local discardButton = createButton(
	identityPanel,
	"DiscardAction",
	"",
	UDim2.new(1, -70, 0, 467),
	UDim2.fromOffset(52, 52),
	COLORS.DangerDark,
	COLORS.Text
)
discardButton.ZIndex = 24
addStroke(discardButton, Color3.fromRGB(240, 130, 124), 0.5, 1)

-- Ícone vetorial de lixeira, sem depender de emoji ou imagem externa.
local trashIcon = Instance.new("Frame")
trashIcon.Name = "TrashIcon"
trashIcon.AnchorPoint = Vector2.new(0.5, 0.5)
trashIcon.Position = UDim2.fromScale(0.5, 0.51)
trashIcon.Size = UDim2.fromOffset(22, 25)
trashIcon.BackgroundTransparency = 1
trashIcon.ZIndex = 25
trashIcon.Parent = discardButton

local trashBody = Instance.new("Frame")
trashBody.Name = "Body"
trashBody.Position = UDim2.fromOffset(4, 7)
trashBody.Size = UDim2.fromOffset(14, 16)
trashBody.BackgroundTransparency = 1
trashBody.BorderSizePixel = 0
trashBody.ZIndex = 25
trashBody.Parent = trashIcon
addCorner(trashBody, 2)
addStroke(trashBody, COLORS.Text, 0.05, 2)

local trashLid = Instance.new("Frame")
trashLid.Name = "Lid"
trashLid.Position = UDim2.fromOffset(1, 4)
trashLid.Size = UDim2.fromOffset(20, 2)
trashLid.BackgroundColor3 = COLORS.Text
trashLid.BorderSizePixel = 0
trashLid.ZIndex = 25
trashLid.Parent = trashIcon
addCorner(trashLid, 2)

local trashHandle = Instance.new("Frame")
trashHandle.Name = "Handle"
trashHandle.Position = UDim2.fromOffset(7, 0)
trashHandle.Size = UDim2.fromOffset(8, 4)
trashHandle.BackgroundTransparency = 1
trashHandle.BorderSizePixel = 0
trashHandle.ZIndex = 25
trashHandle.Parent = trashIcon
addCorner(trashHandle, 2)
addStroke(trashHandle, COLORS.Text, 0.05, 2)

for index, x in ipairs({ 8, 12 }) do
	local line = Instance.new("Frame")
	line.Name = "Line" .. index
	line.Position = UDim2.fromOffset(x, 10)
	line.Size = UDim2.fromOffset(2, 10)
	line.BackgroundColor3 = COLORS.Text
	line.BackgroundTransparency = 0.05
	line.BorderSizePixel = 0
	line.ZIndex = 26
	line.Parent = trashIcon
	addCorner(line, 2)
end

local contentPanel = Instance.new("Frame")
contentPanel.Name = "ContentPanel"
contentPanel.Position = UDim2.fromOffset(316, 16)
contentPanel.Size = UDim2.new(1, -334, 1, -32)
contentPanel.BackgroundColor3 = COLORS.Surface
contentPanel.BackgroundTransparency = 0.02
contentPanel.BorderSizePixel = 0
contentPanel.ZIndex = 22
contentPanel.Parent = detailPage
addCorner(contentPanel, 15)
addStroke(contentPanel, COLORS.Stroke, 0.62, 1)

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Position = UDim2.fromOffset(12, 12)
tabBar.Size = UDim2.new(1, -24, 0, 48)
tabBar.BackgroundColor3 = Color3.fromRGB(14, 25, 22)
tabBar.BorderSizePixel = 0
tabBar.ZIndex = 23
tabBar.Parent = contentPanel
addCorner(tabBar, 11)

local statsTabButton = createButton(
	tabBar,
	"StatsTab",
	"VISÃO GERAL",
	UDim2.fromOffset(5, 5),
	UDim2.new(0.5, -8, 1, -10),
	COLORS.PrimaryDark,
	COLORS.Text
)
statsTabButton.ZIndex = 24

local upgradesTabButton = createButton(
	tabBar,
	"UpgradesTab",
	"UPGRADES",
	UDim2.new(0.5, 3, 0, 5),
	UDim2.new(0.5, -8, 1, -10),
	COLORS.SurfaceRaised,
	COLORS.TextMuted
)
upgradesTabButton.ZIndex = 24

local statsTab = Instance.new("ScrollingFrame")
statsTab.Name = "StatsTabPage"
statsTab.Position = UDim2.fromOffset(12, 72)
statsTab.Size = UDim2.new(1, -24, 1, -84)
statsTab.BackgroundTransparency = 1
statsTab.BorderSizePixel = 0
statsTab.ScrollBarThickness = 5
statsTab.ScrollBarImageColor3 = COLORS.Primary
statsTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
statsTab.CanvasSize = UDim2.new()
statsTab.ZIndex = 23
statsTab.Parent = contentPanel
addPadding(statsTab, 1, 7, 8, 1)

local upgradesTab = Instance.new("ScrollingFrame")
upgradesTab.Name = "UpgradesTabPage"
upgradesTab.Position = UDim2.fromOffset(12, 72)
upgradesTab.Size = UDim2.new(1, -24, 1, -84)
upgradesTab.BackgroundTransparency = 1
upgradesTab.BorderSizePixel = 0
upgradesTab.ScrollBarThickness = 5
upgradesTab.ScrollBarImageColor3 = COLORS.Primary
upgradesTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
upgradesTab.CanvasSize = UDim2.new()
upgradesTab.Visible = false
upgradesTab.ZIndex = 23
upgradesTab.Parent = contentPanel
addPadding(upgradesTab, 1, 7, 8, 1)

local renameBackdrop = Instance.new("TextButton")
renameBackdrop.Name = "RenameBackdrop"
renameBackdrop.Size = UDim2.fromScale(1, 1)
renameBackdrop.BackgroundColor3 = COLORS.Backdrop
renameBackdrop.BackgroundTransparency = 0.18
renameBackdrop.BorderSizePixel = 0
renameBackdrop.Text = ""
renameBackdrop.AutoButtonColor = false
renameBackdrop.Modal = true
renameBackdrop.Visible = false
renameBackdrop.ZIndex = 60
renameBackdrop.Parent = detailPage

local renameDialog = Instance.new("Frame")
renameDialog.Name = "RenameDialog"
renameDialog.AnchorPoint = Vector2.new(0.5, 0.5)
renameDialog.Position = UDim2.fromScale(0.5, 0.5)
renameDialog.Size = UDim2.fromOffset(460, 264)
renameDialog.BackgroundColor3 = COLORS.Panel
renameDialog.BorderSizePixel = 0
renameDialog.ZIndex = 61
renameDialog.Parent = renameBackdrop
addCorner(renameDialog, 16)
addStroke(renameDialog, COLORS.Primary, 0.22, 2)

createLabel(
	renameDialog,
	"Title",
	"DÊ UM NOME AO COMPANHEIRO",
	UDim2.fromOffset(24, 18),
	UDim2.new(1, -48, 0, 28),
	18,
	COLORS.Text,
	Enum.Font.GothamBold
).ZIndex = 62

local renameSpecies = createLabel(
	renameDialog,
	"Species",
	"",
	UDim2.fromOffset(24, 48),
	UDim2.new(1, -48, 0, 20),
	10,
	COLORS.PrimarySoft,
	Enum.Font.GothamBold
)
renameSpecies.ZIndex = 62

local renameInput = Instance.new("TextBox")
renameInput.Name = "NameInput"
renameInput.Position = UDim2.fromOffset(24, 82)
renameInput.Size = UDim2.new(1, -48, 0, 54)
renameInput.BackgroundColor3 = COLORS.SurfaceRaised
renameInput.BorderSizePixel = 0
renameInput.ClearTextOnFocus = false
renameInput.PlaceholderText = "Digite o novo nome"
renameInput.PlaceholderColor3 = COLORS.TextDim
renameInput.Text = ""
renameInput.TextColor3 = COLORS.Text
renameInput.TextSize = 16
renameInput.Font = Enum.Font.GothamMedium
renameInput.TextXAlignment = Enum.TextXAlignment.Left
renameInput.ZIndex = 62
renameInput.Parent = renameDialog
addCorner(renameInput, 10)
addStroke(renameInput, COLORS.Stroke, 0.42, 1)
addPadding(renameInput, 0, 16, 0, 16)

local renameHint = createLabel(
	renameDialog,
	"Hint",
	"O nome será filtrado pelo Roblox antes de aparecer para outros jogadores.",
	UDim2.fromOffset(24, 143),
	UDim2.new(1, -112, 0, 34),
	10,
	COLORS.TextMuted,
	Enum.Font.GothamMedium
)
renameHint.TextWrapped = true
renameHint.ZIndex = 62

local renameCounter = createLabel(
	renameDialog,
	"Counter",
	string.format("0/%d", CompanionCatalog.MaxDisplayNameLength),
	UDim2.new(1, -90, 0, 143),
	UDim2.fromOffset(66, 22),
	10,
	COLORS.TextMuted,
	Enum.Font.GothamBold
)
renameCounter.TextXAlignment = Enum.TextXAlignment.Right
renameCounter.ZIndex = 62

local renameCancelButton = createButton(
	renameDialog,
	"Cancel",
	"CANCELAR",
	UDim2.fromOffset(24, 196),
	UDim2.new(0.42, -7, 0, 44),
	COLORS.SurfaceRaised,
	COLORS.TextMuted
)
renameCancelButton.TextSize = 11
renameCancelButton.ZIndex = 62

local renameSaveButton = createButton(
	renameDialog,
	"Save",
	"SALVAR NOME",
	UDim2.new(0.42, 31, 0, 196),
	UDim2.new(0.58, -55, 0, 44),
	COLORS.PrimaryDark,
	COLORS.Text
)
renameSaveButton.TextSize = 11
renameSaveButton.ZIndex = 62
addStroke(renameSaveButton, COLORS.PrimarySoft, 0.58, 1)

local discardBackdrop = Instance.new("TextButton")
discardBackdrop.Name = "DiscardBackdrop"
discardBackdrop.Size = UDim2.fromScale(1, 1)
discardBackdrop.BackgroundColor3 = COLORS.Backdrop
discardBackdrop.BackgroundTransparency = 0.18
discardBackdrop.BorderSizePixel = 0
discardBackdrop.Text = ""
discardBackdrop.AutoButtonColor = false
discardBackdrop.Modal = true
discardBackdrop.Visible = false
discardBackdrop.ZIndex = 70
discardBackdrop.Parent = detailPage

local discardDialog = Instance.new("Frame")
discardDialog.Name = "DiscardDialog"
discardDialog.AnchorPoint = Vector2.new(0.5, 0.5)
discardDialog.Position = UDim2.fromScale(0.5, 0.5)
discardDialog.Size = UDim2.fromOffset(440, 238)
discardDialog.BackgroundColor3 = COLORS.Panel
discardDialog.BorderSizePixel = 0
discardDialog.ZIndex = 71
discardDialog.Parent = discardBackdrop
addCorner(discardDialog, 16)
addStroke(discardDialog, Color3.fromRGB(225, 101, 96), 0.22, 2)

createLabel(
	discardDialog,
	"Title",
	"DESCARTAR COMPANHEIRO?",
	UDim2.fromOffset(24, 20),
	UDim2.new(1, -48, 0, 28),
	18,
	COLORS.Text,
	Enum.Font.GothamBold
).ZIndex = 72

local discardMessage = createLabel(
	discardDialog,
	"Message",
	"",
	UDim2.fromOffset(24, 59),
	UDim2.new(1, -48, 0, 78),
	12,
	COLORS.TextMuted,
	Enum.Font.GothamMedium
)
discardMessage.TextWrapped = true
discardMessage.TextYAlignment = Enum.TextYAlignment.Top
discardMessage.ZIndex = 72

local discardCancelButton = createButton(
	discardDialog,
	"Cancel",
	"CANCELAR",
	UDim2.fromOffset(24, 166),
	UDim2.new(0.42, -7, 0, 46),
	COLORS.SurfaceRaised,
	COLORS.TextMuted
)
discardCancelButton.TextSize = 11
discardCancelButton.ZIndex = 72

local discardConfirmButton = createButton(
	discardDialog,
	"Confirm",
	"SIM, DESCARTAR",
	UDim2.new(0.42, 31, 0, 166),
	UDim2.new(0.58, -55, 0, 46),
	COLORS.DangerDark,
	COLORS.Text
)
discardConfirmButton.TextSize = 11
discardConfirmButton.ZIndex = 72
addStroke(discardConfirmButton, Color3.fromRGB(240, 130, 124), 0.5, 1)

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 28)
toast.Size = UDim2.fromOffset(460, 50)
toast.BackgroundColor3 = Color3.fromRGB(24, 91, 55)
toast.BackgroundTransparency = 0.02
toast.BorderSizePixel = 0
toast.TextColor3 = COLORS.Text
toast.Font = Enum.Font.GothamBold
toast.TextSize = 13
toast.TextWrapped = true
toast.Visible = false
toast.ZIndex = 1100
toast.Parent = gui
addCorner(toast, 12)
addStroke(toast, COLORS.PrimarySoft, 0.5, 1)

local toastSerial = 0
local selectedMonsterId
local currentPage = "Overview"
local currentDetailTab = "Stats"
local isOpen = false
local actionPending = false
local snapshot = {
	Entries = {},
	EquippedCompanions = {},
	MaxEquipped = CompanionCatalog.MaxEquipped,
	MaxLevel = CompanionCatalog.MaxLevel,
	UpgradeOrder = CompanionCatalog.UpgradeOrder,
	UpgradeDefinitions = CompanionCatalog.Upgrades,
}

local function showToast(message, success)
	if type(message) ~= "string" or message == "" then
		return
	end
	toastSerial += 1
	local serial = toastSerial
	toast.BackgroundColor3 = success == false and COLORS.DangerDark or Color3.fromRGB(24, 91, 55)
	toast.Text = message
	toast.Visible = true
	task.delay(3, function()
		if toastSerial == serial then
			toast.Visible = false
		end
	end)
end

local function findEntry(monsterId)
	for _, entry in ipairs(snapshot.Entries) do
		if entry.MonsterId == monsterId then
			return entry
		end
	end
	return nil
end

local function equippedCount()
	local count = 0
	for slot = 1, snapshot.MaxEquipped or CompanionCatalog.MaxEquipped do
		if snapshot.EquippedCompanions[slot] then
			count += 1
		end
	end
	return count
end

local render

local function invoke(action, first, second)
	if actionPending then
		return false
	end
	actionPending = true
	local ok, response = pcall(request.InvokeServer, request, action, first, second)
	actionPending = false
	if ok and response then
		snapshot = response.Snapshot or snapshot
		showToast(response.Message, response.Success)
		return response.Success
	end
	showToast("Não foi possível concluir agora.", false)
	return false
end

local function closeRenameDialog()
	renameInput:ReleaseFocus()
	renameBackdrop.Visible = false
end

local function closeDiscardDialog()
	discardBackdrop.Visible = false
end

local function updateRenameInput()
	local cleanText = string.gsub(renameInput.Text, "%c", "")
	cleanText = truncateUtf8(cleanText, CompanionCatalog.MaxDisplayNameLength)
	if renameInput.Text ~= cleanText then
		renameInput.Text = cleanText
	end
	local length = utf8Length(cleanText)
	renameCounter.Text = string.format("%d/%d", length, CompanionCatalog.MaxDisplayNameLength)
	renameCounter.TextColor3 = length > 0 and COLORS.TextMuted or COLORS.Danger
	local canSave = length > 0 and not actionPending
	renameSaveButton.Active = canSave
	renameSaveButton.AutoButtonColor = canSave
	renameSaveButton.BackgroundColor3 = canSave and COLORS.PrimaryDark or COLORS.SurfaceDisabled
	renameSaveButton.TextColor3 = canSave and COLORS.Text or COLORS.TextMuted
end

local function openRenameDialog()
	local entry = findEntry(selectedMonsterId)
	if not entry or actionPending then
		return
	end
	closeDiscardDialog()
	renameSpecies.Text = "ESPÉCIE • " .. string.upper(entry.SpeciesName or entry.MonsterId)
	renameInput.Text = entry.DisplayName
	renameBackdrop.Visible = true
	updateRenameInput()
	task.defer(function()
		if renameBackdrop.Visible then
			renameInput:CaptureFocus()
			renameInput.CursorPosition = #renameInput.Text + 1
		end
	end)
end

local function openDiscardDialog()
	local entry = findEntry(selectedMonsterId)
	if not entry or actionPending then
		return
	end
	closeRenameDialog()
	local equippedWarning = entry.Equipped
			and "\nEle também será removido da equipe imediatamente."
		or ""
	discardMessage.Text = string.format(
		"Você perderá %s, seu nível, XP e upgrades permanentemente.%s",
		entry.DisplayName,
		equippedWarning
	)
	discardBackdrop.Visible = true
end

local function confirmDiscard()
	local entry = findEntry(selectedMonsterId)
	if not entry or actionPending then
		return
	end
	if invoke("Discard", entry.MonsterId, true) then
		closeDiscardDialog()
		selectedMonsterId = nil
		currentPage = "Overview"
		render()
	end
end

local function submitRename()
	local entry = findEntry(selectedMonsterId)
	if not entry or actionPending then
		return
	end
	local requestedName = string.gsub(renameInput.Text, "%s+", " ")
	requestedName = string.match(requestedName, "^%s*(.-)%s*$") or ""
	if requestedName == "" then
		showToast("Digite um nome para o companheiro.", false)
		updateRenameInput()
		return
	end
	if invoke("Rename", entry.MonsterId, requestedName) then
		closeRenameDialog()
		render()
	else
		updateRenameInput()
	end
end

local function openDetail(monsterId)
	if not findEntry(monsterId) then
		return
	end
	closeRenameDialog()
	closeDiscardDialog()
	selectedMonsterId = monsterId
	currentPage = "Detail"
	currentDetailTab = "Stats"
	render()
end

local function createTeamSlot(slot)
	local monsterId = snapshot.EquippedCompanions[slot]
	local entry = monsterId and findEntry(monsterId)
	local card = Instance.new("TextButton")
	card.Name = "Slot" .. slot
	card.LayoutOrder = slot
	card.BackgroundColor3 = entry and COLORS.SurfaceSelected or Color3.fromRGB(23, 36, 31)
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = entry ~= nil
	card.Active = entry ~= nil
	card.ZIndex = 24
	card.Parent = slots
	addCorner(card, 11)
	addStroke(card, entry and COLORS.Primary or COLORS.Stroke, entry and 0.32 or 0.78, 1)

	createPortrait(card, entry, 58, UDim2.fromOffset(9, 11))

	createLabel(
		card,
		"Slot",
		"SLOT " .. slot,
		UDim2.fromOffset(78, 9),
		UDim2.new(1, -88, 0, 15),
		8,
		entry and COLORS.PrimarySoft or COLORS.TextDim,
		Enum.Font.GothamBold
	)

	local name = createLabel(
		card,
		"Name",
		entry and entry.DisplayName or "VAZIO",
		UDim2.fromOffset(78, 25),
		UDim2.new(1, -88, 0, 20),
		11,
		entry and COLORS.Text or COLORS.TextMuted,
		Enum.Font.GothamBold
	)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	createLabel(
		card,
		"Level",
		entry and string.format("NÍVEL %d", entry.Level) or "EQUIPE PELA COLEÇÃO",
		UDim2.fromOffset(78, 47),
		UDim2.new(1, -88, 0, 16),
		8,
		COLORS.TextMuted,
		Enum.Font.GothamMedium
	)

	if entry then
		local arrow = createLabel(
			card,
			"Arrow",
			">",
			UDim2.new(1, -22, 0, 29),
			UDim2.fromOffset(14, 18),
			14,
			COLORS.PrimarySoft,
			Enum.Font.GothamBold
		)
		arrow.TextXAlignment = Enum.TextXAlignment.Center
		card.Activated:Connect(function()
			openDetail(entry.MonsterId)
		end)
	end
end

local function createCollectionCard(entry, index)
	local card = Instance.new("TextButton")
	card.Name = entry.MonsterId
	card.LayoutOrder = index
	card.BackgroundColor3 = entry.Equipped and COLORS.SurfaceSelected or COLORS.SurfaceRaised
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = true
	card.ZIndex = 24
	card.Parent = collectionList
	addCorner(card, 11)
	addStroke(
		card,
		entry.Equipped and COLORS.Primary or COLORS.Stroke,
		entry.Equipped and 0.32 or 0.7,
		1
	)

	createPortrait(card, entry, 76, UDim2.fromOffset(9, 18))

	local name = createLabel(
		card,
		"Name",
		entry.DisplayName,
		UDim2.fromOffset(96, 13),
		UDim2.new(1, -108, 0, 20),
		11,
		COLORS.Text,
		Enum.Font.GothamBold
	)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local levelText = entry.DisplayName ~= (entry.SpeciesName or entry.DisplayName)
			and string.format("%s • NÍVEL %d", string.upper(entry.SpeciesName), entry.Level)
		or string.format("NÍVEL %d", entry.Level)
	local levelLabel = createLabel(
		card,
		"Level",
		levelText,
		UDim2.fromOffset(96, 35),
		UDim2.new(1, -108, 0, 16),
		9,
		entry.UpgradePoints > 0 and COLORS.Gold or COLORS.PrimarySoft,
		Enum.Font.GothamBold
	)
	levelLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local styleName = STYLE_NAMES[entry.Stats.Style]
		or string.upper(tostring(entry.Stats.Style or "PADRÃO"))
	local style = createLabel(
		card,
		"Style",
		styleName,
		UDim2.fromOffset(96, 53),
		UDim2.new(1, -108, 0, 15),
		8,
		COLORS.TextMuted,
		Enum.Font.GothamMedium
	)
	style.TextTruncate = Enum.TextTruncate.AtEnd

	if entry.Equipped then
		local status = Instance.new("TextLabel")
		status.Name = "Equipped"
		status.Position = UDim2.fromOffset(96, 77)
		status.Size = UDim2.fromOffset(82, 20)
		status.BackgroundColor3 = COLORS.PrimaryDark
		status.BorderSizePixel = 0
		status.Text = string.format("SLOT %d", entry.Slot or 1)
		status.TextColor3 = COLORS.Text
		status.Font = Enum.Font.GothamBold
		status.TextSize = 8
		status.Parent = card
		addCorner(status, 99)
	elseif entry.UpgradePoints > 0 then
		local points = Instance.new("TextLabel")
		points.Name = "Points"
		points.Position = UDim2.fromOffset(96, 77)
		points.Size = UDim2.fromOffset(92, 20)
		points.BackgroundColor3 = Color3.fromRGB(79, 68, 30)
		points.BorderSizePixel = 0
		points.Text = string.format("%d PTS LIVRES", entry.UpgradePoints)
		points.TextColor3 = COLORS.Gold
		points.Font = Enum.Font.GothamBold
		points.TextSize = 8
		points.Parent = card
		addCorner(points, 99)
	end

	local arrow = createLabel(
		card,
		"Arrow",
		">",
		UDim2.new(1, -25, 0.5, -10),
		UDim2.fromOffset(16, 20),
		15,
		COLORS.PrimarySoft,
		Enum.Font.GothamBold
	)
	arrow.TextXAlignment = Enum.TextXAlignment.Center

	card.Activated:Connect(function()
		openDetail(entry.MonsterId)
	end)
end

local function renderOverview()
	clearGuiObjects(slots)
	clearGuiObjects(collectionList)

	local maxEquipped = snapshot.MaxEquipped or CompanionCatalog.MaxEquipped
	local active = equippedCount()
	teamCount.Text = string.format("%d DE %d", active, maxEquipped)
	collectionCount.Text = string.format("%d DESBLOQUEADOS", #snapshot.Entries)
	collectionEmpty.Visible = #snapshot.Entries == 0
	collectionList.Visible = #snapshot.Entries > 0

	for slot = 1, maxEquipped do
		createTeamSlot(slot)
	end

	if #snapshot.Entries == 0 then
		return
	end

	for index, entry in ipairs(snapshot.Entries) do
		createCollectionCard(entry, index)
	end
end

local function createStatCard(parent, definition, entry, order)
	local card = Instance.new("Frame")
	card.Name = definition.Key
	card.LayoutOrder = order
	card.Size = UDim2.new(0.5, -6, 0, 92)
	card.BackgroundColor3 = COLORS.SurfaceRaised
	card.BorderSizePixel = 0
	card.Parent = parent
	addCorner(card, 11)
	addStroke(card, COLORS.Stroke, 0.78, 1)

	createLabel(
		card,
		"Label",
		definition.Label,
		UDim2.fromOffset(13, 9),
		UDim2.new(1, -26, 0, 18),
		9,
		COLORS.TextMuted,
		Enum.Font.GothamBold
	)

	createLabel(
		card,
		"Value",
		definition.Format(entry.Stats[definition.Key] or 0),
		UDim2.fromOffset(13, 28),
		UDim2.new(1, -26, 0, 30),
		21,
		COLORS.Text,
		Enum.Font.GothamBold
	)

	createLabel(
		card,
		"Description",
		definition.Description,
		UDim2.fromOffset(13, 63),
		UDim2.new(1, -26, 0, 18),
		8,
		COLORS.TextMuted,
		Enum.Font.Gotham
	)
end

local function renderStatsTab(entry)
	clearGuiObjects(statsTab)

	createLabel(
		statsTab,
		"Title",
		"ESTATÍSTICAS ATUAIS",
		UDim2.fromOffset(4, 0),
		UDim2.new(1, -8, 0, 24),
		11,
		COLORS.PrimarySoft,
		Enum.Font.GothamBold
	)

	local grid = Instance.new("Frame")
	grid.Name = "StatsGrid"
	grid.Position = UDim2.fromOffset(4, 34)
	grid.Size = UDim2.new(1, -8, 0, 196)
	grid.BackgroundTransparency = 1
	grid.Parent = statsTab

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -6, 0, 92)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.FillDirectionMaxCells = 2
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for index, definition in ipairs(STAT_DEFINITIONS) do
		createStatCard(grid, definition, entry, index)
	end

	local progressCard = Instance.new("Frame")
	progressCard.Name = "ProgressSummary"
	progressCard.Position = UDim2.fromOffset(4, 244)
	progressCard.Size = UDim2.new(1, -8, 0, 95)
	progressCard.BackgroundColor3 = COLORS.SurfaceRaised
	progressCard.BorderSizePixel = 0
	progressCard.Parent = statsTab
	addCorner(progressCard, 11)

	createLabel(
		progressCard,
		"Title",
		"PROGRESSÃO",
		UDim2.fromOffset(14, 8),
		UDim2.new(1, -28, 0, 18),
		9,
		COLORS.TextMuted,
		Enum.Font.GothamBold
	)

	local spent = CompanionCatalog.SpentPoints(entry.Upgrades)
	createLabel(
		progressCard,
		"Summary",
		string.format(
			"Nível %d de %d  •  %d pontos aplicados  •  %d disponíveis",
			entry.Level,
			snapshot.MaxLevel or CompanionCatalog.MaxLevel,
			spent,
			entry.UpgradePoints
		),
		UDim2.fromOffset(14, 30),
		UDim2.new(1, -28, 0, 22),
		11,
		COLORS.Text,
		Enum.Font.GothamBold
	)

	local levelProgress = entry.Level / math.max(1, snapshot.MaxLevel or CompanionCatalog.MaxLevel)
	createProgressBar(
		progressCard,
		"LevelProgress",
		UDim2.fromOffset(14, 61),
		UDim2.new(1, -28, 0, 9),
		levelProgress,
		entry.Level >= (snapshot.MaxLevel or CompanionCatalog.MaxLevel) and COLORS.Gold or COLORS.Primary
	)

	createLabel(
		statsTab,
		"UpgradeHint",
		entry.UpgradePoints > 0
				and string.format(
					"Você tem %d %s para distribuir. Abra a aba UPGRADES.",
					entry.UpgradePoints,
					entry.UpgradePoints == 1 and "ponto" or "pontos"
				)
			or "Ganhe níveis para receber novos pontos de atributo.",
		UDim2.fromOffset(4, 352),
		UDim2.new(1, -8, 0, 42),
		11,
		entry.UpgradePoints > 0 and COLORS.Gold or COLORS.TextMuted,
		Enum.Font.GothamMedium
	).TextWrapped = true
end

local function renderUpgradesTab(entry)
	clearGuiObjects(upgradesTab)

	local summary = Instance.new("Frame")
	summary.Name = "PointsSummary"
	summary.Position = UDim2.fromOffset(4, 0)
	summary.Size = UDim2.new(1, -8, 0, 72)
	summary.BackgroundColor3 = entry.UpgradePoints > 0
			and Color3.fromRGB(69, 59, 27)
		or COLORS.SurfaceRaised
	summary.BorderSizePixel = 0
	summary.Parent = upgradesTab
	addCorner(summary, 11)
	addStroke(summary, entry.UpgradePoints > 0 and COLORS.Gold or COLORS.Stroke, 0.66, 1)

	createLabel(
		summary,
		"Title",
		"PONTOS DISPONÍVEIS",
		UDim2.fromOffset(14, 9),
		UDim2.new(1, -118, 0, 18),
		9,
		entry.UpgradePoints > 0 and COLORS.Gold or COLORS.TextMuted,
		Enum.Font.GothamBold
	)

	createLabel(
		summary,
		"Description",
		"Cada nível concede 1 ponto. Escolha com cuidado: o gasto é permanente.",
		UDim2.fromOffset(14, 30),
		UDim2.new(1, -115, 0, 28),
		9,
		COLORS.TextMuted,
		Enum.Font.Gotham
	).TextWrapped = true

	local pointsValue = createLabel(
		summary,
		"Value",
		tostring(entry.UpgradePoints),
		UDim2.new(1, -96, 0, 7),
		UDim2.fromOffset(78, 54),
		26,
		entry.UpgradePoints > 0 and COLORS.Gold or COLORS.TextMuted,
		Enum.Font.GothamBold
	)
	pointsValue.TextXAlignment = Enum.TextXAlignment.Center

	local order = snapshot.UpgradeOrder or CompanionCatalog.UpgradeOrder
	local definitions = snapshot.UpgradeDefinitions or CompanionCatalog.Upgrades
	for index, statName in ipairs(order) do
		local definition = definitions[statName]
		local points = entry.Upgrades[statName] or 0
		local canUpgrade = entry.UpgradePoints > 0 and points < definition.MaxPoints

		local row = Instance.new("Frame")
		row.Name = statName
		row.Position = UDim2.fromOffset(4, 84 + (index - 1) * 87)
		row.Size = UDim2.new(1, -8, 0, 76)
		row.BackgroundColor3 = COLORS.SurfaceRaised
		row.BorderSizePixel = 0
		row.Parent = upgradesTab
		addCorner(row, 11)
		addStroke(row, canUpgrade and COLORS.Primary or COLORS.Stroke, canUpgrade and 0.68 or 0.8, 1)

		createLabel(
			row,
			"Name",
			definition.DisplayName,
			UDim2.fromOffset(13, 8),
			UDim2.new(1, -190, 0, 20),
			11,
			COLORS.Text,
			Enum.Font.GothamBold
		)

		createLabel(
			row,
			"Description",
			definition.Description,
			UDim2.fromOffset(13, 30),
			UDim2.new(1, -190, 0, 17),
			9,
			COLORS.TextMuted,
			Enum.Font.Gotham
		)

		createProgressBar(
			row,
			"Progress",
			UDim2.fromOffset(13, 56),
			UDim2.new(1, -192, 0, 7),
			points / math.max(1, definition.MaxPoints),
			points >= definition.MaxPoints and COLORS.Gold or COLORS.Primary
		)

		local progressText = createLabel(
			row,
			"ProgressText",
			string.format("%d / %d", points, definition.MaxPoints),
			UDim2.new(1, -172, 0, 8),
			UDim2.fromOffset(70, 20),
			10,
			points >= definition.MaxPoints and COLORS.Gold or COLORS.PrimarySoft,
			Enum.Font.GothamBold
		)
		progressText.TextXAlignment = Enum.TextXAlignment.Center

		local addPoint = createButton(
			row,
			"AddPoint",
			points >= definition.MaxPoints and "MÁXIMO" or "+1 PONTO",
			UDim2.new(1, -94, 0, 18),
			UDim2.fromOffset(82, 40),
			canUpgrade and COLORS.PrimaryDark or COLORS.SurfaceDisabled,
			canUpgrade and COLORS.Text or COLORS.TextMuted
		)
		addPoint.Active = canUpgrade
		addPoint.AutoButtonColor = canUpgrade

		if canUpgrade then
			addPoint.Activated:Connect(function()
				if invoke("Upgrade", entry.MonsterId, statName) then
					render()
				end
			end)
		end
	end
end

local function updateDetailTabs()
	local showStats = currentDetailTab == "Stats"
	statsTab.Visible = showStats
	upgradesTab.Visible = not showStats
	statsTabButton.BackgroundColor3 = showStats and COLORS.PrimaryDark or COLORS.SurfaceRaised
	statsTabButton.TextColor3 = showStats and COLORS.Text or COLORS.TextMuted
	upgradesTabButton.BackgroundColor3 = showStats and COLORS.SurfaceRaised or COLORS.PrimaryDark
	upgradesTabButton.TextColor3 = showStats and COLORS.TextMuted or COLORS.Text
end

local function renderDetail()
	local entry = findEntry(selectedMonsterId)
	if not entry then
		currentPage = "Overview"
		selectedMonsterId = nil
		return
	end

	clearGuiObjects(portraitHost)
	clearGuiObjects(xpBarHost)
	createPortrait(portraitHost, entry, 200, UDim2.fromOffset(0, 0))

	detailName.Text = entry.DisplayName
	local styleName = STYLE_NAMES[entry.Stats.Style]
		or string.upper(tostring(entry.Stats.Style or "PADRÃO"))
	detailStyle.Text = string.format(
		"%s • %s",
		string.upper(entry.SpeciesName or entry.MonsterId),
		styleName
	)
	detailStyle.TextTruncate = Enum.TextTruncate.AtEnd
	detailStatus.Text = entry.Equipped
			and string.format("EQUIPADO • SLOT %d", entry.Slot or 1)
		or "FORA DA EQUIPE"
	detailStatus.BackgroundColor3 = entry.Equipped and COLORS.PrimaryDark or COLORS.SurfaceDisabled
	detailStatus.TextColor3 = entry.Equipped and COLORS.Text or COLORS.TextMuted
	detailLevel.Text = string.format("NÍVEL %d", entry.Level)
	victoriesValue.Text = tostring(entry.Kills)

	if entry.XPRequired > 0 then
		detailXP.Text = string.format("%d / %d XP", entry.XP, entry.XPRequired)
		createProgressBar(
			xpBarHost,
			"XP",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			entry.XP / math.max(1, entry.XPRequired),
			COLORS.Primary
		)
	else
		detailXP.Text = "NÍVEL MÁXIMO"
		createProgressBar(
			xpBarHost,
			"XP",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			1,
			COLORS.Gold
		)
	end

	local teamFull = equippedCount() >= (snapshot.MaxEquipped or CompanionCatalog.MaxEquipped)
	local canEquip = entry.Equipped or not teamFull
	equipButton.Text = entry.Equipped
			and "DESEQUIPAR"
		or (teamFull and "EQUIPE CHEIA" or "EQUIPAR COMPANHEIRO")
	equipButton.BackgroundColor3 = entry.Equipped
			and COLORS.DangerDark
		or (canEquip and COLORS.PrimaryDark or COLORS.SurfaceDisabled)
	equipButton.TextColor3 = canEquip and COLORS.Text or COLORS.TextMuted
	equipButton.Active = canEquip
	equipButton.AutoButtonColor = canEquip

	renderStatsTab(entry)
	renderUpgradesTab(entry)
	updateDetailTabs()
end

render = function()
	if currentPage == "Detail" and not findEntry(selectedMonsterId) then
		currentPage = "Overview"
		selectedMonsterId = nil
	end

	local active = equippedCount()
	openCounter.Text = tostring(active)
	openCounter.Visible = active > 0

	local inDetail = currentPage == "Detail"
	overviewPage.Visible = not inDetail
	detailPage.Visible = inDetail
	backButton.Visible = inDetail
	headerAccent.Visible = not inDetail
	headerTitle.Position = inDetail and UDim2.fromOffset(154, 12) or UDim2.fromOffset(38, 12)
	headerSubtitle.Position = inDetail and UDim2.fromOffset(154, 40) or UDim2.fromOffset(38, 40)
	headerTitle.Size = inDetail and UDim2.new(1, -230, 0, 27) or UDim2.new(1, -150, 0, 27)
	headerSubtitle.Size = inDetail and UDim2.new(1, -230, 0, 19) or UDim2.new(1, -150, 0, 19)

	if inDetail then
		local entry = findEntry(selectedMonsterId)
		headerTitle.Text = entry and string.upper(entry.DisplayName) or "COMPANHEIRO"
		headerSubtitle.Text = "Informações, atributos, evolução e gerenciamento da equipe."
		renderDetail()
	else
		headerTitle.Text = "EQUIPE DE COMPANHEIROS"
		headerSubtitle.Text = "Selecione um companheiro para abrir sua página completa."
		renderOverview()
	end
end

local function refresh()
	local ok, response = pcall(request.InvokeServer, request, "Get")
	if ok and response and response.Snapshot then
		snapshot = response.Snapshot
		render()
	end
end

local function setOpen(open)
	isOpen = open
	closeRenameDialog()
	closeDiscardDialog()
	panel.Visible = open
	backdrop.Visible = open
	openButton.Visible = not open
	if open then
		currentPage = "Overview"
		selectedMonsterId = nil
		currentDetailTab = "Stats"
		refresh()
	end
end

openButton.Activated:Connect(function()
	setOpen(true)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

backButton.Activated:Connect(function()
	closeRenameDialog()
	closeDiscardDialog()
	currentPage = "Overview"
	selectedMonsterId = nil
	render()
end)

backdrop.Activated:Connect(function()
	setOpen(false)
end)

statsTabButton.Activated:Connect(function()
	currentDetailTab = "Stats"
	updateDetailTabs()
end)

upgradesTabButton.Activated:Connect(function()
	currentDetailTab = "Upgrades"
	updateDetailTabs()
end)

renameButton.Activated:Connect(openRenameDialog)
renameCancelButton.Activated:Connect(closeRenameDialog)
renameBackdrop.Activated:Connect(closeRenameDialog)
renameSaveButton.Activated:Connect(submitRename)
discardButton.Activated:Connect(openDiscardDialog)
discardCancelButton.Activated:Connect(closeDiscardDialog)
discardBackdrop.Activated:Connect(closeDiscardDialog)
discardConfirmButton.Activated:Connect(confirmDiscard)
renameInput:GetPropertyChangedSignal("Text"):Connect(updateRenameInput)
renameInput.FocusLost:Connect(function(enterPressed)
	if enterPressed and renameBackdrop.Visible then
		submitRename()
	end
end)

equipButton.Activated:Connect(function()
	local entry = findEntry(selectedMonsterId)
	if not entry or actionPending then
		return
	end
	local teamFull = equippedCount() >= (snapshot.MaxEquipped or CompanionCatalog.MaxEquipped)
	if not entry.Equipped and teamFull then
		showToast("Sua equipe já possui o máximo de companheiros.", false)
		return
	end
	if invoke("SetEquipped", entry.MonsterId, not entry.Equipped) then
		render()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not isOpen or input.KeyCode ~= Enum.KeyCode.Escape then
		return
	end
	if discardBackdrop.Visible then
		closeDiscardDialog()
	elseif renameBackdrop.Visible then
		closeRenameDialog()
	elseif currentPage == "Detail" then
		currentPage = "Overview"
		selectedMonsterId = nil
		render()
	else
		setOpen(false)
	end
end)

event.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Snapshot then
		snapshot = payload.Snapshot
		render()
	end
	showToast(payload.Message, payload.Success)
end)

refresh()
