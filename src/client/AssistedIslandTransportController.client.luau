-- AssistedIslandTransportController: UI minima do fluxo linear.
--
-- Objetivo concluido -> AVANCAR -> voo -> proxima ilha.
-- Sem seta de rota, guidance, RecommendedLevel ou segunda confirmacao.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage.Shared.Configs.AssistedIslandTransportConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local remote = RemoteRegistry.Get("Navigation", "AssistedIslandTransport", "RemoteEvent")

local VERSION = "LinearTransportClientV1"
local CAMERA_BIND = "AssistedIslandTransportCamera"

local readyToken
local submitting = false
local focusPosition
local savedCamera
local cameraBound = false

local gui = playerGui:FindFirstChild("AssistedIslandTransportHUD")
if not gui or not gui:IsA("ScreenGui") then
	gui = Instance.new("ScreenGui")
	gui.Name = "AssistedIslandTransportHUD"
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 96
gui.Enabled = true

-- Remove residuos criados pela versao antiga deste mesmo controller.
for _, name in ipairs({
	"InputBlocker",
	"WarningPanel",
	"WarningBanner",
	"LandingCountdown",
}) do
	local old = gui:FindFirstChild(name)
	if old and old:GetAttribute("LinearTransportKeep") ~= true then
		old:Destroy()
	end
end
local oldWorldIndicator = workspace:FindFirstChild("LocalNextIslandWorldIndicator")
if oldWorldIndicator then
	oldWorldIndicator:Destroy()
end

local button = gui:FindFirstChild("AdvanceButton")
if not button or not button:IsA("TextButton") then
	if button then
		button:Destroy()
	end
	button = Instance.new("TextButton")
	button.Name = "AdvanceButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.fromScale(0.5, 0.90)
	button.Size = UDim2.fromOffset(230, 58)
	button.BackgroundColor3 = Color3.fromRGB(53, 163, 92)
	button.BackgroundTransparency = 0.04
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBlack
	button.Text = "AVANÇAR  ▶"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeColor3 = Color3.fromRGB(15, 45, 24)
	button.TextStrokeTransparency = 0.4
	button.TextScaled = true
	button.ZIndex = 20
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.18
	stroke.Color = Color3.fromRGB(215, 255, 220)
	stroke.Parent = button
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 18
	constraint.MaxTextSize = 30
	constraint.Parent = button
end
button:SetAttribute("LinearTransportKeep", true)
button.Visible = false

local message = gui:FindFirstChild("TransportMessage")
if not message or not message:IsA("TextLabel") then
	if message then
		message:Destroy()
	end
	message = Instance.new("TextLabel")
	message.Name = "TransportMessage"
	message.AnchorPoint = Vector2.new(0.5, 0)
	message.Position = UDim2.fromScale(0.5, 0.10)
	message.Size = UDim2.new(0.75, 0, 0, 44)
	message.BackgroundTransparency = 1
	message.Font = Enum.Font.GothamBlack
	message.TextColor3 = Color3.new(1, 1, 1)
	message.TextStrokeColor3 = Color3.new(0, 0, 0)
	message.TextStrokeTransparency = 0.25
	message.TextScaled = true
	message.ZIndex = 20
	message.Parent = gui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 16
	constraint.MaxTextSize = 30
	constraint.Parent = message
end
message:SetAttribute("LinearTransportKeep", true)
message.Visible = false
message.Text = ""

local function showReady(token, destination)
	token = tonumber(token)
	if not token then
		readyToken = nil
		button.Visible = false
		return
	end
	readyToken = token
	submitting = false
	button.Text = "AVANÇAR  ▶"
	button.Visible = true
	player:SetAttribute("DungeonAdvanceButtonVisible", true)
	player:SetAttribute("DungeonAdvanceButtonDestination", tonumber(destination))
end

local function hideButton()
	button.Visible = false
	player:SetAttribute("DungeonAdvanceButtonVisible", false)
end

local function syncReady()
	if player:GetAttribute("DungeonManualAdvanceReady") == true then
		showReady(
			player:GetAttribute("DungeonManualAdvanceReadyToken"),
			player:GetAttribute("DungeonAssistedTransportDestination")
		)
	else
		readyToken = nil
		submitting = false
		hideButton()
	end
end

local function showMessage(text)
	message.Text = tostring(text or "")
	message.Visible = message.Text ~= ""
end

local function hideMessage()
	message.Visible = false
	message.Text = ""
end

local function captureCamera()
	local camera = workspace.CurrentCamera
	if not camera or savedCamera then
		return
	end
	savedCamera = {
		Camera = camera,
		Type = camera.CameraType,
		Subject = camera.CameraSubject,
		Fov = camera.FieldOfView,
	}
end

local function stopFlightCamera()
	if cameraBound then
		RunService:UnbindFromRenderStep(CAMERA_BIND)
		cameraBound = false
	end
	local saved = savedCamera
	savedCamera = nil
	focusPosition = nil
	if saved and saved.Camera and saved.Camera.Parent then
		local camera = saved.Camera
		camera.CameraType = saved.Type == Enum.CameraType.Scriptable
			and Enum.CameraType.Custom
			or saved.Type
		if saved.Subject and saved.Subject.Parent then
			camera.CameraSubject = saved.Subject
		else
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		camera.FieldOfView = saved.Fov
	end
end

local function startFlightCamera(position)
	focusPosition = typeof(position) == "Vector3" and position or focusPosition
	captureCamera()
	if cameraBound then
		return
	end
	cameraBound = true
	RunService:BindToRenderStep(
		CAMERA_BIND,
		Enum.RenderPriority.Camera.Value + 30,
		function(dt)
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
			local forward = horizontal.Magnitude > 0.05
				and horizontal.Unit
				or Vector3.new(0, 0, -1)
			local cameraPosition = root.Position
				- forward * (tonumber(Config.CameraDistanceStuds) or 22)
				+ Vector3.new(0, tonumber(Config.CameraHeightStuds) or 12, 0)
			local desired = CFrame.lookAt(cameraPosition, focusPosition, Vector3.yAxis)
			local alpha = 1 - math.exp(-(tonumber(Config.CameraBlendSpeed) or 4) * math.max(dt, 0))
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = camera.CFrame:Lerp(desired, alpha)
			camera.Focus = CFrame.new(focusPosition)
			camera.FieldOfView += ((tonumber(Config.CameraFieldOfView) or 74) - camera.FieldOfView) * alpha
		end
	)
end

local function playWhistle()
	local sound = Instance.new("Sound")
	sound.Name = "LinearIslandTransportWhistle"
	sound.SoundId = tostring(Config.ReleaseWhistleSoundId or "rbxasset://sounds/electronicpingshort.wav")
	sound.Volume = tonumber(Config.ReleaseWhistleVolume) or 0.8
	sound.PlaybackSpeed = tonumber(Config.ReleaseWhistlePlaybackSpeed) or 1.2
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

button.Activated:Connect(function()
	if submitting or not readyToken then
		return
	end
	submitting = true
	button.Text = "AVANÇANDO..."
	hideButton()
	remote:FireServer({ Action = "AdvanceRequest", ReadyToken = readyToken })
end)

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local action = payload.Action
	if action == "ReadyToAdvance" then
		hideMessage()
		showReady(payload.ReadyToken, payload.DestinationIndex)
	elseif action == "Warning" then
		readyToken = nil
		hideButton()
		showMessage("AVANÇANDO PARA A PRÓXIMA ILHA")
		playWhistle()
	elseif action == "BeginFlight" then
		hideButton()
		showMessage("PRÓXIMA ILHA")
		focusPosition = payload.FocusPosition or payload.DestinationPosition
		startFlightCamera(focusPosition)
	elseif action == "Landed" then
		focusPosition = payload.FocusPosition or focusPosition
		showMessage("CHEGOU!")
	elseif action == "Release" then
		stopFlightCamera()
		hideMessage()
		task.defer(syncReady)
	elseif action == "Cancel" then
		stopFlightCamera()
		hideMessage()
		task.defer(syncReady)
	end
end)

for _, attribute in ipairs({
	"DungeonManualAdvanceReady",
	"DungeonManualAdvanceReadyToken",
	"DungeonAssistedTransportDestination",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		task.defer(syncReady)
	end)
end

player.CharacterRemoving:Connect(function()
	stopFlightCamera()
	hideButton()
	hideMessage()
end)

-- Neutraliza atributos visuais da antiga guidance para leitores legados.
player:SetAttribute("DungeonRouteArrowVisible", false)
player:SetAttribute("DungeonRouteArrowEligible", false)
player:SetAttribute("DungeonTransportClientVersion", VERSION)
player:SetAttribute("DungeonAdvanceButtonReady", true)
task.defer(syncReady)

script.Destroying:Connect(function()
	stopFlightCamera()
end)
