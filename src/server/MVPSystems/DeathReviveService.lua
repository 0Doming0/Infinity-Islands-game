-- SkyDungeon V6: tela de morte com renascimento exclusivamente manual.
-- O Developer Product devolve as moedas perdidas antes de recriar o personagem.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local PlayerDataService = require(script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))

local DeathReviveService = {}
local pending = setmetatable({}, { __mode = "k" })
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

local function productId()
	return math.max(0, math.floor(tonumber(MVPConfig.Death.ReviveWithoutCoinLossProductId) or 0))
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
	warn(string.format("[DeathReviveService] Falha ao renascer %s: %s", player.Name, tostring(loadError)))
	deathEvent:FireClient(player, {
		Action = "Error",
		Message = "Não foi possível renascer. Tente novamente.",
	})
	return false
end

local function loadInitialCharacter(player)
	-- O defer permite que PlayerRules e os outros sistemas conectem
	-- CharacterAdded antes do primeiro personagem ser criado.
	task.defer(function()
		if player.Parent and not player.Character and not pending[player] then
			loadCharacterIfDead(player, nil)
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

local function processReceipt(receipt)
	if receipt.ProductId ~= productId() or receipt.ProductId == 0 then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantPurchase(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function DeathReviveService.Start()
	if started then
		return
	end
	started = true
	Players.CharacterAutoLoads = false
	if productId() > 0 then
		MarketplaceService.ProcessReceipt = processReceipt
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
	Players.PlayerAdded:Connect(loadInitialCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		loadInitialCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return DeathReviveService