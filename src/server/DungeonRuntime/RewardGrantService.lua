local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10)

local RewardGrantService = {}

local pendingByGrantId = {}

function RewardGrantService.GrantBundle(player, bundle)
	if not player or player.Parent ~= Players or type(bundle) ~= "table" then
		return false, "InvalidGrantRequest"
	end
	local grantId = tostring(bundle.GrantId or "")
	if grantId == "" or type(bundle.Rewards) ~= "table" then
		return false, "InvalidGrantBundle"
	end
	local previousPending = pendingByGrantId[grantId]
	local applied, duplicate, resultsOrError = PlayerDataService.ApplyDungeonGrant(
		player,
		grantId,
		bundle.Rewards
	)
	if duplicate == true and previousPending and previousPending.Results then
		resultsOrError = previousPending.Results
	end
	if not applied then
		pendingByGrantId[grantId] = {
			Player = player,
			Bundle = bundle,
			Reason = tostring(resultsOrError),
			LastAttemptAt = workspace:GetServerTimeNow(),
		}
		return false, resultsOrError
	end
	local saved = PlayerDataService.Save(player, true)
	if not saved then
		pendingByGrantId[grantId] = {
			Player = player,
			Bundle = bundle,
			Reason = "SavePending",
			LastAttemptAt = workspace:GetServerTimeNow(),
			Results = resultsOrError,
		}
		player:SetAttribute("DungeonRewardSavePending", true)
		return false, "SavePending"
	end
	pendingByGrantId[grantId] = nil
	player:SetAttribute("DungeonRewardSavePending", nil)
	local balance = PlayerDataService.GetCoins(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	if coinsValue and coinsValue:IsA("IntValue") then
		coinsValue.Value = balance
	end
	player:SetAttribute("Coins", balance)
	return true, {
		GrantId = grantId,
		DuplicateGrant = duplicate == true,
		Results = resultsOrError,
	}
end

function RewardGrantService.Retry(grantId)
	local pending = pendingByGrantId[grantId]
	if not pending then
		return true, "NoPendingGrant"
	end
	if not pending.Player or pending.Player.Parent ~= Players then
		return false, "PlayerUnavailable"
	end
	pending.LastAttemptAt = workspace:GetServerTimeNow()
	return RewardGrantService.GrantBundle(pending.Player, pending.Bundle)
end

function RewardGrantService.HasPendingForPlayer(player)
	for _, pending in pairs(pendingByGrantId) do
		if pending.Player == player then
			return true
		end
	end
	return false
end

function RewardGrantService.GetSnapshot()
	local pending = {}
	for grantId, record in pairs(pendingByGrantId) do
		pending[grantId] = {
			UserId = record.Player and record.Player.UserId,
			Reason = record.Reason,
			LastAttemptAt = record.LastAttemptAt,
		}
	end
	return { Pending = pending }
end

return RewardGrantService
