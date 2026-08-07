local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Configs.BossConfig)
local PlayerDamageService = require(script.Parent.Parent.MVPSystems.PlayerDamageService)
local MonsterSpawner = require(script.Parent.Parent.BlockParkour.MonsterSpawner)
local ContentResolver = require(script.Parent.ContentResolver)
local PartyScalingService = require(script.Parent.PartyScalingService)
local RuntimeFolders = require(script.Parent.RuntimeFolders)

local BossService = {}
local activeState

local DEFAULT_BOSS_ID = "GiantBoss"
local THINK_INTERVAL = 0.12
local SNAPSHOT_INTERVAL = 0.2
local RESCUE_CHECK_INTERVAL = 0.25
local PLAYER_SPAWN_COUNT = 4

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function positiveNumberAttribute(instance, name, fallback, minimum)
	local value = instance and instance:GetAttribute(name)
	if typeof(value) ~= "number" then
		return fallback
	end
	return math.max(minimum or 0, value)
end

local function numberFromTable(source, name, fallback)
	local value = type(source) == "table" and source[name] or nil
	return typeof(value) == "number" and value or fallback
end

local function resolveBossDefinition(template, bossId)
	local configured = BossConfig[bossId] or BossConfig[DEFAULT_BOSS_ID]
	assert(configured, "BossConfig precisa possuir ao menos GiantBoss")
	return {
		DisplayName = template and tostring(template:GetAttribute("DisplayName") or configured.DisplayName)
			or configured.DisplayName,
		BaseHealth = positiveNumberAttribute(template, "BaseHealth", configured.BaseHealth, 1),
		BaseDamage = positiveNumberAttribute(template, "BaseDamage", configured.BaseDamage, 0),
		WalkSpeed = positiveNumberAttribute(template, "WalkSpeed", configured.WalkSpeed, 0),
		AttackRange = positiveNumberAttribute(template, "AttackRange", configured.AttackRange, 1),
		AttackCooldown = positiveNumberAttribute(template, "AttackCooldown", configured.AttackCooldown, 0.1),
		DetectionRange = positiveNumberAttribute(template, "DetectionRange", configured.DetectionRange, 1),
		ActivationDelay = positiveNumberAttribute(template, "ActivationDelay", configured.ActivationDelay or 2.5, 0),
		ArenaRescueDepth = positiveNumberAttribute(template, "ArenaRescueDepth", configured.ArenaRescueDepth or 24, 8),
		ArenaRescueProtection = positiveNumberAttribute(
			template,
			"ArenaRescueProtection",
			configured.ArenaRescueProtection or 3,
			0
		),
		PhaseCount = math.clamp(
			math.floor(tonumber(configured.PhaseCount) or 2),
			2,
			3
		),
		PhaseThresholds = configured.PhaseThresholds or { 0.50 },
		PhaseAttackCooldowns = configured.PhaseAttackCooldowns or {
			configured.AttackCooldown,
			configured.AttackCooldown * 0.78,
		},
		MusicSoundId = tostring(configured.MusicSoundId or ""),
		MusicVolume = math.clamp(tonumber(configured.MusicVolume) or 0.55, 0, 1),
		BasicSlam = configured.BasicSlam or {},
		LeapSlam = configured.LeapSlam or {},
		GroundPulse = configured.GroundPulse or {},
		Shockwave = configured.Shockwave or {},
		Summon = configured.Summon or {},
	}
end

local function makePart(name, size, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = name ~= "HumanoidRootPart"
	part.Anchored = false
	part.Parent = parent
	return part
end

local function weld(root, part, offset)
	part.CFrame = root.CFrame * offset
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = root
	joint.Part1 = part
	joint.Parent = part
end

local function createFallbackBoss()
	local model = Instance.new("Model")
	model.Name = "GiantBoss"
	local root = makePart(
		"HumanoidRootPart",
		Vector3.new(8, 9, 8),
		Color3.fromRGB(73, 111, 78),
		model
	)
	root.Transparency = 1
	root.CanCollide = true
	local body = makePart(
		"SlimeBody",
		Vector3.new(15, 14, 15),
		Color3.fromRGB(84, 177, 92),
		model
	)
	body.Shape = Enum.PartType.Ball
	body.Material = Enum.Material.SmoothPlastic
	weld(root, body, CFrame.new(0, 2, 0))
	local shell = makePart(
		"SlimeShell",
		Vector3.new(15.6, 14.6, 15.6),
		Color3.fromRGB(132, 245, 137),
		model
	)
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.Glass
	shell.Transparency = 0.35
	shell.CanCollide = false
	weld(root, shell, CFrame.new(0, 2, 0))
	for index, side in ipairs({ -1, 1 }) do
		local eye = makePart(
			"Eye" .. index,
			Vector3.new(2.1, 2.7, 1.2),
			Color3.fromRGB(19, 28, 24),
			model
		)
		eye.CanCollide = false
		weld(root, eye, CFrame.new(side * 3.1, 4.2, -6.5))
	end
	local crown = makePart(
		"Crown",
		Vector3.new(7, 2.4, 7),
		Color3.fromRGB(245, 193, 54),
		model
	)
	crown.Material = Enum.Material.Metal
	crown.CanCollide = false
	weld(root, crown, CFrame.new(0, 10.2, 0))
	local humanoid = Instance.new("Humanoid")
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function prepareBoss(template, bossId, definition, partySize)
	local boss = template and template:Clone() or createFallbackBoss()
	local humanoid = boss:FindFirstChildWhichIsA("Humanoid", true)
	local root = boss:FindFirstChild("HumanoidRootPart", true) or boss.PrimaryPart
	if not humanoid or not root or not root:IsA("BasePart") then
		boss:Destroy()
		boss = createFallbackBoss()
		humanoid = boss:FindFirstChildWhichIsA("Humanoid", true)
		root = boss.PrimaryPart
	end
	boss.PrimaryPart = root
	local health, damage, multipliers = PartyScalingService.ScaleValues(
		definition.BaseHealth,
		definition.BaseDamage,
		partySize,
		true
	)
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = definition.WalkSpeed
	humanoid.DisplayName = definition.DisplayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	boss.Name = "Boss_" .. bossId
	boss:SetAttribute("BossId", bossId)
	boss:SetAttribute("DisplayName", definition.DisplayName)
	boss:SetAttribute("AttackDamage", damage)
	boss:SetAttribute("AttackRange", definition.AttackRange)
	boss:SetAttribute("AttackCooldown", definition.AttackCooldown)
	boss:SetAttribute("AIController", "Boss")
	boss:SetAttribute("BossActive", false)
	boss:SetAttribute("BossPhase", 1)
	boss:SetAttribute("BossAttack", "Idle")
	boss:SetAttribute("Invulnerable", true)
	boss:SetAttribute("RuntimeMonster", true)
	boss:SetAttribute("IsBoss", true)
	boss:SetAttribute("NoKnockback", true)
	boss:SetAttribute("CanBeKnockedBack", false)
	boss:SetAttribute("StunResistance", 1)
	PartyScalingService.MarkApplied(boss, partySize, multipliers)
	for _, descendant in ipairs(boss:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = true
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanQuery = true
			pcall(function()
				descendant.CollisionGroup = "MVPMonsters"
			end)
		end
	end
	CollectionService:AddTag(boss, "DungeonBoss")
	CollectionService:AddTag(boss, "CombatTarget")
	return boss, humanoid, root
end

local function hiddenMarker(parent, name, cframe, size)
	local marker = parent:FindFirstChild(name)
	if marker and not marker:IsA("BasePart") then
		marker:Destroy()
		marker = nil
	end
	if not marker then
		marker = Instance.new("Part")
		marker.Name = name
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.Transparency = 1
		marker.Parent = parent
	end
	marker.Size = size or Vector3.new(4, 1, 4)
	marker.CFrame = cframe
	return marker
end

local function markerFromContext(context, name)
	if type(context) ~= "table" then
		return nil
	end
	local direct = context[name]
	if direct and direct:IsA("BasePart") then
		return direct
	end
	local markers = context.GameplayMarkers
	local found = markers and markers:FindFirstChild(name, true)
	return found and found:IsA("BasePart") and found or nil
end

local function resolveArenaModelAndFloor(context)
	context = type(context) == "table" and context or {}
	local arena = context.Model or context.Arena or context.Island
	local floor = context.Floor
	if arena and arena:IsA("Model") then
		floor = floor and floor:IsA("BasePart") and floor
			or arena:FindFirstChild("ArenaFloor", true)
			or arena:FindFirstChild("IslandFloor", true)
			or arena.PrimaryPart
			or arena:FindFirstChildWhichIsA("BasePart", true)
	end
	if arena and arena:IsA("Model") and floor and floor:IsA("BasePart") then
		return arena, floor, false
	end

	local generated = RuntimeFolders.Get("GeneratedIslands")
	arena = Instance.new("Model")
	arena.Name = "BossSanctuaryFallback"
	local anchorFloor = context.AnchorFloor
	local anchorPosition = anchorFloor and anchorFloor.Position or Vector3.new(0, 24, 0)
	floor = Instance.new("Part")
	floor.Name = "ArenaFloor"
	floor.Size = Vector3.new(84, 5, 84)
	floor.Anchored = true
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(82, 67, 54)
	floor.CFrame = CFrame.new(anchorPosition + Vector3.new(0, 4, -90))
	floor.Parent = arena
	arena.PrimaryPart = floor
	arena.Parent = generated
	return arena, floor, true
end

local function ensureArenaContract(context)
	local arena, floor, fallback = resolveArenaModelAndFloor(context)
	local content = arena:FindFirstChild("BossArenaContent")
	if content then
		content:Destroy()
	end
	content = Instance.new("Folder")
	content.Name = "BossArenaContent"
	content.Parent = arena

	local center = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	local width = math.max(42, floor.Size.X * 0.84)
	local depth = math.max(42, floor.Size.Z * 0.84)
	local bounds = hiddenMarker(
		content,
		"ArenaBounds",
		center * CFrame.new(0, 11, 0),
		Vector3.new(width, 24, depth)
	)
	bounds:SetAttribute("ArenaBounds", true)

	local safeSpawn = markerFromContext(context, "SafeSpawn")
	if not safeSpawn then
		safeSpawn = hiddenMarker(
			content,
			"SafeSpawn",
			center * CFrame.new(0, 3, depth * 0.28),
			Vector3.new(5, 1, 5)
		)
	end
	local entry = markerFromContext(context, "Entry")
	local entryCFrame = entry and entry.CFrame
		or center * CFrame.new(0, 3, depth * 0.42)
	local bossSpawn = hiddenMarker(
		content,
		"BossSpawn",
		center * CFrame.new(0, 8, -depth * 0.18),
		Vector3.new(7, 1, 7)
	)
	local trigger = hiddenMarker(
		content,
		"BossTrigger",
		entryCFrame * CFrame.new(0, 5, -5),
		Vector3.new(math.clamp(width * 0.55, 20, 44), 12, 10)
	)
	trigger.CanTouch = true
	trigger:SetAttribute("BossTrigger", true)

	local gate = Instance.new("Part")
	gate.Name = "ArenaGate"
	gate.Size = Vector3.new(math.clamp(width * 0.28, 18, 28), 14, 2)
	gate.Anchored = true
	gate.CanCollide = false
	gate.CanTouch = false
	gate.CanQuery = true
	gate.Material = Enum.Material.ForceField
	gate.Color = Color3.fromRGB(108, 220, 139)
	gate.Transparency = 1
	gate.CFrame = entryCFrame * CFrame.new(0, 6.5, 0)
	gate.Parent = content

	local playerSpawns = Instance.new("Folder")
	playerSpawns.Name = "PlayerSpawns"
	playerSpawns.Parent = content
	local side = math.clamp(width * 0.18, 8, 14)
	local forward = depth * 0.22
	local spawnOffsets = {
		Vector3.new(-side, 3, forward),
		Vector3.new(side, 3, forward),
		Vector3.new(-side * 0.5, 3, forward - 8),
		Vector3.new(side * 0.5, 3, forward - 8),
	}
	local spawns = {}
	for index = 1, PLAYER_SPAWN_COUNT do
		local marker = hiddenMarker(
			playerSpawns,
			string.format("PlayerSpawn_%02d", index),
			center * CFrame.new(spawnOffsets[index]),
			Vector3.new(4, 1, 4)
		)
		marker:SetAttribute("PlayerSpawnIndex", index)
		table.insert(spawns, marker)
	end

	local minionSpawns = Instance.new("Folder")
	minionSpawns.Name = "BossMinionSpawns"
	minionSpawns.Parent = content
	for index = 1, 6 do
		local angle = ((index - 1) / 6) * math.pi * 2
		local marker = hiddenMarker(
			minionSpawns,
			string.format("MinionSpawn_%02d", index),
			center * CFrame.new(
				math.cos(angle) * width * 0.3,
				3,
				math.sin(angle) * depth * 0.3
			),
			Vector3.new(3, 1, 3)
		)
		marker:SetAttribute("BossMinionSpawn", true)
	end

	arena:SetAttribute("BossArena", true)
	arena:SetAttribute("BossArenaContractVersion", 1)
	return {
		Arena = arena,
		Floor = floor,
		Content = content,
		Bounds = bounds,
		SafeSpawn = safeSpawn,
		BossSpawn = bossSpawn,
		Trigger = trigger,
		Gate = gate,
		PlayerSpawns = spawns,
		MinionSpawns = minionSpawns,
		Fallback = fallback,
	}
end

local function pointInsideBounds(bounds, position, margin)
	local localPoint = bounds.CFrame:PointToObjectSpace(position)
	local half = bounds.Size * 0.5
	margin = tonumber(margin) or 0
	return math.abs(localPoint.X) <= half.X + margin
		and math.abs(localPoint.Z) <= half.Z + margin
		and localPoint.Y >= -half.Y - margin
		and localPoint.Y <= half.Y + margin
end

local function clampToBounds(bounds, position, inset)
	local localPoint = bounds.CFrame:PointToObjectSpace(position)
	local half = bounds.Size * 0.5
	inset = math.max(1, tonumber(inset) or 5)
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X + inset, half.X - inset),
		0,
		math.clamp(localPoint.Z, -half.Z + inset, half.Z - inset)
	)
	local worldPoint = bounds.CFrame:PointToWorldSpace(clamped)
	return Vector3.new(worldPoint.X, position.Y, worldPoint.Z)
end

local function activePlayer(player)
	if not player or player.Parent ~= Players then
		return nil
	end
	if player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonLifeState") == "Disconnected"
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return character, humanoid, root
end

local function statePlayers(state)
	local result = {}
	for _, userId in ipairs(state.ParticipantUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(result, player)
		end
	end
	return result
end

local function setGateSealed(state, sealed)
	state.ArenaSealed = sealed == true
	local gate = state.ArenaContract.Gate
	gate.CanCollide = state.ArenaSealed
	gate.Transparency = state.ArenaSealed and 0.25 or 1
	gate:SetAttribute("ArenaSealed", state.ArenaSealed)
	state.ArenaContract.Arena:SetAttribute("ArenaSealed", state.ArenaSealed)
end

local function createTelegraph(state, position, radius, duration, label)
	local floor = state.ArenaContract.Floor
	local marker = Instance.new("Part")
	marker.Name = "BossTelegraph_" .. tostring(label or "Attack")
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.18, radius * 2, radius * 2)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 104, 74)
	marker.Transparency = 0.48
	marker.CFrame = CFrame.new(
		position.X,
		floor.Position.Y + floor.Size.Y / 2 + 0.14,
		position.Z
	) * CFrame.Angles(0, 0, math.rad(90))
	marker:SetAttribute("BossTelegraph", true)
	marker:SetAttribute("AttackName", tostring(label or "Attack"))
	marker:SetAttribute("ExpiresAt", serverTime() + duration)
	marker.Parent = state.ArenaContract.Content
	Debris:AddItem(marker, duration + 0.2)
	return marker
end

local function createShockwaveVisual(state, position, radius, duration)
	local ring = Instance.new("Part")
	ring.Name = "BossShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 218, 95)
	ring.Transparency = 0.2
	ring.CFrame = CFrame.new(
		position.X,
		state.ArenaContract.Floor.Position.Y + state.ArenaContract.Floor.Size.Y / 2 + 0.25,
		position.Z
	) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = state.ArenaContract.Content
	task.spawn(function()
		local startedAt = os.clock()
		while ring.Parent and os.clock() - startedAt < duration do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			local diameter = math.max(2, radius * 2 * alpha)
			ring.Size = Vector3.new(0.3, diameter, diameter)
			ring.Transparency = 0.2 + alpha * 0.65
			RunService.Heartbeat:Wait()
		end
		if ring.Parent then
			ring:Destroy()
		end
	end)
	return ring
end

local function damagePlayersInRadius(state, position, radius, damage, source, innerSafeRadius)
	local hit = 0
	for _, player in ipairs(statePlayers(state)) do
		local _, humanoid, root = activePlayer(player)
		if humanoid and root and player:GetAttribute("IsDowned") ~= true then
			local horizontal = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude
			if horizontal <= radius and horizontal >= (innerSafeRadius or 0) then
				PlayerDamageService.Apply(player, humanoid, damage, source)
				hit += 1
			end
		end
	end
	return hit
end

local function currentPhase(state)
	local ratio = state.Humanoid.MaxHealth > 0
		and state.Humanoid.Health / state.Humanoid.MaxHealth
		or 0
	local thresholds = state.Definition.PhaseThresholds
	if state.Definition.PhaseCount <= 2 then
		return ratio <= (thresholds[1] or 0.50) and 2 or 1
	end
	if ratio <= (thresholds[2] or 0.33) then
		return 3
	elseif ratio <= (thresholds[1] or 0.66) then
		return 2
	end
	return 1
end

local function snapshot(state)
	if not state then
		return {
			State = "Unavailable",
		}
	end
	local health = state.Humanoid and math.max(0, state.Humanoid.Health) or 0
	local maximum = state.Humanoid and math.max(1, state.Humanoid.MaxHealth) or 1
	return {
		State = state.Completed and (state.Defeated and "Defeated" or "Stopped")
			or state.Active and "Active"
			or state.Activating and "Activating"
			or "Ready",
		BossId = state.BossId,
		DisplayName = state.Definition.DisplayName,
		Health = health,
		MaxHealth = maximum,
		HealthRatio = health / maximum,
		Phase = state.Phase,
		PhaseCount = state.Definition.PhaseCount,
		Attack = state.AttackName,
		AttackEndsAt = state.AttackEndsAt,
		ActivationEndsAt = state.Boss:GetAttribute("BossActivationEndsAt"),
		ArenaSealed = state.ArenaSealed == true,
		CombatEnabled = state.CombatEnabled == true,
		EligibleUserIds = table.clone(state.EligibleUserIds),
	}
end

local function publish(state, action, targetPlayer, extra)
	if not state then
		return
	end
	local payload = snapshot(state)
	payload.Action = action or "BossSnapshot"
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	workspace:SetAttribute("DungeonBossState", payload.State)
	workspace:SetAttribute("DungeonBossHealth", payload.Health)
	workspace:SetAttribute("DungeonBossMaxHealth", payload.MaxHealth)
	workspace:SetAttribute("DungeonBossPhase", payload.Phase)
	workspace:SetAttribute("DungeonBossPhaseCount", payload.PhaseCount)
	workspace:SetAttribute("DungeonBossDisplayName", payload.DisplayName)
	workspace:SetAttribute("DungeonBossAttack", payload.Attack)
	workspace:SetAttribute("DungeonBossAttackEndsAt", payload.AttackEndsAt)
	workspace:SetAttribute("DungeonBossActivationEndsAt", payload.ActivationEndsAt)
	local remote = state.RemoteEvent
	if remote then
		if targetPlayer and targetPlayer.Parent == Players then
			remote:FireClient(targetPlayer, payload)
		else
			remote:FireAllClients(payload)
		end
	end
end

local function safeCallback(state, name, ...)
	local callback = state[name]
	if type(callback) ~= "function" then
		return nil
	end
	local success, result = pcall(callback, ...)
	if not success then
		warn(string.format("[BossService] %s falhou: %s", name, tostring(result)))
		return nil
	end
	return result
end

local function chooseTarget(state)
	local bestPlayer
	local bestRoot
	local bestDistance = state.Definition.DetectionRange
	for _, player in ipairs(statePlayers(state)) do
		local _, humanoid, root = activePlayer(player)
		if humanoid and root and player:GetAttribute("IsDowned") ~= true then
			local distance = (root.Position - state.Root.Position).Magnitude
			if distance < bestDistance then
				bestPlayer = player
				bestRoot = root
				bestDistance = distance
			end
		end
	end
	return bestPlayer, bestRoot, bestDistance
end

local function teleportPlayerToSpawn(state, player, spawnIndex, reason)
	local character, humanoid, root = activePlayer(player)
	if not character or not humanoid or not root or player:GetAttribute("IsDowned") == true then
		return false
	end
	local spawns = state.ArenaContract.PlayerSpawns
	local spawn = spawns[((spawnIndex - 1) % #spawns) + 1] or state.ArenaContract.SafeSpawn
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = spawn.CFrame * CFrame.new(0, 3, 0)
	local forceField = Instance.new("ForceField")
	forceField.Name = "BossArenaRescueProtection"
	forceField.Visible = false
	forceField.Parent = character
	task.delay(state.Definition.ArenaRescueProtection, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
	player:SetAttribute("BossArenaRescueReason", tostring(reason or "ArenaRescue"))
	player:SetAttribute("BossArenaRescueAt", serverTime())
	player:SetAttribute(
		"BossArenaRescueSerial",
		(tonumber(player:GetAttribute("BossArenaRescueSerial")) or 0) + 1
	)
	return true
end

local function teleportParticipants(state, reason)
	local index = 0
	for _, player in ipairs(statePlayers(state)) do
		if player:GetAttribute("DungeonEliminated") ~= true then
			index += 1
			teleportPlayerToSpawn(state, player, index, reason)
		end
	end
end

local function eligibleParticipants(state)
	local result = {}
	local set = {}
	for _, player in ipairs(statePlayers(state)) do
		if player:GetAttribute("DungeonEliminated") ~= true then
			local _, humanoid = activePlayer(player)
			if humanoid then
				set[player.UserId] = true
				table.insert(result, player.UserId)
			end
		end
	end
	table.sort(result)
	state.EligibleUserIds = result
	state.EligibleUserSet = set
end

local function finishAttack(state, token)
	if activeState ~= state or state.Completed or state.AttackToken ~= token then
		return
	end
	state.Attacking = false
	state.AttackName = "Idle"
	state.AttackEndsAt = nil
	state.Boss:SetAttribute("BossAttack", "Idle")
	state.Boss:SetAttribute("BossAttackEndsAt", nil)
	state.NextAttackAt = os.clock()
		+ (state.Definition.PhaseAttackCooldowns[state.Phase] or state.Definition.AttackCooldown)
	publish(state, "AttackEnded")
end

local function beginAttack(state, attackName, duration)
	if state.Attacking or state.Completed or not state.Active or not state.CombatEnabled then
		return nil
	end
	state.Attacking = true
	state.AttackToken += 1
	state.AttackName = attackName
	state.AttackEndsAt = serverTime() + duration
	state.Boss:SetAttribute("BossAttack", attackName)
	state.Boss:SetAttribute("BossAttackEndsAt", state.AttackEndsAt)
	state.Humanoid:MoveTo(state.Root.Position)
	state.Humanoid:Move(Vector3.zero)
	publish(state, "AttackStarted")
	return state.AttackToken
end

local function attackBasicSlam(state)
	local config = state.Definition.BasicSlam
	local phaseScale = state.Phase >= 2 and 0.88 or 1
	local windup = numberFromTable(config, "Windup", 0.42) * phaseScale
	local radius = numberFromTable(config, "Radius", 7.5)
	local token = beginAttack(state, "BasicSlam", windup + 0.22)
	if not token then
		return
	end
	local position = state.Root.Position
	createTelegraph(state, position, radius, windup, "BasicSlam")
	task.delay(windup, function()
		if activeState ~= state or state.Completed or state.AttackToken ~= token then
			return
		end
		if state.CombatEnabled then
			damagePlayersInRadius(
				state,
				position,
				radius,
				state.Boss:GetAttribute("AttackDamage")
					* numberFromTable(config, "DamageMultiplier", 0.62),
				"BossBasicSlam"
			)
			createShockwaveVisual(state, position, radius, 0.22)
		end
		finishAttack(state, token)
	end)
end

local function attackGroundPulse(state)
	local config = state.Definition.GroundPulse
	local windup = numberFromTable(config, "Windup", 0.75)
	local radius = numberFromTable(config, "Radius", 14)
	local token = beginAttack(state, "GroundPulse", windup + 0.35)
	if not token then
		return
	end
	local position = state.Root.Position
	createTelegraph(state, position, radius, windup, "GroundPulse")
	task.delay(windup, function()
		if activeState ~= state or state.Completed or state.AttackToken ~= token then
			return
		end
		if not state.CombatEnabled then
			finishAttack(state, token)
			return
		end
		damagePlayersInRadius(
			state,
			position,
			radius,
			state.Boss:GetAttribute("AttackDamage") * numberFromTable(config, "DamageMultiplier", 0.85),
			"BossGroundPulse"
		)
		createShockwaveVisual(state, position, radius, 0.3)
		finishAttack(state, token)
	end)
end

local function attackLeapSlam(state, targetRoot)
	local config = state.Definition.LeapSlam
	local phaseSpeed = state.Phase == 3 and 0.75 or (state.Phase == 2 and 0.88 or 1)
	local windup = numberFromTable(config, "Windup", 0.9) * phaseSpeed
	local radius = numberFromTable(config, "Radius", 12) + (state.Phase - 1)
	local token = beginAttack(state, "LeapSlam", windup + 0.55)
	if not token then
		return
	end
	local impact = clampToBounds(state.ArenaContract.Bounds, targetRoot.Position, 8)
	createTelegraph(state, impact, radius, windup, "LeapSlam")
	state.Root.Anchored = true
	state.Boss:PivotTo(CFrame.new(state.Root.Position + Vector3.new(0, 8, 0), impact))
	task.delay(windup, function()
		if activeState ~= state or state.Completed or state.AttackToken ~= token then
			if state.Root.Parent then
				state.Root.Anchored = false
			end
			return
		end
		state.Boss:PivotTo(CFrame.new(impact + Vector3.new(0, 7, 0)))
		state.Root.Anchored = false
		pcall(function()
			state.Root:SetNetworkOwner(nil)
		end)
		if state.CombatEnabled then
			damagePlayersInRadius(
				state,
				impact,
				radius,
				state.Boss:GetAttribute("AttackDamage") * numberFromTable(config, "DamageMultiplier", 1.15),
				"BossLeapSlam"
			)
		end
		createShockwaveVisual(state, impact, radius, 0.38)
		finishAttack(state, token)
	end)
end

local function attackShockwave(state)
	local config = state.Definition.Shockwave
	local windup = numberFromTable(config, "Windup", 1.05)
	local radius = numberFromTable(config, "Radius", 24)
	local innerSafe = numberFromTable(config, "InnerSafeRadius", 7)
	local token = beginAttack(state, "Shockwave", windup + 0.45)
	if not token then
		return
	end
	local position = state.Root.Position
	createTelegraph(state, position, radius, windup, "Shockwave")
	createTelegraph(state, position, innerSafe, windup, "ShockwaveSafeCenter")
	task.delay(windup, function()
		if activeState ~= state or state.Completed or state.AttackToken ~= token then
			return
		end
		if not state.CombatEnabled then
			finishAttack(state, token)
			return
		end
		createShockwaveVisual(state, position, radius, 0.45)
		damagePlayersInRadius(
			state,
			position,
			radius,
			state.Boss:GetAttribute("AttackDamage") * numberFromTable(config, "DamageMultiplier", 1),
			"BossShockwave",
			innerSafe
		)
		finishAttack(state, token)
	end)
end

local function summonMinions(state, requestedCount, reason)
	local config = state.Definition.Summon
	local maximumAlive = math.max(1, math.floor(numberFromTable(config, "MaximumAlive", 5)))
	local alive = MonsterSpawner.GetObjectiveActiveCount(state.MinionEncounterId)
	local count = math.min(math.max(0, requestedCount), math.max(0, maximumAlive - alive))
	if count <= 0 then
		return 0
	end
	local markers = state.ArenaContract.MinionSpawns:GetChildren()
	table.sort(markers, function(left, right)
		return left.Name < right.Name
	end)
	local spawned = 0
	for index = 1, count do
		local marker = markers[((state.MinionSpawnSerial + index - 1) % #markers) + 1]
		state.MinionSpawnSerial += 1
		local spawnSerial = state.MinionSpawnSerial
		createTelegraph(state, marker.Position, 4, 0.55, "Summon")
		task.delay(0.55 + (index - 1) * 0.08, function()
			if activeState ~= state or state.Completed or not state.CombatEnabled then
				return
			end
			local monster = MonsterSpawner.SpawnObjectiveMonster(
				state.ArenaContract.Arena,
				marker,
				{
					EncounterId = state.MinionEncounterId,
					ObjectiveId = "BossMinions",
					GlobalIslandIndex = 13,
					Role = index % 3 == 0 and "Ranged" or "Common",
					SlimeVariant = index % 3 == 0 and "Blue" or "Green",
					ForceHostile = true,
					HealthMultiplier = numberFromTable(config, "HealthMultiplier", 0.75),
					DamageMultiplier = numberFromTable(config, "DamageMultiplier", 0.8),
					SpawnSequence = spawnSerial,
					Seed = state.Seed + spawnSerial * 104729,
				}
			)
			if monster then
				monster:SetAttribute("CoinValue", 0)
				monster:SetAttribute("ScoreValue", 0)
				monster:SetAttribute("BossSummoned", true)
				monster:SetAttribute("BossSummonReason", tostring(reason or "Attack"))
				spawned += 1
			end
		end)
	end
	return spawned
end

local function attackSummon(state)
	local config = state.Definition.Summon
	local windup = numberFromTable(config, "Windup", 0.8)
	local token = beginAttack(state, "SummonSlimes", windup + 0.65)
	if not token then
		return
	end
	local count = math.max(1, math.floor(numberFromTable(config, "BaseCount", 2)))
		+ (state.Phase >= 3 and 1 or 0)
	task.delay(windup, function()
		if activeState ~= state or state.Completed or state.AttackToken ~= token then
			return
		end
		if not state.CombatEnabled then
			finishAttack(state, token)
			return
		end
		summonMinions(state, count, "BossAttack")
		finishAttack(state, token)
	end)
end

local ATTACK_ROTATIONS = {
	[1] = { "BasicSlam", "LeapSlam", "BasicSlam", "GroundPulse" },
	[2] = { "BasicSlam", "LeapSlam", "SummonSlimes", "Shockwave", "GroundPulse" },
}

local function selectAndRunAttack(state, targetRoot)
	local rotation = ATTACK_ROTATIONS[state.Phase] or ATTACK_ROTATIONS[1]
	state.AttackRotationIndex = (state.AttackRotationIndex % #rotation) + 1
	local attack = rotation[state.AttackRotationIndex]
	if attack == "BasicSlam" then
		attackBasicSlam(state)
	elseif attack == "LeapSlam" then
		attackLeapSlam(state, targetRoot)
	elseif attack == "GroundPulse" then
		attackGroundPulse(state)
	elseif attack == "Shockwave" then
		attackShockwave(state)
	elseif attack == "SummonSlimes" then
		attackSummon(state)
	end
end


local function prepareBossMusic(state)
	local existing = state.Boss:FindFirstChild("BossMusic", true)
	if existing and existing:IsA("Sound") then
		existing.Looped = true
		existing.Volume = math.clamp(existing.Volume, 0, 1)
		state.Music = existing
		workspace:SetAttribute("DungeonBossMusicConfigured", true)
		workspace:SetAttribute("DungeonBossMusicSource", "BossTemplate")
		return true
	end
	local soundId = tostring(state.Definition.MusicSoundId or "")
	if soundId == "" then
		workspace:SetAttribute("DungeonBossMusicConfigured", false)
		workspace:SetAttribute("DungeonBossMusicSource", "MissingAsset")
		return false
	end
	local sound = Instance.new("Sound")
	sound.Name = "BossMusic"
	sound.SoundId = soundId
	sound.Volume = state.Definition.MusicVolume
	sound.Looped = true
	sound.RollOffMaxDistance = 220
	sound.Parent = state.ArenaContract.Content
	state.Music = sound
	workspace:SetAttribute("DungeonBossMusicConfigured", true)
	workspace:SetAttribute("DungeonBossMusicSource", "BossConfig")
	return true
end

local function playBossMusic(state)
	local music = state.Music
	if music and music.Parent and not music.IsPlaying then
		music:Play()
		workspace:SetAttribute("DungeonBossMusicPlaying", true)
	end
end

local function stopBossMusic(state)
	local music = state and state.Music
	if music and music.Parent then
		music:Stop()
	end
	workspace:SetAttribute("DungeonBossMusicPlaying", false)
end
local function changePhase(state, nextPhase)
	if nextPhase == state.Phase then
		return
	end
	local previous = state.Phase
	state.Phase = nextPhase
	state.Boss:SetAttribute("BossPhase", nextPhase)
	state.Boss:SetAttribute("BossPhaseChangedAt", serverTime())
	publish(state, "PhaseChanged", nil, {
		PreviousPhase = previous,
	})
	if state.Active and state.CombatEnabled then
		summonMinions(state, nextPhase, "PhaseTransition")
	end
end

local function activate(state, triggeringPlayer)
	if state.Active or state.Activating or state.Completed then
		return false
	end
	state.Activating = true
	state.TriggeringUserId = triggeringPlayer and triggeringPlayer.UserId or nil
	state.ArenaContract.Trigger.CanTouch = false
	setGateSealed(state, true)
	eligibleParticipants(state)
	teleportParticipants(state, "BossActivation")
	state.Boss:SetAttribute("BossActivationStartedAt", serverTime())
	state.Boss:SetAttribute("BossActivationEndsAt", serverTime() + state.Definition.ActivationDelay)
	playBossMusic(state)
	publish(state, "Activating")
	local function completeActivation()
		if activeState ~= state or state.Completed then
			return
		end
		if workspace:GetAttribute("DungeonPhaseState") == "WipePending" then
			task.delay(0.4, completeActivation)
			return
		end
		state.Activating = false
		state.Active = true
		state.CombatEnabled = true
		state.Boss:SetAttribute("BossActive", true)
		state.Boss:SetAttribute("Invulnerable", false)
		state.Boss:SetAttribute("BossActivatedAt", serverTime())
		MonsterSpawner.SetObjectiveMonstersActive(state.MinionEncounterId, true)
		publish(state, "Activated")
		safeCallback(state, "OnActivated", snapshot(state))
	end
	task.delay(state.Definition.ActivationDelay, completeActivation)
	return true
end

local function startAI(state)
	task.spawn(function()
		while activeState == state and not state.Completed and state.Humanoid.Health > 0 do
			if state.Active and state.CombatEnabled then
				local player, targetRoot, distance = chooseTarget(state)
				if targetRoot then
					state.Boss:SetAttribute("TargetUserId", player.UserId)
					if not state.Attacking then
						if distance > state.Definition.AttackRange * 1.15 then
							local destination = clampToBounds(
								state.ArenaContract.Bounds,
								targetRoot.Position,
								8
							)
							state.Humanoid:MoveTo(destination)
						else
							state.Humanoid:MoveTo(state.Root.Position)
						end
						if os.clock() >= state.NextAttackAt then
							selectAndRunAttack(state, targetRoot)
						end
					end
				else
					state.Boss:SetAttribute("TargetUserId", nil)
					state.Humanoid:MoveTo(state.Root.Position)
				end
			end
			task.wait(THINK_INTERVAL)
		end
	end)
end

local function startArenaMonitor(state)
	task.spawn(function()
		local nextSnapshotAt = 0
		while activeState == state and not state.Completed do
			if state.Active or state.Activating then
				local index = 0
				for _, player in ipairs(statePlayers(state)) do
					local _, humanoid, root = activePlayer(player)
					if humanoid and root and player:GetAttribute("IsDowned") ~= true then
						index += 1
						local belowArena = root.Position.Y
							< state.ArenaContract.Floor.Position.Y - state.Definition.ArenaRescueDepth
						local outside = not pointInsideBounds(state.ArenaContract.Bounds, root.Position, 4)
						local lastRescue = tonumber(player:GetAttribute("BossArenaRescueAt")) or 0
						if (belowArena or outside) and serverTime() - lastRescue >= 1.5 then
							teleportPlayerToSpawn(
								state,
								player,
								index,
								belowArena and "FellBelowArena" or "OutsideArena"
							)
						end
					end
				end
				if not pointInsideBounds(state.ArenaContract.Bounds, state.Root.Position, 6) then
					local position = clampToBounds(state.ArenaContract.Bounds, state.Root.Position, 8)
					state.Boss:PivotTo(CFrame.new(position + Vector3.new(0, 7, 0)))
				end
			end
			if os.clock() >= nextSnapshotAt then
				nextSnapshotAt = os.clock() + SNAPSHOT_INTERVAL
				publish(state, "BossSnapshot")
			end
			task.wait(RESCUE_CHECK_INTERVAL)
		end
	end)
end

local function bindPlayers(state)
	state.PlayerConnections = {}
	for _, player in ipairs(statePlayers(state)) do
		table.insert(state.PlayerConnections, player.CharacterAdded:Connect(function()
			if activeState ~= state or state.Completed or not state.Active then
				return
			end
			task.delay(1, function()
				if activeState == state and not state.Completed then
					teleportPlayerToSpawn(state, player, 1, "LateCharacter")
				end
			end)
		end))
	end
	state.PlayerAddedConnection = Players.PlayerAdded:Connect(function(player)
		if state.ParticipantUserSet[player.UserId] then
			task.delay(1, function()
				if activeState == state and not state.Completed then
					publish(state, "BossSnapshot", player)
					if state.Active then
						teleportPlayerToSpawn(state, player, 1, "ReconnectedParticipant")
					end
				end
			end)
		end
	end)
end

local function cleanupConnections(state)
	for _, connection in ipairs(state.PlayerConnections or {}) do
		connection:Disconnect()
	end
	if state.PlayerAddedConnection then
		state.PlayerAddedConnection:Disconnect()
	end
	if state.HealthConnection then
		state.HealthConnection:Disconnect()
	end
	if state.DeathConnection then
		state.DeathConnection:Disconnect()
	end
	if state.TriggerConnection then
		state.TriggerConnection:Disconnect()
	end
end

function BossService.Create(options)
	assert(type(options) == "table", "BossService.Create requer opcoes")
	if activeState and not activeState.Completed then
		return true, activeState
	end
	local bossId = tostring(options.BossId or DEFAULT_BOSS_ID)
	local template = ContentResolver.FindBoss(options.PhaseId, bossId)
	local definition = resolveBossDefinition(template, bossId)
	local arenaContract = ensureArenaContract(options.ArenaContext or options.EndContext)
	local bossFolder = RuntimeFolders.Get("ActiveBoss")
	bossFolder:ClearAllChildren()
	local boss, humanoid, root = prepareBoss(
		template,
		bossId,
		definition,
		math.clamp(math.floor(tonumber(options.PartySize) or 1), 1, 4)
	)
	boss:PivotTo(arenaContract.BossSpawn.CFrame)
	boss.Parent = bossFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local participantUserIds = {}
	local participantUserSet = {}
	for _, value in ipairs(type(options.ParticipantUserIds) == "table" and options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(value) or 0)
		if userId > 0 and not participantUserSet[userId] then
			participantUserSet[userId] = true
			table.insert(participantUserIds, userId)
		end
	end
	local state = {
		SessionId = tostring(options.SessionId or "Dungeon"),
		Seed = math.max(1, math.floor(tonumber(options.Seed) or 1)),
		PhaseId = options.PhaseId,
		BossId = bossId,
		ArenaContract = arenaContract,
		Boss = boss,
		Humanoid = humanoid,
		Root = root,
		Definition = definition,
		ParticipantUserIds = participantUserIds,
		ParticipantUserSet = participantUserSet,
		EligibleUserIds = {},
		EligibleUserSet = {},
		RemoteEvent = options.RemoteEvent,
		OnActivated = options.OnActivated,
		OnDefeated = options.OnDefeated,
		Active = false,
		Activating = false,
		CombatEnabled = false,
		ArenaSealed = false,
		Completed = false,
		Defeated = false,
		Phase = 1,
		AttackName = "Idle",
		AttackEndsAt = nil,
		Attacking = false,
		AttackToken = 0,
		AttackRotationIndex = 0,
		NextAttackAt = math.huge,
		MinionSpawnSerial = 0,
		MinionEncounterId = string.format("Boss:%s", tostring(options.SessionId or "Dungeon")),
	}
	activeState = state
	prepareBossMusic(state)
	setGateSealed(state, false)
	arenaContract.Arena:SetAttribute("PhaseId", options.PhaseId)
	arenaContract.Arena:SetAttribute("BossId", bossId)
	workspace:SetAttribute("DungeonBossState", "Ready")
	workspace:SetAttribute("DungeonBossArenaReady", true)
	workspace:SetAttribute("DungeonBossArenaContractVersion", 1)

	state.TriggerConnection = arenaContract.Trigger.Touched:Connect(function(hit)
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and state.ParticipantUserSet[player.UserId]
			and player:GetAttribute("DungeonEliminated") ~= true
		then
			activate(state, player)
		end
	end)
	state.HealthConnection = humanoid.HealthChanged:Connect(function()
		if activeState ~= state or state.Completed then
			return
		end
		changePhase(state, currentPhase(state))
		publish(state, "HealthChanged")
	end)
	state.DeathConnection = humanoid.Died:Connect(function()
		if state.Completed then
			return
		end
		state.Completed = true
		state.Defeated = true
		state.Active = false
		state.CombatEnabled = false
		state.Boss:SetAttribute("BossActive", false)
		state.Boss:SetAttribute("BossDefeated", true)
		stopBossMusic(state)
		CollectionService:RemoveTag(state.Boss, "CombatTarget")
		MonsterSpawner.DespawnObjectiveMonsters(state.MinionEncounterId)
		setGateSealed(state, false)
		publish(state, "Defeated")
		cleanupConnections(state)
		safeCallback(state, "OnDefeated", state.Boss, snapshot(state))
	end)
	bindPlayers(state)
	startAI(state)
	startArenaMonitor(state)
	publish(state, "Ready")
	return true, state
end

function BossService.SetCombatEnabled(enabled)
	local state = activeState
	if not state or state.Completed then
		return false
	end
	state.CombatEnabled = enabled == true and state.Active
	state.Boss:SetAttribute("BossCombatEnabled", state.CombatEnabled)
	state.Boss:SetAttribute("Invulnerable", not state.CombatEnabled)
	MonsterSpawner.SetObjectiveMonstersActive(state.MinionEncounterId, state.CombatEnabled)
	if not state.CombatEnabled then
		state.Humanoid:MoveTo(state.Root.Position)
		state.Humanoid:Move(Vector3.zero)
	end
	publish(state, "CombatStateChanged")
	return true
end

function BossService.ActivateForTesting(player)
	local state = activeState
	if not state then
		return false
	end
	return activate(state, player)
end

function BossService.RescuePlayer(player, reason)
	local state = activeState
	if not state or state.Completed then
		return false
	end
	return teleportPlayerToSpawn(state, player, 1, reason)
end

function BossService.GetSnapshot()
	return snapshot(activeState)
end

function BossService.GetEligibleUserIds()
	return activeState and table.clone(activeState.EligibleUserIds) or {}
end

function BossService.IsEligible(playerOrUserId)
	local userId = typeof(playerOrUserId) == "Instance"
		and playerOrUserId:IsA("Player")
		and playerOrUserId.UserId
		or math.floor(tonumber(playerOrUserId) or 0)
	return activeState ~= nil and activeState.EligibleUserSet[userId] == true
end

function BossService.Stop()
	local state = activeState
	if not state then
		return
	end
	local wasDefeated = state.Defeated == true
	stopBossMusic(state)
	state.Completed = true
	state.Active = false
	state.Activating = false
	state.CombatEnabled = false
	state.AttackToken += 1
	if state.Root and state.Root.Parent then
		state.Root.Anchored = false
	end
	if state.Humanoid and state.Root and state.Root.Parent then
		state.Humanoid:MoveTo(state.Root.Position)
		state.Humanoid:Move(Vector3.zero)
	end
	if state.Boss and state.Boss.Parent then
		state.Boss:SetAttribute("BossActive", false)
		state.Boss:SetAttribute("Invulnerable", true)
		CollectionService:RemoveTag(state.Boss, "CombatTarget")
	end
	MonsterSpawner.DespawnObjectiveMonsters(state.MinionEncounterId)
	setGateSealed(state, false)
	cleanupConnections(state)
	if not wasDefeated then
		publish(state, "Stopped")
	end
end

return BossService
