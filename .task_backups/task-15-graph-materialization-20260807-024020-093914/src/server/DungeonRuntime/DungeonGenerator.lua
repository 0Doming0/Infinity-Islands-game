local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local ChunkManager = require(script.Parent.Parent.BlockParkour.ChunkManager_SkyDungeon_V10)
local DungeonRoutePlanner = require(script.Parent.DungeonRoutePlanner)

local DungeonGenerator = {}
local activeRoutePlan

function DungeonGenerator.Generate(options)
	assert(type(options) == "table", "DungeonGenerator.Generate requer opcoes")
	local phase = PhaseConfig.Get(options.PhaseId)
	assert(phase, "PhaseId invalido: " .. tostring(options.PhaseId))
	activeRoutePlan = options.RoutePlan or DungeonRoutePlanner.Build({
		Seed = options.Seed,
		RoundLengths = options.RoundLengths or { 3, 4, 5 },
	})
	return ChunkManager.Start({
		PhaseId = options.PhaseId,
		PartySize = math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, phase.MaxPlayers),
		Seed = math.floor(tonumber(options.Seed) or 1),
		MaximumIslandCount = activeRoutePlan.TotalIslandCount + 1,
		RoutePlan = activeRoutePlan,
		OnPhaseReady = options.OnPhaseReady,
		OnBossSanctuaryReady = options.OnBossSanctuaryReady,
		OnRouteIslandEntered = options.OnRouteIslandEntered,
	})
end

function DungeonGenerator.Stop()
	ChunkManager.Stop()
end

function DungeonGenerator.GetEndContext()
	return ChunkManager.GetEndContext()
end

function DungeonGenerator.GetRoutePlan()
	return activeRoutePlan
end

function DungeonGenerator.GetRouteIslandContext(globalIslandIndex)
	return ChunkManager.GetRouteIslandContext(globalIslandIndex)
end

function DungeonGenerator.RequestRouteThrough(globalIslandIndex)
	return ChunkManager.RequestRouteThrough(globalIslandIndex)
end

function DungeonGenerator.CreateBossSanctuary(options)
	return ChunkManager.CreateBossSanctuary(options)
end

return DungeonGenerator
