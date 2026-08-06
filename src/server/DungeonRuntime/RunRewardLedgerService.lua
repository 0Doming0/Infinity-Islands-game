local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10)
local GameplayAnalytics = require(script.Parent.Parent.GameplayAnalyticsService)

local RunRewardLedgerService = {}

local started = false
local sessionId = ""
local participantSet = {}
local pendingByUserId = {}
local coinRewardRemote

local function ensureCoinRemote()
	local remote = ReplicatedStorage:FindFirstChild("CoinReward")
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "CoinReward"
		remote.Parent = ReplicatedStorage
	end
	coinRewardRemote = remote
end

local function roundBucket(userId, roundIndex)
	local user = pendingByUserId[userId]
	if not user then
		user = {}
		pendingByUserId[userId] = user
	end
	local bucket = user[roundIndex]
	if not bucket then
		bucket = { Amount = 0, Sources = {}, Committed = false }
		user[roundIndex] = bucket
	end
	return bucket
end

local function setPlayerAttributes(player, roundIndex, amount)
	player:SetAttribute("PendingRoundCoins", amount)
	player:SetAttribute("PendingRoundCoinsRound", roundIndex)
	player:SetAttribute("PendingRoundCoinsSerial", (player:GetAttribute("PendingRoundCoinsSerial") or 0) + 1)
end

function RunRewardLedgerService.Start(options)
	options = type(options) == "table" and options or {}
	started = true
	sessionId = tostring(options.SessionId or "")
	participantSet = {}
	pendingByUserId = {}
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
			pendingByUserId[userId] = {}
		end
	end
	ensureCoinRemote()
	workspace:SetAttribute("DungeonRewardLedgerEnabled", true)
	workspace:SetAttribute("DungeonPendingCoinsTotal", 0)
end

function RunRewardLedgerService.Stop()
	started = false
	workspace:SetAttribute("DungeonRewardLedgerEnabled", false)
end

function RunRewardLedgerService.AddPendingCoins(player, amount, source, worldPosition, roundIndex)
	if not started or not player or player.Parent ~= Players or not participantSet[player.UserId] then
		return false, 0
	end
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if clean <= 0 then
		return false, 0
	end
	roundIndex = math.clamp(
		math.floor(tonumber(roundIndex) or workspace:GetAttribute("DungeonObjectiveRoundIndex") or 1),
		1,
		3
	)
	local bucket = roundBucket(player.UserId, roundIndex)
	if bucket.Committed then
		return false, bucket.Amount
	end
	bucket.Amount += clean
	local sourceName = tostring(source or "Monster")
	bucket.Sources[sourceName] = (bucket.Sources[sourceName] or 0) + clean
	setPlayerAttributes(player, roundIndex, bucket.Amount)
	workspace:SetAttribute(
		"DungeonPendingCoinsTotal",
		math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonPendingCoinsTotal")) or 0)) + clean
	)
	if coinRewardRemote then
		coinRewardRemote:FireClient(player, {
			Amount = clean,
			PendingAmount = bucket.Amount,
			Pending = true,
			RoundIndex = roundIndex,
			Source = sourceName,
			WorldPosition = typeof(worldPosition) == "Vector3" and worldPosition or nil,
		})
	end
	return true, bucket.Amount
end

function RunRewardLedgerService.GetPendingCoins(playerOrUserId, roundIndex)
	local userId = typeof(playerOrUserId) == "Instance" and playerOrUserId.UserId
		or math.floor(tonumber(playerOrUserId) or 0)
	local user = pendingByUserId[userId]
	local bucket = user and user[math.clamp(math.floor(tonumber(roundIndex) or 1), 1, 3)]
	return bucket and bucket.Amount or 0
end

function RunRewardLedgerService.CommitRound(player, roundIndex)
	if not started or not player or player.Parent ~= Players or not participantSet[player.UserId] then
		return false, "InvalidParticipant"
	end
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 1), 1, 3)
	local bucket = roundBucket(player.UserId, roundIndex)
	if bucket.Committed then
		return true, { Amount = bucket.Amount, AlreadyCommitted = true }
	end
	local amount = bucket.Amount
	local duplicate = false
	local resultsOrError = {}
	if amount > 0 then
		local grantId = string.format(
			"DungeonPendingCoins:%s:%d:R%d",
			sessionId,
			player.UserId,
			roundIndex
		)
		local applied
		applied, duplicate, resultsOrError = PlayerDataService.ApplyDungeonGrant(player, grantId, {
			{ Kind = "Coins", Amount = amount },
		})
		if not applied then
			return false, resultsOrError
		end
		local saved = PlayerDataService.Save(player, true)
		if not saved then
			player:SetAttribute("PendingRoundCoinsSaveFailed", true)
			return false, "SavePending"
		end
	end
	bucket.Committed = true
	player:SetAttribute("PendingRoundCoinsSaveFailed", nil)
	setPlayerAttributes(player, roundIndex, 0)
	local balance = PlayerDataService.GetCoins(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	if coinsValue and coinsValue:IsA("IntValue") then
		coinsValue.Value = balance
	end
	player:SetAttribute("Coins", balance)
	player:SetAttribute("LastCommittedRoundCoins", amount)
	player:SetAttribute("LastCommittedRoundCoinsRound", roundIndex)
	GameplayAnalytics.RecordCoinsEarned(player, "RoundCommit", amount)
	if coinRewardRemote then
		coinRewardRemote:FireClient(player, {
			Amount = amount,
			Balance = balance,
			Pending = false,
			Committed = true,
			RoundIndex = roundIndex,
			Source = "RoundCommit",
		})
	end
	return true, {
		Amount = amount,
		Balance = balance,
		DuplicateGrant = duplicate == true,
		Results = resultsOrError,
	}
end

function RunRewardLedgerService.GetSnapshot()
	local users = {}
	for userId, rounds in pairs(pendingByUserId) do
		users[userId] = {}
		for roundIndex, bucket in pairs(rounds) do
			users[userId][roundIndex] = {
				Amount = bucket.Amount,
				Committed = bucket.Committed == true,
				Sources = table.clone(bucket.Sources),
			}
		end
	end
	return {
		Started = started,
		SessionId = sessionId,
		Users = users,
	}
end

return RunRewardLedgerService
