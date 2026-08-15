local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local POLICY = "PlayerFollowRouteCameraMobileV5"
local CAMERA_HEIGHT = 28
local CAMERA_DISTANCE = 22
local CAMERA_FOV = 70
local POSITION_SMOOTH_SPEED = 10
local ROTATION_SMOOTH_SPEED = 12
local MIN_ROUTE_LENGTH = 0.05
local OBSTRUCTION_PADDING = 1.5
local FOCUS_TOWARD_TARGET_FRACTION = 0.2

local active = false
local renderBound = false
local cameraCFrame
local savedCameraType
local savedCameraSubject
local savedCameraFov
local characterConnections = {}
local lastRouteDirection
local lastRouteSideCenter

local function disconnectCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function getCharacterParts()
	local character = player.Character
	if not character or not character:IsDescendantOf(Workspace) then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or not root:IsDescendantOf(character) then
		return character, humanoid, nil
	end
	return character, humanoid, root
end

local function horizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude < MIN_ROUTE_LENGTH then
		return nil
	end
	return horizontal.Unit
end

local function findAnchor(container, names)
	if not container then
		return nil
	end
	for _, name in ipairs(names) do
		local instance = container:FindFirstChild(name, true)
		if instance and instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

local function getCurrentIslandIndex()
	local value = tonumber(
		player:GetAttribute("CurrentGlobalIslandIndex")
			or Workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or Workspace:GetAttribute("DungeonCurrentObjectiveIsland")
	)
	return value and math.floor(value) or nil
end

local function getIslandByIndex(index, root)
	local indexedIsland
	local nearestIsland
	local nearestDistance = math.huge

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") and tonumber(instance:GetAttribute("GlobalIslandIndex")) then
			local islandIndex = math.floor(tonumber(instance:GetAttribute("GlobalIslandIndex")))
			if index and islandIndex == index then
				indexedIsland = instance
				break
			end
			if root then
				local boundsCFrame = instance:GetBoundingBox()
				local distance = (boundsCFrame.Position - root.Position).Magnitude
				if distance < nearestDistance then
					nearestIsland = instance
					nearestDistance = distance
				end
			end
		end
	end

	return indexedIsland or nearestIsland
end

local function getExitSideTarget(island)
	if not island then
		return nil, nil, nil
	end
	local exit = findAnchor(island, { "ExitAnchor", "Exit" })
	if not exit then
		return nil, nil, nil
	end

	local boundsCFrame, boundsSize = island:GetBoundingBox()
	local exitPosition = boundsCFrame:PointToObjectSpace(exit.Position)
	local halfSize = boundsSize * 0.5
	local distances = {
		{ math.abs(halfSize.X - exitPosition.X), Vector3.new(1, 0, 0), Vector3.new(halfSize.X, 0, 0) },
		{ math.abs(-halfSize.X - exitPosition.X), Vector3.new(-1, 0, 0), Vector3.new(-halfSize.X, 0, 0) },
		{ math.abs(halfSize.Z - exitPosition.Z), Vector3.new(0, 0, 1), Vector3.new(0, 0, halfSize.Z) },
		{ math.abs(-halfSize.Z - exitPosition.Z), Vector3.new(0, 0, -1), Vector3.new(0, 0, -halfSize.Z) },
	}

	local closest = distances[1]
	for index = 2, #distances do
		if distances[index][1] < closest[1] then
			closest = distances[index]
		end
	end

	local sideNormal = boundsCFrame:VectorToWorldSpace(closest[2])
	local sideCenter = boundsCFrame:PointToWorldSpace(closest[3])
	return horizontalUnit(sideNormal), sideCenter, exit.Position
end

local function getCameraTarget(root)
	local playerPosition = root.Position
	local island = getIslandByIndex(getCurrentIslandIndex(), root)
	local sideDirection, sideCenter = getExitSideTarget(island)
	if sideDirection and sideCenter and root:IsDescendantOf(Workspace) then
		lastRouteDirection = sideDirection
		lastRouteSideCenter = sideCenter
	else
		sideDirection = lastRouteDirection
		sideCenter = lastRouteSideCenter
	end

	if sideDirection and sideCenter then
		local focus = Vector3.new(
			playerPosition.X + (sideCenter.X - playerPosition.X) * FOCUS_TOWARD_TARGET_FRACTION,
			playerPosition.Y + (sideCenter.Y - playerPosition.Y) * FOCUS_TOWARD_TARGET_FRACTION,
			playerPosition.Z + (sideCenter.Z - playerPosition.Z) * FOCUS_TOWARD_TARGET_FRACTION
		)
		return sideDirection, focus, sideCenter, playerPosition
	end

	local override = Workspace:GetAttribute("DungeonMobileCameraForwardOverride")
	local overrideDirection = typeof(override) == "Vector3" and horizontalUnit(override) or nil
	if not overrideDirection then
		overrideDirection = lastRouteDirection or Vector3.new(0, 0, -1)
	end

	local focusOverride = Workspace:GetAttribute("DungeonMobileCameraFocusWorldOverride")
	if typeof(focusOverride) == "Vector3" then
		local focus = Vector3.new(
			playerPosition.X + (focusOverride.X - playerPosition.X) * FOCUS_TOWARD_TARGET_FRACTION,
			playerPosition.Y + (focusOverride.Y - playerPosition.Y) * FOCUS_TOWARD_TARGET_FRACTION,
			playerPosition.Z + (focusOverride.Z - playerPosition.Z) * FOCUS_TOWARD_TARGET_FRACTION
		)
		return overrideDirection, focus, focusOverride, playerPosition
	end

	local fallbackCenter = lastRouteSideCenter or (
		playerPosition + overrideDirection * 8
	)
	local fallbackFocus = Vector3.new(
		playerPosition.X + (fallbackCenter.X - playerPosition.X) * FOCUS_TOWARD_TARGET_FRACTION,
		playerPosition.Y + (fallbackCenter.Y - playerPosition.Y) * FOCUS_TOWARD_TARGET_FRACTION,
		playerPosition.Z + (fallbackCenter.Z - playerPosition.Z) * FOCUS_TOWARD_TARGET_FRACTION
	)
	return overrideDirection, fallbackFocus, fallbackCenter, playerPosition
end

local function getHumanoidModel(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildWhichIsA("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getCameraPosition(root, direction, focus)
	local desiredPosition = root.Position - direction * CAMERA_DISTANCE
		+ Vector3.new(0, CAMERA_HEIGHT, 0)

	local rayOrigin = focus
	local rayDirection = desiredPosition - rayOrigin
	if rayDirection.Magnitude > 0.1 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude

		local exclusions = {}
		if player.Character then
			table.insert(exclusions, player.Character)
		end
		params.FilterDescendantsInstances = exclusions

		for _ = 1, 32 do
			local hit = Workspace:Raycast(rayOrigin, rayDirection, params)
			if not hit then
				break
			end

			local humanoidModel = getHumanoidModel(hit.Instance)
			if not humanoidModel then
				desiredPosition = hit.Position + (rayDirection.Unit * -OBSTRUCTION_PADDING)
				break
			end

			table.insert(exclusions, humanoidModel)
			params.FilterDescendantsInstances = exclusions
		end
	end

	return desiredPosition
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = savedCameraType or Enum.CameraType.Custom
	if savedCameraSubject and savedCameraSubject.Parent then
		camera.CameraSubject = savedCameraSubject
	else
		local _, humanoid = getCharacterParts()
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	if savedCameraFov then
		camera.FieldOfView = savedCameraFov
	end
	cameraCFrame = nil
end

local function prepareCamera(camera)
	if not camera then
		return false
	end
	if not savedCameraType then
		savedCameraType = camera.CameraType
		savedCameraSubject = camera.CameraSubject
		savedCameraFov = camera.FieldOfView
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CAMERA_FOV
	return true
end

local function updateCamera(deltaTime)
	if not active then
		return
	end

	local camera = Workspace.CurrentCamera
	local _, _, root = getCharacterParts()
	if not camera or not root or not prepareCamera(camera) then
		return
	end

	local direction, focus, sideCenter, playerPosition = getCameraTarget(root)
	local desiredPosition = getCameraPosition(root, direction, focus)
	local desiredCFrame = CFrame.lookAt(desiredPosition, focus, Vector3.new(0, 1, 0))

	local positionAlpha = 1 - math.exp(-POSITION_SMOOTH_SPEED * math.max(deltaTime, 0))
	local position
	if cameraCFrame then
		position = cameraCFrame.Position:Lerp(desiredPosition, positionAlpha)
	else
		position = desiredPosition
	end

	cameraCFrame = CFrame.lookAt(position, focus, Vector3.new(0, 1, 0))
	camera.CFrame = cameraCFrame
	camera.Focus = CFrame.new(focus)

	player:SetAttribute("DungeonMobileCameraActive", true)
	player:SetAttribute("DungeonMobileCameraMode", "RouteFollowScriptable")
	player:SetAttribute("DungeonMobileCameraPolicy", POLICY)
	player:SetAttribute("DungeonMobileCameraRotationPolicy", "LockedToExitSideCenter")
	player:SetAttribute("DungeonMobileCameraTouchRotationDisabled", true)
	player:SetAttribute("DungeonMobileCameraForward", direction)
	player:SetAttribute("DungeonMobileCameraFocusWorld", focus)
	player:SetAttribute("DungeonMobileCameraSideCenterWorld", sideCenter)
	player:SetAttribute("DungeonMobileCameraPlayerPositionWorld", playerPosition)
end

local function bindCharacter(character)
	disconnectCharacterConnections()
	if not character then
		return
	end
	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			task.defer(function()
				cameraCFrame = nil
			end)
		end
	end))
end

local function activate()
	if active then
		return
	end
	active = true
	bindCharacter(player.Character)
	player:SetAttribute("DungeonMobileCameraReady", true)
	player:SetAttribute("DungeonMobileCameraVersion", POLICY)
	player:SetAttribute("DungeonMobileCameraTouchRotationDisabled", true)
	if not renderBound then
		RunService:BindToRenderStep(
			"DungeonCameraController",
			Enum.RenderPriority.Camera.Value + 1,
			updateCamera
		)
		renderBound = true
	end
end

local function deactivate()
	if not active then
		return
	end
	active = false
	lastRouteDirection = nil
	lastRouteSideCenter = nil
	disconnectCharacterConnections()
	restoreCamera()
	savedCameraType = nil
	savedCameraSubject = nil
	savedCameraFov = nil
	player:SetAttribute("DungeonMobileCameraActive", false)
	player:SetAttribute("DungeonMobileCameraMode", "RobloxDefault")
	player:SetAttribute("DungeonMobileCameraPolicy", "RobloxDefault")
	player:SetAttribute("DungeonMobileCameraTouchRotationDisabled", false)
end

local function smartCameraEligible()
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return false
	end

	if player:GetAttribute("CurrentIsInitialIsland") == true then
		return false
	end

	local currentIslandIndex = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	return currentIslandIndex ~= nil and math.floor(currentIslandIndex) >= 2
end

local function refreshActivation()
	if smartCameraEligible() then
		activate()
	else
		deactivate()
	end
end

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
	cameraCFrame = nil
	lastRouteDirection = nil
	lastRouteSideCenter = nil
	if active then
		task.defer(function()
			local camera = Workspace.CurrentCamera
			if camera then
				cameraCFrame = nil
				prepareCamera(camera)
			end
		end)
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)
player:GetAttributeChangedSignal("CurrentIsInitialIsland"):Connect(refreshActivation)
player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(refreshActivation)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if active then
		cameraCFrame = nil
	end
end)

player:SetAttribute("DungeonMobileCameraControllerLoaded", true)
refreshActivation()

script.Destroying:Connect(function()
	if renderBound then
		RunService:UnbindFromRenderStep("DungeonCameraController")
		renderBound = false
	end
	deactivate()
end)