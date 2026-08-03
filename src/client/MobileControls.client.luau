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
		button.Visible = UserInputService.TouchEnabled
			and equippedSword ~= nil
			and player:GetAttribute("IsDowned") ~= true
	end
end

local function attackAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if player:GetAttribute("IsDowned") == true
		or (player.Character and player.Character:GetAttribute("MovementLocked") == true)
	then
		return Enum.ContextActionResult.Sink
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
ContextActionService:SetTitle(ACTION_NAME, "⚔")
ContextActionService:SetPosition(ACTION_NAME, UDim2.fromScale(0.80, 0.70))

local function styleTouchButton()
	local button = ContextActionService:GetButton(ACTION_NAME)
	if not button then
		return
	end
	button.Name = "SwordAttackButton"
	button.Size = UDim2.fromOffset(76, 76)
	button.BackgroundColor3 = Color3.fromRGB(122, 58, 185)
	button.BackgroundTransparency = 0.12
	button.Visible = UserInputService.TouchEnabled
		and equippedSword ~= nil
		and player:GetAttribute("IsDowned") ~= true
	local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 208, 255)
	stroke.Thickness = 2
	stroke.Parent = button
	local caption = button:FindFirstChild("CompactCaption") or Instance.new("TextLabel")
	caption.Name = "CompactCaption"
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -7)
	caption.Size = UDim2.new(1, -8, 0, 12)
	caption.BackgroundTransparency = 1
	caption.Text = "ATACAR"
	caption.TextColor3 = Color3.fromRGB(245, 232, 255)
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = 9
	caption.Parent = button
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

player:GetAttributeChangedSignal("IsDowned"):Connect(refreshSword)
