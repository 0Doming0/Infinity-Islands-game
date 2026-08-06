local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.BlockParkour.Config_SkyDungeon_V10)

local IslandMarkerService = {}

local CONTRACT_VERSION = 1
local MARKER_ROOT_NAME = "GameplayMarkers"
local MAXIMUM_SEED = 2147483647
local DEFAULT_DIRECTION_ID = "East"

local DIRECTION_VECTORS = table.freeze({
	East = Vector3.new(1, 0, 0),
	West = Vector3.new(-1, 0, 0),
	South = Vector3.new(0, 0, 1),
	North = Vector3.new(0, 0, -1),
})

local MARKER_COLORS = table.freeze({
	SafeSpawn = Color3.fromRGB(84, 255, 170),
	ObjectiveAnchor = Color3.fromRGB(171, 113, 255),
	EnemySpawn = Color3.fromRGB(255, 92, 92),
	ChestSpawn = Color3.fromRGB(255, 211, 92),
	Entry = Color3.fromRGB(92, 184, 255),
	Exit = Color3.fromRGB(255, 142, 78),
})

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % MAXIMUM_SEED
	return seed == 0 and 1 or seed
end

local function directionVector(directionId)
	return DIRECTION_VECTORS[directionId] or DIRECTION_VECTORS[DEFAULT_DIRECTION_ID]
end

local function opposite(vector)
	return Vector3.new(-vector.X, 0, -vector.Z)
end

local function perpendicular(vector)
	return Vector3.new(-vector.Z, 0, vector.X)
end

local function topSurfacePosition(floor)
	return floor.Position + Vector3.new(0, floor.Size.Y / 2 + 0.2, 0)
end

local function horizontalLookAt(position, target, fallbackDirection)
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude < 0.001 then
		flatTarget = position + (fallbackDirection or Vector3.new(0, 0, -1))
	end
	return CFrame.lookAt(position, flatTarget)
end

local function worldToGrid(position)
	local physicalOffsetY = tonumber(workspace:GetAttribute("WorldPhysicalYOffsetStuds")) or 0
	local origin = Config.CENTER_WORLD + Vector3.new(0, physicalOffsetY, 0)
	local relative = (position - origin) / Config.GRID_SIZE
	return Vector3.new(math.round(relative.X), math.round(relative.Y), math.round(relative.Z))
end

local function applyRouteAttributes(instance, spec)
	for _, attributeName in ipairs({
		"RouteSeed",
		"RoundIndex",
		"IslandIndex",
		"GlobalIslandIndex",
		"IncomingDirectionId",
		"NextDirectionId",
		"IsMandatoryRoute",
		"IsRewardIsland",
		"IsBossSanctuary",
		"RouteExitLeadsToBoss",
	}) do
		local value = spec[attributeName]
		if value ~= nil then
			instance:SetAttribute(attributeName, value)
		end
	end
end

local function tagMarker(marker, markerType)
	CollectionService:AddTag(marker, "DungeonGameplayMarker")
	CollectionService:AddTag(marker, "Dungeon" .. markerType)
end

local function markerTransparency()
	return workspace:GetAttribute("ShowDungeonGameplayMarkers") == true and 0.35 or 1
end

local function createMarker(parent, name, markerType, position, lookTarget, spec, index, reservationRadiusCells)
	local marker = Instance.new("Part")
	marker.Name = name
	marker.Size = Vector3.new(2, 0.25, 2)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = MARKER_COLORS[markerType] or Color3.new(1, 1, 1)
	marker.Transparency = markerTransparency()
	marker.CFrame = horizontalLookAt(position, lookTarget, Vector3.new(0, 0, -1))
	marker:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	marker:SetAttribute("MarkerType", markerType)
	marker:SetAttribute("MarkerIndex", index)
	marker:SetAttribute("ReservationRadiusCells", math.max(0, math.floor(tonumber(reservationRadiusCells) or 1)))
	marker:SetAttribute("RequiredMarker", true)
	applyRouteAttributes(marker, spec)
	local grid = worldToGrid(position)
	marker:SetAttribute("GridX", grid.X)
	marker:SetAttribute("GridY", grid.Y)
	marker:SetAttribute("GridZ", grid.Z)
	marker.Parent = parent
	tagMarker(marker, markerType)
	return marker
end

local function edgePosition(floor, outward, insetStuds, lateralStuds)
	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2
	local distance = math.abs(outward.X) * math.max(2, halfX - insetStuds)
		+ math.abs(outward.Z) * math.max(2, halfZ - insetStuds)
	return topSurfacePosition(floor)
		+ outward * distance
		+ perpendicular(outward) * (lateralStuds or 0)
end

local function markerPositionList(root)
	local result = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(result, descendant.Position)
		end
	end
	return result
end

local function farEnough(position, occupied, minimumDistance)
	for _, other in ipairs(occupied) do
		if (Vector3.new(position.X, 0, position.Z) - Vector3.new(other.X, 0, other.Z)).Magnitude < minimumDistance then
			return false
		end
	end
	return true
end

local function enemySpawnCount(floor, isRewardIsland, isBossSanctuary)
	if isBossSanctuary then
		return 0
	end
	local minimumDimension = math.min(floor.Size.X, floor.Size.Z)
	local count = minimumDimension >= 112 and 8 or (minimumDimension >= 76 and 6 or 4)
	if isRewardIsland then
		count = math.max(count, 6)
	end
	return count
end

local function buildEnemySpawns(root, floor, spec, occupied)
	local folder = Instance.new("Folder")
	folder.Name = "EnemySpawns"
	folder:SetAttribute("MarkerType", "EnemySpawns")
	folder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	folder.Parent = root

	local count = enemySpawnCount(floor, spec.IsRewardIsland == true, spec.IsBossSanctuary == true)
	local random = Random.new(normalizedSeed((spec.RouteSeed or spec.Seed or 1) + 67867967))
	local radiusX = math.max(8, floor.Size.X * 0.32)
	local radiusZ = math.max(8, floor.Size.Z * 0.32)
	local angleOffset = random:NextNumber(0, math.pi * 2)
	local created = 0
	local attempts = 0
	local maximumAttempts = math.max(12, count * 6)
	while created < count and attempts < maximumAttempts do
		attempts += 1
		local angle = angleOffset + ((attempts - 1) / math.max(1, count)) * math.pi * 2
			+ random:NextNumber(-0.16, 0.16)
		local radiusMultiplier = random:NextNumber(0.82, 1)
		local position = topSurfacePosition(floor) + Vector3.new(
			math.cos(angle) * radiusX * radiusMultiplier,
			0,
			math.sin(angle) * radiusZ * radiusMultiplier
		)
		if farEnough(position, occupied, 12) then
			created += 1
			local marker = createMarker(
				folder,
				string.format("EnemySpawn_%02d", created),
				"EnemySpawn",
				position,
				topSurfacePosition(floor),
				spec,
				created,
				2
			)
			marker:SetAttribute("SpawnRole", "Standard")
			table.insert(occupied, marker.Position)
		end
	end
	folder:SetAttribute("SpawnCount", created)
	return folder, created
end

local function buildChestSpawns(root, floor, spec, travelDirection, occupied)
	local folder = Instance.new("Folder")
	folder.Name = "ChestSpawns"
	folder:SetAttribute("MarkerType", "ChestSpawns")
	folder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	folder.Parent = root

	local side = perpendicular(travelDirection)
	local sideDistance = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.18, 8, 16)
	local backOffset = travelDirection * -math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.06, 2, 6)
	local center = topSurfacePosition(floor)
	local definitions
	if spec.IsRewardIsland == true then
		definitions = {
			{ Name = "RoundCoreChest", Role = "Core", Side = 1 },
			{ Name = "RoundBonusChest", Role = "Bonus", Side = -1 },
		}
	elseif spec.IsBossSanctuary == true then
		definitions = {}
	else
		definitions = {
			{ Name = "ChestSpawn_01", Role = "Optional", Side = 1 },
			{ Name = "ChestSpawn_02", Role = "Optional", Side = -1 },
		}
	end

	for index, definition in ipairs(definitions) do
		local position = center + side * sideDistance * definition.Side + backOffset
		local marker = createMarker(
			folder,
			definition.Name,
			"ChestSpawn",
			position,
			center,
			spec,
			index,
			2
		)
		marker:SetAttribute("ChestRole", definition.Role)
		marker:SetAttribute("PersonalRewardChest", spec.IsRewardIsland == true)
		marker:SetAttribute("RequiredInteraction", spec.IsRewardIsland == true)
		table.insert(occupied, marker.Position)
	end
	folder:SetAttribute("SpawnCount", #definitions)
	folder:SetAttribute("PersonalChestSet", spec.IsRewardIsland == true)
	return folder, #definitions
end

local function requiredPart(root, name)
	local marker = root:FindFirstChild(name)
	return marker and marker:IsA("BasePart") and marker or nil
end

function IslandMarkerService.Validate(islandModel)
	local root = islandModel and islandModel:FindFirstChild(MARKER_ROOT_NAME)
	if not root or not root:IsA("Folder") then
		return false, "GameplayMarkersMissing"
	end
	for _, name in ipairs({ "SafeSpawn", "ObjectiveAnchor", "Entry", "Exit" }) do
		if not requiredPart(root, name) then
			return false, name .. "Missing"
		end
	end
	local enemySpawns = root:FindFirstChild("EnemySpawns")
	local chestSpawns = root:FindFirstChild("ChestSpawns")
	if not enemySpawns or not enemySpawns:IsA("Folder") then
		return false, "EnemySpawnsMissing"
	end
	if not chestSpawns or not chestSpawns:IsA("Folder") then
		return false, "ChestSpawnsMissing"
	end
	if islandModel:GetAttribute("IsRewardIsland") == true then
		if not chestSpawns:FindFirstChild("RoundCoreChest") then
			return false, "RoundCoreChestMarkerMissing"
		end
		if not chestSpawns:FindFirstChild("RoundBonusChest") then
			return false, "RoundBonusChestMarkerMissing"
		end
	end
	return true
end

function IslandMarkerService.Build(islandModel, spec)
	if not islandModel or not islandModel:IsA("Model") then
		return nil, "InvalidIslandModel"
	end
	spec = type(spec) == "table" and spec or {}
	local floor = islandModel:FindFirstChild("IslandFloor") or islandModel.PrimaryPart
	if not floor or not floor:IsA("BasePart") then
		return nil, "IslandFloorMissing"
	end
	local old = islandModel:FindFirstChild(MARKER_ROOT_NAME)
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = MARKER_ROOT_NAME
	root:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	root:SetAttribute("MarkersReady", false)
	applyRouteAttributes(root, spec)
	root.Parent = islandModel
	CollectionService:AddTag(root, "DungeonGameplayMarkers")

	local incomingTravel = spec.IncomingDirectionId and directionVector(spec.IncomingDirectionId) or nil
	local outgoingTravel = spec.NextDirectionId and directionVector(spec.NextDirectionId) or nil
	if not incomingTravel and outgoingTravel then
		incomingTravel = outgoingTravel
	end
	incomingTravel = incomingTravel or directionVector(DEFAULT_DIRECTION_ID)
	outgoingTravel = outgoingTravel or incomingTravel
	local entryOutward = opposite(incomingTravel)
	local exitOutward = outgoingTravel
	local center = topSurfacePosition(floor)
	local entryPosition = edgePosition(floor, entryOutward, 3, 0)
	local exitPosition = edgePosition(floor, exitOutward, 3, 0)
	local safeInset = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.18, 9, 16)
	local safePosition = entryPosition - entryOutward * safeInset

	local entry = createMarker(root, "Entry", "Entry", entryPosition, center, spec, 1, 2)
	entry:SetAttribute("DirectionId", spec.IncomingDirectionId or "RouteStart")
	entry:SetAttribute("LocksObjectiveProgress", false)
	local exit = createMarker(root, "Exit", "Exit", exitPosition, exitPosition + exitOutward, spec, 1, 2)
	exit:SetAttribute("DirectionId", spec.NextDirectionId or spec.IncomingDirectionId or DEFAULT_DIRECTION_ID)
	exit:SetAttribute("ObjectiveGate", true)
	exit:SetAttribute("ExitLocked", true)
	local safeSpawn = createMarker(root, "SafeSpawn", "SafeSpawn", safePosition, center, spec, 1, 3)
	safeSpawn:SetAttribute("RespawnPriority", 100)
	safeSpawn:SetAttribute("CheckpointScope", spec.IsBossSanctuary == true and "BossArena" or "Island")
	local objective = createMarker(root, "ObjectiveAnchor", "ObjectiveAnchor", center, exitPosition, spec, 1, 3)
	objective:SetAttribute("ObjectivePlacementRadius", math.max(8, math.min(floor.Size.X, floor.Size.Z) * 0.2))
	objective:SetAttribute("SupportsBeacon", spec.IsBossSanctuary ~= true)
	objective:SetAttribute("SupportsNest", spec.IsBossSanctuary ~= true)

	local occupied = markerPositionList(root)
	local _, chestCount = buildChestSpawns(root, floor, spec, outgoingTravel, occupied)
	local _, enemyCount = buildEnemySpawns(root, floor, spec, occupied)

	root:SetAttribute("EnemySpawnCount", enemyCount)
	root:SetAttribute("ChestSpawnCount", chestCount)
	root:SetAttribute("MarkersReady", true)
	islandModel:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	islandModel:SetAttribute("GameplayMarkersReady", true)
	islandModel:SetAttribute(
		"ObjectiveEncounterManaged",
		spec.IsMandatoryRoute == true and spec.IsBossSanctuary ~= true
	)
	islandModel:SetAttribute("EnemyMarkerCount", enemyCount)
	islandModel:SetAttribute("ChestMarkerCount", chestCount)
	floor:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	floor:SetAttribute("GameplayMarkersReady", true)

	local valid, reason = IslandMarkerService.Validate(islandModel)
	if not valid then
		root:SetAttribute("MarkersReady", false)
		islandModel:SetAttribute("GameplayMarkersReady", false)
		return nil, reason
	end
	return root
end

function IslandMarkerService.Get(islandModel, markerName)
	local root = islandModel and islandModel:FindFirstChild(MARKER_ROOT_NAME)
	return root and root:FindFirstChild(markerName, true) or nil
end

function IslandMarkerService.GetAll(islandModel, folderName)
	local root = islandModel and islandModel:FindFirstChild(MARKER_ROOT_NAME)
	local folder = root and root:FindFirstChild(folderName)
	if not folder then
		return {}
	end
	local result = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(result, child)
		end
	end
	table.sort(result, function(left, right)
		return left.Name < right.Name
	end)
	return result
end

function IslandMarkerService.IsReservedCell(islandModel, cell)
	if typeof(cell) ~= "Vector3" then
		return false
	end
	local root = islandModel and islandModel:FindFirstChild(MARKER_ROOT_NAME)
	if not root then
		return false
	end
	for _, marker in ipairs(root:GetDescendants()) do
		if marker:IsA("BasePart") then
			local x = marker:GetAttribute("GridX")
			local z = marker:GetAttribute("GridZ")
			local radius = math.max(0, tonumber(marker:GetAttribute("ReservationRadiusCells")) or 1)
			if typeof(x) == "number" and typeof(z) == "number" then
				local dx = cell.X - x
				local dz = cell.Z - z
				if dx * dx + dz * dz <= radius * radius then
					return true
				end
			end
		end
	end
	return false
end

return table.freeze(IslandMarkerService)
