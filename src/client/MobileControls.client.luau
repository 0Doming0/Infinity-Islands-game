-- SkyDungeon - entrada de ataque sem controlar layout mobile.
--
-- O Roblox Studio e a autoridade visual dos controles de toque.
-- Este script NAO cria botao mobile, NAO define Position/Size/AnchorPoint e
-- NAO move o personagem. Ele conecta os botoes de ataque existentes ao
-- Tool.Activated e publica um sinal local Begin/End para o assistente de hold.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(
	ReplicatedStorage
		:WaitForChild("SwordCombat")
		:WaitForChild("CombatConfig")
)

local ACTION_NAME = "SkyDungeonAttack"
local VERSION = "AuthoredMobileAttackLayoutV3_HoldSignal"

local ATTACK_BUTTON_NAMES = {
	swordattackbutton = true,
	attackbutton = true,
	mobileattackbutton = true,
	attackimagebutton = true,
	attack = true,
}

local equippedSword
local boundButtons = setmetatable({}, { __mode = "k" })
local pressingButtons = setmetatable({}, { __mode = "k" })

local holdSignal = playerGui:FindFirstChild("DungeonMobileAttackHoldSignal")
if holdSignal and not holdSignal:IsA("BindableEvent") then
	holdSignal:Destroy()
	holdSignal = nil
end
if not holdSignal then
	holdSignal = Instance.new("BindableEvent")
	holdSignal.Name = "DungeonMobileAttackHoldSignal"
	holdSignal.Parent = playerGui
end

local function isMobileDungeon()
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
end

local function findEquippedSword()
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if CombatConfig.IsSword(child) then
			return child
		end
	end
	return nil
end

local function canAttack(sword)
	local character = player.Character
	if not character
		or player:GetAttribute("IsDowned") == true
		or character:GetAttribute("MovementLocked") == true
	then
		return false
	end

	return sword ~= nil
		and sword.Parent == character
		and CombatConfig.IsSword(sword)
end

local function activateEquippedSword()
	local sword = equippedSword or findEquippedSword()
	if not canAttack(sword) then
		return false
	end

	equippedSword = sword
	sword:Activate()
	player:SetAttribute(
		"DungeonLastAuthoredAttackInputAt",
		workspace:GetServerTimeNow()
	)
	return true
end

local function isAttackButton(instance)
	if not instance or not instance:IsA("GuiButton") then
		return false
	end

	if ATTACK_BUTTON_NAMES[string.lower(instance.Name)] then
		return true
	end

	local parent = instance.Parent
	return parent
		and ATTACK_BUTTON_NAMES[string.lower(parent.Name)] == true
end

local function refreshButton(button)
	if not button or not button.Parent then
		return
	end

	button.Visible = isMobileDungeon()
		and equippedSword ~= nil
		and player:GetAttribute("IsDowned") ~= true
		and not (
			player.Character
			and player.Character:GetAttribute("MovementLocked") == true
		)
end

local function publishHold(button, phase, input)
	if not isMobileDungeon() or not button or not button.Parent then
		return
	end

	if phase == "Begin" then
		if pressingButtons[button] then
			return
		end
		pressingButtons[button] = true
		button:SetAttribute("DungeonMobileAttackPressed", true)
	else
		if not pressingButtons[button] then
			return
		end
		pressingButtons[button] = nil
		button:SetAttribute("DungeonMobileAttackPressed", false)
	end

	holdSignal:Fire(phase, button, input)
	player:SetAttribute("DungeonMobileAttackHoldSignalPhase", phase)
	player:SetAttribute("DungeonMobileAttackHoldSignalAt", workspace:GetServerTimeNow())
end

local function bindAttackButton(button)
	if not isAttackButton(button) or boundButtons[button] then
		return
	end

	boundButtons[button] = true
	button:SetAttribute("DungeonAuthoredAttackButtonBound", true)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			publishHold(button, "Begin", input)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			publishHold(button, "End", input)
		end
	end)

	-- Eventos de GuiButton servem como redundancia em aparelhos/emuladores onde
	-- InputBegan/InputEnded podem ser interceptados por outro overlay.
	button.MouseButton1Down:Connect(function()
		publishHold(button, "Begin", nil)
	end)
	button.MouseButton1Up:Connect(function()
		publishHold(button, "End", nil)
	end)

	button.Activated:Connect(function()
		activateEquippedSword()
	end)
	refreshButton(button)
end

local function refreshAllButtons()
	local count = 0
	for button in pairs(boundButtons) do
		if button.Parent then
			count += 1
			refreshButton(button)
		end
	end
	player:SetAttribute("DungeonAuthoredAttackButtonCount", count)
end

local function scanButtons()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		bindAttackButton(descendant)
	end
	refreshAllButtons()
end

local function attackAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if activateEquippedSword() then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(
	ACTION_NAME,
	attackAction,
	false,
	Enum.KeyCode.F,
	Enum.KeyCode.ButtonR2
)

local function refreshSword()
	equippedSword = findEquippedSword()
	refreshAllButtons()
end

local function bindCharacter(character)
	equippedSword = nil

	character.ChildAdded:Connect(function(child)
		if CombatConfig.IsSword(child) then
			equippedSword = child
			refreshAllButtons()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child == equippedSword then
			equippedSword = nil
			task.defer(refreshSword)
		end
	end)

	character:GetAttributeChangedSignal("MovementLocked"):Connect(refreshAllButtons)
	task.defer(refreshSword)
end

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindAttackButton, instance)
end)

player:GetAttributeChangedSignal("IsDowned"):Connect(refreshAllButtons)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	refreshAllButtons()
	task.defer(scanButtons)
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

task.defer(scanButtons)

player:SetAttribute("DungeonMobileAttackLayoutOwnedByStudio", true)
player:SetAttribute("DungeonMobileAttackControllerVersion", VERSION)
player:SetAttribute("DungeonMobileAttackHoldSignalReady", true)
