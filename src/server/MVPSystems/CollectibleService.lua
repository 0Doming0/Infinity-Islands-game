--[[
	Sky Dungeon - CollectibleService

	Gera coletaveis pequenos de pontuacao e moeda nas ilhas e rotas.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local generatorModule = script.Parent:FindFirstChild("Generator_SkyDungeon_V10_Deterministic")
if not generatorModule then
	local blockParkour = script:FindFirstAncestor("BlockParkour")
		or ServerScriptService:FindFirstChild("BlockParkour")
	if blockParkour then
		generatorModule = blockParkour:FindFirstChild("Generator_SkyDungeon_V10_Deterministic")
	end
end

assert(
	generatorModule and generatorModule:IsA("ModuleScript"),
	"[SkyDungeon] Generator_SkyDungeon_V10_Deterministic nao encontrado em BlockParkour."
)

local Generator = require(generatorModule)
local ScoreService = require(script.Parent.Parent:FindFirstChild("BlockParkour"):FindFirstChild("ScoreService_SkyDungeon_V10"))

local CONFIG = {
	CHECK_INTERVAL = 0.15,
	CLAIM_RADIUS = 4.75,
	FLOAT_HEIGHT = 0.45,
	RANDOM_SALT = 486187739,

	ISLAND_COUNT = {
		Small = 1,
		Medium = 2,
		Large = 3,
	},
	ISLAND_SPAWN_CHANCE = 0.58,
	ISLAND_MIN_SPACING_STUDS = 12,

	MAIN_ROUTE_CHANCE = 0.12,
	BRANCH_ROUTE_CHANCE = 0.08,
	ROUTE_MIN_PER_ROUND = 2,
	ROUTE_MAX_PER_ROUND = 5,
	ROUTE_MIN_SPACING_STUDS = 14,
}

local DEFINITIONS = {
	{
		Id = "BlueCrystal",
		Color = Color3.fromRGB(48, 170, 255),
		Size = Vector3.new(2.2, 2.8, 2.2),
		Shape = Enum.PartType.Block,
		Score = 1,
		Coins = 1,
		Weight = 55,
	},
	{
		Id = "GoldenOrb",
		Color = Color3.fromRGB(255, 196, 45),
		Size = Vector3.new(2.5, 2.5, 2.5),
		Shape = Enum.PartType.Ball,
		Score = 2,
		Coins = 2,
		Weight = 30,
	},
	{
		Id = "RubyShard",
		Color = Color3.fromRGB(235, 55, 92),
		Size = Vector3.new(1.6, 3.2, 1.6),
		Shape = Enum.PartType.Block,
		Score = 3,
		Coins = 4,
		Weight = 15,
	},
}

local CollectibleService = {}
local started = false
local active = {}
local templateCache = {}
local warnedTemplates = {}

local DEFAULT_COLLECT_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local PROCEDURAL_BONE_NAME = "Bone"
local PROCEDURAL_ANIMATION_DRIVER = "ProceduralBlender"
local ROBLOX_ANIMATION_DRIVER = "RobloxAnimator"

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % 2147483647
	return seed == 0 and 1 or seed
end

local function shuffle(random, source)
	local result = table.clone(source)
	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

local function chooseDefinition(random, preferValuable)
	local totalWeight = 0
	for _, definition in ipairs(DEFINITIONS) do
		local valueBias = preferValuable and (0.55 + definition.Coins * 0.28) or 1
		totalWeight += definition.Weight * valueBias
	end
	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, definition in ipairs(DEFINITIONS) do
		local valueBias = preferValuable and (0.55 + definition.Coins * 0.28) or 1
		accumulated += definition.Weight * valueBias
		if roll <= accumulated then
			return definition
		end
	end
	return DEFINITIONS[#DEFINITIONS]
end

local function isFarEnough(position, selectedPositions, minimumDistance)
	for _, selected in ipairs(selectedPositions) do
		if (position - selected).Magnitude < minimumDistance then
			return false
		end
	end
	return true
end

local function warnTemplate(definition, message)
	if warnedTemplates[definition.Id] then
		return
	end
	warnedTemplates[definition.Id] = true
	warn(string.format("[CollectibleService] %s: %s; usando visual de fallback.", definition.Id, message))
end

local function hasBasePart(instance)
	return instance:IsA("BasePart") or instance:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function usesProceduralBlenderAnimation(instance)
	local bone = instance:FindFirstChild(PROCEDURAL_BONE_NAME, true)
	return bone ~= nil and bone:IsA("Bone")
end

local function findVisualTemplate(definition)
	local cached = templateCache[definition.Id]
	if cached ~= nil then
		return cached or nil
	end

	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local folder = assets and assets:FindFirstChild("Collectibles")
	if not folder or not folder:IsA("Folder") then
		templateCache[definition.Id] = false
		return nil
	end

	local byName
	for _, candidate in ipairs(folder:GetChildren()) do
		if candidate:GetAttribute("CollectibleId") == definition.Id then
			byName = candidate
			break
		elseif candidate.Name == definition.Id then
			byName = candidate
		end
	end

	if not byName then
		templateCache[definition.Id] = false
		return nil
	end
	if byName:GetAttribute("Enabled") == false then
		templateCache[definition.Id] = false
		return nil
	end
	if not (byName:IsA("Model") or byName:IsA("BasePart")) or not hasBasePart(byName) then
		warnTemplate(definition, "o template precisa ser Model ou BasePart e conter ao menos uma BasePart")
		templateCache[definition.Id] = false
		return nil
	end

	templateCache[definition.Id] = byName
	return byName
end

local function prepareVisual(instance)
	local rootPart

	if instance:IsA("Model") then
		rootPart = instance.PrimaryPart
			or instance:FindFirstChild("HumanoidRootPart", true)
			or instance:FindFirstChild("RootPart", true)
			or instance:FindFirstChildWhichIsA("BasePart", true)
	elseif instance:IsA("BasePart") then
		rootPart = instance
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = true

		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = descendant ~= rootPart

			-- Somente a peça raiz deve permanecer ancorada.
			descendant.Anchored = descendant == rootPart
		end
	end

	if instance:IsA("BasePart") then
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.Anchored = true
	end

	if instance:IsA("Model") and rootPart then
		instance.PrimaryPart = rootPart
	end
end

local function createFallbackVisual(definition)
	local part = Instance.new("Part")
	part.Name = "Visual"
	part.Size = definition.Size
	part.Shape = definition.Shape
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = definition.Color
	if definition.Id == "BlueCrystal" then
		part.CFrame = CFrame.Angles(0, math.rad(45), math.rad(45))
	elseif definition.Id == "RubyShard" then
		part.CFrame = CFrame.Angles(0, 0, math.rad(45))
	end
	return part
end

local function hideRuntime(runtime)
	for _, descendant in ipairs(runtime:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanQuery = false
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = false
		end
	end
end

local function playCollectibleAnimation(runtime)
	if not runtime or not runtime:IsDescendantOf(workspace) then
		warn("[CollectibleAnimation] Runtime inválido ou fora do Workspace")
		return nil
	end

	local controller = runtime:FindFirstChildWhichIsA(
		"AnimationController",
		true
	)

	if not controller then
		warn(
			"[CollectibleAnimation] AnimationController não encontrado:",
			runtime:GetFullName()
		)
		return nil
	end

	local animator = controller:FindFirstChildWhichIsA("Animator", true)

	if not animator then
		animator = Instance.new("Animator")
		animator.Name = "Animator"
		animator.Parent = controller
	end

	local animation = runtime:FindFirstChild("MainAnimation", true)

	if not animation or not animation:IsA("Animation") then
		warn(
			"[CollectibleAnimation] MainAnimation inválida:",
			runtime:GetFullName()
		)
		return nil
	end

	if animation.AnimationId == "" then
		warn("[CollectibleAnimation] AnimationId vazio")
		return nil
	end

	local success, trackOrError = pcall(function()
		return controller:LoadAnimation(animation)
	end)

	if not success then
		warn(
			"[CollectibleAnimation] Erro ao carregar:",
			trackOrError
		)
		return nil
	end

	local track = trackOrError

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.1, 1, 1)

	task.delay(1, function()
		if not track then
			return
		end

		print(
			"[CollectibleAnimation]",
			"modelo =", runtime:GetFullName(),
			"id =", animation.AnimationId,
			"length =", track.Length,
			"playing =", track.IsPlaying,
			"weight =", track.WeightCurrent
		)

		if track.Length <= 0 then
			warn(
				"[CollectibleAnimation] A animação foi carregada,",
				"mas continua com duração 0."
			)
		end
	end)

	return track
end

local function breakCollectible(part, entry)
	hideRuntime(entry.Runtime)
	part.Transparency = 1
	part.CanQuery = false

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(entry.ParticleColor)
	particles.LightEmission = 0.8
	particles.Lifetime = NumberRange.new(0.25, 0.45)
	particles.Speed = NumberRange.new(7, 12)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Drag = 5
	particles.Rate = 0
	particles.Parent = part
	particles:Emit(18)

	local sound = Instance.new("Sound")
	sound.SoundId = entry.CollectSoundId
	sound.Volume = 0.55
	sound.RollOffMaxDistance = 45
	sound.Parent = part
	sound:Play()
	Debris:AddItem(entry.Runtime, 0.65)
end

local function createCollectible(parent, surfacePosition, definition, sourceName, targetUserId)
	local runtime = Instance.new("Model")
	runtime.Name = definition.Id

	local AnimeOutline = require(
	    ServerScriptService.MVPSystems.AnimeOutline
    )
	local template = findVisualTemplate(definition)
	local visual
	if template then
		local success, result = pcall(template.Clone, template)
		if success and result then
			visual = result
			visual.Name = "Visual"
		else
			warnTemplate(definition, "nao foi possivel clonar o template")
		end
	end
	visual = visual or createFallbackVisual(definition)
	prepareVisual(visual)
	visual.Parent = runtime

	-- Move apenas a posicao do clone para preservar a orientacao configurada no
	-- Studio, independentemente da PrimaryPart ou do pivot escolhido no template.
	local boundingBox, boundingSize = runtime:GetBoundingBox()
	local targetBottomY = surfacePosition.Y + CONFIG.FLOAT_HEIGHT
	local translation = Vector3.new(
		surfacePosition.X - boundingBox.Position.X,
		targetBottomY - (boundingBox.Position.Y - boundingSize.Y / 2),
		surfacePosition.Z - boundingBox.Position.Z
	)
	runtime:PivotTo(runtime:GetPivot() + translation)
	boundingBox, boundingSize = runtime:GetBoundingBox()

	local part = Instance.new("Part")
	part.Name = "CollectibleHitbox"
	part.Size = Vector3.one
	part.CFrame = CFrame.new(
		boundingBox.Position.X,
		targetBottomY + math.min(2.5, boundingSize.Y / 2),
		boundingBox.Position.Z
	)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = runtime
	runtime.PrimaryPart = part

	for _, instance in ipairs({ runtime, part }) do
		instance:SetAttribute("IsScoreCollectible", true)
		instance:SetAttribute("CollectibleId", definition.Id)
		instance:SetAttribute("ScoreValue", definition.Score)
		instance:SetAttribute("CoinValue", definition.Coins)
		instance:SetAttribute("CollectibleSource", sourceName)
		instance:SetAttribute("Claimed", false)
	end
	runtime:SetAttribute("UsesCustomModel", template ~= nil)
	local usesProceduralAnimation = usesProceduralBlenderAnimation(runtime)
	runtime:SetAttribute(
		"CollectibleAnimationDriver",
		usesProceduralAnimation and PROCEDURAL_ANIMATION_DRIVER or ROBLOX_ANIMATION_DRIVER
	)
	runtime:SetAttribute("UseBlenderProceduralAnimation", usesProceduralAnimation)
	if typeof(targetUserId) == "number" then
		runtime:SetAttribute("TutorialTargetUserId", targetUserId)
		part:SetAttribute("TutorialTargetUserId", targetUserId)
	end
	runtime.Parent = parent
	if not usesProceduralAnimation then
		playCollectibleAnimation(runtime)
	end
	AnimeOutline.Apply(runtime)
	local particleColor = template and template:GetAttribute("ParticleColor")
	local collectSoundId = template and template:GetAttribute("CollectSoundId")
	active[part] = {
		Definition = definition,
		Claimed = false,
		Runtime = runtime,
		ParticleColor = typeof(particleColor) == "Color3" and particleColor or definition.Color,
		CollectSoundId = typeof(collectSoundId) == "string" and collectSoundId ~= ""
			and collectSoundId
			or DEFAULT_COLLECT_SOUND_ID,
		TargetUserId = targetUserId,
	}
	return part
end

local function addCollectibleMarker(island, cell)
	local points = island:FindFirstChild("CollectiblePoints")
	if not points then
		points = Instance.new("Folder")
		points.Name = "CollectiblePoints"
		points.Parent = island
	end
	local marker = Instance.new("Vector3Value")
	marker.Name = string.format("Point_%03d", #points:GetChildren() + 1)
	marker.Value = cell.WorldPosition
	marker:SetAttribute("GridX", cell.Cell.X)
	marker:SetAttribute("GridY", cell.Cell.Y)
	marker:SetAttribute("GridZ", cell.Cell.Z)
	marker.Parent = points
end

local function populateIsland(island, random)
	if island:GetAttribute("CanSpawnItem") ~= true
		or island:GetAttribute("SoloMerchantReserved") == true
	then
		return 0
	end
	local chanceMultiplier = math.max(0, tonumber(island:GetAttribute("CollectibleChanceMultiplier")) or 1)
	if random:NextNumber() > math.clamp(CONFIG.ISLAND_SPAWN_CHANCE * chanceMultiplier, 0, 1) then
		island:SetAttribute("ScoreCollectibleCount", 0)
		return 0
	end
	local desiredCount = CONFIG.ISLAND_COUNT[island:GetAttribute("TerrainSize")] or 3
	local freeCells = shuffle(random, Generator.GetFreeCells(island))
	if #freeCells == 0 then
		return 0
	end

	local content = island:FindFirstChild("MVPContent")
	if not content then
		return 0
	end
	local folder = Instance.new("Folder")
	folder.Name = "ScoreCollectibles"
	folder.Parent = content
	local selectedPositions = {}
	local created = 0
	local hasMonsters = island:FindFirstChild("MonsterSpawnPoints") ~= nil
	for _, cell in ipairs(freeCells) do
		if created >= desiredCount then
			break
		end
		if isFarEnough(cell.SurfacePosition, selectedPositions, CONFIG.ISLAND_MIN_SPACING_STUDS) then
			createCollectible(folder, cell.SurfacePosition, chooseDefinition(random, hasMonsters), "Island")
			addCollectibleMarker(island, cell)
			table.insert(selectedPositions, cell.SurfacePosition)
			created += 1
		end
	end
	if created == 0 then
		folder:Destroy()
	end
	island:SetAttribute("ScoreCollectibleCount", created)
	return created
end

local function getRouteParts(chunk)
	local parts = {}
	for _, descendant in ipairs(chunk:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("IsRoundConnector") == true then
			table.insert(parts, descendant)
		end
	end
	table.sort(parts, function(left, right)
		return left.Name < right.Name
	end)
	return parts
end

local function populateRoutes(chunk, random)
	local candidates = shuffle(random, getRouteParts(chunk))
	if #candidates == 0 then
		return 0
	end
	local folder = Instance.new("Folder")
	folder.Name = "RouteScoreCollectibles"
	folder.Parent = chunk
	local selectedParts = {}
	local selectedPositions = {}
	local selectedSet = {}
	local chanceMultiplier = math.max(0, tonumber(chunk:GetAttribute("CollectibleChanceMultiplier")) or 1)
	local minimumPerRound = math.max(1, math.floor(CONFIG.ROUTE_MIN_PER_ROUND * chanceMultiplier + 0.5))
	local maximumPerRound = math.max(minimumPerRound, math.floor(CONFIG.ROUTE_MAX_PER_ROUND * chanceMultiplier + 0.5))

	local function trySelect(part, requireChance)
		if #selectedParts >= maximumPerRound or selectedSet[part] then
			return false
		end
		if not isFarEnough(part.Position, selectedPositions, CONFIG.ROUTE_MIN_SPACING_STUDS) then
			return false
		end
		if requireChance then
			local chance = part:GetAttribute("PathType") == "MainRoute"
				and CONFIG.MAIN_ROUTE_CHANCE
				or CONFIG.BRANCH_ROUTE_CHANCE
			chance = math.clamp(chance * chanceMultiplier, 0, 1)
			if random:NextNumber() > chance then
				return false
			end
		end
		selectedSet[part] = true
		table.insert(selectedParts, part)
		table.insert(selectedPositions, part.Position)
		return true
	end

	for _, part in ipairs(candidates) do
		trySelect(part, true)
	end
	if #selectedParts < minimumPerRound then
		for _, part in ipairs(candidates) do
			if #selectedParts >= minimumPerRound then
				break
			end
			trySelect(part, false)
		end
	end

	for _, part in ipairs(selectedParts) do
		local surfacePosition = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
		local optionalPath = part:GetAttribute("PathType") ~= "MainRoute"
		createCollectible(folder, surfacePosition, chooseDefinition(random, optionalPath), "Route")
	end
	if #selectedParts == 0 then
		folder:Destroy()
	end
	chunk:SetAttribute("RouteScoreCollectibleCount", #selectedParts)
	return #selectedParts
end

local function processChunk(chunk)
	if not chunk.Parent or chunk:GetAttribute("ScoreCollectiblesProcessed") == true then
		return
	end
	chunk:SetAttribute("ScoreCollectiblesProcessed", true)
	local chunkSeed = normalizedSeed((chunk:GetAttribute("Seed") or 1) + CONFIG.RANDOM_SALT)
	local routeRandom = Random.new(chunkSeed)
	local routeCount = populateRoutes(chunk, routeRandom)
	local islandCount = 0
	local terrainAreas = chunk:FindFirstChild("TerrainAreas")
	if terrainAreas then
		local islands = terrainAreas:GetChildren()
		table.sort(islands, function(left, right)
			return left.Name < right.Name
		end)
		for _, island in ipairs(islands) do
			if island:IsA("Model") and island:GetAttribute("IsSkyIsland") == true then
				local islandSeed = normalizedSeed((island:GetAttribute("IslandSeed") or 1) + CONFIG.RANDOM_SALT)
				islandCount += populateIsland(island, Random.new(islandSeed))
			end
		end
	end
	chunk:SetAttribute("IslandScoreCollectibleCount", islandCount)
	chunk:SetAttribute("TotalScoreCollectibleCount", islandCount + routeCount)
	print(
		string.format(
			"[SkyDungeon] %s recebeu %d coletaveis nas ilhas e %d nas rotas.",
			chunk.Name,
			islandCount,
			routeCount
		)
	)
end

local function tryClaim(part, entry, player)
	if entry.Claimed or not part.Parent or not entry.Runtime.Parent then
		return
	end
	entry.Claimed = true
	part:SetAttribute("Claimed", true)
	entry.Runtime:SetAttribute("Claimed", true)
	local scoreAwarded, coinsAwarded = ScoreService.AwardRewards(
		player,
		entry.Definition.Score,
		entry.Definition.Coins,
		"Collectible:" .. entry.Definition.Id
	)
	if scoreAwarded <= 0 and coinsAwarded <= 0 then
		entry.Claimed = false
		part:SetAttribute("Claimed", false)
		entry.Runtime:SetAttribute("Claimed", false)
		return
	end
	active[part] = nil
	breakCollectible(part, entry)
end

local function proximityPass()
	local radiusSquared = CONFIG.CLAIM_RADIUS * CONFIG.CLAIM_RADIUS
	for part, entry in pairs(active) do
		if not part.Parent or not entry.Runtime.Parent then
			active[part] = nil
			continue
		end
		local closestPlayer
		local closestDistanceSquared = radiusSquared
		for _, player in ipairs(Players:GetPlayers()) do
			if entry.TargetUserId and player.UserId ~= entry.TargetUserId then
				continue
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root then
				local difference = root.Position - part.Position
				local distanceSquared = difference:Dot(difference)
				if distanceSquared <= closestDistanceSquared then
					closestDistanceSquared = distanceSquared
					closestPlayer = player
				end
			end
		end
		if closestPlayer then
			tryClaim(part, entry, closestPlayer)
		end
	end
end

function CollectibleService.RemoveTutorialCollectible(player)
	for part, entry in pairs(active) do
		if entry.TargetUserId == player.UserId then
			active[part] = nil
			if entry.Runtime.Parent then
				entry.Runtime:Destroy()
			end
		end
	end
end

function CollectibleService.EnsureTutorialCollectible(player, surfacePosition)
	if not player or player.Parent ~= Players or typeof(surfacePosition) ~= "Vector3" then
		return nil
	end
	CollectibleService.RemoveTutorialCollectible(player)
	local folder = workspace:FindFirstChild("TutorialRuntime")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TutorialRuntime"
		folder.Parent = workspace
	end
	local part = createCollectible(folder, surfacePosition, DEFINITIONS[1], "Tutorial", player.UserId)
	return part, active[part] and active[part].Runtime or nil
end

function CollectibleService.Start()
	if started then
		return
	end
	started = true
	CollectionService:GetInstanceAddedSignal("SkyDungeonRound"):Connect(processChunk)
	for _, chunk in ipairs(CollectionService:GetTagged("SkyDungeonRound")) do
		processChunk(chunk)
	end
	task.spawn(function()
		while started do
			task.wait(CONFIG.CHECK_INTERVAL)
			proximityPass()
		end
	end)
end

return CollectibleService
