-- IA exclusiva do bau Mimico. Movimento e combate ficam aqui; a animacao
-- procedural das pecas pertence aos Scripts internos do proprio modelo.
-- V4: locomocao cinemática sem HumanoidRootPart, WeldConstraint ou MoveTo.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local MobEventModifiers = require(script.Parent.MobEventModifiers)
local InventoryService = require(script.Parent.Parent.MVPSystems:WaitForChild("InventoryService"))
local AnimeOutline = require(ServerScriptService.MVPSystems:WaitForChild("AnimeOutline"))
ScoreService.Start()
InventoryService.Start()

local MimicAI = {}
local states = setmetatable({}, { __mode = "k" })
local heartbeatConnected = false

local STATE_AWAKE = "Awake"
local STATE_RETURNING = "Returning"
local STATE_DORMANT = "Dormant"
local HOME_SNAP_DISTANCE = 1.75
local MOVEMENT_STEP_INTERVAL = 1 / 30

local function getRoot(model)
	return model:FindFirstChild("MimicRoot", true)
		or model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function removeLegacyMovementRoot(model)
	-- Versoes anteriores criavam uma HumanoidRootPart soldada ao MimicRoot.
	-- Essa montagem disputa CFrame com a animacao procedural do bau.
	local legacyWeld = model:FindFirstChild("MimicMovementRootWeld", true)
	if not legacyWeld or not legacyWeld:IsA("WeldConstraint") then
		return
	end
	local movementRoot = legacyWeld.Parent
	legacyWeld:Destroy()
	if movementRoot and movementRoot:IsA("BasePart") and movementRoot.Name == "HumanoidRootPart" then
		movementRoot:Destroy()
	end
end

local function moveModelTowards(state, destination, speed, dt)
	local offset = destination - state.Position
	local distance = offset.Magnitude
	if distance <= 0.001 then
		return 0
	end
	local stepDistance = math.min(distance, math.max(0, speed) * dt)
	local delta = offset.Unit * stepDistance

	-- PivotTo aplica somente o deslocamento global sobre a pose existente. Ele nao
	-- cria juntas, nao gira o MimicRoot e nao apaga a rotacao procedural das pecas.
	state.Model:PivotTo(state.Model:GetPivot() + delta)
	state.Position += delta
	return stepDistance
end

local function getDamager(model, humanoid)
	local creator = humanoid:FindFirstChild("creator")
	if creator and creator:IsA("ObjectValue") and creator.Value and creator.Value:IsA("Player") then
		return creator.Value
	end
	local userId = model:GetAttribute("LastDamagedByUserId")
	return typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
end

local function playerIsOnOriginIsland(player, state)
	if state.IslandKey then
		local currentIslandKey = player:GetAttribute("CurrentIslandKey")
		if currentIslandKey ~= nil then
			return currentIslandKey == state.IslandKey
		end
	end

	-- Compatibility for old/static islands and for the brief moment before the
	-- chunk manager publishes CurrentIslandKey on a newly entered island.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - state.Home).Magnitude <= state.IslandFallbackRadius
end

local function nearestPlayer(position, maximumDistance, state)
	local nearestHumanoid
	local nearestRoot
	local distance = maximumDistance
	local originIslandOccupied = false
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and playerIsOnOriginIsland(player, state) then
			originIslandOccupied = true
			local current = (root.Position - position).Magnitude
			if current < distance then
				distance = current
				nearestHumanoid = humanoid
				nearestRoot = root
			end
		end
	end
	return nearestHumanoid, nearestRoot, distance, originIslandOccupied
end

local function setProceduralScriptsEnabled(state, enabled)
	for scriptInstance, wasEnabled in pairs(state.ProceduralScripts) do
		if scriptInstance.Parent then
			scriptInstance.Disabled = not (enabled and wasEnabled)
		end
	end
end

local function setModelEnabled(state, enabled)
	state.Model:SetAttribute("Enabled", enabled)
	for part, properties in pairs(state.PartProperties) do
		if part.Parent then
			if enabled then
				part.Transparency = properties.Transparency
				part.CanCollide = properties.CanCollide
				part.CanTouch = properties.CanTouch
				part.CanQuery = properties.CanQuery
			else
				part.Transparency = 1
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
	end
	for effect, wasEnabled in pairs(state.EffectProperties) do
		if effect.Parent then
			effect.Enabled = enabled and wasEnabled
		end
	end
end

local function refreshHomeFromIsland(state)
	if not state.Island or not state.Island.Parent or not state.HomeRelativeToIsland then
		return
	end
	local previousHome = state.Home
	state.HomePivot = state.Island:GetPivot() * state.HomeRelativeToIsland
	state.Home = state.HomePivot.Position
	if previousHome then
		state.Position += state.Home - previousHome
	end
	if state.NormalChestRelativeToIsland then
		state.NormalChestPivot = state.Island:GetPivot() * state.NormalChestRelativeToIsland
	end
	state.Model:SetAttribute("HomePosition", state.Home)
end

local function setMimicState(state, newState)
	if state.State == newState then
		return
	end
	state.State = newState
	state.Model:SetAttribute("MimicState", newState)
	state.Model:SetAttribute("MimicAwake", newState ~= STATE_DORMANT)

	if newState == STATE_AWAKE then
		if state.OnAwake then
			local ok, reason = pcall(state.OnAwake, state.Model, state.DormantDisguise)
			if not ok then
				warn("[MimicAI] Falha ao remover disfarce NormalChest: " .. tostring(reason))
			end
		end
		state.DormantDisguise = nil
		setModelEnabled(state, true)
		state.Model:SetAttribute("Peaceful", false)
		if not CollectionService:HasTag(state.Model, "CombatTarget") then
			CollectionService:AddTag(state.Model, "CombatTarget")
			MobEventModifiers.Apply(state.Model)
		end
		state.Humanoid.AutoRotate = false
		state.Humanoid.WalkSpeed = state.OriginalWalkSpeed
		state.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
		setProceduralScriptsEnabled(state, true)
	elseif newState == STATE_RETURNING then
		state.TargetHumanoid = nil
		state.TargetRoot = nil
		state.Humanoid.AutoRotate = false
		state.Humanoid.WalkSpeed = state.ReturnWalkSpeed
		state.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	else
		state.TargetHumanoid = nil
		state.TargetRoot = nil
		state.Humanoid.AutoRotate = false
		state.Humanoid.WalkSpeed = 0
		state.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		setProceduralScriptsEnabled(state, false)
		state.Humanoid.Health = state.Humanoid.MaxHealth
		state.Model:SetAttribute("Peaceful", true)
		if CollectionService:HasTag(state.Model, "CombatTarget") then
			CollectionService:RemoveTag(state.Model, "CombatTarget")
		end
		state.Model:PivotTo(state.HomePivot)
		state.Position = state.Home
		for part, relativeCFrame in pairs(state.HomePose) do
			if part.Parent and part.Anchored then
				part.CFrame = state.HomePivot * relativeCFrame
			end
		end
		for _, descendant in ipairs(state.Model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
		setModelEnabled(state, false)
		if state.OnDormant then
			local ok, disguiseOrReason = pcall(
				state.OnDormant,
				state.Model,
				state.NormalChestPivot
			)
			if ok then
				state.DormantDisguise = disguiseOrReason
			else
				warn("[MimicAI] Falha ao criar disfarce NormalChest: " .. tostring(disguiseOrReason))
			end
		end
	end
end

local function attack(state)
	local now = os.clock()
	if now < state.NextAttackAt or not state.TargetHumanoid or not state.TargetRoot then
		return
	end
	if
		state.TargetHumanoid.Health <= 0
		or (state.TargetRoot.Position - state.Position).Magnitude > state.AttackRange
	then
		return
	end
	state.NextAttackAt = now + state.AttackCooldown
	state.TargetHumanoid:TakeDamage(state.AttackDamage)
end

local function connectHeartbeat()
	if heartbeatConnected then
		return
	end
	heartbeatConnected = true
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < MOVEMENT_STEP_INTERVAL then
			return
		end
		local step = accumulated
		accumulated = 0
		for model, state in pairs(states) do
			if not model.Parent or state.Humanoid.Health <= 0 or not state.Root.Parent then
				states[model] = nil
				continue
			end
			refreshHomeFromIsland(state)
			if model:GetAttribute("SimulationActive") == false then
				-- Once the origin island sleeps there cannot be an active player on it.
				-- Reset immediately instead of keeping an off-screen Humanoid walking.
				if state.State ~= STATE_DORMANT then
					setMimicState(state, STATE_DORMANT)
				end
				continue
			end
			if model:GetAttribute("CombatStunned") == true then
				continue
			end
			local aggroRange = MobEventModifiers.GetAggroRange(model, state.AggroRange)
			local targetHumanoid, targetRoot, distance, originIslandOccupied =
				nearestPlayer(state.Position, aggroRange, state)

			if not originIslandOccupied and state.State == STATE_AWAKE then
				setMimicState(state, STATE_RETURNING)
			end
			if state.State == STATE_RETURNING then
				if originIslandOccupied and targetRoot then
					setMimicState(state, STATE_AWAKE)
				else
					moveModelTowards(state, state.Home, state.ReturnWalkSpeed, step)
					if (state.Position - state.Home).Magnitude <= HOME_SNAP_DISTANCE then
						setMimicState(state, STATE_DORMANT)
					end
					continue
				end
			end
			if state.State == STATE_DORMANT then
				-- Voltar para a ilha nao desperta o Mimico. Ele so acorda quando o
				-- jogador tenta abrir o NormalChest criado pelo ChestService.
				continue
			end

			state.TargetHumanoid = targetHumanoid
			state.TargetRoot = targetRoot
			if (state.Position - state.Home).Magnitude > state.LeashRange then
				moveModelTowards(state, state.Home, state.ReturnWalkSpeed, step)
			elseif targetRoot then
				-- O mimico anda no plano da ilha; nao tenta subir ate o centro do player.
				local destination = Vector3.new(targetRoot.Position.X, state.Position.Y, targetRoot.Position.Z)
				moveModelTowards(state, destination, state.OriginalWalkSpeed, step)
				if distance <= state.AttackRange then
					attack(state)
				end
			else
				moveModelTowards(state, state.Home, state.ReturnWalkSpeed, step)
			end
		end
	end)
end

function MimicAI.Activate(model, options)
	options = options or {}
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = getRoot(model)
	if not humanoid or not root or not root:IsA("BasePart") then
		return false, "MimicChest precisa de Humanoid e MimicRoot"
	end
	removeLegacyMovementRoot(model)
	-- Nao altere Anchored nem crie soldas: o template e o script procedural sao
	-- os donos da configuracao fisica e da pose do MimicRoot.
	model.PrimaryPart = root
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("MonsterId", "MimicChest")
	model:SetAttribute("DisplayName", "Bau Mimico")
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("AIController", "Mimic")
	local island = model:FindFirstAncestorWhichIsA("Model")
	while island and island:GetAttribute("IsSkyIsland") ~= true do
		island = island:FindFirstAncestorWhichIsA("Model")
	end
	local islandKey = island and island:GetAttribute("IslandNodeKey") or nil
	model:SetAttribute("SimulationActive", not island or island:GetAttribute("SimulationActive") ~= false)
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("IsMimic", true)
	model:SetAttribute("HomePosition", root.Position)
	CollectionService:AddTag(model, "CombatTarget")
	MobEventModifiers.Apply(model)
	AnimeOutline.Apply(model)

	local tier = math.max(1, math.floor(tonumber(options.DifficultyTier) or 1))
	humanoid.MaxHealth = math.floor((tonumber(model:GetAttribute("MaxHealth")) or 90) * (1 + (tier - 1) * 0.20))
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayName = "Bau Mimico"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 18
	humanoid.HealthDisplayDistance = 16
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false

	local proceduralScripts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			proceduralScripts[descendant] = not descendant.Disabled
		end
	end
	local homePivot = model:GetPivot()
	local homeRelativeToIsland = island and island:GetPivot():ToObjectSpace(homePivot) or nil
	local normalChestPivot = typeof(options.NormalChestPivot) == "CFrame" and options.NormalChestPivot or homePivot
	local normalChestRelativeToIsland = island and island:GetPivot():ToObjectSpace(normalChestPivot) or nil
	local homePose = {}
	local partProperties = {}
	local effectProperties = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partProperties[descendant] = {
				Transparency = descendant.Transparency,
				CanCollide = descendant.CanCollide,
				CanTouch = descendant.CanTouch,
				CanQuery = descendant.CanQuery,
			}
		end
		if descendant:IsA("BasePart") and descendant ~= root then
			homePose[descendant] = homePivot:ToObjectSpace(descendant.CFrame)
		end
		if descendant:IsA("Highlight")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
		then
			effectProperties[descendant] = descendant.Enabled
		end
	end

	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Position = root.Position,
		Home = root.Position,
		HomePivot = homePivot,
		HomeRelativeToIsland = homeRelativeToIsland,
		NormalChestPivot = normalChestPivot,
		NormalChestRelativeToIsland = normalChestRelativeToIsland,
		HomePose = homePose,
		PartProperties = partProperties,
		EffectProperties = effectProperties,
		Island = island,
		IslandKey = typeof(islandKey) == "string" and islandKey or nil,
		IslandFallbackRadius = tonumber(model:GetAttribute("IslandFallbackRadius")) or 52,
		State = STATE_AWAKE,
		ProceduralScripts = proceduralScripts,
		OriginalWalkSpeed = humanoid.WalkSpeed,
		ReturnWalkSpeed = tonumber(model:GetAttribute("ReturnWalkSpeed")) or math.max(10, humanoid.WalkSpeed),
		AggroRange = tonumber(model:GetAttribute("AggroRange")) or 58,
		LeashRange = tonumber(model:GetAttribute("LeashRange")) or 46,
		AttackRange = tonumber(model:GetAttribute("AttackRange")) or 5.5,
		AttackCooldown = tonumber(model:GetAttribute("AttackCooldown")) or 1.15,
		AttackDamage = math.floor((tonumber(model:GetAttribute("AttackDamage")) or 12) * (1 + (tier - 1) * 0.12)),
		NextAttackAt = os.clock() + 0.75,
		OnDormant = type(options.OnDormant) == "function" and options.OnDormant or nil,
		OnAwake = type(options.OnAwake) == "function" and options.OnAwake or nil,
		DormantDisguise = nil,
	}
	states[model] = state
	model:SetAttribute("MimicState", STATE_AWAKE)
	model:SetAttribute("MimicAwake", true)
	model:SetAttribute("Enabled", true)
	model:SetAttribute("OriginIslandKey", state.IslandKey)
	connectHeartbeat()

	humanoid.Died:Connect(function()
		if state.OnAwake then
			pcall(state.OnAwake, model, state.DormantDisguise)
		end
		states[model] = nil
		if CollectionService:HasTag(model, "CombatTarget") then
			CollectionService:RemoveTag(model, "CombatTarget")
		end
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
		local damager = getDamager(model, humanoid)
		if damager then
			ScoreService.AwardRewards(
				damager,
				math.max(8, tonumber(options.ScoreReward) or 15),
				math.max(1, tonumber(options.CoinReward) or 50),
				"MimicChest"
			)
			if math.random() <= 0.15 then
				InventoryService.GrantItem(damager, "GreaterHealthPotion", 1)
			end
		end
		Debris:AddItem(model, 0.8)
	end)
	return true
end

function MimicAI.Wake(model)
	local state = states[model]
	if not state or not model.Parent or state.Humanoid.Health <= 0 then
		return false, "Mimico inexistente ou derrotado"
	end
	if state.State ~= STATE_DORMANT then
		return false, "Mimico nao esta disfarçado"
	end
	refreshHomeFromIsland(state)
	state.Model:PivotTo(state.HomePivot)
	state.Position = state.Home
	setMimicState(state, STATE_AWAKE)
	state.NextAttackAt = os.clock() + 0.75
	return true
end

return MimicAI