local CollectionService = game:GetService("CollectionService")

local IslandVariationService = {}

local VERSION = 1
local ROOT_NAME = "StructuralVariation"
local EDGE_MARGIN = 5
local ROUTE_CLEARANCE = 8
local CENTER_CLEARANCE = 9
local MAX_COLLIDABLE_PARTS = 18

local PROFILE_POOLS = table.freeze({
	Mandatory = table.freeze({ "OpenArena", "SplitCover", "RaisedTerraces", "RuinedRing" }),
	Optional = table.freeze({ "OptionalLookout", "OptionalRuins", "OptionalArena" }),
	Reward = table.freeze({ "RewardPavilion" }),
	Boss = table.freeze({ "BossApproach" }),
})

local function horizontalDistance(left, right)
	local dx = left.X - right.X
	local dz = left.Z - right.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function distanceToSegment(point, first, second)
	local ax, az = first.X, first.Z
	local bx, bz = second.X, second.Z
	local px, pz = point.X, point.Z
	local abx, abz = bx - ax, bz - az
	local lengthSquared = abx * abx + abz * abz
	if lengthSquared <= 0.001 then
		return horizontalDistance(point, first)
	end
	local t = math.clamp(((px - ax) * abx + (pz - az) * abz) / lengthSquared, 0, 1)
	local closest = Vector3.new(ax + abx * t, point.Y, az + abz * t)
	return horizontalDistance(point, closest)
end

local function stableStringHash(value)
	local hash = 2166136261
	for index = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, index))
		hash = (hash * 16777619) % 2147483647
	end
	return math.max(1, hash)
end

local function contextNumber(context, name, fallback)
	local spec = context.Spec or {}
	local value = context[name]
	if value == nil then
		value = spec[name]
	end
	if value == nil and context.IslandModel then
		value = context.IslandModel:GetAttribute(name)
	end
	return tonumber(value) or fallback
end

local function contextBoolean(context, name)
	local spec = context.Spec or {}
	local value = context[name]
	if value == nil then
		value = spec[name]
	end
	if value == nil and context.IslandModel then
		value = context.IslandModel:GetAttribute(name)
	end
	return value == true
end

local function collectNamedParts(root, name, result)
	local direct = root and root:FindFirstChild(name)
	if direct and direct:IsA("BasePart") then
		table.insert(result, direct)
	end
	local folder = root and root:FindFirstChild(name .. "s")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(result, child)
			end
		end
	end
end

local function collectMarkerData(context)
	local root = context.GameplayMarkers
		or (context.IslandModel and context.IslandModel:FindFirstChild("GameplayMarkers"))
	local markers = {}
	local entries = {}
	local exits = {}
	if not root then
		return markers, entries, exits
	end
	collectNamedParts(root, "Entry", entries)
	collectNamedParts(root, "Exit", exits)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local markerType = tostring(descendant:GetAttribute("MarkerType") or descendant.Name)
			local clearance = 6
			if string.find(markerType, "SafeSpawn", 1, true) then
				clearance = 16
			elseif string.find(markerType, "Entry", 1, true) then
				clearance = 14
			elseif string.find(markerType, "Exit", 1, true) then
				clearance = 10
			elseif string.find(markerType, "Objective", 1, true) then
				clearance = 12
			elseif string.find(markerType, "Chest", 1, true) then
				clearance = 9
			end
			table.insert(markers, {
				Position = descendant.Position,
				Clearance = clearance,
			})
		end
	end
	return markers, entries, exits
end

local function insideFloor(floor, localOffset, size)
	local halfX = math.max(size.X, size.Z) / 2
	local halfZ = halfX
	return math.abs(localOffset.X) + halfX <= floor.Size.X / 2 - EDGE_MARGIN
		and math.abs(localOffset.Z) + halfZ <= floor.Size.Z / 2 - EDGE_MARGIN
end

local function routeIsClear(worldPosition, size, entries, exits)
	local footprint = math.max(size.X, size.Z) / 2
	for _, entry in ipairs(entries) do
		for _, exit in ipairs(exits) do
			if distanceToSegment(worldPosition, entry.Position, exit.Position) < ROUTE_CLEARANCE + footprint then
				return false
			end
		end
	end
	return true
end

local function markersAreClear(worldPosition, size, markers)
	local footprint = math.max(size.X, size.Z) / 2
	for _, marker in ipairs(markers) do
		if horizontalDistance(worldPosition, marker.Position) < marker.Clearance + footprint then
			return false
		end
	end
	return true
end

local function createPart(folder, floor, definition, markerData)
	local localOffset = definition.Offset
	local size = definition.Size
	if not insideFloor(floor, localOffset, size) then
		return nil
	end
	local localY = floor.Size.Y / 2 + size.Y / 2 + localOffset.Y + (definition.Lift or 0)
	local rotation = definition.Rotation or 0
	local cframe = floor.CFrame
		* CFrame.new(localOffset.X, localY, localOffset.Z)
		* CFrame.Angles(0, rotation, 0)
	local position = cframe.Position
	local markers, entries, exits = markerData.Markers, markerData.Entries, markerData.Exits
	if definition.Overhead ~= true then
		if definition.IgnoreCenter ~= true then
			local center = floor.Position
			if horizontalDistance(position, center) < CENTER_CLEARANCE + math.max(size.X, size.Z) / 2 then
				return nil
			end
		end
		if not markersAreClear(position, size, markers) or not routeIsClear(position, size, entries, exits) then
			return nil
		end
	end
	local part = Instance.new("Part")
	part.Name = definition.Name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = definition.CanCollide ~= false
	part.CanTouch = false
	part.CanQuery = definition.CanQuery ~= false
	part.CastShadow = definition.CastShadow ~= false
	part.Material = definition.Material or Enum.Material.Slate
	part.Color = definition.Color or floor.Color:Lerp(Color3.new(1, 1, 1), 0.12)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("DungeonStructuralVariation", true)
	part:SetAttribute("NavigationObstacle", part.CanCollide)
	part:SetAttribute("SafeRoutePreserved", true)
	part.Parent = folder
	CollectionService:AddTag(part, "DungeonStructuralVariation")
	return part
end

local function addDefinitions(folder, floor, definitions, markerData)
	local created = 0
	local collidable = 0
	for _, definition in ipairs(definitions) do
		if collidable >= MAX_COLLIDABLE_PARTS and definition.CanCollide ~= false then
			continue
		end
		local part = createPart(folder, floor, definition, markerData)
		if part then
			created += 1
			if part.CanCollide then
				collidable += 1
			end
		end
	end
	return created, collidable
end

local function pillar(name, x, z, height, floor, random)
	return {
		Name = name,
		Offset = Vector3.new(x, 0, z),
		Size = Vector3.new(3.2, height, 3.2),
		Rotation = random:NextInteger(0, 3) * math.pi / 2,
		Material = random:NextNumber() < 0.5 and Enum.Material.Slate or Enum.Material.Cobblestone,
		Color = floor.Color:Lerp(Color3.fromRGB(105, 111, 116), 0.38),
	}
end

local function buildOpenArena(floor, random)
	local x = floor.Size.X * 0.28
	local z = floor.Size.Z * 0.27
	local definitions = {}
	for index, signs in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
		table.insert(definitions, {
			Name = string.format("ArenaCover_%02d", index),
			Offset = Vector3.new(x * signs[1], 0, z * signs[2]),
			Size = Vector3.new(6, random:NextNumber(2.4, 3.8), 4),
			Rotation = random:NextInteger(0, 1) * math.pi / 2,
			Material = Enum.Material.Slate,
			Color = floor.Color:Lerp(Color3.fromRGB(87, 96, 105), 0.32),
		})
	end
	return definitions
end

local function buildSplitCover(floor, random)
	local definitions = {}
	local x = floor.Size.X * 0.27
	local z = floor.Size.Z * 0.18
	local positions = {
		{ -x, -z }, { x, -z }, { -x, z }, { x, z },
		{ -x * 0.7, 0 }, { x * 0.7, 0 },
	}
	for index, position in ipairs(positions) do
		table.insert(definitions, {
			Name = string.format("SplitCover_%02d", index),
			Offset = Vector3.new(position[1], 0, position[2]),
			Size = Vector3.new(random:NextNumber(5.5, 8), random:NextNumber(2.5, 4), 3),
			Rotation = (index % 2 == 0) and math.pi / 2 or 0,
			Material = Enum.Material.Cobblestone,
			Color = floor.Color:Lerp(Color3.fromRGB(96, 92, 84), 0.35),
		})
	end
	return definitions
end

local function buildRaisedTerraces(floor, random)
	local definitions = {}
	local x = floor.Size.X * 0.31
	for sideIndex, sign in ipairs({ -1, 1 }) do
		table.insert(definitions, {
			Name = string.format("Terrace_%02d", sideIndex),
			Offset = Vector3.new(x * sign, 0, 0),
			Size = Vector3.new(math.clamp(floor.Size.X * 0.18, 9, 15), 1.5, math.clamp(floor.Size.Z * 0.34, 14, 24)),
			Material = Enum.Material.Slate,
			Color = floor.Color:Lerp(Color3.fromRGB(115, 121, 127), 0.28),
		})
		for step = 1, 2 do
			table.insert(definitions, {
				Name = string.format("TerraceStep_%02d_%02d", sideIndex, step),
				Offset = Vector3.new(x * sign - sign * (6 + step * 2.4), 0, (step == 1 and -4 or 4)),
				Size = Vector3.new(4.2, 0.65 * step, 5.5),
				Material = Enum.Material.Cobblestone,
				Color = floor.Color:Lerp(Color3.fromRGB(103, 108, 112), 0.3),
			})
		end
	end
	return definitions
end

local function buildRuinedRing(floor, random, prefix)
	local definitions = {}
	local radiusX = floor.Size.X * 0.31
	local radiusZ = floor.Size.Z * 0.30
	local count = math.clamp(math.floor(math.min(floor.Size.X, floor.Size.Z) / 13), 5, 8)
	local offset = random:NextNumber(0, math.pi * 2)
	for index = 1, count do
		local angle = offset + (index - 1) / count * math.pi * 2
		table.insert(definitions, pillar(
			string.format("%sPillar_%02d", prefix or "Ruined", index),
			math.cos(angle) * radiusX,
			math.sin(angle) * radiusZ,
			random:NextNumber(5, 10),
			floor,
			random
		))
	end
	return definitions
end

local function buildOptionalLookout(floor, random)
	local definitions = buildRuinedRing(floor, random, "Lookout")
	table.insert(definitions, {
		Name = "LookoutPlatform",
		Offset = Vector3.new(floor.Size.X * 0.29, 0, -floor.Size.Z * 0.25),
		Size = Vector3.new(9, 1.2, 9),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(112, 82, 52),
	})
	return definitions
end

local function buildRewardPavilion(floor, random)
	local definitions = {}
	local x = floor.Size.X * 0.30
	local z = floor.Size.Z * 0.30
	for index, signs in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
		table.insert(definitions, pillar(
			string.format("RewardColumn_%02d", index),
			x * signs[1], z * signs[2], 9, floor, random
		))
	end
	for index, axis in ipairs({ "X", "Z" }) do
		table.insert(definitions, {
			Name = "RewardCanopy_" .. axis,
			Offset = Vector3.new(0, 9.4, 0),
			Lift = 0,
			Size = axis == "X" and Vector3.new(x * 2, 0.7, 3) or Vector3.new(3, 0.7, z * 2),
			CanCollide = false,
			CanQuery = false,
			IgnoreCenter = true,
			Overhead = true,
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(138, 98, 56),
		})
	end
	return definitions
end

local function chooseProfile(context)
	local isBoss = contextBoolean(context, "IsBossSanctuary")
	local isReward = contextBoolean(context, "IsRewardIsland") or contextBoolean(context, "IsRoundExit")
	local isOptional = contextBoolean(context, "IsOptionalRoute")
	local pool = isBoss and PROFILE_POOLS.Boss
		or (isReward and PROFILE_POOLS.Reward)
		or (isOptional and PROFILE_POOLS.Optional)
		or PROFILE_POOLS.Mandatory
	local key = tostring(context.Key or (context.Spec and context.Spec.Key) or "Island")
	local seed = math.floor(contextNumber(context, "RouteSeed", contextNumber(context, "Seed", 1)))
	local physicalIndex = math.floor(contextNumber(
		context,
		"PhysicalIslandIndex",
		contextNumber(context, "PhysicalIndex", contextNumber(context, "GlobalIslandIndex", 1))
	))
	local roundIndex = math.floor(contextNumber(context, "RoundIndex", 1))
	local selector = (stableStringHash(key) + seed + physicalIndex * 7919 + roundIndex * 104729) % #pool + 1
	return pool[selector], seed + physicalIndex * 1009 + roundIndex * 97
end

local PROFILE_BUILDERS = {
	OpenArena = buildOpenArena,
	SplitCover = buildSplitCover,
	RaisedTerraces = buildRaisedTerraces,
	RuinedRing = function(floor, random)
		return buildRuinedRing(floor, random, "Ruined")
	end,
	OptionalLookout = buildOptionalLookout,
	OptionalRuins = function(floor, random)
		return buildRuinedRing(floor, random, "OptionalRuins")
	end,
	OptionalArena = buildOpenArena,
	RewardPavilion = buildRewardPavilion,
	BossApproach = function(floor, random)
		return buildRuinedRing(floor, random, "BossApproach")
	end,
}

function IslandVariationService.Apply(context)
	if type(context) ~= "table" then
		return false, "InvalidVariationContext"
	end
	local island = context.IslandModel
	local floor = context.Floor or (island and (island:FindFirstChild("IslandFloor") or island.PrimaryPart))
	if not island or not island:IsA("Model") or not floor or not floor:IsA("BasePart") then
		return false, "VariationIslandMissing"
	end
	if island:GetAttribute("StructuralVariationVersion") == VERSION
		and island:GetAttribute("StructuralVariationApplied") == true
	then
		return true, island:GetAttribute("StructuralVariationProfile")
	end
	local old = island:FindFirstChild(ROOT_NAME)
	if old then
		old:Destroy()
	end
	local profile, seed = chooseProfile(context)
	local builder = PROFILE_BUILDERS[profile]
	if not builder then
		return false, "VariationProfileMissing:" .. tostring(profile)
	end
	local folder = Instance.new("Folder")
	folder.Name = ROOT_NAME
	folder:SetAttribute("StructuralVariationVersion", VERSION)
	folder:SetAttribute("StructuralVariationProfile", profile)
	folder:SetAttribute("DeterministicSeed", seed)
	folder.Parent = island
	CollectionService:AddTag(folder, "DungeonStructuralVariationRoot")
	local markers, entries, exits = collectMarkerData(context)
	local markerData = { Markers = markers, Entries = entries, Exits = exits }
	local definitions = builder(floor, Random.new(math.max(1, math.abs(seed) % 2147483647)))
	local created, collidable = addDefinitions(folder, floor, definitions, markerData)
	folder:SetAttribute("CreatedPartCount", created)
	folder:SetAttribute("CollidablePartCount", collidable)
	folder:SetAttribute("SafeMarkerCount", #markers)
	folder:SetAttribute("SafeRouteSegmentCount", #entries * #exits)
	island:SetAttribute("StructuralVariationVersion", VERSION)
	island:SetAttribute("StructuralVariationProfile", profile)
	island:SetAttribute("StructuralVariationPartCount", created)
	island:SetAttribute("StructuralVariationCollidableCount", collidable)
	island:SetAttribute("StructuralVariationSafeZonesPreserved", true)
	island:SetAttribute("StructuralVariationRouteClearanceStuds", ROUTE_CLEARANCE)
	island:SetAttribute("StructuralVariationApplied", true)
	workspace:SetAttribute("DungeonIslandVariationReady", true)
	workspace:SetAttribute("DungeonIslandVariationVersion", VERSION)
	workspace:SetAttribute("DungeonIslandVariationPolicy", "DeterministicSafeStructureV1")
	workspace:SetAttribute(
		"DungeonIslandVariationAppliedCount",
		math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonIslandVariationAppliedCount")) or 0)) + 1
	)
	return true, profile, created
end

function IslandVariationService.Validate(island)
	if not island or not island:IsA("Model") then
		return false, "InvalidIsland"
	end
	local folder = island:FindFirstChild(ROOT_NAME)
	if not folder then
		return false, "StructuralVariationMissing"
	end
	if island:GetAttribute("StructuralVariationApplied") ~= true then
		return false, "StructuralVariationNotApplied"
	end
	if island:GetAttribute("StructuralVariationSafeZonesPreserved") ~= true then
		return false, "StructuralVariationSafetyMissing"
	end
	return true
end

return table.freeze(IslandVariationService)
