local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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
local freezeShatterTokens = {}
local slowFieldSerials = {}
local scanAccumulator = 0

local function serverTime()
	return workspace:GetServerTimeNow()
end

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

local function createFallbackOrb(assetName, orbDefinition)
	local model = Instance.new("Model")
	model.Name = assetName
	model:SetAttribute("GeneratedOrbFallback", true)
	local part = Instance.new("Part")
	part.Name = "OrbCore"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.15, 1.15, 1.15)
	part.Material = Enum.Material.Neon
	part.Color = orbDefinition.LaserColor
	part.Parent = model
	local light = Instance.new("PointLight")
	light.Name = "OrbLight"
	light.Color = orbDefinition.LaserColor
	light.Brightness = 1.6
	light.Range = 8
	light.Shadows = false
	light.Parent = part
	model.PrimaryPart = part
	return model
end

local function getOrbAssets()
	local assets = ServerStorage:FindFirstChild("OrbAssets")
	if assets then
		return assets
	end
	assets = Instance.new("Folder")
	assets.Name = "OrbAssets"
	assets.Parent = ServerStorage
	return assets
end

local function getOrbTemplate(orbName, orbDefinition)
	local assetName = orbDefinition.AssetName or (orbName .. "Orb")
	local assets = getOrbAssets()
	local template = assets:FindFirstChild(assetName)
	if template and getOrbRoot(template) then
		return template, assetName
	end
	if template then
		warn(string.format("[OrbCombat] %s sem BasePart; usando reserva.", assetName))
		return createFallbackOrb(assetName, orbDefinition), assetName
	end
	template = createFallbackOrb(assetName, orbDefinition)
	template.Parent = assets
	warn(string.format("[OrbCombat] %s nao encontrado; modelo de reserva criado.", assetName))
	return template, assetName
end

local function positionOrb(orb, root, angle, radiusOffset)
	local radius = ORBIT_RADIUS + (radiusOffset or 0)
	local position = root.Position + Vector3.new(math.cos(angle) * radius, ORBIT_HEIGHT, math.sin(angle) * radius)
	local cframe = CFrame.lookAt(position, root.Position + Vector3.new(0, ORBIT_HEIGHT, 0))
	if orb:IsA("Model") then
		orb:PivotTo(cframe)
	elseif orb:IsA("BasePart") then
		orb.CFrame = cframe
	end
end

local function getOwnedOrbs(player)
	local result = {}
	local maxEquipped = OrbConfig.MaxEquippedOrbs or 2
	local equippedNames = {}
	local serialized = player:GetAttribute("EquippedOrbs")
	if typeof(serialized) == "string" and serialized ~= "" then
		for orbName in string.gmatch(serialized, "[^,]+") do
			if OrbConfig.GetOrb(orbName) and not equippedNames[orbName] then
				table.insert(equippedNames, orbName)
				equippedNames[orbName] = true
			end
		end
	end
	if #equippedNames == 0 then
		for _, orbName in ipairs(OrbConfig.OrbOrder) do
			if player:GetAttribute(OrbConfig.GetLevelAttribute(orbName)) and #equippedNames < maxEquipped then
				table.insert(equippedNames, orbName)
				equippedNames[orbName] = true
			end
		end
	end
	for _, orbName in ipairs(equippedNames) do
		if #result >= maxEquipped then break end
		local levelAttribute = OrbConfig.GetLevelAttribute(orbName)
		local level = levelAttribute and OrbConfig.CleanLevel(player:GetAttribute(levelAttribute)) or 0
		local definition = OrbConfig.GetOrbAtLevel(orbName, level, player)
		if definition then
			table.insert(result, { Name = orbName, Level = level, Definition = definition })
		end
	end
	return result
end

local function clearOrbVisuals(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrbVisual") == true then
			child:Destroy()
		end
	end
end

local function attachOrbVisuals(player, character)
	clearOrbVisuals(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for index, owned in ipairs(getOwnedOrbs(player)) do
		local template, assetName = getOrbTemplate(owned.Name, owned.Definition)
		local clone = template:Clone()
		clone.Name = assetName
		clone:SetAttribute("OrbVisual", true)
		clone:SetAttribute("OrbType", owned.Name)
		clone:SetAttribute("OrbSlot", index)
		clone.Parent = character
		prepareOrbParts(clone)
		positionOrb(clone, root, (index - 1) * math.pi * 2 / 3, (index - 1) * 0.35)
	end
end

local function clearTimedStatus(model, attributeName, expectedUntil)
	local remaining = math.max(0, expectedUntil - serverTime())
	task.delay(remaining, function()
		if model.Parent and tonumber(model:GetAttribute(attributeName)) == expectedUntil and serverTime() >= expectedUntil then
			model:SetAttribute(attributeName, nil)
		end
	end)
end

local function applyBurn(player, target, humanoid, root, orb)
	if not target or not target.Parent or not humanoid or humanoid.Health <= 0 then
		return
	end
	local duration = math.max(0.1, tonumber(orb.StatusDuration) or 3)
	local interval = math.max(0.2, tonumber(orb.BurnTickInterval) or 0.75)
	local damage = math.max(0, tonumber(orb.BurnDamage) or 2)
	if damage <= 0 then
		damage = math.max(1, tonumber(orb.Damage) or 1) * 0.25
	end
	local token = (tonumber(target:GetAttribute("OrbBurnToken")) or 0) + 1
	local expiresAt = serverTime() + duration
	target:SetAttribute("OrbBurnToken", token)
	target:SetAttribute("OrbBurnUntil", expiresAt)
	target:SetAttribute("OrbStatusEffect", "Burn")
	target:SetAttribute("OrbStatusSourceUserId", player.UserId)
	task.spawn(function()
		while target.Parent and humanoid.Parent and humanoid.Health > 0 and target:GetAttribute("OrbBurnToken") == token and serverTime() < expiresAt do
			task.wait(interval)
			if not target.Parent or not humanoid.Parent or humanoid.Health <= 0 or target:GetAttribute("OrbBurnToken") ~= token or serverTime() > expiresAt + 0.01 then
				break
			end
			DamageService.ApplyEffectDamage(player, { Model = target, Humanoid = humanoid, Root = root }, damage, "Orb_Fire_Burn")
		end
		if target.Parent and target:GetAttribute("OrbBurnToken") == token then
			target:SetAttribute("OrbBurnToken", nil)
			target:SetAttribute("OrbBurnUntil", nil)
			if target:GetAttribute("OrbStatusEffect") == "Burn" then
				target:SetAttribute("OrbStatusEffect", nil)
			end
		end
	end)
end

local function applyNebula(player, character, center, orb)
	local chance = math.clamp(tonumber(orb.NebulaChance) or 0, 0, 1)
	if chance <= 0 or math.random() > chance then
		return
	end
	local radius = math.max(3, tonumber(orb.NebulaRadius) or 3)
	local damage = math.clamp(tonumber(orb.NebulaDamage) or ((tonumber(orb.Damage) or 1) * 3.5), OrbConfig.DamageLimits.Min, OrbConfig.DamageLimits.Max)
	local expiresAt = serverTime() + 0.18
	attackConfirmed:FireAllClients(player, "FireNebula", center, radius, expiresAt)
	for _, victim in ipairs(findNearbyTargets(player, character, center, radius, nil)) do
		DamageService.ApplyEffectDamage(player, victim, damage, "Orb_Fire_Nebula")
	end
end

local function applyFireSpread(player, character, target, humanoid, root, orb)
	local chance = math.clamp(tonumber(orb.BurnSpreadChance) or 0, 0, 1)
	if chance <= 0 or math.random() > chance then
		return
	end
	local spreadRadius = math.max(4, tonumber(orb.AOERadius) or 4)
	for _, victim in ipairs(findNearbyTargets(player, character, root.Position, spreadRadius, target)) do
		if not victim.Model:GetAttribute("OrbBurnSpreadFrom") then
			victim.Model:SetAttribute("OrbBurnSpreadFrom", target:GetDebugId())
			applyBurn(player, victim.Model, victim.Humanoid, victim.Root, orb)
			attackConfirmed:FireAllClients(player, "FireBurnSpread", root.Position + Vector3.new(0, 1, 0), victim.Root.Position + Vector3.new(0, 1, 0))
			task.delay(math.max(0.2, tonumber(orb.StatusDuration) or 3), function()
				if victim.Model.Parent and victim.Model:GetAttribute("OrbBurnSpreadFrom") == target:GetDebugId() then
					victim.Model:SetAttribute("OrbBurnSpreadFrom", nil)
				end
			end)
		end
	end
end

local function applyFreeze(player, target, orb)
	local duration = math.max(0.1, tonumber(orb.StatusDuration) or 1.15)
	local previousUntil = tonumber(target:GetAttribute("OrbFrozenUntil")) or 0
	local expiresAt = math.max(previousUntil, serverTime() + duration)
	target:SetAttribute("OrbFrozenUntil", expiresAt)
	target:SetAttribute("OrbStatusEffect", "Freeze")
	target:SetAttribute("OrbStatusSourceUserId", player.UserId)
	target:SetAttribute("CombatInterruptSerial", (tonumber(target:GetAttribute("CombatInterruptSerial")) or 0) + 1)
	clearTimedStatus(target, "OrbFrozenUntil", expiresAt)
	if tonumber(orb.ShatterDamage) and orb.ShatterDamage > 0 and expiresAt > previousUntil then
		local tokenKey = target:GetDebugId() .. ":" .. player.UserId
		local token = (freezeShatterTokens[tokenKey] or 0) + 1
		freezeShatterTokens[tokenKey] = token
		task.delay(math.max(0, expiresAt - serverTime()) + 0.03, function()
			if freezeShatterTokens[tokenKey] ~= token or not target.Parent then return end
			if serverTime() < (tonumber(target:GetAttribute("OrbFrozenUntil")) or 0) - 0.01 then return end
			local humanoid = target:FindFirstChildOfClass("Humanoid")
			local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
			if humanoid and humanoid.Health > 0 and root and not DamageService.IsFriendly(player, target, CombatConfig.FriendlyFire) then
				DamageService.ApplyDirectHit(player, { Model = target, Humanoid = humanoid, Root = root }, math.clamp(orb.ShatterDamage, OrbConfig.DamageLimits.Min, OrbConfig.DamageLimits.Max), "Orb_Ice_Shatter", false)
				target:SetAttribute("OrbShatterSerial", (tonumber(target:GetAttribute("OrbShatterSerial")) or 0) + 1)
				attackConfirmed:FireAllClients(player, "IceShatter", root.Position + Vector3.new(0, 1, 0), target)
			end
			freezeShatterTokens[tokenKey] = nil
		end)
	end
end

local findNearbyTargets

local function applySlowField(player, character, center, orb)
	local radius = math.max(0, tonumber(orb.SlowFieldRadius) or 0)
	if radius <= 0 then return end
	local duration = math.max(0.5, tonumber(orb.StatusDuration) or 1.15) * 1.5
	local fieldId = player.UserId .. ":" .. tostring(math.floor(serverTime() * 1000))
	slowFieldSerials[fieldId] = true
	local expiresAt = serverTime() + duration
	attackConfirmed:FireAllClients(player, "IceSlowField", center, radius, expiresAt)
	task.spawn(function()
		while slowFieldSerials[fieldId] and serverTime() < expiresAt do
			for _, victim in ipairs(findNearbyTargets(player, character, center, radius, nil)) do
				local untilAt = math.max(tonumber(victim.Model:GetAttribute("OrbSlowedUntil")) or 0, serverTime() + 0.3)
				victim.Model:SetAttribute("OrbSlowedUntil", untilAt)
				victim.Model:SetAttribute("OrbSlowMultiplier", math.clamp((tonumber(orb.SlowMultiplier) or 0.45) * 0.7, 0.1, 1))
				victim.Model:SetAttribute("OrbStatusEffect", "SlowField")
				victim.Model:SetAttribute("OrbStatusSourceUserId", player.UserId)
			end
			task.wait(0.15)
		end
		slowFieldSerials[fieldId] = nil
	end)
end

local function applyShadow(player, target, orb)
	local duration = math.max(0.1, tonumber(orb.StatusDuration) or 2.5)
	local expiresAt = math.max(tonumber(target:GetAttribute("OrbSlowedUntil")) or 0, serverTime() + duration)
	local slowMultiplier = math.clamp(tonumber(orb.SlowMultiplier) or 0.45, 0.1, 1)
	target:SetAttribute("OrbSlowedUntil", expiresAt)
	target:SetAttribute("OrbDisorientedUntil", expiresAt)
	target:SetAttribute("OrbSlowMultiplier", slowMultiplier)
	target:SetAttribute("OrbStatusEffect", "SlowDisorient")
	target:SetAttribute("OrbStatusSourceUserId", player.UserId)
	target:SetAttribute("CombatInterruptSerial", (tonumber(target:GetAttribute("CombatInterruptSerial")) or 0) + 1)
	clearTimedStatus(target, "OrbSlowedUntil", expiresAt)
	clearTimedStatus(target, "OrbDisorientedUntil", expiresAt)
end

local function updateShadowMarkVisual(target, markCount)
	local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	if not root then return end
	local existing = target:FindFirstChild("ShadowMarkVisual")
	if existing then existing:Destroy() end
	if markCount <= 0 then return end
	local marker = Instance.new("Highlight")
	marker.Name = "ShadowMarkVisual"
	marker.FillColor = Color3.fromRGB(170, 75, 255)
	marker.OutlineColor = Color3.fromRGB(235, 190, 255)
	marker.FillTransparency = 0.75
	marker.OutlineTransparency = math.clamp(0.55 - markCount * 0.08, 0.1, 0.55)
	marker.DepthMode = Enum.HighlightDepthMode.Occluded
	marker.Adornee = target
	marker.Parent = target
end

local function getLivingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then return nil, nil end
	return character, root
end

findNearbyTargets = function(player, character, center, radius, excluded)
	local results = {}
	local seen = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		local model = descendant:IsA("Model") and descendant or descendant:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and model ~= character and model ~= excluded and model.Parent then
			seen[model] = true
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if humanoid and humanoid.Health > 0 and root and (root.Position - center).Magnitude <= radius and not Players:GetPlayerFromCharacter(model) and not DamageService.IsFriendly(player, model, CombatConfig.FriendlyFire) then
				table.insert(results, { Model = model, Humanoid = humanoid, Root = root })
			end
		end
	end
	table.sort(results, function(a, b)
		return (a.Root.Position - center).Magnitude < (b.Root.Position - center).Magnitude
	end)
	return results
end

local function fireOrbAttack(player, character, root, owned, visual)
	local orb = owned.Definition
	local orbName = owned.Name
	local key = player.UserId .. ":" .. orbName
	local now = serverTime()
	if now - (lastAttackAt[key] or 0) < (tonumber(orb.Cooldown) or 0.65) then return end
	local targets = findNearbyTargets(player, character, root.Position, tonumber(orb.Range) or 13, nil)
	local target = targets[1]
	if not target then return end
	lastAttackAt[key] = now
	local origin = getOrbRoot(visual) and getOrbRoot(visual).Position or root.Position
	local damage = math.clamp(tonumber(orb.Damage) or 1, OrbConfig.DamageLimits.Min, OrbConfig.DamageLimits.Max)
	DamageService.ApplyDirectHit(player, target, damage, "Orb_" .. orbName, false)
	if orbName == "Fire" then
		applyBurn(player, target.Model, target.Humanoid, target.Root, orb)
		applyFireSpread(player, character, target.Model, target.Humanoid, target.Root, orb)
		applyNebula(player, character, target.Root.Position, orb)
	elseif orbName == "Ice" then
		applyFreeze(player, target.Model, orb)
		applySlowField(player, character, target.Root.Position, orb)
	elseif orbName == "Shadow" then
		applyShadow(player, target.Model, orb)
	end
	attackConfirmed:FireAllClients(player, orbName, origin, target.Root.Position + Vector3.new(0, 1, 0))
end

local function attachIfMissing(player, character, root)
	local ownedOrbs = getOwnedOrbs(player)
	local expected = {}
	for _, owned in ipairs(ownedOrbs) do
		expected[owned.Definition.AssetName or (owned.Name .. "Orb")] = true
	end
	local missing = false
	for assetName in pairs(expected) do
		local visual = character:FindFirstChild(assetName)
		if not visual or visual:GetAttribute("OrbVisual") ~= true then
			missing = true
			break
		end
	end
	if missing then
		attachOrbVisuals(player, character)
	end
end

local function bindPlayer(player)
	local function bindCharacter(character)
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if not root then return end
		task.defer(attachOrbVisuals, player, character)
		task.spawn(function()
			for _ = 1, 60 do
				if not character.Parent then return end
				if #getOwnedOrbs(player) > 0 then attachIfMissing(player, character, root) end
				task.wait(0.5)
			end
		end)
	end
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then bindCharacter(player.Character) end
	for _, attribute in ipairs(OrbConfig.OrbOrder) do
		local levelAttribute = OrbConfig.GetLevelAttribute(attribute)
		player:GetAttributeChangedSignal(levelAttribute):Connect(function()
			if player.Character then attachOrbVisuals(player, player.Character) end
		end)
	end
	for _, attribute in ipairs({ "EquippedOrbs", "EquippedOrb", "EquippedOrb2" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if player.Character then attachOrbVisuals(player, player.Character) end
		end)
	end
	for _, attribute in ipairs({ "OrbChoiceProtected", "DungeonAssistedTransportState", "DungeonTransportActive", "DungeonTransportState", "TransportActive", "TransportState" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if attribute == "OrbChoiceProtected" and player:GetAttribute(attribute) == true then return end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root then
				task.delay(0.15, function()
					if character.Parent and root.Parent and #getOwnedOrbs(player) > 0 then
						attachOrbVisuals(player, character)
					end
				end)
			end
		end)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end

RunService.Heartbeat:Connect(function(deltaTime)
	local angle = os.clock() * ORBIT_SPEED
	scanAccumulator += deltaTime
	local shouldScan = scanAccumulator >= TARGET_SCAN_INTERVAL
	if shouldScan then scanAccumulator = 0 end
	for _, player in ipairs(Players:GetPlayers()) do
		local character, root = getLivingCharacter(player)
		if character and root then
			local ownedOrbs = getOwnedOrbs(player)
			for index, owned in ipairs(ownedOrbs) do
				local assetName = owned.Definition.AssetName or (owned.Name .. "Orb")
				local visual = character:FindFirstChild(assetName)
				if visual and visual:GetAttribute("OrbVisual") == true then
					positionOrb(visual, root, angle + (index - 1) * math.pi * 2 / 3, (index - 1) * 0.35)
					if shouldScan then fireOrbAttack(player, character, root, owned, visual) end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		lastAttackAt[player.UserId .. ":" .. orbName] = nil
	end
end)

print("[OrbCombat] Multi-Orb automatic attack ready")