-- Recomendacoes contextuais sem pop-ups de compra.
--
-- O servidor observa a jornada e deixa no maximo uma recomendacao pronta no
-- Mercador do Ceu. A compra so pode ser iniciada por uma acao explicita do
-- jogador dentro da loja (exceto o renascimento, que pertence a tela de morte).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MonetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)

local CONFIG = MVPConfig.Monetization
local MarketingOfferService = {}
local sessions = setmetatable({}, { __mode = "k" })
local event
local started = false

local SIGNAL_KEYS = table.freeze({
	Death = "Deaths",
	ChestOpened = "Chests",
	EliteDefeated = "Elites",
	HealUsed = "Heals",
	CompanionCaptured = "Captures",
	WheelSpin = "WheelSpins",
})

local function now()
	return workspace:GetServerTimeNow()
end

local function configured(definition)
	return definition
		and definition.Enabled ~= false
		and MonetizationCatalog.GetConfiguredAssetId(definition) > 0
end

local function waterIsSafe(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	if not root or not surfaceY then
		return true
	end
	return root.Position.Y - surfaceY >= CONFIG.MinimumWaterGapStuds
end

local function canEvaluate(player, state, timestamp)
	if timestamp - state.JoinedAt < CONFIG.FirstOfferDelaySeconds
		or state.OffersShown >= CONFIG.MaximumOffersPerSession
		or timestamp < state.NextOfferAt
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("ShopOpen") == true
		or player:GetAttribute("InitialGameStarted") ~= true
	then
		return false
	end
	local tutorialStage, tutorialCompleted = PlayerDataService.GetTutorialProgress(player)
	if not tutorialCompleted and tutorialStage < 5 then
		return false
	end
	if timestamp - (tonumber(player:GetAttribute("LastDamageReceivedAt")) or 0)
		< CONFIG.CombatQuietSeconds
	then
		return false
	end
	return waterIsSafe(player)
end

local function ownsAnyWing(player)
	return player:GetAttribute("OwnedWingProductId") ~= nil
		or (tonumber(player:GetAttribute("TemporaryWingUses")) or 0) > 0
end

local function productContext(definition)
	return type(definition.Context) == "string" and definition.Context or "General"
end

local function sessionIntentScore(state, definition)
	local context = productContext(definition)
	local storeInterest = math.min(45, state.Intent.StoreOpens * 18)
	local directInterest = math.min(35, (state.Intent.ProductPrompts[definition.Id] or 0) * 35)
	local contextInterest = math.min(20, (state.Intent.ContextPrompts[context] or 0) * 10)
	local purchaseInterest = math.min(20, (state.Intent.ContextPurchases[context] or 0) * 10)
	return math.clamp(storeInterest + directInterest + contextInterest + purchaseInterest, 0, 100)
end

local function platformSpenderFit(state, definition)
	if not state.PlatformSpenderDataAvailable then
		return nil
	end
	if state.PlatformSpenderStatus == "OtherPayer" then
		-- Neutro: ter dados disponiveis nao deve penalizar quem nao esta no
		-- grupo de gastadores ativos da plataforma.
		return 50
	end
	if state.PlatformSpenderStatus ~= "Active" then
		return nil
	end
	if definition.ProductType == "GamePass" then
		return 100
	end
	if definition.ProductType == "DeveloperProduct" then
		return definition.PaidRandomItem and 70 or 82
	end
	return 55
end

local function weightedScore(behaviorScore, intentScore, spenderScore)
	local behaviorWeight = math.max(0, tonumber(CONFIG.BehaviorContextWeight) or 0.60)
	local intentWeight = math.max(0, tonumber(CONFIG.SessionIntentWeight) or 0.25)
	local spenderWeight = math.max(0, tonumber(CONFIG.PlatformSpenderWeight) or 0.15)
	local weighted = behaviorScore * behaviorWeight + intentScore * intentWeight
	local totalWeight = behaviorWeight + intentWeight
	if spenderScore ~= nil then
		weighted += spenderScore * spenderWeight
		totalWeight += spenderWeight
	end
	if totalWeight <= 0 then
		return 0
	end
	return weighted / totalWeight
end

local function scoreCandidates(player, state, timestamp)
	local signals = state.Signals
	local runLevel = math.max(1, tonumber(player:GetAttribute("RunLevel")) or 1)
	local equipSlots = math.max(1, tonumber(player:GetAttribute("CompanionEquipSlots")) or 1)
	local candidates = {}
	local function add(productId, behaviorScore, reason)
		local definition = MonetizationCatalog.Get(productId)
		if not configured(definition)
			or (definition.PaidRandomItem and not state.PaidRandomItemsAllowed)
			or state.ShownProducts[productId]
			or timestamp < (state.RefusedUntil[productId] or 0)
		then
			return
		end
		behaviorScore = math.clamp(tonumber(behaviorScore) or 0, 0, 100)
		local intentScore = sessionIntentScore(state, definition)
		local spenderScore = platformSpenderFit(state, definition)
		table.insert(candidates, {
			ProductId = productId,
			Score = weightedScore(behaviorScore, intentScore, spenderScore),
			BehaviorScore = behaviorScore,
			IntentScore = intentScore,
			Reason = reason,
		})
	end

	if not ownsAnyWing(player) and runLevel >= 2 then
		add("AzureWings", 30 + runLevel * 15, "Voce chegou longe. Asas podem ajudar nos proximos saltos.")
	end
	if signals.Chests >= 4 then
		add("TreasureExpedition", 20 + signals.Chests * 10, "Voce abriu varios baus nesta expedicao.")
	end
	if signals.Elites >= 1 then
		add("EliteExpedition", 42 + signals.Elites * 18, "Voce ja provou que consegue derrotar Elites.")
	end
	if signals.Deaths >= 2 or signals.Heals >= 3 then
		add("PermanentPotion", 25 + signals.Deaths * 18 + signals.Heals * 10, "Mais vida combina com seu estilo de exploracao.")
	end
	if signals.Deaths >= 2 then
		add("InvisibilityCape", 30 + signals.Deaths * 17, "A capa oferece uma rota de fuga em combates perigosos.")
	end
	if signals.Captures >= 2 and equipSlots < 4 then
		add("CompanionSlot", 30 + signals.Captures * 15, "Sua equipe de slimes esta crescendo.")
	end
	if state.PaidRandomItemsAllowed and signals.WheelSpins >= 3 then
		add("PaidWheelSpin", 20 + signals.WheelSpins * 12, "Voce ja conhece as recompensas e probabilidades da roleta.")
	end

	table.sort(candidates, function(left, right)
		if left.Score ~= right.Score then
			return left.Score > right.Score
		end
		return left.ProductId < right.ProductId
	end)
	return candidates[1]
end

local function loadPlayerSegments(player, state)
	local success, segments = pcall(function()
		return AnalyticsService:GetPlayerSegmentsAsync(player)
	end)
	if player.Parent ~= Players or sessions[player] ~= state then
		return
	end
	local status = success and type(segments) == "table"
		and segments.HasData == true and segments.PlatformSpenderStatus or nil
	if status == Enum.PlayerPlatformSpenderStatus.Active then
		state.PlatformSpenderDataAvailable = true
		state.PlatformSpenderStatus = "Active"
	elseif status == Enum.PlayerPlatformSpenderStatus.OtherPayer then
		state.PlatformSpenderDataAvailable = true
		state.PlatformSpenderStatus = "OtherPayer"
	else
		-- Unknown, HasData=false e qualquer falha usam o algoritmo neutro.
		-- Nenhuma classificacao economica e presumida.
		state.PlatformSpenderDataAvailable = false
		state.PlatformSpenderStatus = "Unknown"
	end
end

local function publish(player, state, candidate)
	state.Pending = candidate
	state.OffersShown += 1
	state.ShownProducts[candidate.ProductId] = true
	state.NextOfferAt = now() + CONFIG.OfferCooldownSeconds
	player:SetAttribute("MerchantOfferReady", true)
	player:SetAttribute("MerchantOfferProductId", candidate.ProductId)
	player:SetAttribute("MerchantOfferReason", candidate.Reason)
	player:SetAttribute("MerchantOffersShown", state.OffersShown)
	if event then
		event:FireClient(player, {
			Action = "OfferReady",
			ProductId = candidate.ProductId,
			Reason = candidate.Reason,
		})
	end
end

local function setup(player)
	if sessions[player] then
		return
	end
	local state = {
		JoinedAt = now(),
		NextOfferAt = 0,
		OffersShown = 0,
		Signals = {
			Deaths = 0,
			Chests = 0,
			Elites = 0,
			Heals = 0,
			Captures = 0,
			WheelSpins = 0,
		},
		ShownProducts = {},
		RefusedUntil = {},
		Pending = nil,
		PaidRandomItemsAllowed = false,
		Intent = {
			StoreOpens = 0,
			LastStoreOpenedAt = 0,
			ProductPrompts = {},
			ContextPrompts = {},
			ContextPurchases = {},
		},
		PlatformSpenderDataAvailable = false,
		PlatformSpenderStatus = "Unknown",
	}
	sessions[player] = state
	task.spawn(loadPlayerSegments, player, state)
end

function MarketingOfferService.SetEvent(remoteEvent)
	event = remoteEvent
end

function MarketingOfferService.SetPaidRandomItemsAllowed(player, allowed)
	setup(player)
	sessions[player].PaidRandomItemsAllowed = allowed == true
end

function MarketingOfferService.Record(player, signalName, amount)
	local key = SIGNAL_KEYS[signalName]
	if not key or not player or player.Parent ~= Players then
		return
	end
	setup(player)
	local state = sessions[player]
	state.Signals[key] += math.max(1, math.floor(tonumber(amount) or 1))
	player:SetAttribute("OfferSignal_" .. key, state.Signals[key])
end

function MarketingOfferService.RecordStoreOpened(player)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute("ShopOpen") ~= true
		or player:GetAttribute("ActiveShopId") ~= "SkyMerchant"
	then
		return
	end
	setup(player)
	local intent = sessions[player].Intent
	local timestamp = now()
	if timestamp - intent.LastStoreOpenedAt
		< (tonumber(CONFIG.StoreOpenIntentDebounceSeconds) or 5)
	then
		return
	end
	intent.LastStoreOpenedAt = timestamp
	intent.StoreOpens += 1
end

function MarketingOfferService.RecordProductPrompt(player, productId)
	if not player or player.Parent ~= Players or type(productId) ~= "string" then
		return
	end
	local definition = MonetizationCatalog.Get(productId)
	if not definition or productId == "ReviveNoCoinLoss" then
		return
	end
	setup(player)
	local intent = sessions[player].Intent
	local context = productContext(definition)
	intent.ProductPrompts[productId] = (intent.ProductPrompts[productId] or 0) + 1
	intent.ContextPrompts[context] = (intent.ContextPrompts[context] or 0) + 1
end

function MarketingOfferService.GetRecommendation(player)
	setup(player)
	local pending = sessions[player].Pending
	if not pending then
		return nil
	end
	return {
		ProductId = pending.ProductId,
		Reason = pending.Reason,
		Score = pending.Score,
	}
end

function MarketingOfferService.Dismiss(player, productId)
	local state = sessions[player]
	if not state or not state.Pending or state.Pending.ProductId ~= productId then
		return false
	end
	state.RefusedUntil[productId] = now() + CONFIG.RefusedProductCooldownSeconds
	state.Pending = nil
	player:SetAttribute("MerchantOfferReady", false)
	player:SetAttribute("MerchantOfferProductId", nil)
	player:SetAttribute("MerchantOfferReason", nil)
	return true
end

function MarketingOfferService.MarkPurchased(player, productId)
	local state = sessions[player]
	if not state then
		return
	end
	local definition = MonetizationCatalog.Get(productId)
	if definition then
		local context = productContext(definition)
		state.Intent.ContextPurchases[context] = (state.Intent.ContextPurchases[context] or 0) + 1
	end
	if state.Pending and state.Pending.ProductId == productId then
		state.Pending = nil
	end
	player:SetAttribute("MerchantOfferReady", false)
	player:SetAttribute("MerchantOfferProductId", nil)
	player:SetAttribute("MerchantOfferReason", nil)
	player:SetAttribute("LastMonetizationPurchase", productId)
	player:SetAttribute(
		"MonetizationPurchaseSerial",
		(tonumber(player:GetAttribute("MonetizationPurchaseSerial")) or 0) + 1
	)
end

function MarketingOfferService.GetSignals(player)
	setup(player)
	return table.clone(sessions[player].Signals)
end

function MarketingOfferService.Start()
	if started then
		return
	end
	started = true
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CONFIG.OfferEvaluationSeconds)
			local timestamp = now()
			for _, player in ipairs(Players:GetPlayers()) do
				local state = sessions[player]
				if state and not state.Pending and canEvaluate(player, state, timestamp) then
					local candidate = scoreCandidates(player, state, timestamp)
					if candidate and candidate.Score >= CONFIG.MinimumOfferScore then
						publish(player, state, candidate)
					end
				end
			end
		end
	end)
end

return MarketingOfferService
