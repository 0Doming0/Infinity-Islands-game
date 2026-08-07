local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PartyService = require(BlockParkour.PartyService)
local PlayerDataService = require(script.Parent.LobbyPlayerDataService)
local TeleportCoordinator = require(script.Parent.TeleportCoordinator)

local PhaseSelectionService = {}
local request
local event
local started = false

local function isLeader(player)
	local leaderUserId = tonumber(player:GetAttribute("PartyLeaderUserId"))
	return not leaderUserId or leaderUserId <= 0 or leaderUserId == player.UserId
end

local function phaseEntries(universeId)
	return PhaseConfig.GetPhasesForUniverse(universeId)
end

local function previousPhaseId(phase)
	if not phase then return nil end
	local entries = phaseEntries(phase.UniverseId)
	local previous
	for _, entry in ipairs(entries) do
		if entry.PhaseId == phase.PhaseId then
			return phase.UnlockAfterPhaseId or (previous and previous.PhaseId) or nil
		end
		previous = entry
	end
	return phase.UnlockAfterPhaseId
end

local function unlockState(player, phase)
	if not phase then
		return false, nil, "Fase inválida."
	end

	local prerequisite = previousPhaseId(phase)
	if not prerequisite then
		return true, nil, nil
	end

	local progress = PlayerDataService.GetPhaseProgress(player, prerequisite)
	if progress and progress.Completions > 0 then
		return true, prerequisite, nil
	end

	local previous = PhaseConfig.Get(prerequisite)
	local previousName = previous and previous.LevelDisplayName or prerequisite
	return false, prerequisite, "Conclua " .. previousName .. " para desbloquear."
end

local function phaseSnapshotFor(player, phaseId)
	local phase = PhaseConfig.Get(phaseId)
	local snapshot = PhaseConfig.ToPublicSnapshot(phaseId)
	if not phase or not snapshot then return nil end

	local progress = PlayerDataService.GetPhaseProgress(player, phaseId)
	local unlocked, prerequisite, lockReason = unlockState(player, phase)

	snapshot.Unlocked = unlocked
	snapshot.UnlockAfterPhaseId = prerequisite
	snapshot.LockReason = lockReason
	snapshot.Completions = progress.Completions
	snapshot.BossDefeated = progress.BossDefeated
	snapshot.BestTime = progress.BestTime
	snapshot.Completed = progress.Completions > 0
	return snapshot
end

local function universeSnapshotFor(player, universeId)
	local universe = PhaseConfig.ToUniverseSnapshot(universeId)
	if not universe then return nil end

	local levels = {}
	local completedCount = 0
	local unlockedCount = 0
	for _, entry in ipairs(phaseEntries(universeId)) do
		local snapshot = phaseSnapshotFor(player, entry.PhaseId)
		if snapshot then
			table.insert(levels, snapshot)
			if snapshot.Completed then completedCount += 1 end
			if snapshot.Unlocked then unlockedCount += 1 end
		end
	end

	universe.Levels = levels
	universe.CompletedLevels = completedCount
	universe.UnlockedLevels = unlockedCount
	universe.IsLeader = isLeader(player)
	return universe
end

local function allUniverseSnapshots(player)
	local result = {}
	for _, universe in ipairs(PhaseConfig.GetUniversesSorted()) do
		local snapshot = universeSnapshotFor(player, universe.UniverseId)
		if snapshot then table.insert(result, snapshot) end
	end
	return result
end

local function allPhaseSnapshots(player)
	local snapshots = {}
	for _, entry in ipairs(PhaseConfig.GetAllSorted()) do
		local snapshot = phaseSnapshotFor(player, entry.PhaseId)
		if snapshot then table.insert(snapshots, snapshot) end
	end
	return snapshots
end

function PhaseSelectionService.OpenUniverse(player, universeId, selectedPhaseId)
	local snapshot = universeSnapshotFor(player, universeId)
	if not snapshot then return false end
	event:FireClient(player, {
		Action = "OpenUniverse",
		Universe = snapshot,
		SelectedPhaseId = selectedPhaseId,
		IsLeader = isLeader(player),
	})
	return true
end

function PhaseSelectionService.Open(player, phaseId)
	local phase = PhaseConfig.Get(phaseId)
	if not phase then return false end
	return PhaseSelectionService.OpenUniverse(player, phase.UniverseId, phaseId)
end

local function lockedResult(player, phaseId)
	local phase = PhaseConfig.Get(phaseId)
	local unlocked, prerequisite, reason = unlockState(player, phase)
	if unlocked then return nil end
	return {
		Success = false,
		Message = reason or "Nível bloqueado.",
		Phase = phaseSnapshotFor(player, phaseId),
		UnlockAfterPhaseId = prerequisite,
	}
end

local function handle(player, action, payload)
	PlayerDataService.Load(player)

	local phaseId = type(payload) == "table" and payload.PhaseId or nil
	local universeId = type(payload) == "table" and payload.UniverseId or nil

	if action == "GetPhase" then
		local snapshot = phaseSnapshotFor(player, phaseId)
		return { Success = snapshot ~= nil, Phase = snapshot }
	elseif action == "GetPhases" then
		return { Success = true, Phases = allPhaseSnapshots(player) }
	elseif action == "GetUniverse" then
		local universe = universeSnapshotFor(player, universeId)
		return { Success = universe ~= nil, Universe = universe }
	elseif action == "GetUniverses" then
		return { Success = true, Universes = allUniverseSnapshots(player) }
	elseif action == "Select" then
		local locked = lockedResult(player, phaseId)
		if locked then return locked end
		local success, message = PartyService.SetSelectedPhase(player, phaseId)
		return {
			Success = success,
			Message = message,
			Phase = phaseSnapshotFor(player, phaseId),
		}
	elseif action == "Start" then
		local locked = lockedResult(player, phaseId)
		if locked then return locked end
		local selected, message = PartyService.SetSelectedPhase(player, phaseId)
		if not selected then
			return { Success = false, Message = message }
		end
		local success, startMessage = TeleportCoordinator.Schedule(player, phaseId)
		return {
			Success = success,
			Message = startMessage,
			Phase = phaseSnapshotFor(player, phaseId),
		}
	elseif action == "Cancel" then
		local success, message = TeleportCoordinator.Cancel(player)
		return { Success = success, Message = message }
	end

	return { Success = false, Message = "Ação inválida." }
end

function PhaseSelectionService.Start()
	if started then return true end
	started = true
	request = RemoteRegistry.Get("PhaseSelection", "Request", "RemoteFunction")
	event = RemoteRegistry.Get("PhaseSelection", "Event", "RemoteEvent")
	request.OnServerInvoke = handle
	TeleportCoordinator.Start()

	workspace:SetAttribute("LobbyUniverseSelectionReady", true)
	workspace:SetAttribute("LobbyUniverseCount", #PhaseConfig.GetUniversesSorted())
	workspace:SetAttribute("LobbyLevelCount", PhaseConfig.Count())
	return true
end

return PhaseSelectionService
