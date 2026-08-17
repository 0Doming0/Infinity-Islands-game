-- Fluxo linear de progressao:
-- SITUAÇÃO ATUAL concluida -> ilha concluida -> AVANÇAR.
--
-- A ilha inicial e as demais usam a mesma regra de conclusao. Este bridge usa
-- exatamente a mesma fonte autoritativa enviada ao HUD (MonsterSpawner) e
-- publica Cleared no modelo para os sistemas de progressao/transporte antigos
-- nao precisarem conhecer diferencas entre tutorial/inicial/ilha numerada.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MonsterSpawner = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("MonsterSpawner")
)
local DungeonGenerator = require(
	ServerScriptService:WaitForChild("DungeonRuntime"):WaitForChild("DungeonGenerator")
)

local VERSION = "LinearIslandObjectiveBridgeV2_NoRecommendedLevel"
local POLL_SECONDS = 0.08
local elapsed = 0

local function cleanIndex(value)
	local number = math.floor(tonumber(value) or 1)
	return math.max(1, number)
end

local function objectiveComplete(index)
	local ok, state = pcall(MonsterSpawner.GetObjectiveState, index)
	if not ok or type(state) ~= "table" then
		return false, nil
	end
	if state.Cleared == true then
		return true, state
	end
	if state.Ready ~= true then
		return false, state
	end

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

	return hadObjective, state
end

local function islandModel(index)
	local ok, context = pcall(DungeonGenerator.GetRouteIslandContext, index)
	if not ok or type(context) ~= "table" then
		return nil
	end
	local island = context.IslandModel or context.Model
	return typeof(island) == "Instance" and island:IsA("Model") and island or nil
end

local function publishPlayer(player)
	if player.Parent ~= Players then
		return
	end

	local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local complete, state = objectiveComplete(index)

	player:SetAttribute("DungeonLinearObjectiveIsland", index)
	player:SetAttribute("DungeonLinearObjectiveComplete", complete)
	player:SetAttribute("DungeonLinearObjectivePolicy", "ClearCurrentSituationThenAdvance")

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
		-- Idempotente. Se IslandCombatService ja publicou a conclusao, nada muda.
		-- Se a ilha inicial usou um caminho legado, isto normaliza para a mesma
		-- representacao esperada pelas ilhas seguintes.
		if island:GetAttribute("Cleared") ~= true then
			island:SetAttribute("Cleared", true)
		end
		island:SetAttribute("CombatRouteCleared", true)
		island:SetAttribute("CombatExitLocked", false)
		island:SetAttribute("LinearObjectiveComplete", true)
		island:SetAttribute("LinearObjectivePolicy", "SituationCompleteMeansCleared")
	end
end

local function enforceLinearPolicy()
	-- CombatRouteProgressionService legado ainda publica estes atributos em alguns
	-- refreshes. Mantemos explicitamente desligados para que nenhuma UI ou sistema
	-- volte a tratar nivel recomendado como requisito de progressao.
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
enforceLinearPolicy()
