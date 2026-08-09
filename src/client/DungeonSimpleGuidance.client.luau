-- Rebuild Part 13 — minimal guidance for all 12 islands + Rewards 1–3 + Boss route.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("DungeonSimpleGuidance")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonSimpleGuidance"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 80
gui.Parent = playerGui

local card = Instance.new("Frame")
card.Name = "ObjectiveCard"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, 0)
card.Size = UDim2.fromOffset(350, 62)
card.BackgroundColor3 = Color3.fromRGB(15, 28, 40)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(104, 221, 255)
stroke.Transparency = 0.20
stroke.Thickness = 1.2
stroke.Parent = card

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(12, 5)
title.Size = UDim2.new(1, -24, 0, 23)
title.BackgroundTransparency = 1
title.Text = "PREPARANDO..."
title.TextColor3 = Color3.fromRGB(245, 250, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = card

local detail = Instance.new("TextLabel")
detail.Position = UDim2.fromOffset(12, 29)
detail.Size = UDim2.new(1, -24, 0, 21)
detail.BackgroundTransparency = 1
detail.Text = ""
detail.TextColor3 = Color3.fromRGB(158, 190, 211)
detail.Font = Enum.Font.GothamMedium
detail.TextSize = 11
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.Parent = card

local wave = Instance.new("TextLabel")
wave.AnchorPoint = Vector2.new(1, 0)
wave.Position = UDim2.new(1, -10, 0, 7)
wave.Size = UDim2.fromOffset(94, 18)
wave.BackgroundTransparency = 1
wave.Text = ""
wave.TextColor3 = Color3.fromRGB(231, 194, 104)
wave.Font = Enum.Font.GothamBold
wave.TextSize = 9
wave.TextXAlignment = Enum.TextXAlignment.Right
wave.Visible = false
wave.Parent = card

-- Island 2 introduces one new visual concept: multi-target progress.
-- It reuses the existing Objective Card instead of adding another panel.
local clearPathProgress = Instance.new("CanvasGroup")
clearPathProgress.Name = "ClearPathProgress"
clearPathProgress.Position = UDim2.fromOffset(12, 30)
clearPathProgress.Size = UDim2.new(1, -24, 0, 22)
clearPathProgress.BackgroundTransparency = 1
clearPathProgress.GroupTransparency = 0
clearPathProgress.Visible = false
clearPathProgress.Parent = card

local progressKind = Instance.new("TextLabel")
progressKind.Name = "Kind"
progressKind.Position = UDim2.fromOffset(0, 1)
progressKind.Size = UDim2.fromOffset(47, 18)
progressKind.BackgroundTransparency = 1
progressKind.Text = "SLIMES"
progressKind.TextColor3 = Color3.fromRGB(132, 169, 192)
progressKind.Font = Enum.Font.GothamBold
progressKind.TextSize = 9
progressKind.TextXAlignment = Enum.TextXAlignment.Left
progressKind.Parent = clearPathProgress

local dotsHolder = Instance.new("Frame")
dotsHolder.Name = "Dots"
dotsHolder.Position = UDim2.fromOffset(54, 6)
dotsHolder.Size = UDim2.fromOffset(82, 10)
dotsHolder.BackgroundTransparency = 1
dotsHolder.Parent = clearPathProgress

local progressDots = {}
local progressDotScales = {}

for index = 1, 3 do
    local dot = Instance.new("Frame")
    dot.Name = "Target" .. tostring(index)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromOffset(8 + (index - 1) * 28, 5)
    dot.Size = UDim2.fromOffset(18, 7)
    dot.BackgroundColor3 = Color3.fromRGB(45, 72, 91)
    dot.BorderSizePixel = 0
    dot.Parent = dotsHolder
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local dotStroke = Instance.new("UIStroke")
    dotStroke.Name = "Stroke"
    dotStroke.Color = Color3.fromRGB(91, 150, 181)
    dotStroke.Transparency = 0.50
    dotStroke.Thickness = 1
    dotStroke.Parent = dot

    local dotScale = Instance.new("UIScale")
    dotScale.Scale = 1
    dotScale.Parent = dot

    progressDots[index] = dot
    progressDotScales[index] = dotScale
end

local progressCount = Instance.new("TextLabel")
progressCount.Name = "Count"
progressCount.AnchorPoint = Vector2.new(1, 0)
progressCount.Position = UDim2.new(1, 0, 0, 0)
progressCount.Size = UDim2.fromOffset(66, 20)
progressCount.BackgroundTransparency = 1
progressCount.Text = "0 / 3"
progressCount.TextColor3 = Color3.fromRGB(224, 246, 255)
progressCount.Font = Enum.Font.GothamBlack
progressCount.TextSize = 12
progressCount.TextXAlignment = Enum.TextXAlignment.Right
progressCount.Parent = clearPathProgress

local progressCountScale = Instance.new("UIScale")
progressCountScale.Scale = 1
progressCountScale.Parent = progressCount

local clearPathLastProgress = nil
local clearPathIntroShown = false
local clearPathPulseSerial = 0

local function pulseClearPathProgress(index)
    clearPathPulseSerial += 1
    local serial = clearPathPulseSerial

    progressCountScale.Scale = 1
    TweenService:Create(
        progressCountScale,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Scale = 1.16 }
    ):Play()

    local dotScale = progressDotScales[index]
    if dotScale then
        dotScale.Scale = 1
        TweenService:Create(
            dotScale,
            TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1.30 }
        ):Play()
    end

    task.delay(0.11, function()
        if serial ~= clearPathPulseSerial then
            return
        end

        TweenService:Create(
            progressCountScale,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { Scale = 1 }
        ):Play()

        if dotScale then
            TweenService:Create(
                dotScale,
                TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Scale = 1 }
            ):Play()
        end
    end)
end

local function updateClearPathProgress(progress, target)
    progress = math.max(0, math.floor(tonumber(progress) or 0))
    target = math.max(1, math.floor(tonumber(target) or 3))

    progressCount.Text = string.format("%d / %d", progress, target)

    for index, dot in ipairs(progressDots) do
        local completed = index <= progress
        dot.BackgroundColor3 = completed
            and Color3.fromRGB(95, 222, 255)
            or Color3.fromRGB(45, 72, 91)

        local dotStroke = dot:FindFirstChild("Stroke")
        if dotStroke and dotStroke:IsA("UIStroke") then
            dotStroke.Color = completed
                and Color3.fromRGB(165, 243, 255)
                or Color3.fromRGB(91, 150, 181)
            dotStroke.Transparency = completed and 0.14 or 0.50
        end
    end

    if not clearPathIntroShown then
        clearPathIntroShown = true
        clearPathProgress.GroupTransparency = 1
        TweenService:Create(
            clearPathProgress,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { GroupTransparency = 0 }
        ):Play()

        player:SetAttribute("GuidedIntroClearPathProgressIntroduced", true)
        player:SetAttribute(
            "GuidedIntroClearPathProgressIntroducedAt",
            workspace:GetServerTimeNow()
        )
    end

    if clearPathLastProgress ~= nil and progress > clearPathLastProgress then
        pulseClearPathProgress(math.clamp(progress, 1, #progressDots))
        player:SetAttribute("GuidedIntroClearPathLastProgress", progress)
        player:SetAttribute(
            "GuidedIntroClearPathLastProgressAt",
            workspace:GetServerTimeNow()
        )
    end

    clearPathLastProgress = progress
end

-- Island 3 introduces a second progression vocabulary: waves.
-- It deliberately does NOT show the total 0/5 kill counter. The lesson is
-- "finish this wave, then another one", not "count five enemies".
local firstWaveBattle = Instance.new("CanvasGroup")
firstWaveBattle.Name = "FirstWaveBattle"
firstWaveBattle.Position = UDim2.fromOffset(12, 30)
firstWaveBattle.Size = UDim2.new(1, -24, 0, 22)
firstWaveBattle.BackgroundTransparency = 1
firstWaveBattle.GroupTransparency = 0
firstWaveBattle.Visible = false
firstWaveBattle.Parent = card

local waveKind = Instance.new("TextLabel")
waveKind.Name = "Kind"
waveKind.Position = UDim2.fromOffset(0, 1)
waveKind.Size = UDim2.fromOffset(44, 18)
waveKind.BackgroundTransparency = 1
waveKind.Text = "ONDA"
waveKind.TextColor3 = Color3.fromRGB(180, 154, 91)
waveKind.Font = Enum.Font.GothamBold
waveKind.TextSize = 9
waveKind.TextXAlignment = Enum.TextXAlignment.Left
waveKind.Parent = firstWaveBattle

local waveStepsHolder = Instance.new("Frame")
waveStepsHolder.Name = "Steps"
waveStepsHolder.Position = UDim2.fromOffset(50, 5)
waveStepsHolder.Size = UDim2.fromOffset(112, 12)
waveStepsHolder.BackgroundTransparency = 1
waveStepsHolder.Parent = firstWaveBattle

local waveSteps = {}
local waveStepScales = {}

for index = 1, 2 do
    local step = Instance.new("Frame")
    step.Name = "Wave" .. tostring(index)
    step.AnchorPoint = Vector2.new(0, 0.5)
    step.Position = UDim2.fromOffset((index - 1) * 56, 6)
    step.Size = UDim2.fromOffset(46, 8)
    step.BackgroundColor3 = Color3.fromRGB(58, 54, 42)
    step.BorderSizePixel = 0
    step.Parent = waveStepsHolder
    Instance.new("UICorner", step).CornerRadius = UDim.new(1, 0)

    local stepStroke = Instance.new("UIStroke")
    stepStroke.Name = "Stroke"
    stepStroke.Color = Color3.fromRGB(143, 124, 75)
    stepStroke.Transparency = 0.52
    stepStroke.Thickness = 1
    stepStroke.Parent = step

    local stepScale = Instance.new("UIScale")
    stepScale.Scale = 1
    stepScale.Parent = step

    waveSteps[index] = step
    waveStepScales[index] = stepScale
end

local waveCountLabel = Instance.new("TextLabel")
waveCountLabel.Name = "Count"
waveCountLabel.AnchorPoint = Vector2.new(1, 0)
waveCountLabel.Position = UDim2.new(1, 0, 0, 0)
waveCountLabel.Size = UDim2.fromOffset(66, 20)
waveCountLabel.BackgroundTransparency = 1
waveCountLabel.Text = "1 / 2"
waveCountLabel.TextColor3 = Color3.fromRGB(245, 218, 145)
waveCountLabel.Font = Enum.Font.GothamBlack
waveCountLabel.TextSize = 12
waveCountLabel.TextXAlignment = Enum.TextXAlignment.Right
waveCountLabel.Parent = firstWaveBattle

local waveCountScale = Instance.new("UIScale")
waveCountScale.Scale = 1
waveCountScale.Parent = waveCountLabel

local waveBattleIntroduced = false
local lastPresentedWave = 0
local lastPresentedWaveState = ""
local wavePulseSerial = 0

local function setWaveStepVisual(index, mode)
    local step = waveSteps[index]
    if not step then
        return
    end

    local stepStroke = step:FindFirstChild("Stroke")

    if mode == "Completed" then
        step.BackgroundColor3 = Color3.fromRGB(230, 193, 94)
        if stepStroke and stepStroke:IsA("UIStroke") then
            stepStroke.Color = Color3.fromRGB(255, 229, 158)
            stepStroke.Transparency = 0.12
        end
    elseif mode == "Active" then
        step.BackgroundColor3 = Color3.fromRGB(112, 91, 44)
        if stepStroke and stepStroke:IsA("UIStroke") then
            stepStroke.Color = Color3.fromRGB(245, 203, 103)
            stepStroke.Transparency = 0.12
        end
    else
        step.BackgroundColor3 = Color3.fromRGB(58, 54, 42)
        if stepStroke and stepStroke:IsA("UIStroke") then
            stepStroke.Color = Color3.fromRGB(143, 124, 75)
            stepStroke.Transparency = 0.52
        end
    end
end

local function pulseWaveStep(index)
    wavePulseSerial += 1
    local serial = wavePulseSerial
    local stepScale = waveStepScales[index]

    waveCountScale.Scale = 1
    TweenService:Create(
        waveCountScale,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Scale = 1.14 }
    ):Play()

    if stepScale then
        stepScale.Scale = 1
        TweenService:Create(
            stepScale,
            TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1.18 }
        ):Play()
    end

    task.delay(0.11, function()
        if serial ~= wavePulseSerial then
            return
        end

        TweenService:Create(
            waveCountScale,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { Scale = 1 }
        ):Play()

        if stepScale then
            TweenService:Create(
                stepScale,
                TweenInfo.new(0.17, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Scale = 1 }
            ):Play()
        end
    end)
end

local function updateFirstWaveBattle(waveIndex, waveCount, waveState)
    waveIndex = math.clamp(math.max(1, math.floor(tonumber(waveIndex) or 1)), 1, 2)
    waveCount = math.max(2, math.floor(tonumber(waveCount) or 2))

    local clearedCurrent = waveState == "Cleared"
    local completedWaves = math.max(0, waveIndex - 1)
    if clearedCurrent then
        completedWaves = math.max(completedWaves, waveIndex)
    end

    for index = 1, 2 do
        if index <= completedWaves then
            setWaveStepVisual(index, "Completed")
        elseif index == waveIndex and not clearedCurrent then
            setWaveStepVisual(index, "Active")
        else
            setWaveStepVisual(index, "Waiting")
        end
    end

    if clearedCurrent and waveIndex < waveCount then
        waveKind.Text = "PRONTA"
        waveCountLabel.Text = string.format("%d / %d", waveIndex, waveCount)
    else
        waveKind.Text = "ONDA"
        waveCountLabel.Text = string.format("%d / %d", waveIndex, waveCount)
    end

    if not waveBattleIntroduced then
        waveBattleIntroduced = true
        firstWaveBattle.GroupTransparency = 1

        TweenService:Create(
            firstWaveBattle,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { GroupTransparency = 0 }
        ):Play()

        player:SetAttribute("GuidedIntroWavesIntroduced", true)
        player:SetAttribute(
            "GuidedIntroWavesIntroducedAt",
            workspace:GetServerTimeNow()
        )
    end

    if waveIndex ~= lastPresentedWave and lastPresentedWave > 0 then
        pulseWaveStep(waveIndex)
        player:SetAttribute("GuidedIntroWaveAdvancedTo", waveIndex)
        player:SetAttribute(
            "GuidedIntroWaveAdvancedAt",
            workspace:GetServerTimeNow()
        )
    elseif clearedCurrent and lastPresentedWaveState ~= "Cleared" then
        pulseWaveStep(waveIndex)
        player:SetAttribute("GuidedIntroWaveCleared", waveIndex)
        player:SetAttribute(
            "GuidedIntroWaveClearedAt",
            workspace:GetServerTimeNow()
        )
    end

    player:SetAttribute("GuidedIntroCurrentWave", waveIndex)
    player:SetAttribute("GuidedIntroWaveCount", waveCount)

    lastPresentedWave = waveIndex
    lastPresentedWaveState = waveState
end

local cardScale = Instance.new("UIScale")
cardScale.Name = "GuidanceVisibilityScale"
cardScale.Scale = 0.97
cardScale.Parent = card

local cardDesiredVisible = false
local cardAnimationSerial = 0

local function setCardVisible(shouldShow)
    if cardDesiredVisible == shouldShow
        and card.Visible == shouldShow
    then
        return
    end

    cardDesiredVisible = shouldShow
    cardAnimationSerial += 1
    local serial = cardAnimationSerial

    if shouldShow then
        card.Visible = true
        TweenService:Create(
            cardScale,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            card,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.08 }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Transparency = 0.20 }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
        TweenService:Create(
            detail,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
    else
        TweenService:Create(
            cardScale,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.97 }
        ):Play()
        TweenService:Create(
            card,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }
        ):Play()
        TweenService:Create(
            detail,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }
        ):Play()

        task.delay(0.16, function()
            if serial == cardAnimationSerial and not cardDesiredVisible then
                card.Visible = false
            end
        end)
    end
end

card.Visible = false

local function hideLegacyPresentation()
    local unified = playerGui:FindFirstChild("DungeonUnifiedHUD")
    local root = unified and unified:FindFirstChild("Root")
    if root then
        for _, name in ipairs({
            "Objective",
            "RouteOverview",
            "ObjectiveContext",
            "OptionalRouteCard",
            "ContextualWaypointGuidance",
        }) do
            local instance = root:FindFirstChild(name)
            if instance then
                instance.Visible = false
            end
        end
    end
end

local function refresh()
    hideLegacyPresentation()

    local state = tostring(workspace:GetAttribute("DungeonProgressionState") or "WaitingForIsland1")
    local progress = math.floor(tonumber(workspace:GetAttribute("DungeonObjectiveProgress")) or 0)
    local target = math.max(1, math.floor(tonumber(workspace:GetAttribute("DungeonObjectiveTarget")) or 1))
    local objectiveTitle = tostring(workspace:GetAttribute("DungeonObjectiveTitle") or "")
    local objectiveId = tostring(workspace:GetAttribute("DungeonObjectiveId") or "")
    local island = math.max(1, math.floor(tonumber(workspace:GetAttribute("DungeonCurrentObjectiveIsland")) or 1))
    local round = math.max(1, math.floor(tonumber(workspace:GetAttribute("DungeonCurrentRoundIndex")) or 1))
    local waveIndex = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonEncounterWaveIndex")) or 0))
    local waveCount = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonEncounterWaveCount")) or 0))
    local waveState = tostring(workspace:GetAttribute("DungeonEncounterWaveState") or "")
    local rewardActive = workspace:GetAttribute("DungeonRewardIslandActive") == true
    local skyAmbushLandingState = tostring(
        workspace:GetAttribute("DungeonSkyAmbushLandingState") or "Idle"
    )
    local skyAmbushLandingExpected = math.max(
        0,
        math.floor(tonumber(workspace:GetAttribute("DungeonSkyAmbushLandingExpected")) or 0)
    )
    local skyAmbushLandingArrived = math.max(
        0,
        math.floor(tonumber(workspace:GetAttribute("DungeonSkyAmbushLandingArrived")) or 0)
    )
    local rewardRound = math.max(
        0,
        math.floor(tonumber(workspace:GetAttribute("DungeonRewardPendingRound")) or 0)
    )
    local coreClaimed = workspace:GetAttribute("DungeonRewardCoreClaimed") == true
    local guardWardsRemaining = math.max(
        0,
        math.floor(tonumber(workspace:GetAttribute("DungeonGuardWardsRemaining")) or 0)
    )
    local guardPhase = tostring(workspace:GetAttribute("DungeonGuardPhase") or "")
    local beaconOccupants = math.max(
        0,
        math.floor(tonumber(workspace:GetAttribute("DungeonBeaconOccupantCount")) or 0)
    )

    if player:GetAttribute("DungeonEntryPresentationState") ~= "Playing" then
        setCardVisible(false)
        wave.Visible = false
        return
    end

    if player:GetAttribute("DungeonFirstVictoryFeedbackActive") == true then
        setCardVisible(false)
        wave.Visible = false
        return
    end

    if player:GetAttribute("DungeonFirstRewardPresentationActive") == true then
        setCardVisible(false)
        wave.Visible = false
        return
    end

    if player:GetAttribute("DungeonBeginnerCurrencyPresentationActive") == true
        or player:GetAttribute("DungeonBeginnerCompanionPresentationActive") == true
        or player:GetAttribute("DungeonBeginnerUpgradePresentationActive") == true
        or player:GetAttribute("DungeonSkyAmbushPresentationActive") == true
        or player:GetAttribute("DungeonRangedThreatPresentationActive") == true
    then
        setCardVisible(false)
        wave.Visible = false
        return
    end

    -- The server warning state itself is also authoritative. Hide the compact
    -- card even if the dedicated presentation client has not set its local
    -- focus attribute yet (prevents a one-frame duplicate on slow devices).
    local serverIntroWarning =
        ((objectiveId == "SkyAmbush" or island == 4)
            and waveState == "AmbushWarning")
        or ((objectiveId == "RangedThreat" or island == 5)
            and waveState == "RangedWarning")

    if serverIntroWarning then
        setCardVisible(false)
        wave.Visible = false
        return
    end

    -- FirstStrike owns a large opening instruction before the normal compact
    -- objective HUD is allowed to appear. This prevents duplicated information.
    if (objectiveId == "FirstStrike" or island == 1)
        and player:GetAttribute("DungeonOpeningMissionState") ~= "CompactReady"
    then
        setCardVisible(false)
        wave.Visible = false
        return
    end

    -- Default Objective Card layout. Specific objectives may temporarily replace
    -- the detail row with a single new visual concept.
    detail.Visible = true
    clearPathProgress.Visible = false
    firstWaveBattle.Visible = false

    local isFirstRewardBattle =
        objectiveId == "FirstRewardBattle"
        or island == 3

    -- Island 3 owns a custom wave row. The legacy top-right wave badge remains
    -- available for later wave objectives, which are not being redesigned here.
    wave.Visible = state == "ObjectiveActive"
        and waveCount > 1
        and not isFirstRewardBattle

    if wave.Visible then
        wave.Text = waveState == "Cleared"
            and "PRÓXIMA ONDA"
            or string.format("ONDA %d/%d", math.max(1, waveIndex), waveCount)
    end

    if (skyAmbushLandingState == "AllLanded" or skyAmbushLandingState == "Timeout")
        and player:GetAttribute("DungeonSkyAmbushLanded") == true
    then
        setCardVisible(false)
        wave.Visible = false
        return

    elseif skyAmbushLandingState == "Waiting"
        and player:GetAttribute("DungeonSkyAmbushLanded") == true
    then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "AGUARDE O GRUPO"
        detail.Text = string.format(
            "%d / %d chegaram",
            skyAmbushLandingArrived,
            math.max(1, skyAmbushLandingExpected)
        )
        stroke.Color = Color3.fromRGB(104, 221, 255)

    elseif state == "WaitingForIsland1" then
        setCardVisible(true)
        title.Text = "PREPARANDO A ILHA"
        detail.Text = "Aguarde um instante..."
        stroke.Color = Color3.fromRGB(104, 221, 255)

    elseif state == "ObjectiveActive" then
        setCardVisible(true)

        if objectiveId == "SkyAmbush" or island == 4 then
            title.Text = "ELIMINE A EMBOSCADA"
            detail.Text = string.format("%d / %d", progress, target)
            stroke.Color = Color3.fromRGB(255, 118, 96)
        elseif objectiveId == "RangedThreat" or island == 5 then
            title.Text = "ELIMINE OS ATIRADORES"
            detail.Text = string.format("%d / %d", progress, target)
            stroke.Color = Color3.fromRGB(108, 180, 255)
        elseif island == 8 and guardWardsRemaining > 0 then
            title.Text = "QUEBRE OS CRISTAIS"
            detail.Text = string.format("%d cristais restantes", guardWardsRemaining)
            stroke.Color = Color3.fromRGB(91, 169, 255)
        elseif island == 8 and guardPhase == "DefeatGuards" then
            title.Text = "DERROTE OS GUARDS"
            detail.Text = string.format("%d / %d", progress, target)
            stroke.Color = Color3.fromRGB(188, 179, 255)
        elseif island == 9 then
            title.Text = beaconOccupants > 0 and "MANTENHA A POSIÇÃO" or "ENTRE NA ÁREA DO FAROL"
            detail.Text = string.format("%d / %d SEGUNDOS", progress, target)
            stroke.Color = Color3.fromRGB(143, 103, 255)
        elseif objectiveId == "FirstStrike" or island == 1 then
            title.Text = "DERROTE O SLIME!"
            detail.Text = string.format("%d / %d", progress, target)
            stroke.Color = Color3.fromRGB(104, 221, 255)
        elseif objectiveId == "ClearThePath" or island == 2 then
            if progress == 0 and clearPathLastProgress ~= 0 then
                clearPathLastProgress = 0
            end
            title.Text = "LIMPE O CAMINHO"
            detail.Visible = false
            clearPathProgress.Visible = true
            updateClearPathProgress(progress, target)
            stroke.Color = Color3.fromRGB(104, 221, 255)
        elseif objectiveId == "FirstRewardBattle" or island == 3 then
            title.Text = waveState == "Cleared"
                and "ONDA CONCLUÍDA"
                or "VENÇA AS ONDAS"
            detail.Visible = false
            firstWaveBattle.Visible = true
            updateFirstWaveBattle(
                math.max(1, waveIndex),
                math.max(2, waveCount),
                waveState
            )
            stroke.Color = Color3.fromRGB(231, 194, 104)
        else
            title.Text = string.upper(objectiveTitle ~= "" and objectiveTitle or "OBJETIVO")
            detail.Text = string.format("ROUND %d   •   ILHA %d   •   %d / %d", round, island, progress, target)

            if island == 3 then
                stroke.Color = Color3.fromRGB(231, 194, 104)
            elseif island == 4 then
                stroke.Color = Color3.fromRGB(255, 118, 96)
            elseif island == 5 then
                stroke.Color = Color3.fromRGB(108, 180, 255)
            elseif island == 8 then
                stroke.Color = Color3.fromRGB(188, 179, 255)
            elseif island == 9 then
                stroke.Color = Color3.fromRGB(143, 103, 255)
            elseif island == 10 then
                stroke.Color = Color3.fromRGB(193, 139, 255)
            elseif island == 11 then
                stroke.Color = Color3.fromRGB(255, 196, 91)
            elseif island == 12 then
                stroke.Color = Color3.fromRGB(255, 218, 103)
            else
                stroke.Color = Color3.fromRGB(104, 221, 255)
            end
        end

    elseif state == "ObjectiveCompleted" then
        setCardVisible(true)
        wave.Visible = false

        if objectiveId == "FirstRewardBattle" or island == 3 then
            title.Text = "ONDAS CONCLUÍDAS"
            detail.Text = "Área segura."
        else
            title.Text = "OBJETIVO CONCLUÍDO!"
            detail.Text = "Liberando a saída..."
        end

        stroke.Color = Color3.fromRGB(99, 235, 160)

    elseif state == "RewardPending" or rewardActive then
        wave.Visible = false

        local firstRewardReady =
            rewardRound == 1
            and player:GetAttribute("GuidedIntroActive") == true

        if firstRewardReady
            and player:GetAttribute("DungeonFirstRewardPresentationStage") ~= "CompactReady"
            and not coreClaimed
        then
            setCardVisible(false)
        else
            setCardVisible(true)

            if firstRewardReady then
                title.Text = coreClaimed and "RECOMPENSA RECEBIDA" or "ABRA O BAÚ"
                detail.Text = coreClaimed
                    and "Pronto."
                    or "Sua recompensa está esperando."
            else
                title.Text = coreClaimed and "CONFIRMANDO RECOMPENSA..." or "ABRA O CORE CHEST"
                detail.Text = coreClaimed
                    and "Aguarde a confirmação."
                    or "O baú principal libera o próximo round."
            end
        end

        stroke.Color = Color3.fromRGB(231, 194, 104)

    elseif state == "RewardCommitted" then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "RECOMPENSA CONFIRMADA!"
        detail.Text = round >= 2 and "Round 3 liberado." or "Round 2 liberado."
        stroke.Color = Color3.fromRGB(231, 194, 104)

    elseif state == "BossTransition" then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "RECOMPENSA FINAL CONFIRMADA!"
        detail.Text = "Preparando o caminho do Boss..."
        stroke.Color = Color3.fromRGB(255, 218, 103)

    elseif state == "BossRouteUnlocked" then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "CAMINHO DO BOSS LIBERADO"
        detail.Text = "Avance para o confronto final."
        stroke.Color = Color3.fromRGB(255, 218, 103)

    elseif state == "BossSanctuaryUnlocked" then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "BOSS"
        detail.Text = "Prepare-se para o confronto final."
        stroke.Color = Color3.fromRGB(255, 120, 96)

    elseif state == "TravelUnlocked" then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "VÁ PARA A PRÓXIMA ILHA"
        detail.Text = "A saída está liberada."
        stroke.Color = Color3.fromRGB(99, 235, 160)

    elseif state == "Part13Validated" then
        setCardVisible(true)
        wave.Visible = false
        title.Text = "DUNGEON COMPLETA"
        detail.Text = "As 12 ilhas e o caminho do Boss foram validados."
        stroke.Color = Color3.fromRGB(255, 218, 103)

    else
        setCardVisible(false)
        wave.Visible = false
    end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize
    if viewport then
        local phone = viewport.X < 700
        card.Size = UDim2.fromOffset(
            phone and math.max(250, math.min(350, viewport.X - 20)) or 350,
            62
        )
        -- Position is owned by DungeonResponsiveUI's absolute top lane.
    end
end

for _, attribute in ipairs({
    "DungeonProgressionState",
    "DungeonObjectiveProgress",
    "DungeonObjectiveTarget",
    "DungeonObjectiveTitle",
    "DungeonObjectiveId",
    "DungeonCurrentObjectiveIsland",
    "DungeonCurrentRoundIndex",
    "DungeonEncounterWaveIndex",
    "DungeonEncounterWaveCount",
    "DungeonEncounterWaveState",
    "DungeonRewardIslandActive",
    "DungeonRewardPendingRound",
    "DungeonSkyAmbushLandingArrived",
    "DungeonSkyAmbushLandingExpected",
    "DungeonSkyAmbushLandingState",
    "DungeonRewardCoreClaimed",
    "DungeonGuardWardsRemaining",
    "DungeonGuardPhase",
    "DungeonBeaconOccupantCount",
    "DungeonBeaconHeldSeconds",
}) do
    workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end

local nextRefresh = 0
RunService.RenderStepped:Connect(function()
    if os.clock() < nextRefresh then
        return
    end
    nextRefresh = os.clock() + 0.25
    refresh()
end)

player:SetAttribute("DungeonSimpleGuidanceReady", true)
workspace:SetAttribute("DungeonSimpleGuidanceReady", true)
player:GetAttributeChangedSignal("DungeonOpeningMissionState"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonFirstVictoryFeedbackActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonFirstRewardPresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonFirstRewardPresentationStage"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonBeginnerCurrencyPresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonBeginnerCompanionPresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonBeginnerUpgradePresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonSkyAmbushPresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonRangedThreatPresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonSkyAmbushLanded"):Connect(refresh)

refresh()
