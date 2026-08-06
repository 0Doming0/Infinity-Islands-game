-- Grupo autoritativo de ate quatro jogadores do mesmo servidor.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)

local CONFIG = MVPConfig.Party or {}
local MISSION = CONFIG.Mission or {}
local MAX_MEMBERS = math.clamp(math.floor(tonumber(CONFIG.MaxMembers) or 4), 1, 4)

local PartyService = {}
local started = false
local parties = {}
local partyByPlayer = setmetatable({}, { __mode = "k" })
local invitesByTarget = setmetatable({}, { __mode = "k" })
local partyRequest
local partyEvent

local function memberArray(party)
	local result = {}
	for member in pairs(party.Members) do
		if member.Parent == Players then
			table.insert(result, member)
		end
	end
	table.sort(result, function(left, right)
		if left == party.Leader then
			return true
		elseif right == party.Leader then
			return false
		end
		return left.UserId < right.UserId
	end)
	return result
end

local function memberCount(party)
	local count = 0
	for _ in pairs(party.Members) do
		count += 1
	end
	return count
end

local function missionComplete(party)
	return party.MobDefeated >= (tonumber(MISSION.MobDefeatedGoal) or 5)
		and party.IslandVisited >= (tonumber(MISSION.IslandVisitedGoal) or 3)
end

local function setPlayerAttributes(player, party)
	if not party then
		player:SetAttribute("PartyId", nil)
		player:SetAttribute("PartyLeaderUserId", nil)
		player:SetAttribute("PartyMemberCount", 0)
		player:SetAttribute("PartyLocked", false)
		player:SetAttribute("PartySelectedPhaseId", nil)
		player:SetAttribute("PartySharedScore", 0)
		player:SetAttribute("PartyMissionMobDefeated", 0)
		player:SetAttribute("PartyMissionIslandVisited", 0)
		player:SetAttribute("PartyMissionComplete", false)
		return
	end
	player:SetAttribute("PartyId", party.Id)
	player:SetAttribute("PartyLeaderUserId", party.Leader and party.Leader.UserId or 0)
	player:SetAttribute("PartyMemberCount", memberCount(party))
	player:SetAttribute("PartyLocked", party.Locked == true)
	player:SetAttribute("PartySelectedPhaseId", party.SelectedPhaseId)
	player:SetAttribute("PartySharedScore", party.SharedScore)
	player:SetAttribute("PartyMissionMobDefeated", party.MobDefeated)
	player:SetAttribute("PartyMissionIslandVisited", party.IslandVisited)
	player:SetAttribute("PartyMissionComplete", party.Completed)
end

local function findPlayer(userId)
	local clean = math.floor(tonumber(userId) or 0)
	return clean > 0 and Players:GetPlayerByUserId(clean) or nil
end

local function serializeInvites(player)
	local result = {}
	local now = os.clock()
	local invites = invitesByTarget[player]
	if not invites then
		return result
	end
	for inviter, expiresAt in pairs(invites) do
		local party = partyByPlayer[inviter]
		if inviter.Parent == Players and expiresAt > now and party and not party.Locked then
			table.insert(result, {
				UserId = inviter.UserId,
				Name = inviter.Name,
				DisplayName = inviter.DisplayName,
				ExpiresAt = expiresAt,
			})
		else
			invites[inviter] = nil
		end
	end
	return result
end

local function serializeState(player)
	local party = partyByPlayer[player]
	local members = {}
	if party then
		for _, member in ipairs(memberArray(party)) do
			table.insert(members, {
				UserId = member.UserId,
				Name = member.Name,
				DisplayName = member.DisplayName,
				IsLeader = member == party.Leader,
			})
		end
	end
	local available = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not partyByPlayer[other] then
			table.insert(available, {
				UserId = other.UserId,
				Name = other.Name,
				DisplayName = other.DisplayName,
			})
		end
	end
	return {
		Party = party and {
			Id = party.Id,
			LeaderUserId = party.Leader and party.Leader.UserId or 0,
			Members = members,
			Locked = party.Locked == true,
			SelectedPhaseId = party.SelectedPhaseId,
			SharedScore = party.SharedScore,
			Mission = {
				Id = tostring(MISSION.Id or "PartyExpedition"),
				Title = tostring(MISSION.Title or "EXPEDICAO EM GRUPO"),
				MobDefeated = party.MobDefeated,
				MobDefeatedGoal = tonumber(MISSION.MobDefeatedGoal) or 5,
				IslandVisited = party.IslandVisited,
				IslandVisitedGoal = tonumber(MISSION.IslandVisitedGoal) or 3,
				Completed = party.Completed,
			},
		} or nil,
		Invites = serializeInvites(player),
		AvailablePlayers = available,
		MaxMembers = MAX_MEMBERS,
		IndicatorDistanceStuds = tonumber(CONFIG.IndicatorDistanceStuds) or 70,
	}
end

local function publishToPlayer(player, action, message)
	if player.Parent == Players then
		partyEvent:FireClient(player, {
			Action = action or "State",
			Message = message,
			State = serializeState(player),
		})
	end
end

local function publishParty(party, action, message)
	for _, member in ipairs(memberArray(party)) do
		setPlayerAttributes(member, party)
		publishToPlayer(member, action, message)
	end
end

local function createParty(leader)
	local existing = partyByPlayer[leader]
	if existing then
		return existing
	end
	local party = {
		Id = "party-" .. HttpService:GenerateGUID(false),
		Leader = leader,
		Members = { [leader] = true },
		Locked = false,
		TeleportToken = nil,
		SelectedPhaseId = nil,
		SharedScore = 0,
		MobDefeated = 0,
		IslandVisited = 0,
		VisitedIslandKeys = {},
		Completed = false,
	}
	parties[party.Id] = party
	partyByPlayer[leader] = party
	setPlayerAttributes(leader, party)
	return party
end

local function destroyIfEmpty(party)
	if memberCount(party) > 0 then
		return false
	end
	parties[party.Id] = nil
	return true
end

local function removeMember(player, reason, force)
	local party = partyByPlayer[player]
	if not party then
		return false, "Voce nao esta em um grupo."
	end
	if party.Locked and not force then
		return false, "O grupo esta bloqueado para o teleporte."
	end
	party.Members[player] = nil
	partyByPlayer[player] = nil
	setPlayerAttributes(player, nil)
	publishToPlayer(player, "Left", reason or "Voce saiu do grupo.")
	if party.Leader == player then
		party.Leader = memberArray(party)[1]
	end
	if not destroyIfEmpty(party) then
		if force and party.Locked and not party.DungeonSession then
			party.Locked = false
			party.TeleportToken = nil
		end
		publishParty(party, "MemberLeft", player.DisplayName .. " saiu do grupo.")
	end
	return true
end

local function invite(player, targetUserId)
	local target = findPlayer(targetUserId)
	if not target or target == player then
		return false, "Jogador indisponivel."
	end
	local party = partyByPlayer[player]
	if party and party.Leader ~= player then
		return false, "Somente o lider pode convidar."
	end
	if party and party.Locked then
		return false, "O grupo esta iniciando uma fase."
	end
	if party and memberCount(party) >= MAX_MEMBERS then
		return false, "O grupo esta cheio."
	end
	if partyByPlayer[target] then
		return false, "Esse jogador ja esta em um grupo."
	end
	-- O primeiro convite cria imediatamente o grupo do remetente.
	party = party or createParty(player)
	local invites = invitesByTarget[target] or {}
	invitesByTarget[target] = invites
	invites[player] = os.clock() + (tonumber(CONFIG.InviteLifetimeSeconds) or 30)
	publishParty(party, "PartyCreated")
	partyEvent:FireClient(target, {
		Action = "Invite",
		Message = player.DisplayName .. " convidou voce para um grupo.",
		FromUserId = player.UserId,
		FromDisplayName = player.DisplayName,
		State = serializeState(target),
	})
	return true, "Convite enviado."
end

local function accept(player, inviterUserId)
	local inviter = findPlayer(inviterUserId)
	local invites = invitesByTarget[player]
	local expiresAt = inviter and invites and invites[inviter]
	if not inviter or not expiresAt or expiresAt <= os.clock() then
		return false, "O convite expirou."
	end
	if partyByPlayer[player] then
		return false, "Voce ja esta em um grupo."
	end
	local party = partyByPlayer[inviter]
	if not party or party.Leader ~= inviter or party.Locked or memberCount(party) >= MAX_MEMBERS then
		return false, "O grupo nao esta mais disponivel."
	end
	invites[inviter] = nil
	party.Members[player] = true
	partyByPlayer[player] = party
	publishParty(party, "MemberJoined", player.DisplayName .. " entrou no grupo.")
	return true, "Voce entrou no grupo."
end

local function handleRequest(player, action, payload)
	if action == "GetState" then
		return true, nil, serializeState(player)
	elseif action == "Invite" then
		local success, message = invite(player, payload.UserId)
		return success, message, serializeState(player)
	elseif action == "Accept" then
		local success, message = accept(player, payload.UserId)
		return success, message, serializeState(player)
	elseif action == "Decline" then
		local inviter = findPlayer(payload.UserId)
		local invites = invitesByTarget[player]
		if inviter and invites then
			invites[inviter] = nil
		end
		return true, "Convite recusado.", serializeState(player)
	elseif action == "Leave" then
		local success, message = removeMember(player)
		return success, message, serializeState(player)
	elseif action == "Kick" then
		local party = partyByPlayer[player]
		local target = findPlayer(payload.UserId)
		if not party or party.Leader ~= player then
			return false, "Somente o lider pode remover membros.", serializeState(player)
		end
		if party.Locked then
			return false, "O grupo esta iniciando uma fase.", serializeState(player)
		end
		if not target or partyByPlayer[target] ~= party or target == player then
			return false, "Membro invalido.", serializeState(player)
		end
		removeMember(target, "Voce foi removido do grupo.")
		return true, "Membro removido.", serializeState(player)
	end
	return false, "Acao invalida.", serializeState(player)
end

function PartyService.GetOrCreateParty(player)
	return partyByPlayer[player] or createParty(player)
end

function PartyService.GetPartyMembers(player)
	local party = partyByPlayer[player]
	return party and memberArray(party) or {}
end

function PartyService.RestoreDungeonParty(players, leaderUserId, phaseId, sessionId)
	local leader
	for _, player in ipairs(players) do
		if player.UserId == leaderUserId then
			leader = player
			break
		end
	end
	leader = leader or players[1]
	if not leader then
		return nil
	end
	local party = partyByPlayer[leader] or createParty(leader)
	parties[party.Id] = nil
	party.Id = "session-" .. tostring(sessionId)
	parties[party.Id] = party
	party.SelectedPhaseId = phaseId
	party.Locked = true
	party.DungeonSession = true
	party.TeleportToken = nil
	for _, player in ipairs(players) do
		local previous = partyByPlayer[player]
		if not previous or previous == party then
			party.Members[player] = true
			partyByPlayer[player] = party
			player:SetAttribute("TeleportingToDungeon", false)
		end
	end
	publishParty(party, "DungeonPartyRestored", "Grupo da expedicao restaurado.")
	return party
end

function PartyService.IsLeader(player)
	local party = partyByPlayer[player]
	return party ~= nil and party.Leader == player
end

function PartyService.SetSelectedPhase(player, phaseId)
	local party = PartyService.GetOrCreateParty(player)
	if party.Leader ~= player then
		return false, "Somente o lider escolhe a fase."
	end
	if party.Locked then
		return false, "O grupo esta bloqueado."
	end
	if not PhaseConfig.IsValid(phaseId) then
		return false, "Fase invalida."
	end
	party.SelectedPhaseId = phaseId
	publishParty(party, "PhaseSelected", "Fase selecionada: " .. phaseId)
	return true, nil, party
end

function PartyService.LockForTeleport(player, token)
	local party = PartyService.GetOrCreateParty(player)
	if party.Leader ~= player then
		return false, "Somente o lider pode iniciar."
	end
	if party.Locked then
		return false, "O grupo ja esta iniciando."
	end
	local members = memberArray(party)
	if #members < 1 or #members > MAX_MEMBERS then
		return false, "Tamanho de grupo invalido."
	end
	for _, member in ipairs(members) do
		if member.Parent ~= Players or member:GetAttribute("TeleportingToDungeon") == true then
			return false, "Um membro esta indisponivel."
		end
	end
	party.Locked = true
	party.TeleportToken = token
	for _, member in ipairs(members) do
		member:SetAttribute("TeleportingToDungeon", true)
	end
	publishParty(party, "TeleportLocked", "Preparando a expedicao...")
	return true, nil, party, members
end

function PartyService.UnlockTeleport(player, token, message)
	local party = partyByPlayer[player]
	if not party or party.Leader ~= player then
		return false
	end
	if token and party.TeleportToken ~= token then
		return false
	end
	party.Locked = false
	party.TeleportToken = nil
	for _, member in ipairs(memberArray(party)) do
		member:SetAttribute("TeleportingToDungeon", false)
	end
	publishParty(party, "TeleportCancelled", message or "Inicio cancelado.")
	return true
end

function PartyService.RecordScore(player, amount, _source)
	local party = partyByPlayer[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not party or clean <= 0 then
		return
	end
	party.SharedScore += clean
	publishParty(party, "Score")
end

function PartyService.RecordMissionProgress(player, objective, amount, uniqueKey)
	local party = partyByPlayer[player]
	local clean = math.max(0, math.floor(tonumber(amount) or 0))
	if not party or clean <= 0 or party.Completed then
		return
	end
	if objective == "MobDefeated" then
		party.MobDefeated += clean
	elseif objective == "IslandVisited" then
		if uniqueKey ~= nil then
			local key = tostring(uniqueKey)
			if party.VisitedIslandKeys[key] then
				return
			end
			party.VisitedIslandKeys[key] = true
		end
		party.IslandVisited += clean
	else
		return
	end
	if missionComplete(party) and not party.Completed then
		party.Completed = true
		publishParty(party, "MissionComplete", "Missao do grupo concluida!")
	else
		publishParty(party, "MissionProgress")
	end
end

function PartyService.Start()
	if started then
		return
	end
	started = true
	partyRequest = RemoteRegistry.Get("Party", "Request", "RemoteFunction")
	partyEvent = RemoteRegistry.Get("Party", "Event", "RemoteEvent")
	partyRequest.OnServerInvoke = function(player, action, payload)
		return handleRequest(player, tostring(action or ""), type(payload) == "table" and payload or {})
	end
	local function setupPlayer(player)
		setPlayerAttributes(player, nil)
		player:SetAttribute("TeleportingToDungeon", false)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		invitesByTarget[player] = nil
		if partyByPlayer[player] then
			removeMember(player, "Voce saiu do grupo.", true)
		end
		for target, invites in pairs(invitesByTarget) do
			invites[player] = nil
			if next(invites) == nil then
				invitesByTarget[target] = nil
			end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
end

return PartyService
