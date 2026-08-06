local Players = game:GetService("Players")

local RewardCatalog = require(script.Parent.RewardCatalog)
local RewardGrantService = require(script.Parent.RewardGrantService)
local RunRewardLedgerService = require(script.Parent.RunRewardLedgerService)

local RewardIslandService = {}

local AUTO_RESOLVE_SECONDS = 45
local RETRY_INTERVAL_SECONDS = 3
local CHEST_ROLES = table.freeze({ "Core", "Bonus" })

local started = false
local options = {}
local participantSet = {}
local currentRound
local generation = 0
local playerRemovingConnection

local function now()
	return workspace:GetServerTimeNow()
end

local function fireClient(player, payload)
	local remote = options.RemoteEvent
	if remote and player and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function playerRecord(userId)
	if not currentRound then
		return nil
	end
	local record = currentRound.Players[userId]
	if not record then
		record = {
			Claims = {
				Core = { State = "Available" },
				Bonus = { State = "Available" },
			},
			CoinsState = "Pending",
			Disconnected = Players:GetPlayerByUserId(userId) == nil,
		}
		currentRound.Players[userId] = record
	end
	return record
end

local function ownSnapshot(player)
	if not currentRound then
		return { Active = false }
	end
	local record = playerRecord(player.UserId)
	return {
		Active = true,
		RoundIndex = currentRound.RoundIndex,
		GlobalIslandIndex = currentRound.GlobalIslandIndex,
		StartedAt = currentRound.StartedAt,
		AutoResolveAt = currentRound.AutoResolveAt,
		Core = table.clone(record.Claims.Core),
		Bonus = table.clone(record.Claims.Bonus),
		CoinsState = record.CoinsState,
		Committed = currentRound.Committed == true,
	}
end

local function publish(player, action, extra)
	local payload = ownSnapshot(player)
	payload.Action = action or "RewardSnapshot"
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	fireClient(player, payload)
end

local function updateWorldAttributes()
	workspace:SetAttribute("DungeonRewardIslandActive", currentRound ~= nil and not currentRound.Committed)
	workspace:SetAttribute("DungeonRewardIslandRound", currentRound and currentRound.RoundIndex or nil)
	workspace:SetAttribute("DungeonRewardIslandIndex", currentRound and currentRound.GlobalIslandIndex or nil)
	workspace:SetAttribute("DungeonRewardIslandStartedAt", currentRound and currentRound.StartedAt or nil)
	workspace:SetAttribute("DungeonRewardIslandAutoResolveAt", currentRound and currentRound.AutoResolveAt or nil)
end

local function createChestPart(parent, name, size, cframe, color, material)
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

local function buildChest(marker, role, parent)
	local model = Instance.new("Model")
	model.Name = role .. "RewardChest"
	model:SetAttribute("RewardChestRole", role)
	model:SetAttribute("PersonalRewardChest", true)
	model:SetAttribute("RoundIndex", currentRound.RoundIndex)
	model:SetAttribute("GlobalIslandIndex", currentRound.GlobalIslandIndex)
	model:SetAttribute("ClaimCount", 0)
	model.Parent = parent
	local baseColor = role == "Core" and Color3.fromRGB(65, 151, 218) or Color3.fromRGB(226, 174, 56)
	local metalColor = role == "Core" and Color3.fromRGB(156, 226, 255) or Color3.fromRGB(255, 229, 130)
	local baseCFrame = marker.CFrame * CFrame.new(0, 1.2, 0)
	local base = createChestPart(model, "Base", Vector3.new(5.2, 2.2, 3.6), baseCFrame, baseColor)
	createChestPart(
		model,
		"Lid",
		Vector3.new(5.4, 1.1, 3.8),
		baseCFrame * CFrame.new(0, 1.65, -0.15) * CFrame.Angles(math.rad(-8), 0, 0),
		baseColor
	)
	createChestPart(
		model,
		"Band",
		Vector3.new(1.05, 3.45, 3.95),
		baseCFrame * CFrame.new(0, 0.75, 0),
		metalColor,
		Enum.Material.Metal
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPersonalReward"
	prompt.ActionText = "Abrir"
	prompt.ObjectText = role == "Core" and "Core Chest" or "Bonus Chest"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("RewardChestRole", role)
	prompt:SetAttribute("RoundIndex", currentRound.RoundIndex)
	prompt.Parent = base
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RewardChestLabel"
	billboard.Adornee = base
	billboard.Size = UDim2.fromOffset(170, 38)
	billboard.StudsOffset = Vector3.new(0, 3.7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 50
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Text = role == "Core" and "CORE CHEST" or "BONUS CHEST"
	label.TextColor3 = metalColor
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
	model.PrimaryPart = base
	return model, prompt
end

local function allClaimsCommitted(record)
	return record.Claims.Core.State == "Claimed" and record.Claims.Bonus.State == "Claimed"
end

local function claimChest(player, role, automatic)
	if not currentRound or currentRound.Committed then
		return false, "RewardRoundInactive"
	end
	if not participantSet[player.UserId] then
		return false, "NotRewardParticipant"
	end
	role = role == "Bonus" and "Bonus" or "Core"
	local record = playerRecord(player.UserId)
	local claim = record.Claims[role]
	if claim.State == "Claimed" then
		publish(player, "RewardAlreadyClaimed", { ChestRole = role })
		return true, "AlreadyClaimed"
	end
	if claim.State == "Granting" and now() - (claim.LastAttemptAt or 0) < 1 then
		return false, "GrantInProgress"
	end
	claim.State = "Granting"
	claim.LastAttemptAt = now()
	claim.Automatic = automatic == true
	local bundle = RewardCatalog.Roll(
		options.SessionId,
		player.UserId,
		currentRound.RoundIndex,
		role
	)
	claim.GrantId = bundle.GrantId
	local granted, resultOrError = RewardGrantService.GrantBundle(player, bundle)
	if not granted then
		claim.State = tostring(resultOrError) == "SavePending" and "Saving" or "RetryPending"
		claim.Error = tostring(resultOrError)
		publish(player, "RewardGrantPending", {
			ChestRole = role,
			Reason = claim.Error,
		})
		return false, resultOrError
	end
	claim.State = "Claimed"
	claim.Error = nil
	claim.ClaimedAt = now()
	claim.Result = resultOrError
	local chest = currentRound.Chests[role]
	if chest and chest.Parent then
		chest:SetAttribute("ClaimCount", (chest:GetAttribute("ClaimCount") or 0) + 1)
	end
	publish(player, "RewardClaimed", {
		ChestRole = role,
		Grant = resultOrError,
		Bundle = bundle,
	})
	return true, resultOrError
end

local function commitPlayerCoins(player)
	local record = playerRecord(player.UserId)
	if record.CoinsState == "Committed" then
		return true
	end
	if not allClaimsCommitted(record) then
		return false, "PersonalChestsPending"
	end
	record.CoinsState = "Committing"
	local committed, resultOrError = RunRewardLedgerService.CommitRound(player, currentRound.RoundIndex)
	if not committed then
		record.CoinsState = "SavePending"
		record.CoinsError = tostring(resultOrError)
		publish(player, "RoundCoinsPending", { Reason = record.CoinsError })
		return false, resultOrError
	end
	record.CoinsState = "Committed"
	record.CoinsError = nil
	record.CoinsResult = resultOrError
	publish(player, "RoundCoinsCommitted", { Coins = resultOrError })
	return true
end

local function onlineEligiblePlayers()
	local result = {}
	for userId in pairs(participantSet) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(result, player)
		end
	end
	return result
end

local function tryCommitRound()
	if not currentRound or currentRound.Committed or currentRound.CommitInProgress then
		return false
	end
	for _, player in ipairs(onlineEligiblePlayers()) do
		local record = playerRecord(player.UserId)
		if not allClaimsCommitted(record) or record.CoinsState ~= "Committed" then
			return false
		end
	end
	currentRound.CommitInProgress = true
	local metadata = {
		RoundIndex = currentRound.RoundIndex,
		GlobalIslandIndex = currentRound.GlobalIslandIndex,
		ResolvedAt = now(),
		Players = {},
	}
	for userId, record in pairs(currentRound.Players) do
		metadata.Players[userId] = {
			CoreGrantId = record.Claims.Core.GrantId,
			BonusGrantId = record.Claims.Bonus.GrantId,
			CoinsState = record.CoinsState,
			Disconnected = record.Disconnected == true,
		}
	end
	local callback = options.CommitRoundReward
	local success, resultOrError
	if type(callback) == "function" then
		success, resultOrError = callback(currentRound.RoundIndex, metadata)
	else
		success, resultOrError = false, "CommitCallbackMissing"
	end
	if not success then
		currentRound.CommitInProgress = false
		currentRound.CommitError = tostring(resultOrError)
		workspace:SetAttribute("DungeonRewardCommitError", currentRound.CommitError)
		return false
	end
	currentRound.Committed = true
	currentRound.CommittedAt = now()
	if currentRound.Context and currentRound.Context.IslandModel then
		currentRound.Context.IslandModel:SetAttribute("RoundRewardActive", false)
		currentRound.Context.IslandModel:SetAttribute("RoundRewardCommitted", true)
	end
	workspace:SetAttribute("DungeonRewardCommitError", nil)
	for _, prompt in pairs(currentRound.Prompts) do
		if prompt and prompt.Parent then
			prompt.Enabled = false
		end
	end
	for _, player in ipairs(onlineEligiblePlayers()) do
		publish(player, "RewardRoundCommitted", { Commit = resultOrError })
	end
	updateWorldAttributes()
	return true
end

local function servicePass(token)
	if token ~= generation or not currentRound or currentRound.Committed then
		return
	end
	local shouldAutoResolve = now() >= currentRound.AutoResolveAt
	for _, player in ipairs(onlineEligiblePlayers()) do
		local record = playerRecord(player.UserId)
		for _, role in ipairs(CHEST_ROLES) do
			local state = record.Claims[role].State
			if state == "Saving" or state == "RetryPending" or (shouldAutoResolve and state == "Available") then
				claimChest(player, role, shouldAutoResolve)
			end
		end
		if allClaimsCommitted(record) and record.CoinsState ~= "Committed" then
			commitPlayerCoins(player)
		end
	end
	tryCommitRound()
end

local function startWorker(token)
	task.spawn(function()
		while started and token == generation and currentRound and not currentRound.Committed do
			servicePass(token)
			task.wait(RETRY_INTERVAL_SECONDS)
		end
	end)
end

function RewardIslandService.Start(startOptions)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	participantSet = {}
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
		end
	end
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		if not currentRound or not participantSet[player.UserId] then
			return
		end
		for _, role in ipairs(CHEST_ROLES) do
			claimChest(player, role, true)
		end
		commitPlayerCoins(player)
		local record = playerRecord(player.UserId)
		record.Disconnected = true
		task.defer(tryCommitRound)
	end)
end

function RewardIslandService.Stop()
	started = false
	generation += 1
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	currentRound = nil
	options = {}
	participantSet = {}
	updateWorldAttributes()
end

function RewardIslandService.BeginRound(result, islandContext)
	if not started or type(result) ~= "table" or type(islandContext) ~= "table" then
		return false, "InvalidRewardRound"
	end
	local roundIndex = math.clamp(math.floor(tonumber(result.RoundIndex) or 1), 1, 3)
	if currentRound and not currentRound.Committed then
		if currentRound.RoundIndex == roundIndex then
			return true, currentRound
		end
		return false, "PreviousRewardRoundActive"
	end
	local island = islandContext.IslandModel
	local markers = islandContext.ChestSpawns
	if not island or not island.Parent or not markers then
		return false, "RewardMarkersMissing"
	end
	local coreMarker = markers:FindFirstChild("RoundCoreChest")
	local bonusMarker = markers:FindFirstChild("RoundBonusChest")
	if not coreMarker or not bonusMarker then
		return false, "PersonalChestMarkersMissing"
	end
	generation += 1
	local content = island:FindFirstChild("RoundRewardContent")
	if content then
		content:Destroy()
	end
	content = Instance.new("Folder")
	content.Name = "RoundRewardContent"
	content:SetAttribute("RoundIndex", roundIndex)
	content:SetAttribute("GlobalIslandIndex", result.GlobalIslandIndex)
	content.Parent = island
	currentRound = {
		RoundIndex = roundIndex,
		GlobalIslandIndex = result.GlobalIslandIndex,
		Context = islandContext,
		Content = content,
		StartedAt = now(),
		AutoResolveAt = now() + AUTO_RESOLVE_SECONDS,
		Players = {},
		Chests = {},
		Prompts = {},
		Committed = false,
	}
	for userId in pairs(participantSet) do
		playerRecord(userId)
	end
	for role, marker in pairs({ Core = coreMarker, Bonus = bonusMarker }) do
		local chest, prompt = buildChest(marker, role, content)
		currentRound.Chests[role] = chest
		currentRound.Prompts[role] = prompt
		prompt.Triggered:Connect(function(player)
			claimChest(player, role, false)
			local record = playerRecord(player.UserId)
			if record and allClaimsCommitted(record) then
				commitPlayerCoins(player)
			end
			tryCommitRound()
		end)
	end
	island:SetAttribute("RoundRewardActive", true)
	island:SetAttribute("RoundRewardIndex", roundIndex)
	island:SetAttribute("RoundRewardAutoResolveAt", currentRound.AutoResolveAt)
	updateWorldAttributes()
	for _, player in ipairs(onlineEligiblePlayers()) do
		publish(player, "RewardRoundStarted")
	end
	startWorker(generation)
	return true, currentRound
end

function RewardIslandService.GetSnapshot(player)
	if player then
		return ownSnapshot(player)
	end
	return {
		Active = currentRound ~= nil and not currentRound.Committed,
		RoundIndex = currentRound and currentRound.RoundIndex,
		GlobalIslandIndex = currentRound and currentRound.GlobalIslandIndex,
		Committed = currentRound and currentRound.Committed == true,
	}
end

function RewardIslandService.Claim(player, chestRole)
	return claimChest(player, chestRole, false)
end

return RewardIslandService
