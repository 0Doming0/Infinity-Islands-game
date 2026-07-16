--[[
	SkyDungeon - ScoreService canonico

	Score e a moeda persistente unica do MVP. RunScore mede apenas a tentativa
	atual e alimenta BestScore. Toda recompensa valida recebe o multiplicador da
	espada selecionada no servidor.
]]

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.PlayerDataService_SkyDungeon_V10)

local DEFAULT_MULTIPLIER = 1
local MIN_MULTIPLIER = 1
local MAX_MULTIPLIER = 25
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

local function setupPlayer(player)
	local data = PlayerDataService.Load(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local score = getOrCreateIntValue(leaderstats, "Score")
	local bestScore = getOrCreateIntValue(leaderstats, "BestScore")
	local runScore = getOrCreateIntValue(player, "RunScore")
	score.Value = data.TotalScore
	bestScore.Value = data.BestScore
	runScore.Value = 0

	if player:GetAttribute("ScoreMultiplier") == nil then
		player:SetAttribute("ScoreMultiplier", DEFAULT_MULTIPLIER)
	end
	player:SetAttribute("ScoreDataLoaded", true)
end

local function getValues(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil, nil, nil
	end
	return leaderstats:FindFirstChild("Score"), leaderstats:FindFirstChild("BestScore"), player:FindFirstChild("RunScore")
end

local function syncPersistentScore(player, totalScore)
	local score = getValues(player)
	if score then
		score.Value = totalScore
	end
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
	local score, bestScore, runScore = getValues(player)
	if not score or not bestScore or not runScore then
		return 0
	end

	local cleanBase = math.max(0, tonumber(baseAmount) or 0)
	local awarded = math.max(0, math.floor(cleanBase * ScoreService.GetMultiplier(player)))
	if awarded == 0 then
		return 0
	end

	local total = PlayerDataService.AddTotalScore(player, awarded)
	score.Value = total
	runScore.Value += awarded
	if runScore.Value > bestScore.Value then
		bestScore.Value = runScore.Value
		PlayerDataService.SetBestScore(player, bestScore.Value)
	end

	player:SetAttribute("LastScoreSource", tostring(source or "Unknown"))
	player:SetAttribute("LastScoreAward", awarded)
	player:SetAttribute("LastScoreSerial", (player:GetAttribute("LastScoreSerial") or 0) + 1)
	return awarded
end

function ScoreService.TrySpend(player, amount)
	local success, remaining = PlayerDataService.TrySpendScore(player, amount)
	if success then
		syncPersistentScore(player, remaining)
	end
	return success, remaining
end

function ScoreService.GetScore(player)
	local score = getValues(player)
	return score and score.Value or PlayerDataService.GetTotalScore(player)
end

function ScoreService.GetRunScore(player)
	local _, _, runScore = getValues(player)
	return runScore and runScore.Value or 0
end

function ScoreService.GetBestScore(player)
	local _, bestScore = getValues(player)
	return bestScore and bestScore.Value or 0
end

function ScoreService.ResetRun(player)
	local _, _, runScore = getValues(player)
	if runScore then
		runScore.Value = 0
	end
	player:SetAttribute("LastScoreSource", nil)
	player:SetAttribute("LastScoreAward", nil)
end

function ScoreService.CommitBest(player)
	local _, bestScore, runScore = getValues(player)
	if not bestScore or not runScore then
		return
	end
	if runScore.Value > bestScore.Value then
		bestScore.Value = runScore.Value
	end
	PlayerDataService.SetBestScore(player, bestScore.Value)
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
