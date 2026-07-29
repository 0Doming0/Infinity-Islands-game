-- SkyDungeon V6: tela de morte com renascimento exclusivamente manual.
-- O Developer Product devolve as moedas perdidas antes de recriar o personagem.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MonetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))
local WorldConfig = require(script.Parent.Parent.BlockParkour:WaitForChild("Config_SkyDungeon_V10"))
local ChunkManager = require(script.Parent.Parent.BlockParkour:WaitForChild("ChunkManager_SkyDungeon_V10"))
local SwordCatalog = require(ReplicatedStorage:WaitForChild("SwordCatalog"))
local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))
local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local PlayerDataService = require(script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local DeveloperProductService = require(script.Parent:WaitForChild("DeveloperProductService"))

local DeathReviveService = {}
local pending = setmetatable({}, { __mode = "k" })
local initialStates = setmetatable({}, { __mode = "k" })
local started = false
local WORLD_LOAD_TIMEOUT_SECONDS = 35
local INITIAL_SPAWN_TIMEOUT_SECONDS = 25
local INITIAL_PROTECTION_TIMEOUT_SECONDS = 35

-- O Roblox não deve recriar o personagem sozinho: todo renascimento depois
-- da morte passa pelos botões validados por este serviço.
Players.CharacterAutoLoads = false

local deathEvent = ReplicatedStorage:FindFirstChild("DeathReviveEvent")
if deathEvent and not deathEvent:IsA("RemoteEvent") then
	deathEvent:Destroy()
	deathEvent = nil
end
if not deathEvent then
	deathEvent = Instance.new("RemoteEvent")
	deathEvent.Name = "DeathReviveEvent"
	deathEvent.Parent = ReplicatedStorage
end

local startRequest = ReplicatedStorage:FindFirstChild("StartGameRequest")
if startRequest and not startRequest:IsA("RemoteFunction") then
	startRequest:Destroy()
	startRequest = nil
end
if not startRequest then
	startRequest = Instance.new("RemoteFunction")
	startRequest.Name = "StartGameRequest"
	startRequest.Parent = ReplicatedStorage
end

local function productId()
	local definition = MonetizationCatalog.Get("ReviveNoCoinLoss")
	local catalogId = math.max(0, math.floor(tonumber(definition and definition.ProductId) or 0))
	local legacyId = MVPConfig.Death.ReviveWithoutCoinLossProductId
	if catalogId > 0 then
		return catalogId
	end
	return math.max(0, math.floor(tonumber(legacyId) or 0))
end

local function setLifecycle(player, state)
	player:SetAttribute("PlayerLifecycleState", state)
end

local function beginRespawn(player, expectedState)
	local sequence = (tonumber(player:GetAttribute("RespawnSequence")) or 0) + 1
	player:SetAttribute("RespawnSequence", sequence)
	player:SetAttribute("RespawnState", "Preparing")
	setLifecycle(player, "Respawning")
	if expectedState then
		expectedState.RespawnSequence = sequence
		expectedState.RespawnStartedAt = os.clock()
	end
	deathEvent:FireClient(player, {
		Action = "PreparingRespawn",
		RespawnSequence = sequence,
	})
	return sequence
end

local function loadCharacterIfDead(player, expectedState, forceReload)
	if not player.Parent then
		return false
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and not forceReload then
		return false
	end

	if expectedState then
		if pending[player] ~= expectedState or (expectedState.Respawning and not forceReload) then
			return false
		end
		expectedState.Respawning = true
	end

	local respawnSequence = beginRespawn(player, expectedState)
	local loaded, loadError = pcall(function()
		player:LoadCharacter()
	end)
	if loaded then
		return true
	end

	if expectedState and player.Parent then
		expectedState.Respawning = false
		pending[player] = expectedState
	end
	player:SetAttribute("RespawnState", "Failed")
	setLifecycle(player, "Failed")
	warn(string.format("[DeathReviveService] Falha ao renascer %s: %s", player.Name, tostring(loadError)))
	deathEvent:FireClient(player, {
		Action = "Error",
		Message = "Não foi possível renascer. Tente novamente.",
		RespawnSequence = respawnSequence,
	})
	return false
end

local function worldIsReady()
	local generated = Workspace:FindFirstChild(WorldConfig.WORLD_MODEL_NAME)
	if not generated then
		return false
	end

	local requiredChunkCount = math.max(
		1,
		math.floor(tonumber(WorldConfig.INITIAL_CHUNK_COUNT) or 1)
	)
	local chunkCount = tonumber(generated:GetAttribute("ChunkCount")) or 0
	local activeChunkCount = tonumber(generated:GetAttribute("ActiveChunkCount")) or 0

	return activeChunkCount > 0
		and (
			generated:GetAttribute("InitialGenerationComplete") == true
			or chunkCount >= requiredChunkCount
		)
end

local function startSnapshot(player)
	local data = PlayerDataService.GetSnapshot(player)
	if not data then
		return nil
	end
	local sword = SwordCatalog.Get(data.EquippedSword)
	local relic = data.EquippedRelic and RelicCatalog.Get(data.EquippedRelic) or nil
	local companions = {}
	for slot, instanceId in ipairs(data.EquippedCompanions) do
		local record = data.OwnedCompanions[instanceId]
		local species = record and CompanionCatalog.Get(record.SpeciesId) or nil
		if record and species then
			table.insert(companions, {
				Slot = slot,
				InstanceId = instanceId,
				SpeciesId = record.SpeciesId,
				DisplayName = record.DisplayName,
				SpeciesName = species.DisplayName,
				Level = record.Level,
				Color = species.Color,
				ImageId = CompanionCatalog.GetImageId(record.SpeciesId),
			})
		end
	end
	return {
		BestScore = data.BestScore,
		Coins = data.Coins,
		CompanionEquipSlots = data.CompanionEquipSlots,
		Sword = sword and {
			Id = sword.SwordId,
			DisplayName = sword.DisplayName,
			Icon = sword.Icon,
			Color = sword.Color,
			AccentColor = sword.AccentColor,
		} or nil,
		Relic = relic and {
			Id = relic.RelicId,
			DisplayName = relic.DisplayName,
			Icon = relic.Icon,
			Color = relic.Color,
			ImageId = relic.ImageId,
		} or nil,
		Companions = companions,
	}
end

local function protectInitialCharacter(player, character)
	local state = initialStates[player]
	if not state or not state.Started or player:GetAttribute("InitialSpawnPositioned") == true then
		return
	end
	local forceField = Instance.new("ForceField")
	forceField.Name = "InitialStartProtection"
	forceField.Visible = false
	forceField.Parent = character
	player:SetAttribute("InitialStartProtection", true)
	task.spawn(function()
		local deadline = os.clock() + INITIAL_PROTECTION_TIMEOUT_SECONDS
		while
			player.Parent
			and character.Parent
			and player:GetAttribute("InitialSpawnPositioned") ~= true
			and os.clock() < deadline
		do
			task.wait(0.05)
		end
		if forceField.Parent then
			task.wait(0.5)
			forceField:Destroy()
		end
		if player.Parent then
			player:SetAttribute("InitialStartProtection", false)
		end
	end)
end

local function spawnInitialCharacter(player, state)
	if not player.Parent or player.Character or state.Spawning then
		return false
	end
	state.Spawning = true
	state.Started = true
	state.SpawnStartedAt = os.clock()
	player:SetAttribute("InitialGameStarted", true)
	player:SetAttribute("InitialSpawnPositioned", false)
	player:SetAttribute("InitialStartState", "Positioning")
	setLifecycle(player, "InitialSpawning")
	local loaded, loadError = pcall(function()
		player:LoadCharacter()
	end)
	if not loaded then
		state.Spawning = false
		state.Started = false
		player:SetAttribute("InitialGameStarted", false)
		player:SetAttribute("InitialStartState", "Ready")
		setLifecycle(player, "AwaitingStart")
		warn(string.format(
			"[DeathReviveService] Falha no primeiro spawn de %s: %s",
			player.Name,
			tostring(loadError)
		))
		return false
	end
	return true
end

local function prepareInitialPlayer(player)
	local state = {
		Ready = false,
		Started = false,
		Spawning = false,
		LastRequestAt = 0,
	}
	initialStates[player] = state
	player:SetAttribute("InitialGameStarted", false)
	player:SetAttribute("InitialSpawnPositioned", false)
	player:SetAttribute("InitialStartState", "LoadingData")
	player:SetAttribute("RespawnState", "NotStarted")
	setLifecycle(player, "LoadingData")
	player.CharacterAdded:Connect(function(character)
		protectInitialCharacter(player, character)
	end)
	player:GetAttributeChangedSignal("RespawnState"):Connect(function()
		local respawnState = player:GetAttribute("RespawnState")
		if respawnState == "Ready" then
			state.Spawning = false
			if player:GetAttribute("InitialGameStarted") == true then
				state.Started = true
				player:SetAttribute("InitialSpawnPositioned", true)
				player:SetAttribute("InitialStartState", "Playing")
				setLifecycle(player, "Playing")
			end
			local reviveState = pending[player]
			if reviveState and reviveState.Respawning then
				pending[player] = nil
				player:SetAttribute("PendingReviveCoinRefund", 0)
			end
		elseif respawnState == "Failed" then
			state.Spawning = false
			setLifecycle(player, "Failed")
		end
	end)
	task.spawn(function()
		state.Loading = true
		local dataLoaded, dataError = pcall(PlayerDataService.Load, player)
		if not player.Parent or initialStates[player] ~= state then
			return
		end
		if not dataLoaded then
			player:SetAttribute("InitialStartState", "DataLoadFailed")
			setLifecycle(player, "Failed")
			state.Loading = false
			warn(string.format(
				"[DeathReviveService] Falha ao carregar dados de %s: %s",
				player.Name,
				tostring(dataError)
			))
			return
		end
		player:SetAttribute("InitialStartState", "PreparingWorld")
		setLifecycle(player, "LoadingWorld")
		local deadline = os.clock() + WORLD_LOAD_TIMEOUT_SECONDS
		while
			player.Parent
			and initialStates[player] == state
			and not worldIsReady()
			and os.clock() < deadline
		do
			task.wait(0.25)
		end
		if player.Parent and initialStates[player] == state then
			if worldIsReady() then
				state.Ready = true
				state.WorldFailed = false
				player:SetAttribute("InitialStartState", "Ready")
				setLifecycle(player, "AwaitingStart")
			else
				state.Ready = false
				state.WorldFailed = true
				player:SetAttribute("InitialStartState", "WorldLoadFailed")
				setLifecycle(player, "Failed")
				warn(string.format(
					"[DeathReviveService] O mundo nao ficou pronto em %ds para %s.",
					WORLD_LOAD_TIMEOUT_SECONDS,
					player.Name
				))
			end
			state.Loading = false
		end
	end)
end

function DeathReviveService.RecordDeath(player, runScore, lostCoins, cause)
	local serial = (player:GetAttribute("DeathScreenSerial") or 0) + 1
	local state = {
		Serial = serial,
		CreatedAt = os.clock(),
		RunScore = math.max(0, math.floor(tonumber(runScore) or 0)),
		LostCoins = math.max(0, math.floor(tonumber(lostCoins) or 0)),
		Cause = tostring(cause or "Unknown"),
		Refunded = false,
	}
	pending[player] = state
	player:SetAttribute("DeathScreenSerial", serial)
	player:SetAttribute("PendingReviveCoinRefund", state.LostCoins)
	player:SetAttribute("RespawnState", "Dead")
	setLifecycle(player, "AwaitingReviveChoice")
	deathEvent:FireClient(player, {
		Action = "Show",
		Serial = serial,
		RunScore = state.RunScore,
		LostCoins = state.LostCoins,
		Cause = state.Cause,
		PauseSeconds = MVPConfig.Death.PauseSeconds,
		FreeRespawnDelaySeconds = MVPConfig.Death.FreeRespawnDelaySeconds,
		ProductId = productId(),
	})
end

local function grantPurchase(player)
	local state = pending[player]
	if state and state.Refunded then
		return true
	end
	local persistedLostCoins, persistedSerial =
		PlayerDataService.GetPendingRevivePurchase(player)
	local lostCoins = state and state.LostCoins or persistedLostCoins
	local serial = state and state.Serial or persistedSerial
	if lostCoins > 0 then
		local refunded = ScoreService.RefundCoins(
			player,
			lostCoins,
			"RobuxReviveRefund"
		)
		if not refunded then
			return false
		end
	end
	PlayerDataService.ClearPendingRevivePurchase(player)
	if state then
		state.Refunded = true
	end
	player:SetAttribute("PendingReviveCoinRefund", 0)
	player:SetAttribute("ReviveGrantedSerial", (player:GetAttribute("ReviveGrantedSerial") or 0) + 1)
	deathEvent:FireClient(player, {
		Action = "Granted",
		Serial = serial,
		CoinsRefunded = lostCoins,
	})
	if state then
		loadCharacterIfDead(player, state)
	end
	return true
end

local function processRevivePurchase(player)
	return grantPurchase(player)
end

function DeathReviveService.Start()
	if started then
		return
	end
	started = true
	Players.CharacterAutoLoads = false
	DeveloperProductService.Start()
	local configuredProductId = productId()
	if configuredProductId > 0 then
		DeveloperProductService.Register(
			configuredProductId,
			"ReviveWithoutCoinLoss",
			processRevivePurchase
		)
	end
	startRequest.OnServerInvoke = function(player, action)
		local state = initialStates[player]
		if not state then
			return { Success = false, Ready = false, State = "LoadingData" }
		end
		if state.WorldFailed and worldIsReady() then
			state.Ready = true
			state.WorldFailed = false
			player:SetAttribute("InitialStartState", "Ready")
			setLifecycle(player, "AwaitingStart")
		end
		if action == "RetryLoading" then
			if state.Loading then
				return { Success = true, Ready = false, Pending = true }
			end
			local retryData = player:GetAttribute("InitialStartState") == "DataLoadFailed"
			state.Loading = true
			state.WorldFailed = false
			player:SetAttribute("InitialStartState", "PreparingWorld")
			setLifecycle(player, "LoadingWorld")
			task.spawn(function()
				if retryData then
					local dataOk, dataError = pcall(PlayerDataService.Load, player)
					if not dataOk then
						state.Loading = false
						state.WorldFailed = true
						player:SetAttribute("InitialStartState", "DataLoadFailed")
						setLifecycle(player, "Failed")
						warn(string.format(
							"[DeathReviveService] Retry de dados falhou para %s: %s",
							player.Name,
							tostring(dataError)
						))
						return
					end
				end
				if not ChunkManager.IsRunning() then
					local startOk, startResult = pcall(ChunkManager.Start)
					if not startOk or startResult == false then
						warn(string.format(
							"[DeathReviveService] Retry do gerador falhou para %s: %s",
							player.Name,
							tostring(startResult)
						))
					end
				end
				local deadline = os.clock() + WORLD_LOAD_TIMEOUT_SECONDS
				while
					player.Parent
					and initialStates[player] == state
					and not worldIsReady()
					and os.clock() < deadline
				do
					task.wait(0.25)
				end
				if not player.Parent or initialStates[player] ~= state then
					return
				end
				state.Ready = worldIsReady()
				state.WorldFailed = not state.Ready
				state.Loading = false
				player:SetAttribute(
					"InitialStartState",
					state.Ready and "Ready" or "WorldLoadFailed"
				)
				setLifecycle(player, state.Ready and "AwaitingStart" or "Failed")
			end)
			return { Success = true, Ready = false, Pending = true }
		elseif action == "Get" then
			return {
				Success = true,
				Ready = state.Ready,
				Started = state.Started,
				State = player:GetAttribute("InitialStartState") or "LoadingData",
				Snapshot = state.Ready and startSnapshot(player) or nil,
			}
		elseif action == "Start" then
			local now = os.clock()
			if now - state.LastRequestAt < 0.5 then
				return { Success = false, Ready = state.Ready, Message = "Aguarde um instante." }
			end
			state.LastRequestAt = now
			if not state.Ready then
				local failed = state.WorldFailed
					or player:GetAttribute("InitialStartState") == "DataLoadFailed"
				return {
					Success = false,
					Ready = false,
					State = player:GetAttribute("InitialStartState"),
					Message = failed
						and "O carregamento falhou. Tente novamente em alguns segundos."
						or "O mundo ainda está carregando.",
				}
			end
			if state.Started then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local playing = player:GetAttribute("PlayerLifecycleState") == "Playing"
					and player:GetAttribute("InitialSpawnPositioned") == true
					and humanoid
					and humanoid.Health > 0
				if playing then
					return { Success = true, Ready = true, Started = true }
				end
				local timedOut = os.clock() - (state.SpawnStartedAt or 0)
					>= INITIAL_SPAWN_TIMEOUT_SECONDS
				local failed = player:GetAttribute("RespawnState") == "Failed"
				if not timedOut and not failed then
					return {
						Success = true,
						Ready = true,
						Started = true,
						Pending = true,
					}
				end
				if character then
					pcall(character.Destroy, character)
				end
				state.Started = false
				state.Spawning = false
				player:SetAttribute("InitialGameStarted", false)
				player:SetAttribute("InitialSpawnPositioned", false)
			end
			local success = spawnInitialCharacter(player, state)
			return {
				Success = success,
				Ready = true,
				Started = success,
				Message = success and nil or "Não foi possível iniciar. Tente novamente.",
			}
		end
		return { Success = false, Ready = state.Ready, Message = "Pedido inválido." }
	end
	deathEvent.OnServerEvent:Connect(function(player, request)
		if type(request) ~= "table" then
			return
		end
		local state = pending[player]
		if not state or request.Serial ~= state.Serial then
			return
		end
		if request.Action == "Purchase" then
			if productId() <= 0 then
				deathEvent:FireClient(player, {
					Action = "Error",
					Message = "Configure o Developer Product de renascimento.",
				})
				return
			end
			PlayerDataService.Load(player)
			if not PlayerDataService.SetPendingRevivePurchase(
				player,
				state.LostCoins,
				state.Serial
			) or not PlayerDataService.Save(player, true) then
				deathEvent:FireClient(player, {
					Action = "Error",
					Message = "Não foi possível preparar a compra com segurança. Tente novamente.",
				})
				return
			end
			local promptOk, promptError = pcall(
				MarketplaceService.PromptProductPurchase,
				MarketplaceService,
				player,
				productId()
			)
			if not promptOk then
				deathEvent:FireClient(player, {
					Action = "Error",
					Message = "Não foi possível abrir a compra. Tente novamente.",
				})
				warn(string.format(
					"[DeathReviveService] Falha ao abrir compra para %s: %s",
					player.Name,
					tostring(promptError)
				))
			end
		elseif request.Action == "FreeRespawn" then
			if os.clock() - state.CreatedAt >= MVPConfig.Death.FreeRespawnDelaySeconds then
				loadCharacterIfDead(player, state)
			end
		elseif request.Action == "RetryRespawn" then
			local timedOut = os.clock() - (state.RespawnStartedAt or 0)
				>= INITIAL_SPAWN_TIMEOUT_SECONDS
			if player:GetAttribute("RespawnState") == "Failed" or timedOut then
				state.Respawning = false
				loadCharacterIfDead(player, state, true)
			end
		end
	end)
	Players.PlayerAdded:Connect(prepareInitialPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		prepareInitialPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		initialStates[player] = nil
	end)
end

return DeathReviveService
