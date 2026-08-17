-- ChestPromptController: interacao de bau para PC/gamepad.
-- Mobile e responsabilidade exclusiva de MobileChestInteractionController.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "ChestPromptDesktopV5"
local desktopViews = setmetatable({}, { __mode = "k" })

local function isChestPrompt(prompt)
	return prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function promptAdornee(prompt)
	local parent = prompt and prompt.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	end
	return nil
end

local function destroyView(prompt)
	local view = desktopViews[prompt]
	if view then
		desktopViews[prompt] = nil
		view:Destroy()
	end
end

local function createView(prompt)
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

ProximityPromptService.PromptShown:Connect(function(prompt)
	if isChestPrompt(prompt) then
		createView(prompt)
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if isChestPrompt(prompt) then
		destroyView(prompt)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if isChestPrompt(prompt) then
		destroyView(prompt)
	end
end)

workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		destroyView(descendant)
	end
end)

player:SetAttribute("DungeonChestPromptVersion", VERSION)
player:SetAttribute("DungeonChestDesktopInteraction", "KeyboardE")
player:SetAttribute("DungeonChestMobileInteraction", "DedicatedMobileController")
