local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ObjectiveCatalog = require(script.Parent.ObjectiveCatalog)
local ObjectiveGateService = require(script.Parent.ObjectiveGateService)
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
local rewardPendingRound
local finalRewardCommitted = false
local signalHandler
local lastRejectedAt = setmetatable({}, { __mode = "k" })
local reportedTargetsByEvent = {}

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

local function setSequenceAttributes(state)
	workspace:SetAttribute("DungeonObjectiveSequenceReady", started)
	workspace:SetAttribute("DungeonObjectiveSequenceState", state)
	workspace:SetAttribute("DungeonCurrentObjectiveIsland", currentGlobalIndex)
	workspace:SetAttribute("DungeonCompletedObjectiveCount", completedObjectiveCount())
	workspace:SetAttribute("DungeonRewardPendingRound", rewardPendingRound)
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
	rewardPendingRound = nil
	finalRewardCommitted = false
	reportedTargetsByEvent = {}
	lastRejectedAt = setmetatable({}, { __mode = "k" })
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
	setSequenceAttributes("Stopped")
end

function ObjectiveSequenceService.HandleIslandEntered(player, context)
	if not started or not player or player.Parent ~= Players or type(context) ~= "table" then
		return false, "InvalidRouteEntry"
	end
	if context.IsBossSanctuary == true then
		if finalRewardCommitted then
			return true
		end
		rejectFutureIsland(player, ObjectiveCatalog.Count() + 1, "BossSanctuaryLocked")
		return false, "BossSanctuaryLocked"
	end
	local requestedIndex = math.floor(tonumber(context.GlobalIslandIndex) or 0)
	if requestedIndex < 1 or requestedIndex > ObjectiveCatalog.Count() then
		return false, "InvalidObjectiveIsland"
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
	completedObjectives[currentGlobalIndex] = true
	setIslandObjectiveState(activeContext, activeDefinition, "Completed")
	local result = {
		ObjectiveId = activeDefinition.Id,
		GlobalIslandIndex = currentGlobalIndex,
		RoundIndex = activeDefinition.RoundIndex,
		IsRewardIsland = activeDefinition.IsRewardIsland == true,
		IsFinalObjective = activeDefinition.IsFinalObjective == true,
	}
	if activeDefinition.IsRewardIsland == true then
		rewardPendingRound = activeDefinition.RoundIndex
		setIslandObjectiveState(activeContext, activeDefinition, "RewardPending")
		applyCurrentGate(true, "RoundRewardPending")
		setSequenceAttributes("RoundRewardPending")
		safeCallback("OnRoundRewardPending", result, activeContext, snapshot)
	else
		applyCurrentGate(false, "ObjectiveCompleted")
		setSequenceAttributes("ObjectiveCompleted")
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
	local isFinal = activeDefinition and activeDefinition.IsFinalObjective == true
	if isFinal and not safeCallback("OnFinalRewardCommitted", activeContext, metadata) then
		return false, "FinalRewardContinuationFailed"
	end
	rewardPendingRound = nil
	finalRewardCommitted = isFinal or finalRewardCommitted
	applyCurrentGate(false, isFinal and "BossRouteUnlocked" or "RoundRewardCommitted")
	setIslandObjectiveState(activeContext, activeDefinition, "Completed")
	setSequenceAttributes(isFinal and "FinalRewardCommitted" or "RoundRewardCommitted")
	safeCallback("OnRoundRewardCommitted", roundIndex, isFinal, activeContext, metadata)
	return true, {
		RoundIndex = roundIndex,
		IsFinal = isFinal,
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
		CurrentObjective = activeDefinition and table.clone(activeDefinition) or nil,
		RewardPendingRound = rewardPendingRound,
		FinalRewardCommitted = finalRewardCommitted,
		CompletedCount = completedObjectiveCount(),
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
