local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local ChunkManager = require(script.Parent.Parent.BlockParkour.ChunkManager_SkyDungeon_V10)

local DungeonGenerator = {}

function DungeonGenerator.Generate(options)
	assert(type(options) == "table", "DungeonGenerator.Generate requer opcoes")
	local phase = PhaseConfig.Get(options.PhaseId)
	assert(phase, "PhaseId invalido: " .. tostring(options.PhaseId))
	return ChunkManager.Start({
		PhaseId = options.PhaseId,
		PartySize = math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, phase.MaxPlayers),
		Seed = math.floor(tonumber(options.Seed) or 1),
		MaximumIslandCount = math.max(1, math.floor(tonumber(options.MaximumIslandCount) or phase.BaseIslandCount)),
		OnPhaseReady = options.OnPhaseReady,
	})
end

function DungeonGenerator.Stop()
	ChunkManager.Stop()
end

function DungeonGenerator.GetEndContext()
	return ChunkManager.GetEndContext()
end

return DungeonGenerator
