-- SkyDungeon - controle de ataque para toque, teclado e gamepad.
-- Tool.Activated continua sendo a unica entrada consumida pelo sistema de
-- combate; este controlador apenas expressa a intencao de ataque.
--
-- Mobile Dungeon Mode / Task 05:
-- no modo mobile, um toque inicia a aproximação/ataque automático do inimigo
-- vivo mais próximo; o próximo toque cancela.
-- SwordInputClient continua sendo responsavel por combo, windup e recovery.

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))
local ACTION_NAME = "SkyDungeonAttack"
local HOLD_RETRY_INTERVAL = math.clamp(CombatConfig.InputBufferTime * 0.5, 0.04, 0.08)
local AUTO_ENGAGE_RADIUS = 36
local AUTO_ENGAGE_MAX_VERTICAL_DISTANCE = 10
local AUTO_ENGAGE_ATTACK_DISTANCE = 5.25
local AUTO_ENGAGE_MOVE_REFRESH_INTERVAL = 0.14
local TARGET_INDICATOR_NAME = "MobileAutoEngageTargetIndicator"

local equippedSword
local holdSerial = 0
local attackHeld = false
local lastHoldStopReason = "NotStarted"
local guidedTarget
local targetIndicator
local lastMoveAt = 0

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

local function targetRoot(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function validAutoEngageTarget(model, character, characterRoot)
	if not model
		or not model:IsA("Model")
		or not model.Parent
		or model == character
		or model:GetAttribute("Peaceful") == true
		or model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("NoSwordDamage") == true
		or model:GetAttribute("ObjectiveTargetCompleted") == true
	then
		return false
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = targetRoot(model)
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end

	local offset = root.Position - characterRoot.Position
	local horizontalDistance = Vector2.new(offset.X, offset.Z).Magnitude
	return math.abs(offset.Y) <= AUTO_ENGAGE_MAX_VERTICAL_DISTANCE
		and horizontalDistance <= AUTO_ENGAGE_RADIUS
end

local function ensureTargetIndicator()
	if targetIndicator and targetIndicator.Parent then
		return targetIndicator
	end

	local old = (workspace.CurrentCamera and workspace.CurrentCamera:FindFirstChild(TARGET_INDICATOR_NAME))
		or workspace:FindFirstChild(TARGET_INDICATOR_NAME)
	if old and old:IsA("Highlight") then
		targetIndicator = old
		return targetIndicator
	end

	targetIndicator = Instance.new("Highlight")
	targetIndicator.Name = TARGET_INDICATOR_NAME
	targetIndicator.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	targetIndicator.FillColor = Color3.fromRGB(255, 226, 99)
	targetIndicator.FillTransparency = 0.88
	targetIndicator.OutlineColor = Color3.fromRGB(255, 255, 255)
	targetIndicator.OutlineTransparency = 0.04
	targetIndicator.Enabled = false
	targetIndicator.Parent = workspace.CurrentCamera or workspace
	return targetIndicator
end

local function clearGuidedTarget(reason)
	guidedTarget = nil
	if targetIndicator and targetIndicator.Parent then
		targetIndicator.Adornee = nil
		targetIndicator.Enabled = false
	end
	player:SetAttribute("DungeonMobileAutoEngageTarget", nil)
	player:SetAttribute("DungeonMobileAutoEngageDistance", nil)
	player:SetAttribute("DungeonMobileAutoEngageState", reason or "Idle")
end

local function findNearestTarget()
	local character = player.Character
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not characterRoot or not characterRoot:IsA("BasePart") then
		return nil
	end

	local nearest
	local nearestDistance = math.huge
	local seen = {}
	for _, taggedInstance in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = taggedInstance:IsA("Model") and taggedInstance
			or taggedInstance:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			if validAutoEngageTarget(model, character, characterRoot) then
				local root = targetRoot(model)
				local offset = root.Position - characterRoot.Position
				local distance = Vector2.new(offset.X, offset.Z).Magnitude
				if distance < nearestDistance then
					nearest = model
					nearestDistance = distance
				end
			end
		end
	end

	return nearest, nearestDistance
end

local function guideToNearestTarget()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		clearGuidedTarget("CharacterUnavailable")
		return false
	end

	local target, distance = findNearestTarget()
	if not target then
		clearGuidedTarget("NoNearbyTarget")
		return false
	end

	guidedTarget = target
	local targetPart = targetRoot(target)
	if not targetPart then
		clearGuidedTarget("TargetLost")
		return false
	end
	local indicator = ensureTargetIndicator()
	indicator.Adornee = target
	indicator.Enabled = true
	player:SetAttribute("DungeonMobileAutoEngageTarget", target.Name)
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)

	local targetPosition = Vector3.new(targetPart.Position.X, root.Position.Y, targetPart.Position.Z)
	if distance > AUTO_ENGAGE_ATTACK_DISTANCE then
		player:SetAttribute("DungeonMobileAutoEngageState", "Approaching")
		if os.clock() - lastMoveAt >= AUTO_ENGAGE_MOVE_REFRESH_INTERVAL then
			lastMoveAt = os.clock()
			humanoid:MoveTo(targetPosition)
		end
		return false
	end

	player:SetAttribute("DungeonMobileAutoEngageState", "Attacking")
	humanoid:Move(Vector3.zero)
	local direction = targetPosition - root.Position
	if direction.Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, targetPosition)
	end
	return true
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
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
	clearGuidedTarget(reason or "Stopped")
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

			if not guideToNearestTarget() then
				if player:GetAttribute("DungeonMobileAutoEngageState") ~= "Approaching" then
					stopHold(player:GetAttribute("DungeonMobileAutoEngageState") or "TargetUnavailable")
					break
				end
				task.wait(HOLD_RETRY_INTERVAL)
				continue
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
		if isMobileDungeon() then
			return Enum.ContextActionResult.Sink
		end
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

	-- No celular, um toque liga/desliga o auto-engage do alvo mais proximo.
	-- KeyboardMouse/Gamepad preservam um ataque por Begin.
	if isMobileDungeon() then
		if not canAttack(equippedSword or findEquippedSword()) then
			stopHold("NoSword")
			return Enum.ContextActionResult.Pass
		end
		if attackHeld then
			stopHold("PlayerCancelled")
		else
			beginHold()
		end
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
player:SetAttribute("DungeonMobileHoldAttackPolicy", "TapToGuideNearestTargetV2")
player:SetAttribute("DungeonMobileAttackHeld", false)
player:SetAttribute("DungeonMobileAttackHoldRetryInterval", HOLD_RETRY_INTERVAL)
player:SetAttribute("DungeonMobileAutoEngageRadius", AUTO_ENGAGE_RADIUS)
player:SetAttribute("DungeonMobileAutoEngageAttackDistance", AUTO_ENGAGE_ATTACK_DISTANCE)
