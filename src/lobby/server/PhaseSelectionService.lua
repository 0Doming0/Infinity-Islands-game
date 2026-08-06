local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PartyService = require(BlockParkour.PartyService)
local TeleportCoordinator = require(script.Parent.TeleportCoordinator)

local PhaseSelectionService = {}
local request
local event
local started = false

local function phaseSnapshot(phaseId)
	return PhaseConfig.ToPublicSnapshot(phaseId)
end

local function allPhaseSnapshots()
	local snapshots = {}
	for _, entry in ipairs(PhaseConfig.GetAllSorted()) do
		table.insert(snapshots, PhaseConfig.ToPublicSnapshot(entry.PhaseId))
	end
	return snapshots
end

function PhaseSelectionService.Open(player, phaseId)
	local snapshot = phaseSnapshot(phaseId)
	if not snapshot then
		return false
	end
	event:FireClient(player, {
		Action = "Open",
		Phase = snapshot,
		IsLeader = not player:GetAttribute("PartyLeaderUserId")
			or player:GetAttribute("PartyLeaderUserId") == player.UserId,
	})
	return true
end

local function handle(player, action, payload)
	local phaseId = type(payload) == "table" and payload.PhaseId or nil
	if action == "GetPhase" then
		return { Success = phaseSnapshot(phaseId) ~= nil, Phase = phaseSnapshot(phaseId) }
	elseif action == "GetPhases" then
		return { Success = true, Phases = allPhaseSnapshots() }
	elseif action == "Select" then
		local success, message = PartyService.SetSelectedPhase(player, phaseId)
		return { Success = success, Message = message, Phase = phaseSnapshot(phaseId) }
	elseif action == "Start" then
		local selected, message = PartyService.SetSelectedPhase(player, phaseId)
		if not selected then
			return { Success = false, Message = message }
		end
		local success, startMessage = TeleportCoordinator.Schedule(player, phaseId)
		return { Success = success, Message = startMessage }
	elseif action == "Cancel" then
		local success, message = TeleportCoordinator.Cancel(player)
		return { Success = success, Message = message }
	end
	return { Success = false, Message = "Acao invalida." }
end

function PhaseSelectionService.Start()
	if started then
		return
	end
	started = true
	request = RemoteRegistry.Get("PhaseSelection", "Request", "RemoteFunction")
	event = RemoteRegistry.Get("PhaseSelection", "Event", "RemoteEvent")
	request.OnServerInvoke = handle
	TeleportCoordinator.Start()
end

return PhaseSelectionService
