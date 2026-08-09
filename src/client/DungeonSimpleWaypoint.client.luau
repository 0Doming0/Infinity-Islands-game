--[[
    Infinity Islands — Rebuild Part 14
    Simple contextual orientation.

    Rule:
    exactly ONE guidance target at a time.

    Priority:
    1. Active objective target.
    2. Required Core Chest.
    3. Current exit after progression unlock.
    4. Boss route exit.

    This script does NOT decide progression.
    It only reads authoritative Workspace state.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("DungeonSimpleWaypoint")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonSimpleWaypoint"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)
gui.DisplayOrder = 75
gui.Parent = playerGui

local arrow = Instance.new("Frame")
arrow.Name = "EdgeArrow"
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Size = UDim2.fromOffset(62, 62)
arrow.BackgroundColor3 = Color3.fromRGB(16, 24, 34)
arrow.BackgroundTransparency = 0.12
arrow.BorderSizePixel = 0
arrow.Visible = false
arrow.Parent = gui
Instance.new("UICorner", arrow).CornerRadius = UDim.new(1, 0)

local arrowStroke = Instance.new("UIStroke")
arrowStroke.Thickness = 1.5
arrowStroke.Transparency = 0.12
arrowStroke.Color = Color3.fromRGB(116, 220, 255)
arrowStroke.Parent = arrow

local arrowGlyph = Instance.new("TextLabel")
arrowGlyph.Name = "Glyph"
arrowGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
arrowGlyph.Position = UDim2.fromScale(0.5, 0.42)
arrowGlyph.Size = UDim2.fromOffset(34, 34)
arrowGlyph.BackgroundTransparency = 1
arrowGlyph.Text = "▲"
arrowGlyph.Font = Enum.Font.GothamBold
arrowGlyph.TextSize = 28
arrowGlyph.TextColor3 = Color3.fromRGB(245, 250, 255)
arrowGlyph.Parent = arrow

local arrowDistance = Instance.new("TextLabel")
arrowDistance.Name = "Distance"
arrowDistance.AnchorPoint = Vector2.new(0.5, 1)
arrowDistance.Position = UDim2.new(0.5, 0, 1, -3)
arrowDistance.Size = UDim2.new(1, -8, 0, 16)
arrowDistance.BackgroundTransparency = 1
arrowDistance.Text = ""
arrowDistance.Font = Enum.Font.GothamMedium
arrowDistance.TextSize = 10
arrowDistance.TextColor3 = Color3.fromRGB(185, 211, 229)
arrowDistance.Parent = arrow

local localAnchor = Instance.new("Part")
localAnchor.Name = "LocalDungeonGuidanceAnchor"
localAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
localAnchor.Anchored = true
localAnchor.CanCollide = false
localAnchor.CanTouch = false
localAnchor.CanQuery = false
localAnchor.Transparency = 1
localAnchor.Parent = Workspace

local billboard = Instance.new("BillboardGui")
billboard.Name = "DungeonSimpleWaypointBillboard"
billboard.Adornee = localAnchor
billboard.Size = UDim2.fromOffset(176, 44)
billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
billboard.AlwaysOnTop = true
billboard.MaxDistance = 150
billboard.Enabled = false
billboard.Parent = gui

local worldLabel = Instance.new("TextLabel")
worldLabel.Size = UDim2.fromScale(1, 1)
worldLabel.BackgroundColor3 = Color3.fromRGB(16, 24, 34)
worldLabel.BackgroundTransparency = 0.18
worldLabel.BorderSizePixel = 0
worldLabel.Text = ""
worldLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
worldLabel.Font = Enum.Font.GothamBold
worldLabel.TextSize = 12
worldLabel.TextWrapped = true
worldLabel.Parent = billboard
Instance.new("UICorner", worldLabel).CornerRadius = UDim.new(0, 9)

local worldStroke = Instance.new("UIStroke")
worldStroke.Thickness = 1.2
worldStroke.Transparency = 0.18
worldStroke.Color = Color3.fromRGB(116, 220, 255)
worldStroke.Parent = worldLabel

local mode = "None"
local targetInstance
local fallbackPosition
local guidanceText = ""
local currentColor = Color3.fromRGB(116, 220, 255)
local nextResolveAt = 0

local function modelFor(instance)
    if not instance then
        return nil
    end
    if instance:IsA("Model") then
        return instance
    end
    return instance:FindFirstAncestorOfClass("Model")
end

local function targetPosition(instance)
    if not instance or not instance.Parent then
        return nil
    end
    if instance:IsA("BasePart") then
        return instance.Position
    elseif instance:IsA("Model") then
        local root = instance:FindFirstChild("HumanoidRootPart", true) or instance.PrimaryPart
        if root and root:IsA("BasePart") then
            return root.Position
        end
        return instance:GetPivot().Position
    end
    return nil
end

local function livingObjectiveModel(model)
    if not model or not model.Parent then
        return false
    end
    if model:GetAttribute("ObjectiveTargetCompleted") == true then
        return false
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end
    return true
end

local function playerRoot()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function nearest(candidates)
    local root = playerRoot()
    local best
    local bestDistance = math.huge

    for _, candidate in ipairs(candidates) do
        local position = targetPosition(candidate)
        if position then
            local distance = root and (position - root.Position).Magnitude or 0
            if distance < bestDistance then
                best = candidate
                bestDistance = distance
            end
        end
    end
    return best
end

local function collectObjectiveCandidates(objectiveId, islandIndex)
    local result = {}
    local seen = {}

    local function consider(instance)
        local model = modelFor(instance)
        if not model or seen[model] then
            return
        end
        seen[model] = true

        if tostring(model:GetAttribute("ObjectiveId") or "") ~= objectiveId then
            return
        end
        if math.floor(tonumber(model:GetAttribute("GlobalIslandIndex")) or 0) ~= islandIndex then
            return
        end
        if not livingObjectiveModel(model) then
            return
        end
        table.insert(result, model)
    end

    for _, instance in ipairs(CollectionService:GetTagged("DungeonObjectiveTarget")) do
        consider(instance)
    end
    for _, instance in ipairs(CollectionService:GetTagged("CombatTarget")) do
        consider(instance)
    end

    return result
end

local function findCoreChest(roundIndex)
    local candidates = {}
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Model")
            and descendant:GetAttribute("RewardChestRole") == "Core"
            and math.floor(tonumber(descendant:GetAttribute("RoundIndex")) or 0) == roundIndex
        then
            table.insert(candidates, descendant)
        end
    end
    return nearest(candidates)
end

local function selectObjectiveTarget(objectiveId, islandIndex)
    local candidates = collectObjectiveCandidates(objectiveId, islandIndex)

    if objectiveId == "BreakTheGuard" then
        local wardsRemaining = math.max(
            0,
            math.floor(tonumber(Workspace:GetAttribute("DungeonGuardWardsRemaining")) or 0)
        )
        if wardsRemaining > 0 then
            local wards = {}
            for _, model in ipairs(candidates) do
                if model:GetAttribute("ObjectiveActorType") == "GuardWard" then
                    table.insert(wards, model)
                end
            end
            if #wards > 0 then
                return nearest(wards), "QUEBRE O CRISTAL", Color3.fromRGB(91, 169, 255)
            end
        end
    end

    if objectiveId == "HoldTheBeacon" then
        for _, model in ipairs(candidates) do
            if model:GetAttribute("ObjectiveActorType") == "Beacon" then
                return model, "FAROL", Color3.fromRGB(143, 103, 255)
            end
        end
    elseif objectiveId == "BreakTheNests" or objectiveId == "NestCluster" then
        local nests = {}
        for _, model in ipairs(candidates) do
            if model:GetAttribute("ObjectiveActorType") == "Nest" then
                table.insert(nests, model)
            end
        end
        if #nests > 0 then
            return nearest(nests), "DESTRUA O NINHO", Color3.fromRGB(193, 139, 255)
        end
    end

    local candidate = nearest(candidates)
    if candidate then
        if objectiveId == "EliteHunt" then
            return candidate, "ELITE", Color3.fromRGB(255, 196, 91)
        elseif objectiveId == "RangedThreat" then
            return candidate, "ATIRADOR", Color3.fromRGB(108, 180, 255)
        elseif objectiveId == "BreakTheGuard" then
            return candidate, "GUARD", Color3.fromRGB(188, 179, 255)
        end
        return candidate, "OBJETIVO", Color3.fromRGB(116, 220, 255)
    end

    return nil
end

local function publishedFallback()
    local value = Workspace:GetAttribute("DungeonObjectiveWaypointPosition")
    return typeof(value) == "Vector3" and value or nil
end

local function resolve()
    local state = tostring(Workspace:GetAttribute("DungeonProgressionState") or "")

    local landingState = tostring(
        Workspace:GetAttribute("DungeonSkyAmbushLandingState") or ""
    )
    local landedAndWaitingForAmbush =
        (landingState == "Waiting"
            or landingState == "AllLanded"
            or landingState == "Timeout")
        and player:GetAttribute("DungeonSkyAmbushLanded") == true

    local serverAmbushWarning =
        tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "SkyAmbush"
        and tostring(Workspace:GetAttribute("DungeonEncounterWaveState") or "") == "AmbushWarning"

    local serverRangedWarning =
        tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "RangedThreat"
        and tostring(Workspace:GetAttribute("DungeonEncounterWaveState") or "") == "RangedWarning"

    if player:GetAttribute("DungeonFirstRewardPresentationActive") == true
        or player:GetAttribute("DungeonBeginnerCurrencyPresentationActive") == true
        or player:GetAttribute("DungeonBeginnerCompanionPresentationActive") == true
        or player:GetAttribute("DungeonBeginnerUpgradePresentationActive") == true
        or player:GetAttribute("DungeonSkyAmbushPresentationActive") == true
        or player:GetAttribute("DungeonRangedThreatPresentationActive") == true
        or landedAndWaitingForAmbush
        or serverAmbushWarning
        or serverRangedWarning
    then
        mode = "None"
        targetInstance = nil
        fallbackPosition = nil
        guidanceText = ""
        player:SetAttribute("DungeonGuidanceMode", mode)
        player:SetAttribute("DungeonGuidanceTargetName", nil)
        return
    end
    local objectiveId = tostring(Workspace:GetAttribute("DungeonObjectiveId") or "")
    local islandIndex = math.floor(tonumber(
        Workspace:GetAttribute("DungeonCurrentObjectiveIsland")
    ) or 0)
    local rewardRound = math.floor(tonumber(
        Workspace:GetAttribute("DungeonRewardPendingRound")
    ) or 0)

    mode = "None"
    targetInstance = nil
    fallbackPosition = nil
    guidanceText = ""
    currentColor = Color3.fromRGB(116, 220, 255)

    if state == "ObjectiveActive" and objectiveId ~= "" and islandIndex > 0 then
        local target, text, color = selectObjectiveTarget(objectiveId, islandIndex)
        targetInstance = target
        fallbackPosition = publishedFallback()
        guidanceText = text or "OBJETIVO"
        currentColor = color or currentColor
        mode = "Objective"

    elseif state == "RewardPending" and rewardRound > 0 then
        targetInstance = findCoreChest(rewardRound)
        fallbackPosition = publishedFallback()
        guidanceText = "CORE CHEST"
        currentColor = rewardRound == 3
            and Color3.fromRGB(255, 218, 103)
            or Color3.fromRGB(188, 179, 255)
        mode = "Reward"

    elseif state == "TravelUnlocked" then
        fallbackPosition = publishedFallback()
        guidanceText = "PRÓXIMA ILHA"
        currentColor = Color3.fromRGB(99, 235, 160)
        mode = "Exit"

    elseif state == "BossRouteUnlocked" then
        fallbackPosition = publishedFallback()
        guidanceText = "CAMINHO DO BOSS"
        currentColor = Color3.fromRGB(255, 218, 103)
        mode = "BossRoute"
    end

    player:SetAttribute("DungeonGuidanceMode", mode)
    player:SetAttribute(
        "DungeonGuidanceTargetName",
        targetInstance and targetInstance.Name or nil
    )
end

local function resolvedPosition()
    return targetPosition(targetInstance) or fallbackPosition
end

local function setVisible(visible)
    billboard.Enabled = visible
    if not visible then
        arrow.Visible = false
    end
end

local function render()
    local camera = Workspace.CurrentCamera
    if not camera then
        setVisible(false)
        return
    end

    local position = resolvedPosition()
    local root = playerRoot()
    if mode == "None" or not position or not root then
        setVisible(false)
        player:SetAttribute("DungeonGuidanceDistance", nil)
        return
    end

    local distance = (position - root.Position).Magnitude
    player:SetAttribute("DungeonGuidanceDistance", math.floor(distance + 0.5))

    if distance <= 7 then
        setVisible(false)
        return
    end

    localAnchor.Position = position
    billboard.Enabled = true
    worldLabel.Text = string.format("%s\n%d studs", guidanceText, math.floor(distance + 0.5))
    worldStroke.Color = currentColor
    arrowStroke.Color = currentColor

    local viewportPoint, onScreen = camera:WorldToViewportPoint(position)
    local physicalViewport = camera.ViewportSize
    local insetTopLeft, insetBottomRight = Vector2.zero, Vector2.zero

    pcall(function()
        insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
    end)

    local viewport = Vector2.new(
        math.max(1, physicalViewport.X - insetTopLeft.X - insetBottomRight.X),
        math.max(1, physicalViewport.Y - insetTopLeft.Y - insetBottomRight.Y)
    )
    local localPoint = Vector2.new(
        viewportPoint.X - insetTopLeft.X,
        viewportPoint.Y - insetTopLeft.Y
    )

    local shortSide = math.min(viewport.X, viewport.Y)
    local edgeX = math.clamp(math.floor(shortSide * 0.09 + 0.5), 42, 70)
    local edgeTop = math.clamp(math.floor(shortSide * 0.12 + 0.5), 50, 88)
    local edgeBottom = math.clamp(math.floor(shortSide * 0.10 + 0.5), 44, 76)

    local safeX = math.max(edgeX, math.min(viewport.X - edgeX, localPoint.X))
    local safeY = math.max(edgeTop, math.min(viewport.Y - edgeBottom, localPoint.Y))

    local comfortablyVisible = onScreen
        and viewportPoint.Z > 0
        and localPoint.X > edgeX
        and localPoint.X < viewport.X - edgeX
        and localPoint.Y > edgeTop
        and localPoint.Y < viewport.Y - edgeBottom

    arrow.Visible = not comfortablyVisible
    if not arrow.Visible then
        return
    end

    if viewportPoint.Z <= 0 then
        safeX = viewport.X - safeX
        safeY = viewport.Y - safeY
    end

    arrow.Position = UDim2.fromOffset(safeX, safeY)
    arrowDistance.Text = string.format("%dm", math.max(1, math.floor(distance / 3.57)))

    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local direction = Vector2.new(safeX, safeY) - center
    if direction.Magnitude > 0.01 then
        arrowGlyph.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
    end
end

for _, attribute in ipairs({
    "DungeonProgressionState",
    "DungeonSkyAmbushLandingState",
    "DungeonObjectiveId",
    "DungeonEncounterWaveState",
    "DungeonCurrentObjectiveIsland",
    "DungeonObjectiveWaypointPosition",
    "DungeonObjectiveWaypointSerial",
    "DungeonRewardPendingRound",
    "DungeonGuardWardsRemaining",
    "DungeonGuardPhase",
}) do
    Workspace:GetAttributeChangedSignal(attribute):Connect(function()
        nextResolveAt = 0
    end)
end

CollectionService:GetInstanceAddedSignal("DungeonObjectiveTarget"):Connect(function()
    nextResolveAt = 0
end)
CollectionService:GetInstanceRemovedSignal("DungeonObjectiveTarget"):Connect(function()
    nextResolveAt = 0
end)
CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function()
    nextResolveAt = 0
end)
CollectionService:GetInstanceRemovedSignal("CombatTarget"):Connect(function()
    nextResolveAt = 0
end)

RunService.RenderStepped:Connect(function()
    local currentTime = os.clock()
    if currentTime >= nextResolveAt then
        nextResolveAt = currentTime + 0.18
        resolve()
    end
    render()
end)

player:SetAttribute("DungeonSimpleWaypointReady", true)
player:SetAttribute("DungeonSimpleWaypointVersion", "SingleTargetV1")
Workspace:SetAttribute("DungeonSimpleWaypointReady", true)
Workspace:SetAttribute("DungeonGuidancePolicy", "OneTargetAtATimeV1")

player:GetAttributeChangedSignal("DungeonFirstRewardPresentationActive"):Connect(resolve)
player:GetAttributeChangedSignal("DungeonBeginnerCurrencyPresentationActive"):Connect(resolve)
player:GetAttributeChangedSignal("DungeonBeginnerCompanionPresentationActive"):Connect(resolve)
player:GetAttributeChangedSignal("DungeonBeginnerUpgradePresentationActive"):Connect(resolve)
player:GetAttributeChangedSignal("DungeonSkyAmbushPresentationActive"):Connect(resolve)
player:GetAttributeChangedSignal("DungeonRangedThreatPresentationActive"):Connect(resolve)
player:GetAttributeChangedSignal("DungeonSkyAmbushLanded"):Connect(resolve)

resolve()
