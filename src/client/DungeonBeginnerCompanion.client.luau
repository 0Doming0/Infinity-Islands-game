--[[
    Infinity Islands — Rebuild Part 37
    First companion introduction.

    Teaches exactly one concept:
        this reward also gave me an ally.

    Server attributes come from the authoritative Round 1 grant result.
    No inventory/equip/stats/XP/upgrades are introduced here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "FirstCompanionRevealV1"
local PRE_REVEAL_BREATH = 0.18
local REVEAL_HOLD = 1.35
local SUBTEXT_DELAY = 0.22

local existing = playerGui:FindFirstChild("DungeonBeginnerCompanionHUD")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonBeginnerCompanionHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 97
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local holder = Instance.new("Frame")
holder.Name = "CompanionReveal"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(390, 122)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.ZIndex = 20
holder.Parent = gui

local holderScale = Instance.new("UIScale")
holderScale.Name = "CompanionRevealScale"
holderScale.Scale = 0.88
holderScale.Parent = holder

-- Small stylized slime portrait: reads as "ally/character", not inventory item.
local portrait = Instance.new("Frame")
portrait.Name = "Portrait"
portrait.AnchorPoint = Vector2.new(0.5, 0)
portrait.Position = UDim2.new(0.5, 0, 0, 0)
portrait.Size = UDim2.fromOffset(58, 48)
portrait.BackgroundColor3 = Color3.fromRGB(84, 211, 119)
portrait.BackgroundTransparency = 1
portrait.BorderSizePixel = 0
portrait.ZIndex = 21
portrait.Parent = holder

local portraitCorner = Instance.new("UICorner")
portraitCorner.CornerRadius = UDim.new(0.44, 0)
portraitCorner.Parent = portrait

local portraitStroke = Instance.new("UIStroke")
portraitStroke.Color = Color3.fromRGB(174, 255, 197)
portraitStroke.Transparency = 1
portraitStroke.Thickness = 1.4
portraitStroke.Parent = portrait

local eyeLeft = Instance.new("Frame")
eyeLeft.Name = "EyeLeft"
eyeLeft.AnchorPoint = Vector2.new(0.5, 0.5)
eyeLeft.Position = UDim2.fromScale(0.36, 0.47)
eyeLeft.Size = UDim2.fromOffset(7, 10)
eyeLeft.BackgroundColor3 = Color3.fromRGB(20, 43, 29)
eyeLeft.BackgroundTransparency = 1
eyeLeft.BorderSizePixel = 0
eyeLeft.ZIndex = 22
eyeLeft.Parent = portrait
Instance.new("UICorner", eyeLeft).CornerRadius = UDim.new(1, 0)

local eyeRight = eyeLeft:Clone()
eyeRight.Name = "EyeRight"
eyeRight.Position = UDim2.fromScale(0.64, 0.47)
eyeRight.Parent = portrait

local sparkle = Instance.new("TextLabel")
sparkle.Name = "Sparkle"
sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
sparkle.Position = UDim2.new(0.5, 35, 0, 15)
sparkle.Size = UDim2.fromOffset(26, 26)
sparkle.BackgroundTransparency = 1
sparkle.Text = "✦"
sparkle.TextColor3 = Color3.fromRGB(164, 255, 203)
sparkle.TextTransparency = 1
sparkle.Font = Enum.Font.GothamBlack
sparkle.TextSize = 20
sparkle.Rotation = 12
sparkle.ZIndex = 23
sparkle.Parent = holder

local eyebrow = Instance.new("TextLabel")
eyebrow.Name = "Eyebrow"
eyebrow.AnchorPoint = Vector2.new(0.5, 0)
eyebrow.Position = UDim2.new(0.5, 0, 0, 53)
eyebrow.Size = UDim2.new(1, -20, 0, 15)
eyebrow.BackgroundTransparency = 1
eyebrow.Text = "NOVO COMPANHEIRO"
eyebrow.TextColor3 = Color3.fromRGB(121, 231, 154)
eyebrow.TextTransparency = 1
eyebrow.Font = Enum.Font.GothamBold
eyebrow.TextSize = 10
eyebrow.ZIndex = 22
eyebrow.Parent = holder

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "Name"
nameLabel.AnchorPoint = Vector2.new(0.5, 0)
nameLabel.Position = UDim2.new(0.5, 0, 0, 68)
nameLabel.Size = UDim2.new(1, -20, 0, 28)
nameLabel.BackgroundTransparency = 1
nameLabel.Text = "GREEN SLIME"
nameLabel.TextColor3 = Color3.fromRGB(245, 251, 247)
nameLabel.TextTransparency = 1
nameLabel.TextStrokeColor3 = Color3.fromRGB(8, 26, 15)
nameLabel.TextStrokeTransparency = 1
nameLabel.Font = Enum.Font.GothamBlack
nameLabel.TextScaled = true
nameLabel.ZIndex = 22
nameLabel.Parent = holder

local nameConstraint = Instance.new("UITextSizeConstraint")
nameConstraint.MinTextSize = 18
nameConstraint.MaxTextSize = 25
nameConstraint.Parent = nameLabel

local detail = Instance.new("TextLabel")
detail.Name = "Detail"
detail.AnchorPoint = Vector2.new(0.5, 0)
detail.Position = UDim2.new(0.5, 0, 0, 98)
detail.Size = UDim2.new(1, -20, 0, 18)
detail.BackgroundTransparency = 1
detail.Text = "Um aliado se juntou a você."
detail.TextColor3 = Color3.fromRGB(180, 205, 187)
detail.TextTransparency = 1
detail.Font = Enum.Font.GothamMedium
detail.TextSize = 10
detail.ZIndex = 22
detail.Parent = holder

local triggered = false
local sequenceSerial = 0

local function displayNameFor(companionId)
    local fallback = companionId == "GreenSlime"
        and "GREEN SLIME"
        or string.upper(
            tostring(companionId or "COMPANHEIRO")
                :gsub("(%l)(%u)", "%1 %2")
        )

    local module = ReplicatedStorage:FindFirstChild("CompanionCatalog")
    if not module or not module:IsA("ModuleScript") then
        return fallback
    end

    local ok, catalog = pcall(require, module)
    if not ok or type(catalog) ~= "table" then
        return fallback
    end

    local definition
    if type(catalog.Get) == "function" then
        local success, result = pcall(catalog.Get, companionId)
        if success then
            definition = result
        end
    end

    if type(definition) == "table"
        and type(definition.DisplayName) == "string"
        and definition.DisplayName ~= ""
    then
        return string.upper(definition.DisplayName)
    end

    return fallback
end

local function readyToPresent()
    if triggered then
        return false
    end
    if player:GetAttribute("GuidedIntroActive") ~= true then
        return false
    end
    if player:GetAttribute("DungeonFirstRewardCompanionGranted") ~= true then
        return false
    end
    if player:GetAttribute("DungeonFirstRewardCompanionDuplicate") == true then
        return false
    end

    local companionId = tostring(
        player:GetAttribute("DungeonFirstRewardCompanionId") or ""
    )
    if companionId == "" then
        return false
    end

    -- Part 36 intentionally teaches currency first.
    if player:GetAttribute("GuidedIntroCurrencyIntroduced") ~= true then
        return false
    end
    if player:GetAttribute("DungeonBeginnerCurrencyPresentationActive") == true then
        return false
    end
    if player:GetAttribute("DungeonBeginnerCurrencyChipVisible") == true then
        return false
    end

    return true
end

local function setVisible(shouldShow)
    sequenceSerial += 1
    local serial = sequenceSerial

    if shouldShow then
        holder.Visible = true
        holderScale.Scale = 0.88

        portrait.BackgroundTransparency = 1
        portraitStroke.Transparency = 1
        eyeLeft.BackgroundTransparency = 1
        eyeRight.BackgroundTransparency = 1
        sparkle.TextTransparency = 1
        eyebrow.TextTransparency = 1
        nameLabel.TextTransparency = 1
        nameLabel.TextStrokeTransparency = 1
        detail.TextTransparency = 1
        TweenService:Create(
            holderScale,
            TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            portrait,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.05 }
        ):Play()
        TweenService:Create(
            portraitStroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Transparency = 0.20 }
        ):Play()
        TweenService:Create(
            eyeLeft,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0 }
        ):Play()
        TweenService:Create(
            eyeRight,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0 }
        ):Play()
        TweenService:Create(
            sparkle,
            TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {
                TextTransparency = 0.10,
                Rotation = 0,
            }
        ):Play()
        TweenService:Create(
            eyebrow,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()
        TweenService:Create(
            nameLabel,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0,
                TextStrokeTransparency = 0.62,
            }
        ):Play()

        task.delay(SUBTEXT_DELAY, function()
            if holder.Parent
                and player:GetAttribute("DungeonBeginnerCompanionPresentationActive") == true
            then
                TweenService:Create(
                    detail,
                    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { TextTransparency = 0.12 }
                ):Play()
            end
        end)
    else
        TweenService:Create(
            holderScale,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.95 }
        ):Play()

        for _, object in ipairs({ sparkle, eyebrow, nameLabel, detail }) do
            TweenService:Create(
                object,
                TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { TextTransparency = 1 }
            ):Play()
        end

        TweenService:Create(
            portrait,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            portraitStroke,
            TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }
        ):Play()
        TweenService:Create(
            eyeLeft,
            TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            eyeRight,
            TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()

        task.delay(0.16, function()
            if serial == sequenceSerial and holder.Parent then
                holder.Visible = false
            end
        end)
    end
end

local function runSequence()
    if not readyToPresent() then
        return
    end

    triggered = true
    local companionId = tostring(
        player:GetAttribute("DungeonFirstRewardCompanionId") or "GreenSlime"
    )

    player:SetAttribute("DungeonBeginnerCompanionPresentationActive", true)
    player:SetAttribute("DungeonBeginnerCompanionPresentationStage", "Breathing")
    player:SetAttribute("GuidedIntroCompanionIntroduced", true)
    player:SetAttribute("GuidedIntroCompanionId", companionId)
    player:SetAttribute(
        "GuidedIntroCompanionIntroducedAt",
        Workspace:GetServerTimeNow()
    )

    task.wait(PRE_REVEAL_BREATH)

    nameLabel.Text = displayNameFor(companionId)
    player:SetAttribute("DungeonBeginnerCompanionPresentationStage", "Reveal")
    setVisible(true)

    task.wait(REVEAL_HOLD)

    player:SetAttribute("DungeonBeginnerCompanionPresentationStage", "Leaving")
    setVisible(false)
    task.wait(0.17)

    player:SetAttribute("DungeonBeginnerCompanionPresentationStage", "Complete")
    player:SetAttribute("DungeonBeginnerCompanionPresentationActive", false)
    player:SetAttribute(
        "DungeonBeginnerCompanionPresentationCompletedAt",
        Workspace:GetServerTimeNow()
    )
end

local function evaluate()
    if readyToPresent() then
        task.spawn(runSequence)
    elseif player:GetAttribute("DungeonFirstRewardCompanionDuplicate") == true then
        player:SetAttribute("GuidedIntroCompanionIntroductionSkipped", "Duplicate")
    end
end

for _, attributeName in ipairs({
    "DungeonFirstRewardCompanionGranted",
    "DungeonFirstRewardCompanionDuplicate",
    "DungeonFirstRewardCompanionId",
    "GuidedIntroCurrencyIntroduced",
    "DungeonBeginnerCurrencyPresentationActive",
    "DungeonBeginnerCurrencyChipVisible",
}) do
    player:GetAttributeChangedSignal(attributeName):Connect(evaluate)
end

player:SetAttribute("DungeonBeginnerCompanionHUDReady", true)
player:SetAttribute("DungeonBeginnerCompanionHUDVersion", VERSION)
player:SetAttribute("DungeonBeginnerCompanionPresentationActive", false)
player:SetAttribute("DungeonBeginnerCompanionPresentationStage", "Waiting")

evaluate()
