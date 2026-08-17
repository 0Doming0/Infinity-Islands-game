-- Player level-up usa o LevelUpPanel autorado no Studio com a animacao original.
-- Orbs e companions continuam usando toasts curtos para nao interromper combate.
-- Se LevelUpPanel tiver invisible=true (ou estiver ausente), o player level-up
-- volta automaticamente para o toast simples como fallback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "AuthoredPlayerLevelPanelV5_WithToastFallback"
local TOAST_GUI_NAME = "ProgressionLevelToastGui"

-- Toasts de Orb/companion e fallback do level do jogador.
local DISPLAY_SECONDS = 1.35
local COMPANION_DISPLAY_SECONDS = 0.9
local FADE_SECONDS = 0.18
local COMPANION_FADE_SECONDS = 0.12

-- Animacao original do LevelUpPanel, restaurada da versao autorada.
local PANEL_SHOW_TIME = 0.42
local PANEL_HIDE_TIME = 0.32
local PANEL_DISPLAY_TIME = 2.4
local PANEL_SLIDE_OFFSET = 42

local random = Random.new()

local toastGui
local toastHolder
local toastIcon
local toastLabel
local toastSerial = 0

local levelPanel
local levelPanelInitialPosition
local levelPanelTransparencyValues = {}
local levelPanelAnimationSerial = 0
local levelPanelInvisibleConnection
local lastPlayerLevelSerial
local lastOrbLevels = {}

local companionOfferSerials = {}
local pendingCompanionUpgrades = {}

local function isTextObject(instance)
	return instance
		and (
			instance:IsA("TextLabel")
			or instance:IsA("TextButton")
			or instance:IsA("TextBox")
		)
end

local function findLevelUpPanel()
	local dungeonHud = playerGui:FindFirstChild("DungeonHUD")
	local direct = dungeonHud and dungeonHud:FindFirstChild("LevelUpPanel", true)
	if direct and direct:IsA("GuiObject") then
		return direct
	end

	-- Fallback de descoberta para manter o asset funcionando caso o ScreenGui
	-- seja renomeado, sem criar uma segunda copia do painel.
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == "LevelUpPanel" and descendant:IsA("GuiObject") then
			return descendant
		end
	end
	return nil
end

local function setLevelPanelFade(value)
	if not levelPanel then
		return
	end

	for object, values in pairs(levelPanelTransparencyValues) do
		if object.Parent then
			object.BackgroundTransparency = values.BackgroundTransparency
				+ (1 - values.BackgroundTransparency) * value

			if values.TextTransparency ~= nil then
				object.TextTransparency = values.TextTransparency
					+ (1 - values.TextTransparency) * value
			end
			if values.ImageTransparency ~= nil then
				object.ImageTransparency = values.ImageTransparency
					+ (1 - values.ImageTransparency) * value
			end
		end
	end
end

local function restoreLevelPanelFade()
	setLevelPanelFade(0)
end

local function stopAndHideLevelPanel()
	levelPanelAnimationSerial += 1
	if levelPanel and levelPanel.Parent then
		levelPanel.Visible = false
		if levelPanelInitialPosition then
			levelPanel.Position = levelPanelInitialPosition
		end
		restoreLevelPanelFade()
	end
end

local function bindLevelPanelInvisibleAttribute()
	if levelPanelInvisibleConnection then
		levelPanelInvisibleConnection:Disconnect()
		levelPanelInvisibleConnection = nil
	end
	if not levelPanel then
		return
	end

	levelPanelInvisibleConnection = levelPanel:GetAttributeChangedSignal("invisible"):Connect(function()
		if levelPanel and levelPanel:GetAttribute("invisible") == true then
			stopAndHideLevelPanel()
		end
	end)
end

local function captureLevelUpPanel()
	local current = findLevelUpPanel()
	if not current then
		return false
	end

	if current ~= levelPanel then
		levelPanel = current
		levelPanelInitialPosition = levelPanel.Position
		levelPanelTransparencyValues = {}

		-- Mesma estrategia da animacao original: respeita os valores autorados no
		-- Studio e apenas interpola temporariamente ate transparencia total.
		for _, descendant in ipairs(levelPanel:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				levelPanelTransparencyValues[descendant] = {
					BackgroundTransparency = descendant.BackgroundTransparency,
					TextTransparency = isTextObject(descendant)
						and descendant.TextTransparency
						or nil,
					ImageTransparency = (
						descendant:IsA("ImageLabel") or descendant:IsA("ImageButton")
					) and descendant.ImageTransparency or nil,
				}
			end
		end
		bindLevelPanelInvisibleAttribute()
	end

	return true
end

local function updateLevelPanelText(level)
	if not captureLevelUpPanel() then
		return
	end
	local levelText = levelPanel:FindFirstChild("LevelText", true)
	if isTextObject(levelText) then
		levelText.Text = string.format("Level %d", level)
	end
end

local function levelPanelAllowed()
	return captureLevelUpPanel()
		and levelPanel.Parent ~= nil
		and levelPanel:GetAttribute("invisible") ~= true
end

local function hideLevelPanelAnimated(expectedSerial)
	if not levelPanelAllowed() then
		stopAndHideLevelPanel()
		return
	end
	if expectedSerial and expectedSerial ~= levelPanelAnimationSerial then
		return
	end

	local currentSerial = levelPanelAnimationSerial
	local hiddenPosition = levelPanelInitialPosition + UDim2.fromOffset(0, -PANEL_SLIDE_OFFSET)

	local positionTween = TweenService:Create(
		levelPanel,
		TweenInfo.new(PANEL_HIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = hiddenPosition }
	)
	local fadeValue = Instance.new("NumberValue")
	fadeValue.Value = 0
	local fadeConnection = fadeValue.Changed:Connect(setLevelPanelFade)
	local fadeTween = TweenService:Create(
		fadeValue,
		TweenInfo.new(PANEL_HIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = 1 }
	)

	positionTween:Play()
	fadeTween:Play()
	positionTween.Completed:Wait()
	fadeConnection:Disconnect()
	fadeValue:Destroy()

	if currentSerial == levelPanelAnimationSerial and levelPanel then
		levelPanel.Visible = false
		levelPanel.Position = levelPanelInitialPosition
		restoreLevelPanelFade()
	end
end

local function showLevelPanelAnimated(level)
	if not levelPanelAllowed() then
		return false
	end

	updateLevelPanelText(level)
	levelPanelAnimationSerial += 1
	local currentSerial = levelPanelAnimationSerial
	local hiddenPosition = levelPanelInitialPosition + UDim2.fromOffset(0, -PANEL_SLIDE_OFFSET)

	levelPanel.Visible = true
	levelPanel.Position = hiddenPosition
	setLevelPanelFade(1)

	local positionTween = TweenService:Create(
		levelPanel,
		TweenInfo.new(PANEL_SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = levelPanelInitialPosition }
	)
	local fadeValue = Instance.new("NumberValue")
	fadeValue.Value = 1
	local fadeConnection = fadeValue.Changed:Connect(setLevelPanelFade)
	local fadeTween = TweenService:Create(
		fadeValue,
		TweenInfo.new(PANEL_SHOW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 0 }
	)

	positionTween:Play()
	fadeTween:Play()
	positionTween.Completed:Wait()
	fadeConnection:Disconnect()
	fadeValue:Destroy()

	if currentSerial ~= levelPanelAnimationSerial then
		return true
	end
	if levelPanel:GetAttribute("invisible") == true then
		stopAndHideLevelPanel()
		return true
	end

	restoreLevelPanelFade()
	task.wait(PANEL_DISPLAY_TIME)
	if currentSerial == levelPanelAnimationSerial then
		hideLevelPanelAnimated(currentSerial)
	end
	return true
end

local function ensureToast()
	if toastGui and toastGui.Parent and toastHolder and toastHolder.Parent
		and toastLabel and toastLabel.Parent and toastIcon and toastIcon.Parent
	then
		return toastHolder, toastLabel, toastIcon
	end

	local old = playerGui:FindFirstChild(TOAST_GUI_NAME)
	if old then
		old:Destroy()
	end

	toastGui = Instance.new("ScreenGui")
	toastGui.Name = TOAST_GUI_NAME
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = false
	toastGui.DisplayOrder = 180
	toastGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toastGui.Parent = playerGui

	toastHolder = Instance.new("Frame")
	toastHolder.Name = "LevelToastHolder"
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0.105, 0)
	toastHolder.Size = UDim2.new(0.92, 0, 0, 44)
	toastHolder.BackgroundTransparency = 1
	toastHolder.BorderSizePixel = 0
	toastHolder.Visible = false
	toastHolder.ZIndex = 181
	toastHolder.Parent = toastGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = toastHolder

	toastIcon = Instance.new("ImageLabel")
	toastIcon.Name = "CompanionLevelIcon"
	toastIcon.Size = UDim2.fromOffset(38, 38)
	toastIcon.BackgroundTransparency = 1
	toastIcon.BorderSizePixel = 0
	toastIcon.Image = ""
	toastIcon.ImageTransparency = 1
	toastIcon.ScaleType = Enum.ScaleType.Fit
	toastIcon.Visible = false
	toastIcon.LayoutOrder = 1
	toastIcon.ZIndex = 182
	toastIcon.Parent = toastHolder

	toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "LevelToast"
	toastLabel.AutomaticSize = Enum.AutomaticSize.X
	toastLabel.Size = UDim2.fromOffset(0, 42)
	toastLabel.BackgroundTransparency = 1
	toastLabel.BorderSizePixel = 0
	toastLabel.Font = Enum.Font.GothamBlack
	toastLabel.Text = ""
	toastLabel.TextColor3 = Color3.fromRGB(255, 239, 118)
	toastLabel.TextStrokeColor3 = Color3.fromRGB(20, 13, 31)
	toastLabel.TextStrokeTransparency = 0.18
	toastLabel.TextSize = 24
	toastLabel.TextWrapped = false
	toastLabel.TextTransparency = 1
	toastLabel.LayoutOrder = 2
	toastLabel.ZIndex = 182
	toastLabel.Parent = toastHolder

	return toastHolder, toastLabel, toastIcon
end

local function showToast(message, color, options)
	if type(message) ~= "string" or message == "" then
		return
	end

	options = type(options) == "table" and options or {}
	local holder, label, icon = ensureToast()
	toastSerial += 1
	local serial = toastSerial
	local duration = math.max(0.1, tonumber(options.Duration) or DISPLAY_SECONDS)
	local fadeSeconds = math.max(0.05, tonumber(options.FadeSeconds) or FADE_SECONDS)
	local imageId = type(options.ImageId) == "string" and options.ImageId or ""
	local showIcon = imageId ~= ""

	label.Text = message
	label.TextColor3 = color or Color3.fromRGB(255, 239, 118)
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.TextSize = math.clamp(math.floor(tonumber(options.TextSize) or 24), 16, 30)
	label.Visible = true

	icon.Image = imageId
	icon.Visible = showIcon
	icon.ImageTransparency = 1
	holder.Visible = true

	TweenService:Create(
		label,
		TweenInfo.new(fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0.18 }
	):Play()
	if showIcon then
		TweenService:Create(
			icon,
			TweenInfo.new(fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ImageTransparency = 0 }
		):Play()
	end

	task.delay(duration, function()
		if serial ~= toastSerial or not holder.Parent then
			return
		end

		local labelFade = TweenService:Create(
			label,
			TweenInfo.new(fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		labelFade:Play()
		if showIcon and icon.Parent then
			TweenService:Create(
				icon,
				TweenInfo.new(fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ ImageTransparency = 1 }
			):Play()
		end
		labelFade.Completed:Wait()

		if serial == toastSerial and holder.Parent then
			holder.Visible = false
			icon.Visible = false
		end
	end)
end

local function onPlayerLevelUp()
	local serial = player:GetAttribute("PlayerLevelUpSerial")
	if serial == nil or serial == lastPlayerLevelSerial then
		return
	end
	lastPlayerLevelSerial = serial

	local level = math.max(
		1,
		math.floor(
			tonumber(player:GetAttribute("LastLevelUpTo"))
				or tonumber(player:GetAttribute("PlayerLevel"))
				or 1
		)
	)

	if levelPanelAllowed() then
		player:SetAttribute("DungeonPlayerLevelUpPresentation", "LevelUpPanel")
		task.spawn(showLevelPanelAnimated, level)
	else
		player:SetAttribute("DungeonPlayerLevelUpPresentation", "ToastFallback")
		showToast("NÍVEL " .. tostring(level) .. "!", Color3.fromRGB(255, 239, 118))
	end
end

local function bindOrbLevelNotifications()
	local folder = ReplicatedStorage:FindFirstChild("OrbCombat")
	local module = folder and folder:FindFirstChild("OrbConfig")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, OrbConfig = pcall(require, module)
	if not ok or type(OrbConfig) ~= "table" then
		return
	end

	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		local attribute = type(OrbConfig.GetLevelAttribute) == "function"
			and OrbConfig.GetLevelAttribute(orbName)
			or nil
		if type(attribute) == "string" and attribute ~= "" then
			lastOrbLevels[attribute] = math.max(
				0,
				math.floor(tonumber(player:GetAttribute(attribute)) or 0)
			)
			player:GetAttributeChangedSignal(attribute):Connect(function()
				local previous = lastOrbLevels[attribute] or 0
				local current = math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
				lastOrbLevels[attribute] = current
				if current <= previous or current <= 0 then
					return
				end
				local definition = type(OrbConfig.GetOrb) == "function" and OrbConfig.GetOrb(orbName) or nil
				local displayName = definition and definition.DisplayName or orbName
				if previous <= 0 then
					showToast(
						string.format("%s DESBLOQUEADO!", tostring(displayName)),
						Color3.fromRGB(255, 167, 92)
					)
				else
					showToast(
						string.format("%s • NÍVEL %d", tostring(displayName), current),
						Color3.fromRGB(255, 167, 92)
					)
				end
			end)
		end
	end
end

local function companionLevelIcon(speciesId)
	if type(speciesId) ~= "string" then
		return ""
	end
	local definition = CompanionCatalog.Get(speciesId)
	return definition and definition.LevelIconImageId or ""
end

local function autoAcceptCompanionOffer(payload, request)
	local serial = math.floor(tonumber(payload.Serial) or 0)
	local instanceId = payload.InstanceId
	if serial <= 0 or type(instanceId) ~= "string" or companionOfferSerials[serial] then
		return
	end

	local available = {}
	for _, option in ipairs(payload.Options or {}) do
		if type(option) == "table"
			and option.Available ~= false
			and type(option.UpgradeId) == "string"
			and option.UpgradeId ~= ""
		then
			table.insert(available, option)
		end
	end
	if #available == 0 then
		return
	end

	local chosen = available[random:NextInteger(1, #available)]
	companionOfferSerials[serial] = true
	pendingCompanionUpgrades[instanceId] = {
		Serial = serial,
		SpeciesId = payload.SpeciesId,
		CompanionName = payload.CompanionName or payload.SpeciesName or "Companheiro",
		Level = math.max(1, math.floor(tonumber(payload.Level) or 1)),
		UpgradeId = chosen.UpgradeId,
		UpgradeLabel = chosen.AttributeLabel or chosen.DisplayName or "MELHORIA",
	}

	player:SetAttribute("DungeonCompanionLastRandomUpgrade", chosen.UpgradeId)
	player:SetAttribute("DungeonCompanionLastRandomUpgradeSerial", serial)

	request:FireServer({
		Serial = serial,
		InstanceId = instanceId,
		UpgradeId = chosen.UpgradeId,
	})
end

local function showConfirmedCompanionUpgrade(payload)
	local instanceId = payload.InstanceId
	local pending = type(instanceId) == "string" and pendingCompanionUpgrades[instanceId] or nil
	if not pending then
		return
	end
	pendingCompanionUpgrades[instanceId] = nil

	if type(payload.UpgradeId) == "string" and payload.UpgradeId ~= pending.UpgradeId then
		return
	end

	local imageId = companionLevelIcon(pending.SpeciesId)
	local upgradeLabel = tostring(pending.UpgradeLabel or "MELHORIA")
	showToast(
		"MELHORIA APLICADA • " .. string.upper(upgradeLabel),
		Color3.fromRGB(126, 255, 176),
		{
			ImageId = imageId,
			Duration = COMPANION_DISPLAY_SECONDS,
			FadeSeconds = COMPANION_FADE_SECONDS,
			TextSize = 22,
		}
	)

	player:SetAttribute("DungeonCompanionUpgradeToastInstanceId", instanceId)
	player:SetAttribute("DungeonCompanionUpgradeToastLevel", pending.Level)
	player:SetAttribute("DungeonCompanionUpgradeToastHasLevelIcon", imageId ~= "")
end

local function bindCompanionProgression()
	local event = ReplicatedStorage:FindFirstChild("CompanionLevelUpEvent")
	local request = ReplicatedStorage:FindFirstChild("CompanionLevelUpRequest")
	if not event or not event:IsA("RemoteEvent")
		or not request or not request:IsA("RemoteEvent")
	then
		return false
	end
	if event:GetAttribute("LinearAutoUpgradeBound") == true then
		return true
	end

	event:SetAttribute("LinearAutoUpgradeBound", true)
	event.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.Action == "Offer" then
			autoAcceptCompanionOffer(payload, request)
		elseif payload.Action == "Selected" then
			showConfirmedCompanionUpgrade(payload)
		end
	end)
	return true
end

player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(onPlayerLevelUp)

playerGui.ChildAdded:Connect(function()
	task.defer(function()
		if captureLevelUpPanel() and levelPanel then
			levelPanel.Visible = false
			levelPanel.Position = levelPanelInitialPosition
			restoreLevelPanelFade()
		end
	end)
end)

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "LevelUpPanel" and descendant:IsA("GuiObject") then
		task.defer(function()
			if captureLevelUpPanel() and levelPanel then
				levelPanel.Visible = false
				levelPanel.Position = levelPanelInitialPosition
				restoreLevelPanelFade()
			end
		end)
	end
end)

task.defer(function()
	if captureLevelUpPanel() and levelPanel then
		levelPanel.Visible = false
		levelPanel.Position = levelPanelInitialPosition
		restoreLevelPanelFade()
	end

	ensureToast()
	bindOrbLevelNotifications()

	if not bindCompanionProgression() then
		task.spawn(function()
			for _ = 1, 60 do
				task.wait(0.5)
				if bindCompanionProgression() then
					break
				end
			end
		end)
	end
end)

player:SetAttribute("DungeonProgressionToastVersion", VERSION)
player:SetAttribute("DungeonBlockingLevelUpPanelDisabled", false)
player:SetAttribute("DungeonPlayerLevelUpPanelPolicy", "AuthoredPanelUnlessInvisibleTrue")
player:SetAttribute("DungeonPlayerLevelUpToastFallback", true)
player:SetAttribute("DungeonCompanionLevelUpChoicePolicy", "AutomaticRandomAvailableUpgrade")
player:SetAttribute("DungeonCompanionUpgradeToastPolicy", "ConfirmedQuickLevelIcon")
