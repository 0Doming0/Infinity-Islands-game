-- SkyDungeon V6: tela de morte com renascimento exclusivamente manual.
-- O Developer Product devolve as moedas perdidas antes de recriar o personagem.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
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
	return math.max(0, math.floor(tonumber(MVPConfig.Death.ReviveWithoutCoinLossProductId) or 0))
end

local function beginRespawn(player, expectedState)
	local sequence = (tonumber(player:GetAttribute("RespawnSequence")) or 0) + 1
	player:SetAttribute("RespawnSequence", sequence)
	player:SetAttribute("RespawnState", "Preparing")
	if expectedState then
		expectedState.RespawnSequence = sequence
	end
	deathEvent:FireClient(player, {
		Action = "PreparingRespawn",
		RespawnSequence = sequence,
	})
	return sequence
end

local function loadCharacterIfDead(player, expectedState)
	if not player.Parent then
		return false
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return false
	end

	if expectedState then
		if pending[player] ~= expectedState or expectedState.Respawning then
			return false
		end
		expectedState.Respawning = true
		pending[player] = nil
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
	warn(string.format("[DeathReviveService] Falha ao renascer %s: %s", player.Name, tostring(loadError)))
	deathEvent:FireClient(player, {
		Action = "Error",
		Message = "Não foi possível renascer. Tente novamente.",
		RespawnSequence = respawnSequence,
	})
	return false
end

local function worldIsReady()
	local generated = Workspace:FindFirstChild("ProceduralStructures")
	return generated ~= nil and generated:GetAttribute("InitialGenerationComplete") == true
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
		while
			player.Parent
			and character.Parent
			and player:GetAttribute("InitialSpawnPositioned") ~= true
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
	player:SetAttribute("InitialGameStarted", true)
	player:SetAttribute("InitialSpawnPositioned", false)
	player:SetAttribute("InitialStartState", "Positioning")
	local loaded, loadError = pcall(function()
		player:LoadCharacter()
	end)
	if not loaded then
		state.Spawning = false
		state.Started = false
		player:SetAttribute("InitialGameStarted", false)
		player:SetAttribute("InitialStartState", "Ready")
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
	player.CharacterAdded:Connect(function(character)
		protectInitialCharacter(player, character)
	end)
	task.spawn(function()
		PlayerDataService.Load(player)
		if not player.Parent or initialStates[player] ~= state then
			return
		end
		player:SetAttribute("InitialStartState", "PreparingWorld")
		while player.Parent and initialStates[player] == state and not worldIsReady() do
			task.wait(0.25)
		end
		if player.Parent and initialStates[player] == state then
			state.Ready = true
			player:SetAttribute("InitialStartState", "Ready")
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
	if not state or state.Refunded then
		return true
	end
	state.Refunded = true
	if state.LostCoins > 0 then
		ScoreService.RefundCoins(player, state.LostCoins, "RobuxReviveRefund")
		task.spawn(PlayerDataService.Save, player, false)
	end
	player:SetAttribute("PendingReviveCoinRefund", 0)
	player:SetAttribute("ReviveGrantedSerial", (player:GetAttribute("ReviveGrantedSerial") or 0) + 1)
	deathEvent:FireClient(player, {
		Action = "Granted",
		CoinsRefunded = state.LostCoins,
	})
	loadCharacterIfDead(player, state)
	return true
end

local function processRevivePurchase(player)
	if not pending[player] then
		return false
	end
	grantPurchase(player)
	return true
end

function DeathReviveService.Start()
	if started then
		return
	end
	started = true
	Players.CharacterAutoLoads = false
	DeveloperProductService.Start()
	DeveloperProductService.Register(productId(), "ReviveWithoutCoinLoss", processRevivePurchase)
	startRequest.OnServerInvoke = function(player, action)
		local state = initialStates[player]
		if not state then
			return { Success = false, Ready = false, State = "LoadingData" }
		end
		if action == "Get" then
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
				return { Success = false, Ready = false, Message = "O mundo ainda está carregando." }
			end
			if state.Started then
				if player.Character or player:GetAttribute("InitialSpawnPositioned") == true then
					return { Success = true, Ready = true, Started = true }
				end
				state.Started = false
				state.Spawning = false
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
			MarketplaceService:PromptProductPurchase(player, productId())
		elseif request.Action == "FreeRespawn" then
			if os.clock() - state.CreatedAt >= MVPConfig.Death.FreeRespawnDelaySeconds then
				loadCharacterIfDead(player, state)
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
