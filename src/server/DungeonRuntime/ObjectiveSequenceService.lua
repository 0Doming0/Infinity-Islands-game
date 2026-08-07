local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ObjectiveCatalog = require(script.Parent.ObjectiveCatalog)
local ObjectiveGateService = require(script.Parent.ObjectiveGateService)
local DungeonPacingService = require(script.Parent.DungeonPacingService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local ObjectiveSignalBridge = require(script.Parent.ObjectiveSignalBridge)

local ObjectiveSequenceService = {}

local started = false
local options = {}
local partySize = 1
local currentGlobalIndex = 1
local activeDefinition
local activeContext
local completedObjectives = {}
local completedRounds = {}
local highestCompletedRound = 0
local currentRoundIndex = 1
local rewardPendingRound
local finalRewardCommitted = false
local signalHandler
local lastRejectedAt = setmetatable({}, { __mode = "k" })
local reportedTargetsByEvent = {}
local pacingTransitionSerial = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function safeCallback(name, ...)
	local callback = options[name]
	if type(callback) ~= "function" then
		return true
	end
	local ok, result = pcall(callback, ...)
	if not ok then
		warn(string.format("[ObjectiveSequenceService] %s falhou: %s", name, tostring(result)))
		return false
	end
	return result ~= false
end

local function completedObjectiveCount()
	local count = 0
	for _, completed in pairs(completedObjectives) do
		if completed == true then
			count += 1
		end
	end
	return count
end

local function completedRoundCount()
	local count = 0
	for _, completed in pairs(completedRounds) do
		if completed == true then
			count += 1
		end
	end
	return count
end

local function copyCompletedRounds()
	local result = {}
	for roundIndex, completed in pairs(completedRounds) do
		if completed == true then
			result[roundIndex] = true
		end
	end
	return result
end

local function optionalRouteContext(context)
	return type(context) == "table"
		and (context.IsOptionalRoute == true or context.GlobalIslandIndex == nil)
end

local function validateRoundExitContract(context, definition)
	local contextIsExit = context and context.IsRoundExit == true
	local definitionIsExit = definition and definition.IsRewardIsland == true
	if contextIsExit ~= definitionIsExit then
		workspace:SetAttribute("DungeonRoundExitContractError", string.format(
			"Island=%s ContextExit=%s DefinitionExit=%s",
			tostring(context and context.GlobalIslandIndex),
			tostring(contextIsExit),
			tostring(definitionIsExit)
		))
		return false, "RoundExitContractMismatch"
	end
	workspace:SetAttribute("DungeonRoundExitContractError", nil)
	return true
end

local function setSequenceAttributes(state)
	workspace:SetAttribute("DungeonObjectiveSequenceReady", started)
	workspace:SetAttribute("DungeonObjectiveSequenceState", state)
	workspace:SetAttribute("DungeonRoundProgressState", state)
	workspace:SetAttribute("DungeonCurrentObjectiveIsland", currentGlobalIndex)
	workspace:SetAttribute("DungeonCurrentRoundIndex", currentRoundIndex)
	workspace:SetAttribute("DungeonCompletedObjectiveCount", completedObjectiveCount())
	workspace:SetAttribute("DungeonCompletedRoundCount", completedRoundCount())
	workspace:SetAttribute("DungeonHighestCompletedRound", highestCompletedRound)
	workspace:SetAttribute("DungeonRewardPendingRound", rewardPendingRound)
	workspace:SetAttribute("DungeonCurrentIslandIsRoundExit", activeContext and activeContext.IsRoundExit == true or false)
	workspace:SetAttribute(
		"DungeonCurrentRoundExitGlobalIsland",
		activeContext and activeContext.IsRoundExit == true and currentGlobalIndex or nil
	)
	workspace:SetAttribute("DungeonCurrentRoundExitCommitted", completedRounds[currentRoundIndex] == true)
	workspace:SetAttribute("DungeonFinalRewardCommitted", finalRewardCommitted)
end

local function definitionFor(globalIslandIndex)
	return ObjectiveCatalog.GetByGlobalIndex(globalIslandIndex, partySize)
end

local function setIslandObjectiveState(context, definition, state)
	local island = context and context.IslandModel
	local anchor = context and context.ObjectiveAnchor
	for _, instance in ipairs({ island, anchor, context and context.Exit }) do
		if instance and instance.Parent then
			instance:SetAttribute("ObjectiveId", definition and definition.Id or nil)
			instance:SetAttribute("ObjectiveType", definition and definition.Type or nil)
			instance:SetAttribute("ObjectiveTarget", definition and definition.Target or nil)
			instance:SetAttribute("ObjectiveProgressEvent", definition and definition.ProgressEvent or nil)
			instance:SetAttribute("ObjectiveState", state)
		end
	end
	if island and island.Parent then
		island:SetAttribute("ObjectiveCompleted", state == "Completed")
		island:SetAttribute("ObjectiveRewardPending", state == "RewardPending")
	end
end

local function resolveGlobalIslandIndex(payload)
	local direct = math.floor(tonumber(payload.GlobalIslandIndex) or 0)
	if direct > 0 then
		return direct
	end
	local target = payload.Target
	if typeof(target) ~= "Instance" then
		return currentGlobalIndex
	end
	local cursor = target
	while cursor and cursor ~= workspace do
		local value = math.floor(tonumber(cursor:GetAttribute("GlobalIslandIndex")) or 0)
		if value > 0 then
			return value
		end
		cursor = cursor.Parent
	end
	return currentGlobalIndex
end

local function targetRole(payload)
	local role = payload.MonsterRole or payload.ObjectiveRole or payload.TargetRole
	local target = payload.Target
	if not role and typeof(target) == "Instance" then
		role = target:GetAttribute("ObjectiveRole")
			or target:GetAttribute("MonsterRole")
			or target:GetAttribute("MonsterArchetype")
			or target:GetAttribute("CombatRole")
	end
	return role and string.lower(tostring(role)) or nil
end

local function targetIsElite(payload)
	if payload.IsElite ~= nil then
		return payload.IsElite == true
	end
	local target = payload.Target
	return typeof(target) == "Instance" and target:GetAttribute("IsElite") == true
end

local function targetWasReported(eventName, target)
	if typeof(target) ~= "Instance" then
		return false
	end
	local bucket = reportedTargetsByEvent[eventName]
	return bucket ~= nil and bucket[target] == true
end

local function markTargetReported(eventName, target)
	if typeof(target) ~= "Instance" then
		return
	end
	local bucket = reportedTargetsByEvent[eventName]
	if not bucket then
		bucket = setmetatable({}, { __mode = "k" })
		reportedTargetsByEvent[eventName] = bucket
	end
	bucket[target] = true
end

local function eventMatchesDefinition(eventName, payload, definition)
	if eventName ~= definition.ProgressEvent then
		return false, "WrongProgressEvent"
	end
	if resolveGlobalIslandIndex(payload) ~= currentGlobalIndex then
		return false, "WrongIsland"
	end
	if definition.RequiredRole then
		local required = string.lower(definition.RequiredRole)
		if targetRole(payload) ~= required then
			return false, "WrongTargetRole"
		end
	end
	if definition.RequireElite == true and not targetIsElite(payload) then
		return false, "TargetNotElite"
	end
	if definition.RequiredTargetAttribute then
		local target = payload.Target
		if typeof(target) ~= "Instance"
			or target:GetAttribute(definition.RequiredTargetAttribute) ~= true
		then
			return false, "WrongMarkedTarget"
		end
	end
	if eventName == "EnemyDefeated" or eventName == "NestDestroyed" then
		if targetWasReported(eventName, payload.Target) then
			return false, "DuplicateTargetEvent"
		end
	end
	return true
end

local function handleObjectiveSignal(eventName, payload)
	if not started or not activeDefinition or not ObjectiveService.IsActive() then
		return false, "NoActiveSequenceObjective"
	end
	local matches, reason = eventMatchesDefinition(eventName, payload, activeDefinition)
	if not matches then
		return false, reason
	end
	local amount = math.max(0, tonumber(payload.Amount) or 1)
	if amount <= 0 then
		return false, "InvalidProgressAmount"
	end
	local accepted, reason = ObjectiveService.AddProgress(amount, payload.SourceUserId, {
		EventName = eventName,
		TargetName = typeof(payload.Target) == "Instance" and payload.Target.Name or nil,
		GlobalIslandIndex = currentGlobalIndex,
		ObjectiveId = activeDefinition.Id,
		ReportedAt = payload.ReportedAt,
	})
	if accepted and (eventName == "EnemyDefeated" or eventName == "NestDestroyed") then
		markTargetReported(eventName, payload.Target)
	end
	return accepted, reason
end

local function applyCurrentGate(locked, reason)
	if not activeContext then
		return false
	end
	ObjectiveService.SetExitLocked(locked)
	return ObjectiveGateService.Apply(activeContext, locked, reason)
end

local function currentSafeSpawn()
	if activeContext and activeContext.SafeSpawn and activeContext.SafeSpawn.Parent then
		return activeContext.SafeSpawn
	end
	if type(options.GetIslandContext) == "function" then
		local context = options.GetIslandContext(currentGlobalIndex)
		return context and context.SafeSpawn
	end
	return nil
end

local function rejectFutureIsland(player, requestedIndex, reason)
	local timestamp = now()
	if timestamp - (lastRejectedAt[player] or 0) < 0.75 then
		return
	end
	lastRejectedAt[player] = timestamp
	player:SetAttribute("DungeonRouteRejectedReason", reason)
	player:SetAttribute("DungeonRouteRejectedIsland", requestedIndex)
	player:SetAttribute("DungeonRouteRejectedAt", timestamp)
	local safeSpawn = currentSafeSpawn()
	local character = player.Character
	if safeSpawn and character and character.Parent then
		task.defer(function()
			if character.Parent and safeSpawn.Parent then
				character:PivotTo(safeSpawn.CFrame * CFrame.new(0, 3, 0))
			end
		end)
	end
	safeCallback("OnRouteRejected", player, requestedIndex, reason, currentGlobalIndex)
end

local function startObjective(context)
	local globalIndex = context and math.floor(tonumber(context.GlobalIslandIndex) or 0) or 0
	local definition = definitionFor(globalIndex)
	if not definition then
		return false, "ObjectiveDefinitionMissing"
	end
	currentGlobalIndex = globalIndex
	currentRoundIndex = definition.RoundIndex
	activeDefinition = definition
	activeContext = context
	reportedTargetsByEvent = {}
	ObjectiveGateService.Apply(context, true, "ObjectiveActive")
	ObjectiveService.SetExitTarget(context.Exit, function(locked)
		ObjectiveGateService.Apply(context, locked, locked and "ObjectiveActive" or "ObjectiveCompleted")
	end)
	setIslandObjectiveState(context, definition, "Active")
	if context.ObjectiveAnchor then
		workspace:SetAttribute("DungeonObjectiveWaypointPosition", context.ObjectiveAnchor.Position)
		workspace:SetAttribute("DungeonObjectiveWaypointTarget", context.ObjectiveAnchor:GetFullName())
	end
	if type(options.RequestRouteThrough) == "function" then
		options.RequestRouteThrough(math.min(ObjectiveCatalog.Count(), globalIndex + 3))
	end
	setSequenceAttributes("ObjectiveActive")
	local snapshot = ObjectiveService.SetObjective(definition)
	pacingTransitionSerial += 1
	safeCallback("OnObjectiveStarted", definition, context, snapshot)
	return true, snapshot
end

local function contextForIndex(index)
	if type(options.GetIslandContext) ~= "function" then
		return nil
	end
	return options.GetIslandContext(index)
end

function ObjectiveSequenceService.Start(startOptions)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	partySize = math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, 4)
	currentGlobalIndex = 1
	activeDefinition = nil
	activeContext = nil
	completedObjectives = {}
	completedRounds = {}
	highestCompletedRound = 0
	currentRoundIndex = 1
	rewardPendingRound = nil
	finalRewardCommitted = false
	reportedTargetsByEvent = {}
	lastRejectedAt = setmetatable({}, { __mode = "k" })
	pacingTransitionSerial += 1
	signalHandler = function(eventName, payload)
		return handleObjectiveSignal(eventName, payload)
	end
	ObjectiveSignalBridge.Bind(signalHandler)
	setSequenceAttributes("WaitingForFirstIsland")
end

function ObjectiveSequenceService.Stop()
	if not started then
		return
	end
	if activeContext then
		ObjectiveGateService.Apply(activeContext, false, "SequenceStopped")
	end
	ObjectiveSignalBridge.Unbind(signalHandler)
	started = false
	options = {}
	activeDefinition = nil
	activeContext = nil
	rewardPendingRound = nil
	signalHandler = nil
	pacingTransitionSerial += 1
	setSequenceAttributes("Stopped")
end

function ObjectiveSequenceService.HandleIslandEntered(player, context)
	if not started or not player or player.Parent ~= Players or type(context) ~= "table" then
		return false, "InvalidRouteEntry"
	end
	if optionalRouteContext(context) then
		player:SetAttribute("DungeonOptionalIslandKey", context.Key)
		player:SetAttribute("DungeonOptionalIslandRound", context.RoundIndex)
		player:SetAttribute("DungeonOptionalIslandVisitedAt", now())
		return true, "OptionalRouteExploration"
	end
	if context.IsBossSanctuary == true then
		if finalRewardCommitted and completedRounds[highestCompletedRound] == true then
			return true
		end
		rejectFutureIsland(player, ObjectiveCatalog.Count() + 1, "BossSanctuaryLocked")
		return false, "BossSanctuaryLocked"
	end

	local requestedIndex = math.floor(tonumber(context.GlobalIslandIndex) or 0)
	if requestedIndex < 1 or requestedIndex > ObjectiveCatalog.Count() then
		return false, "InvalidObjectiveIsland"
	end
	local requestedDefinition = definitionFor(requestedIndex)
	if not requestedDefinition then
		return false, "ObjectiveDefinitionMissing"
	end
	local contractValid, contractError = validateRoundExitContract(context, requestedDefinition)
	if not contractValid then
		rejectFutureIsland(player, requestedIndex, contractError)
		return false, contractError
	end

	local requestedRound = math.floor(tonumber(requestedDefinition.RoundIndex) or 0)
	if requestedRound > currentRoundIndex then
		if requestedRound > currentRoundIndex + 1 then
			rejectFutureIsland(player, requestedIndex, "RoundSequenceSkipped")
			return false, "RoundSequenceSkipped"
		end
		if completedRounds[currentRoundIndex] ~= true then
			rejectFutureIsland(player, requestedIndex, "RoundExitIncomplete")
			return false, "RoundExitIncomplete"
		end
		currentRoundIndex = requestedRound
	elseif requestedRound < currentRoundIndex then
		return true, "PreviousRoundBacktrackingAllowed"
	end

	if requestedIndex < currentGlobalIndex then
		return true, "BacktrackingAllowed"
	end
	if rewardPendingRound and requestedIndex > currentGlobalIndex then
		rejectFutureIsland(player, requestedIndex, "RoundRewardPending")
		return false, "RoundRewardPending"
	end
	if requestedIndex > currentGlobalIndex then
		if not completedObjectives[currentGlobalIndex] then
			rejectFutureIsland(player, requestedIndex, "PreviousObjectiveIncomplete")
			return false, "PreviousObjectiveIncomplete"
		end
		if requestedIndex > currentGlobalIndex + 1 then
			rejectFutureIsland(player, requestedIndex, "ObjectiveSequenceSkipped")
			return false, "ObjectiveSequenceSkipped"
		end
	end
	if completedObjectives[requestedIndex] then
		return true, "ObjectiveAlreadyCompleted"
	end
	local snapshot = ObjectiveService.GetSnapshot()
	if requestedIndex == currentGlobalIndex
		and snapshot.State == "Active"
		and activeDefinition
		and snapshot.Id == activeDefinition.Id
	then
		return true, "ObjectiveAlreadyActive"
	end
	return startObjective(context)
end

function ObjectiveSequenceService.HandleObjectiveCompleted(snapshot)
	if not started or not activeDefinition or not snapshot or snapshot.Id ~= activeDefinition.Id then
		return nil, "ObjectiveCompletionOutOfSequence"
	end
	local contractValid, contractError = validateRoundExitContract(activeContext, activeDefinition)
	if not contractValid then
		applyCurrentGate(true, contractError)
		setSequenceAttributes("RoundExitContractError")
		return nil, contractError
	end

	completedObjectives[currentGlobalIndex] = true
	setIslandObjectiveState(activeContext, activeDefinition, "Completed")
	if type(options.RequestRouteThrough) == "function" then
		local requestedThrough = math.min(ObjectiveCatalog.Count(), currentGlobalIndex + 3)
		options.RequestRouteThrough(requestedThrough)
		workspace:SetAttribute("DungeonObjectiveRouteLookaheadPolicy", "ObjectiveCompletionLookaheadV1")
		workspace:SetAttribute("DungeonObjectiveRouteRequestedThrough", requestedThrough)
	end
	local isRoundExit = activeContext and activeContext.IsRoundExit == true
	local result = {
		ObjectiveId = activeDefinition.Id,
		GlobalIslandIndex = currentGlobalIndex,
		RoundIndex = activeDefinition.RoundIndex,
		IsRewardIsland = activeDefinition.IsRewardIsland == true,
		IsRoundExit = isRoundExit,
		RoundCompleted = false,
		IsFinalObjective = activeDefinition.IsFinalObjective == true,
	}
	if isRoundExit then
		rewardPendingRound = activeDefinition.RoundIndex
		setIslandObjectiveState(activeContext, activeDefinition, "RewardPending")
		applyCurrentGate(true, "RoundExitRewardPending")
		setSequenceAttributes("RoundExitRewardPending")
		DungeonPacingService.BeginRewardWindow(result, activeContext)
		safeCallback("OnRoundRewardPending", result, activeContext, snapshot)
	else
		pacingTransitionSerial += 1
		local token = pacingTransitionSerial
		local completionContext = activeContext
		local completionGlobalIndex = currentGlobalIndex
		applyCurrentGate(true, "ObjectiveCompletionPause")
		setSequenceAttributes("ObjectiveCompletionPause")
		local delaySeconds = DungeonPacingService.BeginObjectiveCompletion(result, completionContext)
		task.delay(delaySeconds, function()
			if not started
				or token ~= pacingTransitionSerial
				or activeContext ~= completionContext
				or currentGlobalIndex ~= completionGlobalIndex
				or completedObjectives[completionGlobalIndex] ~= true
			then
				return
			end
			applyCurrentGate(false, "ObjectiveCompletedWithinRound")
			setSequenceAttributes("ObjectiveCompletedWithinRound")
			DungeonPacingService.FinishObjectiveCompletion(result, completionContext)
		end)
	end
	safeCallback("OnObjectiveCompleted", result, activeContext, snapshot)
	return result
end

function ObjectiveSequenceService.CommitRoundReward(roundIndex, metadata)
	if not started or not rewardPendingRound then
		return false, "NoRoundRewardPending"
	end
	roundIndex = math.floor(tonumber(roundIndex) or 0)
	if roundIndex ~= rewardPendingRound then
		return false, "WrongRewardRound"
	end
	if not activeContext or activeContext.IsRoundExit ~= true then
		return false, "RewardOutsideRoundExit"
	end
	if not activeDefinition
		or activeDefinition.RoundIndex ~= roundIndex
		or activeDefinition.IsRewardIsland ~= true
	then
		return false, "RoundExitDefinitionMismatch"
	end

	local isFinal = activeDefinition.IsFinalObjective == true
	if isFinal and not safeCallback("OnFinalRewardCommitted", activeContext, metadata) then
		return false, "FinalRewardContinuationFailed"
	end

	completedRounds[roundIndex] = true
	highestCompletedRound = math.max(highestCompletedRound, roundIndex)
	currentRoundIndex = roundIndex
	rewardPendingRound = nil
	finalRewardCommitted = isFinal or finalRewardCommitted
	if type(options.RequestRouteThrough) == "function" then
		local requestedThrough = isFinal
			and ObjectiveCatalog.Count()
			or math.min(ObjectiveCatalog.Count(), currentGlobalIndex + 4)
		options.RequestRouteThrough(requestedThrough)
		workspace:SetAttribute("DungeonRoundRouteRequestedThrough", requestedThrough)
	end
	pacingTransitionSerial += 1
	local token = pacingTransitionSerial
	local transitionContext = activeContext
	applyCurrentGate(true, isFinal and "BossTransition" or "RoundTransition")
	setIslandObjectiveState(activeContext, activeDefinition, "Completed")
	setSequenceAttributes(isFinal and "FinalRoundExitTransition" or "RoundExitTransition")
	local delaySeconds = DungeonPacingService.BeginRoundTransition(roundIndex, isFinal, transitionContext)
	safeCallback("OnRoundRewardCommitted", roundIndex, isFinal, activeContext, metadata)
	task.delay(delaySeconds, function()
		if not started or token ~= pacingTransitionSerial or activeContext ~= transitionContext then
			return
		end
		applyCurrentGate(false, isFinal and "BossRouteUnlocked" or "NextRoundUnlocked")
		setSequenceAttributes(isFinal and "FinalRoundExitCommitted" or "RoundExitCommitted")
		DungeonPacingService.FinishRoundTransition(roundIndex, isFinal, transitionContext)
	end)
	return true, {
		RoundIndex = roundIndex,
		RoundCompleted = true,
		HighestCompletedRound = highestCompletedRound,
		NextRoundIndex = isFinal and nil or roundIndex + 1,
		IsFinal = isFinal,
		TransitionSeconds = delaySeconds,
		GlobalIslandIndex = currentGlobalIndex,
	}
end

function ObjectiveSequenceService.EscalateWaypoint()
	if not activeDefinition or not activeContext then
		return false
	end
	local selected
	for _, target in ipairs(CollectionService:GetTagged("DungeonObjectiveTarget")) do
		if target.Parent
			and (target:GetAttribute("ObjectiveId") == nil
				or target:GetAttribute("ObjectiveId") == activeDefinition.Id)
			and math.floor(tonumber(target:GetAttribute("GlobalIslandIndex")) or currentGlobalIndex)
				== currentGlobalIndex
			and target:GetAttribute("ObjectiveTargetCompleted") ~= true
		then
			selected = target
			break
		end
	end
	selected = selected or activeContext.ObjectiveAnchor
	if not selected then
		return false
	end
	local position
	if selected:IsA("BasePart") then
		position = selected.Position
	elseif selected:IsA("Model") then
		position = selected:GetPivot().Position
	else
		position = activeContext.ObjectiveAnchor and activeContext.ObjectiveAnchor.Position
	end
	if not position then
		return false
	end
	workspace:SetAttribute("DungeonObjectiveWaypointPosition", position)
	workspace:SetAttribute("DungeonObjectiveWaypointTarget", selected:GetFullName())
	workspace:SetAttribute(
		"DungeonObjectiveWaypointSerial",
		(tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
	)
	selected:SetAttribute("ObjectiveWaypointEscalated", true)
	return true
end

function ObjectiveSequenceService.RecoverCurrentObjective(snapshot)
	if not activeDefinition or not activeContext then
		return false
	end
	workspace:SetAttribute("DungeonObjectiveRecoveryProfile", activeDefinition.SpawnProfile)
	workspace:SetAttribute("DungeonObjectiveRecoveryIsland", currentGlobalIndex)
	return safeCallback("OnRecoveryRequested", activeDefinition, activeContext, snapshot)
end

function ObjectiveSequenceService.Report(eventName, payload)
	return ObjectiveSignalBridge.Report(eventName, payload)
end

function ObjectiveSequenceService.GetSnapshot()
	return {
		Started = started,
		State = workspace:GetAttribute("DungeonObjectiveSequenceState"),
		CurrentGlobalIslandIndex = currentGlobalIndex,
		CurrentRoundIndex = currentRoundIndex,
		HighestCompletedRound = highestCompletedRound,
		CompletedRounds = copyCompletedRounds(),
		CurrentObjective = activeDefinition and table.clone(activeDefinition) or nil,
		CurrentIslandIsRoundExit = activeContext and activeContext.IsRoundExit == true or false,
		RewardPendingRound = rewardPendingRound,
		FinalRewardCommitted = finalRewardCommitted,
		CompletedCount = completedObjectiveCount(),
		CompletedRoundCount = completedRoundCount(),
		IslandContext = activeContext,
	}
end

function ObjectiveSequenceService.GetCurrentDefinition()
	return activeDefinition and table.clone(activeDefinition) or nil
end

function ObjectiveSequenceService.GetCurrentContext()
	return activeContext or contextForIndex(currentGlobalIndex)
end

return ObjectiveSequenceService
