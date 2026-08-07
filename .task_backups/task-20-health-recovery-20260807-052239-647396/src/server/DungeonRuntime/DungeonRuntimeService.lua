local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local GameContext = require(ReplicatedStorage.Shared.GameContext)
local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local PlaceConfig = require(ReplicatedStorage.Shared.Configs.PlaceConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)

local ChunkManager = require(script.Parent.Parent.BlockParkour.ChunkManager_SkyDungeon_V10)
local PlayerDataService = require(script.Parent.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10)
local PartyService = require(script.Parent.Parent.BlockParkour.PartyService)
local BossService = require(script.Parent.BossService)
local ContentResolver = require(script.Parent.ContentResolver)
local DungeonGenerator = require(script.Parent.DungeonGenerator)
local DungeonStateMachine = require(script.Parent.DungeonStateMachine)
local DungeonPartyLifeService = require(script.Parent.DungeonPartyLifeService)
local DungeonResultCommitService = require(script.Parent.DungeonResultCommitService)
local DungeonReturnService = require(script.Parent.DungeonReturnService)
local DungeonLegacyIsolationService = require(script.Parent.DungeonLegacyIsolationService)
local DungeonSpawnService = require(script.Parent.DungeonSpawnService)
local ObjectiveEncounterService = require(script.Parent.ObjectiveEncounterService)
local ObjectiveSequenceService = require(script.Parent.ObjectiveSequenceService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local RewardIslandService = require(script.Parent.RewardIslandService)
local RunRewardLedgerService = require(script.Parent.RunRewardLedgerService)
local PhaseRegistry = require(script.Parent.PhaseRegistry)
local RuntimeFolders = require(script.Parent.RuntimeFolders)

local DungeonRuntimeService = {}
local started = false
local session
local stateMachine
local resultEvent
local objectiveEvent
local rewardEvent
local lifeEvent
local bossEvent

local function copyUserIds(raw)
	local result = {}
	local seen = {}
	if type(raw) == "table" then
		for _, userId in ipairs(raw) do
			local clean = math.floor(tonumber(userId) or 0)
			if clean > 0 and not seen[clean] then
				seen[clean] = true
				table.insert(result, clean)
			end
		end
	end
	return result, seen
end

local function developmentSession(player)
	local requestedPhase = workspace:GetAttribute("StudioPhaseId")
	local phaseId = PhaseConfig.IsValid(requestedPhase) and requestedPhase or PhaseConfig.GetDefaultId()
	if not phaseId then
		return nil, "Nenhuma fase valida foi descoberta em ServerStorage/GameContent/Phases"
	end
	return {
		Version = 1,
		SessionId = "studio-" .. HttpService:GenerateGUID(false),
		PhaseId = phaseId,
		PartySize = 1,
		LeaderUserId = player.UserId,
		PartyUserIds = { player.UserId },
		Seed = Random.new():NextInteger(1, 2147483646),
		DevelopmentMode = true,
	}
end

local function sanitizeTeleportData(player, raw)
	if type(raw) ~= "table" or not PhaseConfig.IsValid(raw.PhaseId) then
		if RunService:IsStudio() then
			return developmentSession(player)
		end
		return nil, "TeleportData ausente ou PhaseId invalido"
	end
	local userIds, userSet = copyUserIds(raw.PartyUserIds)
	if #userIds == 0 or not userSet[player.UserId] then
		return nil, "Jogador nao pertence a sessao"
	end
	local size = math.clamp(math.floor(tonumber(raw.PartySize) or #userIds), 1, 4)
	if size ~= #userIds then
		return nil, "PartySize inconsistente"
	end
	local sessionId = type(raw.SessionId) == "string" and raw.SessionId or ""
	if sessionId == "" then
		return nil, "SessionId ausente"
	end
	return {
		Version = 1,
		SessionId = sessionId,
		PhaseId = raw.PhaseId,
		PartySize = size,
		LeaderUserId = math.floor(tonumber(raw.LeaderUserId) or 0),
		PartyUserIds = userIds,
		PartyUserSet = userSet,
		Seed = math.clamp(math.floor(tonumber(raw.Seed) or 1), 1, 2147483646),
		DevelopmentMode = false,
	}
end

local function compatibleSession(left, right)
	return left.SessionId == right.SessionId
		and left.PhaseId == right.PhaseId
		and left.PartySize == right.PartySize
end

local function transitionState(nextState, context)
	if not stateMachine then
		return false, "StateMachineUnavailable"
	end
	local success, errorCode = stateMachine:Transition(nextState, context)
	if not success then
		warn(string.format(
			"[DungeonRuntime] Transicao de estado rejeitada: %s -> %s (%s)",
			tostring(stateMachine:GetState()),
			tostring(nextState),
			tostring(errorCode)
		))
	end
	return success, errorCode
end

local function teleportBack(player, reason)
	if PlaceConfig.LobbyPlaceId <= 0 then
		player:SetAttribute("DungeonJoinRejected", reason)
		warn("[DungeonRuntime] " .. player.Name .. " rejeitado: " .. reason)
		return
	end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		ReturnReason = "InvalidSession",
		PhaseId = session and session.PhaseId or PhaseConfig.GetDefaultId(),
	})
	pcall(TeleportService.TeleportAsync, TeleportService, PlaceConfig.LobbyPlaceId, { player }, options)
end

local function sessionPlayers()
	local result = {}
	if not session then
		return result
	end
	for _, userId in ipairs(session.PartyUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(result, player)
		end
	end
	return result
end

local function loadSessionPlayer(player)
	local data = PlayerDataService.Load(player)
	if not data then
		return false
	end
	player:SetAttribute("DungeonSessionId", session.SessionId)
	player:SetAttribute("DungeonPhaseId", session.PhaseId)
	player:SetAttribute("DungeonInitialPartySize", session.PartySize)
	if session.Completed then
		player:SetAttribute("DungeonEliminated", true)
		player:SetAttribute("DungeonLifeState", "Spectating")
		player:SetAttribute("DungeonSpectating", true)
		player:SetAttribute("DungeonSkyBlessingAvailable", false)
	else
		player:SetAttribute("DungeonEliminated", false)
		player:SetAttribute("DungeonLifeState", "Active")
		player:SetAttribute("DungeonSpectating", false)
		player:SetAttribute("DungeonSkyBlessingAvailable", true)
	end
	-- A Dungeon possui combate real mesmo quando o tutorial persistente ainda
	-- nao foi concluido no Lobby. O booleano explicito evita imunidade ilimitada.
	player:SetAttribute("TutorialEnemyProtection", false)
	-- O Lobby ja representa a tela de entrada da experiencia. Ao chegar neste
	-- Place, o jogador deve nascer automaticamente; o fluxo legado de
	-- StartScreen nao pode voltar a coloca-lo em AwaitingStart.
	player:SetAttribute("DungeonRuntimeAutoStart", true)
	player:SetAttribute("InitialGameStarted", true)
	player:SetAttribute("InitialSpawnPositioned", false)
	player:SetAttribute("InitialStartState", "Positioning")
	player:SetAttribute("PlayerLifecycleState", "InitialSpawning")
	DungeonSpawnService.BindPlayer(player)
	local lifeServiceReady = workspace:GetAttribute("DungeonLifeServiceReady") == true
	if lifeServiceReady then
		DungeonPartyLifeService.BindPlayer(player)
	end
	local lifeState = lifeServiceReady
		and DungeonPartyLifeService.GetPlayerState(player.UserId)
		or nil
	-- Espectadores eliminados nao precisam de um personagem fisico ao reconectar.
	-- Evita criar um corpo vivo/colidivel que ficaria parado dentro da Dungeon.
	if lifeState == DungeonPartyLifeService.States.Eliminated then
		if player.Character then
			player.Character:Destroy()
		end
	elseif not player.Character then
		player:LoadCharacter()
	end
	if workspace:GetAttribute("DungeonObjectiveServiceReady") == true then
		ObjectiveService.SetParticipantConnected(player.UserId, true)
	end
	return true
end

local function resultPayloadFor(userId, definition, elapsed, returnDelay, returnAt)
	local committed = session.ResultCommitResults and session.ResultCommitResults[userId] or {
		Success = false,
		Applied = false,
		AlreadyProcessed = false,
		Eligible = false,
		Error = "MissingCommitResult",
	}
	local record = committed.Record or {}
	return {
		Action = "Result",
		Result = session.Result,
		PhaseId = session.PhaseId,
		PhaseName = definition.DisplayName,
		RewardCoins = math.max(0, math.floor(tonumber(record.RewardCoins) or 0)),
		Balance = math.max(0, math.floor(tonumber(record.Balance) or 0)),
		Completions = math.max(0, math.floor(tonumber(record.Completions) or 0)),
		BestTime = tonumber(record.BestTime),
		ElapsedSeconds = elapsed,
		Saved = committed.Success == true,
		Applied = committed.Applied == true,
		AlreadyProcessed = committed.AlreadyProcessed == true,
		EligibleForBossReward = committed.Eligible == true,
		ResultId = committed.ResultId,
		SaveError = committed.Error,
		ReturnDelay = returnDelay,
		ReturnAt = returnAt,
		ManualReturnAt = session.ResultManualReturnAt,
	}
end

local function sendResultToPlayer(player)
	if not session or not session.Completed or not resultEvent then
		return false
	end
	local payload = session.ResultPayloads and session.ResultPayloads[player.UserId]
	if not payload then
		return false
	end
	resultEvent:FireClient(player, payload)
	return true
end

local function freezeResultPlayer(player)
	player:SetAttribute("DungeonResultShown", true)
	player:SetAttribute("DungeonSpectating", false)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character then
		character:SetAttribute("MovementLocked", true)
	end
	if humanoid and humanoid.Health > 0 then
		humanoid:UnequipTools()
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		humanoid:Move(Vector3.zero)
	end
end

local function resultIdsFrom(commitResults)
	local result = {}
	for userId, committed in pairs(type(commitResults) == "table" and commitResults or {}) do
		if committed and type(committed.ResultId) == "string" then
			result[userId] = committed.ResultId
		end
	end
	return result
end

local function notifyResultSaveUpdate(definition, elapsed)
	for _, player in ipairs(sessionPlayers()) do
		local committed = session.ResultCommitResults[player.UserId]
		local record = committed and committed.Record or {}
		resultEvent:FireClient(player, {
			Action = "ResultSaveUpdated",
			Saved = committed and committed.Success == true or false,
			SaveError = committed and committed.Error or "MissingCommitResult",
			RewardCoins = math.max(0, math.floor(tonumber(record.RewardCoins) or 0)),
			Balance = math.max(0, math.floor(tonumber(record.Balance) or 0)),
			Completions = math.max(0, math.floor(tonumber(record.Completions) or 0)),
			BestTime = tonumber(record.BestTime),
			ElapsedSeconds = elapsed,
		})
	end
end

local finishSession

finishSession = function(reason)
	if not session or session.Completed then
		return
	end
	local resultState = reason == "Victory"
		and DungeonStateMachine.States.Victory
		or DungeonStateMachine.States.Defeat
	transitionState(resultState, {
		Reason = reason,
		Force = true,
	})
	session.Completed = true
	session.Active = false
	session.Result = reason
	local bossEligibleUserIds = reason == "Victory"
		and BossService.GetEligibleUserIds()
		or {}
	BossService.Stop()
	DungeonPartyLifeService.Stop()
	ObjectiveEncounterService.Stop()
	RewardIslandService.Stop()
	RunRewardLedgerService.Stop()
	ObjectiveSequenceService.Stop()
	ObjectiveService.Stop()
	ChunkManager.Stop()
	workspace:SetAttribute("DungeonCombatStopped", true)
	for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if model:IsA("Model") then
			model:SetAttribute("SimulationActive", false)
			model:SetAttribute("Invulnerable", true)
			local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
			local root = model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
			if humanoid and root and root:IsA("BasePart") then
				humanoid:MoveTo(root.Position)
			end
		end
	end
	local definition = PhaseConfig.Get(session.PhaseId) or {
		DisplayName = session.PhaseId,
		VictoryCoins = 0,
	}
	local elapsed = session.StartedAt
		and math.max(0, workspace:GetServerTimeNow() - session.StartedAt)
		or 0
	local commitOptions = {
		SessionId = session.SessionId,
		PhaseId = session.PhaseId,
		Result = reason,
		ParticipantUserIds = session.PartyUserIds,
		EligibleUserIds = bossEligibleUserIds,
		ElapsedSeconds = elapsed,
		VictoryCoins = definition.VictoryCoins,
	}
	session.ResultCommitOptions = commitOptions
	local allCommitted, commitResults, commitError =
		DungeonResultCommitService.CommitSession(commitOptions)
	session.ResultCommitResults = commitResults
	session.ResultCommitError = commitError
	workspace:SetAttribute("DungeonResultSaved", allCommitted == true)
	workspace:SetAttribute("DungeonResultSaveError", commitError)

	local returnDelay = allCommitted and 8 or 16
	local resultNow = workspace:GetServerTimeNow()
	local returnAt = resultNow + returnDelay
	session.ResultReturnAt = returnAt
	session.ResultManualReturnAt = allCommitted and resultNow or resultNow + 10
	session.ResultPayloads = {}
	for _, userId in ipairs(session.PartyUserIds) do
		session.ResultPayloads[userId] = resultPayloadFor(
			userId,
			definition,
			elapsed,
			returnDelay,
			returnAt
		)
	end
	for _, player in ipairs(sessionPlayers()) do
		freezeResultPlayer(player)
		sendResultToPlayer(player)
	end

	DungeonReturnService.Begin({
		SessionId = session.SessionId,
		PhaseId = session.PhaseId,
		Result = reason,
		ResultSaved = allCommitted == true,
		ParticipantUserIds = session.PartyUserIds,
		ReturnAt = returnAt,
		ManualReturnAt = session.ResultManualReturnAt,
		CompletedAt = os.time(),
		ResultIds = resultIdsFrom(commitResults),
	})

	if not allCommitted then
		task.spawn(function()
			for _, delaySeconds in ipairs({ 3, 7 }) do
				task.wait(delaySeconds)
				if not session or not session.Completed or workspace:GetAttribute("DungeonResultSaved") == true then
					return
				end
				local retryCommitted, retryResults, retryError =
					DungeonResultCommitService.CommitSession(commitOptions)
				session.ResultCommitResults = retryResults
				session.ResultCommitError = retryError
				workspace:SetAttribute("DungeonResultSaved", retryCommitted == true)
				workspace:SetAttribute("DungeonResultSaveError", retryError)
				for _, userId in ipairs(session.PartyUserIds) do
					session.ResultPayloads[userId] = resultPayloadFor(
						userId,
						definition,
						elapsed,
						returnDelay,
						returnAt
					)
				end
				DungeonReturnService.UpdateResultSaved(
					retryCommitted == true,
					resultIdsFrom(retryResults)
				)
				notifyResultSaveUpdate(definition, elapsed)
				if retryCommitted then
					return
				end
			end
		end)
	end
end

local function startBossEncounter(arenaContext)
	if session.Completed then
		return false, "SessionCompleted"
	end
	local phase = PhaseConfig.Get(session.PhaseId)
	if not phase then
		return false, "PhaseUnavailable"
	end
	local created, bossStateOrError = BossService.Create({
		SessionId = session.SessionId,
		PhaseId = session.PhaseId,
		BossId = phase.BossId,
		PartySize = session.PartySize,
		ParticipantUserIds = session.PartyUserIds,
		Seed = session.Seed,
		ArenaContext = arenaContext,
		RemoteEvent = bossEvent,
		OnActivated = function(snapshot)
			if session.Completed then
				return
			end
			transitionState(DungeonStateMachine.States.BossActive, {
				Reason = "BossArenaActivated",
				BossId = snapshot and snapshot.BossId,
			})
		end,
		OnDefeated = function()
			if not session.Completed then
				finishSession("Victory")
			end
		end,
	})
	if not created then
		workspace:SetAttribute("DungeonBossCreationError", tostring(bossStateOrError))
		warn("[DungeonRuntime] Criacao do chefe falhou: " .. tostring(bossStateOrError))
		return false, bossStateOrError
	end
	workspace:SetAttribute("DungeonBossState", "Ready")
	workspace:SetAttribute("DungeonBossPreparedAt", workspace:GetServerTimeNow())
	return true, bossStateOrError
end

local function beginWorld()
	if session.WorldStarted then
		return
	end
	session.WorldStarted = true
	session.StartedAt = workspace:GetServerTimeNow()
	PartyService.Start()
	PartyService.RestoreDungeonParty(
		sessionPlayers(),
		session.LeaderUserId,
		session.PhaseId,
		session.SessionId
	)
	local phase = PhaseConfig.Get(session.PhaseId)
	if not phase then
		warn("[DungeonRuntime] A fase deixou de estar disponivel: " .. tostring(session.PhaseId))
		finishSession("InvalidSession")
		return
	end
	workspace:SetAttribute("DungeonSessionId", session.SessionId)
	workspace:SetAttribute("DungeonPhaseId", session.PhaseId)
	workspace:SetAttribute("DungeonPartySize", session.PartySize)
	workspace:SetAttribute("DungeonSeed", session.Seed)
	workspace:SetAttribute("DungeonGenerationState", "Generating")
	workspace:SetAttribute("DungeonCombatStopped", false)
	workspace:SetAttribute("DungeonIslandBlockColor", phase.IslandBlockColor)
	workspace:SetAttribute("DungeonIslandBlockMaterial", phase.IslandBlockMaterial)
	workspace:SetAttribute("DungeonIslandBlockTextureId", phase.IslandBlockTextureId)
	workspace:SetAttribute("DungeonTextureStudsPerTileU", phase.TextureStudsPerTileU)
	workspace:SetAttribute("DungeonTextureStudsPerTileV", phase.TextureStudsPerTileV)
	workspace:SetAttribute("DungeonMaximumActiveMonsters", phase.MaximumActiveMonsters)
	workspace:SetAttribute("DungeonEliteReservedMonsterSlots", phase.EliteReservedMonsterSlots)
	workspace:SetAttribute("DungeonDefaultMonsterSpawnChance", phase.DefaultMonsterSpawnChance)
	workspace:SetAttribute("DungeonDecorationSpawnChance", phase.DecorationSpawnChance)
	workspace:SetAttribute("DungeonSessionClosed", false)

	ObjectiveService.Start({
		SessionId = session.SessionId,
		PhaseId = session.PhaseId,
		ParticipantUserIds = session.PartyUserIds,
		RemoteEvent = objectiveEvent,
		OnObjectiveCompleted = function(snapshot)
			local sequenceResult = ObjectiveSequenceService.HandleObjectiveCompleted(snapshot)
			ObjectiveEncounterService.CompleteObjective(snapshot.Id)
			if sequenceResult and stateMachine:GetState() == DungeonStateMachine.States.Active then
				transitionState(
					sequenceResult.IsRewardIsland
						and DungeonStateMachine.States.RoundReward
						or DungeonStateMachine.States.ObjectiveComplete,
					{
						Reason = snapshot.CompletionReason,
						ObjectiveId = snapshot.Id,
						GlobalIslandIndex = snapshot.GlobalIslandIndex,
					}
				)
			end
		end,
		OnWaypointEscalated = function(snapshot)
			workspace:SetAttribute("DungeonObjectiveWaypointEscalatedAt", workspace:GetServerTimeNow())
			workspace:SetAttribute("DungeonObjectiveWaypointId", snapshot.Id)
			ObjectiveSequenceService.EscalateWaypoint()
		end,
		OnRecoveryRequested = function(snapshot)
			workspace:SetAttribute("DungeonObjectiveRecoveryRequestedAt", workspace:GetServerTimeNow())
			workspace:SetAttribute("DungeonObjectiveRecoveryId", snapshot.Id)
			return ObjectiveSequenceService.RecoverCurrentObjective(snapshot)
		end,
	})

	DungeonPartyLifeService.Start({
		ParticipantUserIds = session.PartyUserIds,
		RemoteEvent = lifeEvent,
		OnWipePending = function(reason)
			local current = stateMachine:GetState()
			if current ~= DungeonStateMachine.States.WipePending then
				session.PreWipeState = current
				transitionState(DungeonStateMachine.States.WipePending, {
					Reason = reason,
					Force = true,
				})
			end
		end,
		OnWipeCancelled = function(reason)
			if session.Completed then
				return
			end
			local restoreState = session.PreWipeState
			if restoreState == nil
				or restoreState == DungeonStateMachine.States.WipePending
				or restoreState == DungeonStateMachine.States.Victory
				or restoreState == DungeonStateMachine.States.Defeat
				or restoreState == DungeonStateMachine.States.Returning
			then
				restoreState = DungeonStateMachine.States.Active
			end
			session.PreWipeState = nil
			transitionState(restoreState, {
				Reason = reason or "WipeCancelled",
				Force = true,
			})
		end,
		OnAllEliminated = function(reason)
			if not session.Completed then
				finishSession(reason == "AllParticipantsDisconnected" and "Disconnected" or "Defeat")
			end
		end,
	})

	ObjectiveEncounterService.Start({
		PartySize = session.PartySize,
		ParticipantUserIds = session.PartyUserIds,
	})

	RunRewardLedgerService.Start({
		SessionId = session.SessionId,
		ParticipantUserIds = session.PartyUserIds,
	})
	RewardIslandService.Start({
		SessionId = session.SessionId,
		PhaseId = session.PhaseId,
		ParticipantUserIds = session.PartyUserIds,
		RemoteEvent = rewardEvent,
		CommitRoundReward = function(roundIndex, metadata)
			return ObjectiveSequenceService.CommitRoundReward(roundIndex, metadata)
		end,
	})

	ObjectiveSequenceService.Start({
		PartySize = session.PartySize,
		ParticipantUserIds = session.PartyUserIds,
		GetIslandContext = DungeonGenerator.GetRouteIslandContext,
		RequestRouteThrough = DungeonGenerator.RequestRouteThrough,
		OnObjectiveStarted = function(definition, islandContext)
			local currentState = stateMachine:GetState()
			if currentState ~= DungeonStateMachine.States.Active then
				transitionState(DungeonStateMachine.States.Active, {
					Reason = "ObjectiveStarted",
					ObjectiveId = definition.Id,
					GlobalIslandIndex = definition.GlobalIslandIndex,
				})
			end
			local encounterStarted, encounterError = ObjectiveEncounterService.BeginObjective(
				definition,
				islandContext
			)
			if not encounterStarted then
				workspace:SetAttribute("DungeonEncounterStartError", tostring(encounterError))
				warn("[DungeonRuntime] Encontro do objetivo falhou: " .. tostring(encounterError))
			end
		end,
		OnRoundRewardPending = function(result, islandContext)
			DungeonPartyLifeService.RestoreEliminatedAtReward(
				result.RoundIndex,
				islandContext and islandContext.SafeSpawn
			)
			workspace:SetAttribute("DungeonRoundRewardPending", true)
			workspace:SetAttribute("DungeonRoundRewardIndex", result.RoundIndex)
			workspace:SetAttribute("DungeonRoundRewardIsland", result.GlobalIslandIndex)
			local rewardStarted, rewardError = RewardIslandService.BeginRound(result, islandContext)
			if not rewardStarted then
				workspace:SetAttribute("DungeonRoundRewardError", tostring(rewardError))
				warn("[DungeonRuntime] Reward Island falhou: " .. tostring(rewardError))
			end
		end,
		OnRoundRewardCommitted = function(roundIndex, isFinal, roundExitContext)
			workspace:SetAttribute("DungeonRoundRewardPending", false)
			workspace:SetAttribute("DungeonLastCommittedRewardRound", roundIndex)
			local checkpointUpdated, checkpointError = DungeonSpawnService.CommitRoundCheckpoint(
				roundIndex,
				roundExitContext,
				"RoundExitCommitted:" .. tostring(roundIndex),
				false
			)
			workspace:SetAttribute("DungeonRoundCheckpointReady", checkpointUpdated == true)
			workspace:SetAttribute(
				"DungeonRoundCheckpointError",
				checkpointUpdated and nil or tostring(checkpointError)
			)
			if not checkpointUpdated then
				warn("[DungeonRuntime] Checkpoint do round falhou: " .. tostring(checkpointError))
			end
			if not isFinal then
				transitionState(DungeonStateMachine.States.Transitioning, {
					Reason = "RoundRewardCommitted",
					RoundIndex = roundIndex,
				})
			end
		end,
		OnFinalRewardCommitted = function(finalContext)
			local created, bossContextOrError = DungeonGenerator.CreateBossSanctuary({
				Reason = "FinalRewardCommitted",
				GenerationOwnerUserId = session.LeaderUserId,
			})
			if not created then
				workspace:SetAttribute("DungeonBossSanctuaryError", tostring(bossContextOrError))
				return false
			end
			session.BossSanctuaryContext = bossContextOrError
			transitionState(DungeonStateMachine.States.BossPending, {
				Reason = "FinalRewardCommitted",
				RouteEndKey = finalContext and finalContext.Key,
			})
			local bossPrepared, bossError = startBossEncounter(bossContextOrError)
			if not bossPrepared then
				workspace:SetAttribute("DungeonBossState", "CreationFailed")
				return false, bossError
			end
			return true
		end,
		OnRouteRejected = function(player, requestedIndex, reason, allowedIndex)
			objectiveEvent:FireClient(player, {
				Action = "RouteRejected",
				RequestedIslandIndex = requestedIndex,
				AllowedIslandIndex = allowedIndex,
				Reason = reason,
			})
		end,
		OnRecoveryRequested = function(definition, islandContext, snapshot)
			return ObjectiveEncounterService.Recover(definition, islandContext, snapshot)
		end,
	})

	local success, errorMessage = DungeonGenerator.Generate({
		PhaseId = session.PhaseId,
		PartySize = session.PartySize,
		Seed = session.Seed,
		MaximumIslandCount = phase.BaseIslandCount,
		OnRouteIslandEntered = function(player, islandContext)
			return ObjectiveSequenceService.HandleIslandEntered(player, islandContext)
		end,
		OnBossSanctuaryReady = function(bossContext)
			session.BossSanctuaryContext = bossContext
			workspace:SetAttribute("DungeonBossSanctuaryReadyAt", workspace:GetServerTimeNow())
		end,
		OnPhaseReady = function(endContext)
			if session.Completed then
				return
			end
			-- A rota completa ja foi planejada e materializada, mas o santuario do
			-- chefe permanece bloqueado ate a recompensa final. A tarefa dos
			-- objetivos chamara DungeonGenerator.CreateBossSanctuary no momento certo.
			session.RouteEndContext = endContext
			workspace:SetAttribute("DungeonRouteReady", true)
			workspace:SetAttribute("DungeonRouteReadyAt", workspace:GetServerTimeNow())
			workspace:SetAttribute("DungeonBossState", "WaitingForFinalReward")
			stateMachine:PublishCurrent({
				Reason = "FixedRouteReady",
				RouteEndKey = endContext and endContext.Key,
			})
		end,
	})
	workspace:SetAttribute("DungeonRuntimeReady", success == true)
	if success then
		workspace:SetAttribute("DungeonGenerationState", "Ready")
		local initialContext = DungeonGenerator.GetRouteIslandContext(1)
		local positioned, positionError = DungeonSpawnService.SetInitialCheckpoint(
			initialContext,
			"InitialWorldReady",
			true
		)
		if not positioned then
			workspace:SetAttribute("DungeonInitialSpawnError", tostring(positionError))
			warn("[DungeonRuntime] Spawn inicial falhou: " .. tostring(positionError))
		end
		transitionState(DungeonStateMachine.States.Active, {
			Reason = "InitialWorldReady",
		})
	else
		workspace:SetAttribute("DungeonGenerationState", "Failed")
		workspace:SetAttribute("DungeonGenerationError", tostring(errorMessage))
		warn("[DungeonRuntime] Geracao falhou: " .. tostring(errorMessage))
		finishSession("FailedToGenerate")
	end
end

local function acceptPlayer(player)
	local joinData = player:GetJoinData()
	local parsed, errorMessage = sanitizeTeleportData(player, joinData and joinData.TeleportData)
	if not parsed then
		teleportBack(player, errorMessage)
		return false
	end
	if session and session.DevelopmentMode and parsed.DevelopmentMode then
		if not session.PartyUserSet[player.UserId] and #session.PartyUserIds < 4 then
			table.insert(session.PartyUserIds, player.UserId)
			session.PartyUserSet[player.UserId] = true
			session.PartySize = #session.PartyUserIds
		end
	elseif session and not compatibleSession(session, parsed) then
		teleportBack(player, "Servidor reservado pertence a outra sessao")
		return false
	end
	if not session then
		session = parsed
		session.Active = true
		session.Completed = false
		session.WorldStarted = false
	end
	if not session.PartyUserSet then
		local _, set = copyUserIds(session.PartyUserIds)
		session.PartyUserSet = set
	end
	if not session.PartyUserSet[player.UserId] then
		teleportBack(player, "Jogador fora da lista da sessao")
		return false
	end
	return loadSessionPlayer(player)
end

function DungeonRuntimeService.Start()
	if started then
		return
	end
	started = true
	DungeonLegacyIsolationService.Start()
	Players.CharacterAutoLoads = false
	GameContext.SetCurrentPlaceType("Dungeon")
	DungeonSpawnService.Start({
		ProtectionSeconds = 4,
	})
	ContentResolver.EnsureStructure()
	PhaseRegistry.Refresh()
	RuntimeFolders.Ensure()
	resultEvent = RemoteRegistry.Get("Notifications", "DungeonResult", "RemoteEvent")
	objectiveEvent = RemoteRegistry.Get("Dungeon", "ObjectiveState", "RemoteEvent")
	rewardEvent = RemoteRegistry.Get("Dungeon", "RewardState", "RemoteEvent")
	lifeEvent = RemoteRegistry.Get("Dungeon", "LifeState", "RemoteEvent")
	bossEvent = RemoteRegistry.Get("Dungeon", "BossState", "RemoteEvent")
	DungeonReturnService.Start({
		RemoteEvent = resultEvent,
		LobbyPlaceId = PlaceConfig.LobbyPlaceId,
		OnReturning = function(returnReason)
			transitionState(DungeonStateMachine.States.Returning, {
				Reason = returnReason,
				Force = true,
				ResultSaved = workspace:GetAttribute("DungeonResultSaved") == true,
			})
		end,
		OnClosed = function()
			workspace:SetAttribute("DungeonSessionClosed", true)
		end,
	})
	resultEvent.OnServerEvent:Connect(function(player, request)
		if type(request) ~= "table" or request.Action ~= "GetResult" then
			return
		end
		if session and session.Completed and session.PartyUserSet[player.UserId] then
			DungeonReturnService.AttachPlayer(player)
			sendResultToPlayer(player)
		end
	end)
	stateMachine = DungeonStateMachine.new({
		InitialState = DungeonStateMachine.States.Initializing,
		OnTransition = function(entry)
			workspace:SetAttribute("DungeonPhaseState", entry.State)
			workspace:SetAttribute("DungeonPreviousPhaseState", entry.PreviousState)
			workspace:SetAttribute("DungeonPhaseStateSequence", entry.Sequence)
			workspace:SetAttribute("DungeonPhaseStateChangedAt", entry.EnteredAt)
			workspace:SetAttribute(
				"DungeonPhaseStateReason",
				entry.Context and tostring(entry.Context.Reason or "") or ""
			)
			if session then
				session.State = entry.State
			end
			if entry.State == DungeonStateMachine.States.Active then
				ObjectiveEncounterService.SetCombatEnabled(true)
				BossService.SetCombatEnabled(false)
			elseif entry.State == DungeonStateMachine.States.BossActive then
				ObjectiveEncounterService.SetCombatEnabled(false)
				BossService.SetCombatEnabled(true)
			elseif entry.State == DungeonStateMachine.States.ObjectiveComplete
				or entry.State == DungeonStateMachine.States.Transitioning
				or entry.State == DungeonStateMachine.States.RoundReward
				or entry.State == DungeonStateMachine.States.WipePending
				or entry.State == DungeonStateMachine.States.Victory
				or entry.State == DungeonStateMachine.States.Defeat
				or entry.State == DungeonStateMachine.States.Returning
			then
				ObjectiveEncounterService.SetCombatEnabled(false)
				BossService.SetCombatEnabled(false)
			end
		end,
	})
	workspace:SetAttribute("DungeonRuntimeManaged", true)
	workspace:SetAttribute("DungeonRuntimeReady", false)
	workspace:SetAttribute("DungeonStateMachineReady", true)

	Players.PlayerAdded:Connect(function(player)
		if not acceptPlayer(player) or not session then
			return
		end
		if session.Completed then
			DungeonReturnService.AttachPlayer(player)
			task.defer(function()
				freezeResultPlayer(player)
				sendResultToPlayer(player)
			end)
		elseif not session.WorldStarted then
			task.delay(8, beginWorld)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if session and session.PartyUserSet and session.PartyUserSet[player.UserId] then
			ObjectiveService.SetParticipantConnected(player.UserId, false)
			if not session.Completed then
				DungeonPartyLifeService.MarkDisconnected(player.UserId, "PlayerRemoving")
			end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if acceptPlayer(player) and session then
			if session.Completed then
				DungeonReturnService.AttachPlayer(player)
				task.defer(function()
					freezeResultPlayer(player)
					sendResultToPlayer(player)
				end)
			elseif not session.WorldStarted then
				task.delay(8, beginWorld)
			end
		end
	end
end

function DungeonRuntimeService.GetState()
	return stateMachine and stateMachine:GetState() or nil
end

function DungeonRuntimeService.TransitionState(nextState, context)
	return transitionState(nextState, context)
end

function DungeonRuntimeService.StartObjective(definition)
	assert(stateMachine, "DungeonRuntimeService ainda nao foi iniciado")
	local currentState = stateMachine:GetState()
	if currentState == DungeonStateMachine.States.ObjectiveComplete
		or currentState == DungeonStateMachine.States.Transitioning
		or currentState == DungeonStateMachine.States.RoundReward
	then
		transitionState(DungeonStateMachine.States.Active, {
			Reason = "ObjectiveStarted",
			ObjectiveId = definition and definition.Id,
		})
	end
	assert(
		stateMachine:GetState() == DungeonStateMachine.States.Active,
		"Objetivos so podem iniciar durante o estado Active"
	)
	return ObjectiveService.SetObjective(definition)
end

function DungeonRuntimeService.AddObjectiveProgress(amount, sourceUserId, metadata)
	return ObjectiveService.AddProgress(amount, sourceUserId, metadata)
end

function DungeonRuntimeService.GetObjectiveSnapshot()
	return ObjectiveService.GetSnapshot()
end

function DungeonRuntimeService.ReportObjectiveEvent(eventName, payload)
	return ObjectiveSequenceService.Report(eventName, payload)
end

function DungeonRuntimeService.CommitRoundReward(roundIndex, metadata)
	return ObjectiveSequenceService.CommitRoundReward(roundIndex, metadata)
end

function DungeonRuntimeService.GetObjectiveSequenceSnapshot()
	return ObjectiveSequenceService.GetSnapshot()
end

function DungeonRuntimeService.GetEncounterSnapshot()
	return ObjectiveEncounterService.GetSnapshot()
end

function DungeonRuntimeService.GetRewardSnapshot(player)
	return RewardIslandService.GetSnapshot(player)
end

function DungeonRuntimeService.ClaimRoundReward(player, chestRole)
	return RewardIslandService.Claim(player, chestRole)
end

function DungeonRuntimeService.GetRunRewardLedgerSnapshot()
	return RunRewardLedgerService.GetSnapshot()
end

function DungeonRuntimeService.SetEncounterCombatEnabled(enabled)
	return ObjectiveEncounterService.SetCombatEnabled(enabled)
end

function DungeonRuntimeService.GetBossSnapshot()
	return BossService.GetSnapshot()
end

function DungeonRuntimeService.ActivateBossForTesting(player)
	return BossService.ActivateForTesting(player)
end

function DungeonRuntimeService.GetPartyLifeSnapshot()
	return DungeonPartyLifeService.GetSnapshot()
end

function DungeonRuntimeService.GetReturnSnapshot(playerOrUserId)
	return DungeonReturnService.GetSnapshot(playerOrUserId)
end

function DungeonRuntimeService.RequestReturnToLobby(player, reason)
	return DungeonReturnService.RequestPlayer(player, reason)
end

function DungeonRuntimeService.GetPlayerLifeState(playerOrUserId)
	return DungeonPartyLifeService.GetPlayerState(playerOrUserId)
end

return DungeonRuntimeService
