-- DungeonRuntime/PortraitSafeSpawnPolicy
--
-- Task 16 — Portrait-safe Spawn Placement.
--
-- Reposiciona SOMENTE EnemySpawn markers durante a geração da ilha.
-- Não move inimigos vivos e não altera o número de inimigos.
--
-- Objetivos:
-- - manter Entry -> Objective -> Exit legível;
-- - evitar spawn dentro do corredor visual principal;
-- - evitar ameaças diretamente atrás do SafeSpawn;
-- - preservar distância de entrada/spawn/edge/entre markers;
-- - privilegiar combate lateral no portrait.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.BlockParkour.Config_SkyDungeon_V10)

local PortraitSafeSpawnPolicy = {}

local POLICY = "SideBiasedRouteClearV1"
local CONTRACT_VERSION = 1
local MAXIMUM_SEED = 2147483647

local PROFILES = table.freeze({
	{
		Name = "Strict",
		CorridorPadding = 3.5,
		RearDistance = 52,
		RearDotMinimum = 0.05,
		ExitClearance = 12,
		SpacingMultiplier = 1.0,
	},
	{
		Name = "Compact",
		CorridorPadding = 1.5,
		RearDistance = 44,
		RearDotMinimum = -0.05,
		ExitClearance = 9,
		SpacingMultiplier = 0.90,
	},
	{
		Name = "MinimumSafe",
		CorridorPadding = 0.5,
		RearDistance = 34,
		RearDotMinimum = -0.20,
		ExitClearance = 6,
		SpacingMultiplier = 0.80,
	},
})

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % MAXIMUM_SEED
	return seed == 0 and 1 or seed
end

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(left, right)
	if typeof(left) ~= "Vector3" or typeof(right) ~= "Vector3" then
		return math.huge
	end
	return horizontal(left - right).Magnitude
end

local function horizontalUnit(vector, fallback)
	local flat = horizontal(vector)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	local backup = horizontal(fallback or Vector3.new(0, 0, -1))
	return backup.Magnitude > 0.001 and backup.Unit or Vector3.new(0, 0, -1)
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

local function findPart(root, name)
	local instance = root and root:FindFirstChild(name, true)
	return instance and instance:IsA("BasePart") and instance or nil
end

local function sortedEnemyMarkers(folder)
	local result = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(result, child)
		end
	end
	table.sort(result, function(left, right)
		local li = tonumber(left:GetAttribute("MarkerIndex")) or 0
		local ri = tonumber(right:GetAttribute("MarkerIndex")) or 0
		if li == ri then
			return left.Name < right.Name
		end
		return li < ri
	end)
	return result
end

local function corridorParts(routeContract)
	local result = {}
	local routeFolder = routeContract
		and (routeContract.Folder or routeContract)
	local corridors = routeFolder and routeFolder:FindFirstChild("RouteCorridors")
	if not corridors or not corridors:IsA("Folder") then
		return result
	end
	for _, child in ipairs(corridors:GetChildren()) do
		if child:IsA("BasePart")
			and child:GetAttribute("PortraitRouteCorridor") == true
		then
			table.insert(result, child)
		end
	end
	return result
end

local function distanceFromBoxXZ(box, position)
	local point = box.CFrame:PointToObjectSpace(position)
	local half = box.Size * 0.5
	local dx = math.max(math.abs(point.X) - half.X, 0)
	local dz = math.max(math.abs(point.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function insideCorridor(box, position, padding)
	local point = box.CFrame:PointToObjectSpace(position)
	local half = box.Size * 0.5
	return math.abs(point.X) <= half.X + padding
		and math.abs(point.Z) <= half.Z + padding
end

local function nearestCorridorDistance(corridors, position)
	local result = math.huge
	for _, corridor in ipairs(corridors) do
		result = math.min(result, distanceFromBoxXZ(corridor, position))
	end
	return result
end

local function insidePrimaryZone(zone, position, margin)
	local point = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size * 0.5
	local inset = math.max(0, tonumber(margin) or 0)
	return math.abs(point.X) <= math.max(0, half.X - inset)
		and math.abs(point.Z) <= math.max(0, half.Z - inset)
end

local function farEnough(position, occupied, minimumDistance)
	for _, other in ipairs(occupied) do
		if horizontalDistance(position, other) < minimumDistance then
			return false
		end
	end
	return true
end

local function nearestEntryDistance(gameplayMarkers, position)
	local result = math.huge
	local primary = findPart(gameplayMarkers, "Entry")
	if primary then
		result = math.min(result, horizontalDistance(position, primary.Position))
	end

	local entries = gameplayMarkers:FindFirstChild("Entries")
	if entries and entries:IsA("Folder") then
		for _, child in ipairs(entries:GetChildren()) do
			if child:IsA("BasePart") then
				result = math.min(result, horizontalDistance(position, child.Position))
			end
		end
	end
	return result
end

local function routeForward(routeContract, entry, objective, exit)
	local routeFolder = routeContract and (routeContract.Folder or routeContract)
	local value = routeFolder and routeFolder:GetAttribute("PrimaryPreferredForwardVector")
	if typeof(value) == "Vector3" then
		return horizontalUnit(value, exit.Position - entry.Position)
	end
	return horizontalUnit(exit.Position - entry.Position, objective.Position - entry.Position)
end

local function spawnSide(position, objectivePosition, forward)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local lateral = horizontal(position - objectivePosition):Dot(right)
	if math.abs(lateral) < 3 then
		return "Front"
	end
	return lateral > 0 and "Right" or "Left"
end

local function candidateIsSafe(
	position,
	profile,
	primaryZone,
	corridors,
	safeSpawn,
	entryDistance,
	exit,
	forward,
	minimumSafeDistance,
	minimumEntryDistance,
	minimumSpacing,
	occupied
)
	if not insidePrimaryZone(primaryZone, position, 1.5) then
		return false, "OutsideCameraSafeZone"
	end
	if horizontalDistance(position, safeSpawn.Position) < minimumSafeDistance then
		return false, "TooCloseToSafeSpawn"
	end
	if entryDistance(position) < minimumEntryDistance then
		return false, "TooCloseToEntry"
	end
	if horizontalDistance(position, exit.Position) < profile.ExitClearance then
		return false, "TooCloseToExit"
	end
	if not farEnough(
		position,
		occupied,
		minimumSpacing * profile.SpacingMultiplier
	) then
		return false, "TooCloseToEnemySpawn"
	end

	for _, corridor in ipairs(corridors) do
		if insideCorridor(corridor, position, profile.CorridorPadding) then
			return false, "RouteCorridorBlocked"
		end
	end

	local fromSafe = horizontal(position - safeSpawn.Position)
	local safeDistance = fromSafe.Magnitude
	if safeDistance > 0.001 and safeDistance <= profile.RearDistance then
		local forwardDot = fromSafe.Unit:Dot(forward)
		if forwardDot < profile.RearDotMinimum then
			return false, "BehindEntryView"
		end
	end

	return true
end

local function floorPosition(floor, localX, localZ)
	return floor.CFrame:PointToWorldSpace(Vector3.new(
		localX,
		floor.Size.Y * 0.5 + 0.20,
		localZ
	))
end

local function findReplacement(
	random,
	index,
	profile,
	floor,
	primaryZone,
	corridors,
	safeSpawn,
	objective,
	exit,
	forward,
	entryDistance,
	minimumSafeDistance,
	minimumEntryDistance,
	minimumSpacing,
	occupied
)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local corridorWidth = 14
	for _, corridor in ipairs(corridors) do
		corridorWidth = math.max(corridorWidth, corridor.Size.X)
	end

	local lateralBase = corridorWidth * 0.5 + profile.CorridorPadding + 2.5
	local longitudinalSpan = math.clamp(
		math.min(floor.Size.X, floor.Size.Z) * 0.24,
		8,
		22
	)

	-- Primeiro tenta posições laterais ao ObjectiveAnchor, alternando lados.
	for attempt = 1, 42 do
		local side = ((attempt + index) % 2 == 0) and 1 or -1
		local lateral = lateralBase
			+ ((attempt - 1) % 4) * 2.5
			+ random:NextNumber(-0.7, 0.7)
		local longitudinal = random:NextNumber(
			-longitudinalSpan * 0.45,
			longitudinalSpan
		)

		local candidate = objective.Position
			+ right * lateral * side
			+ forward * longitudinal
		candidate = Vector3.new(
			candidate.X,
			floor.Position.Y + floor.Size.Y * 0.5 + 0.20,
			candidate.Z
		)

		local safe = candidateIsSafe(
			candidate,
			profile,
			primaryZone,
			corridors,
			safeSpawn,
			entryDistance,
			exit,
			forward,
			minimumSafeDistance,
			minimumEntryDistance,
			minimumSpacing,
			occupied
		)
		if safe then
			return candidate
		end
	end

	-- Fallback determinístico: amostra a footprint inteira, ainda respeitando
	-- corredor, entrada, saída e rear safety.
	local localHalfX = math.max(3, floor.Size.X * 0.5 - 4)
	local localHalfZ = math.max(3, floor.Size.Z * 0.5 - 4)

	for _ = 1, 100 do
		local candidate = floorPosition(
			floor,
			random:NextNumber(-localHalfX, localHalfX),
			random:NextNumber(-localHalfZ, localHalfZ)
		)

		local safe = candidateIsSafe(
			candidate,
			profile,
			primaryZone,
			corridors,
			safeSpawn,
			entryDistance,
			exit,
			forward,
			minimumSafeDistance,
			minimumEntryDistance,
			minimumSpacing,
			occupied
		)
		if safe then
			return candidate
		end
	end

	return nil
end

local function updateMarkerMetadata(
	marker,
	position,
	originalPosition,
	profile,
	gameplayMarkers,
	safeSpawn,
	objective,
	corridors,
	forward
)
	local grid = worldToGrid(position)
	marker:SetAttribute("GridX", grid.X)
	marker:SetAttribute("GridY", grid.Y)
	marker:SetAttribute("GridZ", grid.Z)

	marker:SetAttribute(
		"SafeSpawnDistanceStuds",
		horizontalDistance(position, safeSpawn.Position)
	)
	marker:SetAttribute(
		"NearestEntryDistanceStuds",
		nearestEntryDistance(gameplayMarkers, position)
	)
	marker:SetAttribute(
		"RouteCorridorClearanceStuds",
		nearestCorridorDistance(corridors, position)
	)

	local fromSafe = horizontal(position - safeSpawn.Position)
	local forwardDot = fromSafe.Magnitude > 0.001 and fromSafe.Unit:Dot(forward) or 1
	marker:SetAttribute("EntryForwardDot", forwardDot)
	marker:SetAttribute(
		"PortraitSpawnSide",
		spawnSide(position, objective.Position, forward)
	)
	marker:SetAttribute("PortraitSpawnPolicy", POLICY)
	marker:SetAttribute("PortraitSpawnContractVersion", CONTRACT_VERSION)
	marker:SetAttribute("PortraitSpawnSafetyProfile", profile.Name)
	marker:SetAttribute("PortraitSpawnValidated", true)
	marker:SetAttribute(
		"PortraitSpawnAdjusted",
		horizontalDistance(position, originalPosition) > 0.25
	)
	marker:SetAttribute(
		"PortraitSpawnAdjustmentStuds",
		horizontalDistance(position, originalPosition)
	)
end

function PortraitSafeSpawnPolicy.Reconcile(
	islandModel,
	gameplayMarkers,
	cameraContract,
	floor,
	spec
)
	if not islandModel or not islandModel:IsA("Model") then
		return false, "PortraitSpawnIslandMissing"
	end
	if not gameplayMarkers or not gameplayMarkers:IsA("Folder") then
		return false, "PortraitSpawnGameplayMarkersMissing"
	end
	if not cameraContract
		or not cameraContract.Primary
		or not cameraContract.PortraitRoute
	then
		return false, "PortraitSpawnCameraContractMissing"
	end
	if not floor or not floor:IsA("BasePart") then
		return false, "PortraitSpawnFloorMissing"
	end

	local enemyFolder = gameplayMarkers:FindFirstChild("EnemySpawns")
	if not enemyFolder or not enemyFolder:IsA("Folder") then
		return false, "PortraitSpawnEnemyFolderMissing"
	end

	local markers = sortedEnemyMarkers(enemyFolder)
	if #markers == 0 then
		enemyFolder:SetAttribute("PortraitSpawnPolicy", POLICY)
		enemyFolder:SetAttribute("PortraitSpawnContractVersion", CONTRACT_VERSION)
		enemyFolder:SetAttribute("PortraitAdjustedCount", 0)
		enemyFolder:SetAttribute("PortraitSafeSpawnCount", 0)
		enemyFolder:SetAttribute("PortraitSpawnSafetyPassed", true)
		islandModel:SetAttribute("PortraitSpawnSafetyPassed", true)
		return true
	end

	local safeSpawn = findPart(gameplayMarkers, "SafeSpawn")
	local objective = findPart(gameplayMarkers, "ObjectiveAnchor")
	local entry = findPart(gameplayMarkers, "Entry")
	local exit = findPart(gameplayMarkers, "Exit")
	if not safeSpawn or not objective or not entry or not exit then
		return false, "PortraitSpawnSourceMarkerMissing"
	end

	local primaryZone = cameraContract.Primary
	local routeContract = cameraContract.PortraitRoute
	local corridors = corridorParts(routeContract)
	if #corridors == 0 then
		return false, "PortraitSpawnRouteCorridorsMissing"
	end

	local forward = routeForward(routeContract, entry, objective, exit)
	local minimumSafeDistance = tonumber(
		enemyFolder:GetAttribute("MinimumSafeSpawnDistanceStuds")
	) or 12
	local minimumEntryDistance = tonumber(
		enemyFolder:GetAttribute("MinimumEntryDistanceStuds")
	) or 10
	local minimumSpacing = tonumber(
		enemyFolder:GetAttribute("MinimumMarkerSpacingStuds")
	) or 6

	local function entryDistance(position)
		return nearestEntryDistance(gameplayMarkers, position)
	end

	local random = Random.new(normalizedSeed(
		(spec and (spec.RouteSeed or spec.Seed) or 1) + 16071631
	))

	local occupied = {}
	local adjustedCount = 0
	local strictCount = 0
	local leftCount = 0
	local rightCount = 0
	local frontCount = 0

	for index, marker in ipairs(markers) do
		local originalPosition = marker.Position
		local chosenPosition
		local chosenProfile

		for _, profile in ipairs(PROFILES) do
			local safe = candidateIsSafe(
				originalPosition,
				profile,
				primaryZone,
				corridors,
				safeSpawn,
				entryDistance,
				exit,
				forward,
				minimumSafeDistance,
				minimumEntryDistance,
				minimumSpacing,
				occupied
			)
			if safe then
				chosenPosition = originalPosition
				chosenProfile = profile
				break
			end

			local replacement = findReplacement(
				random,
				index,
				profile,
				floor,
				primaryZone,
				corridors,
				safeSpawn,
				objective,
				exit,
				forward,
				entryDistance,
				minimumSafeDistance,
				minimumEntryDistance,
				minimumSpacing,
				occupied
			)
			if replacement then
				chosenPosition = replacement
				chosenProfile = profile
				break
			end
		end

		if not chosenPosition or not chosenProfile then
			enemyFolder:SetAttribute("PortraitSpawnSafetyPassed", false)
			enemyFolder:SetAttribute("PortraitSpawnFailureMarker", marker.Name)
			islandModel:SetAttribute("PortraitSpawnSafetyPassed", false)
			return false, "PortraitSafeSpawnPlacementFailed:" .. marker.Name
		end

		if horizontalDistance(chosenPosition, originalPosition) > 0.25 then
			adjustedCount += 1
		end
		if chosenProfile.Name == "Strict" then
			strictCount += 1
		end

		local flatObjective = Vector3.new(
			objective.Position.X,
			chosenPosition.Y,
			objective.Position.Z
		)
		if horizontalDistance(chosenPosition, flatObjective) < 0.001 then
			flatObjective = chosenPosition + forward
		end
		marker.CFrame = CFrame.lookAt(chosenPosition, flatObjective)

		updateMarkerMetadata(
			marker,
			chosenPosition,
			originalPosition,
			chosenProfile,
			gameplayMarkers,
			safeSpawn,
			objective,
			corridors,
			forward
		)

		local side = marker:GetAttribute("PortraitSpawnSide")
		if side == "Left" then
			leftCount += 1
		elseif side == "Right" then
			rightCount += 1
		else
			frontCount += 1
		end

		table.insert(occupied, chosenPosition)
	end

	enemyFolder:SetAttribute("PortraitSpawnPolicy", POLICY)
	enemyFolder:SetAttribute("PortraitSpawnContractVersion", CONTRACT_VERSION)
	enemyFolder:SetAttribute("PortraitAdjustedCount", adjustedCount)
	enemyFolder:SetAttribute("PortraitStrictCount", strictCount)
	enemyFolder:SetAttribute("PortraitSafeSpawnCount", #markers)
	enemyFolder:SetAttribute("PortraitLeftSpawnCount", leftCount)
	enemyFolder:SetAttribute("PortraitRightSpawnCount", rightCount)
	enemyFolder:SetAttribute("PortraitFrontSpawnCount", frontCount)
	enemyFolder:SetAttribute("PortraitSpawnSafetyPassed", true)

	gameplayMarkers:SetAttribute("PortraitSpawnContractVersion", CONTRACT_VERSION)
	gameplayMarkers:SetAttribute("PortraitSpawnSafetyPassed", true)
	islandModel:SetAttribute("PortraitSpawnContractVersion", CONTRACT_VERSION)
	islandModel:SetAttribute("PortraitSpawnSafetyPassed", true)

	return true
end

function PortraitSafeSpawnPolicy.Validate(gameplayMarkers)
	if not gameplayMarkers or not gameplayMarkers:IsA("Folder") then
		return false, "PortraitSpawnGameplayMarkersMissing"
	end

	local folder = gameplayMarkers:FindFirstChild("EnemySpawns")
	if not folder or not folder:IsA("Folder") then
		return false, "PortraitSpawnEnemyFolderMissing"
	end
	if folder:GetAttribute("PortraitSpawnSafetyPassed") ~= true then
		return false, "PortraitSpawnSafetyNotPassed"
	end

	for _, marker in ipairs(sortedEnemyMarkers(folder)) do
		if marker:GetAttribute("PortraitSpawnValidated") ~= true then
			return false, "PortraitSpawnMarkerNotValidated:" .. marker.Name
		end

		local dot = tonumber(marker:GetAttribute("EntryForwardDot"))
		if not dot or dot < -0.20 then
			return false, "PortraitSpawnBehindEntry:" .. marker.Name
		end

		local clearance = tonumber(
			marker:GetAttribute("RouteCorridorClearanceStuds")
		)
		if clearance == nil or clearance < 0 then
			return false, "PortraitSpawnCorridorClearanceMissing:" .. marker.Name
		end
	end

	return true
end

PortraitSafeSpawnPolicy.Policy = POLICY
PortraitSafeSpawnPolicy.ContractVersion = CONTRACT_VERSION

return table.freeze(PortraitSafeSpawnPolicy)
