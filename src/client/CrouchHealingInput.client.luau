-- CrouchHealingInput: ponte leve entre o agachar autorado e a cura do servidor.
-- Nao altera WalkSpeed, HipHeight, animacao ou movimento. Apenas observa/troca
-- o estado de agachar e publica CrouchStateRequest para PlayerRules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("CrouchStateRequest")

local VERSION = "CrouchHealingBridgeV1"
local BUTTON_NAMES = {
	crouchbutton = true,
	sneakbutton = true,
	duckbutton = true,
	agacharbutton = true,
	crouch = true,
	sneak = true,
	agachar = true,
}
local OBSERVED_ATTRIBUTES = {
	"DungeonCrouching",
	"Crouching",
	"IsCrouching",
	"Sneaking",
	"IsSneaking",
	"CrouchActive",
	"SneakActive",
}

local character
local humanoid
local baseHipHeight
local requested = false
local lastSent
local ctrlHeld = false
local boundButtons = setmetatable({}, { __mode = "k" })
local attributeConnections = {}

local function send(force)
	if not force and lastSent == requested then
		return
	end
	lastSent = requested
	remote:FireServer(requested)
	player:SetAttribute("DungeonCrouchHealingInput", requested)
end

local function setRequested(value, force)
	value = value == true
	if requested == value and not force then
		return
	end
	requested = value
	send(force == true)
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
		setRequested(value, true)
	end
end

local function bindObservedAttributes(instance)
	for _, name in ipairs(OBSERVED_ATTRIBUTES) do
		table.insert(attributeConnections, instance:GetAttributeChangedSignal(name):Connect(function()
			adoptAttribute(instance, name)
		end))
		if instance:GetAttribute(name) == true then
			setRequested(true, true)
		end
	end
end

local function bindCharacter(newCharacter)
	clearAttributeConnections()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	baseHipHeight = humanoid and humanoid.HipHeight or nil
	requested = false
	lastSent = nil
	ctrlHeld = false
	bindObservedAttributes(player)
	bindObservedAttributes(newCharacter)
	setRequested(false, true)
end

local function isCrouchButton(instance)
	if not instance or not instance:IsA("GuiButton") then
		return false
	end
	local current = instance
	for _ = 1, 5 do
		if not current then
			break
		end
		if BUTTON_NAMES[string.lower(current.Name)] then
			return true
		end
		current = current.Parent
	end
	return false
end

local function bindButton(button)
	if not isCrouchButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	button:SetAttribute("DungeonCrouchHealingBound", true)
	button.Activated:Connect(function()
		-- O controller que ja existe continua cuidando da postura/movimento.
		-- Aqui apenas espelhamos a intencao para a recuperacao de vida.
		setRequested(not requested, true)
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
		setRequested(not requested, true)
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		ctrlHeld = true
		setRequested(true, true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftControl and ctrlHeld then
		ctrlHeld = false
		setRequested(false, true)
	end
end)

-- Fallback para sistemas de agachar que alteram fisicamente HipHeight mas nao
-- publicam atributo. So assume autoridade depois de detectar uma reducao real.
task.spawn(function()
	local hipDriven = false
	while script.Parent do
		task.wait(0.12)
		if humanoid and humanoid.Parent and baseHipHeight then
			local lower = humanoid.HipHeight < baseHipHeight - 0.35
			if lower then
				hipDriven = true
				setRequested(true, false)
			elseif hipDriven then
				setRequested(false, false)
			end
		end
	end
end)

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindButton, instance)
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

task.defer(scanButtons)
player:SetAttribute("DungeonCrouchHealingInputVersion", VERSION)
