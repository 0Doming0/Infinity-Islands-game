--[[
	Infinity Islands - Task 19
	DungeonRuntimeService - Standalone Combat MVP

	The Dungeon itself is now the MVP experience.

	ENTRY:
	Player joins server
		-> no Lobby
		-> no TeleportData requirement
		-> no Start screen
		-> no first-match guide
		-> server creates/uses one shared run
		-> player spawns at current Combat checkpoint
		-> first server player starts at Island 1

	This intentionally replaces the older reserved-session/lobby orchestration
	with a much smaller runtime.

	Core services such as IslandCombatService, PlayerLevelService,
	ActiveWorldWindowService and their bootstraps remain independent.

	DEATH:
	simple Roblox-style respawn at the current Dungeon checkpoint.
	No lives/wipe flow is required for this MVP.

	FINAL ROUTE:
	CombatRouteCompletionService publishes victory.
	No automatic Lobby teleport.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameContext = require(
	ReplicatedStorage.Shared.GameContext
)

local PhaseConfig = require(
	ReplicatedStorage.Shared.Configs.PhaseConfig
)

local StandaloneConfig = require(
	ReplicatedStorage.Shared.Configs.StandaloneDungeonConfig
)

local StandaloneEntryConfig = require(
	ReplicatedStorage.Shared.Configs.StandaloneEntryConfig
)

local PlayerDataService = require(
	script.Parent.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10
)

local ContentResolver = require(
	script.Parent.ContentResolver
)

local DungeonGenerator = require(
	script.Parent.DungeonGenerator
)

local DungeonLegacyIsolationService = require(
	script.Parent.DungeonLegacyIsolationService
)

local DungeonSpawnService = require(
	script.Parent.DungeonSpawnService
)

local ObjectiveSequenceService = require(
	script.Parent.ObjectiveSequenceService
)

local ObjectiveService = require(
	script.Parent.ObjectiveService
)

local DungeonRecoveryService = require(
	script.Parent.DungeonRecoveryService
)

local PhaseRegistry = require(
	script.Parent.PhaseRegistry
)

local PaidTestReadinessService = require(
	script.Parent.PaidTestReadinessService
)

local DungeonPacingService = require(
	script.Parent.DungeonPacingService
)

local ObjectiveEncounterService = require(
	script.Parent.ObjectiveEncounterService
)

local RewardIslandService = require(
	script.Parent.RewardIslandService
)

local RunRewardLedgerService = require(
	script.Parent.RunRewardLedgerService
)

local MobCollectibleService = require(
	script.Parent.MobCollectibleService
)

local OptionalIslandService = require(
	script.Parent.OptionalIslandService
)

local BossService = require(
	script.Parent.BossService
)

local BossEncounterDirector = require(
	script.Parent.BossEncounterDirector
)

local DungeonRuntimeService = {}

local started = false
local worldStarting = false
local worldReady = false

local session = nil
local phaseId = nil
local phase = nil

local runtimeState = "Initializing"

local playerConnections =
	setmetatable({}, { __mode = "k" })

local playerEntryState =
	setmetatable({}, { __mode = "k" })

local function publishState(
	state,
	reason
)
	runtimeState = state

	workspace:SetAttribute(
		"DungeonPhaseState",
		state
	)

	workspace:SetAttribute(
		"DungeonPhaseStateReason",
		tostring(reason or "")
	)

	workspace:SetAttribute(
		"DungeonPhaseStateChangedAt",
		workspace:GetServerTimeNow()
	)
end

local function playerList()
	return Players:GetPlayers()
end

local function participantUserIds()
	local result = {}

	for _, player in ipairs(
		playerList()
	) do
		table.insert(
			result,
			player.UserId
		)
	end

	return result
end

local function currentPlayerCount()
	return math.clamp(
		#playerList(),
		1,
		StandaloneConfig.MaximumPlayers
	)
end

local function publishPartySize()
	local size =
		currentPlayerCount()

	workspace:SetAttribute(
		"DungeonPartySize",
		size
	)

	for _, player in ipairs(
		playerList()
	) do
		player:SetAttribute(
			"DungeonInitialPartySize",
			size
		)
	end
end

local function choosePhase()
	local requested =
		workspace:GetAttribute(
			"StandalonePhaseId"
		)
			or workspace:GetAttribute(
				"StudioPhaseId"
			)

	if PhaseConfig.IsValid(requested) then
		return requested
	end

	return PhaseConfig.GetDefaultId()
end

local function applyPhaseAttributes()
	if not phase then
		return
	end

	workspace:SetAttribute(
		"DungeonIslandBlockColor",
		phase.IslandBlockColor
	)
	workspace:SetAttribute(
		"DungeonIslandBlockMaterial",
		phase.IslandBlockMaterial
	)
	workspace:SetAttribute(
		"DungeonIslandBlockTextureId",
		phase.IslandBlockTextureId
	)
	workspace:SetAttribute(
		"DungeonTextureStudsPerTileU",
		phase.TextureStudsPerTileU
	)
	workspace:SetAttribute(
		"DungeonTextureStudsPerTileV",
		phase.TextureStudsPerTileV
	)
	workspace:SetAttribute(
		"DungeonMaximumActiveMonsters",
		phase.MaximumActiveMonsters
	)
	workspace:SetAttribute(
		"DungeonEliteReservedMonsterSlots",
		phase.EliteReservedMonsterSlots
	)
	workspace:SetAttribute(
		"DungeonDefaultMonsterSpawnChance",
		phase.DefaultMonsterSpawnChance
	)
	workspace:SetAttribute(
		"DungeonDecorationSpawnChance",
		phase.DecorationSpawnChance
	)
end

local function checkpointIndex()
	local checkpoint =
		DungeonSpawnService.GetCheckpoint()

	if type(checkpoint) == "table" then
		return math.max(
			StandaloneEntryConfig.ServerStartIsland,
			math.floor(
				tonumber(
					checkpoint.GlobalIslandIndex
				)
					or StandaloneEntryConfig
						.ServerStartIsland
			)
		)
	end

	return StandaloneEntryConfig.ServerStartIsland
end

local function bindSimpleRespawn(
	player,
	character
)
	local humanoid =
		character:WaitForChild(
			"Humanoid",
			10
		)

	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		if player.Parent ~= Players then
			return
		end

		player:SetAttribute(
			"DungeonLastDeathAt",
			workspace:GetServerTimeNow()
		)

		player:SetAttribute(
			"DungeonRespawnPolicy",
			"CurrentCombatCheckpoint"
		)

		task.delay(
			StandaloneConfig.RespawnDelaySeconds,
			function()
				if player.Parent ~= Players then
					return
				end

				-- During/after route completion, keeping respawn available is
				-- friendlier than freezing the player in a finished server.
				player:LoadCharacter()
			end
		)
	end)
end

local function prepareCharacterHooks(player)
	local connections =
		playerConnections[player]

	if connections then
		for _, connection in ipairs(
			connections
		) do
			connection:Disconnect()
		end
	end

	connections = {}

	table.insert(
		connections,
		player.CharacterAdded:Connect(
			function(character)
				task.spawn(
					bindSimpleRespawn,
					player,
					character
				)
			end
		)
	)

	playerConnections[player] =
		connections

	if player.Character then
		task.spawn(
			bindSimpleRespawn,
			player,
			player.Character
		)
	end
end

local function loadPersistentData(player)
	local ok,
		result =
			pcall(
				PlayerDataService.Load,
				player
			)

	if not ok then
		warn(
			"[StandaloneDungeon] PlayerData Load falhou para "
				.. player.Name
				.. ": "
				.. tostring(result)
		)

		player:SetAttribute(
			"DungeonPlayerDataLoadError",
			tostring(result)
		)

		return false
	end

	player:SetAttribute(
		"DungeonPlayerDataLoadError",
		nil
	)

	return result ~= nil
end

local function applyDirectPlayerContract(player)
	player:SetAttribute(
		"DungeonSessionId",
		session.SessionId
	)

	player:SetAttribute(
		"DungeonPhaseId",
		phaseId
	)

	player:SetAttribute(
		"DungeonStandaloneSession",
		true
	)

	player:SetAttribute(
		"DungeonEntrySource",
		"DirectJoin"
	)

	player:SetAttribute(
		"DungeonLobbyUsed",
		false
	)

	player:SetAttribute(
		"DungeonTeleportDataRequired",
		false
	)

	player:SetAttribute(
		"DungeonGuideEnabled",
		false
	)

	player:SetAttribute(
		"DungeonRuntimeAutoStart",
		true
	)

	player:SetAttribute(
		"InitialGameStarted",
		true
	)

	player:SetAttribute(
		"InitialSpawnPositioned",
		false
	)

	player:SetAttribute(
		"InitialStartState",
		"Positioning"
	)

	player:SetAttribute(
		"PlayerLifecycleState",
		"InitialSpawning"
	)

	player:SetAttribute(
		"TutorialEnemyProtection",
		false
	)

	player:SetAttribute(
		"DungeonEliminated",
		false
	)

	player:SetAttribute(
		"DungeonSpectating",
		false
	)

	player:SetAttribute(
		"DungeonLifeState",
		"Active"
	)
end

local function placePlayerInCurrentRun(
	player,
	reason
)
	if player.Parent ~= Players then
		return false,
			"PlayerLeft"
	end

	local state =
		playerEntryState[player]

	if not state then
		state = {
			PositionSerial = 0,
			LastRequestedAt = -math.huge,
			LastIslandIndex = nil,
		}

		playerEntryState[player] = state
	end

	local timestamp =
		workspace:GetServerTimeNow()

	if timestamp - state.LastRequestedAt
		< StandaloneEntryConfig
			.PositionRequestCooldownSeconds
	then
		return false,
			"DuplicatePositionRequest"
	end

	state.LastRequestedAt = timestamp
	state.PositionSerial += 1

	local serial =
		state.PositionSerial

	local index =
		checkpointIndex()

	state.LastIslandIndex = index

	player:SetAttribute(
		"CurrentGlobalIslandIndex",
		index
	)

	player:SetAttribute(
		"DungeonStandaloneJoinIsland",
		index
	)

	player:SetAttribute(
		"DungeonStandaloneLateJoinPolicy",
		StandaloneEntryConfig
			.LateJoinPolicy
	)

	player:SetAttribute(
		"DungeonStandalonePositionSerial",
		serial
	)

	player:SetAttribute(
		"DungeonStandalonePositionReason",
		tostring(
			reason or "StandaloneJoin"
		)
	)

	local context =
		DungeonGenerator
			.GetRouteIslandContext(
				index
			)

	if context then
		ObjectiveSequenceService
			.HandleIslandEntered(
				player,
				context
			)
	end

	if not player.Character then
		player:SetAttribute(
			"DungeonStandaloneCharacterLoadRequested",
			true
		)

		player:LoadCharacter()

		return true,
			"CharacterLoadRequested"
	end

	local positioned,
		positionError =
			DungeonSpawnService.PositionPlayer(
				player,
				reason or "StandaloneJoin"
			)

	player:SetAttribute(
		"DungeonStandalonePositionSucceeded",
		positioned == true
	)

	player:SetAttribute(
		"DungeonStandalonePositionError",
		positioned and nil
			or tostring(positionError)
	)

	return positioned,
		positionError
end

local function acceptPlayer(player)
	if not session then
		return false,
			"SessionNotInitialized"
	end

	applyDirectPlayerContract(player)
	prepareCharacterHooks(player)

	DungeonSpawnService.BindPlayer(
		player
	)

	loadPersistentData(player)

	publishPartySize()

	return true
end

local function startCompatibilityShells()
	-- Task 12 turns these modules into inert compatibility shells.
	-- Starting them keeps old callers safe without reintroducing gameplay.
	local options = {
		SessionId = session.SessionId,
		PhaseId = phaseId,
		PartySize = currentPlayerCount(),
		ParticipantUserIds =
			participantUserIds(),
	}

	pcall(
		ObjectiveService.Start,
		options
	)

	pcall(
		ObjectiveEncounterService.Start,
		options
	)

	pcall(
		RewardIslandService.Start,
		options
	)

	pcall(
		RunRewardLedgerService.Start,
		options
	)

	pcall(
		MobCollectibleService.Start,
		options
	)

	pcall(
		OptionalIslandService.Start,
		options
	)

	pcall(
		BossService.Start,
		options
	)

	pcall(
		BossEncounterDirector.Start,
		options
	)

	pcall(
		DungeonPacingService.Start,
		options
	)
end

local function startRouteProgression()
	local startedProgression,
		errorCode =
			ObjectiveSequenceService.Start({
				PartySize =
					currentPlayerCount(),

				ParticipantUserIds =
					participantUserIds(),

				GetIslandContext =
					DungeonGenerator
						.GetRouteIslandContext,

				RequestRouteThrough =
					DungeonGenerator
						.RequestRouteThrough,

				OnRouteRejected =
					function(
						player,
						requestedIndex,
						reason,
						allowedIndex
					)
						player:SetAttribute(
							"DungeonRouteRejectedReason",
							reason
						)

						player:SetAttribute(
							"DungeonRouteRejectedIsland",
							requestedIndex
						)

						player:SetAttribute(
							"DungeonRouteAllowedIsland",
							allowedIndex
						)
					end,
			})

	if startedProgression == false
		and errorCode ~= "AlreadyStarted"
	then
		return false,
			errorCode
	end

	return true
end

local function startRecovery()
	local ok,
		result =
			pcall(
				DungeonRecoveryService.Start,
				{
					ParticipantUserIds =
						participantUserIds(),

					GetCheckpoint =
						DungeonSpawnService
							.GetCheckpoint,

					PositionPlayer =
						DungeonSpawnService
							.PositionPlayer,

					FallDistanceBelowCheckpoint = 55,
					StuckSeconds = 6.5,
					ProtectionSeconds =
						StandaloneConfig
							.SpawnProtectionSeconds,
				}
			)

	workspace:SetAttribute(
		"DungeonStandaloneRecoveryStarted",
		ok and result ~= false
	)
end

local function startWorld()
	if worldStarting
		or worldReady
	then
		return
	end

	worldStarting = true

	publishState(
		"Generating",
		"StandaloneServerStart"
	)

	workspace:SetAttribute(
		"DungeonGenerationState",
		"Generating"
	)

	local progressionReady,
		progressionError =
			startRouteProgression()

	if not progressionReady then
		worldStarting = false

		workspace:SetAttribute(
			"DungeonGenerationState",
			"Failed"
		)

		workspace:SetAttribute(
			"DungeonGenerationError",
			"RouteProgression:"
				.. tostring(
					progressionError
				)
		)

		return
	end

	local success,
		errorMessage =
			DungeonGenerator.Generate({
				PhaseId = phaseId,
				PartySize =
					currentPlayerCount(),
				Seed = session.Seed,
				RouteIslandCount =
					StandaloneConfig
						.RouteIslandCount,

				OnRouteIslandEntered =
					function(
						player,
						islandContext
					)
						return ObjectiveSequenceService
							.HandleIslandEntered(
								player,
								islandContext
							)
					end,

				OnPhaseReady =
					function(endContext)
						session.RouteEndContext =
							endContext

						workspace:SetAttribute(
							"DungeonRouteReady",
							true
						)

						workspace:SetAttribute(
							"DungeonRouteReadyAt",
							workspace:GetServerTimeNow()
						)

						workspace:SetAttribute(
							"DungeonBossState",
							"Disabled"
						)
					end,
			})

	if not success then
		worldStarting = false

		workspace:SetAttribute(
			"DungeonRuntimeReady",
			false
		)

		workspace:SetAttribute(
			"DungeonGenerationState",
			"Failed"
		)

		workspace:SetAttribute(
			"DungeonGenerationError",
			tostring(errorMessage)
		)

		publishState(
			"Failed",
			errorMessage
		)

		warn(
			"[StandaloneDungeon] geração falhou: "
				.. tostring(errorMessage)
		)

		return
	end

	local initialContext =
		DungeonGenerator
			.GetRouteIslandContext(
			StandaloneEntryConfig.ServerStartIsland
		)

	if not initialContext then
		worldStarting = false

		workspace:SetAttribute(
			"DungeonRuntimeReady",
			false
		)

		workspace:SetAttribute(
			"DungeonGenerationState",
			"Failed"
		)

		workspace:SetAttribute(
			"DungeonGenerationError",
			"InitialIslandContextUnavailable"
		)

		return
	end

	local checkpointReady,
		checkpointError =
			DungeonSpawnService
				.SetInitialCheckpoint(
					initialContext,
					"StandaloneServerStartIsland",
					false
				)

	if not checkpointReady
		and checkpointError
			~= "InitialCheckpointAlreadySet"
	then
		worldStarting = false

		workspace:SetAttribute(
			"DungeonInitialSpawnError",
			tostring(checkpointError)
		)

		return
	end

	worldReady = true
	worldStarting = false

	session.WorldStarted = true
	session.StartedAt =
		workspace:GetServerTimeNow()

	workspace:SetAttribute(
		"DungeonGenerationState",
		"Ready"
	)

	workspace:SetAttribute(
		"DungeonRuntimeReady",
		true
	)

	workspace:SetAttribute(
		"DungeonStandaloneWorldReady",
		true
	)

	workspace:SetAttribute(
		"DungeonStandaloneWorldReadyAt",
		workspace:GetServerTimeNow()
	)

	publishState(
		"Active",
		"Island1Ready"
	)

	startRecovery()

	for _, player in ipairs(
		playerList()
	) do
		placePlayerInCurrentRun(
			player,
			"InitialWorldReady"
		)
	end
end

local function initializeSession()
	phaseId =
		choosePhase()

	if not phaseId then
		return false,
			"NoValidPhase"
	end

	phase =
		PhaseConfig.Get(
			phaseId
		)

	if not phase then
		return false,
			"PhaseUnavailable:"
				.. tostring(phaseId)
	end

	session = {
		Version = 1,
		SessionId =
			"standalone-"
				.. HttpService
					:GenerateGUID(false),

		PhaseId = phaseId,

		Seed =
			Random.new()
				:NextInteger(
					1,
					2147483646
				),

		WorldStarted = false,
		StartedAt = nil,
	}

	workspace:SetAttribute(
		"DungeonSessionId",
		session.SessionId
	)

	workspace:SetAttribute(
		"DungeonPhaseId",
		phaseId
	)

	workspace:SetAttribute(
		"DungeonSeed",
		session.Seed
	)

	workspace:SetAttribute(
		"DungeonStandaloneMode",
		true
	)

	workspace:SetAttribute(
		"DungeonStandaloneVersion",
		StandaloneConfig.Version
	)

	workspace:SetAttribute(
		"DungeonEntryPolicy",
		StandaloneConfig.EntryPolicy
	)

	workspace:SetAttribute(
		"DungeonLobbyEnabled",
		false
	)

	workspace:SetAttribute(
		"DungeonTeleportDataRequired",
		false
	)

	workspace:SetAttribute(
		"DungeonGuideEnabled",
		false
	)

	workspace:SetAttribute(
		"DungeonAutoReturnToLobby",
		false
	)

	workspace:SetAttribute(
		"DungeonStandaloneEntryVersion",
		StandaloneEntryConfig.Version
	)

	workspace:SetAttribute(
		"DungeonStandaloneServerStartIsland",
		StandaloneEntryConfig.ServerStartIsland
	)

	workspace:SetAttribute(
		"DungeonStandaloneLateJoinPolicy",
		StandaloneEntryConfig.LateJoinPolicy
	)

	workspace:SetAttribute(
		"DungeonStandaloneCompletedRunLateJoinPolicy",
		StandaloneEntryConfig
			.CompletedRunLateJoinPolicy
	)

	workspace:SetAttribute(
		"DungeonSessionClosed",
		false
	)

	workspace:SetAttribute(
		"DungeonCombatStopped",
		false
	)

	applyPhaseAttributes()

	return true
end

function DungeonRuntimeService.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	Players.CharacterAutoLoads = false

	DungeonLegacyIsolationService.Start()

	GameContext.SetCurrentPlaceType(
		"Dungeon"
	)

	workspace:SetAttribute(
		"GamePlaceType",
		"Dungeon"
	)

	workspace:SetAttribute(
		"DungeonRuntimeManaged",
		true
	)

	workspace:SetAttribute(
		"DungeonRuntimeReady",
		false
	)

	publishState(
		"Initializing",
		"StandaloneRuntime"
	)

	DungeonSpawnService.Start({
		ProtectionSeconds =
			StandaloneConfig
				.SpawnProtectionSeconds,
	})

	ContentResolver.EnsureStructure()
	PhaseRegistry.Refresh()

	local staticReadiness =
		PaidTestReadinessService
			.ValidateStatic()

	if not staticReadiness.Ready then
		workspace:SetAttribute(
			"DungeonStandaloneStaticReadinessWarning",
			table.concat(
				staticReadiness.Errors or {},
				" | "
			)
		)

		warn(
			"[StandaloneDungeon] readiness: "
				.. tostring(
					workspace:GetAttribute(
						"DungeonStandaloneStaticReadinessWarning"
					)
				)
		)
	end

	local initialized,
		initializationError =
			initializeSession()

	if not initialized then
		workspace:SetAttribute(
			"DungeonRuntimeReady",
			false
		)

		workspace:SetAttribute(
			"DungeonGenerationState",
			"Failed"
		)

		workspace:SetAttribute(
			"DungeonGenerationError",
			initializationError
		)

		publishState(
			"Failed",
			initializationError
		)

		return false,
			initializationError
	end

	startCompatibilityShells()

	Players.PlayerAdded:Connect(
		function(player)
			local accepted =
				acceptPlayer(player)

			if accepted
				and worldReady
			then
				placePlayerInCurrentRun(
					player,
					workspace:GetAttribute(
						"DungeonLinearRouteComplete"
					) == true
						and "LateJoinCompletedRun"
						or "LateJoinCurrentCheckpoint"
				)
			end
		end
	)

	Players.PlayerRemoving:Connect(
		function(player)
			local connections =
				playerConnections[player]

			if connections then
				for _, connection in ipairs(
					connections
				) do
					connection:Disconnect()
				end

				playerConnections[player] = nil
			end

			playerEntryState[player] = nil

			task.defer(
				publishPartySize
			)
		end
	)

	for _, player in ipairs(
		playerList()
	) do
		acceptPlayer(player)
	end

	-- No party-arrival timer and no Lobby session handshake.
	-- The server immediately builds the configured first Combat Island.
	workspace:SetAttribute(
		"DungeonStandaloneWorldStartRequestedAt",
		workspace:GetServerTimeNow()
	)

	task.spawn(
		startWorld
	)

	return true
end

function DungeonRuntimeService.GetState()
	return runtimeState
end

function DungeonRuntimeService.TransitionState(
	nextState,
	context
)
	publishState(
		tostring(nextState),
		context
			and context.Reason
			or "ExternalTransition"
	)

	return true
end

function DungeonRuntimeService.GetObjectiveSnapshot()
	return ObjectiveService.GetSnapshot()
end

function DungeonRuntimeService.GetObjectiveSequenceSnapshot()
	return ObjectiveSequenceService.GetSnapshot()
end

function DungeonRuntimeService.GetPacingSnapshot()
	return DungeonPacingService.GetSnapshot()
end

function DungeonRuntimeService.GetEncounterSnapshot()
	return ObjectiveEncounterService.GetSnapshot()
end

function DungeonRuntimeService.GetRewardSnapshot(player)
	return RewardIslandService.GetSnapshot(
		player
	)
end

function DungeonRuntimeService.ClaimRoundReward(...)
	return false,
		"RewardIslandsDisabled"
end

function DungeonRuntimeService.GetRunRewardLedgerSnapshot()
	return RunRewardLedgerService.GetSnapshot()
end

function DungeonRuntimeService.SetEncounterCombatEnabled(enabled)
	return ObjectiveEncounterService
		.SetCombatEnabled(enabled)
end

function DungeonRuntimeService.GetBossSnapshot()
	return BossService.GetSnapshot()
end

function DungeonRuntimeService.ActivateBossForTesting(...)
	return false,
		"BossDisabled"
end

function DungeonRuntimeService.GetBossDirectorSnapshot()
	return BossEncounterDirector.GetSnapshot()
end

function DungeonRuntimeService.GetMobCollectibleSnapshot()
	return MobCollectibleService.GetSnapshot()
end

function DungeonRuntimeService.GetOptionalIslandSnapshot(player)
	return OptionalIslandService.GetSnapshot(
		player
	)
end

function DungeonRuntimeService.ClaimOptionalIslandReward(...)
	return false,
		"OptionalIslandsDisabled"
end

function DungeonRuntimeService.GetRecoverySnapshot(player)
	return DungeonRecoveryService.GetSnapshot(
		player
	)
end

function DungeonRuntimeService.RequestRecovery(
	player,
	reason
)
	return DungeonSpawnService.PositionPlayer(
		player,
		reason or "ManualRecovery"
	)
end

function DungeonRuntimeService.GetEntrySafetySnapshot()
	return {
		Ready = true,
		Policy = "SpawnProtectionOnly",
	}
end

function DungeonRuntimeService.GetHealthRecoverySnapshot()
	return {
		Ready = false,
		Policy = "SimplifiedMVP",
	}
end

function DungeonRuntimeService.GetPartyLifeSnapshot()
	return {
		Ready = true,
		Policy = "SimpleCheckpointRespawn",
		Players = #playerList(),
	}
end

function DungeonRuntimeService.GetReturnSnapshot()
	return {
		Ready = false,
		LobbyEnabled = false,
		AutoReturn = false,
	}
end

function DungeonRuntimeService.RequestReturnToLobby(...)
	return false,
		"LobbyDisabledInStandaloneMVP"
end

function DungeonRuntimeService.GetPlayerLifeState(
	playerOrUserId
)
	local player =
		typeof(playerOrUserId)
			== "Instance"
			and playerOrUserId
			or Players:GetPlayerByUserId(
				math.floor(
					tonumber(
						playerOrUserId
					) or 0
				)
			)

	if player
		and player.Parent == Players
	then
		return "Active"
	end

	return nil
end

function DungeonRuntimeService.StartObjective(...)
	return false,
		"LegacyObjectivesDisabled"
end

function DungeonRuntimeService.AddObjectiveProgress(...)
	return false,
		"IslandCombatServiceOwnsProgress"
end

function DungeonRuntimeService.ReportObjectiveEvent(...)
	return false,
		"IslandCombatServiceOwnsProgress"
end

function DungeonRuntimeService.CommitRoundReward(...)
	return true,
		"LegacyRewardBypassedLinearRoute"
end

return DungeonRuntimeService
