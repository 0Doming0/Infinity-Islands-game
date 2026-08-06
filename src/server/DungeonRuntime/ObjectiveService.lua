local Players = game:GetService("Players")

local ObjectiveService = {}

local WAYPOINT_ESCALATION_SECONDS = 60
local STALL_RECOVERY_SECONDS = 120
local WATCHDOG_INTERVAL_SECONDS = 1

local started = false
local generation = 0
local revision = 0
local options = {}
local remoteEvent
local currentObjective
local participants = {}
local exitTarget
local exitApplyCallback
local exitLocked = false

local function now()
	return workspace:GetServerTimeNow()
end

local function normalizeUserId(value)
	local userId = math.floor(tonumber(value) or 0)
	return userId > 0 and userId or nil
end

local function copyMetadata(metadata)
	return type(metadata) == "table" and table.clone(metadata) or nil
end

local function setWorkspaceAttribute(name, value)
	workspace:SetAttribute(name, value)
end

local function participantSnapshot()
	local result = {}
	for userId, record in pairs(participants) do
		table.insert(result, {
			UserId = userId,
			Eligible = record.Eligible == true,
			Progress = record.Progress or 0,
			Completed = record.Completed == true,
			Disconnected = record.Disconnected == true,
		})
	end
	table.sort(result, function(left, right)
		return left.UserId < right.UserId
	end)
	return result
end

local function objectiveSnapshot()
	if not currentObjective then
		return {
			Revision = revision,
			State = "Inactive",
			ExitLocked = exitLocked,
			Participants = participantSnapshot(),
		}
	end
	return {
		Revision = revision,
		State = currentObjective.State,
		Id = currentObjective.Id,
		Type = currentObjective.Type,
		Title = currentObjective.Title,
		Description = currentObjective.Description,
		RoundIndex = currentObjective.RoundIndex,
		IslandIndex = currentObjective.IslandIndex,
		GlobalIslandIndex = currentObjective.GlobalIslandIndex,
		Progress = currentObjective.Progress,
		Target = currentObjective.Target,
		CompletionMode = currentObjective.CompletionMode,
		StartedAt = currentObjective.StartedAt,
		LastProgressAt = currentObjective.LastProgressAt,
		CompletedAt = currentObjective.CompletedAt,
		CompletionReason = currentObjective.CompletionReason,
		WaypointEscalated = currentObjective.WaypointEscalated == true,
		RecoveryCount = currentObjective.RecoveryCount or 0,
		Metadata = copyMetadata(currentObjective.Metadata),
		ExitLocked = exitLocked,
		Participants = participantSnapshot(),
	}
end

local function publish()
	revision += 1
	local snapshot = objectiveSnapshot()
	snapshot.Revision = revision
	setWorkspaceAttribute("DungeonObjectiveRevision", revision)
	if remoteEvent then
		remoteEvent:FireAllClients({
			Action = "ObjectiveSnapshot",
			Objective = snapshot,
		})
	end
	if options.OnSnapshot then
		local ok, errorMessage = pcall(options.OnSnapshot, snapshot)
		if not ok then
			warn("[ObjectiveService] OnSnapshot falhou: " .. tostring(errorMessage))
		end
	end
	return snapshot
end

local function applyExitLocked(locked)
	exitLocked = locked == true
	setWorkspaceAttribute("DungeonObjectiveExitLocked", exitLocked)
	if exitTarget and typeof(exitTarget) == "Instance" and exitTarget.Parent then
		exitTarget:SetAttribute("ObjectiveLocked", exitLocked)
	end
	if exitApplyCallback then
		local ok, errorMessage = pcall(exitApplyCallback, exitLocked, exitTarget)
		if not ok then
			warn("[ObjectiveService] Falha ao aplicar bloqueio da saida: " .. tostring(errorMessage))
		end
	end
end

local function resetParticipantProgress()
	for _, record in pairs(participants) do
		record.Progress = 0
		record.Completed = false
	end
end

local function setObjectiveAttributes(objective)
	setWorkspaceAttribute("DungeonObjectiveState", objective and objective.State or "Inactive")
	setWorkspaceAttribute("DungeonObjectiveId", objective and objective.Id or nil)
	setWorkspaceAttribute("DungeonObjectiveType", objective and objective.Type or nil)
	setWorkspaceAttribute("DungeonObjectiveTitle", objective and objective.Title or nil)
	setWorkspaceAttribute("DungeonObjectiveDescription", objective and objective.Description or nil)
	setWorkspaceAttribute("DungeonObjectiveRoundIndex", objective and objective.RoundIndex or nil)
	setWorkspaceAttribute("DungeonObjectiveIslandIndex", objective and objective.IslandIndex or nil)
	setWorkspaceAttribute("DungeonObjectiveGlobalIslandIndex", objective and objective.GlobalIslandIndex or nil)
	setWorkspaceAttribute("DungeonObjectiveProgress", objective and objective.Progress or 0)
	setWorkspaceAttribute("DungeonObjectiveTarget", objective and objective.Target or 0)
	setWorkspaceAttribute("DungeonObjectiveStartedAt", objective and objective.StartedAt or nil)
	setWorkspaceAttribute("DungeonObjectiveLastProgressAt", objective and objective.LastProgressAt or nil)
	setWorkspaceAttribute("DungeonObjectiveWaypointEscalated", objective and objective.WaypointEscalated == true or false)
	setWorkspaceAttribute("DungeonObjectiveRecoveryCount", objective and objective.RecoveryCount or 0)
end

local function eligibleParticipantCount()
	local count = 0
	for _, record in pairs(participants) do
		if record.Eligible and not record.Disconnected then
			count += 1
		end
	end
	return count
end

local function completedParticipantCount()
	local count = 0
	for _, record in pairs(participants) do
		if record.Eligible and not record.Disconnected and record.Completed then
			count += 1
		end
	end
	return count
end

local function shouldComplete()
	if not currentObjective or currentObjective.State ~= "Active" then
		return false
	end
	if currentObjective.CompletionMode == "AllParticipants" then
		local eligible = eligibleParticipantCount()
		return eligible > 0 and completedParticipantCount() >= eligible
	elseif currentObjective.CompletionMode == "AnyParticipant" then
		return completedParticipantCount() > 0
	end
	return currentObjective.Progress >= currentObjective.Target
end

local function markProgressActivity(metadata)
	if not currentObjective then
		return
	end
	currentObjective.LastProgressAt = now()
	currentObjective.LastProgressMetadata = copyMetadata(metadata)
	currentObjective.WaypointEscalated = false
	setWorkspaceAttribute("DungeonObjectiveLastProgressAt", currentObjective.LastProgressAt)
	setWorkspaceAttribute("DungeonObjectiveWaypointEscalated", false)
end

local function setParticipants(rawUserIds)
	local nextParticipants = {}
	if type(rawUserIds) == "table" then
		for _, rawUserId in ipairs(rawUserIds) do
			local userId = normalizeUserId(rawUserId)
			if userId and not nextParticipants[userId] then
				local previous = participants[userId]
				nextParticipants[userId] = previous or {
					Eligible = true,
					Progress = 0,
					Completed = false,
					Disconnected = Players:GetPlayerByUserId(userId) == nil,
				}
			end
		end
	end
	participants = nextParticipants
end

local function restartCurrentObjective(reason)
	if not currentObjective or currentObjective.State ~= "Active" then
		return false
	end
	currentObjective.Progress = 0
	currentObjective.StartedAt = now()
	currentObjective.LastProgressAt = currentObjective.StartedAt
	currentObjective.WaypointEscalated = false
	currentObjective.RecoveryCount = (currentObjective.RecoveryCount or 0) + 1
	currentObjective.LastRecoveryReason = reason
	resetParticipantProgress()
	applyExitLocked(true)
	setObjectiveAttributes(currentObjective)
	publish()
	return true
end

local function runWatchdog(token)
	task.spawn(function()
		while started and generation == token do
			task.wait(WATCHDOG_INTERVAL_SECONDS)
			local objective = currentObjective
			if not objective or objective.State ~= "Active" then
				continue
			end
			local stalledFor = now() - objective.LastProgressAt
			if stalledFor >= WAYPOINT_ESCALATION_SECONDS and not objective.WaypointEscalated then
				objective.WaypointEscalated = true
				setWorkspaceAttribute("DungeonObjectiveWaypointEscalated", true)
				local snapshot = publish()
				if options.OnWaypointEscalated then
					local ok, errorMessage = pcall(options.OnWaypointEscalated, snapshot)
					if not ok then
						warn("[ObjectiveService] OnWaypointEscalated falhou: " .. tostring(errorMessage))
					end
				end
			end
			if stalledFor >= STALL_RECOVERY_SECONDS then
				local snapshot = objectiveSnapshot()
				local recovered = false
				if objective.Recover then
					local ok, result = pcall(objective.Recover, snapshot)
					if not ok then
						warn("[ObjectiveService] Recuperacao do objetivo falhou: " .. tostring(result))
					else
						recovered = result == true
					end
				end
				if options.OnRecoveryRequested then
					local ok, result = pcall(options.OnRecoveryRequested, snapshot)
					if not ok then
						warn("[ObjectiveService] OnRecoveryRequested falhou: " .. tostring(result))
					elseif result == true then
						recovered = true
					end
				end
				if recovered then
					markProgressActivity({ Reason = "Recovered" })
					objective.RecoveryCount = (objective.RecoveryCount or 0) + 1
					setObjectiveAttributes(objective)
					publish()
				elseif objective.RestartOnStall ~= false then
					restartCurrentObjective("Stalled")
				else
					markProgressActivity({ Reason = "RecoveryDeferred" })
					publish()
				end
			end
		end
	end)
end

function ObjectiveService.Start(startOptions)
	if started then
		return
	end
	started = true
	generation += 1
	options = type(startOptions) == "table" and startOptions or {}
	remoteEvent = options.RemoteEvent
	setParticipants(options.ParticipantUserIds)
	applyExitLocked(false)
	setObjectiveAttributes(nil)
	setWorkspaceAttribute("DungeonObjectiveServiceReady", true)
	publish()
	runWatchdog(generation)
end

function ObjectiveService.Stop()
	if not started then
		return
	end
	started = false
	generation += 1
	currentObjective = nil
	applyExitLocked(false)
	setObjectiveAttributes(nil)
	setWorkspaceAttribute("DungeonObjectiveServiceReady", false)
	publish()
	options = {}
	remoteEvent = nil
end

function ObjectiveService.SetParticipants(rawUserIds)
	setParticipants(rawUserIds)
	publish()
end

function ObjectiveService.SetParticipantConnected(userId, connected)
	userId = normalizeUserId(userId)
	if not userId then
		return false
	end
	local record = participants[userId]
	if not record then
		return false
	end
	record.Disconnected = connected ~= true
	publish()
	if shouldComplete() then
		ObjectiveService.Complete("RemainingParticipantsCompleted")
	end
	return true
end

function ObjectiveService.SetParticipantEligible(userId, eligible)
	userId = normalizeUserId(userId)
	if not userId then
		return false
	end
	local record = participants[userId]
	if not record then
		record = {
			Progress = 0,
			Completed = false,
			Disconnected = Players:GetPlayerByUserId(userId) == nil,
		}
		participants[userId] = record
	end
	record.Eligible = eligible == true
	publish()
	return true
end

function ObjectiveService.SetExitTarget(target, applyCallback)
	if target ~= nil and typeof(target) ~= "Instance" then
		error("SetExitTarget requer Instance ou nil")
	end
	if applyCallback ~= nil and type(applyCallback) ~= "function" then
		error("SetExitTarget requer callback ou nil")
	end
	exitTarget = target
	exitApplyCallback = applyCallback
	applyExitLocked(currentObjective ~= nil and currentObjective.State == "Active")
	publish()
end

function ObjectiveService.SetExitLocked(locked)
	applyExitLocked(locked == true)
	publish()
	return true
end

function ObjectiveService.GetExitTarget()
	return exitTarget
end

function ObjectiveService.SetObjective(definition)
	assert(started, "ObjectiveService precisa ser iniciado")
	assert(type(definition) == "table", "SetObjective requer definicao")
	assert(type(definition.Id) == "string" and definition.Id ~= "", "Objetivo requer Id")
	local target = math.max(1, math.floor(tonumber(definition.Target) or 1))
	local startedAt = now()
	currentObjective = {
		Id = definition.Id,
		Type = type(definition.Type) == "string" and definition.Type or definition.Id,
		Title = type(definition.Title) == "string" and definition.Title or definition.Id,
		Description = type(definition.Description) == "string" and definition.Description or "",
		RoundIndex = math.max(1, math.floor(tonumber(definition.RoundIndex) or 1)),
		IslandIndex = math.max(1, math.floor(tonumber(definition.IslandIndex) or 1)),
		GlobalIslandIndex = math.max(1, math.floor(tonumber(definition.GlobalIslandIndex) or definition.IslandIndex or 1)),
		Progress = math.clamp(math.floor(tonumber(definition.InitialProgress) or 0), 0, target),
		Target = target,
		CompletionMode = definition.CompletionMode == "AllParticipants"
			and "AllParticipants"
			or definition.CompletionMode == "AnyParticipant" and "AnyParticipant"
			or "Collective",
		State = "Active",
		StartedAt = startedAt,
		LastProgressAt = startedAt,
		WaypointEscalated = false,
		RecoveryCount = 0,
		Recover = type(definition.Recover) == "function" and definition.Recover or nil,
		RestartOnStall = definition.RestartOnStall ~= false,
		Metadata = copyMetadata(definition.Metadata),
	}
	resetParticipantProgress()
	applyExitLocked(true)
	setObjectiveAttributes(currentObjective)
	local snapshot = publish()
	if options.OnObjectiveStarted then
		local ok, errorMessage = pcall(options.OnObjectiveStarted, snapshot)
		if not ok then
			warn("[ObjectiveService] OnObjectiveStarted falhou: " .. tostring(errorMessage))
		end
	end
	if shouldComplete() then
		ObjectiveService.Complete("InitialProgress")
	end
	return snapshot
end

function ObjectiveService.AddProgress(amount, sourceUserId, metadata)
	if not currentObjective or currentObjective.State ~= "Active" then
		return false, "NoActiveObjective"
	end
	amount = math.max(0, tonumber(amount) or 0)
	if amount <= 0 then
		return false, "InvalidAmount"
	end
	local userId = normalizeUserId(sourceUserId)
	local record = userId and participants[userId] or nil
	if userId and (not record or not record.Eligible or record.Disconnected) then
		return false, "IneligibleParticipant"
	end
	if currentObjective.CompletionMode == "Collective" then
		currentObjective.Progress = math.min(currentObjective.Target, currentObjective.Progress + amount)
	end
	if record then
		record.Progress = math.min(currentObjective.Target, (record.Progress or 0) + amount)
		record.Completed = record.Progress >= currentObjective.Target
	end
	markProgressActivity(metadata)
	setObjectiveAttributes(currentObjective)
	publish()
	if shouldComplete() then
		ObjectiveService.Complete("ProgressTargetReached")
	end
	return true
end

function ObjectiveService.SetProgress(progress, metadata)
	if not currentObjective or currentObjective.State ~= "Active" then
		return false, "NoActiveObjective"
	end
	progress = math.clamp(tonumber(progress) or 0, 0, currentObjective.Target)
	if progress == currentObjective.Progress then
		return true, "Unchanged"
	end
	currentObjective.Progress = progress
	markProgressActivity(metadata)
	setObjectiveAttributes(currentObjective)
	publish()
	if shouldComplete() then
		ObjectiveService.Complete("ProgressTargetReached")
	end
	return true
end

function ObjectiveService.SetParticipantProgress(userId, progress, metadata)
	if not currentObjective or currentObjective.State ~= "Active" then
		return false, "NoActiveObjective"
	end
	userId = normalizeUserId(userId)
	local record = userId and participants[userId] or nil
	if not record or not record.Eligible or record.Disconnected then
		return false, "IneligibleParticipant"
	end
	record.Progress = math.clamp(tonumber(progress) or 0, 0, currentObjective.Target)
	record.Completed = record.Progress >= currentObjective.Target
	markProgressActivity(metadata)
	setObjectiveAttributes(currentObjective)
	publish()
	if shouldComplete() then
		ObjectiveService.Complete("ParticipantTargetReached")
	end
	return true
end

function ObjectiveService.Restart(reason)
	return restartCurrentObjective(reason or "ManualRestart")
end

function ObjectiveService.Complete(reason)
	if not currentObjective or currentObjective.State ~= "Active" then
		return false
	end
	currentObjective.State = "Completed"
	currentObjective.Progress = currentObjective.Target
	currentObjective.CompletedAt = now()
	currentObjective.CompletionReason = reason or "Completed"
	applyExitLocked(false)
	setObjectiveAttributes(currentObjective)
	local snapshot = publish()
	if options.OnObjectiveCompleted then
		local ok, errorMessage = pcall(options.OnObjectiveCompleted, snapshot)
		if not ok then
			warn("[ObjectiveService] OnObjectiveCompleted falhou: " .. tostring(errorMessage))
		end
	end
	return true
end

function ObjectiveService.Clear(reason)
	if currentObjective then
		currentObjective.ClearReason = reason
	end
	currentObjective = nil
	applyExitLocked(false)
	setObjectiveAttributes(nil)
	publish()
end

function ObjectiveService.GetSnapshot()
	return objectiveSnapshot()
end

function ObjectiveService.IsActive()
	return currentObjective ~= nil and currentObjective.State == "Active"
end

return ObjectiveService
