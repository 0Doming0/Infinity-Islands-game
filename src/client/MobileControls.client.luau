-- MobileControls: unica autoridade dos controles mobile essenciais.
--
-- ATAQUE:
--   segurar ATACAR -> trava no mob valido mais proximo -> contorno branco
--   -> Player:Move() dirige continuamente ate o alvo -> ataca no alcance.
--   soltar -> cancela imediatamente e devolve o movimento ao jogador.
--
-- PULO:
--   JumpButton autorado no HUD substitui o JumpButton padrao do TouchGui.
--   Este script nunca posiciona ou redimensiona controles autorados no Studio.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(
	ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig")
)

local VERSION = "DirectPlayerMoveCombatV3"
local ACTION_NAME = "SkyDungeonAttack"
local DRIVE_BIND = "DungeonMobileAttackDrive_" .. tostring(player.UserId)
local TARGET_RADIUS = 100
local MAX_VERTICAL = 20
local ATTACK_DISTANCE = 5.7
local RETARGET_INTERVAL = 0.06
local ATTACK_RETRY = math.clamp(
	(tonumber(CombatConfig.InputBufferTime) or 0.16) * 0.5,
	0.045,
	0.08
)

local ATTACK_BUTTON_NAMES = {
	swordattackbutton = true,
	attackbutton = true,
	mobileattackbutton = true,
	attackimagebutton = true,
	attack = true,
}

local equippedSword
local held = false
local heldInput
local heldButton
local currentTarget
local lastTargetSearch = 0
local lastAttackAt = 0
local driveBound = false

local boundAttackButtons = setmetatable({}, { __mode = "k" })
local boundJumpButtons = setmetatable({}, { __mode = "k" })
local hiddenDefaultJumpButtons = setmetatable({}, { __mode = "k" })

local targetValue = playerGui:FindFirstChild("DungeonMobileCombatTarget")
if targetValue and not targetValue:IsA("ObjectValue") then
	targetValue:Destroy()
	targetValue = nil
end
if not targetValue then
	targetValue = Instance.new("ObjectValue")
	targetValue.Name = "DungeonMobileCombatTarget"
	targetValue.Parent = playerGui
end

local outline = Workspace:FindFirstChild("DungeonMobileAttackTargetOutline")
if outline and not outline:IsA("Highlight") then
	outline:Destroy()
	outline = nil
end
if not outline then
	outline = Instance.new("Highlight")
	outline.Name = "DungeonMobileAttackTargetOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Enabled = false
	outline.Parent = Workspace
end

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
end

local function currentIslandIndex()
	local value = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	if not value or value <= 0 then
		return 1
	end
	return math.max(1, math.floor(value))
end

local function characterParts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil
	end
	return character, humanoid, root
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

local function usableSword()
	local character = player.Character
	local sword = equippedSword or findEquippedSword()
	if not character
		or not sword
		or sword.Parent ~= character
		or not CombatConfig.IsSword(sword)
		or player:GetAttribute("IsDowned") == true
		or character:GetAttribute("MovementLocked") == true
	then
		return nil
	end
	equippedSword = sword
	return sword
end

local function rootOf(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function humanoidOf(model)
	return model and model:FindFirstChildWhichIsA("Humanoid", true) or nil
end

local function isInitialMob(model)
	if not model then
		return false
	end
	if model:GetAttribute("IsInitialIslandMob") == true
		or model:GetAttribute("PassiveUntilAttacked") == true
		or model:GetAttribute("TutorialPassive") == true
	then
		return true
	end
	local value = tonumber(model:GetAttribute("GlobalIslandIndex"))
	return value ~= nil and math.floor(value) == 1
end

local function targetIslandIndex(model)
	local value = tonumber(model:GetAttribute("GlobalIslandIndex"))
		or tonumber(model:GetAttribute("CombatIslandIndex"))
		or tonumber(model:GetAttribute("ProgressionIslandIndex"))
	if not value then
		return isInitialMob(model) and 1 or nil
	end
	if value <= 0 and isInitialMob(model) then
		return 1
	end
	return math.floor(value)
end

local function validTarget(model, character, characterRoot)
	if not model
		or not model:IsA("Model")
		or not model.Parent
		or model == character
	then
		return false
	end

	local initialMob = isInitialMob(model)
	if model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("NoSwordDamage") == true
		or model:GetAttribute("ObjectiveTargetCompleted") == true
	then
		return false
	end
	if model:GetAttribute("SimulationActive") == false and not initialMob then
		return false
	end
	-- A ilha inicial pode manter mobs neutros ate o primeiro golpe.
	if model:GetAttribute("Peaceful") == true and not initialMob then
		return false
	end

	local humanoid = humanoidOf(model)
	local targetRoot = rootOf(model)
	if not humanoid or humanoid.Health <= 0 or not targetRoot then
		return false
	end

	local index = targetIslandIndex(model)
	if index and index > 0 and index ~= currentIslandIndex() then
		return false
	end

	local offset = targetRoot.Position - characterRoot.Position
	local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
	return horizontal <= TARGET_RADIUS and math.abs(offset.Y) <= MAX_VERTICAL
end

local function consider(model, character, root, seen, best)
	if not model or seen[model] then
		return best
	end
	seen[model] = true
	if not validTarget(model, character, root) then
		return best
	end
	local part = rootOf(model)
	local offset = part.Position - root.Position
	local distance = Vector2.new(offset.X, offset.Z).Magnitude
	if not best or distance < best.Distance then
		return { Model = model, Distance = distance }
	end
	return best
end

local function nearestTarget(character, root)
	local seen = {}
	local best

	for _, tagged in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = tagged:IsA("Model") and tagged
			or tagged:FindFirstAncestorOfClass("Model")
		best = consider(model, character, root, seen, best)
	end

	-- Fallback da primeira ilha: funciona mesmo antes de todas as tags terminarem
	-- de ser publicadas pelo servidor.
	if currentIslandIndex() == 1 then
		for _, descendant in ipairs(Workspace:GetDescendants()) do
			if descendant:IsA("Model")
				and (
					descendant:GetAttribute("IsInitialIslandMob") == true
					or (
						descendant:GetAttribute("IslandCombatManaged") == true
						and targetIslandIndex(descendant) == 1
					)
				)
			then
				best = consider(descendant, character, root, seen, best)
			end
		end
	end

	return best and best.Model or nil, best and best.Distance or nil
end

local function setTarget(model, distance, state)
	if currentTarget ~= model then
		currentTarget = model
		outline.Adornee = model
		outline.Enabled = model ~= nil
		targetValue.Value = model
	end
	player:SetAttribute("DungeonMobileAttackHeld", held)
	player:SetAttribute("DungeonMobileAutoEngageTarget", model and model.Name or nil)
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)
	player:SetAttribute("DungeonMobileAutoEngageState", state)
	player:SetAttribute("DungeonMobileAttackTargetOutlined", model ~= nil)
end

local function releaseMovement()
	player:Move(Vector3.zero, false)
end

local function unbindDrive()
	if driveBound then
		RunService:UnbindFromRenderStep(DRIVE_BIND)
		driveBound = false
	end
end

local function stopHold(reason)
	held = false
	heldInput = nil
	heldButton = nil
	unbindDrive()
	releaseMovement()
	setTarget(nil, nil, reason or "Released")
end

local function stepHold()
	if not held then
		return
	end
	if not isMobile()
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonAssistedTransportActive") == true
	then
		stopHold("Unavailable")
		return
	end

	local character, _, root = characterParts()
	local sword = usableSword()
	if not character or not root or not sword then
		stopHold("CharacterUnavailable")
		return
	end

	local now = os.clock()
	if not currentTarget or not validTarget(currentTarget, character, root) then
		if now - lastTargetSearch >= RETARGET_INTERVAL then
			lastTargetSearch = now
			local target, distance = nearestTarget(character, root)
			setTarget(target, distance, target and "TargetLocked" or "Searching")
		end
	end

	if not currentTarget then
		releaseMovement()
		return
	end

	local targetPart = rootOf(currentTarget)
	if not targetPart then
		setTarget(nil, nil, "Retargeting")
		return
	end

	local offset = targetPart.Position - root.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = flatOffset.Magnitude
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)

	if distance > ATTACK_DISTANCE then
		player:SetAttribute("DungeonMobileAutoEngageState", "Approaching")
		if distance > 0.05 then
			-- Player:Move roda depois do controlador padrao de input. Assim o toque
			-- segurando ATACAR nao neutraliza a direcao de perseguicao.
			player:Move(flatOffset.Unit, false)
		end
		return
	end

	releaseMovement()
	player:SetAttribute("DungeonMobileAutoEngageState", "Attacking")

	local flatTarget = Vector3.new(
		targetPart.Position.X,
		root.Position.Y,
		targetPart.Position.Z
	)
	if (flatTarget - root.Position).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end

	if now - lastAttackAt >= ATTACK_RETRY then
		lastAttackAt = now
		sword:Activate()
		player:SetAttribute("DungeonLastAuthoredAttackInputAt", Workspace:GetServerTimeNow())
	end
end

local function beginHold(button, input)
	if held or not isMobile() then
		return
	end
	if player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonAssistedTransportActive") == true
		or (player.Character and player.Character:GetAttribute("MovementLocked") == true)
	then
		return
	end
	if not usableSword() then
		player:SetAttribute("DungeonMobileAutoEngageState", "NoSword")
		return
	end

	held = true
	heldButton = button
	heldInput = input
	lastTargetSearch = 0
	lastAttackAt = -math.huge
	setTarget(nil, nil, "Searching")
	player:SetAttribute("DungeonMobileAttackHoldStartedAt", Workspace:GetServerTimeNow())

	unbindDrive()
	RunService:BindToRenderStep(
		DRIVE_BIND,
		Enum.RenderPriority.Input.Value + 1,
		stepHold
	)
	driveBound = true
	stepHold()
end

local function isAttackButton(instance)
	if not instance or not instance:IsA("GuiButton") then
		return false
	end
	local current = instance
	for _ = 1, 5 do
		if not current then
			break
		end
		if ATTACK_BUTTON_NAMES[string.lower(current.Name)] then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isInsideTouchGui(instance)
	local current = instance
	while current and current ~= playerGui do
		if current.Name == "TouchGui" then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isCustomJumpButton(instance)
	return instance
		and instance:IsA("GuiButton")
		and string.lower(instance.Name) == "jumpbutton"
		and not isInsideTouchGui(instance)
end

local function hideDefaultJumpButton(instance)
	if not instance
		or not instance:IsA("GuiButton")
		or string.lower(instance.Name) ~= "jumpbutton"
		or not isInsideTouchGui(instance)
	then
		return false
	end

	instance.Visible = false
	instance.Active = false
	instance.AutoButtonColor = false
	if hiddenDefaultJumpButtons[instance] then
		return true
	end
	hiddenDefaultJumpButtons[instance] = true
	instance:GetPropertyChangedSignal("Visible"):Connect(function()
		if instance.Parent and instance.Visible then
			instance.Visible = false
		end
	end)
	return true
end

local function performJump()
	if not isMobile()
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonAssistedTransportActive") == true
	then
		return
	end

	local character, humanoid = characterParts()
	if not character or not humanoid or character:GetAttribute("MovementLocked") == true then
		return
	end

	-- Mesmo comportamento simples do pulo padrao: apenas solicita Jump ao
	-- Humanoid. A fisica/estado do Humanoid continua sendo autoridade.
	humanoid.Jump = true
	player:SetAttribute("DungeonCustomJumpAt", Workspace:GetServerTimeNow())
end

local function refreshAttackButton(button)
	if button and button.Parent then
		button.Visible = isMobile()
			and equippedSword ~= nil
			and player:GetAttribute("IsDowned") ~= true
			and not (
				player.Character
				and player.Character:GetAttribute("MovementLocked") == true
			)
	end
end

local function refreshJumpButton(button)
	if button and button.Parent then
		button.Visible = isMobile()
			and player:GetAttribute("IsDowned") ~= true
			and not (
				player.Character
				and player.Character:GetAttribute("MovementLocked") == true
			)
	end
end

local function bindAttackButton(button)
	if not isAttackButton(button) or boundAttackButtons[button] then
		return
	end
	boundAttackButtons[button] = true
	button:SetAttribute("DungeonAuthoredAttackButtonBound", true)
	button:SetAttribute("DungeonMobileAttackHoldBound", true)
	button:SetAttribute("DungeonMobileAutoWalkBound", true)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			beginHold(button, input)
		end
	end)
	button.InputEnded:Connect(function(input)
		if held and heldButton == button and (heldInput == nil or heldInput == input) then
			stopHold("ButtonReleased")
		end
	end)
	button.MouseButton1Down:Connect(function()
		beginHold(button, nil)
	end)
	button.MouseButton1Up:Connect(function()
		if held and heldButton == button then
			stopHold("ButtonReleased")
		end
	end)
	refreshAttackButton(button)
end

local function bindJumpButton(button)
	if not isCustomJumpButton(button) or boundJumpButtons[button] then
		return
	end
	boundJumpButtons[button] = true
	button:SetAttribute("DungeonAuthoredJumpButtonBound", true)
	button.Activated:Connect(performJump)
	refreshJumpButton(button)
end

local function refreshControls()
	equippedSword = findEquippedSword()
	local attackCount = 0
	local jumpCount = 0
	for button in pairs(boundAttackButtons) do
		if button.Parent then
			attackCount += 1
			refreshAttackButton(button)
		end
	end
	for button in pairs(boundJumpButtons) do
		if button.Parent then
			jumpCount += 1
			refreshJumpButton(button)
		end
	end
	player:SetAttribute("DungeonAuthoredAttackButtonCount", attackCount)
	player:SetAttribute("DungeonAuthoredJumpButtonCount", jumpCount)
end

local function inspectGuiInstance(instance)
	if hideDefaultJumpButton(instance) then
		return
	end
	bindAttackButton(instance)
	bindJumpButton(instance)
end

local function scanGui()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		inspectGuiInstance(descendant)
	end
	refreshControls()
end

local function attackAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local sword = usableSword()
	if sword then
		sword:Activate()
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

local function bindCharacter(character)
	stopHold("CharacterChanged")
	equippedSword = nil

	character.ChildAdded:Connect(function(child)
		if CombatConfig.IsSword(child) then
			equippedSword = child
			refreshControls()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedSword then
			equippedSword = nil
			stopHold("SwordUnequipped")
			task.defer(refreshControls)
		end
	end)
	character:GetAttributeChangedSignal("MovementLocked"):Connect(function()
		if character:GetAttribute("MovementLocked") == true then
			stopHold("MovementLocked")
		end
		refreshControls()
	end)
	task.defer(refreshControls)
end

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(inspectGuiInstance, instance)
end)
UserInputService.InputEnded:Connect(function(input)
	if held and heldInput == input then
		stopHold("InputReleased")
	end
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if not isMobile() then
		stopHold("MobileModeEnded")
	end
	task.defer(scanGui)
end)
player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true then
		stopHold("Downed")
	end
	refreshControls()
end)
player:GetAttributeChangedSignal("DungeonAssistedTransportActive"):Connect(function()
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		stopHold("Transport")
	end
	refreshControls()
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

task.defer(scanGui)

player:SetAttribute("DungeonMobileAttackLayoutOwnedByStudio", true)
player:SetAttribute("DungeonMobileAttackControllerVersion", VERSION)
player:SetAttribute("DungeonMobileAutoWalkReady", true)
player:SetAttribute("DungeonMobileHoldAttackReady", true)
player:SetAttribute("DungeonMobileHoldAttackPolicy", "PlayerMoveAfterInputNearestTarget")
player:SetAttribute("DungeonCustomJumpButtonEnabled", true)
player:SetAttribute("DungeonDefaultRobloxJumpButtonDisabled", true)

script.Destroying:Connect(function()
	stopHold("Destroyed")
	ContextActionService:UnbindAction(ACTION_NAME)
	if targetValue and targetValue.Parent then
		targetValue:Destroy()
	end
	if outline and outline.Parent then
		outline:Destroy()
	end
end)
