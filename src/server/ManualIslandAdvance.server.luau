-- ManualIslandAdvance: unica autoridade da progressao linear entre arenas.
--
-- Regra unica, inclusive para a ilha inicial:
--   objetivo atual concluido -> AVANCAR disponivel -> clique -> voo -> proxima ilha.
--
-- Nao existe RecommendedLevel, rota alternativa, guidance ou segundo criterio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Configs.AssistedIslandTransportConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local DungeonGenerator = require(script.Parent.DungeonRuntime.DungeonGenerator)
local MonsterSpawner = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("MonsterSpawner")
)

local remote = RemoteRegistry.Get("Navigation", "AssistedIslandTransport", "RemoteEvent")
local VERSION = "LinearIslandProgressionV1"
local POLL_SECONDS = math.max(0.10, tonumber(Config.EligibilityPollSeconds) or 0.15)
local states = setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function contextFor(index)
	local ok, context = pcall(DungeonGenerator.GetRouteIslandContext, index)
	return ok and type(context) == "table" and context or nil
end

local function islandFor(index)
	local context = contextFor(index)
	local island = context and (context.IslandModel or context.Model)
	return typeof(island) == "Instance" and island:IsA("Model") and island or nil, context
end

local function markerCFrame(marker)
	if typeof(marker) == "CFrame" then
		return marker
	end
	if typeof(marker) == "Instance" and marker:IsA("BasePart") and marker.Parent then
		return marker.CFrame
	end
	return nil
end

local function markerPosition(marker)
	local cf = markerCFrame(marker)
	if cf then
		return cf.Position
	end
	if typeof(marker) == "Instance" and marker:IsA("Model") and marker.Parent then
		return marker:GetPivot().Position
	end
	return nil
end

local function routeTotal()
	local plan = DungeonGenerator.GetRoutePlan()
	return math.max(0, math.floor(
		type(plan) == "table" and tonumber(plan.TotalIslandCount)
			or tonumber(workspace:GetAttribute("DungeonRouteIslandCount"))
			or tonumber(workspace:GetAttribute("DungeonCombatRouteTotalIslands"))
			or tonumber(workspace:GetAttribute("DungeonPlannedCombatIslandCount"))
			or 0
	))
end

local function livingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil
	end
	return character, humanoid, root
end

local function playerAvailable(player)
	return player.Parent == Players
		and player:GetAttribute("IsDowned") ~= true
		and player:GetAttribute("DungeonEliminated") ~= true
		and player:GetAttribute("DungeonSpectating") ~= true
		and player:GetAttribute("SanctuaryRescueState") ~= "Teleporting"
		and livingCharacter(player) ~= nil
end

local function monsterObjectiveComplete(index)
	local ok, snapshot = pcall(MonsterSpawner.GetObjectiveState, index)
	if not ok or type(snapshot) ~= "table" then
		return false
	end
	if snapshot.Cleared == true then
		return true
	end

	local hadVariant = false
	local allVariantsDone = true
	for _, entry in ipairs(snapshot.Variants or {}) do
		local initial = math.max(0, math.floor(tonumber(entry.Initial) or 0))
		local remaining = math.max(0, math.floor(tonumber(entry.Remaining) or initial))
		if initial > 0 then
			hadVariant = true
			if remaining > 0 then
				allVariantsDone = false
			end
		end
	end
	if snapshot.Ready == true and hadVariant and allVariantsDone then
		return true
	end

	local target = math.max(0, math.floor(tonumber(snapshot.TargetCount) or 0))
	local defeated = math.max(0, math.floor(tonumber(snapshot.DefeatedCount) or 0))
	return snapshot.Ready == true and target > 0 and defeated >= target
end

local function islandAttributesComplete(index)
	local island = islandFor(index)
	if not island then
		return false
	end
	if island:GetAttribute("Cleared") == true
		or island:GetAttribute("CombatRouteCleared") == true
		or island:GetAttribute("LinearObjectiveComplete") == true
	then
		return true
	end

	local target = math.max(0, math.floor(tonumber(
		island:GetAttribute("MobTargetCount")
			or island:GetAttribute("MobKillQuota")
	) or 0))
	local defeated = math.max(0, math.floor(tonumber(island:GetAttribute("MobDefeatedCount")) or 0))
	local spawned = math.max(0, math.floor(tonumber(island:GetAttribute("MobSpawnedCount")) or 0))
	local alive = math.max(0, math.floor(tonumber(island:GetAttribute("MobAliveCount")) or 0))

	if target > 0 and defeated >= target then
		return true
	end
	return target > 0 and spawned >= target and alive <= 0
end

local function workspaceObjectiveComplete(index)
	local objectiveIndex = tonumber(
		workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or workspace:GetAttribute("DungeonCurrentObjectiveIsland")
	)
	if objectiveIndex
		and math.floor(objectiveIndex) == index
		and workspace:GetAttribute("DungeonObjectiveState") == "Completed"
	then
		return true
	end

	local feedbackIsland = tonumber(workspace:GetAttribute("DungeonIslandClearFeedbackIsland"))
	return feedbackIsland ~= nil and math.floor(feedbackIsland) == index
end

local function objectiveComplete(index)
	return monsterObjectiveComplete(index)
		or islandAttributesComplete(index)
		or workspaceObjectiveComplete(index)
end

local function normalizeCompletedIsland(index)
	local island = islandFor(index)
	if not island or not island.Parent then
		return
	end
	if island:GetAttribute("Cleared") ~= true then
		island:SetAttribute("Cleared", true)
	end
	island:SetAttribute("CombatRouteCleared", true)
	island:SetAttribute("CombatExitLocked", false)
	island:SetAttribute("LinearObjectiveComplete", true)
end

local function fire(player, payload)
	if player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function clearReady(player)
	player:SetAttribute("DungeonCanAdvance", false)
	player:SetAttribute("DungeonManualAdvanceReady", false)
	player:SetAttribute("DungeonManualAdvanceReadyToken", nil)
	player:SetAttribute("DungeonManualAdvanceReadySource", nil)
end

local function publishObjective(player, index, complete)
	player:SetAttribute("DungeonCurrentObjectiveIsland", index)
	player:SetAttribute("DungeonCurrentObjectiveComplete", complete)
	-- Compatibility for existing HUD/telemetry readers.
	player:SetAttribute("DungeonLinearObjectiveIsland", index)
	player:SetAttribute("DungeonLinearObjectiveComplete", complete)
	player:SetAttribute("DungeonLinearObjectiveReady", true)
	player:SetAttribute("DungeonLinearObjectivePolicy", "ClearCurrentSituationThenAdvance")
end

local function publishReady(player, state, index, destination)
	if state.Phase == "Ready" and state.ReadySource == index then
		return
	end
	state.ReadyToken += 1
	state.ReadySource = index
	state.ReadyDestination = destination
	state.Phase = "Ready"

	player:SetAttribute("DungeonCanAdvance", true)
	player:SetAttribute("DungeonManualAdvanceReady", true)
	player:SetAttribute("DungeonManualAdvanceReadyToken", state.ReadyToken)
	player:SetAttribute("DungeonManualAdvanceReadySource", index)
	player:SetAttribute("DungeonAssistedTransportDestination", destination)
	player:SetAttribute("DungeonAssistedTransportState", "Ready")

	fire(player, {
		Action = "ReadyToAdvance",
		ReadyToken = state.ReadyToken,
		SourceIndex = index,
		DestinationIndex = destination,
		DestinationLabel = "ILHA " .. tostring(destination),
	})
end

local function setIdle(player, state)
	state.Phase = "Idle"
	state.ReadySource = nil
	state.ReadyDestination = nil
	clearReady(player)
	player:SetAttribute("DungeonAssistedTransportState", "Idle")
end

local function restoreCharacter(state)
	local character = state.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or state.Humanoid
	local root = character and character:FindFirstChild("HumanoidRootPart") or state.Root

	if root and root.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = (tonumber(state.WalkSpeed) or 0) > 0 and state.WalkSpeed or 16
		if state.UseJumpPower then
			humanoid.JumpPower = (tonumber(state.JumpPower) or 0) > 0 and state.JumpPower or 50
		else
			humanoid.JumpHeight = (tonumber(state.JumpHeight) or 0) > 0 and state.JumpHeight or 7.2
		end
		humanoid.AutoRotate = state.AutoRotate ~= false
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid:Move(Vector3.zero, false)
	end
	state.Character = nil
	state.Humanoid = nil
	state.Root = nil
end

local function cancel(player, reason)
	local state = states[player]
	if not state then
		return
	end
	restoreCharacter(state)
	player:SetAttribute("DungeonAssistedTransportActive", nil)
	player:SetAttribute("DungeonAssistedTransportDestination", nil)
	setIdle(player, state)
	fire(player, { Action = "Cancel", Reason = reason or "Cancelled" })
end

local function waitDestination(player, index, flightToken)
	local deadline = os.clock() + (tonumber(Config.DestinationReadyTimeoutSeconds) or 5)
	repeat
		local state = states[player]
		if not state or state.FlightToken ~= flightToken then
			return nil
		end
		pcall(DungeonGenerator.RequestRouteThrough, index)
		local context = contextFor(index)
		if context and markerCFrame(context.SafeSpawn) then
			return context
		end
		task.wait(POLL_SECONDS)
	until os.clock() >= deadline
	return nil
end

local function quadraticBezier(a, b, c, t)
	local i = 1 - t
	return i * i * a + 2 * i * t * b + t * t * c
end

local function performFlight(player, sourceIndex, destinationIndex, flightToken)
	local state = states[player]
	if not state or state.FlightToken ~= flightToken then
		return
	end

	local context = waitDestination(player, destinationIndex, flightToken)
	if not context then
		cancel(player, "DestinationUnavailable")
		return
	end

	local character, humanoid, root = livingCharacter(player)
	if not character then
		cancel(player, "CharacterUnavailable")
		return
	end

	local safeSpawn = markerCFrame(context.SafeSpawn)
	if not safeSpawn then
		cancel(player, "SafeSpawnUnavailable")
		return
	end
	local destinationCFrame = safeSpawn * CFrame.new(0, tonumber(Config.SafeSpawnHeightStuds) or 3, 0)
	local focus = markerPosition(context.ObjectiveAnchor)
		or markerPosition(context.Floor)
		or destinationCFrame.Position

	state.Phase = "Flying"
	state.Character = character
	state.Humanoid = humanoid
	state.Root = root
	state.WalkSpeed = humanoid.WalkSpeed
	state.AutoRotate = humanoid.AutoRotate
	state.UseJumpPower = humanoid.UseJumpPower
	state.JumpPower = humanoid.JumpPower
	state.JumpHeight = humanoid.JumpHeight
	clearReady(player)
	player:SetAttribute("DungeonAssistedTransportActive", true)
	player:SetAttribute("DungeonAssistedTransportState", "Flying")
	player:SetAttribute("DungeonAssistedTransportDestination", destinationIndex)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	humanoid.AutoRotate = false

	local startPosition = root.Position
	local endPosition = destinationCFrame.Position
	local horizontal = Vector3.new(endPosition.X - startPosition.X, 0, endPosition.Z - startPosition.Z)
	local distance = horizontal.Magnitude
	local arcHeight = math.clamp(
		distance * (tonumber(Config.ArcHeightPerHorizontalStud) or 0.22),
		tonumber(Config.MinimumArcHeightStuds) or 24,
		tonumber(Config.MaximumArcHeightStuds) or 70
	)
	local control = (startPosition + endPosition) / 2 + Vector3.new(0, arcHeight, 0)
	local duration = math.max(0.2, tonumber(Config.FlightDurationSeconds) or 1.35)

	fire(player, {
		Action = "BeginFlight",
		Token = flightToken,
		Duration = duration,
		SourceIndex = sourceIndex,
		DestinationIndex = destinationIndex,
		DestinationPosition = endPosition,
		FocusPosition = focus,
	})

	local startedAt = now()
	while state.FlightToken == flightToken and playerAvailable(player) do
		local linear = math.clamp((now() - startedAt) / duration, 0, 1)
		local alpha = linear * linear * (3 - 2 * linear)
		local position = quadraticBezier(startPosition, control, endPosition, alpha)
		local nextPosition = quadraticBezier(startPosition, control, endPosition, math.min(1, alpha + 0.02))
		local forward = nextPosition - position
		if forward.Magnitude <= 0.01 then
			forward = destinationCFrame.LookVector
		end
		character:PivotTo(CFrame.lookAt(position, position + forward.Unit))
		if linear >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end

	if state.FlightToken ~= flightToken or not playerAvailable(player) then
		cancel(player, "FlightInterrupted")
		return
	end

	character:PivotTo(destinationCFrame)
	state.Phase = "Landing"
	player:SetAttribute("DungeonAssistedTransportState", "Landing")
	fire(player, {
		Action = "Landed",
		Token = flightToken,
		DestinationIndex = destinationIndex,
		FocusPosition = focus,
	})

	task.wait(math.max(0, tonumber(Config.LandingCountdownSeconds) or 0.25))
	if not states[player] or state.FlightToken ~= flightToken then
		return
	end

	restoreCharacter(state)
	player:SetAttribute("DungeonAssistedTransportActive", nil)
	player:SetAttribute("DungeonAssistedTransportState", "Released")
	fire(player, { Action = "Release", Token = flightToken, DestinationIndex = destinationIndex })

	-- Normalmente o detector de entrada atualiza este indice ao pousar. Mantemos
	-- apenas um fallback curto para que a progressao linear nunca trave por timing.
	state.Phase = "ArrivalWait"
	state.ArrivalDestination = destinationIndex
	state.ArrivalDeadline = now() + 1.25
end

local function beginAdvance(player, token)
	local state = states[player]
	if not state or state.Phase ~= "Ready" or tonumber(token) ~= state.ReadyToken then
		return
	end

	local sourceIndex = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if sourceIndex ~= state.ReadySource or not objectiveComplete(sourceIndex) then
		setIdle(player, state)
		return
	end

	local destinationIndex = sourceIndex + 1
	if destinationIndex > routeTotal() then
		setIdle(player, state)
		return
	end

	state.Phase = "Warning"
	state.FlightToken += 1
	local flightToken = state.FlightToken
	clearReady(player)
	player:SetAttribute("DungeonAssistedTransportState", "Warning")

	local delaySeconds = math.max(0, tonumber(Config.LevelUpDelaySeconds) or 0.25)
	fire(player, {
		Action = "Warning",
		Token = flightToken,
		Countdown = delaySeconds,
		DestinationIndex = destinationIndex,
		DestinationLabel = "ILHA " .. tostring(destinationIndex),
	})

	task.delay(delaySeconds, function()
		local latest = states[player]
		if not latest or latest.FlightToken ~= flightToken or latest.Phase ~= "Warning" then
			return
		end
		if not objectiveComplete(sourceIndex) then
			cancel(player, "ObjectiveChanged")
			return
		end
		performFlight(player, sourceIndex, destinationIndex, flightToken)
	end)
end

local function refreshPlayer(player)
	local state = states[player]
	if not state or player.Parent ~= Players then
		return
	end

	if state.Phase == "Warning" or state.Phase == "Flying" or state.Phase == "Landing" then
		return
	end

	if state.Phase == "ArrivalWait" then
		local current = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
		if current >= (state.ArrivalDestination or current) then
			state.ArrivalDestination = nil
			state.ArrivalDeadline = nil
			setIdle(player, state)
		elseif now() >= (state.ArrivalDeadline or 0) then
			-- Fallback tolerante: o personagem ja foi colocado no SafeSpawn correto.
			-- Atualizar o indice evita ficar preso no source por uma corrida de trigger.
			local destination = state.ArrivalDestination
			if destination then
				player:SetAttribute("CurrentGlobalIslandIndex", destination)
				player:SetAttribute("DungeonLinearArrivalFallbackUsed", true)
				player:SetAttribute("DungeonLinearArrivalFallbackAt", now())
			end
			state.ArrivalDestination = nil
			state.ArrivalDeadline = nil
			setIdle(player, state)
		end
		return
	end

	local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local complete = objectiveComplete(index)
	publishObjective(player, index, complete)
	if complete then
		normalizeCompletedIsland(index)
	end

	local total = routeTotal()
	if complete and total > 0 and index < total and playerAvailable(player) then
		publishReady(player, state, index, index + 1)
	elseif state.Phase == "Ready" then
		setIdle(player, state)
	else
		player:SetAttribute("DungeonCanAdvance", false)
	end
end

local function bindPlayer(player)
	if states[player] then
		return
	end
	states[player] = {
		Phase = "Idle",
		ReadyToken = 0,
		FlightToken = 0,
		ReadySource = nil,
		ReadyDestination = nil,
		ArrivalDestination = nil,
		ArrivalDeadline = nil,
	}
	clearReady(player)
	player:SetAttribute("DungeonLinearProgressionPolicy", "ClearSituationThenAdvance")

	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		task.defer(refreshPlayer, player)
	end)
	player.CharacterAdded:Connect(function()
		task.delay(0.25, refreshPlayer, player)
	end)

	task.spawn(function()
		while player.Parent == Players and states[player] do
			refreshPlayer(player)
			task.wait(POLL_SECONDS)
		end
	end)
end

remote.OnServerEvent:Connect(function(player, payload)
	if type(payload) == "table" and payload.Action == "AdvanceRequest" then
		beginAdvance(player, payload.ReadyToken)
	end
end)

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state then
		restoreCharacter(state)
	end
	states[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

-- Desativa semanticamente os conceitos antigos. Outros scripts podem manter os
-- atributos para compatibilidade, mas eles nao participam mais da progressao.
workspace:SetAttribute("DungeonManualIslandAdvanceReady", true)
workspace:SetAttribute("DungeonManualIslandAdvanceVersion", VERSION)
workspace:SetAttribute("DungeonLinearProgressionPolicy", "ClearSituationThenAdvance")
workspace:SetAttribute("DungeonRecommendedLevelIsHardGate", false)
workspace:SetAttribute("DungeonRecommendedLevelWarningActive", false)
