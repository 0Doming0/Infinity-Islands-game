--[[
	Sky Dungeon - CollectibleService

	Gera coletaveis de pontuacao nas celulas internas das ilhas e tambem nos
	blocos das rotas. Nao cria moedas. Toda recompensa passa pelo ScoreService e
	recebe o multiplicador da espada equipada.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

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
		Small = 3,
		Medium = 5,
		Large = 7,
	},
	ISLAND_MIN_SPACING_STUDS = 7,

	MAIN_ROUTE_CHANCE = 0.34,
	BRANCH_ROUTE_CHANCE = 0.24,
	ROUTE_MIN_PER_ROUND = 6,
	ROUTE_MAX_PER_ROUND = 12,
	ROUTE_MIN_SPACING_STUDS = 9,
}

local DEFINITIONS = {
	{
		Id = "BlueCrystal",
		Color = Color3.fromRGB(48, 170, 255),
		Size = Vector3.new(2.2, 2.8, 2.2),
		Shape = Enum.PartType.Block,
		Score = 25,
		Weight = 55,
	},
	{
		Id = "GoldenOrb",
		Color = Color3.fromRGB(255, 196, 45),
		Size = Vector3.new(2.5, 2.5, 2.5),
		Shape = Enum.PartType.Ball,
		Score = 50,
		Weight = 30,
	},
	{
		Id = "RubyShard",
		Color = Color3.fromRGB(235, 55, 92),
		Size = Vector3.new(1.6, 3.2, 1.6),
		Shape = Enum.PartType.Block,
		Score = 100,
		Weight = 15,
	},
}

local CollectibleService = {}
local started = false
local active = {}

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

local function chooseDefinition(random)
	local totalWeight = 0
	for _, definition in ipairs(DEFINITIONS) do
		totalWeight += definition.Weight
	end
	local roll = random:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, definition in ipairs(DEFINITIONS) do
		accumulated += definition.Weight
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

local function breakCollectible(part, definition)
	part.Transparency = 1
	part.CanQuery = false

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(definition.Color)
	particles.LightEmission = 0.8
	particles.Lifetime = NumberRange.new(0.25, 0.45)
	particles.Speed = NumberRange.new(7, 12)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Drag = 5
	particles.Rate = 0
	particles.Parent = part
	particles:Emit(18)

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.55
	sound.RollOffMaxDistance = 45
	sound.Parent = part
	sound:Play()
	Debris:AddItem(part, 0.65)
end

local function createCollectible(parent, surfacePosition, definition, sourceName)
	local part = Instance.new("Part")
	part.Name = definition.Id
	part.Size = definition.Size
	part.Shape = definition.Shape
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = definition.Color
	part.CFrame = CFrame.new(
		surfacePosition + Vector3.new(0, definition.Size.Y / 2 + CONFIG.FLOAT_HEIGHT, 0)
	)
	if definition.Id == "BlueCrystal" then
		part.CFrame *= CFrame.Angles(0, math.rad(45), math.rad(45))
	elseif definition.Id == "RubyShard" then
		part.CFrame *= CFrame.Angles(0, 0, math.rad(45))
	end
	part:SetAttribute("IsScoreCollectible", true)
	part:SetAttribute("CollectibleId", definition.Id)
	part:SetAttribute("ScoreValue", definition.Score)
	part:SetAttribute("CollectibleSource", sourceName)
	part:SetAttribute("Claimed", false)
	part.Parent = parent

	active[part] = {
		Definition = definition,
		Claimed = false,
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
	if island:GetAttribute("CanSpawnItem") ~= true then
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
	for _, cell in ipairs(freeCells) do
		if created >= desiredCount then
			break
		end
		if isFarEnough(cell.SurfacePosition, selectedPositions, CONFIG.ISLAND_MIN_SPACING_STUDS) then
			createCollectible(folder, cell.SurfacePosition, chooseDefinition(random), "Island")
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

	local function trySelect(part, requireChance)
		if #selectedParts >= CONFIG.ROUTE_MAX_PER_ROUND or selectedSet[part] then
			return false
		end
		if not isFarEnough(part.Position, selectedPositions, CONFIG.ROUTE_MIN_SPACING_STUDS) then
			return false
		end
		if requireChance then
			local chance = part:GetAttribute("PathType") == "MainRoute"
				and CONFIG.MAIN_ROUTE_CHANCE
				or CONFIG.BRANCH_ROUTE_CHANCE
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
	if #selectedParts < CONFIG.ROUTE_MIN_PER_ROUND then
		for _, part in ipairs(candidates) do
			if #selectedParts >= CONFIG.ROUTE_MIN_PER_ROUND then
				break
			end
			trySelect(part, false)
		end
	end

	for _, part in ipairs(selectedParts) do
		local surfacePosition = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
		createCollectible(folder, surfacePosition, chooseDefinition(random), "Route")
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
	if entry.Claimed or not part.Parent then
		return
	end
	entry.Claimed = true
	part:SetAttribute("Claimed", true)
	local awarded = ScoreService.Award(player, entry.Definition.Score, "Collectible:" .. entry.Definition.Id)
	if awarded <= 0 then
		entry.Claimed = false
		part:SetAttribute("Claimed", false)
		return
	end
	active[part] = nil
	breakCollectible(part, entry.Definition)
end

local function proximityPass()
	local radiusSquared = CONFIG.CLAIM_RADIUS * CONFIG.CLAIM_RADIUS
	for part, entry in pairs(active) do
		if not part.Parent then
			active[part] = nil
			continue
		end
		local closestPlayer
		local closestDistanceSquared = radiusSquared
		for _, player in ipairs(Players:GetPlayers()) do
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
