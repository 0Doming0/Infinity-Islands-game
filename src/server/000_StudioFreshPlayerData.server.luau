-- StudioFreshPlayerData
--
-- Em qualquer Play/Test executado dentro do Roblox Studio, a experiencia deve
-- comecar como a de um jogador novo. O reset acontece UMA unica vez por jogador
-- em cada sessao de Play; depois disso Load() e somente pass-through para que XP,
-- level, ilha liberada e demais progressos conquistados durante o teste funcionem.
--
-- Dados de Studio continuam temporarios: nenhum Save/resultado e persistido.
-- Em servidores publicados este script encerra imediatamente e nao altera nada.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local PlayerDataService = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("PlayerDataService_SkyDungeon_V10")
)

local originalLoad = PlayerDataService.Load
local resetPlayers = setmetatable({}, { __mode = "k" })
local VERSION = "FreshBeginnerV2_InitializeOnce"

local function freshData()
	return {
		SchemaVersion = 15,
		Coins = 0,
		Stamina = 0,
		BestScore = 0,
		OwnedSwords = {
			ClassicSword = true,
		},
		EquippedSword = "ClassicSword",
		OwnedWings = {},
		EquippedWings = nil,
		OwnedAbilities = {},
		EquippedAbility = nil,
		OwnedRelics = {},
		EquippedRelic = nil,
		OwnedCompanions = {},
		EquippedCompanions = {},
		CompanionEquipSlots = CompanionCatalog.InitialEquippedSlots,
		Inventory = {},
		-- Marcamos a migracao como concluida somente nesta memoria temporaria para
		-- impedir qualquer caminho legado de tentar acrescentar dados antigos.
		LegacyMVPMigrated = true,
		TutorialStage = 1,
		TutorialCompleted = false,
		AnalyticsOnboardingCompleted = false,
		DailyLastClaimDay = 0,
		DailyStreak = 0,
		Tickets = {
			LuckyWheelSpin = 0,
		},
		Progression = {
			Phases = {
				Phase01 = { Completions = 0, BossDefeated = false, BestTime = nil },
				Phase02 = { Completions = 0, BossDefeated = false, BestTime = nil },
			},
		},
		IslandProgress = {
			HighestCompletedGlobalIslandIndex = 0,
			ResumeGlobalIslandIndex = 1,
		},
		LevelProgress = {
			Level = 1,
			XP = 0,
			TotalXP = 0,
		},
		OrbProgression = {
			Version = "",
			Orbs = {},
			EquippedOrbs = {},
			ClaimedMilestones = {},
			ChoicesCompleted = 0,
		},
		Roulette = {
			TotalSpins = 0,
			LastSpinAt = 0,
		},
		DungeonRewards = {
			ProcessedGrantIds = {},
		},
		DungeonResults = {
			ProcessedResultIds = {},
			LastResult = nil,
		},
		Monetization = {
			TreasureBoostUntil = 0,
			EliteBoostUntil = 0,
			PendingReviveLostCoins = 0,
			PendingReviveSerial = 0,
			PendingSpinAgainSource = "",
			PendingSpinAgainLevel = 0,
			ProcessedPurchaseIds = {},
		},
	}
end

local function replaceDataInPlace(data)
	if type(data) ~= "table" then
		return
	end
	table.clear(data)
	for key, value in pairs(freshData()) do
		data[key] = value
	end
end

local function publishFreshAttributes(player)
	if player.Parent ~= Players then
		return
	end

	player:SetAttribute("StudioFreshPlayerData", true)
	player:SetAttribute("StudioFreshPlayerDataVersion", VERSION)
	player:SetAttribute("StudioFreshPlayerDataInitializedOnce", true)
	player:SetAttribute("StudioFreshPlayerDataResetCount", 1)
	player:SetAttribute("StudioFreshPlayerDataInitializedAt", Workspace:GetServerTimeNow())
	player:SetAttribute("PlayerDataLoaded", true)
	player:SetAttribute("PlayerDataTemporary", true)
	player:SetAttribute("Coins", 0)
	player:SetAttribute("Stamina", 0)
	player:SetAttribute("PlayerLevel", 1)
	player:SetAttribute("PlayerXP", 0)
	player:SetAttribute("PlayerTotalXP", 0)
	player:SetAttribute("CurrentGlobalIslandIndex", 1)
	player:SetAttribute("TutorialStage", 1)
	player:SetAttribute("TutorialCompleted", false)
	player:SetAttribute("EquippedOrb", nil)
	player:SetAttribute("EquippedOrb2", nil)
	player:SetAttribute("EquippedOrbs", "")
	player:SetAttribute("OrbChoicesCompleted", 0)
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceState", "None")

	for _, orbName in ipairs({ "Fire", "Ice", "Shadow" }) do
		player:SetAttribute(orbName .. "OrbLevel", 0)
		player:SetAttribute(orbName .. "OrbXP", 0)
	end
end

local function clearStaleRuntimeObjects(player)
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model")
			and instance:GetAttribute("IsCompanion") == true
			and tonumber(instance:GetAttribute("CompanionOwnerUserId")) == player.UserId
		then
			instance:Destroy()
		end
	end
end

local function resetPlayerOnce(player)
	local data = originalLoad(player)

	-- CRITICO: depois do primeiro reset desta sessao, nunca publique novamente
	-- Level=1/XP=0. Muitos servicos chamam Load() durante o gameplay e isso nao
	-- pode apagar o progresso conquistado alguns segundos antes.
	if resetPlayers[player] then
		if player.Parent == Players then
			player:SetAttribute("StudioFreshPlayerDataLoadPolicy", "PassThroughAfterInitialReset")
		end
		return data
	end

	resetPlayers[player] = true
	replaceDataInPlace(data)
	publishFreshAttributes(player)
	clearStaleRuntimeObjects(player)

	if player.Parent == Players then
		player:SetAttribute("StudioFreshPlayerDataLoadPolicy", "PassThroughAfterInitialReset")
	end

	return data
end

-- Todos os consumidores do ModuleScript compartilham esta mesma tabela.
-- A primeira chamada cria o snapshot iniciante; chamadas seguintes preservam
-- integralmente o progresso feito dentro desta mesma sessao de Play.
PlayerDataService.Load = function(player)
	return resetPlayerOnce(player)
end

-- No Studio, salvar deve parecer bem-sucedido para os sistemas chamadores,
-- mas sem tocar no DataStore real.
PlayerDataService.Save = function(_player, _force)
	return true
end

PlayerDataService.CanSave = function(_player)
	return true
end

-- Estes dois caminhos normalmente usam UpdateAsync diretamente. No Studio eles
-- tambem sao neutralizados para garantir que nenhum resultado de teste persista.
PlayerDataService.CommitDungeonResult = function(_player, _resultId, _payload)
	return true, true, nil, nil
end

PlayerDataService.CommitDungeonResultByUserId = function(_userId, _resultId, _payload)
	return true, true, nil, nil
end

local function setup(player)
	task.spawn(function()
		resetPlayerOnce(player)
	end)
end

Players.PlayerAdded:Connect(setup)
Players.PlayerRemoving:Connect(function(player)
	resetPlayers[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	setup(player)
end

Workspace:SetAttribute("DungeonStudioFreshPlayerDataEnabled", true)
Workspace:SetAttribute("DungeonStudioFreshPlayerDataVersion", VERSION)
Workspace:SetAttribute("DungeonStudioFreshPlayerDataResetPolicy", "OncePerPlaySession")
print("[StudioFreshPlayerData] Perfil iniciante aplicado uma vez; progresso da sessao preservado.")
