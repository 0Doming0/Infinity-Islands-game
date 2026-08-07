-- HUD-11 — configurações, acessibilidade e áudio.
-- Funciona nos dois Places e aplica apenas efeitos locais.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SettingsConfig = require(ReplicatedStorage.Shared.Configs.SettingsConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local request = RemoteRegistry.Get("Settings", "Request", "RemoteFunction")
local event = RemoteRegistry.Get("Settings", "Event", "RemoteEvent")

local VERSION = "CrystalCelestialSettingsV1"

local COLORS = {
	Glass = Color3.fromRGB(12, 26, 42),
	GlassRaised = Color3.fromRGB(22, 47, 64),
	Text = Color3.fromRGB(240, 247, 252),
	Muted = Color3.fromRGB(150, 179, 202),
	Cyan = Color3.fromRGB(108, 226, 255),
	CyanSoft = Color3.fromRGB(184, 243, 255),
	Gold = Color3.fromRGB(232, 195, 104),
	GoldSoft = Color3.fromRGB(255, 225, 143),
	Green = Color3.fromRGB(100, 236, 163),
	Orange = Color3.fromRGB(255, 184, 92),
	Red = Color3.fromRGB(255, 105, 117),
}

local current = SettingsConfig.CloneDefaults()
local busy = false
local applyingSound = setmetatable({}, { __mode = "k" })
local baseVolumes = setmetatable({}, { __mode = "k" })
local soundConnections = setmetatable({}, { __mode = "k" })
local baseTextSizes = setmetatable({}, { __mode = "k" })
local baseStrokeValues = setmetatable({}, { __mode = "k" })

local gui = Instance.new("ScreenGui")
gui.Name = "SkySettingsUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 450
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "SettingsButton"
button.Size = UDim2.fromOffset(44, 38)
button.BackgroundColor3 = COLORS.GlassRaised
button.BackgroundTransparency = 0.06
button.BorderSizePixel = 0
button.Text = "⚙"
button.TextColor3 = COLORS.CyanSoft
button.Font = Enum.Font.GothamBold
button.TextSize = 18
button.ZIndex = 20
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = COLORS.Gold
buttonStroke.Transparency = 0.38
buttonStroke.Parent = button

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(3, 8, 15)
overlay.BackgroundTransparency = 0.30
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.ZIndex = 100
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(620, 590)
panel.BackgroundColor3 = COLORS.Glass
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0
panel.ZIndex = 101
panel.Parent = overlay
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Gold
panelStroke.Transparency = 0.15
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(20, 12)
title.Size = UDim2.new(1, -78, 0, 34)
title.BackgroundTransparency = 1
title.Text = "CONFIGURAÇÕES"
title.TextColor3 = COLORS.GoldSoft
title.Font = Enum.Font.GothamBlack
title.TextSize = 19
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 102
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(21, 43)
subtitle.Size = UDim2.new(1, -80, 0, 20)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Áudio, legibilidade e quantidade de informação na tela."
subtitle.TextColor3 = COLORS.Muted
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 9
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 102
subtitle.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -13, 0, 12)
close.Size = UDim2.fromOffset(40, 36)
close.BackgroundColor3 = Color3.fromRGB(51, 58, 69)
close.BackgroundTransparency = 0.04
close.BorderSizePixel = 0
close.Text = "×"
close.TextColor3 = COLORS.Text
close.Font = Enum.Font.GothamBold
close.TextSize = 19
close.ZIndex = 103
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)

local content = Instance.new("ScrollingFrame")
content.Position = UDim2.fromOffset(18, 76)
content.Size = UDim2.new(1, -36, 1, -136)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 5
content.ScrollBarImageColor3 = COLORS.Cyan
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.ZIndex = 102
content.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = content

local footer = Instance.new("TextLabel")
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 18, 1, -13)
footer.Size = UDim2.new(1, -170, 0, 30)
footer.BackgroundTransparency = 1
footer.Text = "CARREGANDO PREFERÊNCIAS..."
footer.TextColor3 = COLORS.Muted
footer.Font = Enum.Font.GothamBold
footer.TextSize = 8
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.ZIndex = 102
footer.Parent = panel

local reset = Instance.new("TextButton")
reset.AnchorPoint = Vector2.new(1, 1)
reset.Position = UDim2.new(1, -18, 1, -13)
reset.Size = UDim2.fromOffset(142, 32)
reset.BackgroundColor3 = Color3.fromRGB(61, 46, 38)
reset.BackgroundTransparency = 0.04
reset.BorderSizePixel = 0
reset.Text = "RESTAURAR PADRÃO"
reset.TextColor3 = COLORS.GoldSoft
reset.Font = Enum.Font.GothamBold
reset.TextSize = 8
reset.ZIndex = 103
reset.Parent = panel
Instance.new("UICorner", reset).CornerRadius = UDim.new(0, 9)

local rows = {}

local function section(text)
	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(1, -5, 0, 28)
	value.BackgroundTransparency = 1
	value.Text = text
	value.TextColor3 = COLORS.GoldSoft
	value.Font = Enum.Font.GothamBlack
	value.TextSize = 10
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.ZIndex = 103
	value.Parent = content
	return value
end

local function makeRow(key, name, description)
	local row = Instance.new("Frame")
	row.Name = key
	row.Size = UDim2.new(1, -6, 0, 68)
	row.BackgroundColor3 = COLORS.GlassRaised
	row.BackgroundTransparency = 0.07
	row.BorderSizePixel = 0
	row.ZIndex = 103
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Cyan
	stroke.Transparency = 0.58
	stroke.Parent = row

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(12, 7)
	label.Size = UDim2.new(1, -190, 0, 22)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = COLORS.Text
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 104
	label.Parent = row

	local detail = Instance.new("TextLabel")
	detail.Position = UDim2.fromOffset(12, 29)
	detail.Size = UDim2.new(1, -190, 0, 30)
	detail.BackgroundTransparency = 1
	detail.Text = description
	detail.TextColor3 = COLORS.Muted
	detail.Font = Enum.Font.GothamMedium
	detail.TextSize = 8
	detail.TextWrapped = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.ZIndex = 104
	detail.Parent = row

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -11, 0.5, 0)
	action.Size = UDim2.fromOffset(158, 42)
	action.BackgroundColor3 = Color3.fromRGB(29, 70, 83)
	action.BackgroundTransparency = 0.03
	action.BorderSizePixel = 0
	action.Text = "--"
	action.TextColor3 = COLORS.CyanSoft
	action.Font = Enum.Font.GothamBlack
	action.TextSize = 9
	action.ZIndex = 104
	action.Parent = row
	Instance.new("UICorner", action).CornerRadius = UDim.new(0, 10)

	rows[key] = {
		Frame = row,
		Stroke = stroke,
		Action = action,
	}
	return action
end

section("ÁUDIO")
makeRow("MasterVolume", "Volume geral", "Controla todo o áudio do jogo neste dispositivo.")
makeRow("MusicVolume", "Música e ambiente", "Reduz somente músicas, temas e sons ambientes contínuos.")
makeRow("SFXVolume", "Efeitos sonoros", "Combate, interface, impactos, recompensas e outros efeitos.")

section("ACESSIBILIDADE")
makeRow("HighContrast", "Alto contraste", "Reforça bordas e separação dos painéis para melhorar leitura.")
makeRow("TextScale", "Tamanho do texto", "Aumenta ou reduz textos do HUD sem mudar a lógica do jogo.")
makeRow("ReducedEffects", "Reduzir efeitos do HUD", "Remove flashes cosméticos de dano/cura, mantendo avisos críticos do boss.")
makeRow("DamageNumbers", "Números de dano e cura", "Mostra ou esconde os números flutuantes próximos à barra de vida.")

section("INFORMAÇÃO NA TELA")
makeRow("ObjectiveHints", "Dicas dos objetivos", "Mostra explicações extras de farol, ninhos, guardas, elite e outras mecânicas.")
makeRow("WorldMarkers", "Marcadores no mundo", "Mostra caminhos, aliados caídos e outros marcadores de navegação do HUD.")

local VOLUME_OPTIONS = { 0, 0.25, 0.50, 0.75, 1.00 }
local TEXT_OPTIONS = { "Small", "Normal", "Large" }
local TEXT_LABELS = {
	Small = "PEQUENO",
	Normal = "NORMAL",
	Large = "GRANDE",
}

local function nextIn(list, value)
	local currentIndex = table.find(list, value) or 0
	return list[(currentIndex % #list) + 1]
end

local function displayValue(key, value)
	if key == "MasterVolume" or key == "MusicVolume" or key == "SFXVolume" then
		return string.format("%d%%", math.floor((tonumber(value) or 0) * 100 + 0.5))
	elseif key == "TextScale" then
		return TEXT_LABELS[tostring(value)] or "NORMAL"
	end
	return value == true and "ATIVADO" or "DESATIVADO"
end

local function updateRow(key)
	local row = rows[key]
	if not row then return end
	local value = current[key]
	row.Action.Text = displayValue(key, value)
	local enabled = value == true
	if key == "MasterVolume" or key == "MusicVolume" or key == "SFXVolume" or key == "TextScale" then
		row.Action.TextColor3 = COLORS.CyanSoft
		row.Stroke.Color = COLORS.Cyan
	elseif enabled then
		row.Action.TextColor3 = COLORS.Green
		row.Stroke.Color = COLORS.Green
	else
		row.Action.TextColor3 = COLORS.Muted
		row.Stroke.Color = COLORS.Muted
	end
end

local function categoryForSound(sound)
	local group = sound.SoundGroup
	local groupName = group and string.lower(group.Name) or ""
	local path = string.lower(sound:GetFullName())
	local name = string.lower(sound.Name)

	local musicTerms = { "music", "bgm", "theme", "ambient", "ambience", "trilha" }
	for _, term in ipairs(musicTerms) do
		if string.find(groupName, term, 1, true)
			or string.find(name, term, 1, true)
			or string.find(path, term, 1, true)
		then
			return "Music"
		end
	end
	return "SFX"
end

local function soundMultiplier(sound)
	local master = tonumber(current.MasterVolume) or 1
	if categoryForSound(sound) == "Music" then
		return master * (tonumber(current.MusicVolume) or 1)
	end
	return master * (tonumber(current.SFXVolume) or 1)
end

local function applySound(sound)
	if not sound:IsA("Sound") then return end
	if baseVolumes[sound] == nil then
		baseVolumes[sound] = sound.Volume
	end
	applyingSound[sound] = true
	sound.Volume = math.clamp((baseVolumes[sound] or sound.Volume) * soundMultiplier(sound), 0, 10)
	applyingSound[sound] = nil
end

local function watchSound(sound)
	if not sound:IsA("Sound") or soundConnections[sound] then return end
	baseVolumes[sound] = sound.Volume
	soundConnections[sound] = sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if applyingSound[sound] then return end
		local multiplier = soundMultiplier(sound)
		if multiplier <= 0.001 then
			baseVolumes[sound] = sound.Volume
		else
			baseVolumes[sound] = sound.Volume / multiplier
		end
		applySound(sound)
	end)
	applySound(sound)
end

local function scanSounds(container)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Sound") then watchSound(descendant) end
	end
end

local function relevantGuiObject(instance)
	local ancestor = instance
	while ancestor do
		if ancestor:IsA("ScreenGui") then
			return ancestor.Name == "DungeonUnifiedHUD"
				or ancestor.Name == "LobbyUI"
				or ancestor.Name == "PartyUI"
				or ancestor.Name == "SkySettingsUI"
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function applyTextAndContrast(instance)
	if not relevantGuiObject(instance) then return end

	if (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
		and not instance.TextScaled
	then
		if baseTextSizes[instance] == nil then
			baseTextSizes[instance] = instance.TextSize
		end
		local scaleName = tostring(current.TextScale or "Normal")
		local factor = SettingsConfig.TextScaleValues[scaleName] or 1
		instance.TextSize = math.max(7, math.floor((baseTextSizes[instance] or instance.TextSize) * factor + 0.5))
	elseif instance:IsA("UIStroke") then
		if baseStrokeValues[instance] == nil then
			baseStrokeValues[instance] = {
				Thickness = instance.Thickness,
				Transparency = instance.Transparency,
			}
		end
		local base = baseStrokeValues[instance]
		if current.HighContrast == true then
			instance.Thickness = math.max(base.Thickness, base.Thickness * 1.35)
			instance.Transparency = math.max(0, base.Transparency - 0.22)
		else
			instance.Thickness = base.Thickness
			instance.Transparency = base.Transparency
		end
	end
end

local function setBillboardsEnabled(container, enabled)
	if not container then return end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BillboardGui") then
			descendant.Enabled = enabled
		end
	end
end

local function applyDungeonPreferences()
	local dungeon = playerGui:FindFirstChild("DungeonUnifiedHUD")
	if not dungeon then return end
	local hudRoot = dungeon:FindFirstChild("Root")
	if not hudRoot then return end

	local feedback = hudRoot:FindFirstChild("HealthFeedback")
	if feedback then
		for _, name in ipairs({ "DamageTop", "DamageBottom", "DamageLeft", "DamageRight", "HealGlow" }) do
			local visual = feedback:FindFirstChild(name)
			if visual and visual:IsA("GuiObject") then
				visual.Visible = current.ReducedEffects ~= true
			end
		end
		local delta = feedback:FindFirstChild("HealthDelta")
		if delta and delta:IsA("GuiObject") then
			delta.Visible = current.DamageNumbers == true
		end
	end

	local objectiveContext = hudRoot:FindFirstChild("ObjectiveContext")
	if objectiveContext then
		local detail = objectiveContext:FindFirstChild("MechanicDetail")
		if detail and detail:IsA("GuiObject") then
			detail.Visible = current.ObjectiveHints == true
		end
	end

	local routeMarkers = playerGui:FindFirstChild("DungeonRouteWorldMarkers")
	setBillboardsEnabled(routeMarkers, current.WorldMarkers == true)

	local partyLife = dungeon:FindFirstChild("PartyLifeWorldMarkers", true)
	setBillboardsEnabled(partyLife, current.WorldMarkers == true)
end

local function publishLocalAttributes()
	for key, value in pairs(current) do
		player:SetAttribute("ClientSetting_" .. key, value)
	end
	player:SetAttribute("DungeonHUDReducedEffects", current.ReducedEffects == true)
	player:SetAttribute("DungeonHUDWorldMarkersEnabled", current.WorldMarkers == true)
	player:SetAttribute("DungeonHUDObjectiveHintsEnabled", current.ObjectiveHints == true)
	player:SetAttribute("DungeonHUDDamageNumbersEnabled", current.DamageNumbers == true)
end

local function applyAll()
	publishLocalAttributes()

	for sound in pairs(baseVolumes) do
		if sound.Parent then applySound(sound) end
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		applyTextAndContrast(descendant)
	end

	applyDungeonPreferences()

	for key in pairs(rows) do updateRow(key) end
end

local function mergeSettings(settings)
	if type(settings) ~= "table" then return end
	current = SettingsConfig.Sanitize(settings)
	applyAll()
end

local function setPreference(key, value)
	if busy then return end
	busy = true
	footer.Text = "SALVANDO..."
	footer.TextColor3 = COLORS.Orange

	local ok, result = pcall(function()
		return request:InvokeServer("Set", {
			Key = key,
			Value = value,
		})
	end)

	busy = false
	if not ok or type(result) ~= "table" then
		footer.Text = "SERVIÇO DE CONFIGURAÇÕES INDISPONÍVEL"
		footer.TextColor3 = COLORS.Red
		return
	end

	if result.Snapshot and result.Snapshot.Settings then
		mergeSettings(result.Snapshot.Settings)
	end
	if result.Success then
		footer.Text = "ALTERAÇÃO APLICADA • SINCRONIZANDO"
		footer.TextColor3 = COLORS.Cyan
	else
		footer.Text = tostring(result.Message or "NÃO FOI POSSÍVEL ALTERAR")
		footer.TextColor3 = COLORS.Red
	end
end

for key, record in pairs(rows) do
	record.Action.Activated:Connect(function()
		local value = current[key]
		if key == "MasterVolume" or key == "MusicVolume" or key == "SFXVolume" then
			setPreference(key, nextIn(VOLUME_OPTIONS, value))
		elseif key == "TextScale" then
			setPreference(key, nextIn(TEXT_OPTIONS, value))
		else
			setPreference(key, not (value == true))
		end
	end)
end

reset.Activated:Connect(function()
	if busy then return end
	busy = true
	footer.Text = "RESTAURANDO..."
	footer.TextColor3 = COLORS.Orange

	local ok, result = pcall(function()
		return request:InvokeServer("Reset")
	end)

	busy = false
	if ok and type(result) == "table" and result.Snapshot and result.Snapshot.Settings then
		mergeSettings(result.Snapshot.Settings)
		footer.Text = "PADRÕES RESTAURADOS • SINCRONIZANDO"
		footer.TextColor3 = COLORS.Cyan
	else
		footer.Text = "NÃO FOI POSSÍVEL RESTAURAR"
		footer.TextColor3 = COLORS.Red
	end
end)

button.Activated:Connect(function()
	overlay.Visible = not overlay.Visible
end)

close.Activated:Connect(function()
	overlay.Visible = false
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and overlay.Visible then
		overlay.Visible = false
	end
end)

event.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if (payload.Action == "Updated" or payload.Action == "UpdatedAll") and payload.Settings then
		mergeSettings(payload.Settings)
	elseif payload.Action == "Saved" then
		if payload.Settings then mergeSettings(payload.Settings) end
		footer.Text = "✓ PREFERÊNCIAS SALVAS NA CONTA"
		footer.TextColor3 = COLORS.Green
	elseif payload.Action == "SaveFailed" then
		footer.Text = tostring(payload.Message or "SALVAMENTO PENDENTE")
		footer.TextColor3 = COLORS.Orange
	end
end)

local function attachButton()
	local lobby = playerGui:FindFirstChild("LobbyUI")
	local topBar = lobby and lobby:FindFirstChild("TopBar")
	if topBar and topBar:IsA("GuiObject") then
		button.Parent = topBar
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.ZIndex = topBar.ZIndex + 8
		return
	end

	local dungeon = playerGui:FindFirstChild("DungeonUnifiedHUD")
	local hudRoot = dungeon and dungeon:FindFirstChild("Root")
	local party = hudRoot and hudRoot:FindFirstChild("Party")
	if party and party:IsA("GuiObject") then
		button.Parent = party
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -8, 0, 7)
		button.ZIndex = party.ZIndex + 8
		return
	end

	button.Parent = gui
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -14, 0, 12)
	button.ZIndex = 20
end

local function watchDescendant(descendant)
	if descendant:IsA("Sound") then
		watchSound(descendant)
	end
	task.defer(function()
		if descendant.Parent then
			applyTextAndContrast(descendant)
			applyDungeonPreferences()
			attachButton()
		end
	end)
end

workspace.DescendantAdded:Connect(watchDescendant)
SoundService.DescendantAdded:Connect(watchDescendant)
playerGui.DescendantAdded:Connect(watchDescendant)

scanSounds(SoundService)
scanSounds(workspace)
scanSounds(playerGui)

task.spawn(function()
	local ok, result = pcall(function()
		return request:InvokeServer("Get")
	end)
	if ok and type(result) == "table" and result.Success and result.Snapshot then
		mergeSettings(result.Snapshot.Settings)
		if result.Snapshot.Temporary then
			footer.Text = "PREFERÊNCIAS TEMPORÁRIAS • DATASTORE INDISPONÍVEL"
			footer.TextColor3 = COLORS.Orange
		elseif result.Snapshot.Dirty then
			footer.Text = "PREFERÊNCIAS CARREGADAS • SINCRONIZAÇÃO PENDENTE"
			footer.TextColor3 = COLORS.Cyan
		else
			footer.Text = "✓ PREFERÊNCIAS CARREGADAS"
			footer.TextColor3 = COLORS.Green
		end
	else
		footer.Text = "USANDO CONFIGURAÇÕES PADRÃO"
		footer.TextColor3 = COLORS.Orange
		applyAll()
	end
end)

task.defer(attachButton)
task.delay(1, attachButton)
task.delay(3, attachButton)

gui:SetAttribute("SettingsVersion", VERSION)
player:SetAttribute("SkySettingsUIReady", true)
workspace:SetAttribute("SkySettingsUIReady", true)
workspace:SetAttribute("SkySettingsUIPolicy", "PersistentAccessibilityAudioV1")
