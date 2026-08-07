-- HUD-03 — stamina, corrida, agachamento, asa, capa e cooldowns
-- Camada visual sobre o HUD-01/HUD-02. Não substitui controladores de gameplay.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "CrystalCelestialMobilityV1"
local HUD_NAME = "DungeonUnifiedHUD"
local UPDATE_INTERVAL = 0.10
local LOW_STAMINA_RATIO = 0.22

local gui = playerGui:WaitForChild(HUD_NAME, 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-03] HUD-01 não encontrado.")
	return
end

local root = gui:WaitForChild("Root")
local vitals = root:WaitForChild("Vitals")
local staminaBar = vitals:WaitForChild("Stamina")
local staminaFill = staminaBar:WaitForChild("Fill")
local staminaValue = vitals:WaitForChild("StaminaValue")
local staminaTitle = vitals:WaitForChild("StaminaTitle")

local existing = root:FindFirstChild("MobilityAbilities")
if existing then existing:Destroy() end

local panel = Instance.new("Frame")
panel.Name = "MobilityAbilities"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 22, 1, -180)
panel.Size = UDim2.fromOffset(500, 64)
panel.BackgroundColor3 = Color3.fromRGB(13, 25, 40)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.ZIndex = 25
panel.Parent = root
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 15)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(221, 186, 104)
panelStroke.Transparency = 0.28
panelStroke.Thickness = 1.2
panelStroke.Parent = panel

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 52, 70)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(13, 25, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 23, 48)),
})
gradient.Rotation = 10
gradient.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 7)
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.PaddingTop = UDim.new(0, 7)
padding.PaddingBottom = UDim.new(0, 7)
padding.Parent = panel

local function createCard(name, glyph, title)
	local card = Instance.new("Frame")
	card.Name = name
	card.Size = UDim2.fromOffset(88, 50)
	card.BackgroundColor3 = Color3.fromRGB(17, 37, 53)
	card.BackgroundTransparency = 0.14
	card.BorderSizePixel = 0
	card.ZIndex = 26
	card.Parent = panel
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 11)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(97, 214, 245)
	stroke.Transparency = 0.52
	stroke.Thickness = 1
	stroke.Parent = card

	local icon = Instance.new("TextLabel")
	icon.Name = "Glyph"
	icon.Position = UDim2.fromOffset(4, 3)
	icon.Size = UDim2.fromOffset(30, 28)
	icon.BackgroundTransparency = 1
	icon.Text = glyph
	icon.TextColor3 = Color3.fromRGB(179, 239, 255)
	icon.Font = Enum.Font.GothamBlack
	icon.TextSize = 17
	icon.ZIndex = 27
	icon.Parent = card

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Position = UDim2.fromOffset(32, 4)
	label.Size = UDim2.new(1, -36, 0, 20)
	label.BackgroundTransparency = 1
	label.Text = title
	label.TextColor3 = Color3.fromRGB(224, 235, 246)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 8
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 27
	label.Parent = card

	local state = Instance.new("TextLabel")
	state.Name = "State"
	state.Position = UDim2.fromOffset(5, 27)
	state.Size = UDim2.new(1, -10, 0, 18)
	state.BackgroundTransparency = 1
	state.Text = "PRONTO"
	state.TextColor3 = Color3.fromRGB(130, 238, 183)
	state.Font = Enum.Font.GothamBold
	state.TextSize = 8
	state.TextXAlignment = Enum.TextXAlignment.Center
	state.TextTruncate = Enum.TextTruncate.AtEnd
	state.ZIndex = 27
	state.Parent = card

	return {
		Card = card,
		Stroke = stroke,
		Glyph = icon,
		Title = label,
		State = state,
	}
end

local sprintCard = createCard("Sprint", "»", "CORRIDA")
local sneakCard = createCard("Sneak", "◢", "AGACHAR")
local wingCard = createCard("Wing", "✦", "ASA")
local capeCard = createCard("Cape", "◐", "CAPA")
local abilityCard = createCard("Ability", "◆", "HABILIDADE")

local character
local lowStaminaTween

local function now()
	return workspace:GetServerTimeNow()
end

local function numberAttribute(instance, names)
	if not instance then return nil end
	for _, name in ipairs(names) do
		local value = instance:GetAttribute(name)
		if typeof(value) == "number" then
			return value
		end
	end
	return nil
end

local function boolAttribute(instance, names)
	if not instance then return false end
	for _, name in ipairs(names) do
		if instance:GetAttribute(name) == true then
			return true
		end
	end
	return false
end

local function stringAttribute(instance, names)
	if not instance then return nil end
	for _, name in ipairs(names) do
		local value = instance:GetAttribute(name)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

local function setCard(record, active, text, color)
	record.State.Text = text
	record.State.TextColor3 = color
	record.Stroke.Color = color
	record.Stroke.Transparency = active and 0.12 or 0.58
	record.Card.BackgroundTransparency = active and 0.04 or 0.16
end

local function hideLegacyStamina(instance)
	if instance:IsA("ScreenGui") and instance.Name == "SprintStaminaGui" then
		instance.Enabled = false
		instance:SetAttribute("SuppressedByHUD03", true)
	end
end

for _, child in ipairs(playerGui:GetChildren()) do
	hideLegacyStamina(child)
end
playerGui.ChildAdded:Connect(hideLegacyStamina)

local function refreshStamina()
	if not character then
		staminaValue.Text = "-- / --"
		staminaBar.Visible = false
		return
	end
	local maximum = numberAttribute(character, { "SprintStaminaMax", "StaminaMax" })
	local current = numberAttribute(character, { "SprintStamina", "Stamina" })
	if not maximum or maximum <= 0 or not current then
		staminaValue.Text = "-- / --"
		staminaBar.Visible = false
		return
	end

	staminaBar.Visible = true
	current = math.clamp(current, 0, maximum)
	local ratio = current / maximum
	staminaValue.Text = string.format("%d / %d", math.floor(current + 0.5), math.floor(maximum + 0.5))
	staminaFill.Size = UDim2.fromScale(ratio, 1)

	local low = ratio <= LOW_STAMINA_RATIO
	if low and not lowStaminaTween then
		staminaTitle.Text = "STAMINA BAIXA"
		staminaTitle.TextColor3 = Color3.fromRGB(255, 196, 103)
		lowStaminaTween = TweenService:Create(
			staminaFill,
			TweenInfo.new(0.48, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.32 }
		)
		lowStaminaTween:Play()
	elseif not low and lowStaminaTween then
		lowStaminaTween:Cancel()
		lowStaminaTween = nil
		staminaFill.BackgroundTransparency = 0
		staminaTitle.Text = "STAMINA"
		staminaTitle.TextColor3 = Color3.fromRGB(242, 247, 252)
	end

	local sprinting = character:GetAttribute("Sprinting") == true
	if sprinting then
		setCard(sprintCard, true, "CORRENDO", Color3.fromRGB(92, 236, 178))
	elseif low then
		setCard(sprintCard, false, "RECUPERANDO", Color3.fromRGB(255, 196, 103))
	else
		setCard(sprintCard, false, "PRONTO", Color3.fromRGB(140, 215, 238))
	end
end

local function refreshSneak()
	local crouching = character and character:GetAttribute("Crouching") == true
	if crouching then
		setCard(sneakCard, true, "AGACHADO", Color3.fromRGB(105, 236, 184))
	else
		setCard(sneakCard, false, "PRONTO", Color3.fromRGB(150, 210, 226))
	end
end

local function durationState(active, untilAt, activeText, readyText)
	local t = now()
	if active and untilAt and untilAt > t then
		return true, string.format("%s %ds", activeText, math.ceil(untilAt - t))
	elseif active then
		return true, activeText
	elseif untilAt and untilAt > t then
		return false, string.format("%ds", math.ceil(untilAt - t))
	end
	return false, readyText
end

local function refreshWing()
	local active = boolAttribute(player, { "WingActive", "Flying" })
		or boolAttribute(character, { "WingActive", "Flying" })
	local untilAt = numberAttribute(player, { "WingActiveUntil", "WingUntil" })
		or numberAttribute(character, { "WingActiveUntil", "WingUntil" })
	local available = player:GetAttribute("CanFly") == true
		or stringAttribute(player, { "EquippedWingId", "WingId" }) ~= nil
		or active

	if not available then
		setCard(wingCard, false, "NÃO EQUIPADA", Color3.fromRGB(120, 133, 151))
		return
	end
	local on, text = durationState(active, untilAt, "VOANDO", "PRONTA")
	setCard(wingCard, on, text, on and Color3.fromRGB(113, 222, 255) or Color3.fromRGB(158, 223, 239))
end

local function refreshCape()
	local active = boolAttribute(player, { "InvisibleToEnemies", "CapeActive" })
		or boolAttribute(character, { "InvisibleToEnemies", "CapeActive" })
	local untilAt = numberAttribute(player, { "CapeActiveUntil", "InvisibilityUntil" })
		or numberAttribute(character, { "CapeActiveUntil", "InvisibilityUntil" })
	local equipped = stringAttribute(player, { "EquippedCapeId", "CapeId" }) ~= nil or active or untilAt ~= nil

	if not equipped then
		setCard(capeCard, false, "NÃO EQUIPADA", Color3.fromRGB(120, 133, 151))
		return
	end
	local on, text = durationState(active, untilAt, "INVISÍVEL", "PRONTA")
	setCard(capeCard, on, text, on and Color3.fromRGB(203, 145, 255) or Color3.fromRGB(193, 180, 235))
end

local function resolveAbilitySlot(slot)
	local id = stringAttribute(player, {
		"EquippedAbility" .. slot,
		"AbilitySlot" .. slot,
		"Ability" .. slot .. "Id",
	})
	if not id then
		return nil
	end

	local untilAt = numberAttribute(player, {
		"Ability" .. slot .. "CooldownUntil",
		"AbilitySlot" .. slot .. "CooldownUntil",
		id .. "CooldownUntil",
	})
	return id, untilAt
end

local function refreshAbility()
	local firstId, firstUntil = resolveAbilitySlot(1)
	local secondId, secondUntil = resolveAbilitySlot(2)
	local id, untilAt = firstId, firstUntil
	if secondId and secondUntil and (not untilAt or secondUntil > untilAt) then
		id, untilAt = secondId, secondUntil
	end

	if not id then
		setCard(abilityCard, false, "SEM HABILIDADE", Color3.fromRGB(120, 133, 151))
		return
	end

	abilityCard.Title.Text = string.upper(string.sub(id, 1, 12))
	if untilAt and untilAt > now() then
		setCard(abilityCard, false, string.format("%ds", math.ceil(untilAt - now())), Color3.fromRGB(255, 190, 105))
	else
		setCard(abilityCard, true, "PRONTA", Color3.fromRGB(120, 236, 199))
	end
end

local function refreshBlockedState()
	local blocked = player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonLifeState") == "Eliminated"
		or (character and character:GetAttribute("MovementLocked") == true)
	if blocked then
		for _, record in ipairs({ sprintCard, sneakCard, wingCard, capeCard, abilityCard }) do
			record.Card.BackgroundTransparency = 0.48
			record.State.TextColor3 = Color3.fromRGB(132, 140, 154)
		end
	end
end

local function bindCharacter(newCharacter)
	character = newCharacter
	task.defer(function()
		refreshStamina()
		refreshSneak()
		refreshWing()
		refreshCape()
	end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	refreshStamina()
	refreshSneak()
	refreshWing()
	refreshCape()
	refreshAbility()
	refreshBlockedState()
end)

gui:SetAttribute("MobilityAbilitiesVersion", VERSION)
player:SetAttribute("DungeonHUDMobilityReady", true)
player:SetAttribute("DungeonHUDMobilityVersion", VERSION)
workspace:SetAttribute("DungeonHUDMobilityReady", true)
workspace:SetAttribute("DungeonHUDMobilityPolicy", "SprintSneakWingCapeAbilitiesV1")
