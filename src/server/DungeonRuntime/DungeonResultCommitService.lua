local Players = game:GetService("Players")

local PlayerDataService = require(
	script.Parent.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10
)

local DungeonResultCommitService = {}

local function cleanUserIds(raw)
	local result = {}
	local seen = {}
	for _, value in ipairs(type(raw) == "table" and raw or {}) do
		local userId = math.floor(tonumber(value) or 0)
		if userId > 0 and not seen[userId] then
			seen[userId] = true
			table.insert(result, userId)
		end
	end
	return result, seen
end

local function resultIdFor(sessionId, userId)
	return string.format("DungeonResult:%s:%d", tostring(sessionId), userId)
end

local function syncConnectedPlayer(player, record)
	if not player or player.Parent ~= Players or type(record) ~= "table" then
		return
	end
	local balance = math.max(0, math.floor(tonumber(record.Balance) or 0))
	player:SetAttribute("Coins", balance)
	player:SetAttribute("DungeonResultCommitted", true)
	player:SetAttribute("DungeonResultId", tostring(record.ResultId or ""))
	player:SetAttribute("DungeonResult", tostring(record.Result or ""))
	player:SetAttribute("DungeonResultRewardCoins", math.max(0, math.floor(tonumber(record.RewardCoins) or 0)))
	player:SetAttribute("DungeonResultCommitAt", math.max(0, math.floor(tonumber(record.ProcessedAt) or 0)))
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		coins.Value = balance
	end
end

function DungeonResultCommitService.CommitSession(options)
	assert(type(options) == "table", "CommitSession requer opcoes")
	local sessionId = tostring(options.SessionId or "")
	local phaseId = tostring(options.PhaseId or "")
	local resultName = tostring(options.Result or "Defeat")
	if sessionId == "" or phaseId == "" then
		return false, {}, "InvalidSessionResult"
	end

	local participantUserIds = cleanUserIds(options.ParticipantUserIds)
	local _, eligibleSet = cleanUserIds(options.EligibleUserIds)
	local elapsedSeconds = math.max(0, tonumber(options.ElapsedSeconds) or 0)
	local victoryCoins = math.max(0, math.floor(tonumber(options.VictoryCoins) or 0))
	local results = {}
	local allCommitted = true
	local processedCount = 0
	local committedCount = 0
	local failedCount = 0
	local alreadyProcessedCount = 0

	workspace:SetAttribute("DungeonResultCommitState", "Committing")
	workspace:SetAttribute("DungeonResultCommitExpectedCount", #participantUserIds)
	workspace:SetAttribute("DungeonResultCommitCompletedCount", 0)
	workspace:SetAttribute("DungeonResultCommitFailedCount", 0)

	for _, userId in ipairs(participantUserIds) do
		local eligible = resultName == "Victory" and eligibleSet[userId] == true
		local payload = {
			SessionId = sessionId,
			PhaseId = phaseId,
			Result = resultName,
			Eligible = eligible,
			RewardCoins = eligible and victoryCoins or 0,
			ElapsedSeconds = elapsedSeconds,
			CompletedAt = os.time(),
		}
		local resultId = resultIdFor(sessionId, userId)
		local player = Players:GetPlayerByUserId(userId)
		local success, applied, record, errorCode
		if player then
			success, applied, record, errorCode = PlayerDataService.CommitDungeonResult(
				player,
				resultId,
				payload
			)
		else
			success, applied, record, errorCode = PlayerDataService.CommitDungeonResultByUserId(
				userId,
				resultId,
				payload
			)
		end
		results[userId] = {
			Success = success == true,
			Applied = applied == true,
			AlreadyProcessed = success == true and applied ~= true,
			Record = record,
			Error = errorCode,
			Connected = player ~= nil,
			Eligible = eligible,
			ResultId = resultId,
		}
		processedCount += 1
		if success then
			committedCount += 1
			if applied ~= true then
				alreadyProcessedCount += 1
			end
			syncConnectedPlayer(player, record)
		else
			failedCount += 1
			allCommitted = false
		end
		workspace:SetAttribute("DungeonResultCommitProcessedCount", processedCount)
		workspace:SetAttribute("DungeonResultCommitCompletedCount", committedCount)
		workspace:SetAttribute("DungeonResultCommitFailedCount", failedCount)
	end

	workspace:SetAttribute("DungeonResultCommitAlreadyProcessedCount", alreadyProcessedCount)
	workspace:SetAttribute("DungeonResultCommitState", allCommitted and "Committed" or "Failed")
	workspace:SetAttribute("DungeonResultCommitFinishedAt", workspace:GetServerTimeNow())
	return allCommitted, results, allCommitted and nil or "OneOrMoreResultCommitsFailed"
end

function DungeonResultCommitService.ResultIdFor(sessionId, userId)
	return resultIdFor(sessionId, math.floor(tonumber(userId) or 0))
end

return DungeonResultCommitService
