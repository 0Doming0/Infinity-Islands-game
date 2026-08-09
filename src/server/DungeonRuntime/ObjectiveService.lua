-- Compatibility facade during rebuild.
-- Objective state is owned only by DungeonProgressionService.

local DungeonProgressionService = require(script.Parent.DungeonProgressionService)

local ObjectiveService = {}

function ObjectiveService.Start()
    workspace:SetAttribute("DungeonObjectiveServiceReady", true)
    workspace:SetAttribute("DungeonObjectiveServicePolicy", "ProgressionFacadeV3")
end

function ObjectiveService.Stop()
    workspace:SetAttribute("DungeonObjectiveServiceReady", false)
end

function ObjectiveService.SetParticipants()
    return true
end

function ObjectiveService.SetParticipantConnected()
    return true
end

function ObjectiveService.SetParticipantEligible()
    return true
end

function ObjectiveService.SetExitTarget()
    return true
end

function ObjectiveService.SetExitLocked(locked)
    workspace:SetAttribute("DungeonObjectiveExitLocked", locked == true)
    return true
end

function ObjectiveService.GetExitTarget()
    local context = DungeonProgressionService.GetCurrentContext()
    return context and context.Exit or nil
end

function ObjectiveService.SetObjective()
    return DungeonProgressionService.GetSnapshot()
end

function ObjectiveService.AddProgress(amount)
    return DungeonProgressionService.AddProgress(amount)
end

function ObjectiveService.SetProgress(progress)
    local snapshot = DungeonProgressionService.GetSnapshot()
    local current = tonumber(snapshot.Progress) or 0
    local desired = math.max(0, math.floor(tonumber(progress) or 0))
    if desired <= current then
        return true, "UnchangedOrLowerIgnored"
    end
    return DungeonProgressionService.AddProgress(desired - current)
end

function ObjectiveService.SetParticipantProgress()
    return false, "ParticipantProgressNotUsedInRebuild"
end

function ObjectiveService.Restart()
    return false, "RestartNotImplementedInRebuildPart03"
end

function ObjectiveService.MarkRecovered()
    return true
end

function ObjectiveService.Complete(reason)
    return DungeonProgressionService.ForceComplete(reason)
end

function ObjectiveService.Clear()
    return true
end

function ObjectiveService.GetSnapshot()
    return DungeonProgressionService.GetSnapshot()
end

function ObjectiveService.IsActive()
    return DungeonProgressionService.IsActive()
end

return ObjectiveService
