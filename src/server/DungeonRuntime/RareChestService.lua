--[[
	Infinity Islands - RareChestService V1

	Spawns rare chests across materialized Combat Islands.

	Important:
	- maximum 2 chest spawns per island;
	- an island already at 2 is excluded from selection;
	- prefers islands that have received fewer chests;
	- cloned legacy chest scripts/prompts are stripped;
	- ScoreValue/CoinValue are forced to zero;
	- reward is physical XP fragments, never coins;
	- uses MobXPCollectibleService.SpawnXPBurst so chest loot behaves exactly
	  like mob-death XP: scatter -> brief pause -> homing -> true character
	  contact -> XP.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.RareChestConfig
)

local XPCollectibleService = require(
	script.Parent.MobXPCollectibleService
)

local AnimeOutline = require(
	ServerScriptService.MVPSystems.AnimeOutline
)

local Service = {}

local started = false
local random = Random.new()
local activeChests = {}
local activeByIsland =
	setmetatable({}, { __mode = "k" })

local lifetimeByIsland =
	setmetatable({}, { __mode = "k" })

-- A janela de mundo pode descarregar e recriar o mesmo Model. Guardar o
-- limite também pelo índice impede que um raro já aberto reapareça ao voltar
-- para a ilha durante a mesma sessão do servidor.
local lifetimeByIslandIndex = {}

local openedSerial = 0
local spawnedSerial = 0

local function cleanIndex(value)
	local number = tonumber(value)

	return number
		and math.floor(number)
		or nil
end

local function islandIndex(island)
	return cleanIndex(
		island:GetAttribute(
			"GlobalIslandIndex"
		)
	)
end

local function islandLevel(island)
	return math.max(
		1,
		math.floor(
			tonumber(
				island:GetAttribute(
					"IslandLevel"
				)
			)
				or tonumber(
					island:GetAttribute(
						"RecommendedLevel"
					)
				)
				or islandIndex(island)
				or 1
		)
	)
end

local function isCombatIsland(model)
	if not model
		or not model:IsA("Model")
		or not model.Parent
		or not model:IsDescendantOf(workspace)
	then
		return false
	end

	local index = islandIndex(model)

	if not index
		or index
			< Config.MinimumGlobalIslandIndex
	then
		return false
	end

	if model:GetAttribute(
		"IsRewardIsland"
	) == true
		or model:GetAttribute(
			"IsBossSanctuary"
		) == true
	then
		return false
	end

	if model:GetAttribute(
		"CombatIsland"
	) == true
		or model:GetAttribute(
			"IsSkyIsland"
		) == true
		or model:GetAttribute(
			"IslandCombatManaged"
		) == true
	then
		return true
	end

	return model:GetAttribute(
		"GlobalIslandIndex"
	) ~= nil
		and model:GetAttribute(
			"IslandLevel"
		) ~= nil
end

local function collectMaterializedIslands()
	local islands = {}

	for _, descendant in ipairs(
		workspace:GetDescendants()
	) do
		if descendant:IsA("Model")
			and isCombatIsland(
				descendant
			)
		then
			table.insert(
				islands,
				descendant
			)
		end
	end

	table.sort(
		islands,
		function(left, right)
			return (
				islandIndex(left)
					or math.huge
			) < (
				islandIndex(right)
					or math.huge
			)
		end
	)

	return islands
end

local function activeCountForIsland(island)
	local bucket =
		activeByIsland[island]

	if not bucket then
		return 0
	end

	local count = 0

	for chest in pairs(bucket) do
		if chest.Parent then
			count += 1
		else
			bucket[chest] = nil
		end
	end

	return count
end

local function lifetimeCountForIsland(island)
	local index = islandIndex(island)

	return math.max(
		0,
		math.floor(
			tonumber(
				index and lifetimeByIslandIndex[index]
					or lifetimeByIsland[island]
			)
				or tonumber(
					island:GetAttribute(
						"RareChestLifetimeSpawnedCount"
					)
				)
				or 0
		)
	)
end

local function publishIslandCount(island)
	local active =
		activeCountForIsland(island)

	local lifetime =
		lifetimeCountForIsland(island)

	island:SetAttribute(
		"RareChestActiveCount",
		active
	)

	island:SetAttribute(
		"RareChestLifetimeSpawnedCount",
		lifetime
	)

	island:SetAttribute(
		"RareChestMaxPerIsland",
		Config.MaximumChestsPerIsland
	)
end

local function unregisterChest(chest)
	local record =
		activeChests[chest]

	if not record then
		return
	end

	activeChests[chest] = nil

	local island =
		record.Island

	local bucket =
		activeByIsland[island]

	if bucket then
		bucket[chest] = nil
	end

	if island and island.Parent then
		publishIslandCount(island)
	end
end

local function getTemplate()
	local exactMatches = {}

	for _, descendant in ipairs(
		ServerStorage:GetDescendants()
	) do
		if descendant:IsA("Model") then
			if descendant:GetAttribute(
				"ChestRarity"
			) == "Rare"
				or descendant:GetAttribute(
					"RareChest"
				) == true
			then
				return descendant
			end

			for priority, name in ipairs(
				Config.TemplateNames
			) do
				if descendant.Name == name then
					table.insert(
						exactMatches,
						{
							Model = descendant,
							Priority = priority,
						}
					)
					break
				end
			end
		end
	end

	table.sort(
		exactMatches,
		function(left, right)
			return left.Priority
				< right.Priority
		end
	)

	return exactMatches[1]
		and exactMatches[1].Model
		or nil
end

local function fallbackChest()
	local model = Instance.new("Model")
	model.Name = "RareChest"

	local base = Instance.new("Part")
	base.Name = "ChestBase"
	base.Size = Vector3.new(4.2, 2.1, 3)
	base.Material = Enum.Material.Wood
	base.Color =
		Color3.fromRGB(
			111,
			67,
			38
		)
	base.Anchored = true
	base.CanCollide = false
	base.Parent = model

	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(4.3, 1.15, 3.05)
	lid.Material = Enum.Material.Wood
	lid.Color =
		Color3.fromRGB(
			145,
			89,
			45
		)
	lid.CFrame =
		base.CFrame
			* CFrame.new(
				0,
				1.6,
				0
			)
	lid.Anchored = true
	lid.CanCollide = false
	lid.Parent = model

	local band = Instance.new("Part")
	band.Name = "GoldBand"
	band.Size = Vector3.new(0.48, 3.2, 3.12)
	band.Material = Enum.Material.Metal
	band.Color =
		Color3.fromRGB(
			255,
			193,
			55
		)
	band.CFrame =
		base.CFrame
			* CFrame.new(
				0,
				0.55,
				0
			)
	band.Anchored = true
	band.CanCollide = false
	band.Parent = model

	model.PrimaryPart = base

	return model
end

local function sanitizeChest(chest)
	for _, descendant in ipairs(
		chest:GetDescendants()
	) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
		then
			descendant:Destroy()

		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = true
			descendant.AssemblyLinearVelocity =
				Vector3.zero
			descendant.AssemblyAngularVelocity =
				Vector3.zero
		end
	end

	chest:SetAttribute(
		"CoinValue",
		0
	)
	chest:SetAttribute(
		"ScoreValue",
		0
	)
	chest:SetAttribute(
		"LegacyChestCoinRewardsDisabled",
		true
	)
	chest:SetAttribute(
		"RareChest",
		true
	)
	chest:SetAttribute(
		"ChestRarity",
		"Rare"
	)
	chest:SetAttribute(
		"ChestRewardPolicy",
		"PhysicalXPCollectiblesV1"
	)
end

local function chestRoot(chest)
	local root =
		chest.PrimaryPart
		or chest:FindFirstChild(
			"ChestBase",
			true
		)
		or chest:FindFirstChild(
			"Base",
			true
		)
		or chest:FindFirstChildWhichIsA(
			"BasePart",
			true
		)

	if root
		and root:IsA("BasePart")
	then
		chest.PrimaryPart = root
		return root
	end

	return nil
end

local function existingChestPositions(island)
	local positions = {}

	local bucket =
		activeByIsland[island]

	if bucket then
		for chest in pairs(bucket) do
			if chest.Parent then
				table.insert(
					positions,
					chest:GetPivot().Position
				)
			end
		end
	end

	return positions
end

local function farEnoughFromExisting(
	position,
	existing
)
	for _, other in ipairs(existing) do
		local flat =
			Vector3.new(
				position.X - other.X,
				0,
				position.Z - other.Z
			)

		if flat.Magnitude
			< Config.MinimumChestSpacing
		then
			return false
		end
	end

	return true
end

local function markerCandidates(island)
	local candidates = {}

	for _, descendant in ipairs(
		island:GetDescendants()
	) do
		local lower =
			string.lower(descendant.Name)

		if string.find(
			lower,
			"chestspawn",
			1,
			true
		)
		then
			if descendant:IsA("BasePart") then
				table.insert(
					candidates,
					descendant.Position
				)
			elseif descendant:IsA("Attachment") then
				table.insert(
					candidates,
					descendant.WorldPosition
				)
			end
		end
	end

	return candidates
end

local function surfacePartCandidates(island)
	local result = {}

	for _, descendant in ipairs(
		island:GetDescendants()
	) do
		if descendant:IsA("BasePart")
			and descendant.CanCollide
			and descendant.Size.X >= 4
			and descendant.Size.Z >= 4
			and descendant.CFrame.UpVector.Y
				>= 0.72
		then
			table.insert(
				result,
				descendant
			)
		end
	end

	return result
end

local function randomPointOnPart(
	part
)
	local inset =
		Config.EdgeInsetRatio

	local x =
		random:NextNumber(
			-part.Size.X
				* (0.5 - inset),
			part.Size.X
				* (0.5 - inset)
		)

	local z =
		random:NextNumber(
			-part.Size.Z
				* (0.5 - inset),
			part.Size.Z
				* (0.5 - inset)
		)

	return part.CFrame:PointToWorldSpace(
		Vector3.new(
			x,
			part.Size.Y * 0.5,
			z
		)
	)
end

local function findPlacement(island)
	local existing =
		existingChestPositions(island)

	local markers =
		markerCandidates(island)

	-- Authored/procedural chest markers have first priority.
	while #markers > 0 do
		local index =
			random:NextInteger(
				1,
				#markers
			)

		local position =
			table.remove(
				markers,
				index
			)

		if farEnoughFromExisting(
			position,
			existing
		) then
			return position
		end
	end

	local surfaces =
		surfacePartCandidates(island)

	if #surfaces == 0 then
		return nil
	end

	for _ = 1,
		Config.PlacementAttempts
	do
		local surface =
			surfaces[
				random:NextInteger(
					1,
					#surfaces
				)
			]

		local position =
			randomPointOnPart(
				surface
			)

		if farEnoughFromExisting(
			position,
			existing
		) then
			return position
		end
	end

	return nil
end

local function pivotBottomTo(
	chest,
	surfacePosition
)
	local pivot =
		chest:GetPivot()

	local box, size =
		chest:GetBoundingBox()

	local bottomY =
		box.Position.Y
			- size.Y / 2

	local offset =
		Vector3.new(
			surfacePosition.X
				- pivot.Position.X,
			surfacePosition.Y
				+ 0.12
				- bottomY,
			surfacePosition.Z
				- pivot.Position.Z
		)

	chest:PivotTo(
		pivot + offset
	)
end

local function createOpenBurst(
	position
)
	local anchor = Instance.new("Part")
	anchor.Name = "RareChestOpenBurst"
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Parent = workspace

	local particles =
		Instance.new(
			"ParticleEmitter"
		)

	particles.Color =
		ColorSequence.new({
			ColorSequenceKeypoint.new(
				0,
				Color3.fromRGB(
					255,
					215,
					80
				)
			),
			ColorSequenceKeypoint.new(
				1,
				Color3.fromRGB(
					100,
					200,
					255
				)
			),
		})

	particles.LightEmission = 1
	particles.Lifetime =
		NumberRange.new(
			0.28,
			0.55
		)
	particles.Speed =
		NumberRange.new(
			8,
			18
		)
	particles.SpreadAngle =
		Vector2.new(
			180,
			180
		)
	particles.Rate = 0
	particles.Parent = anchor
	particles:Emit(28)

	local light =
		Instance.new("PointLight")
	light.Color =
		Color3.fromRGB(
			255,
			205,
			85
		)
	light.Brightness = 4
	light.Range = 14
	light.Shadows = false
	light.Parent = anchor

	Debris:AddItem(
		anchor,
		0.7
	)
end

local function validOpener(
	player,
	chest,
	prompt
)
	if not player
		or player.Parent ~= Players
	then
		return false
	end

	local character = player.Character
	local humanoid =
		character
		and character:FindFirstChildOfClass(
			"Humanoid"
		)
	local root =
		character
		and character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not chest.Parent
	then
		return false
	end

	local distance =
		(
			root.Position
				- chest:GetPivot().Position
		).Magnitude

	return distance
		<= prompt.MaxActivationDistance
			+ 3
end

local function openChest(
	chest,
	record,
	player,
	prompt
)
	if chest:GetAttribute(
		"RareChestOpened"
	) == true
	then
		return
	end
	if player:GetAttribute("PartyId") ~= nil and player:GetAttribute("PartyCoopProgressEligible") ~= true then
		player:SetAttribute("LastPartyCoopRewardDenied", "RareChestRequiresOwnProgression")
		return
	end

	if not validOpener(
		player,
		chest,
		prompt
	) then
		return
	end

	prompt.Enabled = false

	local island =
		record.Island

	local level =
		islandLevel(island)

	local reward =
		Config.GetXPReward(level)

	local position =
		chest:GetPivot().Position
			+ Vector3.new(
				0,
				2.1,
				0
			)

	local success, err =
		XPCollectibleService
			.SpawnXPBurst(
				player,
				position,
				reward,
				{
					SourceId =
						"RareChest",

					MonsterId =
						"RareChest",

					MobLevel =
						level,

					IslandLevel =
						level,

					GlobalIslandIndex =
						islandIndex(island),

					RewardSource =
						"RareChest",
				}
			)

	if not success then
		prompt.Enabled = true

		chest:SetAttribute(
			"RareChestLastOpenError",
			tostring(err)
		)

		return
	end

	chest:SetAttribute(
		"RareChestOpened",
		true
	)
	chest:SetAttribute(
		"RareChestOpenedByUserId",
		player.UserId
	)
	chest:SetAttribute(
		"RareChestXPReward",
		reward
	)
	chest:SetAttribute(
		"RareChestOpenedAt",
		workspace:GetServerTimeNow()
	)

	openedSerial += 1

	player:SetAttribute(
		"LastRareChestXPReward",
		reward
	)
	player:SetAttribute(
		"LastRareChestIslandIndex",
		islandIndex(island)
	)
	player:SetAttribute(
		"RareChestOpenedSerial",
		openedSerial
	)

	workspace:SetAttribute(
		"DungeonRareChestLastOpenedSerial",
		openedSerial
	)
	workspace:SetAttribute(
		"DungeonRareChestLastRewardXP",
		reward
	)

	createOpenBurst(position)

	unregisterChest(chest)

	task.delay(
		Config.OpenDestroyDelay,
		function()
			if chest.Parent then
				chest:Destroy()
			end
		end
	)
end

local function spawnChestOnIsland(island)
	local active =
		activeCountForIsland(island)

	local lifetime =
		lifetimeCountForIsland(island)

	if active
		>= Config.MaximumChestsPerIsland
		or lifetime
			>= Config.MaximumChestsPerIsland
	then
		return false,
			"IslandChestCapReached"
	end

	local position =
		findPlacement(island)

	if not position then
		return false,
			"NoSafeChestPlacement"
	end

	local template =
		getTemplate()

	local chest =
		template
			and template:Clone()
			or fallbackChest()

	chest.Name =
		"RareChest_Runtime"

	sanitizeChest(chest)

	local root =
		chestRoot(chest)

	if not root then
		chest:Destroy()

		return false,
			"InvalidChestTemplate"
	end

	chest.Parent = island

	pivotBottomTo(
		chest,
		position
	)

	local prompt =
		Instance.new(
			"ProximityPrompt"
		)

	prompt.Name =
		"RareChestPrompt"

	prompt.ActionText =
		Config.PromptActionText

	prompt.ObjectText =
		Config.PromptObjectText

	prompt.MaxActivationDistance =
		Config.PromptDistance

	prompt.HoldDuration =
		Config.PromptHoldDuration

	prompt.RequiresLineOfSight =
		false

	prompt.KeyboardKeyCode =
		Enum.KeyCode.E

	prompt.GamepadKeyCode =
		Enum.KeyCode.ButtonX

	-- O ChestPromptController desenha o indicador pequeno sobre o baú. Sem isso,
	-- este segundo sistema de baús raros continua mostrando o painel padrão.
	prompt.Style =
		Enum.ProximityPromptStyle.Custom

	prompt:SetAttribute(
		"UseSubtleChestPrompt",
		true
	)

	prompt:SetAttribute(
		"ChestPromptLabel",
		Config.PromptObjectText
	)

	prompt:SetAttribute(
		"ChestPromptRare",
		true
	)

	prompt.Parent = root

	AnimeOutline.Apply(
		chest,
		{
			OutlineColor =
				Color3.fromRGB(
					26,
					22,
					18
				),
			OutlineTransparency =
				0.05,
			FillTransparency =
				1,
		}
	)

	local index =
		islandIndex(island)

	local level =
		islandLevel(island)

	chest:SetAttribute(
		"GlobalIslandIndex",
		index
	)
	chest:SetAttribute(
		"IslandLevel",
		level
	)
	chest:SetAttribute(
		"RareChestOpened",
		false
	)
	chest:SetAttribute(
		"RareChestXPReward",
		Config.GetXPReward(level)
	)

	local record = {
		Island = island,
		GlobalIslandIndex = index,
		IslandLevel = level,
	}

	activeChests[chest] =
		record

	local bucket =
		activeByIsland[island]

	if not bucket then
		bucket = {}
		activeByIsland[island] =
			bucket
	end

	bucket[chest] = true

	lifetime += 1
	lifetimeByIsland[island] =
		lifetime
	if index then
		lifetimeByIslandIndex[index] = lifetime
	end

	spawnedSerial += 1

	chest:SetAttribute(
		"RareChestSpawnSerial",
		spawnedSerial
	)

	publishIslandCount(island)

	workspace:SetAttribute(
		"DungeonRareChestSpawnSerial",
		spawnedSerial
	)

	prompt.Triggered:Connect(
		function(player)
			openChest(
				chest,
				record,
				player,
				prompt
			)
		end
	)

	chest.AncestryChanged:Connect(
		function(_, newParent)
			if not newParent then
				unregisterChest(
					chest
				)
			end
		end
	)

	return true,
		chest
end

local function chooseEligibleIsland(
	islands
)
	local candidates = {}

	for _, island in ipairs(islands) do
		local active =
			activeCountForIsland(
				island
			)

		local lifetime =
			lifetimeCountForIsland(
				island
			)

		if active
			< Config.MaximumChestsPerIsland
			and lifetime
				< Config.MaximumChestsPerIsland
		then
			table.insert(
				candidates,
				{
					Island = island,
					Active = active,
					Lifetime = lifetime,
				}
			)
		end
	end

	if #candidates == 0 then
		return nil
	end

	-- Prefer spreading the first chest across different islands. Randomness
	-- remains within the best available occupancy group.
	local bestLifetime = math.huge
	local bestActive = math.huge

	for _, candidate in ipairs(
		candidates
	) do
		if candidate.Lifetime
			< bestLifetime
		then
			bestLifetime =
				candidate.Lifetime

			bestActive =
				candidate.Active

		elseif candidate.Lifetime
			== bestLifetime
		then
			bestActive =
				math.min(
					bestActive,
					candidate.Active
				)
		end
	end

	local preferred = {}

	for _, candidate in ipairs(
		candidates
	) do
		if candidate.Lifetime
			== bestLifetime
			and candidate.Active
				== bestActive
		then
			table.insert(
				preferred,
				candidate.Island
			)
		end
	end

	return preferred[
		random:NextInteger(
			1,
			#preferred
		)
	]
end

local function activeChestCount()
	local count = 0

	for chest in pairs(
		activeChests
	) do
		if chest.Parent then
			count += 1
		else
			activeChests[chest] = nil
		end
	end

	return count
end

local function reconcile()
	if workspace:GetAttribute(
		"DungeonXPCollectibleServiceReady"
	) ~= true
	then
		return
	end

	local islands =
		collectMaterializedIslands()

	local eligibleIslands = {}

	for _, island in ipairs(islands) do
		if Config.IsIslandEligible(
			islandIndex(island)
		) then
			table.insert(
				eligibleIslands,
				island
			)
		end
	end

	local desired =
		Config.GetDesiredActiveChestCount(
			#eligibleIslands
		)

	local active =
		activeChestCount()

	local attempts = 0
	local maximumAttempts =
		math.max(
			8,
			#islands * 3
		)

	while active < desired
		and attempts < maximumAttempts
	do
		attempts += 1

		local island =
			chooseEligibleIsland(
				eligibleIslands
			)

		if not island then
			break
		end

		local success =
			spawnChestOnIsland(
				island
			)

		if success then
			active += 1
		else
			-- Avoid tight-looping on an island whose geometry has no valid
			-- placement. Consume its run quota for this materialization.
			lifetimeByIsland[island] =
				Config.MaximumChestsPerIsland

			publishIslandCount(
				island
			)
		end
	end

	workspace:SetAttribute(
		"DungeonRareChestMaterializedIslandCount",
		#islands
	)
	workspace:SetAttribute(
		"DungeonRareChestEligibleIslandCount",
		#eligibleIslands
	)

	workspace:SetAttribute(
		"DungeonRareChestDesiredActiveCount",
		desired
	)

	workspace:SetAttribute(
		"DungeonRareChestActiveCount",
		activeChestCount()
	)
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonRareChestServiceReady",
		true
	)

	workspace:SetAttribute(
		"DungeonRareChestVersion",
		Config.Version
	)

	workspace:SetAttribute(
		"DungeonRareChestMaxPerIsland",
		Config.MaximumChestsPerIsland
	)

	workspace:SetAttribute(
		"DungeonRareChestRewardPolicy",
		"PhysicalXPCollectiblesV1"
	)

	workspace:SetAttribute(
		"DungeonRareChestCoinsEnabled",
		false
	)

	task.spawn(function()
		while started do
			reconcile()
			task.wait(
				Config.ReconcileInterval
			)
		end
	end)

	print(
		"[RareChestService] ativo: "
			.. "max 2 por ilha, recompensa = XP fisico."
	)

	return true
end

return Service
