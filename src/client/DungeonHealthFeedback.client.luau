-- HUD-02 — vida, dano, cura, regeneração e proteção
-- Depende do HUD-01 (DungeonUnifiedHUD Cristal Celestial).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUD_NAME = "DungeonUnifiedHUD"
local VERSION = "CrystalCelestialHealthV1"
local CRITICAL_RATIO = 0.30
local DAMAGE_FLASH_SECONDS = 0.34
local HEAL_FLASH_SECONDS = 0.42

local gui = playerGui:WaitForChild(HUD_NAME, 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-02] DungeonUnifiedHUD não encontrado. Instale/aplique HUD-01 antes do HUD-02.")
	return
end

local root = gui:WaitForChild("Root")
local vitals = root:WaitForChild("Vitals")
local health = vitals:WaitForChild("Health")
local healthFill = health:WaitForChild("Fill")
local healthLag = health:FindFirstChild("Lag")
local healthTitle = vitals:WaitForChild("HealthTitle")
local emblem = vitals:FindFirstChild("EmblemGlyph")

local existing = root:FindFirstChild("HealthFeedback")
if existing then existing:Destroy() end

local feedback = Instance.new("Frame")
feedback.Name = "HealthFeedback"
feedback.Size = UDim2.fromScale(1, 1)
feedback.BackgroundTransparency = 1
feedback.ZIndex = 200
feedback.Parent = root

local function edge(name, position, size, rotation)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(255, 48, 62)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 200
	frame.Parent = feedback
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.45, 0.56),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	return frame
end

local damageEdges = {
	edge("DamageTop", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.12), 90),
	edge("DamageBottom", UDim2.fromScale(0, 0.88), UDim2.fromScale(1, 0.12), 270),
	edge("DamageLeft", UDim2.fromScale(0, 0), UDim2.fromScale(0.085, 1), 0),
	edge("DamageRight", UDim2.fromScale(0.915, 0), UDim2.fromScale(0.085, 1), 180),
}

local healGlow = Instance.new("Frame")
healGlow.Name = "HealGlow"
healGlow.Size = UDim2.fromScale(1, 1)
healGlow.BackgroundColor3 = Color3.fromRGB(77, 255, 162)
healGlow.BackgroundTransparency = 1
healGlow.BorderSizePixel = 0
healGlow.ZIndex = 199
healGlow.Parent = feedback

local delta = Instance.new("TextLabel")
delta.Name = "HealthDelta"
delta.AnchorPoint = Vector2.new(0, 1)
delta.Position = UDim2.new(0, 154, 1, -180)
delta.Size = UDim2.fromOffset(260, 46)
delta.BackgroundTransparency = 1
delta.Text = ""
delta.TextTransparency = 1
delta.TextStrokeColor3 = Color3.fromRGB(8, 12, 20)
delta.TextStrokeTransparency = 0.28
delta.Font = Enum.Font.GothamBlack
delta.TextSize = 26
delta.TextXAlignment = Enum.TextXAlignment.Left
delta.ZIndex = 205
delta.Parent = feedback

local stateChip = Instance.new("Frame")
stateChip.Name = "HealthStateChip"
stateChip.AnchorPoint = Vector2.new(0, 1)
stateChip.Position = UDim2.new(0, 152, 1, -157)
stateChip.Size = UDim2.fromOffset(300, 30)
stateChip.BackgroundColor3 = Color3.fromRGB(16, 30, 45)
stateChip.BackgroundTransparency = 0.12
stateChip.BorderSizePixel = 0
stateChip.Visible = false
stateChip.ZIndex = 205
stateChip.Parent = feedback
local chipCorner = Instance.new("UICorner")
chipCorner.CornerRadius = UDim.new(0, 9)
chipCorner.Parent = stateChip
local chipStroke = Instance.new("UIStroke")
chipStroke.Color = Color3.fromRGB(102, 222, 255)
chipStroke.Transparency = 0.28
chipStroke.Thickness = 1.2
chipStroke.Parent = stateChip

local chipIcon = Instance.new("TextLabel")
chipIcon.Position = UDim2.fromOffset(7, 0)
chipIcon.Size = UDim2.fromOffset(26, 30)
chipIcon.BackgroundTransparency = 1
chipIcon.Text = "✦"
chipIcon.TextColor3 = Color3.fromRGB(143, 235, 255)
chipIcon.Font = Enum.Font.GothamBold
chipIcon.TextSize = 14
chipIcon.ZIndex = 206
chipIcon.Parent = stateChip

local chipText = Instance.new("TextLabel")
chipText.Position = UDim2.fromOffset(34, 0)
chipText.Size = UDim2.new(1, -41, 1, 0)
chipText.BackgroundTransparency = 1
chipText.Text = ""
chipText.TextColor3 = Color3.fromRGB(235, 248, 255)
chipText.Font = Enum.Font.GothamBold
chipText.TextSize = 11
chipText.TextXAlignment = Enum.TextXAlignment.Left
chipText.ZIndex = 206
chipText.Parent = stateChip

local lastHealth
local lastMaxHealth
local lastHealAt = tonumber(player:GetAttribute("DungeonLastHealAt")) or 0
local flashSerial = 0
local criticalTween
local boundHumanoid
local connections = {}

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function disconnectCharacter()
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	boundHumanoid = nil
end

local function pulseDelta(text, color)
	flashSerial += 1
	local serial = flashSerial
	delta.Text = text
	delta.TextColor3 = color
	delta.TextTransparency = 0
	delta.Position = UDim2.new(0, 154, 1, -170)
	TweenService:Create(delta, TweenInfo.new(0.46, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 154, 1, -196),
	}):Play()
	task.delay(0.48, function()
		if flashSerial ~= serial then return end
		TweenService:Create(delta, TweenInfo.new(0.22), {TextTransparency = 1}):Play()
	end)
end

local function flashDamage(amount, maxHealth)
	local intensity = math.clamp((amount / math.max(1, maxHealth)) * 3.5, 0.16, 0.58)
	for _, frame in ipairs(damageEdges) do
		frame.BackgroundTransparency = 1 - intensity
		TweenService:Create(frame, TweenInfo.new(DAMAGE_FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end
	pulseDelta("-" .. tostring(math.max(1, math.floor(amount + 0.5))), Color3.fromRGB(255, 104, 112))
end

local function flashHeal(amount)
	healGlow.BackgroundTransparency = 0.91
	TweenService:Create(healGlow, TweenInfo.new(HEAL_FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	pulseDelta("+" .. tostring(math.max(1, math.floor(amount + 0.5))), Color3.fromRGB(102, 255, 167))
end

local function updateCritical(ratio)
	local critical = ratio > 0 and ratio <= CRITICAL_RATIO
	player:SetAttribute("DungeonHUDHealthCritical", critical)
	if critical and not criticalTween then
		healthTitle.Text = "VIDA CRÍTICA"
		healthTitle.TextColor3 = Color3.fromRGB(255, 106, 116)
		criticalTween = TweenService:Create(healthFill, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = 0.28,
		})
		criticalTween:Play()
	elseif not critical and criticalTween then
		criticalTween:Cancel()
		criticalTween = nil
		healthFill.BackgroundTransparency = 0
		healthTitle.Text = "VIDA"
		healthTitle.TextColor3 = Color3.fromRGB(242, 247, 252)
	end
end

local function stateLabel()
	local now = serverTime()
	local entryUntil = tonumber(player:GetAttribute("DungeonEntryProtectionUntil")) or 0
	local rescueUntil = tonumber(player:GetAttribute("SanctuaryRescueProtectionUntil")) or 0
	local respawnUntil = tonumber(player:GetAttribute("RespawnProtectionUntil")) or 0
	local protectionUntil = math.max(entryUntil, rescueUntil, respawnUntil)

	if protectionUntil > now then
		return "◆", string.format("PROTEGIDO • %ds", math.ceil(protectionUntil - now)), Color3.fromRGB(255, 221, 128)
	end
	if player:GetAttribute("DungeonHealthRegenerating") == true then
		return "+", "REGENERANDO VIDA", Color3.fromRGB(92, 239, 151)
	end
	local regenAt = tonumber(player:GetAttribute("DungeonHealthRegenStartsAt")) or 0
	if regenAt > now and boundHumanoid and boundHumanoid.Health < boundHumanoid.MaxHealth then
		return "◇", string.format("REGENERAÇÃO EM %ds", math.ceil(regenAt - now)), Color3.fromRGB(126, 220, 255)
	end
	if player:GetAttribute("DungeonHUDHealthCritical") == true then
		return "!", "VIDA CRÍTICA", Color3.fromRGB(255, 105, 115)
	end
	return nil
end

local function refreshStateChip()
	local icon, text, color = stateLabel()
	stateChip.Visible = text ~= nil
	if text then
		chipIcon.Text = icon
		chipIcon.TextColor3 = color
		chipText.Text = text
		chipStroke.Color = color
	end
end

local function refreshProtectionVisual()
	local protected = stateLabel()
	if protected and string.find(select(2, stateLabel()) or "", "PROTEGIDO", 1, true) then
		if emblem and emblem:IsA("TextLabel") then
			emblem.TextColor3 = Color3.fromRGB(255, 226, 145)
		end
	else
		if emblem and emblem:IsA("TextLabel") then
			emblem.TextColor3 = Color3.fromRGB(183, 239, 255)
		end
	end
end

local function onHealthChanged(value)
	if not boundHumanoid then return end
	local current = math.max(0, tonumber(value) or boundHumanoid.Health)
	local maximum = math.max(1, boundHumanoid.MaxHealth)
	if lastHealth ~= nil then
		local change = current - lastHealth
		if change < -0.25 then
			flashDamage(-change, maximum)
			player:SetAttribute("DungeonHUDLastDamageFeedbackAt", serverTime())
			player:SetAttribute("DungeonHUDLastDamageFeedbackAmount", -change)
		elseif change > 0.25 then
			flashHeal(change)
			player:SetAttribute("DungeonHUDLastHealFeedbackAt", serverTime())
			player:SetAttribute("DungeonHUDLastHealFeedbackAmount", change)
		end
	end
	lastHealth = current
	lastMaxHealth = maximum
	updateCritical(current / maximum)
	refreshStateChip()
end

local function bindCharacter(character)
	disconnectCharacter()
	boundHumanoid = character:WaitForChild("Humanoid", 10)
	if not boundHumanoid then return end
	lastHealth = boundHumanoid.Health
	lastMaxHealth = boundHumanoid.MaxHealth
	updateCritical(lastHealth / math.max(1, lastMaxHealth))
	table.insert(connections, boundHumanoid.HealthChanged:Connect(onHealthChanged))
	table.insert(connections, boundHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		lastMaxHealth = boundHumanoid.MaxHealth
		onHealthChanged(boundHumanoid.Health)
	end))
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then task.defer(bindCharacter, player.Character) end

for _, attributeName in ipairs({
	"DungeonHealthRegenerating",
	"DungeonHealthRegenStartsAt",
	"DungeonEntryProtectionUntil",
	"DungeonEntryProtectionActive",
	"SanctuaryRescueProtectionUntil",
	"RespawnProtectionUntil",
	"RespawnProtectionActive",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(function()
		refreshStateChip()
		refreshProtectionVisual()
	end)
end

player:GetAttributeChangedSignal("DungeonLastHealAt"):Connect(function()
	local at = tonumber(player:GetAttribute("DungeonLastHealAt")) or 0
	if at > lastHealAt then
		lastHealAt = at
		local reason = tostring(player:GetAttribute("DungeonLastHealReason") or "Cura")
		local amount = tonumber(player:GetAttribute("DungeonLastHealAmount")) or 0
		player:SetAttribute("DungeonHUDLastServerHealReason", reason)
		player:SetAttribute("DungeonHUDLastServerHealAmount", amount)
	end
end)

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local nowClock = os.clock()
	if nowClock < nextUpdate then return end
	nextUpdate = nowClock + 0.10
	refreshStateChip()
	refreshProtectionVisual()
end)

gui:SetAttribute("HealthFeedbackVersion", VERSION)
player:SetAttribute("DungeonHUDHealthFeedbackReady", true)
player:SetAttribute("DungeonHUDHealthFeedbackVersion", VERSION)
workspace:SetAttribute("DungeonHUDHealthFeedbackReady", true)
workspace:SetAttribute("DungeonHUDHealthFeedbackPolicy", "DamageHealRegenProtectionV1")
