--[[
	BlockParkour MVP - IslandContentService

	Descobre as Terrain_* geradas e oferece uma grade reservavel aos quatro sistemas.
	A rota principal e sua celula-ancora nunca sao oferecidas como livres.
]]

local CollectionService = game:GetService("CollectionService")

local IslandContentService = {}

local CHUNK_TAG = "BlockParkourChunk"
local ISLAND_TAG = "BlockParkourIsland"
local MAX_SEED = 2147483647

local started = false
local islandsByModel = {}
local observers = {}

local function cellKey(x, y, z)
	return string.format("%d,%d,%d", x, y, z)
end

local function readCell(part)
	local x = part:GetAttribute("GridX")
	local y = part:GetAttribute("GridY")
	local z = part:GetAttribute("GridZ")
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function findTerrainAnchor(chunk, terrainId)
	local routeFolder = chunk:FindFirstChild("MainRoute")
	if not routeFolder then
		return nil
	end
	for _, part in ipairs(routeFolder:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("TerrainId") == terrainId then
			return part
		end
	end
	return nil
end

local function notifyAdded(record)
	for _, callback in ipairs(observers) do
		task.spawn(callback, record)
	end
end

local function unregisterIsland(model)
	local record = islandsByModel[model]
	if not record then
		return
	end
	islandsByModel[model] = nil
	if record.AncestryConnection then
		record.AncestryConnection:Disconnect()
	end
end

local function registerIsland(chunk, areaModel)
	if islandsByModel[areaModel] or not areaModel:IsA("Model") then
		return
	end
	local terrainId = areaModel:GetAttribute("TerrainId")
	local terrainSize = areaModel:GetAttribute("TerrainSize")
	local chunkIndex = chunk:GetAttribute("ChunkIndex")
	local chunkSeed = chunk:GetAttribute("Seed")
	local gridSize = chunk:GetAttribute("GridSize")
	if typeof(terrainId) ~= "number" or typeof(chunkIndex) ~= "number" or typeof(chunkSeed) ~= "number" then
		warn("[MVP IslandContent] Ilha ignorada por metadados ausentes: " .. areaModel:GetFullName())
		return
	end

	local cells = {}
	local cellByKey = {}
	for _, descendant in ipairs(areaModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local grid = readCell(descendant)
			if grid then
				local key = cellKey(grid.X, grid.Y, grid.Z)
				local cell = {
					Key = key,
					Grid = grid,
					Part = descendant,
					SurfacePosition = descendant.Position + Vector3.new(0, descendant.Size.Y / 2, 0),
				}
				table.insert(cells, cell)
				cellByKey[key] = cell
			end
		end
	end
	table.sort(cells, function(left, right)
		return left.Key < right.Key
	end)

	local anchor = findTerrainAnchor(chunk, terrainId)
	local contentFolder = areaModel:FindFirstChild("MVPContent")
	if not contentFolder then
		contentFolder = Instance.new("Folder")
		contentFolder.Name = "MVPContent"
		contentFolder.Parent = areaModel
	end

	local islandSeed = (chunkSeed + terrainId * 104729) % MAX_SEED
	if islandSeed == 0 then
		islandSeed = 1
	end
	local islandKey = string.format("Chunk_%03d:Island_%02d", chunkIndex, terrainId)
	areaModel:SetAttribute("IslandKey", islandKey)
	areaModel:SetAttribute("IslandSeed", islandSeed)
	areaModel:SetAttribute("FreeCellCount", #cells)
	CollectionService:AddTag(areaModel, ISLAND_TAG)

	local record = {
		Model = areaModel,
		Chunk = chunk,
		ContentFolder = contentFolder,
		AnchorPart = anchor,
		ChunkIndex = chunkIndex,
		TerrainId = terrainId,
		Size = terrainSize,
		GridSize = gridSize,
		IslandKey = islandKey,
		Seed = islandSeed,
		Cells = cells,
		CellByKey = cellByKey,
		Reservations = {},
	}
	islandsByModel[areaModel] = record
	record.AncestryConnection = areaModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unregisterIsland(areaModel)
		end
	end)
	notifyAdded(record)
end

local function registerChunk(chunk)
	if not chunk:IsA("Model") then
		return
	end
	local terrainFolder = chunk:FindFirstChild("TerrainAreas")
	if not terrainFolder then
		return
	end
	for _, areaModel in ipairs(terrainFolder:GetChildren()) do
		registerIsland(chunk, areaModel)
	end
end

function IslandContentService.Start()
	if started then
		return
	end
	started = true

	CollectionService:GetInstanceAddedSignal(CHUNK_TAG):Connect(registerChunk)
	for _, chunk in ipairs(CollectionService:GetTagged(CHUNK_TAG)) do
		registerChunk(chunk)
	end
	print(string.format("[MVP IslandContent] %d ilha(s) registrada(s)", #IslandContentService.GetIslands()))
end

function IslandContentService.ObserveIslands(callback, includeExisting)
	assert(typeof(callback) == "function", "callback deve ser function")
	table.insert(observers, callback)
	if includeExisting ~= false then
		for _, record in ipairs(IslandContentService.GetIslands()) do
			task.spawn(callback, record)
		end
	end
	return function()
		local index = table.find(observers, callback)
		if index then
			table.remove(observers, index)
		end
	end
end

function IslandContentService.GetIslands()
	local result = {}
	for _, record in pairs(islandsByModel) do
		table.insert(result, record)
	end
	table.sort(result, function(left, right)
		return left.IslandKey < right.IslandKey
	end)
	return result
end

function IslandContentService.GetFreeCells(record)
	local result = {}
	for _, cell in ipairs(record.Cells) do
		if record.Reservations[cell.Key] == nil and cell.Part.Parent ~= nil then
			table.insert(result, cell)
		end
	end
	return result
end

function IslandContentService.ReserveCells(record, cells, ownerId)
	assert(typeof(ownerId) == "string" and ownerId ~= "", "ownerId invalido")
	for _, cell in ipairs(cells) do
		if not record.CellByKey[cell.Key] or record.Reservations[cell.Key] ~= nil then
			return false
		end
	end
	for _, cell in ipairs(cells) do
		record.Reservations[cell.Key] = ownerId
	end
	return true
end

function IslandContentService.ReleaseOwner(record, ownerId)
	for key, currentOwner in pairs(record.Reservations) do
		if currentOwner == ownerId then
			record.Reservations[key] = nil
		end
	end
end

return IslandContentService
