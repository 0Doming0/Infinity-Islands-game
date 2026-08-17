-- Assistencia de combate mobile por PRESS-AND-HOLD.
-- Enquanto o jogador segura o botao de ataque, o personagem procura o mob
-- valido mais proximo, anda ate ele e continua emitindo ataques quando entra
-- no alcance. Soltar o botao devolve o movimento imediatamente ao jogador.
--
-- O layout continua 100% no Roblox Studio: este script nunca altera
-- Position, Size ou AnchorPoint de nenhum botao.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(
	ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig")
)

local VERSION = "MobileAttackAutoWalkHoldV2"
local RENDER_BIND = "DungeonMobileAttackAutoWalk"
local AUTO_RADIUS = 48
local MAX_VERTICAL = 12
local ATTACK_DISTANCE = 5.6
local RETARGET_INTERVAL = 0.08
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
local currentTarget
local lastTargetSearch = 0
local lastAttackAt = 0
local boundButtons = setmetatable({}, { __mode = "k" })

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
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

local function initialPassiveCanBeAttacked(model)
	return model:GetAttribute("PassiveUntilAttacked") == true
		or model:GetAttribute("IsInitialIslandMob") == true
		or model:GetAttribute("TutorialPassive") == true
end

local function validTarget(model, character, characterRoot)
	if not model or not model:IsA("Model") or not model.Parent or model == character then
		return false
	end
	if model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("NoSwordDamage") == true
		or model:GetAttribute("ObjectiveTargetCompleted") == true
		or model:GetAttribute("SimulationActive") == false
	then
		return false
	end
	if model:GetAttribute("Peaceful") == true and not initialPassiveCanBeAttacked(model) then
		return false
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local targetPart = rootOf(model)
	if not humanoid or humanoid.Health <= 0 or not targetPart then
		return false
	end

	local targetIsland = tonumber(
		model:GetAttribute("CombatIslandIndex")
			or model:GetAttribute("GlobalIslandIndex")
	)
	local currentIsland = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	if targetIsland and currentIsland
		and math.floor(targetIsland) ~= math.floor(currentIsland)
	then
		return false
	end

	local offset = targetPart.Position - characterRoot.Position
	local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
	return math.abs(offset.Y) <= MAX_VERTICAL and horizontal <= AUTO_RADIUS
end

local function nearestTarget(character, characterRoot)
	local nearest
	local nearestDistance = math.huge
	local seen = {}
	for _, tagged in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = tagged:IsA("Model") and tagged
			or tagged:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			if validTarget(model, character, characterRoot) then
				local part = rootOf(model)
				local offset = part.Position - characterRoot.Position
				local distance = Vector2.new(offset.X, offset.Z).Magnitude
				if distance < nearestDistance then
					nearest = model
					nearestDistance = distance
				end
			end
	end
	return nearest, nearestDistance
end

local function clearMovement()
	local character, humanoid, root = characterParts()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
		if root then
			humanoid:MoveTo(root.Position)
		end
	end
end

local function setTargetAttributes(model, distance, state)
	player:SetAttribute(
		"DungeonMobileAutoEngageTarget",
		model and model.Name or nil
	)
	player:SetAttribute("DungeonMobileAutoEngageDistance", distance)
	player:SetAttribute("DungeonMobileAutoEngageState", state)
end

local function stop(reason)
	if held then
		held = false
		RunService:UnbindFromRenderStep(RENDER_BIND)
	end
	heldInput = nil
	currentTarget = nil
	clearMovement()
	player:SetAttribute("DungeonMobileAttackHeld", false)
	setTargetAttributes(nil, nil, reason or "Released")
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
			currentTarget = nearestTarget(character, root)
		end
	end

	if not currentTarget then
		-- Nao encerra o hold: se um mob estiver terminando de spawnar, o mesmo
		-- toque passa a persegui-lo assim que ele se tornar um CombatTarget.
		humanoid:Move(Vector3.zero, false)
		setTargetAttributes(nil, nil, "Searching")
		return
	end

	local targetPart = rootOf(currentTarget)
	if not targetPart then
		currentTarget = nil
		return
	end

	local offset = targetPart.Position - root.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = flatOffset.Magnitude
	setTargetAttributes(
		currentTarget,
		distance,
		distance > ATTACK_DISTANCE and "Approaching" or "Attacking"
	)

	if distance > ATTACK_DISTANCE then
		if distance > 0.05 then
			-- Aplicado depois do PlayerModule para que o joystick neutro nao
			-- cancele a aproximacao automatica enquanto o botao estiver segurado.
			humanoid:Move(flatOffset.Unit, false)
			humanoid:MoveTo(Vector3.new(
				targetPart.Position.X,
				root.Position.Y,
				targetPart.Position.Z
			))
		end
		return
	end

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

local function begin(input)
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
		setTargetAttributes(nil, nil, "NoSword")
		return
	end

	held = true
	heldInput = input
	currentTarget = nil
	lastTargetSearch = 0
	lastAttackAt = 0
	player:SetAttribute("DungeonMobileAttackHeld", true)
	player:SetAttribute("DungeonMobileAttackHoldStartedAt", workspace:GetServerTimeNow())
	setTargetAttributes(nil, nil, "Searching")

	RunService:UnbindFromRenderStep(RENDER_BIND)
	RunService:BindToRenderStep(
		RENDER_BIND,
		Enum.RenderPriority.Input.Value + 20,
		stepAutoWalk
	)
	-- Executa uma vez imediatamente para nao esperar o proximo frame perceptivel.
	stepAutoWalk()
end

local function isPressInput(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function isAttackButton(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end
	if BUTTON_NAMES[string.lower(button.Name)] then
		return true
	end
	local parent = button.Parent
	return parent and BUTTON_NAMES[string.lower(parent.Name)] == true
end

local function bindButton(button)
	if not isAttackButton(button) or boundButtons[button] then
		return
	end
	boundButtons[button] = true
	button:SetAttribute("DungeonMobileAutoWalkBound", true)
	button:SetAttribute("DungeonMobileAttackHoldBound", true)

	button.InputBegan:Connect(function(input)
		if isPressInput(input) then
			begin(input)
		end
	end)
	button.InputEnded:Connect(function(input)
		if heldInput == input then
			stop("ButtonReleased")
		end
	end)
end

local function scan()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		bindButton(descendant)
	end
end

-- InputEnded global cobre o caso em que o dedo sai dos limites do botao antes
-- de ser solto.
UserInputService.InputEnded:Connect(function(input)
	if heldInput == input then
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
	task.defer(scan)
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

task.defer(scan)
player:SetAttribute("DungeonMobileAutoWalkReady", true)
player:SetAttribute("DungeonMobileHoldAttackReady", true)
player:SetAttribute("DungeonMobileAutoWalkVersion", VERSION)
player:SetAttribute("DungeonMobileHoldAttackPolicy", "HoldToApproachAndAttackNearestTargetV4")
