-- SkyDungeon - controle de ataque para toque, teclado e gamepad.
-- Tool.Activated continua sendo a unica entrada consumida pelo sistema de
-- combate; este controlador apenas expressa a intencao de ataque.
--
-- Mobile Dungeon Mode / Task 05:
-- no modo mobile, Begin inicia Hold-to-Attack e End/Cancel encerra.
-- SwordInputClient continua sendo responsavel por combo, windup e recovery.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))
local ACTION_NAME = "SkyDungeonAttack"
local HOLD_RETRY_INTERVAL = math.clamp(CombatConfig.InputBufferTime * 0.5, 0.04, 0.08)

local equippedSword
local holdSerial = 0
local attackHeld = false
local lastHoldStopReason = "NotStarted"

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
	return sword ~= nil and sword.Parent == character and CombatConfig.IsSword(sword)
end

local function setHeldState(held, reason)
	attackHeld = held == true
	lastHoldStopReason = tostring(reason or (attackHeld and "Holding" or "Released"))
	player:SetAttribute("DungeonMobileAttackHeld", attackHeld)
	player:SetAttribute("DungeonMobileAttackHoldStopReason", attackHeld and nil or lastHoldStopReason)

	local button = ContextActionService:GetButton(ACTION_NAME)
	if button then
		local compact = button:FindFirstChild("CompactCaption")
		if compact and compact:IsA("TextLabel") then
			compact.Text = attackHeld and "ATACANDO..." or "ATACAR"
		end
		local portrait = button:FindFirstChild("PortraitCaption")
		if portrait and portrait:IsA("TextLabel") then
			portrait.Text = attackHeld and "ATACANDO..." or "ATACAR"
		end
	end
end

local function stopHold(reason)
	holdSerial += 1
	setHeldState(false, reason or "Stopped")
end

local function activateEquippedSword()
	local sword = equippedSword or findEquippedSword()
	if not canAttack(sword) then
		return false
	end
	equippedSword = sword
	sword:Activate()
	return true
end

local function beginHold()
	stopHold("Restarted")
	holdSerial += 1
	local serial = holdSerial

	setHeldState(true, "Holding")
	player:SetAttribute("DungeonMobileAttackHoldStartedAt", workspace:GetServerTimeNow())

	task.spawn(function()
		while attackHeld and serial == holdSerial do
			if not isMobileDungeon() then
				stopHold("MobileModeEnded")
				break
			end

			if not activateEquippedSword() then
				stopHold("AttackUnavailable")
				break
			end

			-- SwordInputClient rejeita ativações antes de NextAttackAt.
			-- Repetimos a intenção em intervalo curto para que o próximo combo
			-- comece assim que o cooldown autoritativo do cliente permitir.
			task.wait(HOLD_RETRY_INTERVAL)
		end
	end)
end

local function refreshSword()
	equippedSword = findEquippedSword()
	if attackHeld and not canAttack(equippedSword) then
		stopHold("SwordUnavailable")
	end

	local button = ContextActionService:GetButton(ACTION_NAME)
	if button then
		button.Visible = isMobileDungeon()
			and equippedSword ~= nil
			and player:GetAttribute("IsDowned") ~= true
			and not (player.Character and player.Character:GetAttribute("MovementLocked") == true)
	end
end

local function attackAction(_, inputState)
	if inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel
	then
		if attackHeld then
			stopHold(inputState == Enum.UserInputState.Cancel and "Cancelled" or "Released")
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end

	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if player:GetAttribute("IsDowned") == true
		or (player.Character and player.Character:GetAttribute("MovementLocked") == true)
	then
		stopHold("Blocked")
		return Enum.ContextActionResult.Sink
	end

	-- Hold-to-Attack e exclusivo da apresentacao Mobile Dungeon.
	-- KeyboardMouse/Gamepad fora do modo mobile preservam um ataque por Begin.
	if isMobileDungeon() then
		if not canAttack(equippedSword or findEquippedSword()) then
			stopHold("NoSword")
			return Enum.ContextActionResult.Pass
		end
		beginHold()
		return Enum.ContextActionResult.Sink
	end

	if activateEquippedSword() then
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
	button.Visible = isMobileDungeon()
		and equippedSword ~= nil
		and player:GetAttribute("IsDowned") ~= true
		and not (player.Character and player.Character:GetAttribute("MovementLocked") == true)
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
	caption.Text = attackHeld and "ATACANDO..." or "ATACAR"
	caption.TextColor3 = Color3.fromRGB(245, 232, 255)
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = 9
	caption.Parent = button
end

local function bindCharacter(character)
	stopHold("CharacterChanged")
	equippedSword = nil

	character.ChildAdded:Connect(function(child)
		if CombatConfig.IsSword(child) then
			equippedSword = child
			refreshSword()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedSword then
			stopHold("SwordUnequipped")
			task.defer(refreshSword)
		end
	end)

	character:GetAttributeChangedSignal("MovementLocked"):Connect(function()
		if character:GetAttribute("MovementLocked") == true then
			stopHold("MovementLocked")
		end
		refreshSword()
	end)

	task.defer(refreshSword)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
task.defer(styleTouchButton)

player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true then
		stopHold("Downed")
	end
	refreshSword()
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if not isMobileDungeon() then
		stopHold("MobileModeEnded")
	end
	refreshSword()
	task.defer(styleTouchButton)
end)

player:SetAttribute("DungeonMobileHoldAttackReady", true)
player:SetAttribute("DungeonMobileHoldAttackPolicy", "HoldIntentToolActivatedV1")
player:SetAttribute("DungeonMobileAttackHeld", false)
player:SetAttribute("DungeonMobileAttackHoldRetryInterval", HOLD_RETRY_INTERVAL)
