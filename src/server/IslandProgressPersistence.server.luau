-- Persistencia individual da rota de ilhas.
-- O mundo/combate continua coletivo, mas concluir uma ilha somente avanca o
-- perfil de quem estava na sua propria proxima ilha (ou elegivel na rota do
-- grupo). Visitas nunca desbloqueiam ilhas para o convidado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(
	ServerScriptService.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local PartyService = require(ServerScriptService.BlockParkour:WaitForChild("PartyService"))
local DungeonGenerator = require(ServerScriptService.DungeonRuntime:WaitForChild("DungeonGenerator"))
local DungeonSpawnService = require(ServerScriptService.DungeonRuntime:WaitForChild("DungeonSpawnService"))
local IslandProgressionConfig = require(ReplicatedStorage.Shared.Configs.IslandProgressionConfig)

local lastClearSerial = 0
local resumeTokens = setmetatable({}, { __mode = "k" })

-- Criar uma rota longa pode levar mais que os poucos segundos usados pela
-- primeira versao. O tempo maior evita mandar o jogador de volta para a ilha
-- inicial apenas porque a proxima ilha ainda esta sendo materializada.
local RESUME_TIMEOUT_SECONDS = 30
local RESUME_RETRY_INTERVAL_SECONDS = 0.25

local function cleanIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function routeCap()
	local plan = DungeonGenerator.GetRoutePlan()
	return math.max(2, math.floor(tonumber(plan and plan.TotalIslandCount) or 2))
end

local function applyAttributes(player, progress)
	local highest = math.max(0, math.floor(tonumber(progress.HighestCompletedGlobalIslandIndex) or 0))
	local resume = cleanIndex(progress.ResumeGlobalIslandIndex)
	player:SetAttribute("SavedHighestCompletedIslandIndex", highest)
	player:SetAttribute("SavedResumeIslandIndex", resume)
	player:SetAttribute("SavedResumeCycleIndex", IslandProgressionConfig.GetCycleIndex(resume))
	player:SetAttribute("IslandProgressPersistenceReady", true)
end

local function loadProgress(player)
	PlayerDataService.Load(player)
	local progress = PlayerDataService.GetIslandProgress(player)
	if progress then
		applyAttributes(player, progress)
	end
	return progress
end

local function progressionEligible(player, islandIndex)
	local resume = cleanIndex(player:GetAttribute("SavedResumeIslandIndex"))
	if resume ~= islandIndex then
		return false
	end
	local coop = PartyService.GetCoopState(player)
	if not coop then
		return true
	end
	return coop.TargetIslandIndex == islandIndex and coop.ProgressionEligible == true
end

local function commitClearForEligiblePlayers(islandIndex)
	for _, player in ipairs(Players:GetPlayers()) do
		if math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0) == islandIndex
			and progressionEligible(player, islandIndex)
		then
			local nextIndex = math.min(routeCap(), islandIndex + 1)
			local success, progress = PlayerDataService.SetIslandProgress(player, islandIndex, nextIndex)
			if success and progress then
				applyAttributes(player, progress)
				player:SetAttribute("LastPersonalIslandCompleted", islandIndex)
				player:SetAttribute("LastPersonalIslandCompletedAt", workspace:GetServerTimeNow())
				player:SetAttribute("LastPersonalIslandCompletionPolicy", "OwnNextIslandOnly")
				task.spawn(PlayerDataService.Save, player, false)
			end
		end
	end
end

local function processClear()
	local serial = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackSerial")) or 0))
	if serial <= lastClearSerial then
		return
	end
	lastClearSerial = serial
	local islandIndex = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackIsland")) or 0))
	if islandIndex >= 2 then
		commitClearForEligiblePlayers(islandIndex)
	end
end

local function resumeAtPersonalIsland(player)
	local resume = math.min(cleanIndex(player:GetAttribute("SavedResumeIslandIndex")), routeCap())
	local token = (resumeTokens[player] or 0) + 1
	resumeTokens[player] = token
	local deadline = os.clock() + RESUME_TIMEOUT_SECONDS

	player:SetAttribute("DungeonPersonalResumeSucceeded", false)
	player:SetAttribute("DungeonPersonalResumeRequestedIndex", resume)
	player:SetAttribute("DungeonPersonalResumeState", "RequestingRoute")
	player:SetAttribute("DungeonPersonalResumeError", nil)
	player:SetAttribute("DungeonPersonalResumeStartedAt", workspace:GetServerTimeNow())

	local requested, requestResult = DungeonGenerator.RequestRouteThrough(resume)
	if not requested then
		player:SetAttribute("DungeonPersonalResumeState", "Failed")
		player:SetAttribute("DungeonPersonalResumeError", tostring(requestResult or "RouteRequestFailed"))
		return false
	end

	repeat
		if player.Parent ~= Players or resumeTokens[player] ~= token then
			return false
		end
		local context = DungeonGenerator.GetRouteIslandContext(resume)
		if not context then
			player:SetAttribute("DungeonPersonalResumeState", "WaitingForIsland")
			player:SetAttribute("DungeonPersonalResumeError", "RouteIslandNotMaterialized")
		elseif not context.SafeSpawn then
			player:SetAttribute("DungeonPersonalResumeState", "WaitingForSafeSpawn")
			player:SetAttribute("DungeonPersonalResumeError", "SafeSpawnUnavailable")
		elseif not player.Character then
			player:SetAttribute("DungeonPersonalResumeState", "WaitingForCharacter")
			player:SetAttribute("DungeonPersonalResumeError", "CharacterUnavailable")
		else
			player:SetAttribute("DungeonPersonalResumeState", "Positioning")
			local positioned, positionError = DungeonSpawnService.PositionPlayerAt(player, context, "PersonalIslandResume")
			if positioned then
				-- So atualizamos o checkpoint logico depois de confirmar que o
				-- personagem chegou fisicamente a ilha salva.
				player:SetAttribute("CurrentGlobalIslandIndex", resume)
				player:SetAttribute("CurrentIslandKey", context.Key)
				player:SetAttribute("DungeonPersonalResumeSucceeded", true)
				player:SetAttribute("DungeonPersonalResumeState", "Succeeded")
				player:SetAttribute("DungeonPersonalResumeError", nil)
				player:SetAttribute("DungeonLastRespawnIslandIndex", resume)
				player:SetAttribute("DungeonLastRespawnPositionedAt", workspace:GetServerTimeNow())
				return true
			end
			player:SetAttribute("DungeonPersonalResumeState", "WaitingToPosition")
			player:SetAttribute("DungeonPersonalResumeError", tostring(positionError or "PositioningFailed"))
		end
		task.wait(RESUME_RETRY_INTERVAL_SECONDS)
	until os.clock() >= deadline
	player:SetAttribute("DungeonPersonalResumeSucceeded", false)
	player:SetAttribute("DungeonPersonalResumeState", "Failed")
	player:SetAttribute("DungeonPersonalResumeError", "ResumeTimeout")
	return false
end

local function bindPlayer(player)
	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		-- A ilha inicial e somente o ponto de partida. Ao entrar na primeira
		-- arena, ela passa a ser o checkpoint pessoal mesmo antes da conclusao.
		local current = math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")) or 0)
		if current >= 2 and cleanIndex(player:GetAttribute("SavedResumeIslandIndex")) == 1 then
			local success, progress = PlayerDataService.SetIslandProgress(player, 1, 2)
			if success and progress then
				applyAttributes(player, progress)
				task.spawn(PlayerDataService.Save, player, false)
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		-- Cada NOVO personagem precisa ser reposicionado no checkpoint pessoal.
		-- DungeonPersonalResumeSucceeded pertence ao personagem anterior e nao
		-- pode impedir o reposicionamento depois de uma morte/respawn.
		player:SetAttribute("DungeonPersonalResumeSucceeded", false)
		task.delay(0.5, function()
			if player.Parent == Players
				and player:GetAttribute("IslandProgressPersistenceReady") == true
				and cleanIndex(player:GetAttribute("SavedResumeIslandIndex")) > 1
				and workspace:GetAttribute("DungeonStandaloneWorldReady") == true
			then
				resumeAtPersonalIsland(player)
			end
		end)
	end)
	task.spawn(function()
		local progress = loadProgress(player)
		if not progress then
			return
		end
		while player.Parent == Players and workspace:GetAttribute("DungeonStandaloneWorldReady") ~= true do
			task.wait(0.2)
		end
		if player.Parent == Players then
			resumeAtPersonalIsland(player)
		end
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

workspace:GetAttributeChangedSignal("DungeonIslandClearFeedbackSerial"):Connect(processClear)
processClear()
