-- CompanionInventoryController.client.luau
--
-- Conecta a CompanionInventoryGui criada manualmente no Studio ao sistema
-- persistente de companions. Este script NAO cria layout, moldura, botoes ou
-- imagens: ele apenas preenche e clona o CompanionCardTemplate ja existente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- A abertura da GUI nao depende dos remotes. Eles podem ser criados alguns
-- segundos depois pelo servidor; nesse caso a tela abre normalmente e os
-- dados sao carregados assim que CompanionService estiver pronto.
local request
local event

local OPEN_BUTTON_NAMES = {
	opencompanions = true,
	openinventorybutton = true,
	companionbutton = true,
	companioninventorybutton = true,
	companionlauncher = true,
}

local function isTextObject(instance)
	return instance
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function isImageObject(instance)
	return instance and (instance:IsA("ImageLabel") or instance:IsA("ImageButton"))
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
	local named = findNamedDescendant(root, names)
	if isTextObject(named) then
		return named
	end
	return nil
end

local function findImage(root, names)
	local named = findNamedDescendant(root, names)
	if isImageObject(named) then
		return named
	end
	return nil
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
	-- Enquanto os PNGs ainda nao tiverem sido enviados ao Roblox, preserva a
	-- imagem que voce colocou manualmente como placeholder no template.
	if isImageObject(instance) and type(imageId) == "string" and imageId ~= "" then
		instance.Image = imageId
	end
end

local function setVisible(instance, visible)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

local function setXPFill(fill, progress)
	if not fill or not fill:IsA("GuiObject") then
		return
	end

	local size = fill.Size
	fill.Size = UDim2.new(math.clamp(progress, 0, 1), 0, size.Y.Scale, size.Y.Offset)
end

local function numberText(value, decimals, suffix)
	local number = tonumber(value) or 0
	local format = decimals > 0 and ("%." .. tostring(decimals) .. "f") or "%.0f"
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

	-- O sistema de combate atual nao usa Vida/Defesa para companions. Em vez de
	-- exibir numeros falsos, os quatro espacos mostram os quatro atributos que
	-- realmente alteram o combate: dano, recarga, alcance e movimento.
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

local inventoryGui
local mainFrame
local companionList
local cardTemplate
local selectedPanel
local selectedId
local currentSnapshot
local cardConnections = {}
local guiConnections = {}
local boundOpenButtons = setmetatable({}, { __mode = "k" })
local isMutating = false

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getEntry(instanceId)
	if not currentSnapshot or type(currentSnapshot.Entries) ~= "table" then
		return nil
	end
	for _, entry in ipairs(currentSnapshot.Entries) do
		if entry.InstanceId == instanceId then
			return entry
		end
	end
	return nil
end

local function applyCard(card, entry, selected)
	card:SetAttribute("CompanionRuntimeCard", true)
	card:SetAttribute("CompanionInstanceId", entry.InstanceId)
	card:SetAttribute("CompanionSpeciesId", entry.SpeciesId)
	card.LayoutOrder = entry.LayoutOrder or 0

	setText(findText(card, { "CompanionName", "CardCompanionName" }), entry.DisplayName)

	local levelPanel = findNamedDescendant(card, { "CardLevelPanel" })
	local levelText = findText(card, { "CardLevelText", "LevelText" }) or fallbackTextInside(levelPanel)
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

	setText(findText(selectedPanel, { "CompanionName", "SelectedCompanionName" }), entry.DisplayName)

	local levelPanel = findNamedDescendant(selectedPanel, { "CardLevelPanel", "LevelPanel" })
	local levelText = findText(selectedPanel, { "CardLevelText", "LevelText", "SelectedLevelText" })
		or fallbackTextInside(levelPanel)
	setText(levelText, string.format("Nível %d", tonumber(entry.Level) or 1))
	setImage(findImage(levelPanel, { "LevelIcon", "ImageLabel" }), entry.LevelIconImageId)

	setImage(findImage(selectedPanel, { "CompanionImage", "Image" }), entry.ImageId)

	local xp = math.max(0, math.floor(tonumber(entry.XP) or 0))
	local required = math.max(0, math.floor(tonumber(entry.XPRequired) or 0))
	local progress = required > 0 and xp / required or 1
	setText(findText(selectedPanel, { "LevelXP", "XPValue", "XPText", "XPAmount" }), required > 0 and string.format("%d / %d", xp, required) or "MAX")
	setXPFill(findNamedDescendant(selectedPanel, { "XPBarFill" }), progress)

	renderStats(findNamedDescendant(selectedPanel, { "StatsPanel" }), entry.Stats)
	setVisible(findNamedDescendant(selectedPanel, { "EquipButton" }), entry.Equipped ~= true)
	setVisible(findNamedDescendant(selectedPanel, { "UnequipButton" }), entry.Equipped == true)
end

local function invoke(action, first, second)
	if not request then
		warn("[CompanionInventory] O sistema de companions ainda esta carregando.")
		return
	end
	if isMutating then
		return
	end
	isMutating = true
	local success, response = pcall(function()
		return request:InvokeServer(action, first, second)
	end)
	isMutating = false

	if not success then
		warn("[CompanionInventory] Falha ao falar com o servidor:", response)
		return
	end

	if type(response) == "table" and type(response.Snapshot) == "table" then
		currentSnapshot = response.Snapshot
	end
end

local function render()
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
	local entries = currentSnapshot.Entries or {}
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

		local clickTarget = card:IsA("GuiButton") and card or card:FindFirstChildWhichIsA("GuiButton", true)
		if clickTarget then
			table.insert(cardConnections, clickTarget.Activated:Connect(function()
				selectedId = entry.InstanceId
				render()
			end))
		end
	end

	setVisible(findNamedDescendant(mainFrame, { "EmptyText" }), #entries == 0)
	renderSelected(getEntry(selectedId))
end

local function requestSnapshot()
	if not request then
		return
	end
	local success, response = pcall(function()
		return request:InvokeServer("Get")
	end)
	if success and type(response) == "table" and type(response.Snapshot) == "table" then
		currentSnapshot = response.Snapshot
		if inventoryGui then
			inventoryGui:SetAttribute("CompanionSnapshotCount", #(currentSnapshot.Entries or {}))
			inventoryGui:SetAttribute("CompanionInventoryStatus", "SnapshotLoaded")
		end
		render()
	elseif not success then
		if inventoryGui then
			inventoryGui:SetAttribute("CompanionInventoryStatus", "SnapshotFailed")
		end
		warn("[CompanionInventory] Nao foi possivel carregar os companions:", response)
	end
end

local function showInventory()
	if mainFrame then
		mainFrame.Visible = true
		requestSnapshot()
	end
end

local function hideInventory()
	if mainFrame then
		mainFrame.Visible = false
	end
end

local function connectButton(button, callback)
	if button and button:IsA("GuiButton") then
		table.insert(guiConnections, button.Activated:Connect(callback))
	end
end

local function isOpenButton(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end
	if OPEN_BUTTON_NAMES[string.lower(button.Name)] then
		return true
	end
	-- Estrutura manual atual: DungeonHUD > CompanionButton (Frame) > ImageButton.
	-- Assim o artista pode manter o ImageButton com o nome padrao do Studio.
	local parent = button.Parent
	return parent and OPEN_BUTTON_NAMES[string.lower(parent.Name)] == true
end

local function connectOpenButton(button)
	if not isOpenButton(button)
		or button:IsDescendantOf(inventoryGui)
		or boundOpenButtons[button]
	then
		return
	end
	boundOpenButtons[button] = true
	connectButton(button, showInventory)
end

local function bindOpenButtons()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		connectOpenButton(descendant)
	end
end

local function findInventoryGui()
	local direct = playerGui:FindFirstChild("CompanionInventoryGui")
	if direct and direct:IsA("ScreenGui") then
		return direct
	end
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child:FindFirstChild("MainFrame") and string.find(string.lower(child.Name), "companion") then
			return child
		end
	end
	return nil
end

local function bindInventoryGui(gui)
	disconnectAll(guiConnections)
	disconnectAll(cardConnections)
	boundOpenButtons = setmetatable({}, { __mode = "k" })

	inventoryGui = gui
	mainFrame = gui:FindFirstChild("MainFrame")
	companionList = findNamedDescendant(mainFrame, { "CompanionList" })
	cardTemplate = findNamedDescendant(companionList, { "CompanionCardTemplate" })
	selectedPanel = findNamedDescendant(mainFrame, { "SelectedCompanion" })
	selectedId = nil
	currentSnapshot = nil

	if not mainFrame or not companionList or not cardTemplate or not selectedPanel then
		warn("[CompanionInventory] Hierarquia incompleta. Sao necessarios MainFrame, CompanionList, CompanionCardTemplate e SelectedCompanion.")
		return
	end

	if not companionList:IsA("ScrollingFrame") then
		warn("[CompanionInventory] CompanionList deve ser um ScrollingFrame.")
	else
		-- Garante que a lista continue rolando quando o jogador possuir muitos
		-- companions, sem mudar o tamanho ou a grade que voce desenhou.
		companionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end

	connectButton(findNamedDescendant(mainFrame, { "CloseButton" }), hideInventory)
	connectButton(findNamedDescendant(selectedPanel, { "EquipButton" }), function()
		local entry = getEntry(selectedId)
		if entry then
			invoke("SetEquipped", entry.InstanceId, true)
			render()
		end
	end)
	connectButton(findNamedDescendant(selectedPanel, { "UnequipButton" }), function()
		local entry = getEntry(selectedId)
		if entry then
			invoke("SetEquipped", entry.InstanceId, false)
			render()
		end
	end)

	bindOpenButtons()
	requestSnapshot()
end

local initialGui = findInventoryGui()
if initialGui then
	bindInventoryGui(initialGui)
end

playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and (child.Name == "CompanionInventoryGui" or (child:FindFirstChild("MainFrame") and string.find(string.lower(child.Name), "companion"))) then
		bindInventoryGui(child)
		return
	end

	connectOpenButton(child)
end)

-- DungeonHUD e CompanionInventoryGui podem ser copiados para PlayerGui em
-- ordens diferentes. Observando descendentes, o ImageButton recebe o clique
-- mesmo quando o DungeonHUD chegar depois do inventario.
playerGui.DescendantAdded:Connect(connectOpenButton)

task.spawn(function()
	local remoteRequest = ReplicatedStorage:WaitForChild("CompanionRequest")
	local remoteEvent = ReplicatedStorage:WaitForChild("CompanionEvent")
	if not remoteRequest:IsA("RemoteFunction") or not remoteEvent:IsA("RemoteEvent") then
		warn("[CompanionInventory] Remotes de companions possuem classes incorretas.")
		return
	end

	request = remoteRequest
	event = remoteEvent
	event.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Snapshot) == "table" then
			currentSnapshot = payload.Snapshot
			render()
		end
	end)
	requestSnapshot()
end)
