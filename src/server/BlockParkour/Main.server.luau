-- Inicializador canonico do Place de dungeon. O runtime valida o TeleportData,
-- carrega os perfis e somente entao inicia o gerador com PhaseId/PartySize/Seed.

local DungeonRuntimeService = require(script.Parent.Parent.DungeonRuntime.DungeonRuntimeService)
DungeonRuntimeService.Start()
