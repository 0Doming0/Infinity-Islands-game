-- ServerScriptService/MVPSystems/StarterSword
--
-- Mantem o nome historico esperado pelo projeto, mas deixa a entrega sob uma
-- unica autoridade. SwordProgressionService tambem e iniciado pelos
-- comerciantes; Start() e idempotente e torna este bootstrap independente
-- deles para que uma falha na vila nao prive o jogador da espada inicial.

local Workspace = game:GetService("Workspace")

local SwordProgressionService = require(script.Parent:WaitForChild("SwordProgressionService"))

SwordProgressionService.Start()

Workspace:SetAttribute("StarterSwordSystemVersion", "CanonicalSwordDeliveryV2")
