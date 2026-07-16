--[[
	SkyDungeon - PlayerDataService canonico

	Persiste o progresso do MVP em um unico registro: pontos totais, melhor
	tentativa, espadas possuidas e espada equipada. O schema e compativel com os
	registros V10 antigos que continham apenas BestScore.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local SCHEMA_VERSION = 2
local STARTER_SWORD_ID = "ClassicSword"
local LOAD_RETRIES = 4
local SAVE_RETRIES = 4
local RETRY_DELAY_SECONDS = 1.5

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local sessions = {}
local loadingSignals = {}

local PlayerDataService = {}

local function markDirty(session)
	session.Dirty = true
	session.Revision += 1
end

local function defaultData()
	return {
		SchemaVersion = SCHEMA_VERSION,
		TotalScore = 0,
		BestScore = 0,
		OwnedSwords = {
			[STARTER_SWORD_ID] = true,
		},
		EquippedSword = STARTER_SWORD_ID,
	}
end

local function sanitizeOwnedSwords(raw)
	local owned = {
		[STARTER_SWORD_ID] = true,
	}
	if type(raw) ~= "table" then
		return owned
	end
	for key, value in pairs(raw) do
		if type(key) == "string" and value == true then
			owned[key] = true
		elseif type(key) == "number" and type(value) == "string" and value ~= "" then
			owned[value] = true
		end
	end
	return owned
end

local function sanitize(raw)
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end

	data.TotalScore = math.max(0, math.floor(tonumber(raw.TotalScore or raw.Score) or 0))
	data.BestScore = math.max(0, math.floor(tonumber(raw.BestScore) or 0))
	data.OwnedSwords = sanitizeOwnedSwords(raw.OwnedSwords)

	local equipped = type(raw.EquippedSword) == "string" and raw.EquippedSword or STARTER_SWORD_ID
	if data.OwnedSwords[equipped] then
		data.EquippedSword = equipped
	end
	return data
end

local function cloneData(data)
	local result = {
		SchemaVersion = SCHEMA_VERSION,
		TotalScore = data.TotalScore,
		BestScore = data.BestScore,
		OwnedSwords = {},
		EquippedSword = data.EquippedSword,
	}
	for swordId, owned in pairs(data.OwnedSwords) do
		if owned then
			result.OwnedSwords[swordId] = true
		end
	end
	return result
end

local function keyFor(player)
	return string.format("Player_%d", player.UserId)
end

local function retry(label, count, callback)
	local lastError
	for attempt = 1, count do
		local success, result = pcall(callback)
		if success then
			return true, result
		end
		lastError = result
		warn(string.format("[PlayerData] %s falhou (%d/%d): %s", label, attempt, count, tostring(result)))
		if attempt < count then
			task.wait(RETRY_DELAY_SECONDS * attempt)
		end
	end
	return false, lastError
end

function PlayerDataService.Load(player)
	local existing = sessions[player]
	if existing then
		return existing.Data
	end
	local inFlight = loadingSignals[player]
	if inFlight then
		inFlight.Event:Wait()
		local loadedSession = sessions[player]
		return loadedSession and loadedSession.Data or defaultData()
	end

	local signal = Instance.new("BindableEvent")
	loadingSignals[player] = signal

	local success, raw = retry("Load " .. player.Name, LOAD_RETRIES, function()
		return store:GetAsync(keyFor(player))
	end)
	local data = sanitize(success and raw or nil)
	sessions[player] = {
		Data = data,
		CanSave = success,
		Dirty = false,
		Revision = 0,
		SessionId = HttpService:GenerateGUID(false),
	}

	player:SetAttribute("PlayerDataLoaded", true)
	player:SetAttribute("PlayerDataTemporary", not success)
	if not success then
		warn("[PlayerData] " .. player.Name .. " usa dados temporarios; a sessao nao sobrescrevera o DataStore.")
	end
	loadingSignals[player] = nil
	signal:Fire()
	signal:Destroy()
	return data
end

function PlayerDataService.Get(player)
	local session = sessions[player]
	return session and session.Data or nil
end

function PlayerDataService.GetSnapshot(player)
	local data = PlayerDataService.Get(player)
	return data and cloneData(data) or nil
end

function PlayerDataService.GetTotalScore(player)
	local data = PlayerDataService.Get(player)
	return data and data.TotalScore or 0
end

function PlayerDataService.AddTotalScore(player, amount)
	local session = sessions[player]
	if not session then
		return 0
	end
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	session.Data.TotalScore += clean
	if clean > 0 then
		markDirty(session)
	end
	return session.Data.TotalScore
end

function PlayerDataService.TrySpendScore(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 or session.Data.TotalScore < clean then
		return false, session and session.Data.TotalScore or 0
	end
	session.Data.TotalScore -= clean
	markDirty(session)
	return true, session.Data.TotalScore
end

function PlayerDataService.SetBestScore(player, value)
	local session = sessions[player]
	if not session then
		return 0
	end
	local nextValue = math.max(session.Data.BestScore, math.max(0, math.floor(tonumber(value) or 0)))
	if nextValue ~= session.Data.BestScore then
		session.Data.BestScore = nextValue
		markDirty(session)
	end
	return nextValue
end

function PlayerDataService.HasSword(player, swordId)
	local data = PlayerDataService.Get(player)
	return data ~= nil and data.OwnedSwords[swordId] == true
end

function PlayerDataService.GrantSword(player, swordId)
	local session = sessions[player]
	if not session or type(swordId) ~= "string" or swordId == "" then
		return false
	end
	if session.Data.OwnedSwords[swordId] then
		return true
	end
	session.Data.OwnedSwords[swordId] = true
	markDirty(session)
	return true
end

function PlayerDataService.SetEquippedSword(player, swordId)
	local session = sessions[player]
	if not session or session.Data.OwnedSwords[swordId] ~= true then
		return false
	end
	session.Data.EquippedSword = swordId
	markDirty(session)
	return true
end

function PlayerDataService.Save(player, force)
	local session = sessions[player]
	if not session or not session.CanSave or (not force and not session.Dirty) then
		return session == nil or session.CanSave
	end

	local snapshot = cloneData(session.Data)
	local snapshotRevision = session.Revision
	local success = retry("Save " .. player.Name, SAVE_RETRIES, function()
		return store:UpdateAsync(keyFor(player), function(previous)
			local previousData = sanitize(previous)
			for swordId, owned in pairs(previousData.OwnedSwords) do
				if owned then
					snapshot.OwnedSwords[swordId] = true
				end
			end
			snapshot.BestScore = math.max(snapshot.BestScore, previousData.BestScore)
			if not snapshot.OwnedSwords[snapshot.EquippedSword] then
				snapshot.EquippedSword = STARTER_SWORD_ID
			end
			return snapshot
		end)
	end)
	if success and session.Revision == snapshotRevision then
		session.Dirty = false
	end
	return success
end

function PlayerDataService.Release(player)
	sessions[player] = nil
	loadingSignals[player] = nil
end

return PlayerDataService
