local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local choiceEvent = orbFolder:WaitForChild("OrbChoiceEvent")
local choiceRequest = orbFolder:WaitForChild("OrbChoiceRequest")

local activePanel
local activeCards = {}
local activeButtonConnections = {}
local activeOfferOptions = {}
local submitting = false

-- O painel criado pelo Lemonade, dentro do DungeonHUD, e a unica interface
-- permitida para a escolha de Orb.
local function looksLikeOrbChoicePanel(instance)
	local name = string.lower(instance.Name)
	local mentionsOrb = string.find(name, "orb", 1, true) ~= nil
	local mentionsChoice = string.find(name, "choice", 1, true) ~= nil
		or string.find(name, "select", 1, true) ~= nil
		or string.find(name, "choose", 1, true) ~= nil
	return instance:IsA("GuiObject") and mentionsOrb and mentionsChoice
end

local function findLemonadePanel()
	for _, instance in ipairs(playerGui:GetDescendants()) do
		if looksLikeOrbChoicePanel(instance) then
			local screenGui = instance:FindFirstAncestorOfClass("ScreenGui")
			if screenGui and screenGui.Name == "DungeonHUD" then
				return instance
			end
		end
	end
	return nil
end

local function hideOtherOrbChoicePanels(keepPanel)
	local found = {}
	for _, instance in ipairs(playerGui:GetDescendants()) do
		if looksLikeOrbChoicePanel(instance) then
			table.insert(found, instance:GetFullName())
			if instance ~= keepPanel and not instance:IsDescendantOf(keepPanel) then
				local screenGui = instance:FindFirstAncestorOfClass("ScreenGui")
				if screenGui and screenGui.Name == "OrbChoiceGui" then
					screenGui:Destroy()
				else
					instance.Visible = false
				end
			end
		end
	end
	print(string.format("[OrbChoiceLemonadeOnlyV2] %d paineis de Orb localizados: %s", #found, table.concat(found, " | ")))
end

-- Se um LocalScript antigo criar sua tela depois da escolha ja estar aberta,
-- ela tambem e imediatamente ocultada. Isso elimina a corrida entre a copia
-- legada do Studio e o HUD atual do Lemonade.
playerGui.DescendantAdded:Connect(function(instance)
	if activePanel and looksLikeOrbChoicePanel(instance) then
		task.defer(function()
			if activePanel and instance.Parent and instance ~= activePanel then
				local screenGui = instance:FindFirstAncestorOfClass("ScreenGui")
				if screenGui and screenGui.Name == "OrbChoiceGui" then
					screenGui:Destroy()
				else
					instance.Visible = false
				end
			end
		end)
	end
end)

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

local function ensureCards(panel)
	local cards = {}
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
			warn(string.format(
				"[OrbChoiceLemonadeOnlyV2] O painel do Lemonade precisa ter '%sCard' ou OrbCardTemplate.",
				orbName
			))
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

local function mapOfferOptions(options)
	local result = {}
	for _, option in ipairs(options or {}) do
		if type(option) == "table" and typeof(option.Orb) == "string" and typeof(option.ChoiceType) == "string" then
			result[option.Orb] = option
		end
	end
	return result
end

local function populateCard(card, orbName, milestone, serial, offeredOption)
	if not card then
		return
	end

	local definition = OrbConfig.GetOrb(orbName)
	local currentLevel = currentOrbLevel(orbName)
	local nextLevel = math.min(currentLevel + 1, OrbConfig.MaxOrbLevel)
	local isNew = currentLevel == 0
	local available = offeredOption ~= nil

	local nameText = findText(card, { "OrbName", "Name", "Title" })
	local levelText = findText(card, { "OrbLevel", "Level" })
	local descriptionText = findText(card, { "Description", "OrbDescription" })
	local badge = findText(card, { "NewBadge", "Badge" })
	local upgradeText = findText(card, { "UpgradeInfo", "Stats", "BeforeAfter" })
	local button = findButton(card)
	if not button then
		warn(string.format("[OrbChoiceLemonadeOnlyV2] '%sCard' do Lemonade nao possui botao de escolha.", orbName))
		return
	end

	if nameText then
		nameText.Text = string.upper(definition.DisplayName)
	end
	if levelText then
		levelText.Text = string.format("Level %d", nextLevel)
	end
	if descriptionText then
		descriptionText.Text = available and definition.Description or (isNew and "Orb raro. Continue jogando para ter a chance de encontrá-lo." or definition.Description)
	end
	if badge then
		badge.Visible = isNew
		badge.Text = "NEW"
	end
	if upgradeText then
		if available then
			local summary = OrbConfig.GetUpgradeSummary(orbName, currentLevel)
			local ability = not isNew and OrbConfig.GetMilestoneAbility(orbName, nextLevel) or nil
			if ability then
				summary ..= string.format("\nNOVA HABILIDADE: %s\n%s", string.upper(ability.Name), ability.Description)
			end
			upgradeText.Text = summary
		else
			upgradeText.Text = isNew and "DISPONIBILIDADE RARA" or "MAX"
		end
	end
	if button then
		local oldConnection = activeButtonConnections[button]
		if oldConnection then
			oldConnection:Disconnect()
		end
		button.Active = available
		button.AutoButtonColor = available
		if button:IsA("TextButton") then
			button.Text = available and (offeredOption.ChoiceType == "NewOrb" and "CHOOSE" or "UPGRADE") or (isNew and "RARE" or "MAX")
		end
		button.Modal = true
		activeButtonConnections[button] = button.Activated:Connect(function()
			if submitting or not available then
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
				ChoiceType = offeredOption.ChoiceType,
				MilestoneLevel = milestone,
				Serial = serial,
			})
		end)
	end
end

local function setPanelVisible(panel, visible)
	panel.Visible = visible
end

local function showOffer(milestone, serial, options)
	milestone = math.floor(tonumber(milestone) or 0)
	serial = math.floor(tonumber(serial) or 0)
	if milestone <= 0 or serial <= 0 then
		return
	end

	local panel = findLemonadePanel()
	if not panel then
		warn("[OrbChoiceLemonadeOnlyV2] Escolha de Orb aguardando: DungeonHUD > OrbChoicePanel do Lemonade nao foi encontrado. Nenhuma GUI alternativa sera criada.")
		return
	end
	hideOtherOrbChoicePanels(panel)
	activePanel = panel
	activeCards = ensureCards(panel)
	if options then
		activeOfferOptions = mapOfferOptions(options)
	end
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
		populateCard(activeCards[orbName], orbName, milestone, serial, activeOfferOptions[orbName])
	end
	setPanelVisible(panel, true)
end

local function hideOffer()
	if activePanel then
		setPanelVisible(activePanel, false)
	end
	activePanel = nil
	activeCards = {}
	activeOfferOptions = {}
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
		showOffer(payload.MilestoneLevel, payload.Serial, payload.Options)
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

print("[OrbChoiceLemonadeOnlyV2] Sistema Lemonade-only pronto")
