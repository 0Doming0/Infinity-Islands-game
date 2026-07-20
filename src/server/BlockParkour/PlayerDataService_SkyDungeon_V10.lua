--[[
	SkyDungeon - dados persistentes canonicos

	Pontuacao da tentativa nunca e moeda. Este registro persiste apenas recorde,
	moedas, inventario e equipamento. Registros V10 antigos sao migrados uma vez;
	TotalScore antigo nao vira saldo para evitar economias com milhoes de moedas.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local LEGACY_MVP_DATASTORE_NAME = "BlockParkour_PlayerData_v1"
local SCHEMA_VERSION = 4
local SCORE_SCALE_VERSION = 3
local STARTER_SWORD_ID = "ClassicSword"
local LOAD_RETRIES = 4
local SAVE_RETRIES = 4
local RETRY_DELAY_SECONDS = 1.5

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local legacyMvpStore = DataStoreService:GetDataStore(LEGACY_MVP_DATASTORE_NAME)
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
		Coins = 0,
		BestScore = 0,
		OwnedSwords = {
			[STARTER_SWORD_ID] = true,
		},
		EquippedSword = STARTER_SWORD_ID,
		Inventory = {},
		LegacyMVPMigrated = false,
		TutorialStage = 1,
		TutorialCompleted = false,
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

local function sanitizeInventory(raw)
	local inventory = {}
	if type(raw) ~= "table" then
		return inventory
	end
	for itemId, amount in pairs(raw) do
		local cleanAmount = math.floor(tonumber(amount) or 0)
		if type(itemId) == "string" and itemId ~= "" and cleanAmount > 0 then
			inventory[itemId] = math.min(cleanAmount, 9999)
		end
	end
	return inventory
end

local function migrateBestScore(raw, sourceVersion)
	local previous = math.max(0, math.floor(tonumber(raw.BestScore) or 0))
	if sourceVersion >= SCORE_SCALE_VERSION then
		return previous
	end
	if previous == 0 then
		return 0
	end
	-- A escala V10 concedia pontos a cada segundo e pela altura inteira.
	-- A divisao preserva parte do recorde sem manter valores multimilionarios.
	return math.max(1, math.floor(previous / math.max(1, MVPConfig.Progression.LegacyScoreDivisor)))
end

local function sanitize(raw)
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end

	local sourceVersion = math.floor(tonumber(raw.SchemaVersion or raw.DataVersion) or 1)
	data.Coins = math.max(0, math.floor(tonumber(raw.Coins) or 0))
	data.BestScore = migrateBestScore(raw, sourceVersion)
	data.OwnedSwords = sanitizeOwnedSwords(raw.OwnedSwords)
	data.Inventory = sanitizeInventory(raw.Inventory or raw.OwnedItems)
	data.LegacyMVPMigrated = raw.LegacyMVPMigrated == true
	-- Perfis anteriores ao tutorial que ja possuem progresso sao tratados como
	-- veteranos; contas realmente novas ainda recebem o fluxo completo.
	local hasTutorialRecord = raw.TutorialCompleted ~= nil or raw.TutorialStage ~= nil
	data.TutorialCompleted = raw.TutorialCompleted == true
		or (not hasTutorialRecord and (data.BestScore > 0 or data.Coins > 0 or next(data.Inventory) ~= nil))
	data.TutorialStage = math.clamp(math.floor(tonumber(raw.TutorialStage) or 1), 1, 5)
	if data.TutorialCompleted then
		data.TutorialStage = 5
	end

	local equipped = type(raw.EquippedSword) == "string" and raw.EquippedSword or STARTER_SWORD_ID
	if data.OwnedSwords[equipped] then
		data.EquippedSword = equipped
	end
	return data
end

local function cloneDictionary(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

local function cloneData(data)
	return {
		SchemaVersion = SCHEMA_VERSION,
		Coins = data.Coins,
		BestScore = data.BestScore,
		OwnedSwords = cloneDictionary(data.OwnedSwords),
		EquippedSword = data.EquippedSword,
		Inventory = cloneDictionary(data.Inventory),
		LegacyMVPMigrated = data.LegacyMVPMigrated == true,
		TutorialStage = data.TutorialStage,
		TutorialCompleted = data.TutorialCompleted == true,
	}
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
	local migrationDirty = success
		and type(raw) == "table"
		and math.floor(tonumber(raw.SchemaVersion) or 1) < SCHEMA_VERSION
	if success and not data.LegacyMVPMigrated then
		local legacySuccess, legacyRaw = retry("LegacyMVP " .. player.Name, 2, function()
			return legacyMvpStore:GetAsync(keyFor(player))
		end)
		if legacySuccess then
			if type(legacyRaw) == "table" then
				data.Coins = math.max(data.Coins, math.max(0, math.floor(tonumber(legacyRaw.Coins) or 0)))
				data.BestScore = math.max(data.BestScore, migrateBestScore(legacyRaw, 1))
				for itemId, amount in pairs(sanitizeInventory(legacyRaw.OwnedItems)) do
					data.Inventory[itemId] = math.max(data.Inventory[itemId] or 0, amount)
				end
			end
			data.LegacyMVPMigrated = true
			migrationDirty = true
		end
	end
	sessions[player] = {
		Data = data,
		CanSave = success,
		Dirty = migrationDirty,
		Revision = 0,
		SessionId = HttpService:GenerateGUID(false),
		Saving = false,
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

function PlayerDataService.GetCoins(player)
	local data = PlayerDataService.Get(player)
	return data and data.Coins or 0
end

function PlayerDataService.GetTutorialProgress(player)
	local data = PlayerDataService.Get(player)
	if not data then
		return 1, false
	end
	return data.TutorialStage, data.TutorialCompleted == true
end

function PlayerDataService.SetTutorialProgress(player, stage, completed)
	local session = sessions[player]
	if not session then
		return false
	end
	local nextCompleted = completed == true or session.Data.TutorialCompleted == true
	local nextStage = math.clamp(math.floor(tonumber(stage) or session.Data.TutorialStage or 1), 1, 5)
	if nextCompleted then
		nextStage = 5
	end
	if
		nextStage ~= session.Data.TutorialStage
		or nextCompleted ~= session.Data.TutorialCompleted
	then
		session.Data.TutorialStage = nextStage
		session.Data.TutorialCompleted = nextCompleted
		markDirty(session)
	end
	return true
end

function PlayerDataService.AddCoins(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 then
		return false, session and session.Data.Coins or 0
	end
	session.Data.Coins += clean
	markDirty(session)
	return true, session.Data.Coins
end

function PlayerDataService.TrySpendCoins(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 or session.Data.Coins < clean then
		return false, session and session.Data.Coins or 0
	end
	session.Data.Coins -= clean
	markDirty(session)
	return true, session.Data.Coins
end

function PlayerDataService.RemoveCoinsPercent(player, percent)
	local session = sessions[player]
	if not session then
		return 0, 0
	end
	local cleanPercent = math.clamp(tonumber(percent) or 0, 0, 1)
	local lost = cleanPercent > 0 and math.ceil(session.Data.Coins * cleanPercent) or 0
	if lost > 0 then
		session.Data.Coins -= lost
		markDirty(session)
	end
	return lost, session.Data.Coins
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

function PlayerDataService.GetItemAmount(player, itemId)
	local data = PlayerDataService.Get(player)
	return data and data.Inventory[itemId] or 0
end

function PlayerDataService.GetInventory(player)
	local data = PlayerDataService.Get(player)
	return data and cloneDictionary(data.Inventory) or {}
end

function PlayerDataService.AddItem(player, itemId, amount, maximumStack)
	local session = sessions[player]
	local clean = math.max(1, math.floor(tonumber(amount) or 1))
	if not session or type(itemId) ~= "string" or itemId == "" then
		return false, 0
	end
	local current = session.Data.Inventory[itemId] or 0
	local maximum = math.max(1, math.floor(tonumber(maximumStack) or 9999))
	if current >= maximum then
		return false, current
	end
	local nextAmount = math.min(maximum, current + clean)
	session.Data.Inventory[itemId] = nextAmount
	markDirty(session)
	return true, nextAmount
end

function PlayerDataService.RemoveItem(player, itemId, amount)
	local session = sessions[player]
	local clean = math.max(1, math.floor(tonumber(amount) or 1))
	if not session or type(itemId) ~= "string" then
		return false, 0
	end
	local current = session.Data.Inventory[itemId] or 0
	if current < clean then
		return false, current
	end
	local nextAmount = current - clean
	if nextAmount == 0 then
		session.Data.Inventory[itemId] = nil
	else
		session.Data.Inventory[itemId] = nextAmount
	end
	markDirty(session)
	return true, nextAmount
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
	if not session or not session.CanSave then
		return session == nil
	end
	if session.Saving then
		if not force then
			return false
		end
		local deadline = os.clock() + 20
		repeat
			task.wait(0.05)
			session = sessions[player]
		until not session or not session.Saving or os.clock() >= deadline
		if not session then
			return true
		end
		if session.Saving then
			return false
		end
	end
	if not force and not session.Dirty then
		return true
	end

	session.Saving = true
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
			snapshot.TutorialCompleted = snapshot.TutorialCompleted or previousData.TutorialCompleted
			snapshot.TutorialStage = snapshot.TutorialCompleted
				and 5
				or math.max(snapshot.TutorialStage, previousData.TutorialStage)
			if not snapshot.OwnedSwords[snapshot.EquippedSword] then
				snapshot.EquippedSword = STARTER_SWORD_ID
			end
			return snapshot
		end)
	end)
	session.Saving = false
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
