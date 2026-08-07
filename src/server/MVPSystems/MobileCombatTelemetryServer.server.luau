-- Mobile Dungeon Mode — Task 18: Mobile Combat Telemetry (server).
--
-- Recebe somente batches numericos do cliente, valida limites e acumula no
-- servidor. AnalyticsService e chamado apenas aqui, como exigido pelo Roblox.
--
-- Privacy:
-- - sem texto livre;
-- - sem chat;
-- - sem coordenadas;
-- - sem nomes customizados;
-- - custom fields usam somente categorias fechadas.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "DungeonMobileCombatTelemetry"
local VERSION = 1
local MIN_REPORT_INTERVAL = 3.0
local MAX_BATCH_ACTIVE_SECONDS = 30
local MAX_COUNTER_PER_BATCH = 120
local MIN_SESSION_FOR_ANALYTICS = 5

local ALLOWED_DEVICE_CLASS = table.freeze({
	CompactPhone = true,
	Phone = true,
	LargePhone = true,
	TabletPortrait = true,
	Unknown = true,
})

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

local states = {}

local function newState()
	return {
		LastReceivedAt = -math.huge,
		LastSequence = 0,
		Reports = 0,
		RejectedReports = 0,
		Finalized = false,

		ActiveSeconds = 0,
		HoldSeconds = 0,
		SoftAimHoldSeconds = 0,
		ThreatVisibleSeconds = 0,

		AcceptedRequests = 0,
		RejectedRequests = 0,
		HitSwings = 0,
		TargetHits = 0,
		HeavyHitSwings = 0,
		HapticPulses = 0,

		DeviceClass = "Unknown",
		ReducedEffects = false,
		LargeControls = false,
		LargeUI = false,
		HapticsEnabled = true,
		WorldMarkersEnabled = true,
	}
end

local function finite(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function boundedNumber(value, minimum, maximum)
	if not finite(value) then
		return nil
	end
	if value < minimum or value > maximum then
		return nil
	end
	return value
end

local function boundedCounter(value)
	value = boundedNumber(value, 0, MAX_COUNTER_PER_BATCH)
	if value == nil then
		return nil
	end
	return math.floor(value + 0.5)
end

local function boolean(value)
	return value == true
end

local function deviceClass(value)
	value = tostring(value or "Unknown")
	return ALLOWED_DEVICE_CLASS[value] and value or "Unknown"
end

local function reject(player, state, reason)
	state.RejectedReports += 1
	player:SetAttribute(
		"DungeonMobileTelemetryServerRejectedReports",
		state.RejectedReports
	)
	player:SetAttribute(
		"DungeonMobileTelemetryServerLastRejectReason",
		reason
	)
end

local function validatePayload(state, payload)
	if type(payload) ~= "table" then
		return nil, "PayloadNotTable"
	end
	if payload.Version ~= VERSION then
		return nil, "VersionMismatch"
	end

	local sequence = boundedCounter(payload.Sequence)
	if not sequence or sequence <= state.LastSequence then
		return nil, "SequenceInvalid"
	end

	local activeSeconds = boundedNumber(
		payload.ActiveSeconds,
		0,
		MAX_BATCH_ACTIVE_SECONDS
	)
	local holdSeconds = boundedNumber(
		payload.HoldSeconds,
		0,
		MAX_BATCH_ACTIVE_SECONDS
	)
	local softAimHoldSeconds = boundedNumber(
		payload.SoftAimHoldSeconds,
		0,
		MAX_BATCH_ACTIVE_SECONDS
	)
	local threatVisibleSeconds = boundedNumber(
		payload.ThreatVisibleSeconds,
		0,
		MAX_BATCH_ACTIVE_SECONDS
	)

	if activeSeconds == nil
		or holdSeconds == nil
		or softAimHoldSeconds == nil
		or threatVisibleSeconds == nil
	then
		return nil, "DurationOutOfRange"
	end

	-- Subduracoes nunca podem exceder significativamente o tempo ativo do batch.
	local durationAllowance = 0.75
	if holdSeconds > activeSeconds + durationAllowance
		or softAimHoldSeconds > holdSeconds + durationAllowance
		or threatVisibleSeconds > activeSeconds + durationAllowance
	then
		return nil, "DurationRelationshipInvalid"
	end

	local counters = {}
	for _, key in ipairs({
		"AcceptedRequests",
		"RejectedRequests",
		"HitSwings",
		"TargetHits",
		"HeavyHitSwings",
		"HapticPulses",
	}) do
		local value = boundedCounter(payload[key])
		if value == nil then
			return nil, "CounterOutOfRange:" .. key
		end
		counters[key] = value
	end

	if counters.HeavyHitSwings > counters.HitSwings + 1 then
		return nil, "HeavyHitsInvalid"
	end
	if counters.TargetHits < counters.HitSwings then
		return nil, "TargetHitsInvalid"
	end

	return {
		Sequence = sequence,
		Final = payload.Final == true,

		ActiveSeconds = activeSeconds,
		HoldSeconds = holdSeconds,
		SoftAimHoldSeconds = softAimHoldSeconds,
		ThreatVisibleSeconds = threatVisibleSeconds,

		AcceptedRequests = counters.AcceptedRequests,
		RejectedRequests = counters.RejectedRequests,
		HitSwings = counters.HitSwings,
		TargetHits = counters.TargetHits,
		HeavyHitSwings = counters.HeavyHitSwings,
		HapticPulses = counters.HapticPulses,

		DeviceClass = deviceClass(payload.DeviceClass),
		ReducedEffects = boolean(payload.ReducedEffects),
		LargeControls = boolean(payload.LargeControls),
		LargeUI = boolean(payload.LargeUI),
		HapticsEnabled = payload.HapticsEnabled ~= false,
		WorldMarkersEnabled = payload.WorldMarkersEnabled ~= false,
	}, nil
end

local function addReport(state, report)
	state.LastSequence = report.Sequence
	state.Reports += 1

	state.ActiveSeconds += report.ActiveSeconds
	state.HoldSeconds += report.HoldSeconds
	state.SoftAimHoldSeconds += report.SoftAimHoldSeconds
	state.ThreatVisibleSeconds += report.ThreatVisibleSeconds

	state.AcceptedRequests += report.AcceptedRequests
	state.RejectedRequests += report.RejectedRequests
	state.HitSwings += report.HitSwings
	state.TargetHits += report.TargetHits
	state.HeavyHitSwings += report.HeavyHitSwings
	state.HapticPulses += report.HapticPulses

	state.DeviceClass = report.DeviceClass
	state.ReducedEffects = report.ReducedEffects
	state.LargeControls = report.LargeControls
	state.LargeUI = report.LargeUI
	state.HapticsEnabled = report.HapticsEnabled
	state.WorldMarkersEnabled = report.WorldMarkersEnabled
end

local function percent(numerator, denominator)
	if denominator <= 0 then
		return 0
	end
	return math.clamp(numerator / denominator * 100, 0, 100)
end

local function ratio(numerator, denominator)
	if denominator <= 0 then
		return 0
	end
	return math.max(0, numerator / denominator)
end

local function fields(state)
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] =
			"Device_" .. state.DeviceClass,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] =
			state.ReducedEffects and "ReducedFX_On" or "ReducedFX_Off",
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] =
			state.LargeControls and "LargeControls_On" or "LargeControls_Off",
	}
end

local function logMetric(player, eventName, value, customFields)
	if RunService:IsStudio() then
		return true
	end

	local success, err = pcall(function()
		AnalyticsService:LogCustomEvent(
			player,
			eventName,
			value,
			customFields
		)
	end)

	if not success then
		warn(
			"[MobileCombatTelemetry] Analytics failed:",
			eventName,
			err
		)
	end

	return success
end

local function finalize(player, reason)
	local state = states[player]
	if not state or state.Finalized then
		return
	end
	state.Finalized = true

	local attackRequests = state.AcceptedRequests + state.RejectedRequests
	local customFields = fields(state)

	local metrics = {
		MobileCombatSessionSeconds = state.ActiveSeconds,
		MobileCombatHitSwingRatePct = percent(
			state.HitSwings,
			state.AcceptedRequests
		),
		MobileCombatTargetsPerHitSwing = ratio(
			state.TargetHits,
			state.HitSwings
		),
		MobileCombatHoldRatioPct = percent(
			state.HoldSeconds,
			state.ActiveSeconds
		),
		MobileCombatSoftAimCoveragePct = percent(
			state.SoftAimHoldSeconds,
			state.HoldSeconds
		),
		MobileCombatRejectRatePct = percent(
			state.RejectedRequests,
			attackRequests
		),
		MobileCombatThreatExposurePct = percent(
			state.ThreatVisibleSeconds,
			state.ActiveSeconds
		),
		MobileCombatHapticPerHitSwing = ratio(
			state.HapticPulses,
			state.HitSwings
		),
	}

	local analyticsSent = 0
	if state.ActiveSeconds >= MIN_SESSION_FOR_ANALYTICS then
		for eventName, value in pairs(metrics) do
			if logMetric(player, eventName, value, customFields) then
				analyticsSent += 1
			end
		end
	end

	player:SetAttribute("DungeonMobileTelemetryServerFinalized", true)
	player:SetAttribute("DungeonMobileTelemetryServerFinalizeReason", reason)
	player:SetAttribute("DungeonMobileTelemetryServerReports", state.Reports)
	player:SetAttribute(
		"DungeonMobileTelemetryServerRejectedReports",
		state.RejectedReports
	)
	player:SetAttribute(
		"DungeonMobileTelemetryServerSessionSeconds",
		state.ActiveSeconds
	)
	player:SetAttribute(
		"DungeonMobileTelemetryServerHitSwingRatePct",
		metrics.MobileCombatHitSwingRatePct
	)
	player:SetAttribute(
		"DungeonMobileTelemetryServerSoftAimCoveragePct",
		metrics.MobileCombatSoftAimCoveragePct
	)
	player:SetAttribute(
		"DungeonMobileTelemetryAnalyticsEventsSent",
		analyticsSent
	)
end

remote.OnServerEvent:Connect(function(player, payload)
	local state = states[player]
	if not state then
		state = newState()
		states[player] = state
	end
	if state.Finalized then
		return
	end

	local now = os.clock()
	if now - state.LastReceivedAt < MIN_REPORT_INTERVAL then
		reject(player, state, "RateLimited")
		return
	end

	local report, reason = validatePayload(state, payload)
	if not report then
		reject(player, state, reason)
		return
	end

	state.LastReceivedAt = now
	addReport(state, report)

	player:SetAttribute("DungeonMobileTelemetryServerReady", true)
	player:SetAttribute("DungeonMobileTelemetryServerReports", state.Reports)
	player:SetAttribute(
		"DungeonMobileTelemetryServerLastSequence",
		state.LastSequence
	)
	player:SetAttribute(
		"DungeonMobileTelemetryServerLastReportAt",
		workspace:GetServerTimeNow()
	)

	if report.Final then
		finalize(player, "ClientFinal")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	-- Finaliza com tudo que chegou no ultimo batch periódico, mesmo se o
	-- cliente não teve tempo de enviar Final durante disconnect/teleporte.
	finalize(player, "PlayerRemoving")
	states[player] = nil
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("DungeonMobileTelemetryServerReady", true)
	player:SetAttribute("DungeonMobileTelemetryServerVersion", VERSION)
	player:SetAttribute(
		"DungeonMobileTelemetryServerPolicy",
		"ValidatedBatchAnalyticsV1"
	)
end)

for _, player in ipairs(Players:GetPlayers()) do
	player:SetAttribute("DungeonMobileTelemetryServerReady", true)
	player:SetAttribute("DungeonMobileTelemetryServerVersion", VERSION)
	player:SetAttribute(
		"DungeonMobileTelemetryServerPolicy",
		"ValidatedBatchAnalyticsV1"
	)
end

workspace:SetAttribute("DungeonMobileTelemetryServerReady", true)
workspace:SetAttribute("DungeonMobileTelemetryServerVersion", VERSION)
workspace:SetAttribute(
	"DungeonMobileTelemetryAnalyticsPolicy",
	"EightAggregatedCustomEventsPerMobileSessionV1"
)
