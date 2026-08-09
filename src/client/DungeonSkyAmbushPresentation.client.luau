--[[
    Infinity Islands — Rebuild Part 39
    Sky Ambush presentation.

    Teaches one new idea:
        danger can arrive AFTER the party lands.

    This is presentation-only. The server owns:
    - party landing gate;
    - objective start;
    - warning delay;
    - enemy spawns.

    During AmbushWarning:
    - Objective Card yields focus;
    - waypoint yields focus;
    - mobile ATTACK yields focus;
    - a short red warning appears.

    As soon as the encounter enters Spawning/Active, this presentation leaves
    and the normal objective card returns.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "SkyAmbushWarningV1"

local existing = playerGui:FindFirstChild("DungeonSkyAmbushPresentation")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonSkyAmbushPresentation"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 93
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local holder = Instance.new("Frame")
holder.Name = "AmbushWarning"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(430, 78)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "AmbushWarningScale"
scale.Scale = 0.90
scale.Parent = holder

local symbol = Instance.new("TextLabel")
symbol.Name = "Symbol"
symbol.AnchorPoint = Vector2.new(0.5, 0)
symbol.Position = UDim2.new(0.5, 0, 0, 0)
symbol.Size = UDim2.fromOffset(38, 30)
symbol.BackgroundTransparency = 1
symbol.Text = "!"
symbol.TextColor3 = Color3.fromRGB(255, 115, 93)
symbol.TextTransparency = 1
symbol.TextStrokeColor3 = Color3.fromRGB(40, 8, 7)
symbol.TextStrokeTransparency = 1
symbol.Font = Enum.Font.GothamBlack
symbol.TextSize = 26
symbol.ZIndex = 22
symbol.Parent = holder

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 28)
title.Size = UDim2.new(1, -20, 0, 31)
title.BackgroundTransparency = 1
title.Text = "EMBOSCADA!"
title.TextColor3 = Color3.fromRGB(255, 245, 242)
title.TextTransparency = 1
title.TextStrokeColor3 = Color3.fromRGB(43, 8, 6)
title.TextStrokeTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.ZIndex = 22
title.Parent = holder

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MinTextSize = 20
titleConstraint.MaxTextSize = 29
titleConstraint.Parent = title

local lineBack = Instance.new("Frame")
lineBack.Name = "LineBack"
lineBack.AnchorPoint = Vector2.new(0.5, 0)
lineBack.Position = UDim2.new(0.5, 0, 0, 66)
lineBack.Size = UDim2.fromOffset(160, 2)
lineBack.BackgroundColor3 = Color3.fromRGB(92, 31, 25)
lineBack.BackgroundTransparency = 1
lineBack.BorderSizePixel = 0
lineBack.ZIndex = 20
lineBack.Parent = holder

local line = Instance.new("Frame")
line.Name = "Line"
line.AnchorPoint = Vector2.new(0.5, 0.5)
line.Position = UDim2.fromScale(0.5, 0.5)
line.Size = UDim2.fromScale(0, 1)
line.BackgroundColor3 = Color3.fromRGB(255, 101, 79)
line.BackgroundTransparency = 1
line.BorderSizePixel = 0
line.ZIndex = 21
line.Parent = lineBack

local edgeTop = Instance.new("Frame")
edgeTop.Name = "EdgeTop"
edgeTop.Position = UDim2.fromScale(0, 0)
edgeTop.Size = UDim2.new(1, 0, 0, 3)
edgeTop.BackgroundColor3 = Color3.fromRGB(255, 77, 60)
edgeTop.BackgroundTransparency = 1
edgeTop.BorderSizePixel = 0
edgeTop.ZIndex = 5
edgeTop.Parent = gui

local active = false
local serial = 0

local function shouldShow()
    return tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "SkyAmbush"
        and tostring(Workspace:GetAttribute("DungeonEncounterWaveState") or "") == "AmbushWarning"
        and player:GetAttribute("DungeonEntryPresentationState") == "Playing"
end

local function show()
    if active then
        return
    end

    active = true
    serial += 1

    player:SetAttribute("DungeonSkyAmbushPresentationActive", true)
    player:SetAttribute("DungeonSkyAmbushPresentationStage", "Warning")
    player:SetAttribute(
        "DungeonSkyAmbushPresentationStartedAt",
        Workspace:GetServerTimeNow()
    )

    holder.Visible = true
    scale.Scale = 0.90
    symbol.TextTransparency = 1
    symbol.TextStrokeTransparency = 1
    title.TextTransparency = 1
    title.TextStrokeTransparency = 1
    lineBack.BackgroundTransparency = 1
    line.Size = UDim2.fromScale(0, 1)
    line.BackgroundTransparency = 1
    edgeTop.BackgroundTransparency = 1
    TweenService:Create(
        scale,
        TweenInfo.new(0.23, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
    TweenService:Create(
        symbol,
        TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 0,
            TextStrokeTransparency = 0.58,
        }
    ):Play()
    TweenService:Create(
        title,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 0,
            TextStrokeTransparency = 0.56,
        }
    ):Play()
    TweenService:Create(
        lineBack,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.78 }
    ):Play()
    TweenService:Create(
        line,
        TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 0.04,
        }
    ):Play()
    TweenService:Create(
        edgeTop,
        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.18 }
    ):Play()

    task.delay(0.16, function()
        if active and edgeTop.Parent then
            TweenService:Create(
                edgeTop,
                TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { BackgroundTransparency = 1 }
            ):Play()
        end
    end)
end

local function hide()
    if not active then
        return
    end

    active = false
    serial += 1
    local mine = serial

    player:SetAttribute("DungeonSkyAmbushPresentationStage", "Leaving")

    TweenService:Create(
        scale,
        TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Scale = 0.96 }
    ):Play()
    TweenService:Create(
        symbol,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }
    ):Play()
    TweenService:Create(
        title,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }
    ):Play()
    TweenService:Create(
        line,
        TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            Size = UDim2.fromScale(0, 1),
            BackgroundTransparency = 1,
        }
    ):Play()
    TweenService:Create(
        lineBack,
        TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
    ):Play()

    task.delay(0.14, function()
        if mine == serial and not active and holder.Parent then
            holder.Visible = false
            player:SetAttribute("DungeonSkyAmbushPresentationStage", "Complete")
            player:SetAttribute("DungeonSkyAmbushPresentationActive", false)
            player:SetAttribute(
                "DungeonSkyAmbushPresentationCompletedAt",
                Workspace:GetServerTimeNow()
            )
        end
    end)
end

local function evaluate()
    if shouldShow() then
        show()
    else
        hide()
    end
end

for _, attributeName in ipairs({
    "DungeonObjectiveId",
    "DungeonEncounterWaveState",
}) do
    Workspace:GetAttributeChangedSignal(attributeName):Connect(evaluate)
end

player:GetAttributeChangedSignal("DungeonEntryPresentationState"):Connect(evaluate)

player:SetAttribute("DungeonSkyAmbushPresentationReady", true)
player:SetAttribute("DungeonSkyAmbushPresentationVersion", VERSION)
player:SetAttribute("DungeonSkyAmbushPresentationActive", false)
player:SetAttribute("DungeonSkyAmbushPresentationStage", "Waiting")

evaluate()
