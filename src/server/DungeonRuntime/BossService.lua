local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Configs.BossConfig)
local PlayerDamageService = require(script.Parent.Parent.MVPSystems.PlayerDamageService)
local ContentResolver = require(script.Parent.ContentResolver)
local PartyScalingService = require(script.Parent.PartyScalingService)
local RuntimeFolders = require(script.Parent.RuntimeFolders)

local BossService = {}
local activeState

local function positiveNumberAttribute(instance, name, fallback, minimum)
	local value = instance and instance:GetAttribute(name)
	if typeof(value) ~= "number" then
		return fallback
	end
	return math.max(minimum or 0, value)
end

local function resolveBossDefinition(template, bossId)
	local configured = BossConfig[bossId] or BossConfig.GiantBoss
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
	}
end

local function makePart(name, size, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = name ~= "HumanoidRootPart"
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
	local root = makePart("HumanoidRootPart", Vector3.new(6, 10, 5), Color3.fromRGB(73, 111, 78), model)
	root.Transparency = 1
	root.CanCollide = true
	local torso = makePart("Torso", Vector3.new(10, 10, 6), Color3.fromRGB(84, 151, 92), model)
	weld(root, torso, CFrame.new(0, 1, 0))
	local head = makePart("Head", Vector3.new(7, 7, 7), Color3.fromRGB(106, 184, 105), model)
	weld(root, head, CFrame.new(0, 9, 0))
	for index, side in ipairs({ -1, 1 }) do
		local arm = makePart("Arm" .. index, Vector3.new(4, 11, 4), Color3.fromRGB(75, 135, 82), model)
		weld(root, arm, CFrame.new(side * 7, 1, 0))
		local leg = makePart("Leg" .. index, Vector3.new(4, 9, 4), Color3.fromRGB(63, 105, 68), model)
		weld(root, leg, CFrame.new(side * 3, -8, 0))
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.BreakJointsOnDeath = false
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
	boss.Name = "Boss_" .. bossId
	boss:SetAttribute("BossId", bossId)
	boss:SetAttribute("DisplayName", definition.DisplayName)
	boss:SetAttribute("AttackDamage", damage)
	boss:SetAttribute("AttackRange", definition.AttackRange)
	boss:SetAttribute("AttackCooldown", definition.AttackCooldown)
	boss:SetAttribute("AIController", "Boss")
	boss:SetAttribute("BossActive", false)
	boss:SetAttribute("Invulnerable", true)
	boss:SetAttribute("RuntimeMonster", true)
	boss:SetAttribute("IsBoss", true)
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

local function createFallbackArena(parent, anchorFloor)
	local arena = Instance.new("Model")
	arena.Name = "BossArena"
	local anchorPosition = anchorFloor and anchorFloor.Position or Vector3.new(0, 20, 0)
	local flat = Vector3.new(anchorPosition.X, 0, anchorPosition.Z)
	local outward = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, -1)
	local arenaPosition = anchorPosition + outward * 78 + Vector3.new(0, 4, 0)
	local floor = makePart("ArenaFloor", Vector3.new(76, 5, 76), Color3.fromRGB(82, 67, 54), arena)
	floor.Anchored = true
	floor.CFrame = CFrame.lookAt(arenaPosition, arenaPosition - outward)
	arena.PrimaryPart = floor
	if anchorFloor then
		local startPosition = anchorFloor.Position + Vector3.new(0, anchorFloor.Size.Y / 2, 0)
		local endPosition = arenaPosition - outward * 40
		local delta = endPosition - startPosition
		local bridge = makePart("BossBridge", Vector3.new(10, 2, math.max(8, delta.Magnitude)), Color3.fromRGB(109, 82, 59), arena)
		bridge.Anchored = true
		bridge.CFrame = CFrame.lookAt(startPosition + delta / 2, endPosition)
	end
	arena.Parent = parent
	return arena, floor
end

local function cloneArena(template, parent, anchorFloor)
	if not template then
		return createFallbackArena(parent, anchorFloor)
	end
	local arena
	if template:IsA("Model") then
		arena = template:Clone()
	else
		arena = Instance.new("Model")
		local clone = template:Clone()
		clone.Parent = arena
		arena.PrimaryPart = clone
	end
	arena.Name = "BossArena"
	local floor = arena:FindFirstChild("ArenaFloor", true)
		or arena:FindFirstChild("IslandFloor", true)
		or arena.PrimaryPart
		or arena:FindFirstChildWhichIsA("BasePart", true)
	if not floor or not floor:IsA("BasePart") then
		arena:Destroy()
		return createFallbackArena(parent, anchorFloor)
	end
	arena.PrimaryPart = arena.PrimaryPart or floor
	local anchorPosition = anchorFloor and anchorFloor.Position or Vector3.new(0, 20, 0)
	local flat = Vector3.new(anchorPosition.X, 0, anchorPosition.Z)
	local outward = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, -1)
	arena:PivotTo(CFrame.lookAt(anchorPosition + outward * 78 + Vector3.new(0, 4, 0), anchorPosition))
	for _, descendant in ipairs(arena:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = true
		end
	end
	arena.Parent = parent
	return arena, floor
end

local function nearestLivingPlayer(position, maximumDistance)
	local bestPlayer
	local bestRoot
	local bestDistance = maximumDistance
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("DungeonEliminated") ~= true then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root then
				local distance = (root.Position - position).Magnitude
				if distance < bestDistance then
					bestPlayer = player
					bestRoot = root
					bestDistance = distance
				end
			end
		end
	end
	return bestPlayer, bestRoot, bestDistance
end

local function activate(state)
	if state.Active or state.Completed then
		return
	end
	state.Active = true
	state.Boss:SetAttribute("BossActive", true)
	state.Boss:SetAttribute("Invulnerable", false)
	state.Trigger.CanTouch = false
	state.Trigger.Transparency = 1
end

local function startAI(state)
	task.spawn(function()
		while activeState == state and not state.Completed and state.Humanoid.Health > 0 do
			if state.Active then
				local player, targetRoot, distance = nearestLivingPlayer(
					state.Root.Position,
					state.Definition.DetectionRange
				)
				if targetRoot then
					state.Boss:SetAttribute("TargetUserId", player.UserId)
					if distance > state.Definition.AttackRange * 0.75 then
						state.Humanoid:MoveTo(targetRoot.Position)
					else
						state.Humanoid:MoveTo(state.Root.Position)
					end
					if distance <= state.Definition.AttackRange and os.clock() >= state.NextAttackAt then
						state.NextAttackAt = os.clock() + state.Definition.AttackCooldown
						local targetHumanoid = targetRoot.Parent and targetRoot.Parent:FindFirstChildOfClass("Humanoid")
						if targetHumanoid and targetHumanoid.Health > 0 then
							PlayerDamageService.ApplyToHumanoid(
								targetHumanoid,
								state.Boss:GetAttribute("AttackDamage"),
								"Boss"
							)
						end
					end
				else
					state.Boss:SetAttribute("TargetUserId", nil)
					state.Humanoid:MoveTo(state.Root.Position)
				end
			end
			RunService.Heartbeat:Wait()
			task.wait(0.12)
		end
	end)
end

function BossService.Create(options)
	assert(type(options) == "table", "BossService.Create requer opcoes")
	if activeState and not activeState.Completed then
		return activeState
	end
	local template = ContentResolver.FindBoss(options.PhaseId, options.BossId)
	local definition = resolveBossDefinition(template, options.BossId)
	local generated = RuntimeFolders.Get("GeneratedIslands")
	local bossFolder = RuntimeFolders.Get("ActiveBoss")
	bossFolder:ClearAllChildren()
	local anchorFloor = options.EndContext and options.EndContext.Floor
	local arena, arenaFloor = cloneArena(ContentResolver.FindBossArena(options.PhaseId), generated, anchorFloor)
	arena:SetAttribute("PhaseId", options.PhaseId)
	arena:SetAttribute("BossArena", true)

	local trigger = arena:FindFirstChild("BossTrigger", true)
	if not trigger or not trigger:IsA("BasePart") then
		trigger = Instance.new("Part")
		trigger.Name = "BossTrigger"
		trigger.Size = Vector3.new(math.max(18, arenaFloor.Size.X * 0.7), 10, 12)
		trigger.CFrame = arenaFloor.CFrame * CFrame.new(0, arenaFloor.Size.Y / 2 + 5, arenaFloor.Size.Z * 0.25)
		trigger.Anchored = true
		trigger.CanCollide = false
		trigger.CanQuery = false
		trigger.Transparency = 1
		trigger.Parent = arena
	end
	local boss, humanoid, root = prepareBoss(
		template,
		options.BossId,
		definition,
		options.PartySize
	)
	boss:PivotTo(arenaFloor.CFrame * CFrame.new(0, arenaFloor.Size.Y / 2 + 10, -arenaFloor.Size.Z * 0.18))
	boss.Parent = bossFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local state = {
		Arena = arena,
		Boss = boss,
		Humanoid = humanoid,
		Root = root,
		Trigger = trigger,
		Definition = definition,
		Active = false,
		Completed = false,
		NextAttackAt = 0,
		OnDefeated = options.OnDefeated,
	}
	activeState = state
	trigger.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			activate(state)
		end
	end)
	humanoid.Died:Connect(function()
		if state.Completed then
			return
		end
		state.Completed = true
		state.Boss:SetAttribute("BossActive", false)
		CollectionService:RemoveTag(state.Boss, "CombatTarget")
		if state.OnDefeated then
			task.spawn(state.OnDefeated, state.Boss)
		end
	end)
	startAI(state)
	workspace:SetAttribute("DungeonPhaseState", "BossReady")
	return state
end

function BossService.Stop()
	if not activeState then
		return
	end
	activeState.Completed = true
	activeState.Humanoid:MoveTo(activeState.Root.Position)
	activeState.Boss:SetAttribute("BossActive", false)
end

return BossService
