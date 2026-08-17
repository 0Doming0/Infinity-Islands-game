-- CrouchHealingInput: ponte leve entre o agachar autorado e a cura do servidor.
-- Nao altera WalkSpeed, HipHeight, animacao ou movimento. Apenas observa o
-- estado/intencao de agachar e publica CrouchStateRequest para PlayerRules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("CrouchStateRequest")

local VERSION = "CrouchHealingBridgeV2_RobustDetection"
local BUTTON_NAMES = {
	crouchbutton = true,
	sneakbutton = true,
	duckbutton = true,
	agacharbutton = true,
	crouch = true,
	sneak = true,
	duck = true,
	agachar = true,
}
local TEXT_HINTS = {
	"agachar",
	"agache",
	"crouch",
	"sneak",
	"duck",
}
local OBSERVED_ATTRIBUTES = {
	"DungeonCrouching",
	"Crouching",
	"IsCrouching",
	"Sneaking",
	"IsSneaking",
	"CrouchActive",
	"SneakActive",
	"Crouched",
	"IsCrouched",
}

local character
local humanoid
local baseHipHeight
local baseCameraOffsetY
local requested = false
local lastSent
local ctrlHeld = false
local boundButtons = setmetatable({}, { __mode = "k" })
local attributeConnections = {}
local boundButtonCount = 0

local function normalize(value)
	value = string.lower(tostring(value or ""))
	value = string.gsub(value, "%s+", "")
	value = string.gsub(value, "[^%w]", "")
	return value
end

local function send(force, source)
	if not force and lastSent == requested then
		return
	end
	lastSent = requested
	remote:FireServer(requested)
	player:SetAttribute("DungeonCrouchHealingInput", requested)
	player:SetAttribute("DungeonCrouchHealingInputSource", source or "Unknown")
	player:SetAttribute("DungeonCrouchHealingInputAt", workspace:GetServerTimeNow())
end

local function setRequested(value, force, source)
	value = value == true
	if requested == value and not force then
		return
	end
	requested = value
	send(force == true, source)
end

local function clearAttributeConnections()
	for _, connection in ipairs(attributeConnections) do
		connection:Disconnect()
	end
	table.clear(attributeConnections)
end

local function adoptAttribute(instance, name)
	local value = instance:GetAttribute(name)
	if typeof(value) == "boolean" then
		setRequested(value, true, "Attribute:" .. name)
	end
end

local function bindObservedAttributes(instance)
	if not instance then
		return
	end
	for _, name in ipairs(OBSERVED_ATTRIBUTES) do
		table.insert(attributeConnections, instance:GetAttributeChangedSignal(name):Connect(function()
			adoptAttribute(instance, name)
		end))
		if instance:GetAttribute(name) == true then
			setRequested(true, true, "Attribute:" .. name)
		end
	end
end

local function bindCharacter(newCharacter)
	clearAttributeConnections()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	baseHipHeight = humanoid and humanoid.HipHeight or nil
	baseCameraOffsetY = humanoid and humanoid.CameraOffset.Y or 0
	requested = false
	lastSent = nil
	ctrlHeld = false
	bindObservedAttributes(player)
	bindObservedAttributes(newCharacter)
	bindObservedAttributes(humanoid)
	setRequested(false, true, "CharacterSpawn")
end

local function containsCrouchHint(value)
	local text = normalize(value)
	if text == "" then
		return false
	end
	if BUTTON_NAMES[text] then
		return true
	end
	for _, hint in ipairs(TEXT_HINTS) do
		if string.find(text, hint, 1, true) then
			return true
		end
	end
	return false
end

local function buttonHasCrouchText(button)
	if button:IsA("TextButton") and containsCrouchHint(button.Text) then
		return true
	end
	for _, descendant in ipairs(button:GetDescendants()) do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
			and containsCrouchHint(descendant.Text)
		then
			return true
		end
	end
	return false
end

local function isCrouchButton(instance)
	if not instance or not instance:IsA("GuiButton") then
		return false
	end
	local current = instance
	for _ = 1, 6 do
		if not current then
			break
		end
		if containsCrouchHint(current.Name) then
			return true
		end
		current = current.Parent
	end
	return buttonHasCrouchText(instance)
end

local function bindButton(button)
	if not isCrouchButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	boundButtonCount += 1
	button:SetAttribute("DungeonCrouchHealingBound", true)
	player:SetAttribute("DungeonCrouchHealingBoundButtonCount", boundButtonCount)

	button.Activated:Connect(function()
		-- O controller visual/fisico de agachar continua podendo cuidar da postura.
		-- Aqui espelhamos a intencao para a recuperacao de vida.
		setRequested(not requested, true, "GuiButton:" .. button.Name)
	end)
end

local function scanButtons()
	for _, instance in ipairs(playerGui:GetDescendants()) do
		bindButton(instance)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.ButtonB then
		setRequested(not requested, true, "KeyboardToggle")
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		ctrlHeld = true
		setRequested(true, true, "KeyboardHold")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftControl and ctrlHeld then
		ctrlHeld = false
		setRequested(false, true, "KeyboardHoldRelease")
	end
end)

-- Fallback para sistemas de agachar que mudam fisicamente o Humanoid mas nao
-- publicam atributo. HipHeight OU CameraOffset bastam para confirmar postura.
task.spawn(function()
	local physicalDriven = false
	while script.Parent do
		task.wait(0.10)
		if humanoid and humanoid.Parent then
			local hipLower = baseHipHeight ~= nil
				and humanoid.HipHeight < baseHipHeight - 0.25
			local cameraLower = humanoid.CameraOffset.Y < (baseCameraOffsetY or 0) - 0.45
			local lower = hipLower or cameraLower
			if lower then
				physicalDriven = true
				setRequested(true, false, hipLower and "HipHeight" or "CameraOffset")
			elseif physicalDriven then
				physicalDriven = false
				setRequested(false, false, "PhysicalPostureReleased")
			end
		end
	end
end)

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindButton, instance)
	-- Alguns botoes recebem texto/filhos alguns frames depois de serem criados.
	if instance:IsA("GuiButton") then
		task.delay(0.5, function()
			if instance.Parent then
				bindButton(instance)
			end
		end)
	end
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

task.defer(scanButtons)
task.delay(1, scanButtons)
task.delay(3, scanButtons)
player:SetAttribute("DungeonCrouchHealingInputVersion", VERSION)
