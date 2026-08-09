--[[
	Infinity Islands - Task 15
	DungeonCameraController V2 - Portrait Arena Top-Down

	Touch:
	- Scriptable elevated arena camera;
	- portrait remains controlled by InputProfileController;
	- near top-down pitch;
	- fixed/semi-fixed yaw for spatial consistency;
	- movement look-ahead;
	- small combat framing shift toward nearby managed slimes;
	- occlusion safety.

	Desktop/console:
	- this controller releases ownership;
	- Roblox default camera remains unchanged.

	This script DOES NOT:
	- create HUD;
	- auto aim;
	- rotate the player;
	- move the player;
	- attack;
	- choose server combat targets.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Config = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("MobileDungeonCameraConfig")
)

local VERSION = Config.Version
local RENDER_STEP =
	"InfinityIslandsDungeonArenaCameraV2"

local active = false

local currentCamera
local savedCameraState

local character
local rootPart
local humanoid

-- Yaw remains stable instead of following every character turn.
local baseForward =
	Vector3.new(0, 0, -1)

local smoothedMovementLookAhead =
	Vector3.zero

local smoothedCombatFocusShift =
	Vector3.zero

local snapNextFrame = true

local cameraChangeConnection
local characterConnections = {}

local function disconnectCharacterConnections()
	for _, connection in ipairs(
		characterConnections
	) do
		connection:Disconnect()
	end

	table.clear(
		characterConnections
	)
end

local function horizontalUnit(
	vector,
	fallback
)
	local horizontal =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if horizontal.Magnitude <= 0.001 then
		return fallback
			or Vector3.new(0, 0, -1)
	end

	return horizontal.Unit
end

local function numberSetting(
	attributeName,
	defaultValue,
	minimum,
	maximum
)
	local value =
		tonumber(
			player:GetAttribute(
				attributeName
			)
		)

	if value == nil then
		value = defaultValue
	end

	return math.clamp(
		value,
		minimum,
		maximum
	)
end

local function ensureTuningAttributes()
	local attributes = {
		DungeonMobileCameraHeight =
			Config.Height,

		DungeonMobileCameraBackDistance =
			Config.BackDistance,

		DungeonMobileCameraFov =
			Config.FieldOfView,

		DungeonMobileCameraLookAhead =
			Config.MovementLookAhead,

		DungeonMobileCameraForwardBias =
			Config.ForwardBias,

		DungeonMobileCameraFocusHeight =
			Config.FocusHeight,

		DungeonMobileCameraSmoothSpeed =
			Config.SmoothSpeed,

		DungeonMobileCameraCombatFocusRadius =
			Config.CombatFocusRadius,

		DungeonMobileCameraCombatFocusShift =
			Config.CombatFocusMaximumShift,
	}

	for name, value in pairs(
		attributes
	) do
		if player:GetAttribute(name) == nil then
			player:SetAttribute(
				name,
				value
			)
		end
	end
end

local function captureCameraState(camera)
	return {
		CameraType =
			camera.CameraType,

		CameraSubject =
			camera.CameraSubject,

		FieldOfView =
			camera.FieldOfView,

		CFrame =
			camera.CFrame,

		Focus =
			camera.Focus,
	}
end

local function restoreCamera(
	camera,
	state
)
	if not camera
		or not camera.Parent
		or not state
	then
		return
	end

	pcall(function()
		camera.CameraType =
			state.CameraType

		camera.CameraSubject =
			state.CameraSubject

		camera.FieldOfView =
			state.FieldOfView

		camera.CFrame =
			state.CFrame

		camera.Focus =
			state.Focus
	end)
end

local function releaseCamera()
	if currentCamera
		and savedCameraState
	then
		restoreCamera(
			currentCamera,
			savedCameraState
		)
	end

	currentCamera = nil
	savedCameraState = nil

	player:SetAttribute(
		"DungeonMobileCameraActive",
		false
	)
end

local function acquireCamera(camera)
	if not camera then
		return false
	end

	if currentCamera ~= camera then
		if currentCamera
			and savedCameraState
		then
			restoreCamera(
				currentCamera,
				savedCameraState
			)
		end

		currentCamera = camera

		savedCameraState =
			captureCameraState(
				camera
			)
	end

	camera.CameraType =
		Enum.CameraType.Scriptable

	camera.FieldOfView =
		numberSetting(
			"DungeonMobileCameraFov",
			Config.FieldOfView,
			Config.MinimumFOV,
			Config.MaximumFOV
		)

	snapNextFrame = true

	player:SetAttribute(
		"DungeonMobileCameraActive",
		true
	)

	return true
end

local function refreshBaseForward()
	if not rootPart then
		return
	end

	baseForward =
		horizontalUnit(
			rootPart.CFrame.LookVector,
			baseForward
		)

	player:SetAttribute(
		"DungeonMobileCameraBaseForward",
		baseForward
	)
end

local function bindCharacter(
	newCharacter
)
	disconnectCharacterConnections()

	character = newCharacter
	rootPart = nil
	humanoid = nil

	smoothedMovementLookAhead =
		Vector3.zero

	smoothedCombatFocusShift =
		Vector3.zero

	snapNextFrame = true

	if not character then
		return
	end

	local function refreshCharacterParts()
		rootPart =
			character
				and character:FindFirstChild(
					"HumanoidRootPart"
				)

		humanoid =
			character
				and character
					:FindFirstChildOfClass(
						"Humanoid"
					)

		if rootPart then
			refreshBaseForward()
			snapNextFrame = true
		end
	end

	table.insert(
		characterConnections,
		character.ChildAdded:Connect(
			function(child)
				if child.Name
						== "HumanoidRootPart"
					or child:IsA("Humanoid")
				then
					task.defer(
						refreshCharacterParts
					)
				end
			end
		)
	)

	table.insert(
		characterConnections,
		character.ChildRemoved:Connect(
			function(child)
				if child == rootPart
					or child == humanoid
				then
					task.defer(
						refreshCharacterParts
					)
				end
			end
		)
	)

	refreshCharacterParts()
end

local function updateBaseForwardFromOverride()
	local override =
		workspace:GetAttribute(
			"DungeonMobileCameraForwardOverride"
		)

	if typeof(override) == "Vector3" then
		local horizontal =
			Vector3.new(
				override.X,
				0,
				override.Z
			)

		if horizontal.Magnitude > 0.001 then
			baseForward =
				horizontal.Unit

			return
		end
	end
end

local function sameCurrentIsland(
	target
)
	local playerIndex =
		tonumber(
			player:GetAttribute(
				"CurrentGlobalIslandIndex"
			)
		)

	local targetIndex =
		tonumber(
			target:GetAttribute(
				"GlobalIslandIndex"
			)
		)

	if not playerIndex
		or not targetIndex
	then
		return true
	end

	return math.floor(playerIndex)
		== math.floor(targetIndex)
end

local function combatTargetPosition(
	target
)
	if not target
		or not target:IsA("Model")
		or not target.Parent
		or target:GetAttribute(
			"IslandCombatManaged"
		) ~= true
		or target:GetAttribute(
			"Peaceful"
		) == true
		or not sameCurrentIsland(
			target
		)
	then
		return nil
	end

	local humanoid =
		target:FindFirstChildWhichIsA(
			"Humanoid",
			true
		)

	if not humanoid
		or humanoid.Health <= 0
	then
		return nil
	end

	local part =
		target:FindFirstChild(
			"HumanoidRootPart",
			true
		)
			or target.PrimaryPart
			or target:FindFirstChildWhichIsA(
				"BasePart",
				true
			)

	return part and part.Position
end

local function desiredCombatFocusShift()
	if Config.CombatFocusEnabled ~= true
		or not rootPart
	then
		return Vector3.zero, 0
	end

	local radius =
		numberSetting(
			"DungeonMobileCameraCombatFocusRadius",
			Config.CombatFocusRadius,
			8,
			32
		)

	local maximumShift =
		numberSetting(
			"DungeonMobileCameraCombatFocusShift",
			Config.CombatFocusMaximumShift,
			0,
			8
		)

	if maximumShift <= 0 then
		return Vector3.zero, 0
	end

	local accumulated =
		Vector3.zero

	local weightTotal = 0
	local count = 0

	for _, target in ipairs(
		CollectionService:GetTagged(
			"CombatTarget"
		)
	) do
		local position =
			combatTargetPosition(
				target
			)

		if not position then
			continue
		end

		local delta =
			Vector3.new(
				position.X
					- rootPart.Position.X,
				0,
				position.Z
					- rootPart.Position.Z
			)

		local distance =
			delta.Magnitude

		if distance <= radius then
			local weight =
				1
					- math.clamp(
						distance / radius,
						0,
						1
					)

			-- Keep distant-but-visible enemies useful for framing.
			weight =
				0.25
					+ weight * 0.75

			accumulated +=
				delta * weight

			weightTotal += weight
			count += 1
		end
	end

	if weightTotal <= 0 then
		return Vector3.zero, 0
	end

	local average =
		accumulated
			/ weightTotal

	local shift =
		average
			* Config.CombatFocusWeight

	if shift.Magnitude > maximumShift then
		shift =
			shift.Unit
				* maximumShift
	end

	return shift,
		count
end

local function occlusionSafePosition(
	focusPosition,
	desiredPosition
)
	if not character then
		return desiredPosition
	end

	local direction =
		desiredPosition
			- focusPosition

	if direction.Magnitude <= 0.01 then
		return desiredPosition
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{ character }

	params.IgnoreWater = true

	local result =
		workspace:Raycast(
			focusPosition,
			direction,
			params
		)

	if not result then
		return desiredPosition
	end

	local padding =
		numberSetting(
			"DungeonMobileCameraOcclusionPadding",
			Config.OcclusionPadding,
			0.5,
			4
		)

	return result.Position
		+ result.Normal * padding
end

local function desiredCameraFrame(
	deltaTime
)
	if not rootPart
		or not rootPart.Parent
	then
		return nil
	end

	updateBaseForwardFromOverride()

	local moveDirection =
		humanoid
			and humanoid.MoveDirection
			or Vector3.zero

	local horizontalMove =
		Vector3.new(
			moveDirection.X,
			0,
			moveDirection.Z
		)

	local movementLookAheadDistance =
		numberSetting(
			"DungeonMobileCameraLookAhead",
			Config.MovementLookAhead,
			0,
			10
		)

	local desiredLookAhead =
		Vector3.zero

	if horizontalMove.Magnitude > 0.05 then
		desiredLookAhead =
			horizontalMove.Unit
				* movementLookAheadDistance
	end

	local lookAheadAlpha =
		1
			- math.exp(
				-Config.LookAheadSmoothSpeed
					* math.max(
						0,
						deltaTime
					)
			)

	smoothedMovementLookAhead =
		smoothedMovementLookAhead:Lerp(
			desiredLookAhead,
			lookAheadAlpha
		)

	local desiredCombatShift,
		combatTargetCount =
			desiredCombatFocusShift()

	local combatAlpha =
		1
			- math.exp(
				-Config.CombatFocusSmoothSpeed
					* math.max(
						0,
						deltaTime
					)
			)

	smoothedCombatFocusShift =
		smoothedCombatFocusShift:Lerp(
			desiredCombatShift,
			combatAlpha
		)

	local height =
		numberSetting(
			"DungeonMobileCameraHeight",
			Config.Height,
			Config.MinimumHeight,
			Config.MaximumHeight
		)

	local backDistance =
		numberSetting(
			"DungeonMobileCameraBackDistance",
			Config.BackDistance,
			Config.MinimumBackDistance,
			Config.MaximumBackDistance
		)

	local forwardBias =
		numberSetting(
			"DungeonMobileCameraForwardBias",
			Config.ForwardBias,
			0,
			8
		)

	local focusHeight =
		numberSetting(
			"DungeonMobileCameraFocusHeight",
			Config.FocusHeight,
			0,
			6
		)

	local focusPosition =
		rootPart.Position
			+ Vector3.new(
				0,
				focusHeight,
				0
			)
			+ baseForward
				* forwardBias
			+ smoothedMovementLookAhead
			+ smoothedCombatFocusShift

	-- Kept as a clean seam for special non-MVP presentation/testing.
	local worldFocusOverride =
		workspace:GetAttribute(
			"DungeonMobileCameraFocusWorldOverride"
		)

	if typeof(worldFocusOverride)
		== "Vector3"
	then
		focusPosition =
			worldFocusOverride
	end

	local desiredPosition =
		focusPosition
			- baseForward
				* backDistance
			+ Vector3.new(
				0,
				height,
				0
			)

	desiredPosition =
		occlusionSafePosition(
			focusPosition,
			desiredPosition
		)

	local desired =
		CFrame.lookAt(
			desiredPosition,
			focusPosition,
			Vector3.new(0, 1, 0)
		)

	local pitchDegrees =
		math.deg(
			math.atan2(
				height,
				backDistance
			)
		)

	local fromVertical =
		90 - pitchDegrees

	player:SetAttribute(
		"DungeonMobileCameraPitchDegrees",
		math.floor(
			pitchDegrees * 10
				+ 0.5
		) / 10
	)

	player:SetAttribute(
		"DungeonMobileCameraDegreesFromVertical",
		math.floor(
			fromVertical * 10
				+ 0.5
		) / 10
	)

	player:SetAttribute(
		"DungeonMobileCameraCombatTargetCount",
		combatTargetCount
	)

	player:SetAttribute(
		"DungeonMobileCameraCombatFocusShift",
		smoothedCombatFocusShift
	)

	return desired,
		focusPosition
end

local function renderCamera(
	deltaTime
)
	if not active
		or player:GetAttribute(
			"DungeonMobileMode"
		) ~= true
	then
		return
	end

	local camera =
		workspace.CurrentCamera

	if not camera then
		return
	end

	if currentCamera ~= camera then
		acquireCamera(camera)
	elseif camera.CameraType
		~= Enum.CameraType.Scriptable
	then
		camera.CameraType =
			Enum.CameraType.Scriptable
	end

	if not rootPart
		or not rootPart.Parent
	then
		if player.Character
			~= character
		then
			bindCharacter(
				player.Character
			)
		end

		return
	end

	local desired,
		focusPosition =
			desiredCameraFrame(
				deltaTime
			)

	if not desired
		or not focusPosition
	then
		return
	end

	camera.FieldOfView =
		numberSetting(
			"DungeonMobileCameraFov",
			Config.FieldOfView,
			Config.MinimumFOV,
			Config.MaximumFOV
		)

	local currentDistance =
		(
			camera.CFrame.Position
				- desired.Position
		).Magnitude

	if snapNextFrame
		or currentDistance
			>= Config.SnapDistance
	then
		camera.CFrame = desired
		snapNextFrame = false
	else
		local smoothSpeed =
			numberSetting(
				"DungeonMobileCameraSmoothSpeed",
				Config.SmoothSpeed,
				2,
				20
			)

		local alpha =
			1
				- math.exp(
					-smoothSpeed
						* math.max(
							0,
							deltaTime
						)
				)

		camera.CFrame =
			camera.CFrame:Lerp(
				desired,
				alpha
			)
	end

	camera.Focus =
		CFrame.new(
			focusPosition
		)

	player:SetAttribute(
		"DungeonMobileCameraPosition",
		camera.CFrame.Position
	)

	player:SetAttribute(
		"DungeonMobileCameraFocus",
		focusPosition
	)
end

local function activate()
	if active
		or player:GetAttribute(
			"DungeonMobileMode"
		) ~= true
	then
		return
	end

	active = true

	ensureTuningAttributes()
	bindCharacter(
		player.Character
	)

	acquireCamera(
		workspace.CurrentCamera
	)

	player:SetAttribute(
		"DungeonMobileCameraReady",
		true
	)

	player:SetAttribute(
		"DungeonMobileCameraVersion",
		VERSION
	)

	player:SetAttribute(
		"DungeonMobileCameraPolicy",
		"PortraitArenaTopDownV2"
	)

	player:SetAttribute(
		"DungeonMobileCameraRotationPolicy",
		"StableYawMovementAndCombatFocus"
	)

	player:SetAttribute(
		"DungeonMobileCameraCombatFocusEnabled",
		Config.CombatFocusEnabled
	)
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

	smoothedMovementLookAhead =
		Vector3.zero

	smoothedCombatFocusShift =
		Vector3.zero

	player:SetAttribute(
		"DungeonMobileCameraActive",
		false
	)
end

local function refreshActivation()
	if player:GetAttribute(
		"DungeonMobileMode"
	) == true
	then
		activate()
	else
		deactivate()
	end
end

player.CharacterAdded:Connect(
	function(newCharacter)
		bindCharacter(
			newCharacter
		)

		if active then
			snapNextFrame = true
		end
	end
)

player:GetAttributeChangedSignal(
	"DungeonMobileMode"
):Connect(
	refreshActivation
)

-- When the player advances to a new island, capture the current facing once.
-- The camera then remains stable through the combat on that island.
player:GetAttributeChangedSignal(
	"CurrentGlobalIslandIndex"
):Connect(function()
	if active
		and rootPart
		and rootPart.Parent
	then
		refreshBaseForward()
		snapNextFrame = true
	end
end)

cameraChangeConnection =
	workspace
		:GetPropertyChangedSignal(
			"CurrentCamera"
		)
		:Connect(function()
			if not active then
				return
			end

			local camera =
				workspace.CurrentCamera

			if camera then
				acquireCamera(
					camera
				)
			end
		end)

RunService:BindToRenderStep(
	RENDER_STEP,
	Enum.RenderPriority.Camera.Value + 1,
	renderCamera
)

player:SetAttribute(
	"DungeonMobileCameraControllerLoaded",
	true
)

player:SetAttribute(
	"DungeonMobileCameraVersion",
	VERSION
)

-- InputProfileController may initialize before or after this LocalScript.
if player:GetAttribute(
	"DungeonInputProfileReady"
) == true
then
	refreshActivation()
else
	local readyConnection

	readyConnection =
		player
			:GetAttributeChangedSignal(
				"DungeonInputProfileReady"
			)
			:Connect(function()
				if player:GetAttribute(
					"DungeonInputProfileReady"
				) == true
				then
					if readyConnection then
						readyConnection:Disconnect()
						readyConnection = nil
					end

					refreshActivation()
				end
			end)

	if player:GetAttribute(
		"DungeonMobileMode"
	) ~= nil
	then
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

	RunService:UnbindFromRenderStep(
		RENDER_STEP
	)
end)
