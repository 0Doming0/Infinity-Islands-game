local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DungeonRecoveryService = {}

local DEFAULT_CHECK_INTERVAL = 0.25
local DEFAULT_FALL_DISTANCE_BELOW_CHECKPOINT = 55
local DEFAULT_FAST_FALL_SPEED = -35
local DEFAULT_FAST_FALL_SECONDS = 0.85
local DEFAULT_GROUND_SCAN_DEPTH = 32
local DEFAULT_EMBEDDED_SECONDS = 1.4
local DEFAULT_STUCK_SECONDS = 6.5
local DEFAULT_STUCK_DISPLACEMENT = 0.8
local DEFAULT_RESCUE_COOLDOWN = 8
local DEFAULT_RESCUE_PROTECTION_SECONDS = 4

local started = false
local options = {}
local participantSet = {}
local records = setmetatable({}, { __mode = "k" })
local heartbeatConnection
local playerRemovingConnection
local accumulator = 0
local rescueCount = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function horizontalDistance(left, right)
	local offset = left - right
	return Vector2.new(offset.X, offset.Z).Magnitude
end

local function checkpointCFrame()
	local callback = options.GetCheckpoint
	if type(callback) ~= "function" then
		return nil
	end
	local context = callback()
	if type(context) ~= "table" then
		return nil
	end
	local marker = context.SafeSpawn
	if typeof(marker) == "Instance" and marker:IsA("BasePart") and marker.Parent then
		return marker.CFrame, context
	end
	if typeof(marker) == "CFrame" then
		return marker, context
	end
	return nil
end

local function eligiblePlayer(player)
	if not player
		or player.Parent ~= Players
		or not participantSet[player.UserId]
		or player:GetAttribute("DungeonSessionId") == nil
		or player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
		or player:GetAttribute("IsDowned") == true
	then
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
		or root.Anchored
		or character:GetAttribute("MovementLocked") == true
		or player:GetAttribute("RespawnState") == "Positioning"
	then
		return nil
	end
	return character, humanoid, root
end

local function recordFor(player, root)
	local record = records[player]
	if not record then
		record = {
			LastPosition = root.Position,
			StuckAnchorPosition = root.Position,
			CooldownUntil = 0,
		}
		records[player] = record
	end
	return record
end

local function groundBelow(character, root, depth)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	local result = workspace:Raycast(
		root.Position + Vector3.new(0, 1.5, 0),
		Vector3.new(0, -math.max(4, depth), 0),
		params
	)
	return result ~= nil and result.Instance ~= nil and result.Instance.CanCollide == true
end

local function embeddedInGeometry(character, root)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.MaxParts = 12
	local size = Vector3.new(
		math.max(0.9, root.Size.X * 0.62),
		math.max(1.1, root.Size.Y * 0.72),
		math.max(0.9, root.Size.Z * 0.62)
	)
	for _, part in ipairs(workspace:GetPartBoundsInBox(root.CFrame, size, params)) do
		if part:IsA("BasePart") and part.CanCollide and part.Transparency < 1 then
			return true, part
		end
	end
	return false, nil
end

local function clearDetection(record, root)
	record.FastFallSince = nil
	record.EmbeddedSince = nil
	record.StuckSince = nil
	record.StuckAnchorPosition = root and root.Position or record.StuckAnchorPosition
	record.LastPosition = root and root.Position or record.LastPosition
end

local function setRescueState(player, state, reason)
	player:SetAttribute("SanctuaryRescueState", state)
	player:SetAttribute("DungeonRecoveryState", state)
	player:SetAttribute("DungeonRecoveryReason", reason)
	player:SetAttribute("DungeonRecoveryStateChangedAt", now())
end

local function performRescue(player, record, reason)
	if record.Rescuing or now() < (record.CooldownUntil or 0) then
		return false, "RecoveryCooldown"
	end
	local callback = options.PositionPlayer
	if type(callback) ~= "function" then
		return false, "PositionCallbackMissing"
	end
	local spawnCFrame = checkpointCFrame()
	if not spawnCFrame then
		return false, "CheckpointUnavailable"
	end

	record.Rescuing = true
	record.CooldownUntil = now() + math.max(1, tonumber(options.RescueCooldownSeconds) or DEFAULT_RESCUE_COOLDOWN)
	setRescueState(player, "Searching", reason)
	player:SetAttribute("DungeonRecoveryRequestedAt", now())

	task.spawn(function()
		setRescueState(player, "Teleporting", reason)
		local success, errorCode = callback(player, "AutoRecovery:" .. tostring(reason))
		if success then
			rescueCount += 1
			local protectionSeconds = math.max(
				1,
				tonumber(options.ProtectionSeconds) or DEFAULT_RESCUE_PROTECTION_SECONDS
			)
			local protectionUntil = now() + protectionSeconds
			player:SetAttribute("SanctuaryRescueProtectionUntil", protectionUntil)
			player:SetAttribute("DungeonRecoveryProtectionUntil", protectionUntil)
			player:SetAttribute("DungeonRecoveryCount", (player:GetAttribute("DungeonRecoveryCount") or 0) + 1)
			player:SetAttribute("DungeonLastRecoveryAt", now())
			player:SetAttribute("DungeonLastRecoveryReason", tostring(reason))
			workspace:SetAttribute("DungeonRecoveryTotalCount", rescueCount)
			workspace:SetAttribute("DungeonLastRecoveryUserId", player.UserId)
			workspace:SetAttribute("DungeonLastRecoveryReason", tostring(reason))
			workspace:SetAttribute("DungeonLastRecoveryAt", now())
			setRescueState(player, "Stabilizing", reason)
			task.delay(protectionSeconds, function()
				if player.Parent == Players
					and player:GetAttribute("DungeonRecoveryState") == "Stabilizing"
				then
					setRescueState(player, "Idle", nil)
				end
			end)
		else
			player:SetAttribute("DungeonRecoveryError", tostring(errorCode))
			setRescueState(player, "Failed", reason)
			task.delay(1, function()
				if player.Parent == Players and player:GetAttribute("DungeonRecoveryState") == "Failed" then
					setRescueState(player, "Idle", nil)
				end
			end)
		end
		record.Rescuing = false
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		clearDetection(record, root)
	end)
	return true
end

local function evaluatePlayer(player)
	local character, humanoid, root = eligiblePlayer(player)
	if not root then
		return
	end
	local record = recordFor(player, root)
	if record.Rescuing or now() < (record.CooldownUntil or 0) then
		record.LastPosition = root.Position
		return
	end

	local spawnCFrame = checkpointCFrame()
	if not spawnCFrame then
		clearDetection(record, root)
		return
	end
	local checkpointY = spawnCFrame.Position.Y
	local fallDistance = math.max(
		25,
		tonumber(options.FallDistanceBelowCheckpoint) or DEFAULT_FALL_DISTANCE_BELOW_CHECKPOINT
	)
	local destroyThreshold = workspace.FallenPartsDestroyHeight + 30
	if root.Position.Y <= checkpointY - fallDistance or root.Position.Y <= destroyThreshold then
		performRescue(player, record, "FellBelowRecoveryThreshold")
		return
	end

	local humanoidState = humanoid:GetState()
	local fastFall = humanoidState == Enum.HumanoidStateType.Freefall
		and root.AssemblyLinearVelocity.Y <= (
			tonumber(options.FastFallSpeed) or DEFAULT_FAST_FALL_SPEED
		)
		and not groundBelow(
			character,
			root,
			math.max(12, tonumber(options.GroundScanDepth) or DEFAULT_GROUND_SCAN_DEPTH)
		)
	if fastFall then
		record.FastFallSince = record.FastFallSince or now()
		if now() - record.FastFallSince >= (
			tonumber(options.FastFallSeconds) or DEFAULT_FAST_FALL_SECONDS
		) then
			performRescue(player, record, "UnrecoverableFall")
			return
		end
	else
		record.FastFallSince = nil
	end

	local embedded, blockingPart = embeddedInGeometry(character, root)
	if embedded then
		record.EmbeddedSince = record.EmbeddedSince or now()
		record.EmbeddedPartName = blockingPart and blockingPart:GetFullName() or nil
		if now() - record.EmbeddedSince >= (
			tonumber(options.EmbeddedSeconds) or DEFAULT_EMBEDDED_SECONDS
		) then
			player:SetAttribute("DungeonRecoveryBlockingPart", record.EmbeddedPartName)
			performRescue(player, record, "EmbeddedInGeometry")
			return
		end
	else
		record.EmbeddedSince = nil
		record.EmbeddedPartName = nil
	end

	local movingIntent = humanoid.MoveDirection.Magnitude >= 0.2
	local horizontalVelocity = Vector2.new(
		root.AssemblyLinearVelocity.X,
		root.AssemblyLinearVelocity.Z
	).Magnitude
	local stableState = humanoidState ~= Enum.HumanoidStateType.Freefall
		and humanoidState ~= Enum.HumanoidStateType.Jumping
		and humanoidState ~= Enum.HumanoidStateType.Swimming
	if movingIntent and stableState and horizontalVelocity <= 2.5 then
		record.StuckSince = record.StuckSince or now()
		record.StuckAnchorPosition = record.StuckAnchorPosition or root.Position
		local displacement = horizontalDistance(root.Position, record.StuckAnchorPosition)
		if displacement > (
			tonumber(options.StuckDisplacementStuds) or DEFAULT_STUCK_DISPLACEMENT
		) then
			record.StuckSince = now()
			record.StuckAnchorPosition = root.Position
		elseif now() - record.StuckSince >= (
			tonumber(options.StuckSeconds) or DEFAULT_STUCK_SECONDS
		) then
			performRescue(player, record, "MovementStuck")
			return
		end
	else
		record.StuckSince = nil
		record.StuckAnchorPosition = root.Position
	end
	record.LastPosition = root.Position
end

function DungeonRecoveryService.Start(startOptions)
	if started then
		return true
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	participantSet = {}
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
		end
	end
	rescueCount = 0
	accumulator = 0
	workspace:SetAttribute("DungeonRecoveryServiceReady", true)
	workspace:SetAttribute("DungeonRecoveryPolicy", "CheckpointFallAndGeometryRecoveryV1")
	workspace:SetAttribute(
		"DungeonRecoveryFallDistanceStuds",
		tonumber(options.FallDistanceBelowCheckpoint) or DEFAULT_FALL_DISTANCE_BELOW_CHECKPOINT
	)
	workspace:SetAttribute(
		"DungeonRecoveryStuckSeconds",
		tonumber(options.StuckSeconds) or DEFAULT_STUCK_SECONDS
	)
	workspace:SetAttribute(
		"DungeonRecoveryProtectionSeconds",
		tonumber(options.ProtectionSeconds) or DEFAULT_RESCUE_PROTECTION_SECONDS
	)
	workspace:SetAttribute("DungeonRecoveryTotalCount", 0)

	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		local interval = math.max(0.1, tonumber(options.CheckInterval) or DEFAULT_CHECK_INTERVAL)
		if accumulator < interval then
			return
		end
		accumulator = 0
		for _, player in ipairs(Players:GetPlayers()) do
			evaluatePlayer(player)
		end
	end)
	return true
end

function DungeonRecoveryService.Stop()
	started = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	for player in pairs(records) do
		if player.Parent == Players then
			player:SetAttribute("SanctuaryRescueState", "Idle")
			player:SetAttribute("DungeonRecoveryState", "Idle")
		end
	end
	records = setmetatable({}, { __mode = "k" })
	participantSet = {}
	options = {}
	workspace:SetAttribute("DungeonRecoveryServiceReady", false)
end

function DungeonRecoveryService.Request(player, reason)
	local _, _, root = eligiblePlayer(player)
	if not root then
		return false, "PlayerNotEligible"
	end
	return performRescue(player, recordFor(player, root), reason or "ManualRecovery")
end

function DungeonRecoveryService.GetSnapshot(player)
	if player then
		local record = records[player]
		return {
			Ready = started,
			State = player:GetAttribute("DungeonRecoveryState") or "Idle",
			Count = player:GetAttribute("DungeonRecoveryCount") or 0,
			CooldownUntil = record and record.CooldownUntil,
			LastReason = player:GetAttribute("DungeonLastRecoveryReason"),
			LastRecoveryAt = player:GetAttribute("DungeonLastRecoveryAt"),
		}
	end
	return {
		Ready = started,
		Policy = "CheckpointFallAndGeometryRecoveryV1",
		ParticipantCount = (function()
			local count = 0
			for _ in pairs(participantSet) do
				count += 1
			end
			return count
		end)(),
		TotalRecoveries = rescueCount,
	}
end

return DungeonRecoveryService
