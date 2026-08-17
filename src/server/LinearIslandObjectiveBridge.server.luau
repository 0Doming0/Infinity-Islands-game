-- Fluxo linear de progressao:
-- SITUAÇÃO ATUAL concluida -> ilha concluida -> AVANÇAR.
--
-- A ilha inicial e as demais usam exatamente a mesma regra. A conclusao e
-- reconhecida por qualquer uma das fontes autoritativas ja existentes no jogo
-- (estado do MonsterSpawner, atributos da arena ou estado publicado do HUD).
-- Isso evita que a ilha inicial fique presa por usar um caminho de onboarding.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MonsterSpawner = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("MonsterSpawner")
)
local DungeonGenerator = require(
	ServerScriptService:WaitForChild("DungeonRuntime"):WaitForChild("DungeonGenerator")
)

local VERSION = "LinearIslandObjectiveBridgeV3_InitialIslandGuaranteed"
local POLL_SECONDS = 0.06
local elapsed = 0

local function cleanIndex(value)
	local number = math.floor(tonumber(value) or 1)
	return math.max(1, number)
end

local function islandModel(index)
	local ok, context = pcall(DungeonGenerator.GetRouteIslandContext, index)
	if not ok or type(context) ~= "table" then
		return nil
	end
	local island = context.IslandModel or context.Model
	return typeof(island) == "Instance" and island:IsA("Model") and island or nil
end

local function modelSaysComplete(island)
	if not island or not island.Parent then
		return false
	end

	if island:GetAttribute("Cleared") == true
		or island:GetAttribute("CombatRouteCleared") == true
		or island:GetAttribute("LinearObjectiveComplete") == true
	then
		return true
	end

	local target = math.max(0, math.floor(tonumber(
		island:GetAttribute("MobTargetCount")
			or island:GetAttribute("MobKillQuota")
			or island:GetAttribute("ObjectiveTargetCount")
	) or 0))
	local defeated = math.max(0, math.floor(tonumber(
		island:GetAttribute("MobDefeatedCount")
			or island:GetAttribute("ObjectiveDefeatedCount")
	) or 0))
	local alive = math.max(0, math.floor(tonumber(
		island:GetAttribute("MobAliveCount")
			or island:GetAttribute("ObjectiveAliveCount")
	) or 0))

	return target > 0 and defeated >= target and alive <= 0
end

local function workspaceSaysComplete(index)
	local objectiveIndex = tonumber(
		workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or workspace:GetAttribute("DungeonCurrentObjectiveIsland")
	)
	if objectiveIndex
		and cleanIndex(objectiveIndex) == index
		and workspace:GetAttribute("DungeonObjectiveState") == "Completed"
	then
		return true
	end

	local feedbackIsland = tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackIsland"))
	return feedbackIsland ~= nil and cleanIndex(feedbackIsland) == index
end

local function spawnerSaysComplete(index)
	local ok, state = pcall(MonsterSpawner.GetObjectiveState, index)
	if not ok or type(state) ~= "table" then
		return false, state
	end
	if state.Cleared == true then
		return true, state
	end

	-- A propria SITUAÇÃO ATUAL e montada a partir destas variantes. Se todas as
	-- quantidades restantes chegaram a zero, consideramos a arena concluida sem
	-- esperar um segundo caminho especial marcar Cleared.
	if state.Ready == true then
		local hadObjective = false
		for _, entry in ipairs(state.Variants or {}) do
			local initial = math.max(0, math.floor(tonumber(entry.Initial) or 0))
			local remaining = math.max(0, math.floor(tonumber(entry.Remaining) or initial))
			if initial > 0 then
				hadObjective = true
				if remaining > 0 then
					return false, state
				end
			end
		end
		if hadObjective then
			return true, state
		end
	end

	return false, state
end

local function objectiveComplete(index)
	local complete, state = spawnerSaysComplete(index)
	if complete then
		return true, state, "MonsterSpawner"
	end

	local island = islandModel(index)
	if modelSaysComplete(island) then
		return true, state, "IslandModel"
	end

	if workspaceSaysComplete(index) then
		return true, state, "ProgressionState"
	end

	return false, state, nil
end

local function publishPlayer(player)
	if player.Parent ~= Players then
		return
	end

	local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local complete, state, source = objectiveComplete(index)

	player:SetAttribute("DungeonLinearObjectiveIsland", index)
	player:SetAttribute("DungeonLinearObjectiveComplete", complete)
	player:SetAttribute("DungeonLinearObjectivePolicy", "ClearCurrentSituationThenAdvance")
	player:SetAttribute("DungeonLinearObjectiveCompleteSource", source)

	if type(state) == "table" then
		player:SetAttribute("DungeonLinearObjectiveReady", state.Ready == true)
	else
		player:SetAttribute("DungeonLinearObjectiveReady", false)
	end

	if not complete then
		return
	end

	local island = islandModel(index)
	if island and island.Parent then
		-- Normaliza a ilha inicial e qualquer arena futura para a mesma linguagem
		-- consumida pelo transporte: Cleared significa AVANÇAR disponivel.
		island:SetAttribute("Cleared", true)
		island:SetAttribute("CombatRouteCleared", true)
		island:SetAttribute("CombatExitLocked", false)
		island:SetAttribute("LinearObjectiveComplete", true)
		island:SetAttribute("LinearObjectivePolicy", "SituationCompleteMeansCleared")
	end
end

local function enforceLinearPolicy()
	if workspace:GetAttribute("DungeonRecommendedLevelIsHardGate") ~= false then
		workspace:SetAttribute("DungeonRecommendedLevelIsHardGate", false)
	end
	if workspace:GetAttribute("DungeonRecommendedLevelWarningActive") ~= false then
		workspace:SetAttribute("DungeonRecommendedLevelWarningActive", false)
	end
end

local function bindPlayer(player)
	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		task.defer(publishPlayer, player)
	end)
	task.defer(publishPlayer, player)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < POLL_SECONDS then
		return
	end
	elapsed = 0
	enforceLinearPolicy()
	for _, player in ipairs(Players:GetPlayers()) do
		publishPlayer(player)
	end
end)

workspace:SetAttribute("DungeonLinearObjectiveBridgeReady", true)
workspace:SetAttribute("DungeonLinearObjectiveBridgeVersion", VERSION)
workspace:SetAttribute("DungeonLinearProgressionPolicy", "ClearSituationThenAdvance")
workspace:SetAttribute("DungeonInitialIslandAdvanceUsesLinearObjective", true)
enforceLinearPolicy()
