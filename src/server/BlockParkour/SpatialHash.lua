--[[
	Indice espacial horizontal para ilhas ativas.

	O mundo cresce sem limite, portanto consultas de proximidade nao podem varrer
	todos os nos a cada jogador. Os buckets guardam somente X/Z; a margem vertical
	e os limites exatos da ilha continuam sendo validados pelo ChunkManager.
]]

local SpatialHash = {}
SpatialHash.__index = SpatialHash

local function bucketCoordinate(value, cellSize)
	return math.floor(value / cellSize)
end

local function bucketKey(x, z)
	return tostring(x) .. ":" .. tostring(z)
end

function SpatialHash.new(cellSize)
	assert(type(cellSize) == "number" and cellSize > 0, "SpatialHash exige cellSize positivo.")
	return setmetatable({
		CellSize = cellSize,
		Buckets = {},
		Entries = {},
	}, SpatialHash)
end

function SpatialHash:Clear()
	table.clear(self.Buckets)
	table.clear(self.Entries)
end

function SpatialHash:Remove(key)
	local entry = self.Entries[key]
	if not entry then
		return false
	end
	local bucket = self.Buckets[entry.BucketKey]
	if bucket then
		bucket[key] = nil
		if next(bucket) == nil then
			self.Buckets[entry.BucketKey] = nil
		end
	end
	self.Entries[key] = nil
	return true
end

function SpatialHash:Insert(key, position, value)
	assert(key ~= nil, "SpatialHash exige uma chave.")
	assert(typeof(position) == "Vector3", "SpatialHash exige uma posicao Vector3.")
	self:Remove(key)
	local x = bucketCoordinate(position.X, self.CellSize)
	local z = bucketCoordinate(position.Z, self.CellSize)
	local cellKey = bucketKey(x, z)
	local bucket = self.Buckets[cellKey]
	if not bucket then
		bucket = {}
		self.Buckets[cellKey] = bucket
	end
	local entry = {
		Key = key,
		Position = position,
		Value = value,
		BucketKey = cellKey,
	}
	bucket[key] = entry
	self.Entries[key] = entry
	return entry
end

function SpatialHash:QueryRadius(position, radius)
	assert(typeof(position) == "Vector3", "SpatialHash exige uma posicao Vector3.")
	radius = math.max(0, tonumber(radius) or 0)
	local minimumX = bucketCoordinate(position.X - radius, self.CellSize)
	local maximumX = bucketCoordinate(position.X + radius, self.CellSize)
	local minimumZ = bucketCoordinate(position.Z - radius, self.CellSize)
	local maximumZ = bucketCoordinate(position.Z + radius, self.CellSize)
	local radiusSquared = radius * radius
	local result = {}
	for x = minimumX, maximumX do
		for z = minimumZ, maximumZ do
			local bucket = self.Buckets[bucketKey(x, z)]
			if bucket then
				for _, entry in pairs(bucket) do
					local dx = entry.Position.X - position.X
					local dz = entry.Position.Z - position.Z
					if dx * dx + dz * dz <= radiusSquared then
						table.insert(result, entry.Value)
					end
				end
			end
		end
	end
	return result
end

return SpatialHash
