--[[
	Infinity Islands - Mobile Accessibility

	Uma unica UI pequena para preferencias locais do mobile.
	O botao Aa fica diretamente ao lado esquerdo do SettingsButton.
	Nao reposiciona nenhum controle de combate autorado no Studio.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonMobileAccessibilityV2_BesideSettings"
local PANEL_OWNER = "Accessibility"
local UPDATE_INTERVAL = 0.25

local COLORS = {
	Glass = Color3.fromRGB(12, 25, 39),
	Raised = Color3.fromRGB(26, 48, 66),
	Text = Color3.fromRGB(243, 249, 253),
	Muted = Color3.fromRGB(161, 187, 207),
	Cyan = Color3.fromRGB(105, 224, 255),
	Green = Color3.fromRGB(103, 232, 165),
	Off = Color3.fromRGB(88, 107, 123),
	Backdrop = Color3.fromRGB(4, 9, 14),
}

local SETTINGS = {
	{
		Key = "ClientSetting_LargeUI",
		Title = "Interface maior",
		Detail = "Aumenta texto e elementos de leitura.",
		Default = false,
	},
	{
		Key = "ClientSetting_LargeControls",
		Title = "Controles maiores",
		Detail = "Aumenta a escala sugerida dos controles.",
		Default = false,
	},
	{
		Key = "ClientSetting_ReducedEffects",
		Title = "Reduzir efeitos",
		Detail = "Diminui efeitos visuais intensos.",
		Default = false,
	},
	{
		Key = "ClientSetting_WorldMarkers",
		Title = "Indicadores de perigo",
		Detail = "Mantem marcadores uteis no mundo.",
		Default = true,
	},
	{
		Key = "ClientSetting_Haptics",
		Title = "Vibracao",
		Detail = "Feedback tatil quando suportado.",
		Default = true,
	},
}

local gui
local accessButton
local backdrop
local panel
local rows = {}
local active = false
local elapsed = 0

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
end

local function ensureBool(name, defaultValue)
	if player:GetAttribute(name) == nil then
		player:SetAttribute(name, defaultValue)
	end
	return player:GetAttribute(name) == true
end

local function publishScales()
	local largeUi = ensureBool("ClientSetting_LargeUI", false)
	local largeControls = ensureBool("ClientSetting_LargeControls", false)

	player:SetAttribute("DungeonMobileUIUserScale", largeUi and 1.08 or 1)
	player:SetAttribute("DungeonMobileTextUserScale", largeUi and 1.16 or 1)
	player:SetAttribute("DungeonMobileTouchUserScale", largeControls and 1.15 or 1)
end

local function addCorner(object, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = object
end

local function addStroke(object, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.Parent = object
end

local function label(parent, text, position, size, textSize, bold)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = position
	item.Size = size
	item.Text = text
	item.TextColor3 = COLORS.Text
	item.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	item.TextSize = textSize
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextWrapped = true
	item.ZIndex = parent.ZIndex + 1
	item.Parent = parent
	return item
end

local function panelOpen()
	return panel and panel.Visible == true
end

local function setPanelOpen(value)
	local open = value == true
	if panel then
		panel.Visible = open
	end
	if backdrop then
		backdrop.Visible = open
	end
	player:SetAttribute("DungeonMobileAccessibilityPanelOpen", open)

	if open then
		playerGui:SetAttribute("SkyDungeonExclusivePanel", PANEL_OWNER)
	elseif playerGui:GetAttribute("SkyDungeonExclusivePanel") == PANEL_OWNER then
		playerGui:SetAttribute("SkyDungeonExclusivePanel", nil)
	end
end

local function refreshRow(row)
	local enabled = player:GetAttribute(row.Definition.Key) == true
	row.Toggle.Text = enabled and "ON" or "OFF"
	row.Toggle.BackgroundColor3 = enabled and COLORS.Green or COLORS.Off
	row.Toggle.TextColor3 = enabled and Color3.fromRGB(12, 39, 31) or COLORS.Text
end

local function createRow(parent, definition, y)
	local frame = Instance.new("Frame")
	frame.Name = definition.Key
	frame.Position = UDim2.fromOffset(12, y)
	frame.Size = UDim2.new(1, -24, 0, 46)
	frame.BackgroundColor3 = COLORS.Raised
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.ZIndex = panel.ZIndex + 1
	frame.Parent = parent
	addCorner(frame, 9)

	label(
		frame,
		definition.Title,
		UDim2.fromOffset(11, 5),
		UDim2.new(1, -80, 0, 17),
		10,
		true
	)

	local detail = label(
		frame,
		definition.Detail,
		UDim2.fromOffset(11, 22),
		UDim2.new(1, -80, 0, 18),
		8,
		false
	)
	detail.TextColor3 = COLORS.Muted

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, -9, 0.5, 0)
	toggle.Size = UDim2.fromOffset(53, 29)
	toggle.BackgroundColor3 = COLORS.Off
	toggle.BorderSizePixel = 0
	toggle.TextColor3 = COLORS.Text
	toggle.Font = Enum.Font.GothamBlack
	toggle.TextSize = 9
	toggle.ZIndex = frame.ZIndex + 2
	toggle.Parent = frame
	addCorner(toggle, 14)

	local row = {
		Definition = definition,
		Frame = frame,
		Toggle = toggle,
	}
	table.insert(rows, row)

	toggle.Activated:Connect(function()
		player:SetAttribute(definition.Key, not (player:GetAttribute(definition.Key) == true))
		publishScales()
		refreshRow(row)
	end)

	refreshRow(row)
end

local function createGui()
	local old = playerGui:FindFirstChild("DungeonMobileAccessibilityUI")
	if old then
		old:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "DungeonMobileAccessibilityUI"
	gui.ResetOnSpawn = false
	-- SettingsUI usa o inset padrao; usar a mesma referencia deixa os botoes alinhados.
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 125
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	accessButton = Instance.new("TextButton")
	accessButton.Name = "AccessibilityButton"
	accessButton.AnchorPoint = Vector2.new(1, 0)
	accessButton.Position = UDim2.new(1, -74, 0, 318)
	accessButton.Size = UDim2.fromOffset(40, 38)
	accessButton.BackgroundColor3 = COLORS.Glass
	accessButton.BackgroundTransparency = 0.04
	accessButton.BorderSizePixel = 0
	accessButton.Text = "Aa"
	accessButton.TextColor3 = COLORS.Cyan
	accessButton.Font = Enum.Font.GothamBlack
	accessButton.TextSize = 14
	accessButton.ZIndex = 126
	accessButton.Parent = gui
	addCorner(accessButton, 10)
	addStroke(accessButton, COLORS.Cyan, 0.26, 1.2)

	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = COLORS.Backdrop
	backdrop.BackgroundTransparency = 0.32
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.ZIndex = 130
	backdrop.Parent = gui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(330, 330)
	panel.BackgroundColor3 = COLORS.Glass
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 131
	panel.Parent = gui
	addCorner(panel, 16)
	addStroke(panel, COLORS.Cyan, 0.24, 1.3)

	local title = label(
		panel,
		"ACESSIBILIDADE",
		UDim2.fromOffset(14, 10),
		UDim2.new(1, -58, 0, 24),
		14,
		true
	)
	title.TextColor3 = COLORS.Cyan

	local subtitle = label(
		panel,
		"Ajustes do mobile",
		UDim2.fromOffset(14, 31),
		UDim2.new(1, -58, 0, 18),
		8,
		false
	)
	subtitle.TextColor3 = COLORS.Muted

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 9)
	close.Size = UDim2.fromOffset(34, 30)
	close.BackgroundColor3 = COLORS.Raised
	close.BorderSizePixel = 0
	close.Text = "x"
	close.TextColor3 = COLORS.Text
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.ZIndex = panel.ZIndex + 2
	close.Parent = panel
	addCorner(close, 9)

	table.clear(rows)
	for index, definition in ipairs(SETTINGS) do
		ensureBool(definition.Key, definition.Default)
		createRow(panel, definition, 55 + (index - 1) * 51)
	end

	accessButton.Activated:Connect(function()
		setPanelOpen(not panelOpen())
	end)
	close.Activated:Connect(function()
		setPanelOpen(false)
	end)
	backdrop.Activated:Connect(function()
		setPanelOpen(false)
	end)
end

local function settingsButton()
	local settingsGui = playerGui:FindFirstChild("SettingsUI")
	local candidate = settingsGui and settingsGui:FindFirstChild("SettingsButton", true)
	return candidate and candidate:IsA("GuiButton") and candidate or nil
end

local function layout()
	if not accessButton or not panel then
		return
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
	panel.Size = UDim2.fromOffset(math.clamp(viewport.X - 26, 286, 360), 330)

	local settings = settingsButton()
	if settings then
		-- SettingsButton: AnchorPoint (1,0). O Aa usa a mesma referencia e fica
		-- imediatamente a esquerda, com 8 px de espaco.
		local gap = 8
		local settingsWidth = settings.AbsoluteSize.X > 0 and settings.AbsoluteSize.X or 48
		accessButton.AnchorPoint = Vector2.new(1, 0)
		accessButton.Position = UDim2.new(
			settings.Position.X.Scale,
			settings.Position.X.Offset - settingsWidth - gap,
			settings.Position.Y.Scale,
			settings.Position.Y.Offset
		)
		accessButton.Size = UDim2.fromOffset(40, math.max(34, settings.AbsoluteSize.Y > 0 and settings.AbsoluteSize.Y or 38))
		player:SetAttribute("DungeonAccessibilityBesideSettings", true)
	else
		accessButton.AnchorPoint = Vector2.new(1, 0)
		accessButton.Position = UDim2.new(1, -74, 0, 318)
		accessButton.Size = UDim2.fromOffset(40, 38)
		player:SetAttribute("DungeonAccessibilityBesideSettings", false)
	end
end

local function hideLegacyContextButtonsWhileOpen()
	if not panelOpen() then
		return
	end
	for _, actionName in ipairs({ "SkyDungeonAttack", "SkyDungeonSprint", "SkyDungeonSneak" }) do
		local button = ContextActionService:GetButton(actionName)
		if button and button:IsA("GuiButton") then
			button.Visible = false
		end
	end
end

local function refreshActivation()
	active = isMobile()
	if not gui then
		createGui()
	end
	gui.Enabled = active
	accessButton.Visible = active
	if not active then
		setPanelOpen(false)
	else
		publishScales()
		layout()
	end

	player:SetAttribute("DungeonMobileAccessibilityReady", true)
	player:SetAttribute("DungeonMobileAccessibilityActive", active)
	player:SetAttribute("DungeonMobileAccessibilityVersion", VERSION)
	player:SetAttribute("DungeonMobileAccessibilityPolicy", "BesideSettingsSessionPreferences")
end

for _, definition in ipairs(SETTINGS) do
	ensureBool(definition.Key, definition.Default)
	player:GetAttributeChangedSignal(definition.Key):Connect(function()
		publishScales()
		for _, row in ipairs(rows) do
			if row.Definition.Key == definition.Key then
				refreshRow(row)
				break
			end
		end
	end)
end

playerGui:GetAttributeChangedSignal("SkyDungeonExclusivePanel"):Connect(function()
	local owner = playerGui:GetAttribute("SkyDungeonExclusivePanel")
	if owner ~= nil and owner ~= PANEL_OWNER and panelOpen() then
		setPanelOpen(false)
	end
end)

playerGui.DescendantAdded:Connect(function(instance)
	if instance.Name == "SettingsButton" then
		task.defer(layout)
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

RunService.Heartbeat:Connect(function(deltaTime)
	if not active then
		return
	end
	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	layout()
	hideLegacyContextButtonsWhileOpen()
end)

createGui()
publishScales()
refreshActivation()

player:SetAttribute("DungeonMobileAccessibilityControllerLoaded", true)
