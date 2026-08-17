-- CompanionInventoryBootstrap.server.luau
-- Inicia o sistema de companions antes de qualquer GUI cliente solicitar o
-- snapshot. CompanionService.Start() e idempotente, entao continua seguro com
-- os outros sistemas que tambem o chamam.

local ServerScriptService = game:GetService("ServerScriptService")

local mvpSystems = ServerScriptService:WaitForChild("MVPSystems")
local CompanionService = require(mvpSystems:WaitForChild("CompanionService"))

CompanionService.Start()
