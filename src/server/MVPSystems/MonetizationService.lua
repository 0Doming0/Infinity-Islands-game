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
				descendant.Transparency = math.max(descendant.Transparency, 0.65)
			end
		end
	end
end

local function publishEntitlements(player, message)
	local wing = bestWing(player)
	local activeFlight = flightStates[player]
	local visualWing = activeFlight and activeFlight.Definition or wing
	local cape = MonetizationCatalog.Get("InvisibilityCape")
	local potion = MonetizationCatalog.Get("PermanentPotion")
	player:SetAttribute("OwnedWingProductId", wing and wing.Id or nil)
	player:SetAttribute("OwnsInvisibilityCape", ownsPass(player, cape))
	player:SetAttribute("OwnsPermanentPotion", ownsPass(player, potion))
	syncEquipment(player, visualWing)
	if event then
		event:FireClient(player, {
			Action = "Entitlements",
			WingProductId = wing and wing.Id or nil,
			TemporaryWingUses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0,
			OwnsCape = player:GetAttribute("OwnsInvisibilityCape") == true,
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
	capeOriginalTransparency[player] = nil
	player:SetAttribute("InvisibleToEnemies", false)
	player:SetAttribute("CapeActiveUntil", nil)
	player:SetAttribute("WingActive", false)
	player:SetAttribute("WingActiveUntil", nil)
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
		Recommended = recommendation ~= nil and recommendation.ProductId == definition.Id,
		RecommendationReason = recommendation and recommendation.ProductId == definition.Id
			and recommendation.Reason or nil,
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

function MonetizationService.GetStore(player)
	local recommendation = MarketingOfferService.GetRecommendation(player)
	local entries = {}
	for _, definition in ipairs(MonetizationCatalog.GetAll()) do
		-- Renascimento possui seu proprio momento e nunca aparece como oferta
		-- generica dentro da loja.
		if definition.Id ~= "ReviveNoCoinLoss"
			and definition.Enabled ~= false
		then
			table.insert(entries, storeEntry(player, definition, recommendation))
		end
	end
	return {
		Entries = entries,
		Recommendation = recommendation,
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

local function promptPurchase(player, productId)
	local definition = MonetizationCatalog.Get(productId)
	if not definition
		or definition.Enabled == false
		or productId == "ReviveNoCoinLoss"
	then
		return false, "Oferta invalida."
	end
	if not isSkyMerchantOpen(player) then
		return false, "Fale com o Mercador do Ceu para comprar."
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
			descendant.Transparency = math.max(descendant.Transparency, 0.65)
		end
	end
	capeOriginalTransparency[player] = original
	player:SetAttribute("InvisibleToEnemies", true)
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

local function activateWing(player)
	local definition = bestWing(player)
	if not definition then
		return false, "Voce nao possui asas."
	end
	local timestamp = workspace:GetServerTimeNow()
	if timestamp < (tonumber(player:GetAttribute("WingReadyAt")) or 0) then
		return false, "As asas ainda estao recarregando."
	end
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
	if definition.Id == "TemporaryWings" then
		local uses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0
		if uses <= 0 then
			return false, "Seus voos temporarios acabaram."
		end
		player:SetAttribute("TemporaryWingUses", uses - 1)
	end
	addWingVisual(character, definition)
	flightStates[player] = {
		EndsAt = timestamp + definition.Wing.FlightSeconds,
		Speed = definition.Wing.HorizontalSpeed,
		Root = root,
		Humanoid = humanoid,
		Definition = definition,
	}
	player:SetAttribute("WingActive", true)
	player:SetAttribute("WingActiveUntil", flightStates[player].EndsAt)
	player:SetAttribute("WingReadyAt", timestamp + definition.Wing.CooldownSeconds)
	publishEntitlements(player)
	return true, "Voo ativado."
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
		elseif action == "OpenStore" then
			if not isSkyMerchantOpen(player) then
				return nil
			end
			MarketingOfferService.RecordStoreOpened(player)
			return MonetizationService.GetStore(player)
		elseif action == "GetEntitlements" then
			local wing = bestWing(player)
			return {
				WingProductId = wing and wing.Id or nil,
				TemporaryWingUses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0,
				OwnsCape = ownsPass(player, MonetizationCatalog.Get("InvisibilityCape")),
				OwnsPermanentPotion = ownsPass(player, MonetizationCatalog.Get("PermanentPotion")),
			}
		elseif action == "Prompt" and type(productId) == "string" then
			local success, message = promptPurchase(player, productId)
			return { Success = success, Message = message, Store = MonetizationService.GetStore(player) }
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
			if
				player.Parent ~= Players
				or timestamp >= state.EndsAt
				or not state.Root.Parent
				or not state.Humanoid.Parent
				or state.Humanoid.Health <= 0
				or player:GetAttribute("IsDowned") == true
				or player:GetAttribute("WaterContacting") == true
			then
				flightStates[player] = nil
				if player.Parent == Players then
					player:SetAttribute("WingActive", false)
					player:SetAttribute("WingActiveUntil", nil)
					publishEntitlements(player)
				end
			else
				local direction = state.Humanoid.MoveDirection
				local horizontal = Vector3.new(direction.X, 0, direction.Z)
				if horizontal.Magnitude < 0.05 then
					local look = state.Root.CFrame.LookVector
					horizontal = Vector3.new(look.X, 0, look.Z)
				end
				horizontal = horizontal.Magnitude > 0.05 and horizontal.Unit or Vector3.zero
				state.Root.AssemblyLinearVelocity = horizontal * state.Speed
					+ Vector3.new(0, math.max(0, math.min(3, state.Root.AssemblyLinearVelocity.Y)), 0)
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
