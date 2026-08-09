--[[
    Infinity Islands — Rebuild Part 19
    Robust deterministic gameplay markers.

    Design rules:
    - actual marker Instances are the source of truth;
    - EntryCount / ExitCount are DERIVED from those Instances;
    - no validation may fail only because a cached count attribute drifted;
    - Reward islands require only the Core Chest used by the rebuild;
    - no optional/bonus gameplay dependency is introduced here.
]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.BlockParkour.Config_SkyDungeon_V10)

local IslandMarkerService = {}

local CONTRACT_VERSION = 4
local ROOT_NAME = "GameplayMarkers"
local DEFAULT_DIRECTION_ID = "East"
local MAXIMUM_SEED = 2147483647

local ENTRY_SAFE_ZONE_RADIUS_STUDS = 16
local ENTRY_PROTECTION_SECONDS = 3
local SAFE_SPAWN_INSET_STUDS = 14

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

local ROUTE_ATTRIBUTES = table.freeze({
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
    return DIRECTION_VECTORS[tostring(directionId or "")]
        or DIRECTION_VECTORS[DEFAULT_DIRECTION_ID]
end

local function opposite(vector)
    return Vector3.new(-vector.X, 0, -vector.Z)
end

local function perpendicular(vector)
    return Vector3.new(-vector.Z, 0, vector.X)
end

local function topSurface(floor)
    return floor.Position + Vector3.new(0, floor.Size.Y / 2 + 0.2, 0)
end

local function horizontalLookAt(position, target, fallback)
    local flat = Vector3.new(target.X, position.Y, target.Z)
    if (flat - position).Magnitude < 0.001 then
        flat = position + (fallback or Vector3.new(0, 0, -1))
    end
    return CFrame.lookAt(position, flat)
end

local function worldToGrid(position)
    local physicalOffsetY = tonumber(workspace:GetAttribute("WorldPhysicalYOffsetStuds")) or 0
    local origin = Config.CENTER_WORLD + Vector3.new(0, physicalOffsetY, 0)
    local relative = (position - origin) / Config.GRID_SIZE
    return Vector3.new(
        math.round(relative.X),
        math.round(relative.Y),
        math.round(relative.Z)
    )
end

local function copyRouteAttributes(instance, spec)
    for _, name in ipairs(ROUTE_ATTRIBUTES) do
        local value = spec[name]
        if value ~= nil then
            instance:SetAttribute(name, value)
        end
    end
end

local function markerTransparency()
    return workspace:GetAttribute("ShowDungeonGameplayMarkers") == true and 0.35 or 1
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

local function createMarker(
    parent,
    name,
    markerType,
    position,
    lookTarget,
    spec,
    index,
    reservationRadius
)
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
    marker.CFrame = horizontalLookAt(
        position,
        lookTarget,
        Vector3.new(0, 0, -1)
    )

    marker:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
    marker:SetAttribute("MarkerType", markerType)
    marker:SetAttribute("MarkerIndex", index)
    marker:SetAttribute(
        "ReservationRadiusCells",
        math.max(0, math.floor(tonumber(reservationRadius) or 1))
    )
    marker:SetAttribute("RequiredMarker", true)

    copyRouteAttributes(marker, spec)

    local grid = worldToGrid(position)
    marker:SetAttribute("GridX", grid.X)
    marker:SetAttribute("GridY", grid.Y)
    marker:SetAttribute("GridZ", grid.Z)

    marker.Parent = parent
    tagMarker(marker, markerType)
    return marker
end

local function edgePosition(floor, outward, inset, lateral)
    local halfX = floor.Size.X / 2
    local halfZ = floor.Size.Z / 2
    local distance =
        math.abs(outward.X) * math.max(2, halfX - inset)
        + math.abs(outward.Z) * math.max(2, halfZ - inset)

    return topSurface(floor)
        + outward * distance
        + perpendicular(outward) * (lateral or 0)
end

local function normalizeConnection(raw, fallbackDirection)
    raw = type(raw) == "table" and raw or {}
    return {
        SourceKey = raw.SourceKey,
        TargetKey = raw.TargetKey,
        DirectionId = raw.DirectionId or fallbackDirection or DEFAULT_DIRECTION_ID,
        RouteBranchId = raw.RouteBranchId,
    }
end

local function pushUnique(result, seen, connection)
    local directionId = tostring(connection.DirectionId or DEFAULT_DIRECTION_ID)
    local endpoint = tostring(connection.SourceKey or connection.TargetKey or "")
    local key = directionId .. "|" .. endpoint

    if seen[key] then
        return
    end

    seen[key] = true
    connection.DirectionId = directionId
    table.insert(result, connection)
end

local function incomingConnections(spec)
    local result = {}
    local seen = {}

    for _, raw in ipairs(
        type(spec.IncomingConnections) == "table" and spec.IncomingConnections or {}
    ) do
        pushUnique(
            result,
            seen,
            normalizeConnection(raw, spec.IncomingDirectionId)
        )
    end

    if #result == 0 then
        pushUnique(result, seen, {
            DirectionId = spec.IncomingDirectionId
                or spec.NextDirectionId
                or DEFAULT_DIRECTION_ID,
            SourceKey = nil,
            RouteBranchId = spec.RouteBranchId,
        })
    end

    return result
end

local function outgoingConnections(spec)
    local result = {}
    local seen = {}

    for _, raw in ipairs(
        type(spec.OutgoingConnections) == "table" and spec.OutgoingConnections or {}
    ) do
        pushUnique(
            result,
            seen,
            normalizeConnection(raw, spec.NextDirectionId)
        )
    end

    for _, directionId in ipairs(
        type(spec.OutgoingDirectionIds) == "table" and spec.OutgoingDirectionIds or {}
    ) do
        pushUnique(result, seen, {
            DirectionId = directionId,
            RouteBranchId = spec.RouteBranchId,
        })
    end

    for _, directionId in ipairs({
        spec.NextDirectionId,
        spec.AlternateNextDirectionId,
    }) do
        if directionId then
            pushUnique(result, seen, {
                DirectionId = directionId,
                RouteBranchId = spec.RouteBranchId,
            })
        end
    end

    if #result == 0 then
        pushUnique(result, seen, {
            DirectionId = spec.IncomingDirectionId or DEFAULT_DIRECTION_ID,
            TargetKey = nil,
            RouteBranchId = spec.RouteBranchId,
        })
    end

    return result
end

local function setConnectionAttributes(marker, connection, index, role)
    marker:SetAttribute("ConnectionIndex", index)
    marker:SetAttribute("ConnectionRole", role)
    marker:SetAttribute("ConnectionDirectionId", connection.DirectionId)
    marker:SetAttribute("DirectionId", connection.DirectionId)
    marker:SetAttribute("ConnectionSourceKey", connection.SourceKey)
    marker:SetAttribute("ConnectionTargetKey", connection.TargetKey)
    marker:SetAttribute("ConnectionBranchId", connection.RouteBranchId)
    marker:SetAttribute("IsPrimaryConnection", index == 1)
end

local function buildConnections(root, floor, spec)
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

    local center = topSurface(floor)
    local entries = incomingConnections(spec)
    local exits = outgoingConnections(spec)

    local entryMarkers = {}
    local exitMarkers = {}

    for index, connection in ipairs(entries) do
        local travel = directionVector(connection.DirectionId)
        local outward = opposite(travel)
        local position = edgePosition(floor, outward, 3, 0)

        local marker = createMarker(
            index == 1 and root or entriesFolder,
            index == 1 and "Entry" or string.format("Entry_%02d", index),
            "Entry",
            position,
            center,
            spec,
            index,
            2
        )
        setConnectionAttributes(marker, connection, index, "Incoming")
        marker:SetAttribute("LocksObjectiveProgress", false)
        table.insert(entryMarkers, marker)
    end

    for index, connection in ipairs(exits) do
        local travel = directionVector(connection.DirectionId)
        local position = edgePosition(floor, travel, 3, 0)

        local marker = createMarker(
            index == 1 and root or exitsFolder,
            index == 1 and "Exit" or string.format("Exit_%02d", index),
            "Exit",
            position,
            position + travel,
            spec,
            index,
            2
        )
        setConnectionAttributes(marker, connection, index, "Outgoing")
        marker:SetAttribute("ObjectiveGate", spec.IsMandatoryRoute == true)
        marker:SetAttribute("ExitLocked", spec.IsMandatoryRoute == true)
        table.insert(exitMarkers, marker)
    end

    return entryMarkers, exitMarkers
end

local function collectConnectionMarkers(root, kind)
    local result = {}
    local seen = {}

    local primary = root:FindFirstChild(kind)
    if primary and primary:IsA("BasePart") then
        seen[primary] = true
        table.insert(result, primary)
    end

    local folder = root:FindFirstChild(kind .. "s")
    if folder and folder:IsA("Folder") then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("BasePart") and not seen[child] then
                seen[child] = true
                table.insert(result, child)
            end
        end
    end

    table.sort(result, function(left, right)
        local li = tonumber(left:GetAttribute("ConnectionIndex"))
            or tonumber(left:GetAttribute("MarkerIndex"))
            or math.huge
        local ri = tonumber(right:GetAttribute("ConnectionIndex"))
            or tonumber(right:GetAttribute("MarkerIndex"))
            or math.huge

        if li == ri then
            return left.Name < right.Name
        end
        return li < ri
    end)

    return result
end

local function normalizeConnectionCounts(root, islandModel, floor)
    local entries = collectConnectionMarkers(root, "Entry")
    local exits = collectConnectionMarkers(root, "Exit")

    local entryCount = #entries
    local exitCount = #exits

    root:SetAttribute("EntryCount", entryCount)
    root:SetAttribute("ExitCount", exitCount)
    root:SetAttribute("RouteEntryCount", entryCount)
    root:SetAttribute("RouteExitCount", exitCount)
    root:SetAttribute("IsRouteConvergence", entryCount > 1)
    root:SetAttribute("IsRouteBranchPoint", exitCount > 1)

    local entriesFolder = root:FindFirstChild("Entries")
    if entriesFolder then
        entriesFolder:SetAttribute("TotalEntryCount", entryCount)
        entriesFolder:SetAttribute("AdditionalEntryCount", math.max(0, entryCount - 1))
    end

    local exitsFolder = root:FindFirstChild("Exits")
    if exitsFolder then
        exitsFolder:SetAttribute("TotalExitCount", exitCount)
        exitsFolder:SetAttribute("AdditionalExitCount", math.max(0, exitCount - 1))
    end

    islandModel:SetAttribute("RouteEntryCount", entryCount)
    islandModel:SetAttribute("RouteExitCount", exitCount)
    islandModel:SetAttribute("IsRouteConvergence", entryCount > 1)
    islandModel:SetAttribute("IsRouteBranchPoint", exitCount > 1)

    if floor then
        floor:SetAttribute("RouteEntryCount", entryCount)
        floor:SetAttribute("RouteExitCount", exitCount)
    end

    return entries, exits
end

local function horizontalDistance(a, b)
    local aa = Vector3.new(a.X, 0, a.Z)
    local bb = Vector3.new(b.X, 0, b.Z)
    return (aa - bb).Magnitude
end

local function createEnemySpawns(root, floor, spec, safeSpawn, entries)
    local folder = Instance.new("Folder")
    folder.Name = "EnemySpawns"
    folder:SetAttribute("MarkerType", "EnemySpawns")
    folder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
    folder.Parent = root

    if spec.IsBossSanctuary == true then
        folder:SetAttribute("RequestedSpawnCount", 0)
        folder:SetAttribute("SpawnCount", 0)
        folder:SetAttribute("SafeSpawnValidationPassed", true)
        return folder, 0
    end

    local center = topSurface(floor)
    local minimumDimension = math.min(floor.Size.X, floor.Size.Z)
    local radiusX = math.max(8, math.min(floor.Size.X * 0.30, floor.Size.X / 2 - 7))
    local radiusZ = math.max(8, math.min(floor.Size.Z * 0.30, floor.Size.Z / 2 - 7))

    -- Six deterministic candidates. Current mandatory encounter never needs
    -- more than four simultaneous targets, so six gives comfortable headroom.
    local random = Random.new(normalizedSeed((spec.RouteSeed or spec.Seed or 1) + 19087))
    local angleOffset = random:NextNumber(0, math.pi * 2)
    local requested = minimumDimension >= 54 and 6 or 4
    local created = 0

    local entryPositions = {}
    for _, entry in ipairs(entries) do
        table.insert(entryPositions, entry.Position)
    end

    local function safeCandidate(position)
        if horizontalDistance(position, safeSpawn.Position) < 11 then
            return false
        end
        for _, entryPosition in ipairs(entryPositions) do
            if horizontalDistance(position, entryPosition) < 10 then
                return false
            end
        end
        return true
    end

    for index = 1, requested * 3 do
        if created >= requested then
            break
        end

        local angle = angleOffset + (index - 1) * (math.pi * 2 / requested)
        local scale = index <= requested and 1 or 0.72
        local position = center + Vector3.new(
            math.cos(angle) * radiusX * scale,
            0,
            math.sin(angle) * radiusZ * scale
        )

        if safeCandidate(position) then
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
            marker:SetAttribute("SafeSpawnValidated", true)
        end
    end

    -- Absolute fallback: the objective system can reuse positions if needed,
    -- but the marker contract itself must never kill world generation.
    if created == 0 then
        created = 1
        local position = center
            + perpendicular(directionVector(spec.NextDirectionId or DEFAULT_DIRECTION_ID))
                * math.max(6, math.min(floor.Size.X, floor.Size.Z) * 0.18)

        local marker = createMarker(
            folder,
            "EnemySpawn_01",
            "EnemySpawn",
            position,
            center,
            spec,
            1,
            2
        )
        marker:SetAttribute("SpawnRole", "Fallback")
        marker:SetAttribute("SafeSpawnValidated", true)
    end

    folder:SetAttribute("RequestedSpawnCount", requested)
    folder:SetAttribute("SpawnCount", created)
    folder:SetAttribute("SafeSpawnValidationPassed", true)
    return folder, created
end

local function createChestSpawns(root, floor, spec, travelDirection)
    local folder = Instance.new("Folder")
    folder.Name = "ChestSpawns"
    folder:SetAttribute("MarkerType", "ChestSpawns")
    folder:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
    folder.Parent = root

    if spec.IsBossSanctuary == true then
        folder:SetAttribute("SpawnCount", 0)
        return folder, 0
    end

    local center = topSurface(floor)
    local side = perpendicular(travelDirection)
    local sideDistance = math.clamp(math.min(floor.Size.X, floor.Size.Z) * 0.18, 7, 14)

    local definitions
    if spec.IsRewardIsland == true then
        -- Rebuild reward contract: Core only.
        definitions = {
            { Name = "RoundCoreChest", Role = "Core", Side = 1 },
        }
    else
        definitions = {
            { Name = "ChestSpawn_01", Role = "Optional", Side = 1 },
            { Name = "ChestSpawn_02", Role = "Optional", Side = -1 },
        }
    end

    for index, definition in ipairs(definitions) do
        local position = center + side * sideDistance * definition.Side
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
    end

    folder:SetAttribute("SpawnCount", #definitions)
    folder:SetAttribute("PersonalChestSet", spec.IsRewardIsland == true)
    return folder, #definitions
end

local function validateConnectionList(markers, kind)
    if #markers < 1 then
        return false, kind .. "Missing"
    end

    local seenIndices = {}
    for _, marker in ipairs(markers) do
        local direction = marker:GetAttribute("ConnectionDirectionId")
        if type(direction) ~= "string" or direction == "" then
            return false, kind .. "DirectionMissing"
        end

        local index = math.floor(
            tonumber(marker:GetAttribute("ConnectionIndex"))
                or tonumber(marker:GetAttribute("MarkerIndex"))
                or 0
        )

        if index < 1 or seenIndices[index] then
            return false, kind .. "IndexInvalid"
        end
        seenIndices[index] = true
    end

    return true
end

function IslandMarkerService.Validate(islandModel)
    local root = islandModel and islandModel:FindFirstChild(ROOT_NAME)
    if not root or not root:IsA("Folder") then
        return false, "GameplayMarkersMissing"
    end

    local floor = islandModel:FindFirstChild("IslandFloor") or islandModel.PrimaryPart
    if not floor or not floor:IsA("BasePart") then
        return false, "IslandFloorMissing"
    end

    for _, name in ipairs({ "SafeSpawn", "ObjectiveAnchor", "Entry", "Exit" }) do
        local marker = root:FindFirstChild(name)
        if not marker or not marker:IsA("BasePart") then
            return false, name .. "Missing"
        end
    end

    if not root:FindFirstChild("Entries") then
        return false, "EntriesFolderMissing"
    end
    if not root:FindFirstChild("Exits") then
        return false, "ExitsFolderMissing"
    end
    if not root:FindFirstChild("EnemySpawns") then
        return false, "EnemySpawnsMissing"
    end
    if not root:FindFirstChild("ChestSpawns") then
        return false, "ChestSpawnsMissing"
    end

    local entries, exits = normalizeConnectionCounts(root, islandModel, floor)

    local ok, reason = validateConnectionList(entries, "Entry")
    if not ok then
        return false, reason
    end
    ok, reason = validateConnectionList(exits, "Exit")
    if not ok then
        return false, reason
    end

    -- The real marker Instances are authoritative. Count drift is repaired,
    -- never treated as a fatal generation error.
    if root:GetAttribute("EntryCount") ~= #entries
        or root:GetAttribute("ExitCount") ~= #exits
    then
        return false, "InternalCountNormalizationFailed"
    end

    if islandModel:GetAttribute("IsRewardIsland") == true then
        local chestFolder = root:FindFirstChild("ChestSpawns")
        if not chestFolder:FindFirstChild("RoundCoreChest") then
            return false, "RoundCoreChestMarkerMissing"
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

    local old = islandModel:FindFirstChild(ROOT_NAME)
    if old then
        old:Destroy()
    end

    local root = Instance.new("Folder")
    root.Name = ROOT_NAME
    root:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
    root:SetAttribute("MarkersReady", false)
    root:SetAttribute("MarkerCountPolicy", "DerivedFromInstancesV1")
    copyRouteAttributes(root, spec)
    root.Parent = islandModel
    CollectionService:AddTag(root, "DungeonGameplayMarkers")

    local entries, exits = buildConnections(root, floor, spec)
    local primaryEntry = entries[1]
    local primaryExit = exits[1]

    if not primaryEntry then
        root:Destroy()
        return nil, "EntryMissing"
    end
    if not primaryExit then
        root:Destroy()
        return nil, "ExitMissing"
    end

    local center = topSurface(floor)
    local entryTravel = directionVector(primaryEntry:GetAttribute("ConnectionDirectionId"))
    local entryOutward = opposite(entryTravel)
    local exitTravel = directionVector(primaryExit:GetAttribute("ConnectionDirectionId"))

    local safeInset = math.min(
        SAFE_SPAWN_INSET_STUDS,
        math.max(7, math.min(floor.Size.X, floor.Size.Z) * 0.18)
    )
    local safePosition = primaryEntry.Position - entryOutward * safeInset

    local safeSpawn = createMarker(
        root,
        "SafeSpawn",
        "SafeSpawn",
        safePosition,
        center,
        spec,
        1,
        3
    )
    safeSpawn:SetAttribute("RespawnPriority", 100)
    safeSpawn:SetAttribute(
        "CheckpointScope",
        spec.IsBossSanctuary == true and "BossArena" or "Island"
    )
    safeSpawn:SetAttribute("EntrySafeZoneRadiusStuds", ENTRY_SAFE_ZONE_RADIUS_STUDS)
    safeSpawn:SetAttribute("EntryProtectionSeconds", ENTRY_PROTECTION_SECONDS)

    local objectiveAnchor = createMarker(
        root,
        "ObjectiveAnchor",
        "ObjectiveAnchor",
        center,
        primaryExit.Position,
        spec,
        1,
        3
    )
    objectiveAnchor:SetAttribute(
        "ObjectivePlacementRadius",
        math.max(8, math.min(floor.Size.X, floor.Size.Z) * 0.2)
    )
    objectiveAnchor:SetAttribute("SupportsBeacon", spec.IsBossSanctuary ~= true)
    objectiveAnchor:SetAttribute("SupportsNest", spec.IsBossSanctuary ~= true)

    local _, chestCount = createChestSpawns(root, floor, spec, exitTravel)
    local _, enemyCount = createEnemySpawns(
        root,
        floor,
        spec,
        safeSpawn,
        entries
    )

    local normalizedEntries, normalizedExits = normalizeConnectionCounts(
        root,
        islandModel,
        floor
    )

    root:SetAttribute("EnemySpawnCount", enemyCount)
    root:SetAttribute("ChestSpawnCount", chestCount)
    root:SetAttribute("EntrySafeZoneRadiusStuds", ENTRY_SAFE_ZONE_RADIUS_STUDS)
    root:SetAttribute("EntryProtectionSeconds", ENTRY_PROTECTION_SECONDS)
    root:SetAttribute("SafeEnemySpawnPolicy", "RebuildDeterministicMarkersV1")

    islandModel:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
    islandModel:SetAttribute("GameplayMarkersReady", true)
    islandModel:SetAttribute(
        "ObjectiveEncounterManaged",
        spec.IsMandatoryRoute == true and spec.IsBossSanctuary ~= true
    )
    islandModel:SetAttribute("EnemyMarkerCount", enemyCount)
    islandModel:SetAttribute("ChestMarkerCount", chestCount)
    islandModel:SetAttribute("EntrySafeZoneRadiusStuds", ENTRY_SAFE_ZONE_RADIUS_STUDS)
    islandModel:SetAttribute("EntryProtectionSeconds", ENTRY_PROTECTION_SECONDS)
    islandModel:SetAttribute("SafeEnemySpawnPolicy", "RebuildDeterministicMarkersV1")

    floor:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)
    floor:SetAttribute("GameplayMarkersReady", true)

    root:SetAttribute("MarkersReady", true)

    local valid, reason = IslandMarkerService.Validate(islandModel)
    if not valid then
        root:SetAttribute("MarkersReady", false)
        islandModel:SetAttribute("GameplayMarkersReady", false)
        return nil, reason
    end

    workspace:SetAttribute("DungeonLastMarkerEntryCount", #normalizedEntries)
    workspace:SetAttribute("DungeonLastMarkerExitCount", #normalizedExits)
    workspace:SetAttribute("DungeonLastMarkerBuildResult", "Valid")
    workspace:SetAttribute("DungeonMarkerContractVersion", CONTRACT_VERSION)

    return root
end

function IslandMarkerService.Get(islandModel, markerName)
    local root = islandModel and islandModel:FindFirstChild(ROOT_NAME)
    return root and root:FindFirstChild(markerName, true) or nil
end

function IslandMarkerService.GetConnectionMarkers(islandModel, kind)
    local root = islandModel and islandModel:FindFirstChild(ROOT_NAME)
    if not root then
        return {}
    end

    if kind == "Entry" or kind == "Entries" then
        return collectConnectionMarkers(root, "Entry")
    elseif kind == "Exit" or kind == "Exits" then
        return collectConnectionMarkers(root, "Exit")
    end

    return {}
end

function IslandMarkerService.GetAll(islandModel, folderName)
    if folderName == "Entries" or folderName == "Exits" then
        return IslandMarkerService.GetConnectionMarkers(islandModel, folderName)
    end

    local root = islandModel and islandModel:FindFirstChild(ROOT_NAME)
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

    local root = islandModel and islandModel:FindFirstChild(ROOT_NAME)
    if not root then
        return false
    end

    for _, marker in ipairs(root:GetDescendants()) do
        if marker:IsA("BasePart") then
            local x = marker:GetAttribute("GridX")
            local z = marker:GetAttribute("GridZ")
            local radius = math.max(
                0,
                tonumber(marker:GetAttribute("ReservationRadiusCells")) or 1
            )

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
