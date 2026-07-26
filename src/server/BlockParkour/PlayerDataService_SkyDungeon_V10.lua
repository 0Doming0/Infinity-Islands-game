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
local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local LEGACY_MVP_DATASTORE_NAME = "BlockParkour_PlayerData_v1"
local SCHEMA_VERSION = 8
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
		Stamina = 0,
		BestScore = 0,
		OwnedSwords = {
			[STARTER_SWORD_ID] = true,
		},
		EquippedSword = STARTER_SWORD_ID,
		OwnedRelics = {},
		EquippedRelic = nil,
		OwnedCompanions = {},
		EquippedCompanions = {},
		Inventory = {},
		LegacyMVPMigrated = false,
		TutorialStage = 1,
		TutorialCompleted = false,
		DailyLastClaimDay = 0,
		DailyStreak = 0,
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

local function sanitizeOwnedRelics(raw)
	local owned = {}
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

local function normalizeCompanionDisplayName(raw, fallback)
	local defaultName = type(fallback) == "string" and fallback ~= "" and fallback or "Companheiro"
	local value = type(raw) == "string" and raw or defaultName
	value = string.gsub(value, "%c", "")
	value = string.gsub(value, "%s+", " ")
	value = string.match(value, "^%s*(.-)%s*$") or ""

	local length = utf8.len(value)
	if not length or length == 0 then
		value = defaultName
		length = utf8.len(value) or #value
	end
	if length > CompanionCatalog.MaxDisplayNameLength then
		local boundary = utf8.offset(value, CompanionCatalog.MaxDisplayNameLength + 1)
		if boundary then
			value = string.sub(value, 1, boundary - 1)
		end
	end
	return value
end

local function sanitizeOwnedCompanions(raw)
	local owned = {}
	if type(raw) ~= "table" then
		return owned
	end
	for monsterId, record in pairs(raw) do
		if type(monsterId) == "string" and monsterId ~= "" and type(record) == "table" then
			local level = math.clamp(
				math.floor(tonumber(record.Level) or 1),
				1,
				CompanionCatalog.MaxLevel
			)
			local upgrades = CompanionCatalog.EmptyUpgrades()
			local remaining = level - 1
			for _, statName in ipairs(CompanionCatalog.UpgradeOrder) do
				local definition = CompanionCatalog.Upgrades[statName]
				local requested = math.clamp(
					math.floor(tonumber(record.Upgrades and record.Upgrades[statName]) or 0),
					0,
					definition.MaxPoints
				)
				upgrades[statName] = math.min(requested, remaining)
				remaining -= upgrades[statName]
			end
			owned[monsterId] = {
				DisplayName = normalizeCompanionDisplayName(record.DisplayName, monsterId),
				Level = level,
				XP = math.max(0, math.floor(tonumber(record.XP) or 0)),
				Kills = math.max(0, math.floor(tonumber(record.Kills) or 0)),
				Upgrades = upgrades,
			}
		end
	end
	return owned
end

local function sanitizeEquippedCompanions(raw, legacy, owned)
	local equipped = {}
	local seen = {}
	local function add(monsterId)
		if
			#equipped < CompanionCatalog.MaxEquipped
			and type(monsterId) == "string"
			and owned[monsterId]
			and not seen[monsterId]
		then
			seen[monsterId] = true
			table.insert(equipped, monsterId)
		end
	end
	if type(raw) == "table" then
		for index = 1, CompanionCatalog.MaxEquipped do
			add(raw[index])
		end
	end
	if #equipped == 0 then
		add(legacy)
	end
	return equipped
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
	data.Stamina = math.max(0, math.floor((tonumber(raw.Stamina) or 0) * 2 + 0.5) / 2)
	data.BestScore = migrateBestScore(raw, sourceVersion)
	data.OwnedSwords = sanitizeOwnedSwords(raw.OwnedSwords)
	data.OwnedRelics = sanitizeOwnedRelics(raw.OwnedRelics)
	data.OwnedCompanions = sanitizeOwnedCompanions(raw.OwnedCompanions)
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
	local equippedRelic = type(raw.EquippedRelic) == "string" and raw.EquippedRelic or nil
	if equippedRelic and data.OwnedRelics[equippedRelic] then
		data.EquippedRelic = equippedRelic
	end
	data.EquippedCompanions = sanitizeEquippedCompanions(
		raw.EquippedCompanions,
		raw.EquippedCompanion,
		data.OwnedCompanions
	)
	data.DailyLastClaimDay = math.max(0, math.floor(tonumber(raw.DailyLastClaimDay) or 0))
	data.DailyStreak = math.clamp(math.floor(tonumber(raw.DailyStreak) or 0), 0, 7)
	return data
end

local function cloneDictionary(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

local function cloneCompanions(source)
	local result = {}
	for monsterId, record in pairs(source) do
		result[monsterId] = {
			DisplayName = record.DisplayName,
			Level = record.Level,
			XP = record.XP,
			Kills = record.Kills,
			Upgrades = cloneDictionary(record.Upgrades),
		}
	end
	return result
end

local function cloneData(data)
	return {
		SchemaVersion = SCHEMA_VERSION,
		Coins = data.Coins,
		Stamina = data.Stamina,
		BestScore = data.BestScore,
		OwnedSwords = cloneDictionary(data.OwnedSwords),
		EquippedSword = data.EquippedSword,
		OwnedRelics = cloneDictionary(data.OwnedRelics),
		EquippedRelic = data.EquippedRelic,
		OwnedCompanions = cloneCompanions(data.OwnedCompanions),
		EquippedCompanions = table.clone(data.EquippedCompanions),
		Inventory = cloneDictionary(data.Inventory),
		LegacyMVPMigrated = data.LegacyMVPMigrated == true,
		TutorialStage = data.TutorialStage,
		TutorialCompleted = data.TutorialCompleted == true,
		DailyLastClaimDay = data.DailyLastClaimDay,
		DailyStreak = data.DailyStreak,
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
		DiscardedCompanions = {},
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

function PlayerDataService.GetStamina(player)
	local data = PlayerDataService.Get(player)
	return data and data.Stamina or 0
end

function PlayerDataService.AddStamina(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor((tonumber(amount) or 0) * 2 + 0.5) / 2)
	if not session or clean <= 0 then
		return false, session and session.Data.Stamina or 0
	end
	session.Data.Stamina += clean
	markDirty(session)
	return true, session.Data.Stamina
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

function PlayerDataService.HasRelic(player, relicId)
	local data = PlayerDataService.Get(player)
	return data ~= nil and data.OwnedRelics[relicId] == true
end

function PlayerDataService.GrantRelic(player, relicId)
	local session = sessions[player]
	if not session or type(relicId) ~= "string" or relicId == "" then
		return false
	end
	if session.Data.OwnedRelics[relicId] then
		return true
	end
	session.Data.OwnedRelics[relicId] = true
	markDirty(session)
	return true
end

function PlayerDataService.SetEquippedRelic(player, relicId)
	local session = sessions[player]
	if not session or session.Data.OwnedRelics[relicId] ~= true then
		return false
	end
	session.Data.EquippedRelic = relicId
	markDirty(session)
	return true
end

function PlayerDataService.GetCompanions(player)
	local data = PlayerDataService.Get(player)
	return data and cloneCompanions(data.OwnedCompanions) or {},
		data and table.clone(data.EquippedCompanions) or {}
end

function PlayerDataService.UnlockCompanion(player, monsterId, displayName)
	local session = sessions[player]
	if not session or type(monsterId) ~= "string" or monsterId == "" then
		return false, false
	end
	if session.Data.OwnedCompanions[monsterId] then
		return true, false
	end
	session.Data.OwnedCompanions[monsterId] = {
		DisplayName = normalizeCompanionDisplayName(displayName, monsterId),
		Level = 1,
		XP = 0,
		Kills = 0,
		Upgrades = CompanionCatalog.EmptyUpgrades(),
	}
	if #session.Data.EquippedCompanions == 0 then
		table.insert(session.Data.EquippedCompanions, monsterId)
	end
	markDirty(session)
	return true, true
end

function PlayerDataService.SetCompanionEquipped(player, monsterId, shouldEquip)
	local session = sessions[player]
	if
		not session
		or type(monsterId) ~= "string"
		or not session.Data.OwnedCompanions[monsterId]
	then
		return false, "Companheiro inválido."
	end
	local equippedIndex = table.find(session.Data.EquippedCompanions, monsterId)
	if shouldEquip == false then
		if equippedIndex then
			table.remove(session.Data.EquippedCompanions, equippedIndex)
			markDirty(session)
		end
		return true
	end
	if equippedIndex then
		return true
	end
	if #session.Data.EquippedCompanions >= CompanionCatalog.MaxEquipped then
		return false, string.format("Você já equipou %d companheiros.", CompanionCatalog.MaxEquipped)
	end
	table.insert(session.Data.EquippedCompanions, monsterId)
	markDirty(session)
	return true
end

function PlayerDataService.RenameCompanion(player, monsterId, displayName)
	local session = sessions[player]
	local record = session and session.Data.OwnedCompanions[monsterId]
	if not record or type(displayName) ~= "string" then
		return false, "Companheiro inválido."
	end
	local cleanName = normalizeCompanionDisplayName(displayName, record.DisplayName)
	if cleanName == record.DisplayName then
		return true
	end
	record.DisplayName = cleanName
	markDirty(session)
	return true
end

function PlayerDataService.DiscardCompanion(player, monsterId)
	local session = sessions[player]
	if
		not session
		or type(monsterId) ~= "string"
		or not session.Data.OwnedCompanions[monsterId]
	then
		return false, "Companheiro inválido."
	end

	for index = #session.Data.EquippedCompanions, 1, -1 do
		if session.Data.EquippedCompanions[index] == monsterId then
			table.remove(session.Data.EquippedCompanions, index)
		end
	end
	session.Data.OwnedCompanions[monsterId] = nil
	markDirty(session)
	session.DiscardedCompanions[monsterId] = session.Revision
	return true
end

-- Compatibilidade com consumidores antigos: substitui toda a equipe por um mob.
function PlayerDataService.SetEquippedCompanion(player, monsterId)
	local session = sessions[player]
	if not session then
		return false
	end
	if monsterId == nil or monsterId == "" then
		table.clear(session.Data.EquippedCompanions)
		markDirty(session)
		return true
	end
	if type(monsterId) ~= "string" or not session.Data.OwnedCompanions[monsterId] then
		return false
	end
	if #session.Data.EquippedCompanions ~= 1 or session.Data.EquippedCompanions[1] ~= monsterId then
		session.Data.EquippedCompanions = { monsterId }
		markDirty(session)
	end
	return true
end

local function grantCompanionXP(record, amount)
	record.Kills += 1
	record.XP += amount
	local leveled = false
	while record.Level < CompanionCatalog.MaxLevel do
		local required = CompanionCatalog.GetXPRequired(record.Level)
		if record.XP < required then
			break
		end
		record.XP -= required
		record.Level += 1
		leveled = true
	end
	if record.Level >= CompanionCatalog.MaxLevel then
		record.XP = 0
	end
	return leveled
end

function PlayerDataService.AddEquippedCompanionsXP(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 then
		return {}
	end
	local results = {}
	for _, monsterId in ipairs(session.Data.EquippedCompanions) do
		local record = session.Data.OwnedCompanions[monsterId]
		if record then
			local leveled = grantCompanionXP(record, clean)
			table.insert(results, {
				MonsterId = monsterId,
				Record = {
					DisplayName = record.DisplayName,
					Level = record.Level,
					XP = record.XP,
					Kills = record.Kills,
					Upgrades = cloneDictionary(record.Upgrades),
				},
				Leveled = leveled,
			})
		end
	end
	if #results > 0 then
		markDirty(session)
	end
	return results
end

function PlayerDataService.AddEquippedCompanionXP(player, amount)
	local result = PlayerDataService.AddEquippedCompanionsXP(player, amount)[1]
	return result ~= nil,
		result and result.MonsterId or nil,
		result and result.Record or nil,
		result and result.Leveled or false
end

function PlayerDataService.UpgradeCompanionStat(player, monsterId, statName)
	local session = sessions[player]
	local record = session and session.Data.OwnedCompanions[monsterId]
	local definition = CompanionCatalog.Upgrades[statName]
	if not record or not definition then
		return false, "Companheiro ou atributo inválido."
	end
	record.Upgrades = record.Upgrades or CompanionCatalog.EmptyUpgrades()
	local spent = CompanionCatalog.SpentPoints(record.Upgrades)
	local available = math.max(0, record.Level - 1 - spent)
	if available <= 0 then
		return false, "Este companheiro não possui pontos disponíveis."
	end
	local current = math.max(0, math.floor(tonumber(record.Upgrades[statName]) or 0))
	if current >= definition.MaxPoints then
		return false, "Este atributo já atingiu o limite."
	end
	record.Upgrades[statName] = current + 1
	markDirty(session)
	return true
end

function PlayerDataService.GetDailyRewardState(player)
	local data = PlayerDataService.Get(player)
	if not data then
		return 0, 0
	end
	return data.DailyLastClaimDay, data.DailyStreak
end

function PlayerDataService.SetDailyRewardState(player, dayIndex, streak)
	local session = sessions[player]
	local cleanDay = math.max(0, math.floor(tonumber(dayIndex) or 0))
	local cleanStreak = math.clamp(math.floor(tonumber(streak) or 0), 0, 7)
	if not session or cleanDay < session.Data.DailyLastClaimDay then
		return false
	end
	session.Data.DailyLastClaimDay = cleanDay
	session.Data.DailyStreak = cleanStreak
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
	local snapshotDiscardedCompanions = cloneDictionary(session.DiscardedCompanions)
	local success = retry("Save " .. player.Name, SAVE_RETRIES, function()
		return store:UpdateAsync(keyFor(player), function(previous)
			local previousData = sanitize(previous)
			for swordId, owned in pairs(previousData.OwnedSwords) do
				if owned then
					snapshot.OwnedSwords[swordId] = true
				end
			end
			for relicId, owned in pairs(previousData.OwnedRelics) do
				if owned then
					snapshot.OwnedRelics[relicId] = true
				end
			end
			for monsterId, previousRecord in pairs(previousData.OwnedCompanions) do
				if not snapshotDiscardedCompanions[monsterId] then
					local currentRecord = snapshot.OwnedCompanions[monsterId]
					if not currentRecord then
						snapshot.OwnedCompanions[monsterId] = previousRecord
					elseif previousRecord.Level > currentRecord.Level then
						snapshot.OwnedCompanions[monsterId] = previousRecord
					elseif previousRecord.Level == currentRecord.Level then
						currentRecord.XP = math.max(currentRecord.XP, previousRecord.XP)
						currentRecord.Kills = math.max(currentRecord.Kills, previousRecord.Kills)
						if
							CompanionCatalog.SpentPoints(previousRecord.Upgrades)
							> CompanionCatalog.SpentPoints(currentRecord.Upgrades)
						then
							currentRecord.Upgrades = cloneDictionary(previousRecord.Upgrades)
						end
					end
				end
			end
			snapshot.BestScore = math.max(snapshot.BestScore, previousData.BestScore)
			snapshot.Stamina = math.max(snapshot.Stamina, previousData.Stamina)
			snapshot.TutorialCompleted = snapshot.TutorialCompleted or previousData.TutorialCompleted
			snapshot.TutorialStage = snapshot.TutorialCompleted
				and 5
				or math.max(snapshot.TutorialStage, previousData.TutorialStage)
			if not snapshot.OwnedSwords[snapshot.EquippedSword] then
				snapshot.EquippedSword = STARTER_SWORD_ID
			end
			if snapshot.EquippedRelic and not snapshot.OwnedRelics[snapshot.EquippedRelic] then
				snapshot.EquippedRelic = nil
			end
			snapshot.EquippedCompanions = sanitizeEquippedCompanions(
				snapshot.EquippedCompanions,
				nil,
				snapshot.OwnedCompanions
			)
			if previousData.DailyLastClaimDay > snapshot.DailyLastClaimDay then
				snapshot.DailyLastClaimDay = previousData.DailyLastClaimDay
				snapshot.DailyStreak = previousData.DailyStreak
			elseif previousData.DailyLastClaimDay == snapshot.DailyLastClaimDay then
				snapshot.DailyStreak = math.max(snapshot.DailyStreak, previousData.DailyStreak)
			end
			return snapshot
		end)
	end)
	session.Saving = false
	if success then
		for monsterId, discardedRevision in pairs(snapshotDiscardedCompanions) do
			if session.DiscardedCompanions[monsterId] == discardedRevision then
				session.DiscardedCompanions[monsterId] = nil
			end
		end
	end
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
