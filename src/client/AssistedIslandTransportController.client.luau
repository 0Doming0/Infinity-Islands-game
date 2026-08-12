-- HUD, controles, camera e audio do transporte assistido.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(
	ReplicatedStorage.Shared.Configs.AssistedIslandTransportConfig
)
local RemoteRegistry = require(
	ReplicatedStorage.Shared.Utilities.RemoteRegistry
)
local remote = RemoteRegistry.Get("Navigation", "AssistedIslandTransport", "RemoteEvent")

local CAMERA_BIND = "AssistedIslandTransportCamera"
local INPUT_ACTION = "AssistedIslandTransportInputBlock"

local activeToken = 0
local phase = "Idle"
local deadline = 0
local destinationLabel = "PRÓXIMA ILHA"
local focusPosition
local controlsBlocked = false
local savedCameraState

local gui = Instance.new("ScreenGui")
gui.Name = "AssistedIslandTransportHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 95
gui.Enabled = false
gui.Parent = playerGui

local inputBlocker = Instance.new("TextButton")
inputBlocker.Name = "InputBlocker"
inputBlocker.Size = UDim2.fromScale(1, 1)
inputBlocker.BackgroundTransparency = 1
inputBlocker.Text = ""
inputBlocker.AutoButtonColor = false
inputBlocker.Active = true
inputBlocker.Selectable = false
inputBlocker.Modal = true
inputBlocker.Visible = false
inputBlocker.ZIndex = 1
inputBlocker.Parent = gui

local banner = Instance.new("Frame")
banner.Name = "WarningBanner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.fromScale(0.5, 0.075)
banner.Size = UDim2.fromOffset(510, 84)
banner.BackgroundColor3 = Color3.fromRGB(18, 25, 43)
banner.BackgroundTransparency = 0.12
banner.BorderSizePixel = 0
banner.ZIndex = 5
banner.Parent = gui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 14)
bannerCorner.Parent = banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = Color3.fromRGB(242, 201, 92)
bannerStroke.Thickness = 2
bannerStroke.Transparency = 0.12
bannerStroke.Parent = banner

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(255, 240, 190)
title.TextScaled = true
title.Text = "AVANÇO PARA A PRÓXIMA ILHA"
title.ZIndex = 6
title.Parent = banner

local description = Instance.new("TextLabel")
description.Name = "Description"
description.Size = UDim2.new(1, -24, 0, 27)
description.Position = UDim2.fromOffset(12, 48)
description.BackgroundTransparency = 1
description.Font = Enum.Font.GothamMedium
description.TextColor3 = Color3.fromRGB(235, 241, 255)
description.TextScaled = true
description.Text = "TRANSPORTE EM 8"
description.ZIndex = 6
description.Parent = banner

local landingCount = Instance.new("TextLabel")
landingCount.Name = "LandingCountdown"
landingCount.AnchorPoint = Vector2.new(0.5, 0.5)
landingCount.Position = UDim2.fromScale(0.5, 0.42)
landingCount.Size = UDim2.fromOffset(240, 180)
landingCount.BackgroundTransparency = 1
landingCount.Font = Enum.Font.GothamBlack
landingCount.TextColor3 = Color3.fromRGB(255, 235, 154)
landingCount.TextStrokeColor3 = Color3.fromRGB(22, 29, 49)
landingCount.TextStrokeTransparency = 0.05
landingCount.TextScaled = true
landingCount.Text = ""
landingCount.Visible = false
landingCount.ZIndex = 8
landingCount.Parent = gui

local function sinkInput()
	return Enum.ContextActionResult.Sink
end

local function blockControls()
	if controlsBlocked then
		return
	end
	controlsBlocked = true
	inputBlocker.Visible = true
	ContextActionService:BindActionAtPriority(
		INPUT_ACTION,
		sinkInput,
		false,
		10000,
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
		Enum.KeyCode.Thumbstick1
	)
end

local function releaseControls()
	if not controlsBlocked then
		return
	end
	controlsBlocked = false
	inputBlocker.Visible = false
	ContextActionService:UnbindAction(INPUT_ACTION)
end

local function captureCamera()
	local camera = workspace.CurrentCamera
	if not camera or savedCameraState then
		return
	end
	savedCameraState = {
		Camera = camera,
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
	}
end

local function restoreCamera()
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	local state = savedCameraState
	savedCameraState = nil
	if not state or not state.Camera or not state.Camera.Parent then
		return
	end
	pcall(function()
		state.Camera.CameraType = state.CameraType
		state.Camera.CameraSubject = state.CameraSubject
		state.Camera.FieldOfView = state.FieldOfView
		state.Camera.CFrame = state.CFrame
		state.Camera.Focus = state.Focus
	end)
end

local function beginCamera()
	captureCamera()
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	RunService:BindToRenderStep(
		CAMERA_BIND,
		Enum.RenderPriority.Camera.Value + 5,
		function(deltaTime)
			local camera = workspace.CurrentCamera
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not camera or not root or not focusPosition then
				return
			end

			local horizontal = Vector3.new(
				focusPosition.X - root.Position.X,
				0,
				focusPosition.Z - root.Position.Z
			)
			local forward = horizontal.Magnitude > 0.01
				and horizontal.Unit
				or Vector3.new(0, 0, -1)
			local cameraPosition = root.Position
				- forward * Config.CameraDistanceStuds
				+ Vector3.new(0, Config.CameraHeightStuds, 0)
			local desired = CFrame.lookAt(cameraPosition, focusPosition)
			local blend = 1 - math.exp(-Config.CameraBlendSpeed * deltaTime)

			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView += (Config.CameraFieldOfView - camera.FieldOfView) * blend
			camera.CFrame = camera.CFrame:Lerp(desired, blend)
			camera.Focus = CFrame.new(focusPosition)
		end
	)
end

local function playWhistle()
	local template = ReplicatedStorage:FindFirstChild("AssistedTransportWhistle", true)
	local sound
	if template and template:IsA("Sound") then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		local configuredId = tostring(
			ReplicatedStorage:GetAttribute("AssistedTransportWhistleSoundId")
				or Config.ReleaseWhistleSoundId
		)
		if string.match(configuredId, "^%d+$") then
			configuredId = "rbxassetid://" .. configuredId
		end
		sound.SoundId = configuredId
		sound.Volume = Config.ReleaseWhistleVolume
		sound.PlaybackSpeed = Config.ReleaseWhistlePlaybackSpeed
	end
	sound.Name = "AssistedTransportReleaseWhistle"
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function resetVisuals()
	gui.Enabled = false
	banner.Visible = true
	landingCount.Visible = false
	landingCount.Text = ""
end

local function cancelLocal()
	activeToken += 1
	phase = "Idle"
	releaseControls()
	restoreCamera()
	resetVisuals()
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	local action = payload.Action
	if action == "Warning" then
		activeToken = tonumber(payload.Token) or (activeToken + 1)
		phase = "Warning"
		deadline = tonumber(payload.TransportAt) or workspace:GetServerTimeNow()
		destinationLabel = tostring(payload.DestinationLabel or "PRÓXIMA ILHA")
		gui.Enabled = true
		banner.Visible = true
		landingCount.Visible = false
		title.Text = "AVANÇO PARA " .. destinationLabel
		if typeof(payload.DestinationPosition) == "Vector3" then
			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(payload.DestinationPosition, 5)
				end)
			end)
		end
	elseif action == "WaitingForClear" then
		if tonumber(payload.Token) ~= activeToken then
			return
		end
		phase = "WaitingForClear"
		gui.Enabled = true
		banner.Visible = true
		title.Text = "PRÓXIMA ILHA PREPARADA"
		description.Text = "DERROTE OS INIMIGOS RESTANTES"
	elseif action == "BeginFlight" then
		if tonumber(payload.Token) ~= activeToken then
			return
		end
		phase = "Flying"
		focusPosition = payload.FocusPosition
		gui.Enabled = true
		banner.Visible = false
		landingCount.Visible = false
		blockControls()
		beginCamera()
		if typeof(payload.DestinationPosition) == "Vector3" then
			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(payload.DestinationPosition, 5)
				end)
			end)
		end
	elseif action == "Landed" then
		if tonumber(payload.Token) ~= activeToken then
			return
		end
		phase = "Landing"
		deadline = tonumber(payload.ReleaseAt) or workspace:GetServerTimeNow()
		focusPosition = payload.FocusPosition or focusPosition
		gui.Enabled = true
		banner.Visible = false
		landingCount.Visible = true
	elseif action == "Release" then
		if tonumber(payload.Token) ~= activeToken then
			return
		end
		phase = "Released"
		landingCount.Visible = true
		landingCount.Text = "VÁ!"
		playWhistle()
		releaseControls()
		restoreCamera()
		local releaseToken = activeToken
		task.delay(0.7, function()
			if activeToken == releaseToken and phase == "Released" then
				phase = "Idle"
				resetVisuals()
			end
		end)
	elseif action == "Cancel" then
		cancelLocal()
	end
end)

RunService.RenderStepped:Connect(function()
	if phase == "Warning" then
		local remaining = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		description.Text = "TRANSPORTE EM " .. tostring(remaining)
	elseif phase == "Landing" then
		local remaining = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		landingCount.Text = tostring(remaining)
	end
end)

player.CharacterRemoving:Connect(cancelLocal)
player:SetAttribute("DungeonAssistedTransportClientReady", true)
