--[[
	Infinity Islands - Mob Group Combat Coordinator V1

	Objetivo do MVP:
	- impedir que todos os mobs que detectaram um jogador ataquem ao mesmo tempo;
	- dar ao jogador janelas reais para ler/esquivar/contra-atacar;
	- preservar a IA individual do SlimeController para quem possui vaga de ataque;
	- manter os demais mobs vivos e presentes, mas em uma formacao de espera;
	- rotacionar as vagas para o combate continuar dinamico.

	Regras por jogador:
	- ilhas 1-2: 1 atacante simultaneo;
	- ilhas 3-6: 2 atacantes simultaneos;
	- ilha 7+: 3 atacantes simultaneos;
	- ataques de pressao (ranged/mortar/lightning) usam no maximo 1 vaga ate
	  a ilha 9 e no maximo 2 a partir da ilha 10;
	- quem nao tem vaga ocupa um anel ao redor do jogador e nao pode atacar;
	- vagas duram alguns segundos e depois podem ser entregues a outro mob;
	- morte/saida de um atacante libera a vaga imediatamente.

	Implementacao:
	O SlimeController ja respeita CombatStunned antes de iniciar ataques.
	Este coordenador usa CombatStunned SOMENTE enquanto GroupCombatHold=true e
	marca GroupCombatStunOwned para nunca limpar um stun que ja existia antes.
	Enquanto o mob esta em espera, este script e a autoridade do MoveTo dele.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TARGET_TAG = "CombatTarget"
local VERSION = "GroupCombatSlotsV1"

local UPDATE_SECONDS = 0.10
local ATTACKER_LEASE_SECONDS = 4.0
local ROTATION_COOLDOWN_SECONDS = 1.6
local MAX_COORDINATION_DISTANCE = 70

local MELEE_WAIT_RADIUS = 11
local LIGHTNING_WAIT_RADIUS = 20
local RANGED_WAIT_RADIUS = 30
local HOLD_POSITION_TOLERANCE = 2.5

local mobRecords = setmetatable({}, { __mode = "k" })
local elapsed = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return 1
	end
	return math.max(1, math.floor(number))
end

local function livingPlayer(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
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
		or player:GetAttribute("IsDowned") == true
		or player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
	then
		return nil
	end
	return player, humanoid, root
end

local function mobParts(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return humanoid, root
end

local function targetUserId(model)
	local value = tonumber(
		model:GetAttribute("TargetUserId")
			or model:GetAttribute("AggroUserId")
	)
	if not value then
		return nil
	end
	value = math.floor(value)
	return value > 0 and value or nil
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function isPressureMob(model)
	if model:GetAttribute("MobIsRanged") == true then
		return true
	end
	local variant = tostring(model:GetAttribute("SlimeVariant") or "")
	return variant == "Blue"
		or variant == "Red"
		or variant == "Fire"
		or variant == "Ice"
		or variant == "Lightning"
end

local function waitRadius(model)
	local variant = tostring(model:GetAttribute("SlimeVariant") or "")
	if variant == "Lightning" then
		return LIGHTNING_WAIT_RADIUS
	end
	if model:GetAttribute("MobIsRanged") == true
		or variant == "Blue"
		or variant == "Red"
		or variant == "Fire"
		or variant == "Ice"
	then
		return RANGED_WAIT_RADIUS
	end
	return MELEE_WAIT_RADIUS
end

local function limitsFor(player)
	local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if index <= 2 then
		return 1, 1
	elseif index <= 6 then
		return 2, 1
	end
	return 3, index >= 10 and 2 or 1
end

local function getRecord(model)
	local record = mobRecords[model]
	if record then
		return record
	end
	record = {
		Role = nil,
		TargetUserId = nil,
		LeaseUntil = 0,
		CooldownUntil = 0,
		PreexistingCombatStunned = false,
		HoldOwned = false,
		LastSeenAt = 0,
	}
	mobRecords[model] = record
	return record
end

local function releaseHold(model, record)
	if not model or not model.Parent then
		return
	end
	if model:GetAttribute("GroupCombatHold") == true then
		if record.HoldOwned
			and model:GetAttribute("GroupCombatStunOwned") == true
			and model:GetAttribute("CombatStunned") == true
		then
			model:SetAttribute("CombatStunned", nil)
		end
	end
	model:SetAttribute("GroupCombatHold", nil)
	model:SetAttribute("GroupCombatStunOwned", nil)
	record.HoldOwned = false
end

local function markAttacker(model, record, userId, slot, currentTime)
	releaseHold(model, record)
	if record.Role ~= "Attacker" or record.TargetUserId ~= userId then
		record.LeaseUntil = currentTime + ATTACKER_LEASE_SECONDS
	end
	record.Role = "Attacker"
	record.TargetUserId = userId
	model:SetAttribute("GroupCombatRole", "Attacker")
	model:SetAttribute("GroupCombatSlot", slot)
	model:SetAttribute("GroupCombatTargetUserId", userId)
	model:SetAttribute("GroupCombatLeaseUntil", record.LeaseUntil)
	model:SetAttribute("GroupCombatCoordinatorVersion", VERSION)
end

local function applyHold(model, record, userId, slot)
	if model:GetAttribute("GroupCombatHold") ~= true then
		record.PreexistingCombatStunned = model:GetAttribute("CombatStunned") == true
		record.HoldOwned = not record.PreexistingCombatStunned
		model:SetAttribute("GroupCombatHold", true)
		model:SetAttribute("GroupCombatStunOwned", record.HoldOwned)
		if record.HoldOwned then
			model:SetAttribute("CombatStunned", true)
		end
	end
	record.Role = "Waiting"
	record.TargetUserId = userId
	model:SetAttribute("GroupCombatRole", "Waiting")
	model:SetAttribute("GroupCombatSlot", slot)
	model:SetAttribute("GroupCombatTargetUserId", userId)
	model:SetAttribute("GroupCombatLeaseUntil", nil)
	model:SetAttribute("GroupCombatCoordinatorVersion", VERSION)
	model:SetAttribute("AIState", "GroupWait")
end

local function clearRole(model, record)
	if model and model.Parent then
		releaseHold(model, record)
		model:SetAttribute("GroupCombatRole", nil)
		model:SetAttribute("GroupCombatSlot", nil)
		model:SetAttribute("GroupCombatTargetUserId", nil)
		model:SetAttribute("GroupCombatLeaseUntil", nil)
	end
	record.Role = nil
	record.TargetUserId = nil
	record.LeaseUntil = 0
end

local function stableAngle(model, slot, count)
	local seed = 0
	for index = 1, #model.Name do
		seed += string.byte(model.Name, index) * index
	end
	local base = (seed % 360) * math.pi / 180
	if count > 1 then
		base += ((slot - 1) / count) * math.pi * 2
	end
	return base
end

local function safeGround(model, player, desired)
	local exclusions = { model }
	if player.Character then
		table.insert(exclusions, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	local result = workspace:Raycast(
		desired + Vector3.new(0, 18, 0),
		Vector3.new(0, -60, 0),
		params
	)
	if result and result.Instance:IsA("BasePart") and result.Instance.CanCollide then
		return result.Position
	end
	return nil
end

local function moveWaitingMob(model, record, player, playerRoot, slot, count)
	local humanoid, root = mobParts(model)
	if not humanoid or not root then
		return
	end

	local radius = waitRadius(model)
	local away = Vector3.new(
		root.Position.X - playerRoot.Position.X,
		0,
		root.Position.Z - playerRoot.Position.Z
	)
	local angle = stableAngle(model, slot, count)
	local fallbackDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local radialDirection = away.Magnitude > 0.5 and away.Unit or fallbackDirection

	-- Mistura a posicao natural do mob com o slot do anel. Isso evita que todos
	-- escolham o mesmo ponto sem obrigar um mob a atravessar o jogador.
	local blended = radialDirection * 0.7 + fallbackDirection * 0.3
	local direction = blended.Magnitude > 0.1 and blended.Unit or fallbackDirection
	local desiredFlat = playerRoot.Position + direction * radius
	local ground = safeGround(model, player, desiredFlat)

	if not ground then
		local fallbackFlat = playerRoot.Position + radialDirection * radius
		ground = safeGround(model, player, fallbackFlat)
	end

	if not ground then
		humanoid:MoveTo(root.Position)
		return
	end

	local distance = horizontalDistance(root.Position, ground)
	if distance > HOLD_POSITION_TOLERANCE then
		humanoid.AutoRotate = true
		humanoid:MoveTo(ground)
	else
		humanoid:MoveTo(root.Position)
		local lookAt = Vector3.new(playerRoot.Position.X, root.Position.Y, playerRoot.Position.Z)
		if (lookAt - root.Position).Magnitude > 0.2 and not root.Anchored then
			root.CFrame = CFrame.lookAt(root.Position, lookAt)
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	model:SetAttribute("GroupCombatHoldRadius", radius)
	model:SetAttribute("GroupCombatHoldPosition", ground)
	model:SetAttribute("AIState", "GroupWait")
end

local function candidateScore(candidate, currentTime)
	local score = candidate.Distance
	if candidate.Record.CooldownUntil > currentTime then
		score += 1000
	end
	return score
end

local function coordinateGroup(userId, candidates, currentTime)
	local player, _, playerRoot = livingPlayer(userId)
	if not player then
		for _, candidate in ipairs(candidates) do
			clearRole(candidate.Model, candidate.Record)
		end
		return
	end

	local maximumAttackers, maximumPressure = limitsFor(player)

	for _, candidate in ipairs(candidates) do
		local record = candidate.Record
		if record.Role == "Attacker"
			and record.TargetUserId == userId
			and record.LeaseUntil <= currentTime
		then
			record.Role = nil
			record.CooldownUntil = currentTime + ROTATION_COOLDOWN_SECONDS
		end
	end

	table.sort(candidates, function(left, right)
		local leftCurrent = left.Record.Role == "Attacker"
			and left.Record.TargetUserId == userId
			and left.Record.LeaseUntil > currentTime
		local rightCurrent = right.Record.Role == "Attacker"
			and right.Record.TargetUserId == userId
			and right.Record.LeaseUntil > currentTime
		if leftCurrent ~= rightCurrent then
			return leftCurrent
		end
		return candidateScore(left, currentTime) < candidateScore(right, currentTime)
	end)

	local selected = {}
	local selectedSet = setmetatable({}, { __mode = "k" })
	local pressureCount = 0

	-- Primeiro preserva quem ainda possui lease para evitar trocas nervosas.
	for _, candidate in ipairs(candidates) do
		if #selected >= maximumAttackers then
			break
		end
		local record = candidate.Record
		if record.Role == "Attacker"
			and record.TargetUserId == userId
			and record.LeaseUntil > currentTime
		then
			if not candidate.Pressure or pressureCount < maximumPressure then
				table.insert(selected, candidate)
				selectedSet[candidate.Model] = true
				if candidate.Pressure then
					pressureCount += 1
				end
			end
		end
	end

	local function fill(allowCooldown)
		for _, candidate in ipairs(candidates) do
			if #selected >= maximumAttackers then
				return
			end
			if selectedSet[candidate.Model] then
				continue
			end
			if not allowCooldown and candidate.Record.CooldownUntil > currentTime then
				continue
			end
			if candidate.Pressure and pressureCount >= maximumPressure then
				continue
			end
			table.insert(selected, candidate)
			selectedSet[candidate.Model] = true
			if candidate.Pressure then
				pressureCount += 1
			end
		end
	end

	fill(false)
	if #selected < maximumAttackers then
		fill(true)
	end

	for slot, candidate in ipairs(selected) do
		markAttacker(candidate.Model, candidate.Record, userId, slot, currentTime)
	end

	local waiting = {}
	for _, candidate in ipairs(candidates) do
		if not selectedSet[candidate.Model] then
			table.insert(waiting, candidate)
		end
	end

	for slot, candidate in ipairs(waiting) do
		applyHold(candidate.Model, candidate.Record, userId, slot)
		moveWaitingMob(
			candidate.Model,
			candidate.Record,
			player,
			playerRoot,
			slot,
			#waiting
		)
	end

	player:SetAttribute("MobGroupCombatActiveAttackers", #selected)
	player:SetAttribute("MobGroupCombatWaitingMobs", #waiting)
	player:SetAttribute("MobGroupCombatMaxAttackers", maximumAttackers)
	player:SetAttribute("MobGroupCombatMaxPressureAttackers", maximumPressure)
	player:SetAttribute("MobGroupCombatCoordinatorVersion", VERSION)
end

local function update()
	local currentTime = now()
	local groups = {}
	local seen = setmetatable({}, { __mode = "k" })

	for _, model in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if not model:IsA("Model")
			or model:GetAttribute("MonsterFamily") ~= "Slime"
			or model:GetAttribute("SimulationActive") == false
		then
			continue
		end

		local humanoid, root = mobParts(model)
		local userId = targetUserId(model)
		if not humanoid or not root or not userId then
			continue
		end

		local player, _, playerRoot = livingPlayer(userId)
		if not player or not playerRoot then
			continue
		end

		local distance = horizontalDistance(root.Position, playerRoot.Position)
		if distance > MAX_COORDINATION_DISTANCE then
			continue
		end

		local record = getRecord(model)
		record.LastSeenAt = currentTime
		seen[model] = true

		groups[userId] = groups[userId] or {}
		table.insert(groups[userId], {
			Model = model,
			Record = record,
			Distance = distance,
			Pressure = isPressureMob(model),
		})
	end

	for userId, candidates in pairs(groups) do
		coordinateGroup(userId, candidates, currentTime)
	end

	for model, record in pairs(mobRecords) do
		if not model.Parent then
			mobRecords[model] = nil
		elseif not seen[model] then
			clearRole(model, record)
		end
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < UPDATE_SECONDS then
		return
	end
	elapsed = 0
	update()
end)

Players.PlayerRemoving:Connect(function(player)
	for model, record in pairs(mobRecords) do
		if record.TargetUserId == player.UserId then
			clearRole(model, record)
		end
	end
end)

workspace:SetAttribute("DungeonMobGroupCombatReady", true)
workspace:SetAttribute("DungeonMobGroupCombatVersion", VERSION)
workspace:SetAttribute("DungeonMobGroupCombatPolicy", "LimitedAttackSlotsWithWaitingRing")
workspace:SetAttribute("DungeonMobGroupCombatAttackerLeaseSeconds", ATTACKER_LEASE_SECONDS)

print("[MobGroupCombat] Ready - vagas de ataque e formacao de espera ativas")
