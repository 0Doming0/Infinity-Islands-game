--[[
	Sky Dungeon V10 - PlayerDataService

	Persiste somente o que deve sobreviver entre partidas nesta etapa: BestScore.
	O Score atual pertence a tentativa e sempre recomeca em zero.
]]

local DataStoreService = game:GetService("DataStoreService")

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local SAVE_RETRIES = 3
local RETRY_DELAY_SECONDS = 2

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local cache = {}

local PlayerDataService = {}

local function defaultData()
	return {
		BestScore = 0,
	}
end

local function sanitize(rawData)
	local data = defaultData()
	if type(rawData) == "table" then
		data.BestScore = math.max(0, math.floor(tonumber(rawData.BestScore) or 0))
	end
	return data
end

local function keyFor(player)
	return string.format("Player_%d", player.UserId)
end

function PlayerDataService.Load(player)
	if cache[player] then
		return cache[player]
	end

	local loadedData
	local success, loadError = pcall(function()
		loadedData = store:GetAsync(keyFor(player))
	end)

	if not success then
		warn(string.format("[SkyDungeon] Falha ao carregar dados de %s: %s", player.Name, tostring(loadError)))
	end

	local data = sanitize(loadedData)
	cache[player] = data
	return data
end

function PlayerDataService.Get(player)
	return cache[player]
end

function PlayerDataService.SetBestScore(player, value)
	local data = cache[player]
	if not data then
		return 0
	end
	data.BestScore = math.max(data.BestScore, math.max(0, math.floor(tonumber(value) or 0)))
	return data.BestScore
end

function PlayerDataService.Save(player)
	local data = cache[player]
	if not data then
		return true
	end

	local snapshot = sanitize(data)
	local lastError
	for attempt = 1, SAVE_RETRIES do
		local success, saveError = pcall(function()
			store:UpdateAsync(keyFor(player), function(previous)
				local previousData = sanitize(previous)
				return {
					BestScore = math.max(previousData.BestScore, snapshot.BestScore),
				}
			end)
		end)
		if success then
			return true
		end
		lastError = saveError
		if attempt < SAVE_RETRIES then
			task.wait(RETRY_DELAY_SECONDS * attempt)
		end
	end

	warn(string.format("[SkyDungeon] Falha ao salvar dados de %s: %s", player.Name, tostring(lastError)))
	return false
end

function PlayerDataService.Release(player)
	cache[player] = nil
end

return PlayerDataService
