local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local phaseRequest = RemoteRegistry.Get("PhaseSelection", "Request", "RemoteFunction")
local phaseEvent = RemoteRegistry.Get("PhaseSelection", "Event", "RemoteEvent")
local rouletteRequest = RemoteRegistry.Get("Roulette", "Request", "RemoteFunction")
local rouletteEvent = RemoteRegistry.Get("Roulette", "Event", "RemoteEvent")
local equipmentRequest = RemoteRegistry.Get("Equipment", "Request", "RemoteFunction")
local equipmentEvent = RemoteRegistry.Get("Equipment", "Event", "RemoteEvent")
local notificationEvent = RemoteRegistry.Get("Notifications", "Lobby", "RemoteEvent")

local COLORS = {
	Glass = Color3.fromRGB(12, 26, 42),
	GlassRaised = Color3.fromRGB(22, 47, 64),
	GlassSoft = Color3.fromRGB(30, 53, 69),
	Text = Color3.fromRGB(240, 247, 252),
	Muted = Color3.fromRGB(149, 178, 201),
	Cyan = Color3.fromRGB(108, 226, 255),
	CyanSoft = Color3.fromRGB(184, 243, 255),
	Gold = Color3.fromRGB(232, 195, 104),
	GoldSoft = Color3.fromRGB(255, 225, 142),
	Green = Color3.fromRGB(101, 236, 163),
	Orange = Color3.fromRGB(255, 184, 92),
	Red = Color3.fromRGB(255, 105, 117),
	Purple = Color3.fromRGB(197, 142, 255),
	Locked = Color3.fromRGB(111, 126, 145),
}

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local scale = Instance.new("UIScale")
scale.Name = "ResponsiveScale"
scale.Scale = 1
scale.Parent = gui

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Position = UDim2.fromOffset(14, 10)
topBar.Size = UDim2.new(1, -28, 0, 56)
topBar.BackgroundColor3 = COLORS.Glass
topBar.BackgroundTransparency = 0.16
topBar.BorderSizePixel = 0
topBar.Parent = gui
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 14)

local topStroke = Instance.new("UIStroke")
topStroke.Color = COLORS.Gold
topStroke.Transparency = 0.45
topStroke.Parent = topBar

local brand = Instance.new("TextLabel")
brand.Position = UDim2.fromOffset(15, 5)
brand.Size = UDim2.fromOffset(270, 27)
brand.BackgroundTransparency = 1
brand.Text = "SKYDUNGEON"
brand.TextColor3 = COLORS.GoldSoft
brand.Font = Enum.Font.GothamBlack
brand.TextSize = 17
brand.TextXAlignment = Enum.TextXAlignment.Left
brand.Parent = topBar

local lobbyCaption = Instance.new("TextLabel")
lobbyCaption.Position = UDim2.fromOffset(16, 30)
lobbyCaption.Size = UDim2.fromOffset(270, 18)
lobbyCaption.BackgroundTransparency = 1
lobbyCaption.Text = "LOBBY • ESCOLHA SEU UNIVERSO"
lobbyCaption.TextColor3 = COLORS.Muted
lobbyCaption.Font = Enum.Font.GothamBold
lobbyCaption.TextSize = 8
lobbyCaption.TextXAlignment = Enum.TextXAlignment.Left
lobbyCaption.Parent = topBar

local coinCard = Instance.new("Frame")
coinCard.AnchorPoint = Vector2.new(1, 0.5)
coinCard.Position = UDim2.new(1, -70, 0.5, 0)
coinCard.Size = UDim2.fromOffset(150, 38)
coinCard.BackgroundColor3 = COLORS.GlassRaised
coinCard.BackgroundTransparency = 0.05
coinCard.BorderSizePixel = 0
coinCard.Parent = topBar
Instance.new("UICorner", coinCard).CornerRadius = UDim.new(0, 11)

local coinStroke = Instance.new("UIStroke")
coinStroke.Color = COLORS.Gold
coinStroke.Transparency = 0.28
coinStroke.Parent = coinCard

local coinIcon = Instance.new("TextLabel")
coinIcon.Position = UDim2.fromOffset(8, 2)
coinIcon.Size = UDim2.fromOffset(34, 34)
coinIcon.BackgroundTransparency = 1
coinIcon.Text = "●"
coinIcon.TextColor3 = COLORS.GoldSoft
coinIcon.Font = Enum.Font.GothamBlack
coinIcon.TextSize = 18
coinIcon.Parent = coinCard

local coinValue = Instance.new("TextLabel")
coinValue.Position = UDim2.fromOffset(43, 2)
coinValue.Size = UDim2.new(1, -51, 1, -4)
coinValue.BackgroundTransparency = 1
coinValue.Text = "0"
coinValue.TextColor3 = COLORS.Text
coinValue.Font = Enum.Font.GothamBlack
coinValue.TextSize = 13
coinValue.TextXAlignment = Enum.TextXAlignment.Left
coinValue.Parent = coinCard

local dock = Instance.new("Frame")
dock.Name = "QuickDock"
dock.AnchorPoint = Vector2.new(0.5, 1)
dock.Position = UDim2.new(0.5, 0, 1, -18)
dock.Size = UDim2.fromOffset(470, 66)
dock.BackgroundColor3 = COLORS.Glass
dock.BackgroundTransparency = 0.10
dock.BorderSizePixel = 0
dock.Parent = gui
Instance.new("UICorner", dock).CornerRadius = UDim.new(0, 17)

local dockStroke = Instance.new("UIStroke")
dockStroke.Color = COLORS.Gold
dockStroke.Transparency = 0.42
dockStroke.Parent = dock

local dockLayout = Instance.new("UIListLayout")
dockLayout.FillDirection = Enum.FillDirection.Horizontal
dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dockLayout.Padding = UDim.new(0, 9)
dockLayout.Parent = dock

local function dockButton(name, glyph, caption)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(138, 48)
	button.BackgroundColor3 = COLORS.GlassRaised
	button.BackgroundTransparency = 0.07
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = dock
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)

	local s = Instance.new("UIStroke")
	s.Color = COLORS.Cyan
	s.Transparency = 0.52
	s.Parent = button

	local icon = Instance.new("TextLabel")
	icon.Position = UDim2.fromOffset(7, 5)
	icon.Size = UDim2.fromOffset(37, 37)
	icon.BackgroundTransparency = 1
	icon.Text = glyph
	icon.TextColor3 = COLORS.CyanSoft
	icon.Font = Enum.Font.GothamBlack
	icon.TextSize = 19
	icon.Parent = button

	local text = Instance.new("TextLabel")
	text.Position = UDim2.fromOffset(45, 4)
	text.Size = UDim2.new(1, -50, 1, -8)
	text.BackgroundTransparency = 1
	text.Text = caption
	text.TextColor3 = COLORS.Text
	text.Font = Enum.Font.GothamBold
	text.TextSize = 10
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = button
	return button
end

local worldsButton = dockButton("Worlds", "◆", "MUNDOS")
local equipmentButton = dockButton("Equipment", "⚔", "EQUIPAR")
local rouletteButton = dockButton("Roulette", "✦", "ROLETA")

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(3, 8, 15)
overlay.BackgroundTransparency = 0.28
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.50)
panel.Size = UDim2.fromOffset(900, 590)
panel.BackgroundColor3 = COLORS.Glass
panel.BackgroundTransparency = 0.025
panel.BorderSizePixel = 0
panel.ZIndex = 51
panel.Parent = overlay
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Gold
panelStroke.Transparency = 0.16
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local panelTitle = Instance.new("TextLabel")
panelTitle.Position = UDim2.fromOffset(22, 12)
panelTitle.Size = UDim2.new(1, -80, 0, 36)
panelTitle.BackgroundTransparency = 1
panelTitle.Text = "UNIVERSOS"
panelTitle.TextColor3 = COLORS.GoldSoft
panelTitle.Font = Enum.Font.GothamBlack
panelTitle.TextSize = 20
panelTitle.TextXAlignment = Enum.TextXAlignment.Left
panelTitle.ZIndex = 52
panelTitle.Parent = panel

local panelSubtitle = Instance.new("TextLabel")
panelSubtitle.Position = UDim2.fromOffset(23, 45)
panelSubtitle.Size = UDim2.new(1, -82, 0, 20)
panelSubtitle.BackgroundTransparency = 1
panelSubtitle.Text = ""
panelSubtitle.TextColor3 = COLORS.Muted
panelSubtitle.Font = Enum.Font.GothamMedium
panelSubtitle.TextSize = 9
panelSubtitle.TextXAlignment = Enum.TextXAlignment.Left
panelSubtitle.ZIndex = 52
panelSubtitle.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 12)
close.Size = UDim2.fromOffset(42, 38)
close.BackgroundColor3 = Color3.fromRGB(52, 58, 69)
close.BackgroundTransparency = 0.05
close.BorderSizePixel = 0
close.Text = "×"
close.TextColor3 = COLORS.Text
close.Font = Enum.Font.GothamBold
close.TextSize = 20
close.ZIndex = 53
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(20, 76)
content.Size = UDim2.new(1, -40, 1, -96)
content.BackgroundTransparency = 1
content.ZIndex = 52
content.Parent = panel

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 76)
toast.Size = UDim2.fromOffset(470, 56)
toast.BackgroundColor3 = Color3.fromRGB(19, 55, 51)
toast.BackgroundTransparency = 0.04
toast.BorderSizePixel = 0
toast.Text = ""
toast.TextColor3 = COLORS.Text
toast.TextWrapped = true
toast.Font = Enum.Font.GothamBold
toast.TextSize = 11
toast.Visible = false
toast.ZIndex = 120
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 13)
local toastStroke = Instance.new("UIStroke")
toastStroke.Color = COLORS.Cyan
toastStroke.Transparency = 0.24
toastStroke.Parent = toast

local toastSerial = 0
local function showToast(message, good)
	toastSerial += 1
	local serial = toastSerial
	toast.Text = tostring(message or "")
	toast.BackgroundColor3 = good == false
		and Color3.fromRGB(79, 31, 42)
		or Color3.fromRGB(18, 57, 55)
	toastStroke.Color = good == false and COLORS.Red or COLORS.Cyan
	toast.Visible = true
	task.delay(4, function()
		if toastSerial == serial then toast.Visible = false end
	end)
end

local function clearContent()
	for _, child in ipairs(content:GetChildren()) do
		child:Destroy()
	end
end

local function invoke(remote, ...)
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		showToast("Falha de comunicação com o servidor.", false)
		return nil
	end
	return result
end

local function open(titleText, subtitleText)
	panelTitle.Text = titleText
	panelSubtitle.Text = subtitleText or ""
	clearContent()
	overlay.Visible = true
end

close.Activated:Connect(function()
	overlay.Visible = false
end)

local function formatTime(seconds)
	if typeof(seconds) ~= "number" then return "--:--" end
	local whole = math.max(0, math.floor(seconds + 0.5))
	return string.format("%02d:%02d", math.floor(whole / 60), whole % 60)
end

local function updateCoins(value)
	if typeof(value) == "number" then
		player:SetAttribute("LobbyCoins", math.max(0, math.floor(value)))
	end
	coinValue.Text = tostring(math.max(0, math.floor(tonumber(player:GetAttribute("LobbyCoins")) or 0)))
end
player:GetAttributeChangedSignal("LobbyCoins"):Connect(function()
	updateCoins()
end)
updateCoins()

local function actionButton(parent, text, color)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(180, 42)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.03
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = COLORS.Text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 10
	button.Parent = parent
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 11)
	return button
end

local function renderUniverseBrowser(universes)
	open("UNIVERSOS", "Escolha um mundo. Cada universo possui vários níveis internos.")

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = COLORS.Cyan
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.Parent = scroll

	for _, universe in ipairs(universes or {}) do
		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, -7, 0, 116)
		card.BackgroundColor3 = COLORS.GlassRaised
		card.BackgroundTransparency = 0.06
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = true
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 15)

		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.Cyan
		stroke.Transparency = 0.42
		stroke.Parent = card

		local glyph = Instance.new("TextLabel")
		glyph.Position = UDim2.fromOffset(13, 13)
		glyph.Size = UDim2.fromOffset(78, 78)
		glyph.BackgroundColor3 = Color3.fromRGB(25, 60, 76)
		glyph.BackgroundTransparency = 0.04
		glyph.BorderSizePixel = 0
		glyph.Text = "◆"
		glyph.TextColor3 = COLORS.CyanSoft
		glyph.Font = Enum.Font.GothamBlack
		glyph.TextSize = 32
		glyph.Parent = card
		Instance.new("UICorner", glyph).CornerRadius = UDim.new(0, 15)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(108, 13)
		name.Size = UDim2.new(1, -300, 0, 28)
		name.BackgroundTransparency = 1
		name.Text = string.upper(tostring(universe.DisplayName or universe.UniverseId))
		name.TextColor3 = COLORS.GoldSoft
		name.Font = Enum.Font.GothamBlack
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Position = UDim2.fromOffset(108, 42)
		desc.Size = UDim2.new(1, -300, 0, 40)
		desc.BackgroundTransparency = 1
		desc.Text = tostring(universe.Description or "")
		desc.TextColor3 = COLORS.Muted
		desc.Font = Enum.Font.GothamMedium
		desc.TextSize = 9
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.Parent = card

		local progress = Instance.new("TextLabel")
		progress.AnchorPoint = Vector2.new(1, 0.5)
		progress.Position = UDim2.new(1, -14, 0.5, 0)
		progress.Size = UDim2.fromOffset(165, 62)
		progress.BackgroundColor3 = Color3.fromRGB(17, 40, 54)
		progress.BackgroundTransparency = 0.05
		progress.BorderSizePixel = 0
		progress.Text = string.format(
			"%d/%d NÍVEIS\n%d DESBLOQUEADOS",
			tonumber(universe.CompletedLevels) or 0,
			tonumber(universe.LevelCount) or #(universe.Levels or {}),
			tonumber(universe.UnlockedLevels) or 0
		)
		progress.TextColor3 = COLORS.CyanSoft
		progress.Font = Enum.Font.GothamBold
		progress.TextSize = 9
		progress.TextWrapped = true
		progress.Parent = card
		Instance.new("UICorner", progress).CornerRadius = UDim.new(0, 11)

		card.Activated:Connect(function()
			local result = invoke(phaseRequest, "GetUniverse", { UniverseId = universe.UniverseId })
			if result and result.Success and result.Universe then
				_G.__SkyDungeonRenderUniverse(result.Universe)
			end
		end)
	end
end

local function renderUniverse(universe, selectedPhaseId)
	open(
		string.upper(tostring(universe.DisplayName or "UNIVERSO")),
		"Escolha um nível. Novos níveis desbloqueiam ao concluir o anterior."
	)

	local left = Instance.new("Frame")
	left.Size = UDim2.fromOffset(278, 1)
	left.Size = UDim2.new(0, 278, 1, 0)
	left.BackgroundColor3 = Color3.fromRGB(20, 43, 59)
	left.BackgroundTransparency = 0.05
	left.BorderSizePixel = 0
	left.Parent = content
	Instance.new("UICorner", left).CornerRadius = UDim.new(0, 16)
	local leftStroke = Instance.new("UIStroke")
	leftStroke.Color = COLORS.Gold
	leftStroke.Transparency = 0.32
	leftStroke.Parent = left

	local emblem = Instance.new("TextLabel")
	emblem.AnchorPoint = Vector2.new(0.5, 0)
	emblem.Position = UDim2.new(0.5, 0, 0, 22)
	emblem.Size = UDim2.fromOffset(120, 120)
	emblem.BackgroundColor3 = Color3.fromRGB(28, 66, 83)
	emblem.BackgroundTransparency = 0.04
	emblem.BorderSizePixel = 0
	emblem.Text = "◆"
	emblem.TextColor3 = COLORS.CyanSoft
	emblem.Font = Enum.Font.GothamBlack
	emblem.TextSize = 48
	emblem.Parent = left
	Instance.new("UICorner", emblem).CornerRadius = UDim.new(0, 22)

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(16, 158)
	name.Size = UDim2.new(1, -32, 0, 32)
	name.BackgroundTransparency = 1
	name.Text = string.upper(tostring(universe.DisplayName or universe.UniverseId))
	name.TextColor3 = COLORS.GoldSoft
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 16
	name.TextWrapped = true
	name.Parent = left

	local desc = Instance.new("TextLabel")
	desc.Position = UDim2.fromOffset(18, 199)
	desc.Size = UDim2.new(1, -36, 0, 88)
	desc.BackgroundTransparency = 1
	desc.Text = tostring(universe.Description or "")
	desc.TextColor3 = COLORS.Muted
	desc.Font = Enum.Font.GothamMedium
	desc.TextSize = 9
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.Parent = left

	local progress = Instance.new("TextLabel")
	progress.AnchorPoint = Vector2.new(0.5, 1)
	progress.Position = UDim2.new(0.5, 0, 1, -24)
	progress.Size = UDim2.new(1, -32, 0, 78)
	progress.BackgroundColor3 = Color3.fromRGB(15, 35, 49)
	progress.BackgroundTransparency = 0.05
	progress.BorderSizePixel = 0
	progress.Text = string.format(
		"PROGRESSÃO DO UNIVERSO\n%d/%d NÍVEIS CONCLUÍDOS",
		tonumber(universe.CompletedLevels) or 0,
		tonumber(universe.LevelCount) or #(universe.Levels or {})
	)
	progress.TextColor3 = COLORS.CyanSoft
	progress.Font = Enum.Font.GothamBold
	progress.TextSize = 10
	progress.TextWrapped = true
	progress.Parent = left
	Instance.new("UICorner", progress).CornerRadius = UDim.new(0, 12)

	local right = Instance.new("ScrollingFrame")
	right.Position = UDim2.fromOffset(294, 0)
	right.Size = UDim2.new(1, -294, 1, 0)
	right.BackgroundTransparency = 1
	right.BorderSizePixel = 0
	right.ScrollBarThickness = 5
	right.ScrollBarImageColor3 = COLORS.Cyan
	right.AutomaticCanvasSize = Enum.AutomaticSize.Y
	right.CanvasSize = UDim2.new()
	right.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = right

	for _, level in ipairs(universe.Levels or {}) do
		local unlocked = level.Unlocked == true
		local completed = level.Completed == true
		local selected = selectedPhaseId == level.PhaseId

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -7, 0, 126)
		card.BackgroundColor3 = completed
			and Color3.fromRGB(23, 55, 54)
			or unlocked and COLORS.GlassRaised
			or Color3.fromRGB(34, 39, 49)
		card.BackgroundTransparency = 0.05
		card.BorderSizePixel = 0
		card.Parent = right
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

		local stroke = Instance.new("UIStroke")
		stroke.Color = selected and COLORS.Gold
			or completed and COLORS.Green
			or unlocked and COLORS.Cyan
			or COLORS.Locked
		stroke.Transparency = selected and 0.08 or 0.42
		stroke.Thickness = selected and 1.5 or 1
		stroke.Parent = card

		local number = Instance.new("TextLabel")
		number.Position = UDim2.fromOffset(11, 10)
		number.Size = UDim2.fromOffset(68, 68)
		number.BackgroundColor3 = unlocked
			and Color3.fromRGB(25, 61, 78)
			or Color3.fromRGB(48, 52, 61)
		number.BorderSizePixel = 0
		number.Text = unlocked and tostring(level.LevelNumber or "?") or "🔒"
		number.TextColor3 = completed and COLORS.Green or unlocked and COLORS.CyanSoft or COLORS.Locked
		number.Font = Enum.Font.GothamBlack
		number.TextSize = 23
		number.Parent = card
		Instance.new("UICorner", number).CornerRadius = UDim.new(0, 13)

		local levelTitle = Instance.new("TextLabel")
		levelTitle.Position = UDim2.fromOffset(92, 9)
		levelTitle.Size = UDim2.new(1, -292, 0, 25)
		levelTitle.BackgroundTransparency = 1
		levelTitle.Text = string.upper(tostring(level.LevelDisplayName or level.DisplayName or level.PhaseId))
		levelTitle.TextColor3 = unlocked and COLORS.Text or COLORS.Locked
		levelTitle.Font = Enum.Font.GothamBlack
		levelTitle.TextSize = 12
		levelTitle.TextXAlignment = Enum.TextXAlignment.Left
		levelTitle.TextTruncate = Enum.TextTruncate.AtEnd
		levelTitle.Parent = card

		local info = Instance.new("TextLabel")
		info.Position = UDim2.fromOffset(92, 35)
		info.Size = UDim2.new(1, -292, 0, 37)
		info.BackgroundTransparency = 1
		info.Text = unlocked
			and string.format(
				"%d objetivos • até %d jogadores • +%d moedas",
				tonumber(level.BaseIslandCount) or 12,
				tonumber(level.MaxPlayers) or 4,
				tonumber(level.VictoryCoins) or 0
			)
			or tostring(level.LockReason or "Nível bloqueado")
		info.TextColor3 = unlocked and COLORS.Muted or COLORS.Orange
		info.Font = Enum.Font.GothamMedium
		info.TextSize = 8
		info.TextWrapped = true
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Top
		info.Parent = card

		local record = Instance.new("TextLabel")
		record.Position = UDim2.fromOffset(92, 78)
		record.Size = UDim2.new(1, -292, 0, 25)
		record.BackgroundTransparency = 1
		if completed then
			record.Text = string.format(
				"✓ %d conclusão(ões) • melhor %s",
				tonumber(level.Completions) or 0,
				formatTime(level.BestTime)
			)
			record.TextColor3 = COLORS.Green
		elseif unlocked then
			record.Text = "DISPONÍVEL"
			record.TextColor3 = COLORS.Cyan
		else
			record.Text = "BLOQUEADO"
			record.TextColor3 = COLORS.Locked
		end
		record.Font = Enum.Font.GothamBold
		record.TextSize = 8
		record.TextXAlignment = Enum.TextXAlignment.Left
		record.Parent = card

		local action = actionButton(
			card,
			unlocked and (universe.IsLeader and "JOGAR" or "AGUARDE O LÍDER") or "BLOQUEADO",
			unlocked and (completed and Color3.fromRGB(38, 110, 80) or Color3.fromRGB(31, 94, 107))
				or Color3.fromRGB(53, 58, 68)
		)
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -12, 0.5, 0)
		action.Active = unlocked and universe.IsLeader == true
		action.AutoButtonColor = action.Active

		if action.Active then
			action.Activated:Connect(function()
				local result = invoke(phaseRequest, "Start", { PhaseId = level.PhaseId })
				if result then showToast(result.Message, result.Success) end
			end)
		elseif not unlocked then
			action.Activated:Connect(function()
				showToast(level.LockReason or "Conclua o nível anterior.", false)
			end)
		end
	end

	local back = Instance.new("TextButton")
	back.Position = UDim2.new(0, 18, 0, 12)
	back.Size = UDim2.fromOffset(120, 32)
	back.BackgroundTransparency = 1
	back.Text = "‹ UNIVERSOS"
	back.TextColor3 = COLORS.CyanSoft
	back.Font = Enum.Font.GothamBold
	back.TextSize = 9
	back.ZIndex = 54
	back.Parent = panel
	back.Activated:Connect(function()
		local result = invoke(phaseRequest, "GetUniverses", {})
		if result and result.Success then renderUniverseBrowser(result.Universes) end
	end)
	task.delay(0, function()
		if not overlay.Visible and back.Parent then back:Destroy() end
	end)
end
_G.__SkyDungeonRenderUniverse = renderUniverse

local function renderRoulette(snapshot)
	open(snapshot.DisplayName or "ROLETA", "Gire para receber moedas, equipamentos ou outros prêmios.")

	updateCoins(snapshot.Coins)

	local wheel = Instance.new("TextLabel")
	wheel.AnchorPoint = Vector2.new(0.5, 0)
	wheel.Position = UDim2.new(0.5, 0, 0, 20)
	wheel.Size = UDim2.fromOffset(240, 240)
	wheel.BackgroundColor3 = Color3.fromRGB(37, 38, 65)
	wheel.BorderSizePixel = 0
	wheel.Text = "✦"
	wheel.TextColor3 = COLORS.GoldSoft
	wheel.Font = Enum.Font.GothamBlack
	wheel.TextSize = 78
	wheel.Parent = content
	Instance.new("UICorner", wheel).CornerRadius = UDim.new(1, 0)
	local wheelStroke = Instance.new("UIStroke")
	wheelStroke.Color = COLORS.Gold
	wheelStroke.Thickness = 2
	wheelStroke.Transparency = 0.16
	wheelStroke.Parent = wheel

	local cost = Instance.new("TextLabel")
	cost.AnchorPoint = Vector2.new(0.5, 0)
	cost.Position = UDim2.new(0.5, 0, 0, 280)
	cost.Size = UDim2.fromOffset(430, 70)
	cost.BackgroundColor3 = COLORS.GlassRaised
	cost.BackgroundTransparency = 0.06
	cost.BorderSizePixel = 0
	cost.Text = string.format(
		"CUSTO: %d %s\nSALDO: %d MOEDAS",
		snapshot.CostAmount or 0,
		snapshot.CostType or "Coins",
		snapshot.Coins or 0
	)
	cost.TextColor3 = COLORS.Text
	cost.Font = Enum.Font.GothamBold
	cost.TextSize = 11
	cost.TextWrapped = true
	cost.Parent = content
	Instance.new("UICorner", cost).CornerRadius = UDim.new(0, 13)

	local spin = actionButton(content, "GIRAR", Color3.fromRGB(131, 91, 32))
	spin.AnchorPoint = Vector2.new(0.5, 0)
	spin.Position = UDim2.new(0.5, 0, 0, 372)
	spin.Size = UDim2.fromOffset(280, 52)
	spin.Activated:Connect(function()
		local result = invoke(rouletteRequest, "Spin", snapshot.WheelId)
		if result and not result.Success then
			showToast(result.Message, false)
			if result.Snapshot then renderRoulette(result.Snapshot) end
		end
	end)
end

local function renderEquipment(snapshot)
	open("EQUIPAMENTOS", "O que você equipa aqui será levado para a próxima Dungeon.")

	local categories = Instance.new("ScrollingFrame")
	categories.Size = UDim2.fromScale(1, 1)
	categories.BackgroundTransparency = 1
	categories.BorderSizePixel = 0
	categories.ScrollBarThickness = 5
	categories.ScrollBarImageColor3 = COLORS.Cyan
	categories.AutomaticCanvasSize = Enum.AutomaticSize.Y
	categories.CanvasSize = UDim2.new()
	categories.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.Parent = categories

	for _, category in ipairs({ "Swords", "Wings", "Companions", "Abilities" }) do
		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, -7, 0, 30)
		header.BackgroundTransparency = 1
		header.Text = string.upper(category)
		header.TextColor3 = COLORS.GoldSoft
		header.Font = Enum.Font.GothamBlack
		header.TextSize = 11
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Parent = categories

		local owned = 0
		for _, entry in ipairs(snapshot[category] or {}) do
			if entry.Owned then
				owned += 1
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, -7, 0, 62)
				row.BackgroundColor3 = entry.Equipped
					and Color3.fromRGB(26, 63, 58)
					or COLORS.GlassRaised
				row.BackgroundTransparency = 0.06
				row.BorderSizePixel = 0
				row.Parent = categories
				Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

				local name = Instance.new("TextLabel")
				name.Position = UDim2.fromOffset(13, 7)
				name.Size = UDim2.new(1, -210, 0, 24)
				name.BackgroundTransparency = 1
				name.Text = entry.DisplayName
				name.TextColor3 = entry.Equipped and COLORS.Green or COLORS.Text
				name.Font = Enum.Font.GothamBold
				name.TextSize = 10
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.Parent = row

				local state = Instance.new("TextLabel")
				state.Position = UDim2.fromOffset(13, 31)
				state.Size = UDim2.new(1, -210, 0, 18)
				state.BackgroundTransparency = 1
				state.Text = entry.Equipped and "✓ EQUIPADO" or "DESBLOQUEADO"
				state.TextColor3 = entry.Equipped and COLORS.Green or COLORS.Muted
				state.Font = Enum.Font.GothamBold
				state.TextSize = 8
				state.TextXAlignment = Enum.TextXAlignment.Left
				state.Parent = row

				local equip = actionButton(
					row,
					entry.Equipped and "EQUIPADO" or "EQUIPAR",
					entry.Equipped and Color3.fromRGB(39, 90, 69) or Color3.fromRGB(34, 85, 101)
				)
				equip.AnchorPoint = Vector2.new(1, 0.5)
				equip.Position = UDim2.new(1, -10, 0.5, 0)
				equip.Size = UDim2.fromOffset(160, 38)
				equip.Active = not entry.Equipped
				equip.AutoButtonColor = equip.Active
				if equip.Active then
					equip.Activated:Connect(function()
						local result = invoke(equipmentRequest, "Set", category, entry.EquipmentId)
						if result then
							showToast(result.Message, result.Success)
							if result.Snapshot then renderEquipment(result.Snapshot) end
						end
					end)
				end
			end
		end

		if owned == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, -7, 0, 48)
			empty.BackgroundColor3 = Color3.fromRGB(39, 43, 52)
			empty.BackgroundTransparency = 0.10
			empty.BorderSizePixel = 0
			empty.Text = "Nenhum item desbloqueado nesta categoria."
			empty.TextColor3 = COLORS.Muted
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 9
			empty.Parent = categories
			Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 11)
		end
	end
end

worldsButton.Activated:Connect(function()
	local result = invoke(phaseRequest, "GetUniverses", {})
	if result and result.Success then
		renderUniverseBrowser(result.Universes)
	end
end)

equipmentButton.Activated:Connect(function()
	local result = invoke(equipmentRequest, "Get")
	if result and result.Success and result.Snapshot then
		renderEquipment(result.Snapshot)
	end
end)

rouletteButton.Activated:Connect(function()
	local result = invoke(rouletteRequest, "Get", "BasicWheel")
	if result and result.Success and result.Snapshot then
		renderRoulette(result.Snapshot)
	end
end)

phaseEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.Action == "OpenUniverse" and data.Universe then
		renderUniverse(data.Universe, data.SelectedPhaseId)
	elseif data.Action == "Open" and data.Phase then
		local result = invoke(phaseRequest, "GetUniverse", { UniverseId = data.Phase.UniverseId })
		if result and result.Success and result.Universe then
			renderUniverse(result.Universe, data.Phase.PhaseId)
		end
	elseif data.Action == "TeleportCountdown" then
		showToast(
			string.format("Entrando em %s em %d segundos...", tostring(data.PhaseId), tonumber(data.Seconds) or 0),
			true
		)
	elseif data.Action == "TeleportCancelled" then
		showToast(data.Message or "Início cancelado.", false)
	end
end)

rouletteEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.Action == "Open" and data.Snapshot then
		renderRoulette(data.Snapshot)
	elseif data.Action == "SpinResult" then
		local result = data.Result or {}
		showToast(string.format(
			"Prêmio: %s x%d%s",
			tostring(result.RewardId),
			result.Amount or 1,
			result.ConvertedDuplicate and " • duplicado convertido em moedas" or ""
		), true)
		if data.Snapshot then
			updateCoins(data.Snapshot.Coins)
			task.delay(0.4, function()
				if overlay.Visible then renderRoulette(data.Snapshot) end
			end)
		end
	end
end)

equipmentEvent.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Action == "Open" and data.Snapshot then
		renderEquipment(data.Snapshot)
	end
end)

notificationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.Action == "ReturnToLobby" then
		if data.ReturnReason == "Victory" then
			showToast("Vitória registrada. Novos níveis podem ter sido desbloqueados!", true)
		elseif data.ReturnReason == "Defeat" then
			showToast("A expedição terminou. Ajuste seus equipamentos e tente novamente.", false)
		else
			showToast("Você retornou ao Lobby.", true)
		end
	end
end)

local function refreshResponsiveScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local target = math.min(viewport.X / 1280, viewport.Y / 720)
	if UserInputService.TouchEnabled then
		target = math.min(target, 0.92)
	end
	scale.Scale = math.clamp(target, 0.62, 1)
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshResponsiveScale)
RunService.RenderStepped:Connect(function()
	refreshResponsiveScale()
end)

-- Atualiza o saldo inicial sem abrir a roleta.
task.defer(function()
	local result = invoke(rouletteRequest, "Get", "BasicWheel")
	if result and result.Success and result.Snapshot then
		updateCoins(result.Snapshot.Coins)
	end
end)

player:SetAttribute("LobbyCrystalCelestialUIReady", true)
workspace:SetAttribute("LobbyCrystalCelestialUIReady", true)
workspace:SetAttribute("LobbyUIArchitecture", "UniverseToLevelsHubV1")
