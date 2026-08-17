-- MobileChestInteractionController
--
-- Autoridade exclusiva da interacao de baus em dispositivos touch.
-- Nao depende de ProximityPromptService.PromptShown.
-- Usa tres sinais simples e confiaveis:
--   1) distancia real HumanoidRootPart -> bau;
--   2) camera confirma que o bau esta dentro da tela;
--   3) toque no botao 3D ou diretamente no proprio bau dispara o mesmo ProximityPrompt.
--
-- A camera nunca e movida por este script; ela apenas ajuda a decidir qual bau
-- visivel deve receber a interacao para evitar UI perdida fora da tela.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "MobileChestInteractionV1_ProximityCameraTap"
local SCAN_INTERVAL = 0.08
local SCREEN_EDGE_MARGIN = 18
local CENTER_WEIGHT = 0.008
local TAP_DEBOUNCE_SECONDS = 0.35

local trackedPrompts = setmetatable({}, { __mode = "k" })
local promptConnections = setmetatable({}, { __mode = "k" })

local activePrompt
local activeDistance = math.huge
local scanAccumulator = 0
local lastTriggerAt = 0

local billboard
local button
local stroke

local function touchEnabled()
	return UserInputService.TouchEnabled == true
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
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	end
	return nil
end

local function chestContainer(prompt)
	local current = prompt and prompt.Parent
	local nearestModel
	while current and current ~= workspace do
		if current:IsA("Model") then
			nearestModel = current
			break
		end
		current = current.Parent
	end
	return nearestModel or (prompt and prompt.Parent)
end

local function maxActivationDistance(prompt)
	return math.max(1, tonumber(prompt and prompt.MaxActivationDistance) or 10)
end

local function distanceToPrompt(prompt)
	local root = characterRoot()
	local position = promptWorldPosition(prompt)
	if not root or not position then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

local function withinActivationRange(prompt)
	if not isChestPrompt(prompt) or not prompt.Enabled or not prompt.Parent then
		return false
	end
	return distanceToPrompt(prompt) <= maxActivationDistance(prompt)
end

local function cameraProjection(prompt)
	local camera = workspace.CurrentCamera
	local position = promptWorldPosition(prompt)
	if not camera or not position then
		return nil
	end

	-- Testamos um ponto levemente acima do ProximityPrompt, que corresponde ao
	-- local onde o BillboardGui aparece e evita considerar um bau abaixo da tela.
	local point, onScreen = camera:WorldToViewportPoint(position + Vector3.new(0, 2.2, 0))
	if not onScreen or point.Z <= 0 then
		return nil
	end

	local viewport = camera.ViewportSize
	if point.X < SCREEN_EDGE_MARGIN
		or point.Y < SCREEN_EDGE_MARGIN
		or point.X > viewport.X - SCREEN_EDGE_MARGIN
		or point.Y > viewport.Y - SCREEN_EDGE_MARGIN
	then
		return nil
	end

	return Vector2.new(point.X, point.Y), viewport
end

local function promptScore(prompt)
	if not withinActivationRange(prompt) then
		return nil
	end

	local screenPoint, viewport = cameraProjection(prompt)
	if not screenPoint then
		return nil
	end

	local distance = distanceToPrompt(prompt)
	local center = viewport * 0.5
	local centerDistance = (screenPoint - center).Magnitude

	-- Distancia fisica continua sendo a prioridade. A camera so desempata em
	-- favor do bau mais facil de enxergar/tocar quando dois estao muito proximos.
	return distance + centerDistance * CENTER_WEIGHT, distance
end

local function ensureBillboard()
	if billboard and billboard.Parent and button and button.Parent then
		return
	end

	billboard = Instance.new("BillboardGui")
	billboard.Name = "MobileSmartChestPrompt"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(180, 56)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	billboard.Enabled = false
	billboard.Parent = playerGui

	button = Instance.new("TextButton")
	button.Name = "TapToOpen"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(25, 43, 67)
	button.BackgroundTransparency = 0.06
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBlack
	button.Text = "ABRIR BAÚ"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeColor3 = Color3.new(0, 0, 0)
	button.TextStrokeTransparency = 0.3
	button.TextScaled = true
	button.ZIndex = 12
	button.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 13)
	corner.Parent = button

	stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(151, 218, 255)
	stroke.Thickness = 1.7
	stroke.Transparency = 0.08
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = button

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 13
	constraint.MaxTextSize = 20
	constraint.Parent = button
end

local function hidePrompt()
	activePrompt = nil
	activeDistance = math.huge
	if billboard then
		billboard.Enabled = false
		billboard.Adornee = nil
	end
	player:SetAttribute("DungeonMobileChestTarget", nil)
	player:SetAttribute("DungeonMobileChestDistance", nil)
	player:SetAttribute("DungeonMobileChestVisible", false)
end

local function showPrompt(prompt, distance)
	local adornee = promptAdornee(prompt)
	if not adornee then
		hidePrompt()
		return
	end

	ensureBillboard()
	activePrompt = prompt
	activeDistance = distance
	billboard.Adornee = adornee
	billboard.MaxDistance = maxActivationDistance(prompt) + 2

	local rare = prompt:GetAttribute("ChestPromptRare") == true
	local label = tostring(prompt:GetAttribute("ChestPromptLabel") or prompt.ObjectText or "Baú")
	button.Text = "TOCAR PARA ABRIR " .. string.upper(label)
	button.BackgroundColor3 = rare and Color3.fromRGB(83, 61, 19) or Color3.fromRGB(25, 43, 67)
	button.TextColor3 = rare and Color3.fromRGB(255, 229, 125) or Color3.new(1, 1, 1)
	stroke.Color = rare and Color3.fromRGB(255, 215, 76) or Color3.fromRGB(151, 218, 255)
	billboard.Enabled = true

	player:SetAttribute("DungeonMobileChestTarget", prompt.Name)
	player:SetAttribute("DungeonMobileChestDistance", math.floor(distance * 10 + 0.5) / 10)
	player:SetAttribute("DungeonMobileChestVisible", true)
end

local function triggerPrompt(prompt)
	if not prompt or prompt ~= activePrompt or not withinActivationRange(prompt) then
		return false
	end
	if not cameraProjection(prompt) then
		return false
	end

	local now = os.clock()
	if now - lastTriggerAt < TAP_DEBOUNCE_SECONDS then
		return false
	end
	lastTriggerAt = now

	prompt:InputHoldBegin()
	task.delay(math.max(0.05, tonumber(prompt.HoldDuration) or 0), function()
		if prompt.Parent then
			prompt:InputHoldEnd()
		end
	end)

	player:SetAttribute("DungeonMobileChestLastTapAt", workspace:GetServerTimeNow())
	return true
end

local function updateTarget()
	if not touchEnabled() then
		hidePrompt()
		return
	end

	local bestPrompt
	local bestScore = math.huge
	local bestDistance = math.huge

	for prompt in pairs(trackedPrompts) do
		if prompt.Parent then
			local score, distance = promptScore(prompt)
			if score and score < bestScore then
				bestPrompt = prompt
				bestScore = score
				bestDistance = distance
			end
		end
	end

	if not bestPrompt then
		hidePrompt()
		return
	end

	if activePrompt ~= bestPrompt or not billboard or not billboard.Enabled then
		showPrompt(bestPrompt, bestDistance)
	else
		activeDistance = bestDistance
		player:SetAttribute("DungeonMobileChestDistance", math.floor(bestDistance * 10 + 0.5) / 10)
	end
end

local function trackPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end

	if isChestPrompt(prompt) then
		trackedPrompts[prompt] = true
	end

	if promptConnections[prompt] then
		return
	end

	local connections = {}
	connections[#connections + 1] = prompt:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
		if isChestPrompt(prompt) then
			trackedPrompts[prompt] = true
		else
			trackedPrompts[prompt] = nil
			if activePrompt == prompt then
				hidePrompt()
			end
		end
	end)
	connections[#connections + 1] = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not prompt.Enabled and activePrompt == prompt then
			hidePrompt()
		end
	end)
	promptConnections[prompt] = connections
end

local function untrackPrompt(prompt)
	trackedPrompts[prompt] = nil
	local connections = promptConnections[prompt]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		promptConnections[prompt] = nil
	end
	if activePrompt == prompt then
		hidePrompt()
	end
end

local function screenTapHitsActiveChest(screenPosition)
	local prompt = activePrompt
	local camera = workspace.CurrentCamera
	if not prompt or not camera or not withinActivationRange(prompt) then
		return false
	end

	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local character = player.Character
	params.FilterDescendantsInstances = character and { character } or {}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not result or not result.Instance then
		return false
	end

	local container = chestContainer(prompt)
	if not container then
		return false
	end
	return result.Instance == container or result.Instance:IsDescendantOf(container)
end

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

if touchEnabled() then
	ensureBillboard()
	button.Activated:Connect(function()
		triggerPrompt(activePrompt)
	end)

	-- Alem do CTA sobre o bau, tocar diretamente no modelo do bau tambem abre.
	-- O ray sai da propria camera no ponto exato tocado pelo jogador.
	UserInputService.TouchTap:Connect(function(touchPositions, processedByUI)
		if processedByUI or not activePrompt then
			return
		end
		local first = touchPositions and touchPositions[1]
		if typeof(first) == "Vector2" and screenTapHitsActiveChest(first) then
			triggerPrompt(activePrompt)
		end
	end)
end

RunService.Heartbeat:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator < SCAN_INTERVAL then
		return
	end
	scanAccumulator = 0
	updateTarget()
end)

player.CharacterRemoving:Connect(hidePrompt)

player:SetAttribute("DungeonMobileChestControllerVersion", VERSION)
player:SetAttribute("DungeonMobileChestSelectionPolicy", "NearestInRangeAndOnScreen")
player:SetAttribute("DungeonMobileChestTapPolicy", "WorldButtonOrDirectChestTap")
player:SetAttribute("DungeonMobileChestCameraPolicy", "VisibilityOnly_NoCameraMovement")
