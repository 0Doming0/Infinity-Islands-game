-- Funil do teste pago para o loop atual de Infinity Islands.
-- Mede somente entrar, derrotar mobs, ganhar XP, subir de nivel e avancar.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))

GameplayAnalytics.Start()

local ANALYTICS_CONFIG = MVPConfig.Analytics or {}
local FUNNEL_NAME = "InfinityIslandsCoreLoopV2"
local VERSION = "CoreActivationAnalyticsV2_InfinityIslands"
local OBSERVATION_SECONDS = 0.25
-- O primeiro teste precisa revelar onde a experiencia fica lenta. Cinco ilhas
-- ja cobrem o onboarding e o primeiro ciclo sem transformar analytics em
-- telemetria excessiva de toda a rota infinita.
local TRACKED_ISLAND_MAX = 5

local STEPS = table.freeze({
	[1] = "PlayerJoined",
	[2] = "FirstMobDefeated",
	[3] = "FirstXPReceived",
	[4] = "FirstLevelUp",
	[5] = "ReachedIsland2",
	[6] = "ReachedIsland3",
	[7] = "ReachedIsland5",
})

local OBSERVED_ATTRIBUTES = table.freeze({
	"SwordKillCount",
	"MobXPFeedbackSerial",
	"PlayerTotalXP",
	"PlayerLevel",
	"CurrentGlobalIslandIndex",
	"LastOrbChoiceAt",
	"LastOrbChoice",
	"DungeonAssistedTransportLastAutomaticSource",
})

local states = setmetatable({}, { __mode = "k" })

workspace:SetAttribute("CoreActivationAnalyticsVersion", VERSION)
workspace:SetAttribute("CoreActivationFunnelName", FUNNEL_NAME)
workspace:SetAttribute("CoreActivationFunnelStepCount", #STEPS)
workspace:SetAttribute("CoreActivationAnalyticsPolicy", "CombatXPLevelIslandProgressionOnly")

local function clean(value, fallback)
	local result = tostring(value or fallback or "Unknown")
	result = string.gsub(result, "[%c]", "")
	if #result > 50 then result = string.sub(result, 1, 50) end
	return result ~= "" and result or tostring(fallback or "Unknown")
end

local function integer(value, fallback)
	return math.floor(tonumber(value) or fallback or 0)
end

local function elapsed(state)
	return math.max(0, math.floor(os.clock() - state.JoinedAt + 0.5))
end

local function fields(player, source)
	return {
		CustomField01 = "Island" .. tostring(math.max(0, integer(player:GetAttribute("CurrentGlobalIslandIndex"), 0))),
		CustomField02 = "Level" .. tostring(math.max(1, integer(player:GetAttribute("PlayerLevel"), 1))),
		CustomField03 = clean(source, "ServerValidated"),
	}
end

local function islandFields(player, islandIndex, source)
	return {
		CustomField01 = "Island" .. tostring(islandIndex),
		CustomField02 = "Level" .. tostring(math.max(1, integer(player:GetAttribute("PlayerLevel"), 1))),
		CustomField03 = clean(source, "ServerValidated"),
	}
end

local function safeCall(label, callback)
	if ANALYTICS_CONFIG.Enabled == false then return false end
	local success, errorMessage = pcall(callback)
	if not success and ANALYTICS_CONFIG.DebugLogs == true then
		warn(string.format("[CoreActivationAnalytics] %s falhou: %s", label, tostring(errorMessage)))
	end
	return success
end

local function logCustom(player, state, eventName, source)
	return safeCall("Custom:" .. eventName, function()
		AnalyticsService:LogCustomEvent(player, eventName, elapsed(state), fields(player, source))
	end)
end

local function isTrackedIsland(islandIndex)
	return islandIndex >= 1 and islandIndex <= TRACKED_ISLAND_MAX
end

local function finishTrackedIsland(player, state, reason)
	local islandIndex = state.TrackedIslandIndex
	local enteredAt = state.TrackedIslandEnteredAt
	if not islandIndex or not enteredAt or not isTrackedIsland(islandIndex) then
		return
	end

	local seconds = math.max(0, math.floor(os.clock() - enteredAt + 0.5))
	safeCall("Custom:IslandTimeSpent", function()
		AnalyticsService:LogCustomEvent(
			player,
			"IslandTimeSpent",
			seconds,
			islandFields(player, islandIndex, reason)
		)
	end)
	player:SetAttribute("CoreActivationLastIslandTime", seconds)
	player:SetAttribute("CoreActivationLastIslandTimeIsland", islandIndex)
	player:SetAttribute("CoreActivationLastIslandTimeReason", clean(reason, "Unknown"))
	state.TrackedIslandEnteredAt = nil
end

local function syncTrackedIsland(player, state)
	local islandIndex = math.max(0, integer(player:GetAttribute("CurrentGlobalIslandIndex"), 0))
	if islandIndex == state.TrackedIslandIndex then
		return
	end

	finishTrackedIsland(player, state, "IslandChanged")
	state.TrackedIslandIndex = islandIndex
	if isTrackedIsland(islandIndex) then
		state.TrackedIslandEnteredAt = os.clock()
		player:SetAttribute("CoreActivationTrackedIsland", islandIndex)
		player:SetAttribute("CoreActivationTrackedIslandEnteredAt", workspace:GetServerTimeNow())
	else
		player:SetAttribute("CoreActivationTrackedIsland", nil)
		player:SetAttribute("CoreActivationTrackedIslandEnteredAt", nil)
	end
end

local function recordIslandClearTime(player, state, islandIndex)
	if
		not isTrackedIsland(islandIndex)
		or state.TrackedIslandIndex ~= islandIndex
		or not state.TrackedIslandEnteredAt
		or state.CompletedTrackedIslands[islandIndex]
	then
		return
	end

	state.CompletedTrackedIslands[islandIndex] = true
	local seconds = math.max(0, math.floor(os.clock() - state.TrackedIslandEnteredAt + 0.5))
	safeCall("Custom:IslandClearTime", function()
		AnalyticsService:LogCustomEvent(
			player,
			"IslandClearTime",
			seconds,
			islandFields(player, islandIndex, "IslandCleared")
		)
	end)
	player:SetAttribute("CoreActivationLastIslandClearTime", seconds)
	player:SetAttribute("CoreActivationLastIslandClearTimeIsland", islandIndex)
end

local function drain(player, state)
	if player.Parent ~= Players then return end
	while state.HighestStep < #STEPS do
		local nextStep = state.HighestStep + 1
		local achievement = state.Achieved[nextStep]
		if not achievement then break end
		local stepName = STEPS[nextStep]
		state.HighestStep = nextStep
		player:SetAttribute("CoreActivationAnalyticsStep", nextStep)
		player:SetAttribute("CoreActivationAnalyticsStage", stepName)
		player:SetAttribute("CoreActivationAnalyticsLastStepAt", workspace:GetServerTimeNow())
		safeCall("Funnel:" .. stepName, function()
			AnalyticsService:LogFunnelStepEvent(player, FUNNEL_NAME, nil, nextStep, stepName, achievement.Fields)
		end)
	end
end

local function mark(player, state, step, source)
	if state.Achieved[step] then return false end
	state.Achieved[step] = { Fields = fields(player, source) }
	drain(player, state)
	return true
end

local function recordOnce(player, state, flag, eventName, source)
	if state.Extras[flag] then return end
	state.Extras[flag] = true
	logCustom(player, state, eventName, source)
	player:SetAttribute("CoreActivationAnalyticsLastEvent", eventName)
	player:SetAttribute("CoreActivationAnalyticsLastEventAt", workspace:GetServerTimeNow())
end

local function syncMilestones(player, state)
	if player.Parent ~= Players then return end
	syncTrackedIsland(player, state)
	mark(player, state, 1, "PlayerAdded")

	local kills = math.max(integer(player:GetAttribute("SwordKillCount"), 0), integer(player:GetAttribute("MobXPFeedbackSerial"), 0))
	if kills > 0 then mark(player, state, 2, "MobDefeated") end
	if (tonumber(player:GetAttribute("PlayerTotalXP")) or 0) > 0 then mark(player, state, 3, "XPGranted") end
	if integer(player:GetAttribute("PlayerLevel"), 1) >= 2 then mark(player, state, 4, "PlayerLevel2") end

	local island = math.max(0, integer(player:GetAttribute("CurrentGlobalIslandIndex"), 0))
	if island >= 2 then mark(player, state, 5, "IslandEntry") end
	if island >= 3 then mark(player, state, 6, "IslandEntry") end
	if island >= 5 then mark(player, state, 7, "IslandEntry") end

	if tonumber(player:GetAttribute("LastOrbChoiceAt")) then
		recordOnce(player, state, "OrbChosen", "FirstOrbChosen", clean(player:GetAttribute("LastOrbChoice"), "UnknownOrb"))
	end
	local transportSource = integer(player:GetAttribute("DungeonAssistedTransportLastAutomaticSource"), 0)
	if transportSource > 0 then
		recordOnce(player, state, "EarlyAutoTransport", "EarlyIslandAutoTransportUsed", "SourceIsland" .. tostring(transportSource))
	end
end

local function syncIslandClear(player, state)
	local serial = math.max(0, integer(workspace:GetAttribute("DungeonIslandClearFeedbackSerial"), 0))
	if serial <= (state.LastIslandClearSerial or 0) then return end
	state.LastIslandClearSerial = serial
	local clearedIsland = math.max(0, integer(workspace:GetAttribute("DungeonIslandClearFeedbackIsland"), 0))
	if clearedIsland > 0 and integer(player:GetAttribute("CurrentGlobalIslandIndex"), 0) == clearedIsland then
		recordIslandClearTime(player, state, clearedIsland)
		recordOnce(player, state, "FirstIslandCleared", "FirstIslandCleared", "Island" .. tostring(clearedIsland))
	end
end

local function recordSessionExit(player, state)
	if state.ExitRecorded then return end
	state.ExitRecorded = true
	safeCall("Custom:SessionExit", function()
		AnalyticsService:LogCustomEvent(player, "SessionExit", elapsed(state), fields(player, "PlayerRemoving"))
	end)
end

local function setupPlayer(player)
	if states[player] then return end
	local state = {
		JoinedAt = os.clock(),
		HighestStep = 0,
		Achieved = {},
		Extras = {},
		ExitRecorded = false,
		TrackedIslandIndex = nil,
		TrackedIslandEnteredAt = nil,
		CompletedTrackedIslands = {},
		LastIslandClearSerial = math.max(0, integer(workspace:GetAttribute("DungeonIslandClearFeedbackSerial"), 0)),
	}
	states[player] = state
	player:SetAttribute("CoreActivationAnalyticsVersion", VERSION)
	player:SetAttribute("CoreActivationAnalyticsEligible", true)
	player:SetAttribute("CoreActivationAnalyticsStep", 0)
	player:SetAttribute("CoreActivationAnalyticsStage", "Ready")
	for _, attributeName in ipairs(OBSERVED_ATTRIBUTES) do
		player:GetAttributeChangedSignal(attributeName):Connect(function()
			if states[player] == state then syncMilestones(player, state) end
		end)
	end
	task.defer(syncMilestones, player, state)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state then
		finishTrackedIsland(player, state, "SessionExit")
		recordSessionExit(player, state)
	end
	states[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(setupPlayer, player) end

task.spawn(function()
	while true do
		task.wait(OBSERVATION_SECONDS)
		for player, state in pairs(states) do syncMilestones(player, state) end
		for player, state in pairs(states) do syncIslandClear(player, state) end
	end
end)

if RunService:IsStudio() then
	print("[CoreActivationAnalytics] Studio: atributos atualizam, mas os eventos nao aparecem no painel Analytics.")
end
print("[CoreActivationAnalytics] " .. VERSION .. " iniciado com funil " .. FUNNEL_NAME .. ".")
