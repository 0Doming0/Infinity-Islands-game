-- Progressao visual nao bloqueante do MVP.
-- Nenhum level-up abre painel ou captura input: jogador, Orb e companion usam
-- apenas um toast curto. Upgrades de companion sao confirmados automaticamente
-- escolhendo uma melhoria valida aleatoria para variar cada companheiro.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "NonBlockingProgressionToastV3_RandomCompanionUpgrade"
local TOAST_GUI_NAME = "ProgressionLevelToastGui"
local DISPLAY_SECONDS = 1.35
local FADE_SECONDS = 0.18
local random = Random.new()

local toastGui
local toastLabel
local toastSerial = 0
local lastPlayerLevelSerial
local lastOrbLevels = {}
local panelConnections = setmetatable({}, { __mode = "k" })

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
	if toastGui and toastGui.Parent and toastLabel and toastLabel.Parent then
		return toastLabel
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

	toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "LevelToast"
	toastLabel.AnchorPoint = Vector2.new(0.5, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0.105, 0)
	toastLabel.Size = UDim2.new(0.72, 0, 0, 42)
	toastLabel.BackgroundTransparency = 1
	toastLabel.BorderSizePixel = 0
	toastLabel.Font = Enum.Font.GothamBlack
	toastLabel.Text = ""
	toastLabel.TextColor3 = Color3.fromRGB(255, 239, 118)
	toastLabel.TextStrokeColor3 = Color3.fromRGB(20, 13, 31)
	toastLabel.TextStrokeTransparency = 0.18
	toastLabel.TextScaled = true
	toastLabel.TextWrapped = false
	toastLabel.TextTransparency = 1
	toastLabel.ZIndex = 181
	toastLabel.Parent = toastGui

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 16
	constraint.MaxTextSize = 32
	constraint.Parent = toastLabel
	return toastLabel
end

local function showToast(message, color)
	if type(message) ~= "string" or message == "" then
		return
	end
	local label = ensureToast()
	toastSerial += 1
	local serial = toastSerial

	label.Text = message
	label.TextColor3 = color or Color3.fromRGB(255, 239, 118)
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Visible = true

	TweenService:Create(
		label,
		TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0.18 }
	):Play()

	task.delay(DISPLAY_SECONDS, function()
		if serial ~= toastSerial or not label.Parent then
			return
		end
		local fade = TweenService:Create(
			label,
			TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fade:Play()
		fade.Completed:Wait()
		if serial == toastSerial and label.Parent then
			label.Visible = false
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

local companionOfferSerials = {}

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
	player:SetAttribute("DungeonCompanionLastRandomUpgrade", chosen.UpgradeId)
	player:SetAttribute("DungeonCompanionLastRandomUpgradeSerial", serial)

	request:FireServer({
		Serial = serial,
		InstanceId = instanceId,
		UpgradeId = chosen.UpgradeId,
	})
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
			local level = math.max(1, math.floor(tonumber(payload.Level) or 1))
			local name = payload.CompanionName or payload.SpeciesName or "Companheiro"
			showToast(
				string.format("%s • NÍVEL %d", tostring(name), level),
				Color3.fromRGB(126, 255, 176)
			)
			autoAcceptCompanionOffer(payload, request)
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
