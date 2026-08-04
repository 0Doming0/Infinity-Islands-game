--[[
	SkyDungeon - Comerciantes da vila

	Cada aldeao possui uma profissao e um catalogo proprio. ProximityPrompt
	funciona em teclado, controle e celular; preco, distancia, catalogo e efeito
	sao sempre validados no servidor.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local VillageShopCatalog = require(ReplicatedStorage:WaitForChild("VillageShopCatalog"))
local ItemCatalog = require(ReplicatedStorage:WaitForChild("ItemCatalog"))
local SwordCatalog = require(ReplicatedStorage:WaitForChild("SwordCatalog"))
local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))
local SwordProgressionService = require(script.Parent.MVPSystems:WaitForChild("SwordProgressionService"))
local InventoryService = require(script.Parent.MVPSystems:WaitForChild("InventoryService"))
local RelicService = require(script.Parent.MVPSystems:WaitForChild("RelicService"))
local RewardService = require(script.Parent.MVPSystems:WaitForChild("RewardService"))
local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))
local CURRENCY_SYMBOL = MVPConfig.Currency.Symbol

local SHOP_TAG = MVPConfig.Village.ShopTag
local MAX_SESSION_DISTANCE = MVPConfig.Village.PromptDistance + 4
local activeVillagers = setmetatable({}, { __mode = "k" })
local playerSessions = {}

local villagerEvent = ReplicatedStorage:FindFirstChild("VillagerEvent")
if not villagerEvent then
	villagerEvent = Instance.new("RemoteEvent")
	villagerEvent.Name = "VillagerEvent"
	villagerEvent.Parent = ReplicatedStorage
end

SwordProgressionService.Start()
InventoryService.Start()
RelicService.Start()
RewardService.Start()

local function getRoot(model)
	local root = model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function getShop(model)
	return model and VillageShopCatalog.GetShop(model:GetAttribute("ShopId")) or nil
end

local function getSkyIsland(instance)
	local current = instance and instance.Parent
	while current do
		if current:IsA("Model") and current:GetAttribute("IsSkyIsland") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getIslandSurfaceY(villager)
	local island = getSkyIsland(villager)
	local floor = island and island:FindFirstChild("IslandFloor")
	if floor and floor:IsA("BasePart") then
		return floor.Position.Y + floor.Size.Y / 2
	end
	return nil
end

local function waterReachedMerchantIsland(villager)
	local islandSurfaceY = getIslandSurfaceY(villager)
	local water = workspace:FindFirstChild("Water")
	local waterSurfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	if not islandSurfaceY or not waterSurfaceY then
		return false
	end
	return waterSurfaceY >= islandSurfaceY
end

local function clearShopSession(player)
	playerSessions[player] = nil
	player:SetAttribute("ShopOpen", false)
	player:SetAttribute("ActiveShopId", nil)
	player:SetAttribute("SkyMerchantOfferValid", nil)
	player:SetAttribute("SkyMerchantRobuxOfferId", nil)
end

local function offerKey(itemType, itemId)
	return tostring(itemType or "") .. ":" .. tostring(itemId or "")
end

local function hashString(value)
	local hash = 0
	for index = 1, #value do
		hash = (hash * 31 + string.byte(value, index)) % 2147483647
	end
	return hash
end

local function getOfferSelectionWeight(offer)
	local price = tonumber(offer.Price)
	if offer.ItemType == "Sword" then
		local sword = SwordCatalog.Get(offer.ItemId)
		price = sword and sword.Price or price
	elseif offer.ItemType == "Item" then
		local item = ItemCatalog.Get(offer.ItemId)
		price = item and item.Price or price
	elseif offer.ItemType == "Relic" then
		local relic = RelicCatalog.Get(offer.ItemId)
		price = relic and relic.Price or price
	end
	-- Preco funciona como aproximacao de poder: ofertas caras continuam
	-- possiveis, mas aparecem com menos frequencia que as basicas.
	return 1 / math.sqrt(1 + math.max(0, price or 0) / 150)
end

local function takeWeightedOffer(pool, random)
	local totalWeight = 0
	for _, offer in ipairs(pool) do
		totalWeight += getOfferSelectionWeight(offer)
	end
	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0
	for index, offer in ipairs(pool) do
		accumulated += getOfferSelectionWeight(offer)
		if roll <= accumulated then
			return table.remove(pool, index)
		end
	end
	return table.remove(pool)
end

local function createStockState(model, shop)
	if shop.SpecialPanel == "Rewards" then
		return { Stock = {}, SpecialPanel = "Rewards" }
	end
	local island = model:FindFirstAncestorWhichIsA("Model")
	while island and island:GetAttribute("IsSkyIsland") ~= true do
		island = island:FindFirstAncestorWhichIsA("Model")
	end
	local seed = (island and tonumber(island:GetAttribute("IslandSeed")) or 1)
		+ MVPConfig.Village.InventoryRandomSalt
		+ hashString(model.Name .. ":" .. shop.ShopId)
	seed = math.floor(math.abs(seed)) % 2147483647
	local random = Random.new(seed == 0 and 1 or seed)
	local offers = table.clone(shop.Items)

	local offerCount = 0
	if #offers > 0 and random:NextNumber() > MVPConfig.Village.EmptyStockChance then
		local minimum = math.clamp(MVPConfig.Village.MinimumOfferTypes, 1, #offers)
		local maximum = math.clamp(MVPConfig.Village.MaximumOfferTypes, minimum, #offers)
		offerCount = random:NextInteger(minimum, maximum)
	end

	local stock = {}
	for _ = 1, offerCount do
		local offer = takeWeightedOffer(offers, random)
		stock[offerKey(offer.ItemType, offer.ItemId)] = {
			ItemType = offer.ItemType,
			ItemId = offer.ItemId,
			Stock = random:NextInteger(
				MVPConfig.Village.MinimumStockPerOffer,
				MVPConfig.Village.MaximumStockPerOffer
			),
		}
	end
	return { Stock = stock }
end

local function getStockEntry(state, itemType, itemId)
	return state and state.Stock[offerKey(itemType, itemId)] or nil
end

local function isOutOfStock(state)
	if not state then
		return true
	end
	if state.SpecialPanel then
		return false
	end
	for _, entry in pairs(state.Stock) do
		if entry.Stock > 0 then
			return false
		end
	end
	return true
end

local function ensureBillboard(model, root, shop)
	if model:FindFirstChild("VillageShopLabel", true) then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VillageShopLabel"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(132, 30)
	billboard.StudsOffset = Vector3.new(0, 3.35, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 22
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 20, 34)
	label.BackgroundTransparency = 0.38
	label.Text = shop.Label
	label.TextColor3 = shop.Color
	label.TextSize = 13
	label.Font = Enum.Font.GothamMedium
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = shop.Color
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = label
end

local function updateAvailability(model, root, shop, state)
	local empty = isOutOfStock(state)
	model:SetAttribute("ShopOutOfStock", empty)
	local billboard = model:FindFirstChild("VillageShopLabel", true)
	local label = billboard and billboard:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = empty and "SEM ESTOQUE" or shop.Label
		label.TextColor3 = empty and Color3.fromRGB(210, 184, 130) or shop.Color
		local labelStroke = label:FindFirstChildWhichIsA("UIStroke")
		if labelStroke then
			labelStroke.Color = label.TextColor3
		end
	end
	local prompt = root:FindFirstChild("VillageShopPrompt") or root:FindFirstChild("SwordShopPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ActionText = shop.SpecialPanel == "Rewards" and "Coletar"
			or empty and "Conversar"
			or "Negociar"
		prompt.ObjectText = empty and (shop.DisplayName .. " — SEM ESTOQUE") or shop.DisplayName
	end
end

local function validateStock(villager, itemType, itemId)
	local state = activeVillagers[villager]
	local entry = getStockEntry(state, itemType, itemId)
	if not entry or entry.Stock <= 0 then
		return nil, "Este aldeao esta sem estoque desse item. Explore outra ilha."
	end
	return entry
end

local function consumeStock(villager, itemType, itemId)
	local state = activeVillagers[villager]
	local entry = getStockEntry(state, itemType, itemId)
	if not entry or entry.Stock <= 0 then
		return false
	end
	entry.Stock -= 1
	local shop = getShop(villager)
	local root = getRoot(villager)
	if shop and root then
		updateAvailability(villager, root, shop, state)
	end
	return true
end

local function buildInventory(player, shop, state)
	local inventory = {}
	if shop.SpecialPanel == "Rewards" or shop.IncludesRewards == true then
		local snapshot = RewardService.GetSnapshot(player)
		local rewards = {
			{
				ItemId = "DailyReward",
				ItemType = "DailyReward",
				DisplayName = string.format("Recompensa diária — dia %d", snapshot.Daily.Streak),
				Description = "Entre em dias consecutivos para melhorar o prêmio.",
				StatsText = string.format("+%d moedas  •  +%d pontos", snapshot.Daily.Coins, snapshot.Daily.Score),
				Color = shop.Color,
				Claimable = snapshot.Daily.Claimable,
				Claimed = not snapshot.Daily.Claimable,
			},
		}
		for _, reward in ipairs(snapshot.Playtime) do
			table.insert(rewards, {
				ItemId = "Playtime_" .. reward.Minutes,
				ItemType = "TimeReward",
				DisplayName = string.format("Tempo jogado — %d minutos", reward.Minutes),
				Description = reward.Claimed and "Coletada nesta sessão."
					or reward.Claimable and "Pronta para coletar."
					or string.format("Faltam %d min.", math.ceil(reward.RemainingSeconds / 60)),
				StatsText = string.format("+%d moedas  •  +%d pontos", reward.Coins, reward.Score),
				Color = Color3.fromRGB(86, 205, 255),
				Minutes = reward.Minutes,
				Claimable = reward.Claimable,
				Claimed = reward.Claimed,
			})
		end
		for _, reward in ipairs(rewards) do
			table.insert(inventory, reward)
		end
	end

	local swordsById = {}
	for _, sword in ipairs(SwordProgressionService.GetShopInventory(player)) do
		swordsById[sword.SwordId] = sword
	end
	local relicsById = {}
	for _, relic in ipairs(RelicService.GetShopInventory(player)) do
		relicsById[relic.RelicId] = relic
	end

	for _, offer in ipairs(shop.Items) do
		local stockEntry = getStockEntry(state, offer.ItemType, offer.ItemId)
		if not stockEntry then
			continue
		end
		if offer.ItemType == "Sword" then
			local sword = swordsById[offer.ItemId]
			if sword then
				table.insert(inventory, {
					ItemId = sword.SwordId,
					ItemType = "Sword",
					SwordId = sword.SwordId,
					DisplayName = sword.DisplayName,
					Description = sword.Description,
					Price = sword.Price,
					BaseDamage = sword.BaseDamage,
					AttackSpeed = sword.AttackSpeed,
					ScoreMultiplier = sword.ScoreMultiplier,
					StatsText = string.format(
						"Dano %d  •  Vel. %.2fx  •  Alcance %.2fx  •  Crítico %d%%  •  Moedas %.2fx",
						sword.BaseDamage,
						sword.AttackSpeed,
						sword.RangeMultiplier,
						math.floor(sword.CriticalChance * 100 + 0.5),
						sword.CoinMultiplier
					),
					Color = sword.Color,
					Owned = sword.Owned,
					Equipped = sword.Equipped,
					Stock = stockEntry.Stock,
				})
			end
		elseif offer.ItemType == "Relic" then
			local relic = relicsById[offer.ItemId]
			if relic then
				relic.Stock = stockEntry.Stock
				table.insert(inventory, relic)
			end
		elseif offer.ItemType == "Item" then
			local item = ItemCatalog.Get(offer.ItemId)
			if item then
				table.insert(inventory, {
					ItemId = item.ItemId,
					ItemType = "Item",
					DisplayName = item.DisplayName,
					Description = item.Description,
					StatsText = string.format("Consumivel - maximo %d", item.MaximumStack),
					Price = item.Price,
					Color = item.Color,
					Stock = stockEntry.Stock,
				})
			end
		else
			table.insert(inventory, {
				ItemId = offer.ItemId,
				ItemType = offer.ItemType,
				DisplayName = offer.DisplayName,
				Description = offer.Description,
				StatsText = offer.StatsText,
				Price = offer.Price,
				Color = offer.Color,
				Stock = stockEntry.Stock,
			})
		end
	end
	return inventory
end

local function sendShop(player, message, success)
	local villager = playerSessions[player]
	local shop = getShop(villager)
	local state = activeVillagers[villager]
	if not shop or not state then
		return
	end
	if shop.ShopId == VillageShopCatalog.GetSkyMerchantShopId() then
		villagerEvent:FireClient(player, {
			action = "showSkyMerchant",
			shopId = shop.ShopId,
			shopTitle = shop.DisplayName,
			shopColor = shop.Color,
			message = message,
			success = success,
			expiresWhenWaterReachesIsland = true,
		})
		return
	end
	local inventory = buildInventory(player, shop, state)
	local emptyStock = isOutOfStock(state)
	local emptyMessage
	if emptyStock then
		emptyMessage = shop.IncludesPremiumStore == true
			and "ITENS ESGOTADOS — recompensas e ofertas especiais continuam disponiveis."
			or "SEM ESTOQUE — explore outras ilhas para encontrar novas ofertas."
	end
	villagerEvent:FireClient(player, {
		action = "showShop",
		shopId = shop.ShopId,
		shopTitle = shop.DisplayName,
		shopColor = shop.Color,
		inventory = inventory,
		coins = ScoreService.GetCoins(player),
		message = message or emptyMessage,
		success = success,
		emptyStock = emptyStock,
		specialPanel = shop.SpecialPanel,
		includesPremiumStore = shop.IncludesPremiumStore == true,
	})
end

local function isSessionValid(player)
	local villager = playerSessions[player]
	if not villager or not villager.Parent or not activeVillagers[villager] or not getShop(villager) then
		return false
	end
	local shop = getShop(villager)
	if shop.ShopId == VillageShopCatalog.GetSkyMerchantShopId()
		and (
			player:GetAttribute("SkyMerchantOfferValid") ~= true
			or waterReachedMerchantIsland(villager)
		)
	then
		return false
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local villagerRoot = getRoot(villager)
	return playerRoot ~= nil
		and villagerRoot ~= nil
		and (playerRoot.Position - villagerRoot.Position).Magnitude <= MAX_SESSION_DISTANCE
end

local function getLivingHumanoid(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, character
end

local function canApplyService(player, offer)
	local humanoid = getLivingHumanoid(player)
	if not humanoid then
		return false, "Seu personagem precisa estar vivo."
	end
	if offer.Effect == "Heal" and humanoid.Health >= humanoid.MaxHealth then
		return false, "Sua vida ja esta cheia."
	elseif offer.Effect == "Vitality" and humanoid.MaxHealth >= offer.Maximum then
		return false, "Voce atingiu o limite de vitalidade desta vida."
	elseif offer.Effect == "Speed" and humanoid.WalkSpeed >= offer.Maximum then
		return false, "Voce atingiu o limite de velocidade desta vida."
	elseif offer.Effect == "Jump" then
		local atLimit = humanoid.UseJumpPower and humanoid.JumpPower >= offer.Maximum
			or not humanoid.UseJumpPower and humanoid.JumpHeight >= offer.HeightMaximum
		if atLimit then
			return false, "Voce atingiu o limite de salto desta vida."
		end
	end
	return true
end

local function applyService(player, offer)
	local humanoid = getLivingHumanoid(player)
	if not humanoid then
		return false
	end
	if offer.Effect == "Heal" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + offer.Amount)
	elseif offer.Effect == "Vitality" then
		humanoid.MaxHealth = math.min(offer.Maximum, humanoid.MaxHealth + offer.Amount)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + offer.Amount)
	elseif offer.Effect == "Speed" then
		humanoid.WalkSpeed = math.min(offer.Maximum, humanoid.WalkSpeed + offer.Amount)
	elseif offer.Effect == "Jump" then
		if humanoid.UseJumpPower then
			humanoid.JumpPower = math.min(offer.Maximum, humanoid.JumpPower + offer.Amount)
		else
			humanoid.JumpHeight = math.min(offer.HeightMaximum, humanoid.JumpHeight + offer.HeightAmount)
		end
	else
		return false
	end
	player:SetAttribute("VillageServicesPurchased", (player:GetAttribute("VillageServicesPurchased") or 0) + 1)
	player:SetAttribute("LastVillageService", offer.ItemId)
	return true
end

local function purchaseService(player, itemId)
	local shop = getShop(playerSessions[player])
	local offer = shop and VillageShopCatalog.FindItem(shop.ShopId, itemId, "Service")
	if not offer then
		return false, "Este aldeao nao oferece esse servico."
	end
	local valid, validationMessage = canApplyService(player, offer)
	if not valid then
		return false, validationMessage
	end
	local paid = ScoreService.TrySpendCoins(player, offer.Price)
	if not paid then
		return false, CURRENCY_SYMBOL .. " Moedas insuficientes."
	end
	if not applyService(player, offer) then
		ScoreService.RefundCoins(player, offer.Price, "VillageServiceRefund")
		return false, "Nao foi possivel aplicar o servico."
	end
	return true, offer.DisplayName .. " adquirido!"
end

local function purchaseItem(player, itemId)
	local shop = getShop(playerSessions[player])
	local offer = shop and VillageShopCatalog.FindItem(shop.ShopId, itemId, "Item")
	local definition = offer and ItemCatalog.Get(itemId)
	if not definition then
		return false, "Este aldeao nao vende esse item."
	end
	local paid, remaining = ScoreService.TrySpendCoins(player, definition.Price)
	if not paid then
		return false, CURRENCY_SYMBOL .. " Moedas insuficientes."
	end
	local granted, message = InventoryService.GrantItem(player, itemId, 1)
	if not granted then
		-- Reembolsa se o limite do inventario impediu a compra.
		ScoreService.RefundCoins(player, definition.Price, "VillageRefund")
		return false, message
	end
	return true, definition.DisplayName .. " comprado! Saldo: " .. CURRENCY_SYMBOL .. " " .. tostring(remaining)
end

local function registerVillager(model)
	if not model:IsA("Model") or activeVillagers[model] then
		return
	end
	local root = getRoot(model)
	local shop = getShop(model)
	if not root or not shop then
		warn("[VillageShop] Aldeao invalido ou sem ShopId: " .. model:GetFullName())
		return
	end
	local state = createStockState(model, shop)
	activeVillagers[model] = state
	model:SetAttribute("NoSwordDamage", true)
	model:SetAttribute("Invulnerable", true)
	ensureBillboard(model, root, shop)

	local prompt = root:FindFirstChild("VillageShopPrompt") or root:FindFirstChild("SwordShopPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "VillageShopPrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = MVPConfig.Village.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
	end
	updateAvailability(model, root, shop, state)

	prompt.Triggered:Connect(function(player)
		if player.Parent == Players then
			local isSkyMerchant = shop.ShopId == VillageShopCatalog.GetSkyMerchantShopId()
			if isSkyMerchant and waterReachedMerchantIsland(model) then
				clearShopSession(player)
				villagerEvent:FireClient(player, {
					action = "merchantOfferExpired",
					message = "A água já chegou à ilha. O Mercador partiu e esta oferta terminou.",
				})
				return
			end
			playerSessions[player] = model
			player:SetAttribute("ShopOpen", true)
			player:SetAttribute("ActiveShopId", shop.ShopId)
			player:SetAttribute("SkyMerchantOfferValid", isSkyMerchant and true or nil)
			player:SetAttribute(
				"SkyMerchantRobuxOfferId",
				isSkyMerchant and model:GetAttribute("RobuxOfferProductId") or nil
			)
			GameplayAnalytics.RecordMerchantOpened(
				player,
				isSkyMerchant and "SkyMerchant" or "VillageMerchant"
			)
			sendShop(player)
		end
	end)
	model.Destroying:Connect(function()
		activeVillagers[model] = nil
		for player, villager in pairs(playerSessions) do
			if villager == model then
				clearShopSession(player)
				villagerEvent:FireClient(player, { action = "closeShop" })
			end
		end
	end)
end

for _, model in ipairs(CollectionService:GetTagged(SHOP_TAG)) do
	task.defer(registerVillager, model)
end
CollectionService:GetInstanceAddedSignal(SHOP_TAG):Connect(function(model)
	task.defer(registerVillager, model)
end)

villagerEvent.OnServerEvent:Connect(function(player, data)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end
	if data.action == "closeShop" then
		clearShopSession(player)
		return
	end
	if not isSessionValid(player) then
		clearShopSession(player)
		villagerEvent:FireClient(player, { action = "shopError", message = "Aproxime-se novamente do aldeao." })
		return
	end

	local itemId = type(data.itemId) == "string" and data.itemId
		or type(data.swordId) == "string" and data.swordId
		or ""
	local shop = getShop(playerSessions[player])
	if data.action == "purchaseSword" then
		if not VillageShopCatalog.FindItem(shop.ShopId, itemId, "Sword") then
			sendShop(player, "Este aldeao nao vende essa espada.", false)
			return
		end
		local stock, stockMessage = validateStock(playerSessions[player], "Sword", itemId)
		if not stock then
			sendShop(player, stockMessage, false)
			return
		end
		local success, message = SwordProgressionService.Purchase(player, itemId)
		if success then
			consumeStock(playerSessions[player], "Sword", itemId)
			GameplayAnalytics.RecordMerchantPurchase(player, "Sword", shop.ShopId)
		end
		sendShop(player, message, success)
	elseif data.action == "equipSword" then
		if not VillageShopCatalog.FindItem(shop.ShopId, itemId, "Sword")
			or not getStockEntry(activeVillagers[playerSessions[player]], "Sword", itemId)
		then
			sendShop(player, "Fale com o comerciante correto para equipar esta espada.", false)
			return
		end
		local success, message = SwordProgressionService.Equip(player, itemId)
		sendShop(player, message, success)
	elseif data.action == "purchaseRelic" then
		if not VillageShopCatalog.FindItem(shop.ShopId, itemId, "Relic") then
			sendShop(player, "Este aldeão não vende essa relíquia.", false)
			return
		end
		local stock, stockMessage = validateStock(playerSessions[player], "Relic", itemId)
		if not stock then
			sendShop(player, stockMessage, false)
			return
		end
		local success, message = RelicService.Purchase(player, itemId)
		if success then
			consumeStock(playerSessions[player], "Relic", itemId)
			GameplayAnalytics.RecordMerchantPurchase(player, "Relic", shop.ShopId)
		end
		sendShop(player, message, success)
	elseif data.action == "equipRelic" then
		if not VillageShopCatalog.FindItem(shop.ShopId, itemId, "Relic") then
			sendShop(player, "Fale com o mercador de relíquias.", false)
			return
		end
		local success, message = RelicService.Equip(player, itemId)
		sendShop(player, message, success)
	elseif data.action == "claimDailyReward"
		and (shop.SpecialPanel == "Rewards" or shop.IncludesRewards == true)
	then
		local success, message = RewardService.ClaimDaily(player)
		sendShop(player, message, success)
	elseif data.action == "claimTimeReward"
		and (shop.SpecialPanel == "Rewards" or shop.IncludesRewards == true)
	then
		local success, message = RewardService.ClaimPlaytime(player, data.minutes)
		sendShop(player, message, success)
	elseif data.action == "purchaseService" then
		local stock, stockMessage = validateStock(playerSessions[player], "Service", itemId)
		if not stock then
			sendShop(player, stockMessage, false)
			return
		end
		local success, message = purchaseService(player, itemId)
		if success then
			consumeStock(playerSessions[player], "Service", itemId)
			GameplayAnalytics.RecordMerchantPurchase(player, "Service", shop.ShopId)
		end
		sendShop(player, message, success)
	elseif data.action == "purchaseItem" then
		local stock, stockMessage = validateStock(playerSessions[player], "Item", itemId)
		if not stock then
			sendShop(player, stockMessage, false)
			return
		end
		local success, message = purchaseItem(player, itemId)
		if success then
			consumeStock(playerSessions[player], "Item", itemId)
			GameplayAnalytics.RecordMerchantPurchase(player, "Item", shop.ShopId)
		end
		sendShop(player, message, success)
	elseif data.action == "refreshShop" then
		sendShop(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		for player, villager in pairs(playerSessions) do
			local shop = getShop(villager)
			if shop
				and shop.ShopId == VillageShopCatalog.GetSkyMerchantShopId()
				and waterReachedMerchantIsland(villager)
			then
				clearShopSession(player)
				villagerEvent:FireClient(player, {
					action = "merchantOfferExpired",
					message = "A água chegou à ilha. O Mercador partiu e a oferta terminou.",
				})
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerSessions[player] = nil
end)

print("[VillageShop] Comerciantes variados e Mercador do Ceu iniciados com validacao no servidor.")
