-- SessionFloodHUD V29
-- Exibe tempo da sessao, contagem do santuario e alerta de dano da agua.
-- A vinheta usa uma ScreenGui separada para alcancar os cantos reais da tela.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local COUNTDOWN_ATTRIBUTE = "SanctuaryFloodCountdownEnd"
local WATER_DAMAGE_ACTIVE_ATTRIBUTE = "WaterDamageActive"
local DANGER_BANNER_SECONDS = 1.2
local DANGER_SOUND_INTERVAL = 2.4
local sessionStartedAt = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "SessionFloodHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 45
gui.Parent = playerGui

-- A interface principal respeita a area segura do Roblox, mas a vinheta precisa
-- ignorar o recuo da barra superior para encostar nas quatro bordas fisicas.
local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "SessionFloodVignette"
vignetteGui.ResetOnSpawn = false
vignetteGui.IgnoreGuiInset = true
vignetteGui.DisplayOrder = 44
vignetteGui.Parent = playerGui

local dangerOverlay = Instance.new("CanvasGroup")
dangerOverlay.Name = "WaterDamageVignette"
dangerOverlay.Position = UDim2.fromScale(0, 0)
dangerOverlay.Size = UDim2.fromScale(1, 1)
dangerOverlay.BackgroundTransparency = 1
dangerOverlay.GroupTransparency = 0.58
dangerOverlay.Visible = false
dangerOverlay.ZIndex = 1
dangerOverlay.Parent = vignetteGui

local function createDangerEdge(name, position, size, gradientRotation)
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Position = position
	edge.Size = size
	edge.BackgroundColor3 = Color3.fromRGB(255, 20, 45)
	edge.BackgroundTransparency = 0.38
	edge.BorderSizePixel = 0
	edge.ZIndex = 1
	edge.Parent = dangerOverlay

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = gradientRotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.42, 0.32),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge
end

createDangerEdge("Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.11), 90)
createDangerEdge("Bottom", UDim2.fromScale(0, 0.89), UDim2.fromScale(1, 0.11), 270)
createDangerEdge("Left", UDim2.fromScale(0, 0), UDim2.fromScale(0.08, 1), 0)
createDangerEdge("Right", UDim2.fromScale(0.92, 0), UDim2.fromScale(0.08, 1), 180)

local dangerBanner = Instance.new("Frame")
dangerBanner.Name = "WaterDamageBanner"
dangerBanner.AnchorPoint = Vector2.new(0.5, 0.5)
dangerBanner.Position = UDim2.fromScale(0.5, 0.4)
dangerBanner.Size = UDim2.fromOffset(360, 76)
dangerBanner.BackgroundTransparency = 1
dangerBanner.BorderSizePixel = 0
dangerBanner.Visible = false
dangerBanner.ZIndex = 10
dangerBanner.Parent = gui

local dangerScale = Instance.new("UIScale")
dangerScale.Scale = 1
dangerScale.Parent = dangerBanner

local dangerTitle = Instance.new("TextLabel")
dangerTitle.Name = "Title"
dangerTitle.Position = UDim2.fromOffset(6, 4)
dangerTitle.Size = UDim2.new(1, -12, 0, 27)
dangerTitle.BackgroundTransparency = 1
dangerTitle.Text = "⚠ ÁGUA CAUSANDO DANO"
dangerTitle.TextColor3 = Color3.fromRGB(255, 235, 238)
dangerTitle.TextStrokeColor3 = Color3.fromRGB(42, 4, 10)
dangerTitle.TextStrokeTransparency = 0.35
dangerTitle.Font = Enum.Font.GothamBold
dangerTitle.TextSize = 18
dangerTitle.ZIndex = 11
dangerTitle.Parent = dangerBanner

local dangerSubtitle = Instance.new("TextLabel")
dangerSubtitle.Name = "Instruction"
dangerSubtitle.Position = UDim2.fromOffset(6, 34)
dangerSubtitle.Size = UDim2.new(1, -12, 0, 30)
dangerSubtitle.BackgroundTransparency = 1
dangerSubtitle.Text = "↑ SUBA AGORA"
dangerSubtitle.TextColor3 = Color3.fromRGB(255, 73, 91)
dangerSubtitle.TextStrokeColor3 = Color3.fromRGB(42, 4, 10)
dangerSubtitle.TextStrokeTransparency = 0.32
dangerSubtitle.Font = Enum.Font.GothamBold
dangerSubtitle.TextSize = 21
dangerSubtitle.ZIndex = 11
dangerSubtitle.Parent = dangerBanner

local climbCue = Instance.new("TextLabel")
climbCue.Name = "ClimbCue"
climbCue.AnchorPoint = Vector2.new(0.5, 0.5)
climbCue.Position = UDim2.fromScale(0.5, 0.68)
climbCue.Size = UDim2.fromOffset(240, 30)
climbCue.BackgroundTransparency = 1
climbCue.BorderSizePixel = 0
climbCue.Text = "↑ PROCURE TERRENO ALTO"
climbCue.TextColor3 = Color3.fromRGB(255, 220, 225)
climbCue.TextStrokeColor3 = Color3.fromRGB(42, 4, 10)
climbCue.TextStrokeTransparency = 0.4
climbCue.Font = Enum.Font.GothamMedium
climbCue.TextSize = 14
climbCue.Visible = false
climbCue.ZIndex = 9
climbCue.Parent = gui

local climbStroke = Instance.new("UIStroke")
climbStroke.Color = Color3.fromRGB(255, 92, 108)
climbStroke.Transparency = 0.72
climbStroke.Thickness = 1
climbStroke.Parent = climbCue

local climbScale = Instance.new("UIScale")
climbScale.Scale = 1
climbScale.Parent = climbCue

local dangerSound = Instance.new("Sound")
dangerSound.Name = "WaterDamageWarning"
dangerSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
dangerSound.Volume = 0.72
dangerSound.PlaybackSpeed = 0.76
dangerSound.Parent = SoundService

local sessionTimer = Instance.new("TextLabel")
sessionTimer.Name = "SessionTimer"
sessionTimer.Position = UDim2.fromOffset(12, 91)
sessionTimer.Size = UDim2.fromOffset(92, 25)
sessionTimer.BackgroundColor3 = Color3.fromRGB(12, 18, 29)
sessionTimer.BackgroundTransparency = 0.42
sessionTimer.BorderSizePixel = 0
sessionTimer.Text = "⏱ 00:00"
sessionTimer.TextColor3 = Color3.fromRGB(175, 205, 232)
sessionTimer.Font = Enum.Font.GothamMedium
sessionTimer.TextSize = 12
sessionTimer.Parent = gui

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(0, 8)
timerCorner.Parent = sessionTimer

local timerStroke = Instance.new("UIStroke")
timerStroke.Color = Color3.fromRGB(100, 139, 175)
timerStroke.Transparency = 0.72
timerStroke.Thickness = 1
timerStroke.Parent = sessionTimer

local warning = Instance.new("Frame")
warning.Name = "SanctuaryFloodWarning"
warning.AnchorPoint = Vector2.new(0.5, 0.5)
warning.Position = UDim2.fromScale(0.5, 0.42)
warning.Size = UDim2.fromOffset(340, 78)
warning.BackgroundTransparency = 1
warning.BorderSizePixel = 0
warning.Visible = false
warning.Parent = gui

local warningScale = Instance.new("UIScale")
warningScale.Scale = 1
warningScale.Parent = warning

local cameraViewportConnection

local function updateWarningScale()
	camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local responsiveScale = math.clamp(camera.ViewportSize.X / 540, 0.66, 1)
	warningScale.Scale = responsiveScale
	dangerScale.Scale = responsiveScale
	climbScale.Scale = math.clamp(camera.ViewportSize.X / 420, 0.72, 1)
end

local function bindCamera()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end
	camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateWarningScale)
	end
	updateWarningScale()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(8, 4)
title.Size = UDim2.new(1, -16, 0, 25)
title.BackgroundTransparency = 1
title.Text = "⚠ ÁGUA NO SANTUÁRIO"
title.TextColor3 = Color3.fromRGB(255, 224, 229)
title.TextStrokeColor3 = Color3.fromRGB(42, 4, 10)
title.TextStrokeTransparency = 0.38
title.Font = Enum.Font.GothamMedium
title.TextSize = 15
title.Parent = warning

local countdown = Instance.new("TextLabel")
countdown.Name = "Countdown"
countdown.Position = UDim2.fromOffset(8, 31)
countdown.Size = UDim2.new(1, -16, 0, 34)
countdown.BackgroundTransparency = 1
countdown.Text = "PROTEÇÃO ACABA EM 5"
countdown.TextColor3 = Color3.fromRGB(255, 87, 102)
countdown.TextStrokeColor3 = Color3.fromRGB(42, 4, 10)
countdown.TextStrokeTransparency = 0.32
countdown.Font = Enum.Font.GothamBold
countdown.TextSize = 20
countdown.Parent = warning

local lastDisplayedSecond
local baseWarningScale = warningScale.Scale
local waterDangerActive = false
local dangerStartedAt = 0
local lastDangerSoundAt = -math.huge

local function formatSessionTime(elapsed)
	local totalSeconds = math.max(0, math.floor(elapsed))
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor(totalSeconds % 3600 / 60)
	local seconds = totalSeconds % 60

	if hours > 0 then
		return string.format("⏱ %d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("⏱ %02d:%02d", minutes, seconds)
end

local function setWarningVisible(visible)
	if warning.Visible == visible then
		return
	end

	warning.Visible = visible
	if visible then
		updateWarningScale()
		baseWarningScale = warningScale.Scale
		warningScale.Scale = baseWarningScale * 0.86
		TweenService:Create(
			warningScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = baseWarningScale }
		):Play()
	else
		lastDisplayedSecond = nil
	end
end

local function playDangerSound(now)
	if now - lastDangerSoundAt < DANGER_SOUND_INTERVAL then
		return
	end
	lastDangerSoundAt = now
	dangerSound:Stop()
	dangerSound.TimePosition = 0
	dangerSound:Play()
end

local function setWaterDangerActive(active, now)
	if waterDangerActive == active then
		return
	end

	waterDangerActive = active
	dangerOverlay.Visible = active
	climbCue.Visible = active
	dangerBanner.Visible = active

	if active then
		dangerStartedAt = now
		lastDangerSoundAt = -math.huge
		updateWarningScale()
		local targetScale = dangerScale.Scale
		dangerScale.Scale = targetScale * 0.78
		TweenService:Create(
			dangerScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = targetScale }
		):Play()
		playDangerSound(now)
	else
		dangerStartedAt = 0
		lastDangerSoundAt = -math.huge
		dangerSound:Stop()
	end
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	sessionTimer.Text = formatSessionTime(now - sessionStartedAt)

	local deadline = tonumber(player:GetAttribute(COUNTDOWN_ATTRIBUTE))
	local remaining = deadline and deadline - workspace:GetServerTimeNow() or 0
	if remaining <= 0 then
		setWarningVisible(false)
	else
		setWarningVisible(true)
		local displayedSecond = math.clamp(math.ceil(remaining), 1, 5)
		countdown.Text = string.format("PROTEÇÃO ACABA EM %d", displayedSecond)

		if displayedSecond ~= lastDisplayedSecond then
			lastDisplayedSecond = displayedSecond
			updateWarningScale()
			baseWarningScale = warningScale.Scale
			warningScale.Scale = baseWarningScale * 1.04
			TweenService:Create(
				warningScale,
				TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = baseWarningScale }
			):Play()
		end
	end

	local serverSaysWaterDamages = player:GetAttribute(WATER_DAMAGE_ACTIVE_ATTRIBUTE) == true
	setWaterDangerActive(serverSaysWaterDamages, now)
	if waterDangerActive then
		dangerBanner.Visible = now - dangerStartedAt <= DANGER_BANNER_SECONDS
		playDangerSound(now)

		local pulse = (math.sin(now * 7.2) + 1) * 0.5
		dangerOverlay.GroupTransparency = 0.52 + pulse * 0.24
		climbCue.TextTransparency = 0.08 + pulse * 0.2
		climbStroke.Transparency = 0.68 + pulse * 0.2
	end
end)
