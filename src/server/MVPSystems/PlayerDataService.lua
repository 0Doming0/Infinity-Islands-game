--[[
	BlockParkour MVP - PlayerDataService

	Mantem Score separado dos dados persistentes. Em caso de falha no carregamento,
	o jogador recebe dados temporarios, mas a sessao nao sobrescreve o DataStore.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDataService = {}

local DATASTORE_NAME = "BlockParkour_PlayerData_v1"
local DATA_VERSION = 1
local LOAD_ATTEMPTS = 3
local SAVE_ATTEMPTS = 3
local RETRY_DELAY_SECONDS = 2
local AUTOSAVE_INTERVAL_SECONDS = 60

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local sessions = {}
local started = false
local closing = false

local function defaultData()
	return {
		DataVersion = DATA_VERSION,
		Coins = 0,
		BestScore = 0,
		OwnedItems = {},
		Equipped = {},
	}
end

local function copyDictionary(source)
	local result = {}
	if typeof(source) == "table" then
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

local function sanitizeData(raw)
	local result = defaultData()
	if typeof(raw) ~= "table" then
		return result
	end

	if typeof(raw.Coins) == "number" then
		result.Coins = math.max(0, math.floor(raw.Coins))
	end
	if typeof(raw.BestScore) == "number" then
		result.BestScore = math.max(0, math.floor(raw.BestScore))
	end

	if typeof(raw.OwnedItems) == "table" then
		for itemId, amount in pairs(raw.OwnedItems) do
			if typeof(itemId) == "string" and itemId ~= "" and typeof(amount) == "number" and amount > 0 then
				result.OwnedItems[itemId] = math.floor(amount)
			end
		end
	end
	if typeof(raw.Equipped) == "table" then
		for slot, itemId in pairs(raw.Equipped) do
			if typeof(slot) == "string" and typeof(itemId) == "string" and itemId ~= "" then
				result.Equipped[slot] = itemId
			end
		end
	end

	return result
end

local function keyForPlayer(player)
	return "Player_" .. tostring(player.UserId)
end

local function retry(operationName, attempts, callback)
	local lastError = nil
	for attempt = 1, attempts do
		local success, result = pcall(callback)
		if success then
			return true, result
		end
		lastError = result
		warn(
			string.format("[MVP PlayerData] %s falhou (%d/%d): %s", operationName, attempt, attempts, tostring(result))
		)
		if attempt < attempts then
			task.wait(RETRY_DELAY_SECONDS * attempt)
		end
	end
	return false, lastError
end

local function makeLeaderstats(player, session)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Value = 0
	score.Parent = leaderstats

	local bestScore = Instance.new("IntValue")
	bestScore.Name = "BestScore"
	bestScore.Value = session.Data.BestScore
	bestScore.Parent = leaderstats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = session.Data.Coins
	coins.Parent = leaderstats

	session.ScoreValue = score
	session.BestScoreValue = bestScore
	session.CoinsValue = coins
end

local function markDirty(session)
	session.Dirty = true
end

local function loadPlayer(player)
	if sessions[player] then
		return
	end

	local success, raw = retry("Load " .. player.Name, LOAD_ATTEMPTS, function()
		return store:GetAsync(keyForPlayer(player))
	end)
	if not player.Parent then
		return
	end

	local session = {
		Data = sanitizeData(success and raw or nil),
		CanSave = success,
		Dirty = false,
		Saving = false,
	}
	sessions[player] = session
	makeLeaderstats(player, session)
	player:SetAttribute("MVPDataLoaded", true)
	player:SetAttribute("MVPDataTemporary", not success)

	if not success then
		warn(string.format("[MVP PlayerData] %s usa dados temporarios; esta sessao nao sera salva", player.Name))
	end

	player.CharacterAdded:Connect(function()
		local current = sessions[player]
		if current and current.ScoreValue then
			current.ScoreValue.Value = 0
		end
	end)
end

local function snapshotForSave(session)
	return {
		DataVersion = DATA_VERSION,
		Coins = session.Data.Coins,
		BestScore = session.Data.BestScore,
		OwnedItems = copyDictionary(session.Data.OwnedItems),
		Equipped = copyDictionary(session.Data.Equipped),
	}
end

local function savePlayer(player, force)
	local session = sessions[player]
	if not session or not session.CanSave or session.Saving or (not force and not session.Dirty) then
		return false
	end

	session.Saving = true
	local snapshot = snapshotForSave(session)
	local success = retry("Save " .. player.Name, SAVE_ATTEMPTS, function()
		return store:UpdateAsync(keyForPlayer(player), function()
			return snapshot
		end)
	end)
	session.Saving = false
	if success then
		session.Dirty = false
	end
	return success
end

local function getSession(player)
	return sessions[player]
end

function PlayerDataService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player, true)
		sessions[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end

	task.spawn(function()
		while not closing do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			for player in pairs(sessions) do
				task.spawn(savePlayer, player, false)
			end
		end
	end)

	game:BindToClose(function()
		closing = true
		if RunService:IsStudio() and #Players:GetPlayers() == 0 then
			return
		end
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(savePlayer, player, true)
		end
		task.wait()
		local deadline = os.clock() + 25
		repeat
			local stillSaving = false
			for _, session in pairs(sessions) do
				stillSaving = stillSaving or session.Saving
			end
			if not stillSaving then
				break
			end
			task.wait(0.1)
		until os.clock() >= deadline
	end)
end

function PlayerDataService.IsLoaded(player)
	return sessions[player] ~= nil
end

function PlayerDataService.GetSnapshot(player)
	local session = getSession(player)
	if not session then
		return nil
	end
	return snapshotForSave(session)
end

function PlayerDataService.AddCoins(player, amount)
	local session = getSession(player)
	if not session or typeof(amount) ~= "number" or amount <= 0 then
		return false
	end
	local integerAmount = math.floor(amount)
	if integerAmount <= 0 then
		return false
	end
	session.Data.Coins += integerAmount
	session.CoinsValue.Value = session.Data.Coins
	markDirty(session)
	return true, session.Data.Coins
end

function PlayerDataService.TrySpendCoins(player, amount)
	local session = getSession(player)
	if not session or typeof(amount) ~= "number" then
		return false, "DataNotLoaded"
	end
	local integerAmount = math.floor(amount)
	if integerAmount < 0 or session.Data.Coins < integerAmount then
		return false, "InsufficientCoins"
	end
	session.Data.Coins -= integerAmount
	session.CoinsValue.Value = session.Data.Coins
	markDirty(session)
	return true, session.Data.Coins
end

function PlayerDataService.AddScore(player, amount)
	local session = getSession(player)
	if not session or typeof(amount) ~= "number" or amount <= 0 then
		return false
	end
	local integerAmount = math.floor(amount)
	if integerAmount <= 0 then
		return false
	end
	session.ScoreValue.Value += integerAmount
	if session.ScoreValue.Value > session.Data.BestScore then
		session.Data.BestScore = session.ScoreValue.Value
		session.BestScoreValue.Value = session.Data.BestScore
		markDirty(session)
	end
	return true, session.ScoreValue.Value, session.Data.BestScore
end

-- Concede Score e Coins sem yield, como uma unica operacao logica do servidor.
-- Isso impede que dois jogadores recebam parcialmente o mesmo coletavel.
function PlayerDataService.GrantAttemptRewards(player, scoreAmount, coinAmount)
	local session = getSession(player)
	if not session or typeof(scoreAmount) ~= "number" or typeof(coinAmount) ~= "number" then
		return false, "InvalidReward"
	end
	local score = math.floor(scoreAmount)
	local coins = math.floor(coinAmount)
	if score < 0 or coins < 0 then
		return false, "InvalidReward"
	end

	session.ScoreValue.Value += score
	session.Data.Coins += coins
	session.CoinsValue.Value = session.Data.Coins
	if session.ScoreValue.Value > session.Data.BestScore then
		session.Data.BestScore = session.ScoreValue.Value
		session.BestScoreValue.Value = session.Data.BestScore
	end
	if score > 0 or coins > 0 then
		markDirty(session)
	end
	return true, session.ScoreValue.Value, session.Data.Coins, session.Data.BestScore
end

function PlayerDataService.AddOwnedItem(player, itemId, amount, stackable)
	local session = getSession(player)
	if not session or typeof(itemId) ~= "string" or itemId == "" then
		return false, "InvalidItem"
	end
	local integerAmount = math.max(1, math.floor(amount or 1))
	local current = session.Data.OwnedItems[itemId] or 0
	if not stackable and current > 0 then
		return false, "AlreadyOwned"
	end
	session.Data.OwnedItems[itemId] = stackable and (current + integerAmount) or 1
	markDirty(session)
	return true, session.Data.OwnedItems[itemId]
end

function PlayerDataService.SetEquipped(player, slot, itemId)
	local session = getSession(player)
	if not session then
		return false, "DataNotLoaded"
	end
	if itemId ~= nil and (session.Data.OwnedItems[itemId] or 0) <= 0 then
		return false, "NotOwned"
	end
	if itemId == nil then
		session.Data.Equipped[slot] = nil
	else
		session.Data.Equipped[slot] = itemId
	end
	markDirty(session)
	return true
end

return PlayerDataService
