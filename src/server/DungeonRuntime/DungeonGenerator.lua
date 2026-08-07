local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local ChunkManager = require(script.Parent.Parent.BlockParkour.ChunkManager_SkyDungeon_V10)
local DungeonRoutePlanner = require(script.Parent.DungeonRoutePlanner)
local DungeonRouteSafetyValidator = require(script.Parent.DungeonRouteSafetyValidator)

local DungeonGenerator = {}
local activeRoutePlan

local function physicalIslandCount(routePlan)
	if type(routePlan) ~= "table" then
		return 0
	end
	local nodes = type(routePlan.Nodes) == "table" and routePlan.Nodes or {}
	return math.max(
		math.floor(tonumber(routePlan.PhysicalIslandCount) or 0),
		#nodes,
		math.floor(tonumber(routePlan.TotalIslandCount) or 0)
	)
end

function DungeonGenerator.Generate(options)
	assert(type(options) == "table", "DungeonGenerator.Generate requer opcoes")
	local phase = PhaseConfig.Get(options.PhaseId)
	assert(phase, "PhaseId invalido: " .. tostring(options.PhaseId))
	activeRoutePlan = options.RoutePlan or DungeonRoutePlanner.Build({
		Seed = options.Seed,
		RoundLengths = options.RoundLengths or { 3, 4, 5 },
	})
	local routeValid, routeValidation = DungeonRouteSafetyValidator.Validate(activeRoutePlan)
	DungeonRouteSafetyValidator.Publish(routeValidation)
	if not routeValid then
		activeRoutePlan = nil
		return false, routeValidation.ErrorCode or "RouteValidationFailed"
	end
	local plannedPhysicalCount = physicalIslandCount(activeRoutePlan)
	return ChunkManager.Start({
		PhaseId = options.PhaseId,
		PartySize = math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, phase.MaxPlayers),
		Seed = math.floor(tonumber(options.Seed) or 1),
		MaximumIslandCount = plannedPhysicalCount + 1,
		RoutePlan = activeRoutePlan,
		OnPhaseReady = options.OnPhaseReady,
		OnBossSanctuaryReady = options.OnBossSanctuaryReady,
		OnRouteIslandEntered = options.OnRouteIslandEntered,
		OnOptionalIslandEntered = options.OnOptionalIslandEntered,
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
