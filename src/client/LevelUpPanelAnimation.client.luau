-- Progressao visual nao bloqueante do MVP.
-- Nenhum level-up abre painel ou captura input: jogador, Orb e companion usam
-- apenas um toast curto. Upgrades de companion sao confirmados automaticamente
-- escolhendo uma melhoria valida aleatoria para variar cada companheiro.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "NonBlockingProgressionToastV4_CompanionLevelIcon"
local TOAST_GUI_NAME = "ProgressionLevelToastGui"
local DISPLAY_SECONDS = 1.35
local COMPANION_DISPLAY_SECONDS = 0.9
local FADE_SECONDS = 0.18
local COMPANION_FADE_SECONDS = 0.12
local random = Random.new()

local toastGui
local toastHolder
local toastIcon
local toastLabel
local toastSerial = 0
local lastPlayerLevelSerial
local lastOrbLevels = {}
local panelConnections = setmetatable({}, { __mode = "k" })
local companionOfferSerials = {}
local pendingCompanionUpgrades = {}

local function suppressLevelUpPanel(root)
	if not root then
		return
	end
	local panel = root:FindFirstChild("LevelUpPanel", true)
	if not panel or not panel:IsA("GuiObject") then
		return
	end
	panel.Visible = false
	if panelConnections[panel] then
		return
	end
	panelConnections[panel] = panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Parent and panel.Visible then
			panel.Visible = false
		end
	end)
end

local function suppressAllLegacyPanels()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			suppressLevelUpPanel(child)
		end
	end
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
	showToast("NÍVEL " .. tostring(level) .. "!", Color3.fromRGB(255, 239, 118))
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
			-- Nao mostramos nada antes da confirmacao; isso evita interromper o
			-- combate e garante que o toast represente uma melhoria realmente aplicada.
			autoAcceptCompanionOffer(payload, request)
		elseif payload.Action == "Selected" then
			showConfirmedCompanionUpgrade(payload)
		end
	end)
	return true
end

player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(onPlayerLevelUp)
playerGui.ChildAdded:Connect(function(child)
	task.defer(suppressLevelUpPanel, child)
end)
playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "LevelUpPanel" and descendant:IsA("GuiObject") then
		task.defer(suppressAllLegacyPanels)
	end
end)

task.defer(function()
	suppressAllLegacyPanels()
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
player:SetAttribute("DungeonBlockingLevelUpPanelDisabled", true)
player:SetAttribute("DungeonCompanionLevelUpChoicePolicy", "AutomaticRandomAvailableUpgrade")
player:SetAttribute("DungeonCompanionUpgradeToastPolicy", "ConfirmedQuickLevelIcon")
