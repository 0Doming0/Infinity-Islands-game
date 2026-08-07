local DungeonPacingService = {}

local POLICY = "ShortReadableTransitionsV1"
local DEFAULTS = table.freeze({
	ObjectivePreparationSeconds = 2.5,
	InterWaveSeconds = 1.5,
	ObjectiveCompletionSeconds = 1.35,
	RoundTransitionSeconds = 2.75,
	BossTransitionSeconds = 4,
	CountdownTickSeconds = 0.1,
})

local started = false
local options = {}
local state = "Stopped"
local stateStartedAt = 0
local stateEndsAt = 0
local serial = 0
local workerToken = 0
local currentDetails = {}

local function now()
	return workspace:GetServerTimeNow()
end

local function durationOption(name)
	return math.max(0, tonumber(options[name]) or DEFAULTS[name] or 0)
end

local function clearContextAttributes()
	for _, name in ipairs({
		"DungeonPacingObjectiveId",
		"DungeonPacingGlobalIslandIndex",
		"DungeonPacingRoundIndex",
		"DungeonPacingWaveIndex",
		"DungeonPacingWaveCount",
		"DungeonPacingEncounterId",
		"DungeonPacingReason",
	}) do
		workspace:SetAttribute(name, nil)
	end
end

local function publish(nextState, duration, details)
	duration = math.max(0, tonumber(duration) or 0)
	details = type(details) == "table" and details or {}
	serial += 1
	state = tostring(nextState or "Idle")
	stateStartedAt = now()
	stateEndsAt = duration > 0 and (stateStartedAt + duration) or 0
	currentDetails = table.clone(details)

	clearContextAttributes()
	workspace:SetAttribute("DungeonPacingReady", started)
	workspace:SetAttribute("DungeonPacingPolicy", POLICY)
	workspace:SetAttribute("DungeonPacingState", state)
	workspace:SetAttribute("DungeonPacingStateStartedAt", stateStartedAt)
	workspace:SetAttribute("DungeonPacingStateEndsAt", stateEndsAt > 0 and stateEndsAt or nil)
	workspace:SetAttribute("DungeonPacingRemainingSeconds", duration)
	workspace:SetAttribute("DungeonPacingSerial", serial)
	workspace:SetAttribute("DungeonPacingObjectiveId", details.ObjectiveId)
	workspace:SetAttribute("DungeonPacingGlobalIslandIndex", details.GlobalIslandIndex)
	workspace:SetAttribute("DungeonPacingRoundIndex", details.RoundIndex)
	workspace:SetAttribute("DungeonPacingWaveIndex", details.WaveIndex)
	workspace:SetAttribute("DungeonPacingWaveCount", details.WaveCount)
	workspace:SetAttribute("DungeonPacingEncounterId", details.EncounterId)
	workspace:SetAttribute("DungeonPacingReason", details.Reason)
	return duration, serial
end

local function startCountdownWorker()
	workerToken += 1
	local token = workerToken
	task.spawn(function()
		while started and token == workerToken do
			local remaining = stateEndsAt > 0 and math.max(0, stateEndsAt - now()) or 0
			workspace:SetAttribute("DungeonPacingRemainingSeconds", remaining)
			task.wait(durationOption("CountdownTickSeconds"))
		end
	end)
end

function DungeonPacingService.Start(startOptions)
	if started then
		return false, "AlreadyStarted"
	end
	started = true
	options = type(startOptions) == "table" and table.clone(startOptions) or {}
	workspace:SetAttribute("DungeonPacingObjectivePreparationSeconds", durationOption("ObjectivePreparationSeconds"))
	workspace:SetAttribute("DungeonPacingInterWaveSeconds", durationOption("InterWaveSeconds"))
	workspace:SetAttribute("DungeonPacingObjectiveCompletionSeconds", durationOption("ObjectiveCompletionSeconds"))
	workspace:SetAttribute("DungeonPacingRoundTransitionSeconds", durationOption("RoundTransitionSeconds"))
	workspace:SetAttribute("DungeonPacingBossTransitionSeconds", durationOption("BossTransitionSeconds"))
	publish("Idle", 0, { Reason = "Started" })
	startCountdownWorker()
	return true
end

function DungeonPacingService.Stop(reason)
	if not started then
		return false
	end
	started = false
	workerToken += 1
	publish("Stopped", 0, { Reason = reason or "Stopped" })
	workspace:SetAttribute("DungeonPacingReady", false)
	return true
end

function DungeonPacingService.BeginObjectivePreparation(definition, context, plan, recovery)
	local duration = recovery == true and 0 or durationOption("ObjectivePreparationSeconds")
	local details = {
		ObjectiveId = definition and definition.Id,
		GlobalIslandIndex = definition and definition.GlobalIslandIndex,
		RoundIndex = definition and definition.RoundIndex,
		Reason = recovery == true and "ObjectiveRecovery" or "ObjectiveEntered",
		ProfileName = plan and plan.ProfileName,
	}
	publish(recovery == true and "CombatRecovery" or "ObjectivePreparation", duration, details)
	workspace:SetAttribute("DungeonCombatPreparationEndsAt", duration > 0 and (now() + duration) or nil)
	return duration
end

function DungeonPacingService.BeginCombat(encounter)
	return publish("CombatActive", 0, {
		ObjectiveId = encounter and encounter.Definition and encounter.Definition.Id,
		GlobalIslandIndex = encounter and encounter.Definition and encounter.Definition.GlobalIslandIndex,
		RoundIndex = encounter and encounter.Definition and encounter.Definition.RoundIndex,
		EncounterId = encounter and encounter.Id,
		Reason = encounter and encounter.Recovery == true and "Recovered" or "PreparationComplete",
	})
end

function DungeonPacingService.BeginWaveBreak(encounter, waveIndex, waveCount)
	local duration = durationOption("InterWaveSeconds")
	publish("InterWave", duration, {
		ObjectiveId = encounter and encounter.Definition and encounter.Definition.Id,
		GlobalIslandIndex = encounter and encounter.Definition and encounter.Definition.GlobalIslandIndex,
		RoundIndex = encounter and encounter.Definition and encounter.Definition.RoundIndex,
		EncounterId = encounter and encounter.Id,
		WaveIndex = waveIndex,
		WaveCount = waveCount,
		Reason = "NextWaveIncoming",
	})
	workspace:SetAttribute("DungeonNextWaveStartsAt", duration > 0 and (now() + duration) or nil)
	return duration
end

function DungeonPacingService.BeginWave(encounter, waveIndex, waveCount)
	workspace:SetAttribute("DungeonNextWaveStartsAt", nil)
	return publish("WaveActive", 0, {
		ObjectiveId = encounter and encounter.Definition and encounter.Definition.Id,
		GlobalIslandIndex = encounter and encounter.Definition and encounter.Definition.GlobalIslandIndex,
		RoundIndex = encounter and encounter.Definition and encounter.Definition.RoundIndex,
		EncounterId = encounter and encounter.Id,
		WaveIndex = waveIndex,
		WaveCount = waveCount,
		Reason = "WaveStarted",
	})
end

function DungeonPacingService.MarkWaveCleared(encounter, waveIndex, waveCount)
	return publish("WaveCleared", 0, {
		ObjectiveId = encounter and encounter.Definition and encounter.Definition.Id,
		GlobalIslandIndex = encounter and encounter.Definition and encounter.Definition.GlobalIslandIndex,
		RoundIndex = encounter and encounter.Definition and encounter.Definition.RoundIndex,
		EncounterId = encounter and encounter.Id,
		WaveIndex = waveIndex,
		WaveCount = waveCount,
		Reason = "WaveCleared",
	})
end

function DungeonPacingService.BeginObjectiveCompletion(result, context)
	local duration = durationOption("ObjectiveCompletionSeconds")
	publish("ObjectiveCompletion", duration, {
		ObjectiveId = result and result.ObjectiveId,
		GlobalIslandIndex = result and result.GlobalIslandIndex,
		RoundIndex = result and result.RoundIndex,
		Reason = "ObjectiveCleared",
	})
	workspace:SetAttribute("DungeonPathUnlockAt", duration > 0 and (now() + duration) or now())
	if context and context.IslandModel then
		context.IslandModel:SetAttribute("ObjectiveCompletionPauseEndsAt", now() + duration)
	end
	return duration
end

function DungeonPacingService.FinishObjectiveCompletion(result)
	workspace:SetAttribute("DungeonPathUnlockAt", nil)
	return publish("RouteOpen", 0, {
		ObjectiveId = result and result.ObjectiveId,
		GlobalIslandIndex = result and result.GlobalIslandIndex,
		RoundIndex = result and result.RoundIndex,
		Reason = "ObjectivePathUnlocked",
	})
end

function DungeonPacingService.BeginRewardWindow(result)
	workspace:SetAttribute("DungeonPathUnlockAt", nil)
	return publish("RewardWindow", 0, {
		ObjectiveId = result and result.ObjectiveId,
		GlobalIslandIndex = result and result.GlobalIslandIndex,
		RoundIndex = result and result.RoundIndex,
		Reason = "RoundExitRewardAvailable",
	})
end

function DungeonPacingService.BeginRoundTransition(roundIndex, isFinal, context)
	local duration = durationOption(isFinal and "BossTransitionSeconds" or "RoundTransitionSeconds")
	local nextState = isFinal and "BossTransition" or "RoundTransition"
	publish(nextState, duration, {
		GlobalIslandIndex = context and context.GlobalIslandIndex,
		RoundIndex = roundIndex,
		Reason = isFinal and "BossRoutePreparing" or "NextRoundPreparing",
	})
	workspace:SetAttribute("DungeonPathUnlockAt", duration > 0 and (now() + duration) or now())
	workspace:SetAttribute("DungeonRoundTransitionEndsAt", not isFinal and (now() + duration) or nil)
	workspace:SetAttribute("DungeonBossTransitionEndsAt", isFinal and (now() + duration) or nil)
	return duration
end

function DungeonPacingService.FinishRoundTransition(roundIndex, isFinal, context)
	workspace:SetAttribute("DungeonPathUnlockAt", nil)
	workspace:SetAttribute("DungeonRoundTransitionEndsAt", nil)
	workspace:SetAttribute("DungeonBossTransitionEndsAt", nil)
	return publish(isFinal and "BossRouteOpen" or "NextRoundOpen", 0, {
		GlobalIslandIndex = context and context.GlobalIslandIndex,
		RoundIndex = roundIndex,
		Reason = isFinal and "BossRouteUnlocked" or "NextRoundUnlocked",
	})
end

function DungeonPacingService.MarkBossReady(context)
	return publish("BossReady", 0, {
		GlobalIslandIndex = context and context.GlobalIslandIndex,
		RoundIndex = context and context.RoundIndex,
		Reason = "BossPrepared",
	})
end

function DungeonPacingService.MarkBossActive(snapshot)
	return publish("BossActive", 0, {
		Reason = snapshot and snapshot.BossId or "BossActivated",
	})
end

function DungeonPacingService.FinishRun(reason)
	if not started then
		return false
	end
	workerToken += 1
	return publish("RunComplete", 0, { Reason = reason or "Completed" })
end

function DungeonPacingService.GetSnapshot()
	return {
		Started = started,
		Policy = POLICY,
		State = state,
		StartedAt = stateStartedAt,
		EndsAt = stateEndsAt > 0 and stateEndsAt or nil,
		RemainingSeconds = stateEndsAt > 0 and math.max(0, stateEndsAt - now()) or 0,
		Serial = serial,
		Details = table.clone(currentDetails),
		Durations = {
			ObjectivePreparationSeconds = durationOption("ObjectivePreparationSeconds"),
			InterWaveSeconds = durationOption("InterWaveSeconds"),
			ObjectiveCompletionSeconds = durationOption("ObjectiveCompletionSeconds"),
			RoundTransitionSeconds = durationOption("RoundTransitionSeconds"),
			BossTransitionSeconds = durationOption("BossTransitionSeconds"),
		},
	}
end

return DungeonPacingService
