-- MobileChestProximityUI
--
-- Mobile: o bau mais proximo e escolhido apenas pela distancia do personagem.
-- Um BillboardGui local aparece acima dele. O texto e somente visual.
-- Ao personagem encostar no volume do bau, o ProximityPrompt e acionado
-- automaticamente e repetido com debounce enquanto houver contato.
--
-- Nao depende de camera, toque em GUI, raycast de tela ou evento Touched.
-- A recompensa/abertura continua sendo validada pelo servidor do proprio bau.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "MobileChestProximityUIV4_RobustAutoContact"
local SCAN_INTERVAL = 0.03
local AUTO_TRIGGER_DEBOUNCE = 0.32
local SHOW_TIME = 0.14
local HIDE_TIME = 0.10

-- Margem propositalmente generosa para mobile. Alguns modelos de bau nao
-- colidem com o personagem, entao um contato estritamente matematico poderia
-- ser atravessado entre dois frames.
local CONTACT_PADDING_XZ = 0.85
local CONTACT_VERTICAL_ALLOWANCE = 3.0

local trackedPrompts = setmetatable({}, { __mode = "k" })
local trackedConnections = setmetatable({}, { __mode = "k" })

local activePrompt = nil
local scanAccumulator = 0
local lastAutoTriggerAt = -math.huge
local visualSerial = 0
local autoTriggerAttempts = 0

local billboard
local visualFrame
local titleLabel
local subtitleLabel

local function isMobileTouch()
	return UserInputService.TouchEnabled == true
		or player:GetAttribute("DungeonMobileMode") == true
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
		if current:IsA("Model") then
			local lowerName = string.lower(current.Name)
			local explicitChest = current:GetAttribute("IsTreasureChest") == true
				or current:GetAttribute("RareChest") == true
				or current:GetAttribute("IsRareChest") == true
				or current:GetAttribute("IsDormantMimicChest") == true
				or tostring(current:GetAttribute("ChestRarity") or "") ~= ""
			local chestNamed = string.find(lowerName, "chest", 1, true) ~= nil
				or string.find(lowerName, "bau", 1, true) ~= nil
			if explicitChest or chestNamed then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function promptBasePart(prompt)
	local parent = prompt and prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("Attachment") then
		local attachmentParent = parent.Parent
		return attachmentParent and attachmentParent:IsA("BasePart") and attachmentParent or nil
	end
	if parent:IsA("BasePart") then
		return parent
	end
	if parent:IsA("Model") then
		return parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
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

local function contactGeometry(prompt)
	local chest = chestModelForPrompt(prompt)
	if chest and chest.Parent then
		local boxCFrame, boxSize = chest:GetBoundingBox()
		return boxCFrame, boxSize, "ChestModel"
	end

	-- Fallback importante: o sistema de baus raros e assets importados podem
	-- nao usar os mesmos atributos do ChestService principal. A propria BasePart
	-- que hospeda o prompt continua sendo uma geometria de contato valida.
	local part = promptBasePart(prompt)
	if part and part.Parent then
		return part.CFrame, part.Size, "PromptBasePart"
	end

	return nil, nil, "MissingGeometry"
end

local function isCharacterTouchingChest(prompt)
	local root = characterRoot()
	if not root then
		return false, "NoCharacter"
	end

	local boxCFrame, boxSize, source = contactGeometry(prompt)
	if not boxCFrame or not boxSize then
		return false, source
	end

	local localRoot = boxCFrame:PointToObjectSpace(root.Position)
	local radiusX = root.Size.X * 0.5 + CONTACT_PADDING_XZ
	local radiusZ = root.Size.Z * 0.5 + CONTACT_PADDING_XZ
	local halfHeight = root.Size.Y * 0.5 + CONTACT_VERTICAL_ALLOWANCE

	local insideX = math.abs(localRoot.X) <= boxSize.X * 0.5 + radiusX
	local insideZ = math.abs(localRoot.Z) <= boxSize.Z * 0.5 + radiusZ
	local insideY = math.abs(localRoot.Y) <= boxSize.Y * 0.5 + halfHeight
	return insideX and insideZ and insideY, source
end

local function ensureCustomMobileStyle(prompt)
	if isChestPrompt(prompt) and prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end

local function ensureUI()
	if billboard and billboard.Parent and visualFrame and visualFrame.Parent then
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

	visualFrame = Instance.new("Frame")
	visualFrame.Name = "ChestContactHint"
	visualFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	visualFrame.Position = UDim2.fromScale(0.5, 0.5)
	visualFrame.Size = UDim2.fromScale(1, 1)
	visualFrame.BackgroundTransparency = 1
	visualFrame.BorderSizePixel = 0
	visualFrame.Active = false
	visualFrame.ZIndex = 20
	visualFrame.Parent = billboard

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
	titleLabel.Parent = visualFrame

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "ContactHint"
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.new(0.5, 0, 0, 43)
	subtitleLabel.Size = UDim2.new(1, -20, 0, 22)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = "ENCOSTE PARA ABRIR"
	subtitleLabel.TextColor3 = Color3.fromRGB(205, 232, 255)
	subtitleLabel.TextSize = 12
	subtitleLabel.TextStrokeColor3 = Color3.fromRGB(12, 18, 27)
	subtitleLabel.TextStrokeTransparency = 0.35
	subtitleLabel.TextTransparency = 1
	subtitleLabel.ZIndex = 21
	subtitleLabel.Parent = visualFrame
end

local function setTextStyle(prompt)
	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")

	titleLabel.Text = rare and "ABRIR BAÚ RARO" or "ABRIR BAÚ"
	subtitleLabel.Text = string.upper(label) .. "  •  ENCOSTE"

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
	player:SetAttribute("DungeonMobileChestContact", false)
	player:SetAttribute("DungeonMobileChestContactGeometry", nil)

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

	TweenService:Create(titleLabel, TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.18,
	}):Play()
	TweenService:Create(subtitleLabel, TweenInfo.new(SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.35,
	}):Play()

	player:SetAttribute("DungeonMobileChestVisible", true)
	player:SetAttribute("DungeonMobileChestDistance", math.floor(distance * 10 + 0.5) / 10)
	player:SetAttribute("DungeonMobileChestTarget", prompt.Name)
end

local function triggerPrompt(prompt)
	if not prompt or not isPromptInRange(prompt) then
		return false
	end

	local now = os.clock()
	if now - lastAutoTriggerAt < AUTO_TRIGGER_DEBOUNCE then
		return false
	end
	lastAutoTriggerAt = now
	autoTriggerAttempts += 1

	local began = pcall(function()
		prompt:InputHoldBegin()
	end)
	if not began then
		player:SetAttribute("DungeonMobileChestLastTriggerResult", "InputHoldBeginFailed")
		return false
	end

	local hold = math.max(0.06, tonumber(prompt.HoldDuration) or 0)
	task.delay(hold + 0.03, function()
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end)

	player:SetAttribute("DungeonMobileChestAutoTriggerAttempts", autoTriggerAttempts)
	player:SetAttribute("DungeonMobileChestLastAutoOpenAt", workspace:GetServerTimeNow())
	player:SetAttribute("DungeonMobileChestLastTriggerResult", "InputHoldStarted")
	return true
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

	local touching, geometrySource = isCharacterTouchingChest(prompt)
	player:SetAttribute("DungeonMobileChestContact", touching)
	player:SetAttribute("DungeonMobileChestContactGeometry", geometrySource)

	-- Tenta novamente enquanto houver contato. O debounce impede spam, mas uma
	-- tentativa perdida nao obriga mais o jogador a sair e entrar no bau.
	if touching and prompt.Enabled then
		triggerPrompt(prompt)
	end
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
player:SetAttribute("DungeonMobileChestUIPolicy", "NearestChest_Billboard_RobustAutoContact")
player:SetAttribute("DungeonMobileChestCameraDependency", false)
player:SetAttribute("DungeonMobileChestWorldTapDependency", false)
player:SetAttribute("DungeonMobileChestFixedHUD", false)
player:SetAttribute("DungeonMobileChestRequiresTap", false)
player:SetAttribute("DungeonMobileChestContactFallbackEnabled", true)
