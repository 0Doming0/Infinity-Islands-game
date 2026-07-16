--[[
	VillagerSystem.server.lua

	Sistema de aldeoes para comercio.
	3 niveis de raridade: Verde (comum), Azul (raro), Vermelho (epico).
	Aldeoes aparecem em plataformas geradas proceduralmente.
	Jogadores usam Score (pontos de sobrevivencia) como moeda.

	Funcionamento:
	- ProceduralGenerator cria markers com tag "ProceduralVillagerSpawn"
	- Este script detecta os markers e spawna aldeoes
	- Aldeoes tem BillboardGui mostrando raridade e "Loja"
	- Jogadores se aproximam e pressionam E para abrir a loja
	- UI mostra itens a venda com precos
	- Compras sao validadas no servidor
	- Cada aldeao tem um estoque limitado e itens randomizados por raridade
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VILLAGER_TAG = "ProceduralVillagerSpawn"
local INTERACT_DISTANCE = 6
local INTERACT_KEY = Enum.KeyCode.E
local rng = Random.new()

local villagerEvent = ReplicatedStorage:FindFirstChild("VillagerEvent")
if not villagerEvent then
	villagerEvent = Instance.new("RemoteEvent")
	villagerEvent.Name = "VillagerEvent"
	villagerEvent.Parent = ReplicatedStorage
end

-- ============================================================
-- CONFIG DE RARIDADE
-- ============================================================
local RARITY_LEVELS = {
	{
		Name = "Verde",
		Color = Color3.fromRGB(60, 200, 80),
		Weight = 60,
		ItemCount = { 2, 3 },
		Discount = 0,
		Items = {
			{ Name = "Speed", Label = "Speed +2", Price = 30, Effect = "Speed" },
			{ Name = "Jump", Label = "Jump +5", Price = 35, Effect = "Jump" },
			{ Name = "Vitality", Label = "Vitality +15 HP", Price = 40, Effect = "Vitality" },
			{ Name = "Shield", Label = "Shield 11s", Price = 45, Effect = "Shield" },
			{ Name = "Heal", Label = "Heal 50 HP", Price = 25, Effect = "Heal" },
		},
	},
	{
		Name = "Azul",
		Color = Color3.fromRGB(50, 120, 240),
		Weight = 30,
		ItemCount = { 3, 4 },
		Discount = 0.10,
		Items = {
			{ Name = "Speed2", Label = "Speed +4", Price = 60, Effect = "Speed", Amount = 4 },
			{ Name = "Jump2", Label = "Jump +10", Price = 65, Effect = "Jump", Amount = 10 },
			{ Name = "Vitality2", Label = "Vitality +30 HP", Price = 70, Effect = "Vitality", Amount = 30, Heal = 60 },
			{ Name = "Shield2", Label = "Shield 18s", Price = 75, Effect = "Shield", Duration = 18 },
			{ Name = "FullHeal", Label = "Heal Full", Price = 80, Effect = "FullHeal" },
			{ Name = "MaxHealth", Label = "MaxHP +25", Price = 85, Effect = "MaxHealth", Amount = 25 },
		},
	},
	{
		Name = "Vermelho",
		Color = Color3.fromRGB(230, 50, 50),
		Weight = 10,
		ItemCount = { 4, 5 },
		Discount = 0.20,
		Items = {
			{ Name = "Speed3", Label = "Speed +6", Price = 110, Effect = "Speed", Amount = 6 },
			{ Name = "Jump3", Label = "Jump +15", Price = 120, Effect = "Jump", Amount = 15 },
			{ Name = "Vitality3", Label = "Vitality +50 HP", Price = 130, Effect = "Vitality", Amount = 50, Heal = 80 },
			{ Name = "Shield3", Label = "Shield 25s", Price = 100, Effect = "Shield", Duration = 25 },
			{ Name = "FullHealMax", Label = "Full Heal+MaxHP", Price = 150, Effect = "FullHealMax", Amount = 40 },
			{ Name = "Overclock", Label = "Overclock 15s", Price = 140, Effect = "Overclock" },
			{ Name = "MegaShield", Label = "Mega Shield 20s", Price = 160, Effect = "MegaShield" },
		},
	},
}

-- ============================================================
-- HELPERS
-- ============================================================

local function chooseRarity()
	local totalWeight = 0
	for _, rarity in RARITY_LEVELS do
		totalWeight += rarity.Weight
	end
	local roll = rng:NextNumber(0, totalWeight)
	local cumulative = 0
	for _, rarity in RARITY_LEVELS do
		cumulative += rarity.Weight
		if roll <= cumulative then
			return rarity
		end
	end
	return RARITY_LEVELS[1]
end

local function generateShopInventory(rarity)
	local count = rng:NextInteger(rarity.ItemCount[1], rarity.ItemCount[2])
	local pool = table.clone(rarity.Items)
	local inventory = {}

	for _ = 1, math.min(count, #pool) do
		local index = rng:NextInteger(1, #pool)
		local item = table.remove(pool, index)
		local price = math.floor(item.Price * (1 - rarity.Discount))
		table.insert(inventory, {
			name = item.Name,
			label = item.Label,
			price = price,
			stock = rng:NextInteger(1, 3),
			effect = item.Effect,
			amount = item.Amount,
			heal = item.Heal,
			duration = item.Duration,
		})
	end

	return inventory
end

local function getScore(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return 0 end
	local score = leaderstats:FindFirstChild("Score")
	return score and score.Value or 0
end

local function spendScore(player, amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	local score = leaderstats:FindFirstChild("Score")
	if not score or score.Value < amount then return false end
	score.Value = score.Value - amount
	return true
end

-- ============================================================
-- APLICAR EFEITOS DE ITENS COMPRADOS
-- ============================================================

local CONFIG = {
	MAX_WALK_SPEED = 28,
	MAX_JUMP_POWER = 80,
	MAX_JUMP_HEIGHT = 12,
	MAX_HEALTH_LIMIT = 250,
}

local function applyPurchasedItem(player, humanoid, character, item)
	local effect = item.effect

	if effect == "Speed" then
		local amount = item.amount or 2
		humanoid.WalkSpeed = math.min(humanoid.WalkSpeed + amount, CONFIG.MAX_WALK_SPEED)

	elseif effect == "Jump" then
		local amount = item.amount or 5
		if humanoid.UseJumpPower then
			humanoid.JumpPower = math.min(humanoid.JumpPower + amount, CONFIG.MAX_JUMP_POWER)
		else
			humanoid.JumpHeight = math.min(humanoid.JumpHeight + (amount / 4), CONFIG.MAX_JUMP_HEIGHT)
		end

	elseif effect == "Vitality" then
		local amount = item.amount or 15
		humanoid.MaxHealth = math.min(humanoid.MaxHealth + amount, CONFIG.MAX_HEALTH_LIMIT)
		local heal = item.heal or 35
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)

	elseif effect == "Shield" then
		local duration = item.duration or 11
		local ff = Instance.new("ForceField")
		ff.Name = "ShopShield"
		ff.Visible = true
		ff.Parent = character
		task.delay(duration, function()
			if ff.Parent then ff:Destroy() end
		end)

	elseif effect == "Heal" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 50)

	elseif effect == "FullHeal" then
		humanoid.Health = humanoid.MaxHealth

	elseif effect == "MaxHealth" then
		local amount = item.amount or 25
		humanoid.MaxHealth = math.min(humanoid.MaxHealth + amount, CONFIG.MAX_HEALTH_LIMIT)

	elseif effect == "FullHealMax" then
		local amount = item.amount or 40
		humanoid.MaxHealth = math.min(humanoid.MaxHealth + amount, CONFIG.MAX_HEALTH_LIMIT)
		humanoid.Health = humanoid.MaxHealth

	elseif effect == "Overclock" then
		-- Speed + Jump boost temporario
		local originalSpeed = humanoid.WalkSpeed
		local originalJump = humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight
		humanoid.WalkSpeed = originalSpeed + 8
		if humanoid.UseJumpPower then
			humanoid.JumpPower = originalJump + 15
		else
			humanoid.JumpHeight = originalJump + 3
		end
		task.delay(15, function()
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid.WalkSpeed = math.min(originalSpeed, humanoid.WalkSpeed - 8)
				if humanoid.UseJumpPower then
					humanoid.JumpPower = math.min(originalJump, humanoid.JumpPower - 15)
				else
					humanoid.JumpHeight = math.min(originalJump, humanoid.JumpHeight - 3)
				end
			end
		end)

	elseif effect == "MegaShield" then
		-- Shield + partial heal
		local ff = Instance.new("ForceField")
		ff.Name = "MegaShopShield"
		ff.Visible = true
		ff.Parent = character
		task.delay(20, function()
			if ff.Parent then ff:Destroy() end
		end)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 40)
	end
end

-- ============================================================
-- CRIAR ALDEAO VISUAL
-- ============================================================

local function createVillagerModel(rarity, position)
	local model = Instance.new("Model")
	model.Name = "Villager_" .. rarity.Name

	-- Corpo principal
	local torsoHeight = 1.0
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(1.4, torsoHeight, 0.8)
	torso.CFrame = CFrame.new(position + Vector3.new(0, torsoHeight * 0.5 + 1.2, 0))
	torso.Anchored = true
	torso.CanCollide = false
	torso.Material = Enum.Material.SmoothPlastic
	torso.Color = rarity.Color:Lerp(Color3.fromRGB(60, 60, 60), 0.3)
	torso.Parent = model

	-- Cabeca
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.9, 0.9, 0.9)
	head.Shape = Enum.PartType.Ball
	head.CFrame = CFrame.new(torso.Position + Vector3.new(0, torsoHeight * 0.5 + 0.55, 0))
	head.Anchored = true
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = rarity.Color
	head.Parent = model

	-- Chapeu/cone indicando raridade
	local hat = Instance.new("Part")
	hat.Name = "Hat"
	hat.Shape = Enum.PartType.Cylinder
	hat.Size = Vector3.new(0.25, 1.4, 1.4)
	hat.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.65, 0)) * CFrame.Angles(0, 0, math.rad(90))
	hat.Anchored = true
	hat.CanCollide = false
	hat.Material = Enum.Material.Neon
	hat.Color = rarity.Color
	hat.Parent = model

	-- Base/pedestal
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.3, 2.8, 2.8)
	base.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = true
	base.Material = Enum.Material.SmoothPlastic
	base.Color = rarity.Color:Lerp(Color3.fromRGB(30, 30, 30), 0.5)
	base.Parent = model

	-- Bracos
	for _, side in { -1, 1 } do
		local arm = Instance.new("Part")
		arm.Name = "Arm" .. (side > 0 and "R" or "L")
		arm.Size = Vector3.new(0.35, 0.8, 0.35)
		arm.CFrame = CFrame.new(torso.Position + Vector3.new(side * 0.85, 0, 0))
		arm.Anchored = true
		arm.CanCollide = false
		arm.Material = Enum.Material.SmoothPlastic
		arm.Color = rarity.Color:Lerp(Color3.fromRGB(80, 80, 80), 0.2)
		arm.Parent = model
	end

	-- BillboardGui mostrando raridade e "Loja"
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VillagerLabel"
	billboard.Size = UDim2.fromOffset(140, 50)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Parent = model

	local labelBg = Instance.new("Frame")
	labelBg.Size = UDim2.fromScale(1, 1)
	labelBg.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
	labelBg.BackgroundTransparency = 0.15
	labelBg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = labelBg

	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Thickness = 2
	stroke.Parent = labelBg

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = rarity.Color
	nameLabel.Text = "Aldeao " .. rarity.Name
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = labelBg

	local shopLabel = Instance.new("TextLabel")
	shopLabel.Size = UDim2.new(1, 0, 0.45, 0)
	shopLabel.Position = UDim2.new(0, 0, 0.55, 0)
	shopLabel.BackgroundTransparency = 1
	shopLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	shopLabel.Text = "Loja [E]"
	shopLabel.TextScaled = true
	shopLabel.Font = Enum.Font.Gotham
	shopLabel.Parent = labelBg

	return model, base
end

-- ============================================================
-- GERENCIAR ALDEOES
-- ============================================================

local activeVillagers = {} -- [model] = { rarity, inventory, position, basePart }
local spawnedByMarker = setmetatable({}, { __mode = "k" })

local function spawnVillager(marker)
	if spawnedByMarker[marker] then return end
	if not marker:IsA("Attachment") or not marker:IsDescendantOf(game) then return end

	local rarity = chooseRarity()
	local position = marker.WorldPosition
	local platformModel = marker:FindFirstAncestorOfClass("Model")
	local parent = platformModel or marker.Parent

	local model, basePart = createVillagerModel(rarity, position)
	model.Parent = parent

	local inventory = generateShopInventory(rarity)

	local villagerData = {
		model = model,
		rarity = rarity,
		inventory = inventory,
		position = position,
		basePart = basePart,
		marker = marker,
	}
	activeVillagers[model] = villagerData
	spawnedByMarker[marker] = model

	model:SetAttribute("IsVillager", true)
	model:SetAttribute("Rarity", rarity.Name)

	-- Animacao de flutuacao na cabeca
	local head = model:FindFirstChild("Head")
	if head then
		local tween = TweenService:Create(
			head,
			TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = head.Position + Vector3.new(0, 0.15, 0) }
		)
		tween:Play()
	end

	-- Limpeza quando o marker e destruido
	marker.Destroying:Connect(function()
		if model.Parent then
			model:Destroy()
		end
		activeVillagers[model] = nil
		spawnedByMarker[marker] = nil
	end)
end

-- Detectar markers existentes e novos
for _, marker in CollectionService:GetTagged(VILLAGER_TAG) do
	task.defer(spawnVillager, marker)
end

CollectionService:GetInstanceAddedSignal(VILLAGER_TAG):Connect(function(marker)
	task.defer(spawnVillager, marker)
end)

-- ============================================================
-- SISTEMA DE INTERACAO (PROXIMIDADE + TECLA E)
-- ============================================================

local playerNearVillager = {} -- [player] = villagerData

-- Polling de proximidade para notificar cliente
task.spawn(function()
	while true do
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then continue end

			local hrp = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not hrp or not humanoid or humanoid.Health <= 0 then
				if playerNearVillager[player] then
					playerNearVillager[player] = nil
					villagerEvent:FireClient(player, { action = "hidePrompt" })
				end
				continue
			end

			local nearestVillager = nil
			local nearestDist = math.huge

			for model, data in activeVillagers do
				if not model.Parent then continue end
				local dist = (data.position - hrp.Position).Magnitude
				if dist < INTERACT_DISTANCE and dist < nearestDist then
					nearestVillager = data
					nearestDist = dist
				end
			end

			if nearestVillager then
				if playerNearVillager[player] ~= nearestVillager then
					playerNearVillager[player] = nearestVillager
					villagerEvent:FireClient(player, {
						action = "showPrompt",
						rarity = nearestVillager.rarity.Name,
						rarityColor = nearestVillager.rarity.Color,
					})
				end
			else
				if playerNearVillager[player] then
					playerNearVillager[player] = nil
					villagerEvent:FireClient(player, { action = "hidePrompt" })
				end
			end
		end
		task.wait(0.2)
	end
end)

-- ============================================================
-- HANDLER DE COMPRAS (CLIENT -> SERVER)
-- ============================================================

-- Rastrear qual aldeao cada jogador esta olhando
-- O cliente envia "openShop" quando pressiona E perto de um aldeao
-- O servidor responde com o inventario
-- O cliente envia "buy" com o index do item

local playerShops = {} -- [player] = villagerData

villagerEvent.OnServerEvent:Connect(function(player, data)
	if not data or not data.action then return end

	if data.action == "openShop" then
		local villager = playerNearVillager[player]
		if not villager then return end

		playerShops[player] = villager

		-- Enviar inventario + score para o cliente
		villagerEvent:FireClient(player, {
			action = "showShop",
			rarity = villager.rarity.Name,
			rarityColor = villager.rarity.Color,
			inventory = villager.inventory,
			score = getScore(player),
		})

	elseif data.action == "closeShop" then
		playerShops[player] = nil

	elseif data.action == "buy" then
		local villager = playerShops[player]
		if not villager then return end

		local itemIndex = data.itemIndex
		if not itemIndex or itemIndex < 1 or itemIndex > #villager.inventory then return end

		local item = villager.inventory[itemIndex]
		if not item or item.stock <= 0 then return end

		-- Validar score
		local score = getScore(player)
		if score < item.price then
			villagerEvent:FireClient(player, {
				action = "purchaseFailed",
				reason = "Pontos insuficientes!",
			})
			return
		end

		-- Cobrar e aplicar efeito
		if not spendScore(player, item.price) then return end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		applyPurchasedItem(player, humanoid, character, item)

		item.stock -= 1

		villagerEvent:FireClient(player, {
			action = "purchaseSuccess",
			itemIndex = itemIndex,
			newStock = item.stock,
			newScore = getScore(player),
			itemLabel = item.label,
		})

		-- Se todos os itens esgotaram, fechar a loja
		local allEmpty = true
		for _, invItem in villager.inventory do
			if invItem.stock > 0 then
				allEmpty = false
				break
			end
		end

		if allEmpty then
			villagerEvent:FireClient(player, { action = "shopEmpty" })
			playerShops[player] = nil
		end
	end
end)

-- Limpeza quando jogador sai
Players.PlayerRemoving:Connect(function(player)
	playerNearVillager[player] = nil
	playerShops[player] = nil
end)