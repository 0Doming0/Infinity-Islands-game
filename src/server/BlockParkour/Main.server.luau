-- Inicializador canonico da geracao. Start e idempotente porque o sistema de
-- agua tambem confirma que o mundo esta pronto antes de iniciar sua simulacao.

local ChunkManager = require(script.Parent.ChunkManager_SkyDungeon_V10)

if not ChunkManager.IsRunning() then
	ChunkManager.Start()
end
