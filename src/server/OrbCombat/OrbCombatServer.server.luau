local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local attackConfirmed = orbFolder:WaitForChild("OrbAttackConfirmed")
local combatFolder = ReplicatedStorage:WaitForChild("SwordCombat")
local CombatConfig = require(combatFolder:WaitForChild("CombatConfig"))
local DamageService = require(script.Parent.Parent:WaitForChild("MVPSystems"):WaitForChild("CombatDamageService"))

local ORBIT_HEIGHT = 4.2
local ORBIT_RADIUS = 2.4
local ORBIT_SPEED = 1.6
local TARGET_SCAN_INTERVAL = 0.08
local lastAttackAt = {}
local scanAccumulator = 0

local function getOrbRoot(orb)
	if orb:IsA("BasePart") then
		return orb
	end
	if orb:IsA("Model") then
		return orb.PrimaryPart or orb:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function prepareOrbParts(orb)
	if orb:IsA("BasePart") then
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanTouch = false
		orb.CanQuery = false
		orb.Massless = true
	end
	for _, descendant in ipairs(orb:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function positionOrb(orb, root, angle)
	local position = root.Position + Vector3.new(
		math.cos(angle) * ORBIT_RADIUS,
		ORBIT_HEIGHT,
		math.sin(angle) * ORBIT_RADIUS
	)
	local cframe = CFrame.lookAt(position, root.Position + Vector3.new(0, ORBIT_HEIGHT, 0))
	if orb:IsA("Model") then
		orb:PivotTo(cframe)
	elseif orb:IsA("BasePart") then
		orb.CFrame = cframe
	end
end

local function attachOrbVisual(player, character)
	local orbName = OrbConfig.NormalizeOrb(player:GetAttribute("EquippedOrb"))
	player:SetAttribute("EquippedOrb", orbName)
	character:SetAttribute("EquippedOrb", orbName)
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrbVisual") == true then
			child:Destroy()
		end
	end
	local assets = ServerStorage:FindFirstChild("OrbAssets")
	local template = assets and assets:FindFirstChild(orbName .. "Orb")
	if not template then
		warn("[OrbCombat] Missing orb template: " .. orbName)
		return
	end
	local clone = template:Clone()
	clone.Name = orbName .. "Orb"
	clone:SetAttribute("OrbVisual", true)
	clone.Parent = character
	local root = character:FindFirstChild("HumanoidRootPart")
	local orbRoot = getOrbRoot(clone)
	if not root or not orbRoot then
		clone:Destroy()
		return
	end
	prepareOrbParts(clone)
	positionOrb(clone, root, 0)
end

local function getLivingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return character, root
end

local function getEquippedOrb(player, character)
	local orbName = OrbConfig.NormalizeOrb(player:GetAttribute("EquippedOrb") or character:GetAttribute("EquippedOrb"))
	local orb = OrbConfig.GetOrb(orbName)
	local visual = character:FindFirstChild(orbName .. "Orb")
	if not visual then
		return nil
	end
	return orbName, orb, visual
end

local function resolveTarget(part, character)
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") and current ~= character then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local root = current:FindFirstChild("HumanoidRootPart") or current.PrimaryPart or current:FindFirstChildWhichIsA("BasePart")
				if root and CollectionService:HasTag(current, CombatConfig.TargetTag) then
					return current, humanoid, root
				end
			end
		end
		current = current.Parent
	end
	return nil
end

local function findTarget(player, character, origin, orb)
	local bestTarget, bestHumanoid, bestRoot, bestDistance
	for _, candidate in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		if candidate:IsA("Model") and candidate:IsDescendantOf(workspace) and candidate ~= character then
			local humanoid = candidate:FindFirstChildOfClass("Humanoid")
			local targetRoot = candidate:FindFirstChild("HumanoidRootPart") or candidate.PrimaryPart or candidate:FindFirstChildWhichIsA("BasePart")
			if humanoid and humanoid.Health > 0 and targetRoot then
				local offset = targetRoot.Position - origin
				local distance = offset.Magnitude
				if distance <= orb.Range and (not bestDistance or distance < bestDistance) and not DamageService.IsFriendly(player, candidate, CombatConfig.FriendlyFire) then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = {character}
					params.IgnoreWater = true
					local result = workspace:Raycast(origin, offset, params)
					local hitModel = result and resolveTarget(result.Instance, character)
					if not result or hitModel == candidate then
						bestTarget, bestHumanoid, bestRoot, bestDistance = candidate, humanoid, targetRoot, distance
					end
				end
			end
		end
	end
	return bestTarget, bestHumanoid, bestRoot
end

local function fireOrbAttack(player, character, root, orbName, orb, visual)
	local orbRoot = getOrbRoot(visual)
	if not orbRoot then
		return
	end
	local now = os.clock()
	if now - (lastAttackAt[player] or -math.huge) < orb.Cooldown then
		return
	end
	local origin = orbRoot.Position
	local target, targetHumanoid, targetRoot = findTarget(player, character, origin, orb)
	if not target then
		return
	end
	lastAttackAt[player] = now
	local damage = math.clamp(orb.Damage, OrbConfig.DamageLimits.Min, OrbConfig.DamageLimits.Max)
	local applied = DamageService.ApplyDirectHit(
		player,
		{Model = target, Humanoid = targetHumanoid, Root = targetRoot},
		damage,
		"Orb_" .. orbName,
		false
	)
	if not applied then
		return
	end
	attackConfirmed:FireAllClients(player, orbName, origin, targetRoot.Position + Vector3.new(0, 1, 0))
end

local function bindPlayer(player)
	if player:GetAttribute("EquippedOrb") == nil then
		player:SetAttribute("EquippedOrb", OrbConfig.DefaultOrb)
	end
	local function bindCharacter(character)
		character:WaitForChild("HumanoidRootPart", 5)
		task.defer(attachOrbVisual, player, character)
	end
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
	player:GetAttributeChangedSignal("EquippedOrb"):Connect(function()
		if player.Character then
			attachOrbVisual(player, player.Character)
		end
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

RunService.Heartbeat:Connect(function(deltaTime)
	local angle = os.clock() * ORBIT_SPEED
	scanAccumulator += deltaTime
	local shouldScan = scanAccumulator >= TARGET_SCAN_INTERVAL
	if shouldScan then
		scanAccumulator = 0
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character, root = getLivingCharacter(player)
		if character and root then
			local orbName, orb, visual = getEquippedOrb(player, character)
			if orbName and visual then
				positionOrb(visual, root, angle)
				if shouldScan then
					fireOrbAttack(player, character, root, orbName, orb, visual)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAttackAt[player] = nil
end)

print("[OrbCombat] Automatic orbit attack ready")