-- DungeonRuntime/CameraSafeZoneService
--
-- Task 14 — contrato espacial para camera portrait.
--
-- Esta camada somente MATERIALIZA e VALIDA metadados/volumes invisiveis.
-- Ela nao move camera, jogador, inimigos ou ilhas.
--
-- Consumers futuros:
-- - Task 15: Portrait-aware Route Generation
-- - Task 16: Portrait-safe Spawn Placement

local CollectionService = game:GetService("CollectionService")

local PortraitRouteGenerationPolicy = require(script.Parent.PortraitRouteGenerationPolicy)

local CameraSafeZoneService = {}

local CONTRACT_VERSION = 1
local FOLDER_NAME = "CameraSafeZones"
local PRIMARY_ZONE_NAME = "Primary"
local FOCUS_EDGE_PADDING = 1.5

local ROUTE_ATTRIBUTES = table.freeze({
	"RoundIndex",
	"IslandIndex",
	"GlobalIslandIndex",
	"IsMandatoryRoute",
	"IsOptionalRoute",
	"IsRewardIsland",
	"IsRoundExit",
	"IsBossSanctuary",
	"RouteBranchId",
	"RouteNodeOrder",
})

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalUnit(vector, fallback)
	local flat = horizontal(vector)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	local backup = horizontal(fallback or Vector3.new(0, 0, -1))
	return backup.Magnitude > 0.001 and backup.Unit or Vector3.new(0, 0, -1)
end

local function copyRouteAttributes(instance, spec)
	spec = type(spec) == "table" and spec or {}
	for _, name in ipairs(ROUTE_ATTRIBUTES) do
		if spec[name] ~= nil then
			instance:SetAttribute(name, spec[name])
		end
	end
end

local function marker(root, name)
	local value = root and root:FindFirstChild(name, true)
	return value and value:IsA("BasePart") and value or nil
end

local function horizontalInside(zone, position, padding)
	if not zone or typeof(position) ~= "Vector3" then
		return false
	end
	local localPoint = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size * 0.5
	local extra = math.max(0, tonumber(padding) or 0)
	return math.abs(localPoint.X) <= half.X + extra
		and math.abs(localPoint.Z) <= half.Z + extra
end

local function safeInset(floor)
	local minimumDimension = math.min(floor.Size.X, floor.Size.Z)
	return math.clamp(minimumDimension * 0.06, 4, 8)
end

local function zoneHeight(floor)
	local minimumDimension = math.min(floor.Size.X, floor.Size.Z)
	return math.clamp(minimumDimension * 0.42, 24, 38)
end

local function clampToFootprint(floor, worldPosition, inset)
	local localPoint = floor.CFrame:PointToObjectSpace(worldPosition)
	local halfX = math.max(2, floor.Size.X * 0.5 - inset - FOCUS_EDGE_PADDING)
	local halfZ = math.max(2, floor.Size.Z * 0.5 - inset - FOCUS_EDGE_PADDING)
	local localSafe = Vector3.new(
		math.clamp(localPoint.X, -halfX, halfX),
		floor.Size.Y * 0.5 + 0.24,
		math.clamp(localPoint.Z, -halfZ, halfZ)
	)
	return floor.CFrame:PointToWorldSpace(localSafe)
end

local function createInvisiblePart(parent, name, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function createFocusMarker(parent, name, role, position, lookTarget, sourceMarker, spec)
	local direction = horizontalUnit(
		lookTarget - position,
		sourceMarker and sourceMarker.CFrame.LookVector or Vector3.new(0, 0, -1)
	)

	local focus = createInvisiblePart(
		parent,
		name,
		Vector3.new(2, 0.25, 2),
		CFrame.lookAt(position, position + direction)
	)
	focus:SetAttribute("CameraSafeZoneContractVersion", CONTRACT_VERSION)
	focus:SetAttribute("CameraFocusMarker", true)
	focus:SetAttribute("CameraFocusRole", role)
	focus:SetAttribute("SourceMarkerName", sourceMarker and sourceMarker.Name or "")
	focus:SetAttribute("PreferredForwardVector", direction)
	copyRouteAttributes(focus, spec)
	CollectionService:AddTag(focus, "DungeonCameraFocusMarker")
	return focus
end

local function countEnemyCoverage(zone, gameplayMarkers)
	local folder = gameplayMarkers and gameplayMarkers:FindFirstChild("EnemySpawns")
	if not folder or not folder:IsA("Folder") then
		return 0, 0
	end

	local total = 0
	local inside = 0
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			total += 1
			if horizontalInside(zone, child.Position, 0.75) then
				inside += 1
			end
		end
	end
	return inside, total
end

function CameraSafeZoneService.Build(islandModel, gameplayMarkers, floor, spec)
	if not islandModel or not islandModel:IsA("Model") then
		return nil, "CameraSafeZoneIslandMissing"
	end
	if not gameplayMarkers or not gameplayMarkers:IsA("Folder") then
		return nil, "CameraSafeZoneGameplayMarkersMissing"
	end
	if not floor or not floor:IsA("BasePart") then
		return nil, "CameraSafeZoneFloorMissing"
	end

	local safeSpawn = marker(gameplayMarkers, "SafeSpawn")
	local objective = marker(gameplayMarkers, "ObjectiveAnchor")
	local entry = marker(gameplayMarkers, "Entry")
	local exit = marker(gameplayMarkers, "Exit")
	if not safeSpawn or not objective or not entry or not exit then
		return nil, "CameraSafeZoneSourceMarkersMissing"
	end

	local old = gameplayMarkers:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder:SetAttribute("CameraSafeZoneContractVersion", CONTRACT_VERSION)
	folder:SetAttribute("CameraSafeZoneReady", false)
	copyRouteAttributes(folder, spec)
	folder.Parent = gameplayMarkers
	CollectionService:AddTag(folder, "DungeonCameraSafeZones")

	local inset = safeInset(floor)
	local height = zoneHeight(floor)
	local zoneSize = Vector3.new(
		math.max(8, floor.Size.X - inset * 2),
		height,
		math.max(8, floor.Size.Z - inset * 2)
	)
	local zoneCFrame = floor.CFrame * CFrame.new(
		0,
		floor.Size.Y * 0.5 + 0.20 + height * 0.5,
		0
	)

	local zone = createInvisiblePart(folder, PRIMARY_ZONE_NAME, zoneSize, zoneCFrame)
	zone:SetAttribute("CameraSafeZone", true)
	zone:SetAttribute("CameraSafeZoneRole", "PrimaryGameplay")
	zone:SetAttribute("CameraSafeZoneContractVersion", CONTRACT_VERSION)
	zone:SetAttribute("HorizontalInsetStuds", inset)
	zone:SetAttribute("VerticalClearanceStuds", height)
	zone:SetAttribute("RecommendedCameraHeightMin", 22)
	zone:SetAttribute("RecommendedCameraHeightMax", 35)
	zone:SetAttribute("RecommendedBackDistanceMin", 12)
	zone:SetAttribute("RecommendedBackDistanceMax", 22)
	zone:SetAttribute("RecommendedFovMin", 68)
	zone:SetAttribute("RecommendedFovMax", 88)
	zone:SetAttribute("SafeSpawnMarkerName", safeSpawn.Name)
	zone:SetAttribute("ObjectiveMarkerName", objective.Name)
	zone:SetAttribute("EntryMarkerName", entry.Name)
	zone:SetAttribute("ExitMarkerName", exit.Name)
	zone:SetAttribute("EnemySpawnFolderName", "EnemySpawns")
	copyRouteAttributes(zone, spec)
	CollectionService:AddTag(zone, "DungeonCameraSafeZone")

	local preferredForward = horizontalUnit(
		exit.Position - entry.Position,
		exit.CFrame.LookVector
	)
	zone:SetAttribute("PreferredForwardVector", preferredForward)

	local entryFocusPosition = clampToFootprint(floor, safeSpawn.Position, inset)
	local objectiveFocusPosition = clampToFootprint(floor, objective.Position, inset)
	local exitFocusPosition = clampToFootprint(floor, exit.Position, inset)

	local entryFocus = createFocusMarker(
		folder,
		"CameraEntryFocus",
		"Entry",
		entryFocusPosition,
		objectiveFocusPosition,
		entry,
		spec
	)
	local objectiveFocus = createFocusMarker(
		folder,
		"CameraObjectiveFocus",
		"Objective",
		objectiveFocusPosition,
		exitFocusPosition,
		objective,
		spec
	)
	local exitFocus = createFocusMarker(
		folder,
		"CameraExitFocus",
		"Exit",
		exitFocusPosition,
		exit.Position + preferredForward * 8,
		exit,
		spec
	)

	local insideEnemies, totalEnemies = countEnemyCoverage(zone, gameplayMarkers)
	local coverage = totalEnemies > 0 and insideEnemies / totalEnemies or 1

	zone:SetAttribute("SafeSpawnInside", horizontalInside(zone, safeSpawn.Position, 0.75))
	zone:SetAttribute("ObjectiveInside", horizontalInside(zone, objective.Position, 0.75))
	zone:SetAttribute("EnemySpawnCoverage", coverage)
	zone:SetAttribute("EnemySpawnInsideCount", insideEnemies)
	zone:SetAttribute("EnemySpawnTotalCount", totalEnemies)

	local portraitRoute, portraitReason = PortraitRouteGenerationPolicy.Build(
		islandModel,
		gameplayMarkers,
		folder,
		zone
	)
	if not portraitRoute then
		folder:SetAttribute("CameraSafeZoneReady", false)
		return nil, portraitReason
	end

	folder:SetAttribute("PrimaryZoneName", PRIMARY_ZONE_NAME)
	folder:SetAttribute("CameraFocusCount", 3)
	folder:SetAttribute("EnemySpawnCoverage", coverage)
	folder:SetAttribute("PortraitRouteContractVersion", PortraitRouteGenerationPolicy.ContractVersion)
	folder:SetAttribute("PortraitRouteReady", true)
	folder:SetAttribute("CameraSafeZoneReady", true)

	gameplayMarkers:SetAttribute("CameraSafeZoneContractVersion", CONTRACT_VERSION)
	gameplayMarkers:SetAttribute("PortraitRouteContractVersion", PortraitRouteGenerationPolicy.ContractVersion)
	gameplayMarkers:SetAttribute("PortraitRouteReady", true)
	gameplayMarkers:SetAttribute("CameraSafeZoneReady", true)
	islandModel:SetAttribute("CameraSafeZoneContractVersion", CONTRACT_VERSION)
	islandModel:SetAttribute("CameraSafeZoneReady", true)
	floor:SetAttribute("CameraSafeZoneContractVersion", CONTRACT_VERSION)
	floor:SetAttribute("CameraSafeZoneReady", true)

	return {
		Folder = folder,
		Primary = zone,
		EntryFocus = entryFocus,
		ObjectiveFocus = objectiveFocus,
		ExitFocus = exitFocus,
		PortraitRoute = portraitRoute,
	}
end

function CameraSafeZoneService.Validate(islandModel, gameplayMarkers)
	if not islandModel or not islandModel:IsA("Model") then
		return false, "CameraSafeZoneIslandMissing"
	end

	gameplayMarkers = gameplayMarkers
		or islandModel:FindFirstChild("GameplayMarkers")
	if not gameplayMarkers or not gameplayMarkers:IsA("Folder") then
		return false, "CameraSafeZoneGameplayMarkersMissing"
	end

	local folder = gameplayMarkers:FindFirstChild(FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return false, "CameraSafeZonesMissing"
	end
	if tonumber(folder:GetAttribute("CameraSafeZoneContractVersion"))
		~= CONTRACT_VERSION
	then
		return false, "CameraSafeZoneContractVersionMismatch"
	end

	local zone = folder:FindFirstChild(PRIMARY_ZONE_NAME)
	if not zone or not zone:IsA("BasePart") then
		return false, "PrimaryCameraSafeZoneMissing"
	end
	if zone:GetAttribute("CameraSafeZone") ~= true then
		return false, "PrimaryCameraSafeZoneFlagMissing"
	end
	if zone.CanCollide or zone.CanTouch or zone.CanQuery then
		return false, "PrimaryCameraSafeZoneMustBeNonPhysical"
	end
	if zone.Size.X < 8 or zone.Size.Y < 20 or zone.Size.Z < 8 then
		return false, "PrimaryCameraSafeZoneTooSmall"
	end

	local safeSpawn = marker(gameplayMarkers, "SafeSpawn")
	local objective = marker(gameplayMarkers, "ObjectiveAnchor")
	if not safeSpawn or not horizontalInside(zone, safeSpawn.Position, 1) then
		return false, "SafeSpawnOutsideCameraSafeZone"
	end
	if not objective or not horizontalInside(zone, objective.Position, 1) then
		return false, "ObjectiveOutsideCameraSafeZone"
	end

	for _, name in ipairs({
		"CameraEntryFocus",
		"CameraObjectiveFocus",
		"CameraExitFocus",
	}) do
		local focus = folder:FindFirstChild(name)
		if not focus or not focus:IsA("BasePart") then
			return false, name .. "Missing"
		end
		if not horizontalInside(zone, focus.Position, 0.25) then
			return false, name .. "OutsideSafeZone"
		end
		if focus:GetAttribute("CameraFocusMarker") ~= true then
			return false, name .. "FlagMissing"
		end
	end

	local forward = zone:GetAttribute("PreferredForwardVector")
	if typeof(forward) ~= "Vector3"
		or horizontal(forward).Magnitude < 0.5
	then
		return false, "CameraSafeZoneForwardMissing"
	end

	local insideEnemies, totalEnemies = countEnemyCoverage(zone, gameplayMarkers)
	if insideEnemies ~= totalEnemies then
		return false, "EnemySpawnOutsideCameraSafeZone"
	end

	local portraitRouteValid, portraitRouteReason = PortraitRouteGenerationPolicy.Validate(
		islandModel,
		gameplayMarkers,
		folder,
		zone
	)
	if not portraitRouteValid then
		return false, portraitRouteReason
	end

	folder:SetAttribute("EnemySpawnCoverage", totalEnemies > 0 and insideEnemies / totalEnemies or 1)
	folder:SetAttribute("PortraitRouteReady", true)
	folder:SetAttribute("CameraSafeZoneReady", true)
	gameplayMarkers:SetAttribute("PortraitRouteReady", true)
	gameplayMarkers:SetAttribute("CameraSafeZoneReady", true)
	islandModel:SetAttribute("PortraitRouteReady", true)
	islandModel:SetAttribute("CameraSafeZoneReady", true)

	return true
end

CameraSafeZoneService.ContractVersion = CONTRACT_VERSION
CameraSafeZoneService.FolderName = FOLDER_NAME

return table.freeze(CameraSafeZoneService)
