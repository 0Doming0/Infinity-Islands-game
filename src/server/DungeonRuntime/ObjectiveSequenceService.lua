-- Compatibility facade during the progression rebuild.
-- All authoritative progression state lives in DungeonProgressionService.

local DungeonProgressionService = require(script.Parent.DungeonProgressionService)
local ObjectiveEncounterService = require(script.Parent.ObjectiveEncounterService)
local RewardIslandService = require(script.Parent.RewardIslandService)

local ObjectiveSequenceService = {}

function ObjectiveSequenceService.Start(options)
    options = type(options) == "table" and options or {}
    local wrapped = table.clone(options)

    -- Critical rebuild rule:
    -- the mandatory encounter must start BEFORE any legacy runtime callback.
    -- A telemetry/state callback must never be able to prevent the mob/object
    -- required by the objective from spawning.
    local originalStarted = options.OnObjectiveStarted
    wrapped.OnObjectiveStarted = function(definition, context, snapshot)
        local encounterStarted, encounterResult = ObjectiveEncounterService.BeginObjective(
            definition,
            context
        )

        if not encounterStarted then
            workspace:SetAttribute("DungeonEncounterStartError", tostring(encounterResult))
            workspace:SetAttribute("DungeonObjectiveStartBridgeState", "EncounterFailed")
            warn(
                "[ObjectiveSequenceService] Mandatory encounter failed: "
                    .. tostring(encounterResult)
            )
            return false
        end

        workspace:SetAttribute("DungeonEncounterStartError", nil)
        workspace:SetAttribute("DungeonObjectiveStartBridgeState", "EncounterStarted")
        workspace:SetAttribute("DungeonObjectiveStartBridgeObjectiveId", definition.Id)

        -- Runtime sessionPlayers is now correctly forward-declared.
        -- Keep the callback protected so presentation/analytics glue can never
        -- cancel the already-started mandatory encounter.
        workspace:SetAttribute("DungeonStudioLegacyObjectiveStartedCallbackSkipped", false)

        if type(originalStarted) == "function" then
            local ok, result = pcall(originalStarted, definition, context, snapshot)
            if not ok then
                workspace:SetAttribute(
                    "DungeonLegacyObjectiveStartedCallbackError",
                    tostring(result)
                )
                warn(
                    "[ObjectiveSequenceService] Legacy OnObjectiveStarted failed after "
                    .. "the mandatory encounter was already started: "
                    .. tostring(result)
                )
                return true
            end
            return result ~= false
        end

        return true
    end

    local originalCompleted = options.OnObjectiveCompleted
    wrapped.OnObjectiveCompleted = function(snapshot, context)
        ObjectiveEncounterService.CompleteObjective(snapshot and snapshot.Id)
        if type(originalCompleted) == "function" then
            local ok, result = pcall(originalCompleted, snapshot, context)
            if not ok then
                workspace:SetAttribute(
                    "DungeonLegacyObjectiveCompletedCallbackError",
                    tostring(result)
                )
                return true
            end
            return result ~= false
        end
        return true
    end

    -- Core reward ownership belongs to the rebuild, not to the legacy runtime.
    -- The callback remains isolated defensively even though the runtime lexical
    -- sessionPlayers bug is fixed in Part 38.
    local originalRewardPending = options.OnRoundRewardPending
    wrapped.OnRoundRewardPending = function(result, context, snapshot)
        local startedReward, rewardResult = RewardIslandService.BeginRound(
            result,
            context
        )

        if not startedReward then
            workspace:SetAttribute(
                "DungeonRebuildRewardStartError",
                tostring(rewardResult)
            )
            workspace:SetAttribute(
                "DungeonRewardPendingBridgeState",
                "RewardFailed"
            )
            return false
        end

        workspace:SetAttribute("DungeonRebuildRewardStartError", nil)
        workspace:SetAttribute(
            "DungeonRewardPendingBridgeState",
            "RewardStarted"
        )
        workspace:SetAttribute(
            "DungeonRewardPendingBridgeRound",
            result and result.RoundIndex or nil
        )

        -- Legacy callback is now non-authoritative. It may still perform
        -- analytics/healing/collectible polish, but it is never allowed to
        -- prevent the Core Chest from existing.
        if type(originalRewardPending) == "function" then
            local ok, legacyResult = pcall(
                originalRewardPending,
                result,
                context,
                snapshot
            )
            if not ok then
                workspace:SetAttribute(
                    "DungeonLegacyRewardPendingCallbackError",
                    tostring(legacyResult)
                )
                workspace:SetAttribute(
                    "DungeonLegacyRewardPendingCallbackHealthy",
                    false
                )
                -- Do not warn here: the known legacy line-55 failure is
                -- diagnostic only and must not spam Studio output.
            else
                workspace:SetAttribute(
                    "DungeonLegacyRewardPendingCallbackError",
                    nil
                )
                workspace:SetAttribute(
                    "DungeonLegacyRewardPendingCallbackHealthy",
                    true
                )
            end
        end

        return true
    end

    local originalRewardCommitted = options.OnRoundRewardCommitted
    wrapped.OnRoundRewardCommitted = function(
        roundIndex,
        isFinal,
        context,
        metadata
    )
        if type(originalRewardCommitted) ~= "function" then
            return true
        end

        local ok, result = pcall(
            originalRewardCommitted,
            roundIndex,
            isFinal,
            context,
            metadata
        )
        if not ok then
            workspace:SetAttribute(
                "DungeonLegacyRewardCommittedCallbackError",
                tostring(result)
            )
            return true
        end
        return result ~= false
    end

    -- Final reward is different: this callback creates/prepares the Boss
    -- Sanctuary, therefore failure remains authoritative.
    local originalFinalRewardCommitted = options.OnFinalRewardCommitted
    wrapped.OnFinalRewardCommitted = function(context, metadata)
        if type(originalFinalRewardCommitted) ~= "function" then
            return false
        end

        local ok, result = pcall(
            originalFinalRewardCommitted,
            context,
            metadata
        )
        if not ok then
            workspace:SetAttribute(
                "DungeonFinalRewardContinuationErrorDetail",
                tostring(result)
            )
            return false
        end
        workspace:SetAttribute(
            "DungeonFinalRewardContinuationErrorDetail",
            nil
        )
        return result ~= false
    end

    DungeonProgressionService.Start(wrapped)
end

function ObjectiveSequenceService.Stop()
    DungeonProgressionService.Stop()
end

function ObjectiveSequenceService.HandleIslandEntered(player, context)
    return DungeonProgressionService.HandleIslandEntered(player, context)
end

function ObjectiveSequenceService.HandleObjectiveCompleted(snapshot)
    return snapshot
end

function ObjectiveSequenceService.CommitRoundReward(roundIndex, metadata)
    return DungeonProgressionService.CommitRoundReward(roundIndex, metadata)
end

function ObjectiveSequenceService.EscalateWaypoint()
    return DungeonProgressionService.EscalateWaypoint()
end

function ObjectiveSequenceService.RecoverCurrentObjective()
    return ObjectiveEncounterService.Recover(
        DungeonProgressionService.GetCurrentDefinition(),
        DungeonProgressionService.GetCurrentContext(),
        DungeonProgressionService.GetSnapshot()
    )
end

function ObjectiveSequenceService.Report(eventName, payload)
    if eventName == "EnemyDefeated" then
        return DungeonProgressionService.ReportEnemyDefeated(payload)
    elseif eventName == "NestDestroyed" then
        return DungeonProgressionService.ReportNestDestroyed(payload)
    elseif eventName == "BeaconHoldSeconds" then
        return DungeonProgressionService.ReportBeaconHoldSeconds(payload)
    end
    return false, "UnsupportedRebuildEvent"
end

function ObjectiveSequenceService.GetSnapshot()
    return DungeonProgressionService.GetSnapshot()
end

function ObjectiveSequenceService.GetCurrentDefinition()
    return DungeonProgressionService.GetCurrentDefinition()
end

function ObjectiveSequenceService.GetCurrentContext()
    return DungeonProgressionService.GetCurrentContext()
end

return ObjectiveSequenceService
