--[[
    Infinity Islands — Rebuild Part 15
    Mobile-first dungeon camera + easy sword attack.

    Touch-only behavior:
    - requests portrait orientation;
    - stable high-angle camera;
    - explicit large ATTACK button;
    - hold ATTACK to continue the existing sword combo;
    - before Tool:Activate(), softly face the nearest valid CombatTarget.

    Security:
    - this client does NOT apply damage;
    - this client does NOT choose server hits;
    - the existing SwordInputClient + SwordCombatServer remain authoritative.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOUCH_DEVICE = UserInputService.TouchEnabled
local PURE_TOUCH = TOUCH_DEVICE and not UserInputService.KeyboardEnabled

-- Desktop/gamepad behavior remains untouched.
if not TOUCH_DEVICE then
    player:SetAttribute("DungeonMobileModeActive", false)
    return
end

local oldGui = playerGui:FindFirstChild("DungeonMobileCombat")
if oldGui then
    oldGui:Destroy()
end

local CAMERA_BIND = "DungeonMobileCamera_" .. tostring(player.UserId)
RunService:UnbindFromRenderStep(CAMERA_BIND)

local CAMERA_OFFSET = Vector3.new(0, 32, 16)
local CAMERA_LOOK_HEIGHT = 2.1
local CAMERA_FOV = 58
local CAMERA_LERP_SPEED = 11

local ASSIST_RADIUS = 18
local ASSIST_MAX_VERTICAL = 9
local HOLD_PULSE = 0.10
local BUTTON_SIZE = 96

local cameraEnabled = true
local attackHeld = false
local attackSerial = 0
local currentAssistTarget
local currentAssistDistance

local function entryPresentationReady()
    return player:GetAttribute("DungeonEntryPresentationState") == "Playing"
end

local function isDungeonRunning()
    local state = Workspace:GetAttribute("DungeonProgressionState")
    if state == nil then
        return false
    end
    state = tostring(state)
    return state ~= "" and state ~= "Stopped"
end

local function livingCharacter()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not character
        or not humanoid
        or humanoid.Health <= 0
        or not root
        or not root:IsA("BasePart")
        or player:GetAttribute("IsDowned") == true
    then
        return nil
    end
    return character, humanoid, root
end

local function isSword(tool)
    return tool
        and tool:IsA("Tool")
        and (
            tool.Name == "ClassicSword"
            or tool:GetAttribute("IsSword") == true
            or tool:GetAttribute("WeaponType") == "Sword"
        )
end

local function equippedSword()
    local character = player.Character
    if not character then
        return nil
    end
    for _, child in ipairs(character:GetChildren()) do
        if isSword(child) then
            return child
        end
    end
    return nil
end

local function targetRoot(model)
    if not model or not model:IsA("Model") or not model.Parent then
        return nil
    end
    local root = model:FindFirstChild("HumanoidRootPart", true)
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
    return root and root:IsA("BasePart") and root or nil
end

local function validTarget(model, character, attackerRoot)
    if not model
        or not model:IsA("Model")
        or not model.Parent
        or model == character
        or model:GetAttribute("ObjectiveTargetCompleted") == true
        or model:GetAttribute("Invulnerable") == true
        or model:GetAttribute("NoSwordDamage") == true
    then
        return false
    end

    local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
    local root = targetRoot(model)
    if not humanoid or humanoid.Health <= 0 or not root then
        return false
    end

    local tutorialTargetUserId = model:GetAttribute("TutorialTargetUserId")
    if typeof(tutorialTargetUserId) == "number"
        and tutorialTargetUserId ~= player.UserId
    then
        return false
    end

    local offset = root.Position - attackerRoot.Position
    if math.abs(offset.Y) > ASSIST_MAX_VERTICAL then
        return false
    end
    if Vector2.new(offset.X, offset.Z).Magnitude > ASSIST_RADIUS then
        return false
    end

    return true
end

local function findAssistTarget()
    local character, _, attackerRoot = livingCharacter()
    if not character then
        return nil
    end

    local currentObjectiveId = tostring(
        Workspace:GetAttribute("DungeonObjectiveId") or ""
    )

    local best
    local bestScore = math.huge
    local seen = {}

    local function consider(candidate)
        local model = candidate
        if candidate and not candidate:IsA("Model") then
            model = candidate:FindFirstAncestorOfClass("Model")
        end
        if not model or seen[model] then
            return
        end
        seen[model] = true

        if not validTarget(model, character, attackerRoot) then
            return
        end

        local root = targetRoot(model)
        local offset = root.Position - attackerRoot.Position
        local horizontalDistance = Vector2.new(offset.X, offset.Z).Magnitude

        -- Current mandatory objective receives a strong preference, but
        -- nearby normal CombatTargets can still be attacked naturally.
        local objectiveBonus = 0
        if currentObjectiveId ~= ""
            and tostring(model:GetAttribute("ObjectiveId") or "") == currentObjectiveId
        then
            objectiveBonus = -7
        end

        local score = horizontalDistance + objectiveBonus
        if score < bestScore then
            best = model
            bestScore = score
            currentAssistDistance = horizontalDistance
        end
    end

    for _, candidate in ipairs(CollectionService:GetTagged("CombatTarget")) do
        consider(candidate)
    end
    for _, candidate in ipairs(CollectionService:GetTagged("DungeonObjectiveTarget")) do
        consider(candidate)
    end

    return best
end

local function faceTarget(model)
    local _, humanoid, root = livingCharacter()
    local target = targetRoot(model)
    if not humanoid or not root or not target then
        return false
    end

    local delta = target.Position - root.Position
    local horizontal = Vector3.new(delta.X, 0, delta.Z)
    if horizontal.Magnitude < 0.05 then
        return false
    end

    -- Network-owned character orientation replicates naturally.
    -- Do not anchor, teleport or lock the player.
    root.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal.Unit)
    humanoid.AutoRotate = true
    return true
end

local function assistedActivate()
    if not isDungeonRunning() then
        return false
    end

    local character = player.Character
    if not character or character:GetAttribute("MovementLocked") == true then
        return false
    end

    local tool = equippedSword()
    if not tool then
        return false
    end

    currentAssistDistance = nil
    currentAssistTarget = findAssistTarget()
    if currentAssistTarget then
        faceTarget(currentAssistTarget)
        player:SetAttribute("DungeonMobileAssistTarget", currentAssistTarget.Name)
        player:SetAttribute(
            "DungeonMobileAssistDistance",
            currentAssistDistance and math.floor(currentAssistDistance + 0.5) or nil
        )
    else
        player:SetAttribute("DungeonMobileAssistTarget", nil)
        player:SetAttribute("DungeonMobileAssistDistance", nil)
    end

    -- Reuses the existing Tool.Activated pipeline.
    -- SwordInputClient still handles local combo animation and RemoteEvent.
    tool:Activate()
    return true
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonMobileCombat"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 72
gui.Parent = playerGui

local attackButton = Instance.new("TextButton")
attackButton.Name = "AttackButton"
attackButton.AnchorPoint = Vector2.new(1, 1)
attackButton.Position = UDim2.new(1, -20, 1, -42)
attackButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
attackButton.BackgroundColor3 = Color3.fromRGB(29, 38, 50)
attackButton.BackgroundTransparency = 0.08
attackButton.BorderSizePixel = 0
attackButton.AutoButtonColor = false
attackButton.Text = "ATTACK"
attackButton.TextColor3 = Color3.fromRGB(248, 250, 255)
attackButton.Font = Enum.Font.GothamBold
attackButton.TextSize = 16
attackButton.Visible = false
attackButton.Parent = gui
Instance.new("UICorner", attackButton).CornerRadius = UDim.new(1, 0)

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Transparency = 0.12
stroke.Color = Color3.fromRGB(106, 211, 255)
stroke.Parent = attackButton

local introPulseStroke = Instance.new("UIStroke")
introPulseStroke.Name = "IntroPulseStroke"
introPulseStroke.Thickness = 2
introPulseStroke.Transparency = 1
introPulseStroke.Color = Color3.fromRGB(255, 218, 116)
introPulseStroke.Parent = attackButton

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 0, -5)
hint.Size = UDim2.fromOffset(118, 18)
hint.BackgroundTransparency = 1
hint.Text = "SEGURE PARA ATACAR"
hint.TextColor3 = Color3.fromRGB(191, 213, 229)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 9
hint.Parent = attackButton

local attackVisible = false
local attackVisibilitySerial = 0
local introPulseSerial = 0
local introPulsePlayed = false

local function playIntroAttackPulse()
    if introPulsePlayed
        or not attackButton.Visible
        or player:GetAttribute("GuidedIntroAttackLearned") == true
    then
        return
    end

    introPulsePlayed = true
    introPulseSerial += 1
    local serial = introPulseSerial
    player:SetAttribute("DungeonMobileAttackIntroPulsePlayed", true)
    player:SetAttribute(
        "DungeonMobileAttackIntroPulseAt",
        Workspace:GetServerTimeNow()
    )

    task.spawn(function()
        for _ = 1, 2 do
            if serial ~= introPulseSerial
                or not attackButton.Visible
                or attackHeld
                or player:GetAttribute("GuidedIntroAttackLearned") == true
            then
                break
            end

            TweenService:Create(
                introPulseStroke,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {
                    Transparency = 0.08,
                    Thickness = 4.5,
                }
            ):Play()
            task.wait(0.20)

            TweenService:Create(
                introPulseStroke,
                TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {
                    Transparency = 1,
                    Thickness = 2,
                }
            ):Play()
            task.wait(0.36)
        end
    end)
end

local function setAttackVisible(shouldShow)
    if attackVisible == shouldShow and attackButton.Visible == shouldShow then
        return
    end

    attackVisible = shouldShow
    attackVisibilitySerial += 1
    local serial = attackVisibilitySerial

    if shouldShow then
        attackButton.Visible = true
        attackButton.BackgroundTransparency = 1
        attackButton.TextTransparency = 1
        stroke.Transparency = 1
        hint.TextTransparency = 1

        TweenService:Create(
            attackButton,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                BackgroundTransparency = 0.08,
                TextTransparency = 0,
            }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Transparency = 0.12 }
        ):Play()
        TweenService:Create(
            hint,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        ):Play()

        if player:GetAttribute("GuidedIntroActive") == true
            and tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "FirstStrike"
            and player:GetAttribute("GuidedIntroAttackLearned") ~= true
        then
            task.delay(0.85, function()
                if attackVisible
                    and player:GetAttribute("GuidedIntroAttackReady") == true
                    and player:GetAttribute("GuidedIntroAttackLearned") ~= true
                then
                    playIntroAttackPulse()
                end
            end)
        end
    else
        attackHeld = false
        attackSerial += 1

        TweenService:Create(
            attackButton,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {
                BackgroundTransparency = 1,
                TextTransparency = 1,
            }
        ):Play()
        TweenService:Create(
            stroke,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }
        ):Play()
        TweenService:Create(
            hint,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }
        ):Play()

        task.delay(0.16, function()
            if serial == attackVisibilitySerial and not attackVisible then
                attackButton.Visible = false
            end
        end)
    end
end

local function refreshButton()
    local baseVisible = entryPresentationReady()
        and isDungeonRunning()
        and player:GetAttribute("IsDowned") ~= true
        and equippedSword() ~= nil

    local beginnerFirstStrike =
        player:GetAttribute("GuidedIntroActive") == true
        and tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "FirstStrike"

    local serverAmbushWarning =
        tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "SkyAmbush"
        and tostring(Workspace:GetAttribute("DungeonEncounterWaveState") or "") == "AmbushWarning"

    local serverRangedWarning =
        tostring(Workspace:GetAttribute("DungeonObjectiveId") or "") == "RangedThreat"
        and tostring(Workspace:GetAttribute("DungeonEncounterWaveState") or "") == "RangedWarning"

    local visible = baseVisible
        and player:GetAttribute("DungeonBeginnerUpgradePresentationActive") ~= true
        and player:GetAttribute("DungeonSkyAmbushPresentationActive") ~= true
        and player:GetAttribute("DungeonRangedThreatPresentationActive") ~= true
        and not serverAmbushWarning
        and not serverRangedWarning

    if beginnerFirstStrike
        and player:GetAttribute("GuidedIntroAttackLearned") ~= true
    then
        visible = baseVisible
            and player:GetAttribute("GuidedIntroAttackReady") == true
    end

    setAttackVisible(visible)
end

local function setPressed(pressed)
    attackButton.BackgroundTransparency = pressed and 0 or 0.08
    attackButton.Size = UDim2.fromOffset(
        pressed and BUTTON_SIZE - 6 or BUTTON_SIZE,
        pressed and BUTTON_SIZE - 6 or BUTTON_SIZE
    )
end

local function startAttackHold()
    if attackHeld or not attackButton.Visible then
        return
    end

    introPulseSerial += 1
    introPulseStroke.Transparency = 1
    introPulseStroke.Thickness = 2

    attackHeld = true
    attackSerial += 1
    local serial = attackSerial
    setPressed(true)

    task.spawn(function()
        assistedActivate()

        while attackHeld and serial == attackSerial do
            task.wait(HOLD_PULSE)
            if attackHeld and serial == attackSerial then
                assistedActivate()
            end
        end
    end)
end

local function stopAttackHold()
    if not attackHeld then
        return
    end
    attackHeld = false
    attackSerial += 1
    setPressed(false)
end

attackButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        startAttackHold()
    end
end)

attackButton.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        stopAttackHold()
    end
end)

UserInputService.TouchEnded:Connect(function()
    stopAttackHold()
end)

local function applyPortrait()
    if not PURE_TOUCH then
        return
    end

    pcall(function()
        playerGui.ScreenOrientation = Enum.ScreenOrientation.Portrait
    end)
end

local function updateCamera()
    if not cameraEnabled
        or not isDungeonRunning()
        or player:GetAttribute("DungeonPresentationCameraLock") == true
    then
        return
    end

    local camera = Workspace.CurrentCamera
    local _, humanoid, root = livingCharacter()
    if not camera or not humanoid or not root then
        return
    end

    if camera.CameraType ~= Enum.CameraType.Scriptable then
        camera.CameraType = Enum.CameraType.Scriptable
    end
    camera.FieldOfView = CAMERA_FOV

    local focus = root.Position + Vector3.new(0, CAMERA_LOOK_HEIGHT, 0)
    local desired = CFrame.lookAt(focus + CAMERA_OFFSET, focus)

    local alpha = 1 - math.exp(-CAMERA_LERP_SPEED * math.min(1 / 20, 1 / 60))
    camera.CFrame = camera.CFrame:Lerp(desired, alpha)
    camera.Focus = CFrame.new(focus)
end

RunService:BindToRenderStep(
    CAMERA_BIND,
    Enum.RenderPriority.Camera.Value,
    updateCamera
)

local function refresh()
    applyPortrait()
    refreshButton()

    player:SetAttribute("DungeonMobileModeActive", isDungeonRunning())
    player:SetAttribute("DungeonMobilePortraitRequested", PURE_TOUCH)
    player:SetAttribute("DungeonMobileCameraMode", "PortraitHighAngleV1")
    player:SetAttribute("DungeonMobileAttackAssist", "NearestCombatTargetV1")
end

Workspace:GetAttributeChangedSignal("DungeonProgressionState"):Connect(refresh)
Workspace:GetAttributeChangedSignal("DungeonEncounterWaveState"):Connect(refresh)
player:GetAttributeChangedSignal("IsDowned"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonEntryPresentationState"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonPresentationCameraLock"):Connect(refresh)
player:GetAttributeChangedSignal("GuidedIntroAttackReady"):Connect(refresh)
player:GetAttributeChangedSignal("GuidedIntroAttackLearned"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonBeginnerUpgradePresentationActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonSkyAmbushPresentationActive"):Connect(refresh)

local function watchCharacter(character)
    refresh()
    character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(refresh)
        end
    end)
    character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(refresh)
        end
    end)
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
    watchCharacter(player.Character)
end

task.spawn(function()
    while gui.Parent do
        task.wait(0.30)
        refreshButton()
    end
end)

Workspace:SetAttribute("DungeonMobilePolicy", "PortraitHighAngleEasyAttackV1")
refresh()
