-- HUD especial: Estilo D — Cristal Celestial
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")
local uiFolder = playerScripts:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("DungeonUITheme"))
local Components = require(uiFolder:WaitForChild("DungeonUIComponents"))
local Router = require(uiFolder:WaitForChild("DungeonUIRouter"))
local ModalManager = require(uiFolder:WaitForChild("DungeonUIModalManager"))
local Colors = Theme.Colors

local existing = playerGui:FindFirstChild("DungeonUnifiedHUD")
if existing then
	existing:Destroy()
end

local disabledCount, suppressedCount = Router.Bind(playerScripts, playerGui)
player:SetAttribute("DungeonUIRouterReady", true)
player:SetAttribute("DungeonUIRouterVersion", Router.Version)
player:SetAttribute("DungeonUIRouterPolicy", Router.Policy)
player:SetAttribute("DungeonClientLegacyScriptsDisabled", disabledCount)
player:SetAttribute("DungeonClientLegacyGuisSuppressed", suppressedCount)

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonUnifiedHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 48
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui:SetAttribute("StyleId", Theme.StyleId)
gui:SetAttribute("StyleName", Theme.StyleName)
gui:SetAttribute("StyleVersion", Theme.Version)
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui

local responsiveGroups = {}
local function trackScale(panel)
	local scale = Components.Scale(panel)
	table.insert(responsiveGroups, { Panel = panel, Scale = scale })
	return scale
end

local function line(parent, position, size, color, transparency)
	local value = Instance.new("Frame")
	value.Position = position
	value.Size = size
	value.BackgroundColor3 = color or Colors.Gold
	value.BackgroundTransparency = transparency or 0.4
	value.BorderSizePixel = 0
	value.ZIndex = parent.ZIndex + 1
	value.Parent = parent
	return value
end

local currencies = Instance.new("Frame")
currencies.Name = "Currencies"
currencies.BackgroundTransparency = 1
currencies.Position = UDim2.fromOffset(22, 20)
currencies.Size = UDim2.fromOffset(310, 170)
currencies.Parent = root
trackScale(currencies)

local function currencyCard(name, y, glyph, glyphColor, titleText)
	local card = Components.GlassPanel(currencies, name, UDim2.fromOffset(0, y), UDim2.fromOffset(300, 74), {
		Radius = 15,
		Transparency = 0.10,
	})
	Components.Diamond(card, "Icon", UDim2.fromOffset(10, 8), UDim2.fromOffset(58, 58), glyphColor, {
		StrokeColor = Colors.GoldSoft,
	})
	local glyphLabel = Components.Label(card, "Glyph", glyph, UDim2.fromOffset(10, 8), UDim2.fromOffset(58, 58), {
		TextSize = 23,
		Font = Enum.Font.GothamBlack,
		Color = Colors.Text,
		XAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8,
	})
	glyphLabel.TextStrokeColor3 = Colors.GlassDeep
	glyphLabel.TextStrokeTransparency = 0.35
	Components.Label(card, "Title", titleText, UDim2.fromOffset(78, 8), UDim2.new(1, -91, 0, 24), {
		TextSize = 13,
		Color = Colors.CyanSoft,
		Font = Enum.Font.GothamMedium,
	})
	local amount = Components.Label(card, "Amount", "0", UDim2.fromOffset(78, 29), UDim2.new(1, -91, 0, 35), {
		TextSize = 25,
		Color = Colors.Text,
		Font = Enum.Font.GothamBold,
	})
	return card, amount
end

local confirmedCard, confirmedCoinsLabel = currencyCard(
	"ConfirmedCoins",
	0,
	"◆",
	Colors.Warning,
	"MOEDAS CONFIRMADAS"
)
local pendingCard, pendingCoinsLabel = currencyCard(
	"PendingCoins",
	88,
	"✦",
	Colors.Purple,
	"MOEDAS PENDENTES"
)

local objectivePanel = Components.GlassPanel(root, "Objective", UDim2.new(0.5, 0, 0, 20), UDim2.fromOffset(800, 108), {
	AnchorPoint = Vector2.new(0.5, 0),
	Radius = 18,
	Transparency = 0.08,
})
trackScale(objectivePanel)

local roundCaption = Components.Label(objectivePanel, "RoundCaption", "RODADA", UDim2.fromOffset(22, 8), UDim2.fromOffset(95, 20), {
	TextSize = 11,
	Color = Colors.Muted,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
local roundValue = Components.Label(objectivePanel, "RoundValue", "1/3", UDim2.fromOffset(22, 28), UDim2.fromOffset(95, 43), {
	TextSize = 28,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
line(objectivePanel, UDim2.fromOffset(128, 13), UDim2.fromOffset(1, 70), Colors.Gold, 0.55)
local islandCaption = Components.Label(objectivePanel, "IslandCaption", "ILHA", UDim2.fromOffset(140, 8), UDim2.fromOffset(85, 20), {
	TextSize = 11,
	Color = Colors.Muted,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
local islandValue = Components.Label(objectivePanel, "IslandValue", "1", UDim2.fromOffset(140, 28), UDim2.fromOffset(85, 43), {
	TextSize = 28,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
line(objectivePanel, UDim2.fromOffset(236, 13), UDim2.fromOffset(1, 70), Colors.Gold, 0.55)
local objectiveTitle = Components.Label(objectivePanel, "Title", "PREPARANDO EXPEDIÇÃO", UDim2.fromOffset(252, 8), UDim2.fromOffset(410, 27), {
	TextSize = 17,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
local objectiveDetail = Components.Label(objectivePanel, "Detail", "Aguarde a rota ser preparada.", UDim2.fromOffset(252, 34), UDim2.fromOffset(410, 20), {
	TextSize = 11,
	Color = Colors.Muted,
	XAlignment = Enum.TextXAlignment.Center,
})
local objectiveBar = Components.Bar(objectivePanel, "Progress", UDim2.fromOffset(270, 62), UDim2.fromOffset(374, 13), Colors.Cyan, {
	Radius = 6,
})
local objectiveProgress = Components.Label(objectivePanel, "ProgressText", "0 / 1", UDim2.fromOffset(252, 78), UDim2.fromOffset(410, 19), {
	TextSize = 11,
	Color = Colors.CyanSoft,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
line(objectivePanel, UDim2.fromOffset(674, 13), UDim2.fromOffset(1, 70), Colors.Gold, 0.55)
Components.Diamond(objectivePanel, "WaypointIcon", UDim2.fromOffset(692, 11), UDim2.fromOffset(58, 58), Colors.Cyan, {
	StrokeColor = Colors.GoldSoft,
})
local waypointDistanceTop = Components.Label(objectivePanel, "WaypointDistance", "--m", UDim2.fromOffset(686, 69), UDim2.fromOffset(72, 26), {
	TextSize = 15,
	Color = Colors.Text,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})

local partyPanel = Components.GlassPanel(root, "Party", UDim2.new(1, -22, 0, 20), UDim2.fromOffset(310, 286), {
	AnchorPoint = Vector2.new(1, 0),
	Radius = 18,
	Transparency = 0.08,
})
trackScale(partyPanel)
Components.Label(partyPanel, "Header", "EQUIPE", UDim2.fromOffset(18, 7), UDim2.new(1, -36, 0, 34), {
	TextSize = 19,
	Color = Colors.GoldSoft,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
line(partyPanel, UDim2.fromOffset(18, 45), UDim2.new(1, -36, 0, 1), Colors.Gold, 0.55)

local partyRows = {}
for index = 1, 4 do
	local row = Instance.new("Frame")
	row.Name = "Member" .. index
	row.Position = UDim2.fromOffset(14, 51 + (index - 1) * 56)
	row.Size = UDim2.new(1, -28, 0, 52)
	row.BackgroundColor3 = Colors.GlassDeep
	row.BackgroundTransparency = 0.42
	row.BorderSizePixel = 0
	row.Visible = false
	row.ZIndex = partyPanel.ZIndex + 1
	row.Parent = partyPanel
	Components.Corner(row, 10)
	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Position = UDim2.fromOffset(5, 5)
	portrait.Size = UDim2.fromOffset(42, 42)
	portrait.BackgroundColor3 = Colors.GlassRaised
	portrait.BorderSizePixel = 0
	portrait.ZIndex = row.ZIndex + 1
	portrait.Parent = row
	Components.Corner(portrait, 21)
	Components.Stroke(portrait, Colors.Gold, 0.18, 1.3)
	local initial = Components.Label(portrait, "Initial", "?", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
		TextSize = 17,
		Font = Enum.Font.GothamBlack,
		Color = Colors.CyanSoft,
		XAlignment = Enum.TextXAlignment.Center,
		ZIndex = portrait.ZIndex + 2,
	})
	local crown = Components.Label(row, "Leader", "♛", UDim2.fromOffset(49, 4), UDim2.fromOffset(20, 18), {
		TextSize = 13,
		Color = Colors.Gold,
		Font = Enum.Font.GothamBold,
		Visible = false,
	})
	crown.Visible = false
	local nameLabel = Components.Label(row, "Name", "Jogador", UDim2.fromOffset(52, 3), UDim2.new(1, -104, 0, 22), {
		TextSize = 12,
		Font = Enum.Font.GothamBold,
	})
	local stateLabel = Components.Label(row, "State", "ATIVO", UDim2.new(1, -54, 0, 3), UDim2.fromOffset(48, 20), {
		TextSize = 9,
		Color = Colors.Success,
		Font = Enum.Font.GothamBold,
		XAlignment = Enum.TextXAlignment.Right,
	})
	local health = Components.Bar(row, "Health", UDim2.fromOffset(54, 30), UDim2.new(1, -112, 0, 10), Colors.Success, {
		Radius = 4,
		StrokeTransparency = 0.5,
	})
	local percent = Components.Label(row, "Percent", "100%", UDim2.new(1, -55, 0, 25), UDim2.fromOffset(50, 20), {
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		XAlignment = Enum.TextXAlignment.Right,
	})
	partyRows[index] = {
		Frame = row,
		Initial = initial,
		Leader = crown,
		Name = nameLabel,
		State = stateLabel,
		Health = health,
		Percent = percent,
	}
end

local vitalsPanel = Components.GlassPanel(root, "Vitals", UDim2.new(0, 22, 1, -18), UDim2.fromOffset(500, 156), {
	AnchorPoint = Vector2.new(0, 1),
	Radius = 20,
	Transparency = 0.06,
})
trackScale(vitalsPanel)
Components.Diamond(vitalsPanel, "CrystalEmblem", UDim2.fromOffset(-16, 6), UDim2.fromOffset(142, 142), Colors.Cyan, {
	StrokeColor = Colors.GoldSoft,
	StrokeThickness = 2.3,
})
local emblemGlyph = Components.Label(vitalsPanel, "EmblemGlyph", "✦", UDim2.fromOffset(-16, 6), UDim2.fromOffset(142, 142), {
	TextSize = 48,
	Font = Enum.Font.GothamBlack,
	Color = Colors.CyanSoft,
	XAlignment = Enum.TextXAlignment.Center,
	ZIndex = 10,
})
local healthTitle = Components.Label(vitalsPanel, "HealthTitle", "VIDA", UDim2.fromOffset(130, 18), UDim2.fromOffset(150, 22), {
	TextSize = 14,
	Font = Enum.Font.GothamBold,
})
local healthValue = Components.Label(vitalsPanel, "HealthValue", "100 / 100", UDim2.new(1, -190, 0, 18), UDim2.fromOffset(172, 22), {
	TextSize = 13,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Right,
})
local healthBar = Components.Bar(vitalsPanel, "Health", UDim2.fromOffset(130, 44), UDim2.new(1, -154, 0, 14), Colors.Health, {
	Radius = 6,
	LagColor = Colors.HealthLag,
})
local staminaTitle = Components.Label(vitalsPanel, "StaminaTitle", "STAMINA", UDim2.fromOffset(130, 70), UDim2.fromOffset(150, 22), {
	TextSize = 14,
	Font = Enum.Font.GothamBold,
})
local staminaValue = Components.Label(vitalsPanel, "StaminaValue", "100 / 100", UDim2.new(1, -190, 0, 70), UDim2.fromOffset(172, 22), {
	TextSize = 13,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Right,
})
local staminaBar = Components.Bar(vitalsPanel, "Stamina", UDim2.fromOffset(130, 96), UDim2.new(1, -154, 0, 14), Colors.Stamina, {
	Radius = 6,
})

local buffHolder = Instance.new("Frame")
buffHolder.Name = "Buffs"
buffHolder.Position = UDim2.fromOffset(130, 116)
buffHolder.Size = UDim2.new(1, -154, 0, 34)
buffHolder.BackgroundTransparency = 1
buffHolder.Parent = vitalsPanel
local buffLayout = Instance.new("UIListLayout")
buffLayout.FillDirection = Enum.FillDirection.Horizontal
buffLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
buffLayout.VerticalAlignment = Enum.VerticalAlignment.Center
buffLayout.Padding = UDim.new(0, 8)
buffLayout.Parent = buffHolder
local buffCards = {}
for index = 1, 4 do
	local card = Instance.new("Frame")
	card.Name = "Buff" .. index
	card.Size = UDim2.fromOffset(76, 32)
	card.BackgroundColor3 = Colors.GlassDeep
	card.BackgroundTransparency = 0.28
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = buffHolder
	Components.Corner(card, 9)
	Components.Stroke(card, Colors.Cyan, 0.45, 1)
	local glyph = Components.Label(card, "Glyph", "✦", UDim2.fromOffset(4, 0), UDim2.fromOffset(25, 32), {
		TextSize = 16,
		Color = Colors.CyanSoft,
		Font = Enum.Font.GothamBold,
		XAlignment = Enum.TextXAlignment.Center,
	})
	local timer = Components.Label(card, "Timer", "0s", UDim2.fromOffset(29, 0), UDim2.new(1, -33, 1, 0), {
		TextSize = 10,
		Color = Colors.Text,
		Font = Enum.Font.GothamBold,
		XAlignment = Enum.TextXAlignment.Center,
	})
	buffCards[index] = { Card = card, Glyph = glyph, Timer = timer }
end

local hotbarPanel = Components.GlassPanel(root, "Hotbar", UDim2.new(0.5, 0, 1, -18), UDim2.fromOffset(590, 134), {
	AnchorPoint = Vector2.new(0.5, 1),
	Radius = 20,
	Transparency = 0.06,
})
trackScale(hotbarPanel)
Components.Label(hotbarPanel, "Header", "ATALHOS", UDim2.fromOffset(18, 4), UDim2.new(1, -36, 0, 28), {
	TextSize = 17,
	Color = Colors.GoldSoft,
	Font = Enum.Font.GothamBold,
	XAlignment = Enum.TextXAlignment.Center,
})
local slotsHolder = Instance.new("Frame")
slotsHolder.Name = "Slots"
slotsHolder.Position = UDim2.fromOffset(15, 36)
slotsHolder.Size = UDim2.new(1, -30, 1, -48)
slotsHolder.BackgroundTransparency = 1
slotsHolder.Parent = hotbarPanel
local slotsLayout = Instance.new("UIListLayout")
slotsLayout.FillDirection = Enum.FillDirection.Horizontal
slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
slotsLayout.Padding = UDim.new(0, 8)
slotsLayout.Parent = slotsHolder

local hotbarSlots = {}
for index = 1, 5 do
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.Size = UDim2.fromOffset(96, 82)
	button.BackgroundColor3 = Colors.GlassDeep
	button.BackgroundTransparency = 0.20
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.ZIndex = hotbarPanel.ZIndex + 1
	button.Parent = slotsHolder
	Components.Corner(button, 12)
	local stroke = Components.Stroke(button, index == 1 and Colors.GoldSoft or Colors.Crystal, index == 1 and 0.05 or 0.50, index == 1 and 2 or 1)
	local number = Components.Label(button, "Number", tostring(index), UDim2.fromOffset(6, 3), UDim2.fromOffset(20, 18), {
		TextSize = 10,
		Color = Colors.Muted,
		Font = Enum.Font.GothamBold,
	})
	local glyph = Components.Label(button, "Glyph", index == 1 and "⚔" or "", UDim2.fromOffset(8, 17), UDim2.new(1, -16, 0, 45), {
		TextSize = index == 1 and 32 or 26,
		Color = index == 1 and Colors.CyanSoft or Colors.Text,
		Font = Enum.Font.GothamBold,
		XAlignment = Enum.TextXAlignment.Center,
	})
	local amount = Components.Label(button, "Amount", "", UDim2.new(0, 6, 1, -24), UDim2.new(1, -12, 0, 20), {
		TextSize = 11,
		Color = Colors.Text,
		Font = Enum.Font.GothamBold,
		XAlignment = Enum.TextXAlignment.Right,
	})
	hotbarSlots[index] = { Button = button, Stroke = stroke, Number = number, Glyph = glyph, Amount = amount }
end
hotbarSlots[5].Glyph.Text = "▣"
hotbarSlots[5].Glyph.TextColor3 = Colors.GoldSoft
hotbarSlots[5].Amount.Text = "ITENS"

local notificationPanel = Components.GlassPanel(root, "Notification", UDim2.new(1, -22, 1, -18), UDim2.fromOffset(430, 96), {
	AnchorPoint = Vector2.new(1, 1),
	Radius = 18,
	Transparency = 0.06,
	Visible = false,
})
trackScale(notificationPanel)
Components.Diamond(notificationPanel, "Icon", UDim2.fromOffset(10, 11), UDim2.fromOffset(72, 72), Colors.Cyan, {
	StrokeColor = Colors.GoldSoft,
})
local notificationGlyph = Components.Label(notificationPanel, "Glyph", "✦", UDim2.fromOffset(10, 11), UDim2.fromOffset(72, 72), {
	TextSize = 25,
	Color = Colors.CyanSoft,
	Font = Enum.Font.GothamBlack,
	XAlignment = Enum.TextXAlignment.Center,
	ZIndex = 10,
})
local notificationTitle = Components.Label(notificationPanel, "Title", "RECOMPENSA COLETADA", UDim2.fromOffset(92, 16), UDim2.new(1, -108, 0, 28), {
	TextSize = 15,
	Color = Colors.Text,
	Font = Enum.Font.GothamBold,
})
local notificationDetail = Components.Label(notificationPanel, "Detail", "+0 moedas", UDim2.fromOffset(92, 44), UDim2.new(1, -108, 0, 31), {
	TextSize = 13,
	Color = Colors.CyanSoft,
	Font = Enum.Font.GothamMedium,
	TextWrapped = true,
})

local stateBanner = Components.GlassPanel(root, "StateBanner", UDim2.fromScale(0.5, 0.52), UDim2.fromOffset(500, 108), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Radius = 20,
	Transparency = 0.03,
	Visible = false,
	StrokeColor = Colors.Danger,
})
trackScale(stateBanner)
local stateTitle = Components.Label(stateBanner, "Title", "DERRUBADO", UDim2.fromOffset(18, 14), UDim2.new(1, -36, 0, 38), {
	TextSize = 25,
	Color = Colors.Danger,
	Font = Enum.Font.GothamBlack,
	XAlignment = Enum.TextXAlignment.Center,
})
local stateDetail = Components.Label(stateBanner, "Detail", "Um aliado pode reviver você.", UDim2.fromOffset(18, 56), UDim2.new(1, -36, 0, 34), {
	TextSize = 13,
	Color = Colors.Text,
	TextWrapped = true,
	XAlignment = Enum.TextXAlignment.Center,
})

local waypointArrow = Components.GlassPanel(root, "WaypointArrow", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(58, 58), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Radius = 29,
	Transparency = 0.18,
	Visible = false,
	CrystalCorners = false,
})
local arrowGlyph = Components.Label(waypointArrow, "Arrow", "▲", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
	TextSize = 25,
	Color = Colors.GoldSoft,
	Font = Enum.Font.GothamBlack,
	XAlignment = Enum.TextXAlignment.Center,
})

local inventoryDrawer = Components.GlassPanel(root, "InventoryDrawer", UDim2.new(0.5, 0, 1, -164), UDim2.fromOffset(520, 290), {
	AnchorPoint = Vector2.new(0.5, 1),
	Radius = 18,
	Transparency = 0.03,
	Visible = false,
})
trackScale(inventoryDrawer)
Components.Label(inventoryDrawer, "Header", "INVENTÁRIO DA EXPEDIÇÃO", UDim2.fromOffset(18, 9), UDim2.new(1, -65, 0, 29), {
	TextSize = 16,
	Color = Colors.GoldSoft,
	Font = Enum.Font.GothamBold,
})
local inventoryClose = Instance.new("TextButton")
inventoryClose.Name = "Close"
inventoryClose.AnchorPoint = Vector2.new(1, 0)
inventoryClose.Position = UDim2.new(1, -10, 0, 8)
inventoryClose.Size = UDim2.fromOffset(34, 32)
inventoryClose.BackgroundColor3 = Colors.GlassRaised
inventoryClose.BorderSizePixel = 0
inventoryClose.Text = "×"
inventoryClose.TextColor3 = Colors.Text
inventoryClose.Font = Enum.Font.GothamBold
inventoryClose.TextSize = 20
inventoryClose.Parent = inventoryDrawer
Components.Corner(inventoryClose, 9)
local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Name = "List"
inventoryList.Position = UDim2.fromOffset(14, 48)
inventoryList.Size = UDim2.new(1, -28, 1, -62)
inventoryList.BackgroundTransparency = 1
inventoryList.BorderSizePixel = 0
inventoryList.ScrollBarThickness = 4
inventoryList.ScrollBarImageColor3 = Colors.Cyan
inventoryList.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryList.CanvasSize = UDim2.new()
inventoryList.Parent = inventoryDrawer
local inventoryLayout = Instance.new("UIListLayout")
inventoryLayout.Padding = UDim.new(0, 7)
inventoryLayout.Parent = inventoryList

local currentObjective = {}
local currentBoss = {}
local lifeRecords = {}
local inventorySnapshot = { Entries = {} }
local toastSerial = 0
local healthTween
local healthLagTween
local objectiveTween
local staminaTween
local bossTween
local activeHumanoid
local humanoidConnections = {}

local function disconnectHumanoid()
	for _, connection in ipairs(humanoidConnections) do
		connection:Disconnect()
	end
	table.clear(humanoidConnections)
	activeHumanoid = nil
end

local function tweenRatio(target, ratio, duration)
	ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
	local tween = TweenService:Create(target, TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
	})
	tween:Play()
	return tween
end

local function confirmedCoins()
	local attribute = player:GetAttribute("Coins")
	if typeof(attribute) == "number" then
		return math.max(0, math.floor(attribute))
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Coins")
	return value and math.max(0, math.floor(tonumber(value.Value) or 0)) or 0
end

local function updateCurrencies()
	confirmedCoinsLabel.Text = string.format("%s", confirmedCoins())
	local pending = math.max(0, math.floor(tonumber(player:GetAttribute("PendingRoundCoins")) or 0))
	pendingCoinsLabel.Text = string.format("%s", pending)
	pendingCard.Visible = pending > 0 or workspace:GetAttribute("DungeonPhaseState") == "Active"
end

local function formatDuration(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	if seconds >= 60 then
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
	return tostring(seconds) .. "s"
end

local function updateVitals()
	local character = player.Character
	local humanoid = activeHumanoid or (character and character:FindFirstChildOfClass("Humanoid"))
	local health = humanoid and math.max(0, humanoid.Health) or 0
	local maxHealth = humanoid and math.max(1, humanoid.MaxHealth) or 100
	local ratio = health / maxHealth
	healthValue.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))
	if healthTween then healthTween:Cancel() end
	healthTween = tweenRatio(healthBar.Fill, ratio, 0.12)
	if healthLagTween then healthLagTween:Cancel() end
	healthLagTween = TweenService:Create(healthBar.Lag, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
	})
	healthLagTween:Play()
	healthBar.Fill.BackgroundColor3 = ratio <= 0.3 and Colors.Danger or Colors.Health

	local currentStamina = character and tonumber(character:GetAttribute("SprintStamina")) or nil
	local maximumStamina = character and tonumber(character:GetAttribute("SprintStaminaMax")) or nil
	if not currentStamina or not maximumStamina or maximumStamina <= 0 then
		currentStamina = 100
		maximumStamina = 100
	end
	staminaValue.Text = string.format("%d / %d", math.floor(currentStamina + 0.5), math.floor(maximumStamina + 0.5))
	if staminaTween then staminaTween:Cancel() end
	staminaTween = tweenRatio(staminaBar.Fill, currentStamina / maximumStamina, 0.14)
end

local BUFFS = {
	{ Glyph = "+", Until = "RespawnProtectionUntil", Active = "RespawnProtectionActive", Color = Colors.Success },
	{ Glyph = "◆", Until = "ShieldBuffUntil", Color = Colors.Crystal },
	{ Glyph = "↑", Until = "SpeedBuffUntil", Color = Colors.Success },
	{ Glyph = "↟", Until = "JumpBuffUntil", Color = Colors.Warning },
	{ Glyph = "✦", Until = "WingActiveUntil", Active = "WingActive", Color = Colors.Cyan },
	{ Glyph = "◐", Until = "CapeActiveUntil", Active = "InvisibleToEnemies", Color = Colors.Purple },
	{ Glyph = "◇", Until = "DungeonEntryProtectionUntil", Active = "DungeonEntryProtectionActive", Color = Colors.GoldSoft },
	{ Glyph = "↺", Until = "SanctuaryRescueProtectionUntil", Color = Colors.CyanSoft },
}

local function updateBuffs()
	local now = workspace:GetServerTimeNow()
	local visible = {}
	for _, definition in ipairs(BUFFS) do
		local untilAt = tonumber(player:GetAttribute(definition.Until)) or 0
		local active = untilAt > now
		if definition.Active and player:GetAttribute(definition.Active) == true then
			active = true
		end
		if active then
			table.insert(visible, {
				Glyph = definition.Glyph,
				Color = definition.Color,
				Remaining = untilAt > now and untilAt - now or 0,
			})
		end
	end
	for index, card in ipairs(buffCards) do
		local definition = visible[index]
		card.Card.Visible = definition ~= nil
		if definition then
			card.Glyph.Text = definition.Glyph
			card.Glyph.TextColor3 = definition.Color
			card.Timer.Text = definition.Remaining > 0 and formatDuration(definition.Remaining) or "ATIVO"
		end
	end
end

local function pacingDetail()
	local state = tostring(workspace:GetAttribute("DungeonPacingState") or "")
	local endsAt = tonumber(workspace:GetAttribute("DungeonPacingStateEndsAt")) or 0
	local remaining = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
	local labels = {
		ObjectivePreparation = "PREPARANDO COMBATE",
		InterWave = "PRÓXIMA ONDA",
		ObjectiveCompletion = "OBJETIVO CONCLUÍDO",
		RoundTransition = "PRÓXIMO ROUND",
		BossTransition = "CAMINHO DO BOSS",
		BossRouteOpen = "ROTA DO BOSS ABERTA",
	}
	local labelText = labels[state]
	if not labelText then
		return nil
	end
	return remaining > 0 and string.format("%s  •  %ds", labelText, remaining) or labelText
end

local function objectiveSnapshot()
	return {
		State = workspace:GetAttribute("DungeonObjectiveState") or "Inactive",
		Title = workspace:GetAttribute("DungeonObjectiveTitle"),
		Description = workspace:GetAttribute("DungeonObjectiveDescription"),
		RoundIndex = workspace:GetAttribute("DungeonObjectiveRoundIndex"),
		IslandIndex = workspace:GetAttribute("DungeonObjectiveIslandIndex"),
		GlobalIslandIndex = workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex"),
		Progress = workspace:GetAttribute("DungeonObjectiveProgress") or 0,
		Target = workspace:GetAttribute("DungeonObjectiveTarget") or 1,
		WaypointEscalated = workspace:GetAttribute("DungeonObjectiveWaypointEscalated") == true,
	}
end

local function bossSnapshot()
	local health = math.max(0, tonumber(workspace:GetAttribute("DungeonBossHealth")) or 0)
	local maximum = math.max(1, tonumber(workspace:GetAttribute("DungeonBossMaxHealth")) or 1)
	return {
		State = workspace:GetAttribute("DungeonBossState") or "Unavailable",
		Health = health,
		MaxHealth = maximum,
		HealthRatio = health / maximum,
		Phase = workspace:GetAttribute("DungeonBossPhase") or 1,
		Attack = workspace:GetAttribute("DungeonBossAttack"),
		Transitioning = workspace:GetAttribute("DungeonBossPhaseTransitioning") == true,
	}
end

local BOSS_ATTACKS = {
	LeapSlam = "SALTO ESMAGADOR — SAIA DO CÍRCULO",
	GroundPulse = "PULSO PRÓXIMO — AFASTE-SE",
	Shockwave = "ONDA DE CHOQUE — REPOSICIONE-SE",
	SummonSlimes = "REFORÇOS INVOCADOS",
	SkyfallVolley = "CHUVA CELESTIAL — SAIA DAS MARCAS",
	CrossSweep = "VARREDURA CRUZADA — PROCURE UMA ÁREA SEGURA",
	ArenaCollapse = "COLAPSO DA ARENA — VÁ PARA O CENTRO",
}

local function applyObjective(snapshot)
	currentObjective = type(snapshot) == "table" and snapshot or objectiveSnapshot()
	local boss = bossSnapshot()
	local bossVisible = boss.State == "Ready" or boss.State == "Activating" or boss.State == "Active"
	if bossVisible then
		local phase = math.max(1, math.floor(tonumber(boss.Phase) or 1))
		roundCaption.Text = "CHEFE"
		roundValue.Text = string.format("F%d", phase)
		islandCaption.Text = "ARENA"
		islandValue.Text = "BOSS"
		objectiveTitle.Text = "REI SLIME COLOSSAL"
		if boss.Transitioning then
			objectiveDetail.Text = "TRANSIÇÃO DE FASE — CHEFE INVULNERÁVEL"
		else
			objectiveDetail.Text = BOSS_ATTACKS[boss.Attack] or "DERROTE O CHEFE"
		end
		objectiveProgress.Text = string.format("%d / %d", math.floor(boss.Health), math.floor(boss.MaxHealth))
		if bossTween then bossTween:Cancel() end
		bossTween = tweenRatio(objectiveBar.Fill, boss.HealthRatio, 0.14)
		objectiveBar.Fill.BackgroundColor3 = phase >= 3 and Colors.Danger or phase == 2 and Colors.Warning or Colors.Cyan
		return
	end

	roundCaption.Text = "RODADA"
	local roundIndex = math.clamp(math.floor(tonumber(currentObjective.RoundIndex) or 1), 1, 3)
	roundValue.Text = string.format("%d/3", roundIndex)
	islandCaption.Text = "ILHA"
	islandValue.Text = tostring(math.max(1, math.floor(tonumber(currentObjective.IslandIndex) or 1)))
	objectiveTitle.Text = string.upper(tostring(currentObjective.Title or "PREPARANDO EXPEDIÇÃO"))
	objectiveDetail.Text = pacingDetail() or tostring(currentObjective.Description or "Aguarde a rota ser preparada.")
	local progress = math.max(0, tonumber(currentObjective.Progress) or 0)
	local target = math.max(1, tonumber(currentObjective.Target) or 1)
	objectiveProgress.Text = string.format("%d / %d", math.floor(progress), math.floor(target))
	if objectiveTween then objectiveTween:Cancel() end
	objectiveTween = tweenRatio(objectiveBar.Fill, progress / target, 0.16)
	objectiveBar.Fill.BackgroundColor3 = Colors.Cyan
end

local function participantState(playerObject, record)
	local state = tostring(record and record.State or playerObject and playerObject:GetAttribute("DungeonLifeState") or "Active")
	if state == "Eliminated" then
		return "ESPECTADOR", Colors.Danger, 0
	elseif state == "Downed" then
		return "CAÍDO", Colors.Warning, 0.15
	elseif state == "Disconnected" then
		return "AUSENTE", Colors.Dim, 0
	end
	local humanoid = playerObject and playerObject.Character and playerObject.Character:FindFirstChildOfClass("Humanoid")
	local ratio = humanoid and humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
	return "ATIVO", Colors.Success, math.clamp(ratio, 0, 1)
end

local function updateParty()
	local entries = {}
	local seen = {}
	for userId, record in pairs(lifeRecords) do
		local numeric = tonumber(userId) or tonumber(record.UserId)
		if numeric and numeric > 0 then
			seen[numeric] = true
			table.insert(entries, { UserId = numeric, Record = record, Player = Players:GetPlayerByUserId(numeric) })
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local sameSession = player:GetAttribute("DungeonSessionId") == nil
			or other:GetAttribute("DungeonSessionId") == player:GetAttribute("DungeonSessionId")
		if sameSession and not seen[other.UserId] then
			table.insert(entries, { UserId = other.UserId, Player = other })
		end
	end
	table.sort(entries, function(left, right)
		if left.UserId == player.UserId then return true end
		if right.UserId == player.UserId then return false end
		return left.UserId < right.UserId
	end)
	for index, row in ipairs(partyRows) do
		local entry = entries[index]
		row.Frame.Visible = entry ~= nil
		if entry then
			local other = entry.Player
			local displayName = other and other.DisplayName or ("Jogador " .. tostring(entry.UserId))
			row.Name.Text = displayName
			row.Initial.Text = string.upper(string.sub(displayName, 1, 1))
			row.Leader.Visible = other and other:GetAttribute("PartyLeaderUserId") == other.UserId or false
			local stateText, stateColor, ratio = participantState(other, entry.Record)
			row.State.Text = stateText
			row.State.TextColor3 = stateColor
			row.Health.Fill.BackgroundColor3 = ratio <= 0.3 and Colors.Danger or ratio <= 0.6 and Colors.Warning or Colors.Success
			row.Health.Fill.Size = UDim2.fromScale(ratio, 1)
			row.Percent.Text = stateText == "ATIVO" and string.format("%d%%", math.floor(ratio * 100 + 0.5)) or "--"
		end
	end
end

local function updateStateBanner()
	local phaseState = tostring(workspace:GetAttribute("DungeonPhaseState") or "")
	local lifeState = tostring(player:GetAttribute("DungeonLifeState") or "Active")
	local downed = lifeState == "Downed" or player:GetAttribute("IsDowned") == true
	local spectating = lifeState == "Eliminated" or player:GetAttribute("DungeonSpectating") == true
	if downed then
		local expiresAt = tonumber(player:GetAttribute("DungeonDownedExpiresAt") or player:GetAttribute("DownedExpiresAt")) or 0
		stateBanner.Visible = true
		stateTitle.Text = string.format("DERRUBADO — %ds", math.max(0, math.ceil(expiresAt - workspace:GetServerTimeNow())))
		stateTitle.TextColor3 = Colors.Danger
		stateDetail.Text = "Um aliado pode reviver você antes do tempo acabar."
	elseif spectating then
		stateBanner.Visible = true
		stateTitle.Text = "ESPECTANDO"
		stateTitle.TextColor3 = Colors.Muted
		stateDetail.Text = "Você retornará na próxima ilha de recompensa."
	elseif workspace:GetAttribute("DungeonWipePending") == true then
		stateBanner.Visible = true
		stateTitle.Text = "EQUIPE DERRUBADA"
		stateTitle.TextColor3 = Colors.Warning
		stateDetail.Text = "Aguardando uma recuperação antes da derrota."
	elseif phaseState == "Victory" then
		stateBanner.Visible = true
		stateTitle.Text = "VITÓRIA"
		stateTitle.TextColor3 = Colors.Success
		stateDetail.Text = "Recompensas finais sendo confirmadas."
	elseif phaseState == "Defeat" then
		stateBanner.Visible = true
		stateTitle.Text = "EXPEDIÇÃO ENCERRADA"
		stateTitle.TextColor3 = Colors.Danger
		stateDetail.Text = "Preparando o retorno ao Lobby."
	else
		stateBanner.Visible = false
	end
end

local function showToast(titleText, detailText, color, glyph)
	toastSerial += 1
	local serial = toastSerial
	notificationTitle.Text = tostring(titleText or "ATUALIZAÇÃO")
	notificationDetail.Text = tostring(detailText or "")
	notificationGlyph.Text = tostring(glyph or "✦")
	notificationGlyph.TextColor3 = color or Colors.CyanSoft
	notificationPanel.Position = UDim2.new(1, 36, 1, -18)
	notificationPanel.Visible = true
	TweenService:Create(notificationPanel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -22, 1, -18),
	}):Play()
	task.delay(3.2, function()
		if serial ~= toastSerial then return end
		local tween = TweenService:Create(notificationPanel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, 36, 1, -18),
		})
		tween:Play()
		tween.Completed:Wait()
		if serial == toastSerial then
			notificationPanel.Visible = false
		end
	end)
end

local function itemGlyph(itemId)
	itemId = tostring(itemId or "")
	if string.find(itemId, "Health", 1, true) then return "+", Colors.Health end
	if string.find(itemId, "Speed", 1, true) then return "↑", Colors.Success end
	if string.find(itemId, "Jump", 1, true) then return "↟", Colors.Warning end
	return "✦", Colors.Purple
end

local inventoryRequest = ReplicatedStorage:FindFirstChild("InventoryRequest")
local inventoryEvent = ReplicatedStorage:FindFirstChild("InventoryEvent")

local function clearInventoryRows()
	for _, child in ipairs(inventoryList:GetChildren()) do
		if child ~= inventoryLayout and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function renderInventory(snapshot)
	inventorySnapshot = type(snapshot) == "table" and snapshot or { Entries = {} }
	clearInventoryRows()
	for index = 2, 4 do
		local entry = inventorySnapshot.Entries and inventorySnapshot.Entries[index - 1]
		local slot = hotbarSlots[index]
		if entry then
			local glyph, color = itemGlyph(entry.ItemId)
			slot.Glyph.Text = glyph
			slot.Glyph.TextColor3 = color
			slot.Amount.Text = "x" .. tostring(entry.Amount or 0)
		else
			slot.Glyph.Text = ""
			slot.Amount.Text = ""
		end
	end

	for index, entry in ipairs(inventorySnapshot.Entries or {}) do
		local row = Instance.new("Frame")
		row.Name = "Item" .. index
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -4, 0, 56)
		row.BackgroundColor3 = Colors.GlassDeep
		row.BackgroundTransparency = 0.24
		row.BorderSizePixel = 0
		row.Parent = inventoryList
		Components.Corner(row, 10)
		Components.Stroke(row, Colors.Crystal, 0.60, 1)
		local glyph, color = itemGlyph(entry.ItemId)
		Components.Label(row, "Glyph", glyph, UDim2.fromOffset(7, 4), UDim2.fromOffset(46, 48), {
			TextSize = 24,
			Color = color,
			Font = Enum.Font.GothamBlack,
			XAlignment = Enum.TextXAlignment.Center,
		})
		Components.Label(row, "Name", string.format("%s  x%d", tostring(entry.DisplayName or entry.ItemId), math.max(0, tonumber(entry.Amount) or 0)), UDim2.fromOffset(57, 5), UDim2.new(1, -160, 0, 24), {
			TextSize = 12,
			Font = Enum.Font.GothamBold,
		})
		Components.Label(row, "Description", tostring(entry.Description or ""), UDim2.fromOffset(57, 28), UDim2.new(1, -160, 0, 21), {
			TextSize = 10,
			Color = Colors.Muted,
		})
		local useButton = Instance.new("TextButton")
		useButton.Name = "Use"
		useButton.AnchorPoint = Vector2.new(1, 0.5)
		useButton.Position = UDim2.new(1, -8, 0.5, 0)
		useButton.Size = UDim2.fromOffset(86, 38)
		useButton.BackgroundColor3 = Colors.GlassRaised
		useButton.BorderSizePixel = 0
		useButton.Text = "USAR"
		useButton.TextColor3 = Colors.CyanSoft
		useButton.Font = Enum.Font.GothamBold
		useButton.TextSize = 11
		useButton.Parent = row
		Components.Corner(useButton, 9)
		Components.Stroke(useButton, Colors.Gold, 0.35, 1)
		useButton.Activated:Connect(function()
			if not inventoryRequest or not inventoryRequest:IsA("RemoteFunction") then
				showToast("INVENTÁRIO INDISPONÍVEL", "Não foi possível usar o item agora.", Colors.Danger, "!")
				return
			end
			local success, response = pcall(inventoryRequest.InvokeServer, inventoryRequest, "Use", entry.ItemId)
			if success and type(response) == "table" and response.Inventory then
				renderInventory(response.Inventory)
				showToast("ITEM UTILIZADO", tostring(entry.DisplayName or entry.ItemId), Colors.Success, glyph)
			elseif not success then
				showToast("FALHA AO USAR", "Tente novamente.", Colors.Danger, "!")
			end
		end)
	end
	if #(inventorySnapshot.Entries or {}) == 0 then
		Components.Label(inventoryList, "Empty", "Nenhum consumível nesta expedição.", UDim2.fromOffset(0, 0), UDim2.new(1, -4, 0, 52), {
			TextSize = 13,
			Color = Colors.Muted,
			XAlignment = Enum.TextXAlignment.Center,
		})
	end
end

local function requestInventory()
	if not inventoryRequest or not inventoryRequest:IsA("RemoteFunction") then
		return
	end
	local success, snapshot = pcall(inventoryRequest.InvokeServer, inventoryRequest, "Get")
	if success and type(snapshot) == "table" then
		renderInventory(snapshot)
	end
end

local function setInventoryOpen(open)
	inventoryDrawer.Visible = open == true
	if open then
		ModalManager.Acquire(playerGui, "DungeonInventory")
		requestInventory()
	else
		ModalManager.Release(playerGui, "DungeonInventory")
	end
end

hotbarSlots[5].Button.Activated:Connect(function()
	setInventoryOpen(not inventoryDrawer.Visible)
end)
inventoryClose.Activated:Connect(function()
	setInventoryOpen(false)
end)
playerGui:GetAttributeChangedSignal("SkyDungeonExclusivePanel"):Connect(function()
	if inventoryDrawer.Visible and not ModalManager.IsOpen(playerGui, "DungeonInventory") then
		inventoryDrawer.Visible = false
	end
end)

local function updateWaypoint()
	local target = workspace:GetAttribute("DungeonObjectiveWaypointPosition")
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if typeof(target) ~= "Vector3" or not rootPart then
		waypointDistanceTop.Text = "--m"
		waypointArrow.Visible = false
		return
	end
	local distance = math.floor((target - rootPart.Position).Magnitude + 0.5)
	waypointDistanceTop.Text = string.format("%dm", distance)
	local escalated = currentObjective.WaypointEscalated == true
		or workspace:GetAttribute("DungeonObjectiveWaypointEscalated") == true
	if not escalated then
		waypointArrow.Visible = false
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local point, onScreen = camera:WorldToViewportPoint(target)
	local viewport = camera.ViewportSize
	if onScreen and point.Z > 0 then
		waypointArrow.Visible = true
		waypointArrow.Rotation = 0
		waypointArrow.Position = UDim2.fromOffset(point.X, math.max(145, point.Y - 52))
	else
		local direction = camera.CFrame:VectorToObjectSpace((target - camera.CFrame.Position).Unit)
		local angle = math.atan2(direction.X, -direction.Z)
		waypointArrow.Visible = true
		waypointArrow.Rotation = math.deg(angle)
		waypointArrow.Position = UDim2.fromOffset(
			viewport.X * 0.5 + math.sin(angle) * viewport.X * 0.42,
			viewport.Y * 0.52 - math.cos(angle) * viewport.Y * 0.35
		)
	end
end

local function updateResponsiveLayout()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local responsive = Theme.GetResponsive(viewport)
	for _, record in ipairs(responsiveGroups) do
		record.Scale.Scale = responsive.Scale
	end
	local margin = responsive.Margin
	if responsive.Phone then
		currencies.Position = UDim2.fromOffset(margin, margin)
		objectivePanel.Position = UDim2.new(0.5, 0, 0, 112)
		partyPanel.Position = UDim2.new(1, -margin, 0, margin)
		partyPanel.Size = UDim2.fromOffset(270, 230)
		vitalsPanel.Position = UDim2.new(0, margin, 1, -margin)
		hotbarPanel.Position = UDim2.new(0.5, 0, 1, -margin)
		notificationPanel.Position = UDim2.new(1, -margin, 1, -margin)
		inventoryDrawer.Position = UDim2.new(0.5, 0, 1, -145)
	elseif responsive.Compact then
		currencies.Position = UDim2.fromOffset(margin, margin)
		objectivePanel.Position = UDim2.new(0.5, 0, 0, margin)
		partyPanel.Position = UDim2.new(1, -margin, 0, margin)
		vitalsPanel.Position = UDim2.new(0, margin, 1, -margin)
		hotbarPanel.Position = UDim2.new(0.5, 0, 1, -margin)
		notificationPanel.Position = UDim2.new(1, -margin, 1, -margin)
		inventoryDrawer.Position = UDim2.new(0.5, 0, 1, -150)
	else
		currencies.Position = UDim2.fromOffset(22, 20)
		objectivePanel.Position = UDim2.new(0.5, 0, 0, 20)
		partyPanel.Position = UDim2.new(1, -22, 0, 20)
		partyPanel.Size = UDim2.fromOffset(310, 286)
		vitalsPanel.Position = UDim2.new(0, 22, 1, -18)
		hotbarPanel.Position = UDim2.new(0.5, 0, 1, -18)
		notificationPanel.Position = UDim2.new(1, -22, 1, -18)
		inventoryDrawer.Position = UDim2.new(0.5, 0, 1, -164)
	end
end

local function bindHumanoid(character)
	disconnectHumanoid()
	activeHumanoid = character and character:WaitForChild("Humanoid", 8)
	if activeHumanoid then
		table.insert(humanoidConnections, activeHumanoid.HealthChanged:Connect(updateVitals))
		table.insert(humanoidConnections, activeHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateVitals))
	end
	for _, attribute in ipairs({ "SprintStamina", "SprintStaminaMax", "Sprinting" }) do
		table.insert(humanoidConnections, character:GetAttributeChangedSignal(attribute):Connect(updateVitals))
	end
	updateVitals()
end

local shared = ReplicatedStorage:FindFirstChild("Shared")
local remotes = shared and shared:FindFirstChild("Remotes")
local dungeonRemotes = remotes and remotes:FindFirstChild("Dungeon")
local objectiveEvent = dungeonRemotes and dungeonRemotes:FindFirstChild("ObjectiveState")
local rewardEvent = dungeonRemotes and dungeonRemotes:FindFirstChild("RewardState")
local lifeEvent = dungeonRemotes and dungeonRemotes:FindFirstChild("LifeState")
local bossEvent = dungeonRemotes and dungeonRemotes:FindFirstChild("BossState")

if objectiveEvent and objectiveEvent:IsA("RemoteEvent") then
	objectiveEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Action == "ObjectiveSnapshot" then
			applyObjective(payload.Objective)
		end
	end)
end
if lifeEvent and lifeEvent:IsA("RemoteEvent") then
	lifeEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Participants) == "table" then
			lifeRecords = payload.Participants
		elseif type(payload) == "table" and type(payload.Snapshot) == "table" and type(payload.Snapshot.Participants) == "table" then
			lifeRecords = payload.Snapshot.Participants
		end
		updateParty()
		updateStateBanner()
	end)
end
if bossEvent and bossEvent:IsA("RemoteEvent") then
	bossEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then currentBoss = payload end
		applyObjective(currentObjective)
	end)
end
if rewardEvent and rewardEvent:IsA("RemoteEvent") then
	rewardEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Active == true then
			showToast("ILHA DE RECOMPENSA", "Abra seus baús antes do próximo round.", Colors.GoldSoft, "◆")
		end
	end)
end

local coinReward = ReplicatedStorage:FindFirstChild("CoinReward")
if coinReward and coinReward:IsA("RemoteEvent") then
	coinReward.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		local amount = math.max(0, math.floor(tonumber(payload.Amount) or 0))
		if amount <= 0 then return end
		if payload.Committed then
			showToast("MOEDAS CONFIRMADAS", string.format("+%d moedas salvas", amount), Colors.GoldSoft, "◆")
		elseif payload.Pending then
			showToast("ESSÊNCIA COLETADA", string.format("+%d moedas pendentes", amount), Colors.CyanSoft, "✦")
		end
		updateCurrencies()
	end)
end

if inventoryEvent and inventoryEvent:IsA("RemoteEvent") then
	inventoryEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Inventory then
			renderInventory(payload.Inventory)
		end
	end)
end

for _, attribute in ipairs({
	"Coins",
	"PendingRoundCoins",
	"DungeonLifeState",
	"DungeonSpectating",
	"IsDowned",
	"DungeonDownedExpiresAt",
	"DownedExpiresAt",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		updateCurrencies()
		updateStateBanner()
	end)
end

for _, attribute in ipairs({
	"DungeonObjectiveRevision",
	"DungeonPacingState",
	"DungeonPacingStateEndsAt",
	"DungeonBossState",
	"DungeonBossHealth",
	"DungeonBossPhase",
	"DungeonBossAttack",
	"DungeonBossPhaseTransitioning",
}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(function()
		applyObjective(objectiveSnapshot())
	end)
end
workspace:GetAttributeChangedSignal("DungeonPhaseState"):Connect(updateStateBanner)
workspace:GetAttributeChangedSignal("DungeonWipePending"):Connect(updateStateBanner)

Players.PlayerAdded:Connect(function()
	task.defer(updateParty)
end)
Players.PlayerRemoving:Connect(function()
	task.defer(updateParty)
end)

player.CharacterAdded:Connect(bindHumanoid)
if player.Character then
	task.defer(bindHumanoid, player.Character)
end

local viewportConnection
local function bindCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end
	updateResponsiveLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

local elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.1 then return end
	elapsed = 0
	updateWaypoint()
	updateBuffs()
	updateStateBanner()
	updateCurrencies()
	updateVitals()
	updateParty()
	local detail = pacingDetail()
	if detail and tostring(workspace:GetAttribute("DungeonBossState") or "") ~= "Active" then
		objectiveDetail.Text = detail
	end
end)

player:SetAttribute("DungeonUnifiedHUDReady", true)
player:SetAttribute("DungeonHUDStyle", Theme.StyleId)
player:SetAttribute("DungeonHUDStyleVersion", Theme.Version)
workspace:SetAttribute("DungeonHUDSpecialTaskStarted", true)
workspace:SetAttribute("DungeonHUDFoundationReady", true)
workspace:SetAttribute("DungeonHUDFoundationPolicy", "CrystalCelestialFoundationV1")
workspace:SetAttribute("DungeonHUDLegacyVisualSystemsPreserved", true)

applyObjective(objectiveSnapshot())
updateCurrencies()
updateParty()
updateVitals()
updateBuffs()
updateStateBanner()
requestInventory()
