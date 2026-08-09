--[[
    Infinity Islands — Rebuild Part 36
    First confirmed-currency introduction.

    Teaches ONE visual concept:
        the reward increased my coin balance.

    Important:
    - ignores PendingRoundCoins completely;
    - ignores initial profile/leaderstats hydration;
    - waits for the Round 1 reward window;
    - waits for the real Core claim;
    - uses the authoritative player Coins attribute;
    - never changes currency itself.

    First reveal:
        ◆
        +40 MOEDAS
        -> ◆ 140

    Later confirmed coin changes during the Guide can briefly reuse the compact chip,
    but the full Confirmed/Pending currencies panel remains hidden until Guide ends.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "BeginnerCurrencyV2"
local FIRST_GAIN_HOLD = 0.72
local BALANCE_HOLD = 2.15
local REPEAT_HOLD = 2.20

local existing = playerGui:FindFirstChild("DungeonBeginnerCurrencyHUD")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonBeginnerCurrencyHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 96
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local holder = Instance.new("Frame")
holder.Name = "CurrencyReveal"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(330, 76)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Parent = gui

local holderScale = Instance.new("UIScale")
holderScale.Name = "CurrencyRevealScale"
holderScale.Scale = 0.90
holderScale.Parent = holder

local glyph = Instance.new("TextLabel")
glyph.Name = "Glyph"
glyph.AnchorPoint = Vector2.new(0.5, 0)
glyph.Position = UDim2.new(0.5, 0, 0, 0)
glyph.Size = UDim2.fromOffset(34, 28)
glyph.BackgroundTransparency = 1
glyph.Text = "◆"
glyph.TextColor3 = Color3.fromRGB(255, 213, 93)
glyph.TextTransparency = 1
glyph.TextStrokeColor3 = Color3.fromRGB(39, 28, 4)
glyph.TextStrokeTransparency = 1
glyph.Font = Enum.Font.GothamBlack
glyph.TextSize = 24
glyph.ZIndex = 22
glyph.Parent = holder

local amountLabel = Instance.new("TextLabel")
amountLabel.Name = "Amount"
amountLabel.AnchorPoint = Vector2.new(0.5, 0)
amountLabel.Position = UDim2.new(0.5, 0, 0, 26)
amountLabel.Size = UDim2.new(1, -18, 0, 32)
amountLabel.BackgroundTransparency = 1
amountLabel.Text = "+0 MOEDAS"
amountLabel.TextColor3 = Color3.fromRGB(251, 247, 226)
amountLabel.TextTransparency = 1
amountLabel.TextStrokeColor3 = Color3.fromRGB(35, 27, 6)
amountLabel.TextStrokeTransparency = 1
amountLabel.Font = Enum.Font.GothamBlack
amountLabel.TextScaled = true
amountLabel.ZIndex = 22
amountLabel.Parent = holder

local amountConstraint = Instance.new("UITextSizeConstraint")
amountConstraint.MinTextSize = 19
amountConstraint.MaxTextSize = 28
amountConstraint.Parent = amountLabel

local meaningLabel = Instance.new("TextLabel")
meaningLabel.Name = "Meaning"
meaningLabel.AnchorPoint = Vector2.new(0.5, 0)
meaningLabel.Position = UDim2.new(0.5, 0, 0, 58)
meaningLabel.Size = UDim2.new(1, -18, 0, 15)
meaningLabel.BackgroundTransparency = 1
meaningLabel.Text = "Agora são suas."
meaningLabel.TextColor3 = Color3.fromRGB(181, 197, 208)
meaningLabel.TextTransparency = 1
meaningLabel.Font = Enum.Font.GothamMedium
meaningLabel.TextSize = 9
meaningLabel.ZIndex = 22
meaningLabel.Parent = holder

local compact = Instance.new("Frame")
compact.Name = "CurrencyChip"
compact.AnchorPoint = Vector2.new(0, 0)
compact.Position = UDim2.fromOffset(10, 8)
compact.Size = UDim2.fromOffset(152, 44)
compact.BackgroundColor3 = Color3.fromRGB(16, 29, 39)
compact.BackgroundTransparency = 1
compact.BorderSizePixel = 0
compact.Visible = false
compact.ZIndex = 20
compact.Parent = gui

local compactCorner = Instance.new("UICorner")
compactCorner.CornerRadius = UDim.new(0, 13)
compactCorner.Parent = compact

local compactStroke = Instance.new("UIStroke")
compactStroke.Color = Color3.fromRGB(255, 211, 91)
compactStroke.Transparency = 1
compactStroke.Thickness = 1.1
compactStroke.Parent = compact

local compactScale = Instance.new("UIScale")
compactScale.Name = "CurrencyChipScale"
compactScale.Scale = 0.96
compactScale.Parent = compact

local compactGlyph = Instance.new("TextLabel")
compactGlyph.Name = "Glyph"
compactGlyph.Position = UDim2.fromOffset(10, 0)
compactGlyph.Size = UDim2.fromOffset(30, 44)
compactGlyph.BackgroundTransparency = 1
compactGlyph.Text = "◆"
compactGlyph.TextColor3 = Color3.fromRGB(255, 213, 93)
compactGlyph.TextTransparency = 1
compactGlyph.Font = Enum.Font.GothamBlack
compactGlyph.TextSize = 18
compactGlyph.ZIndex = 21
compactGlyph.Parent = compact

local compactTitle = Instance.new("TextLabel")
compactTitle.Name = "Title"
compactTitle.Position = UDim2.fromOffset(43, 5)
compactTitle.Size = UDim2.new(1, -52, 0, 13)
compactTitle.BackgroundTransparency = 1
compactTitle.Text = "MOEDAS"
compactTitle.TextColor3 = Color3.fromRGB(194, 168, 95)
compactTitle.TextTransparency = 1
compactTitle.Font = Enum.Font.GothamBold
compactTitle.TextSize = 8
compactTitle.TextXAlignment = Enum.TextXAlignment.Left
compactTitle.ZIndex = 21
compactTitle.Parent = compact

local compactBalance = Instance.new("TextLabel")
compactBalance.Name = "Balance"
compactBalance.Position = UDim2.fromOffset(43, 17)
compactBalance.Size = UDim2.new(1, -52, 0, 22)
compactBalance.BackgroundTransparency = 1
compactBalance.Text = "0"
compactBalance.TextColor3 = Color3.fromRGB(246, 248, 249)
compactBalance.TextTransparency = 1
compactBalance.Font = Enum.Font.GothamBlack
compactBalance.TextSize = 16
compactBalance.TextXAlignment = Enum.TextXAlignment.Left
compactBalance.ZIndex = 21
compactBalance.Parent = compact

local previousCoins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
local candidateDelta = 0
local candidateBalance = previousCoins
local introRunning = false
local introduced = player:GetAttribute("GuidedIntroCurrencyIntroduced") == true
local visibleSerial = 0
local compactSerial = 0

local function beginnerActive()
    return player:GetAttribute("GuidedIntroActive") == true
        and tostring(player:GetAttribute("GuidedIntroPresentationStage") or "") ~= "Complete"
end

local function firstRewardWindowHasStarted()
    local stage = tostring(
        player:GetAttribute("DungeonFirstRewardPresentationStage") or ""
    )
    return stage == "WaitingForChest"
        or stage == "Breathing"
        or stage == "RewardReveal"
        or stage == "CompactReady"
end

local function firstCoreClaimed()
    return Workspace:GetAttribute("DungeonRewardCoreClaimed") == true
        or player:GetAttribute("DungeonRewardCoreClaimed") == true
end

local function fadeRevealOut()
    visibleSerial += 1
    local serial = visibleSerial

    TweenService:Create(
        holderScale,
        TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Scale = 0.95 }
    ):Play()

    for _, label in ipairs({ glyph, amountLabel, meaningLabel }) do
        TweenService:Create(
            label,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = label.TextStrokeTransparency ~= nil and 1 or nil,
            }
        ):Play()
    end

    task.delay(0.15, function()
        if serial == visibleSerial and holder.Parent then
            holder.Visible = false
        end
    end)
end

local function showCompact(balance, holdSeconds)
    compactSerial += 1
    local serial = compactSerial

    compactBalance.Text = tostring(math.max(0, math.floor(balance)))
    compact.Visible = true
    player:SetAttribute("DungeonBeginnerCurrencyChipVisible", true)
    compact.BackgroundTransparency = 1
    compactStroke.Transparency = 1
    compactGlyph.TextTransparency = 1
    compactTitle.TextTransparency = 1
    compactBalance.TextTransparency = 1
    compactScale.Scale = 0.96

    TweenService:Create(
        compact,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.10 }
    ):Play()
    TweenService:Create(
        compactStroke,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Transparency = 0.32 }
    ):Play()
    TweenService:Create(
        compactScale,
        TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()

    for _, label in ipairs({ compactGlyph, compactTitle, compactBalance }) do
        TweenService:Create(
            label,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
    end

    task.delay(holdSeconds or BALANCE_HOLD, function()
        if serial ~= compactSerial then
            return
        end

        TweenService:Create(
            compact,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            compactStroke,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }
        ):Play()
        TweenService:Create(
            compactScale,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.96 }
        ):Play()

        for _, label in ipairs({ compactGlyph, compactTitle, compactBalance }) do
            TweenService:Create(
                label,
                TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { TextTransparency = 1 }
            ):Play()
        end

        task.delay(0.15, function()
            if serial == compactSerial and compact.Parent then
                compact.Visible = false
                player:SetAttribute("DungeonBeginnerCurrencyChipVisible", false)
            end
        end)
    end)
end

local function runFirstIntroduction(delta, balance)
    if introRunning or introduced or not beginnerActive() then
        return
    end

    introRunning = true
    introduced = true

    player:SetAttribute("DungeonBeginnerCurrencyPresentationActive", true)
    player:SetAttribute("DungeonBeginnerCurrencyPresentationStage", "Gain")
    player:SetAttribute("GuidedIntroCurrencyIntroduced", true)
    player:SetAttribute(
        "GuidedIntroCurrencyIntroducedAt",
        Workspace:GetServerTimeNow()
    )
    player:SetAttribute("GuidedIntroFirstConfirmedCoinGain", delta)
    player:SetAttribute("GuidedIntroFirstConfirmedCoinBalance", balance)

    holder.Visible = true
    holderScale.Scale = 0.90
    amountLabel.Text = string.format("+%d MOEDAS", delta)
    glyph.TextTransparency = 1
    glyph.TextStrokeTransparency = 1
    amountLabel.TextTransparency = 1
    amountLabel.TextStrokeTransparency = 1
    meaningLabel.TextTransparency = 1
    TweenService:Create(
        holderScale,
        TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
    TweenService:Create(
        glyph,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 0,
            TextStrokeTransparency = 0.58,
        }
    ):Play()
    TweenService:Create(
        amountLabel,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 0,
            TextStrokeTransparency = 0.58,
        }
    ):Play()

    task.delay(0.18, function()
        if holder.Parent then
            TweenService:Create(
                meaningLabel,
                TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = 0.20 }
            ):Play()
        end
    end)

    task.wait(FIRST_GAIN_HOLD)

    player:SetAttribute("DungeonBeginnerCurrencyPresentationStage", "Balance")
    fadeRevealOut()
    task.wait(0.16)

    showCompact(balance, BALANCE_HOLD)

    player:SetAttribute("DungeonBeginnerCurrencyPresentationStage", "Complete")
    player:SetAttribute("DungeonBeginnerCurrencyPresentationActive", false)
    player:SetAttribute(
        "DungeonBeginnerCurrencyPresentationCompletedAt",
        Workspace:GetServerTimeNow()
    )

    introRunning = false
end

local function tryConsumeCandidate()
    if introduced
        or introRunning
        or candidateDelta <= 0
        or not beginnerActive()
        or not firstRewardWindowHasStarted()
        or not firstCoreClaimed()
    then
        return
    end

    local delta = candidateDelta
    local balance = candidateBalance
    candidateDelta = 0

    task.spawn(runFirstIntroduction, delta, balance)
end

local function onCoinsChanged()
    local current = math.max(
        0,
        math.floor(tonumber(player:GetAttribute("Coins")) or 0)
    )
    local delta = current - previousCoins
    previousCoins = current

    if delta <= 0 then
        return
    end

    -- Ignore initial/profile hydration and any unrelated confirmed reward.
    -- Round 1 presentation must already have started.
    if beginnerActive() and firstRewardWindowHasStarted() and not introduced then
        candidateDelta += delta
        candidateBalance = current
        tryConsumeCandidate()
        return
    end

    -- Once the icon/meaning has been taught, reuse only the small chip for
    -- later confirmed gains during the Guide.
    if beginnerActive() and introduced then
        player:SetAttribute("GuidedIntroLastConfirmedCoinGain", delta)
        player:SetAttribute(
            "GuidedIntroLastConfirmedCoinGainAt",
            Workspace:GetServerTimeNow()
        )
        showCompact(current, REPEAT_HOLD)
    end
end

player:GetAttributeChangedSignal("Coins"):Connect(onCoinsChanged)
player:GetAttributeChangedSignal("DungeonRewardCoreClaimed"):Connect(tryConsumeCandidate)
player:GetAttributeChangedSignal("DungeonFirstRewardPresentationStage"):Connect(tryConsumeCandidate)
Workspace:GetAttributeChangedSignal("DungeonRewardCoreClaimed"):Connect(tryConsumeCandidate)

player:SetAttribute("DungeonBeginnerCurrencyHUDReady", true)
player:SetAttribute("DungeonBeginnerCurrencyHUDVersion", VERSION)
player:SetAttribute("DungeonBeginnerCurrencyPresentationActive", false)
player:SetAttribute("DungeonBeginnerCurrencyChipVisible", false)
player:SetAttribute("DungeonBeginnerCurrencyPresentationStage", introduced and "Complete" or "Waiting")
