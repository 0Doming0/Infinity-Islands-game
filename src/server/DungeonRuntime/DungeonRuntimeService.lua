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
local RuntimeFolders = require(script.Parent.RuntimeFolders)
local DungeonGenerator = require(script.Parent.DungeonGenerator)
local PhaseRegistry = require(script.Parent.PhaseRegistry)

local DungeonRuntimeService = {}
local started = false
local session
local resultEvent

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

local function allPlayersEliminated()
	if not session or session.Completed then
		return false
	end
	local present = 0
	for _, userId in ipairs(session.PartyUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			present += 1
			if player:GetAttribute("DungeonEliminated") ~= true then
				return false
			end
		end
	end
	return present > 0
end

local finishSession

local function bindCharacter(player, character)
	if player:GetAttribute("DungeonEliminated") == true then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		if not session or session.Completed then
			return
		end
		player:SetAttribute("DungeonEliminated", true)
		if allPlayersEliminated() then
			finishSession("Defeat")
		end
	end)
end

local function loadSessionPlayer(player)
	local data = PlayerDataService.Load(player)
	if not data then
		return false
	end
	player:SetAttribute("DungeonSessionId", session.SessionId)
	player:SetAttribute("DungeonPhaseId", session.PhaseId)
	player:SetAttribute("DungeonInitialPartySize", session.PartySize)
	player:SetAttribute("DungeonEliminated", false)
	-- O Lobby ja representa a tela de entrada da experiencia. Ao chegar neste
	-- Place, o jogador deve nascer automaticamente; o fluxo legado de
	-- StartScreen nao pode voltar a coloca-lo em AwaitingStart.
	player:SetAttribute("DungeonRuntimeAutoStart", true)
	player:SetAttribute("InitialGameStarted", true)
	player:SetAttribute("InitialSpawnPositioned", false)
	player:SetAttribute("InitialStartState", "Positioning")
	player:SetAttribute("PlayerLifecycleState", "InitialSpawning")
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if not player.Character then
		player:LoadCharacter()
	else
		bindCharacter(player, player.Character)
	end
	return true
end

local function returnToLobby(reason)
	local players = sessionPlayers()
	if #players == 0 or PlaceConfig.LobbyPlaceId <= 0 then
		workspace:SetAttribute("DungeonReturnPending", PlaceConfig.LobbyPlaceId <= 0)
		workspace:SetAttribute("DungeonSessionClosed", true)
		return
	end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		ReturnReason = reason,
		PhaseId = session.PhaseId,
	})
	local ok, errorMessage = pcall(
		TeleportService.TeleportAsync,
		TeleportService,
		PlaceConfig.LobbyPlaceId,
		players,
		options
	)
	if not ok then
		warn("[DungeonRuntime] Retorno ao lobby falhou: " .. tostring(errorMessage))
		workspace:SetAttribute("DungeonReturnError", tostring(errorMessage))
	end
	workspace:SetAttribute("DungeonSessionClosed", true)
end

finishSession = function(reason)
	if not session or session.Completed then
		return
	end
	session.Completed = true
	session.Active = false
	session.Result = reason
	workspace:SetAttribute("DungeonPhaseState", reason)
	BossService.Stop()
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
	local elapsed = math.max(0, workspace:GetServerTimeNow() - session.StartedAt)
	local saveResults = {}
	for _, player in ipairs(sessionPlayers()) do
		local rewardCoins = 0
		if reason == "Victory" then
			rewardCoins = math.max(0, math.floor(tonumber(definition.VictoryCoins) or 0))
			PlayerDataService.AddCoins(player, rewardCoins)
			PlayerDataService.RecordPhaseCompletion(player, session.PhaseId, elapsed)
		end
		saveResults[player] = PlayerDataService.Save(player, true)
		resultEvent:FireClient(player, {
			Action = "Result",
			Result = reason,
			PhaseId = session.PhaseId,
			PhaseName = definition.DisplayName,
			RewardCoins = rewardCoins,
			ElapsedSeconds = elapsed,
			Saved = saveResults[player] == true,
			ReturnDelay = 7,
		})
	end
	task.delay(7, function()
		returnToLobby(reason)
	end)
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
	workspace:SetAttribute("DungeonPhaseState", "Generating")
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
	local success, errorMessage = DungeonGenerator.Generate({
		PhaseId = session.PhaseId,
		PartySize = session.PartySize,
		Seed = session.Seed,
		MaximumIslandCount = phase.BaseIslandCount,
		OnPhaseReady = function(endContext)
			if session.Completed then
				return
			end
			ChunkManager.Stop()
			BossService.Create({
				PhaseId = session.PhaseId,
				PartySize = session.PartySize,
				BossId = phase.BossId,
				EndContext = endContext,
				OnDefeated = function()
					finishSession("Victory")
				end,
			})
		end,
	})
	workspace:SetAttribute("DungeonRuntimeReady", success == true)
	if not success then
		workspace:SetAttribute("DungeonPhaseState", "FailedToGenerate")
		warn("[DungeonRuntime] Geracao falhou: " .. tostring(errorMessage))
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
	Players.CharacterAutoLoads = false
	GameContext.SetCurrentPlaceType("Dungeon")
	ContentResolver.EnsureStructure()
	PhaseRegistry.Refresh()
	RuntimeFolders.Ensure()
	resultEvent = RemoteRegistry.Get("Notifications", "DungeonResult", "RemoteEvent")
	workspace:SetAttribute("DungeonRuntimeManaged", true)
	workspace:SetAttribute("DungeonRuntimeReady", false)

	Players.PlayerAdded:Connect(function(player)
		if acceptPlayer(player) and session and not session.WorldStarted then
			task.delay(8, beginWorld)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if session and session.PartyUserSet and session.PartyUserSet[player.UserId] then
			player:SetAttribute("DungeonEliminated", true)
			task.defer(function()
				if allPlayersEliminated() then
					finishSession("Defeat")
				end
			end)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if acceptPlayer(player) and session and not session.WorldStarted then
			task.delay(8, beginWorld)
		end
	end
end

return DungeonRuntimeService
