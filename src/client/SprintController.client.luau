-- Corrida sem autoridade visual sobre controles mobile.
-- O Studio define Position/Size/AnchorPoint dos botoes. Este controller apenas
-- conecta input, joystick, gamepad e botoes authored ao SprintRequest.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SprintConfig = require(ReplicatedStorage:WaitForChild("SprintConfig"))
local remote = ReplicatedStorage:WaitForChild("SprintRequest")

local ACTION_NAME = "SkyDungeonSprint"
local VERSION = "AuthoredMobileSprintLayoutV1"
local BUTTON_NAMES = {
	sprintbutton = true,
	runbutton = true,
	mobileSprintButton = true,
}

local wDown = false
local controllerSprintLatched = false
local touchButtonLatched = false
local joystickSprintLatched = false
local joystickTouch
local joystickOrigin
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
local boundButtons = setmetatable({}, { __mode = "k" })

local function formatDuration(seconds)
	local formatted = string.format("%.1f", seconds)
	return string.gsub(formatted, "%.", ",")
end

local function createStaminaGui()
	if staminaGui and staminaGui.Parent then
		return
	end

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
	staminaBackground.Visible = (sprinting or ratio < 0.999)
		and player:GetAttribute("DungeonUnifiedHUDReady") ~= true
	staminaLimitLabel.Text = "LIMITE: " .. formatDuration(maximum) .. " s"
	staminaLimitLabel.Visible = sprinting
		and player:GetAttribute("DungeonUnifiedHUDReady") ~= true
end

local function wantsSprint()
	return (wDown and doubleTapLatched)
		or controllerSprintLatched
		or touchButtonLatched
		or joystickSprintLatched
end

local function publishButtonState()
	for button in pairs(boundButtons) do
		if button.Parent then
			button:SetAttribute("SprintActive", wantsSprint())
			button:SetAttribute("DungeonAuthoredControl", true)
		end
	end
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
	publishButtonState()
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
			publishButtonState()
		end
	end)
	newCharacter:GetAttributeChangedSignal("SprintStamina"):Connect(updateStaminaBar)
	newCharacter:GetAttributeChangedSignal("SprintStaminaMax"):Connect(updateStaminaBar)
	updateCameraFeedback(false)
	updateStaminaBar()
end

local function isSprintButton(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end
	local name = string.lower(button.Name)
	if name == "sprintbutton" or name == "runbutton" or name == "mobilesprintbutton" then
		return true
	end
	local parent = button.Parent
	local parentName = parent and string.lower(parent.Name) or ""
	return parentName == "sprintbutton" or parentName == "runbutton" or parentName == "mobilesprintbutton"
end

local function bindButton(button)
	if not isSprintButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	button:SetAttribute("DungeonAuthoredControl", true)
	button.Activated:Connect(function()
		touchButtonLatched = not touchButtonLatched
		sendSprintRequest(true)
	end)
	publishButtonState()
end

local function scanButtons()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		bindButton(descendant)
	end
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

local function sprintAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		controllerSprintLatched = not controllerSprintLatched
		sendSprintRequest(true)
	end
	return Enum.ContextActionResult.Sink
end

-- false: nao cria botao de toque, portanto nao existe SetPosition por script.
ContextActionService:BindAction(ACTION_NAME, sprintAction, false, Enum.KeyCode.ButtonL3)

UserInputService.TouchStarted:Connect(function(input)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if input.Position.X <= viewport.X * 0.46 and input.Position.Y >= viewport.Y * 0.43 then
		joystickTouch = input
		joystickOrigin = input.Position
		joystickSprintLatched = false
	end
end)

UserInputService.TouchMoved:Connect(function(input)
	if input ~= joystickTouch or not joystickOrigin then
		return
	end
	local delta = input.Position - joystickOrigin
	local push = tonumber(SprintConfig.JoystickSprintPushPixels) or 52
	local tolerance = tonumber(SprintConfig.JoystickSprintHorizontalTolerance) or 1.15
	if delta.Y <= -push and math.abs(delta.X) <= math.abs(delta.Y) * tolerance and not joystickSprintLatched then
		joystickSprintLatched = true
		sendSprintRequest(true)
	end
end)

UserInputService.TouchEnded:Connect(function(input)
	if input ~= joystickTouch then
		return
	end
	joystickTouch = nil
	joystickOrigin = nil
	joystickSprintLatched = false
	sendSprintRequest(true)
end)

player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true then
		controllerSprintLatched = false
		touchButtonLatched = false
		joystickSprintLatched = false
		sendSprintRequest(true)
	end
end)

RunService.Heartbeat:Connect(function()
	if wantsSprint() and character and humanoid and humanoid.Health > 0 then
		if character:GetAttribute("Sprinting") ~= true
			and os.clock() - lastRequestAt >= SprintConfig.RequestRetryInterval
		then
			sendSprintRequest(true)
		end
	end
end)

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindButton, instance)
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

task.defer(scanButtons)
player:SetAttribute("DungeonSprintLayoutOwnedByStudio", true)
player:SetAttribute("DungeonSprintControllerVersion", VERSION)
