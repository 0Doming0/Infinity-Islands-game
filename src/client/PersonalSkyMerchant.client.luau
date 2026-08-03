-- Interacao privada do Mercador do Ceu compartilhado.
--
-- O servidor cria exatamente um modelo replicado para cada jogador elegivel.
-- Todos podem ver a loja, mas somente o proprietario cria localmente o prompt,
-- abre suas recomendacoes e informa o estado do encontro.
--
-- Este LocalScript nunca clona, move ou rotaciona a loja. A representacao fica
-- presa a ilha normal escolhida pelo servidor e desaparece junto com ela.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")
local monetizationEvent = ReplicatedStorage:WaitForChild("MonetizationEvent")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local MODEL_NAME = "PersonalSkyMerchant_" .. tostring(player.UserId)
local LOCAL_INTERACTION_NAME = "PersonalSkyMerchantLocalInteraction"
local UI_EVENT_NAME = "PersonalSkyMerchantOpen"
local CHECK_SECONDS = 0.5
local VERSION = "SharedVisualPrivateInteractionV5"

local activeModel
local activeAnchor
local activePrompt
local activeAttachment
local activeHint
local activeOfferSerial
local encounterState = "Inactive"
local promptVisibleSince
local nearbySince
local awaySince
local updateQueued = false
local openRequestInFlight = false
local encounterReportInFlight = false

local function getLivingRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function getSkyIsland(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("IsSkyIsland") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getIslandKey(island)
	return island and tostring(island:GetAttribute("IslandNodeKey") or "") or ""
end

local function isVillageOrSanctuary(island)
	if not island or not island:IsA("Model") then
		return true
	end
	if island:GetAttribute("VillageSpawned") == true
		or island:GetAttribute("IsSocialSanctuary") == true
	then
		return true
	end
	local role = string.lower(tostring(island:GetAttribute("IslandRole") or ""))
	if string.find(role, "sanctuary", 1, true)
		or string.find(role, "village", 1, true)
	then
		return true
	end
	local village = island:FindFirstChild("MVPVillage")
	if village then
		return true
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:GetAttribute("ProceduralVillage") == true then
			return true
		end
	end
	return false
end

local function isNormalMerchantIsland(island)
	return island
		and island:IsA("Model")
		and island:IsDescendantOf(workspace)
		and island:GetAttribute("IsSkyIsland") == true
		and tostring(island:GetAttribute("IslandType") or "Normal") == "Normal"
		and not isVillageOrSanctuary(island)
end

local function isOwnedMerchant(model)
	return model
		and model:IsA("Model")
		and model:IsDescendantOf(workspace)
		and model:GetAttribute("ServerManagedPersonalSkyMerchant") == true
		and tonumber(model:GetAttribute("OwnerUserId")) == player.UserId
end

local function findOwnedMerchant()
	local direct = workspace:FindFirstChild(MODEL_NAME, true)
	if isOwnedMerchant(direct) then
		return direct
	end
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.Name == MODEL_NAME and isOwnedMerchant(descendant) then
			return descendant
		end
	end
	return nil
end

local function openOfficialMerchantUI(store)
	-- A interface oficial e a unica responsavel por desenhar e comprar ofertas.
	-- Este script apenas entrega o Store retornado pelo servidor ao BindableEvent
	-- criado por MonetizationUI.client.luau. Ele nunca cria uma segunda loja UI.
	local openEvent = playerGui:FindFirstChild(UI_EVENT_NAME)
	if not openEvent then
		openEvent = playerGui:WaitForChild(UI_EVENT_NAME, 1.5)
	end
	if not openEvent or not openEvent:IsA("BindableEvent") then
		player:SetAttribute("PersonalSkyMerchantLastOpenError", "MerchantUIEventMissing")
		return false
	end
	openEvent:Fire(store)
	player:SetAttribute("PersonalSkyMerchantOpenTransport", "OfficialUIEventV5")
	return true
end

local function reportEncounter(outcome)
	if encounterReportInFlight
		or activeOfferSerial == nil
		or player:GetAttribute("MerchantOfferReady") ~= true
	then
		return false
	end
	if outcome == "Presented" and encounterState ~= "Unseen" then
		return false
	end
	if outcome == "Ignored" and encounterState ~= "Presented" then
		return false
	end
	local previous = encounterState
	encounterState = outcome
	encounterReportInFlight = true
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", outcome)
	task.spawn(function()
		local success, result = pcall(request.InvokeServer, request, "PersonalMerchantEncounter", {
			Outcome = outcome,
			OfferSerial = activeOfferSerial,
		})
		encounterReportInFlight = false
		if success and type(result) == "table" and type(result.State) == "string" then
			encounterState = result.State
		elseif not success or type(result) ~= "table" or result.Success ~= true then
			encounterState = previous
		end
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	end)
	return true
end

local function removeInteraction(state)
	if activeAttachment then
		activeAttachment:Destroy()
	end
	if activeModel then
		local localInteraction = activeModel:FindFirstChild(LOCAL_INTERACTION_NAME)
		if localInteraction then
			localInteraction:Destroy()
		end
	end
	activeModel = nil
	activeAnchor = nil
	activePrompt = nil
	activeAttachment = nil
	activeHint = nil
	promptVisibleSince = nil
	nearbySince = nil
	awaySince = nil
	player:SetAttribute("PersonalSkyMerchantClientState", state or "WaitingForSharedMerchant")
end

local function openMerchant()
	if openRequestInFlight or not activeModel or not activeAnchor or not activePrompt then
		return
	end
	local root = getLivingRoot()
	if not root then
		return
	end
	if (root.Position - activeAnchor.Position).Magnitude > activePrompt.MaxActivationDistance + 1 then
		return
	end

	openRequestInFlight = true
	activePrompt.Enabled = false
	if activeHint then
		activeHint.Enabled = false
	end
	player:SetAttribute("PersonalSkyMerchantClientState", "Opening")
	player:SetAttribute("PersonalSkyMerchantLastOpenError", nil)

	local success, result = pcall(request.InvokeServer, request, "ActivatePersonalMerchant")
	openRequestInFlight = false
	if activePrompt and activePrompt.Parent then
		activePrompt.Enabled = true
	end

	local store = type(result) == "table" and result.Store or nil
	local validStore = type(store) == "table"
		and type(store.Entries) == "table"
		and #store.Entries > 0
	if not success or type(result) ~= "table" or result.Success ~= true or not validStore then
		player:SetAttribute("PersonalSkyMerchantClientState", "OpenRejected")
		player:SetAttribute(
			"PersonalSkyMerchantLastOpenError",
			tostring(type(result) == "table" and result.Message or result)
		)
		return
	end

	encounterState = "Opened"
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	player:SetAttribute("PersonalSkyMerchantClientState", "OpenAccepted")
	player:SetAttribute("PersonalSkyMerchantLastStoreEntryCount", #store.Entries)
	player:SetAttribute("PersonalSkyMerchantLastOpenSerial", result.OpenSerial)

	if not openOfficialMerchantUI(store) then
		-- O servidor tambem emite OpenPersonalMerchant. A segunda tentativa cobre
		-- o raro caso de a ponte estar sendo recriada no mesmo frame.
		task.delay(0.25, function()
			local state = tostring(player:GetAttribute("PersonalSkyMerchantUIState") or "")
			if not string.find(state, "Open", 1, true) then
				openOfficialMerchantUI(store)
			end
		end)
	end
end

local function createInteraction(model)
	local island = getSkyIsland(model)
	local targetKey = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
	if not isNormalMerchantIsland(island)
		or targetKey == ""
		or getIslandKey(island) ~= targetKey
		or tostring(model:GetAttribute("SpawnIslandKey") or "") ~= targetKey
	then
		return false
	end

	local anchor = model:FindFirstChild("MerchantInteractionAnchor", true)
	if not anchor or not anchor:IsA("BasePart") then
		player:SetAttribute("PersonalSkyMerchantClientState", "WaitingForInteractionAnchor")
		return false
	end

	local previous = model:FindFirstChild(LOCAL_INTERACTION_NAME)
	if previous then
		previous:Destroy()
	end
	local localInteraction = Instance.new("Folder")
	localInteraction.Name = LOCAL_INTERACTION_NAME
	localInteraction.Parent = model

	for _, child in ipairs(anchor:GetChildren()) do
		if child.Name == "PersonalSkyMerchantPromptAttachment" then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PersonalSkyMerchantPromptAttachment"
	attachment.Parent = anchor
	attachment:SetAttribute("OwnerUserId", player.UserId)

	local promptDistance = math.max(10, tonumber(MVPConfig.Village.PromptDistance) or 13)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PersonalSkyMerchantPrompt"
	prompt.ActionText = "Ver ofertas"
	prompt.ObjectText = "Mercador do Céu"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = promptDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Enabled = true
	prompt.Parent = attachment

	local hint = Instance.new("BillboardGui")
	hint.Name = "PersonalSkyMerchantInteractionHint"
	hint.Adornee = anchor
	hint.Size = UDim2.fromOffset(250, 64)
	hint.StudsOffsetWorldSpace = Vector3.new(0, 0.65, 0)
	hint.AlwaysOnTop = true
	hint.MaxDistance = promptDistance + 5
	hint.Enabled = false
	hint.Active = true
	hint.Parent = localInteraction

	local button = Instance.new("TextButton")
	button.Name = "InteractButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(13, 25, 40)
	button.BackgroundTransparency = 0.08
	button.BorderSizePixel = 0
	button.Text = "[ E ]  VER OFERTAS"
	button.TextColor3 = Color3.fromRGB(245, 249, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.AutoButtonColor = true
	button.Parent = hint
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 210, 86)
	stroke.Transparency = 0.2
	stroke.Thickness = 1.5
	stroke.Parent = button

	activeModel = model
	activeAnchor = anchor
	activePrompt = prompt
	activeAttachment = attachment
	activeHint = hint
	promptVisibleSince = nil
	nearbySince = nil
	awaySince = nil

	prompt.PromptShown:Connect(function()
		if activePrompt ~= prompt then
			return
		end
		hint.Enabled = true
		local shownAt = workspace:GetServerTimeNow()
		promptVisibleSince = shownAt
		task.delay(
			math.max(0.25, tonumber(MVPConfig.Village.PersonalSkyMerchantPromptPresentationSeconds) or 1.5),
			function()
				if activePrompt == prompt
					and promptVisibleSince == shownAt
					and encounterState == "Unseen"
				then
					reportEncounter("Presented")
				end
			end
		)
	end)
	prompt.PromptHidden:Connect(function()
		if activePrompt == prompt then
			promptVisibleSince = nil
			hint.Enabled = false
		end
	end)
	prompt.Triggered:Connect(openMerchant)
	button.Activated:Connect(openMerchant)

	player:SetAttribute("PersonalSkyMerchantClientVersion", VERSION)
	player:SetAttribute("PersonalSkyMerchantClientState", "AttachedToSharedMerchant")
	player:SetAttribute("PersonalSkyMerchantPromptMode", "OwnerOnlyCustomPromptV5")
	player:SetAttribute("PersonalSkyMerchantVisualMode", "ServerSharedOnePerPlayer")
	return true
end

local function syncOfferState()
	if player:GetAttribute("MerchantOfferReady") ~= true then
		activeOfferSerial = nil
		encounterState = "Inactive"
		removeInteraction("WaitingForRecommendation")
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
		return false
	end
	local serial = math.max(0, math.floor(tonumber(player:GetAttribute("MerchantOffersShown")) or 0))
	if activeOfferSerial ~= serial then
		activeOfferSerial = serial
		encounterState = "Unseen"
		removeInteraction("WaitingForSharedMerchant")
	end
	local serverState = player:GetAttribute("PersonalSkyMerchantEncounterState")
	if type(serverState) == "string" and serverState ~= "" then
		encounterState = serverState
	end
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	return true
end

local function update()
	updateQueued = false
	if not syncOfferState() then
		return
	end
	if encounterState == "Ignored" or encounterState == "Dismissed" or encounterState == "Purchased" then
		removeInteraction("EncounterEnded:" .. encounterState)
		return
	end

	local model = findOwnedMerchant()
	if not model then
		removeInteraction("WaitingForSharedMerchant")
		return
	end
	local island = getSkyIsland(model)
	local targetKey = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
	if not isNormalMerchantIsland(island)
		or targetKey == ""
		or getIslandKey(island) ~= targetKey
	then
		removeInteraction("RejectedInvalidMerchantIsland")
		return
	end
	if activeModel ~= model or not activePrompt or not activePrompt.Parent then
		removeInteraction("RebindingSharedMerchant")
		if not createInteraction(model) then
			return
		end
	end

	if player:GetAttribute("ShopOpen") == true
		and player:GetAttribute("ActiveShopId") == "SkyMerchant"
	then
		encounterState = "Opened"
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	end

	local root = getLivingRoot()
	if not root or not activeAnchor or not activePrompt then
		return
	end
	local distance = (root.Position - activeAnchor.Position).Magnitude
	activeHint.Enabled = activePrompt.Enabled
		and distance <= activePrompt.MaxActivationDistance + 0.5
		and encounterState ~= "Ignored"
		and encounterState ~= "Dismissed"
		and encounterState ~= "Purchased"

	local currentKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
	local activeIslandKey = getIslandKey(island)
	if encounterState == "Unseen" then
		local nearbyDistance = math.max(
			activePrompt.MaxActivationDistance,
			tonumber(MVPConfig.Village.PersonalSkyMerchantNearbyPresentationDistance) or 28
		)
		if currentKey == activeIslandKey and distance <= nearbyDistance then
			nearbySince = nearbySince or workspace:GetServerTimeNow()
			if workspace:GetServerTimeNow() - nearbySince
				>= math.max(0.5, tonumber(MVPConfig.Village.PersonalSkyMerchantNearbyPresentationSeconds) or 4)
			then
				reportEncounter("Presented")
			end
		else
			nearbySince = nil
		end
	elseif encounterState == "Presented" then
		local leftIsland = currentKey ~= "" and currentKey ~= activeIslandKey
		local tooFar = distance > math.max(
			activePrompt.MaxActivationDistance + 1,
			tonumber(MVPConfig.Village.PersonalSkyMerchantIgnoreDistance) or 65
		)
		if leftIsland or tooFar then
			awaySince = awaySince or workspace:GetServerTimeNow()
			if workspace:GetServerTimeNow() - awaySince
				>= math.max(0.5, tonumber(MVPConfig.Village.PersonalSkyMerchantIgnoreSeconds) or 3)
			then
				reportEncounter("Ignored")
				removeInteraction("IgnoredAfterDiscovery")
			end
		else
			awaySince = nil
		end
	end
end

local function queueUpdate()
	if updateQueued then
		return
	end
	updateQueued = true
	task.defer(update)
end

local function tryInteractFromInput(input, processed)
	if processed
		or UserInputService:GetFocusedTextBox()
		or not activePrompt
		or not activePrompt.Enabled
		or not activeAnchor
	then
		return
	end
	local keyboardE = input.UserInputType == Enum.UserInputType.Keyboard
		and input.KeyCode == Enum.KeyCode.E
	local gamepadX = input.KeyCode == Enum.KeyCode.ButtonX
	if not keyboardE and not gamepadX then
		return
	end
	local root = getLivingRoot()
	if root and (root.Position - activeAnchor.Position).Magnitude <= activePrompt.MaxActivationDistance + 1 then
		openMerchant()
	end
end

UserInputService.InputBegan:Connect(tryInteractFromInput)
for _, attribute in ipairs({
	"MerchantOfferReady",
	"MerchantOffersShown",
	"MerchantRecommendedProductIds",
	"PersonalSkyMerchantEncounterState",
	"PersonalSkyMerchantTargetIslandKey",
	"CurrentIslandKey",
	"ShopOpen",
	"ActiveShopId",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(queueUpdate)
end
player.CharacterAdded:Connect(function()
	removeInteraction("CharacterRespawning")
	task.delay(1, queueUpdate)
end)
workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model")
		and (
			instance.Name == MODEL_NAME
			or instance:GetAttribute("ServerManagedPersonalSkyMerchant") == true
		)
	then
		queueUpdate()
	end
end)
workspace.DescendantRemoving:Connect(function(instance)
	if instance == activeModel or instance == activeAnchor then
		removeInteraction("SharedMerchantRemovedWithIsland")
		queueUpdate()
	end
end)
monetizationEvent.OnClientEvent:Connect(function(data)
	if type(data) == "table"
		and (
			data.Action == "OfferReady"
			or data.Action == "OfferEnded"
			or data.Action == "OpenPersonalMerchant"
			or data.Action == "PurchaseGranted"
			or data.Action == "Entitlements"
		)
	then
		queueUpdate()
	end
end)

task.spawn(function()
	while true do
		task.wait(CHECK_SECONDS)
		queueUpdate()
	end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Model")
		and descendant:GetAttribute("PersonalSkyMerchantScene") == true
		and tonumber(descendant:GetAttribute("OwnerUserId")) == player.UserId
	then
		-- Remove somente cenas locais das versoes antigas. O modelo oficial V5
		-- possui ServerManagedPersonalSkyMerchant e e mantido pelo servidor.
		descendant:Destroy()
	end
end

player:SetAttribute("PersonalSkyMerchantClientVersion", VERSION)
queueUpdate()
