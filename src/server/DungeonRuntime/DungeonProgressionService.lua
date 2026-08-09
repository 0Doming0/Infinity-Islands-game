--[[
    Infinity Islands — NEW PROGRESSION CORE
    Rebuild Part 03

    Implementado:
    Ilha 1 -> FirstStrike -> 1 kill
    Ilha 2 -> ClearThePath -> 3 kills
    Ilha 3 -> FirstRewardBattle -> 5 kills em 2 ondas -> Reward 1
    Ilha 4 -> SkyAmbush -> 4 kills
    Ilha 5 -> RangedThreat -> 3 ranged kills
    Ilha 6 -> BreakTheNests -> destruir 2 ninhos
    Ilha 7 -> SecondRewardBattle -> 7 kills em 2 ondas -> Reward 2
    Ilha 8 -> BreakTheGuard -> 2 cristais -> 2 Guards
    Ilha 9 -> HoldTheBeacon -> 25 segundos dentro da área
    Ilha 10 -> NestCluster -> destruir exatamente 3 ninhos
    Ilha 11 -> EliteHunt -> derrotar exatamente 1 Elite
    Ilha 12 -> FinalRewardBattle -> 3 ondas / 8 kills -> Reward 3 -> Boss

    A progressão obrigatória das 12 ilhas agora está reconstruída.
]]

local Players = game:GetService("Players")

local ObjectiveGateService = require(script.Parent.ObjectiveGateService)

local DungeonProgressionService = {}

local started = false
local generation = 0
local options = {}

local state = "Stopped"
local currentIsland = 1
local currentContext
local currentDefinition
local progress = 0
local target = 1
local objectiveActive = false
local completedObjectives = {}
local countedTargets = setmetatable({}, { __mode = "k" })
local lastRejectedAt = setmetatable({}, { __mode = "k" })
local rewardPendingRound
local round1Committed = false
local round2Committed = false
local round3Committed = false
local finalRewardCommitted = false

-- SkyAmbush should feel like an actual ambush, not an objective that begins
-- the moment the first party member touches the island boundary.
local skyAmbushArrivals = {}
local skyAmbushLandingGeneration = 0
local SKY_AMBUSH_LANDING_TIMEOUT = 8

local DEFINITIONS = {
    [1] = {
        Id = "FirstStrike",
        Type = "Kill",
        Title = "Derrote o Slime",
        Description = "Derrote o slime para liberar a saída.",
        RoundIndex = 1,
        IslandIndex = 1,
        GlobalIslandIndex = 1,
        Target = 1,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "Kill",
        SpawnProfile = "RebuildFirstStrike",
    },
    [2] = {
        Id = "ClearThePath",
        Type = "Kill",
        Title = "Limpe o Caminho",
        Description = "Derrote os 3 slimes para continuar.",
        RoundIndex = 1,
        IslandIndex = 2,
        GlobalIslandIndex = 2,
        Target = 3,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "Kill",
        SpawnProfile = "RebuildClearThePath",
    },
    [3] = {
        Id = "FirstRewardBattle",
        Type = "Kill",
        Title = "Vença as 2 Ondas",
        Description = "Derrote as duas ondas para concluir o primeiro desafio.",
        RoundIndex = 1,
        IslandIndex = 3,
        GlobalIslandIndex = 3,
        Target = 5,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "WaveBattle",
        SpawnProfile = "RebuildFirstRewardBattle",
    },
    [4] = {
        Id = "SkyAmbush",
        Type = "Kill",
        Title = "Emboscada!",
        Description = "Derrote os 4 slimes que cercaram a ilha.",
        RoundIndex = 2,
        IslandIndex = 1,
        GlobalIslandIndex = 4,
        Target = 4,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "Ambush",
        SpawnProfile = "RebuildSkyAmbush",
    },
    [5] = {
        Id = "RangedThreat",
        Type = "Kill",
        Title = "Elimine os Atiradores",
        Description = "Derrote os 3 slimes ranged para liberar a rota.",
        RoundIndex = 2,
        IslandIndex = 2,
        GlobalIslandIndex = 5,
        Target = 3,
        RequiredRole = "Ranged",
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "KillRole",
        SpawnProfile = "RebuildRangedThreat",
    },
    [6] = {
        Id = "BreakTheNests",
        Type = "Destroy",
        Title = "Destrua os Ninhos",
        Description = "Destrua os 2 ninhos de slime para liberar a rota.",
        RoundIndex = 2,
        IslandIndex = 3,
        GlobalIslandIndex = 6,
        Target = 2,
        ProgressEvent = "NestDestroyed",
        ObjectiveKind = "DestroyNests",
        SpawnProfile = "RebuildBreakTheNests",
    },
    [7] = {
        Id = "SecondRewardBattle",
        Type = "Kill",
        Title = "Vença as 2 Ondas",
        Description = "Derrote as duas ondas e abra o Core Chest.",
        RoundIndex = 2,
        IslandIndex = 4,
        GlobalIslandIndex = 7,
        Target = 7,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "WaveBattle",
        SpawnProfile = "RebuildSecondRewardBattle",
    },
    [8] = {
        Id = "BreakTheGuard",
        Type = "Kill",
        Title = "Quebre a Proteção",
        Description = "Destrua os 2 cristais e depois derrote os 2 Guards.",
        RoundIndex = 3,
        IslandIndex = 1,
        GlobalIslandIndex = 8,
        Target = 2,
        RequiredRole = "Guard",
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "GuardWards",
        SpawnProfile = "RebuildBreakTheGuard",
    },
    [9] = {
        Id = "HoldTheBeacon",
        Type = "Hold",
        Title = "Defenda o Farol",
        Description = "Permaneça na área do farol por 25 segundos.",
        RoundIndex = 3,
        IslandIndex = 2,
        GlobalIslandIndex = 9,
        Target = 25,
        ProgressEvent = "BeaconHoldSeconds",
        ObjectiveKind = "HoldZone",
        SpawnProfile = "RebuildHoldTheBeacon",
    },
    [10] = {
        Id = "NestCluster",
        Type = "Destroy",
        Title = "Destrua a Colônia",
        Description = "Destrua os 3 ninhos para liberar a rota.",
        RoundIndex = 3,
        IslandIndex = 3,
        GlobalIslandIndex = 10,
        Target = 3,
        ProgressEvent = "NestDestroyed",
        ObjectiveKind = "DestroyNests",
        SpawnProfile = "RebuildNestCluster",
    },
    [11] = {
        Id = "EliteHunt",
        Type = "Kill",
        Title = "Derrote o Elite",
        Description = "Derrote o Elite para abrir o caminho final.",
        RoundIndex = 3,
        IslandIndex = 4,
        GlobalIslandIndex = 11,
        Target = 1,
        RequiredRole = "Elite",
        RequireElite = true,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "EliteHunt",
        SpawnProfile = "RebuildEliteHunt",
    },
    [12] = {
        Id = "FinalRewardBattle",
        Type = "Kill",
        Title = "Vença as 3 Ondas Finais",
        Description = "Derrote as 3 ondas e abra o Core Chest final.",
        RoundIndex = 3,
        IslandIndex = 5,
        GlobalIslandIndex = 12,
        Target = 8,
        ProgressEvent = "EnemyDefeated",
        ObjectiveKind = "WaveBattle",
        SpawnProfile = "RebuildFinalRewardBattle",
        IsFinalObjective = true,
    },
}

local MAX_IMPLEMENTED_ISLAND = 12

local function now()
    return workspace:GetServerTimeNow()
end

local function setAttribute(name, value)
    workspace:SetAttribute(name, value)
end

local function setState(nextState)
    state = nextState
    setAttribute("DungeonProgressionState", state)
    setAttribute("DungeonObjectiveSequenceState", state)
    setAttribute("DungeonRoundProgressState", state)
end

local function completedCount()
    local count = 0
    for _, value in pairs(completedObjectives) do
        if value == true then
            count += 1
        end
    end
    return count
end

local function publish()
    setAttribute("DungeonProgressionReady", started)
    setAttribute("DungeonProgressionVersion", "RebuildCoreV13")
    setAttribute("DungeonCurrentObjectiveIsland", currentIsland)
    setAttribute(
        "DungeonCurrentRoundIndex",
        currentDefinition and currentDefinition.RoundIndex or (round2Committed and 3 or (round1Committed and 2 or 1))
    )

    local completed = completedObjectives[currentIsland] == true
    setAttribute(
        "DungeonObjectiveState",
        completed and "Completed"
            or objectiveActive and "Active"
            or "Inactive"
    )
    setAttribute("DungeonObjectiveId", currentDefinition and currentDefinition.Id or nil)
    setAttribute("DungeonObjectiveType", currentDefinition and currentDefinition.Type or nil)
    setAttribute("DungeonObjectiveTitle", currentDefinition and currentDefinition.Title or nil)
    setAttribute("DungeonObjectiveDescription", currentDefinition and currentDefinition.Description or nil)
    setAttribute("DungeonObjectiveRoundIndex", currentDefinition and currentDefinition.RoundIndex or nil)
    setAttribute("DungeonObjectiveIslandIndex", currentDefinition and currentDefinition.IslandIndex or nil)
    setAttribute("DungeonObjectiveGlobalIslandIndex", currentDefinition and currentDefinition.GlobalIslandIndex or nil)
    setAttribute("DungeonObjectiveProgress", progress)
    setAttribute("DungeonObjectiveTarget", target)

    setAttribute("DungeonCompletedObjectiveCount", completedCount())
    setAttribute(
        "DungeonHighestCompletedRound",
        round3Committed and 3 or (round2Committed and 2 or (round1Committed and 1 or 0))
    )
    setAttribute("DungeonRewardPendingRound", rewardPendingRound)
    setAttribute(
        "DungeonCurrentIslandIsRoundExit",
        currentIsland == 3 or currentIsland == 7 or currentIsland == 12
    )
    setAttribute(
        "DungeonCurrentRoundExitCommitted",
        (currentIsland == 3 and round1Committed)
            or (currentIsland == 7 and round2Committed)
            or (currentIsland == 12 and round3Committed)
            or false
    )
    setAttribute("DungeonFinalRewardCommitted", finalRewardCommitted)
end

local function setGateLocked(locked, reason)
    setAttribute("DungeonObjectiveExitLocked", locked == true)

    if currentContext then
        local ok, result = pcall(
            ObjectiveGateService.Apply,
            currentContext,
            locked == true,
            reason
        )
        if not ok then
            warn("[DungeonProgressionService] ObjectiveGateService.Apply falhou: " .. tostring(result))
            setAttribute("DungeonProgressionGateError", tostring(result))
            return false
        end
    end
    return true
end

local function setWaypoint(instance)
    if not instance or not instance.Parent then
        return false
    end

    local position
    if instance:IsA("BasePart") then
        position = instance.Position
    elseif instance:IsA("Model") then
        position = instance:GetPivot().Position
    end

    if not position then
        return false
    end

    setAttribute("DungeonObjectiveWaypointPosition", position)
    setAttribute("DungeonObjectiveWaypointTarget", instance:GetFullName())
    setAttribute(
        "DungeonObjectiveWaypointSerial",
        (tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
    )
    return true
end

local function safeCallback(name, ...)
    local callback = options[name]
    if type(callback) ~= "function" then
        return true
    end

    local ok, result = pcall(callback, ...)
    if not ok then
        warn(string.format("[DungeonProgressionService] %s falhou: %s", name, tostring(result)))
        setAttribute("DungeonProgressionCallbackError", name .. ": " .. tostring(result))
        return false
    end
    return result ~= false
end

local function getContext(index)
    if type(options.GetIslandContext) ~= "function" then
        return nil
    end
    local ok, result = pcall(options.GetIslandContext, index)
    return ok and result or nil
end

local function currentSnapshot()
    local completed = completedObjectives[currentIsland] == true
    return {
        Started = started,
        State = state,
        Id = currentDefinition and currentDefinition.Id or nil,
        Type = currentDefinition and currentDefinition.Type or nil,
        Title = currentDefinition and currentDefinition.Title or nil,
        Description = currentDefinition and currentDefinition.Description or nil,
        CurrentObjective = currentDefinition and table.clone(currentDefinition) or nil,
        CurrentGlobalIslandIndex = currentIsland,
        CurrentRoundIndex = currentDefinition and currentDefinition.RoundIndex or (round2Committed and 3 or (round1Committed and 2 or 1)),
        GlobalIslandIndex = currentDefinition and currentDefinition.GlobalIslandIndex or nil,
        RoundIndex = currentDefinition and currentDefinition.RoundIndex or nil,
        IslandIndex = currentDefinition and currentDefinition.IslandIndex or nil,
        Progress = progress,
        Target = target,
        Completed = completed,
        RewardPendingRound = rewardPendingRound,
        HighestCompletedRound = round3Committed and 3
            or (round2Committed and 2 or (round1Committed and 1 or 0)),
        CompletedRounds = {
            [1] = round1Committed == true,
            [2] = round2Committed == true,
            [3] = round3Committed == true,
        },
        CurrentIslandIsRoundExit = currentIsland == 3
            or currentIsland == 7
            or currentIsland == 12,
        RoundCompleted = (currentIsland == 3 and round1Committed)
            or (currentIsland == 7 and round2Committed)
            or (currentIsland == 12 and round3Committed)
            or false,
        FinalRewardCommitted = finalRewardCommitted,
        IslandContext = currentContext,
        ExitLocked = workspace:GetAttribute("DungeonObjectiveExitLocked") == true,
        CompletedCount = completedCount(),
    }
end

local function restorePlayer(player)
    local context = currentContext or getContext(currentIsland)
    local safeSpawn = context and context.SafeSpawn
    local character = player and player.Character

    if safeSpawn and safeSpawn.Parent and character and character.Parent then
        task.defer(function()
            if character.Parent and safeSpawn.Parent then
                character:PivotTo(safeSpawn.CFrame * CFrame.new(0, 3, 0))
            end
        end)
    end

    if context then
        player:SetAttribute("CurrentIslandKey", context.Key)
        player:SetAttribute("CurrentGlobalIslandIndex", currentIsland)
        player:SetAttribute(
            "CurrentRoundIndex",
            currentDefinition and currentDefinition.RoundIndex or (round2Committed and 3 or (round1Committed and 2 or 1))
        )
        player:SetAttribute(
            "CurrentRouteIslandIndex",
            currentDefinition and currentDefinition.IslandIndex or currentIsland
        )
        player:SetAttribute("CurrentIslandIsOptional", false)
    end
end

local startObjective

local function skyAmbushEligiblePlayers()
    local result = {}

    for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
        local userId = math.floor(tonumber(rawUserId) or 0)
        local player = userId > 0 and Players:GetPlayerByUserId(userId) or nil

        if player and player.Parent == Players then
            local lifeState = tostring(player:GetAttribute("DungeonLifeState") or "")
            local eliminated = player:GetAttribute("DungeonEliminated") == true
                or lifeState == "Eliminated"
                or lifeState == "Spectating"

            if not eliminated then
                table.insert(result, player)
            end
        end
    end

    return result
end

local function publishSkyAmbushLanding(stateName)
    local eligible = skyAmbushEligiblePlayers()
    local arrived = 0

    for _, participant in ipairs(eligible) do
        if skyAmbushArrivals[participant.UserId] == true then
            arrived += 1
        end
    end

    setAttribute("DungeonSkyAmbushLandingState", stateName)
    setAttribute("DungeonSkyAmbushLandingExpected", #eligible)
    setAttribute("DungeonSkyAmbushLandingArrived", arrived)
    setAttribute("DungeonSkyAmbushLandingTimeoutSeconds", SKY_AMBUSH_LANDING_TIMEOUT)

    return arrived, #eligible
end

local function markSkyAmbushArrival(player)
    if not player or player.Parent ~= Players then
        return
    end

    skyAmbushArrivals[player.UserId] = true
    player:SetAttribute("DungeonSkyAmbushLanded", true)
    player:SetAttribute("DungeonSkyAmbushLandedAt", now())
    player:SetAttribute("DungeonRebuildReachedIsland4", true)
end

local function startSkyAmbushLandingWorker(context)
    if workspace:GetAttribute("DungeonSkyAmbushLandingState") == "Waiting" then
        publishSkyAmbushLanding("Waiting")
        return
    end

    skyAmbushLandingGeneration += 1
    local token = skyAmbushLandingGeneration
    local startedAt = now()

    setAttribute("DungeonSkyAmbushLandingStartedAt", startedAt)
    setAttribute("DungeonSkyAmbushLandingTimedOut", false)
    publishSkyAmbushLanding("Waiting")

    task.spawn(function()
        while started
            and token == skyAmbushLandingGeneration
            and currentIsland == 3
            and completedObjectives[3] == true
            and round1Committed
        do
            local arrived, expected = publishSkyAmbushLanding("Waiting")

            if arrived > 0 and arrived >= math.max(1, expected) then
                setAttribute("DungeonSkyAmbushAllLandedAt", now())
                setAttribute("DungeonSkyAmbushLandingState", "AllLanded")

                -- Tiny beat so the last landing settles before the warning owns focus.
                task.wait(0.12)

                if started
                    and token == skyAmbushLandingGeneration
                    and currentIsland == 3
                then
                    setAttribute("DungeonRebuildPart03Validated", true)
                    setAttribute("DungeonRebuildPart03ValidatedAt", now())
                    setAttribute("DungeonRebuildPart04Validated", true)
                    setAttribute("DungeonRebuildPart04ValidatedAt", now())

                    local objectiveStarted, objectiveResult =
                        startObjective(4, context or getContext(4))

                    if objectiveStarted then
                        setAttribute("DungeonSkyAmbushLandingState", "AmbushStarted")
                        setAttribute("DungeonSkyAmbushObjectiveStartedAt", now())
                        setAttribute("DungeonSkyAmbushStartError", nil)
                    else
                        setAttribute("DungeonSkyAmbushLandingState", "StartFailed")
                        setAttribute("DungeonSkyAmbushStartError", tostring(objectiveResult))
                    end
                end
                return
            end

            if now() - startedAt >= SKY_AMBUSH_LANDING_TIMEOUT and arrived > 0 then
                -- Fail-safe only. A connected player stuck before the entry must
                -- not softlock the whole run forever.
                setAttribute("DungeonSkyAmbushLandingTimedOut", true)
                setAttribute("DungeonSkyAmbushLandingState", "Timeout")
                setAttribute("DungeonSkyAmbushLandingTimeoutAt", now())

                task.wait(0.12)

                if started
                    and token == skyAmbushLandingGeneration
                    and currentIsland == 3
                then
                    setAttribute("DungeonRebuildPart03Validated", true)
                    setAttribute("DungeonRebuildPart03ValidatedAt", now())
                    setAttribute("DungeonRebuildPart04Validated", true)
                    setAttribute("DungeonRebuildPart04ValidatedAt", now())

                    local objectiveStarted, objectiveResult =
                        startObjective(4, context or getContext(4))

                    if objectiveStarted then
                        setAttribute("DungeonSkyAmbushLandingState", "AmbushStarted")
                        setAttribute("DungeonSkyAmbushObjectiveStartedAt", now())
                        setAttribute("DungeonSkyAmbushStartError", nil)
                    else
                        setAttribute("DungeonSkyAmbushLandingState", "StartFailed")
                        setAttribute("DungeonSkyAmbushStartError", tostring(objectiveResult))
                    end
                end
                return
            end

            task.wait(0.15)
        end
    end)
end

local function reject(player, requestedIndex, reason)
    if not player or player.Parent ~= Players then
        return false, reason
    end

    local timestamp = now()
    if timestamp - (lastRejectedAt[player] or 0) >= 0.5 then
        lastRejectedAt[player] = timestamp
        player:SetAttribute("DungeonRouteRejectedReason", reason)
        player:SetAttribute("DungeonRouteRejectedIsland", requestedIndex)
        player:SetAttribute("DungeonRouteRejectedAt", timestamp)
        restorePlayer(player)
        safeCallback("OnRouteRejected", player, requestedIndex, reason, currentIsland)
    end
    return false, reason
end

startObjective = function(index, context)
    local definition = DEFINITIONS[index]
    if not definition then
        return false, "ObjectiveNotImplemented"
    end
    if type(context) ~= "table" or not context.IslandModel then
        return false, "ObjectiveIslandContextMissing"
    end

    currentIsland = index
    currentContext = context
    currentDefinition = table.clone(definition)
    progress = 0
    target = definition.Target
    objectiveActive = true
    countedTargets = setmetatable({}, { __mode = "k" })

    setState("ObjectiveActive")
    setGateLocked(true, definition.Id .. "Active")
    setAttribute("DungeonObjectiveStartedAt", now())
    setAttribute("DungeonObjectiveLastProgressAt", now())
    setAttribute("DungeonObjectiveWaypointEscalated", false)
    setAttribute("DungeonProgressionLastSignal", nil)
    setAttribute("DungeonProgressionLastSignalAccepted", nil)
    setAttribute("DungeonProgressionLastSignalReason", nil)

    if context.ObjectiveAnchor then
        setWaypoint(context.ObjectiveAnchor)
    elseif context.SafeSpawn then
        setWaypoint(context.SafeSpawn)
    end

    publish()

    if type(options.RequestRouteThrough) == "function" then
        pcall(options.RequestRouteThrough, math.min(MAX_IMPLEMENTED_ISLAND + 1, index + 1))
    end

    safeCallback(
        "OnObjectiveStarted",
        table.clone(currentDefinition),
        context,
        currentSnapshot()
    )
    return true, currentSnapshot()
end

local function completeCurrentObjective()
    if not currentDefinition or completedObjectives[currentIsland] == true then
        return true
    end

    objectiveActive = false
    completedObjectives[currentIsland] = true
    progress = target

    setState("ObjectiveCompleted")
    setAttribute("DungeonObjectiveCompletedAt", now())
    setAttribute("DungeonObjectiveCompletionReason", currentDefinition.Id .. "Completed")
    setAttribute("DungeonObjectiveLastProgressAt", now())
    publish()

    local completedSnapshot = currentSnapshot()
    safeCallback("OnObjectiveCompleted", completedSnapshot, currentContext)

    -- Reward battles do not unlock travel by themselves.
    -- The corresponding Core Chest must commit the round first.
    local rewardRound
    if currentIsland == 3 then
        rewardRound = 1
    elseif currentIsland == 7 then
        rewardRound = 2
    elseif currentIsland == 12 then
        rewardRound = 3
    end

    if rewardRound then
        rewardPendingRound = rewardRound
        setGateLocked(true, string.format("Round%dRewardPending", rewardRound))
        setState("RewardPending")
        setAttribute("DungeonRoundRewardPending", true)
        setAttribute("DungeonRoundRewardIndex", rewardRound)
        setAttribute("DungeonRoundRewardIsland", currentIsland)
        publish()

        local result = {
            ObjectiveId = currentDefinition.Id,
            GlobalIslandIndex = currentIsland,
            RoundIndex = rewardRound,
            IsRewardIsland = true,
            IsRoundExit = true,
            RoundCompleted = false,
            IsFinalObjective = false,
        }

        local startedReward = safeCallback(
            "OnRoundRewardPending",
            result,
            currentContext,
            completedSnapshot
        )
        if not startedReward then
            setAttribute(
                "DungeonRebuildRewardStartError",
                string.format("Round%d_OnRoundRewardPendingFailed", rewardRound)
            )
        end
        return true
    end

    if currentContext and currentContext.Exit then
        setWaypoint(currentContext.Exit)
    end

    task.delay(0.35, function()
        if not started
            or not currentDefinition
            or completedObjectives[currentIsland] ~= true
        then
            return
        end

        setGateLocked(false, currentDefinition.Id .. "Completed")
        setState("TravelUnlocked")
        publish()
    end)

    return true
end

local function autoStartWorker(token)
    task.spawn(function()
        while started and generation == token and currentDefinition == nil do
            local context = getContext(1)
            if context and context.IslandModel and context.IslandModel.Parent then
                task.wait(0.35)
                if started and generation == token and currentDefinition == nil then
                    startObjective(1, context)
                end
                return
            end
            task.wait(0.20)
        end
    end)
end

function DungeonProgressionService.Start(startOptions)
    if started then
        return
    end

    started = true
    generation += 1
    options = type(startOptions) == "table" and startOptions or {}

    state = "WaitingForIsland1"
    currentIsland = 1
    currentContext = nil
    currentDefinition = nil
    progress = 0
    target = 1
    objectiveActive = false
    completedObjectives = {}
    countedTargets = setmetatable({}, { __mode = "k" })
    lastRejectedAt = setmetatable({}, { __mode = "k" })

    rewardPendingRound = nil
    round1Committed = false
    round2Committed = false
    round3Committed = false
    finalRewardCommitted = false

    skyAmbushArrivals = {}
    skyAmbushLandingGeneration += 1
    setAttribute("DungeonSkyAmbushLandingState", "Idle")
    setAttribute("DungeonSkyAmbushLandingExpected", 0)
    setAttribute("DungeonSkyAmbushLandingArrived", 0)
    setAttribute("DungeonSkyAmbushLandingTimedOut", false)
    setAttribute("DungeonSkyAmbushLandingStartedAt", nil)
    setAttribute("DungeonSkyAmbushAllLandedAt", nil)
    setAttribute("DungeonSkyAmbushLandingTimeoutAt", nil)

    setAttribute("DungeonLegacyObjectiveSystemDisabled", true)
    setAttribute("DungeonRebuildPhase", "Part13_Island12_FinalReward_Boss")
    setAttribute("DungeonRebuildPart01Validated", false)
    setAttribute("DungeonRebuildPart02Validated", false)
    setAttribute("DungeonRebuildPart03Validated", false)
    setAttribute("DungeonRebuildPart04Validated", false)
    setAttribute("DungeonRebuildPart05Validated", false)
    setAttribute("DungeonRebuildPart06Validated", false)
    setAttribute("DungeonRebuildPart07Validated", false)
    setAttribute("DungeonRebuildPart08Validated", false)
    setAttribute("DungeonRebuildPart09Validated", false)
    setAttribute("DungeonRebuildPart10Validated", false)
    setAttribute("DungeonRebuildPart11Validated", false)
    setAttribute("DungeonRebuildPart12Validated", false)
    setAttribute("DungeonRebuildPart13Validated", false)
    setAttribute("DungeonRoundRewardPending", false)
    setAttribute("DungeonRoundRewardIndex", nil)
    setAttribute("DungeonRoundRewardIsland", nil)

    setState("WaitingForIsland1")
    publish()
    autoStartWorker(generation)
end

function DungeonProgressionService.Stop()
    if not started then
        return
    end

    started = false
    generation += 1
    skyAmbushLandingGeneration += 1

    if currentContext then
        pcall(ObjectiveGateService.Apply, currentContext, false, "ProgressionStopped")
    end

    options = {}
    currentContext = nil
    currentDefinition = nil
    objectiveActive = false
    setState("Stopped")
    publish()
end

function DungeonProgressionService.HandleIslandEntered(player, context)
    if not started or not player or player.Parent ~= Players or type(context) ~= "table" then
        return false, "InvalidRouteEntry"
    end

    if context.IsOptionalRoute == true or context.GlobalIslandIndex == nil then
        return reject(player, currentIsland, "OptionalRoutesDisabledDuringRebuild")
    end

    if context.IsBossSanctuary == true then
        if finalRewardCommitted and round3Committed then
            setState("BossSanctuaryUnlocked")
            setAttribute("DungeonRebuildPart13Validated", true)
            setAttribute("DungeonRebuildPart13ValidatedAt", now())
            player:SetAttribute("DungeonRebuildReachedBoss", true)
            publish()
            return true, "BossSanctuaryUnlocked"
        end
        return reject(player, 13, "BossSanctuaryLocked")
    end

    local requestedIndex = math.floor(tonumber(context.GlobalIslandIndex) or 0)
    if requestedIndex <= 0 then
        return false, "InvalidGlobalIslandIndex"
    end

    if requestedIndex < currentIsland then
        return true, "BacktrackingAllowed"
    end

    if requestedIndex == currentIsland then
        currentContext = context

        if requestedIndex == 4 then
            markSkyAmbushArrival(player)
        end

        if not currentDefinition and DEFINITIONS[requestedIndex] then
            startObjective(requestedIndex, context)
        end
        return true, completedObjectives[requestedIndex] and "ObjectiveCompleted" or "ObjectiveActive"
    end

    if requestedIndex > currentIsland + 1 then
        return reject(player, requestedIndex, "ObjectiveSequenceSkipped")
    end

    if completedObjectives[currentIsland] ~= true then
        return reject(player, requestedIndex, "PreviousObjectiveIncomplete")
    end

    -- Entrar na Ilha 4 inicia o Round 2 somente depois do Core Chest do Round 1.
    if requestedIndex <= MAX_IMPLEMENTED_ISLAND then
        if requestedIndex == 4 and not round1Committed then
            return reject(player, requestedIndex, "Round1RewardPending")
        elseif requestedIndex == 8 and not round2Committed then
            return reject(player, requestedIndex, "Round2RewardPending")
        end

        if requestedIndex == 4 and currentIsland == 3 then
            markSkyAmbushArrival(player)
            startSkyAmbushLandingWorker(context)
            return true, "AwaitingPartyLanding"
        end

        if currentIsland == 1 and requestedIndex == 2 then
            setAttribute("DungeonRebuildPart01Validated", true)
            setAttribute("DungeonRebuildPart01ValidatedAt", now())
        elseif currentIsland == 2 and requestedIndex == 3 then
            setAttribute("DungeonRebuildPart02Validated", true)
            setAttribute("DungeonRebuildPart02ValidatedAt", now())
        elseif currentIsland == 3 and requestedIndex == 4 then
            setAttribute("DungeonRebuildPart03Validated", true)
            setAttribute("DungeonRebuildPart03ValidatedAt", now())
            setAttribute("DungeonRebuildPart04Validated", true)
            setAttribute("DungeonRebuildPart04ValidatedAt", now())
        elseif currentIsland == 4 and requestedIndex == 5 then
            setAttribute("DungeonRebuildPart05Validated", true)
            setAttribute("DungeonRebuildPart05ValidatedAt", now())
        elseif currentIsland == 5 and requestedIndex == 6 then
            setAttribute("DungeonRebuildPart06Validated", true)
            setAttribute("DungeonRebuildPart06ValidatedAt", now())
        elseif currentIsland == 6 and requestedIndex == 7 then
            setAttribute("DungeonRebuildPart07Validated", true)
            setAttribute("DungeonRebuildPart07ValidatedAt", now())
        elseif currentIsland == 7 and requestedIndex == 8 then
            setAttribute("DungeonRebuildPart08Validated", true)
            setAttribute("DungeonRebuildPart08ValidatedAt", now())
        elseif currentIsland == 8 and requestedIndex == 9 then
            setAttribute("DungeonRebuildPart09Validated", true)
            setAttribute("DungeonRebuildPart09ValidatedAt", now())
        elseif currentIsland == 9 and requestedIndex == 10 then
            setAttribute("DungeonRebuildPart10Validated", true)
            setAttribute("DungeonRebuildPart10ValidatedAt", now())
        elseif currentIsland == 10 and requestedIndex == 11 then
            setAttribute("DungeonRebuildPart11Validated", true)
            setAttribute("DungeonRebuildPart11ValidatedAt", now())
        elseif currentIsland == 11 and requestedIndex == 12 then
            setAttribute("DungeonRebuildPart12Validated", true)
            setAttribute("DungeonRebuildPart12ValidatedAt", now())
        end

        player:SetAttribute("DungeonRebuildReachedIsland" .. tostring(requestedIndex), true)
        return startObjective(requestedIndex, context)
    end

    -- There is no normal Island 13. After Island 12 only the Boss Sanctuary is valid.
    return reject(player, requestedIndex, "FinalRouteRequiresBossSanctuary")
end

function DungeonProgressionService.ReportEnemyDefeated(payload)
    payload = type(payload) == "table" and payload or {}

    setAttribute("DungeonProgressionLastSignal", "EnemyDefeated")
    setAttribute("DungeonProgressionLastSignalAt", now())

    if not started or not objectiveActive or not currentDefinition then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "NoActiveObjective")
        return false, "NoActiveObjective"
    end

    local targetModel = payload.Target
    if typeof(targetModel) ~= "Instance" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "MissingTarget")
        return false, "MissingTarget"
    end

    if countedTargets[targetModel] == true
        or targetModel:GetAttribute("RebuildProgressionCounted") == true
    then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "DuplicateTarget")
        return false, "DuplicateTarget"
    end

    if targetModel:GetAttribute("ObjectiveSpawned") ~= true then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "NotObjectiveSpawned")
        return false, "NotObjectiveSpawned"
    end

    if tostring(targetModel:GetAttribute("ObjectiveId") or "") ~= currentDefinition.Id then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongObjectiveId")
        return false, "WrongObjectiveId"
    end

    if currentDefinition.RequiredRole then
        local actualRole = tostring(
            payload.MonsterRole or targetModel:GetAttribute("MonsterRole") or ""
        )
        if string.lower(actualRole) ~= string.lower(currentDefinition.RequiredRole) then
            setAttribute("DungeonProgressionLastSignalAccepted", false)
            setAttribute("DungeonProgressionLastSignalReason", "WrongMonsterRole")
            return false, "WrongMonsterRole"
        end
    end

    if currentDefinition.RequireElite == true
        and payload.IsElite ~= true
        and targetModel:GetAttribute("IsElite") ~= true
    then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "TargetNotElite")
        return false, "TargetNotElite"
    end

    local islandIndex = math.floor(tonumber(
        payload.GlobalIslandIndex or targetModel:GetAttribute("GlobalIslandIndex")
    ) or 0)

    if islandIndex ~= currentIsland then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongIsland")
        return false, "WrongIsland"
    end

    countedTargets[targetModel] = true
    targetModel:SetAttribute("RebuildProgressionCounted", true)

    progress = math.min(target, progress + 1)
    setAttribute("DungeonObjectiveProgress", progress)
    setAttribute("DungeonObjectiveLastProgressAt", now())
    setAttribute("DungeonProgressionLastSignalAccepted", true)
    setAttribute("DungeonProgressionLastSignalReason", "Accepted")
    setAttribute("DungeonProgressionAcceptedKillCount", progress)
    publish()

    if progress >= target then
        completeCurrentObjective()
    end

    return true, "Accepted"
end

function DungeonProgressionService.ReportNestDestroyed(payload)
    payload = type(payload) == "table" and payload or {}

    setAttribute("DungeonProgressionLastSignal", "NestDestroyed")
    setAttribute("DungeonProgressionLastSignalAt", now())

    if not started or not objectiveActive or not currentDefinition then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "NoActiveObjective")
        return false, "NoActiveObjective"
    end

    if currentDefinition.ProgressEvent ~= "NestDestroyed" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongProgressEvent")
        return false, "WrongProgressEvent"
    end

    local targetModel = payload.Target
    if typeof(targetModel) ~= "Instance" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "MissingTarget")
        return false, "MissingTarget"
    end

    if countedTargets[targetModel] == true
        or targetModel:GetAttribute("RebuildProgressionCounted") == true
    then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "DuplicateTarget")
        return false, "DuplicateTarget"
    end

    if targetModel:GetAttribute("ObjectiveActorType") ~= "Nest" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongActorType")
        return false, "WrongActorType"
    end

    if tostring(targetModel:GetAttribute("ObjectiveId") or "") ~= currentDefinition.Id then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongObjectiveId")
        return false, "WrongObjectiveId"
    end

    local islandIndex = math.floor(tonumber(
        payload.GlobalIslandIndex or targetModel:GetAttribute("GlobalIslandIndex")
    ) or 0)

    if islandIndex ~= currentIsland then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongIsland")
        return false, "WrongIsland"
    end

    countedTargets[targetModel] = true
    targetModel:SetAttribute("RebuildProgressionCounted", true)
    targetModel:SetAttribute("ObjectiveTargetCompleted", true)

    progress = math.min(target, progress + 1)
    setAttribute("DungeonObjectiveProgress", progress)
    setAttribute("DungeonObjectiveLastProgressAt", now())
    setAttribute("DungeonProgressionLastSignalAccepted", true)
    setAttribute("DungeonProgressionLastSignalReason", "Accepted")
    setAttribute("DungeonProgressionAcceptedNestCount", progress)
    publish()

    if progress >= target then
        completeCurrentObjective()
    end

    return true, "Accepted"
end

function DungeonProgressionService.ReportBeaconHoldSeconds(payload)
    payload = type(payload) == "table" and payload or {}

    setAttribute("DungeonProgressionLastSignal", "BeaconHoldSeconds")
    setAttribute("DungeonProgressionLastSignalAt", now())

    if not started or not objectiveActive or not currentDefinition then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "NoActiveObjective")
        return false, "NoActiveObjective"
    end

    if currentDefinition.ProgressEvent ~= "BeaconHoldSeconds" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongProgressEvent")
        return false, "WrongProgressEvent"
    end

    local beacon = payload.Target
    if typeof(beacon) ~= "Instance" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "MissingTarget")
        return false, "MissingTarget"
    end

    if beacon:GetAttribute("ObjectiveActorType") ~= "Beacon" then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongActorType")
        return false, "WrongActorType"
    end

    if tostring(beacon:GetAttribute("ObjectiveId") or "") ~= currentDefinition.Id then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongObjectiveId")
        return false, "WrongObjectiveId"
    end

    local islandIndex = math.floor(tonumber(
        payload.GlobalIslandIndex or beacon:GetAttribute("GlobalIslandIndex")
    ) or 0)
    if islandIndex ~= currentIsland then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "WrongIsland")
        return false, "WrongIsland"
    end

    if beacon:GetAttribute("BeaconActive") ~= true then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "BeaconNotOccupied")
        return false, "BeaconNotOccupied"
    end

    local amount = math.max(0, math.floor(tonumber(payload.Amount) or 0))
    if amount <= 0 then
        setAttribute("DungeonProgressionLastSignalAccepted", false)
        setAttribute("DungeonProgressionLastSignalReason", "InvalidAmount")
        return false, "InvalidAmount"
    end

    local remaining = math.max(0, target - progress)
    local acceptedAmount = math.min(remaining, amount)
    if acceptedAmount <= 0 then
        return true, "AlreadyComplete"
    end

    progress = math.min(target, progress + acceptedAmount)
    beacon:SetAttribute("BeaconHeldSeconds", progress)

    setAttribute("DungeonObjectiveProgress", progress)
    setAttribute("DungeonObjectiveLastProgressAt", now())
    setAttribute("DungeonProgressionLastSignalAccepted", true)
    setAttribute("DungeonProgressionLastSignalReason", "Accepted")
    setAttribute("DungeonProgressionAcceptedBeaconSeconds", progress)
    publish()

    if progress >= target then
        beacon:SetAttribute("ObjectiveTargetCompleted", true)
        completeCurrentObjective()
    end

    return true, "Accepted"
end

function DungeonProgressionService.AddProgress(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return false, "InvalidAmount"
    end
    if not objectiveActive or not currentDefinition then
        return false, "NoActiveObjective"
    end

    progress = math.min(target, progress + amount)
    setAttribute("DungeonObjectiveProgress", progress)
    setAttribute("DungeonObjectiveLastProgressAt", now())
    publish()

    if progress >= target then
        completeCurrentObjective()
    end
    return true
end

function DungeonProgressionService.CommitRoundReward(roundIndex, metadata)
    roundIndex = math.floor(tonumber(roundIndex) or 0)

    local expectedIsland = ({ [1] = 3, [2] = 7, [3] = 12 })[roundIndex]
    local expectedObjective = ({
        [1] = "FirstRewardBattle",
        [2] = "SecondRewardBattle",
        [3] = "FinalRewardBattle",
    })[roundIndex]

    if not expectedIsland or not expectedObjective then
        return false, "RoundNotImplemented"
    end
    if rewardPendingRound ~= roundIndex then
        return false, string.format("NoRound%dRewardPending", roundIndex)
    end
    if currentIsland ~= expectedIsland
        or not currentDefinition
        or currentDefinition.Id ~= expectedObjective
        or completedObjectives[expectedIsland] ~= true
    then
        return false, string.format("Round%dObjectiveNotCompleted", roundIndex)
    end

    local alreadyCommitted = (roundIndex == 1 and round1Committed)
        or (roundIndex == 2 and round2Committed)
        or (roundIndex == 3 and round3Committed)

    if alreadyCommitted then
        return true, {
            RoundIndex = roundIndex,
            RoundCompleted = true,
            HighestCompletedRound = round3Committed and 3
                or (round2Committed and 2 or 1),
            NextRoundIndex = roundIndex < 3 and roundIndex + 1 or nil,
            IsFinal = roundIndex == 3,
            GlobalIslandIndex = expectedIsland,
            DuplicateCommit = true,
        }
    end

    local isFinal = roundIndex == 3

    -- Preserve the original runtime contract:
    -- boss continuation must succeed BEFORE final progression is committed.
    if isFinal then
        local continued = safeCallback(
            "OnFinalRewardCommitted",
            currentContext,
            metadata
        )
        if not continued then
            setAttribute("DungeonFinalRewardContinuationError", true)
            return false, "FinalRewardContinuationFailed"
        end
        setAttribute("DungeonFinalRewardContinuationError", nil)
    end

    if roundIndex == 1 then
        round1Committed = true
    elseif roundIndex == 2 then
        round2Committed = true
    else
        round3Committed = true
        finalRewardCommitted = true
    end
    rewardPendingRound = nil

    setAttribute("DungeonRoundRewardPending", false)
    setAttribute("DungeonRoundRewardIndex", nil)
    setAttribute("DungeonLastCommittedRewardRound", roundIndex)
    setAttribute(string.format("DungeonRound%dCommittedAt", roundIndex), now())

    setState(isFinal and "BossTransition" or "RewardCommitted")
    publish()

    local result = {
        RoundIndex = roundIndex,
        RoundCompleted = true,
        HighestCompletedRound = round3Committed and 3
            or (round2Committed and 2 or 1),
        NextRoundIndex = isFinal and nil or roundIndex + 1,
        IsFinal = isFinal,
        GlobalIslandIndex = expectedIsland,
        FinalRewardCommitted = finalRewardCommitted,
    }

    safeCallback(
        "OnRoundRewardCommitted",
        roundIndex,
        isFinal,
        currentContext,
        metadata
    )

    if not isFinal and type(options.RequestRouteThrough) == "function" then
        pcall(options.RequestRouteThrough, expectedIsland + 1)
    end

    -- Keep the round-exit gate closed while the runtime prepares the boss.
    task.delay(isFinal and 0.80 or 0.50, function()
        local committed = (roundIndex == 1 and round1Committed)
            or (roundIndex == 2 and round2Committed)
            or (roundIndex == 3 and round3Committed)

        if not started or not committed then
            return
        end

        if currentContext and currentContext.Exit then
            setWaypoint(currentContext.Exit)
        end

        setGateLocked(false, isFinal and "BossRouteUnlocked" or string.format("Round%dCommitted", roundIndex))
        setState(isFinal and "BossRouteUnlocked" or "TravelUnlocked")
        publish()
    end)

    return true, result
end

function DungeonProgressionService.ForceComplete(reason)
    if not currentDefinition then
        return false
    end
    setAttribute("DungeonObjectiveCompletionReason", reason or "ForceComplete")
    return completeCurrentObjective()
end

function DungeonProgressionService.EscalateWaypoint()
    if not objectiveActive or not currentDefinition then
        return false
    end

    setAttribute("DungeonObjectiveWaypointEscalated", true)
    setAttribute(
        "DungeonObjectiveWaypointSerial",
        (tonumber(workspace:GetAttribute("DungeonObjectiveWaypointSerial")) or 0) + 1
    )
    return true
end

function DungeonProgressionService.GetSnapshot()
    return currentSnapshot()
end

function DungeonProgressionService.GetCurrentDefinition()
    return currentDefinition and table.clone(currentDefinition) or nil
end

function DungeonProgressionService.GetCurrentContext()
    return currentContext or getContext(currentIsland)
end

function DungeonProgressionService.IsActive()
    return started and objectiveActive and currentDefinition ~= nil
end

return DungeonProgressionService
