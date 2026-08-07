local Players = game:GetService("Players")

local MonsterSpawner = require(script.Parent.Parent.BlockParkour.MonsterSpawner)
local InventoryService = require(script.Parent.Parent.MVPSystems.InventoryService)
local RunRewardLedgerService = require(script.Parent.RunRewardLedgerService)

local OptionalIslandService = {}

local PROFILE_SUPPLY = "SupplyCache"
local PROFILE_AMBUSH = "AmbushCache"
local PROFILE_ELITE = "EliteCache"
local ENCOUNTER_START_DELAY_SECONDS = 1.25
local POLL_SECONDS = 0.25
local OPTIONAL_SIGNAL_INDEX_BASE = 1000

local started = false
local options = {}
local participantSet = {}
local statesByKey = {}
local generation = 0
local completedCount = 0
local totalClaimCount = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanPartySize()
	return math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, 4)
end

local function participantCount()
	local count = 0
	for _ in pairs(participantSet) do
		count += 1
	end
	return count
end

local function sanitizeName(value)
	return string.gsub(tostring(value or "Optional"), "[^%w_%-]", "_")
end

local function sortedMarkers(folder)
	local result = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(result, child)
			end
		end
	end
	table.sort(result, function(left, right)
		local leftIndex = tonumber(left:GetAttribute("MarkerIndex")) or 0
		local rightIndex = tonumber(right:GetAttribute("MarkerIndex")) or 0
		if leftIndex == rightIndex then
			return left.Name < right.Name
		end
		return leftIndex < rightIndex
	end)
	return result
end

local function chooseProfile(context)
	local spec = type(context.Spec) == "table" and context.Spec or {}
	local seed = math.floor(math.abs(tonumber(spec.Seed or spec.RouteSeed) or 1))
	local branchId = tostring(context.RouteBranchId or spec.RouteBranchId or "")
	local isBranchB = string.match(branchId, "_B$") ~= nil
	local roll = seed % 4
	if isBranchB then
		return roll <= 1 and PROFILE_AMBUSH or PROFILE_ELITE
	end
	return roll <= 1 and PROFILE_SUPPLY or PROFILE_AMBUSH
end

local function profileDefinition(profile, roundIndex, partySize)
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 1), 1, 3)
	partySize = math.clamp(math.floor(tonumber(partySize) or 1), 1, 4)
	if profile == PROFILE_ELITE then
		return {
			DisplayName = "Desafio de Elite",
			LockedText = "DERROTE O GUARDIAO",
			RewardText = "RECOMPENSA DE ELITE",
			Coins = 48 + roundIndex * 14,
			ItemId = "GreaterHealthPotion",
			ItemAmount = 1,
			FallbackCoins = 24,
			CommonCount = math.max(0, partySize - 1),
			EliteCount = 1,
		}
	elseif profile == PROFILE_AMBUSH then
		return {
			DisplayName = "Emboscada do Ceu",
			LockedText = "LIMPE A EMBOSCADA",
			RewardText = "BAU DA EMBOSCADA",
			Coins = 28 + roundIndex * 10,
			ItemId = "HealthPotion",
			ItemAmount = 1,
			FallbackCoins = 14,
			CommonCount = math.clamp(2 + partySize, 3, 6),
			EliteCount = 0,
		}
	end
	return {
		DisplayName = "Cache de Suprimentos",
		LockedText = "SUPRIMENTOS ENCONTRADOS",
		RewardText = "BAU DE SUPRIMENTOS",
		Coins = 16 + roundIndex * 7,
		ItemId = "HealthPotion",
		ItemAmount = 1,
		FallbackCoins = 10,
		CommonCount = 0,
		EliteCount = 0,
	}
end

local function updateWorldAttributes()
	local activeEncounters = 0
	local availableRewards = 0
	for _, state in pairs(statesByKey) do
		if state.EncounterState == "Active" or state.EncounterState == "Spawning" then
			activeEncounters += 1
		end
		if state.Unlocked == true then
			availableRewards += 1
		end
	end
	workspace:SetAttribute("DungeonOptionalContentReady", started)
	workspace:SetAttribute("DungeonOptionalContentVersion", 1)
	workspace:SetAttribute("DungeonOptionalContentPolicy", "SharedEncounterPersonalRewardV1")
	workspace:SetAttribute("DungeonOptionalIslandInitializedCount", (function()
		local count = 0
		for _ in pairs(statesByKey) do
			count += 1
		end
		return count
	end)())
	workspace:SetAttribute("DungeonOptionalActiveEncounterCount", activeEncounters)
	workspace:SetAttribute("DungeonOptionalAvailableRewardCount", availableRewards)
	workspace:SetAttribute("DungeonOptionalEncounterCompletedCount", completedCount)
	workspace:SetAttribute("DungeonOptionalRewardClaimCount", totalClaimCount)
end

local function createPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.Material = material or Enum.Material.WoodPlanks
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function setChestVisual(state, unlocked)
	local model = state.ChestModel
	local prompt = state.Prompt
	local label = state.Label
	if not model or not model.Parent then
		return
	end
	model:SetAttribute("OptionalRewardUnlocked", unlocked == true)
	if prompt and prompt.Parent then
		prompt.Enabled = unlocked == true
		prompt.ActionText = unlocked and "Coletar" or "Bloqueado"
	end
	if label and label.Parent then
		label.Text = unlocked and state.Definition.RewardText or state.Definition.LockedText
		label.TextColor3 = unlocked and Color3.fromRGB(255, 231, 118) or Color3.fromRGB(255, 132, 105)
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "PromptBase" then
			descendant.Material = unlocked and Enum.Material.Neon or Enum.Material.WoodPlanks
		end
	end
end

local function allParticipantsClaimed(state)
	for userId in pairs(participantSet) do
		if state.Claims[userId] ~= true then
			return false
		end
	end
	return next(participantSet) ~= nil
end

local function committedRoundIndex()
	return math.max(
		math.floor(tonumber(workspace:GetAttribute("DungeonHighestCompletedRound")) or 0),
		math.floor(tonumber(workspace:GetAttribute("DungeonCheckpointCommittedRound")) or 0)
	)
end

local function livingParticipant(player)
	if not player or player.Parent ~= Players or not participantSet[player.UserId] then
		return false
	end
	if player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
		or player:GetAttribute("IsDowned") == true
	then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function claimReward(state, player)
	if not started or not state or not state.Unlocked then
		return false, "OptionalRewardLocked"
	end
	if not livingParticipant(player) then
		return false, "PlayerNotEligible"
	end
	if state.Claims[player.UserId] == true then
		player:SetAttribute("DungeonOptionalLastClaimResult", "AlreadyClaimed")
		return true, "AlreadyClaimed"
	end
	if committedRoundIndex() >= state.RoundIndex then
		player:SetAttribute("DungeonOptionalLastClaimResult", "RoundAlreadyCommitted")
		return false, "RoundAlreadyCommitted"
	end

	local worldPosition = state.ChestModel and state.ChestModel:GetPivot().Position or nil
	local coinsAdded = RunRewardLedgerService.AddPendingCoins(
		player,
		state.Definition.Coins,
		"OptionalIsland:" .. state.Profile,
		worldPosition,
		state.RoundIndex
	)
	if coinsAdded ~= true then
		player:SetAttribute("DungeonOptionalLastClaimResult", "CoinLedgerRejected")
		return false, "CoinLedgerRejected"
	end

	local itemGranted, itemError = InventoryService.GrantItem(
		player,
		state.Definition.ItemId,
		state.Definition.ItemAmount,
		"OptionalIsland:" .. state.Profile
	)
	local fallbackCoins = 0
	if not itemGranted then
		fallbackCoins = state.Definition.FallbackCoins
		RunRewardLedgerService.AddPendingCoins(
			player,
			fallbackCoins,
			"OptionalItemFallback:" .. state.Profile,
			worldPosition,
			state.RoundIndex
		)
	end

	state.Claims[player.UserId] = true
	state.ClaimCount += 1
	totalClaimCount += 1
	state.Island:SetAttribute("OptionalRewardClaimCount", state.ClaimCount)
	if state.ChestModel and state.ChestModel.Parent then
		state.ChestModel:SetAttribute("OptionalRewardClaimCount", state.ClaimCount)
	end
	player:SetAttribute("DungeonOptionalRewardAvailable", false)
	player:SetAttribute("DungeonOptionalClaimCount", (player:GetAttribute("DungeonOptionalClaimCount") or 0) + 1)
	player:SetAttribute("DungeonOptionalLastClaimKey", state.Key)
	player:SetAttribute("DungeonOptionalLastClaimProfile", state.Profile)
	player:SetAttribute("DungeonOptionalLastRewardCoins", state.Definition.Coins + fallbackCoins)
	player:SetAttribute("DungeonOptionalLastRewardItem", itemGranted and state.Definition.ItemId or nil)
	player:SetAttribute("DungeonOptionalLastClaimResult", itemGranted and "Claimed" or ("ClaimedItemFallback:" .. tostring(itemError)))
	player:SetAttribute("DungeonOptionalLastClaimAt", now())

	if allParticipantsClaimed(state) and state.Prompt and state.Prompt.Parent then
		state.Prompt.Enabled = false
		state.ChestModel:SetAttribute("OptionalRewardFullyClaimed", true)
	end
	updateWorldAttributes()
	return true, {
		Coins = state.Definition.Coins + fallbackCoins,
		ItemId = itemGranted and state.Definition.ItemId or nil,
		ItemFallback = itemGranted ~= true,
	}
end

local function buildChest(state, marker)
	local content = state.Content
	local model = Instance.new("Model")
	model.Name = "OptionalRewardChest"
	model:SetAttribute("OptionalIslandKey", state.Key)
	model:SetAttribute("OptionalContentProfile", state.Profile)
	model:SetAttribute("RoundIndex", state.RoundIndex)
	model:SetAttribute("PersonalReward", true)
	model:SetAttribute("OptionalRewardClaimCount", 0)
	model.Parent = content

	local baseColor = state.Profile == PROFILE_ELITE and Color3.fromRGB(152, 74, 218)
		or (state.Profile == PROFILE_AMBUSH and Color3.fromRGB(214, 88, 58) or Color3.fromRGB(65, 151, 218))
	local trimColor = Color3.fromRGB(255, 222, 105)
	local baseCFrame = marker.CFrame * CFrame.new(0, 1.25, 0)
	local base = createPart(model, "PromptBase", Vector3.new(5.4, 2.2, 3.8), baseCFrame, baseColor)
	createPart(
		model,
		"Lid",
		Vector3.new(5.6, 1.1, 4),
		baseCFrame * CFrame.new(0, 1.65, -0.12) * CFrame.Angles(math.rad(-7), 0, 0),
		baseColor
	)
	createPart(model, "Band", Vector3.new(1.05, 3.5, 4.1), baseCFrame * CFrame.new(0, 0.75, 0), trimColor, Enum.Material.Metal)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimOptionalReward"
	prompt.ActionText = "Bloqueado"
	prompt.ObjectText = state.Definition.DisplayName
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("OptionalIslandKey", state.Key)
	prompt:SetAttribute("OptionalContentProfile", state.Profile)
	prompt.Parent = base

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OptionalRewardLabel"
	billboard.Adornee = base
	billboard.Size = UDim2.fromOffset(230, 48)
	billboard.StudsOffset = Vector3.new(0, 4.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 75
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(17, 20, 28)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Text = state.Definition.LockedText
	label.TextColor3 = Color3.fromRGB(255, 132, 105)
	label.TextStrokeTransparency = 0.55
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = label

	model.PrimaryPart = base
	state.ChestModel = model
	state.Prompt = prompt
	state.Label = label
	prompt.Triggered:Connect(function(player)
		claimReward(state, player)
	end)
	setChestVisual(state, false)
	return model
end

local function unlockReward(state, reason)
	if not started or state.Unlocked then
		return false
	end
	state.Unlocked = true
	state.CompletedAt = now()
	state.EncounterState = "RewardAvailable"
	completedCount += 1
	state.Island:SetAttribute("OptionalEncounterState", state.EncounterState)
	state.Island:SetAttribute("OptionalEncounterCompleted", true)
	state.Island:SetAttribute("OptionalEncounterCompletedAt", state.CompletedAt)
	state.Island:SetAttribute("OptionalEncounterCompletionReason", tostring(reason or "EncounterCleared"))
	state.Island:SetAttribute("OptionalRewardUnlocked", true)
	setChestVisual(state, true)
	updateWorldAttributes()
	return true
end

local function spawnEnemy(state, role, sequence, isElite)
	local markers = state.EnemyMarkers
	if #markers == 0 then
		return nil, "EnemyMarkersMissing"
	end
	local marker = markers[((sequence - 1) % #markers) + 1]
	local signalIndex = OPTIONAL_SIGNAL_INDEX_BASE
		+ math.max(1, math.floor(tonumber(state.RouteNodeOrder) or sequence))
	local variant
	if isElite then
		variant = state.RoundIndex >= 3 and "Lightning" or "Red"
	elseif role == "Ranged" then
		variant = "Blue"
	else
		variant = state.RoundIndex >= 3 and "Red" or "Green"
	end
	local model, errorCode = MonsterSpawner.SpawnObjectiveMonster(
		state.Island,
		marker,
		{
			EncounterId = state.EncounterId,
			ObjectiveId = "OptionalIsland:" .. state.Key,
			GlobalIslandIndex = signalIndex,
			Role = role,
			SlimeVariant = variant,
			IsElite = isElite == true,
			HealthMultiplier = isElite and 0.92 or 0.86,
			DamageMultiplier = isElite and 0.88 or 0.82,
			SpeedMultiplier = isElite and 0.96 or 0.92,
			WaveIndex = 1,
			SpawnSequence = sequence,
			Seed = math.floor(tonumber(state.Seed) or 1) + sequence * 104729,
		}
	)
	if model then
		model:SetAttribute("OptionalEncounter", true)
		model:SetAttribute("OptionalIslandKey", state.Key)
		model:SetAttribute("OptionalContentProfile", state.Profile)
		model:SetAttribute("OptionalSignalIslandIndex", signalIndex)
	end
	return model, errorCode
end

local function startEncounterWorker(state, token)
	task.spawn(function()
		while started and token == generation and statesByKey[state.Key] == state do
			local active = MonsterSpawner.GetObjectiveActiveCount(state.EncounterId)
			state.Island:SetAttribute("OptionalEncounterActiveEnemies", active)
			workspace:SetAttribute("DungeonOptionalLastActiveEnemyCount", active)
			if state.Spawning ~= true and active <= 0 then
				unlockReward(state, state.SpawnedCount > 0 and "EncounterCleared" or "SpawnFallback")
				return
			end
			task.wait(POLL_SECONDS)
		end
	end)
end

local function beginEncounter(state, token)
	if not started or token ~= generation or statesByKey[state.Key] ~= state or state.EncounterStarted then
		return
	end
	state.EncounterStarted = true
	state.Spawning = true
	state.EncounterState = "Spawning"
	state.Island:SetAttribute("OptionalEncounterState", state.EncounterState)
	state.Island:SetAttribute("OptionalEncounterStartedAt", now())
	state.Island:SetAttribute("OptionalEncounterId", state.EncounterId)
	local sequence = 0
	for _ = 1, state.Definition.CommonCount do
		sequence += 1
		local role = sequence % 3 == 0 and "Ranged" or "Common"
		local model, errorCode = spawnEnemy(state, role, sequence, false)
		if model then
			state.SpawnedCount += 1
		else
			state.LastSpawnError = tostring(errorCode)
		end
		task.wait(0.12)
	end
	for _ = 1, state.Definition.EliteCount do
		sequence += 1
		local model, errorCode = spawnEnemy(state, "Elite", sequence, true)
		if model then
			state.SpawnedCount += 1
		else
			state.LastSpawnError = tostring(errorCode)
		end
		task.wait(0.12)
	end
	state.Spawning = false
	state.EncounterState = state.SpawnedCount > 0 and "Active" or "SpawnFailed"
	state.Island:SetAttribute("OptionalEncounterState", state.EncounterState)
	state.Island:SetAttribute("OptionalEncounterSpawnedCount", state.SpawnedCount)
	state.Island:SetAttribute("OptionalEncounterLastSpawnError", state.LastSpawnError)
	startEncounterWorker(state, token)
end

local function initializeState(context)
	local key = tostring(context.Key or "")
	if key == "" then
		return nil, "OptionalIslandKeyMissing"
	end
	local island = context.IslandModel
	if not island or not island:IsA("Model") or not island.Parent then
		return nil, "OptionalIslandModelMissing"
	end
	local marker = context.ChestSpawns and (
		context.ChestSpawns:FindFirstChild("ChestSpawn_01")
			or context.ChestSpawns:FindFirstChildWhichIsA("BasePart")
	) or context.ObjectiveAnchor or context.SafeSpawn
	if not marker or not marker:IsA("BasePart") then
		return nil, "OptionalChestMarkerMissing"
	end

	local profile = chooseProfile(context)
	local roundIndex = math.clamp(math.floor(tonumber(context.RoundIndex) or 1), 1, 3)
	local spec = type(context.Spec) == "table" and context.Spec or {}
	local content = island:FindFirstChild("OptionalIslandContent")
	if content then
		content:Destroy()
	end
	content = Instance.new("Folder")
	content.Name = "OptionalIslandContent"
	content:SetAttribute("OptionalIslandKey", key)
	content:SetAttribute("OptionalContentProfile", profile)
	content.Parent = island

	local state = {
		Key = key,
		RoundIndex = roundIndex,
		RouteBranchId = context.RouteBranchId or spec.RouteBranchId,
		RouteNodeOrder = spec.RouteNodeOrder,
		Seed = spec.Seed or spec.RouteSeed or 1,
		Profile = profile,
		Definition = profileDefinition(profile, roundIndex, cleanPartySize()),
		Context = context,
		Island = island,
		Content = content,
		EnemyMarkers = sortedMarkers(context.EnemySpawns),
		EncounterId = "Optional-" .. sanitizeName(key),
		EncounterState = "Preparing",
		EncounterStarted = false,
		Spawning = false,
		SpawnedCount = 0,
		Unlocked = false,
		Claims = {},
		ClaimCount = 0,
		Visitors = {},
	}
	statesByKey[key] = state
	island:SetAttribute("OptionalContentManaged", true)
	-- Impede o populador generico de adicionar mobs aleatorios. O encontro
	-- opcional abaixo passa a ser a unica autoridade de combate desta ilha.
	island:SetAttribute("ObjectiveEncounterManaged", true)
	island:SetAttribute("OptionalContentProfile", profile)
	island:SetAttribute("OptionalContentDisplayName", state.Definition.DisplayName)
	island:SetAttribute("OptionalContentRoundIndex", roundIndex)
	island:SetAttribute("OptionalEncounterState", state.EncounterState)
	island:SetAttribute("OptionalEncounterBlocksRoute", false)
	island:SetAttribute("OptionalRewardPersonal", true)
	island:SetAttribute("OptionalRewardCoins", state.Definition.Coins)
	island:SetAttribute("OptionalRewardItemId", state.Definition.ItemId)
	island:SetAttribute("OptionalRewardClaimCount", 0)
	buildChest(state, marker)

	if state.Definition.CommonCount <= 0 and state.Definition.EliteCount <= 0 then
		unlockReward(state, "SupplyCache")
	else
		state.EncounterState = "Warning"
		state.Island:SetAttribute("OptionalEncounterState", state.EncounterState)
		state.Island:SetAttribute("OptionalEncounterStartsAt", now() + ENCOUNTER_START_DELAY_SECONDS)
		local token = generation
		task.delay(ENCOUNTER_START_DELAY_SECONDS, function()
			beginEncounter(state, token)
		end)
	end
	updateWorldAttributes()
	return state
end

function OptionalIslandService.Start(startOptions)
	if started then
		return
	end
	started = true
	generation += 1
	options = type(startOptions) == "table" and startOptions or {}
	options.PartySize = math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, 4)
	participantSet = {}
	statesByKey = {}
	completedCount = 0
	totalClaimCount = 0
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
		end
	end
	InventoryService.Start()
	workspace:SetAttribute("DungeonOptionalExpectedIslandCount", 18)
	workspace:SetAttribute("DungeonOptionalParticipantCount", participantCount())
	updateWorldAttributes()
end

function OptionalIslandService.Stop()
	if not started then
		return
	end
	started = false
	generation += 1
	for _, state in pairs(statesByKey) do
		MonsterSpawner.DespawnObjectiveMonsters(state.EncounterId)
		if state.Content and state.Content.Parent then
			state.Content:Destroy()
		end
	end
	statesByKey = {}
	participantSet = {}
	options = {}
	updateWorldAttributes()
end

function OptionalIslandService.HandleIslandEntered(player, context)
	if not started or not player or player.Parent ~= Players or type(context) ~= "table" then
		return false, "InvalidOptionalEntry"
	end
	if context.IsOptionalRoute ~= true then
		return false, "NotOptionalRoute"
	end
	if not participantSet[player.UserId] then
		return false, "NotParticipant"
	end
	local key = tostring(context.Key or "")
	local state = statesByKey[key]
	if not state then
		local created, errorCode = initializeState(context)
		if not created then
			workspace:SetAttribute("DungeonOptionalLastError", tostring(errorCode))
			return false, errorCode
		end
		state = created
	end
	if state.Visitors[player.UserId] ~= true then
		state.Visitors[player.UserId] = true
		state.Island:SetAttribute("OptionalVisitorCount", (state.Island:GetAttribute("OptionalVisitorCount") or 0) + 1)
		player:SetAttribute("DungeonOptionalIslandVisitCount", (player:GetAttribute("DungeonOptionalIslandVisitCount") or 0) + 1)
	end
	player:SetAttribute("DungeonCurrentOptionalIslandKey", state.Key)
	player:SetAttribute("DungeonCurrentOptionalProfile", state.Profile)
	player:SetAttribute("DungeonOptionalRewardAvailable", state.Unlocked == true and state.Claims[player.UserId] ~= true)
	player:SetAttribute("DungeonOptionalLastEnteredAt", now())
	return true, {
		Key = state.Key,
		Profile = state.Profile,
		EncounterState = state.EncounterState,
		RewardAvailable = state.Unlocked == true and state.Claims[player.UserId] ~= true,
		Claimed = state.Claims[player.UserId] == true,
	}
end

function OptionalIslandService.Claim(player, islandKey)
	local state = statesByKey[tostring(islandKey or "")]
	if not state then
		return false, "OptionalIslandNotInitialized"
	end
	return claimReward(state, player)
end

function OptionalIslandService.GetSnapshot(player)
	local islands = {}
	for key, state in pairs(statesByKey) do
		islands[key] = {
			RoundIndex = state.RoundIndex,
			Profile = state.Profile,
			EncounterState = state.EncounterState,
			SpawnedCount = state.SpawnedCount,
			ActiveEnemyCount = MonsterSpawner.GetObjectiveActiveCount(state.EncounterId),
			RewardAvailable = state.Unlocked == true,
			ClaimCount = state.ClaimCount,
			Claimed = player and state.Claims[player.UserId] == true or nil,
		}
	end
	return {
		Ready = started,
		PartySize = cleanPartySize(),
		ParticipantCount = participantCount(),
		CompletedCount = completedCount,
		TotalClaimCount = totalClaimCount,
		Islands = islands,
	}
end

return OptionalIslandService
