-- Interacao de bau por plataforma.
-- PC preserva o hint [E] no mundo. Mobile usa um botao de tela independente
-- de PromptShown: ele aparece pela distancia real ate o ProximityPrompt do bau.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "ChestPromptV3_MobileDistanceCTA"
local MOBILE_GUI_NAME = "MobileChestInteractionGui"
local MOBILE_SCAN_INTERVAL = 0.10
local MOBILE_DISTANCE_PADDING = 1.5

local desktopViews = setmetatable({}, { __mode = "k" })
local trackedPrompts = setmetatable({}, { __mode = "k" })
local currentMobilePrompt
local scanAccumulator = 0

local mobileGui
local mobileButton

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

local function ensureMobileGui()
	if mobileGui and mobileGui.Parent and mobileButton and mobileButton.Parent then
		return
	end

	local old = playerGui:FindFirstChild(MOBILE_GUI_NAME)
	if old then
		old:Destroy()
	end

	mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = MOBILE_GUI_NAME
	mobileGui.ResetOnSpawn = false
	mobileGui.IgnoreGuiInset = true
	mobileGui.DisplayOrder = 260
	mobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mobileGui.Parent = playerGui

	mobileButton = Instance.new("TextButton")
	mobileButton.Name = "OpenChestButton"
	mobileButton.AnchorPoint = Vector2.new(0.5, 1)
	mobileButton.Position = UDim2.fromScale(0.5, 0.84)
	mobileButton.Size = UDim2.fromOffset(220, 64)
	mobileButton.BackgroundColor3 = Color3.fromRGB(24, 47, 73)
	mobileButton.BackgroundTransparency = 0.04
	mobileButton.BorderSizePixel = 0
	mobileButton.AutoButtonColor = true
	mobileButton.Font = Enum.Font.GothamBlack
	mobileButton.Text = "ABRIR BAÚ"
	mobileButton.TextColor3 = Color3.new(1, 1, 1)
	mobileButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	mobileButton.TextStrokeTransparency = 0.35
	mobileButton.TextScaled = true
	mobileButton.Visible = false
	mobileButton.ZIndex = 261
	mobileButton.Parent = mobileGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = mobileButton

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(154, 220, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = mobileButton

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 16
	constraint.MaxTextSize = 24
	constraint.Parent = mobileButton

	mobileButton.Activated:Connect(function()
		local prompt = currentMobilePrompt
		if prompt then
			triggerPrompt(prompt)
		end
	end)
end

local function hideMobileButton()
	currentMobilePrompt = nil
	if mobileButton then
		mobileButton.Visible = false
	end
	player:SetAttribute("DungeonChestMobileTarget", nil)
end

local function updateMobileButton()
	if not UserInputService.TouchEnabled then
		hideMobileButton()
		return
	end

	ensureMobileGui()
	local nearest
	local nearestDistance = math.huge

	for prompt in pairs(trackedPrompts) do
		if prompt.Parent and promptInMobileRange(prompt) then
			local distance = distanceToPrompt(prompt)
			if distance < nearestDistance then
				nearest = prompt
				nearestDistance = distance
			end
		end
	end

	if not nearest then
		hideMobileButton()
		return
	end

	currentMobilePrompt = nearest
	local rare = nearest:GetAttribute("ChestPromptRare") == true
	local label = tostring(nearest:GetAttribute("ChestPromptLabel") or nearest.ObjectText or "Baú")
	mobileButton.Text = "ABRIR " .. string.upper(label)
	mobileButton.BackgroundColor3 = rare and Color3.fromRGB(91, 65, 17) or Color3.fromRGB(24, 47, 73)
	local stroke = mobileButton:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rare and Color3.fromRGB(255, 218, 79) or Color3.fromRGB(154, 220, 255)
	end
	mobileButton.Visible = true
	player:SetAttribute("DungeonChestMobileTarget", nearest:GetFullName())
	player:SetAttribute("DungeonChestMobileTargetDistance", math.floor(nearestDistance * 10 + 0.5) / 10)
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
			if currentMobilePrompt == prompt then
				hideMobileButton()
			end
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
		-- Mobile nao depende deste evento; a distancia real decide quando ocultar.
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if isChestPrompt(prompt) then
		destroyDesktopView(prompt)
		if currentMobilePrompt == prompt then
			hideMobileButton()
		end
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
		if currentMobilePrompt == descendant then
			hideMobileButton()
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator < MOBILE_SCAN_INTERVAL then
		return
	end
	scanAccumulator = 0
	updateMobileButton()
end)

if UserInputService.TouchEnabled then
	ensureMobileGui()
end

player:SetAttribute("DungeonChestPromptVersion", VERSION)
player:SetAttribute("DungeonChestMobileInteraction", "ScreenButtonByRealDistance")
player:SetAttribute("DungeonChestDesktopInteraction", "KeyboardE")
