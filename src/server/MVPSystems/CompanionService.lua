-- Companheiros capturados ao derrotar monstros. O servidor controla captura,
-- equipe, upgrades, movimento, permissao de alvo e dano.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")
local MarketplaceService = game:GetService("MarketplaceService")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local DeveloperProductService = require(script.Parent:WaitForChild("DeveloperProductService"))
local MarketingOfferService = require(script.Parent:WaitForChild("MarketingOfferService"))
local TradeService = require(script.Parent:WaitForChild("TradeService"))
local SlimeVariants = require(script.Parent.Parent.BlockParkour:WaitForChild("SlimeVariants"))
local SlimeAnimator = require(script.Parent.Parent.BlockParkour:WaitForChild("SlimeAnimator"))
local CompanionCombat = require(script.Parent.Parent.MonsterSystem.CompanionCombat)
local MonsterConfig = require(script.Parent.Parent.MonsterSystem.MonsterConfig)
local MonsterAnimationLoader = require(script.Parent.Parent.MonsterSystem.MonsterAnimationLoader)
local GameplayAnalytics = require(script.Parent.Parent:WaitForChild("GameplayAnalyticsService"))
local RuntimeFolders = require(script.Parent.Parent.DungeonRuntime:WaitForChild("RuntimeFolders"))

local CompanionService = {}
local THINK_INTERVAL = 0.15
local COMPANION_GROUP = "MVPMonsters"
local FALLBACK_FLOOR_Y = -150
local FOLLOW_REPATH_INTERVAL = 0.7
local FOLLOW_WAYPOINT_REACHED_DISTANCE = 2.5
local FOLLOW_DESTINATION_CHANGED_DISTANCE = 3
local FOLLOW_GROUND_PROBE_HEIGHT = 8
local FOLLOW_GROUND_PROBE_DEPTH = 18
local FOLLOW_DIRECT_SAMPLE_SPACING = 2.5
local FOLLOW_MAX_PATH_POINTS = 48
local FOLLOW_PATH_FAILURE_TELEPORT_DELAY = 0.65
local FOLLOW_FALL_RECOVERY_TIME = 0.7
local FOLLOW_STOP_DISTANCE = 2.2
local FOLLOW_JUMP_TRIGGER_DISTANCE = 5.5
local FOLLOW_JUMP_RETRY_INTERVAL = 0.35
local FOLLOW_JUMP_COMMIT_TIME = 0.85
local FOLLOW_JUMP_LANDING_DISTANCE = 3
local FOLLOW_JUMP_FAILURE_DELAY = 1.35
local FOLLOW_JUMP_SAMPLE_SPACING = 1.25
local FOLLOW_STEP_HEIGHT = 1.6

local FORMATION_OFFSETS = {
	Vector3.new(3.5, 0, 3.8),
	Vector3.new(-3.5, 0, 3.8),
	Vector3.new(5.4, 0, 6.7),
	Vector3.new(-5.4, 0, 6.7),
}

local active = setmetatable({}, { __mode = "k" })
local lastMutationAt = setmetatable({}, { __mode = "k" })
local lastRenameAt = setmetatable({}, { __mode = "k" })
local started = false
local event
local request
local elapsed = 0
local random = Random.new()

local function horizontalDistance(left, right)
	local offset = left - right
	return Vector2.new(offset.X, offset.Z).Magnitude
end

local function ensureRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = name
		existing.Parent = ReplicatedStorage
	end
	return existing
end

local function xpRequired(level)
	return CompanionCatalog.GetXPRequired(level)
end

local function monsterFolder()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	return assets and assets:FindFirstChild("Monsters")
end

local function findTemplate(monsterId)
	local folder = monsterFolder()
	if not folder then
		return nil
	end
	local slimeFallback
	for _, template in ipairs(folder:GetChildren()) do
		if template:IsA("Model") then
			local id = template:GetAttribute("MonsterId") or template.Name
			if id == monsterId or template.Name == monsterId then
				return template
			end
			if not slimeFallback and string.find(monsterId, "Slime$") and SlimeVariants.IsSlime(template) then
				slimeFallback = template
			end
		end
	end
	return slimeFallback
end

local function createFallback(monsterId)
	local model = Instance.new("Model")
	model.Name = "Companion_" .. monsterId
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(2.4, 2.4, 2.4)
	root.Material = Enum.Material.SmoothPlastic
	root.Color = Color3.fromRGB(95, 211, 137)
	root.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 12
	humanoid.HipHeight = 0
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function getSpeciesDisplayName(monsterId, template)
	local slimeVariant = string.match(monsterId, "^(%a+)Slime$")
	local slimeDefinition = slimeVariant and SlimeVariants.GetDefinition(slimeVariant)
	if slimeDefinition and type(slimeDefinition.DisplayName) == "string" then
		return slimeDefinition.DisplayName
	end
	if template then
		local attributeName = template:GetAttribute("DisplayName")
		if type(attributeName) == "string" and attributeName ~= "" then
			return attributeName
		end
		local humanoid = MonsterConfig.GetHumanoid(template)
		if humanoid and humanoid.DisplayName ~= "" and humanoid.DisplayName ~= "Humanoid" then
			return humanoid.DisplayName
		end
	end
	local catalogEntry = CompanionCatalog.Get(monsterId)
	return catalogEntry and catalogEntry.DisplayName or monsterId
end

local function getTemplateMetadata(monsterId)
	local template = findTemplate(monsterId)
	local imageValue = template and template:GetAttribute("CompanionImageId") or nil
	return template,
		CompanionCatalog.GetImageId(monsterId, imageValue),
		getSpeciesDisplayName(monsterId, template)
end

local function computedEntryStats(monsterId, record)
	local template = findTemplate(monsterId)
	if not template then
		template = createFallback(monsterId)
	end
	local stats = CompanionCombat.GetStats(template, monsterId, record.Level, record.Upgrades)
	if template.Parent == nil and string.sub(template.Name, 1, 10) == "Companion_" then
		template:Destroy()
	end
	return {
		Damage = math.floor(stats.Damage * 10 + 0.5) / 10,
		AttackCooldown = math.floor(stats.AttackCooldown * 100 + 0.5) / 100,
		WalkSpeed = math.floor(stats.WalkSpeed * 10 + 0.5) / 10,
		AttackRange = math.floor(stats.AttackRange * 10 + 0.5) / 10,
		Style = stats.Behavior,
	}
end

function CompanionService.GetSnapshot(player)
	local companions, equipped = PlayerDataService.GetCompanions(player)
	local equipSlots = PlayerDataService.GetCompanionEquipSlots(player)
	local equippedSlots = {}
	for slot, instanceId in ipairs(equipped) do
		equippedSlots[instanceId] = slot
	end
	local entries = {}
	for instanceId, record in pairs(companions) do
		local speciesId = record.SpeciesId
		local _, imageId, speciesName = getTemplateMetadata(speciesId)
		local spentPoints = CompanionCatalog.SpentPoints(record.Upgrades)
		table.insert(entries, {
			-- MonsterId permanece como o identificador selecionável para manter a
			-- interface antiga compatível. SpeciesId identifica o tipo do slime.
			MonsterId = instanceId,
			InstanceId = instanceId,
			SpeciesId = speciesId,
			DisplayName = record.DisplayName,
			SpeciesName = speciesName,
			ImageId = imageId,
			Level = record.Level,
			XP = record.XP,
			XPRequired = xpRequired(record.Level),
			Kills = record.Kills,
			Equipped = equippedSlots[instanceId] ~= nil,
			Slot = equippedSlots[instanceId],
			UpgradePoints = math.max(0, record.Level - 1 - spentPoints),
			Upgrades = table.clone(record.Upgrades),
			Stats = computedEntryStats(speciesId, record),
		})
	end
	table.sort(entries, function(a, b)
		if a.Equipped ~= b.Equipped then
			return a.Equipped
		end
		if a.Equipped and b.Equipped and a.Slot ~= b.Slot then
			return a.Slot < b.Slot
		end
		if a.Level ~= b.Level then
			return a.Level > b.Level
		end
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	return {
		Entries = entries,
		EquippedCompanions = equipped,
		MaxEquipped = equipSlots,
		MaximumEquipSlots = CompanionCatalog.MaxEquipped,
		NextSlotCoinPrice = CompanionCatalog.GetEquipSlotCoinPrice(equipSlots + 1),
		SlotProductConfigured = CompanionCatalog.EquipSlotDeveloperProductId > 0,
		StoredCount = #entries,
		MaximumStored = CompanionCatalog.MaximumStored,
		MaxLevel = CompanionCatalog.MaxLevel,
		UpgradeOrder = CompanionCatalog.UpgradeOrder,
		UpgradeDefinitions = CompanionCatalog.Upgrades,
	}
end

local function push(player, message, success)
	if event and player.Parent == Players then
		event:FireClient(player, {
			Action = "Update",
			Snapshot = CompanionService.GetSnapshot(player),
			Message = message,
			Success = success ~= false,
		})
	end
end

local function addNameplate(model, root, displayName, level, slot)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CompanionNameplate"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(145, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, math.max(2.2, model:GetExtentsSize().Y * 0.55 + 0.5), 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("%d · %s  Nv.%d", slot, displayName, level)
	label.TextColor3 = Color3.fromRGB(173, 255, 203)
	label.TextStrokeColor3 = Color3.fromRGB(13, 36, 24)
	label.TextStrokeTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui
	return label
end

local function destroyState(state)
	if state and state.Model then
		state.AttackSerial += 1
		if state.IsSlime then
			SlimeAnimator.Stop(state.Model)
		else
			MonsterAnimationLoader.Stop(state.Model)
		end
		state.Model:Destroy()
	end
end

local function destroyActive(player)
	local states = active[player]
	active[player] = nil
	if states then
		for _, state in ipairs(states) do
			destroyState(state)
		end
	end
end

local function ownerCharacter(player)
	if player:GetAttribute("IsDowned") == true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil
end

local function followPosition(ownerRoot, slot)
	local offset = FORMATION_OFFSETS[slot] or FORMATION_OFFSETS[1]
	return (ownerRoot.CFrame * CFrame.new(offset)).Position
end

local function isUnsafeNavigationSurface(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") then
			if
				current:GetAttribute("IsCompanion") == true
				or CollectionService:HasTag(current, "CombatTarget")
				or Players:GetPlayerFromCharacter(current) ~= nil
			then
				return true
			end
		end
		current = current.Parent
	end
	return false
end

local function groundAt(state, position, ownerCharacter)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.Model, ownerCharacter }
	params.IgnoreWater = true
	local origin = position + Vector3.new(0, FOLLOW_GROUND_PROBE_HEIGHT, 0)
	local result = workspace:Raycast(
		origin,
		Vector3.new(0, -(FOLLOW_GROUND_PROBE_HEIGHT + FOLLOW_GROUND_PROBE_DEPTH), 0),
		params
	)
	if
		result
		and result.Instance:IsA("BasePart")
		and result.Instance.CanCollide
		and result.Normal.Y >= 0.55
		and not isUnsafeNavigationSurface(result.Instance)
	then
		return result
	end
	return nil
end

local function safeFollowDestination(state, ownerCharacter, ownerRoot)
	local offset = FORMATION_OFFSETS[state.Slot] or FORMATION_OFFSETS[1]
	for _, scale in ipairs({ 1, 0.72, 0.45, 0.25 }) do
		local candidate = (ownerRoot.CFrame * CFrame.new(offset * scale)).Position
		local ground = groundAt(state, candidate, ownerCharacter)
		if ground then
			return ground.Position
		end
	end
	local ownerGround = groundAt(state, ownerRoot.Position, ownerCharacter)
	return ownerGround and ownerGround.Position or nil
end

local function directFollowPathIsSafe(state, ownerCharacter, destination)
	local offset = destination - state.Root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	if horizontal.Magnitude < 0.1 then
		return true
	end
	local startGround = groundAt(state, state.Root.Position, ownerCharacter)
	if not startGround then
		return false
	end
	local previousHeight = startGround.Position.Y
	local maxHeightChange = math.max(4, state.Humanoid.JumpHeight)
	local samples = math.max(1, math.ceil(horizontal.Magnitude / FOLLOW_DIRECT_SAMPLE_SPACING))
	for index = 1, samples do
		local sample = state.Root.Position:Lerp(destination, index / samples)
		local ground = groundAt(state, sample, ownerCharacter)
		if not ground or math.abs(ground.Position.Y - previousHeight) > maxHeightChange then
			return false
		end
		previousHeight = ground.Position.Y
	end
	return true
end

local function segmentNeedsJump(state, ownerCharacter, fromPosition, toPosition)
	local horizontal = Vector3.new(
		toPosition.X - fromPosition.X,
		0,
		toPosition.Z - fromPosition.Z
	)
	if horizontal.Magnitude < 1 then
		return false
	end
	local fromGround = groundAt(state, fromPosition, ownerCharacter)
	local toGround = groundAt(state, toPosition, ownerCharacter)
	if not fromGround or not toGround then
		return false
	end
	if toGround.Position.Y - fromGround.Position.Y > FOLLOW_STEP_HEIGHT then
		return true
	end
	local samples = math.max(2, math.ceil(horizontal.Magnitude / FOLLOW_JUMP_SAMPLE_SPACING))
	for index = 1, samples - 1 do
		local alpha = index / samples
		local sample = fromPosition:Lerp(toPosition, alpha)
		if not groundAt(state, sample, ownerCharacter) then
			return true
		end
	end
	return false
end

local function markRequiredFollowJumps(state, ownerCharacter, points)
	for index = 1, #points - 1 do
		local current = points[index]
		local nextPoint = points[index + 1]
		if
			current.Action ~= Enum.PathWaypointAction.Jump
			and segmentNeedsJump(
				state,
				ownerCharacter,
				current.Position,
				nextPoint.Position
			)
		then
			current.Action = Enum.PathWaypointAction.Jump
		end
	end
end

local function buildFollowPath(state, ownerCharacter, ownerRoot)
	local destination = safeFollowDestination(state, ownerCharacter, ownerRoot)
	if not destination then
		return nil, nil
	end
	local path = PathfindingService:CreatePath({
		AgentRadius = math.clamp(math.max(state.Root.Size.X, state.Root.Size.Z) * 0.45, 1, 4),
		AgentHeight = math.clamp(state.Model:GetExtentsSize().Y, 3, 12),
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 3,
	})
	local success = pcall(path.ComputeAsync, path, state.Root.Position, destination)
	if success and path.Status == Enum.PathStatus.Success then
		local points = {}
		local previousHeight
		for index, waypoint in ipairs(path:GetWaypoints()) do
			if index > FOLLOW_MAX_PATH_POINTS then
				break
			end
			local ground = groundAt(state, waypoint.Position, ownerCharacter)
			if
				not ground
				or previousHeight
					and math.abs(ground.Position.Y - previousHeight)
						> math.max(5, state.Humanoid.JumpHeight + 1)
			then
				table.clear(points)
				break
			end
			previousHeight = ground.Position.Y
			table.insert(points, {
				Position = waypoint.Position,
				Action = waypoint.Action,
			})
		end
		if #points > 0 then
			markRequiredFollowJumps(state, ownerCharacter, points)
			return points, destination
		end
	end
	if directFollowPathIsSafe(state, ownerCharacter, destination) then
		return {
			{
				Position = destination,
				Action = Enum.PathWaypointAction.Walk,
			},
		}, destination
	end
	return nil, destination
end

local function clearFollowNavigation(state)
	state.FollowPath = nil
	state.FollowPathIndex = 1
	state.FollowDestination = nil
	state.NextFollowPathAt = 0
	state.FollowFailureSince = nil
	state.FollowAirborneTime = 0
	state.FollowJumpActive = false
	state.FollowJumpLandingIndex = nil
	state.FollowJumpStartedAt = 0
	state.NextFollowJumpAt = 0
end

local function isTargetingUser(model, userId)
	for _, attributeName in ipairs({
		"AggroUserId",
		"TargetUserId",
		"CombatOwnerUserId",
		"LastDamagedByUserId",
		"LastHitUserId",
	}) do
		local value = model:GetAttribute(attributeName)
		if typeof(value) == "number" and value == userId then
			return true
		end
	end
	local humanoid = MonsterConfig.GetHumanoid(model)
	local creator = humanoid and humanoid:FindFirstChild("creator")
	local player = creator and creator:IsA("ObjectValue") and creator.Value
	return player and player:IsA("Player") and player.UserId == userId or false
end

local function isOwnersEnemy(player, model)
	if
		not model
		or not model:IsA("Model")
		or not model.Parent
		or model:GetAttribute("IsCompanion") == true
		or model:GetAttribute("Invulnerable") == true
		or not CollectionService:HasTag(model, "CombatTarget")
	then
		return false
	end
	local tutorialOwner = model:GetAttribute("TutorialTargetUserId")
	-- O alvo de treino deve continuar sendo resolvido pelo proprio jogador.
	if typeof(tutorialOwner) == "number" then
		return false
	end
	return isTargetingUser(model, player.UserId)
end

local function targetDescriptor(model)
	local humanoid = MonsterConfig.GetHumanoid(model)
	local root = MonsterConfig.GetRoot(model)
	if humanoid and humanoid.Health > 0 and root then
		return {
			Model = model,
			Humanoid = humanoid,
			Root = root,
		}
	end
	return nil
end

local function resolveTarget(player, state, ownerRoot)
	if state.Target and isOwnersEnemy(player, state.Target.Model) then
		local refreshed = targetDescriptor(state.Target.Model)
		if
			refreshed
			and (refreshed.Root.Position - ownerRoot.Position).Magnitude
				<= CompanionCatalog.OwnerCombatRadius
		then
			state.Target = refreshed
			return refreshed
		end
	end
	state.Target = nil
	local bestDistance = state.CombatStats.DetectionRange
	for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if isOwnersEnemy(player, model) then
			local candidate = targetDescriptor(model)
			if candidate then
				local ownerDistance = (candidate.Root.Position - ownerRoot.Position).Magnitude
				local companionDistance = (candidate.Root.Position - state.Root.Position).Magnitude
				if
					ownerDistance <= CompanionCatalog.OwnerCombatRadius
					and companionDistance < bestDistance
				then
					bestDistance = companionDistance
					state.Target = candidate
				end
			end
		end
	end
	return state.Target
end

local function configurePhysicalModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			-- Nunca reativa a IA interna do inimigo: ela poderia escolher o dono.
			descendant.Disabled = true
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			pcall(function()
				descendant.CollisionGroup = COMPANION_GROUP
			end)
		elseif descendant:IsA("BillboardGui") and descendant.Name == "MobHealthBar" then
			descendant:Destroy()
		end
	end
end

local function teleportToOwner(state, ownerCharacter, ownerRoot)
	local groundPosition = safeFollowDestination(state, ownerCharacter, ownerRoot)
	if not groundPosition then
		return false
	end
	local destination = groundPosition + Vector3.new(0, state.GroundOffset, 0)
	local lookAt = ownerRoot.Position + ownerRoot.CFrame.LookVector * 5
	state.Model:PivotTo(CFrame.lookAt(destination, Vector3.new(lookAt.X, destination.Y, lookAt.Z)))
	state.Root.AssemblyLinearVelocity = Vector3.zero
	state.Root.AssemblyAngularVelocity = Vector3.zero
	state.Target = nil
	state.LastPosition = destination
	state.StuckTime = 0
	state.FollowStuckCount = 0
	clearFollowNavigation(state)
	return true
end

local function spawnState(player, instanceId, record, slot)
	local speciesId = record.SpeciesId
	local template = findTemplate(speciesId)
	local model = template and template:Clone() or createFallback(speciesId)
	model.Name = string.format("Companion_%d_%d_%s", player.UserId, slot, speciesId)
	if template and string.find(speciesId, "Slime$") and SlimeVariants.IsSlime(model) then
		local variant = string.match(speciesId, "^(%a+)Slime$")
		if variant and SlimeVariants.GetDefinition(variant) then
			SlimeVariants.ConfigureClone(model, template, random, variant)
		end
	end
	local scale = math.clamp(tonumber(model:GetAttribute("CompanionScale")) or 0.72, 0.3, 1.5)
	pcall(model.ScaleTo, model, scale)
	local root = MonsterConfig.GetRoot(model)
	local humanoid = MonsterConfig.GetHumanoid(model)
	if not root or not humanoid then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root
	model:SetAttribute("IsCompanion", true)
	model:SetAttribute("CompanionOwnerUserId", player.UserId)
	model:SetAttribute("CompanionSlot", slot)
	model:SetAttribute("CompanionInstanceId", instanceId)
	model:SetAttribute("MonsterId", speciesId)
	model:SetAttribute("CompanionLevel", record.Level)
	model:SetAttribute("CompanionDisplayName", record.DisplayName)
	model:SetAttribute("Invulnerable", true)
	model:SetAttribute("AIController", "Companion")
	model:SetAttribute("UseCustomAI", true)
	model:SetAttribute("SimulationActive", true)
	humanoid.MaxHealth = math.max(1, humanoid.MaxHealth)
	humanoid.Health = humanoid.MaxHealth
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	configurePhysicalModel(model)
	CollectionService:AddTag(model, "Companion")
	model.Parent = RuntimeFolders.Get("PlayerObjects")
	local _, _, characterRoot = ownerCharacter(player)
	if characterRoot then
		model:PivotTo(CFrame.new(followPosition(characterRoot, slot)))
	else
		model:PivotTo(CFrame.new(0, -500, 0))
	end
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local isSlime = SlimeVariants.IsSlime(model)
	if isSlime then
		model:SetAttribute("AIState", "Idle")
		model:SetAttribute("IsMoving", false)
		SlimeAnimator.Start(model, humanoid)
	else
		MonsterAnimationLoader.Bind(model, humanoid)
		MonsterAnimationLoader.Play(model, humanoid, "Idle")
	end
	local state = {
		Owner = player,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		InstanceId = instanceId,
		MonsterId = speciesId,
		DisplayName = record.DisplayName,
		Slot = slot,
		Level = record.Level,
		Upgrades = table.clone(record.Upgrades),
		IsSlime = isSlime,
		CombatStats = nil,
		NextAttackAt = 0,
		NextTeleportAt = 0,
		AbilityCooldowns = {},
		AttackSerial = 0,
		Busy = false,
		Target = nil,
		LastMode = "Idle",
		LastPosition = root.Position,
		StuckTime = 0,
		GroundOffset = math.clamp(humanoid.HipHeight + root.Size.Y * 0.5, 0.75, 10),
		FollowPath = nil,
		FollowPathIndex = 1,
		FollowDestination = nil,
		NextFollowPathAt = 0,
		FollowFailureSince = nil,
		FollowAirborneTime = 0,
		FollowStuckCount = 0,
		FollowJumpActive = false,
		FollowJumpLandingIndex = nil,
		FollowJumpStartedAt = 0,
		NextFollowJumpAt = 0,
		FollowJumpPower = math.max(
			0,
			tonumber(model:GetAttribute("CompanionFollowJumpPower")) or 50
		),
		FollowJumpHeight = math.max(
			0,
			tonumber(model:GetAttribute("CompanionFollowJumpHeight")) or 7.2
		),
		IsTargetValid = function(modelToCheck)
			return isOwnersEnemy(player, modelToCheck)
		end,
	}
	state.CombatStats = CompanionCombat.GetStats(model, speciesId, state.Level, state.Upgrades)
	humanoid.WalkSpeed = state.CombatStats.WalkSpeed
	state.NextTeleportAt = workspace:GetServerTimeNow()
		+ (state.CombatStats.TeleportInterval or math.huge)
	state.Nameplate = addNameplate(model, root, record.DisplayName, record.Level, slot)
	if characterRoot then
		teleportToOwner(state, player.Character, characterRoot)
	end
	return state
end

local function spawnRoster(player)
	destroyActive(player)
	local companions, equipped = PlayerDataService.GetCompanions(player)
	local states = {}
	active[player] = states
	for slot, instanceId in ipairs(equipped) do
		local record = companions[instanceId]
		if record then
			local state = spawnState(player, instanceId, record, slot)
			if state then
				table.insert(states, state)
			end
		end
	end
end

function CompanionService.SynchronizeAfterTeleport(player)
	local character, _, ownerRoot = ownerCharacter(player)
	if not character or not ownerRoot then
		return false, "OwnerUnavailable"
	end
	local synchronized = 0
	for _, state in ipairs(active[player] or {}) do
		if state.Model and state.Model.Parent and teleportToOwner(state, character, ownerRoot) then
			synchronized += 1
		end
	end
	player:SetAttribute(
		"CompanionTeleportSerial",
		(tonumber(player:GetAttribute("CompanionTeleportSerial")) or 0) + 1
	)
	return true, synchronized
end

local function setMovementMode(state, mode)
	if state.LastMode == mode or state.Busy then
		return
	end
	state.LastMode = mode
	state.Model:SetAttribute("MonsterState", mode)
	if state.IsSlime then
		state.Model:SetAttribute("AIState", mode == "Walk" and "Chase" or "Idle")
		state.Model:SetAttribute("IsMoving", mode == "Walk")
	else
		MonsterAnimationLoader.Play(state.Model, state.Humanoid, mode == "Walk" and "Walk" or "Idle")
	end
end

local function moveToward(state, destination)
	state.Humanoid.WalkSpeed = state.CombatStats.WalkSpeed
	state.Humanoid:MoveTo(destination)
	setMovementMode(state, "Walk")
end

local function updateStuck(state, dt)
	if state.LastMode ~= "Walk" or state.Busy then
		state.LastPosition = state.Root.Position
		state.StuckTime = 0
		return false, false
	end
	local moved = (state.Root.Position - state.LastPosition).Magnitude
	state.LastPosition = state.Root.Position
	state.StuckTime = moved < 0.12 and state.StuckTime + dt or 0
	if state.StuckTime >= 0.9 then
		state.StuckTime = 0
		return true, false
	end
	return false, moved >= 0.12
end

local function isFollowAirborne(state)
	local humanoidState = state.Humanoid:GetState()
	return state.Humanoid.FloorMaterial == Enum.Material.Air
		or humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.Freefall
end

local function beginFollowJump(state, waypointIndex, now)
	local landingIndex = math.min(waypointIndex + 1, #state.FollowPath)
	local landing = state.FollowPath[landingIndex]
	if state.Humanoid.UseJumpPower then
		state.Humanoid.JumpPower = math.max(
			state.Humanoid.JumpPower,
			state.FollowJumpPower
		)
	else
		state.Humanoid.JumpHeight = math.max(
			state.Humanoid.JumpHeight,
			state.FollowJumpHeight
		)
	end
	state.FollowJumpActive = true
	state.FollowJumpLandingIndex = landingIndex
	state.FollowJumpStartedAt = now
	state.NextFollowJumpAt = now + FOLLOW_JUMP_RETRY_INTERVAL
	state.Humanoid.Jump = true
	state.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	moveToward(state, landing.Position)
end

local function continueFollowJump(state, ownerCharacter, ownerRoot, dt, now)
	if not state.FollowPath or not state.FollowJumpLandingIndex then
		state.FollowJumpActive = false
		return false
	end
	local landing = state.FollowPath[state.FollowJumpLandingIndex]
	if not landing or not groundAt(state, landing.Position, ownerCharacter) then
		state.FollowPath = nil
		state.NextFollowPathAt = 0
		state.FollowJumpActive = false
		state.FollowJumpLandingIndex = nil
		state.FollowFailureSince = state.FollowFailureSince or now
		return false
	end

	local airborne = isFollowAirborne(state)
	local landingDistance = horizontalDistance(state.Root.Position, landing.Position)
	if
		not airborne
		and landingDistance <= FOLLOW_JUMP_LANDING_DISTANCE
		and now - state.FollowJumpStartedAt > 0.2
	then
		state.FollowPathIndex = state.FollowJumpLandingIndex + 1
		state.FollowJumpActive = false
		state.FollowJumpLandingIndex = nil
		state.FollowStuckCount = 0
		state.StuckTime = 0
		return false
	end

	if
		not airborne
		and now >= state.NextFollowJumpAt
		and now - state.FollowJumpStartedAt < FOLLOW_JUMP_COMMIT_TIME
	then
		state.NextFollowJumpAt = now + FOLLOW_JUMP_RETRY_INTERVAL
		state.Humanoid.Jump = true
		state.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
	if
		not airborne
		and landingDistance > FOLLOW_JUMP_LANDING_DISTANCE
		and now - state.FollowJumpStartedAt >= FOLLOW_JUMP_FAILURE_DELAY
	then
		state.FollowPath = nil
		state.NextFollowPathAt = 0
		state.FollowJumpActive = false
		state.FollowJumpLandingIndex = nil
		state.FollowFailureSince = state.FollowFailureSince or now
		state.FollowStuckCount += 1
		if state.FollowStuckCount >= 2 then
			teleportToOwner(state, ownerCharacter, ownerRoot)
			return true
		end
		state.Humanoid:MoveTo(state.Root.Position)
		setMovementMode(state, "Idle")
		return false
	end
	moveToward(state, landing.Position)
	updateStuck(state, dt)
	return true
end

local function followOwner(state, ownerCharacter, ownerRoot, dt, now)
	local desired = followPosition(ownerRoot, state.Slot)
	local nearbyGround = groundAt(state, state.Root.Position, ownerCharacter)
	if
		not nearbyGround
		and state.Humanoid.FloorMaterial == Enum.Material.Air
		and state.Root.AssemblyLinearVelocity.Y < -2
	then
		state.FollowAirborneTime += dt
	else
		state.FollowAirborneTime = 0
	end
	if state.FollowAirborneTime >= FOLLOW_FALL_RECOVERY_TIME then
		teleportToOwner(state, ownerCharacter, ownerRoot)
		return
	end
	if state.FollowJumpActive then
		if continueFollowJump(state, ownerCharacter, ownerRoot, dt, now) then
			return
		end
	end
	if horizontalDistance(state.Root.Position, desired) <= FOLLOW_STOP_DISTANCE then
		state.Humanoid:MoveTo(state.Root.Position)
		setMovementMode(state, "Idle")
		state.FollowPath = nil
		state.FollowDestination = nil
		state.NextFollowPathAt = 0
		state.FollowFailureSince = nil
		state.FollowStuckCount = 0
		return
	end

	local destinationChanged = not state.FollowDestination
		or horizontalDistance(state.FollowDestination, desired)
			>= FOLLOW_DESTINATION_CHANGED_DISTANCE
	if
		not state.FollowJumpActive
		and (
			destinationChanged
			or not state.FollowPath
			or now >= state.NextFollowPathAt
		)
	then
		state.NextFollowPathAt = now + FOLLOW_REPATH_INTERVAL
		state.FollowPath, state.FollowDestination = buildFollowPath(
			state,
			ownerCharacter,
			ownerRoot
		)
		state.FollowPathIndex = 1
		if state.FollowPath then
			state.FollowFailureSince = nil
		else
			state.FollowFailureSince = state.FollowFailureSince or now
		end
	end

	if not state.FollowPath then
		state.Humanoid:MoveTo(state.Root.Position)
		setMovementMode(state, "Idle")
		if
			state.FollowFailureSince
			and now - state.FollowFailureSince >= FOLLOW_PATH_FAILURE_TELEPORT_DELAY
		then
			teleportToOwner(state, ownerCharacter, ownerRoot)
		end
		return
	end

	while state.FollowPathIndex <= #state.FollowPath do
		local waypoint = state.FollowPath[state.FollowPathIndex]
		if
			waypoint.Action == Enum.PathWaypointAction.Jump
			and horizontalDistance(state.Root.Position, waypoint.Position)
				<= FOLLOW_JUMP_TRIGGER_DISTANCE
		then
			break
		end
		if
			horizontalDistance(state.Root.Position, waypoint.Position)
				> FOLLOW_WAYPOINT_REACHED_DISTANCE
		then
			break
		end
		state.FollowPathIndex += 1
	end
	if state.FollowPathIndex > #state.FollowPath then
		state.FollowPath = nil
		state.NextFollowPathAt = 0
		state.Humanoid:MoveTo(state.Root.Position)
		setMovementMode(state, "Idle")
		return
	end

	local waypoint = state.FollowPath[state.FollowPathIndex]
	if not groundAt(state, waypoint.Position, ownerCharacter) then
		state.FollowPath = nil
		state.NextFollowPathAt = 0
		state.FollowFailureSince = state.FollowFailureSince or now
		state.Humanoid:MoveTo(state.Root.Position)
		setMovementMode(state, "Idle")
		return
	end
	if
		waypoint.Action == Enum.PathWaypointAction.Jump
		and horizontalDistance(state.Root.Position, waypoint.Position)
			<= FOLLOW_JUMP_TRIGGER_DISTANCE
	then
		beginFollowJump(state, state.FollowPathIndex, now)
		return
	end
	moveToward(state, waypoint.Position)

	local stuck, madeProgress = updateStuck(state, dt)
	if madeProgress then
		state.FollowStuckCount = 0
	elseif stuck then
		state.FollowStuckCount += 1
		state.FollowPath = nil
		state.NextFollowPathAt = 0
		if state.FollowStuckCount >= 2 then
			teleportToOwner(state, ownerCharacter, ownerRoot)
		end
	end
end

local function updateCompanion(player, state, dt, now)
	if player:GetAttribute("IsDowned") == true then
		if not state.PausedForDowned then
			state.PausedForDowned = true
			state.AttackSerial += 1
			state.Target = nil
			state.Busy = false
			clearFollowNavigation(state)
			state.Humanoid:MoveTo(state.Root.Position)
			setMovementMode(state, "Idle")
		end
		return
	elseif state.PausedForDowned then
		state.PausedForDowned = false
	end
	local ownerModel, ownerHumanoid, ownerRoot = ownerCharacter(player)
	if not ownerRoot or not ownerHumanoid then
		return
	end
	local ownerDistance = (state.Root.Position - ownerRoot.Position).Magnitude
	if ownerDistance > CompanionCatalog.TeleportDistance or state.Root.Position.Y < FALLBACK_FLOOR_Y then
		teleportToOwner(state, ownerModel, ownerRoot)
		return
	end
	if state.Busy then
		state.Humanoid:MoveTo(state.Root.Position)
		return
	end

	local target = resolveTarget(player, state, ownerRoot)
	if target then
		clearFollowNavigation(state)
		state.FollowStuckCount = 0
		local distance = horizontalDistance(state.Root.Position, target.Root.Position)
		local preferred = math.min(state.CombatStats.PreferredDistance, state.CombatStats.AttackRange * 0.85)
		if
			state.CombatStats.Behavior == "GoldenEscape"
			and now >= state.NextTeleportAt
			and (target.Root.Position - ownerRoot.Position).Magnitude <= CompanionCatalog.OwnerCombatRadius
		then
			local direction = ownerRoot.Position - target.Root.Position
			direction = direction.Magnitude > 0.1 and direction.Unit or ownerRoot.CFrame.LookVector
			local destination = target.Root.Position + direction * math.max(3, preferred)
			state.Model:SetAttribute("AIState", "Teleport")
			state.Model:SetAttribute("IsMoving", false)
			state.Model:PivotTo(CFrame.lookAt(destination, target.Root.Position))
			state.NextTeleportAt = now + (state.CombatStats.TeleportInterval or 8)
		elseif state.CombatStats.RetreatDistance > 0 and distance < state.CombatStats.RetreatDistance then
			local away = state.Root.Position - target.Root.Position
			away = away.Magnitude > 0.1 and away.Unit or ownerRoot.CFrame.RightVector
			moveToward(state, state.Root.Position + away * 8)
		elseif distance > preferred + 1 then
			moveToward(state, target.Root.Position)
		else
			state.Humanoid:MoveTo(state.Root.Position)
			setMovementMode(state, "Idle")
		end
		CompanionCombat.TryAttack(state, target, now)
		local stuck = updateStuck(state, dt)
		if stuck then
			state.Humanoid.Jump = true
		end
	else
		followOwner(state, ownerModel, ownerRoot, dt, now)
	end
end

local function refreshState(player, instanceId, record)
	local states = active[player]
	if not states then
		return
	end
	for _, state in ipairs(states) do
		if state.InstanceId == instanceId then
			state.DisplayName = record.DisplayName
			state.Level = record.Level
			state.Upgrades = table.clone(record.Upgrades)
			state.CombatStats = CompanionCombat.GetStats(
				state.Model,
				record.SpeciesId,
				record.Level,
				record.Upgrades
			)
			state.Humanoid.WalkSpeed = state.CombatStats.WalkSpeed
			state.Model:SetAttribute("CompanionLevel", record.Level)
			state.Model:SetAttribute("CompanionDisplayName", record.DisplayName)
			if state.Nameplate and state.Nameplate.Parent then
				state.Nameplate.Text = string.format(
					"%d · %s  Nv.%d",
					state.Slot,
					record.DisplayName,
					record.Level
				)
			end
		end
	end
end

function CompanionService.SetEquipped(player, instanceId, shouldEquip)
	if TradeService.IsCompanionLocked(player, instanceId) then
		return false, "Esse companheiro está bloqueado em uma troca."
	end
	local companions = PlayerDataService.GetCompanions(player)
	local record = companions[instanceId]
	local wasEquipped = PlayerDataService.IsCompanionEquipped(player, instanceId)
	local success, errorMessage = PlayerDataService.SetCompanionEquipped(player, instanceId, shouldEquip)
	if not success then
		return false, errorMessage
	end
	spawnRoster(player)
	task.spawn(PlayerDataService.Save, player, false)
	local message = shouldEquip == false and "Companheiro desequipado!" or "Companheiro equipado!"
	if shouldEquip == true and not wasEquipped then
		GameplayAnalytics.RecordCompanionEquipped(player, record and record.SpeciesId)
	elseif shouldEquip == false and wasEquipped then
		GameplayAnalytics.RecordCompanionUnequipped(player, record and record.SpeciesId)
	end
	push(player, message, true)
	return true, message
end

local function normalizeRequestedName(value)
	if type(value) ~= "string" then
		return nil, "Digite um nome válido."
	end
	value = string.gsub(value, "%c", "")
	value = string.gsub(value, "%s+", " ")
	value = string.match(value, "^%s*(.-)%s*$") or ""
	local length = utf8.len(value)
	if not length or length == 0 then
		return nil, "O nome não pode ficar vazio."
	end
	if length > CompanionCatalog.MaxDisplayNameLength then
		return nil, string.format(
			"O nome pode ter no máximo %d caracteres.",
			CompanionCatalog.MaxDisplayNameLength
		)
	end
	return value
end

local function filterNameForBroadcast(player, requestedName)
	local cleanName, validationError = normalizeRequestedName(requestedName)
	if not cleanName then
		return nil, validationError
	end
	local success, filterResult = pcall(
		TextService.FilterStringAsync,
		TextService,
		cleanName,
		player.UserId,
		Enum.TextFilterContext.PublicChat
	)
	if not success or not filterResult then
		return nil, "Não foi possível verificar o nome agora. Tente novamente."
	end
	local broadcastSuccess, filteredName = pcall(
		filterResult.GetNonChatStringForBroadcastAsync,
		filterResult
	)
	if not broadcastSuccess or type(filteredName) ~= "string" then
		return nil, "Não foi possível verificar o nome agora. Tente novamente."
	end
	filteredName = string.gsub(filteredName, "%s+", " ")
	filteredName = string.match(filteredName, "^%s*(.-)%s*$") or ""
	local withoutCensorship = string.gsub(filteredName, "#", "")
	withoutCensorship = string.gsub(withoutCensorship, "%s", "")
	if filteredName == "" or withoutCensorship == "" then
		return nil, "Escolha outro nome; este foi bloqueado pelo filtro."
	end
	return filteredName
end

function CompanionService.Rename(player, monsterId, requestedName)
	if TradeService.IsCompanionLocked(player, monsterId) then
		return false, "Esse companheiro está bloqueado em uma troca."
	end
	local companions = PlayerDataService.GetCompanions(player)
	if type(monsterId) ~= "string" or not companions[monsterId] then
		return false, "Companheiro inválido."
	end
	if type(PlayerDataService.RenameCompanion) ~= "function" then
		warn(
			"[CompanionService] PlayerDataService incompatível: "
				.. "substitua PlayerDataService_SkyDungeon_V10.lua pela versão com RenameCompanion."
		)
		return false, "Sistema de nomes desatualizado no servidor."
	end
	local filteredName, filterError = filterNameForBroadcast(player, requestedName)
	if not filteredName then
		return false, filterError
	end
	local success, message = PlayerDataService.RenameCompanion(player, monsterId, filteredName)
	if not success then
		return false, message
	end
	local updatedCompanions = PlayerDataService.GetCompanions(player)
	local record = updatedCompanions[monsterId]
	if record then
		refreshState(player, monsterId, record)
	end
	task.spawn(PlayerDataService.Save, player, false)
	message = "Nome do companheiro atualizado!"
	push(player, message, true)
	return true, message
end

function CompanionService.Discard(player, monsterId)
	if TradeService.IsCompanionLocked(player, monsterId) then
		return false, "Esse companheiro está bloqueado em uma troca."
	end
	local companions = PlayerDataService.GetCompanions(player)
	local record = type(monsterId) == "string" and companions[monsterId] or nil
	if not record then
		return false, "Companheiro inválido."
	end
	if type(PlayerDataService.DiscardCompanion) ~= "function" then
		warn(
			"[CompanionService] PlayerDataService incompatível: "
				.. "substitua PlayerDataService_SkyDungeon_V10.lua pela versão com descarte."
		)
		return false, "Sistema de descarte desatualizado no servidor."
	end

	local success, message = PlayerDataService.DiscardCompanion(player, monsterId)
	if not success then
		return false, message
	end

	spawnRoster(player)
	task.spawn(PlayerDataService.Save, player, false)
	message = string.format("%s foi descartado.", record.DisplayName or monsterId)
	push(player, message, true)
	return true, message
end

function CompanionService.Upgrade(player, monsterId, statName)
	if TradeService.IsCompanionLocked(player, monsterId) then
		return false, "Esse companheiro está bloqueado em uma troca."
	end
	local success, message = PlayerDataService.UpgradeCompanionStat(player, monsterId, statName)
	if not success then
		return false, message
	end
	local companions = PlayerDataService.GetCompanions(player)
	local record = companions[monsterId]
	if record then
		refreshState(player, monsterId, record)
	end
	task.spawn(PlayerDataService.Save, player, false)
	local definition = CompanionCatalog.Upgrades[statName]
	GameplayAnalytics.RecordCompanionUpgrade(
		player,
		record and record.SpeciesId or "OtherCompanion",
		statName
	)
	message = string.format("%s melhorado!", definition.DisplayName)
	push(player, message, true)
	return true, message
end

function CompanionService.RecordDefeat(player, monster)
	if not player or player.Parent ~= Players or not monster then
		return
	end
	PlayerDataService.Load(player)
	local _, equippedBefore = PlayerDataService.GetCompanions(player)
	local xp = math.max(1, math.floor(tonumber(monster:GetAttribute("CompanionXPValue")) or 1))
	local progress = PlayerDataService.AddEquippedCompanionsXP(player, xp)
	local firstLevelUp
	for _, result in ipairs(progress) do
		refreshState(player, result.InstanceId, result.Record)
		if result.Leveled and not firstLevelUp then
			firstLevelUp = result.Record
		end
	end

	local monsterId = monster:GetAttribute("MonsterId") or monster.Name
	local monsterHumanoid = MonsterConfig.GetHumanoid(monster)
	local displayName = monster:GetAttribute("DisplayName")
		or (monsterHumanoid and monsterHumanoid.DisplayName)
		or monsterId
	local canUnlock = monster:GetAttribute("CanBecomeCompanion") ~= false
		and CompanionCatalog.IsSupported(monsterId)
	local chance = CompanionCatalog.GetCaptureChance(
		monsterId,
		monster:GetAttribute("IsElite") == true
	)
	player:SetAttribute("LastCompanionCaptureChance", chance)
	player:SetAttribute(
		"LastCompanionCaptureAttemptSerial",
		(tonumber(player:GetAttribute("LastCompanionCaptureAttemptSerial")) or 0) + 1
	)
	local unlocked = false
	if canUnlock and random:NextNumber() <= chance then
		local success, instanceId
		success, unlocked, instanceId = PlayerDataService.UnlockCompanion(player, monsterId, displayName)
		if success and unlocked and #equippedBefore == 0 then
			spawnRoster(player)
		end
		if unlocked then
			player:SetAttribute("LastCapturedCompanionInstanceId", instanceId)
			MarketingOfferService.Record(player, "CompanionCaptured", 1)
			GameplayAnalytics.RecordCompanionObtained(player, monsterId, "Other")
			if #equippedBefore == 0 then
				GameplayAnalytics.RecordCompanionEquipped(player, monsterId)
			end
		end
	end

	if unlocked then
		push(player, "Novo companheiro: " .. displayName .. "!", true)
	elseif firstLevelUp then
		push(
			player,
			string.format("%s chegou ao nível %d e ganhou 1 ponto!", firstLevelUp.DisplayName, firstLevelUp.Level),
			true
		)
	elseif #progress > 0 then
		push(player)
	end
end

local function buyEquipSlotWithCoins(player)
	if player:GetAttribute("CompanionSlotPurchasePending") == true then
		return false, "Conclua a compra de Robux antes de liberar outro slot."
	end
	local current = PlayerDataService.GetCompanionEquipSlots(player)
	if current >= CompanionCatalog.MaxEquipped then
		return false, "Todos os slots já estão desbloqueados."
	end
	local targetSlot = current + 1
	local price = CompanionCatalog.GetEquipSlotCoinPrice(targetSlot)
	if not price then
		return false, "Preço do próximo slot não configurado."
	end
	local paid, remaining = ScoreService.TrySpendCoins(player, price)
	if not paid then
		return false, string.format("Você precisa de %d moedas.", price)
	end
	local granted, newLimit = PlayerDataService.GrantCompanionEquipSlot(player)
	if not granted then
		ScoreService.RefundCoins(player, price, "CompanionSlotRollback")
		return false, "Não foi possível desbloquear o slot."
	end
	player:SetAttribute("CompanionEquipSlots", newLimit)
	player:SetAttribute("Coins", remaining)
	task.spawn(PlayerDataService.Save, player, false)
	return true, string.format("Slot %d desbloqueado!", newLimit)
end

local function promptEquipSlotProduct(player)
	if player:GetAttribute("CompanionSlotPurchasePending") == true then
		return false, "A compra deste slot ja esta aberta."
	end
	if PlayerDataService.GetCompanionEquipSlots(player) >= CompanionCatalog.MaxEquipped then
		return false, "Todos os slots já estão desbloqueados."
	end
	local productId = math.max(
		0,
		math.floor(tonumber(CompanionCatalog.EquipSlotDeveloperProductId) or 0)
	)
	if productId <= 0 then
		return false, "Configure o Developer Product de slot."
	end
	player:SetAttribute("CompanionSlotPurchasePending", true)
	player:SetAttribute(
		"CompanionSlotPurchaseTarget",
		PlayerDataService.GetCompanionEquipSlots(player) + 1
	)
	local prompted = pcall(
		MarketplaceService.PromptProductPurchase,
		MarketplaceService,
		player,
		productId
	)
	if not prompted then
		player:SetAttribute("CompanionSlotPurchasePending", false)
		player:SetAttribute("CompanionSlotPurchaseTarget", nil)
		return false, "Nao foi possivel abrir a compra."
	end
	return true, "Compra aberta."
end

local function grantPurchasedEquipSlot(player)
	PlayerDataService.Load(player)
	local granted, newLimit = PlayerDataService.GrantCompanionEquipSlot(player)
	player:SetAttribute("CompanionSlotPurchasePending", false)
	player:SetAttribute("CompanionSlotPurchaseTarget", nil)
	if not granted then
		-- As duas interfaces bloqueiam a compra no limite e impedem que moedas
		-- alterem o slot enquanto o prompt esta aberto. Este caso so permanece
		-- como protecao para compras iniciadas fora da interface do jogo.
		warn(string.format(
			"[CompanionService] %s recebeu um recibo de slot ja estando no limite.",
			player.Name
		))
		return true
	end
	player:SetAttribute("CompanionEquipSlots", newLimit)
	push(player, string.format("Slot %d desbloqueado com sucesso!", newLimit), true)
	return true
end

function CompanionService.Start()
	if started then
		return
	end
	started = true
	pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, COMPANION_GROUP)
	event = ensureRemote("RemoteEvent", "CompanionEvent")
	request = ensureRemote("RemoteFunction", "CompanionRequest")
	request.OnServerInvoke = function(player, action, first, second)
		PlayerDataService.Load(player)
		if action ~= "Get" then
			local now = os.clock()
			if now - (lastMutationAt[player] or 0) < 0.15 then
				return {
					Success = false,
					Message = "Aguarde um instante.",
					Snapshot = CompanionService.GetSnapshot(player),
				}
			end
			lastMutationAt[player] = now
		end
		if action == "Rename" then
			local now = os.clock()
			if now - (lastRenameAt[player] or 0) < 2 then
				return {
					Success = false,
					Message = "Aguarde antes de tentar outro nome.",
					Snapshot = CompanionService.GetSnapshot(player),
				}
			end
			lastRenameAt[player] = now
		end
		if action == "Get" then
			return { Success = true, Snapshot = CompanionService.GetSnapshot(player) }
		elseif action == "SetEquipped" and type(first) == "string" and type(second) == "boolean" then
			local success, message = CompanionService.SetEquipped(player, first, second)
			return {
				Success = success,
				Message = message,
				Snapshot = CompanionService.GetSnapshot(player),
			}
		elseif action == "Upgrade" and type(first) == "string" and type(second) == "string" then
			local success, message = CompanionService.Upgrade(player, first, second)
			return {
				Success = success,
				Message = message,
				Snapshot = CompanionService.GetSnapshot(player),
			}
		elseif action == "Rename" and type(first) == "string" and type(second) == "string" then
			local success, message = CompanionService.Rename(player, first, second)
			return {
				Success = success,
				Message = message,
				Snapshot = CompanionService.GetSnapshot(player),
			}
		elseif action == "Discard" and type(first) == "string" and second == true then
			local success, message = CompanionService.Discard(player, first)
			return {
				Success = success,
				Message = message,
				Snapshot = CompanionService.GetSnapshot(player),
			}
		elseif action == "BuySlotCoins" then
			local success, message = buyEquipSlotWithCoins(player)
			return {
				Success = success,
				Message = message,
				Snapshot = CompanionService.GetSnapshot(player),
			}
		elseif action == "BuySlotRobux" then
			local success, message = promptEquipSlotProduct(player)
			return {
				Success = success,
				Message = message,
				Snapshot = CompanionService.GetSnapshot(player),
			}
		end
		return { Success = false, Message = "Pedido inválido." }
	end

	ScoreService.Start()
	DeveloperProductService.Start()
	TradeService.Start()
	DeveloperProductService.Register(
		CompanionCatalog.EquipSlotDeveloperProductId,
		"CompanionEquipSlot",
		grantPurchasedEquipSlot
	)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(
		userId,
		productId,
		purchased
	)
		if productId ~= CompanionCatalog.EquipSlotDeveloperProductId or purchased then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("CompanionSlotPurchasePending", false)
			player:SetAttribute("CompanionSlotPurchaseTarget", nil)
		end
	end)

	local function setup(player)
		PlayerDataService.Load(player)
		player:SetAttribute(
			"CompanionEquipSlots",
			PlayerDataService.GetCompanionEquipSlots(player)
		)
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				if player.Parent == Players then
					spawnRoster(player)
				end
			end)
		end)
		if player.Character then
			task.defer(spawnRoster, player)
		end
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		lastMutationAt[player] = nil
		lastRenameAt[player] = nil
		player:SetAttribute("CompanionSlotPurchasePending", nil)
		player:SetAttribute("CompanionSlotPurchaseTarget", nil)
		destroyActive(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setup, player)
	end
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < THINK_INTERVAL then
			return
		end
		local step = elapsed
		elapsed = 0
		local now = workspace:GetServerTimeNow()
		for player, states in pairs(active) do
			if player.Parent ~= Players then
				destroyActive(player)
				continue
			end
			for _, state in ipairs(states) do
				if state.Model.Parent and state.Root.Parent and state.Humanoid.Health > 0 then
					updateCompanion(player, state, step, now)
				else
					spawnRoster(player)
					break
				end
			end
		end
	end)
end

return CompanionService
