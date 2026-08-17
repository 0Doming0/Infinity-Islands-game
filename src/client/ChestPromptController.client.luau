-- Indicador discreto para os baus. Ele substitui somente ProximityPrompts que
-- o servidor marcou com UseSubtleChestPrompt; revive, NPCs e outros prompts
-- continuam usando o visual original que ja possuem.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local views = setmetatable({}, { __mode = "k" })

local function isChestPrompt(prompt)
	return prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function destroyView(prompt)
	local view = views[prompt]
	if view then
		views[prompt] = nil
		view:Destroy()
	end
end

local function createView(prompt)
	if not isChestPrompt(prompt) or views[prompt] then return end
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then return end

	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SubtleChestPrompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = prompt.MaxActivationDistance + 4
	billboard.Size = UDim2.fromOffset(122, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.25, 0)
	billboard.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "Interact"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = string.format("[E]  ABRIR %s", string.upper(label))
	button.TextColor3 = rare and Color3.fromRGB(255, 222, 94) or Color3.fromRGB(255, 255, 255)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0.2
	button.TextScaled = true
	button.ZIndex = 4
	button.Parent = billboard

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 11
	constraint.MaxTextSize = 16
	constraint.Parent = button

	-- Em celular, o texto e tambem um botao de toque; no PC e controle, a
	-- ProximityPrompt continua recebendo E/X normalmente.
	button.Activated:Connect(function()
		if not prompt.Enabled then return end
		prompt:InputHoldBegin()
		task.delay(math.max(0.05, prompt.HoldDuration), function()
			if prompt.Parent then prompt:InputHoldEnd() end
		end)
	end)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		button.Text = string.format("ABRIR %s", string.upper(label))
	end
	views[prompt] = billboard
end

ProximityPromptService.PromptShown:Connect(createView)
ProximityPromptService.PromptHidden:Connect(destroyView)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if isChestPrompt(prompt) then destroyView(prompt) end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") and descendant.Enabled then
		createView(descendant)
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		descendant:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
			if descendant.Enabled then createView(descendant) end
		end)
	end
end)
