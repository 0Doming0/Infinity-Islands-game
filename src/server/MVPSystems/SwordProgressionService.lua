--[[
	SkyDungeon - SwordProgressionService

	Unico responsavel por catalogo, templates, compra, posse, selecao e entrega
	de espadas. Modelos reais em ServerStorage/MVPAssets/Swords tem prioridade;
	modelos de exemplo sao criados apenas quando um SwordId esta ausente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("SwordCatalog"))
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CURRENCY_SYMBOL = MVPConfig.Currency.Symbol
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PlayerDataService = require(BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local ScoreService = require(BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))

local SwordProgressionService = {}
local started = false
local deliveryTokens = setmetatable({}, { __mode = "k" })
local initializedPlayers = setmetatable({}, { __mode = "k" })
local characterGenerations = setmetatable({}, { __mode = "k" })

local DELIVERY_CHECKPOINTS = table.freeze({ 0, 0.35, 1.5, 4 })
local DELIVERY_VERSION = "FirstSpawnReliableV2"

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function getSwordsFolder()
	local assets = ensureFolder(ServerStorage, "MVPAssets")
	return ensureFolder(assets, "Swords")
end

local function weldToHandle(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

local function createExampleTemplate(definition)
	local tool = Instance.new("Tool")
	tool.Name = definition.SwordId
	tool.ToolTip = definition.DisplayName .. " (modelo de exemplo)"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, -0.25, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 1.45, 0.45)
	handle.Color = definition.AccentColor
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

	local guard = Instance.new("Part")
	guard.Name = "Guard"
	guard.Size = Vector3.new(2.15, 0.25, 0.40)
	guard.CFrame = handle.CFrame * CFrame.new(0, 0.78, 0)
	guard.Color = definition.AccentColor
	guard.Material = Enum.Material.Metal
	guard.CanCollide = false
	guard.CanTouch = false
	guard.Massless = true
	guard.Parent = tool
	weldToHandle(handle, guard)

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.62, 4.15, 0.22)
	blade.CFrame = handle.CFrame * CFrame.new(0, 2.95, 0)
	blade.Color = definition.Color
	blade.Material = definition.Material
	blade.CanCollide = false
	blade.CanTouch = false
	blade.Massless = true
	blade.Parent = tool
	weldToHandle(handle, blade)

	local point = Instance.new("WedgePart")
	point.Name = "BladeTip"
	point.Size = Vector3.new(0.62, 0.72, 0.22)
	point.CFrame = blade.CFrame * CFrame.new(0, 2.42, 0) * CFrame.Angles(0, 0, math.rad(180))
	point.Color = definition.Color
	point.Material = definition.Material
	point.CanCollide = false
	point.CanTouch = false
	point.Massless = true
	point.Parent = tool
	weldToHandle(handle, point)

	tool:SetAttribute("ExampleModel", true)
	return tool
end

local function findTemplate(folder, swordId)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Tool") and (child.Name == swordId or child:GetAttribute("SwordId") == swordId) then
			return child
		end
	end
	return nil
end

local function resolveBaseDamage(template, definition)
	local modelDamage = template:GetAttribute("BaseDamage")
	if typeof(modelDamage) == "number" and modelDamage == modelDamage and modelDamage >= 0 then
		return modelDamage
	end
	return definition.BaseDamage
end

local function configureTemplate(template, definition)
	-- O valor configurado no modelo e a fonte principal. O catalogo serve como
	-- fallback para modelos sem BaseDamage e para os modelos de exemplo.
	local baseDamage = resolveBaseDamage(template, definition)
	template.Name = definition.SwordId
	template.CanBeDropped = false
	template:SetAttribute("Enabled", true)
	template:SetAttribute("IsSword", true)
	template:SetAttribute("WeaponType", "Sword")
	template:SetAttribute("SwordId", definition.SwordId)
	template:SetAttribute("DisplayName", definition.DisplayName)
	template:SetAttribute("BaseDamage", baseDamage)
	template:SetAttribute("AttackSpeed", definition.AttackSpeed)
	template:SetAttribute("ScoreMultiplier", definition.ScoreMultiplier)
	template:SetAttribute("CoinMultiplier", definition.CoinMultiplier)
	template:SetAttribute("KnockbackMultiplier", definition.KnockbackMultiplier)
	template:SetAttribute("RangeMultiplier", definition.RangeMultiplier)
	template:SetAttribute("CriticalChance", definition.CriticalChance)
	template:SetAttribute("Price", definition.Price)

	local animations = ensureFolder(template, "Animations")
	for slot, animationId in pairs(MVPConfig.ExampleAssets.Animations) do
		local animation = animations:FindFirstChild(slot)
		if not animation then
			animation = Instance.new("Animation")
			animation.Name = slot
			animation.AnimationId = animationId
			animation.Parent = animations
		end
	end
	return template
end

local function ensureTemplates()
	local folder = getSwordsFolder()
	for _, definition in ipairs(Catalog.GetAll()) do
		local template = findTemplate(folder, definition.SwordId)
		if not template then
			template = createExampleTemplate(definition)
			template.Parent = folder
		end
		configureTemplate(template, definition)
	end
	return folder
end

local function isCatalogSword(instance)
	return instance:IsA("Tool") and Catalog.Get(instance:GetAttribute("SwordId") or instance.Name) ~= nil
end

local function removeRuntimeSwordsExcept(player, keep)
	local containers = {
		player.Character,
		player:FindFirstChildOfClass("Backpack"),
		player:FindFirstChild("StarterGear"),
	}
	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child ~= keep and isCatalogSword(child) then
					child:Destroy()
				end
			end
		end
	end
end

local function getSwordId(instance)
	if not isCatalogSword(instance) then
		return nil
	end
	return instance:GetAttribute("SwordId") or instance.Name
end

local function findDeliveredSword(player, swordId, character, backpack)
	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if
					getSwordId(child) == swordId
					and child:GetAttribute("ServerValidatedSword") == true
				then
					return child
				end
			end
		end
	end
	return nil
end

local function cloneRuntimeSword(swordId)
	local definition = Catalog.Get(swordId)
	if not definition then
		return nil
	end
	local template = findTemplate(getSwordsFolder(), swordId)
	if not template then
		return nil
	end
	local sword = configureTemplate(template:Clone(), definition)
	for _, descendant in ipairs(sword:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	sword:SetAttribute("ServerValidatedSword", true)
	return sword
end

local function publishSwordAttributes(player, swordId)
	local definition = Catalog.Get(swordId)
	player:SetAttribute("EquippedSword", swordId)
	player:SetAttribute("EquippedSwordName", definition.DisplayName)
	ScoreService.SetSwordMultiplier(player, definition.ScoreMultiplier)
	player:SetAttribute("SwordCoinMultiplier", definition.CoinMultiplier)
end

local function watchDeliveredSword(player, character, sword)
	if sword:GetAttribute("StarterSwordRemovalWatch") == true then
		return
	end
	sword:SetAttribute("StarterSwordRemovalWatch", true)
	sword.AncestryChanged:Connect(function()
		task.delay(0.15, function()
			if
				player.Parent ~= Players
				or player.Character ~= character
				or sword:IsDescendantOf(character)
				or sword:IsDescendantOf(player)
			then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				player:SetAttribute("StarterSwordDeliveryState", "RecoveringRemovedSword")
				SwordProgressionService.DeliverEquippedSword(
					player,
					true,
					character,
					"RuntimeSwordRemoved"
				)
			end
		end)
	end)
end

function SwordProgressionService.DeliverEquippedSword(player, autoEquip, expectedCharacter, reason)
	local data = PlayerDataService.Get(player) or PlayerDataService.Load(player)
	local character = expectedCharacter or player.Character
	if
		player.Parent ~= Players
		or not character
		or player.Character ~= character
	then
		return false, "CharacterChanged"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "CharacterNotAlive"
	end

	local swordId = data.EquippedSword
	if not Catalog.Get(swordId) or not data.OwnedSwords[swordId] then
		swordId = Catalog.GetStarterId()
		PlayerDataService.GrantSword(player, swordId)
		PlayerDataService.SetEquippedSword(player, swordId)
	end

	-- Resolve e valida a mochila atual antes de remover qualquer Tool. No spawn
	-- inicial o Roblox pode substituir uma Backpack criada cedo; apagar primeiro
	-- deixava uma janela na qual a entrega terminava sem espada.
	local backpack = player:FindFirstChildOfClass("Backpack")
		or player:WaitForChild("Backpack", 8)
	if
		not backpack
		or backpack.Parent ~= player
		or player.Character ~= character
	then
		return false, "BackpackChanged"
	end

	local sword = findDeliveredSword(player, swordId, character, backpack)
	if not sword then
		sword = cloneRuntimeSword(swordId)
		if not sword then
			warn("[SwordProgression] Template ausente para " .. swordId)
			player:SetAttribute("StarterSwordDeliveryState", "TemplateMissing")
			return false, "TemplateMissing"
		end
	end

	-- A partir daqui nao ha yield: duas solicitacoes concorrentes nao podem
	-- apagar a arma uma da outra entre a limpeza e a insercao.
	deliveryTokens[player] = (deliveryTokens[player] or 0) + 1
	local token = deliveryTokens[player]
	removeRuntimeSwordsExcept(player, sword)
	if sword.Parent == nil then
		sword.Parent = backpack
	end
	publishSwordAttributes(player, swordId)
	watchDeliveredSword(player, character, sword)
	player:SetAttribute("StarterSwordDeliveryVersion", DELIVERY_VERSION)
	player:SetAttribute("StarterSwordDeliveryState", "Ready")
	player:SetAttribute("StarterSwordLastReason", tostring(reason or "Direct"))
	player:SetAttribute("StarterSwordReady", true)

	if autoEquip ~= false and sword.Parent == backpack then
		task.defer(function()
			if
				deliveryTokens[player] == token
				and player.Character == character
				and humanoid.Parent == character
				and humanoid.Health > 0
				and sword.Parent == backpack
			then
				humanoid:EquipTool(sword)
			end
		end)
	end
	return true, sword
end

function SwordProgressionService.GetShopInventory(player)
	local data = PlayerDataService.Get(player) or PlayerDataService.Load(player)
	local inventory = {}
	for _, definition in ipairs(Catalog.GetAll()) do
		local template = findTemplate(getSwordsFolder(), definition.SwordId)
		local baseDamage = template and resolveBaseDamage(template, definition) or definition.BaseDamage
		table.insert(inventory, {
			SwordId = definition.SwordId,
			DisplayName = definition.DisplayName,
			Description = definition.Description,
			Price = definition.Price,
			BaseDamage = baseDamage,
			AttackSpeed = definition.AttackSpeed,
			ScoreMultiplier = definition.ScoreMultiplier,
			CoinMultiplier = definition.CoinMultiplier,
			KnockbackMultiplier = definition.KnockbackMultiplier,
			RangeMultiplier = definition.RangeMultiplier,
			CriticalChance = definition.CriticalChance,
			Color = definition.Color,
			Owned = data.OwnedSwords[definition.SwordId] == true,
			Equipped = data.EquippedSword == definition.SwordId,
		})
	end
	return inventory
end

function SwordProgressionService.Purchase(player, swordId)
	local definition = Catalog.Get(swordId)
	if not definition then
		return false, "Espada invalida."
	end
	PlayerDataService.Load(player)
	if PlayerDataService.HasSword(player, swordId) then
		return false, "Voce ja possui esta espada."
	end
	local paid, remaining = ScoreService.TrySpendCoins(player, definition.Price)
	if not paid then
		return false, CURRENCY_SYMBOL .. " Moedas insuficientes.", remaining
	end
	PlayerDataService.GrantSword(player, swordId)
	task.spawn(PlayerDataService.Save, player, false)
	player:SetAttribute("OwnedSwordCount", (player:GetAttribute("OwnedSwordCount") or 1) + 1)
	return true, "Espada comprada!", remaining
end

function SwordProgressionService.Equip(player, swordId)
	if not Catalog.Get(swordId) then
		return false, "Espada invalida."
	end
	if not PlayerDataService.HasSword(player, swordId) then
		return false, "Compre esta espada primeiro."
	end
	if not PlayerDataService.SetEquippedSword(player, swordId) then
		return false, "Nao foi possivel equipar."
	end
	SwordProgressionService.DeliverEquippedSword(player, true)
	task.spawn(PlayerDataService.Save, player, false)
	return true, "Espada equipada!"
end

local function setupPlayer(player)
	if initializedPlayers[player] then
		return
	end
	initializedPlayers[player] = true
	player:SetAttribute("StarterSwordDeliveryVersion", DELIVERY_VERSION)
	player:SetAttribute("StarterSwordDeliveryState", "WaitingForCharacter")
	player:SetAttribute("StarterSwordReady", false)

	local function scheduleForCharacter(character)
		characterGenerations[player] = (characterGenerations[player] or 0) + 1
		local generation = characterGenerations[player]
		player:SetAttribute("StarterSwordReady", false)
		player:SetAttribute("StarterSwordDeliveryState", "WaitingForData")

		task.spawn(function()
			-- Checkpoints posteriores tornam a entrega autocorretiva caso outro
			-- sistema do primeiro spawn substitua a Backpack ou remova a Tool.
			local elapsed = 0
			for attempt, checkpoint in ipairs(DELIVERY_CHECKPOINTS) do
				local waitTime = checkpoint - elapsed
				elapsed = checkpoint
				if waitTime > 0 then
					task.wait(waitTime)
				end
				if
					player.Parent ~= Players
					or player.Character ~= character
					or characterGenerations[player] ~= generation
				then
					return
				end
				player:SetAttribute("StarterSwordDeliveryAttempt", attempt)
				local success, failure = SwordProgressionService.DeliverEquippedSword(
					player,
					true,
					character,
					attempt == 1 and "CharacterAdded" or "FirstSpawnVerification"
				)
				if not success then
					player:SetAttribute("StarterSwordDeliveryState", tostring(failure))
				end
			end
		end)
	end

	-- A conexao vem antes do DataStore. Um PlayerAdded de servidor ja aberto
	-- pode gerar o personagem enquanto Load() ainda esta aguardando rede.
	player.CharacterAdded:Connect(scheduleForCharacter)
	if player.Character then
		scheduleForCharacter(player.Character)
	end

	task.spawn(function()
		local data = PlayerDataService.Load(player)
		if player.Parent ~= Players then
			return
		end
		local count = 0
		for _, owned in pairs(data.OwnedSwords) do
			if owned then
				count += 1
			end
		end
		player:SetAttribute("OwnedSwordCount", count)
		player:SetAttribute("EquippedSword", data.EquippedSword)
		if not player.Character then
			player:SetAttribute("StarterSwordDeliveryState", "DataReadyWaitingForCharacter")
		end
	end)
end

function SwordProgressionService.Start()
	if started then
		return
	end
	started = true
	ScoreService.Start()
	ensureTemplates()
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		deliveryTokens[player] = nil
		initializedPlayers[player] = nil
		characterGenerations[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end
	print("[SwordProgression] Catalogo, compra, salvamento e entrega iniciados.")
end

return SwordProgressionService
