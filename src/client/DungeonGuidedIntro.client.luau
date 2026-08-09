--[[
    Infinity Islands — Rebuild Part 25
    Contextual beginner hints.

    The mission teaches first. The Guide only appears if the player needs help.
    There is no persistent tutorial card competing with the objective HUD.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local TOUCH = UserInputService.TouchEnabled

local VERSION = "ContextualHintsV4"
local MOVE_HINT_DELAY = 2.6
local ATTACK_READY_DISTANCE = 11
local ATTACK_HINT_DELAY = 1.25
local REWARD_HINT_DELAY = 2.8

local old = playerGui:FindFirstChild("DungeonGuidedIntroUI")
if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonGuidedIntroUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 92
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true
gui.Parent = playerGui

pcall(function()
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    gui.ClipToDeviceSafeArea = true
end)

local hint = Instance.new("Frame")
hint.Name = "ContextHint"
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 4)
hint.Size = UDim2.fromOffset(330, 42)
hint.BackgroundColor3 = Color3.fromRGB(9, 24, 39)
hint.BackgroundTransparency = 1
hint.BorderSizePixel = 0
hint.Visible = false
hint.Parent = gui
Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(97, 216, 255)
stroke.Transparency = 1
stroke.Thickness = 1.2
stroke.Parent = hint

local text = Instance.new("TextLabel")
text.Name = "Text"
text.Position = UDim2.fromOffset(12, 0)
text.Size = UDim2.new(1, -24, 1, 0)
text.BackgroundTransparency = 1
text.Text = ""
text.TextColor3 = Color3.fromRGB(240, 248, 255)
text.TextTransparency = 1
text.Font = Enum.Font.GothamBold
text.TextSize = 12
text.TextWrapped = true
text.Parent = hint

-- Movement has its own visual language. It lives near the lower safe edge,
-- away from the mission title and objective card, and disappears as soon as
-- the player proves they understand locomotion.
local movementHint = Instance.new("Frame")
movementHint.Name = "MovementHint"
movementHint.AnchorPoint = Vector2.new(0.5, 1)
movementHint.Position = UDim2.new(0.5, 0, 1, -28)
movementHint.Size = UDim2.fromOffset(286, 64)
movementHint.BackgroundColor3 = Color3.fromRGB(7, 20, 34)
movementHint.BackgroundTransparency = 1
movementHint.BorderSizePixel = 0
movementHint.Visible = false
movementHint.ZIndex = 20
movementHint.Parent = gui

local movementCorner = Instance.new("UICorner")
movementCorner.CornerRadius = UDim.new(0, 15)
movementCorner.Parent = movementHint

local movementStroke = Instance.new("UIStroke")
movementStroke.Color = Color3.fromRGB(93, 218, 255)
movementStroke.Transparency = 1
movementStroke.Thickness = 1.1
movementStroke.Parent = movementHint

local movementScale = Instance.new("UIScale")
movementScale.Name = "MovementHintScale"
movementScale.Scale = 0.96
movementScale.Parent = movementHint

local movementIcon = Instance.new("Frame")
movementIcon.Name = "Icon"
movementIcon.AnchorPoint = Vector2.new(0, 0.5)
movementIcon.Position = UDim2.new(0, 12, 0.5, 0)
movementIcon.Size = UDim2.fromOffset(42, 42)
movementIcon.BackgroundColor3 = Color3.fromRGB(16, 45, 65)
movementIcon.BackgroundTransparency = 0.10
movementIcon.BorderSizePixel = 0
movementIcon.ZIndex = 21
movementIcon.Parent = movementHint
local movementIconCorner = Instance.new("UICorner")
movementIconCorner.CornerRadius = UDim.new(0, 11)
movementIconCorner.Parent = movementIcon

local movementLabel = Instance.new("TextLabel")
movementLabel.Name = "Label"
movementLabel.Position = UDim2.fromOffset(64, 8)
movementLabel.Size = UDim2.new(1, -76, 0, 20)
movementLabel.BackgroundTransparency = 1
movementLabel.Text = TOUCH and "MOVIMENTO" or "MOVER"
movementLabel.TextColor3 = Color3.fromRGB(112, 224, 255)
movementLabel.TextTransparency = 1
movementLabel.Font = Enum.Font.GothamBold
movementLabel.TextSize = 10
movementLabel.TextXAlignment = Enum.TextXAlignment.Left
movementLabel.ZIndex = 21
movementLabel.Parent = movementHint

local movementDetail = Instance.new("TextLabel")
movementDetail.Name = "Detail"
movementDetail.Position = UDim2.fromOffset(64, 25)
movementDetail.Size = UDim2.new(1, -76, 0, 28)
movementDetail.BackgroundTransparency = 1
movementDetail.Text = TOUCH
    and "Use o analógico para se mover"
    or "Use WASD para se mover"
movementDetail.TextColor3 = Color3.fromRGB(239, 247, 255)
movementDetail.TextTransparency = 1
movementDetail.Font = Enum.Font.GothamMedium
movementDetail.TextSize = 13
movementDetail.TextXAlignment = Enum.TextXAlignment.Left
movementDetail.TextYAlignment = Enum.TextYAlignment.Top
movementDetail.ZIndex = 21
movementDetail.Parent = movementHint

if TOUCH then
    local ring = Instance.new("Frame")
    ring.Name = "JoystickRing"
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.fromScale(0.5, 0.5)
    ring.Size = UDim2.fromOffset(27, 27)
    ring.BackgroundTransparency = 1
    ring.ZIndex = 22
    ring.Parent = movementIcon
    local ringCorner = Instance.new("UICorner")
    ringCorner.CornerRadius = UDim.new(1, 0)
    ringCorner.Parent = ring
    local ringStroke = Instance.new("UIStroke")
    ringStroke.Color = Color3.fromRGB(123, 226, 255)
    ringStroke.Transparency = 0.28
    ringStroke.Thickness = 1.4
    ringStroke.Parent = ring

    local knob = Instance.new("Frame")
    knob.Name = "JoystickKnob"
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(0.5, 0.5)
    knob.Size = UDim2.fromOffset(11, 11)
    knob.BackgroundColor3 = Color3.fromRGB(126, 229, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 23
    knob.Parent = ring
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob
else
    local keyHolder = Instance.new("Frame")
    keyHolder.Name = "WASD"
    keyHolder.Size = UDim2.fromScale(1, 1)
    keyHolder.BackgroundTransparency = 1
    keyHolder.ZIndex = 22
    keyHolder.Parent = movementIcon

    local keyData = {
        { "W", 15, 3 },
        { "A", 3, 21 },
        { "S", 15, 21 },
        { "D", 27, 21 },
    }

    for _, data in ipairs(keyData) do
        local key = Instance.new("TextLabel")
        key.Name = "Key" .. data[1]
        key.Position = UDim2.fromOffset(data[2], data[3])
        key.Size = UDim2.fromOffset(12, 15)
        key.BackgroundColor3 = Color3.fromRGB(24, 58, 78)
        key.BackgroundTransparency = 0.08
        key.BorderSizePixel = 0
        key.Text = data[1]
        key.TextColor3 = Color3.fromRGB(224, 246, 255)
        key.Font = Enum.Font.GothamBold
        key.TextSize = 8
        key.ZIndex = 23
        key.Parent = keyHolder
        local keyCorner = Instance.new("UICorner")
        keyCorner.CornerRadius = UDim.new(0, 3)
        keyCorner.Parent = key
    end
end

local movementVisible = false
local movementSerial = 0

local function hideMovementHint()
    if not movementVisible then
        return
    end

    movementVisible = false
    movementSerial += 1
    local mine = movementSerial

    TweenService:Create(
        movementHint,
        TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, 0, 1, -20),
        }
    ):Play()
    TweenService:Create(
        movementScale,
        TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Scale = 0.96 }
    ):Play()
    TweenService:Create(
        movementStroke,
        TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Transparency = 1 }
    ):Play()
    TweenService:Create(
        movementLabel,
        TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1 }
    ):Play()
    TweenService:Create(
        movementDetail,
        TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1 }
    ):Play()

    task.delay(0.15, function()
        if mine == movementSerial and not movementVisible then
            movementHint.Visible = false
        end
    end)
end

local function showMovementHint()
    if movementVisible then
        return
    end

    movementVisible = true
    movementSerial += 1
    movementHint.Visible = true
    movementHint.Position = UDim2.new(0.5, 0, 1, -20)
    movementHint.BackgroundTransparency = 1
    movementScale.Scale = 0.96
    movementStroke.Transparency = 1
    movementLabel.TextTransparency = 1
    movementDetail.TextTransparency = 1

    TweenService:Create(
        movementHint,
        TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = 0.12,
            Position = UDim2.new(0.5, 0, 1, -28),
        }
    ):Play()
    TweenService:Create(
        movementScale,
        TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
    TweenService:Create(
        movementStroke,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Transparency = 0.30 }
    ):Play()
    TweenService:Create(
        movementLabel,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0 }
    ):Play()
    TweenService:Create(
        movementDetail,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0 }
    ):Play()
end

-- Attack is introduced only when combat becomes the next meaningful action.
-- On touch, the MobileCombat button itself is the teaching surface.
-- On desktop, a compact mouse hint appears only after a short hesitation.
local attackHint = Instance.new("Frame")
attackHint.Name = "AttackHint"
attackHint.AnchorPoint = Vector2.new(0.5, 1)
attackHint.Position = UDim2.new(0.5, 0, 1, -28)
attackHint.Size = UDim2.fromOffset(260, 58)
attackHint.BackgroundColor3 = Color3.fromRGB(7, 20, 34)
attackHint.BackgroundTransparency = 1
attackHint.BorderSizePixel = 0
attackHint.Visible = false
attackHint.ZIndex = 20
attackHint.Parent = gui

local attackCorner = Instance.new("UICorner")
attackCorner.CornerRadius = UDim.new(0, 15)
attackCorner.Parent = attackHint

local attackStroke = Instance.new("UIStroke")
attackStroke.Color = Color3.fromRGB(255, 210, 105)
attackStroke.Transparency = 1
attackStroke.Thickness = 1.1
attackStroke.Parent = attackHint

local attackScale = Instance.new("UIScale")
attackScale.Name = "AttackHintScale"
attackScale.Scale = 0.96
attackScale.Parent = attackHint

local attackIcon = Instance.new("Frame")
attackIcon.Name = "MouseIcon"
attackIcon.AnchorPoint = Vector2.new(0, 0.5)
attackIcon.Position = UDim2.new(0, 12, 0.5, 0)
attackIcon.Size = UDim2.fromOffset(36, 42)
attackIcon.BackgroundColor3 = Color3.fromRGB(20, 42, 57)
attackIcon.BackgroundTransparency = 0.10
attackIcon.BorderSizePixel = 0
attackIcon.ZIndex = 21
attackIcon.Parent = attackHint

local attackIconCorner = Instance.new("UICorner")
attackIconCorner.CornerRadius = UDim.new(0, 13)
attackIconCorner.Parent = attackIcon

local mouseDivider = Instance.new("Frame")
mouseDivider.Name = "MouseDivider"
mouseDivider.Position = UDim2.new(0.5, 0, 0, 2)
mouseDivider.Size = UDim2.new(0, 1, 0, 14)
mouseDivider.BackgroundColor3 = Color3.fromRGB(119, 149, 169)
mouseDivider.BackgroundTransparency = 0.22
mouseDivider.BorderSizePixel = 0
mouseDivider.ZIndex = 22
mouseDivider.Parent = attackIcon

local mouseButton = Instance.new("Frame")
mouseButton.Name = "PrimaryButton"
mouseButton.Position = UDim2.fromOffset(3, 3)
mouseButton.Size = UDim2.new(0.5, -4, 0, 13)
mouseButton.BackgroundColor3 = Color3.fromRGB(255, 211, 105)
mouseButton.BackgroundTransparency = 0.10
mouseButton.BorderSizePixel = 0
mouseButton.ZIndex = 23
mouseButton.Parent = attackIcon

local mouseButtonCorner = Instance.new("UICorner")
mouseButtonCorner.CornerRadius = UDim.new(0, 6)
mouseButtonCorner.Parent = mouseButton

local attackLabel = Instance.new("TextLabel")
attackLabel.Name = "Label"
attackLabel.Position = UDim2.fromOffset(60, 8)
attackLabel.Size = UDim2.new(1, -72, 0, 18)
attackLabel.BackgroundTransparency = 1
attackLabel.Text = "ATAQUE"
attackLabel.TextColor3 = Color3.fromRGB(255, 219, 131)
attackLabel.TextTransparency = 1
attackLabel.Font = Enum.Font.GothamBold
attackLabel.TextSize = 10
attackLabel.TextXAlignment = Enum.TextXAlignment.Left
attackLabel.ZIndex = 21
attackLabel.Parent = attackHint

local attackDetail = Instance.new("TextLabel")
attackDetail.Name = "Detail"
attackDetail.Position = UDim2.fromOffset(60, 24)
attackDetail.Size = UDim2.new(1, -72, 0, 25)
attackDetail.BackgroundTransparency = 1
attackDetail.Text = "Clique para atacar"
attackDetail.TextColor3 = Color3.fromRGB(242, 248, 255)
attackDetail.TextTransparency = 1
attackDetail.Font = Enum.Font.GothamMedium
attackDetail.TextSize = 13
attackDetail.TextXAlignment = Enum.TextXAlignment.Left
attackDetail.ZIndex = 21
attackDetail.Parent = attackHint

local attackVisible = false
local attackSerial = 0

local function hideAttackHint()
    if not attackVisible then
        return
    end

    attackVisible = false
    attackSerial += 1
    local mine = attackSerial

    TweenService:Create(
        attackHint,
        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, 0, 1, -20),
        }
    ):Play()
    TweenService:Create(
        attackScale,
        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Scale = 0.96 }
    ):Play()
    TweenService:Create(
        attackStroke,
        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Transparency = 1 }
    ):Play()
    TweenService:Create(
        attackLabel,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1 }
    ):Play()
    TweenService:Create(
        attackDetail,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1 }
    ):Play()

    task.delay(0.14, function()
        if mine == attackSerial and not attackVisible then
            attackHint.Visible = false
        end
    end)
end

local function showAttackHint()
    if TOUCH or attackVisible then
        return
    end

    attackVisible = true
    attackSerial += 1
    attackHint.Visible = true
    attackHint.Position = UDim2.new(0.5, 0, 1, -20)
    attackHint.BackgroundTransparency = 1
    attackScale.Scale = 0.96
    attackStroke.Transparency = 1
    attackLabel.TextTransparency = 1
    attackDetail.TextTransparency = 1

    TweenService:Create(
        attackHint,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = 0.12,
            Position = UDim2.new(0.5, 0, 1, -28),
        }
    ):Play()
    TweenService:Create(
        attackScale,
        TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }
    ):Play()
    TweenService:Create(
        attackStroke,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Transparency = 0.30 }
    ):Play()
    TweenService:Create(
        attackLabel,
        TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0 }
    ):Play()
    TweenService:Create(
        attackDetail,
        TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0 }
    ):Play()
end

local serial = 0
local visible = false
local startPosition
local firstStrikeStartedAt
local movementOpportunityStartedAt
local attackOpportunityStartedAt
local nearTargetAt
local rewardStartedAt
local moveHintShown = false
local attackHintShown = false
local rewardHintShown = false
local baselineAccepted = 0
local baselineHit = 0

local function counter(name)
    return math.max(0, tonumber(player:GetAttribute(name)) or 0)
end

local function root()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function hide()
    if not visible then
        return
    end
    visible = false
    serial += 1
    local mine = serial

    TweenService:Create(
        hint,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }
    ):Play()
    TweenService:Create(
        text,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1 }
    ):Play()
    TweenService:Create(
        stroke,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Transparency = 1 }
    ):Play()

    task.delay(0.18, function()
        if mine == serial then
            hint.Visible = false
        end
    end)
end

local function show(message, seconds)
    serial += 1
    local mine = serial
    visible = true
    hint.Visible = true
    text.Text = message

    TweenService:Create(
        hint,
        TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.10 }
    ):Play()
    TweenService:Create(
        text,
        TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0 }
    ):Play()
    TweenService:Create(
        stroke,
        TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Transparency = 0.22 }
    ):Play()

    if seconds then
        task.delay(seconds, function()
            if mine == serial then
                hide()
            end
        end)
    end
end

local function firstStrikeTargetDistance()
    local playerRoot = root()
    if not playerRoot then
        return nil
    end

    for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
        if model:IsA("Model")
            and tostring(model:GetAttribute("ObjectiveId") or "") == "FirstStrike"
            and (
                model:GetAttribute("ObjectiveFocusTarget") == true
                or model:GetAttribute("RebuildProgressionTarget") == true
            )
        then
            local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
            local targetRoot = model:FindFirstChild("HumanoidRootPart", true)
                or model.PrimaryPart
            if humanoid and humanoid.Health > 0 and targetRoot then
                local delta = targetRoot.Position - playerRoot.Position
                return Vector2.new(delta.X, delta.Z).Magnitude
            end
        end
    end
    return nil
end

local function resetFirstStrike()
    firstStrikeStartedAt = os.clock()
    movementOpportunityStartedAt = nil
    attackOpportunityStartedAt = nil
    nearTargetAt = nil
    startPosition = root() and root().Position or nil
    moveHintShown = false
    attackHintShown = false
    baselineAccepted = counter("SwordServerAcceptedRequests")
    baselineHit = counter("SwordHitSerial")
    player:SetAttribute("GuidedIntroMovementLearned", false)
    player:SetAttribute("GuidedIntroMovementHintShown", false)
    player:SetAttribute("GuidedIntroAttackReady", false)
    player:SetAttribute("GuidedIntroAttackLearned", false)
    player:SetAttribute("GuidedIntroAttackHintShown", false)
    player:SetAttribute("GuidedIntroPresentationStage", "Mission")
end

local function update()
    if player:GetAttribute("GuidedIntroActive") ~= true
        or player:GetAttribute("DungeonEntryPresentationState") ~= "Playing"
    then
        hide()
        hideMovementHint()
        return
    end

    local objectiveId = tostring(Workspace:GetAttribute("DungeonObjectiveId") or "")
    local state = tostring(Workspace:GetAttribute("DungeonProgressionState") or "")
    local progress = math.max(0, tonumber(Workspace:GetAttribute("DungeonObjectiveProgress")) or 0)

    if objectiveId == "FirstStrike" and state == "ObjectiveActive" and progress <= 0 then
        if not firstStrikeStartedAt then
            resetFirstStrike()
        end

        local currentRoot = root()
        if currentRoot and not startPosition then
            startPosition = currentRoot.Position
        end

        local moved = 0
        if currentRoot and startPosition then
            local delta = currentRoot.Position - startPosition
            moved = Vector2.new(delta.X, delta.Z).Magnitude
        end

        local openingMissionReady =
            player:GetAttribute("DungeonOpeningMissionState") == "CompactReady"

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local activelyMoving = humanoid
            and humanoid.MoveDirection.Magnitude > 0.08
            or false

        local attackedEarly =
            counter("SwordServerAcceptedRequests") > baselineAccepted
            or counter("SwordHitSerial") > baselineHit

        -- The title "Derrote o Slime!" gets the player's full attention first.
        -- Only after its handoff do we begin measuring whether movement help is needed.
        if openingMissionReady and not movementOpportunityStartedAt then
            movementOpportunityStartedAt = os.clock()
            startPosition = currentRoot and currentRoot.Position or startPosition
            player:SetAttribute("GuidedIntroPresentationStage", "Observe")
        end

        local movementUnderstood =
            moved >= 1.25
            or activelyMoving
            or attackedEarly

        if movementUnderstood
            and player:GetAttribute("GuidedIntroMovementLearned") ~= true
        then
            player:SetAttribute("GuidedIntroMovementLearned", true)
            player:SetAttribute("GuidedIntroMovementLearnedAt", Workspace:GetServerTimeNow())
            player:SetAttribute("GuidedIntroPresentationStage", "MovementUnderstood")
            hideMovementHint()
        end

        if openingMissionReady
            and not movementUnderstood
            and not moveHintShown
            and movementOpportunityStartedAt
            and os.clock() - movementOpportunityStartedAt >= MOVE_HINT_DELAY
        then
            moveHintShown = true
            player:SetAttribute("GuidedIntroMovementHintShown", true)
            player:SetAttribute("GuidedIntroMovementHintShownAt", Workspace:GetServerTimeNow())
            player:SetAttribute("GuidedIntroPresentationStage", "MoveHint")
            showMovementHint()
            return
        end

        if movementUnderstood then
            hideMovementHint()
        end

        local distance = firstStrikeTargetDistance()
        local attackReady = movementUnderstood
            and distance ~= nil
            and distance <= ATTACK_READY_DISTANCE

        if attackReady then
            nearTargetAt = nearTargetAt or os.clock()
            attackOpportunityStartedAt = attackOpportunityStartedAt or os.clock()
        else
            nearTargetAt = nil
            attackOpportunityStartedAt = nil
        end

        local attacked = attackedEarly

        if attacked then
            player:SetAttribute("GuidedIntroAttackReady", true)
            if player:GetAttribute("GuidedIntroAttackLearned") ~= true then
                player:SetAttribute("GuidedIntroAttackLearned", true)
                player:SetAttribute(
                    "GuidedIntroAttackLearnedAt",
                    Workspace:GetServerTimeNow()
                )
            end
            player:SetAttribute("GuidedIntroPresentationStage", "CombatUnderstood")
            hide()
            hideAttackHint()
            return
        end

        player:SetAttribute("GuidedIntroAttackReady", attackReady)

        if attackReady then
            player:SetAttribute("GuidedIntroPresentationStage", "AttackOpportunity")
        end

        -- Touch does not get a second text card. The ATTACK button becomes the
        -- instruction itself and MobileCombat owns its delayed pulse.
        if not TOUCH
            and attackReady
            and not attackHintShown
            and attackOpportunityStartedAt
            and os.clock() - attackOpportunityStartedAt >= ATTACK_HINT_DELAY
        then
            attackHintShown = true
            player:SetAttribute("GuidedIntroAttackHintShown", true)
            player:SetAttribute(
                "GuidedIntroAttackHintShownAt",
                Workspace:GetServerTimeNow()
            )
            player:SetAttribute("GuidedIntroPresentationStage", "AttackHint")
            showAttackHint()
        elseif not attackReady then
            hideAttackHint()
        end

        return
    end

    firstStrikeStartedAt = nil
    movementOpportunityStartedAt = nil
    attackOpportunityStartedAt = nil
    nearTargetAt = nil
    hideMovementHint()
    hideAttackHint()
    player:SetAttribute("GuidedIntroAttackReady", false)

    if state == "RewardPending"
        or Workspace:GetAttribute("DungeonRewardIslandActive") == true
    then
        local pendingRound = math.max(
            0,
            math.floor(tonumber(
                Workspace:GetAttribute("DungeonRewardPendingRound")
            ) or 0)
        )
        local firstReward =
            pendingRound == 1
            and player:GetAttribute("GuidedIntroActive") == true

        -- The first reward gets its own visual reveal. Do not stack a generic
        -- tutorial message on top of "RECOMPENSA!".
        local presentationReady =
            not firstReward
            or player:GetAttribute("DungeonFirstRewardPresentationStage") == "CompactReady"

        local coreClaimed =
            Workspace:GetAttribute("DungeonRewardCoreClaimed") == true
            or player:GetAttribute("DungeonRewardCoreClaimed") == true

        if player:GetAttribute("DungeonBeginnerUpgradePresentationActive") == true
            or coreClaimed
        then
            rewardStartedAt = nil
            hide()
        elseif presentationReady then
            rewardStartedAt = rewardStartedAt or os.clock()
        else
            rewardStartedAt = nil
            hide()
        end

        if presentationReady
            and not coreClaimed
            and player:GetAttribute("DungeonBeginnerUpgradePresentationActive") ~= true
            and not rewardHintShown
            and rewardStartedAt
            and os.clock() - rewardStartedAt >= REWARD_HINT_DELAY
        then
            rewardHintShown = true
            player:SetAttribute("GuidedIntroPresentationStage", "RewardHint")
            show(
                firstReward
                    and "Abra o baú destacado."
                    or "Abra o CORE CHEST para continuar.",
                4.5
            )
        end
        return
    end

    rewardStartedAt = nil

    if math.floor(tonumber(
        Workspace:GetAttribute("DungeonLastCommittedRewardRound")
    ) or 0) >= 1 then
        player:SetAttribute("GuidedIntroPresentationStage", "Complete")
        hide()
    end
end

player:SetAttribute("GuidedIntroPresentationReady", true)
player:SetAttribute("GuidedIntroPresentationVersion", VERSION)

player.CharacterAdded:Connect(function()
    startPosition = nil
    firstStrikeStartedAt = nil
    movementOpportunityStartedAt = nil
    attackOpportunityStartedAt = nil
    hideMovementHint()
    hideAttackHint()
    player:SetAttribute("GuidedIntroAttackReady", false)
    task.defer(update)
end)

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed >= 0.10 then
        elapsed = 0
        update()
    end
end)

update()
