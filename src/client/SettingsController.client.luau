-- Configuracoes locais e compactas do jogador.
-- Volume e desempenho afetam somente este cliente.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MUSIC_GROUP_NAME = "SkyDungeonMusic"
local PANEL_OWNER = "Settings"
local DEFAULT_MUSIC_VOLUME = 1

local musicVolume = DEFAULT_MUSIC_VOLUME
local forcePerformanceMode = false
local draggingSlider = false

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 14
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "SettingsButton"
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -68, 0, 12)
button.Size = UDim2.fromOffset(48, 38)
button.BackgroundColor3 = Color3.fromRGB(23, 31, 48)
button.BackgroundTransparency = 0.18
button.BorderSizePixel = 0
button.Text = "⚙"
button.TextColor3 = Color3.fromRGB(205, 221, 240)
button.Font = Enum.Font.GothamMedium
button.TextSize = 22
button.AutoButtonColor = true
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(118, 151, 184)
buttonStroke.Transparency = 0.7
buttonStroke.Parent = button

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 58)
panel.Size = UDim2.fromOffset(286, 194)
panel.BackgroundColor3 = Color3.fromRGB(14, 19, 30)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 13)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(118, 151, 184)
panelStroke.Transparency = 0.62
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(14, 8)
title.Size = UDim2.new(1, -55, 0, 32)
title.BackgroundTransparency = 1
title.Text = "CONFIGURAÇÕES"
title.TextColor3 = Color3.fromRGB(235, 240, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -8, 0, 7)
closeButton.Size = UDim2.fromOffset(34, 32)
closeButton.BackgroundTransparency = 1
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(174, 187, 205)
closeButton.Font = Enum.Font.GothamMedium
closeButton.TextSize = 24
closeButton.Parent = panel

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(12, 43)
divider.Size = UDim2.new(1, -24, 0, 1)
divider.BackgroundColor3 = Color3.fromRGB(89, 107, 132)
divider.BackgroundTransparency = 0.55
divider.BorderSizePixel = 0
divider.Parent = panel

local musicLabel = Instance.new("TextLabel")
musicLabel.Position = UDim2.fromOffset(14, 51)
musicLabel.Size = UDim2.fromOffset(190, 25)
musicLabel.BackgroundTransparency = 1
musicLabel.Text = "Música"
musicLabel.TextColor3 = Color3.fromRGB(220, 229, 241)
musicLabel.Font = Enum.Font.GothamMedium
musicLabel.TextSize = 13
musicLabel.TextXAlignment = Enum.TextXAlignment.Left
musicLabel.Parent = panel

local volumeLabel = Instance.new("TextLabel")
volumeLabel.AnchorPoint = Vector2.new(1, 0)
volumeLabel.Position = UDim2.new(1, -14, 0, 51)
volumeLabel.Size = UDim2.fromOffset(52, 25)
volumeLabel.BackgroundTransparency = 1
volumeLabel.Text = "100%"
volumeLabel.TextColor3 = Color3.fromRGB(109, 190, 255)
volumeLabel.Font = Enum.Font.GothamBold
volumeLabel.TextSize = 12
volumeLabel.TextXAlignment = Enum.TextXAlignment.Right
volumeLabel.Parent = panel

local minusButton = Instance.new("TextButton")
minusButton.Position = UDim2.fromOffset(14, 79)
minusButton.Size = UDim2.fromOffset(30, 28)
minusButton.BackgroundColor3 = Color3.fromRGB(42, 54, 73)
minusButton.BorderSizePixel = 0
minusButton.Text = "−"
minusButton.TextColor3 = Color3.fromRGB(225, 232, 242)
minusButton.Font = Enum.Font.GothamBold
minusButton.TextSize = 18
minusButton.Parent = panel
Instance.new("UICorner", minusButton).CornerRadius = UDim.new(0, 7)

local plusButton = minusButton:Clone()
plusButton.Name = "VolumeUp"
plusButton.AnchorPoint = Vector2.new(1, 0)
plusButton.Position = UDim2.new(1, -14, 0, 79)
plusButton.Text = "+"
plusButton.Parent = panel

local slider = Instance.new("TextButton")
slider.Name = "MusicSlider"
slider.Position = UDim2.fromOffset(53, 79)
slider.Size = UDim2.new(1, -106, 0, 28)
slider.BackgroundTransparency = 1
slider.BorderSizePixel = 0
slider.Text = ""
slider.AutoButtonColor = false
slider.Parent = panel

local sliderTrack = Instance.new("Frame")
sliderTrack.AnchorPoint = Vector2.new(0, 0.5)
sliderTrack.Position = UDim2.fromScale(0, 0.5)
sliderTrack.Size = UDim2.new(1, 0, 0, 5)
sliderTrack.BackgroundColor3 = Color3.fromRGB(54, 68, 88)
sliderTrack.BorderSizePixel = 0
sliderTrack.Parent = slider
Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1, 0)

local sliderFill = Instance.new("Frame")
sliderFill.Name = "Fill"
sliderFill.Size = UDim2.fromScale(1, 1)
sliderFill.BackgroundColor3 = Color3.fromRGB(36, 153, 255)
sliderFill.BorderSizePixel = 0
sliderFill.Parent = sliderTrack
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)

local sliderKnob = Instance.new("Frame")
sliderKnob.Name = "Knob"
sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sliderKnob.Position = UDim2.fromScale(1, 0.5)
sliderKnob.Size = UDim2.fromOffset(14, 14)
sliderKnob.BackgroundColor3 = Color3.fromRGB(224, 241, 255)
sliderKnob.BorderSizePixel = 0
sliderKnob.Parent = sliderTrack
Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(1, 0)

local performanceRow = Instance.new("Frame")
performanceRow.Position = UDim2.fromOffset(14, 121)
performanceRow.Size = UDim2.new(1, -28, 0, 58)
performanceRow.BackgroundColor3 = Color3.fromRGB(25, 34, 49)
performanceRow.BackgroundTransparency = 0.14
performanceRow.BorderSizePixel = 0
performanceRow.Parent = panel
Instance.new("UICorner", performanceRow).CornerRadius = UDim.new(0, 9)

local performanceLabel = Instance.new("TextLabel")
performanceLabel.Position = UDim2.fromOffset(10, 5)
performanceLabel.Size = UDim2.new(1, -80, 0, 24)
performanceLabel.BackgroundTransparency = 1
performanceLabel.Text = "Desempenho adaptativo"
performanceLabel.TextColor3 = Color3.fromRGB(226, 233, 243)
performanceLabel.Font = Enum.Font.GothamMedium
performanceLabel.TextSize = 13
performanceLabel.TextXAlignment = Enum.TextXAlignment.Left
performanceLabel.Parent = performanceRow

local performanceHint = Instance.new("TextLabel")
performanceHint.Position = UDim2.fromOffset(10, 28)
performanceHint.Size = UDim2.new(1, -80, 0, 22)
performanceHint.BackgroundTransparency = 1
performanceHint.Text = "AUTO • aguardando medição de FPS"
performanceHint.TextColor3 = Color3.fromRGB(145, 159, 180)
performanceHint.Font = Enum.Font.Gotham
performanceHint.TextSize = 10
performanceHint.TextXAlignment = Enum.TextXAlignment.Left
performanceHint.Parent = performanceRow

local performanceButton = Instance.new("TextButton")
performanceButton.Name = "PerformanceToggle"
performanceButton.AnchorPoint = Vector2.new(1, 0.5)
performanceButton.Position = UDim2.new(1, -10, 0.5, 0)
performanceButton.Size = UDim2.fromOffset(58, 30)
performanceButton.BackgroundColor3 = Color3.fromRGB(55, 65, 82)
performanceButton.BorderSizePixel = 0
performanceButton.Text = "AUTO"
performanceButton.TextColor3 = Color3.fromRGB(201, 209, 221)
performanceButton.Font = Enum.Font.GothamBold
performanceButton.TextSize = 11
performanceButton.Parent = performanceRow
Instance.new("UICorner", performanceButton).CornerRadius = UDim.new(1, 0)

local function getMusicGroup()
	local group = SoundService:FindFirstChild(MUSIC_GROUP_NAME)
	if group and group:IsA("SoundGroup") then
		return group
	end
	return nil
end

local function applyMusicVolume()
	local group = getMusicGroup()
	if group then
		group.Volume = musicVolume
	end
	volumeLabel.Text = string.format("%d%%", math.floor(musicVolume * 100 + 0.5))
	sliderFill.Size = UDim2.fromScale(musicVolume, 1)
	sliderKnob.Position = UDim2.fromScale(musicVolume, 0.5)
end

local function setMusicVolume(value)
	musicVolume = math.clamp(math.round(value * 10) / 10, 0, 1)
	applyMusicVolume()
end

local function setVolumeFromScreenPosition(x)
	local left = slider.AbsolutePosition.X
	local width = slider.AbsoluteSize.X
	if width > 0 then
		setMusicVolume((x - left) / width)
	end
end

local function refreshPerformanceUI()
	forcePerformanceMode = player:GetAttribute("ForcePerformanceMode") == true
	local level = tonumber(player:GetAttribute("PerformanceLevel")) or 0
	local tier = tostring(player:GetAttribute("PerformanceTier") or "Normal")
	local fps = tonumber(player:GetAttribute("MeasuredFPS"))

	performanceButton.Text = forcePerformanceMode and "MAX" or "AUTO"
	performanceButton.BackgroundColor3 = forcePerformanceMode
		and Color3.fromRGB(190, 91, 44)
		or Color3.fromRGB(34, 139, 95)
	performanceButton.TextColor3 = Color3.fromRGB(231, 255, 243)

	if forcePerformanceMode then
		performanceHint.Text = "MAX • otimização extrema forçada"
	elseif fps then
		performanceHint.Text = string.format("AUTO • %s • %d FPS", tier, math.floor(fps + 0.5))
	else
		performanceHint.Text = string.format("AUTO • %s", tier)
	end

	performanceLabel.TextColor3 = level >= 2
		and Color3.fromRGB(255, 191, 120)
		or Color3.fromRGB(226, 233, 243)
end

local function setPanelVisible(visible)
	panel.Visible = visible
	button.BackgroundColor3 = visible and Color3.fromRGB(42, 74, 105) or Color3.fromRGB(23, 31, 48)
	if visible then
		playerGui:SetAttribute("SkyDungeonExclusivePanel", PANEL_OWNER)
	end
end

button.MouseButton1Click:Connect(function()
	setPanelVisible(not panel.Visible)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

minusButton.MouseButton1Click:Connect(function()
	setMusicVolume(musicVolume - 0.1)
end)

plusButton.MouseButton1Click:Connect(function()
	setMusicVolume(musicVolume + 0.1)
end)

slider.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingSlider = true
		setVolumeFromScreenPosition(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not draggingSlider then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		setVolumeFromScreenPosition(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingSlider = false
	end
end)

performanceButton.MouseButton1Click:Connect(function()
	forcePerformanceMode = not forcePerformanceMode
	player:SetAttribute("ForcePerformanceMode", forcePerformanceMode)
	refreshPerformanceUI()
end)

playerGui:GetAttributeChangedSignal("SkyDungeonExclusivePanel"):Connect(function()
	if playerGui:GetAttribute("SkyDungeonExclusivePanel") ~= PANEL_OWNER then
		setPanelVisible(false)
	end
end)

SoundService.ChildAdded:Connect(function(child)
	if child.Name == MUSIC_GROUP_NAME then
		task.defer(applyMusicVolume)
	end
end)

for _, attributeName in ipairs({
	"ForcePerformanceMode",
	"PerformanceLevel",
	"PerformanceTier",
	"MeasuredFPS",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(refreshPerformanceUI)
end

if player:GetAttribute("ForcePerformanceMode") == nil then
	player:SetAttribute("ForcePerformanceMode", false)
end
applyMusicVolume()
refreshPerformanceUI()
