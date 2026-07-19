-- IA basica para prototipos e Elites sem IA propria. Assets com IA especifica
-- podem definir UseCentralAI=false e manter seus scripts internos.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local THINK_INTERVAL = 0.20
local DEFAULT_AGGRO_RANGE = 55
local DEFAULT_LEASH_RANGE = 42
local DEFAULT_ATTACK_RANGE = 5
local DEFAULT_ATTACK_COOLDOWN = 1.15

local states = setmetatable({}, { __mode = "k" })

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function nearestPlayer(position, range)
	local selectedHumanoid
	local selectedRoot
	local bestDistance = range
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				selectedHumanoid = humanoid
				selectedRoot = root
			end
		end
	end
	return selectedHumanoid, selectedRoot, bestDistance
end

local function register(model)
	if not model:IsA("Model") or states[model] then
		return
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local root = rootOf(model)
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local home = model:GetAttribute("HomePosition")
	states[model] = {
		Humanoid = humanoid,
		Root = root,
		Home = typeof(home) == "Vector3" and home or root.Position,
		NextAttackAt = 0,
		NextJumpAt = 0,
		LastPosition = root.Position,
		StuckTime = 0,
	}
	humanoid.Died:Connect(function()
		states[model] = nil
	end)
	model.Destroying:Connect(function()
		states[model] = nil
	end)
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(function(model)
	task.defer(register, model)
end)
for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
	task.defer(register, model)
end

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < THINK_INTERVAL then
		return
	end
	local step = accumulated
	accumulated = 0
	local now = os.clock()
	for model, state in pairs(states) do
		local humanoid = state.Humanoid
		local root = state.Root
		if not model.Parent or not root.Parent or humanoid.Health <= 0 then
			states[model] = nil
			continue
		end
		if model:GetAttribute("CombatStunned") == true then
			continue
		end
		local forceAggressive = workspace:GetAttribute("AllMobsAggressive") == true
		if model:GetAttribute("UseCentralAI") ~= true and not forceAggressive then
			continue
		end

		local eventHunt = workspace:GetAttribute("MonsterHuntActive") == true
		local aggro = tonumber(model:GetAttribute("AggroRange")) or DEFAULT_AGGRO_RANGE
		if eventHunt then
			aggro *= 1.45
		end
		local targetHumanoid, targetRoot, distance
		if forceAggressive or model:GetAttribute("Peaceful") ~= true then
			targetHumanoid, targetRoot, distance = nearestPlayer(root.Position, aggro)
		end
		local leash = tonumber(model:GetAttribute("LeashRange")) or DEFAULT_LEASH_RANGE
		if (root.Position - state.Home).Magnitude > leash then
			humanoid:MoveTo(state.Home)
		elseif targetRoot then
			humanoid:MoveTo(targetRoot.Position)
			local attackRange = tonumber(model:GetAttribute("AttackRange")) or DEFAULT_ATTACK_RANGE
			if distance <= attackRange and now >= state.NextAttackAt then
				state.NextAttackAt = now + (tonumber(model:GetAttribute("AttackCooldown")) or DEFAULT_ATTACK_COOLDOWN)
				targetHumanoid:TakeDamage(math.max(1, tonumber(model:GetAttribute("AttackDamage")) or 8))
			end
		else
			humanoid:MoveTo(state.Home)
		end

		local moved = (root.Position - state.LastPosition).Magnitude
		state.LastPosition = root.Position
		state.StuckTime = moved < 0.15 and state.StuckTime + step or 0
		if targetRoot and state.StuckTime >= 0.8 and now >= state.NextJumpAt then
			state.NextJumpAt = now + 1.2
			state.StuckTime = 0
			humanoid.Jump = true
		end
	end
end)
