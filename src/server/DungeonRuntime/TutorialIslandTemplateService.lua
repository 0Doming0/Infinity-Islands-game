local ServerStorage = game:GetService("ServerStorage")

local TutorialIslandTemplateService = {}

local TEMPLATE_NAME = "TutorialIslandTemplate"
local DECORATION_NAME = "TutorialIslandDecoration"
local ANCHOR_NAME = "IslandAnchor"
local EXIT_ANCHOR_NAME = "ExitAnchor"
local ENEMY_AREA_NAME = "areaenemy"

local warnedMissingTemplate = false

local function isPivotable(instance)
	return instance
		and (
			(
				instance:IsA("Model")
					and instance:FindFirstChildWhichIsA(
						"BasePart",
						true
					)
			)
				or instance:IsA("BasePart")
		)
end

local function template()
	local candidate = ServerStorage:FindFirstChild(
		TEMPLATE_NAME,
		true
	)

	if isPivotable(candidate) then
		return candidate
	end

	if not warnedMissingTemplate then
		warnedMissingTemplate = true
		warn(
			"[TutorialIslandTemplate] "
				.. TEMPLATE_NAME
				.. " nao foi encontrado como Model/BasePart em ServerStorage. "
				.. "A Ilha Inicial continuara usando somente a decoracao procedural."
		)
	end

	return nil
end

local function markerCFrame(instance)
	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	return nil
end

local function alignDecoration(
	decoration,
	island,
	floor
)
	local targetAnchor =
		floor.CFrame
		* CFrame.new(0, floor.Size.Y / 2, 0)

	local anchor = decoration:FindFirstChild(
		ANCHOR_NAME,
		true
	)
	local sourceAnchor =
		anchor and markerCFrame(anchor)

	if sourceAnchor then
		local desiredAnchor = targetAnchor
		local exitAnchor = decoration:FindFirstChild(
			EXIT_ANCHOR_NAME,
			true
		)
		local sourceExit =
			exitAnchor and markerCFrame(exitAnchor)
		local gameplayMarkers =
			island:FindFirstChild("GameplayMarkers")
		local exitMarker =
			gameplayMarkers
				and gameplayMarkers:FindFirstChild(
					"Exit"
				)
		local targetExit =
			exitMarker and markerCFrame(exitMarker)

		if sourceExit and targetExit then
			local sourceDirection = Vector3.new(
				sourceExit.Position.X
					- sourceAnchor.Position.X,
				0,
				sourceExit.Position.Z
					- sourceAnchor.Position.Z
			)
			local targetDirection = Vector3.new(
				targetExit.Position.X
					- targetAnchor.Position.X,
				0,
				targetExit.Position.Z
					- targetAnchor.Position.Z
			)

			if sourceDirection.Magnitude > 0.01
				and targetDirection.Magnitude > 0.01
			then
				local sourceYaw = math.atan2(
					sourceDirection.X,
					sourceDirection.Z
				)
				local targetYaw = math.atan2(
					targetDirection.X,
					targetDirection.Z
				)
				local yaw = targetYaw - sourceYaw

				desiredAnchor =
					CFrame.new(targetAnchor.Position)
					* CFrame.Angles(0, yaw, 0)
					* sourceAnchor.Rotation
			end
		end

		local pivot = decoration:GetPivot()
		local anchorFromPivot =
			pivot:ToObjectSpace(sourceAnchor)

		decoration:PivotTo(
			desiredAnchor
				* anchorFromPivot:Inverse()
		)

		return sourceExit and targetExit
			and "IslandAnchorToExitAnchor"
			or "IslandAnchor"
	end

	local boundsCFrame, boundsSize
	if decoration:IsA("Model") then
		boundsCFrame, boundsSize =
			decoration:GetBoundingBox()
	else
		boundsCFrame, boundsSize =
			decoration.CFrame,
			decoration.Size
	end

	local bottomCenter = Vector3.new(
		boundsCFrame.Position.X,
		boundsCFrame.Position.Y
			- boundsSize.Y / 2,
		boundsCFrame.Position.Z
	)
	local displacement =
		targetAnchor.Position - bottomCenter

	decoration:PivotTo(
		decoration:GetPivot() + displacement
	)

	return "BoundingBoxBottomCenter"
end

local function isEnemyAreaName(instance)
	return string.lower(instance.Name)
		== ENEMY_AREA_NAME
		or instance:GetAttribute(
			"TutorialEnemyArea"
		) == true
end

local function isInsideEnemyArea(
	instance,
	root
)
	local current = instance

	while current and current ~= root do
		if isEnemyAreaName(current) then
			return true
		end

		current = current.Parent
	end

	return current == root
		and isEnemyAreaName(root)
end

local function hideMarkerPart(part)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local function isPlacementMarker(instance)
	local name = string.lower(instance.Name)

	return name == "playerspawn"
		or name:sub(-6) == "anchor"
end

local function prepareDecoration(decoration)
	if decoration:IsA("BasePart") then
		decoration.Anchored = true
	end

	for _, descendant in ipairs(
		decoration:GetDescendants()
	) do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute(
				"TutorialKeepDynamic"
			) ~= true
			then
				descendant.Anchored = true
			end

			if isInsideEnemyArea(
				descendant,
				decoration
			)
			then
				hideMarkerPart(descendant)
				descendant:SetAttribute(
					"TutorialEnemyArea",
					true
				)
			elseif isPlacementMarker(descendant)
			then
				hideMarkerPart(descendant)
			end
		end
	end
end

local function tutorialDecoration(island)
	if not island then
		return nil
	end

	return island:FindFirstChild(
		DECORATION_NAME,
		true
	)
end

local function enemyAreaParts(island)
	local root = tutorialDecoration(island)
	if not root then
		return {}
	end

	local result = {}
	local seen = {}

	local function add(part)
		if part:IsA("BasePart")
			and not seen[part]
		then
			seen[part] = true
			table.insert(result, part)
		end
	end

	if root:IsA("BasePart")
		and isEnemyAreaName(root)
	then
		add(root)
	end

	for _, descendant in ipairs(
		root:GetDescendants()
	) do
		if descendant:IsA("BasePart")
			and isInsideEnemyArea(
				descendant,
				root
			)
		then
			add(descendant)
		end
	end

	table.sort(result, function(left, right)
		if left.Name ~= right.Name then
			return left.Name < right.Name
		end

		if left.Position.X ~= right.Position.X then
			return left.Position.X < right.Position.X
		end

		return left.Position.Z < right.Position.Z
	end)

	return result
end

function TutorialIslandTemplateService.Attach(
	island,
	floor,
	spec
)
	if not island
		or not island:IsA("Model")
		or not floor
		or not floor:IsA("BasePart")
	then
		return nil, "InvalidIsland"
	end

	local globalIndex = math.floor(
		tonumber(
			spec and spec.GlobalIslandIndex
				or island:GetAttribute(
					"GlobalIslandIndex"
				)
		) or 0
	)

	if globalIndex ~= 1
		and not (spec and spec.IsStart == true)
	then
		return nil, "NotInitialIsland"
	end

	local existing = tutorialDecoration(island)
	if existing then
		return existing, "AlreadyAttached"
	end

	local source = template()
	if not source then
		island:SetAttribute(
			"TutorialIslandTemplateStatus",
			"Missing"
		)
		return nil, "TemplateMissing"
	end

	local decoration = source:Clone()
	decoration.Name = DECORATION_NAME
	decoration:SetAttribute(
		"TutorialTemplateSource",
		source:GetFullName()
	)
	decoration:SetAttribute(
		"TutorialDecoration",
		true
	)

	local alignmentMode =
		alignDecoration(
			decoration,
			island,
			floor
		)
	prepareDecoration(decoration)
	decoration.Parent = island

	local areaCount = #enemyAreaParts(island)

	island:SetAttribute(
		"ManualTutorialDecorationAttached",
		true
	)
	island:SetAttribute(
		"TutorialIslandTemplateStatus",
		"Attached"
	)
	island:SetAttribute(
		"TutorialIslandTemplateAlignment",
		alignmentMode
	)
	island:SetAttribute(
		"TutorialEnemyAreaCount",
		areaCount
	)

	workspace:SetAttribute(
		"DungeonTutorialIslandTemplateAttached",
		true
	)
	workspace:SetAttribute(
		"DungeonTutorialEnemyAreaCount",
		areaCount
	)

	if areaCount <= 0 then
		warn(
			"[TutorialIslandTemplate] O template foi colocado na Ilha Inicial, "
				.. "mas nenhuma BasePart chamada areaEnemy foi encontrada."
		)
	end

	return decoration, alignmentMode
end

function TutorialIslandTemplateService.GetEnemySpawnCells(
	island,
	requestedAmount,
	gridSize
)
	local areas = enemyAreaParts(island)
	if #areas <= 0 then
		return {}, nil
	end

	local requested = math.max(
		1,
		math.floor(tonumber(requestedAmount) or 1)
	)
	local normalizedGridSize = math.max(
		0.01,
		tonumber(gridSize) or 5
	)
	local candidatesPerArea = math.max(
		9,
		math.ceil(requested * 3 / #areas)
	)
	local axisCount = math.max(
		2,
		math.ceil(math.sqrt(candidatesPerArea))
	)
	local result = {}

	for _, area in ipairs(areas) do
		local insetX = math.min(
			2,
			area.Size.X * 0.15
		)
		local insetZ = math.min(
			2,
			area.Size.Z * 0.15
		)
		local extentX = math.max(
			0,
			area.Size.X / 2 - insetX
		)
		local extentZ = math.max(
			0,
			area.Size.Z / 2 - insetZ
		)

		for row = 1, axisCount do
			for column = 1, axisCount do
				local normalizedX =
					(column - 1)
						/ (axisCount - 1)
						* 2
						- 1
				local normalizedZ =
					(row - 1)
						/ (axisCount - 1)
						* 2
						- 1
				local position =
					area.CFrame:PointToWorldSpace(
						Vector3.new(
							normalizedX * extentX,
							area.Size.Y / 2,
							normalizedZ * extentZ
						)
					)

				table.insert(result, {
					Cell = Vector3.new(
						math.round(
							position.X
								/ normalizedGridSize
						),
						math.round(
							position.Y
								/ normalizedGridSize
						),
						math.round(
							position.Z
								/ normalizedGridSize
						)
					),
					WorldPosition = position,
					SurfacePosition = position,
					TutorialEnemyArea = area,
				})
			end
		end
	end

	return result, areas[1]
end

return table.freeze(TutorialIslandTemplateService)
