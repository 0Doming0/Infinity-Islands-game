-- Loja premium, beneficios e validacoes do MVP.
-- A interface nunca concede nada: compras, politicas, cooldowns e efeitos
-- sao validados pelo servidor.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MonetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))
local RewardWheelCatalog = require(ReplicatedStorage:WaitForChild("RewardWheelCatalog"))
local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local RewardWheelService = require(script.Parent:WaitForChild("RewardWheelService"))
local DeveloperProductService = require(script.Parent:WaitForChild("DeveloperProductService"))
local MarketingOfferService = require(script.Parent:WaitForChild("MarketingOfferService"))
local MonetizationAssetService = require(script.Parent:WaitForChild("MonetizationAssetService"))

local MonetizationService = {}
local started = false
local event
local request
local policies = setmetatable({}, { __mode = "k" })
local passOwnership = setmetatable({}, { __mode = "k" })
local flightStates = setmetatable({}, { __mode = "k" })
local wingEnergyStates = setmetatable({}, { __mode = "k" })
local capeOriginalTransparency = setmetatable({}, { __mode = "k" })

local WING_PRIORITY = table.freeze({
	"CelestialWings",
	"RoyalWings",
	"AzureWings",
})
local WING_RANK = table.freeze({
	AzureWings = 1,
	RoyalWings = 2,
	CelestialWings = 3,
})

local function ensureRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = name
		existing.Parent = ReplicatedStorage
	end
	return existing
end

local function configured(definition)
	return definition
		and definition.Enabled ~= false
		and MonetizationCatalog.GetConfiguredAssetId(definition) > 0
end

local function policyFor(player)
	return policies[player] or {
		PaidRandomItemsAllowed = false,
		PolicyLoaded = false,
	}
end

local function loadPolicy(player)
	local success, result = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local allowed = success and type(result) == "table"
		and result.ArePaidRandomItemsRestricted ~= true
	if not success and RunService:IsStudio() then
		-- PolicyService pode nao responder em testes locais. Esta excecao nunca
		-- e usada em servidor publicado.
		allowed = true
	end
	policies[player] = {
		PaidRandomItemsAllowed = allowed,
		PolicyLoaded = success,
	}
	MarketingOfferService.SetPaidRandomItemsAllowed(player, allowed)
end

local function ownsPass(player, definition)
	if not configured(definition) or definition.ProductType ~= "GamePass" then
		return false
	end
	local cache = passOwnership[player]
	if cache and cache[definition.Id] ~= nil then
		return cache[definition.Id]
	end
	cache = cache or {}
	passOwnership[player] = cache
	local success, owns = pcall(
		MarketplaceService.UserOwnsGamePassAsync,
		MarketplaceService,
		player.UserId,
		definition.PassId
	)
	if success then
		cache[definition.Id] = owns == true
		return cache[definition.Id]
	end
	warn(string.format(
		"[MonetizationService] Nao foi possivel consultar o passe %s de %s.",
		tostring(definition.Id),
		player.Name
	))
	return false
end

local function bestWing(player)
	local data = PlayerDataService.Get(player)
	local selectedId = data and data.EquippedWings
	if selectedId and WING_RANK[selectedId] then
		local selected = MonetizationCatalog.Get(selectedId)
		if ownsPass(player, selected) then
			return selected
		end
	end
	for _, productId in ipairs(WING_PRIORITY) do
		local definition = MonetizationCatalog.Get(productId)
		if ownsPass(player, definition) then
			return definition
		end
	end
	if (tonumber(player:GetAttribute("TemporaryWingUses")) or 0) > 0 then
		return MonetizationCatalog.Get("TemporaryWings")
	end
	return nil
end

local function wingEnergyConfig(definition)
	local wing = definition and definition.Wing
	if not wing then
		return 0, 0
	end
	local maximum = math.max(
		0.25,
		tonumber(wing.StaminaSeconds) or tonumber(wing.FlightSeconds) or 1
	)
	local recharge = math.max(
		0.1,
		tonumber(wing.StaminaRechargePerSecond) or maximum / 4
	)
	return maximum, recharge
end

local function wingFlightConfig(definition)
	local wing = definition and definition.Wing or {}
	return {
		RiseHeight = math.clamp(tonumber(wing.RiseHeight) or 10, 4, 30),
		RiseVelocity = math.clamp(tonumber(wing.RiseVelocity) or 28, 18, 45),
		RiseTimeout = math.clamp(tonumber(wing.RiseTimeout) or 1.2, 0.6, 2.5),
		RiseHorizontalMultiplier = math.clamp(
			tonumber(wing.RiseHorizontalMultiplier) or 0.7,
			0.35,
			1
		),
		GlideFallSpeed = -math.clamp(
			math.abs(tonumber(wing.GlideFallSpeed) or 4.7),
			2.5,
			8
		),
		GlideSpeedMultiplier = math.clamp(
			tonumber(wing.GlideSpeedMultiplier) or 0.84,
			0.5,
			1
		),
		ExhaustedGlideFallSpeed = -math.clamp(
			math.abs(tonumber(wing.ExhaustedGlideFallSpeed) or 8.5),
			6,
			12
		),
		ExhaustedGlideSpeedMultiplier = math.clamp(
			tonumber(wing.ExhaustedGlideSpeedMultiplier) or 0.34,
			0.2,
			0.5
		),
	}
end

local function publishWingEnergy(player, state, force)
	if not state then
		player:SetAttribute("WingStamina", nil)
		player:SetAttribute("WingStaminaMax", nil)
		player:SetAttribute("WingStaminaRechargePerSecond", nil)
		return
	end
	local timestamp = workspace:GetServerTimeNow()
	if not force and timestamp - (state.LastPublishedAt or 0) < 0.1 then
		return
	end
	state.LastPublishedAt = timestamp
	player:SetAttribute("WingStamina", math.max(0, state.Amount))
	player:SetAttribute("WingStaminaMax", state.Maximum)
	player:SetAttribute("WingStaminaRechargePerSecond", state.RechargePerSecond)
end

local function ensureWingEnergy(player, definition)
	if not definition or not definition.Wing then
		wingEnergyStates[player] = nil
		publishWingEnergy(player, nil, true)
		return nil
	end
	local maximum, recharge = wingEnergyConfig(definition)
	local state = wingEnergyStates[player]
	if not state
		or state.DefinitionId ~= definition.Id
		or math.abs(state.Maximum - maximum) > 0.001
	then
		state = {
			DefinitionId = definition.Id,
			Amount = maximum,
			Maximum = maximum,
			RechargePerSecond = recharge,
			LastPublishedAt = 0,
		}
		wingEnergyStates[player] = state
		publishWingEnergy(player, state, true)
	else
		state.RechargePerSecond = recharge
	end
	return state
end

local function bestPermanentWingRank(player)
	for _, productId in ipairs(WING_PRIORITY) do
		local definition = MonetizationCatalog.Get(productId)
		if ownsPass(player, definition) then
			return WING_RANK[productId] or 0
		end
	end
	return 0
end

local function purchaseBlockReason(player, definition)
	if not definition then
		return "Oferta invalida."
	end
	if definition.Id == "CompanionSlot" then
		PlayerDataService.Load(player)
		if player:GetAttribute("CompanionSlotPurchasePending") == true then
			return "A compra deste slot ja esta aberta."
		end
		if
			PlayerDataService.GetCompanionEquipSlots(player)
			>= CompanionCatalog.MaxEquipped
		then
			return "Todos os slots de companheiro ja estao desbloqueados."
		end
	elseif definition.Id == "TemporaryWings" then
		if bestPermanentWingRank(player) > 0 then
			return "Voce ja possui asas permanentes."
		end
	elseif WING_RANK[definition.Id] then
		local ownedRank = bestPermanentWingRank(player)
		if ownedRank >= WING_RANK[definition.Id] then
			return ownedRank == WING_RANK[definition.Id]
				and "Voce ja possui estas asas."
				or "Voce ja possui asas de nivel superior."
		end
	elseif definition.ProductType == "GamePass" and ownsPass(player, definition) then
		return "Voce ja possui este beneficio."
	end
	return nil
end

local function clearWingVisual(character)
	MonetizationAssetService.ClearSlot(character, "Wings")
end

local function addWingVisual(character, definition)
	local torso = character and (
		character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
	)
	if not torso or not torso:IsA("BasePart") or not definition or not definition.Wing then
		return false
	end
	local customEquipped = definition.Asset
		and MonetizationAssetService.Equip(
			character,
			definition,
			"Wings"
		)
	if customEquipped then
		character:SetAttribute("EquippedWingAssetName", definition.Asset.ModelName)
		character:SetAttribute("WingVisualUsesFallback", false)
		return true
	end
	local existing = MonetizationAssetService.GetEquipped(character, definition, "Wings")
	if existing and existing:GetAttribute("MonetizationAssetFallback") == true then
		character:SetAttribute("EquippedWingAssetName", definition.DisplayName)
		character:SetAttribute("WingVisualUsesFallback", true)
		return true
	end
	clearWingVisual(character)
	local folder = Instance.new("Folder")
	folder.Name = "MonetizationWings"
	MonetizationAssetService.MarkFallback(folder, definition, "Wings")
	folder.Parent = character
	for side = -1, 1, 2 do
		for feather = 1, 3 do
			local part = Instance.new("WedgePart")
			part.Name = string.format("Wing_%d_%d", side, feather)
			part.Size = Vector3.new(0.35, 1.1 + feather * 0.38, 2.2 + feather * 0.5)
			part.Color = definition.Wing.Color
			part.Material = Enum.Material.Neon
			part.Transparency = 0.12
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.CFrame = torso.CFrame
				* CFrame.new(side * (0.9 + feather * 0.62), 0.65 - feather * 0.18, 0.55)
				* CFrame.Angles(math.rad(12 + feather * 4), math.rad(side * (18 + feather * 7)), math.rad(side * 24))
			part.Parent = folder
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = part
			weld.Parent = part
		end
	end
	character:SetAttribute("EquippedWingAssetName", definition.DisplayName)
	character:SetAttribute("WingVisualUsesFallback", true)
	return true
end

local function clearCapeVisual(character)
	MonetizationAssetService.ClearSlot(character, "Cape")
	if character then
		character:SetAttribute("EquippedCapeAssetName", nil)
		character:SetAttribute("CapeVisualUsesFallback", nil)
	end
end

local function addCapeVisual(character, definition)
	if not character or not definition then
		return false
	end
	local customEquipped = MonetizationAssetService.Equip(
		character,
		definition,
		"Cape"
	)
	if customEquipped then
		character:SetAttribute("EquippedCapeAssetName", definition.Asset.ModelName)
		character:SetAttribute("CapeVisualUsesFallback", false)
		return true
	end
	local existing = MonetizationAssetService.GetEquipped(character, definition, "Cape")
	if existing and existing:GetAttribute("MonetizationAssetFallback") == true then
		character:SetAttribute("EquippedCapeAssetName", definition.DisplayName)
		character:SetAttribute("CapeVisualUsesFallback", true)
		return true
	end
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return false
	end
	clearCapeVisual(character)
	local cape = Instance.new("Part")
	cape.Name = "MonetizationCape"
	cape.Size = Vector3.new(2.4, 3.4, 0.12)
	cape.Color = Color3.fromRGB(31, 27, 48)
	cape.Material = Enum.Material.Fabric
	cape.CanCollide = false
	cape.CanTouch = false
	cape.CanQuery = false
	cape.Massless = true
	cape.CFrame = torso.CFrame
		* CFrame.new(0, -0.55, 0.72)
		* CFrame.Angles(math.rad(8), 0, 0)
	MonetizationAssetService.MarkFallback(cape, definition, "Cape")
	cape.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Name = "MonetizationAutoWeld"
	weld.Part0 = torso
	weld.Part1 = cape
	weld.Parent = cape
	character:SetAttribute("EquippedCapeAssetName", definition.DisplayName)
	character:SetAttribute("CapeVisualUsesFallback", true)
	return true
end

local function syncEquipment(player, visualWing)
	local character = player.Character
	if not character then
		return
	end
	if visualWing then
		addWingVisual(character, visualWing)
	else
		clearWingVisual(character)
		character:SetAttribute("EquippedWingAssetName", nil)
		character:SetAttribute("WingVisualUsesFallback", nil)
	end
	local cape = MonetizationCatalog.Get("InvisibilityCape")
	if player:GetAttribute("OwnsInvisibilityCape") == true then
		addCapeVisual(character, cape)
	else
		clearCapeVisual(character)
	end
	-- Se um entitlement for atualizado durante a invisibilidade, qualquer
	-- equipamento recem-criado tambem entra no snapshot que sera restaurado.
	if player:GetAttribute("InvisibleToEnemies") == true then
		local original = capeOriginalTransparency[player] or {}
		capeOriginalTransparency[player] = original
		for _, descendant in ipairs(character:GetDescendants()) do
			if (descendant:IsA("BasePart") or descendant:IsA("Decal"))
				and original[descendant] == nil
			then
				original[descendant] = descendant.Transparency
				descendant.Transparency = math.max(descendant.Transparency, 0.82)
			end
		end
	end
end

local function publishEntitlements(player, message)
	local wing = bestWing(player)
	local activeFlight = flightStates[player]
	local availableWing = activeFlight and activeFlight.Definition or wing
	local visualWing = availableWing
	local cape = MonetizationCatalog.Get("InvisibilityCape")
	local potion = MonetizationCatalog.Get("PermanentPotion")
	local staminaMaximum, staminaRecharge = wingEnergyConfig(availableWing)
	ensureWingEnergy(player, availableWing)
	player:SetAttribute("OwnedWingProductId", availableWing and availableWing.Id or nil)
	player:SetAttribute("OwnedWingDisplayName", availableWing and availableWing.DisplayName or nil)
	player:SetAttribute(
		"WingDurationSeconds",
		availableWing and staminaMaximum or nil
	)
	player:SetAttribute("WingCooldownSeconds", nil)
	player:SetAttribute(
		"WingStaminaRechargePerSecond",
		availableWing and staminaRecharge or nil
	)
	player:SetAttribute("OwnsInvisibilityCape", ownsPass(player, cape))
	player:SetAttribute("CapeDurationSeconds", cape.DurationSeconds)
	player:SetAttribute("CapeCooldownSeconds", cape.CooldownSeconds)
	player:SetAttribute("OwnsPermanentPotion", ownsPass(player, potion))
	syncEquipment(player, visualWing)
	if event then
		event:FireClient(player, {
			Action = "Entitlements",
			WingProductId = availableWing and availableWing.Id or nil,
			WingDisplayName = availableWing and availableWing.DisplayName or nil,
			WingDurationSeconds = availableWing and staminaMaximum or nil,
			WingStaminaMax = availableWing and staminaMaximum or nil,
			WingStaminaRechargePerSecond = availableWing and staminaRecharge or nil,
			TemporaryWingUses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0,
			OwnsCape = player:GetAttribute("OwnsInvisibilityCape") == true,
			CapeDurationSeconds = cape.DurationSeconds,
			CapeCooldownSeconds = cape.CooldownSeconds,
			OwnsPermanentPotion = player:GetAttribute("OwnsPermanentPotion") == true,
			Message = message,
		})
	end
end

local function applyPermanentPotion(player, character)
	local definition = MonetizationCatalog.Get("PermanentPotion")
	if not ownsPass(player, definition) then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or humanoid:GetAttribute("PermanentPotionApplied") == true then
		return
	end
	local bonus = math.max(0, tonumber(definition.MaxHealthBonus) or 0)
	humanoid:SetAttribute("PermanentPotionApplied", true)
	humanoid.MaxHealth += bonus
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + bonus)
end

local function setupCharacter(player, character)
	MonetizationAssetService.StopWingAnimations(character, 0)
	capeOriginalTransparency[player] = nil
	flightStates[player] = nil
	wingEnergyStates[player] = nil
	player:SetAttribute("InvisibleToEnemies", false)
	player:SetAttribute("CapeActiveUntil", nil)
	player:SetAttribute("CapeActivatedAt", nil)
	player:SetAttribute("WingActive", false)
	player:SetAttribute("WingActiveUntil", nil)
	player:SetAttribute("WingActivatedAt", nil)
	player:SetAttribute("WingReadyAt", nil)
	player:SetAttribute("WingFlightPhase", nil)
	player:SetAttribute("WingFlightStyle", "FastRiseThenSlowGlide")
	character:SetAttribute("InvisibleToEnemies", false)
	task.defer(applyPermanentPotion, player, character)
	task.delay(1, function()
		if character.Parent and player.Parent == Players then
			publishEntitlements(player)
		end
	end)
end

local function storeEntry(player, definition, recommendation)
	local assetId = MonetizationCatalog.GetConfiguredAssetId(definition)
	local entry = {
		Id = definition.Id,
		DisplayName = definition.DisplayName,
		Description = definition.Description,
		ProductType = definition.ProductType,
		AssetId = assetId,
		SuggestedRobux = definition.SuggestedRobux,
		PreviousRobux = definition.PreviousRobux,
		CoinPrice = definition.CoinPrice,
		Configured = assetId > 0,
		OddsText = definition.OddsText,
		HeroImageId = definition.HeroImageId,
		MerchantPitch = definition.MerchantPitch,
		Recommended = recommendation ~= nil,
		RecommendationReason = recommendation and recommendation.Reason or nil,
		RecommendationScore = recommendation and recommendation.Score or nil,
	}
	local blockedReason = purchaseBlockReason(player, definition)
	if definition.PaidRandomItem and not policyFor(player).PaidRandomItemsAllowed then
		entry.Available = false
		entry.UnavailableReason = "Indisponivel para esta conta ou regiao."
	elseif definition.ProductType == "RewardedAd" and definition.Enabled ~= true then
		entry.Available = false
		entry.UnavailableReason = "Sera ativado quando a experiencia cumprir a elegibilidade de anuncios."
	elseif blockedReason then
		entry.Available = false
		entry.UnavailableReason = blockedReason
	else
		entry.Available = entry.Configured
	end
	if definition.ProductType == "Coins" and not blockedReason then
		entry.Available = true
	end
	return entry
end

local function isGlobalStoreProduct(definition)
	return definition ~= nil
		and definition.Enabled ~= false
		and definition.Id ~= "ReviveNoCoinLoss"
		and (
			definition.ProductType == "DeveloperProduct"
			or definition.ProductType == "GamePass"
		)
end

function MonetizationService.GetGlobalStore(player)
	local recommendations = MarketingOfferService.GetRecommendations(player)
	local recommendationByProductId = {}
	for _, recommendation in ipairs(recommendations) do
		recommendationByProductId[recommendation.ProductId] = recommendation
	end
	local entries = {}
	for _, definition in ipairs(MonetizationCatalog.GetAll()) do
		if isGlobalStoreProduct(definition) then
			table.insert(
				entries,
				storeEntry(player, definition, recommendationByProductId[definition.Id])
			)
		end
	end
	return {
		Entries = entries,
		Recommendation = recommendations[1],
		Recommendations = recommendations,
		PaidRandomItemsAllowed = policyFor(player).PaidRandomItemsAllowed,
	}
end

function MonetizationService.GetStore(player)
	local recommendations = MarketingOfferService.GetRecommendations(player)
	local entries = {}
	for _, recommendation in ipairs(recommendations) do
		if #entries >= 2 then
			break
		end
		local definition = MonetizationCatalog.Get(recommendation.ProductId)
		if definition
			and definition.Id ~= "ReviveNoCoinLoss"
			and definition.Enabled ~= false
		then
			table.insert(entries, storeEntry(player, definition, recommendation))
		end
	end
	return {
		Entries = entries,
		Recommendation = recommendations[1],
		Recommendations = recommendations,
		PaidRandomItemsAllowed = policyFor(player).PaidRandomItemsAllowed,
		TemporaryWingUses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0,
	}
end

local function purchaseTemporaryWings(player)
	local definition = MonetizationCatalog.Get("TemporaryWings")
	local paid = ScoreService.TrySpendCoins(player, definition.CoinPrice)
	if not paid then
		return false, "Moedas insuficientes."
	end
	local uses = (tonumber(player:GetAttribute("TemporaryWingUses")) or 0)
		+ MVPConfig.Monetization.TemporaryWingUsesPerPurchase
	player:SetAttribute("TemporaryWingUses", uses)
	MarketingOfferService.MarkPurchased(player, definition.Id)
	publishEntitlements(player, "Asas temporarias adquiridas!")
	return true, "Voce recebeu 3 voos temporarios."
end

local function setBoostAttribute(player, boostName, expiration)
	player:SetAttribute(boostName .. "BoostUntil", expiration)
	player:SetAttribute(boostName .. "BoostActive", expiration > os.time())
end

local function grantBoost(player, productId, boostName)
	local definition = MonetizationCatalog.Get(productId)
	local success, expiration = PlayerDataService.ExtendMonetizationBoost(
		player,
		boostName,
		definition.DurationSeconds
	)
	if not success then
		return false
	end
	setBoostAttribute(player, boostName, expiration)
	MarketingOfferService.MarkPurchased(player, productId)
	if event then
		event:FireClient(player, {
			Action = "PurchaseGranted",
			ProductId = productId,
			Message = definition.DisplayName .. " ativada!",
		})
	end
	return true
end

local function grantPaidSpin(player, purchaseSourceId)
	-- A politica bloqueia o prompt antes da compra. Um recibo ja pago nunca
	-- pode ficar preso caso a politica falhe ao carregar ou mude depois.
	local success = RewardWheelService.Spin(player, "PaidSpin", {
		Level = tonumber(player:GetAttribute("RunLevel")) or 1,
		Paid = true,
		DeferSave = true,
	})
	if success then
		MarketingOfferService.MarkPurchased(player, purchaseSourceId or "PaidWheelSpin")
	end
	return success == true
end

local function clearSpinAgainPurchase(player)
	PlayerDataService.ClearPendingSpinAgainPurchase(player)
	player:SetAttribute("SpinAgainPurchasePending", false)
	player:SetAttribute("PendingSpinAgainSource", nil)
end

local function grantSpinAgain(player)
	-- Assim como o giro pago comum, um recibo existente precisa ser entregue.
	-- A restricao regional continua aplicada antes de abrir o Marketplace.
	local sourceId, level = PlayerDataService.GetPendingSpinAgainPurchase(player)
	if not RewardWheelCatalog.IsSpinAgainSource(sourceId) then
		return false
	end
	local success = RewardWheelService.Spin(player, sourceId, {
		Level = level,
		Paid = true,
		DeferSave = true,
		SpinAgain = true,
	})
	if not success then
		return false
	end
	clearSpinAgainPurchase(player)
	MarketingOfferService.MarkPurchased(player, "SpinAgain")
	return true
end

local function registerDeveloperProducts()
	local treasure = MonetizationCatalog.Get("TreasureExpedition")
	local elite = MonetizationCatalog.Get("EliteExpedition")
	local spin = MonetizationCatalog.Get("PaidWheelSpin")
	local spinAgain = MonetizationCatalog.Get("SpinAgain")
	DeveloperProductService.Register(treasure.ProductId, treasure.Id, function(player)
		return grantBoost(player, treasure.Id, "Treasure")
	end)
	DeveloperProductService.Register(elite.ProductId, elite.Id, function(player)
		return grantBoost(player, elite.Id, "Elite")
	end)
	DeveloperProductService.Register(spin.ProductId, spin.Id, function(player)
		return grantPaidSpin(player, spin.Id)
	end)
	DeveloperProductService.Register(spinAgain.ProductId, spinAgain.Id, grantSpinAgain)
end

local function validateConfiguration()
	local seen = {}
	local configuredPaidProducts = 0
	local errors = 0
	for key, definition in pairs(MonetizationCatalog.Products) do
		if definition.Enabled == false then
			continue
		end
		if definition.ProductType == "DeveloperProduct"
			or definition.ProductType == "GamePass"
		then
			local assetId = MonetizationCatalog.GetConfiguredAssetId(definition)
			local identity = definition.ProductType .. ":" .. tostring(assetId)
			if assetId <= 0 then
				errors += 1
				warn(string.format(
					"[MonetizationService] %s esta ativo, mas nao possui ID.",
					tostring(key)
				))
			elseif seen[identity] then
				errors += 1
				warn(string.format(
					"[MonetizationService] ID duplicado entre %s e %s: %d.",
					tostring(seen[identity]),
					tostring(key),
					assetId
				))
			else
				seen[identity] = key
				configuredPaidProducts += 1
			end
		end
		if definition.Asset
			and (
				type(definition.Asset.ModelName) ~= "string"
				or definition.Asset.ModelName == ""
			)
		then
			errors += 1
			warn(string.format(
				"[MonetizationService] %s possui Asset sem ModelName.",
				tostring(key)
			))
		end
	end
	workspace:SetAttribute("ConfiguredPaidProductCount", configuredPaidProducts)
	workspace:SetAttribute("MonetizationConfigurationReady", errors == 0)
	return errors == 0
end

local function isSkyMerchantOpen(player)
	return player:GetAttribute("ShopOpen") == true
		and player:GetAttribute("ActiveShopId") == "SkyMerchant"
		and player:GetAttribute("SkyMerchantOfferValid") == true
end

local function playerReachedAssignedMerchant(player)
	local targetKey = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
	if targetKey == "" then
		return false
	end
	local targetValue = player:FindFirstChild("PersonalSkyMerchantTargetIsland")
	local target = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value or nil
	if not target
		or not target:IsA("Model")
		or not target:IsDescendantOf(workspace)
		or target:GetAttribute("IsSkyIsland") ~= true
		or tostring(target:GetAttribute("IslandNodeKey") or "") ~= targetKey
	then
		return false
	end
	local merchant = workspace:FindFirstChild("PersonalSkyMerchant_" .. tostring(player.UserId), true)
	if not merchant
		or not merchant:IsA("Model")
		or merchant:GetAttribute("ServerManagedPersonalSkyMerchant") ~= true
		or tonumber(merchant:GetAttribute("OwnerUserId")) ~= player.UserId
		or tostring(merchant:GetAttribute("SpawnIslandKey") or "") ~= targetKey
	then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local anchor = merchant:FindFirstChild("MerchantInteractionAnchor", true)
	return root
		and root:IsA("BasePart")
		and anchor
		and anchor:IsA("BasePart")
		and (root.Position - anchor.Position).Magnitude
			<= math.max(10, tonumber(MVPConfig.Village.PromptDistance) or 13) + 2
end

local function promptPurchase(player, productId, purchaseSource)
	local definition = MonetizationCatalog.Get(productId)
	if not definition
		or definition.Enabled == false
		or productId == "ReviveNoCoinLoss"
	then
		return false, "Oferta invalida."
	end
	local globalStorePurchase = purchaseSource == "GlobalStore"
	if globalStorePurchase and not isGlobalStoreProduct(definition) then
		return false, "Este produto so pode ser comprado no momento correto do jogo."
	end
	if not globalStorePurchase and not isSkyMerchantOpen(player) then
		return false, "Fale com o Mercador do Ceu para comprar."
	end
	if not globalStorePurchase
		and not MarketingOfferService.IsRecommended(player, productId)
	then
		return false, "Este produto nao foi recomendado para sua jornada."
	end
	if definition.PaidRandomItem and not policyFor(player).PaidRandomItemsAllowed then
		return false, "Esta roleta nao esta disponivel para sua conta ou regiao."
	end
	local blockedReason = purchaseBlockReason(player, definition)
	if blockedReason then
		return false, blockedReason
	end
	if definition.ProductType == "Coins" then
		MarketingOfferService.RecordProductPrompt(player, productId)
		return purchaseTemporaryWings(player)
	elseif not configured(definition) then
		return false, "Configure o ID deste produto no MonetizationCatalog."
	elseif definition.ProductType == "DeveloperProduct" then
		MarketingOfferService.RecordProductPrompt(player, productId)
		if definition.Id == "CompanionSlot" then
			player:SetAttribute("CompanionSlotPurchasePending", true)
			player:SetAttribute(
				"CompanionSlotPurchaseTarget",
				PlayerDataService.GetCompanionEquipSlots(player) + 1
			)
		end
		local prompted = pcall(
			MarketplaceService.PromptProductPurchase,
			MarketplaceService,
			player,
			definition.ProductId
		)
		if not prompted then
			if definition.Id == "CompanionSlot" then
				player:SetAttribute("CompanionSlotPurchasePending", false)
				player:SetAttribute("CompanionSlotPurchaseTarget", nil)
			end
			return false, "Nao foi possivel abrir a compra."
		end
		return true, "Compra aberta."
	elseif definition.ProductType == "GamePass" then
		MarketingOfferService.RecordProductPrompt(player, productId)
		local prompted = pcall(
			MarketplaceService.PromptGamePassPurchase,
			MarketplaceService,
			player,
			definition.PassId
		)
		if not prompted then
			return false, "Nao foi possivel abrir a compra."
		end
		return true, "Compra aberta."
	end
	return false, "Oferta indisponivel."
end

local function promptSpinAgain(player)
	local definition = MonetizationCatalog.Get("SpinAgain")
	if not definition or not configured(definition) then
		return false, "Configure o produto Spin Again."
	end
	if not policyFor(player).PaidRandomItemsAllowed then
		return false, "Esta roleta nao esta disponivel para sua conta ou regiao."
	end
	if player:GetAttribute("SpinAgainPurchasePending") == true then
		return false, "A compra para girar novamente ja esta aberta."
	end
	local offerUntil = tonumber(player:GetAttribute("SpinAgainOfferUntil")) or 0
	if workspace:GetServerTimeNow() > offerUntil then
		return false, "A oferta para girar novamente expirou."
	end
	local sourceId = player:GetAttribute("SpinAgainOfferSource")
	local offerSerial = tonumber(player:GetAttribute("SpinAgainOfferSerial")) or 0
	local lastSpinSerial = tonumber(player:GetAttribute("LastRewardWheelSerial")) or 0
	if
		not RewardWheelCatalog.IsSpinAgainSource(sourceId)
		or offerSerial <= 0
		or offerSerial ~= lastSpinSerial
	then
		return false, "Girar novamente esta disponivel apenas para roletas de Elite e Bau Raro."
	end
	PlayerDataService.Load(player)
	local level = math.max(
		1,
		math.floor(tonumber(player:GetAttribute("SpinAgainOfferLevel")) or 1)
	)
	player:SetAttribute("SpinAgainPurchasePending", true)
	player:SetAttribute("PendingSpinAgainSource", sourceId)
	if
		not PlayerDataService.SetPendingSpinAgainPurchase(player, sourceId, level)
		or not PlayerDataService.Save(player, true)
	then
		clearSpinAgainPurchase(player)
		return false, "Nao foi possivel preparar esta compra. Tente novamente."
	end
	player:SetAttribute("SpinAgainOfferSource", nil)
	player:SetAttribute("SpinAgainOfferLevel", nil)
	player:SetAttribute("SpinAgainOfferSerial", nil)
	player:SetAttribute("SpinAgainOfferUntil", nil)
	local prompted = pcall(
		MarketplaceService.PromptProductPurchase,
		MarketplaceService,
		player,
		definition.ProductId
	)
	if not prompted then
		clearSpinAgainPurchase(player)
		task.spawn(PlayerDataService.Save, player, true)
		if workspace:GetServerTimeNow() <= offerUntil then
			player:SetAttribute("SpinAgainOfferSource", sourceId)
			player:SetAttribute("SpinAgainOfferLevel", level)
			player:SetAttribute("SpinAgainOfferSerial", offerSerial)
			player:SetAttribute("SpinAgainOfferUntil", offerUntil)
		end
		return false, "Nao foi possivel abrir a compra."
	end
	return true, "Compra aberta."
end

local function restoreCape(player)
	local original = capeOriginalTransparency[player]
	capeOriginalTransparency[player] = nil
	local character = player.Character
	if original then
		for instance, transparency in pairs(original) do
			if character and instance.Parent and instance:IsDescendantOf(character) then
				instance.Transparency = transparency
			end
		end
	end
	player:SetAttribute("InvisibleToEnemies", false)
	player:SetAttribute("CapeActiveUntil", nil)
	player:SetAttribute("CapeActivatedAt", nil)
	if character then
		character:SetAttribute("InvisibleToEnemies", false)
	end
end

function MonetizationService.CancelCape(player, reason)
	if not player or player:GetAttribute("InvisibleToEnemies") ~= true then
		return false
	end
	restoreCape(player)
	player:SetAttribute("LastCapeCancelReason", tostring(reason or "Cancelled"))
	player:SetAttribute(
		"LastCapeCancelSerial",
		(tonumber(player:GetAttribute("LastCapeCancelSerial")) or 0) + 1
	)
	return true
end

local function activateCape(player)
	local definition = MonetizationCatalog.Get("InvisibilityCape")
	if not ownsPass(player, definition) then
		return false, "Voce nao possui a Capa de Invisibilidade."
	end
	local timestamp = workspace:GetServerTimeNow()
	if timestamp < (tonumber(player:GetAttribute("CapeReadyAt")) or 0) then
		return false, "A capa ainda esta recarregando."
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character
		or not humanoid
		or humanoid.Health <= 0
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("WaterContacting") == true
		or player:GetAttribute("ShopOpen") == true
	then
		return false, "A capa nao pode ser usada agora."
	end
	local original = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			original[descendant] = descendant.Transparency
			-- O jogador permanece como uma silhueta tenue para conseguir se
			-- orientar, mas deixa de parecer apenas semitransparente.
			descendant.Transparency = math.max(descendant.Transparency, 0.82)
		end
	end
	capeOriginalTransparency[player] = original
	player:SetAttribute("InvisibleToEnemies", true)
	player:SetAttribute("CapeActivatedAt", timestamp)
	player:SetAttribute("CapeActiveUntil", timestamp + definition.DurationSeconds)
	character:SetAttribute("InvisibleToEnemies", true)
	player:SetAttribute("CapeReadyAt", timestamp + definition.CooldownSeconds)
	task.delay(definition.DurationSeconds, function()
		if player.Parent == Players then
			restoreCape(player)
		end
	end)
	return true, "Invisibilidade ativada."
end

local function stopWingFlight(player)
	-- Encerre a animacao mesmo se outra rota ja tiver limpado o estado. Uma
	-- AnimationTrack em loop nao pode sobreviver ao pouso ou cancelamento.
	MonetizationAssetService.StopWingAnimations(player.Character, 0.08)
	flightStates[player] = nil
	if player.Parent == Players then
		player:SetAttribute("WingActive", false)
		player:SetAttribute("WingActiveUntil", nil)
		player:SetAttribute("WingActivatedAt", nil)
		player:SetAttribute("WingReadyAt", nil)
		player:SetAttribute("WingFlightPhase", nil)
		player:SetAttribute("WingRiseTargetY", nil)
		publishEntitlements(player)
	end
end

local function activateWing(player)
	local definition = bestWing(player)
	if not definition then
		return false, "Voce nao possui asas."
	end
	if flightStates[player] then
		return true, "Voce ja esta voando."
	end
	local timestamp = workspace:GetServerTimeNow()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid
		or humanoid.Health <= 0
		or not root
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("WaterContacting") == true
	then
		return false, "As asas nao podem ser usadas agora."
	end
	local energy = ensureWingEnergy(player, definition)
	if not energy or energy.Amount <= 0.1 then
		return false, "Pouse para recuperar a estamina das asas."
	end
	if definition.Id == "TemporaryWings" then
		local uses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0
		if uses <= 0 then
			return false, "Seus voos temporarios acabaram."
		end
		player:SetAttribute("TemporaryWingUses", uses - 1)
	end
	addWingVisual(character, definition)
	local flightConfig = wingFlightConfig(definition)
	local riseStartY = root.Position.Y
	flightStates[player] = {
		Speed = definition.Wing.HorizontalSpeed,
		StartedAt = timestamp,
		RiseEndsAt = timestamp + flightConfig.RiseTimeout,
		RiseStartY = riseStartY,
		RiseTargetY = riseStartY + flightConfig.RiseHeight,
		Phase = "Rising",
		FlightConfig = flightConfig,
		LastDirection = nil,
		Root = root,
		Humanoid = humanoid,
		Definition = definition,
		Energy = energy,
		GroundGraceUntil = timestamp + 0.5,
	}
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(
		velocity.X,
		flightConfig.RiseVelocity,
		velocity.Z
	)
	player:SetAttribute("WingActive", true)
	player:SetAttribute("WingActivatedAt", timestamp)
	player:SetAttribute("WingActiveUntil", nil)
	player:SetAttribute("WingReadyAt", nil)
	player:SetAttribute("WingFlightPhase", "Rising")
	player:SetAttribute("WingFlightStyle", "FastRiseThenSlowGlide")
	player:SetAttribute("WingRiseHeight", flightConfig.RiseHeight)
	player:SetAttribute("WingRiseTargetY", riseStartY + flightConfig.RiseHeight)
	player:SetAttribute("WingLastRiseHeight", nil)
	MonetizationAssetService.SetWingAnimationPlaying(character, definition, true)
	publishWingEnergy(player, energy, true)
	publishEntitlements(player)
	return true, "As asas ganharam altura e abriram para planar."
end

local function updateBoostStates()
	local unixNow = os.time()
	for _, player in ipairs(Players:GetPlayers()) do
		local treasureUntil = tonumber(player:GetAttribute("TreasureBoostUntil")) or 0
		local eliteUntil = tonumber(player:GetAttribute("EliteBoostUntil")) or 0
		local treasureActive = treasureUntil > unixNow
		local eliteActive = eliteUntil > unixNow
		player:SetAttribute("TreasureBoostActive", treasureActive)
		player:SetAttribute("EliteBoostActive", eliteActive)
	end
end

function MonetizationService.RecordSignal(player, signalName, amount)
	MarketingOfferService.Record(player, signalName, amount)
end

function MonetizationService.RecordEliteDefeat(player)
	MarketingOfferService.Record(player, "EliteDefeated", 1)
	return player:GetAttribute("EliteBoostActive") == true
end

function MonetizationService.Start()
	if started then
		return
	end
	started = true
	event = ensureRemote("RemoteEvent", "MonetizationEvent")
	request = ensureRemote("RemoteFunction", "MonetizationRequest")
	workspace:SetAttribute("GlobalStoreServerVersion", "GlobalStoreV2PersonalMerchant")
	workspace:SetAttribute("PersonalSkyMerchantServerVersion", "SharedVisualValidatedOpenV5")
	workspace:SetAttribute("MobilityPerksServerVersion", "WingAnimatorLandingStopV7")
	MarketingOfferService.SetEvent(event)
	MarketingOfferService.Start()
	DeveloperProductService.Start()
	RewardWheelService.Start()
	ScoreService.Start()
	MonetizationAssetService.EnsureAssetFolder()
	validateConfiguration()
	registerDeveloperProducts()

	request.OnServerInvoke = function(player, action, productId)
		if action == "GetStore" then
			return MonetizationService.GetStore(player)
		elseif action == "OpenGlobalStore" then
			MarketingOfferService.RecordStoreOpened(player)
			return MonetizationService.GetGlobalStore(player)
		elseif action == "OpenStore" then
			if not isSkyMerchantOpen(player) then
				return nil
			end
			MarketingOfferService.MarkOpened(player)
			MarketingOfferService.RecordStoreOpened(player)
			return MonetizationService.GetStore(player)
		elseif action == "PersonalMerchantEncounter" and type(productId) == "table" then
			local outcome = productId.Outcome
			local offerSerial = productId.OfferSerial
			local success, message, state = MarketingOfferService.RecordEncounter(
				player,
				outcome,
				offerSerial
			)
			return {
				Success = success,
				Message = message,
				State = state,
			}
		elseif action == "ActivatePersonalMerchant" then
			if player:GetAttribute("MerchantOfferReady") ~= true
				or #MarketingOfferService.GetRecommendations(player) == 0
				or player:GetAttribute("IsDowned") == true
			then
				return {
					Success = false,
					Message = "O Mercador ainda nao possui uma recomendacao para voce.",
				}
			end
			if not playerReachedAssignedMerchant(player) then
				return {
					Success = false,
					Message = "Aproxime-se do seu Mercador do Ceu para ver as ofertas.",
				}
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not root then
				return {
					Success = false,
					Message = "O Mercador aguarda voce retornar a expedicao.",
				}
			end
			local store = MonetizationService.GetStore(player)
			if type(store.Entries) ~= "table" or #store.Entries == 0 then
				return {
					Success = false,
					Message = "As recomendacoes mudaram. O Mercador esta preparando novas ofertas.",
				}
			end
			if not MarketingOfferService.MarkOpened(player) then
				return {
					Success = false,
					Message = "Esta recomendacao expirou. Aguarde uma nova visita do Mercador.",
				}
			end
			player:SetAttribute("ShopOpen", true)
			player:SetAttribute("ActiveShopId", "SkyMerchant")
			player:SetAttribute("SkyMerchantOfferValid", true)
			player:SetAttribute("SkyMerchantRobuxOfferId", nil)
			player:SetAttribute("PersonalSkyMerchantState", "Open")
			local openSerial = (tonumber(player:GetAttribute("PersonalSkyMerchantOpenSerial")) or 0) + 1
			player:SetAttribute("PersonalSkyMerchantOpenSerial", openSerial)
			player:SetAttribute("PersonalSkyMerchantLastOpenedAt", workspace:GetServerTimeNow())
			MarketingOfferService.RecordStoreOpened(player)
			if event then
				event:FireClient(player, {
					Action = "OpenPersonalMerchant",
					Store = store,
					OpenSerial = openSerial,
				})
			end
			return { Success = true, Store = store, OpenSerial = openSerial }
		elseif action == "GetEntitlements" then
			local wing = bestWing(player)
			local cape = MonetizationCatalog.Get("InvisibilityCape")
			local staminaMaximum, staminaRecharge = wingEnergyConfig(wing)
			ensureWingEnergy(player, wing)
			return {
				WingProductId = wing and wing.Id or nil,
				WingDisplayName = wing and wing.DisplayName or nil,
				WingDurationSeconds = wing and staminaMaximum or nil,
				WingStaminaMax = wing and staminaMaximum or nil,
				WingStaminaRechargePerSecond = wing and staminaRecharge or nil,
				TemporaryWingUses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0,
				OwnsCape = ownsPass(player, cape),
				CapeDurationSeconds = cape.DurationSeconds,
				CapeCooldownSeconds = cape.CooldownSeconds,
				OwnsPermanentPotion = ownsPass(player, MonetizationCatalog.Get("PermanentPotion")),
			}
		elseif action == "Prompt" and type(productId) == "string" then
			local success, message = promptPurchase(player, productId)
			return { Success = success, Message = message, Store = MonetizationService.GetStore(player) }
		elseif action == "PromptGlobal" and type(productId) == "string" then
			local success, message = promptPurchase(player, productId, "GlobalStore")
			return {
				Success = success,
				Message = message,
				Store = MonetizationService.GetGlobalStore(player),
			}
		elseif action == "PromptSpinAgain" then
			local success, message = promptSpinAgain(player)
			return { Success = success, Message = message }
		elseif action == "DismissOffer" and type(productId) == "string" then
			local success = MarketingOfferService.Dismiss(player, productId)
			return { Success = success, Store = MonetizationService.GetStore(player) }
		elseif action == "ActivateWing" then
			local success, message = activateWing(player)
			return { Success = success, Message = message }
		elseif action == "ActivateCape" then
			local success, message = activateCape(player)
			return { Success = success, Message = message }
		end
		return { Success = false, Message = "Pedido invalido." }
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, definition in ipairs(MonetizationCatalog.GetAll()) do
			if definition.ProductType == "GamePass" and definition.PassId == passId then
				passOwnership[player] = passOwnership[player] or {}
				passOwnership[player][definition.Id] = true
				MarketingOfferService.MarkPurchased(player, definition.Id)
				if definition.Id == "PermanentPotion" and player.Character then
					applyPermanentPotion(player, player.Character)
				end
				publishEntitlements(player, definition.DisplayName .. " adquirido!")
				break
			end
		end
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(
		userId,
		productId,
		purchased
	)
		local spinAgain = MonetizationCatalog.Get("SpinAgain")
		if not spinAgain or productId ~= spinAgain.ProductId or purchased then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			clearSpinAgainPurchase(player)
			task.spawn(PlayerDataService.Save, player, true)
		end
	end)

	local function setup(player)
		task.spawn(function()
			PlayerDataService.Load(player)
			local pendingSpinSource =
				PlayerDataService.GetPendingSpinAgainPurchase(player)
			-- Uma janela do Marketplace nao sobrevive a desconexao. O contexto
			-- persistente continua reservado para um recibo tardio, mas a nova
			-- sessao nunca fica bloqueada como se o prompt ainda estivesse aberto.
			player:SetAttribute("SpinAgainPurchasePending", false)
			player:SetAttribute(
				"PendingSpinAgainSource",
				RewardWheelCatalog.IsSpinAgainSource(pendingSpinSource)
					and pendingSpinSource or nil
			)
			loadPolicy(player)
			local boosts = PlayerDataService.GetMonetizationState(player)
			setBoostAttribute(player, "Treasure", boosts.TreasureBoostUntil)
			setBoostAttribute(player, "Elite", boosts.EliteBoostUntil)
			publishEntitlements(player)
		end)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function(character)
			MonetizationAssetService.StopWingAnimations(character, 0)
			flightStates[player] = nil
		end)
		player:GetAttributeChangedSignal("WingActive"):Connect(function()
			if player:GetAttribute("WingActive") ~= true then
				MonetizationAssetService.StopWingAnimations(player.Character, 0.08)
			end
		end)
		if player.Character then
			setupCharacter(player, player.Character)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		flightStates[player] = nil
		wingEnergyStates[player] = nil
		capeOriginalTransparency[player] = nil
		passOwnership[player] = nil
		policies[player] = nil
		player:SetAttribute("SpinAgainPurchasePending", nil)
		player:SetAttribute("PendingSpinAgainSource", nil)
	end)

	local boostElapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local timestamp = workspace:GetServerTimeNow()
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("InvisibleToEnemies") == true
				and (
					player:GetAttribute("IsDowned") == true
					or player:GetAttribute("WaterDamageActive") == true
				)
			then
				MonetizationService.CancelCape(
					player,
					player:GetAttribute("IsDowned") == true and "Downed" or "Water"
				)
			end
		end
		for player, state in pairs(flightStates) do
			state.Energy.Amount = math.max(0, state.Energy.Amount - dt)
			publishWingEnergy(player, state.Energy, false)
			local landed = timestamp >= state.GroundGraceUntil
				and state.Humanoid.FloorMaterial ~= Enum.Material.Air
			if
				player.Parent ~= Players
				or not state.Root.Parent
				or not state.Humanoid.Parent
				or state.Humanoid.Health <= 0
				or player:GetAttribute("IsDowned") == true
				or player:GetAttribute("WaterContacting") == true
				or landed
			then
				stopWingFlight(player)
			else
				local flightConfig = state.FlightConfig
				local powered = state.Energy.Amount > 0
				local remainingRise = state.RiseTargetY - state.Root.Position.Y
				local nextPhase
				if timestamp < state.RiseEndsAt and remainingRise > 0.04 then
					nextPhase = "Rising"
				elseif powered then
					nextPhase = "Gliding"
				else
					nextPhase = "ExhaustedGlide"
				end
				local completedRise = state.Phase == "Rising"
					and nextPhase ~= "Rising"
				if nextPhase ~= state.Phase then
					state.Phase = nextPhase
					player:SetAttribute("WingFlightPhase", nextPhase)
					if completedRise then
						player:SetAttribute(
							"WingLastRiseHeight",
							math.max(0, state.Root.Position.Y - state.RiseStartY)
						)
						player:SetAttribute("WingRiseTargetY", nil)
					end
				end
				local moveDirection = state.Humanoid.MoveDirection
				local desiredDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
				if desiredDirection.Magnitude < 0.05 then
					local look = state.Root.CFrame.LookVector
					desiredDirection = Vector3.new(look.X, 0, look.Z)
				end
				desiredDirection = desiredDirection.Magnitude > 0.05
					and desiredDirection.Unit
					or Vector3.zero
				state.LastDirection = state.LastDirection
					and state.LastDirection:Lerp(desiredDirection, math.clamp(dt * 7, 0, 1))
					or desiredDirection
				local currentVelocity = state.Root.AssemblyLinearVelocity
				local horizontalMultiplier
				if state.Phase == "Rising" then
					horizontalMultiplier = flightConfig.RiseHorizontalMultiplier
				elseif state.Phase == "Gliding" then
					horizontalMultiplier = flightConfig.GlideSpeedMultiplier
				else
					horizontalMultiplier = flightConfig.ExhaustedGlideSpeedMultiplier
				end
				local desiredHorizontal =
					state.LastDirection * state.Speed * horizontalMultiplier
				local smoothedHorizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z):Lerp(
					desiredHorizontal,
					math.clamp(dt * 6, 0, 1)
				)
				local verticalVelocity
				if state.Phase == "Rising" then
					-- A altura, e nao apenas o tempo, determina o fim da subida.
					-- A velocidade maxima cria o impulso rapido e a frenagem
					-- proporcional evita ultrapassar perceptivelmente o topo.
					local brakingAcceleration = math.max(
						55,
						(flightConfig.RiseVelocity * flightConfig.RiseVelocity)
							/ math.max(2, 2 * flightConfig.RiseHeight)
					)
					verticalVelocity = math.min(
						flightConfig.RiseVelocity,
						math.sqrt(
							math.max(0, 2 * brakingAcceleration * remainingRise)
						)
					)
					local nextStepDistance = verticalVelocity * dt
					if nextStepDistance > remainingRise then
						verticalVelocity = math.max(0, remainingRise / math.max(dt, 0.001))
					end
				else
					local fallTarget = state.Phase == "Gliding"
						and flightConfig.GlideFallSpeed
						or flightConfig.ExhaustedGlideFallSpeed
					local currentVertical = completedRise and 0 or currentVelocity.Y
					verticalVelocity = currentVertical
						+ (fallTarget - currentVertical)
							* math.clamp(dt * 5.5, 0, 1)
					verticalVelocity = math.max(verticalVelocity, fallTarget)
				end
				state.Root.AssemblyLinearVelocity = smoothedHorizontal
					+ Vector3.new(0, verticalVelocity, 0)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if not flightStates[player] then
				local energy = wingEnergyStates[player]
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local canRecharge = energy
					and humanoid
					and humanoid.Health > 0
					and humanoid.FloorMaterial ~= Enum.Material.Air
					and player:GetAttribute("IsDowned") ~= true
					and player:GetAttribute("WaterContacting") ~= true
				if canRecharge and energy.Amount < energy.Maximum then
					energy.Amount = math.min(
						energy.Maximum,
						energy.Amount + energy.RechargePerSecond * dt
					)
					publishWingEnergy(player, energy, false)
				end
			end
		end
		boostElapsed += dt
		if boostElapsed >= 1 then
			boostElapsed = 0
			updateBoostStates()
		end
	end)
	updateBoostStates()
end

return MonetizationService
