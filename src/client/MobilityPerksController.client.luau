-- Controles discretos para asas e Shadow Cloak.
-- O servidor continua sendo autoridade sobre posse, estamina e recarga.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")
local event = ReplicatedStorage:WaitForChild("MonetizationEvent")

local COLORS = {
	Panel = Color3.fromRGB(13, 20, 31),
	Text = Color3.fromRGB(243, 248, 255),
	Muted = Color3.fromRGB(166, 181, 199),
	Wing = Color3.fromRGB(92, 205, 255),
	WingLow = Color3.fromRGB(255, 190, 92),
	Cape = Color3.fromRGB(188, 142, 255),
	Cooldown = Color3.fromRGB(125, 139, 158),
	Error = Color3.fromRGB(255, 111, 111),
}

local oldGui = player:WaitForChild("PlayerGui"):FindFirstChild("MobilityPerksUI")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MobilityPerksUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player.PlayerGui

-- Fica ao lado direito do personagem, que normalmente ocupa o centro da tela.
local holder = Instance.new("Frame")
holder.Name = "CharacterSideCommands"
holder.AnchorPoint = Vector2.new(0, 0.5)
holder.Position = UDim2.new(0.5, 72, 0.5, 18)
holder.Size = UDim2.fromOffset(176, 74)
holder.BackgroundTransparency = 1
holder.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 7)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = holder

local scale = Instance.new("UIScale")
scale.Parent = holder

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function createCommand(id, order, accent, clickable)
	local container = Instance.new("Frame")
	container.Name = id
	container.Size = UDim2.fromOffset(176, 32)
	container.BackgroundColor3 = COLORS.Panel
	container.BackgroundTransparency = 0.24
	container.BorderSizePixel = 0
	container.LayoutOrder = order
	container.Visible = false
	container.Parent = holder
	addCorner(container, 9)

	local stroke = Instance.new("UIStroke")
	stroke.Name = "StateStroke"
	stroke.Color = accent
	stroke.Transparency = 0.58
	stroke.Thickness = 1
	stroke.Parent = container

	local dot = Instance.new("Frame")
	dot.Name = "StateDot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 9, 0.5, -1)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = accent
	dot.BorderSizePixel = 0
	dot.Parent = container
	addCorner(dot, 6)

	local text = Instance.new("TextLabel")
	text.Name = "Command"
	text.Position = UDim2.fromOffset(23, 0)
	text.Size = UDim2.new(1, -31, 1, -3)
	text.BackgroundTransparency = 1
	text.Text = ""
	text.TextColor3 = COLORS.Text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 12
	text.Parent = container

	local track = Instance.new("Frame")
	track.Name = "EnergyTrack"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 9, 1, -4)
	track.Size = UDim2.new(1, -18, 0, 2)
	track.BackgroundColor3 = Color3.fromRGB(41, 53, 69)
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.Parent = container
	addCorner(track, 2)

	local fill = Instance.new("Frame")
	fill.Name = "Energy"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, 2)

	local button
	if clickable then
		button = Instance.new("TextButton")
		button.Name = "Activate"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.Parent = container
	end

	return {
		Container = container,
		Stroke = stroke,
		Dot = dot,
		Text = text,
		Track = track,
		Fill = fill,
		Button = button,
		Feedback = nil,
		FeedbackUntil = 0,
		Pending = false,
	}
end

local wing = createCommand("WingCommand", 1, COLORS.Wing, false)
local cape = createCommand("CapeCommand", 2, COLORS.Cape, true)
local entitlementData = {}
local lastWingRequestAt = 0
local activeJumpPress = nil
local jumpPressSerial = 0
local boundJumpButtons = {}

-- Um toque curto continua sendo processado normalmente pelo controle padrao
-- do Roblox. Somente uma pressao sustentada vira uma solicitacao de voo.
local WING_HOLD_SECONDS = 0.28
local WING_REQUEST_DEBOUNCE_SECONDS = 0.45

local function setCommand(record, text, color, progress, showTrack)
	record.Text.Text = text
	record.Text.TextColor3 = color == COLORS.Cooldown and COLORS.Muted or COLORS.Text
	record.Dot.BackgroundColor3 = color
	record.Stroke.Color = color
	record.Fill.BackgroundColor3 = color
	record.Fill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
	record.Track.Visible = showTrack == true
end

local function showFeedback(record, message, success)
	record.Feedback = tostring(message or "")
	record.FeedbackUntil = os.clock() + 1.25
	record.Text.Text = record.Feedback
	record.Dot.BackgroundColor3 = success and COLORS.Cape or COLORS.Error
end

local function invoke(action, record, quiet)
	if record.Pending then
		return
	end
	record.Pending = true
	local success, result = pcall(request.InvokeServer, request, action)
	record.Pending = false
	if not quiet then
		if success and type(result) == "table" then
			showFeedback(record, result.Message, result.Success == true)
		else
			showFeedback(record, "Sem conexao", false)
		end
	elseif success and type(result) == "table" and result.Success ~= true then
		showFeedback(record, result.Message, false)
	end
end

local function numberFrom(data, key, attribute, fallback)
	local value = data and tonumber(data[key])
	if value == nil then
		value = tonumber(player:GetAttribute(attribute))
	end
	return value or fallback
end

local function refreshVisibility(data)
	if type(data) == "table" then
		for key, value in pairs(data) do
			entitlementData[key] = value
		end
		-- Campos opcionais precisam ser limpos explicitamente: uma chave com
		-- valor nil nao atravessa um RemoteEvent.
		entitlementData.WingProductId = data.WingProductId
		entitlementData.WingDisplayName = data.WingDisplayName
		entitlementData.TemporaryWingUses = data.TemporaryWingUses
		entitlementData.OwnsCape = data.OwnsCape
	end
	local wingProductId = entitlementData.WingProductId
		or player:GetAttribute("OwnedWingProductId")
	local temporaryUses = numberFrom(
		entitlementData,
		"TemporaryWingUses",
		"TemporaryWingUses",
		0
	)
	wing.Container.Visible = wingProductId ~= nil
		or temporaryUses > 0
		or player:GetAttribute("WingActive") == true
	cape.Container.Visible = entitlementData.OwnsCape == true
		or player:GetAttribute("OwnsInvisibilityCape") == true
end

local function canRequestWing()
	if not wing.Container.Visible or player:GetAttribute("WingActive") == true then
		return false
	end
	local stamina = tonumber(player:GetAttribute("WingStamina")) or 0
	if stamina <= 0.1 then
		return false
	end
	return true
end

local function resetIntentLater(expectedIntent)
	task.delay(0.16, function()
		if player:GetAttribute("WingInputIntent") == expectedIntent then
			player:SetAttribute("WingInputIntent", "Idle")
		end
	end)
end

local function beginJumpPress(source, inputObject)
	if activeJumpPress or UserInputService:GetFocusedTextBox() then
		return
	end
	if not canRequestWing() then
		return
	end

	jumpPressSerial += 1
	local press = {
		Serial = jumpPressSerial,
		Source = source,
		InputObject = inputObject,
		StartedAt = os.clock(),
		ActivatedFlight = false,
	}
	activeJumpPress = press
	player:SetAttribute("WingInputIntent", "Pending")

	task.delay(WING_HOLD_SECONDS, function()
		if activeJumpPress ~= press or press.Serial ~= jumpPressSerial then
			return
		end
		if not canRequestWing() then
			activeJumpPress = nil
			player:SetAttribute("WingInputIntent", "Idle")
			return
		end

		local now = os.clock()
		if now - lastWingRequestAt < WING_REQUEST_DEBOUNCE_SECONDS then
			return
		end
		lastWingRequestAt = now
		press.ActivatedFlight = true
		player:SetAttribute("WingInputIntent", "HoldFlight")
		invoke("ActivateWing", wing, true)
	end)
end

local function jumpPressMatches(press, source, inputObject)
	if not press or press.Source ~= source then
		return false
	end
	-- No toque, identifica o dedo exato que iniciou a pressao. Para teclado e
	-- controle, o InputObject de Begin/End pode ser substituido pelo Roblox.
	if source == "TouchJumpButton" then
		return press.InputObject == inputObject
	end
	return true
end

local function endJumpPress(source, inputObject)
	local press = activeJumpPress
	if not jumpPressMatches(press, source, inputObject) then
		return
	end
	activeJumpPress = nil
	jumpPressSerial += 1

	if press.ActivatedFlight then
		player:SetAttribute("WingInputIntent", "Idle")
	else
		player:SetAttribute("WingInputIntent", "TapJump")
		resetIntentLater("TapJump")
	end
end

local function keyboardOrGamepadSource(input)
	if input.UserInputType == Enum.UserInputType.Keyboard
		and input.KeyCode == Enum.KeyCode.Space
	then
		return "KeyboardSpace"
	end
	if input.KeyCode == Enum.KeyCode.ButtonA then
		return "GamepadA"
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	local source = keyboardOrGamepadSource(input)
	if source then
		beginJumpPress(source, input)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local source = keyboardOrGamepadSource(input)
	if source then
		endJumpPress(source, input)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		endJumpPress("TouchJumpButton", input)
	end
end)

local function bindTouchJumpButton(descendant)
	if not descendant:IsA("GuiButton")
		or descendant.Name ~= "JumpButton"
		or boundJumpButtons[descendant]
	then
		return
	end
	boundJumpButtons[descendant] = true

	descendant.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			beginJumpPress("TouchJumpButton", input)
		end
	end)
	descendant.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			endJumpPress("TouchJumpButton", input)
		end
	end)
end

for _, descendant in ipairs(player.PlayerGui:GetDescendants()) do
	bindTouchJumpButton(descendant)
end
player.PlayerGui.DescendantAdded:Connect(bindTouchJumpButton)

player.CharacterAdded:Connect(function()
	activeJumpPress = nil
	jumpPressSerial += 1
	player:SetAttribute("WingInputIntent", "Idle")
end)

player:GetAttributeChangedSignal("WingActive"):Connect(function()
	if player:GetAttribute("WingActive") == true and activeJumpPress then
		player:SetAttribute("WingInputIntent", "HoldFlight")
	end
end)

local function cancelStaleJumpPress()
	local press = activeJumpPress
	if not press then
		return
	end
	-- Protege contra um InputEnded perdido ao abrir o menu, perder o foco ou
	-- arrastar o dedo para fora do botao.
	if os.clock() - press.StartedAt > 8 then
		activeJumpPress = nil
		jumpPressSerial += 1
		player:SetAttribute("WingInputIntent", "Idle")
	end
end

RunService.Heartbeat:Connect(cancelStaleJumpPress)

--[[
	O controle padrao continua recebendo o mesmo input e executa o pulo. Este
	script apenas observa por quanto tempo o comando ficou pressionado.
	JumpRequest nao e usado para ativar as asas, pois ele nao informa quando
	o jogador soltou o botao.
]]

cape.Button.Activated:Connect(function()
	invoke("ActivateCape", cape, false)
end)

ContextActionService:BindAction("ActivateOwnedCape", function(_, inputState)
	if inputState == Enum.UserInputState.Begin and cape.Container.Visible then
		invoke("ActivateCape", cape, false)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.G)

local function updateWing()
	if not wing.Container.Visible then
		return
	end
	if wing.FeedbackUntil > os.clock() then
		return
	end
	local stamina = tonumber(player:GetAttribute("WingStamina")) or 0
	local maximum = math.max(0.01, tonumber(player:GetAttribute("WingStaminaMax")) or 1)
	local ratio = math.clamp(stamina / maximum, 0, 1)
	local active = player:GetAttribute("WingActive") == true
	local phase = player:GetAttribute("WingFlightPhase")
	local inputName = UserInputService.TouchEnabled and "PULAR" or "ESPACO"
	local color = ratio <= 0.22 and COLORS.WingLow or COLORS.Wing
	if active then
		local stateText = if phase == "Rising"
			then "Subindo"
			elseif phase == "ExhaustedGlide"
			then "Planando sem impulso"
			else "Planando"
		setCommand(
			wing,
			string.format("%s  %d%%", stateText, math.floor(ratio * 100 + 0.5)),
			color,
			ratio,
			true
		)
	elseif ratio < 0.995 then
		setCommand(
			wing,
			string.format(
				"Segure %s  %d%%",
				inputName,
				math.floor(ratio * 100 + 0.5)
			),
			color,
			ratio,
			true
		)
	else
		setCommand(wing, string.format("Segure %s para voar", inputName), COLORS.Wing, 1, true)
	end
end

local function updateCape(now)
	if not cape.Container.Visible then
		return
	end
	if cape.FeedbackUntil > os.clock() then
		return
	end
	local activeUntil = tonumber(player:GetAttribute("CapeActiveUntil")) or 0
	local readyAt = tonumber(player:GetAttribute("CapeReadyAt")) or 0
	local duration = numberFrom(entitlementData, "CapeDurationSeconds", "CapeDurationSeconds", 14)
	local cooldown = numberFrom(entitlementData, "CapeCooldownSeconds", "CapeCooldownSeconds", 45)
	local active = player:GetAttribute("CapeInvisibleToEnemies") == true and activeUntil > now
	if active then
		local remaining = activeUntil - now
		setCommand(
			cape,
			string.format("Invisivel  %.1fs", remaining),
			COLORS.Cape,
			remaining / duration,
			true
		)
	elseif readyAt > now then
		local remaining = readyAt - now
		setCommand(
			cape,
			string.format("Se esconder  %ds", math.ceil(remaining)),
			COLORS.Cooldown,
			1 - remaining / cooldown,
			true
		)
	else
		local inputName = UserInputService.TouchEnabled and "TOCAR" or "G"
		setCommand(cape, string.format("Se esconder — %s", inputName), COLORS.Cape, 1, false)
	end
end

event.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Action == "Entitlements" then
		refreshVisibility(data)
	end
end)

task.spawn(function()
	local success, data = pcall(request.InvokeServer, request, "GetEntitlements")
	if success and type(data) == "table" then
		refreshVisibility(data)
	else
		refreshVisibility()
	end
end)

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / 1000, viewport.Y / 620), 0.72, 1)
	holder.Position = UDim2.new(
		0.5,
		UserInputService.TouchEnabled and 52 or 72,
		0.5,
		18
	)
end

local cameraConnection
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

player:GetAttributeChangedSignal("OwnedWingProductId"):Connect(refreshVisibility)
player:GetAttributeChangedSignal("TemporaryWingUses"):Connect(refreshVisibility)
player:GetAttributeChangedSignal("WingActive"):Connect(refreshVisibility)
player:GetAttributeChangedSignal("OwnsInvisibilityCape"):Connect(refreshVisibility)

local elapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.05 then
		return
	end
	elapsed = 0
	local now = workspace:GetServerTimeNow()
	updateWing()
	updateCape(now)
end)

player:SetAttribute("MobilityPerksClientVersion", "TapJumpHoldFlightV6")
player:SetAttribute("WingInputMode", "TapJumpHoldFlight")
player:SetAttribute("WingHoldThresholdSeconds", WING_HOLD_SECONDS)
player:SetAttribute("WingInputIntent", "Idle")
