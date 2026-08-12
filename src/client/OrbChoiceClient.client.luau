local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local choiceEvent = orbFolder:WaitForChild("OrbChoiceEvent")
local choiceRequest = orbFolder:WaitForChild("OrbChoiceRequest")

local COLORS = {
	Fire = Color3.fromRGB(255, 104, 48),
	Ice = Color3.fromRGB(85, 208, 255),
	Shadow = Color3.fromRGB(174, 90, 255),
}

local activePanel
local activeCards = {}
local activeButtonConnections = {}
local submitting = false

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
end

local function newText(parent, name, text, size, position, fontSize, bold)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(240, 246, 255)
	label.TextSize = fontSize
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function createFallbackPanel()
	local old = playerGui:FindFirstChild("OrbChoiceGui")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OrbChoiceGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Color3.fromRGB(3, 7, 18)
	shade.BackgroundTransparency = 0.28
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "OrbChoicePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.78, 0.66)
	panel.BackgroundColor3 = Color3.fromRGB(13, 25, 49)
	panel.Parent = shade
	addCorner(panel, 18)
	addStroke(panel, Color3.fromRGB(110, 190, 255), 2, 0.18)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 430)
	constraint.MaxSize = Vector2.new(1040, 650)
	constraint.Parent = panel

	local title =
		newText(panel, "Title", "CHOOSE YOUR ORB", UDim2.new(1, -30, 0, 42), UDim2.fromOffset(15, 15), 27, true)
	title.TextColor3 = Color3.fromRGB(255, 221, 103)

	local subtitle = newText(
		panel,
		"Subtitle",
		"Level 3 reward - choose one",
		UDim2.new(1, -30, 0, 30),
		UDim2.fromOffset(15, 54),
		15,
		false
	)
	subtitle.TextColor3 = Color3.fromRGB(176, 203, 230)

	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.BackgroundTransparency = 1
	cards.Position = UDim2.fromOffset(18, 96)
	cards.Size = UDim2.new(1, -36, 1, -116)
	cards.Parent = panel

	local layout = Instance.new("UIGridLayout")
	layout.Name = "CardsLayout"
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.CellSize = UDim2.new(1 / 3, -8, 1, 0)
	layout.FillDirectionMaxCells = 3
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = cards

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.5
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = panel

	return panel
end

local function findAuthoredPanel()
	local hud = playerGui:FindFirstChild("DungeonHUD")
	if not hud then
		return nil
	end
	for _, name in ipairs({ "OrbChoicePanel", "OrbSelectionPanel", "ChooseOrbPanel" }) do
		local candidate = hud:FindFirstChild(name, true)
		if candidate and candidate:IsA("GuiObject") then
			return candidate
		end
	end
	return nil
end

local function findText(root, names)
	for _, name in ipairs(names) do
		local object = root:FindFirstChild(name, true)
		if object and (object:IsA("TextLabel") or object:IsA("TextButton")) then
			return object
		end
	end
	return nil
end

local function findButton(root)
	for _, name in ipairs({ "SelectButton", "ChooseButton", "Button", "Select" }) do
		local object = root:FindFirstChild(name, true)
		if object and object:IsA("GuiButton") then
			return object
		end
	end
	if root:IsA("GuiButton") then
		return root
	end
	return nil
end

local function createFallbackCard(container, orbName)
	local card = Instance.new("Frame")
	card.Name = orbName .. "Card"
	card.BackgroundColor3 = Color3.fromRGB(21, 38, 67)
	card.Parent = container
	addCorner(card, 14)
	addStroke(card, COLORS[orbName], 2, 0.15)

	local icon = Instance.new("Frame")
	icon.Name = "OrbIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.055)
	icon.Size = UDim2.fromOffset(58, 58)
	icon.BackgroundColor3 = COLORS[orbName]
	icon.Parent = card
	addCorner(icon, 99)
	addStroke(icon, Color3.new(1, 1, 1), 2, 0.35)

	local newBadge = newText(card, "NewBadge", "NEW", UDim2.fromOffset(52, 24), UDim2.fromOffset(10, 10), 12, true)
	newBadge.BackgroundTransparency = 0
	newBadge.BackgroundColor3 = Color3.fromRGB(61, 205, 126)
	addCorner(newBadge, 8)

	local name = newText(card, "OrbName", "ORB", UDim2.new(1, -18, 0, 28), UDim2.new(0, 9, 0, 78), 20, true)
	name.TextColor3 = COLORS[orbName]

	newText(card, "OrbLevel", "Level 1", UDim2.new(1, -18, 0, 22), UDim2.new(0, 9, 0, 108), 14, true)
	local description = newText(card, "Description", "", UDim2.new(1, -22, 0, 54), UDim2.new(0, 11, 0, 136), 13, false)
	description.TextColor3 = Color3.fromRGB(195, 213, 232)
	description.TextYAlignment = Enum.TextYAlignment.Top

	local upgrade = newText(card, "UpgradeInfo", "", UDim2.new(1, -22, 0, 72), UDim2.new(0, 11, 0, 198), 12, false)
	upgrade.TextColor3 = Color3.fromRGB(255, 224, 132)
	upgrade.TextYAlignment = Enum.TextYAlignment.Top

	local button = Instance.new("TextButton")
	button.Name = "SelectButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -13)
	button.Size = UDim2.new(1, -24, 0, 42)
	button.BackgroundColor3 = COLORS[orbName]
	button.Font = Enum.Font.GothamBold
	button.Text = "SELECT"
	button.TextColor3 = Color3.fromRGB(10, 18, 32)
	button.TextSize = 15
	button.Parent = card
	addCorner(button, 10)
	return card
end

local function ensureCards(panel)
	local cards = {}
	local container = panel:FindFirstChild("Cards", true)
	local template = panel:FindFirstChild("OrbCardTemplate", true)

	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		local card
		for _, possibleName in ipairs({ orbName .. "Card", orbName .. "Orb", orbName }) do
			local candidate = panel:FindFirstChild(possibleName, true)
			if candidate and candidate:IsA("GuiObject") then
				card = candidate
				break
			end
		end
		if not card and template and template:IsA("GuiObject") then
			card = template:Clone()
			card.Name = orbName .. "Card"
			card.Visible = true
			card.Parent = template.Parent
		end
		if not card then
			if not container then
				container = Instance.new("Frame")
				container.Name = "Cards"
				container.BackgroundTransparency = 1
				container.Position = UDim2.fromScale(0.03, 0.2)
				container.Size = UDim2.fromScale(0.94, 0.76)
				container.Parent = panel
				local layout = Instance.new("UIGridLayout")
				layout.CellPadding = UDim2.fromOffset(10, 10)
				layout.CellSize = UDim2.new(1 / 3, -7, 1, 0)
				layout.FillDirectionMaxCells = 3
				layout.Parent = container
			end
			card = createFallbackCard(container, orbName)
		end
		cards[orbName] = card
	end

	if template and template:IsA("GuiObject") then
		template.Visible = false
	end
	return cards
end

local function currentOrbLevel(orbName)
	return OrbConfig.CleanLevel(player:GetAttribute(OrbConfig.GetLevelAttribute(orbName)))
end

local function populateCard(card, orbName, milestone, serial)
	local definition = OrbConfig.GetOrb(orbName)
	local currentLevel = currentOrbLevel(orbName)
	local nextLevel = math.min(currentLevel + 1, OrbConfig.MaxOrbLevel)
	local isNew = currentLevel == 0

	local nameText = findText(card, { "OrbName", "Name", "Title" })
	local levelText = findText(card, { "OrbLevel", "Level" })
	local descriptionText = findText(card, { "Description", "OrbDescription" })
	local badge = findText(card, { "NewBadge", "Badge" })
	local upgradeText = findText(card, { "UpgradeInfo", "Stats", "BeforeAfter" })
	local button = findButton(card)
	if not button then
		button = Instance.new("TextButton")
		button.Name = "SelectButton"
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, 0, 1, -10)
		button.Size = UDim2.new(1, -20, 0, 40)
		button.BackgroundColor3 = COLORS[orbName]
		button.Font = Enum.Font.GothamBold
		button.TextColor3 = Color3.fromRGB(10, 18, 32)
		button.TextSize = 15
		button.Parent = card
		addCorner(button, 10)
	end

	if nameText then
		nameText.Text = string.upper(definition.DisplayName)
	end
	if levelText then
		levelText.Text = string.format("Level %d", nextLevel)
	end
	if descriptionText then
		descriptionText.Text = definition.Description
	end
	if badge then
		badge.Visible = isNew
		badge.Text = "NEW"
	end
	if upgradeText then
		upgradeText.Text = OrbConfig.GetUpgradeSummary(orbName, currentLevel)
	end
	if button then
		local oldConnection = activeButtonConnections[button]
		if oldConnection then
			oldConnection:Disconnect()
		end
		button.Active = currentLevel < OrbConfig.MaxOrbLevel
		button.AutoButtonColor = currentLevel < OrbConfig.MaxOrbLevel
		if button:IsA("TextButton") then
			button.Text = isNew and "CHOOSE" or "UPGRADE"
		end
		button.Modal = true
		activeButtonConnections[button] = button.Activated:Connect(function()
			if submitting or currentLevel >= OrbConfig.MaxOrbLevel then
				return
			end
			submitting = true
			for _, otherCard in pairs(activeCards) do
				local otherButton = findButton(otherCard)
				if otherButton then
					otherButton.Active = false
					otherButton.AutoButtonColor = false
				end
			end
			choiceRequest:FireServer({
				Orb = orbName,
				MilestoneLevel = milestone,
				Serial = serial,
			})
		end)
	end
end

local function setPanelVisible(panel, visible)
	panel.Visible = visible
	local screenGui = panel:FindFirstAncestorOfClass("ScreenGui")
	if screenGui and screenGui.Name == "OrbChoiceGui" then
		screenGui.Enabled = visible
	end
end

local function showOffer(milestone, serial)
	milestone = math.floor(tonumber(milestone) or 0)
	serial = math.floor(tonumber(serial) or 0)
	if milestone <= 0 or serial <= 0 then
		return
	end

	local panel = findAuthoredPanel() or createFallbackPanel()
	activePanel = panel
	activeCards = ensureCards(panel)
	submitting = false

	local title = findText(panel, { "Title", "OrbChoiceTitle" })
	local subtitle = findText(panel, { "Subtitle", "LevelText", "OrbChoiceSubtitle" })
	if title then
		title.Text = "CHOOSE YOUR ORB"
	end
	if subtitle then
		subtitle.Text = string.format("Level %d reward - choose one", milestone)
	end

	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		populateCard(activeCards[orbName], orbName, milestone, serial)
	end
	setPanelVisible(panel, true)
end

local function hideOffer()
	if activePanel then
		setPanelVisible(activePanel, false)
	end
	activePanel = nil
	activeCards = {}
	for button, connection in pairs(activeButtonConnections) do
		connection:Disconnect()
		activeButtonConnections[button] = nil
	end
	submitting = false
end

choiceEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Action == "Offer" then
		showOffer(payload.MilestoneLevel, payload.Serial)
	elseif payload.Action == "Selected" then
		hideOffer()
	elseif payload.Action == "Rejected" then
		submitting = false
		local pending = tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0
		if pending > 0 then
			showOffer(pending, player:GetAttribute("OrbChoiceSerial"))
		end
	end
end)

player:GetAttributeChangedSignal("PendingOrbChoiceLevel"):Connect(function()
	local pending = tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0
	if pending > 0 then
		showOffer(pending, player:GetAttribute("OrbChoiceSerial"))
	elseif activePanel then
		hideOffer()
	end
end)

task.defer(function()
	local pending = tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0
	if pending > 0 then
		showOffer(pending, player:GetAttribute("OrbChoiceSerial"))
	end
end)

print("[OrbChoiceClient] Orb choices ready")
