-- DungeonRuntime/PortraitRouteGenerationPolicy
--
-- Task 15 — Portrait-aware Route Generation.
--
-- Materializa um contrato visual da rota usando os markers autoritativos
-- existentes. Não move ilhas nem altera progressão.
--
-- Resultado por ilha:
-- CameraSafeZones/PortraitRoute
--   RouteCorridors/
--     EntryToObjective
--     ObjectiveToExit_01...
--   RouteFocus/
--     EntryFocus
--     ObjectiveFocus
--     ExitFocus_01...
--
-- Consumers:
-- - câmera/navigation client;
-- - Task 16 spawn placement;
-- - futuras validações de templates/layout.

local CollectionService = game:GetService("CollectionService")

local PortraitRouteGenerationPolicy = {}

local CONTRACT_VERSION = 1
local ROUTE_FOLDER_NAME = "PortraitRoute"
local MIN_CORRIDOR_WIDTH = 14
local MAX_CORRIDOR_WIDTH = 24
local MAX_READABLE_TURN_DEGREES = 115
local SHARP_TURN_DEGREES = 72
local MIN_SEGMENT_LENGTH = 5

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

local function horizontalDistance(left, right)
	return horizontal(left - right).Magnitude
end

local function angleDegrees(left, right)
	local a = horizontalUnit(left, Vector3.new(0, 0, -1))
	local b = horizontalUnit(right, a)
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

local function collectExits(gameplayMarkers)
	local result = {}
	local primary = gameplayMarkers:FindFirstChild("Exit")
	if primary and primary:IsA("BasePart") then
		table.insert(result, primary)
	end

	local folder = gameplayMarkers:FindFirstChild("Exits")
	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(result, child)
			end
		end
	end

	table.sort(result, function(left, right)
		local li = tonumber(left:GetAttribute("ConnectionIndex"))
			or tonumber(left:GetAttribute("MarkerIndex"))
			or 1
		local ri = tonumber(right:GetAttribute("ConnectionIndex"))
			or tonumber(right:GetAttribute("MarkerIndex"))
			or 1
		if li == ri then
			return left.Name < right.Name
		end
		return li < ri
	end)

	return result
end

local function copyConnectionAttributes(source, target)
	for _, name in ipairs({
		"ConnectionIndex",
		"ConnectionRole",
		"ConnectionDirectionId",
		"DirectionId",
		"ConnectionSourceKey",
		"ConnectionTargetKey",
		"ConnectionBranchId",
		"IsPrimaryConnection",
	}) do
		local value = source:GetAttribute(name)
		if value ~= nil then
			target:SetAttribute(name, value)
		end
	end
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

local function clampFocusToZone(zone, position, edgePadding)
	local localPoint = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size * 0.5
	local padding = math.max(0.5, tonumber(edgePadding) or 1.5)

	local safeLocal = Vector3.new(
		math.clamp(localPoint.X, -half.X + padding, half.X - padding),
		-half.Y + 1.2,
		math.clamp(localPoint.Z, -half.Z + padding, half.Z - padding)
	)
	return zone.CFrame:PointToWorldSpace(safeLocal)
end

local function segmentPart(parent, name, fromPosition, toPosition, width, zoneHeight)
	local fromFlat = Vector3.new(fromPosition.X, fromPosition.Y, fromPosition.Z)
	local toFlat = Vector3.new(toPosition.X, fromPosition.Y, toPosition.Z)
	local delta = toFlat - fromFlat
	local length = delta.Magnitude
	if length < 0.001 then
		return nil
	end

	local center = (fromFlat + toFlat) * 0.5
	local height = math.max(4, math.min(zoneHeight, 10))
	local corridor = createInvisiblePart(
		parent,
		name,
		Vector3.new(width, height, math.max(MIN_SEGMENT_LENGTH, length)),
		CFrame.lookAt(center + Vector3.new(0, height * 0.5, 0), toFlat + Vector3.new(0, height * 0.5, 0))
	)
	corridor:SetAttribute("PortraitRouteCorridor", true)
	corridor:SetAttribute("PortraitRouteContractVersion", CONTRACT_VERSION)
	corridor:SetAttribute("CorridorLengthStuds", length)
	corridor:SetAttribute("CorridorWidthStuds", width)
	CollectionService:AddTag(corridor, "DungeonPortraitRouteCorridor")
	return corridor
end

local function createFocus(parent, name, role, position, forward, source)
	local focus = createInvisiblePart(
		parent,
		name,
		Vector3.new(2, 0.25, 2),
		CFrame.lookAt(position, position + forward)
	)
	focus:SetAttribute("PortraitRouteFocus", true)
	focus:SetAttribute("PortraitRouteFocusRole", role)
	focus:SetAttribute("PortraitRouteContractVersion", CONTRACT_VERSION)
	focus:SetAttribute("PreferredForwardVector", forward)
	focus:SetAttribute("SourceMarkerName", source and source.Name or "")
	if source then
		copyConnectionAttributes(source, focus)
	end
	CollectionService:AddTag(focus, "DungeonPortraitRouteFocus")
	return focus
end

local function routeTurnClass(angle)
	if angle <= 28 then
		return "Straight"
	elseif angle <= 55 then
		return "Gentle"
	elseif angle <= SHARP_TURN_DEGREES then
		return "Turn"
	elseif angle <= MAX_READABLE_TURN_DEGREES then
		return "Sharp"
	end
	return "Hairpin"
end

local function cameraPreferenceScore(exitMarker, objectivePosition, primaryDirection)
	local targetDirection = horizontalUnit(exitMarker.Position - objectivePosition, primaryDirection)
	local angle = angleDegrees(primaryDirection, targetDirection)
	local score = 100 - angle * 0.55

	if exitMarker:GetAttribute("IsPrimaryConnection") == true then
		score += 22
	end

	local targetKey = string.lower(tostring(exitMarker:GetAttribute("ConnectionTargetKey") or ""))
	if string.find(targetKey, "optional", 1, true) then
		score -= 15
	end

	return math.clamp(score, 0, 140), angle
end

function PortraitRouteGenerationPolicy.Build(
	islandModel,
	gameplayMarkers,
	cameraSafeZoneFolder,
	primaryZone
)
	if not islandModel or not islandModel:IsA("Model") then
		return nil, "PortraitRouteIslandMissing"
	end
	if not gameplayMarkers or not gameplayMarkers:IsA("Folder") then
		return nil, "PortraitRouteGameplayMarkersMissing"
	end
	if not cameraSafeZoneFolder or not cameraSafeZoneFolder:IsA("Folder") then
		return nil, "PortraitRouteCameraFolderMissing"
	end
	if not primaryZone or not primaryZone:IsA("BasePart") then
		return nil, "PortraitRoutePrimaryZoneMissing"
	end

	local entry = gameplayMarkers:FindFirstChild("Entry")
	local objective = gameplayMarkers:FindFirstChild("ObjectiveAnchor")
	local exits = collectExits(gameplayMarkers)
	if not entry or not entry:IsA("BasePart")
		or not objective or not objective:IsA("BasePart")
		or #exits == 0
	then
		return nil, "PortraitRouteSourceMarkersMissing"
	end

	local old = cameraSafeZoneFolder:FindFirstChild(ROUTE_FOLDER_NAME)
	if old then
		old:Destroy()
	end

	local routeFolder = Instance.new("Folder")
	routeFolder.Name = ROUTE_FOLDER_NAME
	routeFolder:SetAttribute("PortraitRouteContractVersion", CONTRACT_VERSION)
	routeFolder:SetAttribute("PortraitRouteReady", false)
	routeFolder.Parent = cameraSafeZoneFolder
	CollectionService:AddTag(routeFolder, "DungeonPortraitRoute")

	local corridors = Instance.new("Folder")
	corridors.Name = "RouteCorridors"
	corridors.Parent = routeFolder

	local focuses = Instance.new("Folder")
	focuses.Name = "RouteFocus"
	focuses.Parent = routeFolder

	local corridorWidth = math.clamp(
		math.min(primaryZone.Size.X, primaryZone.Size.Z) * 0.22,
		MIN_CORRIDOR_WIDTH,
		MAX_CORRIDOR_WIDTH
	)

	local entryPosition = clampFocusToZone(primaryZone, entry.Position, 2)
	local objectivePosition = clampFocusToZone(primaryZone, objective.Position, 2)
	local firstExit = exits[1]
	local firstExitPosition = clampFocusToZone(primaryZone, firstExit.Position, 2)

	local incoming = horizontalUnit(
		objectivePosition - entryPosition,
		entry.CFrame.LookVector
	)
	local primaryOutgoing = horizontalUnit(
		firstExitPosition - objectivePosition,
		firstExit.CFrame.LookVector
	)
	local primaryTurn = angleDegrees(incoming, primaryOutgoing)

	local entryCorridor = segmentPart(
		corridors,
		"EntryToObjective",
		entryPosition,
		objectivePosition,
		corridorWidth,
		primaryZone.Size.Y
	)
	if entryCorridor then
		entryCorridor:SetAttribute("CorridorRole", "EntryToObjective")
	end

	local entryFocus = createFocus(
		focuses,
		"EntryFocus",
		"Entry",
		entryPosition,
		incoming,
		entry
	)

	-- Em curvas, o ObjectiveFocus usa o bissetor entre entrada e saída.
	-- Isso evita uma mudança brusca de yaw ao chegar ao centro da ilha.
	local blendedDirection = horizontalUnit(
		incoming + primaryOutgoing,
		primaryOutgoing
	)
	local objectiveFocus = createFocus(
		focuses,
		"ObjectiveFocus",
		"Objective",
		objectivePosition,
		blendedDirection,
		objective
	)
	objectiveFocus:SetAttribute("PrimaryTurnAngleDegrees", primaryTurn)
	objectiveFocus:SetAttribute("PrimaryTurnClass", routeTurnClass(primaryTurn))

	local exitContracts = {}
	for index, exitMarker in ipairs(exits) do
		local exitPosition = clampFocusToZone(primaryZone, exitMarker.Position, 2)
		local direction = horizontalUnit(
			exitPosition - objectivePosition,
			exitMarker.CFrame.LookVector
		)

		local corridor = segmentPart(
			corridors,
			string.format("ObjectiveToExit_%02d", index),
			objectivePosition,
			exitPosition,
			corridorWidth,
			primaryZone.Size.Y
		)
		if corridor then
			corridor:SetAttribute("CorridorRole", "ObjectiveToExit")
			copyConnectionAttributes(exitMarker, corridor)
		end

		local focus = createFocus(
			focuses,
			string.format("ExitFocus_%02d", index),
			"Exit",
			exitPosition,
			direction,
			exitMarker
		)

		local score, branchAngle = cameraPreferenceScore(
			exitMarker,
			objectivePosition,
			primaryOutgoing
		)

		focus:SetAttribute("PortraitCameraPreferenceScore", score)
		focus:SetAttribute("BranchAngleDegrees", branchAngle)
		focus:SetAttribute("IsPrimaryPortraitExit", index == 1)

		if corridor then
			corridor:SetAttribute("PortraitCameraPreferenceScore", score)
			corridor:SetAttribute("BranchAngleDegrees", branchAngle)
		end

		table.insert(exitContracts, {
			Focus = focus,
			Corridor = corridor,
			Score = score,
		})
	end

	local entryObjectiveDistance = horizontalDistance(entryPosition, objectivePosition)
	local objectiveExitDistance = horizontalDistance(objectivePosition, firstExitPosition)

	local readable = entryObjectiveDistance >= MIN_SEGMENT_LENGTH
		and objectiveExitDistance >= MIN_SEGMENT_LENGTH
		and primaryTurn <= MAX_READABLE_TURN_DEGREES

	routeFolder:SetAttribute("PortraitRouteReady", true)
	routeFolder:SetAttribute("PortraitRouteReadable", readable)
	routeFolder:SetAttribute("EntryObjectiveDistanceStuds", entryObjectiveDistance)
	routeFolder:SetAttribute("ObjectiveExitDistanceStuds", objectiveExitDistance)
	routeFolder:SetAttribute("PrimaryTurnAngleDegrees", primaryTurn)
	routeFolder:SetAttribute("PrimaryTurnClass", routeTurnClass(primaryTurn))
	routeFolder:SetAttribute("PrimaryPreferredForwardVector", primaryOutgoing)
	routeFolder:SetAttribute("CorridorWidthStuds", corridorWidth)
	routeFolder:SetAttribute("ExitCount", #exits)
	routeFolder:SetAttribute("BranchPoint", #exits > 1)
	routeFolder:SetAttribute(
		"RequiresExtraCameraTurnGuidance",
		primaryTurn > SHARP_TURN_DEGREES
	)

	islandModel:SetAttribute("PortraitRouteContractVersion", CONTRACT_VERSION)
	islandModel:SetAttribute("PortraitRouteReady", true)
	islandModel:SetAttribute("PortraitRouteReadable", readable)
	islandModel:SetAttribute("PortraitRouteTurnDegrees", primaryTurn)

	return {
		Folder = routeFolder,
		Corridors = corridors,
		Focuses = focuses,
		EntryFocus = entryFocus,
		ObjectiveFocus = objectiveFocus,
		ExitContracts = exitContracts,
		PrimaryTurnDegrees = primaryTurn,
		Readable = readable,
	}
end

function PortraitRouteGenerationPolicy.Validate(
	islandModel,
	gameplayMarkers,
	cameraSafeZoneFolder,
	primaryZone
)
	if not cameraSafeZoneFolder or not cameraSafeZoneFolder:IsA("Folder") then
		return false, "PortraitRouteCameraFolderMissing"
	end
	if not primaryZone or not primaryZone:IsA("BasePart") then
		return false, "PortraitRoutePrimaryZoneMissing"
	end

	local routeFolder = cameraSafeZoneFolder:FindFirstChild(ROUTE_FOLDER_NAME)
	if not routeFolder or not routeFolder:IsA("Folder") then
		return false, "PortraitRouteMissing"
	end
	if tonumber(routeFolder:GetAttribute("PortraitRouteContractVersion"))
		~= CONTRACT_VERSION
	then
		return false, "PortraitRouteContractVersionMismatch"
	end

	local corridors = routeFolder:FindFirstChild("RouteCorridors")
	local focuses = routeFolder:FindFirstChild("RouteFocus")
	if not corridors or not corridors:IsA("Folder") then
		return false, "PortraitRouteCorridorsMissing"
	end
	if not focuses or not focuses:IsA("Folder") then
		return false, "PortraitRouteFocusMissing"
	end

	local entryFocus = focuses:FindFirstChild("EntryFocus")
	local objectiveFocus = focuses:FindFirstChild("ObjectiveFocus")
	local firstExitFocus = focuses:FindFirstChild("ExitFocus_01")
	for name, focus in pairs({
		EntryFocus = entryFocus,
		ObjectiveFocus = objectiveFocus,
		ExitFocus = firstExitFocus,
	}) do
		if not focus or not focus:IsA("BasePart") then
			return false, name .. "Missing"
		end

		local localPoint = primaryZone.CFrame:PointToObjectSpace(focus.Position)
		local half = primaryZone.Size * 0.5
		if math.abs(localPoint.X) > half.X
			or math.abs(localPoint.Z) > half.Z
		then
			return false, name .. "OutsideCameraSafeZone"
		end
	end

	local entryCorridor = corridors:FindFirstChild("EntryToObjective")
	local firstExitCorridor = corridors:FindFirstChild("ObjectiveToExit_01")
	if not entryCorridor or not firstExitCorridor then
		return false, "PortraitPrimaryCorridorMissing"
	end

	local expectedExitCount = 1
	if gameplayMarkers then
		expectedExitCount = #collectExits(gameplayMarkers)
	end
	if tonumber(routeFolder:GetAttribute("ExitCount")) ~= expectedExitCount then
		return false, "PortraitRouteExitCountMismatch"
	end

	if routeFolder:GetAttribute("PortraitRouteReady") ~= true then
		return false, "PortraitRouteNotReady"
	end

	-- Hairpins antigos podem continuar carregando para compatibilidade,
	-- mas ficam explicitamente marcados como não ideais em vez de quebrar a run.
	local turn = tonumber(routeFolder:GetAttribute("PrimaryTurnAngleDegrees"))
	if not turn or turn < 0 or turn > 180 then
		return false, "PortraitRouteTurnInvalid"
	end

	return true
end

PortraitRouteGenerationPolicy.ContractVersion = CONTRACT_VERSION
PortraitRouteGenerationPolicy.FolderName = ROUTE_FOLDER_NAME

return table.freeze(PortraitRouteGenerationPolicy)
