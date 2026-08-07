local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local PlaceConfig = require(ReplicatedStorage.Shared.Configs.PlaceConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PartyService = require(BlockParkour.PartyService)
local PlayerDataService = require(script.Parent.LobbyPlayerDataService)

local TeleportCoordinator = {}
local pendingByLeader = setmetatable({}, { __mode = "k" })
local phaseEvent
local started = false

local function unlock(pending, message)
	if not pending then
		return
	end
	pending.Cancelled = true
	pendingByLeader[pending.Leader] = nil
	PartyService.UnlockTeleport(pending.Leader, pending.Token, message)
	for _, member in ipairs(pending.Members) do
		if member.Parent == Players then
			member:SetAttribute("TeleportingToDungeon", false)
			phaseEvent:FireClient(member, {
				Action = "TeleportCancelled",
				Message = message,
			})
		end
	end
end

local function teleport(pending)
	if pending.Cancelled or pendingByLeader[pending.Leader] ~= pending then
		return
	end
	for _, member in ipairs(pending.Members) do
		if member.Parent ~= Players then
			unlock(pending, "Um membro saiu antes do teleporte.")
			return
		end
		PlayerDataService.Load(member)
		if not PlayerDataService.Save(member, true) then
			unlock(pending, "Nao foi possivel salvar os dados de todos os membros.")
			return
		end
	end
	if PlaceConfig.DungeonPlaceId <= 0 then
		unlock(pending, "Preencha DungeonPlaceId em Shared/Configs/PlaceConfig.lua.")
		return
	end
	local userIds = {}
	for _, member in ipairs(pending.Members) do
		table.insert(userIds, member.UserId)
	end
	local teleportData = {
		Version = 1,
		SessionId = pending.SessionId,
		PhaseId = pending.PhaseId,
		PartySize = #pending.Members,
		LeaderUserId = pending.Leader.UserId,
		PartyUserIds = userIds,
		Seed = pending.Seed,
	}
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData(teleportData)
	local success, errorMessage = pcall(
		TeleportService.TeleportAsync,
		TeleportService,
		PlaceConfig.DungeonPlaceId,
		pending.Members,
		options
	)
	if not success then
		unlock(pending, "Falha ao iniciar a fase: " .. tostring(errorMessage))
	end
end

function TeleportCoordinator.Schedule(leader, phaseId)
	local phase = PhaseConfig.Get(phaseId)
	if not phase then
		return false, "Fase invalida."
	end
	if pendingByLeader[leader] then
		return false, "Ja existe um teleporte em preparacao."
	end
	local token = HttpService:GenerateGUID(false)
	local locked, message, _, members = PartyService.LockForTeleport(leader, token)
	if not locked then
		return false, message
	end
	if #members > phase.MaxPlayers then
		PartyService.UnlockTeleport(leader, token, "O grupo excede o limite desta fase.")
		return false, "O grupo excede o limite desta fase."
	end
	local pending = {
		Leader = leader,
		Members = members,
		PhaseId = phaseId,
		Token = token,
		SessionId = HttpService:GenerateGUID(false),
		Seed = Random.new():NextInteger(1, 2147483646),
		Cancelled = false,
	}
	pendingByLeader[leader] = pending
	for _, member in ipairs(members) do
		phaseEvent:FireClient(member, {
			Action = "TeleportCountdown",
			PhaseId = phaseId,
			Seconds = 3,
			CanCancel = member == leader,
		})
	end
	task.delay(3, teleport, pending)
	return true, "Preparando servidor reservado."
end

function TeleportCoordinator.Cancel(leader)
	local pending = pendingByLeader[leader]
	if not pending then
		return false, "Nao existe inicio para cancelar."
	end
	unlock(pending, "Inicio cancelado pelo lider.")
	return true
end

function TeleportCoordinator.Start()
	if started then
		return
	end
	started = true
	phaseEvent = RemoteRegistry.Get("PhaseSelection", "Event", "RemoteEvent")
	TeleportService.TeleportInitFailed:Connect(function(player, _, errorMessage)
		for _, pending in pairs(pendingByLeader) do
			if table.find(pending.Members, player) then
				unlock(pending, "Teleporte recusado: " .. tostring(errorMessage))
				break
			end
		end
	end)
	if RunService:IsStudio() then
		workspace:SetAttribute("LobbyTeleportStudioMode", true)
	end
end

return TeleportCoordinator
