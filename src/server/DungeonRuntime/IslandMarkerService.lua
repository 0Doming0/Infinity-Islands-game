local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.BlockParkour.Config_SkyDungeon_V10)

local IslandMarkerService = {}

local CONTRACT_VERSION = 3
local MARKER_ROOT_NAME = "GameplayMarkers"
local MAXIMUM_SEED = 2147483647
local DEFAULT_DIRECTION_ID = "East"
local ENEMY_EDGE_INSET_STUDS = 10
local ENEMY_SAFE_SPAWN_DISTANCE_STUDS = 20
local ENEMY_ENTRY_DISTANCE_STUDS = 18
local ENEMY_MARKER_SPACING_STUDS = 9
local ENTRY_SAFE_ZONE_RADIUS_STUDS = 16
local ENTRY_PROTECTION_SECONDS = 3

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

local ROUTE_ATTRIBUTE_NAMES = table.freeze({
	"RouteSeed",
	"RoundIndex",
	"IslandIndex",
	"GlobalIslandIndex",
	"ProtectionGlobalIslandIndex",
	"IncomingDirectionId",
	"NextDirectionId",
	"AlternateNextDirectionId",
	"IsMandatoryRoute",
	"IsOptionalRoute",
	"IsRewardIsland",
	"IsRoundExit",
	"RoundExitIndex",
	"RouteBranchId",
	"RouteNodeOrder",
	"RouteChoiceCount",
	"RouteEntryCount",
	"RouteExitCount",
	"IsRouteConvergence",
	"IsRouteBranchPoint",
	"IsBossSanctuary",
	"RouteExitLeadsToNextRound",
	"RouteExitLeadsToBoss",
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
	for _, attributeName in ipairs(ROUTE_ATTRIBUTE_NAMES) do
		local value = spec[attributeName]
		if value ~= nil then
			instance:SetAttribute(attributeName, value)
		end
	end
end

local function tagMarker(marker, markerType)
	CollectionService:AddTag(marker, "DungeonGameplayMarker")
	CollectionService:AddTag(marker, "Dungeon" .. markerType)
	if markerType == "Entry" then
		CollectionService:AddTag(marker, "DungeonRouteEntry")
	elseif markerType == "Exit" then
		CollectionService:AddTag(marker, "DungeonRouteExit")
	end
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

local function horizontalDistance(left, right)
	if typeof(left) ~= "Vector3" or typeof(right) ~= "Vector3" then
		return math.huge
	end
	return (Vector3.new(left.X, 0, left.Z) - Vector3.new(right.X, 0, right.Z)).Magnitude
end

local function insideFloorInset(floor, position, insetStuds)
	local localPosition = floor.CFrame:PointToObjectSpace(position)
	local inset = math.max(0, tonumber(insetStuds) or 0)
	local halfX = math.max(0, floor.Size.X / 2 - inset)
	local halfZ = math.max(0, floor.Size.Z / 2 - inset)
	return math.abs(localPosition.X) <= halfX and math.abs(localPosition.Z) <= halfZ
end

local function markerPositions(markers)
	local result = {}
	for _, marker in ipairs(type(markers) == "table" and markers or {}) do
		if typeof(marker) == "Instance" and marker:IsA("BasePart") then
			table.insert(result, marker.Position)
		elseif typeof(marker) == "Vector3" then
			table.insert(result, marker)
		end
	end
	return result
end

local function minimumDistance(position, positions)
	local result = math.huge
	for _, other in ipairs(positions or {}) do
		result = math.min(result, horizontalDistance(position, other))
	end
	return result
end

local function cloneConnection(raw, fallbackDirection)
	raw = type(raw) == "table" and raw or {}
	return {
		SourceKey = raw.SourceKey,
		TargetKey = raw.TargetKey,
		DirectionId = raw.DirectionId or fallbackDirection or DEFAULT_DIRECTION_ID,
		RouteBranchId = raw.RouteBranchId,
	}
end

local function appendUniqueConnection(result, seen, connectionSpec)
	local directionId = connectionSpec.DirectionId or DEFAULT_DIRECTION_ID
	local endpoint = connectionSpec.SourceKey or connectionSpec.TargetKey or ""
	local key = directionId .. "|" .. tostring(endpoint)
	if seen[key] then
		return
	end
	seen[key] = true
	connectionSpec.DirectionId = directionId
	table.insert(result, connectionSpec)
end

local function incomingConnections(spec)
	local result = {}
	local seen = {}
	for _, raw in ipairs(type(spec.IncomingConnections) == "table" and spec.IncomingConnections or {}) do
		appendUniqueConnection(result, seen, cloneConnection(raw, spec.IncomingDirectionId))
	end
	if #result == 0 then
		appendUniqueConnection(result, seen, {
			DirectionId = spec.IncomingDirectionId or spec.NextDirectionId or DEFAULT_DIRECTION_ID,
			SourceKey = nil,
			RouteBranchId = spec.RouteBranchId,
		})
	end
	return result
end

local function outgoingConnections(spec)
	local result = {}
	local seen = {}
	for _, raw in ipairs(type(spec.OutgoingConnections) == "table" and spec.OutgoingConnections or {}) do
		appendUniqueConnection(result, seen, cloneConnection(raw, spec.NextDirectionId))
	end
	for _, directionId in ipairs(type(spec.OutgoingDirectionIds) == "table" and spec.OutgoingDirectionIds or {}) do
		appendUniqueConnection(result, seen, {
			DirectionId = directionId,
			RouteBranchId = spec.RouteBranchId,
		})
	end
	for _, directionId in ipairs({ spec.NextDirectionId, spec.AlternateNextDirectionId }) do
		if directionId then
			appendUniqueConnection(result, seen, {
				DirectionId = directionId,
				RouteBranchId = spec.RouteBranchId,
			})
		end
	end
	if #result == 0 then
		appendUniqueConnection(result, seen, {
			DirectionId = spec.IncomingDirectionId or DEFAULT_DIRECTION_ID,
			TargetKey = nil,
			RouteBranchId = spec.RouteBranchId,
		})
	end
	return result
end

local function setConnectionAttributes(marker, connectionSpec, index, role)
	marker:SetAttribute("ConnectionIndex", index)
	marker:SetAttribute("ConnectionRole", role)
	marker:SetAttribute("ConnectionDirectionId", connectionSpec.DirectionId)
	marker:SetAttribute("DirectionId", connectionSpec.DirectionId)
	marker:SetAttribute("ConnectionSourceKey", connectionSpec.SourceKey)
	marker:SetAttribute("ConnectionTargetKey", connectionSpec.TargetKey)
	marker:SetAttribute("ConnectionBranchId", connectionSpec.RouteBranchId)
	marker:SetAttribute("IsPrimaryConnection", index == 1)
end

local function buildConnectionMarkers(root, floor, spec)
	local entriesFolder = Instance.new("Folder")
	entriesFolder.Name = "Entries"
	entriesFolder:SetAttribute("MarkerType", "Entries")
	entriesFolder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	entriesFolder.Parent = root

	local exitsFolder = Instance.new("Folder")
	exitsFolder.Name = "Exits"
	exitsFolder:SetAttribute("MarkerType", "Exits")
	exitsFolder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	exitsFolder.Parent = root

	local center = topSurfacePosition(floor)
	local entries = incomingConnections(spec)
	local exits = outgoingConnections(spec)
	local entryMarkers = {}
	local exitMarkers = {}

	for index, connectionSpec in ipairs(entries) do
		local travel = directionVector(connectionSpec.DirectionId)
		local outward = opposite(travel)
		local position = edgePosition(floor, outward, 3, 0)
		local parent = index == 1 and root or entriesFolder
		local name = index == 1 and "Entry" or string.format("Entry_%02d", index)
		local marker = createMarker(parent, name, "Entry", position, center, spec, index, 2)
		setConnectionAttributes(marker, connectionSpec, index, "Incoming")
		marker:SetAttribute("LocksObjectiveProgress", false)
		entryMarkers[index] = marker
	end

	for index, connectionSpec in ipairs(exits) do
		local travel = directionVector(connectionSpec.DirectionId)
		local position = edgePosition(floor, travel, 3, 0)
		local parent = index == 1 and root or exitsFolder
		local name = index == 1 and "Exit" or string.format("Exit_%02d", index)
		local marker = createMarker(parent, name, "Exit", position, position + travel, spec, index, 2)
		setConnectionAttributes(marker, connectionSpec, index, "Outgoing")
		marker:SetAttribute("ObjectiveGate", spec.IsMandatoryRoute == true)
		marker:SetAttribute("ExitLocked", spec.IsMandatoryRoute == true)
		exitMarkers[index] = marker
	end

	local entryCount = #entryMarkers
	local exitCount = #exitMarkers
	root:SetAttribute("EntryCount", entryCount)
	root:SetAttribute("ExitCount", exitCount)
	root:SetAttribute("IsRouteConvergence", entryCount > 1)
	root:SetAttribute("IsRouteBranchPoint", exitCount > 1)
	entriesFolder:SetAttribute("TotalEntryCount", entryCount)
	entriesFolder:SetAttribute("AdditionalEntryCount", math.max(0, entryCount - 1))
	exitsFolder:SetAttribute("TotalExitCount", exitCount)
	exitsFolder:SetAttribute("AdditionalExitCount", math.max(0, exitCount - 1))

	return {
		Entry = entryMarkers[1],
		Exit = exitMarkers[1],
		Entries = entryMarkers,
		Exits = exitMarkers,
	}
end

local function enemySafetyDistances(floor)
	local minimumDimension = math.min(floor.Size.X, floor.Size.Z)
	return {
		EdgeInset = math.min(ENEMY_EDGE_INSET_STUDS, math.max(5, minimumDimension * 0.16)),
		SafeSpawnDistance = math.min(
			ENEMY_SAFE_SPAWN_DISTANCE_STUDS,
			math.max(12, minimumDimension * 0.32)
		),
		EntryDistance = math.min(
			ENEMY_ENTRY_DISTANCE_STUDS,
			math.max(10, minimumDimension * 0.28)
		),
		MarkerSpacing = math.min(
			ENEMY_MARKER_SPACING_STUDS,
			math.max(6, minimumDimension * 0.18)
		),
	}
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

local function buildEnemySpawns(root, floor, spec, occupied, safePosition, entryMarkers)
	local folder = Instance.new("Folder")
	folder.Name = "EnemySpawns"
	folder:SetAttribute("MarkerType", "EnemySpawns")
	folder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	folder:SetAttribute("RequestedSpawnCount", enemySpawnCount(
		floor,
		spec.IsRewardIsland == true,
		spec.IsBossSanctuary == true
	))
	local safety = enemySafetyDistances(floor)
	folder:SetAttribute("MinimumSafeSpawnDistanceStuds", safety.SafeSpawnDistance)
	folder:SetAttribute("MinimumEntryDistanceStuds", safety.EntryDistance)
	folder:SetAttribute("MinimumEdgeInsetStuds", safety.EdgeInset)
	folder:SetAttribute("MinimumMarkerSpacingStuds", safety.MarkerSpacing)
	folder.Parent = root

	local count = enemySpawnCount(floor, spec.IsRewardIsland == true, spec.IsBossSanctuary == true)
	local random = Random.new(normalizedSeed((spec.RouteSeed or spec.Seed or 1) + 67867967))
	local maximumRadiusX = math.max(4, floor.Size.X / 2 - safety.EdgeInset)
	local maximumRadiusZ = math.max(4, floor.Size.Z / 2 - safety.EdgeInset)
	local radiusX = math.min(math.max(7, floor.Size.X * 0.30), maximumRadiusX)
	local radiusZ = math.min(math.max(7, floor.Size.Z * 0.30), maximumRadiusZ)
	local entryPositions = markerPositions(entryMarkers)
	local center = topSurfacePosition(floor)
	local angleOffset = random:NextNumber(0, math.pi * 2)
	local created = 0
	local attempts = 0
	local maximumAttempts = math.max(48, count * 30)

	local function candidateIsSafe(position)
		return insideFloorInset(floor, position, safety.EdgeInset)
			and horizontalDistance(position, safePosition) >= safety.SafeSpawnDistance
			and minimumDistance(position, entryPositions) >= safety.EntryDistance
			and farEnough(position, occupied, safety.MarkerSpacing)
	end

	local function createEnemyMarker(position)
		created += 1
		local marker = createMarker(
			folder,
			string.format("EnemySpawn_%02d", created),
			"EnemySpawn",
			position,
			center,
			spec,
			created,
			2
		)
		marker:SetAttribute("SpawnRole", "Standard")
		marker:SetAttribute("SafeSpawnDistanceStuds", horizontalDistance(position, safePosition))
		marker:SetAttribute("NearestEntryDistanceStuds", minimumDistance(position, entryPositions))
		marker:SetAttribute("EdgeInsetStuds", safety.EdgeInset)
		marker:SetAttribute("SafeSpawnValidated", true)
		table.insert(occupied, marker.Position)
	end

	while created < count and attempts < maximumAttempts do
		attempts += 1
		local angle = angleOffset + attempts * 2.399963229728653
		local ring = 0.48 + ((attempts - 1) % 4) * 0.14
		local radiusMultiplier = math.clamp(ring + random:NextNumber(-0.04, 0.04), 0.42, 0.94)
		local position = center + Vector3.new(
			math.cos(angle) * radiusX * radiusMultiplier,
			0,
			math.sin(angle) * radiusZ * radiusMultiplier
		)
		if candidateIsSafe(position) then
			createEnemyMarker(position)
		end
	end

	if created < count then
		local insetX = math.max(4, floor.Size.X / 2 - safety.EdgeInset)
		local insetZ = math.max(4, floor.Size.Z / 2 - safety.EdgeInset)
		local fallbackOffsets = {
			Vector3.new(insetX, 0, insetZ),
			Vector3.new(insetX, 0, -insetZ),
			Vector3.new(-insetX, 0, insetZ),
			Vector3.new(-insetX, 0, -insetZ),
			Vector3.new(insetX, 0, 0),
			Vector3.new(-insetX, 0, 0),
			Vector3.new(0, 0, insetZ),
			Vector3.new(0, 0, -insetZ),
		}
		table.sort(fallbackOffsets, function(left, right)
			return horizontalDistance(center + left, safePosition)
				> horizontalDistance(center + right, safePosition)
		end)
		for _, offset in ipairs(fallbackOffsets) do
			if created >= count then
				break
			end
			local position = center + offset
			if candidateIsSafe(position) then
				createEnemyMarker(position)
			end
		end
	end

	folder:SetAttribute("SpawnCount", created)
	folder:SetAttribute("SafeSpawnValidationPassed", created == count or count == 0)
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

local function collectConnectionMarkers(root, kind)
	local result = {}
	local primary = requiredPart(root, kind)
	if primary then
		table.insert(result, primary)
	end
	local folder = root:FindFirstChild(kind .. "s")
	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(result, child)
			end
		end
	end
	table.sort(result, function(left, right)
		local leftIndex = tonumber(left:GetAttribute("ConnectionIndex")) or tonumber(left:GetAttribute("MarkerIndex")) or 1
		local rightIndex = tonumber(right:GetAttribute("ConnectionIndex")) or tonumber(right:GetAttribute("MarkerIndex")) or 1
		if leftIndex == rightIndex then
			return left.Name < right.Name
		end
		return leftIndex < rightIndex
	end)
	return result
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
	local entriesFolder = root:FindFirstChild("Entries")
	local exitsFolder = root:FindFirstChild("Exits")
	if not entriesFolder or not entriesFolder:IsA("Folder") then
		return false, "EntriesFolderMissing"
	end
	if not exitsFolder or not exitsFolder:IsA("Folder") then
		return false, "ExitsFolderMissing"
	end
	local entries = collectConnectionMarkers(root, "Entry")
	local exits = collectConnectionMarkers(root, "Exit")
	if #entries ~= math.max(1, math.floor(tonumber(root:GetAttribute("EntryCount")) or 0)) then
		return false, "EntryCountMismatch"
	end
	if #exits ~= math.max(1, math.floor(tonumber(root:GetAttribute("ExitCount")) or 0)) then
		return false, "ExitCountMismatch"
	end
	for _, marker in ipairs(entries) do
		if type(marker:GetAttribute("ConnectionDirectionId")) ~= "string" then
			return false, "EntryDirectionMissing"
		end
	end
	for _, marker in ipairs(exits) do
		if type(marker:GetAttribute("ConnectionDirectionId")) ~= "string" then
			return false, "ExitDirectionMissing"
		end
	end
	local enemySpawns = root:FindFirstChild("EnemySpawns")
	local chestSpawns = root:FindFirstChild("ChestSpawns")
	if not enemySpawns or not enemySpawns:IsA("Folder") then
		return false, "EnemySpawnsMissing"
	end
	local floor = islandModel:FindFirstChild("IslandFloor") or islandModel.PrimaryPart
	local safety = floor and enemySafetyDistances(floor) or nil
	local safeSpawn = requiredPart(root, "SafeSpawn")
	local safeEntries = collectConnectionMarkers(root, "Entry")
	local entryPositions = markerPositions(safeEntries)
	if floor and safeSpawn and safety then
		for _, marker in ipairs(enemySpawns:GetChildren()) do
			if marker:IsA("BasePart") then
				if not insideFloorInset(floor, marker.Position, safety.EdgeInset) then
					return false, "EnemySpawnTooCloseToEdge"
				end
				if horizontalDistance(marker.Position, safeSpawn.Position) < safety.SafeSpawnDistance then
					return false, "EnemySpawnTooCloseToSafeSpawn"
				end
				if minimumDistance(marker.Position, entryPositions) < safety.EntryDistance then
					return false, "EnemySpawnTooCloseToEntry"
				end
			end
		end
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

	local connections = buildConnectionMarkers(root, floor, spec)
	local entry = connections.Entry
	local exit = connections.Exit
	local center = topSurfacePosition(floor)
	local entryDirection = directionVector(entry:GetAttribute("ConnectionDirectionId"))
	local entryOutward = opposite(entryDirection)
	local outgoingTravel = directionVector(exit:GetAttribute("ConnectionDirectionId"))
	local safeInset = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.18, 9, 16)
	local safePosition = entry.Position - entryOutward * safeInset

	local safeSpawn = createMarker(root, "SafeSpawn", "SafeSpawn", safePosition, center, spec, 1, 3)
	safeSpawn:SetAttribute("RespawnPriority", 100)
	safeSpawn:SetAttribute("CheckpointScope", spec.IsBossSanctuary == true and "BossArena" or "Island")
	safeSpawn:SetAttribute("EntrySafeZoneRadiusStuds", ENTRY_SAFE_ZONE_RADIUS_STUDS)
	safeSpawn:SetAttribute("EntryProtectionSeconds", ENTRY_PROTECTION_SECONDS)
	safeSpawn:SetAttribute("EnemyExclusionRadiusStuds", ENEMY_SAFE_SPAWN_DISTANCE_STUDS)
	local objective = createMarker(root, "ObjectiveAnchor", "ObjectiveAnchor", center, exit.Position, spec, 1, 3)
	objective:SetAttribute("ObjectivePlacementRadius", math.max(8, math.min(floor.Size.X, floor.Size.Z) * 0.2))
	objective:SetAttribute("SupportsBeacon", spec.IsBossSanctuary ~= true)
	objective:SetAttribute("SupportsNest", spec.IsBossSanctuary ~= true)

	local occupied = markerPositionList(root)
	local _, chestCount = buildChestSpawns(root, floor, spec, outgoingTravel, occupied)
	local _, enemyCount = buildEnemySpawns(
		root,
		floor,
		spec,
		occupied,
		safePosition,
		connections.Entries
	)

	local entryCount = #connections.Entries
	local exitCount = #connections.Exits
	root:SetAttribute("EnemySpawnCount", enemyCount)
	root:SetAttribute("EntrySafeZoneRadiusStuds", ENTRY_SAFE_ZONE_RADIUS_STUDS)
	root:SetAttribute("EntryProtectionSeconds", ENTRY_PROTECTION_SECONDS)
	root:SetAttribute("SafeEnemySpawnPolicy", "EdgeAndEntryExclusionV1")
	root:SetAttribute("ChestSpawnCount", chestCount)
	root:SetAttribute("MarkersReady", true)
	islandModel:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	islandModel:SetAttribute("GameplayMarkersReady", true)
	islandModel:SetAttribute("RouteEntryCount", entryCount)
	islandModel:SetAttribute("RouteExitCount", exitCount)
	islandModel:SetAttribute("IsRouteConvergence", entryCount > 1)
	islandModel:SetAttribute("IsRouteBranchPoint", exitCount > 1)
	islandModel:SetAttribute(
		"ObjectiveEncounterManaged",
		spec.IsMandatoryRoute == true and spec.IsBossSanctuary ~= true
	)
	islandModel:SetAttribute("EnemyMarkerCount", enemyCount)
	islandModel:SetAttribute("EntrySafeZoneRadiusStuds", ENTRY_SAFE_ZONE_RADIUS_STUDS)
	islandModel:SetAttribute("EntryProtectionSeconds", ENTRY_PROTECTION_SECONDS)
	islandModel:SetAttribute("SafeEnemySpawnPolicy", "EdgeAndEntryExclusionV1")
	islandModel:SetAttribute("ChestMarkerCount", chestCount)
	floor:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
	floor:SetAttribute("GameplayMarkersReady", true)
	floor:SetAttribute("RouteEntryCount", entryCount)
	floor:SetAttribute("RouteExitCount", exitCount)

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

function IslandMarkerService.GetConnectionMarkers(islandModel, kind)
	local root = islandModel and islandModel:FindFirstChild(MARKER_ROOT_NAME)
	if not root then
		return {}
	end
	if kind == "Entry" or kind == "Entries" then
		return collectConnectionMarkers(root, "Entry")
	end
	if kind == "Exit" or kind == "Exits" then
		return collectConnectionMarkers(root, "Exit")
	end
	return {}
end

function IslandMarkerService.GetAll(islandModel, folderName)
	if folderName == "Entries" or folderName == "Exits" then
		return IslandMarkerService.GetConnectionMarkers(islandModel, folderName)
	end
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
