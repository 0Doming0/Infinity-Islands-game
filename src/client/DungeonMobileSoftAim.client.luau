-- Mobile Dungeon Mode — Task 04: Soft Aim Target Scoring.
--
-- Esta task APENAS seleciona o melhor alvo local.
-- Ela NAO:
-- - gira o personagem;
-- - ativa a Tool;
-- - envia alvo para o servidor;
-- - concede dano;
-- - altera hitbox.
--
-- Tasks posteriores podem consumir o ObjectValue:
-- PlayerGui/DungeonMobileSoftAimTarget

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(
	ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig")
)

local VERSION = "DungeonMobileSoftAimV1"
local UPDATE_INTERVAL = 0.08

local DEFAULTS = {
	MaxDistance = 9,
	MaxAngleDegrees = 45,
	MaxVerticalDifference = 7,
	DistanceWeight = 0.46,
	AngleWeight = 0.54,
	SwitchAdvantage = 0.10,
	StickyExtraDistance = 1.0,
	StickyExtraAngle = 5,
}

local active = false
local elapsed = 0
local currentTarget
local currentScore = -math.huge

local targetValue = playerGui:FindFirstChild("DungeonMobileSoftAimTarget")
if targetValue and not targetValue:IsA("ObjectValue") then
	targetValue:Destroy()
	targetValue = nil
end
if not targetValue then
	targetValue = Instance.new("ObjectValue")
	targetValue.Name = "DungeonMobileSoftAimTarget"
	targetValue.Parent = playerGui
end

local function numberSetting(name, defaultValue, minimum, maximum)
	local value = tonumber(player:GetAttribute(name))
	if value == nil then
		value = defaultValue
	end
	return math.clamp(value, minimum, maximum)
end

local function ensureTuningAttributes()
	local settings = {
		DungeonMobileSoftAimMaxDistance = DEFAULTS.MaxDistance,
		DungeonMobileSoftAimMaxAngle = DEFAULTS.MaxAngleDegrees,
		DungeonMobileSoftAimMaxVerticalDifference = DEFAULTS.MaxVerticalDifference,
		DungeonMobileSoftAimDistanceWeight = DEFAULTS.DistanceWeight,
		DungeonMobileSoftAimAngleWeight = DEFAULTS.AngleWeight,
		DungeonMobileSoftAimSwitchAdvantage = DEFAULTS.SwitchAdvantage,
	}

	for name, value in pairs(settings) do
		if player:GetAttribute(name) == nil then
			player:SetAttribute(name, value)
		end
	end
end

local function targetRoot(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function targetHumanoid(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
		or model:FindFirstChildWhichIsA("Humanoid", true)
end

local function currentEncounterId()
	local value = workspace:GetAttribute("DungeonEncounterId")
	if value == nil or tostring(value) == "" then
		return nil
	end
	return tostring(value)
end

local function currentIslandIndex()
	local value = tonumber(
		workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or workspace:GetAttribute("DungeonCurrentObjectiveIsland")
	)
	if not value then
		return nil
	end
	return math.floor(value)
end

local function belongsToCurrentEncounter(model)
	local activeEncounter = currentEncounterId()
	local targetEncounter = model:GetAttribute("ObjectiveEncounterId")

	if activeEncounter and targetEncounter ~= nil
		and tostring(targetEncounter) ~= activeEncounter
	then
		return false
	end

	local activeIsland = currentIslandIndex()
	local targetIsland = tonumber(model:GetAttribute("GlobalIslandIndex"))
	if activeIsland and targetIsland and targetIsland > 0
		and math.floor(targetIsland) ~= activeIsland
	then
		return false
	end

	return true
end

local function targetCanBeAttacked(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end

	if not CollectionService:HasTag(model, CombatConfig.TargetTag) then
		return false
	end

	if model == player.Character or model:IsDescendantOf(player.Character) then
		return false
	end

	if model:GetAttribute("ObjectiveTargetCompleted") == true
		or model:GetAttribute("ObjectiveAmbushHidden") == true
		or model:GetAttribute("SimulationActive") == false
		or model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("GuardWardProtected") == true
		or model:GetAttribute("EliteShielded") == true
	then
		return false
	end

	if not belongsToCurrentEncounter(model) then
		return false
	end

	local humanoid = targetHumanoid(model)
	if humanoid and humanoid.Health <= 0 then
		return false
	end

	return targetRoot(model) ~= nil
end

local function horizontalDirection(fromPosition, toPosition)
	local delta = toPosition - fromPosition
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil, 0, math.abs(delta.Y)
	end
	return horizontal.Unit, horizontal.Magnitude, math.abs(delta.Y)
end

local function facingDirection(rootPart)
	local look = rootPart.CFrame.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function angleDegrees(forward, direction)
	local dot = math.clamp(forward:Dot(direction), -1, 1)
	return math.deg(math.acos(dot))
end

local function roleBonus(model)
	-- Bonus pequeno: distancia/angulo continuam dominando.
	-- Serve apenas como desempate natural para ameaças/objetivos importantes.
	if model:GetAttribute("IsElite") == true then
		return 0.035
	end

	local role = string.lower(tostring(
		model:GetAttribute("MonsterRole")
			or model:GetAttribute("ObjectiveRole")
			or model:GetAttribute("CombatRole")
			or ""
	))

	if string.find(role, "ranged", 1, true) then
		return 0.025
	elseif string.find(role, "guard", 1, true) then
		return 0.015
	end

	if model:GetAttribute("ObjectiveMechanicActor") == true
		or model:GetAttribute("ObjectiveActorType") ~= nil
	then
		return 0.02
	end

	return 0
end

local function scoreCandidate(model, rootPart, forward, sticky)
	local root = targetRoot(model)
	if not root then
		return nil
	end

	local direction, distance, verticalDifference = horizontalDirection(
		rootPart.Position,
		root.Position
	)
	if not direction then
		return nil
	end

	local maxDistance = numberSetting(
		"DungeonMobileSoftAimMaxDistance",
		DEFAULTS.MaxDistance,
		5,
		14
	)
	local maxAngle = numberSetting(
		"DungeonMobileSoftAimMaxAngle",
		DEFAULTS.MaxAngleDegrees,
		20,
		65
	)
	local maxVertical = numberSetting(
		"DungeonMobileSoftAimMaxVerticalDifference",
		DEFAULTS.MaxVerticalDifference,
		3,
		12
	)

	if sticky then
		maxDistance += DEFAULTS.StickyExtraDistance
		maxAngle += DEFAULTS.StickyExtraAngle
	end

	if distance > maxDistance or verticalDifference > maxVertical then
		return nil
	end

	local angle = angleDegrees(forward, direction)
	if angle > maxAngle then
		return nil
	end

	-- Normaliza ambos em 0..1, onde 1 e melhor.
	local distanceScore = 1 - math.clamp(distance / maxDistance, 0, 1)
	local angleScore = 1 - math.clamp(angle / maxAngle, 0, 1)

	local distanceWeight = numberSetting(
		"DungeonMobileSoftAimDistanceWeight",
		DEFAULTS.DistanceWeight,
		0,
		1
	)
	local angleWeight = numberSetting(
		"DungeonMobileSoftAimAngleWeight",
		DEFAULTS.AngleWeight,
		0,
		1
	)
	local weightTotal = math.max(0.001, distanceWeight + angleWeight)

	local score = (
		distanceScore * distanceWeight
		+ angleScore * angleWeight
	) / weightTotal

	score += roleBonus(model)

	return {
		Model = model,
		Root = root,
		Score = score,
		Distance = distance,
		Angle = angle,
		VerticalDifference = verticalDifference,
	}
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

local function canScoreTargets()
	if not active or player:GetAttribute("DungeonMobileMode") ~= true then
		return false
	end
	if player:GetAttribute("IsDowned") == true then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if character:GetAttribute("MovementLocked") == true then
		return false
	end
	if not equippedSword() then
		return false
	end

	return true
end

local function clearSelection(reason)
	currentTarget = nil
	currentScore = -math.huge
	targetValue.Value = nil

	player:SetAttribute("DungeonMobileSoftAimHasTarget", false)
	player:SetAttribute("DungeonMobileSoftAimTargetName", nil)
	player:SetAttribute("DungeonMobileSoftAimTargetDistance", nil)
	player:SetAttribute("DungeonMobileSoftAimTargetAngle", nil)
	player:SetAttribute("DungeonMobileSoftAimTargetScore", nil)
	player:SetAttribute("DungeonMobileSoftAimClearReason", reason)
end

local function publishSelection(candidate)
	if not candidate then
		clearSelection("NoCandidate")
		return
	end

	currentTarget = candidate.Model
	currentScore = candidate.Score
	targetValue.Value = candidate.Model

	player:SetAttribute("DungeonMobileSoftAimHasTarget", true)
	player:SetAttribute("DungeonMobileSoftAimTargetName", candidate.Model.Name)
	player:SetAttribute("DungeonMobileSoftAimTargetDistance", candidate.Distance)
	player:SetAttribute("DungeonMobileSoftAimTargetAngle", candidate.Angle)
	player:SetAttribute("DungeonMobileSoftAimTargetScore", candidate.Score)
	player:SetAttribute("DungeonMobileSoftAimClearReason", nil)
end

local function selectBestTarget()
	if not canScoreTargets() then
		clearSelection("Unavailable")
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		clearSelection("NoRoot")
		return
	end

	local forward = facingDirection(rootPart)
	local best

	-- Primeiro reavalia o alvo atual com pequena tolerancia extra.
	local stickyCandidate
	if currentTarget and targetCanBeAttacked(currentTarget) then
		stickyCandidate = scoreCandidate(
			currentTarget,
			rootPart,
			forward,
			true
		)
	end

	for _, instance in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		if targetCanBeAttacked(instance) then
			local candidate = scoreCandidate(
				instance,
				rootPart,
				forward,
				instance == currentTarget
			)
			if candidate and (not best or candidate.Score > best.Score) then
				best = candidate
			end
		end
	end

	if stickyCandidate and best and best.Model ~= stickyCandidate.Model then
		local advantage = numberSetting(
			"DungeonMobileSoftAimSwitchAdvantage",
			DEFAULTS.SwitchAdvantage,
			0,
			0.35
		)

		-- Evita flickering entre dois slimes com scores quase iguais.
		if best.Score < stickyCandidate.Score + advantage then
			best = stickyCandidate
		end
	elseif stickyCandidate and not best then
		best = stickyCandidate
	end

	if best then
		publishSelection(best)
	else
		clearSelection("NoCandidate")
	end
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	ensureTuningAttributes()

	player:SetAttribute("DungeonMobileSoftAimReady", true)
	player:SetAttribute("DungeonMobileSoftAimActive", true)
	player:SetAttribute("DungeonMobileSoftAimVersion", VERSION)
	player:SetAttribute("DungeonMobileSoftAimPolicy", "DistanceAngleStickyNoLockV1")

	selectBestTarget()
end

local function deactivate()
	if not active then
		return
	end

	active = false
	clearSelection("Inactive")
	player:SetAttribute("DungeonMobileSoftAimActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

RunService.Heartbeat:Connect(function(deltaTime)
	if not active then
		return
	end

	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0

	selectBestTarget()
end)

player:SetAttribute("DungeonMobileSoftAimControllerLoaded", true)
player:SetAttribute("DungeonMobileSoftAimVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal("DungeonInputProfileReady"):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(function()
	deactivate()
	if targetValue and targetValue.Parent then
		targetValue:Destroy()
	end
end)
