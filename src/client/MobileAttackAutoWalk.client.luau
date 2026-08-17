-- Ataque mobile linear: SEGURAR o botao persegue e ataca o mob mais proximo.
-- Soltar interrompe imediatamente o auto-walk. Enquanto o hold esta ativo, o
-- alvo atual recebe um contorno branco local. A ilha inicial usa a mesma regra,
-- inclusive quando seus slimes ainda estao passivos antes do primeiro golpe.

local CollectionService = game:GetService("CollectionService")
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

local VERSION = "MobileAttackHoldLinearV6_InitialIslandChase"
local AUTO_RADIUS = 90
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

local held = false
local heldInput
local heldButton
local currentTarget
local lastTargetSearch = 0
local lastMoveTo = 0
local lastAttackAt = 0
local simulationConnection
local boundButtons = setmetatable({}, { __mode = "k" })

local outline = Instance.new("Highlight")
outline.Name = "DungeonMobileAttackTargetOutline"
outline.Enabled = false
outline.FillTransparency = 1
outline.OutlineColor = Color3.new(1, 1, 1)
outline.OutlineTransparency = 0
outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
outline.Parent = Workspace

local holdSignal = playerGui:FindFirstChild("DungeonMobileAttackHoldSignal")
if holdSignal and not holdSignal:IsA("BindableEvent") then
	holdSignal = nil
end
if not holdSignal then
	holdSignal = Instance.new("BindableEvent")
	holdSignal.Name = "DungeonMobileAttackHoldSignal"
	holdSignal.Parent = playerGui
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
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return character, humanoid, root
end

local function equippedSword()
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

local function rootOf(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
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
	local globalIndex = tonumber(model:GetAttribute("GlobalIslandIndex"))
	return globalIndex ~= nil and math.floor(globalIndex) == 1
end

local function targetIslandIndex(model)
	-- GlobalIslandIndex representa a rota linear. CombatIslandIndex/indices
	-- numerados legados podem ser 0 especificamente na ilha inicial.
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
	if not model or not model:IsA("Model") or not model.Parent or model == character then
		return false
	end

	local initialMob = isInitialMob(model)
	if model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("NoSwordDamage") == true
		or model:GetAttribute("ObjectiveTargetCompleted") == true
	then
		return false
	end
	-- A inicial pode atravessar um breve estado de simulacao/passividade durante
	-- o onboarding; isso nao deve impedir o jogador de seleciona-la/persegui-la.
	if model:GetAttribute("SimulationActive") == false and not initialMob then
		return false
	end
	if model:GetAttribute("Peaceful") == true and not initialMob then
		return false
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local targetPart = rootOf(model)
	if not humanoid or humanoid.Health <= 0 or not targetPart then
		return false
	end

	local targetIndex = targetIslandIndex(model)
	local playerIndex = currentIslandIndex()
	if targetIndex and targetIndex > 0 and targetIndex ~= playerIndex then
		return false
	end

	local offset = targetPart.Position - characterRoot.Position
	local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
	return math.abs(offset.Y) <= MAX_VERTICAL and horizontal <= AUTO_RADIUS
end

local function considerCandidate(model, character, characterRoot, seen, best)
	if not model or seen[model] then
		return best
	end
	seen[model] = true
	if not validTarget(model, character, characterRoot) then
		return best
	end
	local part = rootOf(model)
	local offset = part.Position - characterRoot.Position
	local distance = Vector2.new(offset.X, offset.Z).Magnitude
	if not best or distance < best.Distance then
		return { Model = model, Distance = distance }
	end
	return best
end

local function nearestTarget(character, characterRoot)
	local seen = {}
	local best

	-- Caminho normal de todas as arenas.
	for _, tagged in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = tagged:IsA("Model") and tagged
			or tagged:FindFirstAncestorOfClass("Model")
		best = considerCandidate(model, character, characterRoot, seen, best)
	end

	-- Fallback explicito da ilha inicial. O adaptador de onboarding pode mudar
	-- atributos/tags alguns frames depois do spawn; o hold nao deve depender
	-- dessa corrida para encontrar os slimes que ja estao visiveis ao jogador.
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
				best = considerCandidate(descendant, character, characterRoot, seen, best)
			end
		end
	end

	return best and best.Model or nil, best and best.Distance or nil
end

local function setOutlinedTarget(model)
	if model and model.Parent then
		outline.Adornee = model
		outline.Enabled = true
	else
		outline.Enabled = false
		outline.Adornee = nil
	end
	player:SetAttribute("DungeonMobileAttackTargetOutlined", model ~= nil)
end

local function setTarget(model, distance, state)
	if currentTarget ~= model then
		currentTarget = model
		setOutlinedTarget(model)
	end
	player:SetAttribute("DungeonMobileAutoEngageTarget", model and model.Name or nil)
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)
	player:SetAttribute("DungeonMobileAutoEngageState", state)
end

local function clearMovement()
	local _, humanoid, root = characterParts()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
		if root then
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

local function stop(reason)
	held = false
	heldInput = nil
	heldButton = nil
	disconnectSimulation()
	clearMovement()
	setTarget(nil, nil, reason or "Released")
	player:SetAttribute("DungeonMobileAttackHeld", false)
end

local function stepAutoWalk()
	if not held then
		return
	end
	if not isMobile()
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonAssistedTransportActive") == true
	then
		stop("Unavailable")
		return
	end

	local character, humanoid, root = characterParts()
	if not character or not humanoid or not root
		or character:GetAttribute("MovementLocked") == true
	then
		stop("CharacterUnavailable")
		return
	end

	local sword = equippedSword()
	if not sword then
		stop("NoSword")
		return
	end

	if not currentTarget or not validTarget(currentTarget, character, root) then
		if os.clock() - lastTargetSearch >= RETARGET_INTERVAL then
			lastTargetSearch = os.clock()
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
			-- PreSimulation roda imediatamente antes da fisica e vence o vetor
			-- neutro que o PlayerModule publica quando o polegar esta no ataque.
			humanoid:Move(flatOffset.Unit, false)
			if os.clock() - lastMoveTo >= MOVE_TO_REFRESH then
				lastMoveTo = os.clock()
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
	humanoid:Move(Vector3.zero, false)
	local flatTarget = Vector3.new(
		targetPart.Position.X,
		root.Position.Y,
		targetPart.Position.Z
	)
	if (flatTarget - root.Position).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end
	if os.clock() - lastAttackAt >= ATTACK_RETRY then
		lastAttackAt = os.clock()
		sword:Activate()
	end
end

local function begin(input, button)
	if held or not isMobile() then
		return
	end
	if player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonAssistedTransportActive") == true
		or (player.Character and player.Character:GetAttribute("MovementLocked") == true)
	then
		return
	end
	if not equippedSword() then
		player:SetAttribute("DungeonMobileAutoEngageState", "NoSword")
		return
	end

	held = true
	heldInput = input
	heldButton = button
	lastTargetSearch = 0
	lastMoveTo = 0
	lastAttackAt = 0
	player:SetAttribute("DungeonMobileAttackHeld", true)
	player:SetAttribute("DungeonMobileAttackHoldStartedAt", Workspace:GetServerTimeNow())
	setTarget(nil, nil, "Searching")

	disconnectSimulation()
	simulationConnection = RunService.PreSimulation:Connect(stepAutoWalk)
	-- Seleciona/destaca imediatamente, antes mesmo do primeiro frame de fisica.
	stepAutoWalk()
end

local function isAttackButton(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end
	if button:GetAttribute("DungeonAuthoredAttackButtonBound") == true then
		return true
	end
	local current = button
	for _ = 1, 3 do
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
	if not isAttackButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	button:SetAttribute("DungeonMobileAutoWalkBound", true)
	button:SetAttribute("DungeonMobileAttackHoldBound", true)

	-- Fallback local. A fonte preferida e o BindableEvent publicado por
	-- MobileControls, porque ele ja conhece exatamente o botao usado no Studio.
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			begin(input, button)
		end
	end)
	button.InputEnded:Connect(function(input)
		if held and (heldInput == input or heldButton == button) then
			stop("ButtonReleased")
		end
	end)
end

local function scanButtons()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		bindButton(descendant)
	end
end

local function inputTouchesAttackButton(input)
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
			if current:IsA("GuiButton") and isAttackButton(current) and current.Visible then
				bindButton(current)
				return current
			end
			current = current.Parent
		end
	end
	return nil
end

holdSignal.Event:Connect(function(phase, button, input)
	if phase == "Begin" then
		begin(input, button)
	elseif phase == "End" and held and (not heldButton or heldButton == button) then
		stop("ButtonReleased")
	end
end)

-- Ultima redundancia para emulador/overlays que bloqueiem o evento do GuiButton.
UserInputService.InputBegan:Connect(function(input)
	if held or not isMobile() then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseButton1
	then
		return
	end
	local button = inputTouchesAttackButton(input)
	if button then
		begin(input, button)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if held and heldInput == input then
		stop("ButtonReleased")
	end
end)

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindButton, instance)
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if not isMobile() then
		stop("MobileModeEnded")
	end
	task.defer(scanButtons)
end)
player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true then
		stop("Downed")
	end
end)
player:GetAttributeChangedSignal("DungeonAssistedTransportActive"):Connect(function()
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		stop("Transport")
	end
end)
player.CharacterAdded:Connect(function(character)
	stop("CharacterChanged")
	character:GetAttributeChangedSignal("MovementLocked"):Connect(function()
		if character:GetAttribute("MovementLocked") == true then
			stop("MovementLocked")
		end
	end)
end)

task.defer(scanButtons)
player:SetAttribute("DungeonMobileAutoWalkReady", true)
player:SetAttribute("DungeonMobileHoldAttackReady", true)
player:SetAttribute("DungeonMobileAutoWalkVersion", VERSION)
player:SetAttribute("DungeonMobileHoldAttackPolicy", "HoldChasesNearestMobIncludingInitialIslandV6")

script.Destroying:Connect(function()
	stop("Destroyed")
	outline:Destroy()
end)
