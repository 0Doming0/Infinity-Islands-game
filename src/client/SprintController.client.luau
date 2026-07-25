-- V23: mostra numericamente o limite atual enquanto o jogador corre.
-- Corrida: dois toques em W, L3 ou botao de toque.
-- Shift pertence ao SneakController e nunca ativa corrida.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local SprintConfig = require(ReplicatedStorage:WaitForChild("SprintConfig"))
local remote = ReplicatedStorage:WaitForChild("SprintRequest")

local ACTION_NAME = "SkyDungeonSprint"
local wDown = false
local controllerSprintDown = false
local touchSprintDown = false
local doubleTapLatched = false
local lastForwardTap = -math.huge
local lastRequestAt = -math.huge
local lastRequestedValue = false
local character
local humanoid
local normalFieldOfView
local fovTween
local staminaGui
local staminaBackground
local staminaFill
local staminaLimitLabel

local function formatDuration(seconds)
	local formatted = string.format("%.1f", seconds)
	return string.gsub(formatted, "%.", ",")
end

local function createStaminaGui()
	if staminaGui and staminaGui.Parent then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	staminaGui = Instance.new("ScreenGui")
	staminaGui.Name = "SprintStaminaGui"
	staminaGui.ResetOnSpawn = false
	staminaGui.IgnoreGuiInset = true
	staminaGui.DisplayOrder = 20
	staminaGui.Parent = playerGui

	staminaBackground = Instance.new("Frame")
	staminaBackground.Name = "Background"
	staminaBackground.AnchorPoint = Vector2.new(1, 1)
	staminaBackground.Position = SprintConfig.StaminaBarPosition
	staminaBackground.Size = SprintConfig.StaminaBarSize
	staminaBackground.BackgroundColor3 = Color3.fromRGB(12, 20, 31)
	staminaBackground.BackgroundTransparency = 0.28
	staminaBackground.BorderSizePixel = 0
	staminaBackground.Visible = false
	staminaBackground.Parent = staminaGui

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(1, 0)
	backgroundCorner.Parent = staminaBackground

	staminaFill = Instance.new("Frame")
	staminaFill.Name = "Fill"
	staminaFill.Size = UDim2.fromScale(1, 1)
	staminaFill.BackgroundColor3 = Color3.fromRGB(36, 153, 255)
	staminaFill.BorderSizePixel = 0
	staminaFill.Parent = staminaBackground

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = staminaFill

	staminaLimitLabel = Instance.new("TextLabel")
	staminaLimitLabel.Name = "CurrentLimit"
	staminaLimitLabel.AnchorPoint = Vector2.new(1, 1)
	staminaLimitLabel.Position = UDim2.new(1, 0, 0, -4)
	staminaLimitLabel.Size = UDim2.fromOffset(180, 20)
	staminaLimitLabel.BackgroundTransparency = 1
	staminaLimitLabel.Font = Enum.Font.GothamBold
	staminaLimitLabel.Text = ""
	staminaLimitLabel.TextColor3 = Color3.fromRGB(111, 202, 255)
	staminaLimitLabel.TextSize = 15
	staminaLimitLabel.TextStrokeColor3 = Color3.fromRGB(5, 16, 27)
	staminaLimitLabel.TextStrokeTransparency = 0.25
	staminaLimitLabel.TextXAlignment = Enum.TextXAlignment.Right
	staminaLimitLabel.Visible = false
	staminaLimitLabel.Parent = staminaBackground
end

local function updateStaminaBar()
	createStaminaGui()
	if not character or not staminaBackground or not staminaFill or not staminaLimitLabel then
		return
	end

	local maximum = character:GetAttribute("SprintStaminaMax")
	local current = character:GetAttribute("SprintStamina")
	if typeof(maximum) ~= "number" or maximum <= 0 or typeof(current) ~= "number" then
		staminaBackground.Visible = false
		staminaLimitLabel.Visible = false
		return
	end

	local ratio = math.clamp(current / maximum, 0, 1)
	local sprinting = character:GetAttribute("Sprinting") == true
	staminaFill.Size = UDim2.fromScale(ratio, 1)
	staminaBackground.Visible = sprinting or ratio < 0.999
	staminaLimitLabel.Text = "LIMITE: " .. formatDuration(maximum) .. " s"
	staminaLimitLabel.Visible = sprinting
end

local function wantsSprint()
	return wDown and doubleTapLatched or controllerSprintDown or touchSprintDown
end

local function sendSprintRequest(force)
	local wanted = wantsSprint()
	local now = os.clock()
	if not force and wanted == lastRequestedValue and now - lastRequestAt < SprintConfig.RequestRetryInterval then
		return
	end
	lastRequestedValue = wanted
	lastRequestAt = now
	remote:FireServer(wanted)
end

local function updateCameraFeedback(sprinting)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not normalFieldOfView then
		normalFieldOfView = camera.FieldOfView
	end
	if fovTween then
		fovTween:Cancel()
	end
	local target = sprinting and math.min(normalFieldOfView + 5, 90) or normalFieldOfView
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = target }
	)
	fovTween:Play()
end

local function bindCharacter(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	doubleTapLatched = false
	lastRequestedValue = false
	normalFieldOfView = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70

	newCharacter:GetAttributeChangedSignal("Sprinting"):Connect(function()
		if newCharacter == character then
			updateCameraFeedback(newCharacter:GetAttribute("Sprinting") == true)
			updateStaminaBar()
		end
	end)
	newCharacter:GetAttributeChangedSignal("SprintStamina"):Connect(function()
		if newCharacter == character then
			updateStaminaBar()
		end
	end)
	newCharacter:GetAttributeChangedSignal("SprintStaminaMax"):Connect(function()
		if newCharacter == character then
			updateStaminaBar()
		end
	end)
	updateCameraFeedback(false)
	updateStaminaBar()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.W then
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local now = os.clock()
		wDown = true
		if now - lastForwardTap <= SprintConfig.DoubleTapWindow then
			doubleTapLatched = true
		end
		lastForwardTap = now
		sendSprintRequest(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W then
		wDown = false
		doubleTapLatched = false
		sendSprintRequest(true)
	end
end)

local function sprintAction(_, inputState, inputObject)
	local isTouch = inputObject.UserInputType == Enum.UserInputType.Touch
	if inputState == Enum.UserInputState.Begin then
		if isTouch then
			touchSprintDown = true
		else
			controllerSprintDown = true
		end
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if isTouch then
			touchSprintDown = false
		else
			controllerSprintDown = false
		end
	end
	sendSprintRequest(true)
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_NAME, sprintAction, true, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle(ACTION_NAME, "CORRER")
ContextActionService:SetPosition(ACTION_NAME, SprintConfig.TouchButtonPosition)

local button = ContextActionService:GetButton(ACTION_NAME)
if button then
	button.Name = "SprintButton"
	button.Size = UDim2.fromOffset(92, 92)
	button.BackgroundColor3 = Color3.fromRGB(54, 164, 214)
	button.BackgroundTransparency = 0.14
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
end

RunService.Heartbeat:Connect(function()
	if wantsSprint() and character and humanoid and humanoid.Health > 0 then
		if
			character:GetAttribute("Sprinting") ~= true
			and os.clock() - lastRequestAt >= SprintConfig.RequestRetryInterval
		then
			sendSprintRequest(true)
		end
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end
