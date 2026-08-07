local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local DungeonReturnService = {}

local MAX_AUTOMATIC_RETRIES = 4
local RETRY_DELAYS = { 2, 4, 7, 10 }
local TELEPORT_WATCHDOG_SECONDS = 15
local MANUAL_REQUEST_COOLDOWN = 1.25

local started = false
local activeSession
local remoteEvent
local lobbyPlaceId = 0
local dungeonPlaceId = 0
local onReturning
local onClosed
local playerStates = {}
local participantSet = {}
local returnLoopToken = 0
local returningPublished = false

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function copyUserIds(raw)
	local result = {}
	local seen = {}
	for _, value in ipairs(type(raw) == "table" and raw or {}) do
		local userId = math.floor(tonumber(value) or 0)
		if userId > 0 and not seen[userId] then
			seen[userId] = true
			table.insert(result, userId)
		end
	end
	return result, seen
end

local function getPlayer(userId)
	return Players:GetPlayerByUserId(userId)
end

local function countStates()
	local counts = {
		Pending = 0,
		Teleporting = 0,
		RetryScheduled = 0,
		Failed = 0,
		Left = 0,
		StudioPreview = 0,
		ConfigurationError = 0,
	}
	for _, record in pairs(playerStates) do
		local stateName = tostring(record.State or "Pending")
		counts[stateName] = (counts[stateName] or 0) + 1
	end
	return counts
end

local function publishWorkspaceState()
	local counts = countStates()
	workspace:SetAttribute("DungeonReturnState", activeSession and "Active" or "Idle")
	workspace:SetAttribute("DungeonReturnAt", activeSession and activeSession.ReturnAt or nil)
	workspace:SetAttribute("DungeonReturnPendingCount", counts.Pending + counts.RetryScheduled)
	workspace:SetAttribute("DungeonReturnTeleportingCount", counts.Teleporting)
	workspace:SetAttribute("DungeonReturnFailedCount", counts.Failed + counts.ConfigurationError)
	workspace:SetAttribute("DungeonReturnLeftCount", counts.Left)
	workspace:SetAttribute("DungeonReturnStudioPreviewCount", counts.StudioPreview)
end

local function publicSnapshot(record)
	return {
		Action = "ReturnStatus",
		State = record.State,
		Attempts = record.Attempts,
		AutomaticRetries = record.AutomaticRetries,
		LastError = record.LastError,
		LastTeleportResult = record.LastTeleportResult,
		CanRetry = record.State == "Failed",
		ReturnAt = activeSession and activeSession.ReturnAt or nil,
		LobbyPlaceId = lobbyPlaceId,
		DungeonPlaceId = dungeonPlaceId,
		Result = activeSession and activeSession.Result or nil,
		ResultSaved = activeSession and activeSession.ResultSaved == true or false,
		ManualReturnAt = activeSession and activeSession.ManualReturnAt or nil,
		Reason = record.LastReason,
	}
end

local function publishToPlayer(record)
	local player = getPlayer(record.UserId)
	if player and remoteEvent then
		player:SetAttribute("DungeonReturnState", record.State)
		player:SetAttribute("DungeonReturnAttempts", record.Attempts)
		player:SetAttribute("DungeonReturnError", record.LastError)
		remoteEvent:FireClient(player, publicSnapshot(record))
	end
	publishWorkspaceState()
end

local function setState(record, stateName, reason, errorMessage, teleportResult)
	record.State = stateName
	record.LastReason = tostring(reason or "")
	record.LastError = errorMessage and tostring(errorMessage) or nil
	record.LastTeleportResult = teleportResult and tostring(teleportResult) or nil
	publishToPlayer(record)
end

local function allConnectedPlayersDeparted()
	if not activeSession then
		return false
	end
	for userId in pairs(participantSet) do
		if getPlayer(userId) then
			return false
		end
	end
	return true
end

local function closeIfEmpty()
	if not activeSession or activeSession.Closed or not allConnectedPlayersDeparted() then
		return false
	end
	activeSession.Closed = true
	workspace:SetAttribute("DungeonReturnPending", false)
	workspace:SetAttribute("DungeonSessionClosed", true)
	workspace:SetAttribute("DungeonSessionClosedAt", serverTime())
	if onClosed then
		task.spawn(onClosed, activeSession.Result)
	end
	return true
end

local function publishReturning(reason)
	if returningPublished then
		return
	end
	returningPublished = true
	workspace:SetAttribute("DungeonReturnPending", true)
	workspace:SetAttribute("DungeonReturnStartedAt", serverTime())
	if onReturning then
		task.spawn(onReturning, tostring(reason or "AutoCountdown"))
	end
end

local function buildTeleportOptions(record)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		ReturnVersion = 1,
		ReturnReason = activeSession.Result,
		DungeonResult = activeSession.Result,
		PhaseId = activeSession.PhaseId,
		SessionId = activeSession.SessionId,
		ResultSaved = activeSession.ResultSaved == true,
		CompletedAt = activeSession.CompletedAt,
		ResultId = activeSession.ResultIds and activeSession.ResultIds[record.UserId] or nil,
	})
	return options
end

local attemptTeleport
local attemptReplay

local function replayTeleportOptions(player)
	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ShouldReserveServer = true
	teleportOptions:SetTeleportData({
		Version = 1,
		SessionId = "replay-" .. HttpService:GenerateGUID(false),
		PhaseId = activeSession.PhaseId,
		PartySize = 1,
		LeaderUserId = player.UserId,
		PartyUserIds = { player.UserId },
		Seed = Random.new():NextInteger(1, 2147483646),
		ReplayOfSessionId = activeSession.SessionId,
		ReplayRequested = true,
		ReplayDepth = math.max(
			1,
			math.floor(tonumber(activeSession.ReplayDepth) or 0) + 1
		),
	})
	return teleportOptions
end

local function publishReplayFailed(record, reason, errorMessage)
	local player = getPlayer(record.UserId)
	setState(record, "Pending", reason or "ReplayFailed", errorMessage)
	record.LastTargetPlaceId = nil
	if player and remoteEvent then
		remoteEvent:FireClient(player, {
			Action = "ReplayFailed",
			Reason = reason or "ReplayFailed",
			Error = errorMessage and tostring(errorMessage) or nil,
		})
	end
end

attemptReplay = function(record)
	if not activeSession or not participantSet[record.UserId] then
		return false, "ReturnSessionInactive"
	end
	local player = getPlayer(record.UserId)
	if not player then
		return false, "PlayerUnavailable"
	end
	if dungeonPlaceId <= 0 then
		publishReplayFailed(record, "DungeonPlaceIdNotConfigured", "DungeonPlaceIdNotConfigured")
		return false, "DungeonPlaceIdNotConfigured"
	end
	if record.State == "Teleporting" then
		publishToPlayer(record)
		return false, "AlreadyTeleporting"
	end
	if RunService:IsStudio() then
		publishReplayFailed(record, "ReplayUnavailableInStudio", "TeleportUnavailableInStudio")
		return false, "TeleportUnavailableInStudio"
	end

	record.RetryToken += 1
	local token = record.RetryToken
	record.LastTargetPlaceId = dungeonPlaceId
	record.LastManualRequestAt = serverTime()
	setState(record, "Teleporting", "ReplayRequest")
	player:SetAttribute("DungeonReplayRequested", true)
	player:SetAttribute("DungeonReplayRequestedAt", serverTime())
	workspace:SetAttribute("DungeonLastReplayRequestedUserId", player.UserId)
	workspace:SetAttribute("DungeonLastReplayRequestedAt", serverTime())

	local teleportOptions = replayTeleportOptions(player)
	local success, resultOrError = pcall(function()
		return TeleportService:TeleportAsync(dungeonPlaceId, { player }, teleportOptions)
	end)
	if not success then
		publishReplayFailed(record, "ReplayTeleportAsyncError", resultOrError)
		return false, tostring(resultOrError)
	end

	task.delay(TELEPORT_WATCHDOG_SECONDS, function()
		if not activeSession
			or record.RetryToken ~= token
			or record.State ~= "Teleporting"
			or record.LastTargetPlaceId ~= dungeonPlaceId
			or not getPlayer(record.UserId)
		then
			return
		end
		publishReplayFailed(record, "ReplayTeleportWatchdog", "Replay teleport did not remove player")
		if activeSession and serverTime() >= activeSession.ReturnAt then
			task.delay(0.5, function()
				if activeSession
					and getPlayer(record.UserId)
					and record.State == "Pending"
				then
					attemptTeleport(record, "ReplayFallbackLobby")
				end
			end)
		end
	end)
	return true, resultOrError
end

local function scheduleRetry(record, reason, errorMessage, teleportResult, retryOptions)
	if not activeSession or not participantSet[record.UserId] then
		return
	end
	local player = getPlayer(record.UserId)
	if not player then
		setState(record, "Left", "PlayerLeft")
		closeIfEmpty()
		return
	end
	if record.AutomaticRetries >= MAX_AUTOMATIC_RETRIES then
		setState(record, "Failed", reason, errorMessage, teleportResult)
		return
	end

	record.AutomaticRetries += 1
	record.RetryToken += 1
	local token = record.RetryToken
	local delaySeconds = RETRY_DELAYS[record.AutomaticRetries] or RETRY_DELAYS[#RETRY_DELAYS]
	record.RetryOptions = retryOptions
	setState(record, "RetryScheduled", reason, errorMessage, teleportResult)
	if remoteEvent then
		remoteEvent:FireClient(player, {
			Action = "ReturnRetryScheduled",
			DelaySeconds = delaySeconds,
			Attempt = record.AutomaticRetries,
			LastError = record.LastError,
		})
	end
	task.delay(delaySeconds, function()
		if not activeSession or record.RetryToken ~= token then
			return
		end
		attemptTeleport(record, "AutomaticRetry", record.RetryOptions)
	end)
end

attemptTeleport = function(record, reason, suppliedOptions)
	if not activeSession or not participantSet[record.UserId] then
		return false, "ReturnSessionInactive"
	end
	local player = getPlayer(record.UserId)
	if not player then
		setState(record, "Left", "PlayerLeft")
		closeIfEmpty()
		return false, "PlayerUnavailable"
	end
	if record.State == "Teleporting" then
		publishToPlayer(record)
		return false, "AlreadyTeleporting"
	end

	publishReturning(reason)
	record.RetryToken += 1
	record.RetryOptions = nil
	record.LastTargetPlaceId = lobbyPlaceId
	if lobbyPlaceId <= 0 then
		setState(record, "ConfigurationError", reason, "LobbyPlaceIdNotConfigured")
		return false, "LobbyPlaceIdNotConfigured"
	end
	if RunService:IsStudio() then
		setState(record, "StudioPreview", reason, "TeleportUnavailableInStudio")
		return false, "TeleportUnavailableInStudio"
	end

	record.Attempts += 1
	record.LastAttemptAt = serverTime()
	local attemptToken = record.RetryToken
	setState(record, "Teleporting", reason)
	local options = suppliedOptions
	if not options or not options:IsA("TeleportOptions") then
		options = buildTeleportOptions(record)
	end
	local success, resultOrError = pcall(function()
		return TeleportService:TeleportAsync(lobbyPlaceId, { player }, options)
	end)
	if not success then
		scheduleRetry(record, "TeleportAsyncError", resultOrError, nil, options)
		return false, tostring(resultOrError)
	end

	task.delay(TELEPORT_WATCHDOG_SECONDS, function()
		if not activeSession
			or record.RetryToken ~= attemptToken
			or record.State ~= "Teleporting"
			or not getPlayer(record.UserId)
		then
			return
		end
		scheduleRetry(record, "TeleportWatchdog", "Teleport did not remove player", nil, options)
	end)
	return true, resultOrError
end

local function requestAll(reason)
	if not activeSession then
		return
	end
	publishReturning(reason)
	local connectedCount = 0
	for _, userId in ipairs(activeSession.ParticipantUserIds) do
		local record = playerStates[userId]
		if record and getPlayer(userId) then
			connectedCount += 1
			task.spawn(attemptTeleport, record, reason or "AutoCountdown")
		end
	end
	if connectedCount == 0 then
		closeIfEmpty()
	end
end

function DungeonReturnService.Start(options)
	if started then
		return
	end
	started = true
	options = type(options) == "table" and options or {}
	remoteEvent = options.RemoteEvent
	lobbyPlaceId = math.floor(tonumber(options.LobbyPlaceId) or 0)
	dungeonPlaceId = math.floor(tonumber(options.DungeonPlaceId) or 0)
	onReturning = options.OnReturning
	onClosed = options.OnClosed

	if remoteEvent then
		remoteEvent.OnServerEvent:Connect(function(player, request)
			if type(request) ~= "table" then
				return
			end
			local action = tostring(request.Action or "")
			if action ~= "ReturnToLobby" and action ~= "ReplayDungeon" then
				return
			end
			local record = playerStates[player.UserId]
			if not activeSession or not record or not participantSet[player.UserId] then
				return
			end
			local now = serverTime()
			if now - (record.LastManualRequestAt or 0) < MANUAL_REQUEST_COOLDOWN then
				return
			end
			record.LastManualRequestAt = now
			if record.State == "Teleporting" then
				publishToPlayer(record)
				return
			end
			if activeSession.ResultSaved ~= true
				and now < (tonumber(activeSession.ManualReturnAt) or 0)
			then
				remoteEvent:FireClient(player, {
					Action = action == "ReplayDungeon" and "ReplayBlocked" or "ReturnBlocked",
					Reason = "WaitingForResultSave",
					AvailableAt = activeSession.ManualReturnAt,
				})
				publishToPlayer(record)
				return
			end
			if record.State == "Failed" then
				record.AutomaticRetries = 0
			end
			if action == "ReplayDungeon" then
				task.spawn(attemptReplay, record)
			else
				task.spawn(attemptTeleport, record, "ManualRequest")
			end
		end)
	end

	TeleportService.TeleportInitFailed:Connect(function(
		player,
		teleportResult,
		errorMessage,
		targetPlaceId,
		teleportOptions
	)
		if not activeSession
			or not player
			or not participantSet[player.UserId]
		then
			return
		end
		local record = playerStates[player.UserId]
		if not record then
			return
		end
		if targetPlaceId == dungeonPlaceId and record.LastTargetPlaceId == dungeonPlaceId then
			record.RetryToken += 1
			publishReplayFailed(record, "ReplayTeleportInitFailed", errorMessage or teleportResult)
			if serverTime() >= activeSession.ReturnAt then
				task.delay(0.5, function()
					if activeSession and getPlayer(record.UserId) and record.State == "Pending" then
						attemptTeleport(record, "ReplayFallbackLobby")
					end
				end)
			end
			return
		end
		if targetPlaceId ~= lobbyPlaceId then
			return
		end
		scheduleRetry(
			record,
			"TeleportInitFailed",
			errorMessage,
			teleportResult,
			teleportOptions
		)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if not activeSession or not participantSet[player.UserId] then
			return
		end
		local record = playerStates[player.UserId]
		if record then
			record.RetryToken += 1
			setState(record, "Left", "PlayerRemoving")
		end
		task.defer(closeIfEmpty)
	end)
end

function DungeonReturnService.Begin(options)
	assert(started, "DungeonReturnService.Start precisa ser chamado primeiro")
	assert(type(options) == "table", "DungeonReturnService.Begin requer opcoes")
	local sessionId = tostring(options.SessionId or "")
	if sessionId == "" then
		return false, "SessionIdMissing"
	end
	if activeSession and activeSession.SessionId == sessionId then
		return true, DungeonReturnService.GetSnapshot()
	end

	returnLoopToken += 1
	returningPublished = false
	local participantUserIds, set = copyUserIds(options.ParticipantUserIds)
	participantSet = set
	playerStates = {}
	local resultIds = {}
	for userId, resultId in pairs(type(options.ResultIds) == "table" and options.ResultIds or {}) do
		local cleanUserId = math.floor(tonumber(userId) or 0)
		if cleanUserId > 0 and type(resultId) == "string" then
			resultIds[cleanUserId] = resultId
		end
	end
	activeSession = {
		SessionId = sessionId,
		PhaseId = tostring(options.PhaseId or ""),
		Result = tostring(options.Result or "Defeat"),
		ResultSaved = options.ResultSaved == true,
		ReplayDepth = math.max(0, math.floor(tonumber(options.ReplayDepth) or 0)),
		ParticipantUserIds = participantUserIds,
		ReturnAt = math.max(serverTime(), tonumber(options.ReturnAt) or serverTime()),
		ManualReturnAt = math.max(serverTime(), tonumber(options.ManualReturnAt) or serverTime()),
		CompletedAt = math.max(0, math.floor(tonumber(options.CompletedAt) or os.time())),
		ResultIds = resultIds,
		Closed = false,
	}
	for _, userId in ipairs(participantUserIds) do
		playerStates[userId] = {
			UserId = userId,
			State = getPlayer(userId) and "Pending" or "Left",
			Attempts = 0,
			AutomaticRetries = 0,
			RetryToken = 0,
			LastManualRequestAt = 0,
			LastTargetPlaceId = nil,
		}
	end
	workspace:SetAttribute("DungeonReturnPending", true)
	workspace:SetAttribute("DungeonSessionClosed", false)
	workspace:SetAttribute("DungeonReturnError", nil)
	publishWorkspaceState()
	for _, record in pairs(playerStates) do
		publishToPlayer(record)
	end

	local loopToken = returnLoopToken
	task.spawn(function()
		while activeSession and returnLoopToken == loopToken and serverTime() < activeSession.ReturnAt do
			task.wait(0.2)
		end
		if activeSession and returnLoopToken == loopToken then
			requestAll("AutoCountdown")
		end
	end)
	return true, DungeonReturnService.GetSnapshot()
end

function DungeonReturnService.UpdateResultSaved(saved, resultIds)
	if not activeSession then
		return false
	end
	activeSession.ResultSaved = saved == true
	if activeSession.ResultSaved then
		activeSession.ManualReturnAt = serverTime()
	end
	for userId, resultId in pairs(type(resultIds) == "table" and resultIds or {}) do
		local cleanUserId = math.floor(tonumber(userId) or 0)
		if cleanUserId > 0 and type(resultId) == "string" then
			activeSession.ResultIds[cleanUserId] = resultId
		end
	end
	return true
end

function DungeonReturnService.AttachPlayer(player)
	if not activeSession or not player or not participantSet[player.UserId] then
		return false
	end
	local record = playerStates[player.UserId]
	if not record then
		return false
	end
	if record.State == "Left" then
		record.State = "Pending"
	end
	activeSession.Closed = false
	workspace:SetAttribute("DungeonSessionClosed", false)
	workspace:SetAttribute("DungeonReturnPending", true)
	publishToPlayer(record)
	if serverTime() >= activeSession.ReturnAt then
		task.spawn(attemptTeleport, record, "LateJoin")
	end
	return true
end

function DungeonReturnService.RequestPlayer(player, reason)
	local record = player and playerStates[player.UserId]
	if not activeSession or not record then
		return false, "ReturnUnavailable"
	end
	return attemptTeleport(record, reason or "ServerRequest")
end

function DungeonReturnService.RequestAll(reason)
	requestAll(reason or "ServerRequest")
end

function DungeonReturnService.GetSnapshot(playerOrUserId)
	if not activeSession then
		return nil
	end
	local snapshot = {
		SessionId = activeSession.SessionId,
		PhaseId = activeSession.PhaseId,
		Result = activeSession.Result,
		ResultSaved = activeSession.ResultSaved,
		ReplayDepth = activeSession.ReplayDepth,
		ReturnAt = activeSession.ReturnAt,
		ManualReturnAt = activeSession.ManualReturnAt,
		LobbyPlaceId = lobbyPlaceId,
		DungeonPlaceId = dungeonPlaceId,
		Players = {},
	}
	local requestedUserId = typeof(playerOrUserId) == "Instance"
		and playerOrUserId:IsA("Player")
		and playerOrUserId.UserId
		or math.floor(tonumber(playerOrUserId) or 0)
	for userId, record in pairs(playerStates) do
		if requestedUserId == 0 or requestedUserId == userId then
			snapshot.Players[userId] = {
				State = record.State,
				Attempts = record.Attempts,
				AutomaticRetries = record.AutomaticRetries,
				LastError = record.LastError,
			}
		end
	end
	return snapshot
end

function DungeonReturnService.Stop()
	returnLoopToken += 1
	activeSession = nil
	participantSet = {}
	playerStates = {}
	returningPublished = false
	publishWorkspaceState()
end

return DungeonReturnService
