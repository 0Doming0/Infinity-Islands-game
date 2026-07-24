-- Grupo autoritativo do MVP. Mantem convites, lideranca, pontuacao coletiva e
-- uma missao cooperativa simples. Todos os membros precisam estar no mesmo servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CONFIG = MVPConfig.Party or {}
local MISSION = CONFIG.Mission or {}

local PartyService = {}
local started = false
local nextPartyId = 0
local parties = {}
local partyByPlayer = setmetatable({}, { __mode = "k" })
local invitesByTarget = setmetatable({}, { __mode = "k" })
local partyRequest
local partyEvent

local function ensureRemote(className, name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote.ClassName ~= className then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

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
		player:SetAttribute("PartySharedScore", 0)
		player:SetAttribute("PartyMissionMobDefeated", 0)
		player:SetAttribute("PartyMissionIslandVisited", 0)
		player:SetAttribute("PartyMissionComplete", false)
		return
	end
	player:SetAttribute("PartyId", party.Id)
	player:SetAttribute("PartyLeaderUserId", party.Leader and party.Leader.UserId or 0)
	player:SetAttribute("PartyMemberCount", memberCount(party))
	player:SetAttribute("PartySharedScore", party.SharedScore)
	player:SetAttribute("PartyMissionMobDefeated", party.MobDefeated)
	player:SetAttribute("PartyMissionIslandVisited", party.IslandVisited)
	player:SetAttribute("PartyMissionComplete", party.Completed)
end

local function serializeInvites(player)
	local result = {}
	local now = os.clock()
	local invites = invitesByTarget[player]
	if not invites then
		return result
	end
	for inviter, expiresAt in pairs(invites) do
		if inviter.Parent == Players and expiresAt > now then
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
		MaxMembers = tonumber(CONFIG.MaxMembers) or 4,
		IndicatorDistanceStuds = tonumber(CONFIG.IndicatorDistanceStuds) or 70,
	}
end

local function publishParty(party, action, message)
	for _, member in ipairs(memberArray(party)) do
		setPlayerAttributes(member, party)
		partyEvent:FireClient(member, {
			Action = action or "State",
			Message = message,
			State = serializeState(member),
		})
	end
end

local function createParty(leader)
	nextPartyId += 1
	local party = {
		Id = string.format("party-%d-%d", game.JobId ~= "" and #game.JobId or 0, nextPartyId),
		Leader = leader,
		Members = { [leader] = true },
		SharedScore = 0,
		MobDefeated = 0,
		IslandVisited = 0,
		VisitedIslandKeys = {},
		Completed = false,
	}
	parties[party.Id] = party
	partyByPlayer[leader] = party
	return party
end

local function dissolveIfSolo(party)
	local members = memberArray(party)
	if #members > 1 then
		return false
	end
	for _, member in ipairs(members) do
		partyByPlayer[member] = nil
		setPlayerAttributes(member, nil)
		partyEvent:FireClient(member, {
			Action = "Dissolved",
			Message = "O grupo foi encerrado.",
			State = serializeState(member),
		})
	end
	parties[party.Id] = nil
	return true
end

local function removeMember(player, reason)
	local party = partyByPlayer[player]
	if not party then
		return false, "Voce nao esta em um grupo."
	end
	party.Members[player] = nil
	partyByPlayer[player] = nil
	setPlayerAttributes(player, nil)
	partyEvent:FireClient(player, {
		Action = "Left",
		Message = reason or "Voce saiu do grupo.",
		State = serializeState(player),
	})
	if party.Leader == player then
		party.Leader = memberArray(party)[1]
	end
	if not dissolveIfSolo(party) then
		publishParty(party, "MemberLeft", player.DisplayName .. " saiu do grupo.")
	end
	return true
end

local function findPlayer(userId)
	userId = tonumber(userId)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
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
	if party and memberCount(party) >= (tonumber(CONFIG.MaxMembers) or 4) then
		return false, "O grupo esta cheio."
	end
	if partyByPlayer[target] then
		return false, "Esse jogador ja esta em um grupo."
	end
	local invites = invitesByTarget[target] or {}
	invitesByTarget[target] = invites
	invites[player] = os.clock() + (tonumber(CONFIG.InviteLifetimeSeconds) or 30)
	partyEvent:FireClient(target, {
		Action = "Invite",
		Message = player.DisplayName .. " convidou voce para um grupo.",
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
	local party = partyByPlayer[inviter] or createParty(inviter)
	if party.Leader ~= inviter or memberCount(party) >= (tonumber(CONFIG.MaxMembers) or 4) then
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
		local success, message = invite(player, payload and payload.UserId)
		return success, message, serializeState(player)
	elseif action == "Accept" then
		local success, message = accept(player, payload and payload.UserId)
		return success, message, serializeState(player)
	elseif action == "Decline" then
		local inviter = findPlayer(payload and payload.UserId)
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
		local target = findPlayer(payload and payload.UserId)
		if not party or party.Leader ~= player then
			return false, "Somente o lider pode remover membros.", serializeState(player)
		end
		if not target or partyByPlayer[target] ~= party or target == player then
			return false, "Membro invalido.", serializeState(player)
		end
		removeMember(target, "Voce foi removido do grupo.")
		return true, "Membro removido.", serializeState(player)
	end
	return false, "Acao invalida.", serializeState(player)
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
	local completedNow = missionComplete(party)
	if completedNow and not party.Completed then
		party.Completed = true
		publishParty(party, "MissionComplete", "Missao do grupo concluida!")
	else
		publishParty(party, "MissionProgress")
	end
end

function PartyService.GetPartyMembers(player)
	local party = partyByPlayer[player]
	return party and memberArray(party) or {}
end

function PartyService.Start()
	if started then
		return
	end
	started = true
	partyRequest = ensureRemote("RemoteFunction", "PartyRequest")
	partyEvent = ensureRemote("RemoteEvent", "PartyEvent")
	partyRequest.OnServerInvoke = function(player, action, payload)
		return handleRequest(player, tostring(action or ""), type(payload) == "table" and payload or {})
	end
	local function setupPlayer(player)
		setPlayerAttributes(player, nil)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		invitesByTarget[player] = nil
		if partyByPlayer[player] then
			removeMember(player, "Voce saiu do grupo.")
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
