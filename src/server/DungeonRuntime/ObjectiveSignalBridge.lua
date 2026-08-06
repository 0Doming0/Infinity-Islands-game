local ObjectiveSignalBridge = {}

local activeHandler

function ObjectiveSignalBridge.Bind(handler)
	assert(type(handler) == "function", "ObjectiveSignalBridge.Bind requer callback")
	activeHandler = handler
	return handler
end

function ObjectiveSignalBridge.Unbind(handler)
	if handler == nil or activeHandler == handler then
		activeHandler = nil
		return true
	end
	return false
end

function ObjectiveSignalBridge.Report(eventName, payload)
	if type(eventName) ~= "string" or eventName == "" then
		return false, "InvalidEventName"
	end
	if not activeHandler then
		return false, "NoObjectiveHandler"
	end
	payload = type(payload) == "table" and table.clone(payload) or {}
	payload.EventName = eventName
	payload.ReportedAt = workspace:GetServerTimeNow()
	local ok, accepted, reason = pcall(activeHandler, eventName, payload)
	if not ok then
		warn("[ObjectiveSignalBridge] Falha ao encaminhar evento: " .. tostring(accepted))
		return false, "HandlerError"
	end
	return accepted == true, reason
end

function ObjectiveSignalBridge.IsBound()
	return activeHandler ~= nil
end

return ObjectiveSignalBridge
