-- SkyDungeon - controle de ataque para toque, teclado e gamepad.
-- Tool.Activated continua sendo a unica entrada consumida pelo sistema de
-- combate; este botao apenas chama Tool:Activate() de forma acessivel.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))
local ACTION_NAME = "SkyDungeonAttack"
local equippedSword

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

local function refreshSword()
	equippedSword = findEquippedSword()
	local button = ContextActionService:GetButton(ACTION_NAME)
	if button then
		button.Visible = UserInputService.TouchEnabled and equippedSword ~= nil
	end
end

local function attackAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local sword = equippedSword or findEquippedSword()
	if sword and sword.Parent == player.Character then
		sword:Activate()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(
	ACTION_NAME,
	attackAction,
	true,
	Enum.KeyCode.F,
	Enum.KeyCode.ButtonR2
)
ContextActionService:SetTitle(ACTION_NAME, "ATACAR")
ContextActionService:SetPosition(ACTION_NAME, UDim2.fromScale(0.82, 0.72))

local function styleTouchButton()
	local button = ContextActionService:GetButton(ACTION_NAME)
	if not button then
		return
	end
	button.Name = "SwordAttackButton"
	button.Size = UDim2.fromOffset(112, 112)
	button.BackgroundColor3 = Color3.fromRGB(122, 58, 185)
	button.BackgroundTransparency = 0.12
	button.Visible = UserInputService.TouchEnabled and equippedSword ~= nil
	local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 208, 255)
	stroke.Thickness = 3
	stroke.Parent = button
end

local function bindCharacter(character)
	equippedSword = nil
	character.ChildAdded:Connect(function(child)
		if CombatConfig.IsSword(child) then
			equippedSword = child
			refreshSword()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedSword then
			task.defer(refreshSword)
		end
	end)
	task.defer(refreshSword)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
task.defer(styleTouchButton)
