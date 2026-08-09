--[[
    Infinity Islands — Rebuild Part 35
    First Reward reveal.

    Goal:
    teach one idea only:
        battle victory -> reward

    The presentation waits for the REAL Round 1 Core Chest to exist.
    It does not claim, open, reward, advance, or alter progression.

    Sequence:
        RewardPending Round 1
        -> short breathing beat
        -> "RECOMPENSA!"
        -> real Core Chest glows
        -> compact HUD may say "ABRA O BAÚ"

    Currency is intentionally NOT introduced here.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "FirstRewardRevealV1"
local BREATH_SECONDS = 0.28
local REVEAL_HOLD_SECONDS = 0.78
local CHEST_FIND_TIMEOUT = 4.0

local existing = playerGui:FindFirstChild("DungeonFirstRewardPresentation")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonFirstRewardPresentation"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 95
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local holder = Instance.new("Frame")
holder.Name = "RewardReveal"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(470, 78)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Parent = gui

local revealScale = Instance.new("UIScale")
revealScale.Name = "RewardRevealScale"
revealScale.Scale = 0.90
revealScale.Parent = holder

local symbol = Instance.new("TextLabel")
symbol.Name = "Symbol"
symbol.AnchorPoint = Vector2.new(0.5, 0)
symbol.Position = UDim2.new(0.5, 0, 0, 0)
symbol.Size = UDim2.fromOffset(38, 30)
symbol.BackgroundTransparency = 1
symbol.Text = "✦"
symbol.TextColor3 = Color3.fromRGB(255, 218, 106)
symbol.TextTransparency = 1
symbol.TextStrokeColor3 = Color3.fromRGB(40, 29, 5)
symbol.TextStrokeTransparency = 1
symbol.Font = Enum.Font.GothamBlack
symbol.TextSize = 25
symbol.ZIndex = 22
symbol.Parent = holder

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 27)
title.Size = UDim2.new(1, -24, 0, 32)
title.BackgroundTransparency = 1
title.Text = "RECOMPENSA!"
title.TextColor3 = Color3.fromRGB(252, 248, 229)
title.TextTransparency = 1
title.TextStrokeColor3 = Color3.fromRGB(35, 27, 8)
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
lineBack.Position = UDim2.new(0.5, 0, 0, 65)
lineBack.Size = UDim2.fromOffset(152, 2)
lineBack.BackgroundColor3 = Color3.fromRGB(92, 72, 25)
lineBack.BackgroundTransparency = 1
lineBack.BorderSizePixel = 0
lineBack.ZIndex = 20
lineBack.Parent = holder

local line = Instance.new("Frame")
line.Name = "Line"
line.AnchorPoint = Vector2.new(0.5, 0.5)
line.Position = UDim2.fromScale(0.5, 0.5)
line.Size = UDim2.fromScale(0, 1)
line.BackgroundColor3 = Color3.fromRGB(255, 216, 101)
line.BackgroundTransparency = 1
line.BorderSizePixel = 0
line.ZIndex = 21
line.Parent = lineBack

local lineGradient = Instance.new("UIGradient")
lineGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.20, 0.10),
    NumberSequenceKeypoint.new(0.80, 0.10),
    NumberSequenceKeypoint.new(1, 1),
})
lineGradient.Parent = line

local triggered = false
local completed = false
local sequenceSerial = 0
local chestHighlight
local chestPulseSerial = 0

local function rewardRound()
    return math.max(
        0,
        math.floor(tonumber(
            Workspace:GetAttribute("DungeonRewardPendingRound")
        ) or 0)
    )
end

local function coreClaimed()
    return Workspace:GetAttribute("DungeonRewardCoreClaimed") == true
end

local function isFirstRewardPending()
    return tostring(
        Workspace:GetAttribute("DungeonProgressionState") or ""
    ) == "RewardPending"
        and rewardRound() == 1
        and Workspace:GetAttribute("DungeonRewardIslandActive") == true
        and not coreClaimed()
end

local function findCoreChest()
    local best

    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Model")
            and descendant:GetAttribute("RewardChestRole") == "Core"
            and math.floor(
                tonumber(descendant:GetAttribute("RoundIndex")) or 0
            ) == 1
        then
            best = descendant
            break
        end
    end

    return best
end

local function waitForCoreChest()
    local start = os.clock()

    repeat
        local chest = findCoreChest()
        if chest then
            return chest
        end

        if not isFirstRewardPending() then
            return nil
        end

        task.wait(0.06)
    until os.clock() - start >= CHEST_FIND_TIMEOUT

    return findCoreChest()
end

local function setRevealVisible(shouldShow)
    sequenceSerial += 1
    local serial = sequenceSerial

    if shouldShow then
        holder.Visible = true
        revealScale.Scale = 0.90
        symbol.TextTransparency = 1
        symbol.TextStrokeTransparency = 1
        title.TextTransparency = 1
        title.TextStrokeTransparency = 1
        lineBack.BackgroundTransparency = 1
        line.Size = UDim2.fromScale(0, 1)
        line.BackgroundTransparency = 1
        TweenService:Create(
            revealScale,
            TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            symbol,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0,
                TextStrokeTransparency = 0.64,
            }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0,
                TextStrokeTransparency = 0.58,
            }
        ):Play()
        TweenService:Create(
            lineBack,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.78 }
        ):Play()
        TweenService:Create(
            line,
            TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 0.04,
            }
        ):Play()
    else
        TweenService:Create(
            revealScale,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.95 }
        ):Play()
        TweenService:Create(
            symbol,
            TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            line,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                Size = UDim2.fromScale(0, 1),
                BackgroundTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            lineBack,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()

        task.delay(0.15, function()
            if serial == sequenceSerial and holder.Parent then
                holder.Visible = false
            end
        end)
    end
end

local function stopChestPulse()
    chestPulseSerial += 1

    if chestHighlight and chestHighlight.Parent then
        local old = chestHighlight
        chestHighlight = nil

        TweenService:Create(
            old,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                FillTransparency = 1,
                OutlineTransparency = 1,
            }
        ):Play()

        task.delay(0.24, function()
            if old.Parent then
                old:Destroy()
            end
        end)
    end
end

local function startChestPulse(chest)
    stopChestPulse()

    if not chest or not chest.Parent then
        return
    end

    chestPulseSerial += 1
    local serial = chestPulseSerial

    local highlight = Instance.new("Highlight")
    highlight.Name = "FirstRewardCoreHighlight"
    highlight.Adornee = chest
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(255, 208, 83)
    highlight.FillTransparency = 0.88
    highlight.OutlineColor = Color3.fromRGB(255, 235, 166)
    highlight.OutlineTransparency = 0.30
    highlight.Parent = chest
    chestHighlight = highlight

    player:SetAttribute("DungeonFirstRewardChestFound", true)
    player:SetAttribute("DungeonFirstRewardChestName", chest:GetFullName())

    task.spawn(function()
        local bright = true

        while serial == chestPulseSerial
            and highlight.Parent
            and isFirstRewardPending()
            and not coreClaimed()
        do
            TweenService:Create(
                highlight,
                TweenInfo.new(0.52, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                {
                    FillTransparency = bright and 0.69 or 0.87,
                    OutlineTransparency = bright and 0.05 or 0.27,
                }
            ):Play()

            bright = not bright
            task.wait(0.52)
        end

        if serial == chestPulseSerial then
            stopChestPulse()
        end
    end)
end

local function finishPresentation()
    if completed then
        return
    end

    completed = true
    setRevealVisible(false)
    task.wait(0.16)

    player:SetAttribute("DungeonFirstRewardPresentationStage", "CompactReady")
    player:SetAttribute("DungeonFirstRewardPresentationActive", false)
    player:SetAttribute("DungeonFirstRewardPresentationComplete", true)
    player:SetAttribute(
        "DungeonFirstRewardPresentationCompletedAt",
        Workspace:GetServerTimeNow()
    )
end

local function runSequence()
    if triggered then
        return
    end
    triggered = true

    player:SetAttribute("DungeonFirstRewardPresentationActive", true)
    player:SetAttribute("DungeonFirstRewardPresentationStage", "WaitingForChest")
    player:SetAttribute("DungeonFirstRewardPresentationComplete", false)
    player:SetAttribute(
        "DungeonFirstRewardPresentationStartedAt",
        Workspace:GetServerTimeNow()
    )

    local chest = waitForCoreChest()
    if not chest then
        player:SetAttribute("DungeonFirstRewardChestFound", false)
        player:SetAttribute(
            "DungeonFirstRewardPresentationError",
            "CoreChestUnavailable"
        )
        player:SetAttribute("DungeonFirstRewardPresentationActive", false)
        player:SetAttribute("DungeonFirstRewardPresentationStage", "Failed")
        return
    end

    if not isFirstRewardPending() then
        player:SetAttribute("DungeonFirstRewardPresentationActive", false)
        player:SetAttribute("DungeonFirstRewardPresentationStage", "Superseded")
        return
    end

    player:SetAttribute("DungeonFirstRewardPresentationStage", "Breathing")
    task.wait(BREATH_SECONDS)

    if coreClaimed() or not isFirstRewardPending() then
        finishPresentation()
        return
    end

    player:SetAttribute("DungeonFirstRewardPresentationStage", "RewardReveal")
    startChestPulse(chest)
    setRevealVisible(true)

    task.wait(REVEAL_HOLD_SECONDS)

    finishPresentation()
end

local function evaluate()
    if triggered then
        return
    end

    if isFirstRewardPending() then
        task.spawn(runSequence)
    end
end

for _, attribute in ipairs({
    "DungeonProgressionState",
    "DungeonRewardPendingRound",
    "DungeonRewardIslandActive",
}) do
    Workspace:GetAttributeChangedSignal(attribute):Connect(evaluate)
end

Workspace:GetAttributeChangedSignal("DungeonRewardCoreClaimed"):Connect(function()
    if coreClaimed() then
        stopChestPulse()
        if player:GetAttribute("DungeonFirstRewardPresentationActive") == true then
            task.spawn(finishPresentation)
        end
    end
end)

player:SetAttribute("DungeonFirstRewardPresentationReady", true)
player:SetAttribute("DungeonFirstRewardPresentationVersion", VERSION)
player:SetAttribute("DungeonFirstRewardPresentationStage", "Waiting")

evaluate()
