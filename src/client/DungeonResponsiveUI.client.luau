--[[
    Infinity Islands — Rebuild Part 23
    Global responsive UI controller.

    Goals:
    - respect Roblox Core UI + device safe areas;
    - compute layout from the safe viewport, not raw width heuristics;
    - adapt portrait/landscape, touch/desktop, tablets and small laptops;
    - keep touch controls physically usable;
    - preserve Roblox PreferredTextSize behavior;
    - provide a generic fallback for ScreenGuis not yet migrated.

    This script is presentation-only.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "AbsoluteTopLaneV2"
local APPLY_BIND = "DungeonResponsiveUI_" .. tostring(player.UserId)

local managedConnections = {}
local pendingApply = false
local lastSignature = ""

local function disconnectManaged()
    for _, connection in ipairs(managedConnections) do
        connection:Disconnect()
    end
    table.clear(managedConnections)
end

local function currentViewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function safeViewport()
    local physical = currentViewport()

    -- GetGuiInset works with IgnoreGuiInset=false and gives the effective
    -- top-left / bottom-right user-GUI insets.
    local ok, topLeft, bottomRight = pcall(function()
        local first, second = GuiService:GetGuiInset()
        return first, second
    end)

    if not ok
        or typeof(topLeft) ~= "Vector2"
        or typeof(bottomRight) ~= "Vector2"
    then
        topLeft = Vector2.zero
        bottomRight = Vector2.zero
    end

    local width = math.max(1, physical.X - topLeft.X - bottomRight.X)
    local height = math.max(1, physical.Y - topLeft.Y - bottomRight.Y)

    return {
        Physical = physical,
        TopLeftInset = topLeft,
        BottomRightInset = bottomRight,
        Size = Vector2.new(width, height),
    }
end

local function preferredTextClass()
    local value = GuiService.PreferredTextSize
    if value == Enum.PreferredTextSize.Largest then
        return "Largest"
    elseif value == Enum.PreferredTextSize.Larger then
        return "Larger"
    elseif value == Enum.PreferredTextSize.Large then
        return "Large"
    end
    return "Medium"
end

local function calculateMetrics()
    local safe = safeViewport()
    local width = safe.Size.X
    local height = safe.Size.Y
    local shortest = math.max(1, math.min(width, height))
    local longest = math.max(width, height)
    local touch = UserInputService.TouchEnabled
    local portrait = height > width * 1.08
    local aspect = width / math.max(1, height)

    -- UI assets were authored around desktop pixel dimensions.
    --
    -- Touch:
    -- 390 px short side -> ~0.59 scale.
    -- 320 px short side -> clamped to 0.52 so 96px actions remain ~50px.
    --
    -- Desktop:
    -- 720p short side -> ~0.82.
    -- 1080p short side -> ~1.18.
    local rawScale
    if touch then
        rawScale = (shortest / 720) ^ 0.85
    else
        rawScale = (shortest / 900) ^ 0.90
    end

    local baseScale = touch
        and math.clamp(rawScale, 0.52, 0.92)
        or math.clamp(rawScale, 0.72, 1.20)

    if GuiService.ViewportDisplaySize == Enum.DisplaySize.Large then
        baseScale = math.min(1.28, baseScale * 1.05)
    end

    local margin = math.clamp(math.floor(shortest * 0.018 + 0.5), 8, 26)
    local gap = math.clamp(math.floor(shortest * 0.014 + 0.5), 6, 18)

    local topbarRect = Rect.new(0, 0, width, 0)
    local topbarOk, resolvedTopbar = pcall(function()
        return GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)
    end)
    if topbarOk and typeof(resolvedTopbar) == "Rect" then
        topbarRect = resolvedTopbar
    end

    local deviceClass
    if touch and shortest < 600 then
        deviceClass = portrait and "PhonePortrait" or "PhoneLandscape"
    elseif touch then
        deviceClass = portrait and "TabletPortrait" or "TabletLandscape"
    elseif width < 1100 or height < 680 then
        deviceClass = "CompactDesktop"
    elseif GuiService.ViewportDisplaySize == Enum.DisplaySize.Large then
        deviceClass = "LargeDisplay"
    else
        deviceClass = "Desktop"
    end

    return {
        Safe = safe,
        Width = width,
        Height = height,
        Shortest = shortest,
        Longest = longest,
        Aspect = aspect,
        Touch = touch,
        Portrait = portrait,
        BaseScale = baseScale,
        Margin = margin,
        Gap = gap,
        DeviceClass = deviceClass,
        PreferredTextClass = preferredTextClass(),
        TopbarRect = topbarRect,
    }
end

-- ScreenInsets=CoreUISafeInsets makes Y=0 start BELOW Roblox's top bar.
-- TopbarSafeInsets, queried through GetInsetArea(), is relative to that same
-- CoreUISafeInsets origin and may therefore have a NEGATIVE Y.
--
-- For non-interactive top-center status UI, that negative Y is exactly what
-- we want: the element begins in the real free top-bar lane instead of being
-- pushed an entire Roblox top-bar height downward.
local function absoluteTopLane(gui, metrics, preferredWidth)
    local rect = metrics.TopbarRect
    local left = rect and rect.Min.X or 0
    local right = rect and rect.Max.X or metrics.Width
    local top = rect and rect.Min.Y or 0

    if right - left < 40 then
        left = 0
        right = metrics.Width
        top = 0
    end

    local availableWidth = math.max(1, right - left)
    local width = math.min(
        preferredWidth,
        math.max(1, availableWidth - 4)
    )
    local centerX = left + availableWidth * 0.5

    -- The coordinates are still relative to CoreUISafeInsets, but the chosen
    -- lane intentionally extends upward into TopbarSafeInsets.
    pcall(function()
        gui.ClipToDeviceSafeArea = false
    end)

    gui:SetAttribute("ResponsiveAbsoluteTopManaged", true)
    gui:SetAttribute("ResponsiveAbsoluteTopY", top)
    gui:SetAttribute("ResponsiveTopbarLaneWidth", availableWidth)

    return centerX, top, width, availableWidth
end

local function topContentBottom(metrics, physicalHeight)
    local rect = metrics.TopbarRect
    local top = rect and rect.Min.Y or 0
    return math.max(0, top + physicalHeight)
end

local function setScreenSafeArea(gui)
    if not gui or not gui:IsA("ScreenGui") then
        return
    end
    if gui:GetAttribute("ResponsiveUIOptOut") == true then
        return
    end

    pcall(function()
        gui.IgnoreGuiInset = false
        gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
        gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
        gui.ClipToDeviceSafeArea = true
    end)

    gui:SetAttribute("ResponsiveUIManaged", true)
    gui:SetAttribute("ResponsiveUIVersion", VERSION)
end

local function getOrCreateScale(object, preferredName)
    if not object or not object:IsA("GuiObject") then
        return nil
    end

    local existing = object:FindFirstChild(preferredName or "ResponsiveScale")
    if existing and existing:IsA("UIScale") then
        return existing
    end

    existing = object:FindFirstChildWhichIsA("UIScale")
    if existing then
        return existing
    end

    local scale = Instance.new("UIScale")
    scale.Name = preferredName or "GlobalResponsiveScale"
    scale.Scale = 1
    scale.Parent = object
    return scale
end

local function fitScale(baseScale, designWidth, designHeight, maxWidth, maxHeight, minimum)
    local scale = baseScale

    if designWidth and designWidth > 0 and maxWidth and maxWidth > 0 then
        scale = math.min(scale, maxWidth / designWidth)
    end
    if designHeight and designHeight > 0 and maxHeight and maxHeight > 0 then
        scale = math.min(scale, maxHeight / designHeight)
    end

    return math.clamp(scale, minimum or 0.42, 1.28)
end

local function applyScale(object, value)
    local scale = getOrCreateScale(object)
    if scale then
        scale.Scale = value
    end
end

local function isFullscreenRoot(object)
    if not object or not object:IsA("GuiObject") then
        return false
    end

    local size = object.Size
    return size.X.Scale >= 0.94
        and size.Y.Scale >= 0.94
        and math.abs(size.X.Offset) <= 8
        and math.abs(size.Y.Offset) <= 8
end

local function applyUnifiedHud(gui, metrics)
    local root = gui:FindFirstChild("Root")
    if not root or not root:IsA("GuiObject") then
        return
    end

    local margin = metrics.Margin
    local coreTop = 0
    local gap = metrics.Gap
    local safeW = metrics.Width
    local safeH = metrics.Height
    local base = metrics.BaseScale
    local objectiveTopX, objectiveTopY, _, objectiveLaneWidth =
        absoluteTopLane(gui, metrics, 800)

    local currencies = root:FindFirstChild("Currencies")
    local objective = root:FindFirstChild("Objective")
    local party = root:FindFirstChild("Party")
    local vitals = root:FindFirstChild("Vitals")
    local hotbar = root:FindFirstChild("Hotbar")
    local notification = root:FindFirstChild("Notification")
    local stateBanner = root:FindFirstChild("StateBanner")
    local inventoryDrawer = root:FindFirstChild("InventoryDrawer")

    -- Decide whether top panels can share one physical row.
    -- Design widths: 310 + 800 + 310 = 1420.
    local sharedTopScale = math.min(
        base,
        math.max(0.1, (safeW - margin * 4) / 1420)
    )
    local stackTop = metrics.Portrait or sharedTopScale < 0.50

    local objectiveScale = math.min(
        fitScale(
            base,
            800,
            108,
            safeW - margin * 2,
            safeH * 0.25,
            0.30
        ),
        math.max(0.30, (objectiveLaneWidth - 4) / 800)
    )

    if stackTop then
        if objective then
            objective.AnchorPoint = Vector2.new(0.5, 0)
            objective.Position = UDim2.fromOffset(objectiveTopX, objectiveTopY)
            objective.Size = UDim2.fromOffset(800, 108)
            applyScale(objective, objectiveScale)
        end

        local objectivePhysicalH = 108 * objectiveScale
        local secondRowY = math.max(
            coreTop,
            objectiveTopY + objectivePhysicalH + gap
        )
        local halfWidth = math.max(1, (safeW - margin * 3) / 2)
        local sideScale = fitScale(
            base,
            310,
            286,
            halfWidth,
            safeH * 0.34,
            0.48
        )

        if currencies then
            currencies.AnchorPoint = Vector2.new(0, 0)
            currencies.Position = UDim2.fromOffset(margin, secondRowY)
            currencies.Size = UDim2.fromOffset(310, 170)
            applyScale(currencies, sideScale)
        end

        if party then
            party.AnchorPoint = Vector2.new(1, 0)
            party.Position = UDim2.new(1, -margin, 0, secondRowY)
            party.Size = UDim2.fromOffset(310, 286)
            applyScale(party, sideScale)
        end
    else
        if currencies then
            currencies.AnchorPoint = Vector2.new(0, 0)
            currencies.Position = UDim2.fromOffset(margin, coreTop)
            currencies.Size = UDim2.fromOffset(310, 170)
            applyScale(currencies, sharedTopScale)
        end

        if objective then
            objective.AnchorPoint = Vector2.new(0.5, 0)
            objective.Position = UDim2.fromOffset(objectiveTopX, objectiveTopY)
            objective.Size = UDim2.fromOffset(800, 108)
            applyScale(
                objective,
                math.min(
                    sharedTopScale,
                    math.max(0.30, (objectiveLaneWidth - 4) / 800)
                )
            )
        end

        if party then
            party.AnchorPoint = Vector2.new(1, 0)
            party.Position = UDim2.new(1, -margin, 0, coreTop)
            party.Size = UDim2.fromOffset(310, 286)
            applyScale(party, sharedTopScale)
        end
    end

    local hotbarScale = fitScale(
        base,
        590,
        134,
        safeW - margin * 2,
        safeH * 0.26,
        metrics.Touch and 0.52 or 0.62
    )
    local vitalsScale = fitScale(
        base,
        500,
        156,
        safeW - margin * 2,
        safeH * 0.28,
        0.48
    )

    if metrics.Portrait then
        if hotbar then
            hotbar.AnchorPoint = Vector2.new(0.5, 1)
            hotbar.Position = UDim2.new(0.5, 0, 1, -margin)
            hotbar.Size = UDim2.fromOffset(590, 134)
            applyScale(hotbar, hotbarScale)
        end

        local hotbarPhysicalH = 134 * hotbarScale
        if vitals then
            vitals.AnchorPoint = Vector2.new(0, 1)
            vitals.Position = UDim2.new(
                0,
                margin,
                1,
                -(margin + hotbarPhysicalH + gap)
            )
            vitals.Size = UDim2.fromOffset(500, 156)
            applyScale(vitals, vitalsScale)
        end
    elseif safeW < 1100 then
        -- Compact landscape: vitals left, hotbar right.
        if vitals then
            vitals.AnchorPoint = Vector2.new(0, 1)
            vitals.Position = UDim2.new(0, margin, 1, -margin)
            vitals.Size = UDim2.fromOffset(500, 156)
            applyScale(vitals, vitalsScale)
        end
        if hotbar then
            hotbar.AnchorPoint = Vector2.new(1, 1)
            hotbar.Position = UDim2.new(1, -margin, 1, -margin)
            hotbar.Size = UDim2.fromOffset(590, 134)
            applyScale(hotbar, hotbarScale)
        end
    else
        if vitals then
            vitals.AnchorPoint = Vector2.new(0, 1)
            vitals.Position = UDim2.new(0, margin, 1, -margin)
            vitals.Size = UDim2.fromOffset(500, 156)
            applyScale(vitals, vitalsScale)
        end
        if hotbar then
            hotbar.AnchorPoint = Vector2.new(0.5, 1)
            hotbar.Position = UDim2.new(0.5, 0, 1, -margin)
            hotbar.Size = UDim2.fromOffset(590, 134)
            applyScale(hotbar, hotbarScale)
        end
    end

    if notification then
        local notificationScale = fitScale(
            math.min(base, 1),
            430,
            96,
            math.min(safeW - margin * 2, safeW * 0.88),
            safeH * 0.24,
            0.52
        )
        applyScale(notification, notificationScale)

        if metrics.Portrait then
            notification.AnchorPoint = Vector2.new(0.5, 1)
            local reservedBottom =
                margin
                + 134 * hotbarScale
                + gap
                + 156 * vitalsScale
                + gap
            notification.Position = UDim2.new(
                0.5,
                0,
                1,
                -reservedBottom
            )
        else
            notification.AnchorPoint = Vector2.new(1, 1)
            notification.Position = UDim2.new(1, -margin, 1, -margin)
        end
    end

    if stateBanner then
        local bannerScale = fitScale(
            1,
            500,
            108,
            safeW - margin * 2,
            safeH * 0.30,
            0.55
        )
        stateBanner.AnchorPoint = Vector2.new(0.5, 0.5)
        stateBanner.Position = UDim2.fromScale(0.5, 0.48)
        stateBanner.Size = UDim2.fromOffset(500, 108)
        applyScale(stateBanner, bannerScale)
    end

    if inventoryDrawer then
        local modalScale = fitScale(
            1,
            520,
            290,
            safeW - margin * 2,
            safeH - margin * 2,
            0.55
        )
        inventoryDrawer.AnchorPoint = Vector2.new(0.5, 0.5)
        inventoryDrawer.Position = UDim2.fromScale(0.5, 0.53)
        inventoryDrawer.Size = UDim2.fromOffset(520, 290)
        applyScale(inventoryDrawer, modalScale)

        if metrics.Touch then
            local close = inventoryDrawer:FindFirstChild("Close")
            if close and close:IsA("GuiButton") then
                -- Compensate for parent scaling so the physical close target
                -- remains at least ~44 px.
                local localMinimum = math.ceil(44 / modalScale)
                local size = math.max(34, localMinimum)
                close.Size = UDim2.fromOffset(size, size)
            end
        end
    end

    gui:SetAttribute("ResponsiveDeviceClass", metrics.DeviceClass)
    gui:SetAttribute("ResponsiveBaseScale", base)
    gui:SetAttribute("ResponsiveSafeWidth", math.floor(safeW + 0.5))
    gui:SetAttribute("ResponsiveSafeHeight", math.floor(safeH + 0.5))
    gui:SetAttribute("ResponsiveTopbarMinX", metrics.TopbarRect.Min.X)
    gui:SetAttribute("ResponsiveTopbarMinY", metrics.TopbarRect.Min.Y)
    gui:SetAttribute("ResponsiveTopbarMaxX", metrics.TopbarRect.Max.X)
    gui:SetAttribute("ResponsiveTopbarMaxY", metrics.TopbarRect.Max.Y)
    gui:SetAttribute("ResponsiveTopPolicy", "TopbarSafeAbsoluteV1")
end

local function applyGuidedIntro(gui, metrics)
    local hint = gui:FindFirstChild("ContextHint")
        or gui:FindFirstChildWhichIsA("Frame")
    if hint then
        local topX, _, laneWidth = absoluteTopLane(gui, metrics, 360)
        local width = math.max(
            190,
            math.min(360, laneWidth, metrics.Width - metrics.Margin * 2)
        )
        local y = topContentBottom(metrics, 62) + 4

        hint.AnchorPoint = Vector2.new(0.5, 0)
        hint.Position = UDim2.fromOffset(topX, y)
        hint.Size = UDim2.fromOffset(width, 42)
    end

    local movement = gui:FindFirstChild("MovementHint")
    if movement and movement:IsA("GuiObject") then
        local width = math.max(
            230,
            math.min(286, metrics.Width - metrics.Margin * 2)
        )
        movement.AnchorPoint = Vector2.new(0.5, 1)
        movement.Position = UDim2.new(
            0.5,
            0,
            1,
            -math.max(20, metrics.Margin + 14)
        )
        movement.Size = UDim2.fromOffset(width, 64)

        local scale = movement:FindFirstChild("ResponsiveMovementScale")
        if not scale then
            scale = Instance.new("UIScale")
            scale.Name = "ResponsiveMovementScale"
            scale.Parent = movement
        end
        scale.Scale = metrics.Touch
            and math.clamp(metrics.Shortest / 390, 0.88, 1.04)
            or math.clamp(metrics.Shortest / 900, 0.82, 1.05)
    end

    local attack = gui:FindFirstChild("AttackHint")
    if attack and attack:IsA("GuiObject") then
        local width = math.max(
            220,
            math.min(260, metrics.Width - metrics.Margin * 2)
        )
        attack.AnchorPoint = Vector2.new(0.5, 1)
        attack.Position = UDim2.new(
            0.5,
            0,
            1,
            -math.max(20, metrics.Margin + 14)
        )
        attack.Size = UDim2.fromOffset(width, 58)

        local scale = attack:FindFirstChild("ResponsiveAttackHintScale")
        if not scale then
            scale = Instance.new("UIScale")
            scale.Name = "ResponsiveAttackHintScale"
            scale.Parent = attack
        end
        scale.Scale = math.clamp(metrics.Shortest / 900, 0.82, 1.05)
    end
end

local function applySimpleGuidance(gui, metrics)
    local card = gui:FindFirstChild("ObjectiveCard")
    if not card or not card:IsA("GuiObject") then
        return
    end

    local guide = playerGui:FindFirstChild("DungeonGuidedIntroUI")
    local guideVisible = guide
        and guide:IsA("ScreenGui")
        and guide.Enabled

    local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 350)
    local width = math.max(
        180,
        math.min(350, laneWidth, metrics.Width - metrics.Margin * 2)
    )

    -- This is the PRIMARY top-center gameplay instruction, so it occupies the
    -- real TopbarSafeInsets lane. No custom vertical margin is added.
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.Position = UDim2.fromOffset(topX, topY)
    card.Size = UDim2.fromOffset(width, 62)

    local clearPathProgress = card:FindFirstChild("ClearPathProgress")
    if clearPathProgress then
        local dots = clearPathProgress:FindFirstChild("Dots")
        local count = clearPathProgress:FindFirstChild("Count")

        if dots and dots:IsA("GuiObject") then
            dots.Position = UDim2.fromOffset(
                width < 275 and 48 or 54,
                6
            )
        end

        if count and count:IsA("TextLabel") then
            count.TextSize = width < 275 and 11 or 12
        end
    end

    local firstWaveBattle = card:FindFirstChild("FirstWaveBattle")
    if firstWaveBattle then
        local steps = firstWaveBattle:FindFirstChild("Steps")
        local count = firstWaveBattle:FindFirstChild("Count")

        if steps and steps:IsA("GuiObject") then
            steps.Position = UDim2.fromOffset(
                width < 275 and 44 or 50,
                5
            )
            steps.Size = UDim2.fromOffset(
                width < 275 and 100 or 112,
                12
            )
        end

        if count and count:IsA("TextLabel") then
            count.TextSize = width < 275 and 11 or 12
        end
    end
end

local function applyMobileCombat(gui, metrics)
    local button = gui:FindFirstChild("AttackButton")
    if not button or not button:IsA("GuiButton") then
        return
    end

    local scale = getOrCreateScale(button, "ResponsiveActionScale")
    if scale then
        -- Preserve a large physical action target across phones/tablets.
        scale.Scale = math.clamp(metrics.Shortest / 390, 0.85, 1.15)
    end

    button.AnchorPoint = Vector2.new(1, 1)
    button.Position = UDim2.new(
        1,
        -math.max(14, metrics.Margin),
        1,
        -math.max(18, metrics.Margin + 14)
    )
end

local function applyBeginnerHealth(gui, metrics)
    local card = gui:FindFirstChild("HealthCard")
    if not card or not card:IsA("GuiObject") then
        return
    end

    local width = math.max(
        232,
        math.min(274, metrics.Width - metrics.Margin * 2)
    )

    card.Size = UDim2.fromOffset(width, 68)

    if metrics.Portrait or metrics.Width < 720 then
        local topX = select(1, absoluteTopLane(gui, metrics, 350))
        card.AnchorPoint = Vector2.new(0.5, 0)
        card.Position = UDim2.fromOffset(
            topX,
            topContentBottom(metrics, 62) + 4
        )
    else
        card.AnchorPoint = Vector2.new(0, 0)
        card.Position = UDim2.fromOffset(
            metrics.Margin,
            0
        )
    end

    local scale = card:FindFirstChild("ResponsiveBeginnerHealthScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "ResponsiveBeginnerHealthScale"
        scale.Parent = card
    end

    scale.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.88, 1.04)
        or math.clamp(metrics.Shortest / 900, 0.82, 1.05)
end

local function applyFirstVictoryFeedback(gui, metrics)
    local holder = gui:FindFirstChild("Feedback")
    if not holder or not holder:IsA("GuiObject") then
        return
    end

    local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 520)
    local width = math.max(
        180,
        math.min(520, laneWidth, metrics.Width - metrics.Margin * 2)
    )

    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.fromOffset(topX, topY)
    holder.Size = UDim2.fromOffset(width, 82)

    local responsiveScale = holder:FindFirstChild("ResponsiveVictoryScale")
    if not responsiveScale then
        responsiveScale = Instance.new("UIScale")
        responsiveScale.Name = "ResponsiveVictoryScale"
        responsiveScale.Parent = holder
    end

    responsiveScale.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.90, 1.02)
        or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
end

local function applyFirstRewardPresentation(gui, metrics)
    local holder = gui:FindFirstChild("RewardReveal")
    if not holder or not holder:IsA("GuiObject") then
        return
    end

    local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 470)
    local width = math.max(
        180,
        math.min(470, laneWidth, metrics.Width - metrics.Margin * 2)
    )

    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.fromOffset(topX, topY)
    holder.Size = UDim2.fromOffset(width, 78)

    local responsiveScale = holder:FindFirstChild("ResponsiveRewardRevealScale")
    if not responsiveScale then
        responsiveScale = Instance.new("UIScale")
        responsiveScale.Name = "ResponsiveRewardRevealScale"
        responsiveScale.Parent = holder
    end

    responsiveScale.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.90, 1.02)
        or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
end

local function applyBeginnerCurrency(gui, metrics)
    local reveal = gui:FindFirstChild("CurrencyReveal")
    local chip = gui:FindFirstChild("CurrencyChip")

    if reveal and reveal:IsA("GuiObject") then
        local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 330)
        local width = math.max(
            180,
            math.min(330, laneWidth, metrics.Width - metrics.Margin * 2)
        )
        reveal.AnchorPoint = Vector2.new(0.5, 0)
        reveal.Position = UDim2.fromOffset(topX, topY)
        reveal.Size = UDim2.fromOffset(width, 76)

        local responsive = reveal:FindFirstChild("ResponsiveCurrencyRevealScale")
        if not responsive then
            responsive = Instance.new("UIScale")
            responsive.Name = "ResponsiveCurrencyRevealScale"
            responsive.Parent = reveal
        end

        responsive.Scale = metrics.Touch
            and math.clamp(metrics.Shortest / 390, 0.90, 1.03)
            or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
    end

    if chip and chip:IsA("GuiObject") then
        if metrics.Portrait or metrics.Width < 720 then
            -- Objective lives mostly inside the real top-bar lane. The coin chip
            -- starts immediately below its physical bottom, not 68px below the
            -- already-inset Core UI origin.
            chip.AnchorPoint = Vector2.new(0, 0)
            chip.Position = UDim2.fromOffset(
                metrics.Margin,
                topContentBottom(metrics, 62) + 4
            )
        else
            chip.AnchorPoint = Vector2.new(0, 0)
            chip.Position = UDim2.fromOffset(
                metrics.Margin,
                0
            )
        end

        local responsive = chip:FindFirstChild("ResponsiveCurrencyChipScale")
        if not responsive then
            responsive = Instance.new("UIScale")
            responsive.Name = "ResponsiveCurrencyChipScale"
            responsive.Parent = chip
        end

        responsive.Scale = metrics.Touch
            and math.clamp(metrics.Shortest / 390, 0.90, 1.04)
            or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
    end
end

local function applyBeginnerCompanion(gui, metrics)
    local holder = gui:FindFirstChild("CompanionReveal")
    if not holder or not holder:IsA("GuiObject") then
        return
    end

    local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 390)
    local width = math.max(
        180,
        math.min(390, laneWidth, metrics.Width - metrics.Margin * 2)
    )

    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.fromOffset(topX, topY)
    holder.Size = UDim2.fromOffset(width, 122)

    local responsive = holder:FindFirstChild("ResponsiveCompanionRevealScale")
    if not responsive then
        responsive = Instance.new("UIScale")
        responsive.Name = "ResponsiveCompanionRevealScale"
        responsive.Parent = holder
    end

    responsive.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.88, 1.02)
        or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
end

local function applyBeginnerUpgrade(gui, metrics)
    local panel = gui:FindFirstChild("UpgradePanel")
    local choices = panel and panel:FindFirstChild("Choices")
    if not panel or not panel:IsA("GuiObject") then
        return
    end

    local availableWidth = math.max(280, metrics.Width - metrics.Margin * 2)
    local availableHeight = math.max(360, metrics.Height - metrics.Margin * 2)
    local portrait = metrics.Portrait or metrics.Width < 760

    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.52)

    if portrait then
        local width = math.min(420, availableWidth)
        local height = math.min(570, availableHeight)
        panel.Size = UDim2.fromOffset(width, height)

        if choices and choices:IsA("GuiObject") then
            choices.Position = UDim2.fromOffset(16, 88)
            choices.Size = UDim2.new(1, -32, 1, -132)

            local layout = choices:FindFirstChildWhichIsA("UIListLayout")
            if layout then
                layout.FillDirection = Enum.FillDirection.Vertical
                layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                layout.VerticalAlignment = Enum.VerticalAlignment.Center
                layout.Padding = UDim.new(0, 8)
            end

            for _, child in ipairs(choices:GetChildren()) do
                if child:IsA("TextButton") then
                    child.Size = UDim2.new(1, 0, 0, math.clamp(
                        math.floor((height - 176) / 3),
                        92,
                        122
                    ))
                end
            end
        end
    else
        local width = math.min(900, availableWidth)
        local height = math.min(286, availableHeight)
        panel.Size = UDim2.fromOffset(width, height)

        if choices and choices:IsA("GuiObject") then
            choices.Position = UDim2.fromOffset(20, 91)
            choices.Size = UDim2.new(1, -40, 0, 152)

            local layout = choices:FindFirstChildWhichIsA("UIListLayout")
            if layout then
                layout.FillDirection = Enum.FillDirection.Horizontal
                layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                layout.VerticalAlignment = Enum.VerticalAlignment.Center
                layout.Padding = UDim.new(0, 12)
            end

            local cardWidth = math.floor(
                math.max(210, math.min(272, (width - 64) / 3))
            )
            for _, child in ipairs(choices:GetChildren()) do
                if child:IsA("TextButton") then
                    child.Size = UDim2.fromOffset(cardWidth, 148)
                end
            end
        end
    end

    local responsive = panel:FindFirstChild("ResponsiveUpgradeScale")
    if not responsive then
        responsive = Instance.new("UIScale")
        responsive.Name = "ResponsiveUpgradeScale"
        responsive.Parent = panel
    end

    responsive.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.86, 1.0)
        or math.clamp(metrics.Shortest / 900, 0.82, 1.0)
end

local function applySkyAmbushPresentation(gui, metrics)
    local holder = gui:FindFirstChild("AmbushWarning")
    if not holder or not holder:IsA("GuiObject") then
        return
    end

    local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 430)
    local width = math.max(
        180,
        math.min(430, laneWidth, metrics.Width - metrics.Margin * 2)
    )

    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.fromOffset(topX, topY)
    holder.Size = UDim2.fromOffset(width, 78)

    local responsive = holder:FindFirstChild("ResponsiveSkyAmbushScale")
    if not responsive then
        responsive = Instance.new("UIScale")
        responsive.Name = "ResponsiveSkyAmbushScale"
        responsive.Parent = holder
    end

    responsive.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.90, 1.03)
        or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
end

local function applyRangedThreatPresentation(gui, metrics)
    local holder = gui:FindFirstChild("RangedWarning")
    if not holder or not holder:IsA("GuiObject") then
        return
    end

    local topX, topY, laneWidth = absoluteTopLane(gui, metrics, 440)
    local width = math.max(
        180,
        math.min(440, laneWidth, metrics.Width - metrics.Margin * 2)
    )

    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.fromOffset(topX, topY)
    holder.Size = UDim2.fromOffset(width, 82)

    local responsive = holder:FindFirstChild("ResponsiveRangedThreatScale")
    if not responsive then
        responsive = Instance.new("UIScale")
        responsive.Name = "ResponsiveRangedThreatScale"
        responsive.Parent = holder
    end

    responsive.Scale = metrics.Touch
        and math.clamp(metrics.Shortest / 390, 0.90, 1.03)
        or math.clamp(metrics.Shortest / 900, 0.84, 1.05)
end

local function applySimpleWaypoint(gui, metrics)
    local arrow = gui:FindFirstChild("EdgeArrow")
    if not arrow or not arrow:IsA("GuiObject") then
        return
    end

    local scale = getOrCreateScale(arrow, "ResponsiveWaypointScale")
    if scale then
        scale.Scale = math.clamp(metrics.Shortest / 720, 0.82, 1.08)
    end
end

local KNOWN_GUI = {
    DungeonUnifiedHUD = applyUnifiedHud,
    DungeonGuidedIntroUI = applyGuidedIntro,
    DungeonSimpleGuidance = applySimpleGuidance,
    DungeonMobileCombat = applyMobileCombat,
    DungeonBeginnerHealthHUD = applyBeginnerHealth,
    DungeonFirstVictoryFeedback = applyFirstVictoryFeedback,
    DungeonFirstRewardPresentation = applyFirstRewardPresentation,
    DungeonBeginnerCurrencyHUD = applyBeginnerCurrency,
    DungeonBeginnerCompanionHUD = applyBeginnerCompanion,
    DungeonBeginnerUpgradeHUD = applyBeginnerUpgrade,
    DungeonSkyAmbushPresentation = applySkyAmbushPresentation,
    DungeonRangedThreatPresentation = applyRangedThreatPresentation,
    DungeonSimpleWaypoint = applySimpleWaypoint,
}

local function applyGenericRoot(gui, metrics)
    if gui:GetAttribute("ResponsiveGenericOptOut") == true then
        return
    end

    for _, object in ipairs(gui:GetChildren()) do
        if object:IsA("GuiObject")
            and not isFullscreenRoot(object)
            and object:GetAttribute("ResponsiveUIOptOut") ~= true
        then
            local size = object.Size
            local designW = math.abs(size.X.Offset)
            local designH = math.abs(size.Y.Offset)

            if designW >= 120 or designH >= 70 then
                local scale = fitScale(
                    metrics.BaseScale,
                    designW > 0 and designW or nil,
                    designH > 0 and designH or nil,
                    metrics.Width - metrics.Margin * 2,
                    metrics.Height - metrics.Margin * 2,
                    metrics.Touch and 0.50 or 0.65
                )
                applyScale(object, scale)
            end
        end
    end
end

local function applyAll()
    pendingApply = false

    local metrics = calculateMetrics()
    local signature = table.concat({
        tostring(math.floor(metrics.Width)),
        tostring(math.floor(metrics.Height)),
        metrics.DeviceClass,
        metrics.PreferredTextClass,
    }, ":")

    lastSignature = signature

    for _, child in ipairs(playerGui:GetChildren()) do
        if child:IsA("ScreenGui") then
            setScreenSafeArea(child)

            local known = KNOWN_GUI[child.Name]
            if known then
                known(child, metrics)
            else
                applyGenericRoot(child, metrics)
            end
        end
    end

    player:SetAttribute("DungeonResponsiveUIReady", true)
    player:SetAttribute("DungeonResponsiveUIVersion", VERSION)
    player:SetAttribute("DungeonResponsiveDeviceClass", metrics.DeviceClass)
    player:SetAttribute("DungeonResponsiveSafeWidth", math.floor(metrics.Width + 0.5))
    player:SetAttribute("DungeonResponsiveSafeHeight", math.floor(metrics.Height + 0.5))
    player:SetAttribute("DungeonResponsiveBaseScale", metrics.BaseScale)
    player:SetAttribute("DungeonResponsivePreferredTextSize", metrics.PreferredTextClass)
    player:SetAttribute("DungeonResponsivePortrait", metrics.Portrait)
end

local function scheduleApply()
    if pendingApply then
        return
    end

    pendingApply = true
    task.defer(function()
        -- One extra scheduler step lets GUI scripts finish their own
        -- synchronous viewport callback before this controller normalizes them.
        task.defer(applyAll)
    end)
end

local function bindCamera()
    disconnectManaged()

    local camera = Workspace.CurrentCamera
    if camera then
        table.insert(
            managedConnections,
            camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleApply)
        )
    end

    table.insert(
        managedConnections,
        GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(scheduleApply)
    )
    table.insert(
        managedConnections,
        GuiService:GetPropertyChangedSignal("ViewportDisplaySize"):Connect(scheduleApply)
    )
    table.insert(
        managedConnections,
        GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(scheduleApply)
    )

    scheduleApply()
end

playerGui.ChildAdded:Connect(function(child)
    if child:IsA("ScreenGui") then
        scheduleApply()
        child.DescendantAdded:Connect(function()
            scheduleApply()
        end)
    end
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

-- Low-frequency guard for scripts that mutate fixed pixel sizes after their
-- initial creation. This is intentionally 4 Hz, not per-frame.
local elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
    elapsed += deltaTime
    if elapsed < 0.25 then
        return
    end
    elapsed = 0

    local metrics = calculateMetrics()
    local signature = table.concat({
        tostring(math.floor(metrics.Width)),
        tostring(math.floor(metrics.Height)),
        metrics.DeviceClass,
        metrics.PreferredTextClass,
    }, ":")

    if signature ~= lastSignature then
        scheduleApply()
        return
    end

    -- Keep only the known critical HUDs normalized.
    for name, callback in pairs(KNOWN_GUI) do
        local gui = playerGui:FindFirstChild(name)
        if gui and gui:IsA("ScreenGui") then
            callback(gui, metrics)
        end
    end
end)
