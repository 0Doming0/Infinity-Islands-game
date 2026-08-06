local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ObjectiveSignalBridge = require(script.Parent.ObjectiveSignalBridge)

local ObjectiveActorService = {}

local actorsByEncounter = {}
local encounterTokens = {}

local function normalizedUserSet(raw)
	local result = {}
	if type(raw) == "table" then
		for _, userId in ipairs(raw) do
			local clean = math.floor(tonumber(userId) or 0)
			if clean > 0 then
				result[clean] = true
			end
		end
	end
	return result
end

local function encounterBucket(encounterId)
	local bucket = actorsByEncounter[encounterId]
	if not bucket then
		bucket = setmetatable({}, { __mode = "k" })
		actorsByEncounter[encounterId] = bucket
	end
	return bucket
end

local function registerActor(encounterId, actor)
	encounterBucket(encounterId)[actor] = true
	actor:SetAttribute("ObjectiveEncounterId", encounterId)
	actor.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			local bucket = actorsByEncounter[encounterId]
			if bucket then
				bucket[actor] = nil
			end
		end
	end)
end

local function createHealthBar(model, root, humanoid, title)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ObjectiveActorHealthBar"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(116, 28)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, 0, 0, 14)
	label.BackgroundTransparency = 1
	label.Text = title
	label.TextColor3 = Color3.fromRGB(238, 230, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.Parent = billboard

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Position = UDim2.fromOffset(5, 17)
	background.Size = UDim2.new(1, -10, 0, 8)
	background.BackgroundColor3 = Color3.fromRGB(27, 20, 35)
	background.BorderSizePixel = 0
	background.ClipsDescendants = true
	background.Parent = billboard
	Instance.new("UICorner", background).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(183, 91, 255)
	fill.BorderSizePixel = 0
	fill.Parent = background
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local function update()
		fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1), 1)
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
end

local function setRouteAttributes(instance, definition)
	instance:SetAttribute("ObjectiveId", definition.Id)
	instance:SetAttribute("GlobalIslandIndex", definition.GlobalIslandIndex)
	instance:SetAttribute("RouteRoundIndex", definition.RoundIndex)
	instance:SetAttribute("RouteIslandIndex", definition.IslandIndex)
end

local function createNestVisual(model, root)
	local podOffsets = {
		Vector3.new(1.9, 1.1, 0.7),
		Vector3.new(-1.6, 1.0, 1.2),
		Vector3.new(0.4, 1.2, -1.8),
	}
	for index, offset in ipairs(podOffsets) do
		local pod = Instance.new("Part")
		pod.Name = string.format("SlimePod_%02d", index)
		pod.Shape = Enum.PartType.Ball
		pod.Size = Vector3.new(1.7, 1.7, 1.7)
		pod.CFrame = root.CFrame * CFrame.new(offset)
		pod.Anchored = true
		pod.CanCollide = false
		pod.CanTouch = false
		pod.CanQuery = false
		pod.Material = Enum.Material.Neon
		pod.Color = index == 2 and Color3.fromRGB(91, 153, 255) or Color3.fromRGB(101, 232, 116)
		pod.Parent = model
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "NestOutline"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(215, 124, 255)
	highlight.OutlineTransparency = 0.08
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
end

function ObjectiveActorService.CreateNest(encounterId, definition, marker, options)
	assert(type(encounterId) == "string" and encounterId ~= "", "EncounterId invalido")
	assert(type(definition) == "table", "Definicao de objetivo invalida")
	assert(marker and marker:IsA("BasePart"), "Marcador de ninho invalido")
	options = type(options) == "table" and options or {}
	local model = Instance.new("Model")
	model.Name = "ObjectiveNest_" .. tostring(options.Index or 1)
	model:SetAttribute("ObjectiveActorType", "Nest")
	model:SetAttribute("MonsterRole", "Nest")
	model:SetAttribute("RuntimeMonster", false)
	model:SetAttribute("ObjectiveTargetCompleted", false)
	model:SetAttribute("NoKnockback", true)
	model:SetAttribute("CanBeKnockedBack", false)
	model:SetAttribute("CanBeStunned", false)
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("SimulationActive", true)
	setRouteAttributes(model, definition)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(6.2, 3.5, 6.2)
	root.CFrame = marker.CFrame * CFrame.new(0, 1.55, 0)
	root.Anchored = true
	root.CanCollide = true
	root.CanTouch = false
	root.CanQuery = true
	root.Material = Enum.Material.Slate
	root.Color = Color3.fromRGB(80, 49, 91)
	root.Parent = model
	setRouteAttributes(root, definition)

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = math.max(1, math.floor(tonumber(options.MaxHealth) or 100))
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayName = "Ninho de Slime"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	model.PrimaryPart = root
	createNestVisual(model, root)
	createHealthBar(model, root, humanoid, "NINHO DE SLIME")

	local parent = options.Parent
		or (marker:FindFirstAncestorWhichIsA("Model"))
		or workspace
	model.Parent = parent
	CollectionService:AddTag(model, "CombatTarget")
	CollectionService:AddTag(model, "DungeonObjectiveTarget")
	CollectionService:AddTag(model, "DungeonSlimeNest")
	registerActor(encounterId, model)

	local destroyed = false
	humanoid.Died:Connect(function()
		if destroyed then
			return
		end
		destroyed = true
		model:SetAttribute("ObjectiveTargetCompleted", true)
		model:SetAttribute("SimulationActive", false)
		root.CanCollide = false
		ObjectiveSignalBridge.Report("NestDestroyed", {
			Target = model,
			GlobalIslandIndex = definition.GlobalIslandIndex,
			Amount = 1,
			SourceUserId = model:GetAttribute("LastDamagedByUserId"),
		})
		if type(options.OnDestroyed) == "function" then
			task.defer(options.OnDestroyed, model)
		end
		task.delay(0.65, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	local spawnInterval = math.max(2, tonumber(options.SpawnInterval) or 8)
	if type(options.OnSpawnRequested) == "function" then
		task.spawn(function()
			while model.Parent and humanoid.Health > 0 and encounterTokens[encounterId] == options.Token do
				task.wait(spawnInterval)
				if model.Parent
					and humanoid.Health > 0
					and model:GetAttribute("SimulationActive") ~= false
					and encounterTokens[encounterId] == options.Token
				then
					options.OnSpawnRequested(model)
				end
			end
		end)
	end
	return model
end

local function createBeaconVisual(model, center, radius)
	local base = Instance.new("Part")
	base.Name = "BeaconBase"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(1.2, 5.5, 5.5)
	base.CFrame = center.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = true
	base.CanTouch = false
	base.CanQuery = true
	base.Material = Enum.Material.Metal
	base.Color = Color3.fromRGB(77, 67, 112)
	base.Parent = model

	local core = Instance.new("Part")
	core.Name = "BeaconCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2.2, 2.2, 2.2)
	core.CFrame = center.CFrame * CFrame.new(0, 3.1, 0)
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(143, 103, 255)
	core.Parent = model

	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Color = core.Color
	light.Brightness = 2
	light.Range = radius + 6
	light.Parent = core

	local zone = Instance.new("Part")
	zone.Name = "BeaconHoldZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(0.3, radius * 2, radius * 2)
	zone.CFrame = center.CFrame * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90))
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.CastShadow = false
	zone.Material = Enum.Material.ForceField
	zone.Color = Color3.fromRGB(133, 99, 255)
	zone.Transparency = 0.72
	zone.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BeaconProgressBillboard"
	billboard.Adornee = core
	billboard.Size = UDim2.fromOffset(170, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 110
	billboard.Parent = model
	local text = Instance.new("TextLabel")
	text.Name = "Progress"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(27, 22, 50)
	text.BackgroundTransparency = 0.18
	text.BorderSizePixel = 0
	text.TextColor3 = Color3.fromRGB(235, 229, 255)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.Text = "MANTENHA O FAROL"
	text.Parent = billboard
	Instance.new("UICorner", text).CornerRadius = UDim.new(0, 8)
	return core, zone, text
end

local function eligiblePlayersInside(position, radius, participantSet)
	local occupants = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if participantSet[player.UserId]
			and player:GetAttribute("DungeonEliminated") ~= true
			and player:GetAttribute("IsDowned") ~= true
		then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local offset = root.Position - position
				local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
				if horizontal <= radius and math.abs(offset.Y) <= 10 then
					table.insert(occupants, player)
				end
			end
		end
	end
	return occupants
end

function ObjectiveActorService.CreateBeacon(encounterId, definition, marker, options)
	assert(type(encounterId) == "string" and encounterId ~= "", "EncounterId invalido")
	assert(type(definition) == "table", "Definicao de objetivo invalida")
	assert(marker and marker:IsA("BasePart"), "Marcador de beacon invalido")
	options = type(options) == "table" and options or {}
	local radius = math.max(6, tonumber(options.Radius) or 13)
	local target = math.max(1, math.floor(tonumber(options.Target) or definition.Target or 20))
	local initialProgress = math.clamp(math.floor(tonumber(options.InitialProgress) or 0), 0, target)
	local participantSet = normalizedUserSet(options.ParticipantUserIds)

	local model = Instance.new("Model")
	model.Name = "ObjectiveBeacon"
	model:SetAttribute("ObjectiveActorType", "Beacon")
	model:SetAttribute("ObjectiveTargetCompleted", false)
	model:SetAttribute("BeaconRadius", radius)
	model:SetAttribute("BeaconTargetSeconds", target)
	model:SetAttribute("BeaconHeldSeconds", initialProgress)
	model:SetAttribute("BeaconOccupantCount", 0)
	model:SetAttribute("SimulationActive", true)
	setRouteAttributes(model, definition)
	local core, _, text = createBeaconVisual(model, marker, radius)
	model.PrimaryPart = core
	local parent = options.Parent
		or marker:FindFirstAncestorWhichIsA("Model")
		or workspace
	model.Parent = parent
	CollectionService:AddTag(model, "DungeonObjectiveTarget")
	CollectionService:AddTag(model, "DungeonHoldBeacon")
	registerActor(encounterId, model)

	local accumulated = 0
	local progress = initialProgress
	local heartbeat
	heartbeat = RunService.Heartbeat:Connect(function(deltaTime)
		if not model.Parent or encounterTokens[encounterId] ~= options.Token then
			if heartbeat then
				heartbeat:Disconnect()
			end
			return
		end
		if model:GetAttribute("SimulationActive") == false then
			return
		end
		local occupants = eligiblePlayersInside(marker.Position, radius, participantSet)
		model:SetAttribute("BeaconOccupantCount", #occupants)
		model:SetAttribute("BeaconActive", #occupants > 0)
		if #occupants == 0 then
			accumulated = 0
			return
		end
		accumulated += deltaTime
		local wholeSeconds = math.floor(accumulated)
		if wholeSeconds <= 0 then
			return
		end
		accumulated -= wholeSeconds
		local accepted = ObjectiveSignalBridge.Report("BeaconHoldSeconds", {
			Target = model,
			GlobalIslandIndex = definition.GlobalIslandIndex,
			SourceUserId = occupants[1] and occupants[1].UserId or nil,
			Amount = wholeSeconds,
		})
		if accepted then
			progress = math.min(target, progress + wholeSeconds)
			model:SetAttribute("BeaconHeldSeconds", progress)
			text.Text = string.format("FAROL  %d / %d", progress, target)
			if progress >= target then
				model:SetAttribute("ObjectiveTargetCompleted", true)
			end
		end
	end)
	return model
end

function ObjectiveActorService.BeginEncounter(encounterId, token)
	encounterTokens[encounterId] = token
	encounterBucket(encounterId)
end

function ObjectiveActorService.SetEncounterActive(encounterId, active)
	local bucket = actorsByEncounter[encounterId]
	if not bucket then
		return 0
	end
	local changed = 0
	for actor in pairs(bucket) do
		if actor.Parent then
			actor:SetAttribute("SimulationActive", active == true)
			if actor:GetAttribute("ObjectiveActorType") == "Nest" then
				actor:SetAttribute("Invulnerable", active ~= true)
			end
			changed += 1
		end
	end
	return changed
end

function ObjectiveActorService.GetAliveNestCount(encounterId)
	local count = 0
	for actor in pairs(actorsByEncounter[encounterId] or {}) do
		if actor.Parent and actor:GetAttribute("ObjectiveActorType") == "Nest" then
			local humanoid = actor:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid and humanoid.Health > 0 then
				count += 1
			end
		end
	end
	return count
end

function ObjectiveActorService.DestroyEncounter(encounterId)
	encounterTokens[encounterId] = nil
	local bucket = actorsByEncounter[encounterId]
	actorsByEncounter[encounterId] = nil
	if not bucket then
		return 0
	end
	local destroyed = 0
	for actor in pairs(bucket) do
		if actor.Parent then
			actor:Destroy()
			destroyed += 1
		end
	end
	return destroyed
end

function ObjectiveActorService.DestroyAll()
	local ids = {}
	for encounterId in pairs(actorsByEncounter) do
		table.insert(ids, encounterId)
	end
	for _, encounterId in ipairs(ids) do
		ObjectiveActorService.DestroyEncounter(encounterId)
	end
end

return ObjectiveActorService
