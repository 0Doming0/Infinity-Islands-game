local Players = game:GetService("Players")

local DownedService = require(script.Parent.Parent.MVPSystems.DownedService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local DungeonPartyLifeService = {}

DungeonPartyLifeService.States = table.freeze({
	Active = "Active",
	Downed = "Downed",
	Eliminated = "Eliminated",
	Disconnected = "Disconnected",
})

local DEFAULT_DOWNED_SECONDS = 10
local DEFAULT_WIPE_CONFIRM_SECONDS = 1.25
local DEFAULT_DISCONNECT_GRACE_SECONDS = 5
local SKY_BLESSING_DELAY_SECONDS = 1.35
local RESTORE_TIMEOUT_SECONDS = 10
local RESTORE_PROTECTION_SECONDS = 4

local started = false
local options = {}
local participants = {}
local participantSet = {}
local connections = {}
local generation = 0
local wipeGeneration = 0
local wipeActive = false
local wipeStartedAt
local wipeReason

local function now()
	return workspace:GetServerTimeNow()
end

local function safeCallback(name, ...)
	local callback = options[name]
	if type(callback) ~= "function" then
		return nil
	end
	local success, result = pcall(callback, ...)
	if not success then
		warn(string.format("[DungeonPartyLifeService] %s falhou: %s", name, tostring(result)))
		return nil
	end
	return result
end

local function normalizeUserIds(raw)
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

local function lifeRemote()
	return options.RemoteEvent
end

local function recordSnapshot(record)
	return {
		UserId = record.UserId,
		State = record.State,
		Connected = record.Player ~= nil and record.Player.Parent == Players,
		DownedExpiresAt = record.DownedExpiresAt,
		EliminatedAt = record.EliminatedAt,
		SkyBlessingAvailable = record.SkyBlessingAvailable == true,
		RestoringAtReward = record.RestoringAtReward == true,
		LastReason = record.LastReason,
	}
end

local function partyCounts()
	local counts = {
		Active = 0,
		Downed = 0,
		Eliminated = 0,
		Disconnected = 0,
		Connected = 0,
		Total = 0,
	}
	for _, record in pairs(participants) do
		counts.Total += 1
		counts[record.State] = (counts[record.State] or 0) + 1
		if record.Player and record.Player.Parent == Players then
			counts.Connected += 1
		end
	end
	return counts
end

local function snapshot()
	local result = {
		Started = started,
		WipePending = wipeActive,
		WipeStartedAt = wipeStartedAt,
		WipeReason = wipeReason,
		Counts = partyCounts(),
		Participants = {},
	}
	for userId, record in pairs(participants) do
		result.Participants[userId] = recordSnapshot(record)
	end
	return result
end

local function publish(action, targetPlayer, extra)
	local remote = lifeRemote()
	local payload = snapshot()
	payload.Action = action or "LifeSnapshot"
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	if not remote then
		return payload
	end
	if targetPlayer and targetPlayer.Parent == Players then
		remote:FireClient(targetPlayer, payload)
	else
		remote:FireAllClients(payload)
	end
	return payload
end

local function updateWorldAttributes()
	local counts = partyCounts()
	workspace:SetAttribute("DungeonLifeServiceReady", started)
	workspace:SetAttribute("DungeonActivePlayerCount", counts.Active)
	workspace:SetAttribute("DungeonDownedPlayerCount", counts.Downed)
	workspace:SetAttribute("DungeonEliminatedPlayerCount", counts.Eliminated)
	workspace:SetAttribute("DungeonDisconnectedPlayerCount", counts.Disconnected)
	workspace:SetAttribute("DungeonWipePending", wipeActive)
	workspace:SetAttribute("DungeonWipeStartedAt", wipeStartedAt)
	workspace:SetAttribute("DungeonWipeReason", wipeReason)
end

local function applyPlayerState(record)
	local player = record.Player
	if not player or player.Parent ~= Players then
		return
	end
	player:SetAttribute("DungeonLifeState", record.State)
	player:SetAttribute("DungeonLifeStateChangedAt", record.ChangedAt)
	player:SetAttribute("DungeonLifeStateReason", record.LastReason)
	player:SetAttribute("DungeonSkyBlessingAvailable", record.SkyBlessingAvailable == true)
	player:SetAttribute("DungeonDownedExpiresAt", record.DownedExpiresAt)
	player:SetAttribute("DungeonEliminated", record.State == DungeonPartyLifeService.States.Eliminated)
	player:SetAttribute("DungeonSpectating", record.State == DungeonPartyLifeService.States.Eliminated)
	player:SetAttribute("DungeonRewardRespawning", record.RestoringAtReward == true)
	if record.State == DungeonPartyLifeService.States.Eliminated then
		player:SetAttribute("DungeonSpectatorInvisible", true)
		player:SetAttribute("PlayerLifecycleState", "Spectating")
		player:SetAttribute("RespawnState", "Spectating")
	elseif record.State == DungeonPartyLifeService.States.Downed then
		player:SetAttribute("PlayerLifecycleState", "Downed")
	elseif record.State == DungeonPartyLifeService.States.Active then
		player:SetAttribute("DungeonDownedResolution", nil)
		player:SetAttribute("DungeonSpectatorInvisible", nil)
		-- Limpa flags deixadas por versoes antigas do transporte. Os sistemas
		-- atuais usam estados especificos para capa e espectador.
		player:SetAttribute("InvisibleToEnemies", nil)
		local character = player.Character
		if character then
			character:SetAttribute("InvisibleToEnemies", nil)
		end
		if player:GetAttribute("RespawnState") == "Spectating" then
			player:SetAttribute("RespawnState", "Ready")
		end
		player:SetAttribute("PlayerLifecycleState", "Playing")
	end
end

local evaluateParty

local function setState(record, nextState, reason)
	if not record or record.State == nextState then
		if record and reason then
			record.LastReason = tostring(reason)
			applyPlayerState(record)
		end
		return false
	end
	local previousState = record.State
	record.State = nextState
	record.ChangedAt = now()
	record.LastReason = tostring(reason or "Unknown")
	if nextState ~= DungeonPartyLifeService.States.Downed then
		record.DownedExpiresAt = nil
	end
	if nextState == DungeonPartyLifeService.States.Eliminated then
		record.EliminatedAt = record.EliminatedAt or now()
		ObjectiveService.SetParticipantEligible(record.UserId, false)
	elseif nextState == DungeonPartyLifeService.States.Active then
		record.EliminatedAt = nil
		ObjectiveService.SetParticipantEligible(record.UserId, true)
	end
	applyPlayerState(record)
	updateWorldAttributes()
	publish("ParticipantStateChanged", nil, {
		UserId = record.UserId,
		PreviousState = previousState,
		State = nextState,
		Reason = record.LastReason,
	})
	safeCallback("OnParticipantStateChanged", recordSnapshot(record), previousState)
	task.defer(function()
		if started and evaluateParty then
			evaluateParty("ParticipantStateChanged")
		end
	end)
	return true
end

local function livingHumanoid(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function activeBlessingCandidate()
	local candidates = {}
	for _, record in pairs(participants) do
		if record.State == DungeonPartyLifeService.States.Downed
			and record.SkyBlessingAvailable == true
			and record.Player
			and record.Player.Parent == Players
		then
			table.insert(candidates, record)
		end
	end
	table.sort(candidates, function(left, right)
		return (left.DownedExpiresAt or math.huge) < (right.DownedExpiresAt or math.huge)
	end)
	return candidates[1]
end

local function cancelWipe(reason)
	if not wipeActive then
		return false
	end
	wipeGeneration += 1
	wipeActive = false
	local startedAt = wipeStartedAt
	wipeStartedAt = nil
	wipeReason = nil
	updateWorldAttributes()
	publish("WipeCancelled", nil, {
		Reason = reason or "ActiveParticipantRestored",
		PreviousWipeStartedAt = startedAt,
	})
	safeCallback("OnWipeCancelled", reason or "ActiveParticipantRestored")
	return true
end

local function consumeSkyBlessing(record, token)
	local tiedToWipe = token ~= nil
	if not started
		or not record
		or record.State ~= DungeonPartyLifeService.States.Downed
		or record.SkyBlessingAvailable ~= true
		or (tiedToWipe and (token ~= wipeGeneration or not wipeActive))
	then
		return false
	end
	record.SkyBlessingAvailable = false
	applyPlayerState(record)
	publish("SkyBlessingTriggered", nil, {
		UserId = record.UserId,
		RestoreDelaySeconds = SKY_BLESSING_DELAY_SECONDS,
	})
	task.delay(SKY_BLESSING_DELAY_SECONDS, function()
		if not started
			or record.State ~= DungeonPartyLifeService.States.Downed
			or (tiedToWipe and (token ~= wipeGeneration or not wipeActive))
		then
			return
		end
		local revived = DownedService.ForceRevive(record.Player, "SkyBlessing")
		if not revived then
			warn("[DungeonPartyLifeService] SkyBlessing nao conseguiu levantar " .. tostring(record.UserId))
			-- Um personagem pode desaparecer entre o disparo e o revive. Nesse caso,
			-- tenta a proxima bencao disponivel sem iniciar outro wipe paralelo.
			if tiedToWipe then
				local fallback = activeBlessingCandidate()
				if fallback and fallback ~= record then
					consumeSkyBlessing(fallback, token)
				end
			end
		end
	end)
	return true
end

local function beginWipe(reason)
	if wipeActive then
		return false
	end
	wipeActive = true
	wipeStartedAt = now()
	wipeReason = tostring(reason or "NoActiveParticipants")
	wipeGeneration += 1
	local token = wipeGeneration
	updateWorldAttributes()
	publish("WipePending", nil, {
		Reason = wipeReason,
		ConfirmSeconds = DEFAULT_WIPE_CONFIRM_SECONDS,
	})
	safeCallback("OnWipePending", wipeReason, snapshot())

	local blessing = activeBlessingCandidate()
	if blessing then
		consumeSkyBlessing(blessing, token)
	end

	task.spawn(function()
		local emptySince
		local disconnectedSince
		while started and wipeActive and token == wipeGeneration do
			local counts = partyCounts()
			if counts.Active > 0 then
				cancelWipe("ParticipantRecovered")
				return
			end
			if counts.Downed > 0 then
				emptySince = nil
				disconnectedSince = nil
			elseif counts.Connected == 0 then
				disconnectedSince = disconnectedSince or now()
				if now() - disconnectedSince >= DEFAULT_DISCONNECT_GRACE_SECONDS then
					safeCallback("OnAllEliminated", "AllParticipantsDisconnected", snapshot())
					return
				end
			else
				emptySince = emptySince or now()
				if now() - emptySince >= DEFAULT_WIPE_CONFIRM_SECONDS then
					safeCallback("OnAllEliminated", "AllParticipantsEliminated", snapshot())
					return
				end
			end
			task.wait(0.2)
		end
	end)
	return true
end

evaluateParty = function(reason)
	if not started then
		return
	end
	local counts = partyCounts()
	if counts.Active > 0 then
		cancelWipe(reason or "ActiveParticipantPresent")
		return
	end
	if counts.Total > 0 then
		beginWipe(reason or "NoActiveParticipants")
	end
end

local function eliminate(record, reason)
	if not record or record.State == DungeonPartyLifeService.States.Eliminated then
		return false
	end
	record.RestoringAtReward = false
	return setState(record, DungeonPartyLifeService.States.Eliminated, reason or "HumanoidDied")
end

local function finishRewardRestore(record, character, restoreCFrame, restoreToken)
	local player = record.Player
	if not player or player.Parent ~= Players then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", RESTORE_TIMEOUT_SECONDS)
	local root = character:WaitForChild("HumanoidRootPart", RESTORE_TIMEOUT_SECONDS)
	if not humanoid or not root or record.RestoreToken ~= restoreToken then
		record.RestoringAtReward = false
		applyPlayerState(record)
		return
	end
	local deadline = os.clock() + RESTORE_TIMEOUT_SECONDS
	repeat
		task.wait(0.1)
	until player.Parent ~= Players
		or player.Character ~= character
		or player:GetAttribute("RespawnState") == "Ready"
		or os.clock() >= deadline
	if player.Parent ~= Players or player.Character ~= character or record.RestoreToken ~= restoreToken then
		return
	end
	if restoreCFrame then
		character:PivotTo(restoreCFrame * CFrame.new(0, 3, 0))
	end
	local forceField = Instance.new("ForceField")
	forceField.Name = "DungeonRewardReturnProtection"
	forceField.Visible = false
	forceField.Parent = character
	task.delay(RESTORE_PROTECTION_SECONDS, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
	record.RestoringAtReward = false
	record.RestoreCFrame = nil
	record.EliminatedAt = nil
	setState(record, DungeonPartyLifeService.States.Active, "ReturnedAtRewardIsland")
	publish("ReturnedAtRewardIsland", nil, {
		UserId = record.UserId,
		RoundIndex = record.RestoreRoundIndex,
	})
end

local function bindCharacter(record, character)
	if record.DiedConnection then
		record.DiedConnection:Disconnect()
		record.DiedConnection = nil
	end
	record.Character = character
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	record.Humanoid = humanoid
	record.DiedConnection = humanoid.Died:Connect(function()
		if started and participants[record.UserId] == record then
			local player = record.Player
			local cause = player and (
				player:GetAttribute("LastEnemyDamageSource")
				or (player:GetAttribute("WaterContacting") == true and "Water")
			) or nil
			eliminate(record, cause or "HumanoidDied")
		end
	end)
	if record.RestoringAtReward then
		local token = record.RestoreToken
		task.spawn(finishRewardRestore, record, character, record.RestoreCFrame, token)
	elseif record.State ~= DungeonPartyLifeService.States.Eliminated and humanoid.Health > 0 then
		setState(record, DungeonPartyLifeService.States.Active, "CharacterReady")
	end
end

local function disconnectRecordConnections(record)
	for _, connectionName in ipairs({ "CharacterAddedConnection", "DownedConnection", "DiedConnection" }) do
		local connection = record[connectionName]
		if connection then
			connection:Disconnect()
			record[connectionName] = nil
		end
	end
end

local function bindPlayer(player)
	local record = participants[player.UserId]
	if not record then
		return false
	end
	disconnectRecordConnections(record)
	record.Player = player
	player:SetAttribute("DungeonSessionParticipant", true)
	if record.State == DungeonPartyLifeService.States.Disconnected then
		if record.StateBeforeDisconnect == DungeonPartyLifeService.States.Eliminated then
			setState(record, DungeonPartyLifeService.States.Eliminated, "EliminatedParticipantReconnected")
		elseif record.StateBeforeDisconnect == DungeonPartyLifeService.States.Downed then
			-- Desconectar enquanto derrubado nao pode funcionar como revive gratuito.
			-- O participante retorna como eliminado e aguarda a proxima Reward Island.
			setState(record, DungeonPartyLifeService.States.Eliminated, "DownedParticipantReconnected")
		else
			record.StateBeforeDisconnect = nil
		end
	end
	record.CharacterAddedConnection = player.CharacterAdded:Connect(function(character)
		bindCharacter(record, character)
	end)
	record.DownedConnection = player:GetAttributeChangedSignal("IsDowned"):Connect(function()
		if not started or participants[record.UserId] ~= record then
			return
		end
		if player:GetAttribute("IsDowned") == true then
			record.DownedExpiresAt = tonumber(player:GetAttribute("DownedExpiresAt"))
			setState(record, DungeonPartyLifeService.States.Downed, "FatalDamageIntercepted")
			consumeSkyBlessing(record, nil)
		elseif record.State == DungeonPartyLifeService.States.Downed then
			local resolution = player:GetAttribute("DungeonDownedResolution")
			if resolution ~= "Eliminated" and livingHumanoid(player) then
				setState(
					record,
					DungeonPartyLifeService.States.Active,
					resolution == "SkyBlessing" and "SkyBlessing" or "Revived"
				)
			end
		end
	end)
	if player.Character then
		bindCharacter(record, player.Character)
	elseif record.State == DungeonPartyLifeService.States.Eliminated then
		applyPlayerState(record)
	end
	ObjectiveService.SetParticipantConnected(player.UserId, true)
	publish("LifeSnapshot", player)
	return true
end

local function playerAdded(player)
	if participantSet[player.UserId] then
		bindPlayer(player)
	end
end

local function playerRemoving(player)
	local record = participants[player.UserId]
	if not record then
		return
	end
	record.StateBeforeDisconnect = record.State
	disconnectRecordConnections(record)
	record.Player = nil
	record.Character = nil
	record.Humanoid = nil
	ObjectiveService.SetParticipantConnected(player.UserId, false)
	setState(record, DungeonPartyLifeService.States.Disconnected, "PlayerRemoving")
end

function DungeonPartyLifeService.Start(startOptions)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	participants = {}
	local userIds
	userIds, participantSet = normalizeUserIds(options.ParticipantUserIds)
	generation += 1
	wipeGeneration += 1
	wipeActive = false
	wipeStartedAt = nil
	wipeReason = nil

	workspace:SetAttribute("DungeonDownedDurationSeconds", DEFAULT_DOWNED_SECONDS)
	workspace:SetAttribute("DungeonReviveWeaknessSeconds", 12)
	workspace:SetAttribute("DungeonRewardRespawnEnabled", true)

	for _, userId in ipairs(userIds) do
		participants[userId] = {
			UserId = userId,
			State = DungeonPartyLifeService.States.Disconnected,
			ChangedAt = now(),
			LastReason = "WaitingForParticipant",
			SkyBlessingAvailable = true,
		}
	end
	DownedService.Start()
	connections.PlayerAdded = Players.PlayerAdded:Connect(playerAdded)
	connections.PlayerRemoving = Players.PlayerRemoving:Connect(playerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		playerAdded(player)
	end
	updateWorldAttributes()
	publish("LifeServiceStarted")
	task.defer(function()
		if started and evaluateParty then
			evaluateParty("LifeServiceStarted")
		end
	end)
end

function DungeonPartyLifeService.Stop()
	if not started then
		return
	end
	started = false
	wipeGeneration += 1
	wipeActive = false
	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
	connections = {}
	for _, record in pairs(participants) do
		disconnectRecordConnections(record)
	end
	workspace:SetAttribute("DungeonLifeServiceReady", false)
	workspace:SetAttribute("DungeonWipePending", false)
	options = {}
end

function DungeonPartyLifeService.BindPlayer(player)
	if not started or not player or not participantSet[player.UserId] then
		return false
	end
	return bindPlayer(player)
end

function DungeonPartyLifeService.RestoreEliminatedAtReward(roundIndex, safeSpawn)
	if not started then
		return 0
	end
	local restoreCFrame
	if typeof(safeSpawn) == "Instance" and safeSpawn:IsA("BasePart") then
		restoreCFrame = safeSpawn.CFrame
	elseif typeof(safeSpawn) == "CFrame" then
		restoreCFrame = safeSpawn
	end
	local restored = 0
	for _, record in pairs(participants) do
		local player = record.Player
		if record.State == DungeonPartyLifeService.States.Eliminated
			and player
			and player.Parent == Players
			and not record.RestoringAtReward
		then
			record.RestoringAtReward = true
			record.RestoreRoundIndex = math.max(1, math.floor(tonumber(roundIndex) or 1))
			record.RestoreCFrame = restoreCFrame
			record.RestoreToken = (record.RestoreToken or 0) + 1
			applyPlayerState(record)
			local loaded, loadError = pcall(player.LoadCharacter, player)
			if loaded then
				restored += 1
			else
				record.RestoringAtReward = false
				applyPlayerState(record)
				warn("[DungeonPartyLifeService] Retorno na recompensa falhou: " .. tostring(loadError))
			end
		end
	end
	if restored > 0 then
		publish("RewardRespawnStarted", nil, {
			RoundIndex = roundIndex,
			PlayerCount = restored,
		})
	end
	return restored
end

function DungeonPartyLifeService.MarkDisconnected(userId, reason)
	local record = participants[math.floor(tonumber(userId) or 0)]
	if not record then
		return false
	end
	-- PlayerRemoving tambem e observado internamente. Uma segunda chamada nao
	-- pode substituir StateBeforeDisconnect por Disconnected, pois esse valor
	-- decide se um eliminado continua espectador ao reconectar.
	if record.State == DungeonPartyLifeService.States.Disconnected then
		return false
	end
	record.StateBeforeDisconnect = record.State
	record.Player = nil
	return setState(record, DungeonPartyLifeService.States.Disconnected, reason or "Disconnected")
end

function DungeonPartyLifeService.GetPlayerState(playerOrUserId)
	local userId = typeof(playerOrUserId) == "Instance"
		and playerOrUserId:IsA("Player")
		and playerOrUserId.UserId
		or math.floor(tonumber(playerOrUserId) or 0)
	local record = participants[userId]
	return record and record.State or nil
end

function DungeonPartyLifeService.IsEliminated(playerOrUserId)
	return DungeonPartyLifeService.GetPlayerState(playerOrUserId)
		== DungeonPartyLifeService.States.Eliminated
end

function DungeonPartyLifeService.GetSnapshot()
	return snapshot()
end

return DungeonPartyLifeService
