-- Rebuild Part 07
-- EnemyDefeated goes directly to the single progression authority.

local DungeonProgressionService = require(script.Parent.DungeonProgressionService)

local ObjectiveSignalBridge = {}

local compatibilityHandler

function ObjectiveSignalBridge.Bind(handler)
    compatibilityHandler = type(handler) == "function" and handler or nil
    return handler
end

function ObjectiveSignalBridge.Unbind(handler)
    if handler == nil or compatibilityHandler == handler then
        compatibilityHandler = nil
    end
    return true
end

function ObjectiveSignalBridge.Report(eventName, payload)
    if type(eventName) ~= "string" or eventName == "" then
        return false, "InvalidEventName"
    end

    if eventName == "EnemyDefeated" then
        local ok, accepted, reason = pcall(
            DungeonProgressionService.ReportEnemyDefeated,
            payload
        )
        if not ok then
            workspace:SetAttribute("DungeonProgressionLastSignalAccepted", false)
            workspace:SetAttribute("DungeonProgressionLastSignalReason", "ProgressionError")
            warn("[ObjectiveSignalBridge] Progression error: " .. tostring(accepted))
            return false, "ProgressionError"
        end
        return accepted == true, reason
    end

    if eventName == "NestDestroyed" then
        local ok, accepted, reason = pcall(
            DungeonProgressionService.ReportNestDestroyed,
            payload
        )
        if not ok then
            workspace:SetAttribute("DungeonProgressionLastSignalAccepted", false)
            workspace:SetAttribute("DungeonProgressionLastSignalReason", "ProgressionError")
            warn("[ObjectiveSignalBridge] Nest progression error: " .. tostring(accepted))
            return false, "ProgressionError"
        end
        return accepted == true, reason
    end

    if eventName == "BeaconHoldSeconds" then
        local ok, accepted, reason = pcall(
            DungeonProgressionService.ReportBeaconHoldSeconds,
            payload
        )
        if not ok then
            workspace:SetAttribute("DungeonProgressionLastSignalAccepted", false)
            workspace:SetAttribute("DungeonProgressionLastSignalReason", "ProgressionError")
            warn("[ObjectiveSignalBridge] Beacon progression error: " .. tostring(accepted))
            return false, "ProgressionError"
        end
        return accepted == true, reason
    end

    return false, "UnsupportedRebuildEvent"
end

function ObjectiveSignalBridge.IsBound()
    return true
end

return ObjectiveSignalBridge
