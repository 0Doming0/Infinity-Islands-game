--[[
    Infinity Islands — Rebuild Part 40
    First ranged enemy telegraph.

    One new concept:
        some enemies attack from distance.

    Server owns the timing:
        RangedThreat
        -> DungeonEncounterWaveState = "RangedWarning"
        -> ~0.82s
        -> spawn 3 Blue/Ranged slimes

    This UI is purely presentational and never starts/spawns the encounter.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "RangedThreatWarningV1"

local existing = playerGui:FindFirstChild("DungeonRangedThreatPresentation")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonRangedThreatPresentation"
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
holder.Name = "RangedWarning"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(440, 82)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "RangedWarningScale"
scale.Scale = 0.92
scale.Parent = holder

local icon = Instance.new("Frame")
icon.Name = "ProjectileIcon"
icon.AnchorPoint = Vector2.new(0.5, 0)
icon.Position = UDim2.new(0.5, 0, 0, 0)
icon.Size = UDim2.fromOffset(42, 26)
icon.BackgroundTransparency = 1
icon.ZIndex = 21
icon.Parent = holder

local shot = Instance.new("Frame")
shot.Name = "Shot"
shot.AnchorPoint = Vector2.new(0.5, 0.5)
shot.Position = UDim2.fromScale(0.5, 0.5)
shot.Size = UDim2.fromOffset(28, 5)
shot.BackgroundColor3 = Color3.fromRGB(116, 193, 255)
shot.BackgroundTransparency = 1
shot.BorderSizePixel = 0
shot.Rotation = -13
shot.ZIndex = 22
shot.Parent = icon
Instance.new("UICorner", shot).CornerRadius = UDim.new(1, 0)

local head = Instance.new("Frame")
head.Name = "ProjectileHead"
head.AnchorPoint = Vector2.new(0.5, 0.5)
head.Position = UDim2.new(1, -3, 0.5, 0)
head.Size = UDim2.fromOffset(10, 10)
head.BackgroundColor3 = Color3.fromRGB(169, 224, 255)
head.BackgroundTransparency = 1
head.BorderSizePixel = 0
head.ZIndex = 23
head.Parent = shot
Instance.new("UICorner", head).CornerRadius = UDim.new(1, 0)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 27)
title.Size = UDim2.new(1, -18, 0, 29)
title.BackgroundTransparency = 1
title.Text = "ATIRADORES À FRENTE"
title.TextColor3 = Color3.fromRGB(239, 248, 255)
title.TextTransparency = 1
title.TextStrokeColor3 = Color3.fromRGB(5, 18, 29)
title.TextStrokeTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.ZIndex = 22
title.Parent = holder

local constraint = Instance.new("UITextSizeConstraint")
constraint.MinTextSize = 17
constraint.MaxTextSize = 25
constraint.Parent = title

local detail = Instance.new("TextLabel")
detail.Name = "Detail"
detail.AnchorPoint = Vector2.new(0.5, 0)
detail.Position = UDim2.new(0.5, 0, 0, 58)
detail.Size = UDim2.new(1, -18, 0, 17)
detail.BackgroundTransparency = 1
detail.Text = "Eles atacam de longe."
detail.TextColor3 = Color3.fromRGB(149, 202, 236)
detail.TextTransparency = 1
detail.Font = Enum.Font.GothamMedium
detail.TextSize = 10
detail.ZIndex = 22
detail.Parent = holder

local visible = false
local serial = 0
local introduced = false

local function serverWarningActive()
    return tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "RangedThreat"
        and tostring(Workspace:GetAttribute("DungeonEncounterWaveState") or "") == "RangedWarning"
end

local function show()
    if visible then
        return
    end

    visible = true
    serial += 1

    holder.Visible = true
    scale.Scale = 0.92

    shot.BackgroundTransparency = 1
    head.BackgroundTransparency = 1
    title.TextTransparency = 1
    title.TextStrokeTransparency = 1
    detail.TextTransparency = 1
    TweenService:Create(
        scale,
        TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
    TweenService:Create(
        shot,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.06 }
    ):Play()
    TweenService:Create(
        head,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.02 }
    ):Play()
    TweenService:Create(
        title,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 0,
            TextStrokeTransparency = 0.58,
        }
    ):Play()
    TweenService:Create(
        detail,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0.10 }
    ):Play()

    if not introduced then
        introduced = true
        player:SetAttribute("GuidedIntroRangedThreatIntroduced", true)
        player:SetAttribute(
            "GuidedIntroRangedThreatIntroducedAt",
            Workspace:GetServerTimeNow()
        )
    end

    player:SetAttribute("DungeonRangedThreatPresentationActive", true)
    player:SetAttribute("DungeonRangedThreatPresentationStage", "Warning")
end

local function hide()
    if not visible then
        player:SetAttribute("DungeonRangedThreatPresentationActive", false)
        return
    end

    visible = false
    serial += 1
    local mine = serial
    TweenService:Create(
        scale,
        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Scale = 0.96 }
    ):Play()
    TweenService:Create(
        shot,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
    ):Play()
    TweenService:Create(
        head,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
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
        detail,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1 }
    ):Play()

    player:SetAttribute("DungeonRangedThreatPresentationStage", "Leaving")

    task.delay(0.14, function()
        if mine == serial and not visible and holder.Parent then
            holder.Visible = false
            player:SetAttribute("DungeonRangedThreatPresentationActive", false)
            player:SetAttribute("DungeonRangedThreatPresentationStage", "Complete")
            player:SetAttribute(
                "DungeonRangedThreatPresentationCompletedAt",
                Workspace:GetServerTimeNow()
            )
        end
    end)
end

local function refresh()
    if serverWarningActive() then
        show()
    else
        hide()
    end
end

Workspace:GetAttributeChangedSignal("DungeonObjectiveId"):Connect(refresh)
Workspace:GetAttributeChangedSignal("DungeonEncounterWaveState"):Connect(refresh)

player:SetAttribute("DungeonRangedThreatPresentationReady", true)
player:SetAttribute("DungeonRangedThreatPresentationVersion", VERSION)
player:SetAttribute("DungeonRangedThreatPresentationActive", false)
player:SetAttribute("DungeonRangedThreatPresentationStage", "Waiting")

refresh()
