--[[
    Infinity Islands — Rebuild Part 32
    FirstStrike completion presentation.

    Presentation-only:
    - detects the real FirstStrike completion;
    - briefly celebrates the player's first enemy defeat;
    - waits for the REAL TravelUnlocked state;
    - then announces "CAMINHO LIBERADO";
    - pulses the actual Exit marker.

    It never unlocks gates or advances progression itself.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "FirstVictoryFeedbackV1"
local DEFEAT_HOLD = 0.58
local PATH_HOLD = 0.82
local TRAVEL_WAIT_LIMIT = 3.0

local existing = playerGui:FindFirstChild("DungeonFirstVictoryFeedback")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonFirstVictoryFeedback"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 94
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local holder = Instance.new("Frame")
holder.Name = "Feedback"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(520, 82)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "FeedbackScale"
scale.Scale = 0.92
scale.Parent = holder

local symbol = Instance.new("TextLabel")
symbol.Name = "Symbol"
symbol.AnchorPoint = Vector2.new(0.5, 0)
symbol.Position = UDim2.new(0.5, 0, 0, 0)
symbol.Size = UDim2.fromOffset(34, 32)
symbol.BackgroundTransparency = 1
symbol.Text = "✓"
symbol.TextColor3 = Color3.fromRGB(103, 235, 165)
symbol.TextTransparency = 1
symbol.TextStrokeColor3 = Color3.fromRGB(5, 18, 28)
symbol.TextStrokeTransparency = 1
symbol.Font = Enum.Font.GothamBlack
symbol.TextSize = 27
symbol.ZIndex = 22
symbol.Parent = holder

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 30)
title.Size = UDim2.new(1, -20, 0, 31)
title.BackgroundTransparency = 1
title.Text = "PRIMEIRO INIMIGO DERROTADO"
title.TextColor3 = Color3.fromRGB(244, 250, 255)
title.TextTransparency = 1
title.TextStrokeColor3 = Color3.fromRGB(5, 18, 28)
title.TextStrokeTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.ZIndex = 22
title.Parent = holder

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MinTextSize = 17
titleConstraint.MaxTextSize = 26
titleConstraint.Parent = title

local line = Instance.new("Frame")
line.Name = "Line"
line.AnchorPoint = Vector2.new(0.5, 0)
line.Position = UDim2.new(0.5, 0, 0, 68)
line.Size = UDim2.fromOffset(148, 2)
line.BackgroundColor3 = Color3.fromRGB(103, 235, 165)
line.BackgroundTransparency = 1
line.BorderSizePixel = 0
line.ZIndex = 21
line.Parent = holder

local lineGradient = Instance.new("UIGradient")
lineGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.22, 0.12),
    NumberSequenceKeypoint.new(0.78, 0.12),
    NumberSequenceKeypoint.new(1, 1),
})
lineGradient.Parent = line

local triggered = false
local sequenceSerial = 0

local function setFeedbackVisible(shouldShow)
    sequenceSerial += 1
    local serial = sequenceSerial

    if shouldShow then
        holder.Visible = true
        scale.Scale = 0.92
        symbol.TextTransparency = 1
        symbol.TextStrokeTransparency = 1
        title.TextTransparency = 1
        title.TextStrokeTransparency = 1
        line.BackgroundTransparency = 1
        TweenService:Create(
            scale,
            TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            symbol,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0,
                TextStrokeTransparency = 0.56,
            }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0,
                TextStrokeTransparency = 0.56,
            }
        ):Play()
        TweenService:Create(
            line,
            TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.06 }
        ):Play()
    else
        TweenService:Create(
            scale,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.95 }
        ):Play()
        TweenService:Create(
            symbol,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            line,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()

        task.delay(0.17, function()
            if serial == sequenceSerial and holder.Parent then
                holder.Visible = false
            end
        end)
    end
end

local function routeExit()
    local islandIndex =
        tonumber(Workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex"))
        or tonumber(Workspace:GetAttribute("DungeonCurrentObjectiveIsland"))
        or 1

    local best

    for _, marker in ipairs(CollectionService:GetTagged("DungeonRouteExit")) do
        if marker:IsA("BasePart")
            and marker.Parent
            and (
                tonumber(marker:GetAttribute("GlobalIslandIndex")) == islandIndex
                or tonumber(marker.Parent:GetAttribute("GlobalIslandIndex")) == islandIndex
            )
        then
            best = marker
            break
        end
    end

    if best then
        return best
    end

    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("BasePart")
            and (
                descendant.Name == "Exit"
                or descendant:GetAttribute("MarkerType") == "Exit"
            )
        then
            local candidateIndex =
                tonumber(descendant:GetAttribute("GlobalIslandIndex"))
                or tonumber(descendant.Parent and descendant.Parent:GetAttribute("GlobalIslandIndex"))
            if candidateIndex == islandIndex then
                return descendant
            end
        end
    end

    return nil
end

local function pulseExit()
    local exit = routeExit()
    if not exit then
        player:SetAttribute("DungeonFirstVictoryExitPulseFound", false)
        return
    end

    player:SetAttribute("DungeonFirstVictoryExitPulseFound", true)
    player:SetAttribute("DungeonFirstVictoryExitName", exit:GetFullName())

    local highlight = Instance.new("Highlight")
    highlight.Name = "FirstVictoryExitHighlight"
    highlight.Adornee = exit
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(88, 222, 255)
    highlight.FillTransparency = 1
    highlight.OutlineColor = Color3.fromRGB(157, 242, 255)
    highlight.OutlineTransparency = 1
    highlight.Parent = exit

    TweenService:Create(
        highlight,
        TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            FillTransparency = 0.72,
            OutlineTransparency = 0.06,
        }
    ):Play()

    task.delay(0.46, function()
        if highlight.Parent then
            TweenService:Create(
                highlight,
                TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {
                    FillTransparency = 1,
                    OutlineTransparency = 1,
                }
            ):Play()
            task.wait(0.58)
            if highlight.Parent then
                highlight:Destroy()
            end
        end
    end)
end

local function waitForTravelUnlocked()
    if tostring(Workspace:GetAttribute("DungeonProgressionState") or "") == "TravelUnlocked" then
        return true
    end

    local resolved = false
    local connection
    connection = Workspace:GetAttributeChangedSignal("DungeonProgressionState"):Connect(function()
        if tostring(Workspace:GetAttribute("DungeonProgressionState") or "") == "TravelUnlocked" then
            resolved = true
            connection:Disconnect()
        end
    end)

    local startedAt = os.clock()
    while not resolved and os.clock() - startedAt < TRAVEL_WAIT_LIMIT do
        task.wait(0.05)
    end

    if connection and connection.Connected then
        connection:Disconnect()
    end

    return resolved
        or tostring(Workspace:GetAttribute("DungeonProgressionState") or "") == "TravelUnlocked"
end

local function runSequence()
    if triggered then
        return
    end
    triggered = true

    player:SetAttribute("DungeonFirstVictoryFeedbackActive", true)
    player:SetAttribute("DungeonFirstVictoryFeedbackVersion", VERSION)
    player:SetAttribute("DungeonFirstVictoryFeedbackStage", "EnemyDefeated")
    player:SetAttribute(
        "DungeonFirstVictoryFeedbackStartedAt",
        Workspace:GetServerTimeNow()
    )

    symbol.Text = "✓"
    symbol.TextColor3 = Color3.fromRGB(103, 235, 165)
    title.Text = "PRIMEIRO INIMIGO DERROTADO"
    line.BackgroundColor3 = Color3.fromRGB(103, 235, 165)

    setFeedbackVisible(true)
    task.wait(DEFEAT_HOLD)

    local travelUnlocked = waitForTravelUnlocked()

    if travelUnlocked then
        player:SetAttribute("DungeonFirstVictoryFeedbackStage", "PathUnlocked")

        -- Morph, don't stack another message.
        TweenService:Create(
            title,
            TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }
        ):Play()
        TweenService:Create(
            symbol,
            TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }
        ):Play()
        task.wait(0.11)

        symbol.Text = "▲"
        symbol.TextColor3 = Color3.fromRGB(103, 222, 255)
        title.Text = "CAMINHO LIBERADO"
        line.BackgroundColor3 = Color3.fromRGB(103, 222, 255)

        TweenService:Create(
            title,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
        TweenService:Create(
            symbol,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()

        pulseExit()
        task.wait(PATH_HOLD)
    else
        -- Never lie to the player. If the gate did not actually unlock, do not
        -- display "CAMINHO LIBERADO". Leave a diagnostic instead.
        player:SetAttribute(
            "DungeonFirstVictoryFeedbackTravelTimeout",
            true
        )
    end

    setFeedbackVisible(false)
    task.wait(0.18)

    player:SetAttribute("DungeonFirstVictoryFeedbackStage", "Complete")
    player:SetAttribute("DungeonFirstVictoryFeedbackActive", false)
    player:SetAttribute(
        "DungeonFirstVictoryFeedbackCompletedAt",
        Workspace:GetServerTimeNow()
    )
end

local function shouldTrigger()
    if triggered then
        return false
    end
    if player:GetAttribute("GuidedIntroActive") ~= true then
        return false
    end

    local objectiveId = tostring(
        Workspace:GetAttribute("DungeonObjectiveId") or ""
    )
    local progress = math.max(
        0,
        tonumber(Workspace:GetAttribute("DungeonObjectiveProgress")) or 0
    )
    local target = math.max(
        1,
        tonumber(Workspace:GetAttribute("DungeonObjectiveTarget")) or 1
    )
    local objectiveState = tostring(
        Workspace:GetAttribute("DungeonObjectiveState") or ""
    )
    local progressionState = tostring(
        Workspace:GetAttribute("DungeonProgressionState") or ""
    )

    return objectiveId == "FirstStrike"
        and progress >= target
        and (
            objectiveState == "Completed"
            or progressionState == "ObjectiveCompleted"
            or progressionState == "TravelUnlocked"
        )
end

local function evaluate()
    if shouldTrigger() then
        task.spawn(runSequence)
    end
end

for _, attribute in ipairs({
    "DungeonObjectiveId",
    "DungeonObjectiveProgress",
    "DungeonObjectiveTarget",
    "DungeonObjectiveState",
    "DungeonProgressionState",
}) do
    Workspace:GetAttributeChangedSignal(attribute):Connect(evaluate)
end

player:SetAttribute("DungeonFirstVictoryFeedbackReady", true)
player:SetAttribute("DungeonFirstVictoryFeedbackVersion", VERSION)

evaluate()
