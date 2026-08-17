-- Indicador de interacao para os baus.
-- Ele substitui somente ProximityPrompts marcados pelo servidor com
-- UseSubtleChestPrompt; revive, NPCs e outros prompts continuam intactos.
-- PC preserva o hint de teclado. Mobile recebe um CTA grande e claramente tocavel.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local views = setmetatable({}, { __mode = "k" })

local VERSION = "ChestPromptV2_ObviousMobileTouch"

local function isChestPrompt(prompt)
	return prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function isTouchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function destroyView(prompt)
	local view = views[prompt]
	if view then
		views[prompt] = nil
		view:Destroy()
	end
end

local function triggerPrompt(prompt)
	if not prompt.Parent or not prompt.Enabled then
		return
	end

	prompt:InputHoldBegin()
	task.delay(math.max(0.05, prompt.HoldDuration), function()
		if prompt.Parent then
			prompt:InputHoldEnd()
		end
	end)
end

local function createView(prompt)
	if not isChestPrompt(prompt) or views[prompt] then
		return
	end

	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local mobile = isTouchOnly()
	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")
	local upperLabel = string.upper(label)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = mobile and "MobileChestPrompt" or "SubtleChestPrompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = prompt.MaxActivationDistance + 4
	billboard.Size = mobile and UDim2.fromOffset(184, 62) or UDim2.fromOffset(138, 32)
	billboard.StudsOffsetWorldSpace = mobile and Vector3.new(0, 2.55, 0) or Vector3.new(0, 2.25, 0)
	billboard.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "Interact"
	button.Size = UDim2.fromScale(1, 1)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = rare and Color3.fromRGB(255, 222, 94) or Color3.fromRGB(255, 255, 255)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0.2
	button.TextWrapped = true
	button.TextScaled = true
	button.ZIndex = 4
	button.Parent = billboard

	if mobile then
		-- Nao usamos somente texto no celular: este e um botao visual grande,
		-- com contraste e area de toque confortavel.
		button.Text = "TOQUE PARA ABRIR\n" .. upperLabel
		button.BackgroundColor3 = rare and Color3.fromRGB(83, 61, 19) or Color3.fromRGB(25, 43, 67)
		button.BackgroundTransparency = 0.08
		button.AutoButtonColor = true

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 13)
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = rare and Color3.fromRGB(255, 215, 76) or Color3.fromRGB(151, 218, 255)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.12
		stroke.Parent = button

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 5)
		padding.PaddingBottom = UDim.new(0, 5)
		padding.Parent = button
	else
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		local keyName = "E"
		if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
			keyName = "X"
		end
		button.Text = string.format("[%s]  ABRIR %s", keyName, upperLabel)
	end

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = mobile and 13 or 11
	constraint.MaxTextSize = mobile and 19 or 16
	constraint.Parent = button

	button.Activated:Connect(function()
		triggerPrompt(prompt)
	end)

	billboard:SetAttribute("ChestPromptInputMode", mobile and "TouchButton" or "KeyboardOrGamepad")
	views[prompt] = billboard
end

ProximityPromptService.PromptShown:Connect(createView)
ProximityPromptService.PromptHidden:Connect(destroyView)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if isChestPrompt(prompt) then
		destroyView(prompt)
	end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") and descendant.Enabled then
		createView(descendant)
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		descendant:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
			if descendant.Enabled then
				createView(descendant)
			end
		end)
	end
end)

player:SetAttribute("DungeonChestPromptVersion", VERSION)
player:SetAttribute("DungeonChestMobileInteraction", "LargeTouchButton")
player:SetAttribute("DungeonChestDesktopInteraction", "KeyboardE")
