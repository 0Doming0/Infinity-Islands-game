-- Recomendacoes contextuais sem pop-ups de compra.
--
-- O servidor observa a jornada e deixa no maximo duas recomendacoes prontas no
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

local function deterministicFraction(player, salt)
	local userId = math.max(0, tonumber(player.UserId) or 0)
	local value = (userId * 48271 + math.max(0, salt or 0) * 69621 + 17) % 2147483647
	return (value % 10000) / 10000
end

local function firstOfferDelay(player)
	local base = math.max(0, tonumber(CONFIG.FirstOfferDelaySeconds) or 0)
	local jitter = math.max(0, tonumber(CONFIG.FirstOfferDelayJitterSeconds) or 0)
	return base + deterministicFraction(player, 11) * jitter
end

local function needObservationDelay(player, state, score)
	local urgent = score >= (tonumber(CONFIG.UrgentOfferScore) or math.huge)
	local base = urgent
		and math.max(0, tonumber(CONFIG.UrgentNeedObservationSeconds) or 0)
		or math.max(0, tonumber(CONFIG.NeedObservationSeconds) or 0)
	local jitter = urgent
		and math.max(0, tonumber(CONFIG.UrgentNeedObservationJitterSeconds) or 0)
		or math.max(0, tonumber(CONFIG.NeedObservationJitterSeconds) or 0)
	local salt = state.OffersShown * 97 + math.floor(score * 10 + 0.5)
	return base + deterministicFraction(player, salt) * jitter
end

local function configured(definition)
	return definition
		and definition.Enabled ~= false
		and MonetizationCatalog.GetConfiguredAssetId(definition) > 0
end

local function canEvaluate(player, state, timestamp)
	if timestamp < state.FirstOfferAt then
		return false, "WaitingForOfferDelay", state.FirstOfferAt - timestamp
	end
	if state.OffersShown >= CONFIG.MaximumOffersPerSession then
		return false, "SessionOfferLimit"
	end
	if timestamp < state.NextOfferAt then
		return false, "WaitingForOfferCooldown", state.NextOfferAt - timestamp
	end
	if player:GetAttribute("IsDowned") == true then
		return false, "WaitingForRecovery"
	end
	-- Abrir outra interface ou ainda existir um modelo antigo nao pode impedir
	-- a preparacao da recomendacao. O WorldService V8 limpa modelos obsoletos e
	-- a compra continua dependendo de interacao explicita com o Mercador.
	if player:GetAttribute("InitialGameStarted") ~= true then
		return false, "WaitingForGameStart"
	end
	local tutorialStage, tutorialCompleted = PlayerDataService.GetTutorialProgress(player)
	if not tutorialCompleted and tutorialStage < 5 then
		return false, "WaitingForTutorial"
	end

	-- Preparar uma recomendacao nao abre UI nem compra. Bloquear esta etapa por
	-- dano recente ou proximidade da agua fazia jogadores em movimento normal
	-- nunca chegarem a MerchantOfferReady. A interacao continua validada quando
	-- o jogador encontra fisicamente a loja e pressiona E.
	return true, "Eligible"
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
	local ownedWingProductId = player:GetAttribute("OwnedWingProductId")
	local ownsPermanentWing = ownedWingProductId ~= nil
	local candidates = {}
	local fallbackUsed = false
	local fallbackProductId

	local function add(productId, behaviorScore, reason, isFallback)
		local definition = MonetizationCatalog.Get(productId)
		if not configured(definition)
			or (definition.PaidRandomItem and not state.PaidRandomItemsAllowed)
			or state.ShownProducts[productId]
			or timestamp < (state.RefusedUntil[productId] or 0)
		then
			return false
		end
		if productId == "TemporaryWings" and ownsPermanentWing then
			return false
		end
		if productId == "InvisibilityCape"
			and player:GetAttribute("OwnsInvisibilityCape") == true
		then
			return false
		end
		if productId == "CompanionSlot" and equipSlots >= 4 then
			return false
		end
		behaviorScore = math.clamp(tonumber(behaviorScore) or 0, 0, 100)
		local intentScore = sessionIntentScore(state, definition)
		local spenderScore = platformSpenderFit(state, definition)
		local candidate = {
			ProductId = productId,
			Context = productContext(definition),
			Score = weightedScore(behaviorScore, intentScore, spenderScore),
			BehaviorScore = behaviorScore,
			IntentScore = intentScore,
			Reason = reason,
			Fallback = isFallback == true,
		}
		table.insert(candidates, candidate)
		if candidate.Fallback and not fallbackProductId then
			fallbackUsed = true
			fallbackProductId = productId
		end
		return true
	end

	if not ownsAnyWing(player) and runLevel < 2 then
		add(
			"TemporaryWings",
			97,
			"Experimente tres voos antes de decidir quais asas combinam com sua jornada."
		)
	end
	if not ownsAnyWing(player) and runLevel >= 2 then
		add("AzureWings", 30 + runLevel * 15, "Voce chegou longe. Asas podem ajudar nos proximos saltos.")
	end
	if runLevel >= 4
		and ownedWingProductId ~= "RoyalWings"
		and ownedWingProductId ~= "CelestialWings"
	then
		add("RoyalWings", 22 + runLevel * 14, "Seu nivel pede mais tempo para corrigir a rota durante o voo.")
	end
	if runLevel >= 6 and ownedWingProductId ~= "CelestialWings" then
		add("CelestialWings", 18 + runLevel * 14, "As rotas mais altas valorizam um voo mais longo.")
	end
	if signals.Chests >= 4 then
		add("TreasureExpedition", 20 + signals.Chests * 10, "Voce abriu varios baus nesta expedicao.")
	end
	if signals.Elites >= 1 then
		add("EliteExpedition", 42 + signals.Elites * 18, "Voce ja provou que consegue derrotar Elites.")
	end
	if (signals.Deaths >= 2 or signals.Heals >= 3)
		and player:GetAttribute("OwnsPermanentPotion") ~= true
	then
		add("PermanentPotion", 25 + signals.Deaths * 18 + signals.Heals * 10, "Mais vida combina com seu estilo de exploracao.")
	end
	if signals.Deaths >= 2
		and player:GetAttribute("OwnsInvisibilityCape") ~= true
	then
		add("InvisibilityCape", 30 + signals.Deaths * 17, "A capa oferece uma rota de fuga em combates perigosos.")
	end
	if signals.Captures >= 2 and equipSlots < 4 then
		add("CompanionSlot", 30 + signals.Captures * 15, "Sua equipe de slimes esta crescendo.")
	end
	if state.PaidRandomItemsAllowed and signals.WheelSpins >= 3 then
		add("PaidWheelSpin", 20 + signals.WheelSpins * 12, "Voce ja conhece as recompensas e probabilidades da roleta.")
	end

	local bestNaturalScore = 0
	for _, candidate in ipairs(candidates) do
		bestNaturalScore = math.max(bestNaturalScore, candidate.Score)
	end
	if bestNaturalScore < (tonumber(CONFIG.MinimumOfferScore) or 0) then
		-- Sempre existe pelo menos uma recomendacao utilizavel para o primeiro
		-- encontro. A ordem evita oferecer asas temporarias a quem ja possui asas
		-- permanentes e termina em um produto repetivel nao aleatorio.
		local fallbackOptions = {
			{
				Id = "TemporaryWings",
				Score = 98,
				Reason = "Leve tres impulsos de voo para experimentar novas rotas nesta expedicao.",
			},
			{
				Id = "InvisibilityCape",
				Score = 96,
				Reason = "Tenha uma rota de fuga pronta para os combates mais perigosos.",
			},
			{
				Id = "CompanionSlot",
				Score = 94,
				Reason = "Prepare um espaco extra para ampliar sua equipe de slimes.",
			},
			{
				Id = "EliteExpedition",
				Score = 92,
				Reason = "Guarde este selo para transformar sua proxima caca a Elite em uma recompensa maior.",
			},
		}
		for _, fallback in ipairs(fallbackOptions) do
			if add(fallback.Id, fallback.Score, fallback.Reason, true) then
				break
			end
		end
	end

	player:SetAttribute("PersonalSkyMerchantRawCandidateCount", #candidates)
	player:SetAttribute("PersonalSkyMerchantCandidateFallbackUsed", fallbackUsed)
	player:SetAttribute("PersonalSkyMerchantCandidateFallbackProductId", fallbackProductId)

	table.sort(candidates, function(left, right)
		if left.Score ~= right.Score then
			return left.Score > right.Score
		end
		return left.ProductId < right.ProductId
	end)
	return candidates
end

local function selectBestCandidates(candidates)
	local best = candidates[1]
	if not best or best.Score < CONFIG.MinimumOfferScore then
		return {}
	end
	local maximum = math.max(1, math.floor(tonumber(CONFIG.MaximumMerchantRecommendations) or 1))
	maximum = math.min(2, maximum)
	local scoreWindow = math.max(0, tonumber(CONFIG.MerchantRecommendationScoreWindow) or 0)
	local selected = {}
	local selectedContexts = {}
	for _, candidate in ipairs(candidates) do
		if #selected >= maximum or candidate.Score < CONFIG.MinimumOfferScore then
			break
		end
		if best.Score - candidate.Score <= scoreWindow
			and not selectedContexts[candidate.Context]
		then
			selectedContexts[candidate.Context] = true
			table.insert(selected, candidate)
		end
	end
	return selected
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
		state.PlatformSpenderDataAvailable = false
		state.PlatformSpenderStatus = "Unknown"
	end
end

local function setEncounterState(player, state, encounterState)
	state.EncounterState = encounterState
	player:SetAttribute("PersonalSkyMerchantEncounterState", encounterState)
	player:SetAttribute("PersonalSkyMerchantEncounterSerial", state.EncounterSerial or 0)
end

local function clearOfferAttributes(player)
	player:SetAttribute("MerchantOfferReady", false)
	player:SetAttribute("MerchantOfferProductId", nil)
	player:SetAttribute("MerchantOfferReason", nil)
	player:SetAttribute("MerchantOfferScore", nil)
	player:SetAttribute("MerchantRecommendedProductIds", nil)
	player:SetAttribute("MerchantRecommendedOfferCount", 0)
end

local function endPendingEncounter(player, state, outcome, applyRefusedCooldown)
	if not state.Pending then
		return false
	end
	local timestamp = now()
	if applyRefusedCooldown then
		for _, candidate in ipairs(state.Pending) do
			state.RefusedUntil[candidate.ProductId] = timestamp + CONFIG.RefusedProductCooldownSeconds
		end
	end
	state.Pending = nil
	state.NextOfferAt = math.max(
		state.NextOfferAt or 0,
		timestamp + math.max(0, tonumber(CONFIG.OfferCooldownSeconds) or 0)
	)
	clearOfferAttributes(player)
	setEncounterState(player, state, outcome)
	player:SetAttribute("PersonalSkyMerchantState", outcome)
	if event then
		event:FireClient(player, {
			Action = "OfferEnded",
			Outcome = outcome,
			OfferSerial = state.EncounterSerial,
		})
	end
	return true
end

local function publish(player, state, candidates)
	local primary = candidates[1]
	state.Pending = candidates
	state.OffersShown += 1
	state.EncounterSerial = state.OffersShown
	local productIds = {}
	for _, candidate in ipairs(candidates) do
		state.ShownProducts[candidate.ProductId] = true
		table.insert(productIds, candidate.ProductId)
	end
	state.NextOfferAt = now() + CONFIG.OfferCooldownSeconds
	state.NeedSignature = nil
	state.NeedReadyAt = nil
	player:SetAttribute("MerchantOffersShown", state.OffersShown)
	setEncounterState(player, state, "Unseen")
	player:SetAttribute("MerchantOfferProductId", primary.ProductId)
	player:SetAttribute("MerchantOfferReason", primary.Reason)
	player:SetAttribute("MerchantOfferScore", math.floor(primary.Score * 10 + 0.5) / 10)
	player:SetAttribute("MerchantRecommendedProductIds", table.concat(productIds, ","))
	player:SetAttribute("MerchantRecommendedOfferCount", #productIds)
	player:SetAttribute("PersonalSkyMerchantState", "Ready")
	player:SetAttribute("MerchantOfferReady", true)
	if event then
		event:FireClient(player, {
			Action = "OfferReady",
			ProductId = primary.ProductId,
			ProductIds = productIds,
			Reason = primary.Reason,
			Score = primary.Score,
		})
	end
end

local function setup(player)
	if sessions[player] then
		return
	end
	local joinedAt = now()
	local state = {
		JoinedAt = joinedAt,
		FirstOfferAt = joinedAt + firstOfferDelay(player),
		NextOfferAt = 0,
		OffersShown = 0,
		EncounterSerial = 0,
		EncounterState = "Inactive",
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
		NeedSignature = nil,
		NeedReadyAt = nil,
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
	player:SetAttribute("PersonalSkyMerchantAlgorithmVersion", "GuaranteedEncounterV8")
	player:SetAttribute("PersonalSkyMerchantState", "WaitingForEligibility")
	player:SetAttribute("MerchantOfferReady", false)
	player:SetAttribute("MerchantOffersShown", 0)
	player:SetAttribute("PersonalSkyMerchantEncounterSerial", 0)
	player:SetAttribute("PersonalSkyMerchantEncounterState", "Inactive")
	player:SetAttribute("MerchantOfferScore", nil)
	player:SetAttribute("MerchantRecommendedProductIds", nil)
	player:SetAttribute("MerchantRecommendedOfferCount", 0)
	player:SetAttribute("PersonalSkyMerchantRawCandidateCount", 0)
	player:SetAttribute("PersonalSkyMerchantSelectedCandidateCount", 0)
	player:SetAttribute("PersonalSkyMerchantCandidateFallbackUsed", false)
	player:SetAttribute("PersonalSkyMerchantCandidateFallbackProductId", nil)
	player:SetAttribute("PersonalSkyMerchantPendingRecovered", false)
	player:SetAttribute(
		"PersonalSkyMerchantWaitSeconds",
		math.max(0, math.ceil(state.FirstOfferAt - joinedAt))
	)
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
	if timestamp - intent.LastStoreOpenedAt < (tonumber(CONFIG.StoreOpenIntentDebounceSeconds) or 5) then
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
	local primary = pending and pending[1]
	if not primary then
		return nil
	end
	return {
		ProductId = primary.ProductId,
		Reason = primary.Reason,
		Score = primary.Score,
	}
end

function MarketingOfferService.GetRecommendations(player)
	setup(player)
	local result = {}
	for _, candidate in ipairs(sessions[player].Pending or {}) do
		table.insert(result, {
			ProductId = candidate.ProductId,
			Reason = candidate.Reason,
			Score = candidate.Score,
		})
	end
	return result
end

function MarketingOfferService.IsRecommended(player, productId)
	for _, candidate in ipairs(MarketingOfferService.GetRecommendations(player)) do
		if candidate.ProductId == productId then
			return true
		end
	end
	return false
end

function MarketingOfferService.RecordEncounter(player, outcome, offerSerial)
	if not player or player.Parent ~= Players or type(outcome) ~= "string" then
		return false, "InvalidEncounter", "Inactive"
	end
	setup(player)
	local state = sessions[player]
	local serial = math.floor(tonumber(offerSerial) or -1)
	if not state.Pending
		or serial ~= state.EncounterSerial
		or player:GetAttribute("MerchantOfferReady") ~= true
	then
		return false, "StaleOffer", state.EncounterState
	end

	if outcome == "Presented" then
		if state.EncounterState == "Unseen" then
			setEncounterState(player, state, "Presented")
			player:SetAttribute("PersonalSkyMerchantState", "Presented")
		end
		local accepted = state.EncounterState == "Presented" or state.EncounterState == "Opened"
		if accepted then
			return true, nil, state.EncounterState
		end
		return false, "InvalidTransition", state.EncounterState
	elseif outcome == "Ignored" then
		if state.EncounterState ~= "Presented" then
			return false, "InvalidTransition", state.EncounterState
		end
		local ended = endPendingEncounter(player, state, "Ignored", true)
		return ended, ended and nil or "NoPendingOffer", state.EncounterState
	elseif outcome == "Dismissed" then
		if state.EncounterState ~= "Opened" then
			return false, "InvalidTransition", state.EncounterState
		end
		local ended = endPendingEncounter(player, state, "Dismissed", true)
		return ended, ended and nil or "NoPendingOffer", state.EncounterState
	end
	return false, "InvalidOutcome", state.EncounterState
end

function MarketingOfferService.MarkOpened(player)
	local state = sessions[player]
	if not state or not state.Pending then
		return false
	end
	if state.EncounterState ~= "Unseen"
		and state.EncounterState ~= "Presented"
		and state.EncounterState ~= "Opened"
	then
		return false
	end
	setEncounterState(player, state, "Opened")
	player:SetAttribute("PersonalSkyMerchantState", "Opened")
	return true
end

function MarketingOfferService.Dismiss(player, productId)
	local state = sessions[player]
	if not state or not state.Pending then
		return false
	end
	local containsProduct = false
	for _, candidate in ipairs(state.Pending) do
		if candidate.ProductId == productId then
			containsProduct = true
		end
	end
	if not containsProduct then
		return false
	end
	return endPendingEncounter(player, state, "Dismissed", true)
end

function MarketingOfferService.ExpireEncounter(player, offerSerial)
	if not player or player.Parent ~= Players then
		return false
	end
	local state = sessions[player]
	if not state or not state.Pending then
		return false
	end
	local serial = math.max(0, math.floor(tonumber(offerSerial) or -1))
	if serial ~= state.EncounterSerial then
		return false
	end
	if player:GetAttribute("ShopOpen") == true
		and player:GetAttribute("ActiveShopId") == "SkyMerchant"
	then
		player:SetAttribute("ShopOpen", false)
		player:SetAttribute("ActiveShopId", nil)
		player:SetAttribute("SkyMerchantOfferValid", nil)
		player:SetAttribute("SkyMerchantRobuxOfferId", nil)
	end
	return endPendingEncounter(player, state, "ExpiredWithIsland", false)
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
	if state.Pending then
		for index = #state.Pending, 1, -1 do
			if state.Pending[index].ProductId == productId then
				table.remove(state.Pending, index)
			end
		end
		if #state.Pending == 0 then
			state.Pending = nil
		end
	end
	if state.Pending then
		local primary = state.Pending[1]
		local productIds = {}
		for _, candidate in ipairs(state.Pending) do
			table.insert(productIds, candidate.ProductId)
		end
		player:SetAttribute("MerchantOfferReady", true)
		player:SetAttribute("MerchantOfferProductId", primary.ProductId)
		player:SetAttribute("MerchantOfferReason", primary.Reason)
		player:SetAttribute("MerchantOfferScore", math.floor(primary.Score * 10 + 0.5) / 10)
		player:SetAttribute("MerchantRecommendedProductIds", table.concat(productIds, ","))
		player:SetAttribute("MerchantRecommendedOfferCount", #productIds)
		player:SetAttribute("PersonalSkyMerchantState", "ReadyAfterPurchase")
		if state.EncounterState ~= "Opened" then
			setEncounterState(player, state, "Unseen")
		end
		if event then
			event:FireClient(player, {
				Action = "OfferReady",
				ProductId = primary.ProductId,
				ProductIds = productIds,
				Reason = primary.Reason,
				Score = primary.Score,
			})
		end
	else
		clearOfferAttributes(player)
		setEncounterState(player, state, "Purchased")
		player:SetAttribute("PersonalSkyMerchantState", "Purchased")
	end
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

local function restorePendingAttributes(player, state)
	local pending = state.Pending
	local primary = pending and pending[1]
	if not primary then
		return false
	end
	local encounterState = tostring(state.EncounterState or "Unseen")
	if encounterState == "Ignored"
		or encounterState == "Dismissed"
		or encounterState == "Purchased"
		or encounterState == "ExpiredWithIsland"
	then
		return false
	end
	local recovered = player:GetAttribute("MerchantOfferReady") ~= true
		or player:GetAttribute("MerchantOfferProductId") ~= primary.ProductId
	local productIds = {}
	for _, candidate in ipairs(pending) do
		table.insert(productIds, candidate.ProductId)
	end
	player:SetAttribute("MerchantOfferProductId", primary.ProductId)
	player:SetAttribute("MerchantOfferReason", primary.Reason)
	player:SetAttribute("MerchantOfferScore", math.floor(primary.Score * 10 + 0.5) / 10)
	player:SetAttribute("MerchantRecommendedProductIds", table.concat(productIds, ","))
	player:SetAttribute("MerchantRecommendedOfferCount", #productIds)
	player:SetAttribute("MerchantOfferReady", true)
	player:SetAttribute("PersonalSkyMerchantPendingRecovered", recovered)
	return true
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
				if state and state.Pending then
					restorePendingAttributes(player, state)
				elseif state then
					player:SetAttribute("PersonalSkyMerchantPendingRecovered", false)
					local eligible, reason, waitSeconds = canEvaluate(player, state, timestamp)
					player:SetAttribute("PersonalSkyMerchantState", reason)
					player:SetAttribute("PersonalSkyMerchantEligibilityReason", reason)
					player:SetAttribute(
						"PersonalSkyMerchantWaitSeconds",
						waitSeconds and math.max(0, math.ceil(waitSeconds)) or nil
					)

					if eligible then
						local candidates = selectBestCandidates(scoreCandidates(player, state, timestamp))
						player:SetAttribute("PersonalSkyMerchantSelectedCandidateCount", #candidates)
						if #candidates > 0 then
							local productIds = {}
							for _, candidate in ipairs(candidates) do
								table.insert(productIds, candidate.ProductId)
							end
							local signature = table.concat(productIds, ",")
							local bestScore = candidates[1].Score
							if state.NeedSignature ~= signature or not state.NeedReadyAt then
								state.NeedSignature = signature
								state.NeedReadyAt = timestamp + needObservationDelay(player, state, bestScore)
							else
								state.NeedReadyAt = math.min(
									state.NeedReadyAt,
									timestamp + needObservationDelay(player, state, bestScore)
								)
							end
							local remaining = math.max(0, state.NeedReadyAt - timestamp)
							player:SetAttribute(
								"PersonalSkyMerchantCandidateScore",
								math.floor(bestScore * 10 + 0.5) / 10
							)
							player:SetAttribute("PersonalSkyMerchantWaitSeconds", math.ceil(remaining))
							if remaining <= 0 then
								publish(player, state, candidates)
							else
								player:SetAttribute("PersonalSkyMerchantState", "WaitingForNaturalMoment")
							end
						else
							state.NeedSignature = nil
							state.NeedReadyAt = nil
							player:SetAttribute("PersonalSkyMerchantCandidateScore", nil)
							player:SetAttribute("PersonalSkyMerchantState", "WaitingForNeed")
						end
					end
				end
			end
		end
	end)
end

return MarketingOfferService
