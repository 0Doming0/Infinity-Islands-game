--[[
	Sky Dungeon V10 - ChunkManager

	Um chunk e um round/andar. A agua mantem um buffer de rounds seguros e o
	progresso mediano do grupo funciona como antecipacao secundaria. Um jogador
	isolado no topo nao consegue mais puxar toda a geracao sozinho.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config_SkyDungeon_V10)
local Generator = require(script.Parent.Generator_SkyDungeon_V10_Deterministic)

local ChunkManager = {}

local running = false
local generationBusy = false
local worldModel
local chunksFolder
local chunkCount = 0
local currentEndGrid = Config.START_GRID
local highestGeneratedY = Config.CENTER_WORLD.Y
local baseSeed = 0
local activeChunks = {}
local removedChunkCount = 0
local latestWaterY = Config.CENTER_WORLD.Y - 100000

local function validateConfig()
	assert(Config.INITIAL_CHUNK_COUNT >= 1, "[SkyDungeon] INITIAL_CHUNK_COUNT deve ser >= 1.")
	assert(Config.CHUNK_CHECK_INTERVAL_SECONDS >= 0.25, "[SkyDungeon] Intervalo de verificacao muito baixo.")
	assert(Config.MAX_CHUNKS_PER_CHECK >= 1, "[SkyDungeon] MAX_CHUNKS_PER_CHECK deve ser >= 1.")
	assert(Config.MAX_TOTAL_CHUNKS >= 0, "[SkyDungeon] MAX_TOTAL_CHUNKS deve ser >= 0.")
	assert(Config.ROUND_GENERATION_RETRIES >= 1, "[SkyDungeon] ROUND_GENERATION_RETRIES deve ser >= 1.")
	assert(
		Config.GROUP_PROGRESS_PERCENTILE > 0 and Config.GROUP_PROGRESS_PERCENTILE <= 1,
		"[SkyDungeon] Percentil do grupo deve ficar entre 0 e 1."
	)
end

local function seedForRound(index, attempt)
	local maximumSeed = 2147483647
	local retrySalt = (attempt - 1) * 104729
	local seed = (baseSeed + (index - 1) * Config.CHUNK_SEED_STEP + retrySalt) % maximumSeed
	return seed == 0 and 1 or seed
end

local function getAlivePlayerYs()
	local values = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if rootPart and humanoid and humanoid.Health > 0 then
			table.insert(values, rootPart.Position.Y)
		end
	end
	table.sort(values)
	return values
end

local function getGroupProgressY()
	local values = getAlivePlayerYs()
	if #values == 0 then
		return nil
	end
	local index = math.clamp(math.ceil(#values * Config.GROUP_PROGRESS_PERCENTILE), 1, #values)
	return values[index]
end

local function reachedChunkLimit()
	return Config.MAX_TOTAL_CHUNKS > 0 and chunkCount >= Config.MAX_TOTAL_CHUNKS
end

local function countActiveChunks()
	local count = 0
	for _ in pairs(activeChunks) do
		count += 1
	end
	return count
end

local function getLowestActiveChunkIndex()
	local lowest
	for index in pairs(activeChunks) do
		lowest = lowest and math.min(lowest, index) or index
	end
	return lowest
end

local function countRoundsAbove(referenceY)
	local count = 0
	for _, record in pairs(activeChunks) do
		if record.TopWorldY > referenceY then
			count += 1
		end
	end
	return count
end

local function updateWorldAttributes()
	if not worldModel then
		return
	end
	worldModel:SetAttribute("ChunkCount", chunkCount)
	worldModel:SetAttribute("RoundCount", chunkCount)
	worldModel:SetAttribute("ActiveChunkCount", countActiveChunks())
	worldModel:SetAttribute("ActiveRoundCount", countActiveChunks())
	worldModel:SetAttribute("RemovedChunkCount", removedChunkCount)
	worldModel:SetAttribute("LowestActiveChunkIndex", getLowestActiveChunkIndex() or 0)
	worldModel:SetAttribute("HighestGeneratedY", highestGeneratedY)
	worldModel:SetAttribute("CurrentEndGrid", currentEndGrid)
	worldModel:SetAttribute("LatestWaterY", latestWaterY)
end

local function hasAlivePlayerInside(record)
	local margin = Config.GRID_SIZE
	for _, playerY in ipairs(getAlivePlayerYs()) do
		if playerY >= record.BottomWorldY - margin and playerY <= record.TopWorldY + margin then
			return true
		end
	end
	return false
end

local function generateNextChunk(reason)
	if generationBusy or reachedChunkLimit() then
		return false
	end
	generationBusy = true
	local nextIndex = chunkCount + 1
	local chunkName = string.format("Chunk_%03d", nextIndex)
	local generatedModel
	local metadata
	local lastError

	for attempt = 1, Config.ROUND_GENERATION_RETRIES do
		local succeeded, resultModel, resultMetadata = xpcall(function()
			return Generator.Generate(chunksFolder, {
				ChunkIndex = nextIndex,
				RoundIndex = nextIndex,
				ModelName = chunkName,
				StartGrid = currentEndGrid,
				Seed = seedForRound(nextIndex, attempt),
				ReuseStartBlock = nextIndex > 1,
				ReplaceExisting = false,
			})
		end, debug.traceback)
		if succeeded then
			generatedModel = resultModel
			metadata = resultMetadata
			break
		end
		lastError = resultModel
		warn(string.format("[SkyDungeon] Tentativa %d falhou em %s: %s", attempt, chunkName, tostring(lastError)))
	end

	if not generatedModel then
		generationBusy = false
		warn(
			string.format("[SkyDungeon] Nao foi possivel gerar %s apos os retries.\n%s", chunkName, tostring(lastError))
		)
		return false
	end

	chunkCount = nextIndex
	currentEndGrid = metadata.EndGrid
	highestGeneratedY = metadata.TopWorldY
	activeChunks[nextIndex] = {
		Model = generatedModel,
		BottomWorldY = metadata.BottomWorldY,
		TopWorldY = metadata.TopWorldY,
		Archetype = metadata.RoundArchetype,
		Seed = metadata.Seed,
	}
	generatedModel:SetAttribute("PreviousChunk", nextIndex > 1 and string.format("Chunk_%03d", nextIndex - 1) or "None")
	generatedModel:SetAttribute("GenerationReason", reason or "Unknown")
	CollectionService:AddTag(generatedModel, "BlockParkourChunk")
	CollectionService:AddTag(generatedModel, "SkyDungeonRound")
	updateWorldAttributes()
	generationBusy = false
	print(
		string.format(
			"[SkyDungeon] Round %d pronto (%s) | Topo %.1f | Motivo: %s",
			nextIndex,
			tostring(metadata.RoundArchetype),
			highestGeneratedY,
			reason or "Unknown"
		)
	)
	return true
end

local function prepareWorld()
	local oldWorld = workspace:FindFirstChild(Config.WORLD_MODEL_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end
	local oldSingleMap = workspace:FindFirstChild(Config.MODEL_NAME)
	if oldSingleMap then
		oldSingleMap:Destroy()
	end

	worldModel = Instance.new("Model")
	worldModel.Name = Config.WORLD_MODEL_NAME
	worldModel:SetAttribute("DynamicChunksEnabled", true)
	worldModel:SetAttribute("GenerationUnit", "Round")
	worldModel:SetAttribute("GenerationMode", "WaterBufferAndGroupMedian")
	worldModel:SetAttribute("GridSize", Config.GRID_SIZE)
	worldModel:SetAttribute("BaseSeed", baseSeed)
	worldModel.Parent = workspace

	chunksFolder = Instance.new("Folder")
	chunksFolder.Name = "Chunks"
	chunksFolder.Parent = worldModel
	updateWorldAttributes()
end

function ChunkManager.Start()
	if running then
		warn("[SkyDungeon] ChunkManager ja esta em execucao.")
		return
	end
	validateConfig()
	if not Config.ENABLE_DYNAMIC_CHUNKS then
		Generator.Generate(workspace)
		return
	end

	running = true
	baseSeed = Config.SEED or (os.time() % 2147483647)
	currentEndGrid = Config.START_GRID
	highestGeneratedY = Config.CENTER_WORLD.Y
	chunkCount = 0
	activeChunks = {}
	removedChunkCount = 0
	latestWaterY = Config.CENTER_WORLD.Y - 100000
	prepareWorld()

	for _ = 1, Config.INITIAL_CHUNK_COUNT do
		if not generateNextChunk("InitialBuffer") then
			break
		end
	end

	task.spawn(function()
		while running do
			task.wait(Config.CHUNK_CHECK_INTERVAL_SECONDS)
			if Config.ENABLE_GROUP_PROGRESS_GENERATION then
				local groupY = getGroupProgressY()
				if groupY and highestGeneratedY - groupY <= Config.GROUP_GENERATE_AHEAD_STUDS then
					local roundsAhead = countRoundsAbove(groupY)
					if roundsAhead <= Config.MAX_ROUNDS_AHEAD_OF_GROUP then
						generateNextChunk("GroupMedian")
					end
				end
			end
		end
	end)

	print(string.format("[SkyDungeon] Torre iniciada | Seed base %d | %d rounds prontos", baseSeed, chunkCount))
end

-- API principal da agua: mantem N rounds inteiros acima da zona de seguranca.
function ChunkManager.EnsureRoundsAheadOfWater(waterSurfaceY, desiredRounds, maximumRounds)
	if not running then
		return false, 0, highestGeneratedY, chunkCount
	end
	latestWaterY = waterSurfaceY
	local desired = math.max(1, math.floor(desiredRounds or 2))
	local limit = math.max(1, math.floor(maximumRounds or Config.MAX_CHUNKS_PER_CHECK))
	local safetyLine = waterSurfaceY + Config.GROUP_GENERATE_AHEAD_STUDS
	local safeRounds = countRoundsAbove(safetyLine)
	local generatedNow = 0
	while safeRounds < desired and generatedNow < limit and not reachedChunkLimit() do
		if not generateNextChunk("WaterApproaching") then
			break
		end
		generatedNow += 1
		safeRounds = countRoundsAbove(safetyLine)
	end
	updateWorldAttributes()
	return safeRounds >= desired, safeRounds, highestGeneratedY, chunkCount
end

-- Compatibilidade: gera rounds completos ate cobrir a altura solicitada.
function ChunkManager.EnsureGeneratedThrough(targetWorldY, maximumChunks)
	if not running or generationBusy then
		return false, highestGeneratedY, chunkCount
	end
	local limit = maximumChunks or Config.MAX_CHUNKS_PER_CHECK
	local generatedNow = 0
	while highestGeneratedY < targetWorldY and generatedNow < limit and not reachedChunkLimit() do
		if not generateNextChunk("HeightCompatibility") then
			break
		end
		generatedNow += 1
	end
	return highestGeneratedY >= targetWorldY, highestGeneratedY, chunkCount
end

function ChunkManager.GetRoundStatus(referenceY)
	local currentRound = 0
	local safeRounds = 0
	for index = 1, chunkCount do
		local record = activeChunks[index]
		if record then
			if referenceY >= record.BottomWorldY and referenceY <= record.TopWorldY then
				currentRound = index
			end
			if record.TopWorldY > referenceY then
				safeRounds += 1
			end
		end
	end
	return {
		CurrentRound = currentRound,
		GeneratedRounds = chunkCount,
		ActiveRounds = countActiveChunks(),
		SafeRoundsAhead = safeRounds,
		HighestGeneratedY = highestGeneratedY,
		GroupProgressY = getGroupProgressY(),
	}
end

function ChunkManager.GetHighestGeneratedY()
	return highestGeneratedY
end

function ChunkManager.GetGroupProgressY()
	return getGroupProgressY()
end

function ChunkManager.CleanupBelowWater(waterSurfaceY, marginStuds, minimumActiveChunks)
	if not running or generationBusy or not worldModel then
		return 0, countActiveChunks()
	end
	latestWaterY = waterSurfaceY
	local safeMargin = math.max(0, marginStuds or 0)
	local minimumToKeep = math.max(1, math.floor(minimumActiveChunks or Config.MIN_ACTIVE_CHUNKS))
	local activeCount = countActiveChunks()
	local removedNow = 0

	for index = 1, chunkCount do
		if activeCount <= minimumToKeep then
			break
		end
		local record = activeChunks[index]
		if record and record.TopWorldY + safeMargin < waterSurfaceY and not hasAlivePlayerInside(record) then
			if record.Model and record.Model.Parent then
				record.Model:Destroy()
			end
			activeChunks[index] = nil
			activeCount -= 1
			removedNow += 1
			removedChunkCount += 1
		end
	end
	if removedNow > 0 then
		updateWorldAttributes()
		print(string.format("[SkyDungeon] Agua removeu %d round(s) | %d ativos", removedNow, activeCount))
	end
	return removedNow, activeCount
end

function ChunkManager.GetWorldModel()
	return worldModel
end

function ChunkManager.IsRunning()
	return running
end

function ChunkManager.Stop()
	running = false
end

return ChunkManager
