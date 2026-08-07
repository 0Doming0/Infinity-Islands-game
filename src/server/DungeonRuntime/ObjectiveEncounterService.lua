local HttpService = game:GetService("HttpService")

local MonsterSpawner = require(script.Parent.Parent.BlockParkour.MonsterSpawner)
local EncounterCatalog = require(script.Parent.EncounterCatalog)
local ObjectiveActorService = require(script.Parent.ObjectiveActorService)
local ObjectiveMechanicService = require(script.Parent.ObjectiveMechanicService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local DungeonPacingService = require(script.Parent.DungeonPacingService)

local ObjectiveEncounterService = {}

local IMPOSSIBLE_CHECK_INTERVAL_SECONDS = 1
local IMPOSSIBLE_CONFIRM_SECONDS = 2.5
local IMPOSSIBLE_GRACE_SECONDS = 4
local MAX_PROACTIVE_RECOVERIES_PER_OBJECTIVE = 2

local started = false
local options = {}
local current
local tokenSerial = 0
local proactiveRecoveryAttempts = {}

local function now()
	return workspace:GetServerTimeNow()
end

local function sortedMarkers(folder)
	local result = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(result, child)
			end
		end
	end
	table.sort(result, function(a, b)
		local left = tonumber(a:GetAttribute("MarkerIndex")) or 0
		local right = tonumber(b:GetAttribute("MarkerIndex")) or 0
		if left == right then
			return a.Name < b.Name
		end
		return left < right
	end)
	return result
end

local function encounterAlive(encounter)
	return started
		and current == encounter
		and encounter.Active == true
		and encounter.Completing ~= true
		and encounter.Token == tokenSerial
end

local function updateAttributes(encounter, state)
	workspace:SetAttribute("DungeonEncounterState", state)
	workspace:SetAttribute("DungeonEncounterId", encounter and encounter.Id or nil)
	workspace:SetAttribute("DungeonEncounterObjectiveId", encounter and encounter.Definition.Id or nil)
	workspace:SetAttribute("DungeonEncounterIsland", encounter and encounter.Definition.GlobalIslandIndex or nil)
	workspace:SetAttribute("DungeonEncounterProfile", encounter and encounter.Plan.ProfileName or nil)
	workspace:SetAttribute("DungeonEncounterActiveEnemies", encounter and MonsterSpawner.GetObjectiveActiveCount(encounter.Id) or 0)
	workspace:SetAttribute("DungeonEncounterUpdatedAt", now())
end

local function stopEncounter(encounter, reason)
	if not encounter or encounter.Active == false then
		return
	end
	encounter.Active = false
	encounter.StopReason = reason
	ObjectiveMechanicService.EndEncounter(encounter, reason)
	ObjectiveActorService.DestroyEncounter(encounter.Id)
	MonsterSpawner.DespawnObjectiveMonsters(encounter.Id)
	if encounter.Context and encounter.Context.IslandModel then
		encounter.Context.IslandModel:SetAttribute("ObjectiveEncounterActive", false)
		encounter.Context.IslandModel:SetAttribute("ObjectiveEncounterStopReason", reason)
	end
	updateAttributes(encounter, reason or "Stopped")
end

local function markerForSpawn(encounter)
	local markers = encounter.EnemyMarkers
	if #markers == 0 then
		return encounter.Context.ObjectiveAnchor
	end
	encounter.MarkerCursor = (encounter.MarkerCursor % #markers) + 1
	return markers[encounter.MarkerCursor]
end

local function waitWhileAlive(encounter, seconds)
	local remaining = math.max(0, tonumber(seconds) or 0)
	local last = os.clock()
	while encounterAlive(encounter) and remaining > 0 do
		if encounter.Paused then
			last = os.clock()
			task.wait(0.15)
		else
			local currentClock = os.clock()
			remaining -= currentClock - last
			last = currentClock
			if remaining > 0 then
				task.wait(math.min(0.15, remaining))
			end
		end
	end
	return encounterAlive(encounter)
end

local function waitForCapacity(encounter)
	while encounterAlive(encounter) do
		if encounter.Paused then
			task.wait(0.2)
			continue
		end
		local active = MonsterSpawner.GetObjectiveActiveCount(encounter.Id)
		workspace:SetAttribute("DungeonEncounterActiveEnemies", active)
		if active < encounter.Plan.MaxAlive then
			return true
		end
		task.wait(0.2)
	end
	return false
end

local function spawnOne(encounter, enemy, waveIndex, sequenceIndex)
	if not waitForCapacity(encounter) then
		return nil
	end
	local marker = markerForSpawn(encounter)
	if not marker then
		warn("[ObjectiveEncounter] Ilha sem marcador de inimigo: " .. encounter.Definition.Id)
		return nil
	end
	local attempts = 0
	while encounterAlive(encounter) and attempts < 20 do
		attempts += 1
		local model, reason = MonsterSpawner.SpawnObjectiveMonster(
			encounter.Context.IslandModel,
			marker,
			{
				EncounterId = encounter.Id,
				ObjectiveId = encounter.Definition.Id,
				GlobalIslandIndex = encounter.Definition.GlobalIslandIndex,
				Role = enemy.Role,
				SlimeVariant = enemy.SlimeVariant,
				IsElite = enemy.IsElite == true,
				HealthMultiplier = enemy.HealthMultiplier,
				DamageMultiplier = enemy.DamageMultiplier,
				SpeedMultiplier = enemy.SpeedMultiplier,
				WaveIndex = waveIndex,
				SpawnSequence = sequenceIndex,
				Seed = encounter.Seed + waveIndex * 1009 + sequenceIndex * 97,
			}
		)
		if model then
			encounter.SpawnedCount += 1
			ObjectiveMechanicService.RegisterSpawnedEnemy(
				encounter,
				model,
				enemy,
				waveIndex,
				sequenceIndex
			)
			workspace:SetAttribute("DungeonEncounterSpawnedCount", encounter.SpawnedCount)
			return model
		end
		encounter.LastSpawnError = tostring(reason)
		workspace:SetAttribute("DungeonEncounterLastSpawnError", encounter.LastSpawnError)
		task.wait(0.35)
	end
	return nil
end

local function spawnEnemyList(encounter, enemies, waveIndex)
	local sequenceIndex = 0
	for _, enemy in ipairs(enemies or {}) do
		for _ = 1, math.max(0, math.floor(tonumber(enemy.Count) or 0)) do
			if not encounterAlive(encounter) then
				return false
			end
			sequenceIndex += 1
			spawnOne(encounter, enemy, waveIndex, sequenceIndex)
			task.wait(0.12)
		end
	end
	return encounterAlive(encounter)
end

local function waitForEncounterClear(encounter)
	while encounterAlive(encounter) do
		if encounter.Paused then
			task.wait(0.2)
			continue
		end
		local active = MonsterSpawner.GetObjectiveActiveCount(encounter.Id)
		workspace:SetAttribute("DungeonEncounterActiveEnemies", active)
		if active <= 0 then
			return true
		end
		task.wait(0.25)
	end
	return false
end

local function startWaveWorker(encounter)
	task.spawn(function()
		local waveCount = #(encounter.Plan.Waves or {})
		for waveIndex, wave in ipairs(encounter.Plan.Waves or {}) do
			if not waitWhileAlive(encounter, wave.DelaySeconds) then
				return
			end
			if waveIndex > 1 then
				local breakSeconds = DungeonPacingService.BeginWaveBreak(encounter, waveIndex, waveCount)
				if not waitWhileAlive(encounter, breakSeconds) then
					return
				end
			end
			encounter.WaveIndex = waveIndex
			workspace:SetAttribute("DungeonEncounterWaveIndex", waveIndex)
			workspace:SetAttribute("DungeonEncounterWaveCount", waveCount)
			DungeonPacingService.BeginWave(encounter, waveIndex, waveCount)
			spawnEnemyList(encounter, wave.Enemies, waveIndex)
			if wave.WaitForClear and waveIndex < waveCount then
				if not waitForEncounterClear(encounter) then
					return
				end
				DungeonPacingService.MarkWaveCleared(encounter, waveIndex, waveCount)
			end
		end
		if encounterAlive(encounter) then
			encounter.AllWavesSpawned = true
			workspace:SetAttribute("DungeonEncounterAllWavesSpawned", true)
			updateAttributes(encounter, "AllWavesSpawned")
		end
	end)
end

local function spawnNestMinion(encounter, nest)
	if not encounterAlive(encounter)
		or MonsterSpawner.GetObjectiveActiveCount(encounter.Id) >= encounter.Plan.MaxAlive
	then
		return false
	end
	local enemy = {
		Role = encounter.Plan.NestMonsterRole or "Common",
		SlimeVariant = encounter.Plan.NestMonsterVariant or "Green",
		Count = 1,
	}
	local marker = markerForSpawn(encounter)
	if marker and nest and nest.PrimaryPart then
		-- Alterna os marcadores globais, mas registra qual ninho solicitou a cria.
		marker:SetAttribute("LastNestSpawnSource", nest.Name)
	end
	return spawnOne(encounter, enemy, 90, encounter.SpawnedCount + 1) ~= nil
end

local function createNests(encounter)
	local markers = encounter.EnemyMarkers
	local count = math.max(1, math.floor(tonumber(encounter.Plan.NestCount) or 1))
	for index = 1, count do
		local marker = markers[((index - 1) % math.max(1, #markers)) + 1]
			or encounter.Context.ObjectiveAnchor
		if marker then
			ObjectiveActorService.CreateNest(encounter.Id, encounter.Definition, marker, {
				Index = index,
				MaxHealth = encounter.Plan.NestHealth,
				SpawnInterval = encounter.Plan.NestSpawnInterval,
				Parent = encounter.Context.IslandModel,
				Token = encounter.Token,
				OnSpawnRequested = function(nest)
					spawnNestMinion(encounter, nest)
				end,
			})
		end
	end
	if encounter.Plan.OpeningWave then
		task.spawn(function()
			waitWhileAlive(encounter, 0.25)
			spawnEnemyList(encounter, encounter.Plan.OpeningWave, 1)
		end)
	end
end

local function startBeaconDefense(encounter, initialProgress)
	local beacon = ObjectiveActorService.CreateBeacon(
		encounter.Id,
		encounter.Definition,
		encounter.Context.ObjectiveAnchor,
		{
			Radius = encounter.Plan.BeaconRadius,
			Target = encounter.Definition.Target,
			InitialProgress = initialProgress,
			ParticipantUserIds = options.ParticipantUserIds,
			Parent = encounter.Context.IslandModel,
			Token = encounter.Token,
		}
	)
	encounter.Beacon = beacon
	task.spawn(function()
		waitWhileAlive(encounter, 0.25)
		spawnEnemyList(encounter, encounter.Plan.OpeningWave, 1)
		local cycle = 1
		while encounterAlive(encounter) do
			if not waitWhileAlive(encounter, encounter.Plan.ContinuousInterval) then
				return
			end
			cycle += 1
			if MonsterSpawner.GetObjectiveActiveCount(encounter.Id) < encounter.Plan.MaxAlive then
				spawnEnemyList(encounter, encounter.Plan.ContinuousWave, cycle)
			end
		end
	end)
end

local function activateEncounter(encounter, beginOptions)
	if not encounterAlive(encounter) then
		return false
	end
	encounter.Preparing = false
	encounter.Paused = false
	encounter.ActivatedAt = now()
	ObjectiveMechanicService.SetEncounterActive(encounter, true)
	DungeonPacingService.BeginCombat(encounter)
	if encounter.Plan.Mode == "Nests" then
		createNests(encounter)
		encounter.ObjectiveActorsCreated = true
	elseif encounter.Plan.Mode == "Beacon" then
		startBeaconDefense(
			encounter,
			math.max(0, math.floor(tonumber(beginOptions.InitialProgress) or 0))
		)
		encounter.ObjectiveActorsCreated = true
	else
		startWaveWorker(encounter)
	end
	updateAttributes(encounter, "Active")
	return true
end

local function currentObjectiveProgress(encounter)
	if workspace:GetAttribute("DungeonObjectiveId") ~= encounter.Definition.Id then
		return nil
	end
	local target = math.max(
		1,
		math.floor(tonumber(workspace:GetAttribute("DungeonObjectiveTarget")) or encounter.Definition.Target or 1)
	)
	local progress = math.clamp(
		math.floor(tonumber(workspace:GetAttribute("DungeonObjectiveProgress")) or 0),
		0,
		target
	)
	return progress, target
end

local function impossibleEncounterReason(encounter)
	if not encounterAlive(encounter)
		or encounter.Preparing
		or encounter.Paused
		or encounter.RecoveryInProgress
		or not encounter.ActivatedAt
		or now() - encounter.ActivatedAt < IMPOSSIBLE_GRACE_SECONDS
	then
		return nil
	end

	local progress, target = currentObjectiveProgress(encounter)
	if not progress or progress >= target then
		return nil
	end

	if encounter.Plan.Mode == "Waves" then
		if encounter.AllWavesSpawned == true
			and MonsterSpawner.GetObjectiveActiveCount(encounter.Id) <= 0
		then
			return "WavesExhaustedBeforeTarget"
		end
	elseif encounter.Plan.Mode == "Nests" then
		if encounter.ObjectiveActorsCreated == true
			and ObjectiveActorService.GetAliveNestCount(encounter.Id) <= 0
		then
			return "NestsExhaustedBeforeTarget"
		end
	elseif encounter.Plan.Mode == "Beacon" then
		if encounter.ObjectiveActorsCreated == true
			and ObjectiveActorService.GetAliveBeaconCount(encounter.Id) <= 0
		then
			return "BeaconMissingBeforeTarget"
		end
	end

	return nil
end

local function startImpossibleEncounterWatchdog(encounter)
	task.spawn(function()
		while encounterAlive(encounter) do
			task.wait(IMPOSSIBLE_CHECK_INTERVAL_SECONDS)
			if not encounterAlive(encounter) then
				return
			end

			local reason = impossibleEncounterReason(encounter)
			if not reason then
				encounter.ImpossibleReason = nil
				encounter.ImpossibleSince = nil
				continue
			end

			if encounter.ImpossibleReason ~= reason then
				encounter.ImpossibleReason = reason
				encounter.ImpossibleSince = now()
				continue
			end
			if now() - (encounter.ImpossibleSince or now()) < IMPOSSIBLE_CONFIRM_SECONDS then
				continue
			end

			local objectiveId = encounter.Definition.Id
			local attemptCount = proactiveRecoveryAttempts[objectiveId] or 0
			if attemptCount >= MAX_PROACTIVE_RECOVERIES_PER_OBJECTIVE then
				workspace:SetAttribute("DungeonEncounterProactiveRecoveryExhausted", true)
				workspace:SetAttribute("DungeonEncounterProactiveRecoveryExhaustedId", objectiveId)
				workspace:SetAttribute("DungeonEncounterProactiveRecoveryExhaustedReason", reason)
				return
			end

			local snapshot = ObjectiveService.GetSnapshot()
			if snapshot.State ~= "Active" or snapshot.Id ~= objectiveId then
				return
			end

			encounter.RecoveryInProgress = true
			proactiveRecoveryAttempts[objectiveId] = attemptCount + 1
			workspace:SetAttribute("DungeonEncounterProactiveRecoveryReason", reason)
			workspace:SetAttribute("DungeonEncounterProactiveRecoveryId", objectiveId)
			workspace:SetAttribute("DungeonEncounterProactiveRecoveryAttempt", attemptCount + 1)
			workspace:SetAttribute("DungeonEncounterProactiveRecoveryRequestedAt", now())

			local recovered = ObjectiveEncounterService.Recover(
				encounter.Definition,
				encounter.Context,
				snapshot
			)
			if recovered then
				ObjectiveService.MarkRecovered("ImpossibleEncounter:" .. reason, {
					Reason = reason,
					RecoverySource = "EncounterViabilityWatchdog",
					RecoveryAttempt = attemptCount + 1,
				})
				workspace:SetAttribute("DungeonEncounterProactiveRecoveredAt", now())
				return
			end

			encounter.RecoveryInProgress = false
			workspace:SetAttribute("DungeonEncounterProactiveRecoveryError", "EncounterRestartFailed")
			encounter.ImpossibleSince = now()
		end
	end)
end

function ObjectiveEncounterService.Start(startOptions)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	options.PartySize = math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, 4)
	options.ParticipantUserIds = type(options.ParticipantUserIds) == "table"
		and table.clone(options.ParticipantUserIds)
		or {}
	proactiveRecoveryAttempts = {}
	ObjectiveMechanicService.Start()
	workspace:SetAttribute("DungeonEncounterServiceReady", true)
	workspace:SetAttribute("DungeonEncounterViabilityPolicy", "ProactiveImpossibleStateRecoveryV1")
	workspace:SetAttribute("DungeonEncounterProactiveRecoveryExhausted", false)
	updateAttributes(nil, "Idle")
end

function ObjectiveEncounterService.Stop()
	if current then
		stopEncounter(current, "ServiceStopped")
	end
	current = nil
	ObjectiveActorService.DestroyAll()
	ObjectiveMechanicService.Stop()
	MonsterSpawner.DespawnObjectiveMonsters(nil)
	started = false
	options = {}
	proactiveRecoveryAttempts = {}
	tokenSerial += 1
	workspace:SetAttribute("DungeonEncounterServiceReady", false)
	updateAttributes(nil, "Stopped")
end

function ObjectiveEncounterService.BeginObjective(definition, context, beginOptions)
	if not started then
		return false, "EncounterServiceNotStarted"
	end
	if type(definition) ~= "table" or type(context) ~= "table" or not context.IslandModel then
		return false, "InvalidEncounterContext"
	end
	if current then
		stopEncounter(current, "ReplacedByNextObjective")
	end
	beginOptions = type(beginOptions) == "table" and beginOptions or {}
	tokenSerial += 1
	local remainingTarget = math.max(
		1,
		math.floor(tonumber(beginOptions.RemainingTarget or definition.Target) or 1)
	)
	local plan = EncounterCatalog.Build(definition, options.PartySize, remainingTarget)
	local encounter = {
		Id = string.format(
			"%s-%02d-%s",
			definition.Id,
			definition.GlobalIslandIndex,
			string.sub(HttpService:GenerateGUID(false), 1, 8)
		),
		Token = tokenSerial,
		Seed = math.floor(tonumber(context.Spec and context.Spec.Seed) or definition.GlobalIslandIndex * 104729),
		Definition = definition,
		Context = context,
		Plan = plan,
		Active = true,
		EnemyMarkers = sortedMarkers(context.EnemySpawns),
		MarkerCursor = 0,
		SpawnedCount = 0,
		WaveIndex = 0,
		Recovery = beginOptions.Recovery == true,
		StartedAt = now(),
	}
	current = encounter
	ObjectiveActorService.BeginEncounter(encounter.Id, encounter.Token)
	ObjectiveMechanicService.BeginEncounter(encounter)
	context.IslandModel:SetAttribute("ObjectiveEncounterManaged", true)
	context.IslandModel:SetAttribute("ObjectiveEncounterActive", true)
	context.IslandModel:SetAttribute("ObjectiveEncounterId", encounter.Id)
	context.IslandModel:SetAttribute("ObjectiveSpawnProfile", plan.ProfileName)
	context.IslandModel:SetAttribute("ObjectiveEncounterMaxAlive", plan.MaxAlive)
	context.IslandModel:SetAttribute("ObjectiveEncounterRecovery", encounter.Recovery)
	workspace:SetAttribute("DungeonEncounterSpawnedCount", 0)
	workspace:SetAttribute("DungeonEncounterWaveIndex", 0)
	workspace:SetAttribute("DungeonEncounterWaveCount", #(plan.Waves or {}))
	workspace:SetAttribute("DungeonEncounterAllWavesSpawned", false)
	workspace:SetAttribute("DungeonEncounterLastSpawnError", nil)
	local preparationSeconds = DungeonPacingService.BeginObjectivePreparation(
		definition,
		context,
		plan,
		encounter.Recovery
	)
	encounter.Preparing = preparationSeconds > 0
	encounter.Paused = preparationSeconds > 0
	context.IslandModel:SetAttribute("ObjectivePreparationSeconds", preparationSeconds)
	context.IslandModel:SetAttribute(
		"ObjectivePreparationEndsAt",
		preparationSeconds > 0 and (now() + preparationSeconds) or nil
	)
	updateAttributes(encounter, encounter.Recovery and "Recovering" or (preparationSeconds > 0 and "Preparing" or "Starting"))

	if preparationSeconds > 0 then
		task.delay(preparationSeconds, function()
			activateEncounter(encounter, beginOptions)
		end)
	else
		activateEncounter(encounter, beginOptions)
	end
	startImpossibleEncounterWatchdog(encounter)
	return true, encounter.Id
end

function ObjectiveEncounterService.CompleteObjective(objectiveId)
	local encounter = current
	if not encounter or (objectiveId and encounter.Definition.Id ~= objectiveId) then
		return false, "EncounterObjectiveMismatch"
	end
	encounter.CompletedAt = now()
	encounter.Completing = true
	encounter.Context.IslandModel:SetAttribute("ObjectiveEncounterCompleted", true)
	updateAttributes(encounter, "Completing")
	task.defer(function()
		if current == encounter then
			stopEncounter(encounter, "ObjectiveCompleted")
			current = nil
			updateAttributes(nil, "ObjectiveCompleted")
		end
	end)
	return true
end

function ObjectiveEncounterService.Recover(definition, context, snapshot)
	if not started then
		return false
	end
	local target = math.max(1, math.floor(tonumber(snapshot and snapshot.Target or definition.Target) or 1))
	local progress = math.max(0, math.floor(tonumber(snapshot and snapshot.Progress) or 0))
	local remaining = math.max(1, target - progress)
	local success = ObjectiveEncounterService.BeginObjective(definition, context, {
		RemainingTarget = remaining,
		InitialProgress = progress,
		Recovery = true,
	})
	if success then
		workspace:SetAttribute("DungeonEncounterRecoveredAt", now())
		workspace:SetAttribute("DungeonEncounterRecoveryRemaining", remaining)
	end
	return success == true
end

function ObjectiveEncounterService.SetCombatEnabled(enabled)
	local encounter = current
	if not encounter then
		return false
	end
	enabled = enabled == true
	if enabled and encounter.Preparing == true then
		updateAttributes(encounter, "Preparing")
		return true
	end
	encounter.Paused = not enabled
	ObjectiveActorService.SetEncounterActive(encounter.Id, enabled)
	ObjectiveMechanicService.SetEncounterActive(encounter, enabled)
	MonsterSpawner.SetObjectiveMonstersActive(encounter.Id, enabled)
	updateAttributes(encounter, enabled and "Active" or "Paused")
	return true
end

function ObjectiveEncounterService.GetSnapshot()
	local encounter = current
	if not encounter then
		return {
			Started = started,
			State = workspace:GetAttribute("DungeonEncounterState"),
			Active = false,
		}
	end
	return {
		Started = started,
		State = workspace:GetAttribute("DungeonEncounterState"),
		Active = encounter.Active,
		EncounterId = encounter.Id,
		ObjectiveId = encounter.Definition.Id,
		GlobalIslandIndex = encounter.Definition.GlobalIslandIndex,
		ProfileName = encounter.Plan.ProfileName,
		Mode = encounter.Plan.Mode,
		WaveIndex = encounter.WaveIndex,
		WaveCount = #(encounter.Plan.Waves or {}),
		SpawnedCount = encounter.SpawnedCount,
		ActiveEnemyCount = MonsterSpawner.GetObjectiveActiveCount(encounter.Id),
		AliveNestCount = ObjectiveActorService.GetAliveNestCount(encounter.Id),
		Recovery = encounter.Recovery,
		Mechanic = ObjectiveMechanicService.GetSnapshot(encounter),
		StartedAt = encounter.StartedAt,
	}
end

return ObjectiveEncounterService
