-- MobileChestProximityUI
--
-- Interacao de bau pensada especificamente para mobile sem depender da camera.
-- Quando o personagem entra no alcance fisico de um bau, um botao fixo aparece
-- na HUD. O bau valido mais proximo vira o alvo. Sair do alcance esconde o botao.
--
-- A autoridade continua sendo o ProximityPrompt + servico de bau do servidor.
-- Este script apenas escolhe um prompt por distancia e aciona o mesmo prompt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "MobileChestProximityUIV1_DistanceOnly"
local SCAN_INTERVAL = 0.08
local TAP_DEBOUNCE = 0.28

local trackedPrompts = setmetatable({}, { __mode = "k" })
local trackedConnections = setmetatable({}, { __mode = "k" })

local activePrompt = nil
local scanAccumulator = 0
local lastTapAt = 0

local screenGui
local panel
local button
local titleLabel
local subtitleLabel
local stroke

local function isMobileTouch()
	return UserInputService.TouchEnabled == true
end

if not isMobileTouch() then
	player:SetAttribute("DungeonMobileChestUIVersion", VERSION)
	player:SetAttribute("DungeonMobileChestUIPolicy", "DisabledWithoutTouch")
	return
end

local function isChestPrompt(prompt)
	return prompt
		and prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function characterRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

local function promptDistance(prompt)
	local root = characterRoot()
	local position = promptPosition(prompt)
	if not root or not position then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

local function activationDistance(prompt)
	return math.max(1, tonumber(prompt and prompt.MaxActivationDistance) or 10)
end

local function isPromptInRange(prompt)
	if not isChestPrompt(prompt) or not prompt.Enabled or not prompt.Parent then
		return false
	end
	return promptDistance(prompt) <= activationDistance(prompt)
end

local function ensureCustomMobileStyle(prompt)
	if isChestPrompt(prompt) and prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		-- No mobile usamos nosso botao fixo de tela; esconder o prompt 3D nativo
		-- evita que a interface dependa do enquadramento da camera.
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end

local function ensureUI()
	if screenGui and screenGui.Parent and panel and panel.Parent and button and button.Parent then
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MobileChestProximityUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 900
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = true
	screenGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "ChestPromptPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -86)
	panel.Size = UDim2.fromOffset(236, 72)
	panel.BackgroundColor3 = Color3.fromRGB(23, 39, 60)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 50
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(151, 218, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.08
	stroke.Parent = panel

	button = Instance.new("TextButton")
	button.Name = "OpenChestButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.ZIndex = 51
	button.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "ActionText"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 10)
	titleLabel.Size = UDim2.new(1, -20, 0, 29)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = "ABRIR BAÚ"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextSize = 22
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.TextStrokeTransparency = 0.45
	titleLabel.ZIndex = 52
	titleLabel.Parent = panel

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "ChestName"
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.new(0.5, 0, 0, 40)
	subtitleLabel.Size = UDim2.new(1, -20, 0, 20)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = "TOQUE PARA INTERAGIR"
	subtitleLabel.TextColor3 = Color3.fromRGB(197, 225, 255)
	subtitleLabel.TextSize = 13
	subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	subtitleLabel.ZIndex = 52
	subtitleLabel.Parent = panel
end

local function hideUI()
	activePrompt = nil
	if panel then
		panel.Visible = false
	end
	player:SetAttribute("DungeonMobileChestVisible", false)
	player:SetAttribute("DungeonMobileChestDistance", nil)
	player:SetAttribute("DungeonMobileChestTarget", nil)
end

local function showUI(prompt, distance)
	ensureUI()
	activePrompt = prompt

	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")

	titleLabel.Text = rare and "ABRIR BAÚ RARO" or "ABRIR BAÚ"
	subtitleLabel.Text = string.upper(label) .. "  •  TOQUE AQUI"
	panel.BackgroundColor3 = rare and Color3.fromRGB(78, 57, 18) or Color3.fromRGB(23, 39, 60)
	stroke.Color = rare and Color3.fromRGB(255, 215, 76) or Color3.fromRGB(151, 218, 255)
	titleLabel.TextColor3 = rare and Color3.fromRGB(255, 232, 137) or Color3.new(1, 1, 1)
	subtitleLabel.TextColor3 = rare and Color3.fromRGB(255, 220, 105) or Color3.fromRGB(197, 225, 255)
	panel.Visible = true

	player:SetAttribute("DungeonMobileChestVisible", true)
	player:SetAttribute("DungeonMobileChestDistance", math.floor(distance * 10 + 0.5) / 10)
	player:SetAttribute("DungeonMobileChestTarget", prompt.Name)
end

local function chooseNearestPrompt()
	local bestPrompt = nil
	local bestDistance = math.huge

	for prompt in pairs(trackedPrompts) do
		if prompt.Parent and isPromptInRange(prompt) then
			local distance = promptDistance(prompt)
			if distance < bestDistance then
				bestPrompt = prompt
				bestDistance = distance
			end
		end
	end

	return bestPrompt, bestDistance
end

local function updateNearestPrompt()
	local prompt, distance = chooseNearestPrompt()
	if not prompt then
		hideUI()
		return
	end

	if activePrompt ~= prompt or not panel or not panel.Visible then
		showUI(prompt, distance)
	else
		player:SetAttribute("DungeonMobileChestDistance", math.floor(distance * 10 + 0.5) / 10)
	end
end

local function triggerActivePrompt()
	local prompt = activePrompt
	if not prompt or not isPromptInRange(prompt) then
		hideUI()
		return
	end

	local now = os.clock()
	if now - lastTapAt < TAP_DEBOUNCE then
		return
	end
	lastTapAt = now

	-- Usa o mesmo caminho de input do ProximityPrompt. Assim Triggered continua
	-- chegando ao servidor que ja valida jogador vivo/distancia/recompensa.
	prompt:InputHoldBegin()
	local hold = math.max(0.05, tonumber(prompt.HoldDuration) or 0)
	task.delay(hold, function()
		if prompt.Parent and prompt.Enabled and isPromptInRange(prompt) then
			prompt:InputHoldEnd()
		else
			pcall(function()
				prompt:InputHoldEnd()
			end)
		end
	end)

	player:SetAttribute("DungeonMobileChestLastTapAt", workspace:GetServerTimeNow())
end

local function trackPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") or trackedConnections[prompt] then
		return
	end

	local connections = {}
	connections[#connections + 1] = prompt:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
		if isChestPrompt(prompt) then
			trackedPrompts[prompt] = true
			ensureCustomMobileStyle(prompt)
		else
			trackedPrompts[prompt] = nil
			if activePrompt == prompt then
				hideUI()
			end
		end
	end)
	connections[#connections + 1] = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not prompt.Enabled and activePrompt == prompt then
			hideUI()
		end
	end)
	connections[#connections + 1] = prompt:GetPropertyChangedSignal("Style"):Connect(function()
		ensureCustomMobileStyle(prompt)
	end)
	trackedConnections[prompt] = connections

	if isChestPrompt(prompt) then
		trackedPrompts[prompt] = true
		ensureCustomMobileStyle(prompt)
	end
end

local function untrackPrompt(prompt)
	trackedPrompts[prompt] = nil
	local connections = trackedConnections[prompt]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		trackedConnections[prompt] = nil
	end
	if activePrompt == prompt then
		hideUI()
	end
end

ensureUI()
button.Activated:Connect(triggerActivePrompt)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		trackPrompt(descendant)
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		trackPrompt(descendant)
	end
end)

workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		untrackPrompt(descendant)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator < SCAN_INTERVAL then
		return
	end
	scanAccumulator = 0
	updateNearestPrompt()
end)

player.CharacterRemoving:Connect(hideUI)

player:SetAttribute("DungeonMobileChestUIVersion", VERSION)
player:SetAttribute("DungeonMobileChestUIPolicy", "NearestChestByCharacterDistanceOnly")
player:SetAttribute("DungeonMobileChestCameraDependency", false)
player:SetAttribute("DungeonMobileChestWorldTapDependency", false)
