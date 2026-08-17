-- Interacao de bau por plataforma.
-- PC preserva o hint [E] no mundo.
-- Mobile usa um BillboardGui tocavel acima do proprio bau, descoberto pela
-- distancia real ate o ProximityPrompt para nao depender de PromptShown.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "ChestPromptV4_MobileWorldTap"
local MOBILE_SCAN_INTERVAL = 0.10
local MOBILE_DISTANCE_PADDING = 1.5

local desktopViews = setmetatable({}, { __mode = "k" })
local mobileViews = setmetatable({}, { __mode = "k" })
local trackedPrompts = setmetatable({}, { __mode = "k" })
local scanAccumulator = 0

local function isChestPrompt(prompt)
	return prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

local function promptAdornee(prompt)
	local parent = prompt and prompt.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	end
	return nil
end

local function characterRoot()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function distanceToPrompt(prompt)
	local root = characterRoot()
	local position = promptPosition(prompt)
	if not root or not position then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

local function promptInMobileRange(prompt)
	if not isChestPrompt(prompt) or not prompt.Enabled or not prompt.Parent then
		return false
	end
	local limit = math.max(0, tonumber(prompt.MaxActivationDistance) or 0)
	return distanceToPrompt(prompt) <= limit + MOBILE_DISTANCE_PADDING
end

local function triggerPrompt(prompt)
	if not promptInMobileRange(prompt) then
		return
	end

	prompt:InputHoldBegin()
	task.delay(math.max(0.05, tonumber(prompt.HoldDuration) or 0), function()
		if prompt.Parent then
			prompt:InputHoldEnd()
		end
	end)
end

local function destroyDesktopView(prompt)
	local view = desktopViews[prompt]
	if view then
		desktopViews[prompt] = nil
		view:Destroy()
	end
end

local function destroyMobileView(prompt)
	local view = mobileViews[prompt]
	if view then
		mobileViews[prompt] = nil
		view:Destroy()
	end
end

local function createDesktopView(prompt)
	if not isChestPrompt(prompt) or desktopViews[prompt] then
		return
	end
	if not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled then
		return
	end

	local adornee = promptAdornee(prompt)
	if not adornee then
		return
	end

	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")
	local upperLabel = string.upper(label)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SubtleChestPrompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = prompt.MaxActivationDistance + 4
	billboard.Size = UDim2.fromOffset(138, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.25, 0)
	billboard.Parent = playerGui

	local labelObject = Instance.new("TextLabel")
	labelObject.Name = "Interact"
	labelObject.Size = UDim2.fromScale(1, 1)
	labelObject.BackgroundTransparency = 1
	labelObject.BorderSizePixel = 0
	labelObject.Font = Enum.Font.GothamBold
	labelObject.TextColor3 = rare and Color3.fromRGB(255, 222, 94) or Color3.fromRGB(255, 255, 255)
	labelObject.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	labelObject.TextStrokeTransparency = 0.2
	labelObject.TextScaled = true
	labelObject.ZIndex = 4
	labelObject.Parent = billboard

	local keyName = UserInputService.KeyboardEnabled and "E" or "X"
	labelObject.Text = string.format("[%s]  ABRIR %s", keyName, upperLabel)

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 11
	constraint.MaxTextSize = 16
	constraint.Parent = labelObject

	desktopViews[prompt] = billboard
end

local function createMobileView(prompt)
	if not UserInputService.TouchEnabled or not promptInMobileRange(prompt) or mobileViews[prompt] then
		return
	end

	local adornee = promptAdornee(prompt)
	if not adornee then
		return
	end

	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")
	local upperLabel = string.upper(label)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MobileChestPrompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = prompt.MaxActivationDistance + MOBILE_DISTANCE_PADDING + 2
	billboard.Size = UDim2.fromOffset(176, 54)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.45, 0)
	billboard.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "TapToOpen"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = rare and Color3.fromRGB(83, 61, 19) or Color3.fromRGB(25, 43, 67)
	button.BackgroundTransparency = 0.08
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBlack
	button.Text = "ABRIR " .. upperLabel
	button.TextColor3 = rare and Color3.fromRGB(255, 229, 125) or Color3.fromRGB(255, 255, 255)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0.3
	button.TextScaled = true
	button.ZIndex = 10
	button.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = rare and Color3.fromRGB(255, 215, 76) or Color3.fromRGB(151, 218, 255)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.1
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = button

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 13
	constraint.MaxTextSize = 19
	constraint.Parent = button

	button.Activated:Connect(function()
		if promptInMobileRange(prompt) then
			triggerPrompt(prompt)
		end
	end)

	billboard:SetAttribute("ChestPromptInputMode", "WorldTouchButton")
	mobileViews[prompt] = billboard
end

local function updateMobileViews()
	if not UserInputService.TouchEnabled then
		for prompt in pairs(mobileViews) do
			destroyMobileView(prompt)
		end
		return
	end

	local visibleCount = 0
	local nearestDistance = math.huge
	for prompt in pairs(trackedPrompts) do
		if prompt.Parent and promptInMobileRange(prompt) then
			createMobileView(prompt)
			visibleCount += 1
			nearestDistance = math.min(nearestDistance, distanceToPrompt(prompt))
		else
			destroyMobileView(prompt)
		end
	end

	player:SetAttribute("DungeonChestMobileWorldPromptCount", visibleCount)
	player:SetAttribute(
		"DungeonChestMobileNearestDistance",
		nearestDistance < math.huge and math.floor(nearestDistance * 10 + 0.5) / 10 or nil
	)
end

local function trackPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if isChestPrompt(prompt) then
		trackedPrompts[prompt] = true
	end

	prompt:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
		if isChestPrompt(prompt) then
			trackedPrompts[prompt] = true
		else
			trackedPrompts[prompt] = nil
			destroyDesktopView(prompt)
			destroyMobileView(prompt)
		end
	end)
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if isChestPrompt(prompt) then
		trackedPrompts[prompt] = true
		createDesktopView(prompt)
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if isChestPrompt(prompt) then
		destroyDesktopView(prompt)
		-- Mobile nao depende deste evento; a distancia real controla o BillboardGui.
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if isChestPrompt(prompt) then
		destroyDesktopView(prompt)
		destroyMobileView(prompt)
	end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		trackPrompt(descendant)
	end
end

workspace.DescendantAdded:Connect(trackPrompt)
workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		trackedPrompts[descendant] = nil
		destroyDesktopView(descendant)
		destroyMobileView(descendant)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator < MOBILE_SCAN_INTERVAL then
		return
	end
	scanAccumulator = 0
	updateMobileViews()
end)

player:SetAttribute("DungeonChestPromptVersion", VERSION)
player:SetAttribute("DungeonChestMobileInteraction", "WorldBillboardTapByRealDistance")
player:SetAttribute("DungeonChestDesktopInteraction", "KeyboardE")
