--[[
    Infinity Islands — Rebuild Part 38
    First run-upgrade presentation.

    Closes the first complete gameplay loop:
        fight -> objective -> reward -> become stronger

    Server remains authoritative:
    - RunUpgradeService chooses the 3 deterministic options.
    - Client only displays payload and sends ChooseRunUpgrade.
    - server auto-pick remains the softlock fallback.

    The first choice waits until reward/currency/companion presentations finish.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "FirstRunUpgradeChoiceV1"
local ROUND_INDEX = 1
local CONFIRM_HOLD = 0.82

local shared = ReplicatedStorage:WaitForChild("Shared", 15)
local remotes = shared and shared:WaitForChild("Remotes", 15)
local dungeonRemotes = remotes and remotes:WaitForChild("Dungeon", 15)
local upgradeRemote = dungeonRemotes
    and dungeonRemotes:WaitForChild("RunUpgradeState", 15)

if not upgradeRemote or not upgradeRemote:IsA("RemoteEvent") then
    player:SetAttribute("DungeonBeginnerUpgradeHUDReady", false)
    player:SetAttribute("DungeonBeginnerUpgradeHUDError", "RunUpgradeStateMissing")
    return
end

local existing = playerGui:FindFirstChild("DungeonBeginnerUpgradeHUD")
if existing then
    existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonBeginnerUpgradeHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 98
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(4, 9, 15)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Visible = false
dim.ZIndex = 10
dim.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "UpgradePanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromOffset(900, 286)
panel.BackgroundColor3 = Color3.fromRGB(8, 21, 34)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 20
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 20)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(91, 205, 236)
panelStroke.Transparency = 1
panelStroke.Thickness = 1.2
panelStroke.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Name = "UpgradePanelScale"
panelScale.Scale = 0.94
panelScale.Parent = panel

local eyebrow = Instance.new("TextLabel")
eyebrow.Name = "Eyebrow"
eyebrow.Position = UDim2.fromOffset(22, 12)
eyebrow.Size = UDim2.new(1, -44, 0, 16)
eyebrow.BackgroundTransparency = 1
eyebrow.Text = "SUA PRIMEIRA MELHORIA"
eyebrow.TextColor3 = Color3.fromRGB(115, 216, 244)
eyebrow.TextTransparency = 1
eyebrow.Font = Enum.Font.GothamBold
eyebrow.TextSize = 10
eyebrow.TextXAlignment = Enum.TextXAlignment.Center
eyebrow.ZIndex = 22
eyebrow.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(22, 29)
title.Size = UDim2.new(1, -44, 0, 32)
title.BackgroundTransparency = 1
title.Text = "ESCOLHA UM UPGRADE"
title.TextColor3 = Color3.fromRGB(246, 250, 253)
title.TextTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Center
title.ZIndex = 22
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Position = UDim2.fromOffset(22, 61)
subtitle.Size = UDim2.new(1, -44, 0, 19)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Fica ativo durante esta expedição."
subtitle.TextColor3 = Color3.fromRGB(170, 190, 204)
subtitle.TextTransparency = 1
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 11
subtitle.TextXAlignment = Enum.TextXAlignment.Center
subtitle.ZIndex = 22
subtitle.Parent = panel

local cards = Instance.new("Frame")
cards.Name = "Choices"
cards.Position = UDim2.fromOffset(20, 91)
cards.Size = UDim2.new(1, -40, 0, 152)
cards.BackgroundTransparency = 1
cards.ZIndex = 21
cards.Parent = panel

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.FillDirection = Enum.FillDirection.Horizontal
cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cardsLayout.Padding = UDim.new(0, 12)
cardsLayout.Parent = cards

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.AnchorPoint = Vector2.new(0.5, 1)
timerLabel.Position = UDim2.new(0.5, 0, 1, -13)
timerLabel.Size = UDim2.new(1, -40, 0, 20)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = ""
timerLabel.TextColor3 = Color3.fromRGB(135, 159, 176)
timerLabel.TextTransparency = 1
timerLabel.Font = Enum.Font.GothamMedium
timerLabel.TextSize = 10
timerLabel.TextXAlignment = Enum.TextXAlignment.Center
timerLabel.ZIndex = 22
timerLabel.Parent = panel

local choiceRecords = {}
local pendingPayload
local resolvedPayload
local showing = false
local selecting = false
local completed = false
local presentationSerial = 0
local timerConnection

local function priorPresentationComplete()
    if player:GetAttribute("GuidedIntroActive") ~= true then
        return true
    end

    if player:GetAttribute("DungeonFirstRewardPresentationActive") == true then
        return false
    end
    if player:GetAttribute("DungeonBeginnerCurrencyPresentationActive") == true then
        return false
    end
    if player:GetAttribute("DungeonBeginnerCurrencyChipVisible") == true then
        return false
    end
    if player:GetAttribute("DungeonBeginnerCompanionPresentationActive") == true then
        return false
    end

    local companionGranted =
        player:GetAttribute("DungeonFirstRewardCompanionGranted") == true
    local companionDuplicate =
        player:GetAttribute("DungeonFirstRewardCompanionDuplicate") == true

    if companionGranted then
        return player:GetAttribute("GuidedIntroCompanionIntroduced") == true
            and tostring(
                player:GetAttribute("DungeonBeginnerCompanionPresentationStage") or ""
            ) == "Complete"
    end

    if companionDuplicate then
        return player:GetAttribute("GuidedIntroCompanionIntroductionSkipped") == "Duplicate"
    end

    -- If no companion result was produced for some valid future content variant,
    -- currency completion is sufficient; do not softlock the upgrade UI.
    return player:GetAttribute("GuidedIntroCurrencyIntroduced") == true
end

local function stopTimer()
    if timerConnection then
        timerConnection:Disconnect()
        timerConnection = nil
    end
end

local function clearChoices()
    for _, record in ipairs(choiceRecords) do
        if record.Button and record.Button.Parent then
            record.Button:Destroy()
        end
    end
    table.clear(choiceRecords)
end

local function setPanelVisible(visible)
    presentationSerial += 1
    local serial = presentationSerial

    if visible then
        dim.Visible = true
        panel.Visible = true
        dim.BackgroundTransparency = 1
        panel.BackgroundTransparency = 1
        panelStroke.Transparency = 1
        panelScale.Scale = 0.94

        for _, label in ipairs({ eyebrow, title, subtitle, timerLabel }) do
            label.TextTransparency = 1
        end

        TweenService:Create(
            dim,
            TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.48 }
        ):Play()
        TweenService:Create(
            panel,
            TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.05 }
        ):Play()
        TweenService:Create(
            panelStroke,
            TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Transparency = 0.26 }
        ):Play()
        TweenService:Create(
            panelScale,
            TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()

        for _, label in ipairs({ eyebrow, title, subtitle, timerLabel }) do
            TweenService:Create(
                label,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = 0 }
            ):Play()
        end
    else
        stopTimer()

        TweenService:Create(
            dim,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            panel,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(
            panelStroke,
            TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }
        ):Play()
        TweenService:Create(
            panelScale,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0.96 }
        ):Play()

        task.delay(0.17, function()
            if serial == presentationSerial and not showing then
                dim.Visible = false
                panel.Visible = false
            end
        end)
    end
end

local function sendChoice(choice)
    if selecting or completed or type(choice) ~= "table" then
        return
    end

    selecting = true
    player:SetAttribute("DungeonBeginnerUpgradePresentationStage", "Selecting")
    player:SetAttribute("DungeonBeginnerUpgradeRequestedId", choice.Id)
    player:SetAttribute(
        "DungeonBeginnerUpgradeRequestedAt",
        Workspace:GetServerTimeNow()
    )

    for _, record in ipairs(choiceRecords) do
        record.Button.Active = false
        record.Button.AutoButtonColor = false
        record.Button.BackgroundTransparency =
            record.Choice.Id == choice.Id and 0.05 or 0.34
    end

    upgradeRemote:FireServer({
        Action = "ChooseRunUpgrade",
        RoundIndex = ROUND_INDEX,
        UpgradeId = choice.Id,
    })
end

local function makeChoiceCard(choice)
    local button = Instance.new("TextButton")
    button.Name = "Choice_" .. tostring(choice.Id or "Unknown")
    button.Size = UDim2.fromOffset(272, 148)
    button.BackgroundColor3 = Color3.fromRGB(14, 35, 52)
    button.BackgroundTransparency = 0.11
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = true
    button.ZIndex = 23
    button.Parent = cards

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(94, 193, 222)
    stroke.Transparency = 0.40
    stroke.Thickness = 1
    stroke.Parent = button

    local glyph = Instance.new("TextLabel")
    glyph.Name = "Glyph"
    glyph.Position = UDim2.fromOffset(12, 10)
    glyph.Size = UDim2.fromOffset(44, 42)
    glyph.BackgroundColor3 = Color3.fromRGB(19, 54, 75)
    glyph.BackgroundTransparency = 0.12
    glyph.BorderSizePixel = 0
    glyph.Text = tostring(choice.Glyph or "✦")
    glyph.TextColor3 = Color3.fromRGB(141, 228, 250)
    glyph.Font = Enum.Font.GothamBlack
    glyph.TextSize = 23
    glyph.ZIndex = 24
    glyph.Parent = button
    Instance.new("UICorner", glyph).CornerRadius = UDim.new(0, 11)

    local cardTitle = Instance.new("TextLabel")
    cardTitle.Name = "Title"
    cardTitle.Position = UDim2.fromOffset(65, 9)
    cardTitle.Size = UDim2.new(1, -77, 0, 38)
    cardTitle.BackgroundTransparency = 1
    cardTitle.Text = string.upper(tostring(choice.Title or "UPGRADE"))
    cardTitle.TextColor3 = Color3.fromRGB(244, 250, 253)
    cardTitle.Font = Enum.Font.GothamBold
    cardTitle.TextSize = 14
    cardTitle.TextWrapped = true
    cardTitle.TextXAlignment = Enum.TextXAlignment.Left
    cardTitle.TextYAlignment = Enum.TextYAlignment.Center
    cardTitle.ZIndex = 24
    cardTitle.Parent = button

    local description = Instance.new("TextLabel")
    description.Name = "Description"
    description.Position = UDim2.fromOffset(12, 59)
    description.Size = UDim2.new(1, -24, 0, 47)
    description.BackgroundTransparency = 1
    description.Text = tostring(choice.Description or "")
    description.TextColor3 = Color3.fromRGB(179, 199, 212)
    description.Font = Enum.Font.GothamMedium
    description.TextSize = 11
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.TextYAlignment = Enum.TextYAlignment.Top
    description.ZIndex = 24
    description.Parent = button

    local choose = Instance.new("TextLabel")
    choose.Name = "Choose"
    choose.AnchorPoint = Vector2.new(0, 1)
    choose.Position = UDim2.new(0, 12, 1, -9)
    choose.Size = UDim2.new(1, -24, 0, 24)
    choose.BackgroundColor3 = Color3.fromRGB(28, 78, 102)
    choose.BackgroundTransparency = 0.10
    choose.BorderSizePixel = 0
    choose.Text = "ESCOLHER"
    choose.TextColor3 = Color3.fromRGB(198, 241, 252)
    choose.Font = Enum.Font.GothamBold
    choose.TextSize = 10
    choose.ZIndex = 24
    choose.Parent = button
    Instance.new("UICorner", choose).CornerRadius = UDim.new(0, 8)

    button.Activated:Connect(function()
        sendChoice(choice)
    end)

    table.insert(choiceRecords, {
        Choice = choice,
        Button = button,
        Stroke = stroke,
    })
end

local function startTimer(autoPickAt)
    stopTimer()

    if not tonumber(autoPickAt) then
        timerLabel.Text = "Escolha uma melhoria."
        return
    end

    timerConnection = RunService.Heartbeat:Connect(function()
        local remaining = math.max(
            0,
            tonumber(autoPickAt) - Workspace:GetServerTimeNow()
        )

        if remaining <= 0 then
            timerLabel.Text = "Escolhendo automaticamente..."
            stopTimer()
            return
        end

        timerLabel.Text = string.format(
            "Escolha automática em %ds",
            math.max(1, math.ceil(remaining))
        )
    end)
end

local function showChoices(payload)
    if showing or completed or type(payload) ~= "table" then
        return
    end

    local choices = type(payload.Choices) == "table" and payload.Choices or {}
    if #choices == 0 then
        return
    end

    showing = true
    selecting = false
    clearChoices()

    for _, choice in ipairs(choices) do
        makeChoiceCard(choice)
    end

    player:SetAttribute("DungeonBeginnerUpgradePresentationActive", true)
    player:SetAttribute("DungeonBeginnerUpgradePresentationStage", "Choosing")
    player:SetAttribute("GuidedIntroPresentationStage", "UpgradeChoice")
    player:SetAttribute("DungeonBeginnerUpgradeChoiceCount", #choices)
    player:SetAttribute(
        "DungeonBeginnerUpgradePresentationStartedAt",
        Workspace:GetServerTimeNow()
    )

    setPanelVisible(true)
    startTimer(payload.AutoPickAt)
end

local function choiceTitle(payload)
    local selectedId = tostring(payload.SelectedUpgradeId or "")
    local sourceChoices = pendingPayload
        and type(pendingPayload.Choices) == "table"
        and pendingPayload.Choices
        or {}

    for _, choice in ipairs(sourceChoices) do
        if tostring(choice.Id or "") == selectedId then
            return tostring(choice.Title or selectedId), tostring(choice.Glyph or "✦")
        end
    end

    return selectedId ~= "" and selectedId or "Upgrade", "✦"
end

local function showResolved(payload)
    if completed then
        return
    end

    resolvedPayload = payload

    if not priorPresentationComplete() then
        return
    end

    if not showing then
        showing = true
        player:SetAttribute("DungeonBeginnerUpgradePresentationActive", true)
        setPanelVisible(true)
    end

    selecting = true
    stopTimer()

    local selectedTitle, selectedGlyph = choiceTitle(payload)
    eyebrow.Text = payload.Automatic == true
        and "ESCOLHA AUTOMÁTICA"
        or "ESCOLHA FEITA"
    title.Text = "UPGRADE ATIVO"
    subtitle.Text = string.format("%s  %s", selectedGlyph, selectedTitle)
    timerLabel.Text = "Você ficou mais forte nesta expedição."

    cards.Visible = false

    player:SetAttribute("DungeonBeginnerUpgradePresentationStage", "Confirmed")
    player:SetAttribute("GuidedIntroUpgradeIntroduced", true)
    player:SetAttribute("GuidedIntroUpgradeSelectedId", payload.SelectedUpgradeId)
    player:SetAttribute("GuidedIntroUpgradeAutomatic", payload.Automatic == true)
    player:SetAttribute(
        "GuidedIntroUpgradeIntroducedAt",
        Workspace:GetServerTimeNow()
    )

    task.delay(CONFIRM_HOLD, function()
        if completed then
            return
        end

        completed = true
        showing = false
        setPanelVisible(false)

        player:SetAttribute("DungeonBeginnerUpgradePresentationStage", "Complete")
        player:SetAttribute("DungeonBeginnerUpgradePresentationActive", false)
        player:SetAttribute("GuidedIntroCoreLoopCompleted", true)
        player:SetAttribute(
            "GuidedIntroCoreLoopCompletedAt",
            Workspace:GetServerTimeNow()
        )
        player:SetAttribute("GuidedIntroPresentationStage", "CoreLoopLearned")
    end)
end

local function evaluate()
    if completed then
        return
    end

    if resolvedPayload then
        showResolved(resolvedPayload)
        return
    end

    if pendingPayload and priorPresentationComplete() then
        showChoices(pendingPayload)
    end
end

upgradeRemote.OnClientEvent:Connect(function(payload)
    if type(payload) ~= "table"
        or math.floor(tonumber(payload.RoundIndex) or 0) ~= ROUND_INDEX
    then
        return
    end

    if payload.Action == "RunUpgradeChoiceOffered"
        and payload.Resolved ~= true
    then
        pendingPayload = payload
        player:SetAttribute("DungeonBeginnerUpgradeOfferReceived", true)
        player:SetAttribute(
            "DungeonBeginnerUpgradeOfferReceivedAt",
            Workspace:GetServerTimeNow()
        )
        evaluate()
    elseif payload.Action == "RunUpgradeChoiceResolved"
        or payload.Resolved == true
    then
        resolvedPayload = payload
        evaluate()
    end
end)

for _, attributeName in ipairs({
    "DungeonFirstRewardPresentationActive",
    "DungeonBeginnerCurrencyPresentationActive",
    "DungeonBeginnerCurrencyChipVisible",
    "DungeonBeginnerCompanionPresentationActive",
    "DungeonBeginnerCompanionPresentationStage",
    "GuidedIntroCompanionIntroduced",
    "GuidedIntroCompanionIntroductionSkipped",
}) do
    player:GetAttributeChangedSignal(attributeName):Connect(evaluate)
end

player:SetAttribute("DungeonBeginnerUpgradeHUDReady", true)
player:SetAttribute("DungeonBeginnerUpgradeHUDVersion", VERSION)
player:SetAttribute("DungeonBeginnerUpgradePresentationActive", false)
player:SetAttribute("DungeonBeginnerUpgradePresentationStage", "Waiting")
