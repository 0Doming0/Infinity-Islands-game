local ServerScriptService = game:GetService("ServerScriptService")

local companionService = require(
	ServerScriptService.MVPSystems:WaitForChild("CompanionService")
)

companionService.Start()
print("[CompanionBootstrap] CompanionService ativo")
