--[[
    Infinity Islands — Rebuild Part 25
    First-impression world loading + opening presentation.

    This exact controller can run from ReplicatedFirst (preferred) or
    StarterPlayerScripts (fallback). The first copy to start becomes owner.

    Ready means ALL of these are true:
    1. procedural world generation is Ready;
    2. the local player's managed spawn is Ready;
    3. FirstStrike is the active objective;
    4. the mandatory FirstStrike slime exists and is alive.

    Only then:
    - the camera is framed toward the slime;
    - the loading curtains open;
    - "Derrote o Slime!" is revealed;
    - controls are returned to the player.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
    return
end

if player:GetAttribute("DungeonEntryPresentationControllerActive") == true then
    return
end
player:SetAttribute("DungeonEntryPresentationControllerActive", true)
player:SetAttribute("DungeonEntryPresentationVersion", "WorldCurtainFirstStrikeV4")
player:SetAttribute("DungeonEntryPresentationState", "Loading")
player:SetAttribute("DungeonPresentationCameraLock", true)
player:SetAttribute("DungeonOpeningMissionState", "Waiting")

local playerGui = player:WaitForChild("PlayerGui")
local TOUCH = UserInputService.TouchEnabled

pcall(function()
    ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local previous = playerGui:FindFirstChild("DungeonWorldLoading")
if previous then
    previous:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonWorldLoading"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(4, 10, 20)
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1000
backdrop.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 10, 21)),
    ColorSequenceKeypoint.new(0.42, Color3.fromRGB(11, 30, 52)),
    ColorSequenceKeypoint.new(0.68, Color3.fromRGB(12, 35, 58)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 11, 22)),
})
gradient.Rotation = 90
gradient.Parent = backdrop

-- A quiet celestial field gives the loading screen identity without adding
-- information. It is deterministic and intentionally sparse.
local starLayer = Instance.new("Frame")
starLayer.Name = "CelestialField"
starLayer.Size = UDim2.fromScale(1, 1)
starLayer.BackgroundTransparency = 1
starLayer.ZIndex = 1001
starLayer.Parent = gui

local random = Random.new(2508)
local stars = {}
for index = 1, 18 do
    local star = Instance.new("Frame")
    star.Name = "Star" .. tostring(index)
    local size = random:NextInteger(2, 4)
    star.AnchorPoint = Vector2.new(0.5, 0.5)
    star.Position = UDim2.fromScale(
        random:NextNumber(0.07, 0.93),
        random:NextNumber(0.08, 0.91)
    )
    star.Size = UDim2.fromOffset(size, size)
    star.BackgroundColor3 = index % 4 == 0
        and Color3.fromRGB(125, 222, 255)
        or Color3.fromRGB(225, 242, 255)
    star.BackgroundTransparency = random:NextNumber(0.55, 0.82)
    star.BorderSizePixel = 0
    star.Rotation = 45
    star.ZIndex = 1001
    star.Parent = starLayer
    table.insert(stars, {
        Object = star,
        Base = star.BackgroundTransparency,
        Phase = random:NextNumber(0, math.pi * 2),
        Speed = random:NextNumber(0.45, 0.95),
    })
end

local horizonGlow = Instance.new("Frame")
horizonGlow.Name = "HorizonGlow"
horizonGlow.AnchorPoint = Vector2.new(0.5, 0.5)
horizonGlow.Position = UDim2.fromScale(0.5, 0.48)
horizonGlow.Size = UDim2.new(0.72, 0, 0, 1)
horizonGlow.BackgroundColor3 = Color3.fromRGB(74, 184, 225)
horizonGlow.BackgroundTransparency = 0.82
horizonGlow.BorderSizePixel = 0
horizonGlow.ZIndex = 1001
horizonGlow.Parent = gui
local horizonConstraint = Instance.new("UISizeConstraint")
horizonConstraint.MinSize = Vector2.new(240, 1)
horizonConstraint.MaxSize = Vector2.new(850, 1)
horizonConstraint.Parent = horizonGlow

local leftCurtain = Instance.new("Frame")
leftCurtain.Name = "LeftCurtain"
leftCurtain.Size = UDim2.new(0.5, 2, 1, 0)
leftCurtain.Position = UDim2.fromScale(0, 0)
leftCurtain.BackgroundColor3 = Color3.fromRGB(5, 15, 29)
leftCurtain.BackgroundTransparency = 0.08
leftCurtain.BorderSizePixel = 0
leftCurtain.ZIndex = 1002
leftCurtain.Parent = gui

local rightCurtain = Instance.new("Frame")
rightCurtain.Name = "RightCurtain"
rightCurtain.AnchorPoint = Vector2.new(1, 0)
rightCurtain.Size = UDim2.new(0.5, 2, 1, 0)
rightCurtain.Position = UDim2.fromScale(1, 0)
rightCurtain.BackgroundColor3 = Color3.fromRGB(5, 15, 29)
rightCurtain.BackgroundTransparency = 0.08
rightCurtain.BorderSizePixel = 0
rightCurtain.ZIndex = 1002
rightCurtain.Parent = gui

local emblemHolder = Instance.new("Frame")
emblemHolder.Name = "Emblem"
emblemHolder.AnchorPoint = Vector2.new(0.5, 0.5)
emblemHolder.Position = UDim2.fromScale(0.5, 0.40)
emblemHolder.Size = UDim2.fromOffset(76, 76)
emblemHolder.BackgroundTransparency = 1
emblemHolder.ZIndex = 1010
emblemHolder.Parent = gui

local emblemScale = Instance.new("UIScale")
emblemScale.Name = "BreathingScale"
emblemScale.Scale = 1
emblemScale.Parent = emblemHolder

local outerDiamond = Instance.new("Frame")
outerDiamond.Name = "OuterDiamond"
outerDiamond.AnchorPoint = Vector2.new(0.5, 0.5)
outerDiamond.Position = UDim2.fromScale(0.5, 0.5)
outerDiamond.Size = UDim2.fromScale(0.72, 0.72)
outerDiamond.Rotation = 45
outerDiamond.BackgroundColor3 = Color3.fromRGB(8, 26, 45)
outerDiamond.BackgroundTransparency = 0.08
outerDiamond.BorderSizePixel = 0
outerDiamond.ZIndex = 1010
outerDiamond.Parent = emblemHolder
local outerCorner = Instance.new("UICorner")
outerCorner.CornerRadius = UDim.new(0, 8)
outerCorner.Parent = outerDiamond
local outerStroke = Instance.new("UIStroke")
outerStroke.Color = Color3.fromRGB(109, 224, 255)
outerStroke.Transparency = 0.34
outerStroke.Thickness = 1.4
outerStroke.Parent = outerDiamond

local innerDiamond = Instance.new("Frame")
innerDiamond.Name = "InnerDiamond"
innerDiamond.AnchorPoint = Vector2.new(0.5, 0.5)
innerDiamond.Position = UDim2.fromScale(0.5, 0.5)
innerDiamond.Size = UDim2.fromScale(0.34, 0.34)
innerDiamond.Rotation = 45
innerDiamond.BackgroundColor3 = Color3.fromRGB(113, 224, 255)
innerDiamond.BackgroundTransparency = 0.08
innerDiamond.BorderSizePixel = 0
innerDiamond.ZIndex = 1011
innerDiamond.Parent = emblemHolder
local innerCorner = Instance.new("UICorner")
innerCorner.CornerRadius = UDim.new(0, 4)
innerCorner.Parent = innerDiamond

local brand = Instance.new("TextLabel")
brand.Name = "Brand"
brand.AnchorPoint = Vector2.new(0.5, 0.5)
brand.Position = UDim2.fromScale(0.5, 0.515)
brand.Size = UDim2.new(1, -40, 0, 50)
brand.BackgroundTransparency = 1
brand.Text = "INFINITY ISLANDS"
brand.TextColor3 = Color3.fromRGB(239, 248, 255)
brand.Font = Enum.Font.GothamBlack
brand.TextScaled = true
brand.ZIndex = 1010
brand.Parent = gui
local brandConstraint = Instance.new("UITextSizeConstraint")
brandConstraint.MinTextSize = 21
brandConstraint.MaxTextSize = 36
brandConstraint.Parent = brand

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.565)
status.Size = UDim2.new(1, -48, 0, 26)
status.BackgroundTransparency = 1
status.Text = "Preparando sua expedição..."
status.TextColor3 = Color3.fromRGB(167, 197, 220)
status.Font = Enum.Font.GothamMedium
status.TextSize = 12
status.ZIndex = 1010
status.Parent = gui

local barBack = Instance.new("Frame")
barBack.Name = "ProgressBack"
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.fromScale(0.5, 0.622)
barBack.Size = UDim2.new(0.38, 0, 0, 4)
barBack.BackgroundColor3 = Color3.fromRGB(21, 47, 67)
barBack.BackgroundTransparency = 0.14
barBack.BorderSizePixel = 0
barBack.ZIndex = 1010
barBack.Parent = gui
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local barConstraint = Instance.new("UISizeConstraint")
barConstraint.MinSize = Vector2.new(150, 4)
barConstraint.MaxSize = Vector2.new(360, 4)
barConstraint.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0.03, 1)
barFill.BackgroundColor3 = Color3.fromRGB(103, 222, 255)
barFill.BorderSizePixel = 0
barFill.ZIndex = 1011
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

local barShine = Instance.new("UIGradient")
barShine.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(74, 180, 225)),
    ColorSequenceKeypoint.new(0.72, Color3.fromRGB(126, 234, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 253, 255)),
})
barShine.Rotation = 0
barShine.Parent = barFill

-- Purely visual breathing/twinkle. No loading logic is tied to this animation.
task.spawn(function()
    local pulseUp = true
    while gui.Parent
        and player:GetAttribute("DungeonEntryPresentationState") == "Loading"
    do
        local targetScale = pulseUp and 1.055 or 0.975
        local targetTransparency = pulseUp and 0.14 or 0.34
        pulseUp = not pulseUp

        TweenService:Create(
            emblemScale,
            TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            { Scale = targetScale }
        ):Play()
        TweenService:Create(
            outerStroke,
            TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            { Transparency = targetTransparency }
        ):Play()
        task.wait(1.25)
    end
end)

local starElapsed = 0
RunService.RenderStepped:Connect(function(dt)
    if not gui.Parent
        or player:GetAttribute("DungeonEntryPresentationState") ~= "Loading"
    then
        return
    end

    starElapsed += dt
    for _, record in ipairs(stars) do
        local wave = (math.sin(starElapsed * record.Speed + record.Phase) + 1) * 0.5
        record.Object.BackgroundTransparency = math.clamp(
            record.Base - wave * 0.16,
            0.38,
            0.88
        )
    end
end)

local missionHolder = Instance.new("Frame")
missionHolder.Name = "OpeningMissionHolder"
missionHolder.AnchorPoint = Vector2.new(0.5, 0)
missionHolder.Position = UDim2.new(0.5, 0, 0, 0)
missionHolder.Size = UDim2.new(1, -28, 0, 82)
missionHolder.BackgroundTransparency = 1
missionHolder.ZIndex = 1020
missionHolder.Parent = gui

local missionScale = Instance.new("UIScale")
missionScale.Name = "OpeningMissionScale"
missionScale.Scale = 0.88
missionScale.Parent = missionHolder

local missionGlow = Instance.new("TextLabel")
missionGlow.Name = "Glow"
missionGlow.Size = UDim2.fromScale(1, 1)
missionGlow.BackgroundTransparency = 1
missionGlow.Text = "Derrote o Slime!"
missionGlow.TextColor3 = Color3.fromRGB(95, 220, 255)
missionGlow.TextTransparency = 1
missionGlow.TextStrokeColor3 = Color3.fromRGB(95, 220, 255)
missionGlow.TextStrokeTransparency = 1
missionGlow.Font = Enum.Font.GothamBlack
missionGlow.TextScaled = true
missionGlow.ZIndex = 1020
missionGlow.Parent = missionHolder
local missionGlowConstraint = Instance.new("UITextSizeConstraint")
missionGlowConstraint.MinTextSize = 25
missionGlowConstraint.MaxTextSize = TOUCH and 38 or 46
missionGlowConstraint.Parent = missionGlow

local mission = Instance.new("TextLabel")
mission.Name = "OpeningMission"
mission.Size = UDim2.fromScale(1, 1)
mission.BackgroundTransparency = 1
mission.Text = "Derrote o Slime!"
mission.TextColor3 = Color3.fromRGB(250, 252, 255)
mission.TextStrokeColor3 = Color3.fromRGB(5, 14, 25)
mission.TextStrokeTransparency = 1
mission.TextTransparency = 1
mission.Font = Enum.Font.GothamBlack
mission.TextScaled = true
mission.ZIndex = 1021
mission.Parent = missionHolder
local missionConstraint = Instance.new("UITextSizeConstraint")
missionConstraint.MinTextSize = 25
missionConstraint.MaxTextSize = TOUCH and 38 or 46
missionConstraint.Parent = mission

local missionLineBack = Instance.new("Frame")
missionLineBack.Name = "UnderlineBack"
missionLineBack.AnchorPoint = Vector2.new(0.5, 1)
missionLineBack.Position = UDim2.new(0.5, 0, 1, -5)
missionLineBack.Size = UDim2.fromOffset(118, 2)
missionLineBack.BackgroundColor3 = Color3.fromRGB(28, 69, 91)
missionLineBack.BackgroundTransparency = 1
missionLineBack.BorderSizePixel = 0
missionLineBack.ZIndex = 1020
missionLineBack.Parent = missionHolder

local missionLine = Instance.new("Frame")
missionLine.Name = "Underline"
missionLine.AnchorPoint = Vector2.new(0.5, 0.5)
missionLine.Position = UDim2.fromScale(0.5, 0.5)
missionLine.Size = UDim2.fromScale(0, 1)
missionLine.BackgroundColor3 = Color3.fromRGB(103, 222, 255)
missionLine.BackgroundTransparency = 1
missionLine.BorderSizePixel = 0
missionLine.ZIndex = 1021
missionLine.Parent = missionLineBack

local missionLineGradient = Instance.new("UIGradient")
missionLineGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.22, 0.18),
    NumberSequenceKeypoint.new(0.78, 0.18),
    NumberSequenceKeypoint.new(1, 1),
})
missionLineGradient.Parent = missionLine

local function positionOpeningMission()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

    local coreTopLeft = Vector2.zero
    local topbarRelative = Rect.new(0, 0, viewport.X, 0)

    pcall(function()
        coreTopLeft = select(1, GuiService:GetGuiInset())
    end)
    pcall(function()
        topbarRelative = GuiService:GetInsetArea(
            Enum.ScreenInsets.TopbarSafeInsets
        )
    end)

    -- This ScreenGui is fullscreen (IgnoreGuiInset=true). GetInsetArea is
    -- relative to CoreUISafeInsets, so add Core's physical origin to recover
    -- the REAL free top-bar rectangle in fullscreen pixels.
    local left = coreTopLeft.X + topbarRelative.Min.X
    local right = coreTopLeft.X + topbarRelative.Max.X
    local top = coreTopLeft.Y + topbarRelative.Min.Y

    if right - left < 40 then
        left = 8
        right = viewport.X - 8
        top = 0
    end

    local laneWidth = math.max(1, right - left)
    local centerX = left + laneWidth * 0.5
    local width = math.max(1, laneWidth - 4)

    local shortest = math.min(viewport.X, viewport.Y)
    local height = math.clamp(math.floor(shortest * 0.115), 66, 88)

    missionHolder.Position = UDim2.fromOffset(centerX, top)
    missionHolder.Size = UDim2.fromOffset(width, height)

    player:SetAttribute("DungeonOpeningMissionAbsoluteTopY", top)
    player:SetAttribute("DungeonOpeningMissionTopbarWidth", laneWidth)
end

positionOpeningMission()

GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
    positionOpeningMission()
end)

local controls
task.spawn(function()
    local ok, resolved = pcall(function()
        local playerScripts = player:WaitForChild("PlayerScripts", 15)
        local module = playerScripts and playerScripts:WaitForChild("PlayerModule", 15)
        if not module then
            return nil
        end
        return require(module):GetControls()
    end)
    if ok and resolved then
        controls = resolved
        pcall(function()
            controls:Disable()
        end)
    end
end)

local function characterParts()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if character
        and humanoid
        and humanoid.Health > 0
        and root
        and root:IsA("BasePart")
    then
        return character, humanoid, root
    end
    return nil
end

local function targetRoot(model)
    if not model or not model:IsA("Model") or not model.Parent then
        return nil
    end
    return model:FindFirstChild("HumanoidRootPart", true)
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function firstStrikeTarget()
    local best
    local bestRoot
    local bestPriority = math.huge
    local seen = {}

    local function consider(candidate)
        local model = candidate
        if candidate and not candidate:IsA("Model") then
            model = candidate:FindFirstAncestorOfClass("Model")
        end
        if not model or seen[model] or not model.Parent then
            return
        end
        seen[model] = true

        if tostring(model:GetAttribute("ObjectiveId") or "") ~= "FirstStrike" then
            return
        end
        if model:GetAttribute("RebuildProgressionTarget") ~= true
            and model:GetAttribute("ObjectiveFocusTarget") ~= true
        then
            return
        end

        local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
        local root = targetRoot(model)
        if not humanoid or humanoid.Health <= 0 or not root then
            return
        end

        local priority = model:GetAttribute("ObjectiveFocusTarget") == true and 0 or 1
        if priority < bestPriority then
            best = model
            bestRoot = root
            bestPriority = priority
        end
    end

    for _, item in ipairs(CollectionService:GetTagged("CombatTarget")) do
        consider(item)
    end
    for _, item in ipairs(CollectionService:GetTagged("DungeonObjectiveTarget")) do
        consider(item)
    end

    if not best then
        for _, item in ipairs(Workspace:GetDescendants()) do
            if item:IsA("Model")
                and tostring(item:GetAttribute("ObjectiveId") or "") == "FirstStrike"
            then
                consider(item)
            end
        end
    end

    return best, bestRoot
end

local function readiness()
    local worldReady =
        tostring(Workspace:GetAttribute("DungeonGenerationState") or "") == "Ready"
        and Workspace:GetAttribute("DungeonRuntimeReady") == true

    local spawnReady =
        player:GetAttribute("RespawnState") == "Ready"
        and player:GetAttribute("InitialSpawnPositioned") == true
        and characterParts() ~= nil

    local objectiveReady =
        tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "FirstStrike"
        and tostring(Workspace:GetAttribute("DungeonProgressionState") or "") == "ObjectiveActive"

    local slime, slimeRoot = firstStrikeTarget()
    local slimeReady = slime ~= nil and slimeRoot ~= nil

    local score = 0
    if worldReady then score += 1 end
    if spawnReady then score += 1 end
    if objectiveReady then score += 1 end
    if slimeReady then score += 1 end

    local message
    if not worldReady then
        message = "Construindo as ilhas..."
    elseif not spawnReady then
        message = "Preparando seu ponto de entrada..."
    elseif not objectiveReady then
        message = "Preparando seu primeiro desafio..."
    elseif not slimeReady then
        message = "Posicionando o primeiro inimigo..."
    else
        message = "Pronto!"
    end

    return score, message, slime, slimeRoot
end

local progressTween
local function userFacingLoadingCopy(score)
    if score >= 4 then
        return "Tudo pronto."
    elseif score >= 2 then
        return "Quase pronto..."
    end
    return "Preparando sua expedição..."
end

local function showProgress(score, diagnosticMessage)
    status.Text = userFacingLoadingCopy(score)

    -- Never show a mathematically empty bar; a tiny initial fill communicates
    -- that the experience is alive without inventing fake percentage.
    local ratio = math.clamp(math.max(0.03, score / 4), 0, 1)
    if progressTween then
        progressTween:Cancel()
    end
    progressTween = TweenService:Create(
        barFill,
        TweenInfo.new(0.34, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(ratio, 1) }
    )
    progressTween:Play()

    player:SetAttribute("DungeonEntryLoadingProgress", score)
    player:SetAttribute("DungeonEntryLoadingStatus", diagnosticMessage)
    player:SetAttribute("DungeonEntryLoadingDisplayText", status.Text)
end

local function markerForIsland(globalIslandIndex, markerType)
    if not globalIslandIndex then
        return nil
    end

    local tagName = markerType == "Exit"
        and "DungeonRouteExit"
        or "Dungeon" .. tostring(markerType)

    for _, marker in ipairs(CollectionService:GetTagged(tagName)) do
        if marker:IsA("BasePart")
            and marker.Parent
            and tonumber(marker:GetAttribute("GlobalIslandIndex")) == globalIslandIndex
        then
            return marker
        end
    end

    -- Fallback for a marker that was created before CollectionService tagging
    -- finished replicating to the client.
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("BasePart")
            and descendant:GetAttribute("MarkerType") == markerType
            and tonumber(descendant:GetAttribute("GlobalIslandIndex")) == globalIslandIndex
        then
            return descendant
        end
    end

    return nil
end

local function horizontalUnit(fromPosition, toPosition, fallback)
    local delta = toPosition - fromPosition
    local flat = Vector3.new(delta.X, 0, delta.Z)
    if flat.Magnitude < 0.05 then
        return fallback or Vector3.new(0, 0, -1), 0
    end
    return flat.Unit, flat.Magnitude
end

local function openingComposition(slimeRoot)
    local character, humanoid, playerRoot = characterParts()
    local camera = Workspace.CurrentCamera
    if not camera or not character or not humanoid or not playerRoot or not slimeRoot then
        return nil
    end

    local direction, slimeDistance = horizontalUnit(
        playerRoot.Position,
        slimeRoot.Position,
        playerRoot.CFrame.LookVector
    )

    -- During loading the player has no control, so orienting the avatar is
    -- presentation-safe and removes the awkward "body looking elsewhere" frame.
    local facingPoint = playerRoot.Position + direction
    playerRoot.CFrame = CFrame.lookAt(
        playerRoot.Position,
        Vector3.new(facingPoint.X, playerRoot.Position.Y, facingPoint.Z)
    )
    playerRoot.AssemblyAngularVelocity = Vector3.zero

    local globalIslandIndex =
        tonumber(slimeRoot.Parent and slimeRoot.Parent:GetAttribute("GlobalIslandIndex"))
        or tonumber(Workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex"))
        or 1

    local exitMarker = markerForIsland(globalIslandIndex, "Exit")
    local routeCuePosition
    local hasRouteCue = false

    if exitMarker then
        local exitDirection, exitDistance = horizontalUnit(
            playerRoot.Position,
            exitMarker.Position,
            direction
        )

        -- Only use the Exit as a visual cue if it lies broadly in the same
        -- direction as the slime. A side/back exit would weaken the composition.
        local alignment = direction:Dot(exitDirection)
        if alignment >= 0.35 and exitDistance >= slimeDistance * 0.70 then
            routeCuePosition = exitMarker.Position
            hasRouteCue = true
        end
    end

    local viewport = camera.ViewportSize
    local portrait = viewport.Y > viewport.X * 1.08
    local touchLandscape = TOUCH and not portrait

    -- Composition targets:
    -- portrait: closer + a little higher so player/slime fit vertically;
    -- landscape: lower, more cinematic third-person angle.
    local backDistance
    local cameraHeight
    local fov

    if portrait then
        backDistance = math.clamp(slimeDistance * 0.42 + 7.0, 9.5, 13.5)
        cameraHeight = math.clamp(slimeDistance * 0.28 + 6.0, 8.0, 11.5)
        fov = 56
    elseif touchLandscape then
        backDistance = math.clamp(slimeDistance * 0.48 + 7.0, 10.0, 14.5)
        cameraHeight = math.clamp(slimeDistance * 0.18 + 4.5, 6.0, 8.5)
        fov = 60
    else
        backDistance = math.clamp(slimeDistance * 0.52 + 7.5, 10.5, 15.5)
        cameraHeight = math.clamp(slimeDistance * 0.14 + 4.2, 5.5, 7.8)
        fov = 62
    end

    local right = Vector3.new(-direction.Z, 0, direction.X)
    local lateralOffset = portrait and 0 or math.clamp(slimeDistance * 0.04, 0.35, 0.75)

    local finalCameraPosition =
        playerRoot.Position
        - direction * backDistance
        + right * lateralOffset
        + Vector3.new(0, cameraHeight, 0)

    local slimeAim =
        slimeRoot.Position
        + Vector3.new(0, math.max(1.4, slimeRoot.Size.Y * 0.28), 0)

    -- Keep slime dominant. Route is only a subtle secondary cue.
    local aimPoint = slimeAim
    if routeCuePosition then
        local routeAim = routeCuePosition + Vector3.new(0, 1.2, 0)
        aimPoint = slimeAim:Lerp(routeAim, portrait and 0.08 or 0.13)
    end

    local finalCFrame = CFrame.lookAt(finalCameraPosition, aimPoint)

    -- A very small dolly during curtain opening makes the reveal feel authored
    -- without feeling like a cutscene that steals control.
    local revealStartPosition =
        finalCameraPosition
        - direction * 1.15
        + Vector3.new(0, 0.35, 0)
    local revealStartCFrame = CFrame.lookAt(revealStartPosition, aimPoint)

    return {
        Camera = camera,
        Humanoid = humanoid,
        PlayerRoot = playerRoot,
        SlimeRoot = slimeRoot,
        ExitMarker = exitMarker,
        HasRouteCue = hasRouteCue,
        StartCFrame = revealStartCFrame,
        FinalCFrame = finalCFrame,
        Focus = aimPoint,
        FOV = fov,
        SlimeDistance = slimeDistance,
        Portrait = portrait,
    }
end

local function frameFirstStrike(slimeRoot)
    local composition = openingComposition(slimeRoot)
    if not composition then
        return nil
    end

    local camera = composition.Camera
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = composition.FOV
    camera.CFrame = composition.StartCFrame
    camera.Focus = CFrame.new(composition.Focus)

    player:SetAttribute(
        "DungeonOpeningCameraTarget",
        slimeRoot.Parent and slimeRoot.Parent.Name or "FirstStrike"
    )
    player:SetAttribute(
        "DungeonOpeningCameraComposition",
        "PlayerSlimeRouteV1"
    )
    player:SetAttribute(
        "DungeonOpeningCameraHasRouteCue",
        composition.HasRouteCue
    )
    player:SetAttribute(
        "DungeonOpeningCameraSlimeDistance",
        math.floor(composition.SlimeDistance * 10 + 0.5) / 10
    )
    player:SetAttribute(
        "DungeonOpeningCameraFOV",
        composition.FOV
    )
    player:SetAttribute(
        "DungeonOpeningCameraOrientation",
        composition.Portrait and "Portrait" or "Landscape"
    )

    return composition
end

local function restoreGameplayCamera()
    local _, humanoid = characterParts()
    local camera = Workspace.CurrentCamera
    player:SetAttribute("DungeonPresentationCameraLock", false)

    if not TOUCH and camera and humanoid then
        camera.CameraSubject = humanoid
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = 70
    end
end

local function openWorld(slimeRoot)
    if player:GetAttribute("DungeonEntryPresentationState") ~= "Loading" then
        return
    end

    player:SetAttribute("DungeonEntryPresentationState", "Opening")
    showProgress(4, "Pronto!")

    -- Camera MUST already be composed before any world pixel is revealed.
    local composition = frameFirstStrike(slimeRoot)
    RunService.RenderStepped:Wait()

    if composition then
        -- Re-evaluate once after the render step in case avatar replication
        -- changed its root CFrame during the handoff.
        composition = frameFirstStrike(slimeRoot) or composition
    end

    brand.Visible = false
    status.Visible = false
    barBack.Visible = false

    local curtainInfo = TweenInfo.new(
        0.62,
        Enum.EasingStyle.Quint,
        Enum.EasingDirection.InOut
    )
    TweenService:Create(
        leftCurtain,
        curtainInfo,
        { Position = UDim2.new(-0.52, 0, 0, 0) }
    ):Play()
    TweenService:Create(
        rightCurtain,
        curtainInfo,
        { Position = UDim2.new(1.52, 0, 0, 0) }
    ):Play()
    TweenService:Create(
        backdrop,
        TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 1 }
    ):Play()

    if composition and composition.Camera then
        TweenService:Create(
            composition.Camera,
            TweenInfo.new(
                0.78,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ),
            {
                CFrame = composition.FinalCFrame,
                FieldOfView = composition.FOV,
            }
        ):Play()
    end

    task.delay(0.14, function()
        player:SetAttribute("DungeonOpeningMissionState", "Revealing")
        positionOpeningMission()

        TweenService:Create(
            missionScale,
            TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        ):Play()
        TweenService:Create(
            mission,
            TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0,
                TextStrokeTransparency = 0.38,
            }
        ):Play()
        TweenService:Create(
            missionGlow,
            TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                TextTransparency = 0.72,
                TextStrokeTransparency = 0.76,
            }
        ):Play()
        TweenService:Create(
            missionLineBack,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.72 }
        ):Play()
        TweenService:Create(
            missionLine,
            TweenInfo.new(0.30, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 0.04,
            }
        ):Play()

        task.delay(0.34, function()
            if player:GetAttribute("DungeonOpeningMissionState") == "Revealing" then
                player:SetAttribute("DungeonOpeningMissionState", "Holding")
            end
        end)
    end)

    task.wait(0.70)

    player:SetAttribute("DungeonEntryPresentationState", "Playing")
    player:SetAttribute("DungeonEntryPresentationCompletedAt", Workspace:GetServerTimeNow())

    if controls then
        pcall(function()
            controls:Enable()
        end)
    end

    -- Give the player a moment to understand the target before returning camera authority.
    task.delay(0.70, restoreGameplayCamera)

    task.delay(1.45, function()
        if not gui.Parent then
            return
        end

        player:SetAttribute("DungeonOpeningMissionState", "HandingOff")

        -- The large instruction becomes lighter and slightly smaller before
        -- the compact objective card is allowed to take ownership.
        TweenService:Create(
            missionScale,
            TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { Scale = 0.86 }
        ):Play()
        TweenService:Create(
            mission,
            TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            missionGlow,
            TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            missionLine,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                Size = UDim2.fromScale(0, 1),
                BackgroundTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            missionLineBack,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        ):Play()

        task.wait(0.20)

        -- Only now may the normal objective HUD display the same information.
        player:SetAttribute("DungeonOpeningMissionState", "CompactReady")
        player:SetAttribute(
            "DungeonOpeningMissionCompletedAt",
            Workspace:GetServerTimeNow()
        )

        task.wait(0.12)
        if gui.Parent then
            gui:Destroy()
        end
    end)
end

local startedAt = os.clock()
local MINIMUM_LOADING_VISIBLE_SECONDS = 0.90
local nextCheck = 0

RunService.RenderStepped:Connect(function()
    if player:GetAttribute("DungeonEntryPresentationState") ~= "Loading" then
        return
    end

    if os.clock() < nextCheck then
        return
    end
    nextCheck = os.clock() + 0.10

    local score, message, _, slimeRoot = readiness()
    showProgress(score, message)

    if score >= 4
        and slimeRoot
        and os.clock() - startedAt >= MINIMUM_LOADING_VISIBLE_SECONDS
    then
        openWorld(slimeRoot)
        return
    end

    if os.clock() - startedAt > 12 then
        player:SetAttribute("DungeonEntryLoadingSlow", true)
        status.Text = "Só mais um instante..."
    end
end)
