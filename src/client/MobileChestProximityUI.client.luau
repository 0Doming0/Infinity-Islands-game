-- MobileChestProximityUI
--
-- Interacao de bau pensada especificamente para mobile sem depender da camera
-- para escolher o alvo. O personagem entra no alcance fisico de um bau, o bau
-- valido mais proximo vira o alvo e recebe um BillboardGui local tocavel acima
-- dele. Sair do alcance esconde o indicador.
--
-- A autoridade continua sendo o ProximityPrompt + servico de bau do servidor.
-- Este script apenas escolhe um prompt por distancia e aciona o mesmo prompt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "MobileChestProximityUIV2_DistanceBillboardTouch"
local SCAN_INTERVAL = 0.08
local TAP_DEBOUNCE = 0.28
local SHOW_TIME = 0.14
local HIDE_TIME = 0.10

local trackedPrompts = setmetatable({}, { __mode = "k" })
local trackedConnections = setmetatable({}, { __mode = "k" })

local activePrompt = nil
local scanAccumulator = 0
local lastTapAt = 0
local visualSerial = 0

local billboard
local touchButton
local titleLabel
local subtitleLabel
local uiScale

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

local function promptWorldPosition(prompt)
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

local function promptAdornee(prompt)
	local parent = prompt and prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("Attachment") or parent:IsA("BasePart") then
		return parent
	end
	if parent:IsA("Model") then
		return parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function chestModelForPrompt(prompt)
	local current = prompt and prompt.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("IsTreasureChest") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function anchorWorldY(adornee)
	if adornee and adornee:IsA("Attachment") then
		return adornee.WorldPosition.Y
	end
	if adornee and adornee:IsA("BasePart") then
		return adornee.Position.Y
	end
	return nil
end

local function billboardOffset(prompt, adornee)
	local anchorY = anchorWorldY(adornee)
	local chest = chestModelForPrompt(prompt)
	if anchorY and chest and chest.Parent then
		local boxCFrame, boxSize = chest:GetBoundingBox()
		local topY = boxCFrame.Position.Y + boxSize.Y * 0.5
		return Vector3.new(0, math.max(2.2, topY - anchorY + 1.15), 0)
	end
	return Vector3.new(0, 3.0, 0)
end

local function promptDistance(prompt)
	local root = characterRoot()
	local position = promptWorldPosition(prompt)
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
		-- O prompt nativo fica escondido apenas neste cliente touch. A escolha do
		-- bau continua sendo feita por distancia; o BillboardGui e apenas visual.
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end

local function ensureUI()
	if billboard and billboard.Parent and touchButton and touchButton.Parent then
		return
	end

	billboard = Instance.new("BillboardGui")
	billboard.Name = "MobileChestWorldPrompt"
	billboard.Size = UDim2.fromOffset(220, 82)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Enabled = false
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.Parent = playerGui

	uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.9
	uiScale.Parent = billboard

	-- O botao ocupa uma area maior que o texto, mas permanece invisivel. Isso
	-- deixa o toque confortavel no celular sem desenhar uma caixa na tela.
	touchButton = Instance.new("TextButton")
	touchButton.Name = "OpenChestTouchTarget"
	touchButton.AnchorPoint = Vector2.new(0.5, 0.5)
	touchButton.Position = UDim2.fromScale(0.5, 0.5)
	touchButton.Size = UDim2.fromScale(1, 1)
	touchButton.BackgroundTransparency = 1
	touchButton.BorderSizePixel = 0
	touchButton.Text = ""
	touchButton.AutoButtonColor = false
	touchButton.Active = true
	touchButton.ZIndex = 20
	touchButton.Parent = billboard

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "ActionText"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 8)
	titleLabel.Size = UDim2.new(1, -12, 0, 38)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = "ABRIR BAÚ"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextSize = 21
	titleLabel.TextStrokeColor3 = Color3.fromRGB(12, 18, 27)
	titleLabel.TextStrokeTransparency = 0.18
	titleLabel.TextTransparency = 1
	titleLabel.ZIndex = 21
	titleLabel.Parent = touchButton

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "TouchHint"
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.new(0.5, 0, 0, 43)
	subtitleLabel.Size = UDim2.new(1, -20, 0, 22)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = "TOQUE PARA ABRIR"
	subtitleLabel.TextColor3 = Color3.fromRGB(205, 232, 255)
	subtitleLabel.TextSize = 12
	subtitleLabel.TextStrokeColor3 = Color3.fromRGB(12, 18, 27)
	subtitleLabel.TextStrokeTransparency = 0.35
	subtitleLabel.TextTransparency = 1
	subtitleLabel.ZIndex = 21
	subtitleLabel.Parent = touchButton
end

local function setTextStyle(prompt)
	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")

	titleLabel.Text = rare and "ABRIR BAÚ RARO" or "ABRIR BAÚ"
	subtitleLabel.Text = string.upper(label) .. "  •  TOQUE"

	if rare then
		titleLabel.TextColor3 = Color3.fromRGB(255, 229, 121)
		subtitleLabel.TextColor3 = Color3.fromRGB(255, 218, 91)
	else
		titleLabel.TextColor3 = Color3.new(1, 1, 1)
		subtitleLabel.TextColor3 = Color3.fromRGB(205, 232, 255)
	end
end

local function hideUI(immediate)
	activePrompt = nil
	visualSerial += 1
	local serial = visualSerial

	player:SetAttribute("DungeonMobileChestVisible", false)
	player:SetAttribute("DungeonMobileChestDistance", nil)
	player:SetAttribute("DungeonMobileChestTarget", nil)

	if not billboard then
		return
	end

	if immediate then
		billboard.Enabled = false
		billboard.Adornee = nil
		if titleLabel then
			titleLabel.TextTransparency = 1
			titleLabel.TextStrokeTransparency = 1
		end
		if subtitleLabel then
			subtitleLabel.TextTransparency = 1
			subtitleLabel.TextStrokeTransparency = 1
		end
		if uiScale then
			uiScale.Scale = 0.9
		end
		return
	end

	TweenService:Create(titleLabel, TweenInfo.new(HIDE_TIME), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	TweenService:Create(subtitleLabel, TweenInfo.new(HIDE_TIME), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	TweenService:Create(uiScale, TweenInfo.new(HIDE_TIME), { Scale = 0.92 }):Play()

	task.delay(HIDE_TIME, function()
		if visualSerial ~= serial or activePrompt ~= nil then
			return
		end
		billboard.Enabled = false
		billboard.Adornee = nil
	end)
end

local function showUI(prompt, distance)
	ensureUI()
	local adornee = promptAdornee(prompt)
	if not adornee then
		hideUI(true)
		return
	end

	activePrompt = prompt
	visualSerial += 1
	setTextStyle(prompt)

	billboard.Adornee = adornee
	billboard.StudsOffsetWorldSpace = billboardOffset(prompt, adornee)
	billboard.Enabled = true

	titleLabel.TextTransparency = 1
	titleLabel.TextStrokeTransparency = 1
	subtitleLabel.TextTransparency = 1
	subtitleLabel.TextStrokeTransparency = 1
	uiScale.Scale = 0.9

	TweenService:Create(titleLabel, TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.18,
	}):Play()
	TweenService:Create(subtitleLabel, TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.35,
	}):Play()
	TweenService:Create(uiScale, TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

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
		if activePrompt ~= nil or (billboard and billboard.Enabled) then
			hideUI(false)
		end
		return
	end

	if activePrompt ~= prompt or not billboard or not billboard.Enabled then
		showUI(prompt, distance)
	else
		local adornee = promptAdornee(prompt)
		if adornee and billboard.Adornee ~= adornee then
			billboard.Adornee = adornee
			billboard.StudsOffsetWorldSpace = billboardOffset(prompt, adornee)
		end
		player:SetAttribute("DungeonMobileChestDistance", math.floor(distance * 10 + 0.5) / 10)
	end
end

local function triggerActivePrompt()
	local prompt = activePrompt
	if not prompt or not isPromptInRange(prompt) then
		hideUI(false)
		return
	end

	local now = os.clock()
	if now - lastTapAt < TAP_DEBOUNCE then
		return
	end
	lastTapAt = now

	-- Usa o mesmo caminho de input do ProximityPrompt. Triggered continua
	-- chegando ao servidor, que valida jogador vivo, distancia e recompensa.
	prompt:InputHoldBegin()
	local hold = math.max(0.05, tonumber(prompt.HoldDuration) or 0)
	task.delay(hold, function()
		pcall(function()
			prompt:InputHoldEnd()
		end)
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
				hideUI(false)
			end
		end
	end)
	connections[#connections + 1] = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not prompt.Enabled and activePrompt == prompt then
			hideUI(false)
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
		hideUI(false)
	end
end

ensureUI()
touchButton.Activated:Connect(triggerActivePrompt)

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

player.CharacterRemoving:Connect(function()
	hideUI(true)
end)

player:SetAttribute("DungeonMobileChestUIVersion", VERSION)
player:SetAttribute("DungeonMobileChestUIPolicy", "NearestChestByDistance_BillboardTouch")
player:SetAttribute("DungeonMobileChestCameraDependency", false)
player:SetAttribute("DungeonMobileChestWorldTapDependency", false)
player:SetAttribute("DungeonMobileChestFixedHUD", false)
