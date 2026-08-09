-- Tarefa 01 - bootstrap isolado da nova progressao por ilha.
-- O lobby nao importa este arquivo; somente dungeon.project.json importa src/server.

local IslandProgressionService = require(
	script.Parent.DungeonRuntime.IslandProgressionService
)

local ok, result, detail = pcall(
	IslandProgressionService.Start
)

if not ok then
	workspace:SetAttribute(
		"DungeonIslandProgressionReady",
		false
	)
	workspace:SetAttribute(
		"DungeonIslandProgressionError",
		tostring(result)
	)
	warn(
		"[IslandProgressionBootstrap] Falha ao iniciar: "
			.. tostring(result)
	)
elseif result == false
	and detail ~= "AlreadyStarted"
then
	workspace:SetAttribute(
		"DungeonIslandProgressionError",
		tostring(detail)
	)
	warn(
		"[IslandProgressionBootstrap] Start recusado: "
			.. tostring(detail)
	)
else
	workspace:SetAttribute(
		"DungeonIslandProgressionError",
		nil
	)
end
