--[[
	Infinity Islands - Direct Island Start + Initial Combat Guide

	Mantem o inicio instantaneo do MVP e adiciona SOMENTE na ilha inicial um
	guia curto de combate:
	- usa a ordem publicada pela SITUAÇÃO ATUAL (MobObjectiveVariantOrder);
	- escolhe um mob vivo da primeira variante ainda pendente;
	- publica esse alvo em PlayerGui.DungeonInitialGuideTarget;
	- mostra uma espada sobre a cabeça do alvo e o texto ATAQUE na tela;
	- mantem o mesmo alvo ate ele morrer/ficar invalido;
	- quando a cota da ilha termina, remove o guia. A camera volta ao modo
	  inteligente e o servidor de progressao pode liberar AVANÇAR normalmente.

	Este controller nao bloqueia input e nao cria uma segunda regra de progresso.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("InstantOnboardingConfig")
)

local TARGET_TAG = "CombatTarget"
local GUIDE_UPDATE_SECONDS = 0.10
local GUIDE_VERSION = "InitialCombatGuideV1_ObjectiveOrder"

local BLOCKED_GUI_NAMES = {
	StartScreen = true,
	StartUI = true,
	DungeonStartScreen = true,
	DungeonStartUI = true,
	ReadyScreen = true,
	ReadyUI = true,
	TutorialScreen = true,
	TutorialUI = true,
	InitialScreen = true,
	InitialUI = true,
	SpawnScreen = true,
	SpawnUI = true,
	LoadingScreen = true,
	LoadingUI = true,
	DungeonLoadingScreen = true,
	DungeonLoadingUI = true,
	StartMenu = true,
	DungeonStartMenu = true,
}

local BLOCKED_SCRIPT_NAMES = {
	DungeonSpectator = true,
	WorldEventUI = true,
	VillagerUI = true,
	TutorialUI = true,
	MonetizationUI = true,
	LeaderboardUI = true,
	RewardWheelUI = true,
	DungeonPartyLifeHUD = true,
	DungeonUnifiedHUD = true,
	DungeonObjectiveHUD = true,
	DungeonRewardsHUD = true,
}

local guideTargetValue = playerGui:FindFirstChild("DungeonInitialGuideTarget")
if guideTargetValue and not guideTargetValue:IsA("ObjectValue") then
	guideTargetValue:Destroy()
	guideTargetValue = nil
end
if not guideTargetValue then
	guideTargetValue = Instance.new("ObjectValue")
	guideTargetValue.Name = "DungeonInitialGuideTarget"
	guideTargetValue.Parent = playerGui
end

guideTargetValue.Value = nil

local guideGui
local guideLabel
local swordBillboard
local swordAdornee
local currentGuideTarget
local elapsed = 0

local function setHidden(instance)
	if instance:IsA("ScreenGui") then
		instance.Enabled = false
		return true
	end

	if instance:IsA("GuiObject") then
		instance.Visible = false
		return true
	end

	return false
end

local function suppress(instance)
	if not instance or not instance.Parent then
		return
	end

	if BLOCKED_GUI_NAMES[instance.Name] then
		if setHidden(instance) then
			instance:SetAttribute("SuppressedByDirectIslandStart", true)

			if instance:IsA("ScreenGui") then
				if instance:GetAttribute("DirectIslandStartBound") ~= true then
					instance:SetAttribute("DirectIslandStartBound", true)
					instance:GetPropertyChangedSignal("Enabled"):Connect(function()
						if instance.Parent and instance.Enabled then
							instance.Enabled = false
						end
					end)
				end
			elseif instance:IsA("GuiObject") then
				if instance:GetAttribute("DirectIslandStartBound") ~= true then
					instance:SetAttribute("DirectIslandStartBound", true)
					instance:GetPropertyChangedSignal("Visible"):Connect(function()
						if instance.Parent and instance.Visible then
							instance.Visible = false
						end
					end)
				end
			end
		end
	end

	if instance:IsA("LocalScript") and BLOCKED_SCRIPT_NAMES[instance.Name] then
		instance.Disabled = true
		instance:SetAttribute("DisabledByDirectIslandStart", true)
	end
end

local function suppressAll()
	for _, instance in ipairs(playerGui:GetDescendants()) do
		suppress(instance)
	end
	for _, instance in ipairs(playerGui:GetChildren()) do
		suppress(instance)
	end

	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	if playerScripts then
		for _, instance in ipairs(playerScripts:GetDescendants()) do
			suppress(instance)
		end
	end
end

local function forceDirectStartAttributes()
	player:SetAttribute("DungeonRuntimeAutoStart", true)
	player:SetAttribute("InitialGameStarted", true)
	player:SetAttribute("DungeonStartConfirmationRequired", false)
	player:SetAttribute("DungeonTutorialBlocking", false)
	player:SetAttribute("DungeonGuideEnabled", false)
	player:SetAttribute("DungeonOnboardingBlocksGameplay", false)
	player:SetAttribute("DungeonInstantOnboardingClientReady", true)
	player:SetAttribute("DungeonInstantOnboardingVersion", Config.Version)
	player:SetAttribute("DungeonInstantOnboardingPolicy", Config.Policy)
end

local function currentIslandIndex()
	return math.max(
		1,
		math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 1)
	)
end

local function humanoidAndRoot(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return humanoid, root
end

local function initialIslandFor(model)
	local cursor = model
	while cursor and cursor ~= Workspace do
		if cursor:IsA("Model") then
			local index = tonumber(cursor:GetAttribute("GlobalIslandIndex"))
				or tonumber(cursor:GetAttribute("ProgressionIslandIndex"))
			if cursor:GetAttribute("IsInitialIsland") == true
				or cursor:GetAttribute("NumberedIslandIndex") == 0
				or cursor:GetAttribute("IslandRole") == "CombatEntry"
				or (index and math.floor(index) == 1)
			then
				return cursor
			end
		end
		cursor = cursor.Parent
	end
	return nil
end

local function objectiveOrder(island)
	local result = {}
	local encoded = tostring(island and island:GetAttribute("MobObjectiveVariantOrder") or "")
	for token in string.gmatch(encoded, "[^,%s]+") do
		table.insert(result, token)
	end
	return result
end

local function objectiveFinished(island)
	if not island or not island.Parent then
		return false
	end
	if island:GetAttribute("Cleared") == true
		or island:GetAttribute("CombatRouteCleared") == true
		or island:GetAttribute("LinearObjectiveComplete") == true
	then
		return true
	end

	local target = math.max(
		0,
		math.floor(tonumber(
			island:GetAttribute("MobTargetCount")
				or island:GetAttribute("MobKillQuota")
				or island:GetAttribute("MobFiniteTargetCount")
		) or 0)
	)
	local defeated = math.max(
		0,
		math.floor(tonumber(
			island:GetAttribute("MobDefeatedCount")
				or island:GetAttribute("MobFiniteDefeatedCount")
		) or 0)
	)
	if target > 0 and defeated >= target then
		return true
	end

	local order = objectiveOrder(island)
	local hadObjective = false
	for _, variant in ipairs(order) do
		local initial = math.max(0, math.floor(tonumber(
			island:GetAttribute("MobObjectiveInitial_" .. variant)
		) or 0))
		if initial > 0 then
			hadObjective = true
			local remaining = math.max(0, math.floor(tonumber(
				island:GetAttribute("MobObjectiveRemaining_" .. variant)
			) or initial))
			if remaining > 0 then
				return false
			end
		end
	end
	return hadObjective
end

local function desiredVariant(island)
	for _, variant in ipairs(objectiveOrder(island)) do
		local initial = math.max(0, math.floor(tonumber(
			island:GetAttribute("MobObjectiveInitial_" .. variant)
		) or 0))
		local remaining = math.max(0, math.floor(tonumber(
			island:GetAttribute("MobObjectiveRemaining_" .. variant)
		) or initial))
		if initial > 0 and remaining > 0 then
			return variant
		end
	end
	return nil
end

local function validInitialTarget(model, requestedVariant)
	if not model
		or not model:IsA("Model")
		or model:GetAttribute("IsInitialIslandMob") ~= true
	then
		return false
	end
	local humanoid = humanoidAndRoot(model)
	if not humanoid then
		return false
	end
	if requestedVariant then
		local variant = tostring(model:GetAttribute("SlimeVariant") or "Green")
		if variant ~= requestedVariant then
			return false
		end
	end
	return initialIslandFor(model) ~= nil
end

local function playerRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function chooseGuideTarget(island)
	local requestedVariant = desiredVariant(island)

	-- Nao troca de alvo no meio da orientacao. A camera permanece estavel ate
	-- o mob atual morrer ou deixar de ser valido.
	if validInitialTarget(currentGuideTarget, requestedVariant) then
		return currentGuideTarget
	end

	local root = playerRoot()
	local best
	local bestScore = math.huge

	for _, model in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if validInitialTarget(model, requestedVariant) then
			local _, mobRoot = humanoidAndRoot(model)
			local distance = root and (mobRoot.Position - root.Position).Magnitude or 0
			local firstPriority = model:GetAttribute("FirstCombatEngagementPriority") == true
			local score = distance - (firstPriority and 10000 or 0)
			if score < bestScore then
				best = model
				bestScore = score
			end
		end
	end

	-- Se os atributos da lista ainda estiverem replicando, nao trava o guia:
	-- escolhe qualquer slime inicial vivo e corrige para a ordem assim que a
	-- SITUAÇÃO ATUAL publicar MobObjectiveVariantOrder.
	if not best and requestedVariant == nil then
		for _, model in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
			if validInitialTarget(model, nil) then
				local _, mobRoot = humanoidAndRoot(model)
				local distance = root and (mobRoot.Position - root.Position).Magnitude or 0
				if distance < bestScore then
					best = model
					bestScore = distance
				end
			end
		end
	end

	return best
end

local function ensureGuideGui()
	if guideGui and guideGui.Parent then
		return
	end

	guideGui = playerGui:FindFirstChild("DungeonInitialAttackGuide")
	if guideGui and not guideGui:IsA("ScreenGui") then
		guideGui:Destroy()
		guideGui = nil
	end
	if not guideGui then
		guideGui = Instance.new("ScreenGui")
		guideGui.Name = "DungeonInitialAttackGuide"
		guideGui.ResetOnSpawn = false
		guideGui.IgnoreGuiInset = true
		guideGui.DisplayOrder = 90
		guideGui.Parent = playerGui
	end

	guideLabel = guideGui:FindFirstChild("AttackText")
	if not guideLabel or not guideLabel:IsA("TextLabel") then
		if guideLabel then
			guideLabel:Destroy()
		end
		guideLabel = Instance.new("TextLabel")
		guideLabel.Name = "AttackText"
		guideLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		guideLabel.Position = UDim2.fromScale(0.5, 0.76)
		guideLabel.Size = UDim2.fromOffset(180, 48)
		guideLabel.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
		guideLabel.BackgroundTransparency = 0.22
		guideLabel.BorderSizePixel = 0
		guideLabel.Text = "ATAQUE"
		guideLabel.TextColor3 = Color3.new(1, 1, 1)
		guideLabel.TextStrokeTransparency = 0.25
		guideLabel.Font = Enum.Font.GothamBlack
		guideLabel.TextSize = 24
		guideLabel.Visible = false
		guideLabel.Parent = guideGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = guideLabel
	end
end

local function clearSwordBillboard()
	if swordBillboard then
		swordBillboard:Destroy()
		swordBillboard = nil
	end
	swordAdornee = nil
end

local function attachSwordBillboard(target)
	local _, root = humanoidAndRoot(target)
	if not root then
		clearSwordBillboard()
		return
	end
	if swordBillboard and swordBillboard.Parent and swordAdornee == root then
		return
	end

	clearSwordBillboard()

	swordBillboard = Instance.new("BillboardGui")
	swordBillboard.Name = "DungeonInitialAttackSword"
	swordBillboard.Adornee = root
	swordBillboard.AlwaysOnTop = true
	swordBillboard.LightInfluence = 0
	swordBillboard.MaxDistance = 120
	swordBillboard.Size = UDim2.fromOffset(52, 52)
	swordBillboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	swordBillboard.Parent = playerGui

	local icon = Instance.new("TextLabel")
	icon.Name = "SwordIcon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Text = "⚔"
	icon.TextColor3 = Color3.fromRGB(255, 238, 170)
	icon.TextStrokeColor3 = Color3.fromRGB(30, 22, 10)
	icon.TextStrokeTransparency = 0.1
	icon.Font = Enum.Font.GothamBlack
	icon.TextScaled = true
	icon.Parent = swordBillboard

	swordAdornee = root
end

local function clearGuide(completed)
	currentGuideTarget = nil
	guideTargetValue.Value = nil
	if guideLabel then
		guideLabel.Visible = false
	end
	clearSwordBillboard()
	player:SetAttribute("DungeonInitialCombatGuideActive", false)
	player:SetAttribute("DungeonInitialCombatGuideTarget", nil)
	if completed == true then
		player:SetAttribute("DungeonInitialCombatGuideComplete", true)
	end
end

local function updateGuide()
	if currentIslandIndex() ~= 1
		or player:GetAttribute("DungeonAssistedTransportActive") == true
	then
		clearGuide(currentIslandIndex() > 1)
		return
	end

	local island
	for _, candidate in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if candidate:IsA("Model") and candidate:GetAttribute("IsInitialIslandMob") == true then
			island = initialIslandFor(candidate)
			if island then
				break
			end
		end
	end

	if not island then
		-- Durante os primeiros frames os mobs ainda podem nao ter sido criados.
		clearGuide(false)
		return
	end

	if objectiveFinished(island) then
		clearGuide(true)
		return
	end

	local target = chooseGuideTarget(island)
	if not target then
		clearGuide(false)
		return
	end

	currentGuideTarget = target
	guideTargetValue.Value = target
	ensureGuideGui()
	guideLabel.Visible = true
	attachSwordBillboard(target)

	player:SetAttribute("DungeonInitialCombatGuideActive", true)
	player:SetAttribute("DungeonInitialCombatGuideComplete", false)
	player:SetAttribute("DungeonInitialCombatGuideTarget", target.Name)
	player:SetAttribute("DungeonInitialCombatGuideVersion", GUIDE_VERSION)
	player:SetAttribute("DungeonInitialCombatGuideVariant", tostring(target:GetAttribute("SlimeVariant") or "Green"))
end

suppressAll()
forceDirectStartAttributes()
ensureGuideGui()

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(suppress, instance)
end)

local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
if playerScripts then
	playerScripts.DescendantAdded:Connect(function(instance)
		task.defer(suppress, instance)
	end)
end

for _, attributeName in ipairs({
	"InitialGameStarted",
	"DungeonStartConfirmationRequired",
	"DungeonTutorialBlocking",
	"DungeonGuideEnabled",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(function()
		task.defer(forceDirectStartAttributes)
	end)
end

player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
	task.defer(updateGuide)
end)
player.CharacterAdded:Connect(function()
	currentGuideTarget = nil
	task.delay(0.15, updateGuide)
end)

CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(function()
	task.defer(updateGuide)
end)
CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(function(instance)
	if instance == currentGuideTarget then
		currentGuideTarget = nil
		task.defer(updateGuide)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < GUIDE_UPDATE_SECONDS then
		return
	end
	elapsed = 0
	updateGuide()
end)

task.delay(
	math.max(0.5, tonumber(Config.TargetTimeToControlSeconds) or 2.5),
	function()
		suppressAll()
		forceDirectStartAttributes()
		updateGuide()
	end
)

player:SetAttribute("DungeonInitialCombatGuideVersion", GUIDE_VERSION)
updateGuide()

print(
	"[DirectIslandStart] Ready; initial combat guide follows SITUAÇÃO ATUAL."
)
