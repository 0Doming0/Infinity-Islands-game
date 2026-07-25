-- Recompensas diárias persistentes e marcos de tempo por sessão.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PlayerDataService = require(script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))

local RewardService = {}
local sessions = setmetatable({}, { __mode = "k" })
local started = false

local function todayIndex()
	return math.floor(os.time() / 86400)
end

local function ensureSession(player)
	local state = sessions[player]
	if not state then
		state = {
			StartedAt = os.clock(),
			ClaimedPlaytime = {},
			AnnouncedPlaytime = {},
		}
		sessions[player] = state
	end
	return state
end

local function nextDailyState(player)
	local lastDay, streak = PlayerDataService.GetDailyRewardState(player)
	local today = todayIndex()
	if lastDay >= today then
		return false, streak, today
	end
	local nextStreak = lastDay == today - 1 and math.min(7, streak + 1) or 1
	return true, nextStreak, today
end

function RewardService.GetSnapshot(player)
	PlayerDataService.Load(player)
	local state = ensureSession(player)
	local dailyClaimable, nextStreak = nextDailyState(player)
	local dailyDefinition = MVPConfig.Rewards.Daily[math.clamp(nextStreak, 1, #MVPConfig.Rewards.Daily)]
	local elapsedSeconds = math.max(0, os.clock() - state.StartedAt)
	local playtime = {}
	for _, definition in ipairs(MVPConfig.Rewards.Playtime) do
		local claimed = state.ClaimedPlaytime[definition.Minutes] == true
		table.insert(playtime, {
			Minutes = definition.Minutes,
			Coins = definition.Coins,
			Score = definition.Score,
			Claimed = claimed,
			Claimable = not claimed and elapsedSeconds >= definition.Minutes * 60,
			RemainingSeconds = math.max(0, math.ceil(definition.Minutes * 60 - elapsedSeconds)),
		})
	end
	return {
		Daily = {
			Claimable = dailyClaimable,
			Streak = nextStreak,
			Coins = dailyDefinition.Coins,
			Score = dailyDefinition.Score,
		},
		Playtime = playtime,
		ElapsedSeconds = math.floor(elapsedSeconds),
	}
end

function RewardService.ClaimDaily(player)
	PlayerDataService.Load(player)
	local claimable, streak, today = nextDailyState(player)
	if not claimable then
		return false, "A recompensa diária de hoje já foi coletada."
	end
	local definition = MVPConfig.Rewards.Daily[math.clamp(streak, 1, #MVPConfig.Rewards.Daily)]
	if not PlayerDataService.SetDailyRewardState(player, today, streak) then
		return false, "Não foi possível registrar a recompensa."
	end
	ScoreService.AwardRewards(player, definition.Score, definition.Coins, "DailyReward")
	task.spawn(PlayerDataService.Save, player, false)
	player:SetAttribute("DailyRewardStreak", streak)
	return true, string.format("Dia %d: +%d moedas e +%d pontos!", streak, definition.Coins, definition.Score)
end

function RewardService.ClaimPlaytime(player, minutes)
	local state = ensureSession(player)
	local cleanMinutes = math.floor(tonumber(minutes) or 0)
	local definition
	for _, candidate in ipairs(MVPConfig.Rewards.Playtime) do
		if candidate.Minutes == cleanMinutes then
			definition = candidate
			break
		end
	end
	if not definition then
		return false, "Recompensa de tempo inválida."
	end
	if state.ClaimedPlaytime[cleanMinutes] then
		return false, "Esta recompensa já foi coletada nesta sessão."
	end
	if os.clock() - state.StartedAt < cleanMinutes * 60 then
		return false, "Continue jogando para liberar esta recompensa."
	end
	state.ClaimedPlaytime[cleanMinutes] = true
	ScoreService.AwardRewards(player, definition.Score, definition.Coins, "PlaytimeReward")
	return true, string.format("%d min: +%d moedas e +%d pontos!", cleanMinutes, definition.Coins, definition.Score)
end

local function setupPlayer(player)
	PlayerDataService.Load(player)
	ensureSession(player)
	local _, streak = PlayerDataService.GetDailyRewardState(player)
	player:SetAttribute("DailyRewardStreak", streak)
end

function RewardService.Start()
	if started then
		return
	end
	started = true
	ScoreService.Start()
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end
	task.spawn(function()
		while started do
			task.wait(5)
			for player, state in pairs(sessions) do
				if player.Parent ~= Players then
					sessions[player] = nil
					continue
				end
				for _, definition in ipairs(MVPConfig.Rewards.Playtime) do
					if
						not state.ClaimedPlaytime[definition.Minutes]
						and not state.AnnouncedPlaytime[definition.Minutes]
						and os.clock() - state.StartedAt >= definition.Minutes * 60
					then
						state.AnnouncedPlaytime[definition.Minutes] = true
						player:SetAttribute(
							"RewardAvailableSerial",
							(player:GetAttribute("RewardAvailableSerial") or 0) + 1
						)
						player:SetAttribute("LastRewardAvailable", definition.Minutes .. " minutos")
					end
				end
			end
		end
	end)
end

return RewardService
