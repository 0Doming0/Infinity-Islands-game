--[[
	SkyDungeon - MonsterSpawner

	ModuleScript chamado diretamente por Generator.Generate.
	Nao observa o Workspace e nao tenta reconstruir a geometria da ilha.
	Recebe as celulas logicas livres de Generator.GetFreeCells().

	LOCAL
	ServerScriptService/BlockParkour/MonsterSpawner

	MODELOS
	ServerStorage/MVPAssets/Monsters

	ATRIBUTOS DO MODEL
	Enabled             Boolean  true
	MonsterId           String   "GreenSlime"
	DisplayName         String   "Slime Verde"
	MaxHealth           Number   50
	ScoreValue          Number   3
	CoinValue           Number   5
	AttackDamage        Number   8
	SpawnChance         Number   1
	SpawnWeight         Number   10
	MinimumIslandSize   String   "Small", "Medium" ou "Large"
	SpawnMode           String   "Solo", "Group" ou "Boss"
	GroupMin            Number   2
	GroupMax            Number   5
	GroupSpacing        Number   5
	DropChance          Number   0
	DropItemId          String   ""
	Peaceful            Boolean  false
	UseCentralAI        Boolean  true
	SlimeVariant        String   "Random", "Green", "Blue", "Red", "Fire", "Ice", "Lightning" ou "Golden"
	KeepEmbeddedAIScripts Boolean false
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local InventoryService = require(script.Parent.Parent.MVPSystems:WaitForChild("InventoryService"))
local ServerScriptService = game:GetService("ServerScriptService")
local SlimeController = require(script.Parent.SlimeController)
local SlimeVariants = require(script.Parent.SlimeVariants)
local PartyService = require(script.Parent.PartyService)
local MonsterSystem = script.Parent.Parent:WaitForChild("MonsterSystem")
local MonsterConfig = require(MonsterSystem.MonsterConfig)
local MonsterLoot = require(MonsterSystem.MonsterLoot)
local MonsterValidator = require(MonsterSystem.MonsterValidator)
local CombatDamageService = require(script.Parent.Parent.MVPSystems.CombatDamageService)
local CompanionService = require(script.Parent.Parent.MVPSystems.CompanionService)
local RewardWheelService = require(script.Parent.Parent.MVPSystems.RewardWheelService)
local MonetizationService = require(script.Parent.Parent.MVPSystems.MonetizationService)

ScoreService.Start()
InventoryService.Start()
CompanionService.Start()

local MonsterSpawner = {}

local CONFIG = {
	MAX_MONSTERS = 45,
	-- Mantem vagas globais para que ilhas Elite nao fiquem vazias quando os
	-- rounds anteriores ja preencheram o mapa com grupos de mobs normais.
	ELITE_RESERVED_SLOTS = 3,
	DEFAULT_SPAWN_CHANCE = 0.72,
	DEFAULT_SPAWN_WEIGHT = 10,
	DEFAULT_GROUP_MIN = 2,
	DEFAULT_GROUP_MAX = 4,
	DEFAULT_GROUP_SPACING = 5,
	DEFAULT_MAX_HEALTH = 50,
	DEFAULT_SCORE_VALUE = 3,
	DEFAULT_COIN_VALUE = 5,
	DEFAULT_ATTACK_DAMAGE = 8,
	DEFAULT_DROP_CHANCE = 0,
	DEFAULT_MINIMUM_ISLAND_SIZE = "Small",

	LOOT_CHECK_INTERVAL = 0.15,
	LOOT_LIFETIME = 20,
	LOOT_PICKUP_RADIUS = 6,

	RANDOM_SALT = 91373,
	MAX_SEED = 2147483647,
	ELITE_BOUNDARY_HEIGHT = 20,
	ELITE_BOUNDARY_THICKNESS = 2,
}

local SIZE_RANK = {
	Small = 1,
	Medium = 2,
	Large = 3,
}

local activeMonsters = {}
local REMOVED_MONSTER_IDS = {
	Golem = true,
	StoneGolem = true,
}
local activeLoot = {}
local monsterCount = 0
local initialized = false

local function normalizedSeed(value)
	local seed = math.floor(math.abs(value or 1)) % CONFIG.MAX_SEED
	return seed == 0 and 1 or seed
end

local function numberAttribute(instance, name, defaultValue)
	local value = instance:GetAttribute(name)
	return typeof(value) == "number" and value or defaultValue
end

local function getSpawnLimit(isElite)
	if isElite then
		return CONFIG.MAX_MONSTERS
	end
	return math.max(0, CONFIG.MAX_MONSTERS - CONFIG.ELITE_RESERVED_SLOTS)
end

local function getRoot(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getHumanoid(model)
	return model and model:FindFirstChildWhichIsA("Humanoid", true)
end

local function createMobHealthBar(model, root, humanoid, modelHeight)
	local old = model:FindFirstChild("MobHealthBar")
	if old then
		old:Destroy()
	end

	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MobHealthBar"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(66, 8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, math.max(3.2, modelHeight * 0.55 + 1.1), 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Enabled = false
	billboard.Parent = model

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(18, 24, 22)
	background.BackgroundTransparency = 0.15
	background.BorderSizePixel = 0
	background.ClipsDescendants = true
	background.Parent = billboard
	Instance.new("UICorner", background).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(50, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = background
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(7, 12, 9)
	stroke.Thickness = 1
	stroke.Transparency = 0.12
	stroke.Parent = background

	local function update()
		local maximum = math.max(1, humanoid.MaxHealth)
		local ratio = math.clamp(humanoid.Health / maximum, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		billboard.Enabled = humanoid.Health > 0 and ratio < 0.999
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
end

local function ensureEliteBoundary(island)
	if island:GetAttribute("IslandType") ~= "Elite" or island:FindFirstChild("EliteMobBoundary") then
		return
	end
	local floor = island:FindFirstChild("IslandFloor")
	if not floor or not floor:IsA("BasePart") then
		return
	end

	pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, "EliteIslandBoundary")
	local folder = Instance.new("Folder")
	folder.Name = "EliteMobBoundary"
	folder.Parent = island
	local thickness = CONFIG.ELITE_BOUNDARY_THICKNESS
	local height = CONFIG.ELITE_BOUNDARY_HEIGHT
	local centerY = floor.Size.Y / 2 + height / 2
	local barriers = {
		{
			Name = "North",
			Size = Vector3.new(floor.Size.X + thickness * 2, height, thickness),
			Offset = Vector3.new(0, centerY, -(floor.Size.Z / 2 + thickness / 2)),
		},
		{
			Name = "South",
			Size = Vector3.new(floor.Size.X + thickness * 2, height, thickness),
			Offset = Vector3.new(0, centerY, floor.Size.Z / 2 + thickness / 2),
		},
		{
			Name = "West",
			Size = Vector3.new(thickness, height, floor.Size.Z),
			Offset = Vector3.new(-(floor.Size.X / 2 + thickness / 2), centerY, 0),
		},
		{
			Name = "East",
			Size = Vector3.new(thickness, height, floor.Size.Z),
			Offset = Vector3.new(floor.Size.X / 2 + thickness / 2, centerY, 0),
		},
	}
	for _, definition in ipairs(barriers) do
		local barrier = Instance.new("Part")
		barrier.Name = definition.Name
		barrier.Size = definition.Size
		barrier.CFrame = floor.CFrame * CFrame.new(definition.Offset)
		barrier.Anchored = true
		barrier.CanCollide = true
		barrier.CanTouch = false
		barrier.CanQuery = false
		barrier.CastShadow = false
		barrier.Transparency = 1
		barrier:SetAttribute("EliteMobBoundary", true)
		local assigned = pcall(function()
			barrier.CollisionGroup = "EliteIslandBoundary"
		end)
		if not assigned then
			barrier.CanCollide = false
			warn("[MonsterSpawner] Grupo EliteIslandBoundary indisponivel; barreira desativada.")
		end
		barrier.Parent = folder
	end
end

local function getMonsterFolder()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "MVPAssets"
		assets.Parent = ServerStorage
	end
	local folder = assets:FindFirstChild("Monsters")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Monsters"
		folder.Parent = assets
	end
	return folder
end

local function createPrototypeMonster(folder)
	local model = Instance.new("Model")
	model.Name = "PrototypeSlime"
	model:SetAttribute("MonsterId", "PrototypeSlime")
	model:SetAttribute("MonsterType", "Slime")
	model:SetAttribute("DisplayName", "Slime de Prototipo")
	model:SetAttribute("Enabled", true)
	model:SetAttribute("MaxHealth", 45)
	model:SetAttribute("ScoreValue", 3)
	model:SetAttribute("CoinValue", 5)
	model:SetAttribute("AttackDamage", 8)
	model:SetAttribute("SpawnChance", 0.72)
	model:SetAttribute("SpawnWeight", 10)
	model:SetAttribute("MinimumIslandSize", "Small")
	model:SetAttribute("SpawnMode", "Group")
	model:SetAttribute("GroupMin", 2)
	model:SetAttribute("GroupMax", 3)
	model:SetAttribute("GroupSpacing", 5)
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("UseCentralAI", true)
	-- A chance autoritativa vem do CompanionCatalog; este Attribute permanece
	-- apenas como telemetria/compatibilidade com assets antigos.
	model:SetAttribute("CompanionUnlockChance", 0.06)
	model:SetAttribute("CompanionImageId", "")
	model:SetAttribute("CompanionScale", 0.72)
	model:SetAttribute("PrototypeModel", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.8, 2.2, 2.8)
	root.Shape = Enum.PartType.Ball
	root.Material = Enum.Material.SmoothPlastic
	root.Color = Color3.fromRGB(80, 205, 92)
	root.Anchored = false
	root.CanCollide = true
	root.Parent = model
	local face = Instance.new("Decal")
	face.Name = "PrototypeFace"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = root
	local humanoid = Instance.new("Humanoid")
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = folder
	warn("[MonsterSpawner] Nenhum modelo encontrado. PrototypeSlime criado; substitua em ServerStorage/MVPAssets/Monsters.")
	return model
end

local function getTemplates()
	local folder = getMonsterFolder()
	local templates = {}
	for _, template in ipairs(folder:GetChildren()) do
		local monsterId = template:GetAttribute("MonsterId") or template.Name
		if REMOVED_MONSTER_IDS[monsterId] or REMOVED_MONSTER_IDS[template.Name] then
			continue
		end
		local valid, errors = MonsterValidator.Validate(template)
		if valid then
			table.insert(templates, template)
		elseif template:GetAttribute("Enabled") ~= false then
			warn(string.format(
				"[MonsterSpawner] Ignorando %s: %s",
				template:GetFullName(),
				MonsterValidator.Format(errors)
			))
		end
	end
	table.sort(templates, function(a, b)
		return a.Name < b.Name
	end)
	if #templates == 0 then
		table.insert(templates, createPrototypeMonster(folder))
	end
	return templates
end

local function chooseWeightedTemplate(random, templates, islandSize)
	local islandRank = SIZE_RANK[islandSize] or 0
	local candidates = {}
	local totalWeight = 0

	for _, template in ipairs(templates) do
		local minimumSize = template:GetAttribute("MinimumIslandSize") or CONFIG.DEFAULT_MINIMUM_ISLAND_SIZE
		local minimumRank = SIZE_RANK[minimumSize] or math.huge
		local weight = math.max(0, numberAttribute(template, "SpawnWeight", CONFIG.DEFAULT_SPAWN_WEIGHT))
		if islandRank >= minimumRank and weight > 0 then
			totalWeight += weight
			table.insert(candidates, {
				Template = template,
				Weight = weight,
			})
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, candidate in ipairs(candidates) do
		accumulated += candidate.Weight
		if roll <= accumulated then
			return candidate.Template
		end
	end
	return candidates[#candidates].Template
end

local function getSpawnAmount(template, random)
	local mode = template:GetAttribute("SpawnMode") or "Solo"
	if mode == "Group" then
		local minimum = math.max(1, math.floor(numberAttribute(template, "GroupMin", CONFIG.DEFAULT_GROUP_MIN)))
		local maximum = math.max(minimum, math.floor(numberAttribute(template, "GroupMax", CONFIG.DEFAULT_GROUP_MAX)))
		return random:NextInteger(minimum, maximum), mode, minimum
	end
	return 1, mode, 1
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function shuffle(random, values)
	local result = table.clone(values)
	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

local function isValidCellRecord(record)
	return typeof(record) == "table"
		and typeof(record.Cell) == "Vector3"
		and typeof(record.SurfacePosition) == "Vector3"
end

local function selectSpawnCells(cells, amount, spacing, random)
	local valid = {}
	for _, record in ipairs(cells) do
		if isValidCellRecord(record) then
			table.insert(valid, record)
		end
	end

	local candidates = shuffle(random, valid)
	local selected = {}
	local selectedSet = {}

	for _, candidate in ipairs(candidates) do
		local farEnough = true
		for _, existing in ipairs(selected) do
			if horizontalDistance(candidate.SurfacePosition, existing.SurfacePosition) < spacing then
				farEnough = false
				break
			end
		end

		if farEnough then
			table.insert(selected, candidate)
			selectedSet[candidate] = true
			if #selected >= amount then
				return selected
			end
		end
	end

	-- Em salas compactas, relaxa o espacamento, mas continua usando celulas diferentes.
	for _, candidate in ipairs(candidates) do
		if not selectedSet[candidate] then
			table.insert(selected, candidate)
			selectedSet[candidate] = true
			if #selected >= amount then
				break
			end
		end
	end

	return selected
end

local function ensureMaterials(player)
	local folder = player:FindFirstChild("Materials")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Materials"
		folder.Parent = player
	end
	return folder
end

local function awardRewards(player, scoreAmount, coinAmount, worldPosition)
	if player then
		ScoreService.AwardRewards(player, scoreAmount, coinAmount, "Monster", worldPosition)
	end
end

local function getRecordedDamager(entry, model, humanoid)
	if entry.LastDamager and entry.LastDamager.Parent == Players then
		return entry.LastDamager
	end

	local creator = humanoid:FindFirstChild("creator")
	if creator and creator:IsA("ObjectValue") and creator.Value and creator.Value:IsA("Player") then
		return creator.Value
	end

	local userId = model:GetAttribute("LastDamagedByUserId")
	if typeof(userId) ~= "number" then
		userId = model:GetAttribute("LastHitUserId")
	end
	if typeof(userId) == "number" then
		return Players:GetPlayerByUserId(userId)
	end
	return nil
end

local function createDeathParticles(root, color)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(89, 220, 91))
	emitter.LightEmission = 0.5
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = root
	emitter:Emit(24)
end

local function createLoot(parent, position, itemId, amount)
	if not itemId or itemId == "" then
		return
	end

	local pickup = Instance.new("Part")
	pickup.Name = "Loot_" .. itemId
	pickup.Size = Vector3.new(1.4, 0.35, 1.4)
	pickup.Position = position + Vector3.new(0, 1, 0)
	pickup.Anchored = true
	pickup.CanCollide = false
	pickup.CanTouch = false
	pickup.CanQuery = true
	pickup.Material = Enum.Material.Neon
	pickup.Color = Color3.fromRGB(255, 210, 65)
	pickup:SetAttribute("ItemId", itemId)
	pickup:SetAttribute("Amount", math.max(1, math.floor(tonumber(amount) or 1)))
	pickup:SetAttribute("Claimed", false)
	pickup.Parent = parent

	activeLoot[pickup] = {
		ItemId = itemId,
		Amount = math.max(1, math.floor(tonumber(amount) or 1)),
		ExpiresAt = os.clock() + CONFIG.LOOT_LIFETIME,
	}
end

local function unregisterMonster(model)
	SlimeController.Stop(model)
	if activeMonsters[model] then
		activeMonsters[model] = nil
		monsterCount = math.max(0, monsterCount - 1)
	end
	if CollectionService:HasTag(model, "CombatTarget") then
		CollectionService:RemoveTag(model, "CombatTarget")
	end
end

local function createMarker(pointsFolder, cellRecord, index, template, spawnMode)
	local marker = Instance.new("CFrameValue")
	marker.Name = string.format("Monster_%02d", index)
	marker.Value = CFrame.new(cellRecord.SurfacePosition)
	marker:SetAttribute("GridX", cellRecord.Cell.X)
	marker:SetAttribute("GridY", cellRecord.Cell.Y)
	marker:SetAttribute("GridZ", cellRecord.Cell.Z)
	marker:SetAttribute("MonsterId", template:GetAttribute("MonsterId") or template.Name)
	marker:SetAttribute("SpawnMode", spawnMode)
	marker.Parent = pointsFolder
	return marker
end

local function spawnClone(template, parent, island, cellRecord, marker, random, spawnMode, slimeVariantForSpawn)
	local elite = island:GetAttribute("IslandType") == "Elite"
	if monsterCount >= getSpawnLimit(elite) then
		return false
	end

    local AnimeOutline = require(
	    ServerScriptService.MVPSystems.AnimeOutline
    )
	local MobDamageFeedback = require(
	    ServerScriptService.MVPSystems.MobDamageFeedback
    )

	local clone = template:Clone()
	local root = getRoot(clone)
	local humanoid = getHumanoid(clone)
	if not root or not humanoid then
		clone:Destroy()
		return false
	end

	clone.PrimaryPart = root
	local slimeDefinition, slimeVariant = SlimeVariants.ConfigureClone(
		clone,
		template,
		random,
		slimeVariantForSpawn
	)
	local monsterId = slimeDefinition and slimeDefinition.MonsterId
		or template:GetAttribute("MonsterId")
		or template.Name
	local displayName = slimeDefinition and slimeDefinition.DisplayName
		or template:GetAttribute("DisplayName")
		or monsterId
	local maxHealth = math.max(1, numberAttribute(template, "MaxHealth", CONFIG.DEFAULT_MAX_HEALTH))
	local scoreValue = math.max(0, numberAttribute(template, "ScoreValue", CONFIG.DEFAULT_SCORE_VALUE))
	if template:GetAttribute("RewardScaleVersion") ~= 2 and scoreValue > 10 then
		scoreValue = math.max(1, math.floor(scoreValue / 10))
	end
	local coinValue = math.max(0, numberAttribute(template, "CoinValue", CONFIG.DEFAULT_COIN_VALUE))
	local attackDamage = math.max(0, numberAttribute(template, "AttackDamage", CONFIG.DEFAULT_ATTACK_DAMAGE))
	if slimeDefinition then
		maxHealth *= slimeDefinition.HealthMultiplier
		scoreValue *= slimeDefinition.ScoreMultiplier
		coinValue *= slimeDefinition.CoinMultiplier
		attackDamage = slimeDefinition.AttackDamage or attackDamage
	end
	local roundIndex = tonumber(island:GetAttribute("RoundIndex")) or 1
	local difficultyTier = math.clamp(
		math.floor((roundIndex - 1) / MVPConfig.Difficulty.RoundsPerTier) + 1,
		1,
		MVPConfig.Difficulty.MaximumTier
	)
	local healthMultiplier = 1 + (difficultyTier - 1) * MVPConfig.Difficulty.HealthPerTier
	local damageMultiplier = 1 + (difficultyTier - 1) * MVPConfig.Difficulty.DamagePerTier
	local routeRewardMultiplier = math.max(0.1, tonumber(island:GetAttribute("RouteRewardMultiplier")) or 1)
	local rewardMultiplier = (1 + (difficultyTier - 1) * MVPConfig.Difficulty.RewardPerTier)
		* routeRewardMultiplier
	if elite then
		healthMultiplier *= MVPConfig.Difficulty.EliteHealthMultiplier
		damageMultiplier *= MVPConfig.Difficulty.EliteDamageMultiplier
		rewardMultiplier *= MVPConfig.Difficulty.EliteRewardMultiplier
	end
	maxHealth = math.floor(maxHealth * healthMultiplier)
	attackDamage = math.floor(attackDamage * damageMultiplier)
	scoreValue = math.max(1, math.floor(scoreValue * rewardMultiplier))
	coinValue = math.max(1, math.floor(coinValue * rewardMultiplier))
	if elite then
		scoreValue = math.max(15, scoreValue)
		coinValue = math.max(25, coinValue)
	end

	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 18
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = math.clamp(
		numberAttribute(template, "WalkSpeed", humanoid.WalkSpeed)
			* (elite and MVPConfig.Difficulty.EliteSpeedMultiplier or 1),
		4,
		28
	)

	clone.Name = "Monster_" .. monsterId
	clone:SetAttribute("DisplayName", displayName)
	clone:SetAttribute("RuntimeMonster", true)
	clone:SetAttribute("MonsterId", monsterId)
	clone:SetAttribute("SpawnMode", spawnMode)
	clone:SetAttribute("ScoreValue", scoreValue)
	clone:SetAttribute("CoinValue", coinValue)
	clone:SetAttribute("AttackDamage", attackDamage)
	clone:SetAttribute("DifficultyTier", difficultyTier)
	clone:SetAttribute("IsElite", elite)
	if elite then
		local baseAttackCooldown = slimeDefinition and slimeDefinition.AttackCooldown
			or numberAttribute(template, "AttackCooldown", 1.15)
		clone:SetAttribute(
			"AttackCooldown",
			math.max(0.25, baseAttackCooldown * MVPConfig.Difficulty.EliteAttackCooldownMultiplier)
		)
	end
	clone:SetAttribute("HomePosition", cellRecord.SurfacePosition)
	local initiallyPeaceful = template:GetAttribute("Peaceful") == true
	if slimeDefinition then
		initiallyPeaceful = slimeDefinition.InitiallyPeaceful
	end
	clone:SetAttribute("Peaceful", not elite and initiallyPeaceful)
	local usesSlimeController = slimeDefinition ~= nil
	local useCentralAI = not usesSlimeController and template:GetAttribute("UseCustomAI") ~= true
	if useCentralAI then
		MonsterConfig.ApplyRuntimeDefaults(clone)
	end
	clone:SetAttribute("UseCentralAI", useCentralAI)
	clone:SetAttribute("AIController", usesSlimeController and "Slime" or (useCentralAI and "Generic" or "Custom"))
	clone:SetAttribute("SimulationActive", island:GetAttribute("SimulationActive") ~= false)
	clone:SetAttribute("SpawnSurfacePosition", cellRecord.SurfacePosition)
	clone:SetAttribute("SpawnGridX", cellRecord.Cell.X)
	clone:SetAttribute("SpawnGridY", cellRecord.Cell.Y)
	clone:SetAttribute("SpawnGridZ", cellRecord.Cell.Z)
	if slimeVariant then
		marker:SetAttribute("SlimeVariant", slimeVariant)
		marker:SetAttribute("MonsterId", monsterId)
	end
	CollectionService:AddTag(clone, "CombatTarget")

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BaseScript") and (useCentralAI or usesSlimeController) then
			if
				not slimeDefinition
				or (
					template:GetAttribute("KeepEmbeddedAIScripts") ~= true
					and descendant.Name ~= "Animate"
					and descendant:GetAttribute("AllowWithSlimeController") ~= true
				)
			then
				descendant.Disabled = true
			end
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			pcall(function()
				descendant.CollisionGroup = "MVPMonsters"
			end)
			-- Necessario para GetPartBoundsInBox detectar o corpo do mob.
			descendant.CanQuery = true
		end
	end

	-- Alinha a base real do modelo ao piso. Isso funciona mesmo quando o Pivot
	-- ou o HumanoidRootPart nao ficam exatamente no centro vertical do monstro.
	clone:PivotTo(CFrame.identity)
	local boundingBox, boundingSize = clone:GetBoundingBox()
	local bottomOffset = boundingBox.Position.Y - boundingSize.Y / 2
	local desiredBottomY = cellRecord.SurfacePosition.Y + 0.15
	clone:PivotTo(
		CFrame.new(cellRecord.SurfacePosition.X, desiredBottomY - bottomOffset, cellRecord.SurfacePosition.Z)
			* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	)
	createMobHealthBar(clone, root, humanoid, boundingSize.Y)

	local entry = {
		Model = clone,
		Root = root,
		Humanoid = humanoid,
		Island = island,
		Marker = marker,
		ScoreValue = scoreValue,
		CoinValue = coinValue,
		DropChance = math.clamp(numberAttribute(template, "DropChance", CONFIG.DEFAULT_DROP_CHANCE), 0, 1),
		DropItemId = template:GetAttribute("DropItemId") or "",
		LootDefinitions = MonsterLoot.Read(template),
		LootRolls = math.max(1, math.floor(numberAttribute(template, "LootRolls", 1))),
		DeathParticleColor = clone:GetAttribute("DeathParticleColor") or template:GetAttribute("DeathParticleColor"),
		LastDamager = nil,
		SlimeDefinition = slimeDefinition and table.clone(slimeDefinition) or nil,
	}
	if entry.SlimeDefinition then
		entry.SlimeDefinition.AttackDamage = attackDamage
		if elite and entry.SlimeDefinition.AttackCooldown then
			entry.SlimeDefinition.AttackCooldown = math.max(
				0.25,
				entry.SlimeDefinition.AttackCooldown * MVPConfig.Difficulty.EliteAttackCooldownMultiplier
			)
		end
	end
	activeMonsters[clone] = entry
	monsterCount += 1

	humanoid.Died:Connect(function()
		if not activeMonsters[clone] then
			return
		end
		unregisterMonster(clone)
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end

		local deathPosition = root.Position
		local damager = getRecordedDamager(entry, clone, humanoid)
		if damager then
			awardRewards(damager, entry.ScoreValue, entry.CoinValue, deathPosition)
			PartyService.RecordMissionProgress(damager, "MobDefeated", 1, clone)
			CompanionService.RecordDefeat(damager, clone)
			if clone:GetAttribute("SpawnMode") == "Boss" then
				RewardWheelService.Spin(damager, "Boss", {
					Level = clone:GetAttribute("DifficultyTier"),
					MonsterId = clone:GetAttribute("MonsterId"),
					WorldPosition = deathPosition,
				})
			end
			if clone:GetAttribute("IsElite") == true and random:NextNumber() <= 0.25 then
				InventoryService.GrantItem(damager, "HealthPotion", 1)
			end
			if clone:GetAttribute("IsElite") == true then
				MonetizationService.RecordEliteDefeat(damager)
			end
		end
		if root.Parent then
			createDeathParticles(root, entry.DeathParticleColor)
		end
		if root.Parent and entry.Island.Parent then
			local lootFolder = entry.Island:FindFirstChild("MVPLoot")
			if not lootFolder then
				lootFolder = Instance.new("Folder")
				lootFolder.Name = "MVPLoot"
				lootFolder.Parent = entry.Island
			end
			for lootIndex, loot in ipairs(MonsterLoot.Roll(entry.LootDefinitions, entry.LootRolls, random)) do
				local angle = lootIndex * 2.399
				local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.min(2, lootIndex * 0.35)
				createLoot(lootFolder, root.Position + offset, loot.ItemId, loot.Amount)
			end
		end
		Debris:AddItem(clone, 0.7)
	end)

	clone.Parent = parent
	if entry.SlimeDefinition then
		SlimeController.Start(entry, entry.SlimeDefinition, random, {
			OnTeleported = function(destinationIsland)
				entry.Island = destinationIsland
			end,
			OnExpired = function()
				if activeMonsters[clone] then
					unregisterMonster(clone)
				end
				if clone.Parent then
					clone:Destroy()
				end
			end,
		})
	end
	if not elite then
	    AnimeOutline.Apply(clone)
	else
        AnimeOutline.Apply(clone, {
	        OutlineColor = Color3.fromRGB(255, 210, 70),
	        OutlineTransparency = 0.05,
        })
	end 

	MobDamageFeedback.Bind(clone)

	clone.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			unregisterMonster(clone)
		end
	end)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return true
end

function MonsterSpawner.DamageMonster(player, model, damage)
	local entry = activeMonsters[model]
	local runtimeModel = model
	while not entry and runtimeModel and runtimeModel ~= workspace do
		runtimeModel = runtimeModel.Parent
		entry = runtimeModel and activeMonsters[runtimeModel]
	end
	if not entry or entry.Humanoid.Health <= 0 then
		return false
	end
	entry.LastDamager = player
	return CombatDamageService.ApplyDirectHit(player, {
		Model = entry.Model,
		Humanoid = entry.Humanoid,
		Root = entry.Root,
	}, damage, "LegacyMonsterDamage")
end

local function setupPlayer(player)
	ensureMaterials(player)
end

local function lootPass()
	for pickup, entry in pairs(activeLoot) do
		if not pickup.Parent or os.clock() >= entry.ExpiresAt then
			activeLoot[pickup] = nil
			if pickup.Parent then
				pickup:Destroy()
			end
			continue
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if
				root
				and humanoid
				and humanoid.Health > 0
				and (root.Position - pickup.Position).Magnitude <= CONFIG.LOOT_PICKUP_RADIUS
			then
				pickup:SetAttribute("Claimed", true)
				activeLoot[pickup] = nil
				local granted = InventoryService.GrantItem(player, entry.ItemId, entry.Amount)
				if not granted then
					-- Compatibilidade para materiais de assets antigos ainda nao
					-- cadastrados como consumiveis no ItemCatalog.
					local materials = ensureMaterials(player)
					local value = materials:FindFirstChild(entry.ItemId)
					if not value then
						value = Instance.new("IntValue")
						value.Name = entry.ItemId
						value.Parent = materials
					end
					value.Value += entry.Amount
				end
				pickup:Destroy()
				break
			end
		end
	end
end

local function initialize()
	if initialized then
		return
	end
	initialized = true
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
	task.spawn(function()
		while true do
			task.wait(CONFIG.LOOT_CHECK_INTERVAL)
			lootPass()
		end
	end)
end

function MonsterSpawner.PopulateIsland(island, freeCells, context)
	initialize()
	assert(island and island:IsA("Model"), "[MonsterSpawner] Ilha invalida.")
	assert(typeof(freeCells) == "table", "[MonsterSpawner] freeCells precisa ser tabela.")
	context = context or {}
	local yieldCallback = context.YieldCallback
	SlimeController.RegisterIsland(island, freeCells)

	local eliteIsland = island:GetAttribute("IslandType") == "Elite"
	if eliteIsland then
		ensureEliteBoundary(island)
	end
	if
		island:GetAttribute("CanSpawnMonster") ~= true
		or island:GetAttribute("HasBoss") == true
		or island:FindFirstChild("MonsterSpawnPoints")
		or monsterCount >= getSpawnLimit(eliteIsland)
	then
		return 0
	end

	local islandSize = island:GetAttribute("TerrainSize") or "Small"
	if not SIZE_RANK[islandSize] then
		warn("[MonsterSpawner] TerrainSize invalido em " .. island:GetFullName())
		return 0
	end

	local templates = getTemplates()
	if #templates == 0 then
		return 0
	end

	local islandSeed = island:GetAttribute("IslandSeed")
	local terrainId = island:GetAttribute("TerrainId") or 1
	local baseSeed = typeof(islandSeed) == "number" and islandSeed or (context.RoundSeed or 1)
	local seed = normalizedSeed(baseSeed + terrainId * 7907 + CONFIG.RANDOM_SALT)
	local random = Random.new(seed)
	local template = chooseWeightedTemplate(random, templates, islandSize)
	if not template and eliteIsland then
		-- Uma ilha Elite nunca deve ficar vazia apenas porque todos os modelos
		-- cadastrados pedem uma ilha maior.
		template = templates[random:NextInteger(1, #templates)]
	end
	if not template then
		return 0
	end

	local routeChanceMultiplier = math.max(0, tonumber(island:GetAttribute("MonsterChanceMultiplier")) or 1)
	local spawnChance = eliteIsland and 1
		or math.clamp(
			numberAttribute(template, "SpawnChance", CONFIG.DEFAULT_SPAWN_CHANCE) * routeChanceMultiplier,
			0,
			1
		)
	if random:NextNumber() > spawnChance then
		return 0
	end

	local amount, spawnMode, groupMinimum = getSpawnAmount(template, random)
	if eliteIsland then
		-- Elite e uma classificacao do monstro/ilha, nao um SpawnMode. Manter um
		-- modo valido evita quebrar consumidores que aceitam apenas Solo/Group/Boss.
		amount, spawnMode, groupMinimum = 1, "Solo", 1
	end
	amount = math.min(amount, getSpawnLimit(eliteIsland) - monsterCount)
	local spacing = spawnMode == "Group"
		and math.max(0, numberAttribute(template, "GroupSpacing", CONFIG.DEFAULT_GROUP_SPACING))
		or 0
	local selectedCells = selectSpawnCells(freeCells, spawnMode == "Group" and amount or 1, spacing, random)

	if #selectedCells == 0 then
		return 0
	end
	if spawnMode == "Group" and #selectedCells < groupMinimum then
		warn(
			string.format(
				"[MonsterSpawner] %s possui %d celulas livres, abaixo do GroupMin %d. Grupo nao criado.",
				island:GetFullName(),
				#selectedCells,
				groupMinimum
			)
		)
		return 0
	end

	local pointsFolder = Instance.new("Folder")
	pointsFolder.Name = "MonsterSpawnPoints"
	pointsFolder:SetAttribute("SpawnMode", spawnMode)
	pointsFolder:SetAttribute("MonsterId", template:GetAttribute("MonsterId") or template.Name)
	if SlimeVariants.IsSlime(template) then
		pointsFolder:SetAttribute("SlimeVariant", "Mixed")
	end
	pointsFolder.Parent = island

	local monsterFolder = Instance.new("Folder")
	monsterFolder.Name = spawnMode == "Boss" and "MVPBoss" or "MVPMonsters"
	monsterFolder:SetAttribute("SpawnMode", spawnMode)
	monsterFolder:SetAttribute("MonsterId", template:GetAttribute("MonsterId") or template.Name)
	if SlimeVariants.IsSlime(template) then
		monsterFolder:SetAttribute("SlimeVariant", "Mixed")
	end
	monsterFolder.Parent = island

	local spawned = 0
	for index, cellRecord in ipairs(selectedCells) do
		local marker = createMarker(pointsFolder, cellRecord, index, template, spawnMode)
		local monsterSeed = normalizedSeed(seed + index * 101)
		local monsterRandom = Random.new(monsterSeed)
		local roundIndex = tonumber(island:GetAttribute("RoundIndex")) or 1
		local difficultyTier = math.clamp(
			math.floor((roundIndex - 1) / MVPConfig.Difficulty.RoundsPerTier) + 1,
			1,
			MVPConfig.Difficulty.MaximumTier
		)
		local slimeVariant = SlimeVariants.IsSlime(template)
			and SlimeVariants.SelectVariant(template, monsterRandom, {
				DisallowGolden = eliteIsland,
				DifficultyTier = difficultyTier,
			})
			or nil
		if
			spawnClone(
				template,
				monsterFolder,
				island,
				cellRecord,
				marker,
				monsterRandom,
				spawnMode,
				slimeVariant
			)
		then
			spawned += 1
		else
			marker:Destroy()
		end
		-- Clonar um rig pode publicar dezenas de descendentes. Limitar a uma
		-- unidade por fatia impede que grupos completos cheguem juntos ao cliente.
		if yieldCallback then
			yieldCallback()
		end
	end

	if spawned == 0 then
		monsterFolder:Destroy()
		pointsFolder:Destroy()
		return 0
	end

	if spawnMode == "Boss" then
		island:SetAttribute("HasBoss", true)
	end
	island:SetAttribute("MonsterSpawnMode", spawnMode)
	island:SetAttribute("MonsterSpawnCount", spawned)

	print(
		string.format(
			"[MonsterSpawner] %s criou %d x %s em %s usando %d celulas logicas.",
			spawnMode,
			spawned,
			template:GetAttribute("MonsterId") or template.Name,
			island:GetFullName(),
			#freeCells
		)
	)
	return spawned
end

function MonsterSpawner.GetActiveCount()
	return monsterCount
end

-- Fornece uma copia somente-leitura dos alvos ativos ao sistema de combate.
-- Isso evita depender exclusivamente de CanQuery/GetPartBoundsInBox em assets importados.
function MonsterSpawner.GetCombatTargets()
	local targets = {}
	for model, entry in pairs(activeMonsters) do
		if model.Parent and entry.Root.Parent and entry.Humanoid.Health > 0 then
			table.insert(targets, {
				Model = model,
				Humanoid = entry.Humanoid,
				Root = entry.Root,
			})
		end
	end
	return targets
end

initialize()

return MonsterSpawner
