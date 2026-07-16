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
	ScoreValue          Number   25
	SpawnChance         Number   1
	SpawnWeight         Number   10
	MinimumIslandSize   String   "Small", "Medium" ou "Large"
	SpawnMode           String   "Solo", "Group" ou "Boss"
	GroupMin            Number   2
	GroupMax            Number   5
	GroupSpacing        Number   5
	DropChance          Number   0
	DropItemId          String   ""
	Peaceful            Boolean  true
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)

ScoreService.Start()

local MonsterSpawner = {}

local CONFIG = {
	MAX_MONSTERS = 45,
	DEFAULT_SPAWN_CHANCE = 1,
	DEFAULT_SPAWN_WEIGHT = 10,
	DEFAULT_GROUP_MIN = 2,
	DEFAULT_GROUP_MAX = 4,
	DEFAULT_GROUP_SPACING = 5,
	DEFAULT_MAX_HEALTH = 50,
	DEFAULT_SCORE_VALUE = 25,
	DEFAULT_DROP_CHANCE = 0,
	DEFAULT_MINIMUM_ISLAND_SIZE = "Small",

	SWORD_DAMAGE = 25,
	SWORD_RANGE = 8,
	SWORD_COOLDOWN = 0.65,

	LOOT_CHECK_INTERVAL = 0.15,
	LOOT_LIFETIME = 20,
	LOOT_PICKUP_RADIUS = 6,

	RANDOM_SALT = 91373,
	MAX_SEED = 2147483647,
}

local SIZE_RANK = {
	Small = 1,
	Medium = 2,
	Large = 3,
}

local activeMonsters = {}
local activeLoot = {}
local lastAttackByPlayer = setmetatable({}, { __mode = "k" })
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

local function getMonsterFolder()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local folder = assets and assets:FindFirstChild("Monsters")
	if not folder or not folder:IsA("Folder") then
		warn("[MonsterSpawner] ServerStorage/MVPAssets/Monsters ausente ou invalido.")
		return nil
	end
	return folder
end

local function validateTemplate(template)
	if not template:IsA("Model") then
		return false, "nao e Model"
	end
	if template:GetAttribute("Enabled") == false then
		return false, "desativado"
	end
	if not getHumanoid(template) then
		return false, "Humanoid ausente"
	end
	if not getRoot(template) then
		return false, "HumanoidRootPart ou PrimaryPart ausente"
	end

	local mode = template:GetAttribute("SpawnMode") or "Solo"
	if mode ~= "Solo" and mode ~= "Group" and mode ~= "Boss" then
		return false, "SpawnMode invalido: " .. tostring(mode)
	end

	local minimumSize = template:GetAttribute("MinimumIslandSize") or CONFIG.DEFAULT_MINIMUM_ISLAND_SIZE
	if not SIZE_RANK[minimumSize] then
		return false, "MinimumIslandSize invalido: " .. tostring(minimumSize)
	end

	return true
end

local function getTemplates()
	local folder = getMonsterFolder()
	if not folder then
		return {}
	end

	local templates = {}
	for _, template in ipairs(folder:GetChildren()) do
		local valid, reason = validateTemplate(template)
		if valid then
			table.insert(templates, template)
		elseif template:GetAttribute("Enabled") ~= false then
			warn(string.format("[MonsterSpawner] Ignorando %s: %s", template:GetFullName(), reason))
		end
	end
	table.sort(templates, function(a, b)
		return a.Name < b.Name
	end)
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

local function awardScore(player, amount, _multiplierOverride)
	if player and amount > 0 then
		-- O multiplicador canonico fica no Player e e definido pela espada
		-- selecionada. multiplierOverride e mantido apenas na assinatura antiga.
		ScoreService.Award(player, amount, "Monster")
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

local function createLoot(parent, position, itemId)
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
	pickup:SetAttribute("Claimed", false)
	pickup.Parent = parent

	activeLoot[pickup] = {
		ItemId = itemId,
		ExpiresAt = os.clock() + CONFIG.LOOT_LIFETIME,
	}
end

local function unregisterMonster(model)
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

local function spawnClone(template, parent, island, cellRecord, marker, random, spawnMode)
	if monsterCount >= CONFIG.MAX_MONSTERS then
		return false
	end

	local clone = template:Clone()
	local root = getRoot(clone)
	local humanoid = getHumanoid(clone)
	if not root or not humanoid then
		clone:Destroy()
		return false
	end

	clone.PrimaryPart = root
	local monsterId = template:GetAttribute("MonsterId") or template.Name
	local displayName = template:GetAttribute("DisplayName") or monsterId
	local maxHealth = math.max(1, numberAttribute(template, "MaxHealth", CONFIG.DEFAULT_MAX_HEALTH))
	local scoreValue = math.max(0, numberAttribute(template, "ScoreValue", CONFIG.DEFAULT_SCORE_VALUE))

	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.DisplayName = displayName
	humanoid.BreakJointsOnDeath = false

	clone.Name = "Monster_" .. monsterId
	clone:SetAttribute("RuntimeMonster", true)
	clone:SetAttribute("MonsterId", monsterId)
	clone:SetAttribute("SpawnMode", spawnMode)
	clone:SetAttribute("ScoreValue", scoreValue)
	clone:SetAttribute("Peaceful", template:GetAttribute("Peaceful") ~= false)
	clone:SetAttribute("SpawnSurfacePosition", cellRecord.SurfacePosition)
	clone:SetAttribute("SpawnGridX", cellRecord.Cell.X)
	clone:SetAttribute("SpawnGridY", cellRecord.Cell.Y)
	clone:SetAttribute("SpawnGridZ", cellRecord.Cell.Z)
	CollectionService:AddTag(clone, "CombatTarget")

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
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

	local entry = {
		Model = clone,
		Root = root,
		Humanoid = humanoid,
		Island = island,
		Marker = marker,
		ScoreValue = scoreValue,
		DropChance = math.clamp(numberAttribute(template, "DropChance", CONFIG.DEFAULT_DROP_CHANCE), 0, 1),
		DropItemId = template:GetAttribute("DropItemId") or "",
		DeathParticleColor = template:GetAttribute("DeathParticleColor"),
		LastDamager = nil,
	}
	activeMonsters[clone] = entry
	monsterCount += 1

	humanoid.Died:Connect(function()
		if not activeMonsters[clone] then
			return
		end
		unregisterMonster(clone)

		local damager = getRecordedDamager(entry, clone, humanoid)
		if damager then
			awardScore(damager, entry.ScoreValue, clone:GetAttribute("LastSwordScoreMultiplier"))
		end
		if root.Parent then
			createDeathParticles(root, entry.DeathParticleColor)
		end
		if root.Parent and entry.DropItemId ~= "" and random:NextNumber() <= entry.DropChance and island.Parent then
			local lootFolder = island:FindFirstChild("MVPLoot")
			if not lootFolder then
				lootFolder = Instance.new("Folder")
				lootFolder.Name = "MVPLoot"
				lootFolder.Parent = island
			end
			createLoot(lootFolder, root.Position, entry.DropItemId)
		end
		Debris:AddItem(clone, 0.7)
	end)

	clone.Parent = parent
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

local function findNearestMonster(position)
	local nearest = nil
	local nearestDistanceSquared = CONFIG.SWORD_RANGE * CONFIG.SWORD_RANGE
	for model, entry in pairs(activeMonsters) do
		if not model.Parent or not entry.Root.Parent or entry.Humanoid.Health <= 0 then
			unregisterMonster(model)
			continue
		end

		local difference = entry.Root.Position - position
		local distanceSquared = difference:Dot(difference)
		if distanceSquared <= nearestDistanceSquared then
			nearest = entry
			nearestDistanceSquared = distanceSquared
		end
	end
	return nearest
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
	if player then
		entry.Model:SetAttribute("LastDamagedByUserId", player.UserId)
	end
	entry.Humanoid:TakeDamage(math.max(0, damage or 0))
	return true
end

local function containerHasDamageTool(container)
	if not container then
		return false
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and (child.Name == "WoodenSword" or typeof(child:GetAttribute("Damage")) == "number") then
			return true
		end
	end
	return false
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
				local materials = ensureMaterials(player)
				local value = materials:FindFirstChild(entry.ItemId)
				if not value then
					value = Instance.new("IntValue")
					value.Name = entry.ItemId
					value.Parent = materials
				end
				value.Value += 1
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

	if
		island:GetAttribute("CanSpawnMonster") ~= true
		or island:GetAttribute("HasBoss") == true
		or island:FindFirstChild("MonsterSpawnPoints")
		or monsterCount >= CONFIG.MAX_MONSTERS
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
	if not template then
		return 0
	end

	local spawnChance = math.clamp(numberAttribute(template, "SpawnChance", CONFIG.DEFAULT_SPAWN_CHANCE), 0, 1)
	if random:NextNumber() > spawnChance then
		return 0
	end

	local amount, spawnMode, groupMinimum = getSpawnAmount(template, random)
	amount = math.min(amount, CONFIG.MAX_MONSTERS - monsterCount)
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
	pointsFolder.Parent = island

	local monsterFolder = Instance.new("Folder")
	monsterFolder.Name = spawnMode == "Boss" and "MVPBoss" or "MVPMonsters"
	monsterFolder:SetAttribute("SpawnMode", spawnMode)
	monsterFolder:SetAttribute("MonsterId", template:GetAttribute("MonsterId") or template.Name)
	monsterFolder.Parent = island

	local spawned = 0
	for index, cellRecord in ipairs(selectedCells) do
		local marker = createMarker(pointsFolder, cellRecord, index, template, spawnMode)
		local monsterSeed = normalizedSeed(seed + index * 101)
		if spawnClone(template, monsterFolder, island, cellRecord, marker, Random.new(monsterSeed), spawnMode) then
			spawned += 1
		else
			marker:Destroy()
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
