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
local ItemCatalog = require(ReplicatedStorage:WaitForChild("ItemCatalog"))

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local LEGACY_MVP_DATASTORE_NAME = "BlockParkour_PlayerData_v1"
local SCHEMA_VERSION = 13
local SCORE_SCALE_VERSION = 3
local STARTER_SWORD_ID = "ClassicSword"
local LOAD_RETRIES = 4
local SAVE_RETRIES = 4
local RETRY_DELAY_SECONDS = 1.5
local MAX_PROCESSED_PURCHASE_IDS = 500

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
		OwnedWings = {},
		EquippedWings = nil,
		OwnedAbilities = {},
		EquippedAbility = nil,
		OwnedRelics = {},
		EquippedRelic = nil,
		OwnedCompanions = {},
		EquippedCompanions = {},
		CompanionEquipSlots = CompanionCatalog.InitialEquippedSlots,
		Inventory = {},
		LegacyMVPMigrated = false,
		TutorialStage = 1,
		TutorialCompleted = false,
		AnalyticsOnboardingCompleted = false,
		DailyLastClaimDay = 0,
		DailyStreak = 0,
		Tickets = {
			LuckyWheelSpin = 0,
		},
		Progression = {
			Phases = {
				Phase01 = { Completions = 0, BossDefeated = false, BestTime = nil },
				Phase02 = { Completions = 0, BossDefeated = false, BestTime = nil },
			},
		},
		Roulette = {
			TotalSpins = 0,
			LastSpinAt = 0,
		},
		DungeonRewards = {
			ProcessedGrantIds = {},
		},
		DungeonResults = {
			ProcessedResultIds = {},
			LastResult = nil,
		},
		Monetization = {
			TreasureBoostUntil = 0,
			EliteBoostUntil = 0,
			PendingReviveLostCoins = 0,
			PendingReviveSerial = 0,
			PendingSpinAgainSource = "",
			PendingSpinAgainLevel = 0,
			ProcessedPurchaseIds = {},
		},
	}
end

local function sanitizeProcessedPurchaseIds(raw)
	local entries = {}
	if type(raw) == "table" then
		for purchaseId, processedAt in pairs(raw) do
			if type(purchaseId) == "string" and purchaseId ~= "" then
				table.insert(entries, {
					Id = purchaseId,
					ProcessedAt = math.max(1, math.floor(tonumber(processedAt) or 1)),
				})
			end
		end
	end
	table.sort(entries, function(left, right)
		if left.ProcessedAt == right.ProcessedAt then
			return left.Id > right.Id
		end
		return left.ProcessedAt > right.ProcessedAt
	end)
	local result = {}
	for index = 1, math.min(#entries, MAX_PROCESSED_PURCHASE_IDS) do
		local entry = entries[index]
		result[entry.Id] = entry.ProcessedAt
	end
	return result
end


local function sanitizeDungeonRewardGrantIds(raw)
	local entries = {}
	if type(raw) == "table" then
		for grantId, processedAt in pairs(raw) do
			if type(grantId) == "string" and grantId ~= "" then
				table.insert(entries, {
					Id = grantId,
					ProcessedAt = math.max(1, math.floor(tonumber(processedAt) or 1)),
				})
			end
		end
	end
	table.sort(entries, function(left, right)
		if left.ProcessedAt == right.ProcessedAt then
			return left.Id > right.Id
		end
		return left.ProcessedAt > right.ProcessedAt
	end)
	local result = {}
	for index = 1, math.min(#entries, 500) do
		local entry = entries[index]
		result[entry.Id] = entry.ProcessedAt
	end
	return result
end


local function cloneDungeonResultRecord(source)
	if type(source) ~= "table" then
		return nil
	end
	return {
		ResultId = tostring(source.ResultId or ""),
		SessionId = tostring(source.SessionId or ""),
		PhaseId = tostring(source.PhaseId or ""),
		Result = tostring(source.Result or "Defeat"),
		Eligible = source.Eligible == true,
		RewardCoins = math.max(0, math.floor(tonumber(source.RewardCoins) or 0)),
		ElapsedSeconds = math.max(0, tonumber(source.ElapsedSeconds) or 0),
		ProcessedAt = math.max(1, math.floor(tonumber(source.ProcessedAt) or 1)),
		CompletedAt = math.max(1, math.floor(tonumber(source.CompletedAt) or source.ProcessedAt or 1)),
		Balance = math.max(0, math.floor(tonumber(source.Balance) or 0)),
		Completions = math.max(0, math.floor(tonumber(source.Completions) or 0)),
		BestTime = tonumber(source.BestTime) and math.max(0.01, tonumber(source.BestTime)) or nil,
		CommitToken = tostring(source.CommitToken or ""),
	}
end

local function sanitizeDungeonResults(raw)
	local records = {}
	local processed = type(raw) == "table" and raw.ProcessedResultIds or nil
	if type(processed) == "table" then
		for resultId, source in pairs(processed) do
			if type(resultId) == "string" and resultId ~= "" then
				local record
				if type(source) == "table" then
					record = cloneDungeonResultRecord(source)
				else
					record = cloneDungeonResultRecord({
						ResultId = resultId,
						ProcessedAt = source,
					})
				end
				if record then
					record.ResultId = resultId
					table.insert(records, record)
				end
			end
		end
	end
	table.sort(records, function(left, right)
		if left.ProcessedAt == right.ProcessedAt then
			return left.ResultId > right.ResultId
		end
		return left.ProcessedAt > right.ProcessedAt
	end)
	local result = {
		ProcessedResultIds = {},
		LastResult = nil,
	}
	for index = 1, math.min(#records, 100) do
		local record = records[index]
		result.ProcessedResultIds[record.ResultId] = record
	end
	local requestedLast = type(raw) == "table" and cloneDungeonResultRecord(raw.LastResult) or nil
	if requestedLast and result.ProcessedResultIds[requestedLast.ResultId] then
		result.LastResult = result.ProcessedResultIds[requestedLast.ResultId]
	elseif records[1] and result.ProcessedResultIds[records[1].ResultId] then
		result.LastResult = result.ProcessedResultIds[records[1].ResultId]
	end
	return result
end

local function cloneDungeonResults(source)
	local result = {
		ProcessedResultIds = {},
		LastResult = nil,
	}
	for resultId, record in pairs(source.ProcessedResultIds or {}) do
		result.ProcessedResultIds[resultId] = cloneDungeonResultRecord(record)
	end
	result.LastResult = cloneDungeonResultRecord(source.LastResult)
	return result
end


local function sanitizeDungeonRewardGrantIds(raw)
	local entries = {}
	if type(raw) == "table" then
		for grantId, processedAt in pairs(raw) do
			if type(grantId) == "string" and grantId ~= "" then
				table.insert(entries, {
					Id = grantId,
					ProcessedAt = math.max(1, math.floor(tonumber(processedAt) or 1)),
				})
			end
		end
	end
	table.sort(entries, function(left, right)
		if left.ProcessedAt == right.ProcessedAt then
			return left.Id > right.Id
		end
		return left.ProcessedAt > right.ProcessedAt
	end)
	local result = {}
	for index = 1, math.min(#entries, 500) do
		local entry = entries[index]
		result[entry.Id] = entry.ProcessedAt
	end
	return result
end


local function cloneDungeonResultRecord(source)
	if type(source) ~= "table" then
		return nil
	end
	return {
		ResultId = tostring(source.ResultId or ""),
		SessionId = tostring(source.SessionId or ""),
		PhaseId = tostring(source.PhaseId or ""),
		Result = tostring(source.Result or "Defeat"),
		Eligible = source.Eligible == true,
		RewardCoins = math.max(0, math.floor(tonumber(source.RewardCoins) or 0)),
		ElapsedSeconds = math.max(0, tonumber(source.ElapsedSeconds) or 0),
		ProcessedAt = math.max(1, math.floor(tonumber(source.ProcessedAt) or 1)),
		CompletedAt = math.max(1, math.floor(tonumber(source.CompletedAt) or source.ProcessedAt or 1)),
		Balance = math.max(0, math.floor(tonumber(source.Balance) or 0)),
		Completions = math.max(0, math.floor(tonumber(source.Completions) or 0)),
		BestTime = tonumber(source.BestTime) and math.max(0.01, tonumber(source.BestTime)) or nil,
		CommitToken = tostring(source.CommitToken or ""),
	}
end

local function sanitizeDungeonResults(raw)
	local records = {}
	local processed = type(raw) == "table" and raw.ProcessedResultIds or nil
	if type(processed) == "table" then
		for resultId, source in pairs(processed) do
			if type(resultId) == "string" and resultId ~= "" then
				local record
				if type(source) == "table" then
					record = cloneDungeonResultRecord(source)
				else
					record = cloneDungeonResultRecord({
						ResultId = resultId,
						ProcessedAt = source,
					})
				end
				if record then
					record.ResultId = resultId
					table.insert(records, record)
				end
			end
		end
	end
	table.sort(records, function(left, right)
		if left.ProcessedAt == right.ProcessedAt then
			return left.ResultId > right.ResultId
		end
		return left.ProcessedAt > right.ProcessedAt
	end)
	local result = {
		ProcessedResultIds = {},
		LastResult = nil,
	}
	for index = 1, math.min(#records, 100) do
		local record = records[index]
		result.ProcessedResultIds[record.ResultId] = record
	end
	local requestedLast = type(raw) == "table" and cloneDungeonResultRecord(raw.LastResult) or nil
	if requestedLast and result.ProcessedResultIds[requestedLast.ResultId] then
		result.LastResult = result.ProcessedResultIds[requestedLast.ResultId]
	elseif records[1] and result.ProcessedResultIds[records[1].ResultId] then
		result.LastResult = result.ProcessedResultIds[records[1].ResultId]
	end
	return result
end

local function cloneDungeonResults(source)
	local result = {
		ProcessedResultIds = {},
		LastResult = nil,
	}
	for resultId, record in pairs(source.ProcessedResultIds or {}) do
		result.ProcessedResultIds[resultId] = cloneDungeonResultRecord(record)
	end
	result.LastResult = cloneDungeonResultRecord(source.LastResult)
	return result
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

local function sanitizeOwnedSet(raw)
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

local function sanitizeTickets(raw)
	local tickets = { LuckyWheelSpin = 0 }
	if type(raw) ~= "table" then
		return tickets
	end
	for ticketId, amount in pairs(raw) do
		if type(ticketId) == "string" and ticketId ~= "" then
			tickets[ticketId] = math.clamp(math.floor(tonumber(amount) or 0), 0, 9999)
		end
	end
	return tickets
end

local function sanitizePhaseProgress(raw)
	local result = {
		Phase01 = { Completions = 0, BossDefeated = false, BestTime = nil },
		Phase02 = { Completions = 0, BossDefeated = false, BestTime = nil },
	}
	local phases = type(raw) == "table" and raw.Phases or nil
	if type(phases) ~= "table" then
		return { Phases = result }
	end
	for phaseId, defaults in pairs(result) do
		local saved = type(phases[phaseId]) == "table" and phases[phaseId] or {}
		local bestTime = tonumber(saved.BestTime)
		defaults.Completions = math.max(0, math.floor(tonumber(saved.Completions) or 0))
		defaults.BossDefeated = saved.BossDefeated == true or defaults.Completions > 0
		defaults.BestTime = bestTime and bestTime > 0 and bestTime or nil
	end
	return { Phases = result }
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

local function companionInstanceId(savedId, speciesId, record, legacy)
	local explicit = type(record.InstanceId) == "string" and record.InstanceId or nil
	if explicit and explicit ~= "" then
		return explicit
	end
	if not legacy and type(savedId) == "string" and savedId ~= "" then
		return savedId
	end
	local safeSpecies = string.gsub(speciesId, "[^%w_%-]", "_")
	return "legacy_" .. safeSpecies
end

local function sanitizeOwnedCompanions(raw)
	local owned = {}
	local migratedIds = {}
	if type(raw) ~= "table" then
		return owned, migratedIds
	end

	local savedIds = {}
	for savedId in pairs(raw) do
		if type(savedId) == "string" and savedId ~= "" then
			table.insert(savedIds, savedId)
		end
	end
	table.sort(savedIds)

	local storedCount = 0
	for _, savedId in ipairs(savedIds) do
		if storedCount >= CompanionCatalog.MaximumStored then
			break
		end
		local record = raw[savedId]
		if type(record) == "table" then
			local speciesId = type(record.SpeciesId) == "string" and record.SpeciesId
				or type(record.MonsterId) == "string" and record.MonsterId
				or savedId
			local legacy = record.SpeciesId == nil and record.MonsterId == nil
			if not CompanionCatalog.IsSupported(speciesId) then
				continue
			end
			local instanceId = companionInstanceId(savedId, speciesId, record, legacy)
			local suffix = 2
			local baseId = instanceId
			while owned[instanceId] do
				instanceId = string.format("%s_%d", baseId, suffix)
				suffix += 1
			end
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
			owned[instanceId] = {
				InstanceId = instanceId,
				SpeciesId = speciesId,
				DisplayName = normalizeCompanionDisplayName(record.DisplayName, speciesId),
				Level = level,
				XP = math.max(0, math.floor(tonumber(record.XP) or 0)),
				Kills = math.max(0, math.floor(tonumber(record.Kills) or 0)),
				Upgrades = upgrades,
			}
			migratedIds[savedId] = instanceId
			storedCount += 1
		end
	end
	return owned, migratedIds
end

local function sanitizeEquippedCompanions(raw, legacy, owned, migratedIds, equipSlots)
	local equipped = {}
	local seen = {}
	local limit = math.clamp(
		math.floor(tonumber(equipSlots) or CompanionCatalog.InitialEquippedSlots),
		CompanionCatalog.InitialEquippedSlots,
		CompanionCatalog.MaxEquipped
	)
	local function add(instanceId)
		instanceId = migratedIds and migratedIds[instanceId] or instanceId
		if
			#equipped < limit
			and type(instanceId) == "string"
			and owned[instanceId]
			and not seen[instanceId]
		then
			seen[instanceId] = true
			table.insert(equipped, instanceId)
		end
	end
	if type(raw) == "table" then
		for index = 1, limit do
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
	data.OwnedWings = sanitizeOwnedSet(raw.OwnedWings or (raw.Inventory and raw.Inventory.Wings))
	data.OwnedAbilities = sanitizeOwnedSet(raw.OwnedAbilities or (raw.Inventory and raw.Inventory.Abilities))
	data.OwnedRelics = sanitizeOwnedRelics(raw.OwnedRelics)
	local migratedCompanionIds
	data.OwnedCompanions, migratedCompanionIds = sanitizeOwnedCompanions(raw.OwnedCompanions)
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
	data.AnalyticsOnboardingCompleted = raw.AnalyticsOnboardingCompleted == true

	local equipped = type(raw.EquippedSword) == "string" and raw.EquippedSword or STARTER_SWORD_ID
	if data.OwnedSwords[equipped] then
		data.EquippedSword = equipped
	end
	local equippedWings = type(raw.EquippedWings) == "string" and raw.EquippedWings
		or type(raw.Equipped) == "table" and raw.Equipped.Wings
	if equippedWings and data.OwnedWings[equippedWings] then
		data.EquippedWings = equippedWings
	end
	local equippedAbility = type(raw.EquippedAbility) == "string" and raw.EquippedAbility
		or type(raw.Equipped) == "table" and raw.Equipped.Ability
	if equippedAbility and data.OwnedAbilities[equippedAbility] then
		data.EquippedAbility = equippedAbility
	end
	local equippedRelic = type(raw.EquippedRelic) == "string" and raw.EquippedRelic or nil
	if equippedRelic and data.OwnedRelics[equippedRelic] then
		data.EquippedRelic = equippedRelic
	end
	local requestedEquipSlots = math.clamp(
		math.floor(tonumber(raw.CompanionEquipSlots) or CompanionCatalog.InitialEquippedSlots),
		CompanionCatalog.InitialEquippedSlots,
		CompanionCatalog.MaxEquipped
	)
	if sourceVersion < SCHEMA_VERSION and type(raw.EquippedCompanions) == "table" then
		requestedEquipSlots = math.max(requestedEquipSlots, math.min(#raw.EquippedCompanions, CompanionCatalog.MaxEquipped))
	end
	data.CompanionEquipSlots = requestedEquipSlots
	data.EquippedCompanions = sanitizeEquippedCompanions(
		raw.EquippedCompanions,
		raw.EquippedCompanion,
		data.OwnedCompanions,
		migratedCompanionIds,
		data.CompanionEquipSlots
	)
	data.DailyLastClaimDay = math.max(0, math.floor(tonumber(raw.DailyLastClaimDay) or 0))
	data.DailyStreak = math.clamp(math.floor(tonumber(raw.DailyStreak) or 0), 0, 7)
	data.Tickets = sanitizeTickets(raw.Tickets or (raw.Inventory and raw.Inventory.Tickets))
	data.Progression = sanitizePhaseProgress(raw.Progression)
	local rawRoulette = type(raw.Roulette) == "table" and raw.Roulette or {}
	data.Roulette = {
		TotalSpins = math.max(0, math.floor(tonumber(rawRoulette.TotalSpins) or 0)),
		LastSpinAt = math.max(0, math.floor(tonumber(rawRoulette.LastSpinAt) or 0)),
	}
	local rawMonetization = type(raw.Monetization) == "table" and raw.Monetization or {}
	local rawDungeonRewards = type(raw.DungeonRewards) == "table" and raw.DungeonRewards or {}
	data.DungeonRewards = {
		ProcessedGrantIds = sanitizeDungeonRewardGrantIds(rawDungeonRewards.ProcessedGrantIds),
	}
	data.DungeonResults = sanitizeDungeonResults(raw.DungeonResults)
	local rawDungeonRewards = type(raw.DungeonRewards) == "table" and raw.DungeonRewards or {}
	data.DungeonRewards = {
		ProcessedGrantIds = sanitizeDungeonRewardGrantIds(rawDungeonRewards.ProcessedGrantIds),
	}
	data.DungeonResults = sanitizeDungeonResults(raw.DungeonResults)
	data.Monetization = {
		TreasureBoostUntil = math.max(0, math.floor(tonumber(rawMonetization.TreasureBoostUntil) or 0)),
		EliteBoostUntil = math.max(0, math.floor(tonumber(rawMonetization.EliteBoostUntil) or 0)),
		PendingReviveLostCoins = math.max(
			0,
			math.floor(tonumber(rawMonetization.PendingReviveLostCoins) or 0)
		),
		PendingReviveSerial = math.max(
			0,
			math.floor(tonumber(rawMonetization.PendingReviveSerial) or 0)
		),
		PendingSpinAgainSource = (
			rawMonetization.PendingSpinAgainSource == "Boss"
				or rawMonetization.PendingSpinAgainSource == "RareChest"
		) and rawMonetization.PendingSpinAgainSource or "",
		PendingSpinAgainLevel = math.max(
			0,
			math.floor(tonumber(rawMonetization.PendingSpinAgainLevel) or 0)
		),
		ProcessedPurchaseIds = sanitizeProcessedPurchaseIds(
			rawMonetization.ProcessedPurchaseIds
		),
	}
	return data
end

local function cloneDictionary(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

local function cloneMonetization(source)
	local result = cloneDictionary(source)
	result.ProcessedPurchaseIds = cloneDictionary(source.ProcessedPurchaseIds or {})
	return result
end

local function cloneCompanions(source)
	local result = {}
	for instanceId, record in pairs(source) do
		result[instanceId] = {
			InstanceId = instanceId,
			SpeciesId = record.SpeciesId,
			DisplayName = record.DisplayName,
			Level = record.Level,
			XP = record.XP,
			Kills = record.Kills,
			Upgrades = cloneDictionary(record.Upgrades),
		}
	end
	return result
end

local function cloneProgression(source)
	local phases = {}
	for phaseId, progress in pairs(source.Phases or {}) do
		phases[phaseId] = {
			Completions = progress.Completions,
			BossDefeated = progress.BossDefeated == true,
			BestTime = progress.BestTime,
		}
	end
	return { Phases = phases }
end

local function cloneData(data)
	return {
		SchemaVersion = SCHEMA_VERSION,
		Coins = data.Coins,
		Stamina = data.Stamina,
		BestScore = data.BestScore,
		OwnedSwords = cloneDictionary(data.OwnedSwords),
		EquippedSword = data.EquippedSword,
		OwnedWings = cloneDictionary(data.OwnedWings),
		EquippedWings = data.EquippedWings,
		OwnedAbilities = cloneDictionary(data.OwnedAbilities),
		EquippedAbility = data.EquippedAbility,
		OwnedRelics = cloneDictionary(data.OwnedRelics),
		EquippedRelic = data.EquippedRelic,
		OwnedCompanions = cloneCompanions(data.OwnedCompanions),
		EquippedCompanions = table.clone(data.EquippedCompanions),
		CompanionEquipSlots = data.CompanionEquipSlots,
		Inventory = cloneDictionary(data.Inventory),
		LegacyMVPMigrated = data.LegacyMVPMigrated == true,
		TutorialStage = data.TutorialStage,
		TutorialCompleted = data.TutorialCompleted == true,
		AnalyticsOnboardingCompleted = data.AnalyticsOnboardingCompleted == true,
		DailyLastClaimDay = data.DailyLastClaimDay,
		DailyStreak = data.DailyStreak,
		Tickets = cloneDictionary(data.Tickets),
		Progression = cloneProgression(data.Progression),
		Roulette = cloneDictionary(data.Roulette),
		DungeonRewards = {
			ProcessedGrantIds = cloneDictionary(data.DungeonRewards.ProcessedGrantIds),
		},
		DungeonResults = cloneDungeonResults(data.DungeonResults),
		Monetization = cloneMonetization(data.Monetization),
	}
end

local function keyForUserId(userId)
	return string.format("Player_%d", math.max(1, math.floor(tonumber(userId) or 0)))
end

local function keyFor(player)
	return keyForUserId(player.UserId)
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

function PlayerDataService.CanSave(player)
	local session = sessions[player]
	return session ~= nil and session.CanSave == true
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

function PlayerDataService.GetAnalyticsOnboardingCompleted(player)
	local data = PlayerDataService.Get(player)
	return data and data.AnalyticsOnboardingCompleted == true or false
end

function PlayerDataService.SetAnalyticsOnboardingCompleted(player)
	local session = sessions[player]
	if not session then
		return false
	end
	if session.Data.AnalyticsOnboardingCompleted ~= true then
		session.Data.AnalyticsOnboardingCompleted = true
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

function PlayerDataService.HasWings(player, wingId)
	local data = PlayerDataService.Get(player)
	return data ~= nil and data.OwnedWings[wingId] == true
end

function PlayerDataService.GrantWings(player, wingId)
	local session = sessions[player]
	if not session or type(wingId) ~= "string" or wingId == "" then
		return false
	end
	if not session.Data.OwnedWings[wingId] then
		session.Data.OwnedWings[wingId] = true
		markDirty(session)
	end
	return true
end

function PlayerDataService.SetEquippedWings(player, wingId)
	local session = sessions[player]
	if not session then
		return false
	end
	if wingId == nil or wingId == "" then
		session.Data.EquippedWings = nil
		markDirty(session)
		return true
	end
	if session.Data.OwnedWings[wingId] ~= true then
		return false
	end
	session.Data.EquippedWings = wingId
	markDirty(session)
	return true
end

function PlayerDataService.HasAbility(player, abilityId)
	local data = PlayerDataService.Get(player)
	return data ~= nil and data.OwnedAbilities[abilityId] == true
end

function PlayerDataService.GrantAbility(player, abilityId)
	local session = sessions[player]
	if not session or type(abilityId) ~= "string" or abilityId == "" then
		return false
	end
	if not session.Data.OwnedAbilities[abilityId] then
		session.Data.OwnedAbilities[abilityId] = true
		markDirty(session)
	end
	return true
end

function PlayerDataService.SetEquippedAbility(player, abilityId)
	local session = sessions[player]
	if not session then
		return false
	end
	if abilityId == nil or abilityId == "" then
		session.Data.EquippedAbility = nil
		markDirty(session)
		return true
	end
	if session.Data.OwnedAbilities[abilityId] ~= true then
		return false
	end
	session.Data.EquippedAbility = abilityId
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

function PlayerDataService.GetCompanionEquipSlots(player)
	local data = PlayerDataService.Get(player)
	return data and data.CompanionEquipSlots or CompanionCatalog.InitialEquippedSlots
end

function PlayerDataService.GrantCompanionEquipSlot(player)
	local session = sessions[player]
	if not session then
		return false, CompanionCatalog.InitialEquippedSlots
	end
	local current = math.clamp(
		math.floor(tonumber(session.Data.CompanionEquipSlots) or CompanionCatalog.InitialEquippedSlots),
		CompanionCatalog.InitialEquippedSlots,
		CompanionCatalog.MaxEquipped
	)
	if current >= CompanionCatalog.MaxEquipped then
		return false, current
	end
	session.Data.CompanionEquipSlots = current + 1
	markDirty(session)
	return true, session.Data.CompanionEquipSlots
end

function PlayerDataService.UnlockCompanion(player, monsterId, displayName)
	local session = sessions[player]
	if
		not session
		or type(monsterId) ~= "string"
		or monsterId == ""
		or not CompanionCatalog.IsSupported(monsterId)
	then
		return false, false, nil
	end
	local count = 0
	for _ in pairs(session.Data.OwnedCompanions) do
		count += 1
	end
	if count >= CompanionCatalog.MaximumStored then
		return false, false, nil
	end
	local instanceId = "companion_" .. HttpService:GenerateGUID(false)
	session.Data.OwnedCompanions[instanceId] = {
		InstanceId = instanceId,
		SpeciesId = monsterId,
		DisplayName = normalizeCompanionDisplayName(displayName, monsterId),
		Level = 1,
		XP = 0,
		Kills = 0,
		Upgrades = CompanionCatalog.EmptyUpgrades(),
	}
	if
		#session.Data.EquippedCompanions == 0
		and session.Data.CompanionEquipSlots >= 1
	then
		table.insert(session.Data.EquippedCompanions, instanceId)
	end
	markDirty(session)
	return true, true, instanceId
end

function PlayerDataService.SetCompanionEquipped(player, instanceId, shouldEquip)
	local session = sessions[player]
	if
		not session
		or type(instanceId) ~= "string"
		or not session.Data.OwnedCompanions[instanceId]
	then
		return false, "Companheiro inválido."
	end
	local equippedIndex = table.find(session.Data.EquippedCompanions, instanceId)
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
	if #session.Data.EquippedCompanions >= session.Data.CompanionEquipSlots then
		return false, string.format(
			"Você possui %d slot(s) de companheiro.",
			session.Data.CompanionEquipSlots
		)
	end
	table.insert(session.Data.EquippedCompanions, instanceId)
	markDirty(session)
	return true
end

function PlayerDataService.IsCompanionEquipped(player, instanceId)
	local data = PlayerDataService.Get(player)
	return data ~= nil and table.find(data.EquippedCompanions, instanceId) ~= nil
end

local function countCompanions(source)
	local count = 0
	for _ in pairs(source) do
		count += 1
	end
	return count
end

local function validateTradeOffer(session, instanceIds)
	local seen = {}
	local records = {}
	if type(instanceIds) ~= "table" or #instanceIds > 4 then
		return nil, "Oferta inválida."
	end
	for _, instanceId in ipairs(instanceIds) do
		if type(instanceId) ~= "string" or seen[instanceId] then
			return nil, "Oferta contém um companheiro inválido."
		end
		seen[instanceId] = true
		local record = session.Data.OwnedCompanions[instanceId]
		if not record then
			return nil, "Um companheiro da oferta não pertence mais ao jogador."
		end
		if table.find(session.Data.EquippedCompanions, instanceId) then
			return nil, "Desequipe o companheiro antes de trocá-lo."
		end
		records[instanceId] = cloneCompanions({ [instanceId] = record })[instanceId]
	end
	return records
end

function PlayerDataService.TransferCompanions(playerA, playerB, offerA, offerB)
	local sessionA = sessions[playerA]
	local sessionB = sessions[playerB]
	if not sessionA or not sessionB or playerA == playerB then
		return false, "Jogadores indisponíveis."
	end
	local recordsA, errorA = validateTradeOffer(sessionA, offerA)
	if not recordsA then
		return false, errorA
	end
	local recordsB, errorB = validateTradeOffer(sessionB, offerB)
	if not recordsB then
		return false, errorB
	end
	if
		countCompanions(sessionA.Data.OwnedCompanions) - #offerA + #offerB
			> CompanionCatalog.MaximumStored
		or countCompanions(sessionB.Data.OwnedCompanions) - #offerB + #offerA
			> CompanionCatalog.MaximumStored
	then
		return false, "Um dos inventários atingiu o limite técnico."
	end
	for instanceId in pairs(recordsA) do
		if sessionB.Data.OwnedCompanions[instanceId] then
			return false, "Identidade duplicada detectada; a troca foi cancelada."
		end
	end
	for instanceId in pairs(recordsB) do
		if sessionA.Data.OwnedCompanions[instanceId] then
			return false, "Identidade duplicada detectada; a troca foi cancelada."
		end
	end

	for instanceId in pairs(recordsA) do
		sessionA.Data.OwnedCompanions[instanceId] = nil
		sessionB.Data.OwnedCompanions[instanceId] = recordsA[instanceId]
	end
	for instanceId in pairs(recordsB) do
		sessionB.Data.OwnedCompanions[instanceId] = nil
		sessionA.Data.OwnedCompanions[instanceId] = recordsB[instanceId]
	end
	markDirty(sessionA)
	markDirty(sessionB)
	for instanceId in pairs(recordsA) do
		sessionA.DiscardedCompanions[instanceId] = sessionA.Revision
	end
	for instanceId in pairs(recordsB) do
		sessionB.DiscardedCompanions[instanceId] = sessionB.Revision
	end
	return true, nil, recordsA, recordsB
end

function PlayerDataService.ApplyTradeRecovery(player, outgoingIds, incomingRecords)
	local session = sessions[player]
	if not session or type(outgoingIds) ~= "table" or type(incomingRecords) ~= "table" then
		return false
	end
	local changed = false
	local removed = {}
	for _, instanceId in ipairs(outgoingIds) do
		if type(instanceId) == "string" and session.Data.OwnedCompanions[instanceId] then
			for equippedIndex = #session.Data.EquippedCompanions, 1, -1 do
				if session.Data.EquippedCompanions[equippedIndex] == instanceId then
					table.remove(session.Data.EquippedCompanions, equippedIndex)
				end
			end
			session.Data.OwnedCompanions[instanceId] = nil
			table.insert(removed, instanceId)
			changed = true
		end
	end
	for instanceId, record in pairs(incomingRecords) do
		if
			type(instanceId) == "string"
			and type(record) == "table"
			and CompanionCatalog.IsSupported(record.SpeciesId)
			and not session.Data.OwnedCompanions[instanceId]
		then
			if countCompanions(session.Data.OwnedCompanions) >= CompanionCatalog.MaximumStored then
				return false
			end
			local copy = cloneCompanions({ [instanceId] = record })[instanceId]
			if copy then
				session.Data.OwnedCompanions[instanceId] = copy
				changed = true
			end
		end
	end
	if changed then
		markDirty(session)
		for _, instanceId in ipairs(removed) do
			session.DiscardedCompanions[instanceId] = session.Revision
		end
	end
	return true
end

function PlayerDataService.RenameCompanion(player, instanceId, displayName)
	local session = sessions[player]
	local record = session and session.Data.OwnedCompanions[instanceId]
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

function PlayerDataService.DiscardCompanion(player, instanceId)
	local session = sessions[player]
	if
		not session
		or type(instanceId) ~= "string"
		or not session.Data.OwnedCompanions[instanceId]
	then
		return false, "Companheiro inválido."
	end

	for index = #session.Data.EquippedCompanions, 1, -1 do
		if session.Data.EquippedCompanions[index] == instanceId then
			table.remove(session.Data.EquippedCompanions, index)
		end
	end
	session.Data.OwnedCompanions[instanceId] = nil
	markDirty(session)
	session.DiscardedCompanions[instanceId] = session.Revision
	return true
end

-- Compatibilidade com consumidores antigos: substitui toda a equipe por um mob.
function PlayerDataService.SetEquippedCompanion(player, companionId)
	local session = sessions[player]
	if not session then
		return false
	end
	if companionId == nil or companionId == "" then
		table.clear(session.Data.EquippedCompanions)
		markDirty(session)
		return true
	end
	local instanceId = type(companionId) == "string" and companionId or nil
	if instanceId and not session.Data.OwnedCompanions[instanceId] then
		for candidateId, record in pairs(session.Data.OwnedCompanions) do
			if record.SpeciesId == companionId then
				instanceId = candidateId
				break
			end
		end
	end
	if not instanceId or not session.Data.OwnedCompanions[instanceId] then
		return false
	end
	if #session.Data.EquippedCompanions ~= 1 or session.Data.EquippedCompanions[1] ~= instanceId then
		session.Data.EquippedCompanions = { instanceId }
		markDirty(session)
	end
	return true
end

local function grantCompanionXP(record, amount)
	record.Kills += 1
	record.XP += amount
	local levelsGained = 0
	while record.Level < CompanionCatalog.MaxLevel do
		local required = CompanionCatalog.GetXPRequired(record.Level)
		if record.XP < required then
			break
		end
		record.XP -= required
		record.Level += 1
		levelsGained += 1
	end
	if record.Level >= CompanionCatalog.MaxLevel then
		record.XP = 0
	end
	return levelsGained
end

function PlayerDataService.AddEquippedCompanionsXP(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 then
		return {}
	end
	local results = {}
	for _, instanceId in ipairs(session.Data.EquippedCompanions) do
		local record = session.Data.OwnedCompanions[instanceId]
		if record then
			local levelsGained = grantCompanionXP(record, clean)
			table.insert(results, {
				InstanceId = instanceId,
				MonsterId = record.SpeciesId,
				LevelsGained = levelsGained,
				Record = {
					DisplayName = record.DisplayName,
					Level = record.Level,
					XP = record.XP,
					Kills = record.Kills,
					Upgrades = cloneDictionary(record.Upgrades),
				},
				Leveled = levelsGained > 0,
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
		result and result.Leveled or false,
		result and result.LevelsGained or 0
end

function PlayerDataService.UpgradeCompanionStat(player, instanceId, statName)
	local session = sessions[player]
	local record = session and session.Data.OwnedCompanions[instanceId]
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

function PlayerDataService.GetTicketAmount(player, ticketId)
	local data = PlayerDataService.Get(player)
	return data and math.max(0, math.floor(tonumber(data.Tickets[ticketId]) or 0)) or 0
end

function PlayerDataService.AddTicket(player, ticketId, amount)
	local session = sessions[player]
	local clean = math.max(1, math.floor(tonumber(amount) or 1))
	if not session or type(ticketId) ~= "string" or ticketId == "" then
		return false, 0
	end
	local nextAmount = math.min(9999, (session.Data.Tickets[ticketId] or 0) + clean)
	session.Data.Tickets[ticketId] = nextAmount
	markDirty(session)
	return true, nextAmount
end

function PlayerDataService.RemoveTicket(player, ticketId, amount)
	local session = sessions[player]
	local clean = math.max(1, math.floor(tonumber(amount) or 1))
	if not session or type(ticketId) ~= "string" then
		return false, 0
	end
	local current = session.Data.Tickets[ticketId] or 0
	if current < clean then
		return false, current
	end
	local nextAmount = current - clean
	session.Data.Tickets[ticketId] = nextAmount
	markDirty(session)
	return true, nextAmount
end

function PlayerDataService.RecordRouletteSpin(player)
	local session = sessions[player]
	if not session then
		return false
	end
	session.Data.Roulette.TotalSpins += 1
	session.Data.Roulette.LastSpinAt = os.time()
	markDirty(session)
	return true
end

function PlayerDataService.GetPhaseProgress(player, phaseId)
	local data = PlayerDataService.Get(player)
	local progress = data and data.Progression.Phases[phaseId]
	return progress and {
		Completions = progress.Completions,
		BossDefeated = progress.BossDefeated,
		BestTime = progress.BestTime,
	} or nil
end

function PlayerDataService.RecordPhaseCompletion(player, phaseId, elapsedSeconds)
	local session = sessions[player]
	local progress = session and session.Data.Progression.Phases[phaseId]
	if not progress then
		return false
	end
	local elapsed = math.max(0.01, tonumber(elapsedSeconds) or math.huge)
	progress.Completions += 1
	progress.BossDefeated = true
	if elapsed < math.huge and (not progress.BestTime or elapsed < progress.BestTime) then
		progress.BestTime = elapsed
	end
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

function PlayerDataService.GetMonetizationState(player)
	local data = PlayerDataService.Get(player)
	return data and cloneMonetization(data.Monetization) or {
		TreasureBoostUntil = 0,
		EliteBoostUntil = 0,
		PendingReviveLostCoins = 0,
		PendingReviveSerial = 0,
		PendingSpinAgainSource = "",
		PendingSpinAgainLevel = 0,
		ProcessedPurchaseIds = {},
	}
end

function PlayerDataService.HasProcessedPurchase(player, purchaseId)
	local data = PlayerDataService.Get(player)
	local cleanId = tostring(purchaseId or "")
	return data ~= nil
		and cleanId ~= ""
		and type(data.Monetization.ProcessedPurchaseIds) == "table"
		and data.Monetization.ProcessedPurchaseIds[cleanId] ~= nil
end

function PlayerDataService.MarkProcessedPurchase(player, purchaseId)
	local session = sessions[player]
	local cleanId = tostring(purchaseId or "")
	if not session or cleanId == "" then
		return false
	end
	local processed = session.Data.Monetization.ProcessedPurchaseIds
	if processed[cleanId] == nil then
		processed[cleanId] = os.time()
		session.Data.Monetization.ProcessedPurchaseIds =
			sanitizeProcessedPurchaseIds(processed)
		markDirty(session)
	end
	return true
end

function PlayerDataService.SetPendingRevivePurchase(player, lostCoins, serial)
	local session = sessions[player]
	if not session then
		return false
	end
	session.Data.Monetization.PendingReviveLostCoins =
		math.max(0, math.floor(tonumber(lostCoins) or 0))
	session.Data.Monetization.PendingReviveSerial =
		math.max(0, math.floor(tonumber(serial) or 0))
	markDirty(session)
	return true
end

function PlayerDataService.GetPendingRevivePurchase(player)
	local data = PlayerDataService.Get(player)
	if not data then
		return 0, 0
	end
	return math.max(
		0,
		math.floor(tonumber(data.Monetization.PendingReviveLostCoins) or 0)
	), math.max(
		0,
		math.floor(tonumber(data.Monetization.PendingReviveSerial) or 0)
	)
end

function PlayerDataService.ClearPendingRevivePurchase(player)
	local session = sessions[player]
	if not session then
		return false
	end
	if
		session.Data.Monetization.PendingReviveLostCoins ~= 0
		or session.Data.Monetization.PendingReviveSerial ~= 0
	then
		session.Data.Monetization.PendingReviveLostCoins = 0
		session.Data.Monetization.PendingReviveSerial = 0
		markDirty(session)
	end
	return true
end

function PlayerDataService.SetPendingSpinAgainPurchase(player, sourceId, level)
	local session = sessions[player]
	if
		not session
		or (sourceId ~= "Boss" and sourceId ~= "RareChest")
	then
		return false
	end
	session.Data.Monetization.PendingSpinAgainSource = sourceId
	session.Data.Monetization.PendingSpinAgainLevel =
		math.max(1, math.floor(tonumber(level) or 1))
	markDirty(session)
	return true
end

function PlayerDataService.GetPendingSpinAgainPurchase(player)
	local data = PlayerDataService.Get(player)
	if not data then
		return "", 0
	end
	local sourceId = data.Monetization.PendingSpinAgainSource
	if sourceId ~= "Boss" and sourceId ~= "RareChest" then
		return "", 0
	end
	return sourceId, math.max(
		1,
		math.floor(tonumber(data.Monetization.PendingSpinAgainLevel) or 1)
	)
end

function PlayerDataService.ClearPendingSpinAgainPurchase(player)
	local session = sessions[player]
	if not session then
		return false
	end
	if
		session.Data.Monetization.PendingSpinAgainSource ~= ""
		or session.Data.Monetization.PendingSpinAgainLevel ~= 0
	then
		session.Data.Monetization.PendingSpinAgainSource = ""
		session.Data.Monetization.PendingSpinAgainLevel = 0
		markDirty(session)
	end
	return true
end

function PlayerDataService.ExtendMonetizationBoost(player, boostName, durationSeconds)
	local session = sessions[player]
	if not session or (boostName ~= "Treasure" and boostName ~= "Elite") then
		return false, 0
	end
	local key = boostName .. "BoostUntil"
	local current = math.max(os.time(), tonumber(session.Data.Monetization[key]) or 0)
	local nextExpiration = current + math.max(1, math.floor(tonumber(durationSeconds) or 1))
	session.Data.Monetization[key] = nextExpiration
	markDirty(session)
	return true, nextExpiration
end


function PlayerDataService.HasDungeonGrant(player, grantId)
	local data = PlayerDataService.Get(player)
	local cleanId = tostring(grantId or "")
	return data ~= nil
		and cleanId ~= ""
		and data.DungeonRewards.ProcessedGrantIds[cleanId] ~= nil
end

function PlayerDataService.ApplyDungeonGrant(player, grantId, rewards)
	local session = sessions[player]
	local cleanId = tostring(grantId or "")
	if not session or cleanId == "" or type(rewards) ~= "table" or #rewards == 0 then
		return false, false, "InvalidDungeonGrant"
	end
	if session.Data.DungeonRewards.ProcessedGrantIds[cleanId] ~= nil then
		return true, true, {}
	end
	for _, reward in ipairs(rewards) do
		local kind = type(reward) == "table" and tostring(reward.Kind or "") or ""
		if kind ~= "Coins" and kind ~= "Sword" and kind ~= "Companion" and kind ~= "Item" then
			return false, false, "UnsupportedDungeonReward:" .. kind
		end
		if kind ~= "Coins" and (type(reward.Id) ~= "string" or reward.Id == "") then
			return false, false, "DungeonRewardIdMissing"
		end
		if kind == "Companion" and not CompanionCatalog.IsSupported(reward.Id) then
			return false, false, "UnsupportedCompanion:" .. tostring(reward.Id)
		end
		if kind == "Item" and not ItemCatalog.Get(reward.Id) then
			return false, false, "UnsupportedItem:" .. tostring(reward.Id)
		end
	end

	local results = {}
	local compensationCoins = 0
	for _, reward in ipairs(rewards) do
		local kind = tostring(reward.Kind)
		local amount = kind == "Coins"
			and math.max(0, math.floor(tonumber(reward.Amount) or 0))
			or math.max(1, math.floor(tonumber(reward.Amount) or 1))
		local duplicateCoins = math.max(0, math.floor(tonumber(reward.DuplicateCoins) or 0))
		if kind == "Coins" then
			session.Data.Coins += amount
			table.insert(results, { Kind = kind, Amount = amount })
		elseif kind == "Sword" then
			local duplicate = session.Data.OwnedSwords[reward.Id] == true
			if duplicate then
				compensationCoins += duplicateCoins
			else
				session.Data.OwnedSwords[reward.Id] = true
			end
			table.insert(results, {
				Kind = kind,
				Id = reward.Id,
				Amount = 1,
				Duplicate = duplicate,
				CompensationCoins = duplicate and duplicateCoins or 0,
			})
		elseif kind == "Companion" then
			local duplicate = false
			for _, record in pairs(session.Data.OwnedCompanions) do
				if record.SpeciesId == reward.Id then
					duplicate = true
					break
				end
			end
			local storedCount = 0
			for _ in pairs(session.Data.OwnedCompanions) do
				storedCount += 1
			end
			if duplicate or storedCount >= CompanionCatalog.MaximumStored then
				compensationCoins += duplicateCoins
			else
				local definition = CompanionCatalog.Get(reward.Id)
				local instanceId = "companion_" .. HttpService:GenerateGUID(false)
				session.Data.OwnedCompanions[instanceId] = {
					InstanceId = instanceId,
					SpeciesId = reward.Id,
					DisplayName = definition.DisplayName,
					Level = 1,
					XP = 0,
					Kills = 0,
					Upgrades = CompanionCatalog.EmptyUpgrades(),
				}
				if #session.Data.EquippedCompanions == 0 and session.Data.CompanionEquipSlots >= 1 then
					table.insert(session.Data.EquippedCompanions, instanceId)
				end
			end
			table.insert(results, {
				Kind = kind,
				Id = reward.Id,
				Amount = 1,
				Duplicate = duplicate or storedCount >= CompanionCatalog.MaximumStored,
				CompensationCoins = (duplicate or storedCount >= CompanionCatalog.MaximumStored) and duplicateCoins or 0,
			})
		elseif kind == "Item" then
			local definition = ItemCatalog.Get(reward.Id)
			local current = session.Data.Inventory[reward.Id] or 0
			local maximum = math.max(1, math.floor(tonumber(definition.MaximumStack) or 9999))
			local granted = math.max(0, math.min(amount, maximum - current))
			if granted > 0 then
				session.Data.Inventory[reward.Id] = current + granted
			end
			local rejected = amount - granted
			if rejected > 0 then
				compensationCoins += duplicateCoins
			end
			table.insert(results, {
				Kind = kind,
				Id = reward.Id,
				Amount = granted,
				Duplicate = rejected > 0,
				CompensationCoins = rejected > 0 and duplicateCoins or 0,
			})
		end
	end
	if compensationCoins > 0 then
		session.Data.Coins += compensationCoins
		table.insert(results, { Kind = "Coins", Amount = compensationCoins, Compensation = true })
	end
	session.Data.DungeonRewards.ProcessedGrantIds[cleanId] = os.time()
	session.Data.DungeonRewards.ProcessedGrantIds = sanitizeDungeonRewardGrantIds(
		session.Data.DungeonRewards.ProcessedGrantIds
	)
	markDirty(session)
	return true, false, results
end


local function normalizeDungeonResult(resultId, payload)
	if type(payload) ~= "table" then
		return nil, "InvalidDungeonResultPayload"
	end
	local cleanId = tostring(resultId or "")
	local sessionId = tostring(payload.SessionId or "")
	local phaseId = tostring(payload.PhaseId or "")
	local resultName = tostring(payload.Result or "Defeat")
	if cleanId == "" or sessionId == "" or phaseId == "" then
		return nil, "InvalidDungeonResultIdentity"
	end
	return {
		ResultId = cleanId,
		SessionId = sessionId,
		PhaseId = phaseId,
		Result = resultName,
		Eligible = resultName == "Victory" and payload.Eligible == true,
		RewardCoins = math.max(0, math.floor(tonumber(payload.RewardCoins) or 0)),
		ElapsedSeconds = math.max(0, tonumber(payload.ElapsedSeconds) or 0),
		CompletedAt = math.max(1, math.floor(tonumber(payload.CompletedAt) or os.time())),
	}
end

local function applyDungeonResult(data, definition, commitToken)
	local existing = data.DungeonResults.ProcessedResultIds[definition.ResultId]
	if existing then
		return existing
	end
	local progress = data.Progression.Phases[definition.PhaseId]
	if not progress then
		progress = { Completions = 0, BossDefeated = false, BestTime = nil }
		data.Progression.Phases[definition.PhaseId] = progress
	end
	local rewardCoins = definition.Eligible and definition.RewardCoins or 0
	if definition.Result == "Victory" and definition.Eligible then
		data.Coins += rewardCoins
		progress.Completions += 1
		progress.BossDefeated = true
		if definition.ElapsedSeconds > 0
			and (not progress.BestTime or definition.ElapsedSeconds < progress.BestTime)
		then
			progress.BestTime = definition.ElapsedSeconds
		end
	end
	local record = {
		ResultId = definition.ResultId,
		SessionId = definition.SessionId,
		PhaseId = definition.PhaseId,
		Result = definition.Result,
		Eligible = definition.Eligible,
		RewardCoins = rewardCoins,
		ElapsedSeconds = definition.ElapsedSeconds,
		ProcessedAt = os.time(),
		CompletedAt = definition.CompletedAt,
		Balance = data.Coins,
		Completions = progress.Completions,
		BestTime = progress.BestTime,
		CommitToken = commitToken,
	}
	data.DungeonResults.ProcessedResultIds[definition.ResultId] = record
	data.DungeonResults.LastResult = record
	data.DungeonResults = sanitizeDungeonResults(data.DungeonResults)
	return data.DungeonResults.ProcessedResultIds[definition.ResultId]
end

local function commitDungeonResultByUserId(userId, resultId, payload)
	local cleanUserId = math.floor(tonumber(userId) or 0)
	if cleanUserId <= 0 then
		return false, false, nil, "InvalidUserId"
	end
	local definition, validationError = normalizeDungeonResult(resultId, payload)
	if not definition then
		return false, false, nil, validationError
	end
	local commitToken = HttpService:GenerateGUID(false)
	local success, persisted = retry(
		"DungeonResult " .. tostring(cleanUserId),
		SAVE_RETRIES,
		function()
			return store:UpdateAsync(keyForUserId(cleanUserId), function(previous)
				local data = sanitize(previous)
				applyDungeonResult(data, definition, commitToken)
				return data
			end)
		end
	)
	if not success then
		return false, false, nil, tostring(persisted)
	end
	local persistedData = sanitize(persisted)
	local record = persistedData.DungeonResults.ProcessedResultIds[definition.ResultId]
	if not record then
		return false, false, nil, "DungeonResultMissingAfterCommit"
	end
	return true, record.CommitToken == commitToken, cloneDungeonResultRecord(record), nil, persistedData
end

function PlayerDataService.GetDungeonResult(player, resultId)
	local data = PlayerDataService.Get(player)
	local record = data
		and data.DungeonResults.ProcessedResultIds[tostring(resultId or "")]
	return cloneDungeonResultRecord(record)
end

function PlayerDataService.GetLastDungeonResult(player)
	local data = PlayerDataService.Get(player)
	return data and cloneDungeonResultRecord(data.DungeonResults.LastResult) or nil
end

function PlayerDataService.CommitDungeonResultByUserId(userId, resultId, payload)
	local success, applied, record, errorCode = commitDungeonResultByUserId(
		userId,
		resultId,
		payload
	)
	return success, applied, record, errorCode
end

function PlayerDataService.CommitDungeonResult(player, resultId, payload)
	if not player or player.Parent ~= Players then
		return false, false, nil, "InvalidPlayer"
	end
	PlayerDataService.Load(player)
	local session = sessions[player]
	if not session or not session.CanSave then
		return false, false, nil, "PlayerDataNotSaveable"
	end
	-- Primeiro confirma todos os grants e moedas de rodadas já concluídas. O
	-- resultado final nunca deve substituir um snapshot mais novo por um antigo.
	if not PlayerDataService.Save(player, true) then
		return false, false, nil, "PreResultSaveFailed"
	end
	local success, applied, record, errorCode, persistedData =
		commitDungeonResultByUserId(player.UserId, resultId, payload)
	if success and persistedData and sessions[player] == session then
		session.Data = persistedData
		session.Dirty = false
		session.Revision += 1
	end
	return success, applied, record, errorCode
end


function PlayerDataService.HasDungeonGrant(player, grantId)
	local data = PlayerDataService.Get(player)
	local cleanId = tostring(grantId or "")
	return data ~= nil
		and cleanId ~= ""
		and data.DungeonRewards.ProcessedGrantIds[cleanId] ~= nil
end

function PlayerDataService.ApplyDungeonGrant(player, grantId, rewards)
	local session = sessions[player]
	local cleanId = tostring(grantId or "")
	if not session or cleanId == "" or type(rewards) ~= "table" or #rewards == 0 then
		return false, false, "InvalidDungeonGrant"
	end
	if session.Data.DungeonRewards.ProcessedGrantIds[cleanId] ~= nil then
		return true, true, {}
	end
	for _, reward in ipairs(rewards) do
		local kind = type(reward) == "table" and tostring(reward.Kind or "") or ""
		if kind ~= "Coins" and kind ~= "Sword" and kind ~= "Companion" and kind ~= "Item" then
			return false, false, "UnsupportedDungeonReward:" .. kind
		end
		if kind ~= "Coins" and (type(reward.Id) ~= "string" or reward.Id == "") then
			return false, false, "DungeonRewardIdMissing"
		end
		if kind == "Companion" and not CompanionCatalog.IsSupported(reward.Id) then
			return false, false, "UnsupportedCompanion:" .. tostring(reward.Id)
		end
		if kind == "Item" and not ItemCatalog.Get(reward.Id) then
			return false, false, "UnsupportedItem:" .. tostring(reward.Id)
		end
	end

	local results = {}
	local compensationCoins = 0
	for _, reward in ipairs(rewards) do
		local kind = tostring(reward.Kind)
		local amount = kind == "Coins"
			and math.max(0, math.floor(tonumber(reward.Amount) or 0))
			or math.max(1, math.floor(tonumber(reward.Amount) or 1))
		local duplicateCoins = math.max(0, math.floor(tonumber(reward.DuplicateCoins) or 0))
		if kind == "Coins" then
			session.Data.Coins += amount
			table.insert(results, { Kind = kind, Amount = amount })
		elseif kind == "Sword" then
			local duplicate = session.Data.OwnedSwords[reward.Id] == true
			if duplicate then
				compensationCoins += duplicateCoins
			else
				session.Data.OwnedSwords[reward.Id] = true
			end
			table.insert(results, {
				Kind = kind,
				Id = reward.Id,
				Amount = 1,
				Duplicate = duplicate,
				CompensationCoins = duplicate and duplicateCoins or 0,
			})
		elseif kind == "Companion" then
			local duplicate = false
			for _, record in pairs(session.Data.OwnedCompanions) do
				if record.SpeciesId == reward.Id then
					duplicate = true
					break
				end
			end
			local storedCount = 0
			for _ in pairs(session.Data.OwnedCompanions) do
				storedCount += 1
			end
			if duplicate or storedCount >= CompanionCatalog.MaximumStored then
				compensationCoins += duplicateCoins
			else
				local definition = CompanionCatalog.Get(reward.Id)
				local instanceId = "companion_" .. HttpService:GenerateGUID(false)
				session.Data.OwnedCompanions[instanceId] = {
					InstanceId = instanceId,
					SpeciesId = reward.Id,
					DisplayName = definition.DisplayName,
					Level = 1,
					XP = 0,
					Kills = 0,
					Upgrades = CompanionCatalog.EmptyUpgrades(),
				}
				if #session.Data.EquippedCompanions == 0 and session.Data.CompanionEquipSlots >= 1 then
					table.insert(session.Data.EquippedCompanions, instanceId)
				end
			end
			table.insert(results, {
				Kind = kind,
				Id = reward.Id,
				Amount = 1,
				Duplicate = duplicate or storedCount >= CompanionCatalog.MaximumStored,
				CompensationCoins = (duplicate or storedCount >= CompanionCatalog.MaximumStored) and duplicateCoins or 0,
			})
		elseif kind == "Item" then
			local definition = ItemCatalog.Get(reward.Id)
			local current = session.Data.Inventory[reward.Id] or 0
			local maximum = math.max(1, math.floor(tonumber(definition.MaximumStack) or 9999))
			local granted = math.max(0, math.min(amount, maximum - current))
			if granted > 0 then
				session.Data.Inventory[reward.Id] = current + granted
			end
			local rejected = amount - granted
			if rejected > 0 then
				compensationCoins += duplicateCoins
			end
			table.insert(results, {
				Kind = kind,
				Id = reward.Id,
				Amount = granted,
				Duplicate = rejected > 0,
				CompensationCoins = rejected > 0 and duplicateCoins or 0,
			})
		end
	end
	if compensationCoins > 0 then
		session.Data.Coins += compensationCoins
		table.insert(results, { Kind = "Coins", Amount = compensationCoins, Compensation = true })
	end
	session.Data.DungeonRewards.ProcessedGrantIds[cleanId] = os.time()
	session.Data.DungeonRewards.ProcessedGrantIds = sanitizeDungeonRewardGrantIds(
		session.Data.DungeonRewards.ProcessedGrantIds
	)
	markDirty(session)
	return true, false, results
end


local function normalizeDungeonResult(resultId, payload)
	if type(payload) ~= "table" then
		return nil, "InvalidDungeonResultPayload"
	end
	local cleanId = tostring(resultId or "")
	local sessionId = tostring(payload.SessionId or "")
	local phaseId = tostring(payload.PhaseId or "")
	local resultName = tostring(payload.Result or "Defeat")
	if cleanId == "" or sessionId == "" or phaseId == "" then
		return nil, "InvalidDungeonResultIdentity"
	end
	return {
		ResultId = cleanId,
		SessionId = sessionId,
		PhaseId = phaseId,
		Result = resultName,
		Eligible = resultName == "Victory" and payload.Eligible == true,
		RewardCoins = math.max(0, math.floor(tonumber(payload.RewardCoins) or 0)),
		ElapsedSeconds = math.max(0, tonumber(payload.ElapsedSeconds) or 0),
		CompletedAt = math.max(1, math.floor(tonumber(payload.CompletedAt) or os.time())),
	}
end

local function applyDungeonResult(data, definition, commitToken)
	local existing = data.DungeonResults.ProcessedResultIds[definition.ResultId]
	if existing then
		return existing
	end
	local progress = data.Progression.Phases[definition.PhaseId]
	if not progress then
		progress = { Completions = 0, BossDefeated = false, BestTime = nil }
		data.Progression.Phases[definition.PhaseId] = progress
	end
	local rewardCoins = definition.Eligible and definition.RewardCoins or 0
	if definition.Result == "Victory" and definition.Eligible then
		data.Coins += rewardCoins
		progress.Completions += 1
		progress.BossDefeated = true
		if definition.ElapsedSeconds > 0
			and (not progress.BestTime or definition.ElapsedSeconds < progress.BestTime)
		then
			progress.BestTime = definition.ElapsedSeconds
		end
	end
	local record = {
		ResultId = definition.ResultId,
		SessionId = definition.SessionId,
		PhaseId = definition.PhaseId,
		Result = definition.Result,
		Eligible = definition.Eligible,
		RewardCoins = rewardCoins,
		ElapsedSeconds = definition.ElapsedSeconds,
		ProcessedAt = os.time(),
		CompletedAt = definition.CompletedAt,
		Balance = data.Coins,
		Completions = progress.Completions,
		BestTime = progress.BestTime,
		CommitToken = commitToken,
	}
	data.DungeonResults.ProcessedResultIds[definition.ResultId] = record
	data.DungeonResults.LastResult = record
	data.DungeonResults = sanitizeDungeonResults(data.DungeonResults)
	return data.DungeonResults.ProcessedResultIds[definition.ResultId]
end

local function commitDungeonResultByUserId(userId, resultId, payload)
	local cleanUserId = math.floor(tonumber(userId) or 0)
	if cleanUserId <= 0 then
		return false, false, nil, "InvalidUserId"
	end
	local definition, validationError = normalizeDungeonResult(resultId, payload)
	if not definition then
		return false, false, nil, validationError
	end
	local commitToken = HttpService:GenerateGUID(false)
	local success, persisted = retry(
		"DungeonResult " .. tostring(cleanUserId),
		SAVE_RETRIES,
		function()
			return store:UpdateAsync(keyForUserId(cleanUserId), function(previous)
				local data = sanitize(previous)
				applyDungeonResult(data, definition, commitToken)
				return data
			end)
		end
	)
	if not success then
		return false, false, nil, tostring(persisted)
	end
	local persistedData = sanitize(persisted)
	local record = persistedData.DungeonResults.ProcessedResultIds[definition.ResultId]
	if not record then
		return false, false, nil, "DungeonResultMissingAfterCommit"
	end
	return true, record.CommitToken == commitToken, cloneDungeonResultRecord(record), nil, persistedData
end

function PlayerDataService.GetDungeonResult(player, resultId)
	local data = PlayerDataService.Get(player)
	local record = data
		and data.DungeonResults.ProcessedResultIds[tostring(resultId or "")]
	return cloneDungeonResultRecord(record)
end

function PlayerDataService.GetLastDungeonResult(player)
	local data = PlayerDataService.Get(player)
	return data and cloneDungeonResultRecord(data.DungeonResults.LastResult) or nil
end

function PlayerDataService.CommitDungeonResultByUserId(userId, resultId, payload)
	local success, applied, record, errorCode = commitDungeonResultByUserId(
		userId,
		resultId,
		payload
	)
	return success, applied, record, errorCode
end

function PlayerDataService.CommitDungeonResult(player, resultId, payload)
	if not player or player.Parent ~= Players then
		return false, false, nil, "InvalidPlayer"
	end
	PlayerDataService.Load(player)
	local session = sessions[player]
	if not session or not session.CanSave then
		return false, false, nil, "PlayerDataNotSaveable"
	end
	-- Primeiro confirma todos os grants e moedas de rodadas já concluídas. O
	-- resultado final nunca deve substituir um snapshot mais novo por um antigo.
	if not PlayerDataService.Save(player, true) then
		return false, false, nil, "PreResultSaveFailed"
	end
	local success, applied, record, errorCode, persistedData =
		commitDungeonResultByUserId(player.UserId, resultId, payload)
	if success and persistedData and sessions[player] == session then
		session.Data = persistedData
		session.Dirty = false
		session.Revision += 1
	end
	return success, applied, record, errorCode
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
			for wingId, owned in pairs(previousData.OwnedWings) do
				if owned then
					snapshot.OwnedWings[wingId] = true
				end
			end
			for abilityId, owned in pairs(previousData.OwnedAbilities) do
				if owned then
					snapshot.OwnedAbilities[abilityId] = true
				end
			end
			for relicId, owned in pairs(previousData.OwnedRelics) do
				if owned then
					snapshot.OwnedRelics[relicId] = true
				end
			end
			for instanceId, previousRecord in pairs(previousData.OwnedCompanions) do
				if not snapshotDiscardedCompanions[instanceId] then
					local currentRecord = snapshot.OwnedCompanions[instanceId]
					if not currentRecord then
						snapshot.OwnedCompanions[instanceId] = previousRecord
					elseif previousRecord.Level > currentRecord.Level then
						snapshot.OwnedCompanions[instanceId] = previousRecord
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
			snapshot.CompanionEquipSlots = math.max(
				snapshot.CompanionEquipSlots,
				previousData.CompanionEquipSlots
			)
			snapshot.TutorialCompleted = snapshot.TutorialCompleted or previousData.TutorialCompleted
			snapshot.AnalyticsOnboardingCompleted = snapshot.AnalyticsOnboardingCompleted
				or previousData.AnalyticsOnboardingCompleted
			snapshot.TutorialStage = snapshot.TutorialCompleted
				and 5
				or math.max(snapshot.TutorialStage, previousData.TutorialStage)
			if not snapshot.OwnedSwords[snapshot.EquippedSword] then
				snapshot.EquippedSword = STARTER_SWORD_ID
			end
			if snapshot.EquippedWings and not snapshot.OwnedWings[snapshot.EquippedWings] then
				snapshot.EquippedWings = nil
			end
			if snapshot.EquippedAbility and not snapshot.OwnedAbilities[snapshot.EquippedAbility] then
				snapshot.EquippedAbility = nil
			end
			if snapshot.EquippedRelic and not snapshot.OwnedRelics[snapshot.EquippedRelic] then
				snapshot.EquippedRelic = nil
			end
			snapshot.EquippedCompanions = sanitizeEquippedCompanions(
				snapshot.EquippedCompanions,
				nil,
				snapshot.OwnedCompanions,
				nil,
				snapshot.CompanionEquipSlots
			)
			if previousData.DailyLastClaimDay > snapshot.DailyLastClaimDay then
				snapshot.DailyLastClaimDay = previousData.DailyLastClaimDay
				snapshot.DailyStreak = previousData.DailyStreak
			elseif previousData.DailyLastClaimDay == snapshot.DailyLastClaimDay then
				snapshot.DailyStreak = math.max(snapshot.DailyStreak, previousData.DailyStreak)
			end
			for phaseId, previousProgress in pairs(previousData.Progression.Phases) do
				local current = snapshot.Progression.Phases[phaseId]
				if current then
					current.Completions = math.max(current.Completions, previousProgress.Completions)
					current.BossDefeated = current.BossDefeated or previousProgress.BossDefeated
					if previousProgress.BestTime and (
						not current.BestTime or previousProgress.BestTime < current.BestTime
					) then
						current.BestTime = previousProgress.BestTime
					end
				end
			end
			snapshot.Roulette.TotalSpins = math.max(
				snapshot.Roulette.TotalSpins,
				previousData.Roulette.TotalSpins
			)
			snapshot.Roulette.LastSpinAt = math.max(
				snapshot.Roulette.LastSpinAt,
				previousData.Roulette.LastSpinAt
			)
			snapshot.Monetization.TreasureBoostUntil = math.max(
				snapshot.Monetization.TreasureBoostUntil,
				previousData.Monetization.TreasureBoostUntil
			)
			snapshot.Monetization.EliteBoostUntil = math.max(
				snapshot.Monetization.EliteBoostUntil,
				previousData.Monetization.EliteBoostUntil
			)
			for purchaseId, processedAt in pairs(
				previousData.Monetization.ProcessedPurchaseIds
			) do
				snapshot.Monetization.ProcessedPurchaseIds[purchaseId] = math.max(
					tonumber(snapshot.Monetization.ProcessedPurchaseIds[purchaseId]) or 0,
					processedAt
				)
			end
			snapshot.Monetization.ProcessedPurchaseIds = sanitizeProcessedPurchaseIds(
				snapshot.Monetization.ProcessedPurchaseIds
			)
			for grantId, processedAt in pairs(previousData.DungeonRewards.ProcessedGrantIds) do
				snapshot.DungeonRewards.ProcessedGrantIds[grantId] = math.max(
					tonumber(snapshot.DungeonRewards.ProcessedGrantIds[grantId]) or 0,
					processedAt
				)
			end
			snapshot.DungeonRewards.ProcessedGrantIds = sanitizeDungeonRewardGrantIds(
				snapshot.DungeonRewards.ProcessedGrantIds
			)
			local inheritedCommittedResult = false
			for resultId, previousRecord in pairs(
				previousData.DungeonResults.ProcessedResultIds
			) do
				local currentRecord = snapshot.DungeonResults.ProcessedResultIds[resultId]
				if not currentRecord
					or previousRecord.ProcessedAt >= currentRecord.ProcessedAt
				then
					if not currentRecord then
						inheritedCommittedResult = true
					end
					snapshot.DungeonResults.ProcessedResultIds[resultId] =
						cloneDungeonResultRecord(previousRecord)
				end
			end
			if inheritedCommittedResult then
				snapshot.Coins = math.max(snapshot.Coins, previousData.Coins)
			end
			snapshot.DungeonResults = sanitizeDungeonResults(snapshot.DungeonResults)
			return snapshot
		end)
	end)
	session.Saving = false
	if success then
		for purchaseId, processedAt in pairs(
			snapshot.Monetization.ProcessedPurchaseIds
		) do
			session.Data.Monetization.ProcessedPurchaseIds[purchaseId] = math.max(
				tonumber(session.Data.Monetization.ProcessedPurchaseIds[purchaseId]) or 0,
				processedAt
			)
		end
		session.Data.Monetization.ProcessedPurchaseIds = sanitizeProcessedPurchaseIds(
			session.Data.Monetization.ProcessedPurchaseIds
		)
		for grantId, processedAt in pairs(snapshot.DungeonRewards.ProcessedGrantIds) do
			session.Data.DungeonRewards.ProcessedGrantIds[grantId] = math.max(
				tonumber(session.Data.DungeonRewards.ProcessedGrantIds[grantId]) or 0,
				processedAt
			)
		end
		session.Data.DungeonRewards.ProcessedGrantIds = sanitizeDungeonRewardGrantIds(
			session.Data.DungeonRewards.ProcessedGrantIds
		)
		for resultId, record in pairs(snapshot.DungeonResults.ProcessedResultIds) do
			local current = session.Data.DungeonResults.ProcessedResultIds[resultId]
			if not current or record.ProcessedAt >= current.ProcessedAt then
				session.Data.DungeonResults.ProcessedResultIds[resultId] =
					cloneDungeonResultRecord(record)
			end
		end
		session.Data.DungeonResults = sanitizeDungeonResults(session.Data.DungeonResults)
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
