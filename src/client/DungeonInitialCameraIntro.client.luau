-- Apresentacao cinematografica inicial apenas para desktop/gamepad.
-- No mobile nao existe mais uma etapa de camera normal: DungeonCameraController
-- assume a camera inteligente desde o spawn da primeira ilha.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local VERSION = "InitialIslandCameraIntroV3_DesktopOnly"
local CAMERA_BIND = "DungeonInitialCameraIntro"
local INPUT_ACTION = "DungeonInitialCameraIntroBlock"
local INTRO_DURATION = 3.4
local TARGET_WAIT = 8
local START_HEIGHT = 38
local START_BACK = 24
local played = false
local blocked = false
local controls

local function isMobile()
	return UserInputService.TouchEnabled == true
		or player:GetAttribute("DungeonMobileMode") == true
end

local function playerControls()
	if controls then
		return controls
	end
	local scripts = player:FindFirstChildOfClass("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return require(module):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function sink()
	return Enum.ContextActionResult.Sink
end

local function setBlocked(character, value)
	if blocked == value then
		return
	end
	blocked = value
	if character and character.Parent then
		character:SetAttribute("MovementLocked", value and true or nil)
		character:SetAttribute("DungeonInitialCameraIntroLocked", value and true or nil)
	end
	if value then
		ContextActionService:BindActionAtPriority(
			INPUT_ACTION,
			sink,
			false,
			10000,
			Enum.KeyCode.W,
			Enum.KeyCode.A,
			Enum.KeyCode.S,
			Enum.KeyCode.D,
			Enum.KeyCode.Space,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.Thumbstick1,
			Enum.UserInputType.MouseButton1
		)
		local current = playerControls()
		if current then
			current:Disable()
		end
	else
		ContextActionService:UnbindAction(INPUT_ACTION)
		local current = playerControls()
		if current then
			current:Enable()
		end
	end
end

local function characterParts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return character, humanoid, root
end

local function firstIsland(root)
	local closest
	local closestDistance = math.huge
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") and tonumber(instance:GetAttribute("GlobalIslandIndex")) == 1 then
			if not root then
				return instance
			end
			local bounds = instance:GetBoundingBox()
			local distance = (bounds.Position - root.Position).Magnitude
			if distance < closestDistance then
				closest = instance
				closestDistance = distance
			end
		end
	end
	return closest
end

local function exitAnchor(island)
	if not island then
		return nil
	end
	local exit = island:FindFirstChild("ExitAnchor", true)
		or island:FindFirstChild("Exit", true)
	return exit and exit:IsA("BasePart") and exit or nil
end

local function playIntro(character, humanoid, root, exit)
	if isMobile() then
		return false
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end

	local savedType = camera.CameraType
	local savedSubject = camera.CameraSubject
	local savedFov = camera.FieldOfView
	local savedCFrame = camera.CFrame
	local savedFocus = camera.Focus

	local focusPosition = exit.Position + Vector3.new(0, 2.5, 0)
	local away = Vector3.new(
		root.Position.X - focusPosition.X,
		0,
		root.Position.Z - focusPosition.Z
	)
	if away.Magnitude <= 0.1 then
		away = -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if away.Magnitude <= 0.1 then
		away = Vector3.new(0, 0, 1)
	end
	away = away.Unit
	local startPosition = root.Position + away * START_BACK + Vector3.new(0, START_HEIGHT, 0)
	local startCFrame = CFrame.lookAt(startPosition, focusPosition, Vector3.yAxis)
	local startFocus = CFrame.new(focusPosition)

	setBlocked(character, true)
	player:SetAttribute("DungeonInitialCameraIntroState", "PlayingDesktop")
	camera.CameraType = Enum.CameraType.Scriptable

	local startedAt = os.clock()
	RunService:BindToRenderStep(
		CAMERA_BIND,
		Enum.RenderPriority.Camera.Value + 30,
		function()
			if isMobile() then
				return
			end
			local linear = math.clamp((os.clock() - startedAt) / INTRO_DURATION, 0, 1)
			local alpha = linear * linear * (3 - 2 * linear)
			camera.CFrame = startCFrame:Lerp(savedCFrame, alpha)
			camera.Focus = startFocus:Lerp(savedFocus, alpha)
			camera.FieldOfView = savedFov
		end
	)

	while player.Character == character
		and character.Parent
		and not isMobile()
		and os.clock() - startedAt < INTRO_DURATION
	do
		RunService.RenderStepped:Wait()
	end

	RunService:UnbindFromRenderStep(CAMERA_BIND)
	if camera.Parent and not isMobile() then
		camera.CameraType = savedType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or savedType
		camera.CameraSubject = (savedSubject and savedSubject.Parent and savedSubject) or humanoid
		camera.FieldOfView = savedFov
	end
	setBlocked(character, false)
	player:SetAttribute("DungeonInitialCameraIntroState", isMobile() and "SkippedForMobileSmartCamera" or "Completed")
	return true
end

local function startOnce()
	if played then
		return
	end
	played = true

	-- TouchEnabled existe antes dos atributos do perfil, portanto esta saida nao
	-- sofre race condition no primeiro spawn mobile.
	if isMobile() then
		setBlocked(player.Character, false)
		player:SetAttribute("DungeonInitialCameraIntroState", "SkippedForMobileSmartCamera")
		player:SetAttribute("DungeonInitialCameraIntroCompletedAt", Workspace:GetServerTimeNow())
		return
	end

	player:SetAttribute("DungeonInitialCameraIntroState", "WaitingForInitialIsland")
	local deadline = os.clock() + TARGET_WAIT
	repeat
		if isMobile() then
			setBlocked(player.Character, false)
			player:SetAttribute("DungeonInitialCameraIntroState", "SkippedForMobileSmartCamera")
			return
		end
		local character, humanoid, root = characterParts()
		local island = root and firstIsland(root) or nil
		local exit = exitAnchor(island)
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
	setBlocked(player.Character, false)
end)
