local service = require(
	script.Parent.DungeonRuntime.AssistedIslandTransportService
)

local ok, result, detail = pcall(service.Start)
if not ok or (result == false and detail ~= "AlreadyStarted") then
	workspace:SetAttribute("DungeonAssistedTransportReady", false)
	workspace:SetAttribute(
		"DungeonAssistedTransportBootstrapError",
		tostring(ok and detail or result)
	)
	warn("[AssistedIslandTransport] Falha ao iniciar: " .. tostring(ok and detail or result))
else
	workspace:SetAttribute("DungeonAssistedTransportBootstrapError", nil)
end
