local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(
	ReplicatedStorage.Shared.Configs.PhaseConfig
)

local ChunkManager = require(
	script.Parent.Parent.BlockParkour.ChunkManager_SkyDungeon_V10
)

local DungeonRoutePlanner = require(
	script.Parent.DungeonRoutePlanner
)

local DungeonRouteSafetyValidator = require(
	script.Parent.DungeonRouteSafetyValidator
)

local DungeonLinearRouteSafetyValidator = require(
	script.Parent.DungeonLinearRouteSafetyValidator
)

local DungeonGenerator = {}

local activeRoutePlan

local DEFAULT_LINEAR_COMBAT_ISLAND_COUNT = 24

local function physicalIslandCount(routePlan)
	if type(routePlan) ~= "table" then
		return 0
	end

	local nodes =
		type(routePlan.Nodes) == "table"
			and routePlan.Nodes
			or {}

	return math.max(
		math.floor(
			tonumber(
				routePlan.PhysicalIslandCount
			) or 0
		),
		#nodes,
		math.floor(
			tonumber(
				routePlan.TotalIslandCount
			) or 0
		)
	)
end

local function routeIslandCount(options)
	local requested =
		tonumber(
			options.RouteIslandCount
		)
		or tonumber(
			workspace:GetAttribute(
				"DungeonCombatRouteIslandCount"
			)
		)
		or DEFAULT_LINEAR_COMBAT_ISLAND_COUNT

	return math.clamp(
		math.floor(requested),
		2,
		200
	)
end

local function validatorFor(routePlan)
	if routePlan
		and routePlan.Topology
			== "LinearCombatRouteV1"
	then
		return DungeonLinearRouteSafetyValidator
	end

	return DungeonRouteSafetyValidator
end

function DungeonGenerator.Generate(options)
	assert(
		type(options) == "table",
		"DungeonGenerator.Generate requer opcoes"
	)

	local phase =
		PhaseConfig.Get(options.PhaseId)

	assert(
		phase,
		"PhaseId invalido: "
			.. tostring(options.PhaseId)
	)

	activeRoutePlan =
		options.RoutePlan
		or DungeonRoutePlanner.Build({
			Seed = options.Seed,

			-- RoundLengths ainda pode chegar de consumidores antigos,
			-- mas a nova rota nao depende dele.
			RoundLengths =
				options.RoundLengths,

			TotalIslandCount =
				routeIslandCount(options),
		})

	local routeValidator =
		validatorFor(activeRoutePlan)

	local routeValid,
		routeValidation =
			routeValidator.Validate(
				activeRoutePlan
			)

	routeValidator.Publish(
		routeValidation
	)

	if not routeValid then
		activeRoutePlan = nil

		return
			false,
			routeValidation.ErrorCode
				or "RouteValidationFailed"
	end

	local plannedPhysicalCount =
		physicalIslandCount(
			activeRoutePlan
		)

	workspace:SetAttribute(
		"DungeonRouteArchitecture",
		tostring(
			activeRoutePlan.Topology
				or "Unknown"
		)
	)

	workspace:SetAttribute(
		"DungeonPlannedCombatIslandCount",
		activeRoutePlan.TotalIslandCount
	)

	workspace:SetAttribute(
		"DungeonCombatRouteSpacingVersion",
		activeRoutePlan.CompactSpacingVersion
	)

	workspace:SetAttribute(
		"DungeonCombatRouteSpacingPolicy",
		activeRoutePlan.CompactSpacingPolicy
	)

	workspace:SetAttribute(
		"DungeonCombatRouteConnectorMinStuds",
		activeRoutePlan
			.ConnectorHorizontalStudsMinimum
	)

	workspace:SetAttribute(
		"DungeonCombatRouteConnectorMaxStuds",
		activeRoutePlan
			.ConnectorHorizontalStudsMaximum
	)

	workspace:SetAttribute(
		"DungeonCombatRouteConnectorAverageStuds",
		activeRoutePlan
			.ConnectorHorizontalStudsAverage
	)

	workspace:SetAttribute(
		"DungeonCombatRouteVerticalRiseStuds",
		activeRoutePlan.VerticalRiseStuds
	)

	workspace:SetAttribute(
		"DungeonRouteUsesRounds",
		activeRoutePlan.Topology
			~= "LinearCombatRouteV1"
	)

	workspace:SetAttribute(
		"DungeonRouteUsesOptionalIslands",
		math.floor(
			tonumber(
				activeRoutePlan.OptionalIslandCount
			) or 0
		) > 0
	)

	workspace:SetAttribute(
		"DungeonRouteUsesRewardIslands",
		activeRoutePlan.Topology
			~= "LinearCombatRouteV1"
	)

	workspace:SetAttribute(
		"DungeonRouteBossCompatibilityOnly",
		false
	)
	workspace:SetAttribute(
		"DungeonBossProgressionEnabled",
		false
	)

	local started, startError =
		ChunkManager.Start({
			PhaseId = options.PhaseId,

			PartySize =
				math.clamp(
					math.floor(
						tonumber(
							options.PartySize
						) or 1
					),
					1,
					phase.MaxPlayers
				),

			Seed =
				math.floor(
					tonumber(
						options.Seed
					) or 1
				),

			MaximumIslandCount =
				plannedPhysicalCount,

			RoutePlan =
				activeRoutePlan,

			OnPhaseReady =
				function(endContext)
					if type(
						options.OnPhaseReady
					) == "function"
					then
						local ok,
							err =
							pcall(
								options.OnPhaseReady,
								endContext
							)

						if not ok then
							workspace:SetAttribute(
								"DungeonPhaseReadyCallbackError",
								tostring(err)
							)
							warn(
								"[DungeonGenerator] OnPhaseReady: "
									.. tostring(err)
							)
						end
					end

					-- The legacy runtime callback still writes
					-- WaitingForFinalReward. The Combat MVP has no boss/reward phase.
					workspace:SetAttribute(
						"DungeonBossState",
						"Disabled"
					)
					workspace:SetAttribute(
						"DungeonBossProgressionEnabled",
						false
					)
					workspace:SetAttribute(
						"DungeonRoundRewardPending",
						false
					)
				end,

			OnBossSanctuaryReady = nil,

			OnRouteIslandEntered =
				options.OnRouteIslandEntered,

			OnOptionalIslandEntered = nil,
		})

	if not started then
		activeRoutePlan = nil

		workspace:SetAttribute(
			"DungeonInitialRouteReady",
			false
		)

		workspace:SetAttribute(
			"DungeonInitialRouteError",
			tostring(
				startError
					or "ChunkManagerStartFailed"
			)
		)

		return false, startError
	end

	workspace:SetAttribute(
		"DungeonInitialRouteReady",
		false
	)

	workspace:SetAttribute(
		"DungeonInitialRouteWaitPolicy",
		"WaitForMaterializedWindowV1"
	)

	local deadline =
		os.clock() + 22

	while not ChunkManager
		.IsInitialGenerationComplete()
		and os.clock() < deadline
	do
		task.wait(0.05)
	end

	local initialReady =
		ChunkManager
			.IsInitialGenerationComplete()

	workspace:SetAttribute(
		"DungeonInitialRouteReady",
		initialReady
	)

	workspace:SetAttribute(
		"DungeonInitialRouteReadyAt",
		initialReady
			and workspace:GetServerTimeNow()
			or nil
	)

	if not initialReady then
		workspace:SetAttribute(
			"DungeonInitialRouteError",
			"InitialRouteGenerationTimeout"
		)

		ChunkManager.Stop()
		activeRoutePlan = nil

		return
			false,
			"InitialRouteGenerationTimeout"
	end

	workspace:SetAttribute(
		"DungeonInitialRouteError",
		nil
	)

	return true
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

function DungeonGenerator.GetRouteIslandContext(
	globalIslandIndex
)
	local context =
		ChunkManager.GetRouteIslandContext(
			globalIslandIndex
		)

	if type(context) ~= "table"
		or type(activeRoutePlan) ~= "table"
	then
		return context
	end

	local index =
		math.floor(
			tonumber(globalIslandIndex) or 0
		)

	local spec =
		activeRoutePlan.Nodes
			and activeRoutePlan.Nodes[index]

	if not spec then
		return context
	end

	context.CombatRouteCompactSpacingVersion =
		spec.CombatRouteCompactSpacingVersion

	context.IncomingConnectorHorizontalStuds =
		spec.IncomingConnectorHorizontalStuds

	context.IncomingConnectorEstimatedWalkSeconds =
		spec.IncomingConnectorEstimatedWalkSeconds

	context.IncomingVerticalRiseStuds =
		spec.IncomingVerticalRiseStuds

	return context
end

function DungeonGenerator.RequestRouteThrough(
	globalIslandIndex
)
	return ChunkManager.RequestRouteThrough(
		globalIslandIndex
	)
end

-- Task 12: Boss Sanctuary was removed from the Combat MVP.
function DungeonGenerator.CreateBossSanctuary(_options)
	workspace:SetAttribute(
		"DungeonBossSanctuaryCreationBlocked",
		true
	)

	return false,
		"BossSanctuaryDisabledInCombatMVP"
end

return DungeonGenerator
