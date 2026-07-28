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
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local RewardWheelService = require(script.Parent:WaitForChild("RewardWheelService"))
local DeveloperProductService = require(script.Parent:WaitForChild("DeveloperProductService"))
local MarketingOfferService = require(script.Parent:WaitForChild("MarketingOfferService"))

local MonetizationService = {}
local started = false
local event
local request
local random = Random.new()
local policies = setmetatable({}, { __mode = "k" })
local passOwnership = setmetatable({}, { __mode = "k" })
local flightStates = setmetatable({}, { __mode = "k" })
local capeOriginalTransparency = setmetatable({}, { __mode = "k" })

local WING_PRIORITY = table.freeze({
	"CelestialWings",
	"RoyalWings",
	"AzureWings",
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
	return definition and MonetizationCatalog.GetConfiguredAssetId(definition) > 0
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
	cache[definition.Id] = success and owns == true
	return cache[definition.Id]
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

local function clearWingVisual(character)
	local existing = character and character:FindFirstChild("MonetizationWings")
	if existing then
		existing:Destroy()
	end
end

local function addWingVisual(character, definition)
	clearWingVisual(character)
	local torso = character and (
		character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
	)
	if not torso or not torso:IsA("BasePart") or not definition or not definition.Wing then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "MonetizationWings"
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
end

local function publishEntitlements(player, message)
	local wing = bestWing(player)
	local cape = MonetizationCatalog.Get("InvisibilityCape")
	local potion = MonetizationCatalog.Get("PermanentPotion")
	player:SetAttribute("OwnedWingProductId", wing and wing.Id or nil)
	player:SetAttribute("OwnsInvisibilityCape", ownsPass(player, cape))
	player:SetAttribute("OwnsPermanentPotion", ownsPass(player, potion))
	if player.Character and wing then
		addWingVisual(player.Character, wing)
	end
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
	player:SetAttribute("InvisibleToEnemies", false)
	character:SetAttribute("InvisibleToEnemies", false)
	task.defer(applyPermanentPotion, player, character)
	task.delay(1, function()
		if character.Parent and player.Parent == Players then
			local wing = bestWing(player)
			if wing then
				addWingVisual(character, wing)
			end
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
	if definition.PaidRandomItem and not policyFor(player).PaidRandomItemsAllowed then
		entry.Available = false
		entry.UnavailableReason = "Indisponivel para esta conta ou regiao."
	elseif definition.ProductType == "RewardedAd" and definition.Enabled ~= true then
		entry.Available = false
		entry.UnavailableReason = "Sera ativado quando a experiencia cumprir a elegibilidade de anuncios."
	else
		entry.Available = entry.Configured
	end
	if definition.ProductType == "Coins" then
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
		if definition.Id ~= "ReviveNoCoinLoss" then
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
	task.spawn(PlayerDataService.Save, player, false)
	if event then
		event:FireClient(player, {
			Action = "PurchaseGranted",
			ProductId = productId,
			Message = definition.DisplayName .. " ativada!",
		})
	end
	return true
end

local function grantPaidSpin(player)
	if not policyFor(player).PaidRandomItemsAllowed then
		return false
	end
	local success = RewardWheelService.Spin(player, "PaidSpin", {
		Level = tonumber(player:GetAttribute("RunLevel")) or 1,
		Paid = true,
	})
	if success then
		MarketingOfferService.MarkPurchased(player, "PaidWheelSpin")
	end
	return success == true
end

local function registerDeveloperProducts()
	local treasure = MonetizationCatalog.Get("TreasureExpedition")
	local elite = MonetizationCatalog.Get("EliteExpedition")
	local spin = MonetizationCatalog.Get("PaidWheelSpin")
	DeveloperProductService.Register(treasure.ProductId, treasure.Id, function(player)
		return grantBoost(player, treasure.Id, "Treasure")
	end)
	DeveloperProductService.Register(elite.ProductId, elite.Id, function(player)
		return grantBoost(player, elite.Id, "Elite")
	end)
	DeveloperProductService.Register(spin.ProductId, spin.Id, grantPaidSpin)
end

local function isSkyMerchantOpen(player)
	return player:GetAttribute("ShopOpen") == true
		and player:GetAttribute("ActiveShopId") == "SkyMerchant"
		and player:GetAttribute("SkyMerchantOfferValid") == true
end

local function promptPurchase(player, productId)
	local definition = MonetizationCatalog.Get(productId)
	if not definition or productId == "ReviveNoCoinLoss" then
		return false, "Oferta invalida."
	end
	if not isSkyMerchantOpen(player) then
		return false, "Fale com o Mercador do Ceu para comprar."
	end
	if definition.PaidRandomItem and not policyFor(player).PaidRandomItemsAllowed then
		return false, "Esta roleta nao esta disponivel para sua conta ou regiao."
	end
	if definition.ProductType == "Coins" then
		MarketingOfferService.RecordProductPrompt(player, productId)
		return purchaseTemporaryWings(player)
	elseif not configured(definition) then
		return false, "Configure o ID deste produto no MonetizationCatalog."
	elseif definition.ProductType == "DeveloperProduct" then
		MarketingOfferService.RecordProductPrompt(player, productId)
		MarketplaceService:PromptProductPurchase(player, definition.ProductId)
		return true, "Compra aberta."
	elseif definition.ProductType == "GamePass" then
		if ownsPass(player, definition) then
			return false, "Voce ja possui este beneficio."
		end
		MarketingOfferService.RecordProductPrompt(player, productId)
		MarketplaceService:PromptGamePassPurchase(player, definition.PassId)
		return true, "Compra aberta."
	end
	return false, "Oferta indisponivel."
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
	if character then
		character:SetAttribute("InvisibleToEnemies", false)
	end
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
	if not character or not humanoid or humanoid.Health <= 0 or player:GetAttribute("IsDowned") == true then
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
	if not humanoid or humanoid.Health <= 0 or not root or player:GetAttribute("IsDowned") == true then
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
	}
	player:SetAttribute("WingActive", true)
	player:SetAttribute("WingReadyAt", timestamp + definition.Wing.CooldownSeconds)
	publishEntitlements(player)
	return true, "Voo ativado."
end

local function updateWorldBoosts()
	local treasureMultiplier = 1
	local eliteMultiplier = 1
	local unixNow = os.time()
	for _, player in ipairs(Players:GetPlayers()) do
		local treasureUntil = tonumber(player:GetAttribute("TreasureBoostUntil")) or 0
		local eliteUntil = tonumber(player:GetAttribute("EliteBoostUntil")) or 0
		local treasureActive = treasureUntil > unixNow
		local eliteActive = eliteUntil > unixNow
		player:SetAttribute("TreasureBoostActive", treasureActive)
		player:SetAttribute("EliteBoostActive", eliteActive)
		if treasureActive then
			treasureMultiplier = math.max(
				treasureMultiplier,
				MonetizationCatalog.Get("TreasureExpedition").ChanceMultiplier
			)
		end
		if eliteActive then
			eliteMultiplier = math.max(
				eliteMultiplier,
				MonetizationCatalog.Get("EliteExpedition").ChanceMultiplier
			)
		end
	end
	workspace:SetAttribute("TreasureMonetizationChanceMultiplier", treasureMultiplier)
	workspace:SetAttribute("EliteMonetizationChanceMultiplier", eliteMultiplier)
end

function MonetizationService.RecordSignal(player, signalName, amount)
	MarketingOfferService.Record(player, signalName, amount)
end

function MonetizationService.RecordEliteDefeat(player)
	MarketingOfferService.Record(player, "EliteDefeated", 1)
	if player:GetAttribute("EliteBoostActive") ~= true then
		return false
	end
	local chance = MonetizationCatalog.Get("EliteExpedition").BonusRewardChance
	if random:NextNumber() > chance then
		return false
	end
	return RewardWheelService.Spin(player, "RareChest", {
		Level = tonumber(player:GetAttribute("RunLevel")) or 1,
		EliteBonus = true,
	})
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
			return {
				WingProductId = (bestWing(player) and bestWing(player).Id) or nil,
				TemporaryWingUses = tonumber(player:GetAttribute("TemporaryWingUses")) or 0,
				OwnsCape = ownsPass(player, MonetizationCatalog.Get("InvisibilityCape")),
			}
		elseif action == "Prompt" and type(productId) == "string" then
			local success, message = promptPurchase(player, productId)
			return { Success = success, Message = message, Store = MonetizationService.GetStore(player) }
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

	local function setup(player)
		task.spawn(function()
			PlayerDataService.Load(player)
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
	end)

	local boostElapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local timestamp = workspace:GetServerTimeNow()
		for player, state in pairs(flightStates) do
			if
				player.Parent ~= Players
				or timestamp >= state.EndsAt
				or not state.Root.Parent
				or not state.Humanoid.Parent
				or state.Humanoid.Health <= 0
			then
				flightStates[player] = nil
				if player.Parent == Players then
					player:SetAttribute("WingActive", false)
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
			updateWorldBoosts()
		end
	end)
	updateWorldBoosts()
end

return MonetizationService
