-- Funil de ativacao inicial separado do onboarding historico.
--
-- O funil existente em GameplayAnalyticsService continua registrando a jornada
-- detalhada. Este controlador cria o funil "CoreActivationV1" para responder
-- rapidamente onde novos jogadores abandonam os principais sistemas do MVP.
-- Eventos que acontecem fora de ordem ficam marcados localmente e somente sao
-- enviados quando todos os passos anteriores foram atingidos. Isso evita que o
-- Analytics do Roblox considere passos intermediarios como concluidos por salto.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))
local PlayerDataService = require(
	script.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)

GameplayAnalytics.Start()

local ANALYTICS_CONFIG = MVPConfig.Analytics or {}
local FUNNEL_NAME = "CoreActivationV1"
local VERSION = "CoreActivationAnalyticsV1"
local OBSERVATION_SECONDS = 0.25

local STEPS = table.freeze({
	[1] = "PlayerJoined",
	[2] = "GameStarted",
	[3] = "TutorialStarted",
	[4] = "TutorialFinished",
	[5] = "FirstEnemyDefeated",
	[6] = "FirstChestOpened",
	[7] = "FirstRewardWheelSpin",
	[8] = "FirstCompanionObtained",
	[9] = "FirstSkyMerchantOpened",
	[10] = "ReachedSecondIsland",
	[11] = "FirstExpeditionCompleted",
})

local states = setmetatable({}, { __mode = "k" })

workspace:SetAttribute("CoreActivationAnalyticsVersion", VERSION)
workspace:SetAttribute("CoreActivationFunnelName", FUNNEL_NAME)
workspace:SetAttribute("CoreActivationFunnelStepCount", #STEPS)

local function clean(value, fallback)
	local result = tostring(value or fallback or "Unknown")
	result = string.gsub(result, "[%c]", "")
	if #result > 50 then
		result = string.sub(result, 1, 50)
	end
	return result ~= "" and result or tostring(fallback or "Unknown")
end

local function fields(player, source)
	local tutorialOutcome = clean(player:GetAttribute("TutorialCompletionOutcome"), "Pending")
	local currentLevel = math.max(
		0,
		math.floor(
			tonumber(player:GetAttribute("CurrentLogicalLevel"))
				or tonumber(player:GetAttribute("CurrentRoundIndex"))
				or 0
		)
	)
	return {
		CustomField01 = tutorialOutcome,
		CustomField02 = "Level" .. tostring(currentLevel),
		CustomField03 = clean(source, "ServerValidated"),
	}
end

local function debugLog(message)
	if ANALYTICS_CONFIG.DebugLogs == true then
		print("[CoreActivationAnalytics] " .. message)
	end
end

local function safeCall(label, callback)
	if ANALYTICS_CONFIG.Enabled == false then
		return false
	end
	local success, errorMessage = pcall(callback)
	if not success then
		if ANALYTICS_CONFIG.DebugLogs == true then
			warn(string.format(
				"[CoreActivationAnalytics] %s falhou: %s",
				label,
				tostring(errorMessage)
			))
		end
		return false
	end
	return true
end

local function logOutcomeOnce(player, state)
	if state.TutorialOutcomeLogged or player:GetAttribute("TutorialCompleted") ~= true then
		return
	end
	state.TutorialOutcomeLogged = true
	local skipped = player:GetAttribute("TutorialSkipped") == true
	local eventName = skipped and "TutorialSkipped" or "TutorialCompleted"
	GameplayAnalytics.RecordCustom(
		player,
		eventName,
		math.max(0, math.floor(os.clock() - state.JoinedAt + 0.5)),
		clean(player:GetAttribute("TutorialCompletionOutcome"), skipped and "Skipped" or "Completed"),
		"CoreActivationV1",
		"ServerValidated",
		true
	)
end

local function drain(player, state)
	if not state.Eligible or player.Parent ~= Players then
		return
	end
	while state.HighestStep < #STEPS do
		local nextStep = state.HighestStep + 1
		local achievement = state.Achieved[nextStep]
		if not achievement then
			break
		end
		local stepName = STEPS[nextStep]
		state.HighestStep = nextStep
		player:SetAttribute("CoreActivationAnalyticsStep", nextStep)
		player:SetAttribute("CoreActivationAnalyticsStage", stepName)
		player:SetAttribute("CoreActivationAnalyticsLastStepAt", workspace:GetServerTimeNow())
		safeCall("Funnel:" .. stepName, function()
			-- funnelSessionId nil transforma este funil em uma jornada unica por
			-- usuario. Repeticoes do mesmo passo sao ignoradas pelo Roblox.
			AnalyticsService:LogFunnelStepEvent(
				player,
				FUNNEL_NAME,
				nil,
				nextStep,
				stepName,
				achievement.Fields
			)
		end)
		debugLog(string.format("%s atingiu %d/%d %s", player.Name, nextStep, #STEPS, stepName))
	end
end

local function mark(player, state, step, source)
	if not state.Eligible or state.Achieved[step] then
		return false
	end
	state.Achieved[step] = {
		At = workspace:GetServerTimeNow(),
		Source = source,
		Fields = fields(player, source),
	}

	-- Os marcos que ainda nao existiam no servico historico tambem ficam
	-- disponiveis na pagina de eventos personalizados.
	if step == 7 then
		GameplayAnalytics.RecordCustom(
			player,
			"FirstRewardWheelSpin",
			math.max(0, math.floor(os.clock() - state.JoinedAt + 0.5)),
			clean(player:GetAttribute("LastRewardWheelSource"), "RewardWheel"),
			clean(player:GetAttribute("LastRewardWheelCategory"), "UnknownReward"),
			"CoreActivationV1",
			true
		)
	elseif step == 9 then
		GameplayAnalytics.RecordMerchantOpened(player, "SkyMerchant")
	end

	drain(player, state)
	return true
end

local function onboardingStep(player)
	return math.max(0, math.floor(tonumber(player:GetAttribute("AnalyticsOnboardingStep")) or 0))
end

local function syncMilestones(player, state)
	if not state.Eligible or player.Parent ~= Players then
		return
	end

	mark(player, state, 1, "PlayerAdded")

	if player:GetAttribute("InitialGameStarted") == true then
		mark(player, state, 2, "InitialGameStarted")
	end

	if player:GetAttribute("TutorialActive") == true
		or player:GetAttribute("TutorialCompleted") == true
	then
		mark(player, state, 3, "TutorialState")
	end

	if player:GetAttribute("TutorialCompleted") == true then
		mark(
			player,
			state,
			4,
			player:GetAttribute("TutorialSkipped") == true and "TutorialSkipped" or "TutorialCompleted"
		)
		logOutcomeOnce(player, state)
	end

	local existingStep = onboardingStep(player)
	if existingStep >= 7
		or (tonumber(player:GetAttribute("SwordKillCount")) or 0) > 0
		or tostring(player:GetAttribute("AnalyticsOnboardingStage") or "") == "FirstEnemyDefeated"
	then
		mark(player, state, 5, "CombatValidated")
	end

	if existingStep >= 9
		or (tonumber(player:GetAttribute("OfferSignal_Chests")) or 0) > 0
		or tostring(player:GetAttribute("AnalyticsOnboardingStage") or "") == "FirstChestOpened"
	then
		mark(player, state, 6, "ChestValidated")
	end

	local wheelSerial = math.max(0, math.floor(tonumber(player:GetAttribute("LastRewardWheelSerial")) or 0))
	if wheelSerial > 0 then
		mark(player, state, 7, clean(player:GetAttribute("LastRewardWheelSource"), "RewardWheel"))
	end

	if existingStep >= 11
		or (tonumber(player:GetAttribute("OfferSignal_Captures")) or 0) > 0
		or player:GetAttribute("LastCapturedCompanionInstanceId") ~= nil
		or (wheelSerial > 0 and player:GetAttribute("LastRewardWheelCategory") == "Companion")
		or tostring(player:GetAttribute("AnalyticsOnboardingStage") or "") == "FirstCompanionObtained"
	then
		mark(player, state, 8, "CompanionValidated")
	end

	if player:GetAttribute("ShopOpen") == true
		and tostring(player:GetAttribute("ActiveShopId") or "") == "SkyMerchant"
	then
		mark(player, state, 9, "SkyMerchantPrompt")
	end

	local logicalLevel = tonumber(player:GetAttribute("CurrentLogicalLevel"))
		or tonumber(player:GetAttribute("CurrentRoundIndex"))
		or 0
	if logicalLevel >= 2 or existingStep >= 13 then
		mark(player, state, 10, "NaturalProgress")
	end

	if existingStep >= 16
		or tostring(player:GetAttribute("AnalyticsOnboardingStage") or "") == "FirstExpeditionCompleted"
	then
		mark(player, state, 11, "CoreLoopComplete")
	end
end

local OBSERVED_ATTRIBUTES = table.freeze({
	"InitialGameStarted",
	"TutorialActive",
	"TutorialCompleted",
	"TutorialSkipped",
	"TutorialCompletionOutcome",
	"SwordKillCount",
	"OfferSignal_Chests",
	"OfferSignal_Captures",
	"LastRewardWheelSerial",
	"LastRewardWheelSource",
	"LastRewardWheelCategory",
	"LastCapturedCompanionInstanceId",
	"ShopOpen",
	"ActiveShopId",
	"CurrentLogicalLevel",
	"CurrentRoundIndex",
	"AnalyticsOnboardingStep",
	"AnalyticsOnboardingStage",
})

local function setupPlayer(player)
	if states[player] then
		return
	end
	local state = {
		JoinedAt = os.clock(),
		Eligible = false,
		HighestStep = 0,
		Achieved = {},
		TutorialOutcomeLogged = false,
	}
	states[player] = state
	player:SetAttribute("CoreActivationAnalyticsVersion", VERSION)
	player:SetAttribute("CoreActivationAnalyticsEligible", false)
	player:SetAttribute("CoreActivationAnalyticsStep", 0)
	player:SetAttribute("CoreActivationAnalyticsStage", "LoadingPlayerData")

	for _, attributeName in ipairs(OBSERVED_ATTRIBUTES) do
		player:GetAttributeChangedSignal(attributeName):Connect(function()
			local current = states[player]
			if current == state then
				syncMilestones(player, state)
			end
		end)
	end

	task.spawn(function()
		PlayerDataService.Load(player)
		if player.Parent ~= Players or states[player] ~= state then
			return
		end
		local previouslyCompleted = PlayerDataService.GetAnalyticsOnboardingCompleted(player) == true
		state.Eligible = not previouslyCompleted
		player:SetAttribute("CoreActivationAnalyticsEligible", state.Eligible)
		if not state.Eligible then
			player:SetAttribute("CoreActivationAnalyticsStage", "ExistingCompletedPlayerIgnored")
			return
		end
		player:SetAttribute("CoreActivationAnalyticsStage", "Ready")
		syncMilestones(player, state)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

task.spawn(function()
	while true do
		task.wait(OBSERVATION_SECONDS)
		for player, state in pairs(states) do
			if player.Parent == Players then
				syncMilestones(player, state)
			end
		end
	end
end)

if RunService:IsStudio() then
	print("[CoreActivationAnalytics] Studio detectado: atributos de diagnostico funcionam, eventos Roblox nao aparecem no painel.")
end

print("[CoreActivationAnalytics] " .. VERSION .. " iniciado com funil " .. FUNNEL_NAME .. ".")
