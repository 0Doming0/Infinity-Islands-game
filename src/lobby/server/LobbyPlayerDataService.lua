-- Dados mínimos e seguros usados pelo Lobby.
-- Mantém o mesmo DataStore da Dungeon, mas atualiza apenas os campos que o
-- Lobby realmente possui. Campos de resultado, recompensas e progressão da
-- Dungeon são preservados integralmente no UpdateAsync.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))

local DATASTORE_NAME = "SkyDungeonPlayerData_V10"
local SCHEMA_VERSION = 13
local STARTER_SWORD_ID = "ClassicSword"
local LOAD_RETRIES = 4
local SAVE_RETRIES = 4
local RETRY_DELAY_SECONDS = 1.25

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local sessions = {}
local loadingSignals = {}

local LobbyPlayerDataService = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[deepCopy(key)] = deepCopy(item)
	end
	return copy
end

local function keyFor(player)
	return string.format("Player_%d", player.UserId)
end

local function retry(label, attempts, callback)
	local lastError
	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[LobbyData] %s falhou (%d/%d): %s", label, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(RETRY_DELAY_SECONDS * attempt)
		end
	end
	return false, lastError
end

local function defaultData()
	return {
		SchemaVersion = SCHEMA_VERSION,
		Coins = 0,
		OwnedSwords = { [STARTER_SWORD_ID] = true },
		EquippedSword = STARTER_SWORD_ID,
		OwnedWings = {},
		EquippedWings = nil,
		OwnedAbilities = {},
		EquippedAbility = nil,
		OwnedCompanions = {},
		EquippedCompanions = {},
		CompanionEquipSlots = CompanionCatalog.InitialEquippedSlots,
		Tickets = { LuckyWheelSpin = 0 },
		Roulette = {
			TotalSpins = 0,
			LastSpinAt = 0,
		},
		-- Lido pelo Lobby para desbloqueio de níveis. O Lobby NÃO grava este campo.
		Progression = { Phases = {} },
	}
end

local function sanitizeOwnedSet(source, starterId)
	local result = {}
	if starterId then
		result[starterId] = true
	end
	if type(source) == "table" then
		for key, value in pairs(source) do
			if type(key) == "string" and value == true then
				result[key] = true
			elseif type(key) == "number" and type(value) == "string" and value ~= "" then
				result[value] = true
			end
		end
	end
	return result
end

local function sanitizeCompanions(source)
	local result = {}
	if type(source) ~= "table" then
		return result
	end
	local count = 0
	for instanceId, record in pairs(source) do
		if count >= CompanionCatalog.MaximumStored then
			break
		end
		if type(instanceId) == "string" and type(record) == "table" then
			local speciesId = tostring(record.SpeciesId or record.MonsterId or "")
			if CompanionCatalog.IsSupported(speciesId) then
				result[instanceId] = {
					InstanceId = instanceId,
					SpeciesId = speciesId,
					DisplayName = tostring(record.DisplayName or speciesId),
					Level = math.clamp(math.floor(tonumber(record.Level) or 1), 1, CompanionCatalog.MaxLevel),
					XP = math.max(0, math.floor(tonumber(record.XP) or 0)),
					Kills = math.max(0, math.floor(tonumber(record.Kills) or 0)),
					Upgrades = deepCopy(record.Upgrades or CompanionCatalog.EmptyUpgrades()),
				}
				count += 1
			end
		end
	end
	return result
end

local function sanitizeEquipped(source, owned, limit)
	local result = {}
	local seen = {}
	if type(source) == "table" then
		for _, instanceId in ipairs(source) do
			if #result >= limit then
				break
			end
			if type(instanceId) == "string" and owned[instanceId] and not seen[instanceId] then
				seen[instanceId] = true
				table.insert(result, instanceId)
			end
		end
	end
	return result
end

local function sanitizeTickets(source)
	local result = { LuckyWheelSpin = 0 }
	if type(source) == "table" then
		for ticketId, amount in pairs(source) do
			if type(ticketId) == "string" and ticketId ~= "" then
				result[ticketId] = math.clamp(math.floor(tonumber(amount) or 0), 0, 9999)
			end
		end
	end
	return result
end


local function sanitizeProgression(source)
	local result = { Phases = {} }
	local phases = type(source) == "table" and source.Phases or nil
	if type(phases) ~= "table" then
		return result
	end
	for phaseId, raw in pairs(phases) do
		if type(phaseId) == "string" and phaseId ~= "" and type(raw) == "table" then
			local bestTime = tonumber(raw.BestTime)
			result.Phases[phaseId] = {
				Completions = math.max(0, math.floor(tonumber(raw.Completions) or 0)),
				BossDefeated = raw.BossDefeated == true or (tonumber(raw.Completions) or 0) > 0,
				BestTime = bestTime and bestTime > 0 and bestTime or nil,
			}
		end
	end
	return result
end

local function sanitize(raw)
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	data.SchemaVersion = math.max(SCHEMA_VERSION, math.floor(tonumber(raw.SchemaVersion) or 0))
	data.Coins = math.max(0, math.floor(tonumber(raw.Coins) or 0))
	data.OwnedSwords = sanitizeOwnedSet(raw.OwnedSwords, STARTER_SWORD_ID)
	data.OwnedWings = sanitizeOwnedSet(raw.OwnedWings)
	data.OwnedAbilities = sanitizeOwnedSet(raw.OwnedAbilities)
	data.EquippedSword = type(raw.EquippedSword) == "string" and raw.EquippedSword or STARTER_SWORD_ID
	if not data.OwnedSwords[data.EquippedSword] then
		data.EquippedSword = STARTER_SWORD_ID
	end
	data.EquippedWings = type(raw.EquippedWings) == "string" and raw.EquippedWings or nil
	if data.EquippedWings and not data.OwnedWings[data.EquippedWings] then
		data.EquippedWings = nil
	end
	data.EquippedAbility = type(raw.EquippedAbility) == "string" and raw.EquippedAbility or nil
	if data.EquippedAbility and not data.OwnedAbilities[data.EquippedAbility] then
		data.EquippedAbility = nil
	end
	data.OwnedCompanions = sanitizeCompanions(raw.OwnedCompanions)
	data.CompanionEquipSlots = math.clamp(
		math.floor(tonumber(raw.CompanionEquipSlots) or CompanionCatalog.InitialEquippedSlots),
		CompanionCatalog.InitialEquippedSlots,
		CompanionCatalog.MaxEquipped
	)
	data.EquippedCompanions = sanitizeEquipped(
		raw.EquippedCompanions,
		data.OwnedCompanions,
		data.CompanionEquipSlots
	)
	data.Tickets = sanitizeTickets(raw.Tickets)
	local roulette = type(raw.Roulette) == "table" and raw.Roulette or {}
	data.Roulette = {
		TotalSpins = math.max(0, math.floor(tonumber(roulette.TotalSpins) or 0)),
		LastSpinAt = math.max(0, math.floor(tonumber(roulette.LastSpinAt) or 0)),
	}
	data.Progression = sanitizeProgression(raw.Progression)
	return data
end

local function markDirty(session)
	session.Dirty = true
	session.Revision += 1
end

local function mergeLobbyFields(previous, data)
	local merged = type(previous) == "table" and deepCopy(previous) or {}
	merged.SchemaVersion = math.max(SCHEMA_VERSION, math.floor(tonumber(merged.SchemaVersion) or 0))
	merged.Coins = data.Coins
	merged.OwnedSwords = deepCopy(data.OwnedSwords)
	merged.EquippedSword = data.EquippedSword
	merged.OwnedWings = deepCopy(data.OwnedWings)
	merged.EquippedWings = data.EquippedWings
	merged.OwnedAbilities = deepCopy(data.OwnedAbilities)
	merged.EquippedAbility = data.EquippedAbility
	merged.OwnedCompanions = deepCopy(data.OwnedCompanions)
	merged.EquippedCompanions = table.clone(data.EquippedCompanions)
	merged.CompanionEquipSlots = data.CompanionEquipSlots
	merged.Tickets = deepCopy(data.Tickets)
	merged.Roulette = deepCopy(data.Roulette)
	return merged
end

function LobbyPlayerDataService.Load(player)
	local existing = sessions[player]
	if existing then
		return existing.Data
	end
	local loading = loadingSignals[player]
	if loading then
		loading.Event:Wait()
		local loaded = sessions[player]
		return loaded and loaded.Data or defaultData()
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
		Saving = false,
	}
	player:SetAttribute("PlayerDataLoaded", true)
	player:SetAttribute("PlayerDataTemporary", not success)
	player:SetAttribute("LobbyCoins", data.Coins)
	loadingSignals[player] = nil
	signal:Fire()
	signal:Destroy()
	return data
end

function LobbyPlayerDataService.Get(player)
	local session = sessions[player]
	return session and session.Data or nil
end

function LobbyPlayerDataService.Save(player, force)
	local session = sessions[player]
	if not session then
		return false
	end
	if not session.CanSave then
		return false
	end
	if session.Saving then
		return false
	end
	if not force and not session.Dirty then
		return true
	end
	session.Saving = true
	local snapshot = deepCopy(session.Data)
	local revision = session.Revision
	local success = retry("Save " .. player.Name, SAVE_RETRIES, function()
		return store:UpdateAsync(keyFor(player), function(previous)
			return mergeLobbyFields(previous, snapshot)
		end)
	end)
	session.Saving = false
	if success and session.Revision == revision then
		session.Dirty = false
	end
	return success == true
end

function LobbyPlayerDataService.Release(player)
	sessions[player] = nil
	loadingSignals[player] = nil
end

function LobbyPlayerDataService.AddCoins(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 then
		return false, session and session.Data.Coins or 0
	end
	session.Data.Coins += clean
	markDirty(session)
	player:SetAttribute("LobbyCoins", session.Data.Coins)
	return true, session.Data.Coins
end

function LobbyPlayerDataService.TrySpendCoins(player, amount)
	local session = sessions[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not session or clean <= 0 or session.Data.Coins < clean then
		return false, session and session.Data.Coins or 0
	end
	session.Data.Coins -= clean
	markDirty(session)
	player:SetAttribute("LobbyCoins", session.Data.Coins)
	return true, session.Data.Coins
end


function LobbyPlayerDataService.GetCoins(player)
	local data = LobbyPlayerDataService.Get(player)
	return data and data.Coins or 0
end

function LobbyPlayerDataService.GetPhaseProgress(player, phaseId)
	local data = LobbyPlayerDataService.Get(player) or LobbyPlayerDataService.Load(player)
	local progress = data and data.Progression and data.Progression.Phases[phaseId]
	if not progress then
		return {
			Completions = 0,
			BossDefeated = false,
			BestTime = nil,
		}
	end
	return {
		Completions = math.max(0, math.floor(tonumber(progress.Completions) or 0)),
		BossDefeated = progress.BossDefeated == true,
		BestTime = tonumber(progress.BestTime),
	}
end

function LobbyPlayerDataService.HasSword(player, swordId)
	local data = LobbyPlayerDataService.Get(player)
	return data ~= nil and data.OwnedSwords[swordId] == true
end

function LobbyPlayerDataService.GrantSword(player, swordId)
	local session = sessions[player]
	if not session or type(swordId) ~= "string" or swordId == "" then
		return false
	end
	if not session.Data.OwnedSwords[swordId] then
		session.Data.OwnedSwords[swordId] = true
		markDirty(session)
	end
	return true
end

function LobbyPlayerDataService.GrantWings(player, wingId)
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

function LobbyPlayerDataService.SetEquippedSword(player, swordId)
	local session = sessions[player]
	if not session or session.Data.OwnedSwords[swordId] ~= true then
		return false
	end
	session.Data.EquippedSword = swordId
	markDirty(session)
	return true
end

function LobbyPlayerDataService.SetEquippedWings(player, wingId)
	local session = sessions[player]
	if not session or session.Data.OwnedWings[wingId] ~= true then
		return false
	end
	session.Data.EquippedWings = wingId
	markDirty(session)
	return true
end

function LobbyPlayerDataService.SetEquippedAbility(player, abilityId)
	local session = sessions[player]
	if not session or session.Data.OwnedAbilities[abilityId] ~= true then
		return false
	end
	session.Data.EquippedAbility = abilityId
	markDirty(session)
	return true
end

function LobbyPlayerDataService.GetCompanions(player)
	local data = LobbyPlayerDataService.Get(player)
	return data and deepCopy(data.OwnedCompanions) or {},
		data and table.clone(data.EquippedCompanions) or {}
end

function LobbyPlayerDataService.UnlockCompanion(player, speciesId, displayName)
	local session = sessions[player]
	if not session or not CompanionCatalog.IsSupported(speciesId) then
		return false, false, nil
	end
	local stored = 0
	for _ in pairs(session.Data.OwnedCompanions) do
		stored += 1
	end
	if stored >= CompanionCatalog.MaximumStored then
		return false, false, nil
	end
	local instanceId = "companion_" .. HttpService:GenerateGUID(false)
	session.Data.OwnedCompanions[instanceId] = {
		InstanceId = instanceId,
		SpeciesId = speciesId,
		DisplayName = tostring(displayName or speciesId),
		Level = 1,
		XP = 0,
		Kills = 0,
		Upgrades = CompanionCatalog.EmptyUpgrades(),
	}
	if #session.Data.EquippedCompanions == 0 then
		table.insert(session.Data.EquippedCompanions, instanceId)
	end
	markDirty(session)
	return true, true, instanceId
end

function LobbyPlayerDataService.SetCompanionEquipped(player, instanceId, shouldEquip)
	local session = sessions[player]
	if not session or not session.Data.OwnedCompanions[instanceId] then
		return false, "Companheiro inválido."
	end
	local index = table.find(session.Data.EquippedCompanions, instanceId)
	if shouldEquip == false then
		if index then
			table.remove(session.Data.EquippedCompanions, index)
			markDirty(session)
		end
		return true
	end
	if index then
		return true
	end
	if #session.Data.EquippedCompanions >= session.Data.CompanionEquipSlots then
		return false, "Sem slot de companheiro disponível."
	end
	table.insert(session.Data.EquippedCompanions, instanceId)
	markDirty(session)
	return true
end

function LobbyPlayerDataService.AddTicket(player, ticketId, amount)
	local session = sessions[player]
	local clean = math.max(1, math.floor(tonumber(amount) or 1))
	if not session or type(ticketId) ~= "string" or ticketId == "" then
		return false, 0
	end
	session.Data.Tickets[ticketId] = math.min(9999, (session.Data.Tickets[ticketId] or 0) + clean)
	markDirty(session)
	return true, session.Data.Tickets[ticketId]
end

function LobbyPlayerDataService.RemoveTicket(player, ticketId, amount)
	local session = sessions[player]
	local clean = math.max(1, math.floor(tonumber(amount) or 1))
	local current = session and session.Data.Tickets[ticketId] or 0
	if not session or current < clean then
		return false, current
	end
	session.Data.Tickets[ticketId] = current - clean
	markDirty(session)
	return true, session.Data.Tickets[ticketId]
end

function LobbyPlayerDataService.RecordRouletteSpin(player)
	local session = sessions[player]
	if not session then
		return false
	end
	session.Data.Roulette.TotalSpins += 1
	session.Data.Roulette.LastSpinAt = os.time()
	markDirty(session)
	return true
end

return LobbyPlayerDataService
