local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SHOW_TIME = 0.42
local HIDE_TIME = 0.32
local DISPLAY_TIME = 2.4
local SLIDE_OFFSET = 42

local panel
local initialPosition
local transparencyValues = {}
local animationSerial = 0
local lastLevelUpSerial

local function findPanel()
	local hud = playerGui:FindFirstChild("DungeonHUD")
	return hud and hud:FindFirstChild("LevelUpPanel", true)
end

local function findLevelText()
	local currentPanel = findPanel()
	return currentPanel and currentPanel:FindFirstChild("LevelText", true)
end

local function updateLevelText(level)
	local levelText = findLevelText()
	if levelText and levelText:IsA("TextLabel") then
		levelText.Text = string.format("Level %d", level)
	end
end

local function capturePanel()
	local current = findPanel()
	if not current then
		return false
	end

	if current ~= panel then
		panel = current
		initialPosition = panel.Position
		transparencyValues = {}

		for _, descendant in ipairs(panel:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				transparencyValues[descendant] = {
					BackgroundTransparency = descendant.BackgroundTransparency,
					TextTransparency = (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox"))
						and descendant.TextTransparency
						or nil,
					ImageTransparency = (descendant:IsA("ImageLabel") or descendant:IsA("ImageButton"))
						and descendant.ImageTransparency
						or nil,
				}
			end
		end
	end

	return true
end

local function setFade(value)
	if not panel then
		return
	end

	for object, values in pairs(transparencyValues) do
		if object.Parent then
			object.BackgroundTransparency = values.BackgroundTransparency + (1 - values.BackgroundTransparency) * value

			if values.TextTransparency ~= nil then
				object.TextTransparency = values.TextTransparency + (1 - values.TextTransparency) * value
			end
			if values.ImageTransparency ~= nil then
				object.ImageTransparency = values.ImageTransparency + (1 - values.ImageTransparency) * value
			end
		end
	end
end

local function restoreFade()
	setFade(0)
end

local function hidePanel()
	if not capturePanel() then
		return
	end

	animationSerial += 1
	local currentSerial = animationSerial
	local hiddenPosition = initialPosition + UDim2.fromOffset(0, -SLIDE_OFFSET)

	local positionTween = TweenService:Create(
		panel,
		TweenInfo.new(HIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Position = hiddenPosition}
	)
	local fadeValue = Instance.new("NumberValue")
	fadeValue.Value = 0
	local fadeConnection = fadeValue.Changed:Connect(function(value)
		setFade(value)
	end)
	local fadeTween = TweenService:Create(
		fadeValue,
		TweenInfo.new(HIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Value = 1}
	)

	positionTween:Play()
	fadeTween:Play()
	positionTween.Completed:Wait()
	fadeConnection:Disconnect()
	fadeValue:Destroy()

	if currentSerial == animationSerial and panel then
		panel.Visible = false
		panel.Position = initialPosition
		restoreFade()
	end
end

local function showPanel()
	if not capturePanel() then
		return
	end

	animationSerial += 1
	local currentSerial = animationSerial
	local hiddenPosition = initialPosition + UDim2.fromOffset(0, -SLIDE_OFFSET)

	panel.Visible = true
	panel.Position = hiddenPosition
	setFade(1)

	local positionTween = TweenService:Create(
		panel,
		TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = initialPosition}
	)
	local fadeValue = Instance.new("NumberValue")
	fadeValue.Value = 1
	local fadeConnection = fadeValue.Changed:Connect(function(value)
		setFade(value)
	end)
	local fadeTween = TweenService:Create(
		fadeValue,
		TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Value = 0}
	)

	positionTween:Play()
	fadeTween:Play()
	positionTween.Completed:Wait()
	fadeConnection:Disconnect()
	fadeValue:Destroy()
	restoreFade()

	if currentSerial ~= animationSerial then
		return
	end

	task.wait(DISPLAY_TIME)
	if currentSerial == animationSerial then
		hidePanel()
	end
end

local function onLevelUp()
	local serial = player:GetAttribute("PlayerLevelUpSerial")
	if serial == nil or serial == lastLevelUpSerial then
		return
	end

	lastLevelUpSerial = serial
	local level = tonumber(player:GetAttribute("LastLevelUpTo"))
		or tonumber(player:GetAttribute("PlayerLevel"))
		or 1
	updateLevelText(level)
	task.spawn(showPanel)
end

player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(onLevelUp)

playerGui.ChildAdded:Connect(function()
	task.defer(capturePanel)
end)

task.defer(function()
	capturePanel()
	if panel then
		panel.Visible = false
		panel.Position = initialPosition
		restoreFade()
	end
end)