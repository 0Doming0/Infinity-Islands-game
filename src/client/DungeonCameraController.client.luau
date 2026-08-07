-- Mobile Dungeon Mode — Task 02: portrait camera prototype.
--
-- Depende da Task 01 (InputProfileController.client.luau).
-- So assume a camera quando DungeonMobileMode == true.
-- PC/console continuam usando a camera padrao do Roblox.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local VERSION = "DungeonPortraitCameraV1"
local RENDER_STEP = "InfinityIslandsDungeonPortraitCamera"

local DEFAULTS = {
	Height = 25,
	BackDistance = 14,
	FieldOfView = 70,
	MovementLookAhead = 5.5,
	ForwardBias = 4,
	FocusHeight = 2.2,
	SmoothSpeed = 9,
	LookAheadSmoothSpeed = 8,
	SnapDistance = 55,
	OcclusionPadding = 1.4,
}

local active = false
local currentCamera
local savedCameraState
local character
local rootPart
local humanoid
local baseForward = Vector3.new(0, 0, -1)
local smoothedMovementLookAhead = Vector3.zero
local snapNextFrame = true
local cameraChangeConnection
local characterConnections = {}

local function disconnectCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function horizontalUnit(vector, fallback)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function numberSetting(attributeName, defaultValue, minimum, maximum)
	local value = tonumber(player:GetAttribute(attributeName))
	if value == nil then
		value = defaultValue
	end
	return math.clamp(value, minimum, maximum)
end

local function ensureTuningAttributes()
	local attributes = {
		DungeonMobileCameraHeight = DEFAULTS.Height,
		DungeonMobileCameraBackDistance = DEFAULTS.BackDistance,
		DungeonMobileCameraFov = DEFAULTS.FieldOfView,
		DungeonMobileCameraLookAhead = DEFAULTS.MovementLookAhead,
		DungeonMobileCameraForwardBias = DEFAULTS.ForwardBias,
		DungeonMobileCameraFocusHeight = DEFAULTS.FocusHeight,
		DungeonMobileCameraSmoothSpeed = DEFAULTS.SmoothSpeed,
	}

	for name, value in pairs(attributes) do
		if player:GetAttribute(name) == nil then
			player:SetAttribute(name, value)
		end
	end
end

local function captureCameraState(camera)
	return {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
	}
end

local function restoreCamera(camera, state)
	if not camera or not camera.Parent or not state then
		return
	end

	pcall(function()
		camera.CameraType = state.CameraType
		camera.CameraSubject = state.CameraSubject
		camera.FieldOfView = state.FieldOfView
		camera.CFrame = state.CFrame
		camera.Focus = state.Focus
	end)
end

local function releaseCamera()
	if currentCamera and savedCameraState then
		restoreCamera(currentCamera, savedCameraState)
	end

	currentCamera = nil
	savedCameraState = nil
	player:SetAttribute("DungeonMobileCameraActive", false)
end

local function acquireCamera(camera)
	if not camera then
		return false
	end

	if currentCamera ~= camera then
		if currentCamera and savedCameraState then
			restoreCamera(currentCamera, savedCameraState)
		end
		currentCamera = camera
		savedCameraState = captureCameraState(camera)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = numberSetting(
		"DungeonMobileCameraFov",
		DEFAULTS.FieldOfView,
		50,
		90
	)

	snapNextFrame = true
	player:SetAttribute("DungeonMobileCameraActive", true)
	return true
end

local function bindCharacter(newCharacter)
	disconnectCharacterConnections()

	character = newCharacter
	rootPart = nil
	humanoid = nil
	smoothedMovementLookAhead = Vector3.zero
	snapNextFrame = true

	if not character then
		return
	end

	rootPart = character:FindFirstChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid")

	local function refreshCharacterParts()
		rootPart = character and character:FindFirstChild("HumanoidRootPart")
		humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if rootPart then
			baseForward = horizontalUnit(rootPart.CFrame.LookVector, baseForward)
			player:SetAttribute("DungeonMobileCameraBaseForward", baseForward)
			snapNextFrame = true
		end
	end

	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if child.Name == "HumanoidRootPart" or child:IsA("Humanoid") then
			task.defer(refreshCharacterParts)
		end
	end))

	table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
		if child == rootPart or child == humanoid then
			task.defer(refreshCharacterParts)
		end
	end))

	refreshCharacterParts()
end

local function updateBaseForwardFromOverride()
	local override = workspace:GetAttribute("DungeonMobileCameraForwardOverride")
	if typeof(override) == "Vector3" then
		local horizontal = Vector3.new(override.X, 0, override.Z)
		if horizontal.Magnitude > 0.001 then
			baseForward = horizontal.Unit
			return
		end
	end
end

local function occlusionSafePosition(focusPosition, desiredPosition)
	if not character then
		return desiredPosition
	end

	local direction = desiredPosition - focusPosition
	if direction.Magnitude <= 0.01 then
		return desiredPosition
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = workspace:Raycast(focusPosition, direction, params)
	if not result then
		return desiredPosition
	end

	local padding = numberSetting(
		"DungeonMobileCameraOcclusionPadding",
		DEFAULTS.OcclusionPadding,
		0.5,
		4
	)

	return result.Position + result.Normal * padding
end

local function desiredCameraFrame(deltaTime)
	if not rootPart or not rootPart.Parent then
		return nil
	end

	updateBaseForwardFromOverride()

	local moveDirection = humanoid and humanoid.MoveDirection or Vector3.zero
	local horizontalMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)

	local movementLookAheadDistance = numberSetting(
		"DungeonMobileCameraLookAhead",
		DEFAULTS.MovementLookAhead,
		0,
		10
	)
	local desiredLookAhead = Vector3.zero
	if horizontalMove.Magnitude > 0.05 then
		desiredLookAhead = horizontalMove.Unit * movementLookAheadDistance
	end

	local lookAheadSpeed = DEFAULTS.LookAheadSmoothSpeed
	local lookAheadAlpha = 1 - math.exp(-lookAheadSpeed * math.max(0, deltaTime))
	smoothedMovementLookAhead = smoothedMovementLookAhead:Lerp(
		desiredLookAhead,
		lookAheadAlpha
	)

	local height = numberSetting(
		"DungeonMobileCameraHeight",
		DEFAULTS.Height,
		16,
		38
	)
	local backDistance = numberSetting(
		"DungeonMobileCameraBackDistance",
		DEFAULTS.BackDistance,
		8,
		24
	)
	local forwardBias = numberSetting(
		"DungeonMobileCameraForwardBias",
		DEFAULTS.ForwardBias,
		0,
		10
	)
	local focusHeight = numberSetting(
		"DungeonMobileCameraFocusHeight",
		DEFAULTS.FocusHeight,
		0,
		6
	)

	local focusPosition =
		rootPart.Position
		+ Vector3.new(0, focusHeight, 0)
		+ baseForward * forwardBias
		+ smoothedMovementLookAhead

	-- Task 13+ seam: encounters especiais podem fornecer um foco mundial
	-- sem disputar ownership de Camera.CFrame com este controller.
	local worldFocusOverride = workspace:GetAttribute(
		"DungeonMobileCameraFocusWorldOverride"
	)
	if typeof(worldFocusOverride) == "Vector3" then
		focusPosition = worldFocusOverride
	end

	local desiredPosition =
		focusPosition
		- baseForward * backDistance
		+ Vector3.new(0, height, 0)

	desiredPosition = occlusionSafePosition(focusPosition, desiredPosition)

	local desired = CFrame.lookAt(
		desiredPosition,
		focusPosition,
		Vector3.new(0, 1, 0)
	)

	local pitchDegrees = math.deg(math.atan2(height, backDistance))
	player:SetAttribute(
		"DungeonMobileCameraPitchDegrees",
		math.floor(pitchDegrees * 10 + 0.5) / 10
	)

	return desired, focusPosition
end

local function renderCamera(deltaTime)
	if not active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if currentCamera ~= camera then
		acquireCamera(camera)
	elseif camera.CameraType ~= Enum.CameraType.Scriptable then
		-- Outro sistema tentou tomar a camera. Enquanto esta task estiver ativa,
		-- o modo mobile da Dungeon permanece o dono da camera normal de gameplay.
		camera.CameraType = Enum.CameraType.Scriptable
	end

	if not rootPart or not rootPart.Parent then
		if player.Character ~= character then
			bindCharacter(player.Character)
		end
		return
	end

	local desired, focusPosition = desiredCameraFrame(deltaTime)
	if not desired or not focusPosition then
		return
	end

	camera.FieldOfView = numberSetting(
		"DungeonMobileCameraFov",
		DEFAULTS.FieldOfView,
		50,
		90
	)

	local snapDistance = DEFAULTS.SnapDistance
	local currentDistance = (camera.CFrame.Position - desired.Position).Magnitude
	if snapNextFrame or currentDistance >= snapDistance then
		camera.CFrame = desired
		snapNextFrame = false
	else
		local smoothSpeed = numberSetting(
			"DungeonMobileCameraSmoothSpeed",
			DEFAULTS.SmoothSpeed,
			2,
			18
		)
		local alpha = 1 - math.exp(-smoothSpeed * math.max(0, deltaTime))
		camera.CFrame = camera.CFrame:Lerp(desired, alpha)
	end

	-- Focus ajuda sistemas de render/streaming a manterem a regiao do jogador
	-- como ponto importante mesmo usando CameraType.Scriptable.
	camera.Focus = CFrame.new(focusPosition)

	player:SetAttribute("DungeonMobileCameraPosition", camera.CFrame.Position)
	player:SetAttribute("DungeonMobileCameraFocus", focusPosition)
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	ensureTuningAttributes()
	bindCharacter(player.Character)
	acquireCamera(workspace.CurrentCamera)

	player:SetAttribute("DungeonMobileCameraReady", true)
	player:SetAttribute("DungeonMobileCameraVersion", VERSION)
	player:SetAttribute("DungeonMobileCameraPolicy", "PortraitElevatedSemiFixedFocusOverrideV2")
end

local function deactivate()
	if not active then
		return
	end

	active = false
	releaseCamera()
	disconnectCharacterConnections()

	character = nil
	rootPart = nil
	humanoid = nil
	smoothedMovementLookAhead = Vector3.zero

	player:SetAttribute("DungeonMobileCameraActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

player.CharacterAdded:Connect(function(newCharacter)
	bindCharacter(newCharacter)
	if active then
		snapNextFrame = true
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

cameraChangeConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if not active then
		return
	end

	local camera = workspace.CurrentCamera
	if camera then
		acquireCamera(camera)
	end
end)

RunService:BindToRenderStep(
	RENDER_STEP,
	Enum.RenderPriority.Camera.Value + 1,
	renderCamera
)

player:SetAttribute("DungeonMobileCameraControllerLoaded", true)
player:SetAttribute("DungeonMobileCameraVersion", VERSION)

-- A Task 01 pode iniciar antes ou depois deste LocalScript.
if player:GetAttribute("DungeonInputProfileReady") == true then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal("DungeonInputProfileReady"):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)

	-- Fallback: se o atributo DungeonMobileMode ja existir, nao precisamos
	-- aguardar explicitamente o Ready.
	if player:GetAttribute("DungeonMobileMode") ~= nil then
		if readyConnection then
			readyConnection:Disconnect()
			readyConnection = nil
		end
		refreshActivation()
	end
end

script.Destroying:Connect(function()
	deactivate()
	if cameraChangeConnection then
		cameraChangeConnection:Disconnect()
		cameraChangeConnection = nil
	end
	RunService:UnbindFromRenderStep(RENDER_STEP)
end)
