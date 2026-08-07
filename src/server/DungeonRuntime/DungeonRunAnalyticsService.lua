local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CONFIG = MVPConfig.Analytics or {}

local DungeonRunAnalyticsService = {}

local statesByKey = {}

local function clean(value, fallback)
	local text = tostring(value or fallback or "Unknown")
	text = string.gsub(text, "[%c]", "")
	if #text > 50 then
		text = string.sub(text, 1, 50)
	end
	return text ~= "" and text or tostring(fallback or "Unknown")
end

local function keyFor(sessionId, userId)
	return tostring(sessionId or "") .. ":" .. tostring(math.floor(tonumber(userId) or 0))
end

local function fields(first, second, third)
	return {
		CustomField01 = clean(first),
		CustomField02 = clean(second),
		CustomField03 = clean(third),
	}
end

local function now()
	return workspace:GetServerTimeNow()
end

local function log(player, eventName, value, first, second, third)
	if CONFIG.Enabled == false or not player or player.Parent ~= Players then
		return false
	end
	local success, errorMessage = pcall(function()
		AnalyticsService:LogCustomEvent(
			player,
			eventName,
			math.max(0, tonumber(value) or 0),
			fields(first, second, third)
		)
	end)
	if not success and CONFIG.DebugLogs == true then
		warn(string.format(
			"[DungeonRunAnalytics] %s falhou para %s: %s",
			tostring(eventName),
			player.Name,
			tostring(errorMessage)
		))
	end
	return success
end

local function stateFor(player)
	local sessionId = player and player:GetAttribute("AnalyticsDungeonSessionId")
	if type(sessionId) ~= "string" or sessionId == "" then
		return nil
	end
	return statesByKey[keyFor(sessionId, player.UserId)]
end

local function runMeta(state)
	return string.format(
		"Party%d_Run%d",
		math.max(1, math.floor(tonumber(state.PartySize) or 1)),
		math.max(1, math.floor(tonumber(state.RunOrdinal) or 1))
	)
end

local function elapsed(state)
	if not state then return 0 end
	if state.StartedAt then
		return math.max(0, now() - state.StartedAt)
	end
	return math.max(0, now() - state.JoinedAt)
end

local function emit(player, state, eventName, options)
	options = type(options) == "table" and options or {}
	local repeatable = options.Repeatable == true
	if not repeatable and state.Events[eventName] == true then
		return false
	end
	if not repeatable then
		state.Events[eventName] = true
	end
	local value = options.Value
	if value == nil then value = elapsed(state) end
	local stage = clean(options.Stage or state.Stage, "UnknownStage")
	local detail = clean(options.Detail or runMeta(state), runMeta(state))
	local recorded = log(player, eventName, value, state.PhaseId, stage, detail)
	if recorded then
		state.LastEvent = eventName
		state.LastEventAt = now()
		state.LastEventElapsed = value
		player:SetAttribute("AnalyticsDungeonLastEvent", eventName)
		player:SetAttribute("AnalyticsDungeonLastEventAt", state.LastEventAt)
		player:SetAttribute("AnalyticsDungeonLastEventElapsed", value)
	end
	return recorded
end

function DungeonRunAnalyticsService.BeginPlayer(player, context)
	if not player or player.Parent ~= Players then return false end
	context = type(context) == "table" and context or {}
	local sessionId = tostring(context.SessionId or "")
	if sessionId == "" then return false end

	local key = keyFor(sessionId, player.UserId)
	local state = statesByKey[key]
	if not state then
		local replayDepth = math.max(0, math.floor(tonumber(context.ReplayDepth) or 0))
		state = {
			SessionId = sessionId,
			PhaseId = clean(context.PhaseId, "UnknownPhase"),
			PartySize = math.clamp(math.floor(tonumber(context.PartySize) or 1), 1, 4),
			ReplayDepth = replayDepth,
			RunOrdinal = replayDepth + 1,
			ReplayOfSessionId = clean(context.ReplayOfSessionId, "None"),
			JoinedAt = now(),
			StartedAt = nil,
			Stage = "PlayerJoined",
			Events = {},
			Deaths = 0,
			Completed = false,
		}
		statesByKey[key] = state
	end

	player:SetAttribute("AnalyticsDungeonSessionId", state.SessionId)
	player:SetAttribute("AnalyticsDungeonRunOrdinal", state.RunOrdinal)
	player:SetAttribute("AnalyticsDungeonReplayDepth", state.ReplayDepth)
	player:SetAttribute("AnalyticsDungeonStage", state.Stage)

	return emit(player, state, "PlayerJoined", {
		Stage = "AcceptedSession",
		Value = 0,
	})
end

function DungeonRunAnalyticsService.RunStarted(player)
	local state = stateFor(player)
	if not state or state.StartedAt then return false end
	local startedAt = now()
	local loadSeconds = math.max(0, startedAt - state.JoinedAt)
	state.StartedAt = startedAt
	state.Stage = "FirstStrike"
	player:SetAttribute("AnalyticsDungeonRunStartedAt", startedAt)
	player:SetAttribute("AnalyticsDungeonStage", state.Stage)
	emit(player, state, "RunStarted", {
		Stage = state.Stage,
		Detail = runMeta(state),
		Value = loadSeconds,
	})
	if state.ReplayDepth == 1 then
		emit(player, state, "SecondRunStarted", {
			Stage = state.Stage,
			Detail = "DirectReplay",
			Value = loadSeconds,
		})
	end
	return true
end

function DungeonRunAnalyticsService.UpdateStage(player, stageName)
	local state = stateFor(player)
	if not state then return false end
	state.Stage = clean(stageName, state.Stage)
	player:SetAttribute("AnalyticsDungeonStage", state.Stage)
	return true
end

function DungeonRunAnalyticsService.Milestone(player, eventName, stageName, detail)
	local state = stateFor(player)
	if not state then return false end
	if stageName then
		DungeonRunAnalyticsService.UpdateStage(player, stageName)
	end
	return emit(player, state, eventName, {
		Stage = state.Stage,
		Detail = detail or runMeta(state),
	})
end

function DungeonRunAnalyticsService.PlayerDied(player, cause, stageName)
	local state = stateFor(player)
	if not state then return false end
	if stageName then
		DungeonRunAnalyticsService.UpdateStage(player, stageName)
	end
	state.Deaths += 1
	player:SetAttribute("AnalyticsDungeonDeathCount", state.Deaths)
	return emit(player, state, "PlayerDied", {
		Repeatable = true,
		Stage = state.Stage,
		Detail = clean(cause, "Unknown"),
	})
end

function DungeonRunAnalyticsService.Abandoned(player, stageName, reason)
	local state = stateFor(player)
	if not state or state.Completed then return false end
	if stageName then
		DungeonRunAnalyticsService.UpdateStage(player, stageName)
	end
	return emit(player, state, "RunAbandoned", {
		Stage = state.Stage,
		Detail = clean(reason, "PlayerRemoving"),
	})
end

function DungeonRunAnalyticsService.Complete(player, result)
	local state = stateFor(player)
	if not state then return false end
	state.Completed = true
	state.Result = clean(result, "Unknown")
	player:SetAttribute("AnalyticsDungeonRunCompleted", true)
	player:SetAttribute("AnalyticsDungeonRunResult", state.Result)
	player:SetAttribute("AnalyticsDungeonRunElapsed", elapsed(state))
	return true
end

function DungeonRunAnalyticsService.GetSnapshot(player)
	local state = stateFor(player)
	if not state then return nil end
	return {
		SessionId = state.SessionId,
		PhaseId = state.PhaseId,
		PartySize = state.PartySize,
		ReplayDepth = state.ReplayDepth,
		RunOrdinal = state.RunOrdinal,
		Stage = state.Stage,
		Deaths = state.Deaths,
		Completed = state.Completed,
		Result = state.Result,
		ElapsedSeconds = elapsed(state),
		LastEvent = state.LastEvent,
		LastEventElapsed = state.LastEventElapsed,
	}
end

workspace:SetAttribute("DungeonRunAnalyticsReady", true)
workspace:SetAttribute("DungeonRunAnalyticsVersion", 1)
workspace:SetAttribute(
	"DungeonRunAnalyticsPolicy",
	"PaidTestFunnelSessionDedupedTimeToMilestoneV1"
)

return table.freeze(DungeonRunAnalyticsService)
