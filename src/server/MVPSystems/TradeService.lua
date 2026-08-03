-- Troca autoritativa de companheiros no mesmo servidor. Cada transação é
-- registrada antes da transferência e indexada por usuário para recuperação.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)

local TradeService = {}
local CONFIG = MVPConfig.Social.Trade
local MAX_OFFER = tonumber(CONFIG.MaximumCompanionsPerOffer) or 4
local INVITE_LIFETIME = tonumber(CONFIG.InviteLifetimeSeconds) or 30
local MAX_DISTANCE = tonumber(CONFIG.MaximumDistanceStuds) or 60
local CONFIRM_COUNTDOWN = tonumber(CONFIG.ConfirmationCountdownSeconds) or 3
local REQUEST_INTERVAL = 0.12
local STORE_RETRIES = 3

local transactionStore = DataStoreService:GetDataStore("SkyDungeonTradeTransactions_V1")
local indexStore = DataStoreService:GetDataStore("SkyDungeonTradeIndexes_V1")
local sessionsByPlayer = setmetatable({}, { __mode = "k" })
local invitesByTarget = setmetatable({}, { __mode = "k" })
local lockedCompanions = setmetatable({}, { __mode = "k" })
local lastRequestAt = setmetatable({}, { __mode = "k" })
local started = false
local request
local event

local function retry(label, callback)
	local lastError
	for attempt = 1, STORE_RETRIES do
		local success, result = pcall(callback)
		if success then
			return true, result
		end
		lastError = result
		warn(string.format("[TradeService] %s falhou (%d/%d): %s", label, attempt, STORE_RETRIES, tostring(result)))
		if attempt < STORE_RETRIES then
			task.wait(0.6 * attempt)
		end
	end
	return false, lastError
end

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

local function findPlayer(userId)
	userId = tonumber(userId)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function playerIsAvailable(player)
	if
		not player
		or player.Parent ~= Players
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("InitialGameStarted") ~= true
		or (not RunService:IsStudio() and not PlayerDataService.CanSave(player))
	then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

local function playersAreNear(left, right)
	local leftRoot = left.Character and left.Character:FindFirstChild("HumanoidRootPart")
	local rightRoot = right.Character and right.Character:FindFirstChild("HumanoidRootPart")
	return leftRoot ~= nil
		and rightRoot ~= nil
		and (leftRoot.Position - rightRoot.Position).Magnitude <= MAX_DISTANCE
end

local function copyArray(source)
	local result = {}
	for _, value in ipairs(source or {}) do
		table.insert(result, value)
	end
	return result
end

local function recordSnapshot(instanceId, record)
	if not record then
		return nil
	end
	local species = CompanionCatalog.Get(record.SpeciesId)
	return {
		InstanceId = instanceId,
		SpeciesId = record.SpeciesId,
		SpeciesName = species and species.DisplayName or record.SpeciesId,
		DisplayName = record.DisplayName,
		Level = record.Level,
		XP = record.XP,
		Kills = record.Kills,
		Upgrades = table.clone(record.Upgrades or {}),
		Color = species and species.Color or Color3.fromRGB(160, 200, 180),
		ImageId = CompanionCatalog.GetImageId(record.SpeciesId),
	}
end

local function offerSnapshots(player, offer)
	local companions = PlayerDataService.GetCompanions(player)
	local result = {}
	for _, instanceId in ipairs(offer or {}) do
		local snapshot = recordSnapshot(instanceId, companions[instanceId])
		if snapshot then
			table.insert(result, snapshot)
		end
	end
	return result
end

local function availableInventory(player)
	local companions, equipped = PlayerDataService.GetCompanions(player)
	local equippedSet = {}
	for _, instanceId in ipairs(equipped) do
		equippedSet[instanceId] = true
	end
	local entries = {}
	for instanceId, record in pairs(companions) do
		local snapshot = recordSnapshot(instanceId, record)
		snapshot.TradeLocked = TradeService.IsCompanionLocked(player, instanceId)
		snapshot.Equipped = equippedSet[instanceId] == true
		table.insert(entries, snapshot)
	end
	table.sort(entries, function(left, right)
		if left.Level ~= right.Level then
			return left.Level > right.Level
		end
		return string.lower(left.DisplayName) < string.lower(right.DisplayName)
	end)
	return entries
end

local function validInvites(player)
	local result = {}
	local invites = invitesByTarget[player]
	local now = os.clock()
	for inviter, expiresAt in pairs(invites or {}) do
		if inviter.Parent == Players and expiresAt > now and not sessionsByPlayer[inviter] then
			table.insert(result, {
				UserId = inviter.UserId,
				DisplayName = inviter.DisplayName,
				ExpiresAt = expiresAt,
			})
		else
			invites[inviter] = nil
		end
	end
	table.sort(result, function(left, right)
		return string.lower(left.DisplayName) < string.lower(right.DisplayName)
	end)
	return result
end

local function stateFor(player)
	local session = sessionsByPlayer[player]
	local availablePlayers = {}
	if not session then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and not sessionsByPlayer[other] and playerIsAvailable(other) then
				table.insert(availablePlayers, {
					UserId = other.UserId,
					DisplayName = other.DisplayName,
				})
			end
		end
		table.sort(availablePlayers, function(left, right)
			return string.lower(left.DisplayName) < string.lower(right.DisplayName)
		end)
	end
	if not session then
		return {
			Session = nil,
			Invites = validInvites(player),
			AvailablePlayers = availablePlayers,
			Inventory = availableInventory(player),
			MaxOffer = MAX_OFFER,
			PersistenceMode = PlayerDataService.CanSave(player) and "Persistent" or "StudioTemporary",
		}
	end
	local partner = session.A == player and session.B or session.A
	local ownOffer = session.Offers[player]
	local partnerOffer = session.Offers[partner]
	return {
		Session = {
			Id = session.Id,
			PartnerUserId = partner.UserId,
			PartnerDisplayName = partner.DisplayName,
			OwnOffer = offerSnapshots(player, ownOffer),
			PartnerOffer = offerSnapshots(partner, partnerOffer),
			OwnLocked = session.Locked[player] == true,
			PartnerLocked = session.Locked[partner] == true,
			OwnConfirmed = session.Confirmed[player] == true,
			PartnerConfirmed = session.Confirmed[partner] == true,
			CountdownEndsAt = session.CountdownEndsAt,
		},
		Inventory = availableInventory(player),
		Invites = {},
		AvailablePlayers = {},
		MaxOffer = MAX_OFFER,
		PersistenceMode = PlayerDataService.CanSave(player) and "Persistent" or "StudioTemporary",
	}
end

local function publish(player, action, message, metadata)
	if event and player.Parent == Players then
		local payload = {
			Action = action or "State",
			Message = message,
			State = stateFor(player),
		}
		for key, value in pairs(metadata or {}) do
			payload[key] = value
		end
		event:FireClient(player, payload)
	end
end

local function publishSession(session, action, message)
	publish(session.A, action, message)
	publish(session.B, action, message)
end

local function unlockOffer(player, offer)
	local locks = lockedCompanions[player]
	for _, instanceId in ipairs(offer or {}) do
		if locks then
			locks[instanceId] = nil
		end
	end
	if locks and next(locks) == nil then
		lockedCompanions[player] = nil
	end
end

local function restoreAutoUnequipped(session, player)
	local restored = session.AutoUnequipped and session.AutoUnequipped[player]
	for instanceId in pairs(restored or {}) do
		PlayerDataService.SetCompanionEquipped(player, instanceId, true)
	end
	if session.AutoUnequipped then
		session.AutoUnequipped[player] = {}
	end
end

local function cancelSession(session, reason)
	if not session or session.Cancelled then
		return
	end
	session.Cancelled = true
	session.CountdownSerial += 1
	for _, player in ipairs({ session.A, session.B }) do
		unlockOffer(player, session.Offers[player])
		restoreAutoUnequipped(session, player)
		if sessionsByPlayer[player] == session then
			sessionsByPlayer[player] = nil
			publish(player, "Cancelled", reason or "Troca cancelada.")
		end
	end
end

function TradeService.CancelForPlayer(player, reason)
	local session = sessionsByPlayer[player]
	if session then
		cancelSession(session, reason)
		return true
	end
	return false
end

function TradeService.IsCompanionLocked(player, instanceId)
	local locks = lockedCompanions[player]
	return locks ~= nil and locks[instanceId] == true
end

local function resetConfirmations(session)
	session.Locked[session.A] = false
	session.Locked[session.B] = false
	session.Confirmed[session.A] = false
	session.Confirmed[session.B] = false
	session.CountdownEndsAt = nil
	session.CountdownSerial += 1
end

local function updateIndex(userId, transactionId, add)
	return retry("Index " .. tostring(userId), function()
		return indexStore:UpdateAsync("User_" .. tostring(userId), function(previous)
			local list = type(previous) == "table" and previous or {}
			local output = {}
			local found = false
			for _, value in ipairs(list) do
				if type(value) == "string" and value ~= transactionId then
					table.insert(output, value)
				elseif value == transactionId then
					found = true
				end
			end
			if add and not found then
				table.insert(output, transactionId)
			end
			while #output > 30 do
				table.remove(output, 1)
			end
			return output
		end)
	end)
end

local function updateTransaction(transactionId, callback)
	return retry("Transação " .. transactionId, function()
		return transactionStore:UpdateAsync(transactionId, callback)
	end)
end

local function companionRecords(player, offer)
	local companions = PlayerDataService.GetCompanions(player)
	local records = {}
	for _, instanceId in ipairs(offer) do
		local record = companions[instanceId]
		if not record then
			return nil
		end
		records[instanceId] = {
			InstanceId = instanceId,
			SpeciesId = record.SpeciesId,
			DisplayName = record.DisplayName,
			Level = record.Level,
			XP = record.XP,
			Kills = record.Kills,
			Upgrades = table.clone(record.Upgrades or {}),
		}
	end
	return records
end

local function markRecovered(transactionId, userId)
	return updateTransaction(transactionId, function(previous)
		if type(previous) ~= "table" then
			return previous
		end
		previous.Recovered = type(previous.Recovered) == "table" and previous.Recovered or {}
		previous.Recovered[tostring(userId)] = true
		if
			previous.Recovered[tostring(previous.AUserId)] == true
			and previous.Recovered[tostring(previous.BUserId)] == true
		then
			previous.Status = "Completed"
			previous.CompletedAt = os.time()
		else
			previous.Status = "PendingRecovery"
		end
		return previous
	end)
end

local function refreshCompanionUI(player)
	local companionEvent = ReplicatedStorage:FindFirstChild("CompanionEvent")
	if companionEvent and companionEvent:IsA("RemoteEvent") and player.Parent == Players then
		companionEvent:FireClient(player, {
			Action = "Refresh",
			Message = "Inventário atualizado pela troca.",
			Success = true,
		})
	end
end

local function finalizeSession(session, serial)
	if
		session.Cancelled
		or sessionsByPlayer[session.A] ~= session
		or sessionsByPlayer[session.B] ~= session
		or session.CountdownSerial ~= serial
	then
		return
	end
	if
		not playerIsAvailable(session.A)
		or not playerIsAvailable(session.B)
		or not playersAreNear(session.A, session.B)
	then
		cancelSession(session, "A troca foi cancelada porque os jogadores se afastaram.")
		return
	end
	local offerA = copyArray(session.Offers[session.A])
	local offerB = copyArray(session.Offers[session.B])
	local recordsA = companionRecords(session.A, offerA)
	local recordsB = companionRecords(session.B, offerB)
	if not recordsA or not recordsB then
		cancelSession(session, "A oferta mudou e a troca foi cancelada.")
		return
	end

	-- No Studio, DataStore pode estar desabilitado. A troca continua funcional
	-- entre os clientes de teste, sem fingir que os dados temporarios persistem.
	if RunService:IsStudio()
		and (not PlayerDataService.CanSave(session.A) or not PlayerDataService.CanSave(session.B))
	then
		local transferred, transferError = PlayerDataService.TransferCompanions(
			session.A,
			session.B,
			offerA,
			offerB
		)
		if not transferred then
			cancelSession(session, transferError or "A troca de teste nao pode ser concluida.")
			return
		end
		unlockOffer(session.A, offerA)
		unlockOffer(session.B, offerB)
		sessionsByPlayer[session.A] = nil
		sessionsByPlayer[session.B] = nil
		refreshCompanionUI(session.A)
		refreshCompanionUI(session.B)
		publish(session.A, "Completed", "Troca concluida no teste local!", {
			PartnerDisplayName = session.B.DisplayName,
			Temporary = true,
		})
		publish(session.B, "Completed", "Troca concluida no teste local!", {
			PartnerDisplayName = session.A.DisplayName,
			Temporary = true,
		})
		return
	end

	local transactionId = "trade_" .. HttpService:GenerateGUID(false)
	local transaction = {
		SchemaVersion = 1,
		Status = "Prepared",
		CreatedAt = os.time(),
		AUserId = session.A.UserId,
		BUserId = session.B.UserId,
		OfferA = offerA,
		OfferB = offerB,
		RecordsA = recordsA,
		RecordsB = recordsB,
		Recovered = {},
	}
	local stored = retry("Preparar " .. transactionId, function()
		transactionStore:SetAsync(transactionId, transaction)
		return true
	end)
	if not stored then
		cancelSession(session, "Não foi possível proteger a transação. Tente novamente.")
		return
	end
	local indexedA = updateIndex(session.A.UserId, transactionId, true)
	local indexedB = updateIndex(session.B.UserId, transactionId, true)
	if not indexedA or not indexedB then
		updateTransaction(transactionId, function(previous)
			if type(previous) == "table" then
				previous.Status = "Cancelled"
			end
			return previous
		end)
		cancelSession(session, "Não foi possível registrar a transação. Tente novamente.")
		return
	end

	local transferred, transferError = PlayerDataService.TransferCompanions(
		session.A,
		session.B,
		offerA,
		offerB
	)
	if not transferred then
		updateTransaction(transactionId, function(previous)
			if type(previous) == "table" then
				previous.Status = "Cancelled"
				previous.Error = tostring(transferError)
			end
			return previous
		end)
		updateIndex(session.A.UserId, transactionId, false)
		updateIndex(session.B.UserId, transactionId, false)
		cancelSession(session, transferError or "A troca não pôde ser concluída.")
		return
	end

	local savedA = PlayerDataService.Save(session.A, true)
	if savedA then
		if markRecovered(transactionId, session.A.UserId) then
			updateIndex(session.A.UserId, transactionId, false)
		end
	end
	local savedB = PlayerDataService.Save(session.B, true)
	if savedB then
		if markRecovered(transactionId, session.B.UserId) then
			updateIndex(session.B.UserId, transactionId, false)
		end
	end
	unlockOffer(session.A, offerA)
	unlockOffer(session.B, offerB)
	sessionsByPlayer[session.A] = nil
	sessionsByPlayer[session.B] = nil
	refreshCompanionUI(session.A)
	refreshCompanionUI(session.B)
	local message = savedA and savedB
		and "Troca concluída!"
		or "Troca concluída; a sincronização será verificada no próximo acesso."
	publish(session.A, "Completed", message, { PartnerDisplayName = session.B.DisplayName })
	publish(session.B, "Completed", message, { PartnerDisplayName = session.A.DisplayName })
end

local function beginCountdown(session)
	session.CountdownSerial += 1
	local serial = session.CountdownSerial
	session.CountdownEndsAt = workspace:GetServerTimeNow() + CONFIRM_COUNTDOWN
	publishSession(session, "Countdown", "Troca confirmada. Verificando ofertas...")
	task.delay(CONFIRM_COUNTDOWN, function()
		finalizeSession(session, serial)
	end)
end

local function invite(player, targetUserId)
	local target = findPlayer(targetUserId)
	if
		not playerIsAvailable(player)
		or not playerIsAvailable(target)
		or target == player
		or sessionsByPlayer[player]
		or sessionsByPlayer[target]
		or not playersAreNear(player, target)
	then
		return false, "Jogador indisponível."
	end
	local invites = invitesByTarget[target] or {}
	invitesByTarget[target] = invites
	invites[player] = os.clock() + INVITE_LIFETIME
	publish(target, "Invite", player.DisplayName .. " convidou você para uma troca.", {
		FromUserId = player.UserId,
		FromDisplayName = player.DisplayName,
	})
	return true, "Convite enviado."
end

local function accept(player, inviterUserId)
	local inviter = findPlayer(inviterUserId)
	local invites = invitesByTarget[player]
	local expiresAt = inviter and invites and invites[inviter]
	if
		not inviter
		or not expiresAt
		or expiresAt <= os.clock()
		or sessionsByPlayer[player]
		or sessionsByPlayer[inviter]
		or not playerIsAvailable(player)
		or not playerIsAvailable(inviter)
		or not playersAreNear(player, inviter)
	then
		return false, "Convite expirado ou jogador distante."
	end
	invites[inviter] = nil
	local session = {
		Id = "session_" .. HttpService:GenerateGUID(false),
		A = inviter,
		B = player,
		Offers = {
			[inviter] = {},
			[player] = {},
		},
		Locked = {
			[inviter] = false,
			[player] = false,
		},
		Confirmed = {
			[inviter] = false,
			[player] = false,
		},
		AutoUnequipped = {
			[inviter] = {},
			[player] = {},
		},
		CountdownSerial = 0,
		CountdownEndsAt = nil,
		Cancelled = false,
	}
	sessionsByPlayer[inviter] = session
	sessionsByPlayer[player] = session
	publishSession(session, "Started", "Troca iniciada. Slimes equipados serao desequipados ao entrar na oferta.")
	return true, "Troca iniciada."
end

local function mutateOffer(player, instanceId, shouldAdd)
	local session = sessionsByPlayer[player]
	if not session or type(instanceId) ~= "string" then
		return false, "Troca ou companheiro inválido."
	end
	if session.Locked[player] then
		return false, "Destrave sua oferta antes de alterá-la."
	end
	local offer = session.Offers[player]
	local index = table.find(offer, instanceId)
	if shouldAdd then
		local companions = PlayerDataService.GetCompanions(player)
		if
			index
			or #offer >= MAX_OFFER
			or not companions[instanceId]
			or TradeService.IsCompanionLocked(player, instanceId)
		then
			return false, "Esse companheiro não pode entrar na oferta."
		end
		if PlayerDataService.IsCompanionEquipped(player, instanceId) then
			local unequipped = PlayerDataService.SetCompanionEquipped(player, instanceId, false)
			if not unequipped then
				return false, "Nao foi possivel desequipar esse slime para a troca."
			end
			session.AutoUnequipped[player][instanceId] = true
		end
		table.insert(offer, instanceId)
		lockedCompanions[player] = lockedCompanions[player] or {}
		lockedCompanions[player][instanceId] = true
	else
		if not index then
			return false, "Esse companheiro não está na oferta."
		end
		table.remove(offer, index)
		unlockOffer(player, { instanceId })
		if session.AutoUnequipped[player][instanceId] then
			session.AutoUnequipped[player][instanceId] = nil
			PlayerDataService.SetCompanionEquipped(player, instanceId, true)
		end
	end
	resetConfirmations(session)
	publishSession(session, "OfferChanged", "A oferta foi alterada; confirme novamente.")
	return true
end

local function lockOffer(player)
	local session = sessionsByPlayer[player]
	if not session then
		return false, "Nenhuma troca ativa."
	end
	session.Locked[player] = not session.Locked[player]
	session.Confirmed[session.A] = false
	session.Confirmed[session.B] = false
	session.CountdownEndsAt = nil
	session.CountdownSerial += 1
	publishSession(session, "LockChanged")
	return true
end

local function confirm(player)
	local session = sessionsByPlayer[player]
	if not session then
		return false, "Nenhuma troca ativa."
	end
	local partner = session.A == player and session.B or session.A
	if not session.Locked[player] or not session.Locked[partner] then
		return false, "Os dois jogadores precisam travar as ofertas."
	end
	if session.Confirmed[player] then
		return false, "Sua confirmação já foi registrada."
	end
	session.Confirmed[player] = true
	publishSession(session, "ConfirmChanged")
	if session.Confirmed[partner] then
		beginCountdown(session)
	end
	return true
end

local function recoverPlayer(player)
	PlayerDataService.Load(player)
	local loaded, list = retry("Ler índice " .. player.UserId, function()
		return indexStore:GetAsync("User_" .. tostring(player.UserId))
	end)
	if not loaded or type(list) ~= "table" then
		return
	end
	for _, transactionId in ipairs(list) do
		local transactionLoaded, transaction = retry("Recuperar " .. tostring(transactionId), function()
			return transactionStore:GetAsync(transactionId)
		end)
		if
			not transactionLoaded
			or type(transaction) ~= "table"
			or transaction.Status == "Completed"
			or transaction.Status == "Cancelled"
		then
			updateIndex(player.UserId, transactionId, false)
			continue
		end
		local isA = transaction.AUserId == player.UserId
		local isB = transaction.BUserId == player.UserId
		if not isA and not isB then
			updateIndex(player.UserId, transactionId, false)
			continue
		end
		local outgoing = isA and transaction.OfferA or transaction.OfferB
		local incoming = isA and transaction.RecordsB or transaction.RecordsA
		if PlayerDataService.ApplyTradeRecovery(player, outgoing, incoming)
			and PlayerDataService.Save(player, true)
		then
			if markRecovered(transactionId, player.UserId) then
				updateIndex(player.UserId, transactionId, false)
			end
		end
	end
end

local function handleRequest(player, action, payload)
	if action == "Get" then
		return { Success = true, State = stateFor(player) }
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or 0) < REQUEST_INTERVAL then
		return { Success = false, Message = "Aguarde um instante.", State = stateFor(player) }
	end
	lastRequestAt[player] = now
	local success = false
	local message
	if action == "Invite" then
		success, message = invite(player, payload.UserId)
	elseif action == "Accept" then
		success, message = accept(player, payload.UserId)
	elseif action == "Decline" then
		local inviter = findPlayer(payload.UserId)
		local invites = invitesByTarget[player]
		if inviter and invites then
			invites[inviter] = nil
		end
		success, message = true, "Convite recusado."
	elseif action == "Add" then
		success, message = mutateOffer(player, payload.InstanceId, true)
	elseif action == "Remove" then
		success, message = mutateOffer(player, payload.InstanceId, false)
	elseif action == "Lock" then
		success, message = lockOffer(player)
	elseif action == "Confirm" then
		success, message = confirm(player)
	elseif action == "Cancel" then
		success = TradeService.CancelForPlayer(player, "Troca cancelada.")
		message = success and "Troca cancelada." or "Nenhuma troca ativa."
	end
	return { Success = success, Message = message, State = stateFor(player) }
end

function TradeService.Start()
	if started then
		return
	end
	started = true
	request = ensureRemote("RemoteFunction", "TradeRequest")
	event = ensureRemote("RemoteEvent", "TradeEvent")
	request.OnServerInvoke = function(player, action, payload)
		PlayerDataService.Load(player)
		return handleRequest(
			player,
			tostring(action or ""),
			type(payload) == "table" and payload or {}
		)
	end
	local function setup(player)
		task.spawn(recoverPlayer, player)
		player:GetAttributeChangedSignal("IsDowned"):Connect(function()
			if player:GetAttribute("IsDowned") == true then
				TradeService.CancelForPlayer(player, "A troca foi cancelada porque um jogador caiu.")
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		TradeService.CancelForPlayer(player, "O outro jogador saiu do servidor.")
		invitesByTarget[player] = nil
		lockedCompanions[player] = nil
		lastRequestAt[player] = nil
		for target, invites in pairs(invitesByTarget) do
			invites[player] = nil
			if next(invites) == nil then
				invitesByTarget[target] = nil
			end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
	task.spawn(function()
		while started do
			task.wait(1)
			local checked = {}
			for _, session in pairs(sessionsByPlayer) do
				if not checked[session] then
					checked[session] = true
					if
						not playerIsAvailable(session.A)
						or not playerIsAvailable(session.B)
						or not playersAreNear(session.A, session.B)
					then
						cancelSession(session, "Troca cancelada: jogadores indisponíveis ou distantes.")
					end
				end
			end
		end
	end)
end

return TradeService
