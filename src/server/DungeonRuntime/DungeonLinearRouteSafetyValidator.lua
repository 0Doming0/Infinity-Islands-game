--[[
	Infinity Islands - Tarefa 02
	Validador da rota LinearCombatRouteV1.

	Este validador nao exige:
	- RoundExit;
	- RewardIsland;
	- OptionalRouteIsland;
	- BossSanctuary na rota principal.

	Ele valida o que agora importa:
	- sequencia global continua;
	- uma unica cadeia;
	- conexoes fisicamente validas;
	- deterministic/materialization contract;
	- nenhum branch/convergence;
	- terminal unico.
]]

local IslandGraphPlanner = require(
	script.Parent.Parent.BlockParkour.IslandGraphPlanner
)

local DungeonLinearRouteSafetyValidator = {}

local MAX_REPORTED_ERRORS = 32

local function addError(
	report,
	code,
	message,
	nodeKey,
	targetKey
)
	report.ErrorCount += 1

	if not report.ErrorCode then
		report.ErrorCode = code
		report.ErrorMessage = message
		report.ErrorNodeKey = nodeKey
		report.ErrorTargetKey = targetKey
	end

	if #report.Errors < MAX_REPORTED_ERRORS then
		table.insert(
			report.Errors,
			{
				Code = code,
				Message = message,
				NodeKey = nodeKey,
				TargetKey = targetKey,
			}
		)
	end
end

local function isInteger(value)
	return typeof(value) == "number"
		and value == math.floor(value)
end

local function validateConnectionCells(
	report,
	source,
	target,
	directionId
)
	local success, planOrError =
		pcall(
			IslandGraphPlanner.PlanConnection,
			source,
			target,
			directionId
		)

	if not success then
		addError(
			report,
			"ConnectionPlanInvalid",
			tostring(planOrError),
			source.Key,
			target.Key
		)
		return false
	end

	local cells = planOrError.Cells

	if type(cells) ~= "table"
		or #cells < 3
	then
		addError(
			report,
			"ConnectionTooShort",
			"A conexao precisa possuir celulas fisicas entre as ilhas.",
			source.Key,
			target.Key
		)
		return false
	end

	for index = 2, #cells do
		local delta =
			cells[index]
			- cells[index - 1]

		local horizontal =
			math.abs(delta.X)
			+ math.abs(delta.Z)

		local vertical =
			delta.Y

		if horizontal ~= 1
			or vertical < 0
			or vertical > 1
		then
			addError(
				report,
				"UnsafeConnectionStep",
				string.format(
					"Passo %d invalido: horizontal=%s vertical=%s",
					index - 1,
					tostring(horizontal),
					tostring(vertical)
				),
				source.Key,
				target.Key
			)
			return false
		end
	end

	return true
end

local function expectedTarget(
	source,
	directionId
)
	local direction =
		IslandGraphPlanner.GetDirection(
			directionId
		)

	if not direction then
		return nil
	end

	return
		source.LaneX + direction.DeltaX,
		source.LaneZ + direction.DeltaZ,
		source.Level + 1
end

function DungeonLinearRouteSafetyValidator.Validate(
	routePlan
)
	local report = {
		Version = 2,
		Mode = "LinearCombatRouteV1",
		Passed = false,

		ErrorCount = 0,
		Errors = {},

		NodeCount = 0,
		MandatoryNodeCount = 0,
		OptionalNodeCount = 0,
		RoundExitCount = 0,
		ConnectionCount = 0,
		ReachableNodeCount = 0,
		TerminalCount = 0,
	}

	if type(routePlan) ~= "table" then
		addError(
			report,
			"RoutePlanMissing",
			"O planejamento da rota nao existe."
		)
		return false, report
	end

	if routePlan.Topology
		~= "LinearCombatRouteV1"
	then
		addError(
			report,
			"WrongTopology",
			"Validador linear recebeu outra topologia."
		)
		return false, report
	end

	local nodes =
		type(routePlan.Nodes) == "table"
			and routePlan.Nodes
			or {}

	local total =
		math.floor(
			tonumber(
				routePlan.TotalIslandCount
			) or 0
		)

	if total < 2 then
		addError(
			report,
			"IslandCountTooSmall",
			"A rota linear precisa de ao menos 2 ilhas."
		)
	end

	if #nodes ~= total then
		addError(
			report,
			"NodeCountMismatch",
			"Nodes e TotalIslandCount divergem."
		)
	end

	if math.floor(
		tonumber(
			routePlan.PhysicalIslandCount
		) or 0
	) ~= #nodes
	then
		addError(
			report,
			"PhysicalCountMismatch",
			"PhysicalIslandCount diverge de Nodes."
		)
	end

	if math.floor(
		tonumber(
			routePlan.OptionalIslandCount
		) or 0
	) ~= 0
	then
		addError(
			report,
			"OptionalIslandsNotAllowed",
			"A rota linear nao pode declarar ilhas opcionais."
		)
	end

	local nodeByKey = {}
	local laneVisits = {}

	for index, spec in ipairs(nodes) do
		report.NodeCount += 1

		if type(spec) ~= "table"
			or type(spec.Key) ~= "string"
			or spec.Key == ""
		then
			addError(
				report,
				"NodeKeyMissing",
				"Ilha sem Key valido."
			)
			continue
		end

		if nodeByKey[spec.Key] then
			addError(
				report,
				"DuplicateNodeKey",
				"Duas ilhas usam a mesma Key.",
				spec.Key
			)
			continue
		end

		nodeByKey[spec.Key] = spec

		if spec.RouteNodeOrder ~= index then
			addError(
				report,
				"RouteNodeOrderInvalid",
				"RouteNodeOrder precisa ser igual ao GlobalIslandIndex.",
				spec.Key
			)
		end

		if spec.GlobalIslandIndex ~= index then
			addError(
				report,
				"GlobalIslandIndexInvalid",
				"GlobalIslandIndex precisa ser sequencial.",
				spec.Key
			)
		end

		if not isInteger(spec.LaneX)
			or not isInteger(spec.LaneZ)
			or not isInteger(spec.Level)
		then
			addError(
				report,
				"NodeCoordinateInvalid",
				"Coordenada logica invalida.",
				spec.Key
			)
		end

		if spec.Level ~= index - 1 then
			addError(
				report,
				"LogicalLevelInvalid",
				"Cada Combat Island precisa subir exatamente um LogicalLevel.",
				spec.Key
			)
		end

		if spec.IsMandatoryRoute ~= true then
			addError(
				report,
				"MandatoryFlagMissing",
				"Combat Island precisa pertencer a rota obrigatoria.",
				spec.Key
			)
		else
			report.MandatoryNodeCount += 1
		end

		if spec.IsOptionalRoute == true then
			report.OptionalNodeCount += 1
			addError(
				report,
				"OptionalRouteForbidden",
				"Combat route nao aceita OptionalRouteIsland.",
				spec.Key
			)
		end

		if spec.IsRewardIsland == true then
			addError(
				report,
				"RewardIslandForbidden",
				"Combat route nao aceita RewardIsland.",
				spec.Key
			)
		end

		if spec.IsRoundExit == true then
			report.RoundExitCount += 1
			addError(
				report,
				"RoundExitForbidden",
				"Combat route nao aceita RoundExit.",
				spec.Key
			)
		end

		if spec.IsBossSanctuary == true then
			addError(
				report,
				"BossNodeForbidden",
				"BossSanctuary nao pode fazer parte de Nodes.",
				spec.Key
			)
		end

		if spec.IsSanctuary == true then
			addError(
				report,
				"SanctuaryNodeForbidden",
				"Combat Island nao deve ser Sanctuary.",
				spec.Key
			)
		end

		if index == 1 then
			if spec.IsStart ~= true then
				addError(
					report,
					"StartFlagMissing",
					"A primeira ilha precisa ser IsStart.",
					spec.Key
				)
			end
		elseif spec.IsStart == true then
			addError(
				report,
				"MultipleStartNodes",
				"Apenas a primeira ilha pode ser IsStart.",
				spec.Key
			)
		end

		local lane =
			tostring(spec.LaneX)
			.. ":"
			.. tostring(spec.LaneZ)

		if laneVisits[lane] then
			addError(
				report,
				"HorizontalLaneReused",
				"A rota reutilizou a mesma coordenada X/Z.",
				spec.Key,
				laneVisits[lane]
			)
		else
			laneVisits[lane] = spec.Key
		end

		local materialization =
			type(
				routePlan
					.MaterializationIndexByGlobalIndex
			) == "table"
			and routePlan
				.MaterializationIndexByGlobalIndex[
					index
				]
			or nil

		if materialization ~= index then
			addError(
				report,
				"MaterializationIndexMismatch",
				"Indice de materializacao precisa ser 1:1.",
				spec.Key
			)
		end
	end

	for index, spec in ipairs(nodes) do
		if not spec.Key then
			continue
		end

		local incoming =
			type(spec.IncomingConnections)
				== "table"
				and spec.IncomingConnections
				or {}

		local outgoing =
			type(spec.OutgoingConnections)
				== "table"
				and spec.OutgoingConnections
				or {}

		if index == 1 then
			if #incoming ~= 0 then
				addError(
					report,
					"StartHasInbound",
					"A primeira ilha nao pode possuir entrada.",
					spec.Key
				)
			end
		else
			if #incoming ~= 1 then
				addError(
					report,
					"InboundCountInvalid",
					"Cada Combat Island depois da primeira precisa de exatamente uma entrada.",
					spec.Key
				)
			else
				local previous =
					nodes[index - 1]

				local edge = incoming[1]

				if edge.SourceKey
					~= previous.Key
				then
					addError(
						report,
						"WrongInboundSource",
						"A entrada nao vem da ilha anterior.",
						spec.Key,
						edge.SourceKey
					)
				end
			end
		end

		if index < #nodes then
			if #outgoing ~= 1 then
				addError(
					report,
					"OutboundCountInvalid",
					"Combat Island intermediaria precisa de exatamente uma saida.",
					spec.Key
				)
			else
				local nextSpec =
					nodes[index + 1]

				local edge = outgoing[1]

				if edge.TargetKey
					~= nextSpec.Key
				then
					addError(
						report,
						"WrongOutboundTarget",
						"A saida nao aponta para a proxima Combat Island.",
						spec.Key,
						edge.TargetKey
					)
				end

				if type(edge.DirectionId)
					~= "string"
				then
					addError(
						report,
						"ConnectionDirectionMissing",
						"Conexao sem DirectionId.",
						spec.Key,
						nextSpec.Key
					)
				else
					local expectedX,
						expectedZ,
						expectedLevel =
							expectedTarget(
								spec,
								edge.DirectionId
							)

					if expectedX ~= nextSpec.LaneX
						or expectedZ ~= nextSpec.LaneZ
						or expectedLevel
							~= nextSpec.Level
					then
						addError(
							report,
							"DirectionTargetMismatch",
							"DirectionId nao corresponde a coordenada da proxima ilha.",
							spec.Key,
							nextSpec.Key
						)
					end

					validateConnectionCells(
						report,
						spec,
						nextSpec,
						edge.DirectionId
					)
				end

				report.ConnectionCount += 1
			end
		else
			if #outgoing ~= 0 then
				addError(
					report,
					"TerminalHasOutbound",
					"A ultima Combat Island precisa ser terminal.",
					spec.Key
				)
			end

			report.TerminalCount += 1
		end

		report.ReachableNodeCount += 1
	end

	if report.MandatoryNodeCount ~= total then
		addError(
			report,
			"MandatoryCountMismatch",
			"Todas as ilhas precisam ser obrigatorias."
		)
	end

	if report.OptionalNodeCount ~= 0 then
		addError(
			report,
			"OptionalCountMismatch",
			"Nao pode existir ilha opcional."
		)
	end

	if report.RoundExitCount ~= 0 then
		addError(
			report,
			"RoundExitCountMismatch",
			"Nao pode existir RoundExit."
		)
	end

	if report.ConnectionCount
		~= math.max(0, total - 1)
	then
		addError(
			report,
			"ConnectionCountMismatch",
			"Uma rota linear de N ilhas precisa de N-1 conexoes."
		)
	end

	if report.TerminalCount ~= 1 then
		addError(
			report,
			"TerminalCountInvalid",
			"A rota precisa possuir um unico terminal."
		)
	end

	report.Passed =
		report.ErrorCount == 0

	return report.Passed, report
end

function DungeonLinearRouteSafetyValidator.Publish(
	report
)
	report =
		type(report) == "table"
			and report
			or {}

	workspace:SetAttribute(
		"DungeonRouteValidationReady",
		true
	)

	workspace:SetAttribute(
		"DungeonRouteValidationPassed",
		report.Passed == true
	)

	workspace:SetAttribute(
		"DungeonRouteValidationVersion",
		report.Version or 2
	)

	workspace:SetAttribute(
		"DungeonRouteValidationMode",
		"LinearCombatRouteV1"
	)

	workspace:SetAttribute(
		"DungeonRouteValidationErrorCount",
		report.ErrorCount or 0
	)

	workspace:SetAttribute(
		"DungeonRouteValidationError",
		report.ErrorCode
	)

	workspace:SetAttribute(
		"DungeonRouteValidationMessage",
		report.ErrorMessage
	)

	workspace:SetAttribute(
		"DungeonRouteValidationNodeKey",
		report.ErrorNodeKey
	)

	workspace:SetAttribute(
		"DungeonRouteValidationTargetKey",
		report.ErrorTargetKey
	)

	workspace:SetAttribute(
		"DungeonValidatedPhysicalIslandCount",
		report.NodeCount or 0
	)

	workspace:SetAttribute(
		"DungeonValidatedMandatoryIslandCount",
		report.MandatoryNodeCount or 0
	)

	workspace:SetAttribute(
		"DungeonValidatedOptionalIslandCount",
		report.OptionalNodeCount or 0
	)

	workspace:SetAttribute(
		"DungeonValidatedRoundExitCount",
		report.RoundExitCount or 0
	)

	workspace:SetAttribute(
		"DungeonValidatedConnectionCount",
		report.ConnectionCount or 0
	)

	workspace:SetAttribute(
		"DungeonValidatedReachableIslandCount",
		report.ReachableNodeCount or 0
	)

	workspace:SetAttribute(
		"DungeonValidatedTerminalIslandCount",
		report.TerminalCount or 0
	)
end

return table.freeze(
	DungeonLinearRouteSafetyValidator
)
