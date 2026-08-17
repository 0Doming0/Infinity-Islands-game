-- Avanco confirmado pelo jogador entre arenas.
-- Fluxo: missao concluida -> ReadyToAdvance -> botao AVANCAR -> voo automatico.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Configs.AssistedIslandTransportConfig)
local IslandProgressionConfig = require(ReplicatedStorage.Shared.Configs.IslandProgressionConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local DungeonGenerator = require(script.Parent.DungeonRuntime.DungeonGenerator)
local MonsterSpawner = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("MonsterSpawner")
)

local remote = RemoteRegistry.Get("Navigation", "AssistedIslandTransport", "RemoteEvent")
local VERSION = "ManualIslandAdvanceV3_AuthoritativeClear"
local states = setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
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

local function islandFor(context)
	return type(context) == "table" and (context.IslandModel or context.Model) or nil
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

local function playerCanTravel(player)
	return player.Parent == Players
		and player:GetAttribute("IsDowned") ~= true
		and player:GetAttribute("DungeonEliminated") ~= true
		and player:GetAttribute("DungeonSpectating") ~= true
		and player:GetAttribute("SanctuaryRescueState") ~= "Teleporting"
		and livingCharacter(player) ~= nil
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

local function recommendedLevel(index, context)
	local island = islandFor(context)
	return math.max(1, math.floor(
		tonumber(
			island and (
				island:GetAttribute("RecommendedLevel")
					or island:GetAttribute("IslandLevel")
			)
		)
			or IslandProgressionConfig.GetRecommendedLevel(index)
	))
end

-- A fonte da verdade da missao ja existe no MonsterSpawner/objetivo da ilha.
-- O atributo do Model fica como fallback porque o CombatRouteProgressionService
-- tambem o publica quando a ilha e concluida.
local function currentMissionCleared(index, context)
	local island = islandFor(context)
	if island and (
		island:GetAttribute("Cleared") == true
			or island:GetAttribute("CombatRouteCleared") == true
	) then
		return true
	end

	local ok, objectiveState = pcall(MonsterSpawner.GetObjectiveState, index)
	if ok and type(objectiveState) == "table" and objectiveState.Cleared == true then
		return true
	end

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

	local clearedFeedbackIsland = tonumber(
		workspace:GetAttribute("DungeonIslandClearFeedbackIsland")
	)
	return clearedFeedbackIsland ~= nil
		and math.floor(clearedFeedbackIsland) == index
end

local function resolveEligibility(player, allowBusy)
	if Config.ManualAdvanceEnabled ~= true or not playerCanTravel(player) then
		return nil, "Unavailable"
	end

	local state = states[player]
	if not state then
		return nil, "Unavailable"
	end
	if not allowBusy and (
		state.Phase == "Flying"
		or state.Phase == "Landing"
		or state.Phase == "Warning"
	) then
		return nil, "Busy"
	end

	local currentIndex = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if state.WaitingForArrivalIndex then
		if currentIndex < state.WaitingForArrivalIndex then
			return nil, "WaitingForArrival"
		end
		state.WaitingForArrivalIndex = nil
		state.Phase = "Idle"
	end

	local total = routeTotal()
	if total <= 0 or currentIndex >= total then
		return nil, "NoNextIsland"
	end

	local currentContext = DungeonGenerator.GetRouteIslandContext(currentIndex)
	if Config.RequireCurrentIslandCleared
		and not currentMissionCleared(currentIndex, currentContext)
	then
		return nil, "CurrentIslandNotCleared"
	end

	local destinationIndex = currentIndex + 1
	DungeonGenerator.RequestRouteThrough(destinationIndex)
	local destinationContext = DungeonGenerator.GetRouteIslandContext(destinationIndex)
	local requiredLevel = recommendedLevel(destinationIndex, destinationContext)

	-- RecommendedLevel e apenas aviso no CombatRouteProgressionService.
	-- Nunca bloquear o botao/voo por nivel se a missao atual foi concluida.
	return {
		CurrentIndex = currentIndex,
		DestinationIndex = destinationIndex,
		CurrentContext = currentContext,
		DestinationContext = destinationContext,
		RecommendedLevel = requiredLevel,
	}, nil
end

local function fire(player, payload)
	if player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function hideReady(player, reason)
	local state = states[player]
	if not state then
		return
	end
	if state.Phase == "Ready" then
		state.Phase = "Idle"
		state.ReadyForSourceIndex = nil
		state.ReadyDestinationIndex = nil
		player:SetAttribute("DungeonManualAdvanceReady", false)
		player:SetAttribute("DungeonAssistedTransportState", "Idle")
		fire(player, {
			Action = "AdvanceUnavailable",
			Reason = reason or "Unavailable",
		})
	end
end

local function publishReady(player, eligibility)
	local state = states[player]
	if not state
		or state.Phase == "Flying"
		or state.Phase == "Landing"
		or state.Phase == "Warning"
	then
		return
	end
	if state.Phase == "Ready"
		and state.ReadyForSourceIndex == eligibility.CurrentIndex
	then
		return
	end

	state.ReadyToken += 1
	state.Phase = "Ready"
	state.ReadyForSourceIndex = eligibility.CurrentIndex
	state.ReadyDestinationIndex = eligibility.DestinationIndex
	player:SetAttribute("DungeonManualAdvanceReady", true)
	player:SetAttribute("DungeonManualAdvanceReadySource", eligibility.CurrentIndex)
	player:SetAttribute("DungeonAssistedTransportState", "ReadyToAdvance")
	player:SetAttribute("DungeonAssistedTransportDestination", eligibility.DestinationIndex)

	local destinationContext = eligibility.DestinationContext
	local destinationPosition = destinationContext and (
		markerPosition(destinationContext.ObjectiveAnchor)
			or markerPosition(destinationContext.Floor)
			or markerPosition(destinationContext.SafeSpawn)
	) or nil

	fire(player, {
		Action = "ReadyToAdvance",
		ReadyToken = state.ReadyToken,
		SourceIndex = eligibility.CurrentIndex,
		DestinationIndex = eligibility.DestinationIndex,
		DestinationLabel = "ILHA " .. tostring(math.max(1, eligibility.DestinationIndex - 1)),
		DestinationPosition = destinationPosition,
		RecommendedLevel = eligibility.RecommendedLevel,
	})
end

local function restoreCharacter(state)
	local character = state.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		or state.Humanoid
	local root = character and character:FindFirstChild("HumanoidRootPart")
		or state.Root

	if root and root.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = (tonumber(state.WalkSpeedWas) or 0) > 0
			and state.WalkSpeedWas
			or 16
		if state.UseJumpPowerWas then
			humanoid.JumpPower = (tonumber(state.JumpPowerWas) or 0) > 0
				and state.JumpPowerWas
				or 50
		else
			humanoid.JumpHeight = (tonumber(state.JumpHeightWas) or 0) > 0
				and state.JumpHeightWas
				or 7.2
		end
		humanoid.AutoRotate = state.AutoRotateWas ~= false
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid:Move(Vector3.zero, false)
	end

	state.Character = nil
	state.Humanoid = nil
	state.Root = nil
end

local function quadraticBezier(a, b, c, t)
	local i = 1 - t
	return i * i * a + 2 * i * t * b + t * t * c
end

local function waitForDestination(player, index, flightToken)
	local deadline = os.clock() + Config.DestinationReadyTimeoutSeconds
	repeat
		local state = states[player]
		if not state or state.FlightToken ~= flightToken then
			return nil
		end
		DungeonGenerator.RequestRouteThrough(index)
		local context = DungeonGenerator.GetRouteIslandContext(index)
		if context and markerCFrame(context.SafeSpawn) then
			return context
		end
		task.wait(Config.EligibilityPollSeconds)
	until os.clock() >= deadline
	return nil
end

local function cancelTravel(player, reason)
	local state = states[player]
	if not state then
		return
	end
	restoreCharacter(state)
	state.Phase = "Idle"
	state.WaitingForArrivalIndex = nil
	state.ReadyForSourceIndex = nil
	state.ReadyDestinationIndex = nil
	player:SetAttribute("DungeonManualAdvanceReady", false)
	player:SetAttribute("DungeonAssistedTransportActive", nil)
	player:SetAttribute("DungeonAssistedTransportState", "Idle")
	player:SetAttribute("DungeonAssistedTransportDestination", nil)
	fire(player, { Action = "Cancel", Reason = reason or "Cancelled" })
end

local function performFlight(player, eligibility, flightToken)
	local state = states[player]
	if not state or state.FlightToken ~= flightToken then
		return
	end

	local destinationContext = eligibility.DestinationContext
	if not destinationContext or not markerCFrame(destinationContext.SafeSpawn) then
		destinationContext = waitForDestination(
			player,
			eligibility.DestinationIndex,
			flightToken
		)
	end
	if not destinationContext then
		cancelTravel(player, "DestinationUnavailable")
		return
	end

	local character, humanoid, root = livingCharacter(player)
	if not character then
		cancelTravel(player, "CharacterUnavailable")
		return
	end

	local safeSpawn = markerCFrame(destinationContext.SafeSpawn)
	local destinationCFrame = safeSpawn * CFrame.new(0, Config.SafeSpawnHeightStuds, 0)
	local focusPosition = markerPosition(destinationContext.ObjectiveAnchor)
		or markerPosition(destinationContext.Floor)
		or destinationCFrame.Position

	state.Phase = "Flying"
	state.Character = character
	state.Humanoid = humanoid
	state.Root = root
	state.AutoRotateWas = humanoid.AutoRotate
	state.WalkSpeedWas = humanoid.WalkSpeed
	state.JumpPowerWas = humanoid.JumpPower
	state.JumpHeightWas = humanoid.JumpHeight
	state.UseJumpPowerWas = humanoid.UseJumpPower
	player:SetAttribute("DungeonManualAdvanceReady", false)
	player:SetAttribute("DungeonAssistedTransportActive", true)
	player:SetAttribute("DungeonAssistedTransportState", "Flying")

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	humanoid.Sit = false

	local startPosition = root.Position
	local endPosition = destinationCFrame.Position
	local horizontal = Vector3.new(
		endPosition.X - startPosition.X,
		0,
		endPosition.Z - startPosition.Z
	)
	local distance = horizontal.Magnitude
	local arcHeight = math.clamp(
		distance * Config.ArcHeightPerHorizontalStud,
		Config.MinimumArcHeightStuds,
		Config.MaximumArcHeightStuds
	)
	local lateral = Vector3.zero
	if distance > 0.01 then
		local side = Vector3.new(-horizontal.Z, 0, horizontal.X).Unit
		local sign = ((player.UserId + eligibility.DestinationIndex) % 2 == 0)
			and 1
			or -1
		lateral = side
			* math.min(
				distance * Config.LateralCurvePerHorizontalStud,
				Config.MaximumLateralCurveStuds
			)
			* sign
	end
	local control = (startPosition + endPosition) / 2
		+ Vector3.new(0, arcHeight, 0)
		+ lateral

	fire(player, {
		Action = "BeginFlight",
		Token = flightToken,
		Duration = Config.FlightDurationSeconds,
		FocusPosition = focusPosition,
		DestinationPosition = endPosition,
		DestinationIndex = eligibility.DestinationIndex,
	})

	local startedAt = now()
	while state.FlightToken == flightToken and playerCanTravel(player) do
		local linear = math.clamp(
			(now() - startedAt) / Config.FlightDurationSeconds,
			0,
			1
		)
		local alpha = linear * linear * (3 - 2 * linear)
		local position = quadraticBezier(startPosition, control, endPosition, alpha)
		local nextPosition = quadraticBezier(
			startPosition,
			control,
			endPosition,
			math.min(1, alpha + 0.015)
		)
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

	if state.FlightToken ~= flightToken or not playerCanTravel(player) then
		cancelTravel(player, "FlightInterrupted")
		return
	end

	character:PivotTo(destinationCFrame)
	state.Phase = "Landing"
	player:SetAttribute("DungeonAssistedTransportState", "LandingCountdown")
	local releaseAt = now() + Config.LandingCountdownSeconds
	fire(player, {
		Action = "Landed",
		Token = flightToken,
		ReleaseAt = releaseAt,
		Countdown = Config.LandingCountdownSeconds,
		FocusPosition = focusPosition,
	})

	while state.FlightToken == flightToken
		and now() < releaseAt
		and playerCanTravel(player)
	do
		RunService.Heartbeat:Wait()
	end
	if state.FlightToken ~= flightToken or not playerCanTravel(player) then
		cancelTravel(player, "LandingInterrupted")
		return
	end

	restoreCharacter(state)
	player:SetAttribute("DungeonAssistedTransportActive", nil)
	state.Phase = "ArrivalWait"
	state.WaitingForArrivalIndex = eligibility.DestinationIndex
	player:SetAttribute("DungeonAssistedTransportState", "Released")
	fire(player, { Action = "Release", Token = flightToken })
end

local function beginAdvance(player, readyToken)
	local state = states[player]
	if not state
		or state.Phase ~= "Ready"
		or tonumber(readyToken) ~= state.ReadyToken
	then
		return
	end

	local eligibility = resolveEligibility(player, false)
	if not eligibility
		or eligibility.CurrentIndex ~= state.ReadyForSourceIndex
	then
		hideReady(player, "EligibilityChanged")
		return
	end

	state.Phase = "Warning"
	state.FlightToken += 1
	local flightToken = state.FlightToken
	player:SetAttribute("DungeonManualAdvanceReady", false)
	player:SetAttribute("DungeonAssistedTransportState", "Warning")
	local transportAt = now() + Config.LevelUpDelaySeconds

	fire(player, {
		Action = "Warning",
		Reason = "PlayerConfirmedAdvance",
		Token = flightToken,
		TransportAt = transportAt,
		Countdown = Config.LevelUpDelaySeconds,
		DestinationIndex = eligibility.DestinationIndex,
		DestinationLabel = "ILHA " .. tostring(math.max(1, eligibility.DestinationIndex - 1)),
		RecommendedLevel = eligibility.RecommendedLevel,
	})

	task.delay(Config.LevelUpDelaySeconds, function()
		local latest = states[player]
		if not latest
			or latest.FlightToken ~= flightToken
			or latest.Phase ~= "Warning"
		then
			return
		end

		local finalEligibility = resolveEligibility(player, true)
		if not finalEligibility
			or finalEligibility.CurrentIndex ~= eligibility.CurrentIndex
		then
			cancelTravel(player, "EligibilityChanged")
			return
		end
		performFlight(player, finalEligibility, flightToken)
	end)
end

local function refreshPlayer(player)
	local state = states[player]
	if not state then
		return
	end
	if state.Phase == "Flying"
		or state.Phase == "Landing"
		or state.Phase == "Warning"
	then
		return
	end

	local eligibility = resolveEligibility(player, false)
	if eligibility then
		publishReady(player, eligibility)
	else
		hideReady(player, "MissionNotReady")
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
		ReadyForSourceIndex = nil,
		ReadyDestinationIndex = nil,
		WaitingForArrivalIndex = nil,
	}
	player:SetAttribute("DungeonManualAdvanceReady", false)

	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		task.defer(refreshPlayer, player)
	end)
	player.CharacterAdded:Connect(function()
		task.delay(0.4, refreshPlayer, player)
	end)

	task.spawn(function()
		while player.Parent == Players and states[player] do
			refreshPlayer(player)
			task.wait(math.max(0.12, Config.EligibilityPollSeconds))
		end
	end)
end

remote.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" or payload.Action ~= "AdvanceRequest" then
		return
	end
	beginAdvance(player, payload.ReadyToken)
end)

-- O clear oficial ja publica este serial. Reagir a ele deixa o botao aparecer
-- imediatamente, sem depender do proximo ciclo de polling.
workspace:GetAttributeChangedSignal("DungeonIslandClearFeedbackSerial"):Connect(function()
	local clearedIndex = tonumber(
		workspace:GetAttribute("DungeonIslandClearFeedbackIsland")
	)
	if not clearedIndex then
		return
	end
	clearedIndex = math.floor(clearedIndex)
	for _, player in ipairs(Players:GetPlayers()) do
		local currentIndex = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
		if currentIndex and math.floor(currentIndex) == clearedIndex then
			task.defer(refreshPlayer, player)
		end
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

workspace:SetAttribute("DungeonManualIslandAdvanceReady", true)
workspace:SetAttribute("DungeonManualIslandAdvanceVersion", VERSION)
