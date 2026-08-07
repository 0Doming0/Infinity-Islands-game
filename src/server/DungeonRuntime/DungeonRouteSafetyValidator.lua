local IslandGraphPlanner = require(script.Parent.Parent.BlockParkour.IslandGraphPlanner)

local DungeonRouteSafetyValidator = {}

local MAX_REPORTED_ERRORS = 32

local function addError(report, code, message, nodeKey, targetKey)
	report.ErrorCount += 1
	if not report.ErrorCode then
		report.ErrorCode = code
		report.ErrorMessage = message
		report.ErrorNodeKey = nodeKey
		report.ErrorTargetKey = targetKey
	end
	if #report.Errors < MAX_REPORTED_ERRORS then
		table.insert(report.Errors, {
			Code = code,
			Message = message,
			NodeKey = nodeKey,
			TargetKey = targetKey,
		})
	end
end

local function isInteger(value)
	return typeof(value) == "number" and value == math.floor(value)
end

local function connectionExists(connections, sourceKey, targetKey, directionId, isIncoming)
	for _, connection in ipairs(type(connections) == "table" and connections or {}) do
		local matchingKey = isIncoming and connection.SourceKey or connection.TargetKey
		local expectedKey = isIncoming and sourceKey or targetKey
		if matchingKey == expectedKey and connection.DirectionId == directionId then
			return true
		end
	end
	return false
end

local function validateConnectionCells(report, source, target, directionId)
	local success, planOrError = pcall(
		IslandGraphPlanner.PlanConnection,
		source,
		target,
		directionId
	)
	if not success then
		addError(report, "ConnectionPlanInvalid", tostring(planOrError), source.Key, target.Key)
		return false
	end
	local cells = planOrError.Cells
	if type(cells) ~= "table" or #cells < 3 then
		addError(
			report,
			"ConnectionTooShort",
			"A conexao precisa possuir ao menos uma celula fisica entre as ilhas.",
			source.Key,
			target.Key
		)
		return false
	end
	for index = 2, #cells do
		local delta = cells[index] - cells[index - 1]
		local horizontal = math.abs(delta.X) + math.abs(delta.Z)
		local vertical = delta.Y
		if horizontal ~= 1 or vertical < 0 or vertical > 1 then
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

local function reachableFrom(startKey, adjacency)
	local visited = { [startKey] = true }
	local queue = { startKey }
	local head = 1
	while head <= #queue do
		local key = queue[head]
		head += 1
		for _, targetKey in ipairs(adjacency[key] or {}) do
			if not visited[targetKey] then
				visited[targetKey] = true
				table.insert(queue, targetKey)
			end
		end
	end
	return visited
end

local function canReachExit(startKey, exitKey, adjacency, allowed)
	if startKey == exitKey then
		return true
	end
	local visited = { [startKey] = true }
	local queue = { startKey }
	local head = 1
	while head <= #queue do
		local key = queue[head]
		head += 1
		for _, targetKey in ipairs(adjacency[key] or {}) do
			if targetKey == exitKey then
				return true
			end
			if allowed[targetKey] and not visited[targetKey] then
				visited[targetKey] = true
				table.insert(queue, targetKey)
			end
		end
	end
	return false
end

function DungeonRouteSafetyValidator.Validate(routePlan)
	local report = {
		Version = 1,
		Passed = false,
		ErrorCount = 0,
		Errors = {},
		NodeCount = 0,
		MandatoryNodeCount = 0,
		OptionalNodeCount = 0,
		RoundExitCount = 0,
		ConnectionCount = 0,
		ReachableNodeCount = 0,
	}
	if type(routePlan) ~= "table" then
		addError(report, "RoutePlanMissing", "O planejamento da rota nao existe.")
		return false, report
	end
	local routeNodes = type(routePlan.Nodes) == "table" and routePlan.Nodes or {}
	local boss = type(routePlan.BossSanctuary) == "table" and routePlan.BossSanctuary or nil
	if #routeNodes == 0 then
		addError(report, "RouteNodesMissing", "A rota nao possui ilhas planejadas.")
		return false, report
	end
	if not boss or type(boss.Key) ~= "string" then
		addError(report, "BossSanctuaryMissing", "O santuario do boss nao foi planejado.")
	end

	local nodeByKey = {}
	local orderedNodes = {}
	local startNode
	local mandatoryByGlobalIndex = {}
	local roundNodes = {}
	local roundExits = {}

	for order, spec in ipairs(routeNodes) do
		report.NodeCount += 1
		if type(spec) ~= "table" or type(spec.Key) ~= "string" or spec.Key == "" then
			addError(report, "NodeKeyMissing", "Ilha planejada sem Key valido.")
			continue
		end
		if nodeByKey[spec.Key] then
			addError(report, "DuplicateNodeKey", "Duas ilhas usam a mesma Key.", spec.Key)
			continue
		end
		if spec.RouteNodeOrder ~= order then
			addError(
				report,
				"RouteNodeOrderInvalid",
				"RouteNodeOrder nao corresponde a ordem de materializacao.",
				spec.Key
			)
		end
		if not isInteger(spec.LaneX) or not isInteger(spec.LaneZ) or not isInteger(spec.Level) then
			addError(report, "NodeCoordinateInvalid", "Coordenada logica invalida.", spec.Key)
		end
		nodeByKey[spec.Key] = spec
		table.insert(orderedNodes, spec)
		if spec.IsStart == true then
			if startNode then
				addError(report, "MultipleStartNodes", "A rota possui mais de uma ilha inicial.", spec.Key)
			else
				startNode = spec
			end
		end
		if spec.IsMandatoryRoute == true then
			report.MandatoryNodeCount += 1
			local globalIndex = math.floor(tonumber(spec.GlobalIslandIndex) or 0)
			if globalIndex <= 0 or mandatoryByGlobalIndex[globalIndex] then
				addError(report, "MandatoryIndexInvalid", "GlobalIslandIndex obrigatorio invalido.", spec.Key)
			else
				mandatoryByGlobalIndex[globalIndex] = spec
			end
		elseif spec.IsOptionalRoute == true then
			report.OptionalNodeCount += 1
			if spec.GlobalIslandIndex ~= nil then
				addError(report, "OptionalHasGlobalIndex", "Ilha opcional nao pode possuir objetivo global.", spec.Key)
			end
		end
		local roundIndex = math.floor(tonumber(spec.RoundIndex) or 0)
		if roundIndex <= 0 then
			addError(report, "RoundIndexInvalid", "Ilha sem RoundIndex valido.", spec.Key)
		else
			roundNodes[roundIndex] = roundNodes[roundIndex] or {}
			table.insert(roundNodes[roundIndex], spec)
		end
		if spec.IsRoundExit == true then
			report.RoundExitCount += 1
			if roundExits[roundIndex] then
				addError(report, "MultipleRoundExits", "Round possui mais de uma RoundExit.", spec.Key)
			else
				roundExits[roundIndex] = spec
			end
			if spec.IsMandatoryRoute ~= true or spec.IsRewardIsland ~= true then
				addError(report, "RoundExitRoleInvalid", "RoundExit precisa ser obrigatoria e de recompensa.", spec.Key)
			end
		end
	end

	if boss and type(boss.Key) == "string" then
		if nodeByKey[boss.Key] then
			addError(report, "BossKeyCollision", "Boss usa uma Key ja ocupada.", boss.Key)
		else
			nodeByKey[boss.Key] = boss
			table.insert(orderedNodes, boss)
		end
	end
	if not startNode then
		addError(report, "StartNodeMissing", "A rota nao possui uma ilha inicial.")
	end

	local totalMandatory = math.max(0, math.floor(tonumber(routePlan.TotalIslandCount) or 0))
	for globalIndex = 1, totalMandatory do
		if not mandatoryByGlobalIndex[globalIndex] then
			addError(
				report,
				"MandatorySequenceGap",
				"Falta a ilha obrigatoria global " .. tostring(globalIndex) .. "."
			)
		end
		local materializationIndex = type(routePlan.MaterializationIndexByGlobalIndex) == "table"
			and routePlan.MaterializationIndexByGlobalIndex[globalIndex]
			or nil
		local spec = mandatoryByGlobalIndex[globalIndex]
		if spec and materializationIndex ~= spec.RouteNodeOrder then
			addError(
				report,
				"MaterializationIndexMismatch",
				"Indice fisico e indice obrigatorio estao inconsistentes.",
				spec.Key
			)
		end
	end
	if report.MandatoryNodeCount ~= totalMandatory then
		addError(report, "MandatoryCountMismatch", "Quantidade de ilhas obrigatorias divergente.")
	end
	if math.floor(tonumber(routePlan.PhysicalIslandCount) or 0) ~= #routeNodes then
		addError(report, "PhysicalCountMismatch", "PhysicalIslandCount divergente de Nodes.")
	end
	if math.floor(tonumber(routePlan.OptionalIslandCount) or 0) ~= report.OptionalNodeCount then
		addError(report, "OptionalCountMismatch", "OptionalIslandCount divergente.")
	end

	local adjacency = {}
	local computedInbound = {}
	local edgeKeys = {}
	for _, source in ipairs(orderedNodes) do
		adjacency[source.Key] = adjacency[source.Key] or {}
		local outgoing = type(source.OutgoingConnections) == "table" and source.OutgoingConnections or {}
		if source.IsBossSanctuary ~= true and #outgoing == 0 then
			addError(report, "DeadEndNode", "Ilha sem caminho de continuacao.", source.Key)
		end
		if source.IsOptionalRoute == true and #outgoing ~= 1 then
			addError(report, "OptionalExitCountInvalid", "Ilha opcional precisa possuir uma unica saida.", source.Key)
		end
		for _, edge in ipairs(outgoing) do
			local target = nodeByKey[edge.TargetKey]
			local edgeKey = source.Key .. "__TO__" .. tostring(edge.TargetKey)
			if edgeKeys[edgeKey] then
				addError(report, "DuplicateConnection", "Conexao duplicada.", source.Key, edge.TargetKey)
				continue
			end
			edgeKeys[edgeKey] = true
			report.ConnectionCount += 1
			if not target then
				addError(report, "ConnectionTargetMissing", "Destino da conexao nao existe.", source.Key, edge.TargetKey)
				continue
			end
			if type(edge.DirectionId) ~= "string" then
				addError(report, "ConnectionDirectionMissing", "Conexao sem DirectionId.", source.Key, target.Key)
				continue
			end
			if not connectionExists(target.IncomingConnections, source.Key, target.Key, edge.DirectionId, true) then
				addError(
					report,
					"IncomingConnectionMismatch",
					"O destino nao registra a conexao de entrada correspondente.",
					source.Key,
					target.Key
				)
			end
			validateConnectionCells(report, source, target, edge.DirectionId)
			table.insert(adjacency[source.Key], target.Key)
			computedInbound[target.Key] = (computedInbound[target.Key] or 0) + 1
		end
	end

	for _, spec in ipairs(orderedNodes) do
		local incoming = type(spec.IncomingConnections) == "table" and spec.IncomingConnections or {}
		local actualInbound = computedInbound[spec.Key] or 0
		if spec.IsStart == true then
			if #incoming ~= 0 or actualInbound ~= 0 then
				addError(report, "StartHasInbound", "A ilha inicial nao pode possuir entrada.", spec.Key)
			end
		elseif #incoming == 0 or actualInbound == 0 then
			addError(report, "UnreachableInboundMissing", "Ilha sem conexao de entrada.", spec.Key)
		elseif actualInbound ~= #incoming then
			addError(report, "InboundCountMismatch", "Quantidade de entradas divergente.", spec.Key)
		end
		if spec.IsOptionalRoute == true then
			if #incoming ~= 1 then
				addError(report, "OptionalEntryCountInvalid", "Ilha opcional precisa possuir uma unica entrada.", spec.Key)
			end
			for _, targetKey in ipairs(adjacency[spec.Key] or {}) do
				local target = nodeByKey[targetKey]
				if target and target.RoundIndex ~= spec.RoundIndex then
					addError(report, "OptionalCrossesRound", "Ilha opcional nao pode sair diretamente do round.", spec.Key, targetKey)
				end
			end
		end
	end

	if startNode then
		local reachable = reachableFrom(startNode.Key, adjacency)
		for _, spec in ipairs(orderedNodes) do
			if reachable[spec.Key] then
				report.ReachableNodeCount += 1
			else
				addError(report, "NodeUnreachableFromStart", "Ilha nao pode ser alcancada desde o inicio.", spec.Key)
			end
		end
	end

	local expectedRounds = type(routePlan.RoundLengths) == "table" and #routePlan.RoundLengths or 0
	for roundIndex = 1, expectedRounds do
		local exit = roundExits[roundIndex]
		if not exit then
			addError(report, "RoundExitMissing", "Round sem RoundExit unica: " .. tostring(roundIndex))
			continue
		end
		local configuredExit = type(routePlan.RoundExitGlobalIndices) == "table"
			and routePlan.RoundExitGlobalIndices[roundIndex]
			or nil
		if configuredExit ~= exit.GlobalIslandIndex then
			addError(report, "RoundExitIndexMismatch", "Indice configurado da RoundExit divergente.", exit.Key)
		end
		local allowed = {}
		for _, spec in ipairs(roundNodes[roundIndex] or {}) do
			allowed[spec.Key] = true
		end
		for _, spec in ipairs(roundNodes[roundIndex] or {}) do
			if not canReachExit(spec.Key, exit.Key, adjacency, allowed) then
				addError(
					report,
					"RoundExitUnreachable",
					"Ilha do round nao possui caminho ate a RoundExit.",
					spec.Key,
					exit.Key
				)
			end
		end
	end

	report.Passed = report.ErrorCount == 0
	return report.Passed, report
end

function DungeonRouteSafetyValidator.Publish(report)
	report = type(report) == "table" and report or {}
	workspace:SetAttribute("DungeonRouteValidationReady", true)
	workspace:SetAttribute("DungeonRouteValidationPassed", report.Passed == true)
	workspace:SetAttribute("DungeonRouteValidationVersion", report.Version or 1)
	workspace:SetAttribute("DungeonRouteValidationErrorCount", report.ErrorCount or 0)
	workspace:SetAttribute("DungeonRouteValidationError", report.ErrorCode)
	workspace:SetAttribute("DungeonRouteValidationMessage", report.ErrorMessage)
	workspace:SetAttribute("DungeonRouteValidationNodeKey", report.ErrorNodeKey)
	workspace:SetAttribute("DungeonRouteValidationTargetKey", report.ErrorTargetKey)
	workspace:SetAttribute("DungeonValidatedPhysicalIslandCount", report.NodeCount or 0)
	workspace:SetAttribute("DungeonValidatedMandatoryIslandCount", report.MandatoryNodeCount or 0)
	workspace:SetAttribute("DungeonValidatedOptionalIslandCount", report.OptionalNodeCount or 0)
	workspace:SetAttribute("DungeonValidatedRoundExitCount", report.RoundExitCount or 0)
	workspace:SetAttribute("DungeonValidatedConnectionCount", report.ConnectionCount or 0)
	workspace:SetAttribute("DungeonValidatedReachableIslandCount", report.ReachableNodeCount or 0)
end

return table.freeze(DungeonRouteSafetyValidator)
