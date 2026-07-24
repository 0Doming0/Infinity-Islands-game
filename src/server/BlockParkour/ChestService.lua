-- ChestService Real NormalChest Swap V3
-- Baús comuns, Ilha do Tesouro e revelacao do Mimico.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local MimicAI = require(script.Parent.MimicAI)
local AnimeOutline = require(ServerScriptService.MVPSystems:WaitForChild("AnimeOutline"))

local ChestService = {}
local active = setmetatable({}, { __mode = "k" })

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function createNormalPrototype(folder)
	local model = Instance.new("Model")
	model.Name = "NormalChest"
	model:SetAttribute("PrototypeModel", true)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(3.8, 1.6, 2.8)
	root.Color = Color3.fromRGB(112, 68, 37)
	root.Material = Enum.Material.WoodPlanks
	root.Parent = model
	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(3.9, 0.8, 2.9)
	lid.CFrame = root.CFrame * CFrame.new(0, 1.15, 0)
	lid.Color = Color3.fromRGB(139, 83, 42)
	lid.Material = Enum.Material.WoodPlanks
	lid.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = lid
	weld.Parent = lid
	model.PrimaryPart = root
	model.Parent = folder
	warn("[ChestService] NormalChest de prototipo criado em ServerStorage/MVPAssets/Chests.")
	return model
end

local function createMimicPrototype(folder)
	local model = Instance.new("Model")
	model.Name = "MimicChest"
	model:SetAttribute("PrototypeModel", true)
	model:SetAttribute("MaxHealth", 90)
	model:SetAttribute("AttackDamage", 12)
	local root = Instance.new("Part")
	root.Name = "MimicRoot"
	root.Size = Vector3.new(3.8, 2.8, 3.2)
	root.Color = Color3.fromRGB(100, 54, 34)
	root.Material = Enum.Material.WoodPlanks
	root.Anchored = false
	root.Parent = model
	local mouth = Instance.new("Part")
	mouth.Name = "Mouth"
	mouth.Size = Vector3.new(3.2, 0.35, 0.4)
	mouth.Color = Color3.fromRGB(30, 12, 15)
	mouth.CanCollide = false
	mouth.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = mouth
	weld.Parent = mouth
	local humanoid = Instance.new("Humanoid")
	Instance.new("Animator", humanoid)
	humanoid.Parent = model
	local animations = Instance.new("Folder")
	animations.Name = "Animations"
	animations.Parent = model
	local main = Instance.new("Animation")
	main.Name = "Main"
	main.Parent = animations
	model.PrimaryPart = root
	model.Parent = folder
	warn("[ChestService] MimicChest de prototipo criado; substitua pelo modelo em ServerStorage/MVPAssets/Chests/MimicChest.")
	return model
end

local function getTemplates()
	local assets = ensureFolder(ServerStorage, "MVPAssets")
	local folder = ensureFolder(assets, "Chests")
	local normal = folder:FindFirstChild("NormalChest")
	local mimic = folder:FindFirstChild("MimicChest")
	if not normal or not normal:IsA("Model") then
		normal = createNormalPrototype(folder)
	end
	if not mimic or not mimic:IsA("Model") then
		mimic = createMimicPrototype(folder)
	end
	return normal, mimic
end

local function getRoot(model, mimic)
	local root = mimic and model:FindFirstChild("Cube.002", true)
		or mimic and model:FindFirstChild("MimicRoot", true)
		or mimic and model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Root", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function prepare(model, anchored, preserveScripts, preserveAnchoring)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			-- The custom MimicChest owns its animation scripts. Keep their original
			-- Enabled/Disabled state; ordinary chest templates remain inert.
			if not preserveScripts then
				descendant.Disabled = true
			end
		elseif descendant:IsA("BasePart") then
			if not preserveAnchoring then
				descendant.Anchored = anchored
			end
			descendant.CanTouch = false
			descendant.CanQuery = true
			if not anchored then
				pcall(function()
					descendant.CollisionGroup = "MVPMonsters"
				end)
			end
		end
	end
end

local function alignBottom(model, surfacePosition, yaw)
	model:PivotTo(CFrame.identity)
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	model:PivotTo(CFrame.new(surfacePosition.X, surfacePosition.Y - bottom + 0.08, surfacePosition.Z)
		* CFrame.Angles(0, yaw, 0))
end

local function isFarEnough(record, selected)
	for _, other in ipairs(selected) do
		local flat = Vector2.new(record.SurfacePosition.X - other.SurfacePosition.X, record.SurfacePosition.Z - other.SurfacePosition.Z)
		if flat.Magnitude < MVPConfig.Chests.MinimumChestSpacing then
			return false
		end
	end
	return true
end

local function selectCells(cells, amount, random)
	local candidates = table.clone(cells)
	for index = #candidates, 2, -1 do
		local other = random:NextInteger(1, index)
		candidates[index], candidates[other] = candidates[other], candidates[index]
	end
	local selected = {}
	for _, record in ipairs(candidates) do
		if isFarEnough(record, selected) then
			table.insert(selected, record)
			if #selected >= amount then
				break
			end
		end
	end
	return selected
end

local function revealParticles(position, color)
	local part = Instance.new("Part")
	part.Name = "ChestBurst"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Position = position
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.3, 0.55)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(22)
	Debris:AddItem(part, 0.8)
end

local function createDormantMimicDisguise(mimic, normalTemplate, island, pivot)
	if not mimic.Parent or not normalTemplate or not normalTemplate:IsA("Model") then
		return nil
	end
	local chest = normalTemplate:Clone()
	local root = getRoot(chest, false)
	if not root then
		chest:Destroy()
		return nil
	end
	chest.PrimaryPart = root
	prepare(chest, true, false)
	chest.Name = "NormalChest"
	chest:SetAttribute("IsTreasureChest", true)
	chest:SetAttribute("IsDormantMimicChest", true)
	chest:SetAttribute("Opened", false)
	chest.Parent = island:FindFirstChild("MVPChests") or island
	chest:PivotTo(pivot)
	AnimeOutline.Apply(chest)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WakeMimicPrompt"
	prompt.ActionText = "Abrir"
	prompt.ObjectText = "Bau"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.18
	prompt.MaxActivationDistance = MVPConfig.Chests.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local opening = false
	prompt.Triggered:Connect(function(player)
		if opening or not chest.Parent or not mimic.Parent then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not playerRoot
			or (playerRoot.Position - root.Position).Magnitude > MVPConfig.Chests.PromptDistance + 3
		then
			return
		end
		opening = true
		prompt.Enabled = false
		local revealPosition = root.Position
		local success, reason = MimicAI.Wake(mimic)
		if not success then
			opening = false
			if prompt.Parent then
				prompt.Enabled = true
			end
			warn("[ChestService] Falha ao despertar Mimico: " .. tostring(reason))
			return
		end
		revealParticles(revealPosition, Color3.fromRGB(210, 63, 75))
		if chest.Parent then
			chest:Destroy()
		end
	end)
	return chest
end

local function activateChest(chest, player)
	local state = active[chest]
	if not state or state.Opened or not chest.Parent then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local chestRoot = getRoot(chest, false)
	if not humanoid or humanoid.Health <= 0 or not playerRoot or not chestRoot
		or (playerRoot.Position - chestRoot.Position).Magnitude > MVPConfig.Chests.PromptDistance + 3
	then
		return
	end
	state.Opened = true
	local prompt = chestRoot:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
	local position = chestRoot.Position
	active[chest] = nil

	if not state.IsMimic then
		ScoreService.AwardCoins(player, state.CoinReward, "TreasureChest")
		revealParticles(position, Color3.fromRGB(255, 216, 72))
		chest:SetAttribute("Opened", true)
		for _, descendant in ipairs(chest:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.Transparency = math.max(descendant.Transparency, 0.55)
			end
		end
		Debris:AddItem(chest, 0.45)
		return
	end

	local mimic = state.MimicTemplate:Clone()
	local root = getRoot(mimic, true)
	local humanoidMimic = mimic:FindFirstChildWhichIsA("Humanoid", true)
	if not root or not humanoidMimic then
		warn("[ChestService] MimicChest invalido; recompensa normal entregue.")
		ScoreService.AwardCoins(player, state.CoinReward, "InvalidMimicRefund")
		chest:Destroy()
		return
	end
	mimic.PrimaryPart = root
	-- O rig atual anima os Bones dentro de Cube.002. Preserve a ancoragem do
	-- template; MimicAI assume o movimento cinemático do MeshPart inteiro.
	prepare(mimic, false, true, true)
	mimic.Name = "Monster_MimicChest"
	alignBottom(mimic, state.SurfacePosition, state.Yaw)
	mimic.Parent = state.Island
	chest:Destroy()
	revealParticles(root.Position, Color3.fromRGB(210, 63, 75))
	local success, reason = MimicAI.Activate(mimic, {
		DifficultyTier = state.DifficultyTier,
		CoinReward = state.CoinReward,
		ScoreReward = 15 + state.DifficultyTier * 2,
		NormalChestPivot = state.NormalChestPivot,
		OnDormant = function(mimicModel, normalChestPivot)
			return createDormantMimicDisguise(
				mimicModel,
				state.NormalTemplate,
				state.Island,
				normalChestPivot
			)
		end,
		OnAwake = function(_, disguise)
			if typeof(disguise) == "Instance" and disguise.Parent then
				disguise:Destroy()
			end
		end,
	})
	if not success then
		warn("[ChestService] Falha ao ativar Mimico: " .. tostring(reason))
		mimic:Destroy()
	end
end

local function spawnChest(parent, island, record, index, isMimic, coinReward, random, normalTemplate, mimicTemplate, tier)
	local chest = normalTemplate:Clone()

	local root = getRoot(chest, false)
	if not root then
		chest:Destroy()
		return false
	end
	chest.PrimaryPart = root
	prepare(chest, true, false)
	chest.Name = string.format("Chest_%02d", index)
	chest:SetAttribute("IsTreasureChest", true)
	chest:SetAttribute("Opened", false)
	chest.Parent = parent
	AnimeOutline.Apply(chest)
	local yaw = random:NextNumber(0, math.pi * 2)
	alignBottom(chest, record.SurfacePosition, yaw)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenChestPrompt"
	prompt.ActionText = "Abrir"
	prompt.ObjectText = "Bau"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.18
	prompt.MaxActivationDistance = MVPConfig.Chests.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	active[chest] = {
		Island = island,
		MimicTemplate = mimicTemplate,
		NormalTemplate = normalTemplate,
		NormalChestPivot = chest:GetPivot(),
		SurfacePosition = record.SurfacePosition,
		Yaw = yaw,
		IsMimic = isMimic,
		CoinReward = coinReward,
		DifficultyTier = tier,
		Opened = false,
	}
	prompt.Triggered:Connect(function(player)
		activateChest(chest, player)
	end)
	return true
end

function ChestService.PopulateIsland(island, freeCells, context)
	context = context or {}
	if island:FindFirstChild("ChestSpawnPoints") then
		return 0
	end
	local islandType = island:GetAttribute("IslandType") or "Normal"
	local role = tostring(island:GetAttribute("IslandRole") or "")
	if islandType ~= "Normal" and islandType ~= "Treasure" then
		return 0
	end
	if string.find(role, "Sanctuary", 1, true) then
		return 0
	end
	local seed = math.floor(math.abs((island:GetAttribute("IslandSeed") or context.RoundSeed or 1)
		+ MVPConfig.Chests.RandomSalt)) % 2147483647
	local random = Random.new(seed == 0 and 1 or seed)
	local chanceMultiplier = math.max(0, tonumber(island:GetAttribute("ChestChanceMultiplier")) or 1)
	local normalChance = math.clamp(MVPConfig.Chests.NormalIslandChance * chanceMultiplier, 0, 1)
	if islandType ~= "Treasure" and random:NextNumber() > normalChance then
		return 0
	end

	local desired = islandType == "Treasure"
		and random:NextInteger(MVPConfig.Chests.TreasureMinimumChests, MVPConfig.Chests.TreasureMaximumChests)
		or 1
	local selected = selectCells(freeCells, desired, random)
	if #selected == 0 then
		return 0
	end
	local normalTemplate, mimicTemplate = getTemplates()
	local points = Instance.new("Folder")
	points.Name = "ChestSpawnPoints"
	points.Parent = island
	local folder = Instance.new("Folder")
	folder.Name = "MVPChests"
	folder.Parent = island
	local tier = math.max(1, math.floor(tonumber(island:GetAttribute("DangerLevel")) or 1))
	local mimicCount = 0
	local spawned = 0
	for index, record in ipairs(selected) do
		local isMimic = random:NextNumber() <= MVPConfig.Chests.MimicChance
		if islandType == "Treasure" and mimicCount >= MVPConfig.Chests.TreasureMaximumMimics then
			isMimic = false
		end
		if isMimic then
			mimicCount += 1
		end
		local rewardMultiplier = tonumber(island:GetAttribute("RewardMultiplier")) or 1
		local minimum = isMimic and MVPConfig.Chests.MimicMinimumCoins or MVPConfig.Chests.NormalMinimumCoins
		local maximum = isMimic and MVPConfig.Chests.MimicMaximumCoins or MVPConfig.Chests.NormalMaximumCoins
		local reward = math.floor(random:NextInteger(minimum, maximum) * rewardMultiplier)
		local marker = Instance.new("CFrameValue")
		marker.Name = string.format("Chest_%02d", index)
		marker.Value = CFrame.new(record.SurfacePosition)
		marker:SetAttribute("GridX", record.Cell.X)
		marker:SetAttribute("GridY", record.Cell.Y)
		marker:SetAttribute("GridZ", record.Cell.Z)
		marker.Parent = points
		if spawnChest(folder, island, record, index, isMimic, reward, random, normalTemplate, mimicTemplate, tier) then
			spawned += 1
		else
			marker:Destroy()
		end
	end
	island:SetAttribute("ChestCount", spawned)
	return spawned
end

return ChestService
