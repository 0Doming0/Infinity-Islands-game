-- HUD, controles, camera e audio do transporte assistido.

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
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
local guidanceDestinationLabel = "PRÓXIMA ILHA"
local focusPosition
local guidanceStartedAt = 0
local guidanceSourceIndex
local guidanceTargetIndex
local guidanceFallbackPosition
local guidanceSteps = {}
local guidanceStepIndex = 1
local guidanceLastIslandIndex
local guidanceActive = false
local controlsBlocked = false
local savedCameraState

-- Se este ScreenGui ja existir em StarterGui, o controller preserva o visual
-- criado no Studio e anima apenas os objetos com estes nomes.
local gui = playerGui:FindFirstChild("AssistedIslandTransportHUD")
if not gui or not gui:IsA("ScreenGui") then
	gui = Instance.new("ScreenGui")
	gui.Name = "AssistedIslandTransportHUD"
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 95
gui.Enabled = false

local inputBlocker = gui:FindFirstChild("InputBlocker")
if not inputBlocker or not inputBlocker:IsA("TextButton") then
	inputBlocker = Instance.new("TextButton")
	inputBlocker.Name = "InputBlocker"
	inputBlocker.Size = UDim2.fromScale(1, 1)
	inputBlocker.BackgroundTransparency = 1
	inputBlocker.Text = ""
	inputBlocker.AutoButtonColor = false
	inputBlocker.Active = true
	inputBlocker.Selectable = false
	inputBlocker.Modal = true
	inputBlocker.ZIndex = 1
	inputBlocker.Parent = gui
end
inputBlocker.Visible = false

local banner = gui:FindFirstChild("WarningPanel")
	or gui:FindFirstChild("WarningBanner")
if not banner or not banner:IsA("Frame") then
	banner = Instance.new("Frame")
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
end
banner.Name = "WarningPanel"

local title = banner:FindFirstChild("Title")
if not title or not title:IsA("TextLabel") then
	title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -24, 0, 36)
	title.Position = UDim2.fromOffset(12, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 240, 190)
	title.TextScaled = true
	title.ZIndex = 6
	title.Parent = banner
end
title.Text = "AVANÇO PARA A PRÓXIMA ILHA"
title.TextColor3 = Color3.fromRGB(255, 255, 255)

local description = banner:FindFirstChild("Description")
if not description or not description:IsA("TextLabel") then
	description = Instance.new("TextLabel")
	description.Name = "Description"
	description.Size = UDim2.new(1, -24, 0, 27)
	description.Position = UDim2.fromOffset(12, 48)
	description.BackgroundTransparency = 1
	description.Font = Enum.Font.GothamMedium
	description.TextColor3 = Color3.fromRGB(235, 241, 255)
	description.TextScaled = true
	description.ZIndex = 6
	description.Parent = banner
end
description.Text = "TRANSPORTE EM 8"
description.TextColor3 = Color3.fromRGB(255, 255, 255)

local landingCount = gui:FindFirstChild("LandingCountdown")
if not landingCount or not landingCount:IsA("TextLabel") then
	landingCount = Instance.new("TextLabel")
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
	landingCount.ZIndex = 8
	landingCount.Parent = gui
end
landingCount.Text = ""
landingCount.TextColor3 = Color3.fromRGB(255, 255, 255)
landingCount.Visible = false

-- Indicador 3D inteiramente local. Nao depende de modelos no ReplicatedStorage.
local worldIndicator = Instance.new("Model")
worldIndicator.Name = "LocalNextIslandWorldIndicator"

local indicatorRoot = Instance.new("Part")
indicatorRoot.Name = "Root"
indicatorRoot.Size = Vector3.new(0.2, 0.2, 0.2)
indicatorRoot.Transparency = 1
indicatorRoot.Anchored = true
indicatorRoot.CanCollide = false
indicatorRoot.CanTouch = false
indicatorRoot.CanQuery = false
indicatorRoot.CastShadow = false
indicatorRoot.CFrame = CFrame.new()
indicatorRoot.Parent = worldIndicator
worldIndicator.PrimaryPart = indicatorRoot

local function createArrowPart(name, size, localCFrame, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = localCFrame
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Parent = worldIndicator
	return part
end

local arrowColor = Color3.fromRGB(255, 231, 145)
createArrowPart(
	"Shaft",
	Vector3.new(0.42, 0.24, 2.7),
	CFrame.new(0, 0, -0.75),
	Color3.fromRGB(255, 255, 242)
)
createArrowPart(
	"ArrowHeadLeft",
	Vector3.new(0.42, 0.26, 1.85),
	CFrame.new(-0.58, 0, -2.05) * CFrame.Angles(0, math.rad(-45), 0),
	arrowColor
)
createArrowPart(
	"ArrowHeadRight",
	Vector3.new(0.42, 0.26, 1.85),
	CFrame.new(0.58, 0, -2.05) * CFrame.Angles(0, math.rad(45), 0),
	arrowColor
)

local indicatorLight = Instance.new("PointLight")
indicatorLight.Name = "PulseLight"
indicatorLight.Color = arrowColor
indicatorLight.Range = 10
indicatorLight.Brightness = 1.4
indicatorLight.Parent = indicatorRoot

local worldLabel = Instance.new("BillboardGui")
worldLabel.Name = "WorldLabel"
worldLabel.Adornee = indicatorRoot
worldLabel.Size = UDim2.fromOffset(190, 38)
worldLabel.StudsOffsetWorldSpace = Vector3.new(0, 1.05, 0)
worldLabel.AlwaysOnTop = true
worldLabel.LightInfluence = 0
worldLabel.MaxDistance = 90
worldLabel.Parent = indicatorRoot

local worldLabelText = Instance.new("TextLabel")
worldLabelText.Name = "IslandName"
worldLabelText.Size = UDim2.fromScale(1, 1)
worldLabelText.BackgroundColor3 = Color3.fromRGB(18, 25, 43)
worldLabelText.BackgroundTransparency = 0.18
worldLabelText.BorderSizePixel = 0
worldLabelText.Font = Enum.Font.GothamBold
worldLabelText.Text = "PRÓXIMA ILHA"
worldLabelText.TextColor3 = Color3.fromRGB(255, 255, 255)
worldLabelText.TextScaled = true
worldLabelText.TextStrokeTransparency = 0.65
worldLabelText.Parent = worldLabel
Instance.new("UICorner", worldLabelText).CornerRadius = UDim.new(0, 10)

local worldLabelStroke = Instance.new("UIStroke")
worldLabelStroke.Color = Color3.fromRGB(242, 201, 92)
worldLabelStroke.Thickness = 1.5
worldLabelStroke.Transparency = 0.14
worldLabelStroke.Parent = worldLabelText

local function setWorldIndicatorVisible(visible)
	if visible then
		if worldIndicator.Parent ~= workspace then
			worldIndicator.Parent = workspace
		end
	else
		worldIndicator.Parent = nil
	end
	player:SetAttribute("DungeonRouteArrowVisible", visible == true)
end

local arrowBasePartCount = 0
for _, descendant in ipairs(worldIndicator:GetDescendants()) do
	if descendant:IsA("BasePart") then
		arrowBasePartCount += 1
	end
end
player:SetAttribute(
	"DungeonRouteArrowCreated",
	worldIndicator.PrimaryPart == indicatorRoot and arrowBasePartCount >= 4
)
player:SetAttribute("DungeonRouteArrowPartCount", arrowBasePartCount)
player:SetAttribute("DungeonRouteArrowVersion", "RouteWaypointArrowFallbackV3")
player:SetAttribute("DungeonRouteArrowVisible", false)

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
	setWorldIndicatorVisible(false)
	guidanceActive = false
	guidanceSourceIndex = nil
	guidanceTargetIndex = nil
	guidanceFallbackPosition = nil
	guidanceSteps = {}
	guidanceStepIndex = 1
	guidanceLastIslandIndex = nil
	player:SetAttribute("DungeonRouteArrowTargetIsland", nil)
	player:SetAttribute("DungeonRouteArrowWaypointIsland", nil)
	player:SetAttribute("DungeonRouteArrowWaypointKind", nil)
	player:SetAttribute("DungeonRouteArrowWaitingForMarker", false)
end

local function cleanIslandIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function rebuildGuidanceSteps(currentIndex)
	guidanceSteps = {}
	guidanceStepIndex = 1
	guidanceLastIslandIndex = currentIndex

	if not guidanceTargetIndex or currentIndex >= guidanceTargetIndex then
		return
	end

	table.insert(guidanceSteps, {
		IslandIndex = currentIndex,
		Kind = "Exit",
	})
	for islandIndex = currentIndex + 1, guidanceTargetIndex do
		table.insert(guidanceSteps, {
			IslandIndex = islandIndex,
			Kind = "Entry",
		})
		if islandIndex < guidanceTargetIndex then
			table.insert(guidanceSteps, {
				IslandIndex = islandIndex,
				Kind = "Exit",
			})
		end
	end
end

local function markerForStep(step, playerPosition)
	local tag = step.Kind == "Entry" and "DungeonRouteEntry" or "DungeonRouteExit"
	local best
	local bestScore = math.huge
	for _, marker in ipairs(CollectionService:GetTagged(tag)) do
		local markerIndex = tonumber(marker:GetAttribute("GlobalIslandIndex"))
		if marker:IsA("BasePart")
			and marker.Parent
			and markerIndex ~= nil
			and math.floor(markerIndex) == step.IslandIndex
		then
			local score = (marker.Position - playerPosition).Magnitude
			if marker:GetAttribute("IsPrimaryConnection") == true then
				score -= 10000
			end
			if score < bestScore then
				best = marker
				bestScore = score
			end
		end
	end
	return best
end

local function updateGuidanceIndicator()
	if not guidanceActive or not guidanceTargetIndex then
		setWorldIndicatorVisible(false)
		return
	end

	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not playerRoot or not playerRoot:IsA("BasePart") then
		setWorldIndicatorVisible(false)
		return
	end

	local currentIndex = cleanIslandIndex(
		player:GetAttribute("CurrentGlobalIslandIndex")
	)
	if currentIndex >= guidanceTargetIndex then
		guidanceActive = false
		setWorldIndicatorVisible(false)
		return
	end
	if guidanceLastIslandIndex ~= currentIndex then
		rebuildGuidanceSteps(currentIndex)
	end

	local step = guidanceSteps[guidanceStepIndex]
	local marker = step and markerForStep(step, playerRoot.Position)
	while marker
		and (marker.Position - playerRoot.Position).Magnitude
			<= Config.GuidanceWaypointArrivalRadiusStuds
	do
		guidanceStepIndex += 1
		step = guidanceSteps[guidanceStepIndex]
		marker = step and markerForStep(step, playerRoot.Position)
	end

	local targetPosition
	local waypointIsland
	local waypointKind
	if marker then
		targetPosition = marker.Position
		waypointIsland = step.IslandIndex
		waypointKind = step.Kind
		player:SetAttribute("DungeonRouteArrowWaitingForMarker", false)
	elseif Config.GuidanceFallbackToDestination
		and typeof(guidanceFallbackPosition) == "Vector3"
	then
		-- O streaming pode entregar a ilha antes dos marcadores com tags. Nao
		-- escondemos a seta nesse intervalo: usamos o destino enviado pelo servidor.
		targetPosition = guidanceFallbackPosition
		waypointIsland = guidanceTargetIndex
		waypointKind = "DestinationFallback"
		player:SetAttribute("DungeonRouteArrowWaitingForMarker", true)
	else
		setWorldIndicatorVisible(false)
		player:SetAttribute("DungeonRouteArrowWaitingForMarker", true)
		return
	end

	local direction = Vector3.new(
		targetPosition.X - playerRoot.Position.X,
		0,
		targetPosition.Z - playerRoot.Position.Z
	)
	if direction.Magnitude <= 0.01 then
		setWorldIndicatorVisible(false)
		return
	end
	direction = direction.Unit

	local elapsed = workspace:GetServerTimeNow() - guidanceStartedAt
	local wave = math.sin(elapsed * Config.GuidancePulseSpeed)
	local bob = wave * Config.GuidanceBobStuds
	local pulse = 1 + math.max(0, wave) * Config.GuidancePulseAmount
	local arrowPosition = playerRoot.Position
		+ Vector3.new(0, Config.GuidanceHeightStuds + bob, 0)

	setWorldIndicatorVisible(true)
	worldIndicator:PivotTo(CFrame.lookAt(arrowPosition, arrowPosition + direction))
	pcall(function()
		worldIndicator:ScaleTo(Config.GuidanceArrowScale * pulse)
	end)
	indicatorLight.Brightness = 1.35 + math.max(0, wave) * 1.1
	worldLabelText.Text = guidanceDestinationLabel
	player:SetAttribute("DungeonRouteArrowTargetIsland", guidanceTargetIndex)
	player:SetAttribute("DungeonRouteArrowWaypointIsland", waypointIsland)
	player:SetAttribute("DungeonRouteArrowWaypointKind", waypointKind)
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
	if action == "Guidance" then
		activeToken = tonumber(payload.Token) or (activeToken + 1)
		phase = "Guidance"
		destinationLabel = tostring(payload.DestinationLabel or "PRÓXIMA ILHA")
		guidanceDestinationLabel = destinationLabel
		guidanceSourceIndex = cleanIslandIndex(payload.SourceIndex)
		guidanceTargetIndex = cleanIslandIndex(
			payload.TargetIndex or payload.DestinationIndex
		)
		guidanceFallbackPosition = typeof(payload.DestinationPosition) == "Vector3"
			and payload.DestinationPosition
			or nil
		guidanceStartedAt = workspace:GetServerTimeNow()
		guidanceActive = true
		releaseControls()
		restoreCamera()
		gui.Enabled = false
		rebuildGuidanceSteps(guidanceSourceIndex)
		if typeof(payload.DestinationPosition) == "Vector3" then
			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(payload.DestinationPosition, 5)
				end)
			end)
		end
	elseif action == "Warning" then
		activeToken = tonumber(payload.Token) or (activeToken + 1)
		phase = "Warning"
		deadline = tonumber(payload.TransportAt) or workspace:GetServerTimeNow()
		destinationLabel = tostring(payload.DestinationLabel or "PRÓXIMA ILHA")
		guidanceDestinationLabel = tostring(
			payload.GuidanceDestinationLabel or destinationLabel
		)
		if tonumber(payload.GuidanceTargetIndex) then
			guidanceSourceIndex = cleanIslandIndex(
				payload.GuidanceSourceIndex
					or player:GetAttribute("CurrentGlobalIslandIndex")
			)
			guidanceTargetIndex = cleanIslandIndex(payload.GuidanceTargetIndex)
			guidanceFallbackPosition = typeof(payload.DestinationPosition) == "Vector3"
				and payload.DestinationPosition
				or nil
			guidanceStartedAt = workspace:GetServerTimeNow()
			guidanceActive = true
			rebuildGuidanceSteps(guidanceSourceIndex)
		end
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
		guidanceActive = false
		setWorldIndicatorVisible(false)
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
		guidanceActive = false
		setWorldIndicatorVisible(false)
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
	if guidanceActive then
		updateGuidanceIndicator()
	end
end)

player.CharacterRemoving:Connect(cancelLocal)
player:SetAttribute("DungeonAssistedTransportClientReady", true)
