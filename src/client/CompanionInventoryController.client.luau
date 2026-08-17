-- CompanionInventoryController.client.luau
--
-- Autoridade cliente da CompanionInventoryGui autorada no Studio.
-- Nao cria o layout: conecta o launcher, torna o MainFrame responsivo,
-- renderiza snapshots do CompanionService e envia equip/unequip ao servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "AuthoredRealtimeResponsiveV4_FirstUnlockGate"
local RESPONSIVE_SCALE_NAME = "CompanionResponsiveScale"
local VIEWPORT_PADDING = Vector2.new(28, 28)
local MAX_RESPONSIVE_SCALE = 1.12
local MIN_RESPONSIVE_SCALE = 0.25
local FALLBACK_MAIN_WIDTH = 629
local FALLBACK_MAIN_HEIGHT = 317

local request
local event

local OPEN_BUTTON_NAMES = {
	opencompanions = true,
	openinventorybutton = true,
	companionbutton = true,
	companioninventorybutton = true,
	companionlauncher = true,
}

local inventoryGui
local mainFrame
local companionList
local cardTemplate
local selectedPanel
local selectedId
local currentSnapshot
local snapshotSerial = 0
local isMutating = false

local responsiveScale
local responsiveBaseWidth
local responsiveBaseHeight

local cardConnections = {}
local inventoryConnections = {}
local launcherRoots = setmetatable({}, { __mode = "k" })
local boundLauncherButtons = setmetatable({}, { __mode = "k" })

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function isTextObject(instance)
	return instance
		and (
			instance:IsA("TextLabel")
			or instance:IsA("TextButton")
			or instance:IsA("TextBox")
		)
end

local function isImageObject(instance)
	return instance
		and (instance:IsA("ImageLabel") or instance:IsA("ImageButton"))
end

local function findNamedDescendant(root, names)
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local direct = root:FindFirstChild(name)
		if direct then
			return direct
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		for _, name in ipairs(names) do
			if descendant.Name == name then
				return descendant
			end
		end
	end

	return nil
end

local function findText(root, names)
	local instance = findNamedDescendant(root, names)
	return isTextObject(instance) and instance or nil
end

local function findImage(root, names)
	local instance = findNamedDescendant(root, names)
	return isImageObject(instance) and instance or nil
end

local function fallbackTextInside(root)
	if not root then
		return nil
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if isTextObject(descendant) then
			return descendant
		end
	end
	return nil
end

local function setText(instance, value)
	if isTextObject(instance) then
		instance.Text = tostring(value or "")
	end
end

local function setImage(instance, imageId)
	if isImageObject(instance)
		and type(imageId) == "string"
		and imageId ~= ""
	then
		instance.Image = imageId
	end
end

local function setVisible(instance, visible)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible == true
	end
end

local function setXPFill(fill, progress)
	if not fill or not fill:IsA("GuiObject") then
		return
	end
	local size = fill.Size
	fill.Size = UDim2.new(
		math.clamp(tonumber(progress) or 0, 0, 1),
		0,
		size.Y.Scale,
		size.Y.Offset
	)
end

local function numberText(value, decimals, suffix)
	local number = tonumber(value) or 0
	local format = decimals > 0
		and ("%." .. tostring(decimals) .. "f")
		or "%.0f"
	return string.format(format, number) .. (suffix or "")
end

local function statRow(statsPanel, names)
	if not statsPanel then
		return nil
	end
	for _, name in ipairs(names) do
		local row = statsPanel:FindFirstChild(name, true)
		if row and row:IsA("GuiObject") then
			return row
		end
	end
	return nil
end

local function setStatRow(row, labelText, valueText)
	if not row then
		return
	end

	local label = findText(row, { "StatLabel", "AttributeLabel", "Label" })
	local value = findText(row, { "StatValue", "AttributeValue", "Value" })

	if not label or not value then
		local texts = {}
		for _, descendant in ipairs(row:GetDescendants()) do
			if isTextObject(descendant) then
				table.insert(texts, descendant)
			end
		end
		label = label or texts[1]
		value = value or texts[2]
	end

	setText(label, labelText)
	setText(value, valueText)
end

local function renderStats(panel, stats)
	if not panel or type(stats) ~= "table" then
		return
	end

	setStatRow(
		statRow(panel, { "AttackStat", "DamageStat", "AtaqueStat" }),
		"DANO",
		numberText(stats.Damage, 1)
	)
	setStatRow(
		statRow(panel, { "DefenseStat", "CooldownStat", "RecargaStat", "DefesaStat" }),
		"RECARGA",
		numberText(stats.AttackCooldown, 2, "s")
	)
	setStatRow(
		statRow(panel, { "HealthStat", "RangeStat", "VidaStat", "AlcanceStat" }),
		"ALCANCE",
		numberText(stats.AttackRange, 1)
	)
	setStatRow(
		statRow(panel, { "SpeedStat", "MoveSpeedStat", "VelocidadeStat" }),
		"VELOCIDADE",
		numberText(stats.WalkSpeed, 1)
	)
end

local function snapshotEntries()
	if not currentSnapshot or type(currentSnapshot.Entries) ~= "table" then
		return {}
	end
	return currentSnapshot.Entries
end

local function hasUnlockedCompanion()
	return #snapshotEntries() > 0
end

local function getEntry(instanceId)
	if type(instanceId) ~= "string" then
		return nil
	end
	for _, entry in ipairs(snapshotEntries()) do
		if entry.InstanceId == instanceId then
			return entry
		end
	end
	return nil
end

local function launcherRootFor(instance)
	if not instance then
		return nil
	end

	if OPEN_BUTTON_NAMES[string.lower(instance.Name)] then
		return instance
	end

	local parent = instance.Parent
	if parent and OPEN_BUTTON_NAMES[string.lower(parent.Name)] then
		return parent
	end

	return nil
end

local function applyLauncherState(root)
	if not root or not root.Parent then
		return
	end

	local unlocked = hasUnlockedCompanion()

	-- invisible=true e uma trava do DungeonHUDBootstrap. Ela so deve ser
	-- removida quando o jogador realmente possuir ao menos um companion.
	if unlocked and root:GetAttribute("invisible") == true then
		root:SetAttribute("invisible", nil)
	end

	if root:IsA("GuiObject") then
		root.Visible = unlocked
	end
	if root:IsA("GuiButton") then
		root.Active = unlocked
	end

	local clickTarget = root:IsA("GuiButton")
		and root
		or root:FindFirstChildWhichIsA("GuiButton", true)
	if clickTarget then
		if unlocked and clickTarget:GetAttribute("invisible") == true then
			clickTarget:SetAttribute("invisible", nil)
		end
		clickTarget.Visible = unlocked
		clickTarget.Active = unlocked
	end

	root:SetAttribute("CompanionUnlockVisible", unlocked)
end

local function updateAllLaunchers()
	local unlocked = hasUnlockedCompanion()
	local count = 0

	for root in pairs(launcherRoots) do
		if root.Parent then
			count += 1
			applyLauncherState(root)
		end
	end

	player:SetAttribute("DungeonCompanionButtonActive", unlocked)
	player:SetAttribute("DungeonCompanionButtonVisible", unlocked)
	player:SetAttribute("DungeonCompanionUnlockedCount", #snapshotEntries())
	player:SetAttribute("DungeonCompanionLauncherCount", count)
end

local function applyCard(card, entry, selected)
	card:SetAttribute("CompanionRuntimeCard", true)
	card:SetAttribute("CompanionInstanceId", entry.InstanceId)
	card:SetAttribute("CompanionSpeciesId", entry.SpeciesId)
	card.LayoutOrder = entry.LayoutOrder or 0

	setText(findText(card, { "CompanionName", "CardCompanionName" }), entry.DisplayName)

	local levelPanel = findNamedDescendant(card, { "CardLevelPanel" })
	local levelText = findText(card, { "CardLevelText", "LevelText" })
		or fallbackTextInside(levelPanel)
	setText(levelText, string.format("Nível %d", tonumber(entry.Level) or 1))
	setImage(findImage(levelPanel, { "LevelIcon", "ImageLabel" }), entry.LevelIconImageId)

	setImage(findImage(card, { "CompanionImage", "Image" }), entry.ImageId)
	setVisible(findNamedDescendant(card, { "SelectionGlow" }), selected)
	setVisible(findNamedDescendant(card, { "EquippedMark" }), entry.Equipped == true)
end

local function renderSelected(entry)
	if not selectedPanel then
		return
	end

	setVisible(selectedPanel, entry ~= nil)
	if not entry then
		return
	end

	setText(
		findText(selectedPanel, { "CompanionName", "SelectedCompanionName" }),
		entry.DisplayName
	)

	local levelPanel = findNamedDescendant(selectedPanel, { "CardLevelPanel", "LevelPanel" })
	local levelText = findText(
		selectedPanel,
		{ "CardLevelText", "LevelText", "SelectedLevelText" }
	) or fallbackTextInside(levelPanel)
	setText(levelText, string.format("Nível %d", tonumber(entry.Level) or 1))
	setImage(findImage(levelPanel, { "LevelIcon", "ImageLabel" }), entry.LevelIconImageId)
	setImage(findImage(selectedPanel, { "CompanionImage", "Image" }), entry.ImageId)

	local xp = math.max(0, math.floor(tonumber(entry.XP) or 0))
	local required = math.max(0, math.floor(tonumber(entry.XPRequired) or 0))
	local progress = required > 0 and xp / required or 1
	setText(
		findText(selectedPanel, { "LevelXP", "XPValue", "XPText", "XPAmount" }),
		required > 0 and string.format("%d / %d", xp, required) or "MAX"
	)
	setXPFill(findNamedDescendant(selectedPanel, { "XPBarFill" }), progress)

	renderStats(findNamedDescendant(selectedPanel, { "StatsPanel" }), entry.Stats)
	setVisible(findNamedDescendant(selectedPanel, { "EquipButton" }), entry.Equipped ~= true)
	setVisible(findNamedDescendant(selectedPanel, { "UnequipButton" }), entry.Equipped == true)
end

local function render()
	updateAllLaunchers()

	if not companionList or not cardTemplate or not currentSnapshot then
		return
	end

	disconnectAll(cardConnections)
	for _, child in ipairs(companionList:GetChildren()) do
		if child:GetAttribute("CompanionRuntimeCard") == true then
			child:Destroy()
		end
	end

	cardTemplate.Visible = false
	local entries = snapshotEntries()

	if selectedId and not getEntry(selectedId) then
		selectedId = nil
	end
	if not selectedId and entries[1] then
		selectedId = entries[1].InstanceId
	end

	for index, entry in ipairs(entries) do
		entry.LayoutOrder = index
		local card = cardTemplate:Clone()
		card.Name = "CompanionCard_" .. tostring(entry.InstanceId)
		card.Parent = companionList
		card.Visible = true
		applyCard(card, entry, entry.InstanceId == selectedId)

		local clickTarget = card:IsA("GuiButton")
			and card
			or card:FindFirstChildWhichIsA("GuiButton", true)
		if clickTarget then
			table.insert(cardConnections, clickTarget.Activated:Connect(function()
				selectedId = entry.InstanceId
				render()
			end))
		end
	end

	setVisible(findNamedDescendant(mainFrame, { "EmptyText" }), #entries == 0)
	renderSelected(getEntry(selectedId))

	if inventoryGui then
		inventoryGui:SetAttribute("CompanionSnapshotCount", #entries)
		inventoryGui:SetAttribute("CompanionSelectedInstanceId", selectedId)
	end
end

local function applySnapshot(snapshot, source)
	if type(snapshot) ~= "table" then
		return false
	end

	currentSnapshot = snapshot
	snapshotSerial += 1

	if inventoryGui then
		inventoryGui:SetAttribute("CompanionInventoryStatus", "SnapshotLoaded")
		inventoryGui:SetAttribute("CompanionSnapshotSource", tostring(source or "Unknown"))
		inventoryGui:SetAttribute("CompanionSnapshotSerial", snapshotSerial)
	end

	render()
	return true
end

local function requestSnapshot()
	if not request then
		if inventoryGui then
			inventoryGui:SetAttribute("CompanionInventoryStatus", "WaitingForServer")
		end
		return
	end

	local success, response = pcall(function()
		return request:InvokeServer("Get")
	end)

	if success and type(response) == "table" and type(response.Snapshot) == "table" then
		applySnapshot(response.Snapshot, "Request")
	elseif not success then
		if inventoryGui then
			inventoryGui:SetAttribute("CompanionInventoryStatus", "SnapshotFailed")
		end
		warn("[CompanionInventory] Nao foi possivel carregar companions:", response)
	end
end

local function invoke(action, first, second)
	if not request or isMutating then
		return false
	end

	isMutating = true
	local success, response = pcall(function()
		return request:InvokeServer(action, first, second)
	end)
	isMutating = false

	if not success then
		warn("[CompanionInventory] Falha ao falar com o servidor:", response)
		return false
	end

	if type(response) == "table" and type(response.Snapshot) == "table" then
		applySnapshot(response.Snapshot, "Mutation:" .. tostring(action))
	end

	return type(response) == "table" and response.Success ~= false
end

local function updateResponsiveScale()
	if not mainFrame or not mainFrame.Parent or not responsiveScale then
		return
	end

	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local availableWidth = math.max(1, viewport.X - VIEWPORT_PADDING.X * 2)
	local availableHeight = math.max(1, viewport.Y - VIEWPORT_PADDING.Y * 2)
	local width = math.max(1, tonumber(responsiveBaseWidth) or FALLBACK_MAIN_WIDTH)
	local height = math.max(1, tonumber(responsiveBaseHeight) or FALLBACK_MAIN_HEIGHT)

	local scale = math.min(availableWidth / width, availableHeight / height)
	scale = math.clamp(scale, MIN_RESPONSIVE_SCALE, MAX_RESPONSIVE_SCALE)
	responsiveScale.Scale = scale

	mainFrame:SetAttribute("CompanionResponsiveScale", scale)
	mainFrame:SetAttribute("CompanionResponsiveViewportWidth", math.floor(viewport.X + 0.5))
	mainFrame:SetAttribute("CompanionResponsiveViewportHeight", math.floor(viewport.Y + 0.5))
	player:SetAttribute("DungeonCompanionInventoryResponsiveScale", scale)
end

local function bindResponsiveMainFrame()
	if not mainFrame or not mainFrame:IsA("GuiObject") then
		return
	end

	responsiveBaseWidth = tonumber(mainFrame:GetAttribute("CompanionResponsiveBaseWidth"))
	responsiveBaseHeight = tonumber(mainFrame:GetAttribute("CompanionResponsiveBaseHeight"))

	if not responsiveBaseWidth or responsiveBaseWidth <= 0 then
		responsiveBaseWidth = math.abs(mainFrame.Size.X.Offset)
		if responsiveBaseWidth <= 0 then
			responsiveBaseWidth = mainFrame.AbsoluteSize.X
		end
		if responsiveBaseWidth <= 0 then
			responsiveBaseWidth = FALLBACK_MAIN_WIDTH
		end
		mainFrame:SetAttribute("CompanionResponsiveBaseWidth", responsiveBaseWidth)
	end

	if not responsiveBaseHeight or responsiveBaseHeight <= 0 then
		responsiveBaseHeight = math.abs(mainFrame.Size.Y.Offset)
		if responsiveBaseHeight <= 0 then
			responsiveBaseHeight = mainFrame.AbsoluteSize.Y
		end
		if responsiveBaseHeight <= 0 then
			responsiveBaseHeight = FALLBACK_MAIN_HEIGHT
		end
		mainFrame:SetAttribute("CompanionResponsiveBaseHeight", responsiveBaseHeight)
	end

	if mainFrame.Size.X.Scale ~= 0 or mainFrame.Size.Y.Scale ~= 0 then
		mainFrame.Size = UDim2.fromOffset(
			math.floor(responsiveBaseWidth + 0.5),
			math.floor(responsiveBaseHeight + 0.5)
		)
	end

	responsiveScale = mainFrame:FindFirstChild(RESPONSIVE_SCALE_NAME)
	if responsiveScale and not responsiveScale:IsA("UIScale") then
		responsiveScale:Destroy()
		responsiveScale = nil
	end
	if not responsiveScale then
		responsiveScale = Instance.new("UIScale")
		responsiveScale.Name = RESPONSIVE_SCALE_NAME
		responsiveScale.Parent = mainFrame
	end

	local function bindCamera(camera)
		if camera then
			table.insert(
				inventoryConnections,
				camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
			)
		end
		updateResponsiveScale()
	end

	bindCamera(Workspace.CurrentCamera)
	table.insert(
		inventoryConnections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindCamera(Workspace.CurrentCamera)
		end)
	)

	mainFrame:SetAttribute("CompanionResponsivePolicy", "UIScaleFitViewport")
	player:SetAttribute("DungeonCompanionInventoryResponsive", true)
end

local function hideInventory()
	if mainFrame then
		mainFrame.Visible = false
	end
	player:SetAttribute("DungeonCompanionInventoryOpen", false)
end

local function showInventory()
	if not hasUnlockedCompanion() then
		hideInventory()
		return
	end
	if mainFrame then
		mainFrame.Visible = true
		player:SetAttribute("DungeonCompanionInventoryOpen", true)
		requestSnapshot()
	end
end

local function registerLauncher(instance)
	local root = launcherRootFor(instance)
	if not root then
		return
	end
	if inventoryGui and root:IsDescendantOf(inventoryGui) then
		return
	end

	launcherRoots[root] = true
	applyLauncherState(root)

	local clickTarget = root:IsA("GuiButton")
		and root
		or root:FindFirstChildWhichIsA("GuiButton", true)
	if clickTarget and not boundLauncherButtons[clickTarget] then
		boundLauncherButtons[clickTarget] = true
		clickTarget.Activated:Connect(showInventory)
	end
end

local function scanLaunchers()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		registerLauncher(descendant)
	end
	updateAllLaunchers()
end

local function findInventoryGui()
	local direct = playerGui:FindFirstChild("CompanionInventoryGui")
	if direct and direct:IsA("ScreenGui") then
		return direct
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui")
			and child:FindFirstChild("MainFrame", true)
			and string.find(string.lower(child.Name), "companion")
		then
			return child
		end
	end

	return nil
end

local function bindInventoryGui(gui)
	disconnectAll(inventoryConnections)
	disconnectAll(cardConnections)

	inventoryGui = gui
	inventoryGui:SetAttribute("invisible", nil)
	inventoryGui.Enabled = true
	inventoryGui.ResetOnSpawn = false

	-- A posicao Y autorada passa a usar o topo REAL da viewport, sem a margem
	-- automatica reservada pelo Roblox para a top bar/CoreGui.
	inventoryGui.IgnoreGuiInset = true
	inventoryGui:SetAttribute("CompanionIgnoreGuiInset", true)
	inventoryGui:SetAttribute("CompanionInventoryControllerVersion", VERSION)

	mainFrame = findNamedDescendant(gui, { "MainFrame" })
	companionList = findNamedDescendant(mainFrame, { "CompanionList" })
	cardTemplate = findNamedDescendant(companionList, { "CompanionCardTemplate" })
	selectedPanel = findNamedDescendant(mainFrame, { "SelectedCompanion" })
	selectedId = nil

	if not mainFrame or not companionList or not cardTemplate or not selectedPanel then
		inventoryGui:SetAttribute("CompanionInventoryStatus", "HierarchyIncomplete")
		warn(
			"[CompanionInventory] Hierarquia incompleta: MainFrame, CompanionList, "
				.. "CompanionCardTemplate e SelectedCompanion sao obrigatorios."
		)
		return
	end

	mainFrame:SetAttribute("invisible", nil)
	mainFrame.Visible = false
	mainFrame:SetAttribute("CompanionPositionPolicy", "IgnoreRobloxTopInset")
	player:SetAttribute("DungeonCompanionInventoryOpen", false)
	player:SetAttribute("DungeonCompanionInventoryIgnoreGuiInset", true)

	if companionList:IsA("ScrollingFrame") then
		companionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end

	bindResponsiveMainFrame()

	local closeButton = findNamedDescendant(mainFrame, { "CloseButton" })
	if closeButton and closeButton:IsA("GuiButton") then
		table.insert(inventoryConnections, closeButton.Activated:Connect(hideInventory))
	end

	local equipButton = findNamedDescendant(selectedPanel, { "EquipButton" })
	if equipButton and equipButton:IsA("GuiButton") then
		table.insert(inventoryConnections, equipButton.Activated:Connect(function()
			local entry = getEntry(selectedId)
			if entry then
				invoke("SetEquipped", entry.InstanceId, true)
			end
		end))
	end

	local unequipButton = findNamedDescendant(selectedPanel, { "UnequipButton" })
	if unequipButton and unequipButton:IsA("GuiButton") then
		table.insert(inventoryConnections, unequipButton.Activated:Connect(function()
			local entry = getEntry(selectedId)
			if entry then
				invoke("SetEquipped", entry.InstanceId, false)
			end
		end))
	end

	if currentSnapshot then
		render()
	end
	requestSnapshot()
	scanLaunchers()
end

local function tryBindInventory(instance)
	if not instance or not instance:IsA("ScreenGui") then
		return false
	end
	if instance == inventoryGui then
		return true
	end
	if instance.Name == "CompanionInventoryGui"
		or (
			instance:FindFirstChild("MainFrame", true)
			and string.find(string.lower(instance.Name), "companion")
		)
	then
		bindInventoryGui(instance)
		return true
	end
	return false
end

local initialGui = findInventoryGui()
if initialGui then
	bindInventoryGui(initialGui)
end

-- O launcher deve iniciar oculto ate o servidor confirmar que existe ao menos
-- um companion salvo/desbloqueado.
scanLaunchers()
updateAllLaunchers()

playerGui.ChildAdded:Connect(function(child)
	if tryBindInventory(child) then
		return
	end
	registerLauncher(child)
end)

playerGui.DescendantAdded:Connect(function(instance)
	registerLauncher(instance)
end)

task.spawn(function()
	local remoteRequest = ReplicatedStorage:WaitForChild("CompanionRequest")
	local remoteEvent = ReplicatedStorage:WaitForChild("CompanionEvent")
	if not remoteRequest:IsA("RemoteFunction") or not remoteEvent:IsA("RemoteEvent") then
		warn("[CompanionInventory] Remotes de companions possuem classes incorretas.")
		return
	end

	request = remoteRequest
	event = remoteEvent
	player:SetAttribute("DungeonCompanionInventoryServerConnected", true)

	event.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Snapshot) == "table" then
			applySnapshot(payload.Snapshot, "CompanionEvent")
		end
	end)

	requestSnapshot()
end)

player:SetAttribute("DungeonCompanionInventoryControllerVersion", VERSION)
player:SetAttribute("DungeonCompanionButtonUnlockPolicy", "VisibleAfterFirstCompanion")
