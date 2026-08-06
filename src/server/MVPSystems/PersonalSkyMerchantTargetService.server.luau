-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

-- Escolhe uma ilha alcançável para cada encontro pessoal do Mercador do Céu.
--
-- Prioridade V8:
-- 1. ilha futura publicada pela intenção real de movimento;
-- 2. ilha futura normal mais próxima fisicamente;
-- 3. ilha normal segura atual ou mais próxima, após uma espera curta.
--
-- A oferta permanece viva enquanto o encontro ainda não foi aberto. Se a ilha
-- for reciclada ou o jogador mudar de ramificação, o alvo é recalculado.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local TARGET_VALUE_NAME = "PersonalSkyMerchantTargetIsland"
local INTENT_VALUE_NAME = "WorldIntentTargetIsland"
local CHECK_SECONDS = 0.5
local WATER_CLEARANCE_STUDS = 8
local INTENT_GRACE_SECONDS = math.max(
	1,
	tonumber(MVPConfig.Village.PersonalSkyMerchantIntentWaitSeconds) or 5
)
local SAFE_FALLBACK_SECONDS = math.max(
	INTENT_GRACE_SECONDS,
	tonumber(MVPConfig.Village.PersonalSkyMerchantSafeFallbackSeconds) or 11
)
local VERSION = "GuaranteedReachableFallbackV8"

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
	state.TargetProgress = nil
	state.TargetSource = nil
	local value = getOrCreateTargetValue(player)
	value.Value = nil
	player:SetAttribute("PersonalSkyMerchantTargetIslandKey", nil)
	player:SetAttribute("PersonalSkyMerchantTargetLockedAt", nil)
	player:SetAttribute("PersonalSkyMerchantTargetSource", nil)
	player:SetAttribute("PersonalSkyMerchantTargetProgress", nil)
	player:SetAttribute("PersonalSkyMerchantTargetDistance", nil)
	player:SetAttribute(
		"PersonalSkyMerchantTargetAssignmentState",
		assignmentState or "WaitingForFutureIsland"
	)
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

local function floorOf(island)
	local floor = island and island:FindFirstChild("IslandFloor")
	return floor and floor:IsA("BasePart") and floor or nil
end

local function isNormalMerchantIsland(island)
	return island
		and island:IsA("Model")
		and island:IsDescendantOf(workspace)
		and island:GetAttribute("IsSkyIsland") == true
		and tostring(island:GetAttribute("IslandType") or "Normal") == "Normal"
		and not isVillageOrSanctuary(island)
		and floorOf(island) ~= nil
end

local function isAboveWater(island)
	local floor = floorOf(island)
	if not floor then
		return false
	end
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	if not surfaceY then
		return true
	end
	return floor.Position.Y + floor.Size.Y / 2 > surfaceY + WATER_CLEARANCE_STUDS
end

local function islandProgress(island)
	return tonumber(island and island:GetAttribute("LogicalLevel"))
		or tonumber(island and island:GetAttribute("RoundIndex"))
end

local function currentProgress(player)
	return tonumber(player:GetAttribute("CurrentLogicalLevel"))
		or tonumber(player:GetAttribute("CurrentRoundIndex"))
		or -math.huge
end

local function getLivingRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function distanceToIsland(player, island)
	local root = getLivingRoot(player)
	local floor = floorOf(island)
	if not root or not floor then
		return math.huge
	end
	return (floor.Position - root.Position).Magnitude
end

local function isBaseCandidate(state, island)
	if not isNormalMerchantIsland(island) or not isAboveWater(island) then
		return false
	end
	local key = getIslandKey(island)
	if key == "" then
		return false
	end
	local rejectedUntil = tonumber(state.RejectedKeys[key]) or 0
	if rejectedUntil > workspace:GetServerTimeNow() then
		return false
	end
	state.RejectedKeys[key] = nil
	return true
end

local function isFutureCandidate(player, state, island)
	if not isBaseCandidate(state, island) then
		return false
	end
	local key = getIslandKey(island)
	return key ~= tostring(player:GetAttribute("CurrentIslandKey") or "")
		and state.VisitedKeys[key] ~= true
end

local function resolveGeneratedFutureIsland(player, state)
	local progressNow = currentProgress(player)
	local candidates = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if isFutureCandidate(player, state, descendant) then
			local progress = islandProgress(descendant)
			if progress and progress > progressNow then
				table.insert(candidates, {
					Island = descendant,
					Progress = progress,
					Distance = distanceToIsland(player, descendant),
					Key = getIslandKey(descendant),
				})
			end
		end
	end
	table.sort(candidates, function(left, right)
		if left.Progress ~= right.Progress then
			return left.Progress < right.Progress
		end
		if left.Distance ~= right.Distance then
			return left.Distance < right.Distance
		end
		return left.Key < right.Key
	end)
	local nearestDistance = candidates[1] and candidates[1].Distance or nil
	player:SetAttribute("PersonalSkyMerchantFutureCandidateCount", #candidates)
	player:SetAttribute(
		"PersonalSkyMerchantNearestCandidateDistance",
		nearestDistance and nearestDistance < math.huge
			and math.floor(nearestDistance + 0.5)
			or nil
	)
	return candidates[1] and candidates[1].Island or nil
end

local function resolveSafeFallbackIsland(player, state)
	local currentKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
	local currentIsland = findIslandByKey(currentKey)
	if isBaseCandidate(state, currentIsland) then
		player:SetAttribute("PersonalSkyMerchantFallbackCandidateCount", 1)
		return currentIsland, "CurrentSafeNormalIsland"
	end

	local progressNow = currentProgress(player)
	local candidates = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if isBaseCandidate(state, descendant) then
			local progress = islandProgress(descendant) or progressNow
			local progressPenalty = progress >= progressNow and 0 or 1
			table.insert(candidates, {
					Island = descendant,
					ProgressPenalty = progressPenalty,
					ProgressDelta = math.abs(progress - progressNow),
					Distance = distanceToIsland(player, descendant),
					Key = getIslandKey(descendant),
				})
		end
	end
	table.sort(candidates, function(left, right)
		if left.ProgressPenalty ~= right.ProgressPenalty then
			return left.ProgressPenalty < right.ProgressPenalty
		end
		if left.ProgressDelta ~= right.ProgressDelta then
			return left.ProgressDelta < right.ProgressDelta
		end
		if left.Distance ~= right.Distance then
			return left.Distance < right.Distance
		end
		return left.Key < right.Key
	end)
	player:SetAttribute("PersonalSkyMerchantFallbackCandidateCount", #candidates)
	return candidates[1] and candidates[1].Island or nil, "NearestSafeNormalIsland"
end

local function lockTarget(player, state, island, source)
	local key = getIslandKey(island)
	if key == "" or not isBaseCandidate(state, island) then
		return false
	end
	local serial = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("PersonalSkyMerchantEncounterSerial")) or 0)
	)
	state.Target = island
	state.TargetKey = key
	state.TargetOfferSerial = serial
	state.TargetProgress = islandProgress(island) or currentProgress(player)
	state.TargetSource = source or "Unknown"
	local value = getOrCreateTargetValue(player)
	value.Value = island
	local distance = distanceToIsland(player, island)
	player:SetAttribute("PersonalSkyMerchantTargetIslandKey", key)
	player:SetAttribute("PersonalSkyMerchantTargetLockedAt", workspace:GetServerTimeNow())
	player:SetAttribute("PersonalSkyMerchantTargetOfferSerial", serial)
	player:SetAttribute("PersonalSkyMerchantTargetSource", state.TargetSource)
	player:SetAttribute("PersonalSkyMerchantTargetProgress", state.TargetProgress)
	player:SetAttribute(
		"PersonalSkyMerchantTargetDistance",
		distance < math.huge and math.floor(distance + 0.5) or nil
	)
	local assignmentState = "LockedToFutureNormalIsland"
	if state.TargetSource == "CurrentSafeNormalIsland" then
		assignmentState = "LockedToCurrentSafeIsland"
	elseif state.TargetSource == "NearestSafeNormalIsland" then
		assignmentState = "LockedToNearestSafeIsland"
	end
	player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", assignmentState)
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
	if not target or not isBaseCandidate(state, target) then
		return false
	end
	if getIslandKey(target) ~= state.TargetKey then
		return false
	end
	local serial = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("PersonalSkyMerchantEncounterSerial")) or 0)
	)
	return serial == state.TargetOfferSerial
end

local function isRetargetable(encounterState)
	return encounterState == "Unseen" or encounterState == "Presented"
end

local function resetForOffer(player, state, serial)
	clearTarget(player, state, "WaitingForRoute")
	state.OfferSerial = serial
	state.OfferReadyAt = workspace:GetServerTimeNow()
	table.clear(state.RejectedKeys)
	state.LastRetargetRequestSerial = tonumber(
		player:GetAttribute("PersonalSkyMerchantRetargetRequestSerial")
	) or 0
	player:SetAttribute("PersonalSkyMerchantRejectedTargetIslandKey", nil)
	player:SetAttribute("PersonalSkyMerchantFutureCandidateCount", 0)
	player:SetAttribute("PersonalSkyMerchantFallbackCandidateCount", 0)
end

local function updatePlayer(player)
	local state = states[player]
	if not state or player.Parent ~= Players then
		return
	end
	rememberCurrentIsland(player, state)

	if player:GetAttribute("MerchantOfferReady") ~= true then
		state.OfferReadyAt = nil
		state.OfferSerial = nil
		table.clear(state.RejectedKeys)
		if state.Target then
			clearTarget(player, state, "WaitingForRecommendation")
		else
			player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForRecommendation")
		end
		return
	end

	local serial = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("PersonalSkyMerchantEncounterSerial")) or 0)
	)
	if state.OfferSerial ~= serial then
		resetForOffer(player, state, serial)
	end

	local retargetRequestSerial = tonumber(
		player:GetAttribute("PersonalSkyMerchantRetargetRequestSerial")
	) or 0
	if retargetRequestSerial ~= (state.LastRetargetRequestSerial or 0) then
		state.LastRetargetRequestSerial = retargetRequestSerial
		local rejectedKey = tostring(
			player:GetAttribute("PersonalSkyMerchantRejectedTargetIslandKey") or ""
		)
		if rejectedKey ~= "" then
			state.RejectedKeys[rejectedKey] = workspace:GetServerTimeNow() + 6
			if state.TargetKey == rejectedKey then
				clearTarget(player, state, "RetargetingAfterSpawnFailure")
			end
		end
	end

	local encounterState = tostring(player:GetAttribute("PersonalSkyMerchantEncounterState") or "Unseen")
	if encounterState == "Ignored"
		or encounterState == "Dismissed"
		or encounterState == "Purchased"
		or encounterState == "ExpiredWithIsland"
	then
		clearTarget(player, state, "EncounterEnded:" .. encounterState)
		return
	end

	if state.Target then
		if targetStillValid(player, state) then
			local currentKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
			local progressNow = currentProgress(player)
			local targetProgress = state.TargetProgress or progressNow
			local isFutureSource = state.TargetSource == "TravelIntent"
				or state.TargetSource == "NearestReachableGeneratedIsland"
			if isRetargetable(encounterState)
				and isFutureSource
				and currentKey ~= state.TargetKey
				and progressNow >= targetProgress
			then
				clearTarget(player, state, "RetargetingAfterRouteChanged")
			else
				local value = getOrCreateTargetValue(player)
				if value.Value ~= state.Target then
					value.Value = state.Target
				end
				return
			end
		else
			clearTarget(
				player,
				state,
				isRetargetable(encounterState)
					and "TargetLostRetargeting"
					or "TargetLostAfterOpen"
			)
			if not isRetargetable(encounterState) then
				return
			end
		end
	end

	if not isRetargetable(encounterState) then
		return
	end

	local readyFor = workspace:GetServerTimeNow() - (state.OfferReadyAt or workspace:GetServerTimeNow())
	local candidate = resolveIntentIsland(player)
	if isFutureCandidate(player, state, candidate) then
		lockTarget(player, state, candidate, "TravelIntent")
		return
	end

	if readyFor < INTENT_GRACE_SECONDS then
		player:SetAttribute("PersonalSkyMerchantTargetSource", nil)
		player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForTravelIntent")
		player:SetAttribute(
			"PersonalSkyMerchantTargetWaitSeconds",
			math.ceil(INTENT_GRACE_SECONDS - readyFor)
		)
		return
	end

	candidate = resolveGeneratedFutureIsland(player, state)
	if isFutureCandidate(player, state, candidate) then
		player:SetAttribute("PersonalSkyMerchantTargetWaitSeconds", nil)
		lockTarget(player, state, candidate, "NearestReachableGeneratedIsland")
		return
	end

	if readyFor < SAFE_FALLBACK_SECONDS then
		player:SetAttribute("PersonalSkyMerchantTargetSource", nil)
		player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForSafeFallback")
		player:SetAttribute(
			"PersonalSkyMerchantTargetWaitSeconds",
			math.ceil(SAFE_FALLBACK_SECONDS - readyFor)
		)
		return
	end

	local fallbackSource
	candidate, fallbackSource = resolveSafeFallbackIsland(player, state)
	if candidate and lockTarget(player, state, candidate, fallbackSource) then
		player:SetAttribute("PersonalSkyMerchantTargetWaitSeconds", nil)
		return
	end

	player:SetAttribute("PersonalSkyMerchantTargetSource", nil)
	player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForAnySafeNormalIsland")
	player:SetAttribute("PersonalSkyMerchantTargetWaitSeconds", nil)
end

local function setupPlayer(player)
	if states[player] then
		return
	end
	local state = {
		VisitedKeys = {},
		RejectedKeys = {},
		Target = nil,
		TargetKey = nil,
		TargetOfferSerial = nil,
		TargetProgress = nil,
		TargetSource = nil,
		OfferReadyAt = nil,
		OfferSerial = nil,
		LastRetargetRequestSerial = 0,
	}
	states[player] = state
	getOrCreateTargetValue(player)
	player:SetAttribute("PersonalSkyMerchantSpawnPolicy", VERSION)
	player:SetAttribute("PersonalSkyMerchantTargetAssignmentState", "WaitingForRecommendation")
	player:SetAttribute("PersonalSkyMerchantFutureCandidateCount", 0)
	player:SetAttribute("PersonalSkyMerchantFallbackCandidateCount", 0)
	rememberCurrentIsland(player, state)

	for _, attribute in ipairs({
		"MerchantOfferReady",
		"MerchantOffersShown",
		"PersonalSkyMerchantEncounterSerial",
		"PersonalSkyMerchantEncounterState",
		"PersonalSkyMerchantRejectedTargetIslandKey",
		"PersonalSkyMerchantRetargetRequestSerial",
		"WorldIntentTargetIslandKey",
		"CurrentIslandKey",
		"CurrentLogicalLevel",
		"CurrentRoundIndex",
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
