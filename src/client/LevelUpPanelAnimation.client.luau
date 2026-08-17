local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SHOW_TIME = 0.42
local HIDE_TIME = 0.32
local DISPLAY_TIME = 2.4
local SLIDE_OFFSET = 42
local SCREEN_MARGIN = 20
local MAX_SCREEN_WIDTH_RATIO = 0.92
local MAX_SCREEN_HEIGHT_RATIO = 0.70
local RESPONSIVE_SCALE_NAME = "DungeonLevelUpResponsiveScale"
local TOP_BIASED_VERTICAL_POSITION = 0.30

local panel
local initialPosition = UDim2.fromScale(0.5, TOP_BIASED_VERTICAL_POSITION)
local transparencyValues = {}
local animationSerial = 0
local lastLevelUpSerial
local cameraViewportConnection

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

local function getViewport()
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function getResponsiveScale()
	if not panel then
		return nil
	end

	local scale = panel:FindFirstChild(RESPONSIVE_SCALE_NAME)
	if scale and not scale:IsA("UIScale") then
		scale:Destroy()
		scale = nil
	end
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = RESPONSIVE_SCALE_NAME
		scale.Scale = 1
		scale.Parent = panel
	end
	return scale
end

local function centerAndScalePanel()
	if not panel or not panel.Parent then
		return
	end

	-- The panel belongs in the visual center of every device.  The Studio
	-- design keeps its authored Size; only the final scale is reduced when it
	-- would otherwise extend beyond the player's screen.
	panel.AnchorPoint = Vector2.new(0.5, 0.5)

	local responsiveScale = getResponsiveScale()
	if not responsiveScale then
		return
	end

	local activeScale = math.max(responsiveScale.Scale, 0.001)
	local absoluteSize = panel.AbsoluteSize
	if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
		return
	end

	local authoredWidth = absoluteSize.X / activeScale
	local authoredHeight = absoluteSize.Y / activeScale
	local viewport = getViewport()
	local maximumWidth = math.max(1, viewport.X * MAX_SCREEN_WIDTH_RATIO - SCREEN_MARGIN * 2)
	local maximumHeight = math.max(1, viewport.Y * MAX_SCREEN_HEIGHT_RATIO - SCREEN_MARGIN * 2)
	local targetScale = math.min(1, maximumWidth / authoredWidth, maximumHeight / authoredHeight)

	responsiveScale.Scale = math.max(0.01, targetScale)

	-- Horizontal center is fixed. Vertically, the panel favors the upper third
	-- of the display but is clamped so even a large mobile layout stays whole.
	local scaledHeight = authoredHeight * responsiveScale.Scale
	local minimumCenterY = (SCREEN_MARGIN + scaledHeight * 0.5) / viewport.Y
	local maximumCenterY = 1 - minimumCenterY
	local verticalPosition = TOP_BIASED_VERTICAL_POSITION
	-- Durante a criacao/troca de uma janela muito pequena, o Roblox pode
	-- informar uma ViewportSize menor que o proprio painel. Nessa situacao nao
	-- existe faixa vertical valida para o clamp; centralizamos provisoriamente
	-- ate a proxima atualizacao da viewport.
	if maximumCenterY >= minimumCenterY then
		verticalPosition = math.clamp(
			TOP_BIASED_VERTICAL_POSITION,
			minimumCenterY,
			maximumCenterY
		)
	else
		verticalPosition = 0.5
	end
	initialPosition = UDim2.fromScale(0.5, verticalPosition)

	if panel.Visible then
		panel.Position = initialPosition
	end
end

local function bindViewport()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(centerAndScalePanel)
		end)
	end
end

local function capturePanel()
	local current = findPanel()
	if not current then
		return false
	end

	if current ~= panel then
		panel = current
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

		bindViewport()
	end

	centerAndScalePanel()

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
	centerAndScalePanel()
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

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewport()
	task.defer(centerAndScalePanel)
end)

task.defer(function()
	capturePanel()
	if panel then
		panel.Visible = false
		panel.Position = initialPosition
		restoreFade()
	end
end)
