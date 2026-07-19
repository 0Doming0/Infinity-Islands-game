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
local SwordProgressionService = require(script.Parent.MVPSystems:WaitForChild("SwordProgressionService"))
local InventoryService = require(script.Parent.MVPSystems:WaitForChild("InventoryService"))
local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))

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

local function buildInventory(player, shop)
	local swordsById = {}
	for _, sword in ipairs(SwordProgressionService.GetShopInventory(player)) do
		swordsById[sword.SwordId] = sword
	end

	local inventory = {}
	for _, offer in ipairs(shop.Items) do
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
					StatsText = string.format("Dano %d  -  Velocidade %.2fx", sword.BaseDamage, sword.AttackSpeed),
					Color = sword.Color,
					Owned = sword.Owned,
					Equipped = sword.Equipped,
				})
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
			})
		end
	end
	return inventory
end

local function sendShop(player, message, success)
	local villager = playerSessions[player]
	local shop = getShop(villager)
	if not shop then
		return
	end
	villagerEvent:FireClient(player, {
		action = "showShop",
		shopId = shop.ShopId,
		shopTitle = shop.DisplayName,
		shopColor = shop.Color,
		inventory = buildInventory(player, shop),
		coins = ScoreService.GetCoins(player),
		message = message,
		success = success,
	})
end

local function isSessionValid(player)
	local villager = playerSessions[player]
	if not villager or not villager.Parent or not activeVillagers[villager] or not getShop(villager) then
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
		return false, "Moedas insuficientes."
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
		return false, "Moedas insuficientes."
	end
	local granted, message = InventoryService.GrantItem(player, itemId, 1)
	if not granted then
		-- Reembolsa se o limite do inventario impediu a compra.
		ScoreService.RefundCoins(player, definition.Price, "VillageRefund")
		return false, message
	end
	return true, definition.DisplayName .. " comprado! Saldo: " .. tostring(remaining)
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
	activeVillagers[model] = true
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
	prompt.ActionText = "Negociar"
	prompt.ObjectText = shop.DisplayName

	prompt.Triggered:Connect(function(player)
		if player.Parent == Players then
			playerSessions[player] = model
			player:SetAttribute("ShopOpen", true)
			sendShop(player)
		end
	end)
	model.Destroying:Connect(function()
		activeVillagers[model] = nil
		for player, villager in pairs(playerSessions) do
			if villager == model then
				playerSessions[player] = nil
				player:SetAttribute("ShopOpen", false)
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
		playerSessions[player] = nil
		player:SetAttribute("ShopOpen", false)
		return
	end
	if not isSessionValid(player) then
		playerSessions[player] = nil
		player:SetAttribute("ShopOpen", false)
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
		local success, message = SwordProgressionService.Purchase(player, itemId)
		sendShop(player, message, success)
	elseif data.action == "equipSword" then
		if not VillageShopCatalog.FindItem(shop.ShopId, itemId, "Sword") then
			sendShop(player, "Fale com o comerciante correto para equipar esta espada.", false)
			return
		end
		local success, message = SwordProgressionService.Equip(player, itemId)
		sendShop(player, message, success)
	elseif data.action == "purchaseService" then
		local success, message = purchaseService(player, itemId)
		sendShop(player, message, success)
	elseif data.action == "purchaseItem" then
		local success, message = purchaseItem(player, itemId)
		sendShop(player, message, success)
	elseif data.action == "refreshShop" then
		sendShop(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerSessions[player] = nil
end)

print("[VillageShop] Comerciantes variados iniciados com validacao no servidor.")
