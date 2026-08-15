-- Transporte autoritativo para a proxima ilha adequada ao PlayerLevel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(
	ReplicatedStorage.Shared.Configs.AssistedIslandTransportConfig
)
local IslandProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.IslandProgressionConfig
)
local RemoteRegistry = require(
	ReplicatedStorage.Shared.Utilities.RemoteRegistry
)
local DungeonGenerator = require(script.Parent.DungeonGenerator)

local AssistedIslandTransportService = {}

local started = false
local remote
local states = setmetatable({}, { __mode = "k" })
local connections = setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function islandFor(context)
	if type(context) ~= "table" then
		return nil
	end
	return context.IslandModel or context.Model
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
	local cframe = markerCFrame(marker)
	if cframe then
		return cframe.Position
	end
	if typeof(marker) == "Instance" and marker:IsA("Model") and marker.Parent then
		return marker:GetPivot().Position
	end
	return nil
end

local function livingCharacter(player)
	if not player or player.Parent ~= Players then
		return nil
	end
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
	return math.max(
		0,
		math.floor(
			type(plan) == "table" and tonumber(plan.TotalIslandCount)
				or tonumber(workspace:GetAttribute("DungeonRouteIslandCount"))
				or 0
		)
	)
end

local function recommendedLevel(index, context)
	local island = islandFor(context)
	return math.max(
		1,
		math.floor(
			tonumber(
				island
					and (
						island:GetAttribute("RecommendedLevel")
						or island:GetAttribute("IslandLevel")
					)
			)
				or IslandProgressionConfig.GetRecommendedLevel(index)
		)
	)
end

local function currentIslandCleared(context)
	if not Config.RequireCurrentIslandCleared then
		return true
	end
	local island = islandFor(context)
	return island ~= nil and island:GetAttribute("Cleared") == true
end

local function resolveEligibility(player, allowUncleared)
	if not Config.Enabled or not playerCanTravel(player) then
		return nil, "PlayerUnavailable"
	end

	local state = states[player]
	if state and now() < (state.CooldownUntil or 0) then
		return nil, "Cooldown"
	end

	local currentIndex = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local total = routeTotal()
	if total <= 0 or currentIndex >= total then
		return nil, "NoNextIsland"
	end

	local nextIndex = currentIndex + 1
	local currentContext = DungeonGenerator.GetRouteIslandContext(currentIndex)
	local destinationContext = DungeonGenerator.GetRouteIslandContext(nextIndex)
	local playerLevel = cleanIndex(player:GetAttribute("PlayerLevel"))
	local requiredLevel = recommendedLevel(nextIndex, destinationContext)

	if playerLevel < requiredLevel then
		return nil, "LevelBelowRecommendation"
	end

	if not allowUncleared and not currentIslandCleared(currentContext) then
		return nil, "CurrentIslandNotCleared"
	end

	return {
		CurrentIndex = currentIndex,
		DestinationIndex = nextIndex,
		CurrentContext = currentContext,
		DestinationContext = destinationContext,
		RecommendedLevel = requiredLevel,
	}, nil
end

local function resolveGuidanceRoute(player)
	if not Config.GuidanceIndicatorEnabled or not playerCanTravel(player) then
		return nil
	end

	local currentIndex = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local total = routeTotal()
	local playerLevel = cleanIndex(player:GetAttribute("PlayerLevel"))
	local targetIndex = currentIndex

	for index = currentIndex + 1, total do
		local context = DungeonGenerator.GetRouteIslandContext(index)
		if recommendedLevel(index, context) > playerLevel then
			break
		end
		targetIndex = index
	end

	if targetIndex <= currentIndex then
		return nil
	end

	return {
		CurrentIndex = currentIndex,
		TargetIndex = targetIndex,
		TargetRecommendedLevel = recommendedLevel(
			targetIndex,
			DungeonGenerator.GetRouteIslandContext(targetIndex)
		),
	}
end

local function setProtected(player, state, active)
	if active then
		player:SetAttribute("DungeonAssistedTransportActive", true)
	else
		player:SetAttribute("DungeonAssistedTransportActive", nil)
	end
end

local function fire(player, payload)
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function automaticFlightUsed(state, sourceIndex)
	local counts = state and state.FlightCountBySourceIsland
	return (counts and (counts[sourceIndex] or 0) or 0)
		>= Config.AutomaticFlightsPerSourceIsland
end

local function beginGuidance(player, eligibility, reason)
	local state = states[player]
	if not state then
		return
	end

	state.Token += 1
	local token = state.Token
	state.Phase = "Guidance"
	state.GuidanceTargetIndex = eligibility.TargetIndex
	state.DestinationIndex = eligibility.TargetIndex
	player:SetAttribute("DungeonRouteArrowEligible", true)
	player:SetAttribute(
		"DungeonRouteArrowRequiredLevel",
		eligibility.TargetRecommendedLevel
	)
	player:SetAttribute("DungeonRouteArrowServerTargetIsland", eligibility.TargetIndex)
	player:SetAttribute("DungeonRouteArrowTriggeredAt", now())

	DungeonGenerator.RequestRouteThrough(eligibility.TargetIndex)
	local destinationContext = DungeonGenerator.GetRouteIslandContext(
		eligibility.TargetIndex
	)
	local destinationCFrame = destinationContext
		and markerCFrame(destinationContext.SafeSpawn)
	local focusPosition = destinationContext
		and (
			markerPosition(destinationContext.ObjectiveAnchor)
			or markerPosition(destinationContext.Floor)
		)
		or nil
	local destinationPosition = focusPosition
		or (destinationCFrame and destinationCFrame.Position)
		or nil

	player:SetAttribute("DungeonAssistedTransportState", "Guidance")
	player:SetAttribute(
		"DungeonAssistedTransportDestination",
		eligibility.TargetIndex
	)
	local payload = {
		Action = "Guidance",
		Token = token,
		Reason = tostring(reason or "AutomaticFlightAlreadyUsed"),
		SourceIndex = eligibility.CurrentIndex,
		DestinationIndex = eligibility.TargetIndex,
		TargetIndex = eligibility.TargetIndex,
		DestinationLabel = "ILHA "
			.. tostring(math.max(1, eligibility.TargetIndex - 1)),
		DestinationPosition = destinationPosition,
		RecommendedLevel = eligibility.TargetRecommendedLevel,
	}
	if destinationPosition then
		player:SetAttribute("DungeonRouteArrowDestinationPosition", destinationPosition)
	end
	fire(player, payload)

	if not destinationPosition then
		task.spawn(function()
			local deadline = os.clock() + Config.DestinationReadyTimeoutSeconds
			repeat
				if not states[player] or states[player].Token ~= token or states[player].Phase ~= "Guidance" then
					return
				end
				DungeonGenerator.RequestRouteThrough(eligibility.TargetIndex)
				local context = DungeonGenerator.GetRouteIslandContext(eligibility.TargetIndex)
				local safeSpawn = context and markerCFrame(context.SafeSpawn)
				local focus = context and (markerPosition(context.ObjectiveAnchor) or markerPosition(context.Floor))
				local position = focus or (safeSpawn and safeSpawn.Position)
				if position then
					payload.DestinationPosition = position
					player:SetAttribute("DungeonRouteArrowDestinationPosition", position)
					fire(player, payload)
					return
				end
				task.wait(Config.EligibilityPollSeconds)
			until os.clock() >= deadline
		end)
	end
end

local function restoreCharacter(state)
	local root = state.Root
	local humanoid = state.Humanoid
	local character = state.Character
	if character and character.Parent then
		root = character:FindFirstChild("HumanoidRootPart") or root
		humanoid = character:FindFirstChildOfClass("Humanoid") or humanoid
	end
	if root and root.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = (tonumber(state.WalkSpeedWas) or 0) > 0 and state.WalkSpeedWas or 16
		if state.UseJumpPowerWas then
			humanoid.JumpPower = (tonumber(state.JumpPowerWas) or 0) > 0 and state.JumpPowerWas or 50
		else
			humanoid.JumpHeight = (tonumber(state.JumpHeightWas) or 0) > 0 and state.JumpHeightWas or 7.2
		end
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid.AutoRotate = state.AutoRotateWasEnabled ~= false
		humanoid:Move(Vector3.zero, false)
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
	if character and character.Parent then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Anchored then
				descendant.Anchored = false
			end
		end
	end
	state.Root = nil
	state.Humanoid = nil
	state.Character = nil
end

local function verifyReleasedCharacter(player)
	local character, humanoid, root = livingCharacter(player)
	if not character then
		return
	end
	if root.Anchored then
		root.Anchored = false
	end
	if humanoid.PlatformStand or humanoid.Sit then
		humanoid.PlatformStand = false
		humanoid.Sit = false
	end
	if humanoid.AutoRotate == false then
		humanoid.AutoRotate = true
	end
	pcall(function()
		root:SetNetworkOwnershipAuto()
	end)
end

local function cancel(player, reason)
	local state = states[player]
	if not state then
		return
	end
	state.Token += 1
	if state.Protected then
		state.Protected = false
		setProtected(player, state, false)
	end
	restoreCharacter(state)
	state.Phase = "Idle"
	state.GuidanceTargetIndex = nil
	player:SetAttribute("DungeonAssistedTransportState", "Idle")
	player:SetAttribute("DungeonAssistedTransportDestination", nil)
	player:SetAttribute("DungeonRouteArrowEligible", false)
	fire(player, {
		Action = "Cancel",
		Reason = tostring(reason or "Cancelled"),
	})
end

local function waitForContext(index, token, player)
	DungeonGenerator.RequestRouteThrough(index)
	local deadline = os.clock() + Config.DestinationReadyTimeoutSeconds
	repeat
		if not states[player] or states[player].Token ~= token then
			return nil
		end
		local context = DungeonGenerator.GetRouteIslandContext(index)
		if context and markerCFrame(context.SafeSpawn) then
			return context
		end
		task.wait(Config.EligibilityPollSeconds)
	until os.clock() >= deadline
	return nil
end

local function quadraticBezier(startPosition, controlPosition, endPosition, alpha)
	local inverse = 1 - alpha
	return inverse * inverse * startPosition
		+ 2 * inverse * alpha * controlPosition
		+ alpha * alpha * endPosition
end

local function performFlight(player, eligibility, token)
	local state = states[player]
	if not state or state.Token ~= token then
		return
	end

	local destinationContext = eligibility.DestinationContext
	if not destinationContext or not markerCFrame(destinationContext.SafeSpawn) then
		destinationContext = waitForContext(eligibility.DestinationIndex, token, player)
	end
	if not destinationContext then
		cancel(player, "DestinationUnavailable")
		return
	end

	local character, humanoid, root = livingCharacter(player)
	if not character then
		cancel(player, "CharacterUnavailable")
		return
	end

	local safeSpawn = markerCFrame(destinationContext.SafeSpawn)
	local destinationCFrame = safeSpawn * CFrame.new(0, Config.SafeSpawnHeightStuds, 0)
	local focusPosition = markerPosition(destinationContext.ObjectiveAnchor)
		or markerPosition(destinationContext.Floor)
		or destinationCFrame.Position

	state.Phase = "Flying"
	state.Character = character
	state.Root = root
	state.Humanoid = humanoid
	state.RootWasAnchored = root.Anchored
	state.AutoRotateWasEnabled = humanoid.AutoRotate
	state.WalkSpeedWas = humanoid.WalkSpeed
	state.JumpPowerWas = humanoid.JumpPower
	state.JumpHeightWas = humanoid.JumpHeight
	state.UseJumpPowerWas = humanoid.UseJumpPower
	state.Protected = true
	state.DestinationIndex = eligibility.DestinationIndex
	setProtected(player, state, true)

	player:SetAttribute("DungeonAssistedTransportState", "Flying")
	player:SetAttribute("DungeonAssistedTransportDestination", eligibility.DestinationIndex)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	humanoid.Sit = false

	local startPosition = root.Position
	local endPosition = destinationCFrame.Position
	local horizontalOffset = Vector3.new(
		endPosition.X - startPosition.X,
		0,
		endPosition.Z - startPosition.Z
	)
	local horizontalDistance = horizontalOffset.Magnitude
	local arcHeight = math.clamp(
		horizontalDistance * Config.ArcHeightPerHorizontalStud,
		Config.MinimumArcHeightStuds,
		Config.MaximumArcHeightStuds
	)
	local lateral = Vector3.zero
	if horizontalDistance > 0.01 then
		local side = Vector3.new(-horizontalOffset.Z, 0, horizontalOffset.X).Unit
		local sign = ((player.UserId + eligibility.DestinationIndex) % 2 == 0) and 1 or -1
		lateral = side
			* math.min(
				horizontalDistance * Config.LateralCurvePerHorizontalStud,
				Config.MaximumLateralCurveStuds
			)
			* sign
	end
	local controlPosition = (startPosition + endPosition) / 2
		+ Vector3.new(0, arcHeight, 0)
		+ lateral

	fire(player, {
		Action = "BeginFlight",
		Token = token,
		Duration = Config.FlightDurationSeconds,
		FocusPosition = focusPosition,
		DestinationPosition = endPosition,
		DestinationIndex = eligibility.DestinationIndex,
	})

	local startedAt = now()
	while state.Token == token and playerCanTravel(player) do
		local linearAlpha = math.clamp(
			(now() - startedAt) / Config.FlightDurationSeconds,
			0,
			1
		)
		local alpha = linearAlpha * linearAlpha * (3 - 2 * linearAlpha)
		local position = quadraticBezier(startPosition, controlPosition, endPosition, alpha)
		local nextAlpha = math.min(1, alpha + 0.015)
		local nextPosition = quadraticBezier(startPosition, controlPosition, endPosition, nextAlpha)
		local forward = nextPosition - position
		if forward.Magnitude <= 0.01 then
			forward = destinationCFrame.LookVector
		end
		character:PivotTo(CFrame.lookAt(position, position + forward.Unit))
		if linearAlpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end

	if state.Token ~= token or not playerCanTravel(player) then
		cancel(player, "FlightInterrupted")
		return
	end

	character:PivotTo(destinationCFrame)
	state.FlightCountBySourceIsland[eligibility.CurrentIndex] =
		(state.FlightCountBySourceIsland[eligibility.CurrentIndex] or 0) + 1
	player:SetAttribute(
		"DungeonAssistedTransportLastAutomaticSource",
		eligibility.CurrentIndex
	)
	state.Phase = "Landing"
	player:SetAttribute("DungeonAssistedTransportState", "LandingCountdown")
	local releaseAt = now() + Config.LandingCountdownSeconds
	fire(player, {
		Action = "Landed",
		Token = token,
		ReleaseAt = releaseAt,
		Countdown = Config.LandingCountdownSeconds,
		FocusPosition = focusPosition,
	})

	while state.Token == token and now() < releaseAt and playerCanTravel(player) do
		RunService.Heartbeat:Wait()
	end
	if state.Token ~= token or not playerCanTravel(player) then
		cancel(player, "LandingInterrupted")
		return
	end

	state.CooldownUntil = now() + Config.CooldownSeconds
	restoreCharacter(state)
	if state.Protected then
		state.Protected = false
		setProtected(player, state, false)
	end
	verifyReleasedCharacter(player)
	fire(player, {
		Action = "Release",
		Token = token,
	})

	task.delay(0.35, function()
		local latest = states[player]
		if latest and latest.Token == token and latest.Phase == "Landing" then
			verifyReleasedCharacter(player)
		end
	end)

	task.delay(Config.ReleaseProtectionSeconds, function()
		local latest = states[player]
		if not latest or latest.Token ~= token then
			return
		end
		verifyReleasedCharacter(player)
		local continuedTarget = tonumber(latest.GuidanceTargetIndex)
		if Config.GuidanceIndicatorEnabled
			and continuedTarget
			and continuedTarget > eligibility.DestinationIndex
		then
			beginGuidance(player, {
				CurrentIndex = eligibility.DestinationIndex,
				TargetIndex = continuedTarget,
				TargetRecommendedLevel = recommendedLevel(
					continuedTarget,
					DungeonGenerator.GetRouteIslandContext(continuedTarget)
				),
			}, "ContinueAfterAutomaticFlight")
		else
			latest.Phase = "Idle"
			latest.GuidanceTargetIndex = nil
			player:SetAttribute("DungeonAssistedTransportState", "Idle")
			player:SetAttribute("DungeonAssistedTransportDestination", nil)
			player:SetAttribute("DungeonRouteArrowEligible", false)
		end
	end)
end

local function beginLevelUpCountdown(player)
	local state = states[player]
	if not state
		or state.Phase == "Warning"
		or state.Phase == "WaitingForClear"
		or state.Phase == "Flying"
		or state.Phase == "Landing"
	then
		return
	end

	local guidanceRoute = resolveGuidanceRoute(player)
	local eligibility = resolveEligibility(player, true)
	if not eligibility then
		cancel(player, "NotEligibleAfterLevelUp")
		return
	end

	if Config.GuidanceIndicatorEnabled
		and automaticFlightUsed(state, eligibility.CurrentIndex)
	then
		if guidanceRoute then
			beginGuidance(player, guidanceRoute, "AutomaticFlightAlreadyUsed")
		end
		return
	end

	state.GuidanceTargetIndex = guidanceRoute and guidanceRoute.TargetIndex or nil
	player:SetAttribute("DungeonRouteArrowEligible", guidanceRoute ~= nil)
	player:SetAttribute(
		"DungeonRouteArrowRequiredLevel",
		eligibility.RecommendedLevel
	)
	player:SetAttribute(
		"DungeonRouteArrowServerTargetIsland",
		guidanceRoute and guidanceRoute.TargetIndex or eligibility.DestinationIndex
	)
	player:SetAttribute("DungeonRouteArrowTriggeredAt", now())
	state.Token += 1
	local token = state.Token
	state.Phase = "Warning"
	local transportAt = now() + Config.LevelUpDelaySeconds
	DungeonGenerator.RequestRouteThrough(eligibility.DestinationIndex)
	local earlyContext = DungeonGenerator.GetRouteIslandContext(
		eligibility.DestinationIndex
	)
	if earlyContext then
		eligibility.DestinationContext = earlyContext
	end
	local earlyDestinationCFrame = earlyContext
		and markerCFrame(earlyContext.SafeSpawn)
	player:SetAttribute("DungeonAssistedTransportState", "Warning")
	player:SetAttribute("DungeonAssistedTransportDestination", eligibility.DestinationIndex)
	fire(player, {
		Action = "Warning",
		Token = token,
		TransportAt = transportAt,
		Countdown = Config.LevelUpDelaySeconds,
		DestinationIndex = eligibility.DestinationIndex,
		DestinationLabel = "ILHA " .. tostring(math.max(1, eligibility.DestinationIndex - 1)),
		RecommendedLevel = eligibility.RecommendedLevel,
		GuidanceSourceIndex = guidanceRoute and guidanceRoute.CurrentIndex or nil,
		GuidanceTargetIndex = guidanceRoute and guidanceRoute.TargetIndex or nil,
		GuidanceDestinationLabel = guidanceRoute
			and (
				"ILHA "
					.. tostring(math.max(1, guidanceRoute.TargetIndex - 1))
			)
			or nil,
		DestinationPosition = earlyDestinationCFrame
			and earlyDestinationCFrame.Position
			or nil,
	})

	task.spawn(function()
		while state.Token == token and now() < transportAt do
			if not playerCanTravel(player)
				or cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex")) ~= eligibility.CurrentIndex
			then
				cancel(player, "WarningCancelled")
				return
			end
			task.wait(Config.EligibilityPollSeconds)
		end
		if state.Token ~= token then
			return
		end

		local finalEligibility, reason = resolveEligibility(player, false)
		if not finalEligibility and reason == "CurrentIslandNotCleared" then
			state.Phase = "WaitingForClear"
			player:SetAttribute("DungeonAssistedTransportState", "WaitingForClear")
			fire(player, {
				Action = "WaitingForClear",
				Token = token,
				DestinationIndex = eligibility.DestinationIndex,
			})
			repeat
				task.wait(Config.EligibilityPollSeconds)
				if state.Token ~= token
					or not playerCanTravel(player)
					or cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex")) ~= eligibility.CurrentIndex
				then
					cancel(player, "ClearWaitCancelled")
					return
				end
				finalEligibility, reason = resolveEligibility(player, false)
			until finalEligibility or reason ~= "CurrentIslandNotCleared"
		end

		if not finalEligibility then
			cancel(player, reason or "EligibilityChanged")
			return
		end
		performFlight(player, finalEligibility, token)
	end)
end

local function bindPlayer(player)
	if states[player] then
		return
	end
	states[player] = {
		Token = 0,
		Phase = "Idle",
		CooldownUntil = 0,
		FlightCountBySourceIsland = {},
		GuidanceTargetIndex = nil,
	}
	player:SetAttribute("DungeonAssistedTransportState", "Idle")

	local list = {}
	connections[player] = list
	table.insert(list, player:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
		beginLevelUpCountdown(player)
	end))
	table.insert(list, player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(function()
		beginLevelUpCountdown(player)
	end))
	table.insert(list, player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		local state = states[player]
		if state and (
			state.Phase == "Warning"
			or state.Phase == "WaitingForClear"
		) then
			cancel(player, "PlayerAdvancedManually")
		elseif state and state.Phase == "Guidance" then
			local currentIndex = cleanIndex(
				player:GetAttribute("CurrentGlobalIslandIndex")
			)
			if currentIndex >= cleanIndex(state.GuidanceTargetIndex) then
				cancel(player, "GuidanceDestinationReached")
			end
		end
	end))
	table.insert(list, player.CharacterRemoving:Connect(function()
		local state = states[player]
		if not state or state.Phase ~= "Guidance" then
			cancel(player, "CharacterRemoving")
		end
	end))
	table.insert(list, player.CharacterAdded:Connect(function()
		task.spawn(function()
			local deadline = os.clock() + Config.DestinationReadyTimeoutSeconds
			repeat
				task.wait(Config.EligibilityPollSeconds)
			until playerCanTravel(player) or os.clock() >= deadline

			local state = states[player]
			if not state or state.Phase ~= "Guidance" then
				return
			end
			local route = resolveGuidanceRoute(player)
			if route then
				beginGuidance(player, route, "RespawnResume")
			else
				cancel(player, "GuidanceNoLongerRequired")
			end
		end)
	end))
end

local function unbindPlayer(player)
	cancel(player, "PlayerRemoving")
	for _, connection in ipairs(connections[player] or {}) do
		connection:Disconnect()
	end
	connections[player] = nil
	states[player] = nil
end

function AssistedIslandTransportService.Start()
	if started then
		return false, "AlreadyStarted"
	end
	Config.Validate()
	remote = RemoteRegistry.Get("Navigation", "AssistedIslandTransport", "RemoteEvent")
	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(unbindPlayer)

	workspace:SetAttribute("DungeonAssistedTransportReady", true)
	workspace:SetAttribute("DungeonAssistedTransportVersion", Config.Version)
	workspace:SetAttribute("DungeonAssistedTransportLevelUpDelay", Config.LevelUpDelaySeconds)
	return true
end

return AssistedIslandTransportService
