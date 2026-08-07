-- Tarefa 29: diretor complementar do boss.
-- Coordena transicoes de fase, ataques de arena e recompensa fisica final.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDamageService = require(script.Parent.Parent.MVPSystems.PlayerDamageService)
local MobCollectibleService = require(script.Parent.MobCollectibleService)

local BossEncounterDirector = {}

local POLICY = "ThreePhaseArenaDirectorV1"
local CONFIG = {
	PhaseTransitionSeconds = 1.65,
	PhaseRecoverySeconds = 1.15,
	SignatureIntervals = { 99, 10.5, 7.5 },
	SkyfallWindup = 1.05,
	SkyfallRadius = 7.5,
	CrossSweepWindup = 1.15,
	CrossSweepHalfWidth = 5.5,
	ArenaCollapseWindup = 1.35,
	ArenaCollapseSafeRadius = 10,
	RewardTravelSeconds = 2.8,
	RewardMinimumCoins = 50,
	RewardMaximumCoins = 250,
}

local started = false
local sessionId = ""
local participantSet = {}
local activeState
local activeOptions = {}
local connections = {}
local directorContent
local phaseToken = 0
local signatureToken = 0
local nextSignatureAt = math.huge
local signatureIndex = 0
local rewardIssued = false
local heartbeatConnection

local function now()
	return workspace:GetServerTimeNow()
end

local function clearConnections()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function bossAlive(state)
	return state
		and state.Boss
		and state.Boss.Parent
		and state.Humanoid
		and state.Humanoid.Health > 0
		and state.Completed ~= true
end

local function eligiblePlayer(player, targetUserId)
	if not player or player.Parent ~= Players then
		return nil
	end
	if next(participantSet) ~= nil and participantSet[player.UserId] ~= true then
		return nil
	end
	if targetUserId and targetUserId > 0 and player.UserId ~= targetUserId then
		return nil
	end
	if player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
		or player:GetAttribute("IsDowned") == true
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return player, humanoid, root
end

local function statePlayers()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if eligiblePlayer(player) then
			table.insert(result, player)
		end
	end
	return result
end

local function floorTop(state)
	local floor = state.ArenaContract and state.ArenaContract.Floor
	return floor and (floor.Position.Y + floor.Size.Y * 0.5 + 0.16) or 0
end

local function arenaCenter(state)
	local bounds = state.ArenaContract and state.ArenaContract.Bounds
	if bounds then
		return bounds.Position
	end
	local floor = state.ArenaContract and state.ArenaContract.Floor
	return floor and floor.Position or state.Root.Position
end

local function createDisk(state, name, position, radius, color, transparency, duration)
	local disk = Instance.new("Part")
	disk.Name = name
	disk.Shape = Enum.PartType.Cylinder
	disk.Size = Vector3.new(0.18, radius * 2, radius * 2)
	disk.Anchored = true
	disk.CanCollide = false
	disk.CanTouch = false
	disk.CanQuery = false
	disk.CastShadow = false
	disk.Material = Enum.Material.Neon
	disk.Color = color
	disk.Transparency = transparency
	disk.CFrame = CFrame.new(position.X, floorTop(state), position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	disk:SetAttribute("BossDirectorTelegraph", true)
	disk:SetAttribute("ExpiresAt", now() + duration)
	disk.Parent = directorContent
	Debris:AddItem(disk, duration + 0.4)
	return disk
end

local function createLane(state, name, cframe, size, color, duration)
	local lane = Instance.new("Part")
	lane.Name = name
	lane.Size = size
	lane.CFrame = cframe
	lane.Anchored = true
	lane.CanCollide = false
	lane.CanTouch = false
	lane.CanQuery = false
	lane.CastShadow = false
	lane.Material = Enum.Material.Neon
	lane.Color = color
	lane.Transparency = 0.5
	lane:SetAttribute("BossDirectorTelegraph", true)
	lane:SetAttribute("ExpiresAt", now() + duration)
	lane.Parent = directorContent
	Debris:AddItem(lane, duration + 0.4)
	return lane
end

local function createBurst(state, position, color, amount)
	local anchor = Instance.new("Part")
	anchor.Name = "BossDirectorBurst"
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Parent = directorContent or workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, color),
	})
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.35, 0.85)
	emitter.Speed = NumberRange.new(10, 25)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(amount or 60)
	Debris:AddItem(anchor, 1.2)
end

local function damagePlayer(player, humanoid, amount, source)
	if not player or not humanoid or amount <= 0 then
		return 0
	end
	return PlayerDamageService.Apply(player, humanoid, amount, source)
end

local function baseDamage(state)
	return math.max(1, tonumber(state.Boss:GetAttribute("AttackDamage")) or 18)
end

local function setDirectorState(stateName, endsAt)
	workspace:SetAttribute("DungeonBossDirectorReady", started)
	workspace:SetAttribute("DungeonBossDirectorPolicy", POLICY)
	workspace:SetAttribute("DungeonBossDirectorState", stateName)
	workspace:SetAttribute("DungeonBossDirectorStateEndsAt", endsAt)
	workspace:SetAttribute("DungeonBossDirectorUpdatedAt", now())
end

local function stopBossMovement(state)
	if not bossAlive(state) then
		return
	end
	state.Humanoid:MoveTo(state.Root.Position)
	state.Humanoid:Move(Vector3.zero)
	state.Root.AssemblyLinearVelocity = Vector3.zero
	state.Root.AssemblyAngularVelocity = Vector3.zero
end

local function beginDirectorAttack(state, attackName, duration)
	if not bossAlive(state)
		or state.Active ~= true
		or state.CombatEnabled ~= true
		or state.Attacking == true
		or state.Boss:GetAttribute("BossPhaseTransitioning") == true
	then
		return nil
	end
	state.Attacking = true
	state.AttackToken = (state.AttackToken or 0) + 1
	state.AttackName = attackName
	state.AttackEndsAt = now() + duration
	state.Boss:SetAttribute("BossAttack", attackName)
	state.Boss:SetAttribute("BossAttackEndsAt", state.AttackEndsAt)
	workspace:SetAttribute("DungeonBossAttack", attackName)
	workspace:SetAttribute("DungeonBossAttackEndsAt", state.AttackEndsAt)
	stopBossMovement(state)
	setDirectorState("SignatureAttack:" .. attackName, state.AttackEndsAt)
	return state.AttackToken
end

local function finishDirectorAttack(state, token)
	if activeState ~= state or not bossAlive(state) or state.AttackToken ~= token then
		return
	end
	state.Attacking = false
	state.AttackName = "Idle"
	state.AttackEndsAt = nil
	state.Boss:SetAttribute("BossAttack", "Idle")
	state.Boss:SetAttribute("BossAttackEndsAt", nil)
	workspace:SetAttribute("DungeonBossAttack", "Idle")
	workspace:SetAttribute("DungeonBossAttackEndsAt", nil)
	state.NextAttackAt = os.clock() + CONFIG.PhaseRecoverySeconds
	setDirectorState("CombatActive", nil)
end

local function phaseTransition(state, phase)
	if not bossAlive(state) or phase <= 1 then
		return
	end
	phaseToken += 1
	local token = phaseToken
	local duration = CONFIG.PhaseTransitionSeconds
	state.AttackToken = (state.AttackToken or 0) + 1
	state.Attacking = true
	state.AttackName = "PhaseTransition"
	state.AttackEndsAt = now() + duration
	state.CombatEnabled = false
	state.Boss:SetAttribute("BossPhaseTransitioning", true)
	state.Boss:SetAttribute("BossAttack", "PhaseTransition")
	state.Boss:SetAttribute("BossAttackEndsAt", state.AttackEndsAt)
	state.Boss:SetAttribute("Invulnerable", true)
	state.Root.Anchored = true
	stopBossMovement(state)
	workspace:SetAttribute("DungeonBossPhaseTransitioning", true)
	workspace:SetAttribute("DungeonBossPhaseTransitionEndsAt", state.AttackEndsAt)
	workspace:SetAttribute("DungeonBossPhaseTransitionPhase", phase)
	setDirectorState("PhaseTransition", state.AttackEndsAt)

	local center = state.Root.Position
	for index = 1, 3 do
		task.delay((index - 1) * 0.16, function()
			if activeState == state and bossAlive(state) and phaseToken == token then
				createDisk(
					state,
					"PhasePulse_" .. index,
					center,
					7 + index * 5,
					phase == 2 and Color3.fromRGB(108, 187, 255) or Color3.fromRGB(255, 95, 181),
					0.38,
					0.7
				)
				createBurst(
					state,
					center + Vector3.new(0, 5, 0),
					phase == 2 and Color3.fromRGB(108, 187, 255) or Color3.fromRGB(255, 95, 181),
					28
				)
			end
		end)
	end

	task.delay(duration, function()
		if activeState ~= state or not bossAlive(state) or phaseToken ~= token then
			return
		end
		state.Root.Anchored = false
		pcall(function()
			state.Root:SetNetworkOwner(nil)
		end)
		state.Attacking = false
		state.AttackName = "Idle"
		state.AttackEndsAt = nil
		state.CombatEnabled = true
		state.NextAttackAt = os.clock() + CONFIG.PhaseRecoverySeconds
		state.Boss:SetAttribute("BossPhaseTransitioning", false)
		state.Boss:SetAttribute("BossAttack", "Idle")
		state.Boss:SetAttribute("BossAttackEndsAt", nil)
		state.Boss:SetAttribute("Invulnerable", false)
		workspace:SetAttribute("DungeonBossPhaseTransitioning", false)
		workspace:SetAttribute("DungeonBossPhaseTransitionEndsAt", nil)
		workspace:SetAttribute("DungeonBossPhaseTransitionCompletedAt", now())
		nextSignatureAt = os.clock() + CONFIG.PhaseRecoverySeconds + 1
		setDirectorState("CombatActive", nil)
	end)
end

local function attackSkyfall(state)
	local windup = CONFIG.SkyfallWindup
	local token = beginDirectorAttack(state, "SkyfallVolley", windup + 0.45)
	if not token then
		return false
	end
	local positions = {}
	for _, player in ipairs(statePlayers()) do
		local _, _, root = eligiblePlayer(player)
		if root then
			local bounds = state.ArenaContract.Bounds
			local localPoint = bounds.CFrame:PointToObjectSpace(root.Position)
			local half = bounds.Size * 0.5
			local clamped = Vector3.new(
				math.clamp(localPoint.X, -half.X + 7, half.X - 7),
				0,
				math.clamp(localPoint.Z, -half.Z + 7, half.Z - 7)
			)
			table.insert(positions, bounds.CFrame:PointToWorldSpace(clamped))
		end
	end
	if #positions == 0 then
		table.insert(positions, arenaCenter(state))
	end
	local maximum = math.min(#positions, math.max(1, state.Phase))
	for index = 1, maximum do
		createDisk(
			state,
			"SkyfallTarget_" .. index,
			positions[index],
			CONFIG.SkyfallRadius,
			Color3.fromRGB(255, 116, 91),
			0.42,
			windup
		)
	end
	task.delay(windup, function()
		if activeState ~= state or not bossAlive(state) or state.AttackToken ~= token then
			return
		end
		for _, position in ipairs(positions) do
			createBurst(state, position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 116, 91), 45)
			for _, player in ipairs(statePlayers()) do
				local _, humanoid, root = eligiblePlayer(player)
				if humanoid and root then
					local horizontal = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude
					if horizontal <= CONFIG.SkyfallRadius then
						damagePlayer(player, humanoid, baseDamage(state) * 0.9, "BossSkyfallVolley")
					end
				end
			end
		end
		finishDirectorAttack(state, token)
	end)
	return true
end

local function attackCrossSweep(state)
	local windup = CONFIG.CrossSweepWindup
	local token = beginDirectorAttack(state, "CrossSweep", windup + 0.4)
	if not token then
		return false
	end
	local bounds = state.ArenaContract.Bounds
	local size = bounds.Size
	local center = CFrame.new(bounds.Position.X, floorTop(state), bounds.Position.Z)
	createLane(
		state,
		"CrossSweep_X",
		center,
		Vector3.new(size.X * 0.92, 0.22, CONFIG.CrossSweepHalfWidth * 2),
		Color3.fromRGB(255, 90, 142),
		windup
	)
	createLane(
		state,
		"CrossSweep_Z",
		center,
		Vector3.new(CONFIG.CrossSweepHalfWidth * 2, 0.22, size.Z * 0.92),
		Color3.fromRGB(255, 90, 142),
		windup
	)
	task.delay(windup, function()
		if activeState ~= state or not bossAlive(state) or state.AttackToken ~= token then
			return
		end
		createBurst(state, center.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 90, 142), 70)
		for _, player in ipairs(statePlayers()) do
			local _, humanoid, root = eligiblePlayer(player)
			if humanoid and root then
				local localPoint = bounds.CFrame:PointToObjectSpace(root.Position)
				if math.abs(localPoint.X) <= CONFIG.CrossSweepHalfWidth
					or math.abs(localPoint.Z) <= CONFIG.CrossSweepHalfWidth
				then
					damagePlayer(player, humanoid, baseDamage(state), "BossCrossSweep")
				end
			end
		end
		finishDirectorAttack(state, token)
	end)
	return true
end

local function attackArenaCollapse(state)
	local windup = CONFIG.ArenaCollapseWindup
	local token = beginDirectorAttack(state, "ArenaCollapse", windup + 0.5)
	if not token then
		return false
	end
	local center = arenaCenter(state)
	local bounds = state.ArenaContract.Bounds
	local radius = math.min(bounds.Size.X, bounds.Size.Z) * 0.46
	createDisk(
		state,
		"ArenaCollapseDanger",
		center,
		radius,
		Color3.fromRGB(255, 76, 104),
		0.62,
		windup
	)
	createDisk(
		state,
		"ArenaCollapseSafe",
		center,
		CONFIG.ArenaCollapseSafeRadius,
		Color3.fromRGB(95, 255, 181),
		0.35,
		windup
	)
	task.delay(windup, function()
		if activeState ~= state or not bossAlive(state) or state.AttackToken ~= token then
			return
		end
		createBurst(state, center + Vector3.new(0, 1, 0), Color3.fromRGB(255, 76, 104), 90)
		for _, player in ipairs(statePlayers()) do
			local _, humanoid, root = eligiblePlayer(player)
			if humanoid and root then
				local horizontal = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
				if horizontal > CONFIG.ArenaCollapseSafeRadius and horizontal <= radius + 4 then
					damagePlayer(player, humanoid, baseDamage(state) * 1.05, "BossArenaCollapse")
				end
			end
		end
		finishDirectorAttack(state, token)
	end)
	return true
end

local SIGNATURE_ROTATIONS = {
	[2] = { "SkyfallVolley", "CrossSweep" },
	[3] = { "ArenaCollapse", "SkyfallVolley", "CrossSweep" },
}

local function runSignatureAttack(state)
	local phase = math.clamp(math.floor(tonumber(state.Boss:GetAttribute("BossPhase")) or state.Phase or 1), 1, 3)
	local rotation = SIGNATURE_ROTATIONS[phase]
	if not rotation then
		return false
	end
	signatureIndex = (signatureIndex % #rotation) + 1
	local attack = rotation[signatureIndex]
	if attack == "SkyfallVolley" then
		return attackSkyfall(state)
	elseif attack == "CrossSweep" then
		return attackCrossSweep(state)
	elseif attack == "ArenaCollapse" then
		return attackArenaCollapse(state)
	end
	return false
end

local function setupArenaDetails(state)
	local content = state.ArenaContract.Content
	local old = content:FindFirstChild("BossDirectorContent")
	if old then
		old:Destroy()
	end
	directorContent = Instance.new("Folder")
	directorContent.Name = "BossDirectorContent"
	directorContent.Parent = content

	local bounds = state.ArenaContract.Bounds
	local center = CFrame.new(bounds.Position.X, floorTop(state) + 4, bounds.Position.Z)
	local halfX = bounds.Size.X * 0.5
	local halfZ = bounds.Size.Z * 0.5
	for index, offset in ipairs({
		Vector3.new(-halfX * 0.52, 0, -halfZ * 0.52),
		Vector3.new(halfX * 0.52, 0, -halfZ * 0.52),
		Vector3.new(-halfX * 0.52, 0, halfZ * 0.52),
		Vector3.new(halfX * 0.52, 0, halfZ * 0.52),
	}) do
		local pillar = Instance.new("Part")
		pillar.Name = string.format("ArenaCover_%02d", index)
		pillar.Size = Vector3.new(5, 8, 5)
		pillar.CFrame = center * CFrame.new(offset)
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.CanTouch = false
		pillar.CanQuery = true
		pillar.Material = Enum.Material.Slate
		pillar.Color = Color3.fromRGB(72, 82, 105)
		pillar:SetAttribute("BossArenaCover", true)
		pillar.Parent = directorContent
	end
	state.ArenaContract.Arena:SetAttribute("BossArenaDirectorVersion", 1)
	state.ArenaContract.Arena:SetAttribute("BossArenaCoverCount", 4)
end

local function heartbeat()
	local state = activeState
	if not started or not bossAlive(state) then
		return
	end
	if state.Active == true
		and state.CombatEnabled == true
		and state.Attacking ~= true
		and state.Boss:GetAttribute("BossPhaseTransitioning") ~= true
		and os.clock() >= nextSignatureAt
	then
		local phase = math.clamp(math.floor(tonumber(state.Boss:GetAttribute("BossPhase")) or 1), 1, 3)
		if runSignatureAttack(state) then
			nextSignatureAt = os.clock() + (CONFIG.SignatureIntervals[phase] or 9)
		else
			nextSignatureAt = os.clock() + 1
		end
	end
end

function BossEncounterDirector.Start(options)
	if started then
		return
	end
	options = type(options) == "table" and options or {}
	started = true
	sessionId = tostring(options.SessionId or "")
	participantSet = {}
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
		end
	end
	workspace:SetAttribute("DungeonBossDirectorVersion", 1)
	workspace:SetAttribute("DungeonBossDirectorReady", true)
	workspace:SetAttribute("DungeonBossDirectorPolicy", POLICY)
	workspace:SetAttribute("DungeonBossRewardPhysical", true)
	setDirectorState("WaitingForBoss", nil)
end

function BossEncounterDirector.Attach(state, options)
	if not started or type(state) ~= "table" or not state.Boss or not state.Humanoid then
		return false, "InvalidBossState"
	end
	clearConnections()
	activeState = state
	activeOptions = type(options) == "table" and table.clone(options) or {}
	rewardIssued = false
	phaseToken += 1
	signatureToken += 1
	signatureIndex = 0
	nextSignatureAt = math.huge
	setupArenaDetails(state)
	local lastPhase = math.clamp(math.floor(tonumber(state.Boss:GetAttribute("BossPhase")) or 1), 1, 3)
	table.insert(connections, state.Boss:GetAttributeChangedSignal("BossPhase"):Connect(function()
		local phase = math.clamp(math.floor(tonumber(state.Boss:GetAttribute("BossPhase")) or 1), 1, 3)
		if phase > lastPhase then
			lastPhase = phase
			phaseTransition(state, phase)
		end
	end))
	table.insert(connections, state.Boss:GetAttributeChangedSignal("BossActive"):Connect(function()
		if state.Boss:GetAttribute("BossActive") == true then
			nextSignatureAt = os.clock() + 5.5
			setDirectorState("CombatActive", nil)
		end
	end))
	heartbeatConnection = RunService.Heartbeat:Connect(heartbeat)
	workspace:SetAttribute("DungeonBossDirectorAttached", true)
	workspace:SetAttribute("DungeonBossDirectorBossId", tostring(state.BossId or "GiantBoss"))
	workspace:SetAttribute("DungeonBossDirectorArenaReady", true)
	setDirectorState("BossReady", nil)
	return true
end

function BossEncounterDirector.HandleDefeated(boss, snapshot)
	local state = activeState
	if rewardIssued or not state then
		return 0
	end
	rewardIssued = true
	local position = state.Root and state.Root.Position or arenaCenter(state)
	local eligibleUserIds = type(snapshot) == "table" and snapshot.EligibleUserIds
		or state.EligibleUserIds
	eligibleUserIds = type(eligibleUserIds) == "table" and eligibleUserIds or {}
	local rewardCoins = math.clamp(
		math.floor(tonumber(activeOptions.BossRewardCoins) or CONFIG.RewardMinimumCoins),
		CONFIG.RewardMinimumCoins,
		CONFIG.RewardMaximumCoins
	)
	local dropCount = 0
	for index, userId in ipairs(eligibleUserIds) do
		local angle = ((index - 1) / math.max(1, #eligibleUserIds)) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 4
		local model = MobCollectibleService.Drop({
			Position = position + offset,
			Amount = rewardCoins,
			RoundIndex = 3,
			TargetUserId = userId,
			ExclusiveToTarget = true,
			AllowDownedTarget = true,
			SourceType = "BossRewardCollectible",
			SourceMonsterId = boss and boss:GetAttribute("BossId") or "GiantBoss",
			IsElite = true,
		})
		if model then
			dropCount += 1
		end
	end
	MobCollectibleService.AttractAll("BossDefeatedReward")
	createBurst(state, position + Vector3.new(0, 5, 0), Color3.fromRGB(255, 210, 77), 130)
	workspace:SetAttribute("DungeonBossRewardDropCount", dropCount)
	workspace:SetAttribute("DungeonBossRewardCoinsPerPlayer", rewardCoins)
	workspace:SetAttribute("DungeonBossRewardIssuedAt", now())
	workspace:SetAttribute("DungeonBossRewardCollectingUntil", now() + CONFIG.RewardTravelSeconds)
	setDirectorState("BossRewardCollecting", now() + CONFIG.RewardTravelSeconds)
	return CONFIG.RewardTravelSeconds
end

function BossEncounterDirector.GetSnapshot()
	return {
		Started = started,
		SessionId = sessionId,
		Policy = POLICY,
		Attached = activeState ~= nil,
		BossAlive = bossAlive(activeState) == true,
		RewardIssued = rewardIssued,
		State = workspace:GetAttribute("DungeonBossDirectorState"),
		StateEndsAt = workspace:GetAttribute("DungeonBossDirectorStateEndsAt"),
	}
end

function BossEncounterDirector.Stop()
	clearConnections()
	phaseToken += 1
	signatureToken += 1
	if activeState and activeState.Root and activeState.Root.Parent then
		activeState.Root.Anchored = false
	end
	if directorContent and directorContent.Parent then
		directorContent:Destroy()
	end
	directorContent = nil
	activeState = nil
	activeOptions = {}
	participantSet = {}
	sessionId = ""
	started = false
	workspace:SetAttribute("DungeonBossDirectorReady", false)
	workspace:SetAttribute("DungeonBossDirectorAttached", false)
	workspace:SetAttribute("DungeonBossPhaseTransitioning", false)
	setDirectorState("Stopped", nil)
end

return BossEncounterDirector
