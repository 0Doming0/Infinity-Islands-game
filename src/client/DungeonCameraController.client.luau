-- Camera inteligente unica para toda a rota mobile, inclusive a ilha inicial.
-- Nao existe mais troca entre camera normal -> camera da ilha inicial -> camera
-- das demais ilhas. No mobile, este controller assume desde o spawn e segue o
-- jogador pela rota inteira. Cameras temporarias de transporte continuam tendo
-- prioridade maior durante o voo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local POLICY = "LinearSmartMobileCameraV6_AllIslands"
local CAMERA_BIND = "DungeonCameraController"
local CAMERA_HEIGHT = 28
local CAMERA_DISTANCE = 22
local CAMERA_FOV = 70
local POSITION_SMOOTH_SPEED = 7
local ROTATION_SMOOTH_SPEED = 8
local FOV_SMOOTH_SPEED = 6
local MIN_ROUTE_LENGTH = 0.05
local OBSTRUCTION_PADDING = 1.5
local FOCUS_TOWARD_TARGET_FRACTION = 0.2

local active = false
local renderBound = false
local cameraCFrame
local cameraFocusPosition
local savedCameraType
local savedCameraSubject
local savedCameraFov
local lastRouteDirection
local lastRouteSideCenter

local function isMobileDevice()
	-- DungeonMobileMode continua sendo a autoridade quando o perfil ja carregou,
	-- mas TouchEnabled elimina a janela de alguns frames no primeiro spawn.
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
end

local function characterParts()
	local character = player.Character
	if not character or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
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

local function currentIslandIndex()
	local value = tonumber(
		player:GetAttribute("CurrentGlobalIslandIndex")
			or Workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or Workspace:GetAttribute("DungeonCurrentObjectiveIsland")
	)
	if value then
		return math.max(1, math.floor(value))
	end
	-- Antes do primeiro atributo replicar, o jogador ja esta fisicamente na
	-- primeira ilha. Tratar esse instante como ilha 1 evita cair na camera normal.
	return 1
end

local function islandByIndex(index, root)
	local exact
	local nearest
	local nearestDistance = math.huge

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") then
			local candidateIndex = tonumber(instance:GetAttribute("GlobalIslandIndex"))
			if candidateIndex then
				candidateIndex = math.floor(candidateIndex)
				if candidateIndex == index then
					exact = instance
					break
				end
				if root then
					local bounds = instance:GetBoundingBox()
					local distance = (bounds.Position - root.Position).Magnitude
					if distance < nearestDistance then
						nearest = instance
						nearestDistance = distance
					end
				end
			end
		end
	end
	return exact or nearest
end

local function exitSideTarget(island)
	if not island then
		return nil
	end
	local exit = findAnchor(island, { "ExitAnchor", "Exit" })
	if not exit then
		return nil
	end

	local boundsCFrame, boundsSize = island:GetBoundingBox()
	local exitLocal = boundsCFrame:PointToObjectSpace(exit.Position)
	local half = boundsSize * 0.5
	local candidates = {
		{ math.abs(half.X - exitLocal.X), Vector3.new(1, 0, 0), Vector3.new(half.X, 0, 0) },
		{ math.abs(-half.X - exitLocal.X), Vector3.new(-1, 0, 0), Vector3.new(-half.X, 0, 0) },
		{ math.abs(half.Z - exitLocal.Z), Vector3.new(0, 0, 1), Vector3.new(0, 0, half.Z) },
		{ math.abs(-half.Z - exitLocal.Z), Vector3.new(0, 0, -1), Vector3.new(0, 0, -half.Z) },
	}
	local closest = candidates[1]
	for i = 2, #candidates do
		if candidates[i][1] < closest[1] then
			closest = candidates[i]
		end
	end

	local direction = horizontalUnit(boundsCFrame:VectorToWorldSpace(closest[2]))
	local sideCenter = boundsCFrame:PointToWorldSpace(closest[3])
	return direction, sideCenter
end

local function routeTarget(root)
	local playerPosition = root.Position
	local island = islandByIndex(currentIslandIndex(), root)
	local direction, sideCenter = exitSideTarget(island)

	if direction and sideCenter then
		lastRouteDirection = direction
		lastRouteSideCenter = sideCenter
	else
		direction = lastRouteDirection
		sideCenter = lastRouteSideCenter
	end

	if not direction then
		direction = horizontalUnit(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	end
	if not sideCenter then
		sideCenter = playerPosition + direction * 8
	end

	local focus = Vector3.new(
		playerPosition.X + (sideCenter.X - playerPosition.X) * FOCUS_TOWARD_TARGET_FRACTION,
		playerPosition.Y + (sideCenter.Y - playerPosition.Y) * FOCUS_TOWARD_TARGET_FRACTION,
		playerPosition.Z + (sideCenter.Z - playerPosition.Z) * FOCUS_TOWARD_TARGET_FRACTION
	)
	return direction, focus, sideCenter
end

local function humanoidModel(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildWhichIsA("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function cameraPosition(root, direction, focus)
	local desired = root.Position - direction * CAMERA_DISTANCE
		+ Vector3.new(0, CAMERA_HEIGHT, 0)
	local rayDirection = desired - focus
	if rayDirection.Magnitude <= 0.1 then
		return desired
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}
	if player.Character then
		table.insert(excluded, player.Character)
	end
	params.FilterDescendantsInstances = excluded

	for _ = 1, 24 do
		local hit = Workspace:Raycast(focus, rayDirection, params)
		if not hit then
			break
		end
		local model = humanoidModel(hit.Instance)
		if not model then
			desired = hit.Position - rayDirection.Unit * OBSTRUCTION_PADDING
			break
		end
		table.insert(excluded, model)
		params.FilterDescendantsInstances = excluded
	end
	return desired
end

local function captureCamera(camera)
	if savedCameraType ~= nil then
		return
	end
	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject
	savedCameraFov = camera.FieldOfView
	cameraCFrame = camera.CFrame
	cameraFocusPosition = camera.Focus.Position
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		if savedCameraSubject and savedCameraSubject.Parent then
			camera.CameraSubject = savedCameraSubject
		else
			local _, humanoid = characterParts()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		if savedCameraFov then
			camera.FieldOfView = savedCameraFov
		end
	end
	savedCameraType = nil
	savedCameraSubject = nil
	savedCameraFov = nil
	cameraCFrame = nil
	cameraFocusPosition = nil
end

local function updateCamera(deltaTime)
	if not active then
		return
	end
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		-- O transporte possui camera propria com prioridade maior. Nao brigamos
		-- com ela; ao terminar, a camera linear retoma no frame seguinte.
		return
	end

	local camera = Workspace.CurrentCamera
	local _, _, root = characterParts()
	if not camera or not root then
		return
	end
	captureCamera(camera)
	camera.CameraType = Enum.CameraType.Scriptable

	local direction, focus, sideCenter = routeTarget(root)
	local desiredPosition = cameraPosition(root, direction, focus)
	local positionAlpha = 1 - math.exp(-POSITION_SMOOTH_SPEED * math.max(deltaTime, 0))
	local rotationAlpha = 1 - math.exp(-ROTATION_SMOOTH_SPEED * math.max(deltaTime, 0))
	local fovAlpha = 1 - math.exp(-FOV_SMOOTH_SPEED * math.max(deltaTime, 0))

	cameraCFrame = cameraCFrame or camera.CFrame
	cameraFocusPosition = cameraFocusPosition or focus
	local position = cameraCFrame.Position:Lerp(desiredPosition, positionAlpha)
	cameraFocusPosition = cameraFocusPosition:Lerp(focus, rotationAlpha)
	if (cameraFocusPosition - position).Magnitude < 0.1 then
		cameraFocusPosition = position + direction * CAMERA_DISTANCE
	end
	cameraCFrame = CFrame.lookAt(position, cameraFocusPosition, Vector3.yAxis)
	camera.CFrame = cameraCFrame
	camera.Focus = CFrame.new(cameraFocusPosition)
	camera.FieldOfView += (CAMERA_FOV - camera.FieldOfView) * fovAlpha

	player:SetAttribute("DungeonMobileCameraActive", true)
	player:SetAttribute("DungeonMobileCameraMode", "LinearRouteFollow")
	player:SetAttribute("DungeonMobileCameraPolicy", POLICY)
	player:SetAttribute("DungeonMobileCameraTouchRotationDisabled", true)
	player:SetAttribute("DungeonMobileCameraForward", direction)
	player:SetAttribute("DungeonMobileCameraFocusWorld", cameraFocusPosition)
	player:SetAttribute("DungeonMobileCameraSideCenterWorld", sideCenter)
end

local function eligible()
	if not isMobileDevice() then
		return false
	end
	if player:GetAttribute("DungeonMVPVictory") == true then
		return false
	end
	return currentIslandIndex() >= 1
end

local function activate()
	if active then
		return
	end
	active = true
	player:SetAttribute("DungeonMobileCameraReady", true)
	player:SetAttribute("DungeonMobileCameraVersion", POLICY)
	player:SetAttribute("DungeonMobileCameraTouchRotationDisabled", true)
	if not renderBound then
		RunService:BindToRenderStep(
			CAMERA_BIND,
			Enum.RenderPriority.Camera.Value + 10,
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
	restoreCamera()
	player:SetAttribute("DungeonMobileCameraActive", false)
	player:SetAttribute("DungeonMobileCameraMode", "RobloxDefault")
	player:SetAttribute("DungeonMobileCameraPolicy", "RobloxDefault")
	player:SetAttribute("DungeonMobileCameraTouchRotationDisabled", false)
end

local function refresh()
	if eligible() then
		activate()
	else
		deactivate()
	end
end

player.CharacterAdded:Connect(function()
	cameraCFrame = nil
	cameraFocusPosition = nil
	lastRouteDirection = nil
	lastRouteSideCenter = nil
	task.defer(refresh)
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refresh)
player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
	lastRouteDirection = nil
	lastRouteSideCenter = nil
	refresh()
end)
player:GetAttributeChangedSignal("DungeonMVPVictory"):Connect(refresh)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	cameraCFrame = nil
	cameraFocusPosition = nil
	savedCameraType = nil
	savedCameraSubject = nil
	savedCameraFov = nil
end)

player:SetAttribute("DungeonMobileCameraControllerLoaded", true)
refresh()

script.Destroying:Connect(function()
	if renderBound then
		RunService:UnbindFromRenderStep(CAMERA_BIND)
		renderBound = false
	end
	deactivate()
end)
