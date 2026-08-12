-- Task 30 — UI dos inimigos e números de dano.
-- Somente apresentação local. Dano continua autoritativo no servidor.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local feedbackEvent = RemoteRegistry.Get("Combat", "EnemyDamageFeedback", "RemoteEvent")

local VERSION = "EnemyPresentationReplicationSafeV3"
local MAX_DISTANCE = 82
local DAMAGE_LIFETIME = 0.62
local HIT_CONFIRM_LIFETIME = 0.18
local KILL_CONFIRM_LIFETIME = 0.82
local BIND_RETRY_SECONDS = 8
local BIND_RETRY_INTERVAL = 0.05

local COLORS = {
	Text = Color3.fromRGB(245, 250, 255),
	Muted = Color3.fromRGB(184, 202, 216),
	Health = Color3.fromRGB(77, 224, 118),
	Warning = Color3.fromRGB(255, 190, 75),
	Danger = Color3.fromRGB(255, 84, 92),
	Gold = Color3.fromRGB(255, 217, 103),
	Damage = Color3.fromRGB(255, 244, 215),
	Heavy = Color3.fromRGB(255, 156, 71),
	Relic = Color3.fromRGB(198, 133, 255),
	Companion = Color3.fromRGB(116, 227, 255),
	Glass = Color3.fromRGB(12, 20, 28),
}

local watched = setmetatable({}, { __mode = "k" })
local binding = setmetatable({}, { __mode = "k" })
local hitSerial = 0
local hitConfirmSerial = 0
local killConfirmSerial = 0

local oldOverlay = playerGui:FindFirstChild("EnemyCombatFeedbackOverlay")
if oldOverlay then
	oldOverlay:Destroy()
end

local overlay = Instance.new("ScreenGui")
overlay.Name = "EnemyCombatFeedbackOverlay"
overlay.ResetOnSpawn = false
overlay.IgnoreGuiInset = true
overlay.DisplayOrder = 86
overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
overlay.Parent = playerGui

local hitMarker = Instance.new("TextLabel")
hitMarker.Name = "HitMarker"
hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
hitMarker.Position = UDim2.fromScale(0.5, 0.5)
hitMarker.Size = UDim2.fromOffset(54, 54)
hitMarker.BackgroundTransparency = 1
hitMarker.Text = "×"
hitMarker.TextColor3 = COLORS.Damage
hitMarker.TextStrokeColor3 = Color3.fromRGB(5, 8, 12)
hitMarker.TextStrokeTransparency = 0.16
hitMarker.TextTransparency = 1
hitMarker.Font = Enum.Font.GothamBlack
hitMarker.TextSize = 31
hitMarker.ZIndex = 90
hitMarker.Parent = overlay
local hitMarkerScale = Instance.new("UIScale")
hitMarkerScale.Scale = 1
hitMarkerScale.Parent = hitMarker

local killConfirm = Instance.new("TextLabel")
killConfirm.Name = "KillConfirm"
killConfirm.AnchorPoint = Vector2.new(0.5, 0)
killConfirm.Position = UDim2.new(0.5, 0, 0.57, 0)
killConfirm.Size = UDim2.fromOffset(390, 40)
killConfirm.BackgroundTransparency = 1
killConfirm.Text = ""
killConfirm.TextColor3 = COLORS.Gold
killConfirm.TextStrokeColor3 = Color3.fromRGB(5, 8, 12)
killConfirm.TextStrokeTransparency = 0.16
killConfirm.TextTransparency = 1
killConfirm.Font = Enum.Font.GothamBlack
killConfirm.TextSize = 16
killConfirm.ZIndex = 90
killConfirm.Parent = overlay
local killConfirmScale = Instance.new("UIScale")
killConfirmScale.Scale = 1
killConfirmScale.Parent = killConfirm

local function getRoot(model)
	if not model or not model:IsA("Model") then return nil end
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then return root end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getHumanoid(model)
	return model and model:FindFirstChildWhichIsA("Humanoid", true)
end

local function healthColor(ratio)
	if ratio <= 0.28 then
		return COLORS.Danger
	elseif ratio <= 0.58 then
		return COLORS.Warning
	end
	return COLORS.Health
end

local function modelHeight(model)
	local ok, _, size = pcall(model.GetBoundingBox, model)
	return ok and size.Y or 4
end

local function displayName(model, humanoid)
	local value = model:GetAttribute("DisplayName")
	if type(value) ~= "string" or value == "" then
		value = humanoid.DisplayName
	end
	if type(value) ~= "string" or value == "" then
		value = model:GetAttribute("MonsterId") or model.Name
	end
	if model:GetAttribute("IsElite") == true then
		return "★ " .. tostring(value)
	end
	return tostring(value)
end

local function hideLegacyDisplay(model, humanoid)
	pcall(function()
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end)
	pcall(function()
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end)
	pcall(function()
		humanoid.NameDisplayDistance = 0
	end)

	local old = model:FindFirstChild("MobHealthBar")
	if old and old:IsA("BillboardGui") then
		old.Enabled = false
	end
end

local function bindEnemy(model)
	if watched[model] then return true end
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return false
	end
	if Players:GetPlayerFromCharacter(model) then return false end

	local humanoid = getHumanoid(model)
	local root = getRoot(model)
	if not humanoid or not root then return false end

	watched[model] = true
	hideLegacyDisplay(model, humanoid)

	local old = model:FindFirstChild("EnemyStatusBillboard")
	if old then old:Destroy() end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EnemyStatusBillboard"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(148, 42)
	billboard.StudsOffsetWorldSpace = Vector3.new(
		0,
		math.max(3.3, modelHeight(model) * 0.55 + 1.2),
		0
	)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Parent = model

	local name = Instance.new("TextLabel")
	name.Name = "EnemyName"
	name.Position = UDim2.fromOffset(2, 0)
	name.Size = UDim2.new(1, -4, 0, 16)
	name.BackgroundTransparency = 1
	name.Text = displayName(model, humanoid)
	name.TextColor3 = model:GetAttribute("IsElite") == true and COLORS.Gold or COLORS.Text
	name.TextStrokeColor3 = Color3.fromRGB(3, 7, 10)
	name.TextStrokeTransparency = 0.28
	name.Font = Enum.Font.GothamBold
	name.TextSize = 11
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "HealthTrack"
	track.Position = UDim2.fromOffset(12, 19)
	track.Size = UDim2.new(1, -24, 0, 8)
	track.BackgroundColor3 = COLORS.Glass
	track.BackgroundTransparency = 0.08
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = billboard
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLORS.Health
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = model:GetAttribute("IsElite") == true and COLORS.Gold or Color3.fromRGB(4, 9, 12)
	stroke.Thickness = model:GetAttribute("IsElite") == true and 1.4 or 1
	stroke.Transparency = 0.12
	stroke.Parent = track

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.Position = UDim2.fromOffset(2, 29)
	healthText.Size = UDim2.new(1, -4, 0, 12)
	healthText.BackgroundTransparency = 1
	healthText.Text = ""
	healthText.TextColor3 = COLORS.Muted
	healthText.TextStrokeTransparency = 0.55
	healthText.Font = Enum.Font.GothamBold
	healthText.TextSize = 8
	healthText.Parent = billboard

	local function update()
		if not humanoid.Parent or humanoid.Health <= 0 then
			billboard.Enabled = false
			return
		end
		local maximum = math.max(1, humanoid.MaxHealth)
		local currentHealth = math.clamp(humanoid.Health, 0, maximum)
		local ratio = currentHealth / maximum
		local importantTarget = model:GetAttribute("IsElite") == true
			or model:GetAttribute("ObjectiveFocusTarget") == true
			or model:GetAttribute("ObjectivePriorityTarget") == true
			or model:GetAttribute("ObjectiveWaypointEscalated") == true
		billboard.Enabled = importantTarget or currentHealth < maximum
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = healthColor(ratio)
		healthText.Text = string.format("%d / %d", math.ceil(currentHealth), math.ceil(maximum))
		name.Text = displayName(model, humanoid)
		name.TextColor3 = model:GetAttribute("IsElite") == true and COLORS.Gold or COLORS.Text
		stroke.Color = model:GetAttribute("IsElite") == true and COLORS.Gold or Color3.fromRGB(4, 9, 12)
	end

	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	model:GetAttributeChangedSignal("DisplayName"):Connect(update)
	model:GetAttributeChangedSignal("IsElite"):Connect(update)
	model:GetAttributeChangedSignal("ObjectiveFocusTarget"):Connect(update)
	model:GetAttributeChangedSignal("ObjectivePriorityTarget"):Connect(update)
	model:GetAttributeChangedSignal("ObjectiveWaypointEscalated"):Connect(update)
	model.Destroying:Connect(function()
		watched[model] = nil
		binding[model] = nil
	end)
	update()
	return true
end

local function queueBindEnemy(instance)
	if typeof(instance) ~= "Instance"
		or not instance:IsA("Model")
		or watched[instance]
		or binding[instance]
	then
		return
	end

	binding[instance] = true
	task.spawn(function()
		local deadline = os.clock() + BIND_RETRY_SECONDS
		repeat
			if bindEnemy(instance) then
				break
			end
			task.wait(BIND_RETRY_INTERVAL)
		until not instance.Parent or os.clock() >= deadline

		binding[instance] = nil
	end)
end

local function damageColor(source, heavy)
	if heavy then return COLORS.Heavy end
	local normalized = string.lower(tostring(source or ""))
	if string.find(normalized, "relic", 1, true)
		or string.find(normalized, "fire", 1, true)
		or string.find(normalized, "lightning", 1, true)
	then
		return COLORS.Relic
	elseif string.find(normalized, "companion", 1, true) then
		return COLORS.Companion
	end
	return COLORS.Damage
end

local function damageNumbersEnabled()
	local value = player:GetAttribute("ClientSetting_DamageNumbers")
	if value == nil then
		value = player:GetAttribute("DungeonHUDDamageNumbersEnabled")
	end
	return value ~= false
end

local function sourceIsCompanion(source)
	return string.find(string.lower(tostring(source or "")), "companion", 1, true) ~= nil
end

local function playHitConfirm(payload)
	if type(payload) ~= "table" or sourceIsCompanion(payload.Source) then
		return
	end

	hitConfirmSerial += 1
	local serial = hitConfirmSerial
	local defeated = payload.Defeated == true
	local heavy = payload.Heavy == true

	hitMarker.Text = defeated and "✦" or "×"
	hitMarker.TextColor3 = defeated and COLORS.Gold or heavy and COLORS.Heavy or COLORS.Damage
	hitMarker.TextSize = defeated and 38 or heavy and 35 or 30
	hitMarker.TextTransparency = 0
	hitMarker.TextStrokeTransparency = 0.12
	hitMarkerScale.Scale = defeated and 0.54 or 0.66

	TweenService:Create(
		hitMarkerScale,
		TweenInfo.new(0.09, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = defeated and 1.26 or heavy and 1.16 or 1 }
	):Play()

	task.delay(HIT_CONFIRM_LIFETIME, function()
		if hitConfirmSerial ~= serial then
			return
		end
		TweenService:Create(
			hitMarker,
			TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}
		):Play()
	end)
end

local function playKillConfirm(payload)
	if type(payload) ~= "table" or payload.Defeated ~= true then
		return
	end
	local target = payload.Target
	if not target or not target:IsA("Model") then
		return
	end

	local humanoid = getHumanoid(target)
	local name = humanoid and displayName(target, humanoid)
		or target:GetAttribute("DisplayName")
		or target:GetAttribute("MonsterId")
		or target.Name
	local elite = target:GetAttribute("IsElite") == true

	killConfirmSerial += 1
	local serial = killConfirmSerial
	killConfirm.Text = elite
		and ("★ ELITE DERROTADO • " .. string.upper(tostring(name)))
		or ("DERROTADO • " .. string.upper(tostring(name)))
	killConfirm.TextColor3 = elite and COLORS.Gold or COLORS.Text
	killConfirm.TextTransparency = 0
	killConfirm.TextStrokeTransparency = 0.14
	killConfirm.Position = UDim2.new(0.5, 0, 0.57, 8)
	killConfirmScale.Scale = 0.84

	TweenService:Create(
		killConfirmScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = elite and 1.08 or 1 }
	):Play()
	TweenService:Create(
		killConfirm,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.57, 0) }
	):Play()

	task.delay(KILL_CONFIRM_LIFETIME * 0.58, function()
		if killConfirmSerial ~= serial then
			return
		end
		TweenService:Create(
			killConfirm,
			TweenInfo.new(KILL_CONFIRM_LIFETIME * 0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.57, -8),
			}
		):Play()
	end)
end

local function playDamageNumber(payload)
	if not damageNumbersEnabled() or type(payload) ~= "table" then return end
	local target = payload.Target
	if not target or not target:IsA("Model") or not target:IsDescendantOf(workspace) then return end

	local root = getRoot(target)
	if not root then return end

	local amount = math.max(0, tonumber(payload.Amount) or 0)
	if amount <= 0 then return end

	hitSerial += 1
	local serial = hitSerial
	local heavy = payload.Heavy == true
	local defeated = payload.Defeated == true
	local source = payload.Source

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LocalDamageNumber"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(122, 54)
	local side = ((serial % 5) - 2) * 0.22
	local startY = math.max(3.4, modelHeight(target) * 0.55 + 1.5)
	billboard.StudsOffsetWorldSpace = Vector3.new(side, startY, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 100
	billboard.Parent = playerGui

	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = defeated
		and string.format("%d!", math.max(1, math.floor(amount + 0.5)))
		or tostring(math.max(1, math.floor(amount + 0.5)))
	text.TextColor3 = defeated and COLORS.Gold or damageColor(source, heavy)
	text.TextStrokeColor3 = Color3.fromRGB(8, 10, 14)
	text.TextStrokeTransparency = 0.10
	text.Font = Enum.Font.GothamBlack
	text.TextSize = defeated and 29 or heavy and 26 or 21
	text.Rotation = ((serial % 3) - 1) * 4
	text.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.62
	scale.Parent = text

	TweenService:Create(
		scale,
		TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.08 }
	):Play()

	TweenService:Create(
		billboard,
		TweenInfo.new(DAMAGE_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(side * 1.6, startY + 2.25, 0) }
	):Play()

	task.delay(0.24, function()
		if not text.Parent then return end
		TweenService:Create(
			text,
			TweenInfo.new(DAMAGE_LIFETIME - 0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		):Play()
	end)

	task.delay(DAMAGE_LIFETIME + 0.05, function()
		if billboard.Parent then billboard:Destroy() end
	end)
end

for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
	queueBindEnemy(model)
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function(instance)
	queueBindEnemy(instance)
end)

CollectionService:GetInstanceRemovedSignal("CombatTarget"):Connect(function(instance)
	watched[instance] = nil
	binding[instance] = nil
end)

feedbackEvent.OnClientEvent:Connect(function(payload)
	if type(payload) == "table"
		and typeof(payload.Target) == "Instance"
		and payload.Target:IsA("Model")
	then
		-- Recuperacao defensiva: se a tag chegou antes dos descendentes do clone,
		-- o primeiro golpe garante uma nova tentativa de criar o indicador.
		queueBindEnemy(payload.Target)
	end
	playHitConfirm(payload)
	playKillConfirm(payload)
	playDamageNumber(payload)
end)

player:SetAttribute("EnemyCombatFeedbackReady", true)
player:SetAttribute("EnemyCombatFeedbackVersion", VERSION)
workspace:SetAttribute("EnemyCombatFeedbackReady", true)
workspace:SetAttribute("EnemyCombatFeedbackPolicy", "FocusedHealthHitConfirmKillFeedbackV2")
