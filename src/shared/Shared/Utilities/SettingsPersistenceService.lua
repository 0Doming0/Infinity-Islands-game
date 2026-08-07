-- Persistência compartilhada de preferências entre Lobby e Dungeon.
-- Este módulo só deve ser requerido no servidor.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.Configs.SettingsConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)

local SettingsPersistenceService = {}

local store = DataStoreService:GetDataStore(SettingsConfig.DataStoreName)
local sessions = {}
local request
local event
local started = false
local placeLabel = "Unknown"
local saveSerial = 0

local function keyFor(player)
	return "u_" .. tostring(player.UserId)
end

local function retry(label, attempts, callback)
	local lastError
	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(0.65 * attempt)
		end
	end
	warn(string.format("[Settings/%s] %s: %s", placeLabel, label, tostring(lastError)))
	return false, lastError
end

local function publishAttributes(player, settings)
	for key, value in pairs(settings) do
		player:SetAttribute("Setting_" .. key, value)
	end
	player:SetAttribute("SettingsLoaded", true)
end

local function load(player)
	local existing = sessions[player]
	if existing then
		return existing.Settings
	end

	local success, raw = retry("Load " .. player.Name, 3, function()
		return store:GetAsync(keyFor(player))
	end)

	local settings = SettingsConfig.Sanitize(success and raw or nil)
	sessions[player] = {
		Settings = settings,
		Dirty = false,
		Saving = false,
		SaveScheduled = false,
		LastError = success and nil or tostring(raw),
		Revision = 0,
	}
	publishAttributes(player, settings)
	player:SetAttribute("SettingsTemporary", not success)
	return settings
end

local function snapshot(player)
	local settings = load(player)
	local result = {}
	for key, value in pairs(settings) do
		result[key] = value
	end
	local session = sessions[player]
	return {
		Settings = result,
		Temporary = player:GetAttribute("SettingsTemporary") == true,
		Dirty = session and session.Dirty == true,
		LastError = session and session.LastError or nil,
		Revision = session and session.Revision or 0,
	}
end

local function save(player, force)
	local session = sessions[player]
	if not session or session.Saving or (not force and not session.Dirty) then
		return session and not session.Dirty or false
	end

	session.Saving = true
	local payload = SettingsConfig.Sanitize(session.Settings)
	local revision = session.Revision

	local success, result = retry("Save " .. player.Name, 3, function()
		store:SetAsync(keyFor(player), payload)
		return true
	end)

	session.Saving = false
	if success then
		if session.Revision == revision then
			session.Dirty = false
		end
		session.LastError = nil
		player:SetAttribute("SettingsTemporary", false)
		if player.Parent == Players and event then
			event:FireClient(player, {
				Action = "Saved",
				Revision = revision,
				Settings = SettingsConfig.Sanitize(session.Settings),
			})
		end
	else
		session.LastError = tostring(result)
		if player.Parent == Players and event then
			event:FireClient(player, {
				Action = "SaveFailed",
				Message = "Preferências não foram salvas ainda. O servidor tentará novamente.",
			})
		end
	end
	return success
end

local function scheduleSave(player)
	local session = sessions[player]
	if not session or session.SaveScheduled then
		return
	end
	session.SaveScheduled = true
	saveSerial += 1
	local serial = saveSerial
	task.delay(1.6, function()
		local current = sessions[player]
		if not current then return end
		current.SaveScheduled = false
		if player.Parent == Players then
			save(player, false)
		end
	end)
end

local function setOne(player, key, value)
	if type(key) ~= "string" or not SettingsConfig.IsKnown(key) then
		return {
			Success = false,
			Message = "Configuração inválida.",
			Snapshot = snapshot(player),
		}
	end

	local normalized = SettingsConfig.NormalizeValue(key, value)
	if normalized == nil then
		return {
			Success = false,
			Message = "Valor inválido.",
			Snapshot = snapshot(player),
		}
	end

	local settings = load(player)
	local session = sessions[player]
	if settings[key] ~= normalized then
		settings[key] = normalized
		session.Dirty = true
		session.Revision += 1
		publishAttributes(player, settings)
		event:FireClient(player, {
			Action = "Updated",
			Key = key,
			Value = normalized,
			Settings = SettingsConfig.Sanitize(settings),
			Revision = session.Revision,
		})
		scheduleSave(player)
	end

	return {
		Success = true,
		Message = "Preferência atualizada.",
		Snapshot = snapshot(player),
	}
end

local function reset(player)
	local session = sessions[player]
	if not session then
		load(player)
		session = sessions[player]
	end
	session.Settings = SettingsConfig.CloneDefaults()
	session.Dirty = true
	session.Revision += 1
	publishAttributes(player, session.Settings)
	event:FireClient(player, {
		Action = "UpdatedAll",
		Settings = SettingsConfig.Sanitize(session.Settings),
		Revision = session.Revision,
	})
	scheduleSave(player)
	return {
		Success = true,
		Message = "Configurações restauradas.",
		Snapshot = snapshot(player),
	}
end

local function handle(player, action, payload)
	if action == "Get" then
		return {
			Success = true,
			Snapshot = snapshot(player),
		}
	elseif action == "Set" and type(payload) == "table" then
		return setOne(player, payload.Key, payload.Value)
	elseif action == "Reset" then
		return reset(player)
	elseif action == "SaveNow" then
		local saved = save(player, true)
		return {
			Success = saved == true,
			Message = saved and "Preferências salvas." or "Não foi possível salvar agora.",
			Snapshot = snapshot(player),
		}
	end
	return {
		Success = false,
		Message = "Ação inválida.",
		Snapshot = snapshot(player),
	}
end

local function setupPlayer(player)
	task.spawn(function()
		load(player)
	end)
end

function SettingsPersistenceService.Start(label)
	if started then
		return true
	end
	started = true
	placeLabel = tostring(label or "Unknown")

	request = RemoteRegistry.Get("Settings", "Request", "RemoteFunction")
	event = RemoteRegistry.Get("Settings", "Event", "RemoteEvent")
	request.OnServerInvoke = handle

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		sessions[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			save(player, true)
		end
	end)

	workspace:SetAttribute("SkySettingsPersistenceReady", true)
	workspace:SetAttribute("SkySettingsPersistenceVersion", SettingsConfig.DataStoreVersion)
	workspace:SetAttribute("SkySettingsPersistencePlace", placeLabel)
	return true
end

return SettingsPersistenceService
