-- Mobile Dungeon Mode — Task 17: Device Scaling + Accessibility.
--
-- Preferencias desta versao sao locais por sessao. Se um sistema persistente
-- publicar os mesmos Attributes antes deste controller iniciar, eles sao
-- preservados e usados em vez dos defaults.
--
-- Integracoes:
-- ClientSetting_ReducedEffects -> Tasks 08/09/10
-- ClientSetting_WorldMarkers   -> Task 09
-- ClientSetting_Haptics        -> Task 08
-- DungeonMobileUIUserScale     -> Task 03
-- DungeonMobileTouchUserScale  -> Task 03
-- DungeonMobileTextUserScale   -> Tasks 09/10/11

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonMobileAccessibilityV1"
local RENDER_STEP = "InfinityIslandsMobileAccessibility"
local UPDATE_INTERVAL = 0.20

local ACTIONS_TO_HIDE = {
	"SkyDungeonAttack",
	"SkyDungeonSprint",
	"SkyDungeonSneak",
}

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

local active = false
local elapsed = 0
local gui
local accessButton
local backdrop
local panel
local rows = {}
local viewportConnection

local function getViewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(390, 844)
end

local function getInsets()
	local topLeft = Vector2.zero
	local bottomRight = Vector2.zero
	local success, first, second = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if success then
		topLeft = typeof(first) == "Vector2" and first or Vector2.zero
		bottomRight = typeof(second) == "Vector2" and second or Vector2.zero
	end
	return topLeft, bottomRight
end

local function ensureBool(name, defaultValue)
	if player:GetAttribute(name) == nil then
		player:SetAttribute(name, defaultValue)
	end
	return player:GetAttribute(name) == true
end

local function deviceClass(viewport)
	if viewport.X < 350 or viewport.Y < 650 then
		return "CompactPhone", 0.94
	elseif viewport.X < 430 then
		return "Phone", 1.00
	elseif viewport.X < 600 then
		return "LargePhone", 1.04
	end
	return "TabletPortrait", 1.08
end

local function publishScales()
	local largeUi = ensureBool("ClientSetting_LargeUI", false)
	local largeControls = ensureBool("ClientSetting_LargeControls", false)

	player:SetAttribute(
		"DungeonMobileUIUserScale",
		largeUi and 1.08 or 1.00
	)
	player:SetAttribute(
		"DungeonMobileTextUserScale",
		largeUi and 1.16 or 1.00
	)
	player:SetAttribute(
		"DungeonMobileTouchUserScale",
		largeControls and 1.15 or 1.00
	)
end

local function publishDeviceMetrics()
	local viewport = getViewport()
	local topLeft, bottomRight = getInsets()
	local class, recommendedScale = deviceClass(viewport)

	player:SetAttribute("DungeonMobileDeviceClass", class)
	player:SetAttribute("DungeonMobileDeviceRecommendedScale", recommendedScale)
	player:SetAttribute("DungeonMobileViewportWidth", math.floor(viewport.X + 0.5))
	player:SetAttribute("DungeonMobileViewportHeight", math.floor(viewport.Y + 0.5))
	player:SetAttribute("DungeonMobileSafeInsetTop", math.floor(topLeft.Y + 0.5))
	player:SetAttribute("DungeonMobileSafeInsetBottom", math.floor(bottomRight.Y + 0.5))
	player:SetAttribute(
		"DungeonMobileCompactDevice",
		class == "CompactPhone"
	)

	publishScales()
end

local function panelOpen()
	return player:GetAttribute("DungeonMobileAccessibilityPanelOpen") == true
end

local function setPanelOpen(open)
	player:SetAttribute("DungeonMobileAccessibilityPanelOpen", open == true)
	if backdrop then
		backdrop.Visible = open == true
	end
	if panel then
		panel.Visible = open == true
	end
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

local function createLabel(parent, text, position, size, textSize, bold)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextColor3 = COLORS.Text
	label.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.ZIndex = parent.ZIndex + 1
	label.Parent = parent
	return label
end

local SETTINGS = {
	{
		Key = "ClientSetting_LargeUI",
		Title = "Texto e interface maiores",
		Detail = "Aumenta leitura sem cobrir o centro.",
		Default = false,
	},
	{
		Key = "ClientSetting_LargeControls",
		Title = "Controles maiores",
		Detail = "Aumenta o botão de ataque.",
		Default = false,
	},
	{
		Key = "ClientSetting_ReducedEffects",
		Title = "Reduzir efeitos",
		Detail = "Remove pulsos, ring e vibração.",
		Default = false,
	},
	{
		Key = "ClientSetting_WorldMarkers",
		Title = "Indicadores de perigo",
		Detail = "Setas para ameaças fora da tela.",
		Default = true,
	},
	{
		Key = "ClientSetting_Haptics",
		Title = "Vibração no acerto",
		Detail = "Feedback tátil quando suportado.",
		Default = true,
	},
}

local function rowValue(row)
	return player:GetAttribute(row.Definition.Key) == true
end

local function updateRow(row)
	local enabled = rowValue(row)
	row.Toggle.Text = enabled and "ON" or "OFF"
	row.Toggle.BackgroundColor3 = enabled and COLORS.Green or COLORS.Off
	row.Toggle.TextColor3 = enabled and Color3.fromRGB(12, 39, 31) or COLORS.Text
end

local function refreshRows()
	for _, row in ipairs(rows) do
		updateRow(row)
	end
end

local function toggleSetting(row)
	local key = row.Definition.Key
	player:SetAttribute(key, not rowValue(row))
	publishScales()
	refreshRows()
end

local function createRow(parent, definition, y)
	local row = Instance.new("Frame")
	row.Name = definition.Key
	row.Position = UDim2.fromOffset(12, y)
	row.Size = UDim2.new(1, -24, 0, 46)
	row.BackgroundColor3 = COLORS.Raised
	row.BackgroundTransparency = 0.12
	row.BorderSizePixel = 0
	row.ZIndex = panel.ZIndex + 1
	row.Parent = parent
	addCorner(row, 9)

	local title = createLabel(
		row,
		definition.Title,
		UDim2.fromOffset(11, 5),
		UDim2.new(1, -80, 0, 17),
		10,
		true
	)
	title.TextColor3 = COLORS.Text

	local detail = createLabel(
		row,
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
	toggle.AutoButtonColor = true
	toggle.Text = "OFF"
	toggle.TextColor3 = COLORS.Text
	toggle.Font = Enum.Font.GothamBlack
	toggle.TextSize = 9
	toggle.ZIndex = row.ZIndex + 2
	toggle.Parent = row
	addCorner(toggle, 14)

	local record = {
		Definition = definition,
		Frame = row,
		Title = title,
		Detail = detail,
		Toggle = toggle,
	}
	table.insert(rows, record)

	toggle.Activated:Connect(function()
		toggleSetting(record)
	end)

	updateRow(record)
end

local function createGui()
	if gui and gui.Parent then
		return
	end

	local existing = playerGui:FindFirstChild("DungeonMobileAccessibilityUI")
	if existing then
		existing:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "DungeonMobileAccessibilityUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 125
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	accessButton = Instance.new("TextButton")
	accessButton.Name = "AccessibilityButton"
	accessButton.AnchorPoint = Vector2.new(0, 0)
	accessButton.Size = UDim2.fromOffset(40, 34)
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
	panel.Position = UDim2.fromScale(0.5, 0.50)
	panel.Size = UDim2.fromOffset(330, 330)
	panel.BackgroundColor3 = COLORS.Glass
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 131
	panel.Parent = gui
	addCorner(panel, 16)
	addStroke(panel, COLORS.Cyan, 0.24, 1.3)

	local title = createLabel(
		panel,
		"ACESSIBILIDADE",
		UDim2.fromOffset(14, 10),
		UDim2.new(1, -58, 0, 24),
		14,
		true
	)
	title.TextColor3 = COLORS.Cyan

	local subtitle = createLabel(
		panel,
		"Ajustes do Dungeon mobile",
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
	close.Text = "×"
	close.TextColor3 = COLORS.Text
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.ZIndex = panel.ZIndex + 2
	close.Parent = panel
	addCorner(close, 9)

	table.clear(rows)
	for index, definition in ipairs(SETTINGS) do
		ensureBool(definition.Key, definition.Default)
		createRow(panel, definition, 55 + (index - 1) * 51)
	end

	local sessionNote = createLabel(
		panel,
		"Preferências locais desta sessão.",
		UDim2.fromOffset(14, 309),
		UDim2.new(1, -28, 0, 14),
		7,
		false
	)
	sessionNote.TextColor3 = COLORS.Muted
	sessionNote.TextXAlignment = Enum.TextXAlignment.Center

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

local function layout()
	if not gui or not accessButton or not panel then
		return
	end

	local viewport = getViewport()
	local topLeft = getInsets()
	local width = math.clamp(viewport.X - 26, 286, 360)
	local height = 330

	panel.Size = UDim2.fromOffset(width, height)

	-- Abaixo do CombatHeader e antes da faixa reservada aos threat indicators.
	accessButton.Position = UDim2.fromOffset(
		math.max(8, topLeft.X + 8),
		math.max(146, topLeft.Y + 150)
	)

	local class = tostring(player:GetAttribute("DungeonMobileDeviceClass") or "")
	accessButton.Size = class == "CompactPhone"
		and UDim2.fromOffset(38, 32)
		or UDim2.fromOffset(40, 34)
end

local function hideCombatActionsWhileOpen()
	if not panelOpen() then
		return
	end
	for _, actionName in ipairs(ACTIONS_TO_HIDE) do
		local button = ContextActionService:GetButton(actionName)
		if button and button:IsA("GuiButton") then
			button.Visible = false
		end
	end
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	createGui()
	active = true
	gui.Enabled = true

	ensureBool("ClientSetting_LargeUI", false)
	ensureBool("ClientSetting_LargeControls", false)
	ensureBool("ClientSetting_ReducedEffects", false)
	ensureBool("ClientSetting_WorldMarkers", true)
	ensureBool("ClientSetting_Haptics", true)

	publishDeviceMetrics()
	refreshRows()
	layout()

	player:SetAttribute("DungeonMobileAccessibilityReady", true)
	player:SetAttribute("DungeonMobileAccessibilityActive", true)
	player:SetAttribute("DungeonMobileAccessibilityVersion", VERSION)
	player:SetAttribute(
		"DungeonMobileAccessibilityPolicy",
		"ResponsivePortraitSessionSettingsV1"
	)
end

local function deactivate()
	if not active then
		return
	end

	active = false
	setPanelOpen(false)
	if gui then
		gui.Enabled = false
	end
	player:SetAttribute("DungeonMobileAccessibilityActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

local function bindCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if active then
				publishDeviceMetrics()
				layout()
			end
		end)
	end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera()
	if active then
		publishDeviceMetrics()
		layout()
	end
end)
bindCamera()

for _, setting in ipairs(SETTINGS) do
	player:GetAttributeChangedSignal(setting.Key):Connect(function()
		if active then
			publishScales()
			refreshRows()
		end
	end)
end

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
	publishDeviceMetrics()
	layout()
end)

RunService:BindToRenderStep(
	RENDER_STEP,
	Enum.RenderPriority.Last.Value + 10,
	hideCombatActionsWhileOpen
)

player:SetAttribute("DungeonMobileAccessibilityControllerLoaded", true)
player:SetAttribute("DungeonMobileAccessibilityVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(function()
	deactivate()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	RunService:UnbindFromRenderStep(RENDER_STEP)
end)
