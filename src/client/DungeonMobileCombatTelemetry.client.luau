-- Mobile Dungeon Mode — Task 18: Mobile Combat Telemetry (client).
--
-- Coleta somente contadores/duracoes do combate mobile.
-- Nao envia texto livre, nomes de jogadores, chat, posicao ou conteudo pessoal.
--
-- Rede:
-- - batch a cada ~15s;
-- - deltas numericos pequenos;
-- - servidor valida e acumula;
-- - AnalyticsService nunca e chamado pelo cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = 1
local REMOTE_NAME = "DungeonMobileCombatTelemetry"
local SAMPLE_INTERVAL = 0.20
local REPORT_INTERVAL = 15.0

local remote
local active = false
local sampleElapsed = 0
local reportElapsed = 0
local sequence = 0

local session = {
	ActiveSeconds = 0,
	HoldSeconds = 0,
	SoftAimHoldSeconds = 0,
	ThreatVisibleSeconds = 0,
	ReportsSent = 0,
}

local pending = {
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
}

local lastAccepted = 0
local lastRejected = 0
local lastHitSerial = 0
local lastHapticAt

local function finiteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function nonNegativeAttribute(name)
	local value = tonumber(player:GetAttribute(name))
	if not finiteNumber(value) then
		return 0
	end
	return math.max(0, value)
end

local function softAimAvailable()
	local value = playerGui:FindFirstChild("DungeonMobileSoftAimTarget")
	return value
		and value:IsA("ObjectValue")
		and value.Value ~= nil
		and value.Value.Parent ~= nil
		or false
end

local function attackHeld()
	return player:GetAttribute("DungeonMobileAttackHeld") == true
end

local function threatVisible()
	return (tonumber(player:GetAttribute("DungeonOffscreenThreatVisibleCount")) or 0) > 0
end

local function refreshCounterBaselines()
	lastAccepted = nonNegativeAttribute("SwordServerAcceptedRequests")
	lastRejected = nonNegativeAttribute("SwordServerRejectedRequests")
	lastHitSerial = nonNegativeAttribute("SwordHitSerial")
	lastHapticAt = player:GetAttribute("DungeonLastHitHapticAt")
end

local function addCounterDelta(attributeName, previous)
	local current = nonNegativeAttribute(attributeName)
	local delta = current >= previous and (current - previous) or current
	return current, math.max(0, delta)
end

local function pollAuthoritativeCounters()
	local accepted, acceptedDelta = addCounterDelta(
		"SwordServerAcceptedRequests",
		lastAccepted
	)
	lastAccepted = accepted
	pending.AcceptedRequests += acceptedDelta

	local rejected, rejectedDelta = addCounterDelta(
		"SwordServerRejectedRequests",
		lastRejected
	)
	lastRejected = rejected
	pending.RejectedRequests += rejectedDelta

	local hitSerial, hitDelta = addCounterDelta(
		"SwordHitSerial",
		lastHitSerial
	)
	if hitDelta > 0 then
		-- SwordHitSerial normalmente sobe 1 por swing. Se varios updates forem
		-- coalescidos, HitCount representa o snapshot mais recente; portanto
		-- TargetHits recebe no minimo hitDelta para nunca produzir <1 alvo/swing.
		local hitCount = math.max(
			hitDelta,
			math.floor(nonNegativeAttribute("SwordHitCount") + 0.5)
		)
		pending.HitSwings += hitDelta
		pending.TargetHits += hitCount
		if player:GetAttribute("SwordHitHeavy") == true then
			pending.HeavyHitSwings += 1
		end
	end
	lastHitSerial = hitSerial
end

local function snapshotSettings()
	return {
		DeviceClass = tostring(
			player:GetAttribute("DungeonMobileDeviceClass") or "Unknown"
		),
		ReducedEffects = player:GetAttribute("ClientSetting_ReducedEffects") == true,
		LargeControls = player:GetAttribute("ClientSetting_LargeControls") == true,
		LargeUI = player:GetAttribute("ClientSetting_LargeUI") == true,
		HapticsEnabled = player:GetAttribute("ClientSetting_Haptics") ~= false,
		WorldMarkersEnabled = player:GetAttribute("ClientSetting_WorldMarkers") ~= false,
	}
end

local function resetPending()
	for key in pairs(pending) do
		pending[key] = 0
	end
end

local function hasPendingData()
	return pending.ActiveSeconds > 0
		or pending.AcceptedRequests > 0
		or pending.RejectedRequests > 0
		or pending.HitSwings > 0
		or pending.HapticPulses > 0
end

local function sendBatch(final)
	if not remote or not remote.Parent then
		return
	end

	pollAuthoritativeCounters()

	if not hasPendingData() and not final then
		return
	end

	sequence += 1
	local settings = snapshotSettings()

	local payload = {
		Version = VERSION,
		Sequence = sequence,
		Final = final == true,

		ActiveSeconds = pending.ActiveSeconds,
		HoldSeconds = pending.HoldSeconds,
		SoftAimHoldSeconds = pending.SoftAimHoldSeconds,
		ThreatVisibleSeconds = pending.ThreatVisibleSeconds,

		AcceptedRequests = pending.AcceptedRequests,
		RejectedRequests = pending.RejectedRequests,
		HitSwings = pending.HitSwings,
		TargetHits = pending.TargetHits,
		HeavyHitSwings = pending.HeavyHitSwings,
		HapticPulses = pending.HapticPulses,

		DeviceClass = settings.DeviceClass,
		ReducedEffects = settings.ReducedEffects,
		LargeControls = settings.LargeControls,
		LargeUI = settings.LargeUI,
		HapticsEnabled = settings.HapticsEnabled,
		WorldMarkersEnabled = settings.WorldMarkersEnabled,
	}

	remote:FireServer(payload)

	session.ReportsSent += 1
	player:SetAttribute("DungeonMobileTelemetryReportsSent", session.ReportsSent)
	player:SetAttribute("DungeonMobileTelemetryLastSequence", sequence)
	player:SetAttribute("DungeonMobileTelemetryLastReportAt", workspace:GetServerTimeNow())

	resetPending()
	reportElapsed = 0
end

local function sample(deltaTime)
	local dt = math.clamp(deltaTime, 0, 0.5)

	pending.ActiveSeconds += dt
	session.ActiveSeconds += dt

	if attackHeld() then
		pending.HoldSeconds += dt
		session.HoldSeconds += dt

		if softAimAvailable() then
			pending.SoftAimHoldSeconds += dt
			session.SoftAimHoldSeconds += dt
		end
	end

	if threatVisible() then
		pending.ThreatVisibleSeconds += dt
		session.ThreatVisibleSeconds += dt
	end

	pollAuthoritativeCounters()

	player:SetAttribute(
		"DungeonMobileTelemetrySessionSeconds",
		session.ActiveSeconds
	)
	player:SetAttribute(
		"DungeonMobileTelemetryHoldSeconds",
		session.HoldSeconds
	)
	player:SetAttribute(
		"DungeonMobileTelemetrySoftAimHoldSeconds",
		session.SoftAimHoldSeconds
	)
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	sampleElapsed = 0
	reportElapsed = 0
	refreshCounterBaselines()

	player:SetAttribute("DungeonMobileTelemetryReady", remote ~= nil)
	player:SetAttribute("DungeonMobileTelemetryActive", true)
	player:SetAttribute("DungeonMobileTelemetryVersion", VERSION)
	player:SetAttribute(
		"DungeonMobileTelemetryPolicy",
		"NumericBatchServerValidatedV1"
	)
end

local function deactivate()
	if not active then
		return
	end

	-- Envia o ultimo batch antes de sair do Dungeon mobile.
	sendBatch(true)
	active = false
	player:SetAttribute("DungeonMobileTelemetryActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

local function bindRemote()
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
		player:SetAttribute("DungeonMobileTelemetryReady", true)
		return
	end

	task.spawn(function()
		local object = ReplicatedStorage:WaitForChild(REMOTE_NAME, 20)
		if object and object:IsA("RemoteEvent") then
			remote = object
			player:SetAttribute("DungeonMobileTelemetryReady", true)
		else
			player:SetAttribute("DungeonMobileTelemetryReady", false)
		end
	end)
end

bindRemote()

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

player:GetAttributeChangedSignal("DungeonLastHitHapticAt"):Connect(function()
	if not active then
		return
	end
	local value = player:GetAttribute("DungeonLastHitHapticAt")
	if value ~= nil and value ~= lastHapticAt then
		lastHapticAt = value
		pending.HapticPulses += 1
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not active then
		return
	end

	sampleElapsed += deltaTime
	reportElapsed += deltaTime

	if sampleElapsed >= SAMPLE_INTERVAL then
		local elapsed = sampleElapsed
		sampleElapsed = 0
		sample(elapsed)
	end

	if reportElapsed >= REPORT_INTERVAL then
		sendBatch(false)
	end
end)

player:SetAttribute("DungeonMobileTelemetryControllerLoaded", true)
player:SetAttribute("DungeonMobileTelemetryVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(deactivate)
