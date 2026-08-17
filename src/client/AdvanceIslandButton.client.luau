-- Botao temporario de avanco entre arenas.
-- O servidor so oferece este botao quando a missao atual esta concluida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local remote = RemoteRegistry.Get("Navigation", "AssistedIslandTransport", "RemoteEvent")

local VERSION = "AdvanceIslandButtonV1"
local readyToken
local submitting = false

local gui = Instance.new("ScreenGui")
gui.Name = "AdvanceIslandButtonGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 96
gui.Enabled = false
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "AdvanceButton"
button.AnchorPoint = Vector2.new(0.5, 1)
button.Position = UDim2.new(0.5, 0, 0.89, 0)
button.Size = UDim2.fromOffset(230, 58)
button.BackgroundColor3 = Color3.fromRGB(53, 163, 92)
button.BackgroundTransparency = 0.06
button.BorderSizePixel = 0
button.AutoButtonColor = true
button.Font = Enum.Font.GothamBlack
button.Text = "AVANÇAR  ▶"
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.TextStrokeColor3 = Color3.fromRGB(15, 55, 27)
button.TextStrokeTransparency = 0.38
button.TextScaled = true
button.ZIndex = 2
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(196, 255, 207)
stroke.Transparency = 0.08
stroke.Parent = button

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 18)
padding.PaddingRight = UDim.new(0, 18)
padding.PaddingTop = UDim.new(0, 9)
padding.PaddingBottom = UDim.new(0, 9)
padding.Parent = button

local constraint = Instance.new("UITextSizeConstraint")
constraint.MinTextSize = 18
constraint.MaxTextSize = 30
constraint.Parent = button

local scale = Instance.new("UIScale")
scale.Scale = 1
scale.Parent = button

local function hide()
	readyToken = nil
	submitting = false
	gui.Enabled = false
	scale.Scale = 1
	player:SetAttribute("DungeonAdvanceButtonVisible", false)
end

local function show(payload)
	readyToken = tonumber(payload.ReadyToken)
	if not readyToken then
		hide()
		return
	end
	submitting = false
	button.Text = "AVANÇAR  ▶"
	gui.Enabled = true
	player:SetAttribute("DungeonAdvanceButtonVisible", true)
	player:SetAttribute("DungeonAdvanceButtonDestination", tonumber(payload.DestinationIndex))

	scale.Scale = 0.88
	TweenService:Create(
		scale,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

button.Activated:Connect(function()
	if submitting or not readyToken then
		return
	end
	submitting = true
	button.Text = "AVANÇANDO..."
	remote:FireServer({
		Action = "AdvanceRequest",
		ReadyToken = readyToken,
	})
	-- Some imediatamente; o Warning/voo do controller de transporte assume a tela.
	task.delay(0.05, hide)
end)

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Action == "ReadyToAdvance" then
		show(payload)
	elseif payload.Action == "AdvanceUnavailable"
		or payload.Action == "Warning"
		or payload.Action == "BeginFlight"
		or payload.Action == "Landed"
		or payload.Action == "Release"
		or payload.Action == "Cancel"
	then
		hide()
	end
end)

player.CharacterRemoving:Connect(hide)
player:SetAttribute("DungeonAdvanceButtonReady", true)
player:SetAttribute("DungeonAdvanceButtonVersion", VERSION)
