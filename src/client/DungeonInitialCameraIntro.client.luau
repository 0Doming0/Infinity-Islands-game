--[[
	Infinity Islands - Initial Island Camera Intro V1

	A primeira entrada mostra a ilha a partir de uma camera alta voltada para o
	ExitAnchor. A transicao e apenas local: nao move o personagem e nao interfere
	com checkpoints. Durante a apresentacao, movimento e ataque ficam bloqueados.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local VERSION = "InitialIslandCameraIntroV1"
local CAMERA_BIND = "DungeonInitialCameraIntro"
local INPUT_ACTION = "DungeonInitialCameraIntroBlock"
local INPUT_PRIORITY = 10000
local INTRO_DURATION_SECONDS = 3.4
local TARGET_WAIT_SECONDS = 8
local START_HEIGHT = 38
local START_BACK_DISTANCE = 24

local played = false
local controlsBlocked = false
local playerControls

local function smoothstep(alpha)
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function sinkInput()
	return Enum.ContextActionResult.Sink
end

local function resolvePlayerControls()
	if playerControls then
		return playerControls
	end

	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end

	local ok, controls = pcall(function()
		return require(module):GetControls()
	end)
	if ok then
		playerControls = controls
	end
	return playerControls
end

local function setControlsBlocked(character, blocked)
	if blocked == controlsBlocked then
		return
	end
	controlsBlocked = blocked

	if character and character.Parent then
		character:SetAttribute("MovementLocked", blocked and true or nil)
		character:SetAttribute("DungeonInitialCameraIntroLocked", blocked and true or nil)
	end

	if blocked then
		ContextActionService:BindActionAtPriority(
			INPUT_ACTION,
			sinkInput,
			false,
			INPUT_PRIORITY,
			Enum.KeyCode.W,
			Enum.KeyCode.A,
			Enum.KeyCode.S,
			Enum.KeyCode.D,
			Enum.KeyCode.Up,
			Enum.KeyCode.Down,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right,
			Enum.KeyCode.Space,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.ButtonL3,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.Thumbstick1,
			Enum.UserInputType.MouseButton1,
			Enum.UserInputType.MouseButton2,
			Enum.UserInputType.Touch
		)
		local controls = resolvePlayerControls()
		if controls then
			controls:Disable()
		end
	else
		ContextActionService:UnbindAction(INPUT_ACTION)
		local controls = resolvePlayerControls()
		if controls then
			controls:Enable()
		end
	end
end

local function rootParts(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function initialIsland(root)
	local desiredIndex = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	if not desiredIndex or desiredIndex < 1 then
		desiredIndex = 1
	end

	local closest
	local closestDistance = math.huge
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") then
			local index = tonumber(instance:GetAttribute("GlobalIslandIndex"))
			if index and math.floor(index) == math.floor(desiredIndex) then
				return instance
			end
			if tonumber(instance:GetAttribute("GlobalIslandIndex")) == 1 and root then
				local bounds = instance:GetBoundingBox()
				local distance = (bounds.Position - root.Position).Magnitude
				if distance < closestDistance then
					closest = instance
					closestDistance = distance
				end
			end
		end
	end
	return closest
end

local function exitAnchor(island)
	if not island then
		return nil
	end
	for _, name in ipairs({ "ExitAnchor", "Exit" }) do
		local anchor = island:FindFirstChild(name, true)
		if anchor and anchor:IsA("BasePart") then
			return anchor
		end
	end
	return nil
end

local function findIntroTarget()
	local character = player.Character
	local humanoid, root = rootParts(character)
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end

	if player:GetAttribute("InitialSpawnPositioned") ~= true then
		return nil
	end
	local currentIslandIndex = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	if currentIslandIndex and math.floor(currentIslandIndex) > 1 then
		return nil
	end

	local island = initialIsland(root)
	local exit = exitAnchor(island)
	if not exit then
		return nil
	end

	return character, humanoid, root, exit
end

local function playIntro(character, humanoid, root, exit)
	local camera = Workspace.CurrentCamera
	if not camera or not camera.Parent then
		return false
	end

	local saved = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
	}

	local exitPosition = exit.Position + Vector3.new(0, 2.5, 0)
	local away = Vector3.new(
		root.Position.X - exitPosition.X,
		0,
		root.Position.Z - exitPosition.Z
	)
	if away.Magnitude < 0.1 then
		away = -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, 1)
	end
	away = away.Unit

	local startPosition = root.Position + away * START_BACK_DISTANCE + Vector3.new(0, START_HEIGHT, 0)
	local startCFrame = CFrame.lookAt(startPosition, exitPosition, Vector3.yAxis)
	local startFocus = CFrame.new(exitPosition)

	setControlsBlocked(character, true)
	player:SetAttribute("DungeonInitialCameraIntroState", "Playing")
	player:SetAttribute("DungeonInitialCameraIntroStartedAt", Workspace:GetServerTimeNow())
	player:SetAttribute("DungeonInitialCameraIntroTarget", exit:GetFullName())
	player:SetAttribute("DungeonInitialCameraIntroDuration", INTRO_DURATION_SECONDS)
	camera.CameraType = Enum.CameraType.Scriptable

	local startedAt = os.clock()
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 30, function()
		local elapsed = os.clock() - startedAt
		local alpha = smoothstep(elapsed / INTRO_DURATION_SECONDS)
		camera.CFrame = startCFrame:Lerp(saved.CFrame, alpha)
		camera.Focus = startFocus:Lerp(saved.Focus, alpha)
		camera.FieldOfView = saved.FieldOfView
	end)

	while character.Parent and player.Character == character and os.clock() - startedAt < INTRO_DURATION_SECONDS do
		RunService.RenderStepped:Wait()
	end

	RunService:UnbindFromRenderStep(CAMERA_BIND)
	if camera.Parent then
		camera.FieldOfView = saved.FieldOfView
		camera.CameraType = saved.CameraType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or saved.CameraType
		camera.CameraSubject = (saved.CameraSubject and saved.CameraSubject.Parent and saved.CameraSubject) or humanoid
	end

	setControlsBlocked(character, false)
	player:SetAttribute("DungeonInitialCameraIntroState", "Completed")
	player:SetAttribute("DungeonInitialCameraIntroCompletedAt", Workspace:GetServerTimeNow())
	return true
end

local function startOnce()
	if played then
		return
	end
	played = true
	player:SetAttribute("DungeonInitialCameraIntroState", "WaitingForInitialIsland")

	local deadline = os.clock() + TARGET_WAIT_SECONDS
	repeat
		local character, humanoid, root, exit = findIntroTarget()
		if character and humanoid and root and exit then
			playIntro(character, humanoid, root, exit)
			return
		end
		task.wait(0.1)
	until os.clock() >= deadline

	player:SetAttribute("DungeonInitialCameraIntroState", "SkippedTargetUnavailable")
end

player.CharacterAdded:Connect(function()
	if not played then
		task.defer(startOnce)
	end
end)

player:SetAttribute("DungeonInitialCameraIntroLoaded", true)
player:SetAttribute("DungeonInitialCameraIntroVersion", VERSION)
task.defer(startOnce)

script.Destroying:Connect(function()
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	setControlsBlocked(player.Character, false)
end)
