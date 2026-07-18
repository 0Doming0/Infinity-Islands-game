-- IA exclusiva do bau Mimico. Usa uma unica animacao Animations/Main; se ela
-- tiver o marcador Bite, o dano sincroniza com o quadro da mordida.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local InventoryService = require(script.Parent.Parent.MVPSystems:WaitForChild("InventoryService"))
ScoreService.Start()
InventoryService.Start()

local MimicAI = {}
local states = setmetatable({}, { __mode = "k" })
local heartbeatConnected = false

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getDamager(model, humanoid)
	local creator = humanoid:FindFirstChild("creator")
	if creator and creator:IsA("ObjectValue") and creator.Value and creator.Value:IsA("Player") then
		return creator.Value
	end
	local userId = model:GetAttribute("LastDamagedByUserId")
	return typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
end

local function nearestPlayer(position, maximumDistance)
	local nearestHumanoid
	local nearestRoot
	local distance = maximumDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			local current = (root.Position - position).Magnitude
			if current < distance then
				distance = current
				nearestHumanoid = humanoid
				nearestRoot = root
			end
		end
	end
	return nearestHumanoid, nearestRoot, distance
end

local function attack(state)
	local now = os.clock()
	if now < state.NextAttackAt or not state.TargetHumanoid or not state.TargetRoot then
		return
	end
	if state.TargetHumanoid.Health <= 0 or (state.TargetRoot.Position - state.Root.Position).Magnitude > state.AttackRange then
		return
	end
	state.NextAttackAt = now + state.AttackCooldown
	state.TargetHumanoid:TakeDamage(state.AttackDamage)
end

local function playMainAnimation(model, humanoid, state)
	local folder = model:FindFirstChild("Animations")
	local animation = folder and folder:FindFirstChild("Main")
	if not animation or not animation:IsA("Animation") or animation.AnimationId == "" then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local success, track = pcall(animator.LoadAnimation, animator, animation)
	if not success then
		warn("[MimicAI] Animacao Main falhou: " .. tostring(track))
		return
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.1, 1, 1)
	state.AnimationTrack = track
	state.UsesBiteMarker = false
	track:GetMarkerReachedSignal("Bite"):Connect(function()
		state.UsesBiteMarker = true
		attack(state)
	end)
end

local function connectHeartbeat()
	if heartbeatConnected then
		return
	end
	heartbeatConnected = true
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.18 then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = os.clock()
		for model, state in pairs(states) do
			if not model.Parent or state.Humanoid.Health <= 0 or not state.Root.Parent then
				states[model] = nil
				continue
			end
			if model:GetAttribute("CombatStunned") == true then
				continue
			end
			local targetHumanoid, targetRoot, distance = nearestPlayer(state.Root.Position, state.AggroRange)
			state.TargetHumanoid = targetHumanoid
			state.TargetRoot = targetRoot
			if (state.Root.Position - state.Home).Magnitude > state.LeashRange then
				state.Humanoid:MoveTo(state.Home)
			elseif targetRoot then
				state.Humanoid:MoveTo(targetRoot.Position)
				if distance <= state.AttackRange and not state.UsesBiteMarker then
					attack(state)
				end
			else
				state.Humanoid:MoveTo(state.Home)
			end

			local moved = (state.Root.Position - state.LastPosition).Magnitude
			state.LastPosition = state.Root.Position
			state.StuckFor = moved < 0.12 and state.StuckFor + step or 0
			if targetRoot and state.StuckFor >= 0.7 and now >= state.NextJumpAt then
				state.NextJumpAt = now + 1.1
				state.StuckFor = 0
				state.Humanoid.Jump = true
			end
		end
	end)
end

function MimicAI.Activate(model, options)
	options = options or {}
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = getRoot(model)
	if not humanoid or not root or not root:IsA("BasePart") then
		return false, "MimicChest precisa de Humanoid e HumanoidRootPart"
	end
	model.PrimaryPart = root
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("MonsterId", "MimicChest")
	model:SetAttribute("DisplayName", "Bau Mimico")
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("IsMimic", true)
	model:SetAttribute("HomePosition", root.Position)
	CollectionService:AddTag(model, "CombatTarget")
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local tier = math.max(1, math.floor(tonumber(options.DifficultyTier) or 1))
	humanoid.MaxHealth = math.floor((tonumber(model:GetAttribute("MaxHealth")) or 90) * (1 + (tier - 1) * 0.20))
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayName = "Bau Mimico"
	humanoid.BreakJointsOnDeath = false

	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Home = root.Position,
		AggroRange = tonumber(model:GetAttribute("AggroRange")) or 58,
		LeashRange = tonumber(model:GetAttribute("LeashRange")) or 46,
		AttackRange = tonumber(model:GetAttribute("AttackRange")) or 5.5,
		AttackCooldown = tonumber(model:GetAttribute("AttackCooldown")) or 1.15,
		AttackDamage = math.floor((tonumber(model:GetAttribute("AttackDamage")) or 12) * (1 + (tier - 1) * 0.12)),
		NextAttackAt = os.clock() + 0.75,
		NextJumpAt = 0,
		LastPosition = root.Position,
		StuckFor = 0,
		UsesBiteMarker = false,
	}
	states[model] = state
	playMainAnimation(model, humanoid, state)
	connectHeartbeat()

	humanoid.Died:Connect(function()
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

return MimicAI
