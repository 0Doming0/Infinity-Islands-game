--[[
    Infinity Islands — Rebuild Part 31
    Beginner health presentation.

    Health is introduced by consequence, not by explanation:
    - full health at spawn: no health HUD;
    - first real damage: health-only card enters;
    - no stamina/buffs are exposed yet;
    - while damaged: card remains useful;
    - after full recovery: card leaves after a short hold.

    This is presentation-only. It never changes Humanoid health.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "BeginnerHealthRevealV1"
local FULL_THRESHOLD = 0.995
local FULL_HEALTH_HOLD = 2.2

local existing = playerGui:FindFirstChild("DungeonBeginnerHealthHUD")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonBeginnerHealthHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 57
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local card = Instance.new("Frame")
card.Name = "HealthCard"
card.AnchorPoint = Vector2.new(0, 0)
card.Position = UDim2.fromOffset(10, 0)
card.Size = UDim2.fromOffset(274, 68)
card.BackgroundColor3 = Color3.fromRGB(8, 23, 38)
card.BackgroundTransparency = 1
card.BorderSizePixel = 0
card.Visible = false
card.ZIndex = 10
card.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 15)
corner.Parent = card

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(244, 79, 91)
stroke.Transparency = 1
stroke.Thickness = 1.2
stroke.Parent = card

local cardScale = Instance.new("UIScale")
cardScale.Name = "HealthRevealScale"
cardScale.Scale = 0.95
cardScale.Parent = card

local iconHolder = Instance.new("Frame")
iconHolder.Name = "HeartHolder"
iconHolder.AnchorPoint = Vector2.new(0, 0.5)
iconHolder.Position = UDim2.new(0, 11, 0.5, 0)
iconHolder.Size = UDim2.fromOffset(44, 44)
iconHolder.BackgroundColor3 = Color3.fromRGB(56, 22, 31)
iconHolder.BackgroundTransparency = 0.12
iconHolder.BorderSizePixel = 0
iconHolder.ZIndex = 11
iconHolder.Parent = card

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0, 12)
iconCorner.Parent = iconHolder

local heart = Instance.new("TextLabel")
heart.Name = "Heart"
heart.Size = UDim2.fromScale(1, 1)
heart.BackgroundTransparency = 1
heart.Text = "♥"
heart.TextColor3 = Color3.fromRGB(247, 80, 93)
heart.TextTransparency = 1
heart.Font = Enum.Font.GothamBold
heart.TextSize = 23
heart.ZIndex = 12
heart.Parent = iconHolder

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(67, 8)
title.Size = UDim2.fromOffset(70, 18)
title.BackgroundTransparency = 1
title.Text = "VIDA"
title.TextColor3 = Color3.fromRGB(247, 110, 119)
title.TextTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 10
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 11
title.Parent = card

local value = Instance.new("TextLabel")
value.Name = "Value"
value.AnchorPoint = Vector2.new(1, 0)
value.Position = UDim2.new(1, -12, 0, 8)
value.Size = UDim2.fromOffset(118, 18)
value.BackgroundTransparency = 1
value.Text = "100 / 100"
value.TextColor3 = Color3.fromRGB(242, 248, 255)
value.TextTransparency = 1
value.Font = Enum.Font.GothamBold
value.TextSize = 11
value.TextXAlignment = Enum.TextXAlignment.Right
value.ZIndex = 11
value.Parent = card

local barBack = Instance.new("Frame")
barBack.Name = "HealthBar"
barBack.Position = UDim2.fromOffset(67, 34)
barBack.Size = UDim2.new(1, -80, 0, 12)
barBack.BackgroundColor3 = Color3.fromRGB(32, 16, 22)
barBack.BackgroundTransparency = 1
barBack.BorderSizePixel = 0
barBack.ClipsDescendants = true
barBack.ZIndex = 11
barBack.Parent = card

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBack

local lagFill = Instance.new("Frame")
lagFill.Name = "LagFill"
lagFill.Size = UDim2.fromScale(1, 1)
lagFill.BackgroundColor3 = Color3.fromRGB(255, 148, 105)
lagFill.BackgroundTransparency = 1
lagFill.BorderSizePixel = 0
lagFill.ZIndex = 12
lagFill.Parent = barBack

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(239, 58, 73)
fill.BackgroundTransparency = 1
fill.BorderSizePixel = 0
fill.ZIndex = 13
fill.Parent = barBack

local fillGradient = Instance.new("UIGradient")
fillGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 111)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(222, 43, 61)),
})
fillGradient.Parent = fill

local detail = Instance.new("TextLabel")
detail.Name = "Detail"
detail.Position = UDim2.fromOffset(67, 49)
detail.Size = UDim2.new(1, -80, 0, 13)
detail.BackgroundTransparency = 1
detail.Text = ""
detail.TextColor3 = Color3.fromRGB(176, 198, 215)
detail.TextTransparency = 1
detail.Font = Enum.Font.GothamMedium
detail.TextSize = 9
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.ZIndex = 11
detail.Parent = card

local visible = false
local visibilitySerial = 0
local recoverySerial = 0
local healthConnection
local maxHealthConnection
local lastHealth
local lastRatio = 1
local firstDamageObserved = false
local lagTween
local fillTween

local function beginnerPresentationActive()
    if player:GetAttribute("GuidedIntroActive") ~= true then
        return false
    end

    if player:GetAttribute("DungeonBeginnerUpgradePresentationActive") == true then
        return false
    end

    local stage = tostring(
        player:GetAttribute("GuidedIntroPresentationStage") or ""
    )
    return stage ~= "Complete"
end

local function setCardVisible(shouldShow)
    if visible == shouldShow and card.Visible == shouldShow then
        return
    end

    visible = shouldShow
    visibilitySerial += 1
    local serial = visibilitySerial

    if shouldShow then
        card.Visible = true
        cardScale.Scale = 0.95

        TweenService:Create(
            card,
            TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.08 }
        ):Play()
        TweenService:Create(
            cardScale,
            TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Transparency = 0.24 }
        ):Play()
        TweenService:Create(
            heart,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
        TweenService:Create(
            title,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
        TweenService:Create(
            value,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
        TweenService:Create(
            barBack,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.12 }
        ):Play()
        TweenService:Create(
            fill,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0 }
        ):Play()
        TweenService:Create(
            lagFill,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.10 }
        ):Play()
    else
        TweenService:Create(
            card,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            cardScale,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.96 }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }
        ):Play()
        for _, object in ipairs({ heart, title, value, detail }) do
            TweenService:Create(
                object,
                TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { TextTransparency = 1 }
            ):Play()
        end
        TweenService:Create(
            barBack,
            TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            fill,
            TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            lagFill,
            TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()

        task.delay(0.16, function()
            if serial == visibilitySerial and not visible and card.Parent then
                card.Visible = false
            end
        end)
    end
end

local function pulseDamage()
    local original = cardScale.Scale
    cardScale.Scale = math.max(original, 1)

    TweenService:Create(
        cardScale,
        TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Scale = 1.035 }
    ):Play()
    TweenService:Create(
        stroke,
        TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Transparency = 0.04,
            Thickness = 2.0,
        }
    ):Play()

    task.delay(0.10, function()
        TweenService:Create(
            cardScale,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                Transparency = 0.24,
                Thickness = 1.2,
            }
        ):Play()
    end)
end

local function scheduleHideAfterRecovery()
    recoverySerial += 1
    local serial = recoverySerial

    task.delay(FULL_HEALTH_HOLD, function()
        if serial ~= recoverySerial then
            return
        end
        if lastRatio >= FULL_THRESHOLD then
            setCardVisible(false)
        end
    end)
end

local function updateHealth(humanoid, health, damageOccurred)
    if not humanoid or humanoid.Parent == nil or humanoid.MaxHealth <= 0 then
        return
    end

    local ratio = math.clamp(health / humanoid.MaxHealth, 0, 1)
    local previousRatio = lastRatio
    lastRatio = ratio

    value.Text = string.format(
        "%d / %d",
        math.max(0, math.floor(health + 0.5)),
        math.max(1, math.floor(humanoid.MaxHealth + 0.5))
    )

    if fillTween then
        fillTween:Cancel()
    end
    fillTween = TweenService:Create(
        fill,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(ratio, 1) }
    )
    fillTween:Play()

    if damageOccurred then
        if lagTween then
            lagTween:Cancel()
        end
        lagFill.Size = UDim2.fromScale(math.max(ratio, previousRatio), 1)
        task.delay(0.18, function()
            if lagFill.Parent then
                lagTween = TweenService:Create(
                    lagFill,
                    TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Size = UDim2.fromScale(ratio, 1) }
                )
                lagTween:Play()
            end
        end)
    else
        lagFill.Size = UDim2.fromScale(ratio, 1)
    end

    if not beginnerPresentationActive() then
        setCardVisible(false)
        return
    end

    if damageOccurred then
        recoverySerial += 1
        setCardVisible(true)
        pulseDamage()

        if not firstDamageObserved then
            firstDamageObserved = true
            player:SetAttribute("GuidedIntroHealthLearned", true)
            player:SetAttribute(
                "GuidedIntroHealthIntroducedAt",
                Workspace:GetServerTimeNow()
            )
            player:SetAttribute(
                "GuidedIntroPresentationStage",
                "HealthIntroduced"
            )

            detail.Text = "Não deixe chegar a zero."
            detail.TextTransparency = 1
            TweenService:Create(
                detail,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = 0.18 }
            ):Play()

            task.delay(2.1, function()
                if detail.Parent then
                    TweenService:Create(
                        detail,
                        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                        { TextTransparency = 1 }
                    ):Play()
                end
            end)
        end
    end

    if ratio < FULL_THRESHOLD then
        recoverySerial += 1
        if firstDamageObserved then
            setCardVisible(true)
        end
    elseif firstDamageObserved then
        scheduleHideAfterRecovery()
    end
end

local function disconnectHumanoid()
    if healthConnection then
        healthConnection:Disconnect()
        healthConnection = nil
    end
    if maxHealthConnection then
        maxHealthConnection:Disconnect()
        maxHealthConnection = nil
    end
end

local function bindCharacter(character)
    disconnectHumanoid()

    firstDamageObserved =
        player:GetAttribute("GuidedIntroHealthLearned") == true

    local humanoid = character and character:WaitForChild("Humanoid", 8)
    if not humanoid then
        return
    end

    lastHealth = humanoid.Health
    lastRatio = humanoid.MaxHealth > 0
        and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        or 1

    fill.Size = UDim2.fromScale(lastRatio, 1)
    lagFill.Size = UDim2.fromScale(lastRatio, 1)
    value.Text = string.format(
        "%d / %d",
        math.max(0, math.floor(humanoid.Health + 0.5)),
        math.max(1, math.floor(humanoid.MaxHealth + 0.5))
    )

    -- Do not reveal health merely because the character spawned below max HP.
    -- The introduction is tied to an observed damage event in this session.
    setCardVisible(false)

    healthConnection = humanoid.HealthChanged:Connect(function(health)
        local previous = lastHealth or health
        local damageOccurred = health < previous - 0.05
        lastHealth = health
        updateHealth(humanoid, health, damageOccurred)
    end)

    maxHealthConnection = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        lastHealth = math.min(lastHealth or humanoid.Health, humanoid.Health)
        updateHealth(humanoid, humanoid.Health, false)
    end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
    task.defer(bindCharacter, player.Character)
end

player:GetAttributeChangedSignal("GuidedIntroActive"):Connect(function()
    if not beginnerPresentationActive() then
        setCardVisible(false)
    end
end)

player:GetAttributeChangedSignal("GuidedIntroPresentationStage"):Connect(function()
    if not beginnerPresentationActive() then
        setCardVisible(false)
    end
end)

player:GetAttributeChangedSignal("DungeonBeginnerUpgradePresentationActive"):Connect(function()
    if not beginnerPresentationActive() then
        setCardVisible(false)
    end
end)

player:SetAttribute("DungeonBeginnerHealthHUDReady", true)
player:SetAttribute("DungeonBeginnerHealthHUDVersion", VERSION)
