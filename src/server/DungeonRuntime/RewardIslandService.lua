--[[
    Infinity Islands — Rebuild Part 08
    Minimal Core-only Reward Service for Rounds 1, 2 and 3.

    One Core Chest per reward battle.
    RewardCatalog + RewardGrantService remain authoritative for the grant.
    Progression commit remains authoritative in DungeonProgressionService.
]]

local Players = game:GetService("Players")

local RewardCatalog = require(script.Parent.RewardCatalog)
local RewardGrantService = require(script.Parent.RewardGrantService)

local RewardIslandService = {}

local ROUND_ISLANDS = {
    [1] = 3,
    [2] = 7,
    [3] = 12,
}

local started = false
local options = {}
local participantSet = {}
local currentRound
local generation = 0

local function now()
    return workspace:GetServerTimeNow()
end

local function setWorldAttributes()
    workspace:SetAttribute(
        "DungeonRewardIslandActive",
        currentRound ~= nil and currentRound.Committed ~= true
    )
    workspace:SetAttribute(
        "DungeonRewardIslandRound",
        currentRound and currentRound.RoundIndex or nil
    )
    workspace:SetAttribute(
        "DungeonRewardIslandIndex",
        currentRound and currentRound.GlobalIslandIndex or nil
    )
    workspace:SetAttribute(
        "DungeonRewardRequiredChestRole",
        currentRound and "Core" or nil
    )
    workspace:SetAttribute(
        "DungeonRewardProgressionPolicy",
        "RebuildCoreOnlyUpgradeGateV1"
    )
end

local function fireClient(player, action, extra)
    local remote = options.RemoteEvent
    if not remote or not player or player.Parent ~= Players then
        return
    end

    local payload = {
        Action = action,
        Active = currentRound ~= nil and currentRound.Committed ~= true,
        RoundIndex = currentRound and currentRound.RoundIndex or nil,
        GlobalIslandIndex = currentRound and currentRound.GlobalIslandIndex or nil,
        RequiredChestRole = "Core",
        RequiredClaimComplete = currentRound
            and currentRound.ClaimedBy[player.UserId] == true
            or false,
        Committed = currentRound and currentRound.Committed == true or false,
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            payload[key] = value
        end
    end

    remote:FireClient(player, payload)
end

local function createPart(parent, name, size, cframe, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = false
    part.CanQuery = true
    part.Material = material or Enum.Material.WoodPlanks
    part.Color = color
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function createCoreChest(marker, parent, roundIndex, globalIslandIndex)
    local model = Instance.new("Model")
    model.Name = "CoreRewardChest"
    model:SetAttribute("RewardChestRole", "Core")
    model:SetAttribute("RoundIndex", roundIndex)
    model:SetAttribute("GlobalIslandIndex", globalIslandIndex)
    model:SetAttribute("RebuildRewardChest", true)
    model.Parent = parent

    local baseColor
    local metalColor
    if roundIndex == 1 then
        baseColor = Color3.fromRGB(65, 151, 218)
        metalColor = Color3.fromRGB(156, 226, 255)
    elseif roundIndex == 2 then
        baseColor = Color3.fromRGB(92, 112, 220)
        metalColor = Color3.fromRGB(188, 179, 255)
    else
        baseColor = Color3.fromRGB(172, 118, 36)
        metalColor = Color3.fromRGB(255, 218, 103)
    end

    local baseCFrame = marker.CFrame * CFrame.new(0, 1.2, 0)
    local base = createPart(
        model,
        "Base",
        Vector3.new(5.2, 2.2, 3.6),
        baseCFrame,
        baseColor
    )
    createPart(
        model,
        "Lid",
        Vector3.new(5.4, 1.1, 3.8),
        baseCFrame * CFrame.new(0, 1.65, -0.15) * CFrame.Angles(math.rad(-8), 0, 0),
        baseColor
    )
    createPart(
        model,
        "Band",
        Vector3.new(1.05, 3.45, 3.95),
        baseCFrame * CFrame.new(0, 0.75, 0),
        metalColor,
        Enum.Material.Metal
    )

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "OpenRebuildCoreReward"
    prompt.ActionText = "Abrir"
    prompt.ObjectText = string.format("Core Chest • Round %d", roundIndex)
    prompt.HoldDuration = 0.25
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt:SetAttribute("RewardChestRole", "Core")
    prompt:SetAttribute("RoundIndex", roundIndex)
    prompt:SetAttribute("ProgressionRequired", true)
    prompt.Parent = base

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RewardChestLabel"
    billboard.Adornee = base
    billboard.Size = UDim2.fromOffset(170, 38)
    billboard.StudsOffset = Vector3.new(0, 3.7, 0)
    billboard.AlwaysOnTop = false
    billboard.MaxDistance = 55
    billboard.Parent = model

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
    label.BackgroundTransparency = 0.18
    label.BorderSizePixel = 0
    label.Text = string.format("CORE CHEST • ROUND %d", roundIndex)
    label.TextColor3 = metalColor
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.Parent = billboard
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)

    model.PrimaryPart = base
    return model, prompt
end

local function beginUpgradeChoice(player)
    if not currentRound or not player then
        return false, "RewardRoundInactive"
    end

    local callback = options.BeginUpgradeChoice
    if type(callback) ~= "function" then
        return true, "UpgradeChoiceCallbackMissing"
    end

    local ok, result, reason = pcall(
        callback,
        player,
        currentRound.RoundIndex
    )
    if not ok then
        return false, tostring(result)
    end

    return result ~= false, reason
end

local function upgradeChoiceResolved(player)
    if not currentRound or not player then
        return false
    end

    local callback = options.IsUpgradeChoiceResolved
    if type(callback) ~= "function" then
        return true
    end

    local ok, resolved = pcall(
        callback,
        player,
        currentRound.RoundIndex
    )
    return ok and resolved == true
end

local function allOnlineParticipantsReady()
    if not currentRound then
        return false
    end

    local hasParticipant = false
    for userId in pairs(participantSet) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            hasParticipant = true

            if currentRound.ClaimedBy[userId] ~= true then
                return false
            end

            if not upgradeChoiceResolved(player) then
                return false
            end
        end
    end

    return hasParticipant
end

local function hasOnlineParticipantPendingClaim()
    if not currentRound then
        return false
    end

    for userId in pairs(participantSet) do
        local player = Players:GetPlayerByUserId(userId)
        if player and currentRound.ClaimedBy[userId] ~= true then
            return true
        end
    end

    return false
end


local function tryCommit()
    if not currentRound
        or currentRound.Committed
        or currentRound.CommitInProgress
        or not allOnlineParticipantsReady()
    then
        return false
    end

    local callback = options.CommitRoundReward
    if type(callback) ~= "function" then
        workspace:SetAttribute("DungeonRewardCommitError", "CommitCallbackMissing")
        return false
    end

    currentRound.CommitInProgress = true

    local metadata = {
        RoundIndex = currentRound.RoundIndex,
        GlobalIslandIndex = currentRound.GlobalIslandIndex,
        ResolvedAt = now(),
        Policy = "RebuildCoreOnlyUpgradeGateV1",
        Players = {},
    }

    for userId, claimed in pairs(currentRound.ClaimedBy) do
        local player = Players:GetPlayerByUserId(userId)
        metadata.Players[userId] = {
            CoreClaimed = claimed == true,
            GrantId = currentRound.GrantIds[userId],
            UpgradeResolved = player and upgradeChoiceResolved(player) or false,
            UpgradeId = player and player:GetAttribute("DungeonRunLastUpgradeId") or nil,
        }
    end

    local success, resultOrError = callback(currentRound.RoundIndex, metadata)
    if not success then
        currentRound.CommitInProgress = false
        workspace:SetAttribute("DungeonRewardCommitError", tostring(resultOrError))
        return false
    end

    currentRound.Committed = true
    currentRound.CommittedAt = now()
    currentRound.CommitResult = resultOrError

    if currentRound.Prompt and currentRound.Prompt.Parent then
        currentRound.Prompt.Enabled = false
    end

    local island = currentRound.Context and currentRound.Context.IslandModel
    if island and island.Parent then
        island:SetAttribute("RoundRewardActive", false)
        island:SetAttribute("RoundRewardCommitted", true)
    end

    workspace:SetAttribute("DungeonRewardCommitError", nil)
    workspace:SetAttribute("DungeonRewardCoreClaimed", true)
    workspace:SetAttribute("DungeonRewardCommittedAt", currentRound.CommittedAt)
    setWorldAttributes()

    for userId in pairs(participantSet) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            fireClient(player, "RewardRoundCommitted", {
                Commit = resultOrError,
            })
        end
    end

    return true
end

local function claimCore(player)
    if not currentRound or currentRound.Committed then
        return false, "RewardRoundInactive"
    end
    if not player or player.Parent ~= Players or not participantSet[player.UserId] then
        return false, "NotRewardParticipant"
    end

    if currentRound.ClaimedBy[player.UserId] == true then
        tryCommit()
        return true, "AlreadyClaimed"
    end

    if currentRound.Granting[player.UserId] == true then
        return false, "GrantInProgress"
    end

    currentRound.Granting[player.UserId] = true
    if currentRound.Prompt and currentRound.Prompt.Parent then
        currentRound.Prompt.Enabled = false
    end

    local bundle = RewardCatalog.Roll(
        options.SessionId,
        player.UserId,
        currentRound.RoundIndex,
        "Core"
    )

    local granted, resultOrError = RewardGrantService.GrantBundle(player, bundle)
    currentRound.Granting[player.UserId] = nil

    if not granted then
        workspace:SetAttribute("DungeonRewardGrantError", tostring(resultOrError))
        player:SetAttribute("DungeonRewardGrantError", tostring(resultOrError))

        if currentRound.Prompt and currentRound.Prompt.Parent and not currentRound.Committed then
            currentRound.Prompt.Enabled = true
        end

        fireClient(player, "RewardGrantPending", {
            ChestRole = "Core",
            Reason = tostring(resultOrError),
        })
        return false, resultOrError
    end

    currentRound.ClaimedBy[player.UserId] = true
    currentRound.GrantIds[player.UserId] = bundle.GrantId

    workspace:SetAttribute("DungeonRewardGrantError", nil)
    workspace:SetAttribute("DungeonRewardLastClaimUserId", player.UserId)
    workspace:SetAttribute("DungeonRewardCoreClaimed", true)
    player:SetAttribute("DungeonRewardCoreClaimed", true)

    -- Presentation bridge for the FIRST reward only.
    -- Use the authoritative grant result so a duplicate companion converted
    -- into coins never produces a false "NEW COMPANION" message.
    if currentRound.RoundIndex == 1 then
        local firstCompanionId
        local firstCompanionDuplicate = false
        local grantResults = type(resultOrError) == "table"
            and resultOrError.Results
            or nil

        if type(grantResults) == "table" then
            for _, rewardResult in ipairs(grantResults) do
                if type(rewardResult) == "table"
                    and rewardResult.Kind == "Companion"
                then
                    firstCompanionId = tostring(rewardResult.Id or "")
                    firstCompanionDuplicate = rewardResult.Duplicate == true
                    break
                end
            end
        end

        player:SetAttribute(
            "DungeonFirstRewardCompanionId",
            firstCompanionId ~= "" and firstCompanionId or nil
        )
        player:SetAttribute(
            "DungeonFirstRewardCompanionDuplicate",
            firstCompanionId ~= nil and firstCompanionDuplicate or nil
        )
        player:SetAttribute(
            "DungeonFirstRewardCompanionGranted",
            firstCompanionId ~= nil and not firstCompanionDuplicate or false
        )
        player:SetAttribute(
            "DungeonFirstRewardCompanionGrantResolvedAt",
            workspace:GetServerTimeNow()
        )
    end

    fireClient(player, "RewardClaimed", {
        ChestRole = "Core",
        Grant = resultOrError,
        Bundle = bundle,
    })

    local upgradeStarted, upgradeReason = beginUpgradeChoice(player)
    player:SetAttribute("DungeonRewardUpgradeChoiceStarted", upgradeStarted == true)
    player:SetAttribute(
        "DungeonRewardUpgradeChoiceStartError",
        upgradeStarted and nil or tostring(upgradeReason)
    )
    player:SetAttribute(
        "DungeonRewardUpgradeChoiceRound",
        currentRound.RoundIndex
    )

    local committed = tryCommit()

    if currentRound
        and not currentRound.Committed
        and currentRound.Prompt
        and currentRound.Prompt.Parent
    then
        currentRound.Prompt.Enabled = hasOnlineParticipantPendingClaim()
    end

    return true, committed and "Committed" or resultOrError
end

function RewardIslandService.Start(startOptions)
    if started then
        return
    end

    started = true
    options = type(startOptions) == "table" and startOptions or {}
    participantSet = {}

    for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
        local userId = math.floor(tonumber(rawUserId) or 0)
        if userId > 0 then
            participantSet[userId] = true
        end
    end

    workspace:SetAttribute("DungeonRewardServicePolicy", "RebuildCoreOnlyUpgradeGateV1")
    setWorldAttributes()
end

function RewardIslandService.Stop()
    started = false
    generation += 1

    if currentRound and currentRound.Content and currentRound.Content.Parent then
        currentRound.Content:Destroy()
    end

    currentRound = nil
    options = {}
    participantSet = {}
    setWorldAttributes()
end

function RewardIslandService.BeginRound(result, islandContext)
    if not started or type(result) ~= "table" or type(islandContext) ~= "table" then
        return false, "InvalidRewardRound"
    end

    local roundIndex = math.floor(tonumber(result.RoundIndex) or 0)
    local expectedIsland = ROUND_ISLANDS[roundIndex]
    if not expectedIsland then
        return false, "RoundNotImplemented"
    end

    local globalIslandIndex = math.floor(tonumber(result.GlobalIslandIndex) or 0)
    if globalIslandIndex ~= expectedIsland then
        return false, "WrongRewardIsland"
    end

    if currentRound and not currentRound.Committed then
        if currentRound.RoundIndex == roundIndex then
            return true, currentRound
        end
        return false, "PreviousRewardRoundActive"
    end

    local island = islandContext.IslandModel
    local markers = islandContext.ChestSpawns
    if not island or not island.Parent or not markers then
        return false, "RewardMarkersMissing"
    end

    local coreMarker = markers:FindFirstChild("RoundCoreChest")
    if not coreMarker or not coreMarker:IsA("BasePart") then
        return false, "CoreChestMarkerMissing"
    end

    generation += 1

    local oldContent = island:FindFirstChild("RebuildRoundRewardContent")
    if oldContent then
        oldContent:Destroy()
    end

    local content = Instance.new("Folder")
    content.Name = "RebuildRoundRewardContent"
    content:SetAttribute("RoundIndex", roundIndex)
    content:SetAttribute("GlobalIslandIndex", globalIslandIndex)
    content.Parent = island

    currentRound = {
        RoundIndex = roundIndex,
        GlobalIslandIndex = globalIslandIndex,
        Context = islandContext,
        Content = content,
        StartedAt = now(),
        ClaimedBy = {},
        GrantIds = {},
        Granting = {},
        Committed = false,
        CommitInProgress = false,
    }

    local chest, prompt = createCoreChest(
        coreMarker,
        content,
        roundIndex,
        globalIslandIndex
    )
    currentRound.Chest = chest
    currentRound.Prompt = prompt

    prompt.Triggered:Connect(function(player)
        claimCore(player)
    end)

    island:SetAttribute("RoundRewardActive", true)
    island:SetAttribute("RoundRewardIndex", roundIndex)
    island:SetAttribute("RoundRewardRequiredChestRole", "Core")
    island:SetAttribute("RoundRewardOptionalAutoCollect", false)

    workspace:SetAttribute("DungeonRewardCoreClaimed", false)
    workspace:SetAttribute("DungeonRewardGrantError", nil)
    workspace:SetAttribute("DungeonRewardCommitError", nil)
    setWorldAttributes()

    for userId in pairs(participantSet) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            player:SetAttribute("DungeonRewardCoreClaimed", nil)
            player:SetAttribute("DungeonRewardUpgradeChoiceStarted", false)
            player:SetAttribute("DungeonRewardUpgradeChoiceStartError", nil)
            player:SetAttribute("DungeonRewardUpgradeChoiceRound", roundIndex)

            if currentRound.RoundIndex == 1 then
                player:SetAttribute("DungeonFirstRewardCompanionId", nil)
                player:SetAttribute("DungeonFirstRewardCompanionDuplicate", nil)
                player:SetAttribute("DungeonFirstRewardCompanionGranted", false)
                player:SetAttribute("DungeonFirstRewardCompanionGrantResolvedAt", nil)
            end

            fireClient(player, "RewardRoundStarted")
        end
    end

    local monitorToken = generation
    task.spawn(function()
        while started
            and monitorToken == generation
            and currentRound
            and currentRound.RoundIndex == roundIndex
            and not currentRound.Committed
        do
            tryCommit()
            task.wait(0.20)
        end
    end)

    return true, currentRound
end

function RewardIslandService.GetSnapshot(player)
    if not currentRound then
        return { Active = false }
    end

    return {
        Active = currentRound.Committed ~= true,
        RoundIndex = currentRound.RoundIndex,
        GlobalIslandIndex = currentRound.GlobalIslandIndex,
        RequiredChestRole = "Core",
        RequiredClaimComplete = player
            and currentRound.ClaimedBy[player.UserId] == true
            or false,
        UpgradeChoiceResolved = player and upgradeChoiceResolved(player) or false,
        Committed = currentRound.Committed == true,
    }
end

function RewardIslandService.Claim(player, chestRole)
    if chestRole and chestRole ~= "Core" then
        return false, "OnlyCoreChestImplemented"
    end
    return claimCore(player)
end

return RewardIslandService
