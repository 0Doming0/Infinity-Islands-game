-- Escolhe uma unica ilha futura para cada encontro do Mercador do Ceu.
--
-- O gerador continua sendo a autoridade sobre a rota pretendida do jogador.
-- Este controlador apenas converte essa intencao em um encontro persistente:
-- depois que uma ilha futura e escolhida, o alvo nao muda porque o jogador
-- olhou para outro lado. Sem uma ilha futura valida, o mercador nao aparece.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TARGET_VALUE_NAME = "PersonalSkyMerchantTargetIsland"
local INTENT_VALUE_NAME = "WorldIntentTargetIsland"
local CHECK_SECONDS = 0.5
local WATER_CLEARANCE_STUDS = 8
local VERSION = "FutureNormalIslandLockedV2"

local states = setmetatable({}, { __mode = "k" })

local function getIslandKey(island)
	if not island or not island:IsA("Model") then
		return ""
	end
	return tostring(island:GetAttribute("IslandNodeKey") or "")
end

local function getOrCreateTargetValue(player)
	local value = player:FindFirstChild(TARGET_VALUE_NAME)
	if value and not value:IsA("ObjectValue") then
		value:Destroy()
		value = nil
	end
	if not value then
		value = Instance.new("ObjectValue")
		value.Name = TARGET_VALUE_NAME
		value.Parent = player
	end
	return value
end

local function clearTarget(player, state, assignmentState)
	state.Target = nil
	state.TargetKey = nil
	state.TargetOfferSerial = nil
	local value = getOrCreateTargetValue(player)
	value.Value = nil
	player:SetAttribute("PersonalSkyMerchantTargetIslandKey", nil)
	player:SetAttribute("PersonalSkyMerchantTargetLockedAt", nil)
	player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", assignmentState or "WaitingForFutureIsland")
end

local function findIslandByKey(key)
	if type(key) ~= "string" or key == "" then
		return nil
	end
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("IsSkyIsland") == true
			and getIslandKey(descendant) == key
		then
			return descendant
		end
	end
	return nil
end

local function resolveIntentIsland(player)
	local intentValue = player:FindFirstChild(INTENT_VALUE_NAME)
	local island = intentValue and intentValue:IsA("ObjectValue") and intentValue.Value or nil
	local key = tostring(player:GetAttribute("WorldIntentTargetIslandKey") or "")
	if island and island:IsA("Model") and getIslandKey(island) == key then
		return island
	end
	return findIslandByKey(key)
end

local function isVillageOrSanctuary(island)
	if not island or not island:IsA("Model") then
		return true
	end
	if island:GetAttribute("VillageSpawned") == true
		or island:GetAttribute("IsSocialSanctuary") == true
		or CollectionService:HasTag(island, "SkyDungeonSanctuary")
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
	if village
		and (
			village:GetAttribute("ProceduralVillage") == true
			or village:IsA("Folder")
		)
	then
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

local function isAboveWater(island)
	local floor = island:FindFirstChild("IslandFloor")
	if not floor or not floor:IsA("BasePart") then
		return false
	end
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	if not surfaceY then
		return true
	end
	return floor.Position.Y + floor.Size.Y / 2 > surfaceY + WATER_CLEARANCE_STUDS
end

local function isFutureCandidate(player, state, island)
	if not isNormalMerchantIsland(island) then
		return false
	end
	local key = getIslandKey(island)
	if key == ""
		or key == tostring(player:GetAttribute("CurrentIslandKey") or "")
		or state.VisitedKeys[key] == true
	then
		return false
	end
	if not isAboveWater(island) then
		return false
	end
	return true
end

local function lockTarget(player, state, island)
	local key = getIslandKey(island)
	if key == "" then
		return false
	end
	state.Target = island
	state.TargetKey = key
	state.TargetOfferSerial = math.max(0, math.floor(tonumber(player:GetAttribute("MerchantOffersShown")) or 0))
	local value = getOrCreateTargetValue(player)
	value.Value = island
	player:SetAttribute("PersonalSkyMerchantTargetIslandKey", key)
	player:SetAttribute("PersonalSkyMerchantTargetLockedAt", workspace:GetServerTimeNow())
	player:SetAttribute("PersonalSkyMerchantTargetOfferSerial", state.TargetOfferSerial)
	player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "LockedToFutureNormalIsland")
	player:SetAttribute("PersonalSkyMerchantSpawnPolicy", VERSION)
	return true
end

local function rememberCurrentIsland(player, state)
	local currentKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
	if currentKey ~= "" then
		state.VisitedKeys[currentKey] = true
	end
	if state.TargetKey and currentKey == state.TargetKey then
		player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "PlayerArrivedAtTarget")
	end
end

local function targetStillValid(player, state)
	local target = state.Target
	if not target
		return false
	end
	if not isNormalMerchantIsland(target)
		or getIslandKey(target) ~= state.TargetKey
		or not isAboveWater(target)
	then
		return false
	end
	local offerSerial = math.max(0, math.floor(tonumber(player:GetAttribute("MerchantOffersShown")) or 0))
	return offerSerial == state.TargetOfferSerial
end

local function updatePlayer(player)
	local state = states[player]
	if not state or player.Parent ~= Players then
		return
	end
	rememberCurrentIsland(player, state)

	if player:GetAttribute("MerchantOfferReady") ~= true then
		if state.Target then
			clearTarget(player, state, "WaitingForRecommendation")
		else
			player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForRecommendation")
		end
		return
	end

	local encounterState = tostring(player:GetAttribute("PersonalSkyMerchantEncounterState") or "Unseen")
	if encounterState == "Ignored"
		or encounterState == "Dismissed"
		or encounterState == "Purchased"
	then
		clearTarget(player, state, "EncounterEnded:" .. encounterState)
		return
	end

	if state.Target then
		if targetStillValid(player, state) then
			local value = getOrCreateTargetValue(player)
			if value.Value ~= state.Target then
				value.Value = state.Target
			end
			return
		end
		-- Uma ilha removida antes de ser percebida pode ser substituida por uma
		-- futura. Depois de apresentada, o cliente encerra o encontro como ignorado.
		clearTarget(player, state, encounterState == "Unseen"
			and "TargetLostBeforeDiscovery"
			or "TargetLostAfterPresentation")
		if encounterState ~= "Unseen" then
			return
		end
	end

	if encounterState ~= "Unseen" then
		return
	end
	local candidate = resolveIntentIsland(player)
	if isFutureCandidate(player, state, candidate) then
		lockTarget(player, state, candidate)
	else
		player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForFutureIsland")
	end
end

local function setupPlayer(player)
	if states[player] then
		return
	end
	local state = {
		VisitedKeys = {},
		Target = nil,
		TargetKey = nil,
		TargetOfferSerial = nil,
	}
	states[player] = state
	getOrCreateTargetValue(player)
	player:SetAttribute("PersonalSkyMerchantSpawnPolicy", VERSION)
	player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForRecommendation")
	rememberCurrentIsland(player, state)

	for _, attribute in ipairs({
		"MerchantOfferReady",
		"MerchantOffersShown",
		"PersonalSkyMerchantEncounterState",
		"WorldIntentTargetIslandKey",
		"CurrentIslandKey",
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			updatePlayer(player)
		end)
	end
	local intentValue = player:FindFirstChild(INTENT_VALUE_NAME)
	if intentValue and intentValue:IsA("ObjectValue") then
		intentValue:GetPropertyChangedSignal("Value"):Connect(function()
			updatePlayer(player)
		end)
	end
	player.ChildAdded:Connect(function(child)
		if child.Name == INTENT_VALUE_NAME and child:IsA("ObjectValue") then
			child:GetPropertyChangedSignal("Value"):Connect(function()
				updatePlayer(player)
			end)
			updatePlayer(player)
		end
	end)
	updatePlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

task.spawn(function()
	while true do
		task.wait(CHECK_SECONDS)
		for player in pairs(states) do
			updatePlayer(player)
		end
	end
end)
