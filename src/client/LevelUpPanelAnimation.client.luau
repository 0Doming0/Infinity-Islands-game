-- Experience Polish: level up nunca deve interromper combate.
-- O antigo LevelUpPanel permanece no HUD apenas como asset legado, mas este
-- controller o mantem oculto e usa somente notificacoes curtas e nao modais.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "NonBlockingProgressionToastV1"
local TOAST_GUI_NAME = "ProgressionLevelToastGui"
local DISPLAY_SECONDS = 1.35
local FADE_SECONDS = 0.18

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

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MinTextSize = 16
	sizeConstraint.MaxTextSize = 32
	sizeConstraint.Parent = toastLabel

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

	local fadeIn = TweenService:Create(
		label,
		TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = 0,
			TextStrokeTransparency = 0.18,
		}
	)
	fadeIn:Play()

	task.delay(DISPLAY_SECONDS, function()
		if serial ~= toastSerial or not label.Parent then
			return
		end

		local fadeOut = TweenService:Create(
			label,
			TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}
		)
		fadeOut:Play()
		fadeOut.Completed:Wait()
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
	local orbFolder = ReplicatedStorage:FindFirstChild("OrbCombat")
	local configModule = orbFolder and orbFolder:FindFirstChild("OrbConfig")
	if not configModule or not configModule:IsA("ModuleScript") then
		return
	end

	local success, OrbConfig = pcall(require, configModule)
	if not success or type(OrbConfig) ~= "table" then
		return
	end

	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		local attribute = type(OrbConfig.GetLevelAttribute) == "function"
			and OrbConfig.GetLevelAttribute(orbName)
			or nil
		if type(attribute) == "string" and attribute ~= "" then
			lastOrbLevels[attribute] = math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
			player:GetAttributeChangedSignal(attribute):Connect(function()
				local previous = lastOrbLevels[attribute] or 0
				local current = math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
				lastOrbLevels[attribute] = current
				if current > previous and previous > 0 then
					local definition = type(OrbConfig.GetOrb) == "function" and OrbConfig.GetOrb(orbName) or nil
					local displayName = definition and definition.DisplayName or orbName
					showToast(
						string.format("%s • NÍVEL %d", tostring(displayName), current),
						Color3.fromRGB(255, 167, 92)
					)
				end
			end)
		end
	end
end

local function bindCompanionNotification()
	local remote = ReplicatedStorage:FindFirstChild("CompanionLevelUpEvent")
	if not remote or not remote:IsA("RemoteEvent") then
		return false
	end

	if remote:GetAttribute("NonBlockingToastBound") == true then
		return true
	end
	remote:SetAttribute("NonBlockingToastBound", true)
	remote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or payload.Action ~= "Offer" then
			return
		end
		local level = math.max(1, math.floor(tonumber(payload.Level) or 1))
		local name = payload.CompanionName or payload.SpeciesName or "Companheiro"
		showToast(
			string.format("%s • NÍVEL %d", tostring(name), level),
			Color3.fromRGB(126, 255, 176)
		)
	end)
	return true
end

player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(onPlayerLevelUp)

playerGui.ChildAdded:Connect(function(child)
	task.defer(function()
		suppressLevelUpPanel(child)
	end)
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

	if not bindCompanionNotification() then
		-- O remote e criado pelo CompanionService. Esperamos sem bloquear o boot.
		task.spawn(function()
			for _ = 1, 60 do
				task.wait(0.5)
				if bindCompanionNotification() then
					break
				end
			end
		end)
	end
end)

player:SetAttribute("DungeonProgressionToastVersion", VERSION)
player:SetAttribute("DungeonBlockingLevelUpPanelDisabled", true)
