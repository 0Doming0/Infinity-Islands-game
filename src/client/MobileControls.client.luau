-- MobileControls: unica autoridade do ataque mobile.
--
-- Regra simples:
--   segurar ATACAR -> seleciona o mob valido mais proximo -> contorno branco
--   -> auto-walk ate o alcance -> ataca continuamente.
--   soltar ATACAR -> para imediatamente e devolve o movimento ao jogador.
--
-- O layout continua 100% autorado no Roblox Studio. Este script nunca altera
-- Position, Size ou AnchorPoint dos botoes.

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

local VERSION = "LinearMobileCombatV1"
local ACTION_NAME = "SkyDungeonAttack"
local TARGET_RADIUS = 100
local MAX_VERTICAL = 20
local ATTACK_DISTANCE = 5.8
local RETARGET_INTERVAL = 0.10
local MOVE_REFRESH = 0.10
local ATTACK_INTERVAL = math.max(0.09, (tonumber(CombatConfig.InputBufferTime) or 0.16) * 0.7)

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
local lastRetargetAt = 0
local lastMoveAt = 0
local lastAttackAt = 0
local simulationConnection
local boundButtons = setmetatable({}, { __mode = "k" })

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
	local index = tonumber(model:GetAttribute("GlobalIslandIndex"))
	return index ~= nil and math.floor(index) == 1
end

local function targetIslandIndex(model)
	local value = tonumber(model:GetAttribute("GlobalIslandIndex"))
		or tonumber(model:GetAttribute("ProgressionIslandIndex"))
		or tonumber(model:GetAttribute("CombatIslandIndex"))
	if not value then
		return isInitialMob(model) and 1 or nil
	end
	if value <= 0 and isInitialMob(model) then
		return 1
	end
	return math.floor(value)
end

local function validTarget(model, character, root)
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
	-- A primeira arena pode manter slimes neutros antes do primeiro golpe.
	-- Eles continuam sendo alvos validos para o jogador.
	if model:GetAttribute("Peaceful") == true and not initialMob then
		return false
	end

	local humanoid = humanoidOf(model)
	local targetRoot = rootOf(model)
	if not humanoid or humanoid.Health <= 0 or not targetRoot then
		return false
	end

	local targetIndex = targetIslandIndex(model)
	if targetIndex and targetIndex > 0 and targetIndex ~= currentIslandIndex() then
		return false
	end

	local offset = targetRoot.Position - root.Position
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
	local targetRoot = rootOf(model)
	local offset = targetRoot.Position - root.Position
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

	-- Fallback da primeira arena: nao depender de uma corrida entre spawn, tag e
	-- adaptacao de passividade para conseguir perseguir um slime que ja esta visivel.
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
	currentTarget = model
	targetValue.Value = model
	outline.Adornee = model
	outline.Enabled = model ~= nil

	player:SetAttribute("DungeonMobileAttackHeld", held)
	player:SetAttribute("DungeonMobileAutoEngageTarget", model and model.Name or nil)
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)
	player:SetAttribute("DungeonMobileAutoEngageState", state)
	player:SetAttribute("DungeonMobileAttackTargetOutlined", model ~= nil)
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

local function stopMovement()
	local _, humanoid, root = characterParts()
	if humanoid and root then
		humanoid:Move(Vector3.zero, false)
		humanoid:MoveTo(root.Position)
	end
end

local function stopHold(reason)
	held = false
	heldInput = nil
	heldButton = nil
	if simulationConnection then
		simulationConnection:Disconnect()
		simulationConnection = nil
	end
	stopMovement()
	setTarget(nil, nil, reason or "Idle")
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

	local character, humanoid, root = characterParts()
	local sword = usableSword()
	if not character or not humanoid or not root or not sword then
		stopHold("CharacterUnavailable")
		return
	end

	local now = os.clock()
	if now - lastRetargetAt >= RETARGET_INTERVAL then
		lastRetargetAt = now
		local nearest, distance = nearestTarget(character, root)
		if nearest ~= currentTarget then
			setTarget(nearest, distance, nearest and "TargetLocked" or "Searching")
		elseif nearest then
			player:SetAttribute("DungeonMobileAutoEngageDistance", distance)
		end
	end

	if not currentTarget or not validTarget(currentTarget, character, root) then
		setTarget(nil, nil, "Searching")
		return
	end

	local targetRoot = rootOf(currentTarget)
	if not targetRoot then
		setTarget(nil, nil, "Searching")
		return
	end

	local offset = targetRoot.Position - root.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = flatOffset.Magnitude
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)

	if distance > ATTACK_DISTANCE then
		player:SetAttribute("DungeonMobileAutoEngageState", "Approaching")
		if distance > 0.05 then
			humanoid:Move(flatOffset.Unit, false)
			if now - lastMoveAt >= MOVE_REFRESH then
				lastMoveAt = now
				humanoid:MoveTo(Vector3.new(
					targetRoot.Position.X,
					root.Position.Y,
					targetRoot.Position.Z
				))
			end
		end
		return
	end

	player:SetAttribute("DungeonMobileAutoEngageState", "Attacking")
	humanoid:Move(Vector3.zero, false)
	humanoid:MoveTo(root.Position)
	local flatTarget = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
	if (flatTarget - root.Position).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end

	if now - lastAttackAt >= ATTACK_INTERVAL then
		lastAttackAt = now
		sword:Activate()
		player:SetAttribute("DungeonLastAuthoredAttackInputAt", Workspace:GetServerTimeNow())
	end
end

local function beginHold(button, input)
	if held or not isMobile() or not usableSword() then
		return
	end
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		return
	end

	held = true
	heldButton = button
	heldInput = input
	lastRetargetAt = 0
	lastMoveAt = 0
	lastAttackAt = -math.huge
	setTarget(nil, nil, "Searching")
	player:SetAttribute("DungeonMobileAttackHoldStartedAt", Workspace:GetServerTimeNow())

	if simulationConnection then
		simulationConnection:Disconnect()
	end
	simulationConnection = RunService.PreSimulation:Connect(stepHold)
	stepHold()
end

local function isAttackButton(instance)
	if not instance or not instance:IsA("GuiButton") then
		return false
	end
	local current = instance
	for _ = 1, 4 do
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

local function refreshButton(button)
	if not button or not button.Parent then
		return
	end
	button.Visible = isMobile()
		and equippedSword ~= nil
		and player:GetAttribute("IsDowned") ~= true
		and not (
			player.Character
			and player.Character:GetAttribute("MovementLocked") == true
		)
end

local function bindButton(button)
	if not isAttackButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	button:SetAttribute("DungeonAuthoredAttackButtonBound", true)
	button:SetAttribute("DungeonMobileAttackHoldBound", true)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			beginHold(button, input)
		end
	end)

	button.InputEnded:Connect(function(input)
		if held and heldButton == button and (heldInput == nil or heldInput == input) then
			stopHold("Released")
		end
	end)

	-- Studio device emulator sometimes exposes mouse-style button events instead
	-- of a stable Touch InputObject. These are a small fallback, not another system.
	button.MouseButton1Down:Connect(function()
		beginHold(button, nil)
	end)
	button.MouseButton1Up:Connect(function()
		if held and heldButton == button then
			stopHold("Released")
		end
	end)

	refreshButton(button)
end

local function refreshButtons()
	equippedSword = findEquippedSword()
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
		bindButton(descendant)
	end
	refreshButtons()
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
			refreshButtons()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedSword then
			equippedSword = nil
			stopHold("SwordUnequipped")
			task.defer(refreshButtons)
		end
	end)
	character:GetAttributeChangedSignal("MovementLocked"):Connect(function()
		if character:GetAttribute("MovementLocked") == true then
			stopHold("MovementLocked")
		end
		refreshButtons()
	end)
	task.defer(refreshButtons)
end

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindButton, instance)
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if not isMobile() then
		stopHold("MobileModeEnded")
	end
	task.defer(scanButtons)
end)
player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true then
		stopHold("Downed")
	end
	refreshButtons()
end)
player:GetAttributeChangedSignal("DungeonAssistedTransportActive"):Connect(function()
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		stopHold("Transport")
	end
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

task.defer(scanButtons)

player:SetAttribute("DungeonMobileAttackLayoutOwnedByStudio", true)
player:SetAttribute("DungeonMobileAttackControllerVersion", VERSION)
player:SetAttribute("DungeonMobileAutoWalkReady", true)
player:SetAttribute("DungeonMobileHoldAttackReady", true)
player:SetAttribute("DungeonMobileHoldAttackPolicy", "HoldNearestTargetApproachAttack")

script.Destroying:Connect(function()
	stopHold("Destroyed")
	if targetValue and targetValue.Parent then
		targetValue:Destroy()
	end
	if outline and outline.Parent then
		outline:Destroy()
	end
end)
