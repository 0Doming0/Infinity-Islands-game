-- Mobile Dungeon Mode — Task 08: Strong Hit Feedback + Haptics.
--
-- Camada 100% local de apresentacao.
-- Nao altera dano, hitbox, combo, cooldown ou selecao de alvo.
--
-- O evento EnemyDamageFeedback ja e produzido pelo servidor somente depois de
-- dano valido. SwordHitSerial e incrementado uma unica vez por swing que acertou
-- ao menos um alvo, entao o haptico nao multiplica em ataques multi-target.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local feedbackEvent = RemoteRegistry.Get("Combat", "EnemyDamageFeedback", "RemoteEvent")

local VERSION = "DungeonStrongHitFeedbackV1"
local FLASH_LIFETIME = 0.16
local HEAVY_FLASH_LIFETIME = 0.23

local COLORS = {
	Normal = Color3.fromRGB(255, 238, 177),
	Heavy = Color3.fromRGB(255, 143, 64),
	Defeat = Color3.fromRGB(255, 217, 103),
	Outline = Color3.fromRGB(255, 255, 255),
}

local normalHaptic
local heavyHaptic
local hapticsInitialized = false
local visualSerial = 0

local function reducedEffectsEnabled()
	local value = player:GetAttribute("ClientSetting_ReducedEffects")
	if value == nil then
		value = player:GetAttribute("ReducedMotion")
	end
	if value == nil then
		value = player:GetAttribute("ReduceMotion")
	end
	return value == true
end

local function hapticsEnabled()
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return false
	end
	if reducedEffectsEnabled() then
		return false
	end

	-- Task 17 podera expor uma preferencia persistente com estes nomes.
	-- Ate la, haptics fica habilitado por padrao quando suportado pelo device.
	local setting = player:GetAttribute("ClientSetting_Haptics")
	if setting == nil then
		setting = player:GetAttribute("DungeonMobileHapticsEnabled")
	end
	return setting ~= false
end

local function createHaptic(name, effectType)
	local success, effect = pcall(function()
		local object = Instance.new("HapticEffect")
		object.Name = name
		object.Type = effectType
		object.Parent = workspace
		return object
	end)
	return success and effect or nil
end

local function initializeHaptics()
	if hapticsInitialized then
		return
	end
	hapticsInitialized = true

	normalHaptic = createHaptic(
		"DungeonHitHaptic",
		Enum.HapticEffectType.GameplayCollision
	)
	heavyHaptic = createHaptic(
		"DungeonHeavyHitHaptic",
		Enum.HapticEffectType.GameplayExplosion
	)

	player:SetAttribute(
		"DungeonHitHapticsAvailable",
		normalHaptic ~= nil or heavyHaptic ~= nil
	)
end

local function playHaptic(heavy)
	if not hapticsEnabled() then
		return
	end

	initializeHaptics()

	local effect = heavy and heavyHaptic or normalHaptic
	if not effect then
		effect = normalHaptic or heavyHaptic
	end
	if not effect then
		return
	end

	pcall(function()
		effect:Play()
	end)

	player:SetAttribute(
		"DungeonLastHitHapticAt",
		workspace:GetServerTimeNow()
	)
	player:SetAttribute(
		"DungeonLastHitHapticKind",
		heavy and "Heavy" or "Normal"
	)
end

local function getRoot(model)
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

local function impactColor(payload)
	if payload.Defeated == true then
		return COLORS.Defeat
	end
	if payload.Heavy == true then
		return COLORS.Heavy
	end
	return COLORS.Normal
end

local function createTargetFlash(target, color, heavy, reduced)
	local highlight = Instance.new("Highlight")
	highlight.Name = "LocalSwordHitFlash"
	highlight.Adornee = target
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = color
	highlight.OutlineColor = COLORS.Outline
	highlight.FillTransparency = reduced and 0.82 or (heavy and 0.34 or 0.45)
	highlight.OutlineTransparency = reduced and 0.52 or 0.18
	highlight.Parent = target

	local lifetime = reduced and 0.09 or (heavy and HEAVY_FLASH_LIFETIME or FLASH_LIFETIME)

	TweenService:Create(
		highlight,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			FillTransparency = 1,
			OutlineTransparency = 1,
		}
	):Play()

	task.delay(lifetime + 0.04, function()
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end

local function createImpactRing(root, color, heavy)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LocalSwordImpactRing"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(24, 24)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Parent = playerGui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = heavy and 4 or 3
	stroke.Transparency = 0.04
	stroke.Parent = ring

	local lifetime = heavy and 0.24 or 0.18
	local finalSize = heavy and 96 or 76

	TweenService:Create(
		billboard,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(finalSize, finalSize) }
	):Play()

	TweenService:Create(
		stroke,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			Transparency = 1,
			Thickness = 1,
		}
	):Play()

	task.delay(lifetime + 0.04, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function playVisualImpact(payload)
	if type(payload) ~= "table" then
		return
	end

	local target = payload.Target
	if not target
		or not target:IsA("Model")
		or not target:IsDescendantOf(workspace)
	then
		return
	end

	local root = getRoot(target)
	if not root then
		return
	end

	local amount = math.max(0, tonumber(payload.Amount) or 0)
	if amount <= 0 then
		return
	end

	visualSerial += 1
	local heavy = payload.Heavy == true
	local reduced = reducedEffectsEnabled()
	local color = impactColor(payload)

	createTargetFlash(target, color, heavy, reduced)
	if not reduced then
		createImpactRing(root, color, heavy)
	end

	player:SetAttribute("DungeonHitFeedbackSerial", visualSerial)
	player:SetAttribute("DungeonLastHitFeedbackAt", workspace:GetServerTimeNow())
	player:SetAttribute("DungeonLastHitFeedbackHeavy", heavy)
	player:SetAttribute("DungeonLastHitFeedbackDefeated", payload.Defeated == true)
end

feedbackEvent.OnClientEvent:Connect(playVisualImpact)

player:GetAttributeChangedSignal("SwordHitSerial"):Connect(function()
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	local hitCount = math.max(0, tonumber(player:GetAttribute("SwordHitCount")) or 0)
	if hitCount <= 0 then
		return
	end

	playHaptic(player:GetAttribute("SwordHitHeavy") == true)
end)

player:SetAttribute("DungeonStrongHitFeedbackReady", true)
player:SetAttribute("DungeonStrongHitFeedbackVersion", VERSION)
player:SetAttribute("DungeonStrongHitFeedbackPolicy", "FlashRingOneHapticPerSwingV1")

workspace:SetAttribute("DungeonStrongHitFeedbackReady", true)
workspace:SetAttribute("DungeonStrongHitFeedbackPolicy", "FlashRingOneHapticPerSwingV1")

script.Destroying:Connect(function()
	for _, effect in ipairs({ normalHaptic, heavyHaptic }) do
		if effect and effect.Parent then
			effect:Destroy()
		end
	end
end)
