--[[
	SkyDungeon - pontuacao e moeda

	RunScore mede apenas a tentativa atual; BestScore e o recorde persistente;
	Coins e a unica moeda. Toda alteracao passa pelo servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PlayerDataService = require(script.Parent.PlayerDataService_SkyDungeon_V10)

local coinRewardRemote = ReplicatedStorage:FindFirstChild("CoinReward")
if coinRewardRemote and not coinRewardRemote:IsA("RemoteEvent") then
	coinRewardRemote:Destroy()
	coinRewardRemote = nil
end
if not coinRewardRemote then
	coinRewardRemote = Instance.new("RemoteEvent")
	coinRewardRemote.Name = "CoinReward"
	coinRewardRemote.Parent = ReplicatedStorage
end

local DEFAULT_MULTIPLIER = 1
local MIN_MULTIPLIER = 1
local MAX_MULTIPLIER = 3
local AUTOSAVE_INTERVAL_SECONDS = 60

local ScoreService = {}
local started = false

local function getOrCreateIntValue(parent, name)
	local value = parent:FindFirstChild(name)
	if value and not value:IsA("IntValue") then
		value:Destroy()
		value = nil
	end
	if not value then
		value = Instance.new("IntValue")
		value.Name = name
		value.Parent = parent
	end
	return value
end

local function getValues(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil, nil, nil, nil
	end
	return leaderstats:FindFirstChild("Score"),
		leaderstats:FindFirstChild("BestScore"),
		leaderstats:FindFirstChild("Coins"),
		player:FindFirstChild("RunScore")
end

local function syncRunScore(player, value)
	local score, _, _, runScore = getValues(player)
	if score then
		score.Value = value
	end
	if runScore then
		runScore.Value = value
	end
	player:SetAttribute("RunScore", value)
end

local function syncBestScore(player, value)
	local _, bestScore = getValues(player)
	if bestScore then
		bestScore.Value = value
	end
	player:SetAttribute("BestScore", value)
end

local function syncCoins(player, value)
	local _, _, coins = getValues(player)
	if coins then
		coins.Value = value
	end
	player:SetAttribute("Coins", value)
end

local function setupPlayer(player)
	local data = PlayerDataService.Load(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	getOrCreateIntValue(leaderstats, "Score")
	getOrCreateIntValue(leaderstats, "BestScore")
	getOrCreateIntValue(leaderstats, "Coins")
	getOrCreateIntValue(player, "RunScore")
	syncRunScore(player, 0)
	syncBestScore(player, data.BestScore)
	syncCoins(player, data.Coins)

	if player:GetAttribute("ScoreMultiplier") == nil then
		player:SetAttribute("ScoreMultiplier", DEFAULT_MULTIPLIER)
	end
	player:SetAttribute("ScoreDataLoaded", true)
end

function ScoreService.GetMultiplier(player)
	return math.clamp(tonumber(player:GetAttribute("ScoreMultiplier")) or DEFAULT_MULTIPLIER, MIN_MULTIPLIER, MAX_MULTIPLIER)
end

function ScoreService.SetSwordMultiplier(player, multiplier)
	local clean = math.clamp(tonumber(multiplier) or DEFAULT_MULTIPLIER, MIN_MULTIPLIER, MAX_MULTIPLIER)
	player:SetAttribute("ScoreMultiplier", clean)
	return clean
end

function ScoreService.Award(player, baseAmount, source)
	local score, bestScore, _, runScore = getValues(player)
	if not score or not bestScore or not runScore then
		return 0
	end
	local cleanBase = math.max(0, tonumber(baseAmount) or 0)
	local awarded = math.max(0, math.floor(cleanBase * ScoreService.GetMultiplier(player)))
	if awarded == 0 then
		return 0
	end

	local nextRun = runScore.Value + awarded
	syncRunScore(player, nextRun)
	if nextRun > bestScore.Value then
		local savedBest = PlayerDataService.SetBestScore(player, nextRun)
		syncBestScore(player, savedBest)
		player:SetAttribute("BestScoreUpdatedSerial", (player:GetAttribute("BestScoreUpdatedSerial") or 0) + 1)
	end
	player:SetAttribute("LastScoreSource", tostring(source or "Unknown"))
	player:SetAttribute("LastScoreAward", awarded)
	player:SetAttribute("LastScoreSerial", (player:GetAttribute("LastScoreSerial") or 0) + 1)
	return awarded
end

function ScoreService.AwardCoins(player, baseAmount, source, worldPosition)
	local multiplier = math.max(1, tonumber(workspace:GetAttribute("CoinRewardMultiplier")) or 1)
	local awarded = math.max(0, math.floor((tonumber(baseAmount) or 0) * multiplier))
	if awarded <= 0 then
		return 0
	end
	local success, balance = PlayerDataService.AddCoins(player, awarded)
	if not success then
		return 0
	end
	syncCoins(player, balance)
	player:SetAttribute("LastCoinSource", tostring(source or "Unknown"))
	player:SetAttribute("LastCoinAward", awarded)
	player:SetAttribute("LastCoinSerial", (player:GetAttribute("LastCoinSerial") or 0) + 1)
	coinRewardRemote:FireClient(player, {
		Amount = awarded,
		Balance = balance,
		Source = tostring(source or "Unknown"),
		WorldPosition = if typeof(worldPosition) == "Vector3" then worldPosition else nil,
	})
	return awarded
end

function ScoreService.RefundCoins(player, amount, source)
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	local success, balance = PlayerDataService.AddCoins(player, clean)
	if success then
		syncCoins(player, balance)
		player:SetAttribute("LastCoinSource", tostring(source or "Refund"))
	end
	return success, balance
end

function ScoreService.AwardRewards(player, scoreAmount, coinAmount, source, worldPosition)
	return ScoreService.Award(player, scoreAmount, source),
		ScoreService.AwardCoins(player, coinAmount, source, worldPosition)
end

function ScoreService.TrySpendCoins(player, amount)
	local success, remaining = PlayerDataService.TrySpendCoins(player, amount)
	if success then
		syncCoins(player, remaining)
	end
	return success, remaining
end

-- Compatibilidade com lojas antigas. Todo gasto agora usa Coins.
function ScoreService.TrySpend(player, amount)
	return ScoreService.TrySpendCoins(player, amount)
end

function ScoreService.GetScore(player)
	return ScoreService.GetRunScore(player)
end

function ScoreService.GetRunScore(player)
	local _, _, _, runScore = getValues(player)
	return runScore and runScore.Value or 0
end

function ScoreService.GetBestScore(player)
	local _, bestScore = getValues(player)
	return bestScore and bestScore.Value or 0
end

function ScoreService.GetCoins(player)
	local _, _, coins = getValues(player)
	return coins and coins.Value or PlayerDataService.GetCoins(player)
end

function ScoreService.ResetRun(player)
	syncRunScore(player, 0)
	player:SetAttribute("LastScoreSource", nil)
	player:SetAttribute("LastScoreAward", nil)
end

function ScoreService.CommitBest(player)
	local runScore = ScoreService.GetRunScore(player)
	local nextBest = PlayerDataService.SetBestScore(player, runScore)
	syncBestScore(player, nextBest)
	return nextBest
end

function ScoreService.HandleDeath(player, cause)
	if not PlayerDataService.Get(player) then
		return 0, 0, 0
	end
	local runScore = ScoreService.GetRunScore(player)
	ScoreService.CommitBest(player)
	local lostCoins, remainingCoins = PlayerDataService.RemoveCoinsPercent(
		player,
		MVPConfig.Progression.DeathCoinLossPercent
	)
	syncCoins(player, remainingCoins)
	player:SetAttribute("LastDeathRunScore", runScore)
	player:SetAttribute("LastDeathCoinsLost", lostCoins)
	player:SetAttribute("LastDeathCause", tostring(cause or "Unknown"))
	player:SetAttribute("DeathPenaltySerial", (player:GetAttribute("DeathPenaltySerial") or 0) + 1)
	ScoreService.ResetRun(player)
	return runScore, lostCoins, remainingCoins
end

function ScoreService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		ScoreService.CommitBest(player)
		PlayerDataService.Save(player, true)
		PlayerDataService.Release(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end

	task.spawn(function()
		while started do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				ScoreService.CommitBest(player)
				task.spawn(PlayerDataService.Save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			ScoreService.CommitBest(player)
			PlayerDataService.Save(player, true)
		end
	end)
end

return ScoreService