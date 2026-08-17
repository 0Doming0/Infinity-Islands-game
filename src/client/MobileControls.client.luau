-- SkyDungeon - entrada de ataque sem controlar layout mobile.
--
-- O Roblox Studio passa a ser a autoridade visual dos controles de toque.
-- Este script NAO cria botao mobile, NAO define Position/Size/AnchorPoint e
-- NAO move o personagem ate um inimigo. Ele apenas conecta os botoes de ataque
-- existentes no DungeonHUD ao Tool.Activated.
--
-- SwordInputClient continua responsavel por combo, buffer, animacao e pela
-- assistencia leve de direcao no momento do golpe.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(
	ReplicatedStorage
		:WaitForChild("SwordCombat")
		:WaitForChild("CombatConfig")
)

local ACTION_NAME = "SkyDungeonAttack"
local VERSION = "AuthoredMobileAttackLayoutV1"

local ATTACK_BUTTON_NAMES = {
	swordattackbutton = true,
	attackbutton = true,
	mobileattackbutton = true,
	attackimagebutton = true,
	attack = true,
}

local equippedSword
local boundButtons = setmetatable({}, { __mode = "k" })

local function isMobileDungeon()
	return player:GetAttribute("DungeonMobileMode") == true
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

	-- Visibilidade e a unica propriedade visual que este controller pode tocar.
	-- Position, Size e AnchorPoint pertencem exclusivamente ao layout do Studio.
	button.Visible = isMobileDungeon()
		and equippedSword ~= nil
		and player:GetAttribute("IsDowned") ~= true
		and not (
			player.Character
			and player.Character:GetAttribute("MovementLocked") == true
		)
end

local function bindAttackButton(button)
	if not isAttackButton(button) or boundButtons[button] then
		return
	end

	boundButtons[button] = true
	button:SetAttribute("DungeonAuthoredAttackButtonBound", true)
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

-- Keyboard/gamepad continuam funcionais, mas false impede o ContextActionService
-- de fabricar um botao de toque com posicao controlada por codigo.
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

player:SetAttribute("DungeonMobileHoldAttackReady", false)
player:SetAttribute("DungeonMobileAutoEngageState", "DisabledForAuthoredControls")
player:SetAttribute("DungeonMobileAttackLayoutOwnedByStudio", true)
player:SetAttribute("DungeonMobileAttackControllerVersion", VERSION)
