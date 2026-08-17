-- MobileControls: unica autoridade do ataque mobile.
--
-- Comportamento do MVP:
--   segurar ATACAR -> trava no mob valido mais proximo -> contorno branco
--   -> caminha continuamente ate ele -> ataca enquanto estiver no alcance.
--   soltar -> cancela imediatamente a perseguicao.
--
-- O alvo fica travado enquanto continuar valido. Nao trocamos para outro mob
-- mais proximo no meio do hold, evitando zigue-zague e sensacao de controle ruim.
-- O layout dos botoes continua 100% autorado no Roblox Studio.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
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

local VERSION = "SmoothHoldAttackV2"
local ACTION_NAME = "SkyDungeonAttack"
local TARGET_RADIUS = 90
local MAX_VERTICAL = 18
local ATTACK_DISTANCE = 5.6
local RETARGET_INTERVAL = 0.06
local MOVE_TO_REFRESH = 0.10
local ATTACK_RETRY = math.clamp(
	(tonumber(CombatConfig.InputBufferTime) or 0.16) * 0.5,
	0.045,
	0.08
)

local BUTTON_NAMES = {
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
local lastMoveTo = 0
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
	-- Slimes neutros da ilha inicial continuam sendo atacaveis e perseguiveis.
	if model:GetAttribute("Peaceful") == true and not initialMob then
		return false
	end

	local humanoid = humanoidOf(model)
	local targetPart = rootOf(model)
	if not humanoid or humanoid.Health <= 0 or not targetPart then
		return false
	end

	local index = targetIslandIndex(model)
	if index and index > 0 and index ~= currentIslandIndex() then
		return false
	end

	local offset = targetPart.Position - characterRoot.Position
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

	-- A primeira ilha pode receber suas tags alguns frames depois do spawn.
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

local function clearMovement()
	local _, humanoid, root = characterParts()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
		if root then
			-- Cancela somente o ultimo MoveTo ao SOLTAR o botao.
			humanoid:MoveTo(root.Position)
		end
	end
end

local function disconnectSimulation()
	if simulationConnection then
		simulationConnection:Disconnect()
		simulationConnection = nil
	end
end

local function stopHold(reason)
	held = false
	heldInput = nil
	heldButton = nil
	disconnectSimulation()
	clearMovement()
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

	local character, humanoid, root = characterParts()
	local sword = usableSword()
	if not character or not humanoid or not root or not sword then
		stopHold("CharacterUnavailable")
		return
	end

	local now = os.clock()

	-- Mantem o alvo atual enquanto ele estiver vivo/valido. So procura outro
	-- quando ele morreu, saiu da arena ou ficou invalido.
	if not currentTarget or not validTarget(currentTarget, character, root) then
		if now - lastTargetSearch >= RETARGET_INTERVAL then
			lastTargetSearch = now
			local target, distance = nearestTarget(character, root)
			setTarget(target, distance, target and "TargetLocked" or "Searching")
		end
	end

	if not currentTarget then
		humanoid:Move(Vector3.zero, false)
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
			-- PreSimulation vence o vetor neutro do PlayerModule quando o polegar
			-- esta segurando o botao de ataque.
			humanoid:Move(flatOffset.Unit, false)
			if now - lastMoveTo >= MOVE_TO_REFRESH then
				lastMoveTo = now
				humanoid:MoveTo(Vector3.new(
					targetPart.Position.X,
					root.Position.Y,
					targetPart.Position.Z
				))
			end
		end
		return
	end

	player:SetAttribute("DungeonMobileAutoEngageState", "Attacking")
	-- Nao usamos MoveTo(root.Position) aqui: isso era o que deixava o hold
	-- travado/seco ao cruzar o limite de alcance. Apenas zeramos o vetor manual.
	humanoid:Move(Vector3.zero, false)

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
	lastMoveTo = 0
	lastAttackAt = -math.huge
	setTarget(nil, nil, "Searching")
	player:SetAttribute("DungeonMobileAttackHoldStartedAt", Workspace:GetServerTimeNow())

	disconnectSimulation()
	simulationConnection = RunService.PreSimulation:Connect(stepHold)
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
		if BUTTON_NAMES[string.lower(current.Name)] then
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

	-- Fallback importante para o emulador mobile do Studio.
	button.MouseButton1Down:Connect(function()
		beginHold(button, nil)
	end)
	button.MouseButton1Up:Connect(function()
		if held and heldButton == button then
			stopHold("ButtonReleased")
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

local function inputAttackButton(input)
	local position = input.Position
	local ok, objects = pcall(
		GuiService.GetGuiObjectsAtPosition,
		GuiService,
		math.floor(position.X),
		math.floor(position.Y)
	)
	if not ok then
		return nil
	end
	for _, object in ipairs(objects) do
		local current = object
		for _ = 1, 5 do
			if not current then
				break
			end
			if current:IsA("GuiButton") and current.Visible and isAttackButton(current) then
				bindButton(current)
				return current
			end
			current = current.Parent
		end
	end
	return nil
end

-- Redundancia de input proposital: alguns overlays/emuladores nao entregam
-- InputBegan/InputEnded de forma consistente ao GuiButton.
UserInputService.InputBegan:Connect(function(input)
	if held or not isMobile() then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseButton1
	then
		return
	end
	local button = inputAttackButton(input)
	if button then
		beginHold(button, input)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if held and heldInput == input then
		stopHold("ButtonReleased")
	end
end)

local function manualAttackAction(_, inputState)
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
	manualAttackAction,
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
player:SetAttribute("DungeonMobileHoldAttackPolicy", "HoldLocksNearestAndChasesUntilReleaseV2")

script.Destroying:Connect(function()
	stopHold("Destroyed")
	if targetValue and targetValue.Parent then
		targetValue:Destroy()
	end
	if outline and outline.Parent then
		outline:Destroy()
	end
end)
