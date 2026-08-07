-- Mobile Dungeon Mode — Task 13: Boss Camera Integration.
--
-- Usa exclusivamente os seams do DungeonCameraController:
--   workspace.DungeonMobileCameraForwardOverride
--   workspace.DungeonMobileCameraFocusWorldOverride
--
-- Nao escreve Camera.CFrame.
-- Nao move jogador/Boss.
-- Nao altera IA, dano, hitbox ou arena.
--
-- Objetivo: enquadrar jogador + Boss em portrait preservando leitura dos
-- telegraphs e liberdade para dodge/posicionamento.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local VERSION = "DungeonPortraitBossCameraV1"
local UPDATE_INTERVAL = 0.06

local DEFAULTS = {
	MinBossDistance = 4,
	MaxBossDistance = 90,
	BaseHeight = 25,
	MaxHeight = 33,
	BaseBackDistance = 14,
	MaxBackDistance = 20,
	BaseFov = 72,
	MaxFov = 84,
	BaseLookAhead = 2.8,
	PhaseTransitionFovBonus = 4,
	DangerAttackFovBonus = 3,
	FocusFraction = 0.42,
	MinFocusLead = 5.5,
	MaxFocusLead = 18,
	FocusHeight = 2.8,
}

local CAMERA_ATTRS = {
	"DungeonMobileCameraHeight",
	"DungeonMobileCameraBackDistance",
	"DungeonMobileCameraFov",
	"DungeonMobileCameraLookAhead",
}

local WIDE_ATTACKS = {
	SkyfallVolley = true,
	CrossSweep = true,
	ArenaCollapse = true,
	PhaseTransition = true,
}

local active = false
local elapsed = 0
local savedCameraAttributes
local currentBoss
local lastBossDistance = 0

local function horizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end
	return horizontal.Unit
end

local function playerRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function bossRoot(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function bossHumanoid(model)
	return model and model:FindFirstChildWhichIsA("Humanoid", true)
end

local function isUsableBoss(model)
	if not model or not model.Parent or not model:IsA("Model") then
		return false
	end

	if model:GetAttribute("IsBoss") ~= true
		and not CollectionService:HasTag(model, "DungeonBoss")
	then
		return false
	end

	local humanoid = bossHumanoid(model)
	return humanoid ~= nil and humanoid.Health > 0 and bossRoot(model) ~= nil
end

local function findBoss(root)
	if currentBoss and isUsableBoss(currentBoss) then
		return currentBoss
	end

	local best
	local bestDistance = math.huge

	for _, model in ipairs(CollectionService:GetTagged("DungeonBoss")) do
		if isUsableBoss(model) then
			local targetRoot = bossRoot(model)
			local distance = root
				and (targetRoot.Position - root.Position).Magnitude
				or 0
			if distance < bestDistance then
				best = model
				bestDistance = distance
			end
		end
	end

	if not best then
		for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
			if isUsableBoss(model) then
				local targetRoot = bossRoot(model)
				local distance = root
					and (targetRoot.Position - root.Position).Magnitude
					or 0
				if distance < bestDistance then
					best = model
					bestDistance = distance
				end
			end
		end
	end

	currentBoss = best
	return best
end

local function bossCameraState()
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return false, "NotMobile"
	end
	if player:GetAttribute("IsDowned") == true then
		return false, "Downed"
	end
	if player:GetAttribute("DungeonSpectating") == true
		or player:GetAttribute("DungeonEliminated") == true
	then
		return false, "Spectating"
	end

	local state = tostring(workspace:GetAttribute("DungeonBossState") or "")
	if state == "Activating" or state == "Active" then
		return true, state
	end

	return false, state ~= "" and state or "Inactive"
end

local function saveCameraAttributes()
	if savedCameraAttributes then
		return
	end

	savedCameraAttributes = {}
	for _, name in ipairs(CAMERA_ATTRS) do
		savedCameraAttributes[name] = {
			Exists = player:GetAttribute(name) ~= nil,
			Value = player:GetAttribute(name),
		}
	end
end

local function restoreCameraAttributes()
	if not savedCameraAttributes then
		return
	end

	for name, record in pairs(savedCameraAttributes) do
		if record.Exists then
			player:SetAttribute(name, record.Value)
		else
			player:SetAttribute(name, nil)
		end
	end

	savedCameraAttributes = nil
end

local function clearOverrides(reason)
	workspace:SetAttribute("DungeonMobileCameraFocusWorldOverride", nil)
	workspace:SetAttribute("DungeonMobileCameraForwardOverride", nil)

	restoreCameraAttributes()

	currentBoss = nil
	lastBossDistance = 0

	player:SetAttribute("DungeonMobileBossCameraActive", false)
	player:SetAttribute("DungeonMobileBossCameraState", reason)
	player:SetAttribute("DungeonMobileBossCameraBossName", nil)
	player:SetAttribute("DungeonMobileBossCameraDistance", nil)
	player:SetAttribute("DungeonMobileBossCameraFocus", nil)
	player:SetAttribute("DungeonMobileBossCameraForward", nil)
end

local function cameraTargets(distance)
	local normalized = math.clamp((distance - 16) / 42, 0, 1)

	local height = DEFAULTS.BaseHeight
		+ (DEFAULTS.MaxHeight - DEFAULTS.BaseHeight) * normalized
	local back = DEFAULTS.BaseBackDistance
		+ (DEFAULTS.MaxBackDistance - DEFAULTS.BaseBackDistance) * normalized
	local fov = DEFAULTS.BaseFov
		+ (DEFAULTS.MaxFov - DEFAULTS.BaseFov) * normalized

	local transitioning = workspace:GetAttribute("DungeonBossPhaseTransitioning") == true
	local attack = tostring(
		workspace:GetAttribute("DungeonBossAttack")
			or (currentBoss and currentBoss:GetAttribute("BossAttack"))
			or "Idle"
	)

	if transitioning then
		height += 2
		fov += DEFAULTS.PhaseTransitionFovBonus
	elseif WIDE_ATTACKS[attack] then
		fov += DEFAULTS.DangerAttackFovBonus
	end

	return math.clamp(height, 22, 35),
		math.clamp(back, 12, 22),
		math.clamp(fov, 68, 88),
		attack
end

local function publishFraming(root, model, targetRoot, bossState)
	local offset = targetRoot.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontal.Magnitude
	if distance < DEFAULTS.MinBossDistance
		or distance > DEFAULTS.MaxBossDistance
	then
		clearOverrides("BossOutOfFramingRange")
		return
	end

	local direction = horizontalUnit(horizontal)
	if not direction then
		return
	end

	saveCameraAttributes()

	local focusLead = math.clamp(
		distance * DEFAULTS.FocusFraction,
		DEFAULTS.MinFocusLead,
		DEFAULTS.MaxFocusLead
	)

	-- Foco entre jogador e Boss. Mantemos Y perto do jogador para que telegraphs
	-- no chao continuem visiveis e o Boss nao empurre a camera para cima.
	local focus = root.Position
		+ direction * focusLead
		+ Vector3.new(0, DEFAULTS.FocusHeight, 0)

	local height, backDistance, fov, attack = cameraTargets(distance)

	player:SetAttribute("DungeonMobileCameraHeight", height)
	player:SetAttribute("DungeonMobileCameraBackDistance", backDistance)
	player:SetAttribute("DungeonMobileCameraFov", fov)
	player:SetAttribute("DungeonMobileCameraLookAhead", DEFAULTS.BaseLookAhead)

	-- Task12 libera o ForwardOverride quando Boss entra em Activating/Active.
	-- Task13 passa a ser o dono contextual desses dois seams durante a luta.
	workspace:SetAttribute("DungeonMobileCameraForwardOverride", direction)
	workspace:SetAttribute("DungeonMobileCameraFocusWorldOverride", focus)

	lastBossDistance = distance

	player:SetAttribute("DungeonMobileBossCameraActive", true)
	player:SetAttribute("DungeonMobileBossCameraState", bossState)
	player:SetAttribute("DungeonMobileBossCameraBossName", model.Name)
	player:SetAttribute("DungeonMobileBossCameraDistance", distance)
	player:SetAttribute("DungeonMobileBossCameraFocus", focus)
	player:SetAttribute("DungeonMobileBossCameraForward", direction)
	player:SetAttribute("DungeonMobileBossCameraAttack", attack)
	player:SetAttribute(
		"DungeonMobileBossCameraPhase",
		tonumber(workspace:GetAttribute("DungeonBossPhase"))
			or tonumber(model:GetAttribute("BossPhase"))
			or 1
	)
end

local function update()
	if not active then
		return
	end

	local allowed, state = bossCameraState()
	if not allowed then
		if player:GetAttribute("DungeonMobileBossCameraActive") == true
			or savedCameraAttributes
		then
			clearOverrides(state)
		end
		return
	end

	local root = playerRoot()
	if not root then
		clearOverrides("NoPlayerRoot")
		return
	end

	local boss = findBoss(root)
	local targetRoot = boss and bossRoot(boss)
	if not boss or not targetRoot then
		-- Durante a pequena janela de replicacao da ativacao, nao escrevemos
		-- um framing falso. Task02 mantem sua camera base ate o Boss aparecer.
		if player:GetAttribute("DungeonMobileBossCameraActive") == true then
			clearOverrides("BossNotReplicated")
		end
		return
	end

	publishFraming(root, boss, targetRoot, state)
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	player:SetAttribute("DungeonMobileBossCameraReady", true)
	player:SetAttribute("DungeonMobileBossCameraActive", false)
	player:SetAttribute("DungeonMobileBossCameraVersion", VERSION)
	player:SetAttribute(
		"DungeonMobileBossCameraPolicy",
		"PlayerBossSharedFocusWideTelegraphV1"
	)

	update()
end

local function deactivate()
	if not active then
		return
	end

	active = false
	clearOverrides("Inactive")
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

CollectionService:GetInstanceAddedSignal("DungeonBoss"):Connect(function(model)
	if active and isUsableBoss(model) then
		currentBoss = model
		task.defer(update)
	end
end)

CollectionService:GetInstanceRemovedSignal("DungeonBoss"):Connect(function(model)
	if model == currentBoss then
		currentBoss = nil
		if active then
			task.defer(update)
		end
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)
player.CharacterAdded:Connect(function()
	currentBoss = nil
	if active then
		task.defer(update)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not active then
		return
	end

	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0

	update()
end)

player:SetAttribute("DungeonMobileBossCameraControllerLoaded", true)
player:SetAttribute("DungeonMobileBossCameraVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(deactivate)
