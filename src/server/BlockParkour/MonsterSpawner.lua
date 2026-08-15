--[[
	Infinity Islands - Task 05 + Task 07 + Task 08
	MonsterSpawner - LevelInCycle + CycleIndex authority

	REPLACES the old RoundIndex/DifficultyTier normal-island spawning model.

	New Combat Island flow:
	1. Generator calls PopulateIsland(island, freeCells, context).
	2. PopulateIsland deterministically PLANS the encounter, but does not need
	   to spawn future-island mobs immediately.
	3. It announces MobTargetCount to IslandCombatService.
	4. When CombatState becomes "Active", planned mobs are spawned.
	5. Every regular mob receives:
		- GlobalIslandIndex
		- IslandLevel
		- RecommendedLevel
		- MobLevel = LevelInCycle
		- IslandCombatManaged = true
	6. HP / damage are based on MobLevel + CycleIndex, then party scaling.
	7. PlayerLevel is never read.

	Task 06:
	- deterministic threat-budget composition;
	- level-based variant unlocks;
	- guaranteed introduction of newly-unlocked mechanics;
	- mobile-safe ranged/special caps;
	- Golden excluded from regular Combat Islands.

	Task 07:
	- CycleIndex is read only from the island/global progression index;
	- LevelInCycle repeats the 1-12 stat and mob-count curve;
	- the advanced roster remains globally unlocked and never returns to Green;
	- HP and damage compound by 3x per completed cycle;
	- movement speed compounds by 2x per completed cycle;
	- PlayerLevel remains excluded from enemy scaling.

	Task 08:
	- XP compounds by 3x per completed cycle;
	- cycle XP is applied once to XPReward before the risk bonus;
	- the physical collectible service consumes the same XPReward attribute.

	Legacy objective API is kept temporarily so the migration does not break:
	SpawnObjectiveMonster / DespawnObjectiveMonsters / etc.
	Those legacy encounter mobs are marked IslandCombatManaged=false and do
	NOT count toward the new island clear condition.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local IslandMobScalingConfig = require(
	ReplicatedStorage.Shared.Configs.IslandMobScalingConfig
)

local IslandMobRosterConfig = require(
	ReplicatedStorage.Shared.Configs.IslandMobRosterConfig
)

local MobXPConfig = require(
	ReplicatedStorage.Shared.Configs.MobXPConfig
)

local IslandMobSpawnConfig = require(
	ReplicatedStorage.Shared.Configs.IslandMobSpawnConfig
)

local EarlyGamePacingConfig = require(
	ReplicatedStorage.Shared.Configs.EarlyGamePacingConfig
)

local FirstCombatEngagementConfig = require(
	ReplicatedStorage.Shared.Configs.FirstCombatEngagementConfig
)

local IslandProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.IslandProgressionConfig
)

local SlimeController = require(script.Parent.SlimeController)
local SlimeVariants = require(script.Parent.SlimeVariants)

local MonsterSystem =
	script.Parent.Parent:WaitForChild("MonsterSystem")

local MonsterConfig = require(MonsterSystem.MonsterConfig)
local MonsterValidator = require(MonsterSystem.MonsterValidator)

local CombatDamageService = require(
	script.Parent.Parent.MVPSystems.CombatDamageService
)

local CompanionService = require(
	script.Parent.Parent.MVPSystems:WaitForChild("CompanionService")
)

local AnimeOutline = require(
	script.Parent.Parent.MVPSystems.AnimeOutline
)

local MobDamageFeedback = require(
	script.Parent.Parent.MVPSystems.MobDamageFeedback
)

local ContentResolver = require(
	script.Parent.Parent.DungeonRuntime.ContentResolver
)

local PartyScalingService = require(
	script.Parent.Parent.DungeonRuntime.PartyScalingService
)

local TutorialIslandTemplateService = require(
	script.Parent.Parent.DungeonRuntime.TutorialIslandTemplateService
)

local ObjectiveSignalBridge = require(
	script.Parent.Parent.DungeonRuntime.ObjectiveSignalBridge
)

local IslandCombatService = require(
	script.Parent.Parent.DungeonRuntime.IslandCombatService
)

local PlayerLevelService = require(
	script.Parent.Parent.DungeonRuntime.PlayerLevelService
)

local GameplayAnalytics = require(
	ServerScriptService:WaitForChild("GameplayAnalyticsService")
)

local MonsterSpawner = {}

local CONFIG = {
	MAX_SEED = 2147483647,
	RANDOM_SALT = 91373,

	DEFAULT_MAX_HEALTH = 50,
	DEFAULT_ATTACK_DAMAGE = 8,
	DEFAULT_SPAWN_WEIGHT = 10,
	DEFAULT_MINIMUM_ISLAND_SIZE = "Small",

	OBJECTIVE_MIN_PLAYER_SPACING = 8,
	OBJECTIVE_RING_STEP = 5.5,
	OBJECTIVE_RING_COUNT = 3,
	OBJECTIVE_RING_SLOTS = 8,
}

local SIZE_RANK = {
	Small = 1,
	Medium = 2,
	Large = 3,
}

local REMOVED_MONSTER_IDS = {
	Golem = true,
	StoneGolem = true,
}

local initialized = false
local activeMonsters = {}
local monsterCount = 0

-- One deterministic plan per IslandModel.
local plansByIsland =
	setmetatable({}, { __mode = "k" })

local plansByIndex = {}

local function normalizedSeed(value)
	local seed =
		math.floor(
			math.abs(
				tonumber(value) or 1
			)
		) % CONFIG.MAX_SEED

	return seed == 0 and 1 or seed
end

local function numberAttribute(
	instance,
	name,
	defaultValue
)
	local value =
		instance and instance:GetAttribute(name)

	return typeof(value) == "number"
		and value
		or defaultValue
end

local function cleanIndex(value)
	local number = tonumber(value)

	if not number then
		return nil
	end

	number = math.floor(number)

	return number >= 1 and number or nil
end

local function globalIslandIndex(island)
	return cleanIndex(
		island
			and (
				island:GetAttribute("GlobalIslandIndex")
				or island:GetAttribute(
					"ProgressionIslandIndex"
				)
			)
	)
end

local function isInitialIsland(island, resolvedGlobalIndex)
	if not island then
		return resolvedGlobalIndex == 1
	end

	if island:GetAttribute("IsInitialIsland") == true
		or island:GetAttribute("NumberedIslandIndex") == 0
		or island:GetAttribute("IslandRole") == "CombatEntry"
	then
		return true
	end

	return resolvedGlobalIndex == 1
end

local function islandLevel(island)
	local explicit =
		tonumber(
			island
			and island:GetAttribute("IslandLevel")
		)

	if explicit then
		return math.max(1, math.floor(explicit))
	end

	local index = globalIslandIndex(island)

	if index then
		return IslandProgressionConfig.GetIslandLevel(index)
	end

	return 1
end

local function recommendedLevel(island)
	local explicit =
		tonumber(
			island
			and island:GetAttribute(
				"RecommendedLevel"
			)
		)

	if explicit then
		return math.max(1, math.floor(explicit))
	end

	return islandLevel(island)
end

local function islandCycleIndex(island, globalIndex)
	local explicit =
		tonumber(
			island
			and island:GetAttribute(
				"CycleIndex"
			)
		)

	if explicit then
		return math.max(1, math.floor(explicit))
	end

	return IslandProgressionConfig.GetCycleIndex(
		globalIndex or globalIslandIndex(island) or 1
	)
end

local function mobLevelInCycle(island, globalIndex)
	local explicit =
		tonumber(
			island
			and island:GetAttribute(
				"LevelInCycle"
			)
		)

	if explicit then
		return math.max(1, math.floor(explicit))
	end

	return IslandProgressionConfig.GetLevelInCycle(
		globalIndex or globalIslandIndex(island) or 1
	)
end

local function getRoot(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local root =
		model:FindFirstChild("HumanoidRootPart", true)

	if root and root:IsA("BasePart") then
		return root
	end

	if model.PrimaryPart
		and model.PrimaryPart:IsA("BasePart")
	then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA(
		"BasePart",
		true
	)
end

local function getHumanoid(model)
	return model
		and model:FindFirstChildWhichIsA(
			"Humanoid",
			true
		)
end

local function getSpawnLimit()
	return math.max(
		1,
		math.floor(
			tonumber(
				workspace:GetAttribute(
					"DungeonMaximumActiveMonsters"
				)
			)
				or IslandMobScalingConfig
				.DefaultMaximumActiveMonsters
		)
	)
end

local function isLinearCombatIsland(island)
	return island
		and island:IsA("Model")
		and globalIslandIndex(island) ~= nil
		and island:GetAttribute("IsMandatoryRoute")
		~= false
		and island:GetAttribute("IsOptionalRoute")
		~= true
		and island:GetAttribute("IsRewardIsland")
		~= true
		and island:GetAttribute("IsBossSanctuary")
		~= true
end

local function getMonsterFolder()
	local phaseId =
		tostring(
			workspace:GetAttribute("DungeonPhaseId")
			or "Phase01"
		)

	local folder =
		ContentResolver.GetPhaseCategory(
			phaseId,
			"Enemies"
		)

	if folder then
		return folder
	end

	local assets =
		ServerStorage:FindFirstChild("MVPAssets")

	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "MVPAssets"
		assets.Parent = ServerStorage
	end

	local fallback =
		assets:FindFirstChild("Monsters")

	if not fallback then
		fallback = Instance.new("Folder")
		fallback.Name = "Monsters"
		fallback.Parent = assets
	end

	return fallback
end

local function createPrototypeMonster(folder)
	local model = Instance.new("Model")
	model.Name = "PrototypeSlime"

	model:SetAttribute("MonsterId", "PrototypeSlime")
	model:SetAttribute("MonsterType", "Slime")
	model:SetAttribute(
		"DisplayName",
		"Slime de Prototipo"
	)
	model:SetAttribute("Enabled", true)
	model:SetAttribute("MaxHealth", 45)
	model:SetAttribute("AttackDamage", 8)
	model:SetAttribute("SpawnWeight", 10)
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("UseCustomAI", false)
	model:SetAttribute("PrototypeModel", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.8, 2.2, 2.8)
	root.Shape = Enum.PartType.Ball
	root.Material = Enum.Material.SmoothPlastic
	root.Color = Color3.fromRGB(80, 205, 92)
	root.Anchored = false
	root.CanCollide = true
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	model.PrimaryPart = root
	model.Parent = folder

	warn(
		"[MonsterSpawner] Nenhum template valido encontrado. "
			.. "PrototypeSlime criado como fallback."
	)

	return model
end

local function getTemplates()
	local folder = getMonsterFolder()
	local templates = {}

	for _, template in ipairs(folder:GetChildren()) do
		if not template:IsA("Model") then
			continue
		end

		local monsterId =
			template:GetAttribute("MonsterId")
			or template.Name

		if REMOVED_MONSTER_IDS[monsterId]
			or REMOVED_MONSTER_IDS[template.Name]
		then
			continue
		end

		local valid, errors =
			MonsterValidator.Validate(template)

		if valid then
			table.insert(templates, template)
		elseif template:GetAttribute("Enabled")
			~= false
		then
			warn(
				string.format(
					"[MonsterSpawner] Ignorando %s: %s",
					template:GetFullName(),
					MonsterValidator.Format(errors)
				)
			)
		end
	end

	table.sort(
		templates,
		function(left, right)
			return left.Name < right.Name
		end
	)

	if #templates == 0 then
		table.insert(
			templates,
			createPrototypeMonster(folder)
		)
	end

	return templates
end

local function regularTemplate()
	local templates = getTemplates()

	for _, template in ipairs(templates) do
		if SlimeVariants.IsSlime(template) then
			return template
		end
	end

	return templates[1]
end

local function objectiveTemplate(options)
	local templates = getTemplates()
	local requestedId =
		tostring(options.MonsterId or "")

	if requestedId ~= "" then
		for _, template in ipairs(templates) do
			if (
				template:GetAttribute("MonsterId")
					or template.Name
				) == requestedId
			then
				return template
			end
		end
	end

	for _, template in ipairs(templates) do
		if SlimeVariants.IsSlime(template) then
			return template
		end
	end

	return templates[1]
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z

	return math.sqrt(dx * dx + dz * dz)
end

local function shuffle(random, source)
	local result = table.clone(source)

	for index = #result, 2, -1 do
		local other =
			random:NextInteger(1, index)

		result[index], result[other] =
			result[other], result[index]
	end

	return result
end

local function validCellRecord(record)
	return typeof(record) == "table"
		and typeof(record.Cell) == "Vector3"
		and typeof(record.SurfacePosition)
		== "Vector3"
end

local function validCells(source)
	local result = {}

	for _, record in ipairs(source or {}) do
		if validCellRecord(record) then
			table.insert(result, record)
		end
	end

	return result
end

local function selectSpawnCells(
	cells,
	amount,
	spacing,
	random
)
	local candidates =
		shuffle(random, validCells(cells))

	local selected = {}
	local selectedSet = {}

	for _, candidate in ipairs(candidates) do
		local farEnough = true

		for _, existing in ipairs(selected) do
			if horizontalDistance(
				candidate.SurfacePosition,
				existing.SurfacePosition
				) < spacing
			then
				farEnough = false
				break
			end
		end

		if farEnough then
			table.insert(selected, candidate)
			selectedSet[candidate] = true

			if #selected >= amount then
				return selected
			end
		end
	end

	-- Compact island fallback:
	-- fill remaining spots using the farthest currently-available cell.
	while #selected < amount do
		local best
		local bestDistance = -1

		for _, candidate in ipairs(candidates) do
			if selectedSet[candidate] then
				continue
			end

			local nearest = math.huge

			for _, existing in ipairs(selected) do
				nearest = math.min(
					nearest,
					horizontalDistance(
						candidate.SurfacePosition,
						existing.SurfacePosition
					)
				)
			end

			if #selected == 0 then
				nearest = math.huge
			end

			if nearest > bestDistance then
				best = candidate
				bestDistance = nearest
			end
		end

		if not best then
			break
		end

		table.insert(selected, best)
		selectedSet[best] = true
	end

	return selected
end

local function positionFromReference(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end

	return nil
end

local function firstCombatReference(island)
	for _, name in ipairs(
		FirstCombatEngagementConfig.ReferenceNames
		) do
		local candidate =
			island:FindFirstChild(
				name,
				true
			)

		local position =
			positionFromReference(
				candidate
			)

		if position then
			return position,
				name
		end
	end

	return island:GetPivot().Position,
		"IslandPivot"
end

local function prioritizeFirstCombatCell(
	cells,
	island,
	globalIslandIndex
)
	if not FirstCombatEngagementConfig
		.AppliesToIsland(
			globalIslandIndex
		)
			or #cells <= 0
	then
		return cells,
			nil
	end

	local referencePosition,
		referenceName =
		firstCombatReference(
			island
		)

	local bestIndex = nil
	local bestScore = math.huge
	local bestDistance = nil

	for index, cell in ipairs(cells) do
		local distance =
			horizontalDistance(
				referencePosition,
				cell.SurfacePosition
			)

		local score =
			FirstCombatEngagementConfig
			.ScoreDistance(
				distance
			)

		if score < bestScore then
			bestScore = score
			bestIndex = index
			bestDistance = distance
		end
	end

	if bestIndex
		and bestIndex ~= 1
	then
		cells[1],
			cells[bestIndex] =
			cells[bestIndex],
			cells[1]
	end

	return cells,
		{
			ReferenceName =
			referenceName,

			ReferencePosition =
			referencePosition,

			Distance =
			bestDistance,

			WithinPreferredBand =
			FirstCombatEngagementConfig
			.IsInPreferredBand(
				bestDistance
			),
		}
end

local function createMarker(
	pointsFolder,
	cellRecord,
	index,
	template,
	spawnMode
)
	local marker = Instance.new("CFrameValue")
	marker.Name =
		string.format(
			"Monster_%02d",
			index
		)
	marker.Value =
		CFrame.new(cellRecord.SurfacePosition)

	marker:SetAttribute(
		"GridX",
		cellRecord.Cell.X
	)
	marker:SetAttribute(
		"GridY",
		cellRecord.Cell.Y
	)
	marker:SetAttribute(
		"GridZ",
		cellRecord.Cell.Z
	)
	marker:SetAttribute(
		"MonsterId",
		template:GetAttribute("MonsterId")
			or template.Name
	)
	marker:SetAttribute(
		"SpawnMode",
		spawnMode
	)

	marker.Parent = pointsFolder

	return marker
end

local function getRecordedDamager(
	entry,
	model,
	humanoid
)
	if entry.LastDamager
		and entry.LastDamager.Parent == Players
	then
		return entry.LastDamager
	end

	local creator =
		humanoid:FindFirstChild("creator")

	if creator
		and creator:IsA("ObjectValue")
		and creator.Value
		and creator.Value:IsA("Player")
	then
		return creator.Value
	end

	local userId =
		model:GetAttribute("LastDamagedByUserId")
		or model:GetAttribute("LastHitUserId")

	if typeof(userId) == "number" then
		return Players:GetPlayerByUserId(userId)
	end

	return nil
end

local function xpParticipants(
	killer,
	islandIndex
)
	local result = {}
	local seen = {}

	local function add(player)
		if not player
			or not player:IsA("Player")
			or player.Parent ~= Players
			or seen[player.UserId]
		then
			return
		end

		seen[player.UserId] = true
		table.insert(result, player)
	end

	-- The death must have a valid attribution, but the killer is always
	-- protected from losing XP due to a one-frame island-index transition.
	add(killer)

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		local currentIndex =
			cleanIndex(
				player:GetAttribute(
					"CurrentGlobalIslandIndex"
				)
			)

		if currentIndex == islandIndex then
			add(player)
		end
	end

	return result
end

local function awardManagedMobXP(
	entry,
	model,
	killer
)
	if not entry
		or not model
		or model:GetAttribute(
			"IslandCombatManaged"
		) ~= true
	then
		return false, "NotManagedCombatMob"
	end

	if not killer
		or not killer:IsA("Player")
		or killer.Parent ~= Players
	then
		model:SetAttribute(
			"XPRewardClaimStatus",
			"NoAttributedPlayer"
		)
		return false, "NoAttributedPlayer"
	end

	-- Server-authoritative one-shot claim. The Died path is normally already
	-- single-fire, but this guards future callbacks/retries from double paying.
	if model:GetAttribute(
		"XPRewardClaimed"
		) == true
	then
		return false, "AlreadyClaimed"
	end

	model:SetAttribute(
		"XPRewardClaimed",
		true
	)
	model:SetAttribute(
		"XPRewardClaimedAt",
		workspace:GetServerTimeNow()
	)
	model:SetAttribute(
		"XPRewardKillerUserId",
		killer.UserId
	)

	local islandIndex =
		cleanIndex(
			entry.GlobalIslandIndex
			or model:GetAttribute(
				"GlobalIslandIndex"
			)
		)

	if not islandIndex then
		model:SetAttribute(
			"XPRewardClaimStatus",
			"MissingIslandIndex"
		)
		return false, "MissingIslandIndex"
	end

	local mobLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					model:GetAttribute(
						"MobLevel"
					)
				) or 1
			)
		)

	local riskRewardLevel =
		math.max(
			1,
			math.floor(
				tonumber(
					model:GetAttribute(
						"RecommendedLevel"
					)
				) or mobLevel
			)
		)

	local baseReward =
		math.max(
			1,
			math.floor(
				tonumber(
					model:GetAttribute(
						"XPReward"
					)
				)
				or MobXPConfig
				.GetMobXPReward(
					model:GetAttribute(
						"SlimeVariant"
					),
					mobLevel,
					model:GetAttribute(
						"XPRewardMultiplier"
					)
				)
			)
		)

	local recipients =
		xpParticipants(
			killer,
			islandIndex
		)

	local awarded = 0
	local totalGranted = 0
	local highestRiskBonus = 0

	for _, player in ipairs(recipients) do
		local playerLevel =
			math.max(
				1,
				math.floor(
					tonumber(
						player:GetAttribute(
							"PlayerLevel"
						)
					) or 1
				)
			)

		local amount,
			riskBonus =
			MobXPConfig
			.GetAwardForPlayer(
				baseReward,
				riskRewardLevel,
				playerLevel
			)

		local success =
			PlayerLevelService.AwardXP(
				player,
				amount,
				"MobDefeated:"
				.. tostring(
					model:GetAttribute(
						"SlimeVariant"
					)
					or model:GetAttribute(
						"MonsterId"
					)
					or model.Name
				)
			)

		if success then
			local companionOk, companionError = pcall(
				CompanionService.RecordDefeat,
				player,
				model,
				amount
			)
			if not companionOk then
				warn("[MonsterSpawner] Falha ao processar companheiro: " .. tostring(companionError))
			end
			awarded += 1
			totalGranted += amount
			highestRiskBonus =
				math.max(
					highestRiskBonus,
					riskBonus
				)

			player:SetAttribute(
				"LastMobXPBaseReward",
				baseReward
			)
			player:SetAttribute(
				"LastMobXPRiskBonus",
				riskBonus
			)
			player:SetAttribute(
				"LastMobXPFinalReward",
				amount
			)
			player:SetAttribute(
				"LastMobXPLevel",
				mobLevel
			)
			player:SetAttribute(
				"LastMobXPRiskLevel",
				riskRewardLevel
			)
			player:SetAttribute(
				"LastMobXPCycleIndex",
				model:GetAttribute(
					"CycleIndex"
				)
			)
			player:SetAttribute(
				"LastMobXPRewardMultiplier",
				model:GetAttribute(
					"XPRewardMultiplier"
				)
			)
			player:SetAttribute(
				"LastMobXPIslandIndex",
				islandIndex
			)
			player:SetAttribute(
				"LastMobXPVariant",
				tostring(
					model:GetAttribute(
						"SlimeVariant"
					)
						or model:GetAttribute(
							"MonsterId"
						)
						or model.Name
				)
			)
			player:SetAttribute(
				"LastMobXPWasRisky",
				riskBonus > 0
			)
			player:SetAttribute(
				"LastMobDefeatedAt",
				workspace:GetServerTimeNow()
			)
			player:SetAttribute(
				"MobXPFeedbackSerial",
				(
					tonumber(
						player:GetAttribute(
							"MobXPFeedbackSerial"
						)
					) or 0
				) + 1
			)
		end
	end

	model:SetAttribute(
		"XPRewardRecipientCount",
		awarded
	)
	model:SetAttribute(
		"XPRewardTotalGranted",
		totalGranted
	)
	model:SetAttribute(
		"XPRewardHighestRiskBonus",
		highestRiskBonus
	)
	model:SetAttribute(
		"XPRewardClaimStatus",
		awarded > 0
			and "Awarded"
			or "NoEligibleRecipients"
	)

	workspace:SetAttribute(
		"DungeonLastMobXPAwardIsland",
		islandIndex
	)
	workspace:SetAttribute(
		"DungeonLastMobXPAwardRecipients",
		awarded
	)
	workspace:SetAttribute(
		"DungeonLastMobXPAwardTotal",
		totalGranted
	)
	workspace:SetAttribute(
		"DungeonLastMobXPAwardAt",
		workspace:GetServerTimeNow()
	)

	return awarded > 0,
		awarded
end

local function createDeathParticles(root, color)
	if not root or not root.Parent then
		return
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color =
		ColorSequence.new(
			color
			or Color3.fromRGB(89, 220, 91)
		)
	emitter.LightEmission = 0.5
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle =
		Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = root
	emitter:Emit(20)

	Debris:AddItem(emitter, 1)
end

local function publishPlanConcurrency(plan)
	if not plan
		or not plan.Island
		or not plan.Island.Parent
	then
		return
	end

	local pending =
		math.max(
			0,
			plan.MaxAlive
			- plan.Alive
		)

	plan.Island:SetAttribute(
		"MobMaxAlive",
		plan.MaxAlive
	)
	plan.Island:SetAttribute(
		"MobActiveAliveCount",
		plan.Alive
	)
	plan.Island:SetAttribute(
		"MobPendingSpawnCount",
		pending
	)
	plan.Island:SetAttribute("MobRespawnPendingCount", pending)
	plan.Island:SetAttribute("MobInfiniteRespawnEnabled", true)
	plan.Island:SetAttribute("MobLifetimeSpawnedCount", plan.Spawned)
	plan.Island:SetAttribute(
		"MobSpawnPresentation",
		"SkyDrop"
	)
	plan.Island:SetAttribute(
		"MobSpawnStaggerSeconds",
		plan.SpawnStaggerSeconds
	)
	plan.Island:SetAttribute(
		"MobSkyDropHeightStuds",
		IslandMobSpawnConfig
			.SkyDropHeightStuds
	)
	plan.Island:SetAttribute(
		"MobSpawnConcurrencyVersion",
		IslandMobSpawnConfig.Version
	)
end

local function unregisterMonster(model)
	local entry = activeMonsters[model]

	SlimeController.Stop(model)

	if entry then
		activeMonsters[model] = nil
		monsterCount =
			math.max(0, monsterCount - 1)

		if entry.IslandCombatManaged == true
			and entry.PlanAliveCounted == true
		then
			entry.PlanAliveCounted = false

			local plan =
				plansByIndex[
			entry.GlobalIslandIndex
			]

			if plan then
				plan.Alive =
					math.max(
						0,
						(plan.Alive or 0) - 1
					)

				publishPlanConcurrency(plan)
			end
		end
	end

	if CollectionService:HasTag(
		model,
		"CombatTarget"
		)
	then
		CollectionService:RemoveTag(
			model,
			"CombatTarget"
		)
	end

	return entry
end

local function configureRuntimeScripts(
	clone,
	template,
	usesSlimeController,
	useCentralAI
)
	for _, descendant in ipairs(
		clone:GetDescendants()
		) do
		if descendant:IsA("BaseScript")
			and (
				usesSlimeController
					or useCentralAI
			)
		then
			if descendant.Name ~= "Animate"
				and template:GetAttribute(
					"KeepEmbeddedAIScripts"
				) ~= true
					and descendant:GetAttribute(
						"AllowWithSlimeController"
					) ~= true
			then
				descendant.Disabled = true
			end
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanQuery = true

			pcall(function()
				descendant.CollisionGroup =
					"MVPMonsters"
			end)
		end
	end
end

local function roleMultipliers(role)
	if role == "Guard" then
		return 1.5, 0.9, 0.78
	elseif role == "Ranged" then
		return 1, 1, 0.88
	elseif role == "Elite" then
		return 1.15, 1, 1.05
	end

	return 1, 1, 1
end

local attemptSpawnPlan

local function spawnClone(
	template,
	parent,
	island,
	cellRecord,
	marker,
	random,
	spawnMode,
	slimeVariantForSpawn,
	spawnOptions
)
	spawnOptions =
		type(spawnOptions) == "table"
		and spawnOptions
		or {}

	if monsterCount >= getSpawnLimit() then
		return false, nil, "GlobalMonsterLimitReached"
	end

	local clone = template:Clone()

	local root = getRoot(clone)
	local humanoid = getHumanoid(clone)

	if not root or not humanoid then
		clone:Destroy()
		return false, nil, "InvalidMonsterRig"
	end

	clone.PrimaryPart = root

	local slimeDefinition,
		slimeVariant =
		SlimeVariants.ConfigureClone(
			clone,
			template,
			random,
			slimeVariantForSpawn
		)

	local monsterId =
		slimeDefinition
		and slimeDefinition.MonsterId
		or template:GetAttribute(
			"MonsterId"
		)
		or template.Name

	local displayName =
		slimeDefinition
		and slimeDefinition.DisplayName
		or template:GetAttribute(
			"DisplayName"
		)
		or monsterId

	local globalIndex =
		cleanIndex(
			spawnOptions.GlobalIslandIndex
			or globalIslandIndex(island)
		)

	local initialIsland =
		spawnOptions.InitialIsland == true
		or isInitialIsland(island, globalIndex)

	local modelScaleMultiplier =
		initialIsland
		and EarlyGamePacingConfig
		.InitialIslandModelScale
		or 1

	if modelScaleMultiplier ~= 1 then
		clone:ScaleTo(
			clone:GetScale()
				* modelScaleMultiplier
		)
	end

	local mobLevel =
		mobLevelInCycle(island, globalIndex)
	local cycleIndex =
		islandCycleIndex(island, globalIndex)
	local cycleMultipliers =
		IslandMobScalingConfig.GetCycleMultipliers(
			cycleIndex
		)

	local baseHealth =
		math.max(
			1,
			numberAttribute(
				template,
				"MaxHealth",
				CONFIG.DEFAULT_MAX_HEALTH
			)
		)

	local baseDamage =
		math.max(
			0,
			numberAttribute(
				template,
				"AttackDamage",
				CONFIG.DEFAULT_ATTACK_DAMAGE
			)
		)

	if slimeDefinition and not initialIsland then
		baseHealth *=
			slimeDefinition.HealthMultiplier
			or 1
	end

	if slimeDefinition then
		baseDamage =
			slimeDefinition.AttackDamage
			or baseDamage
	end

	local healthLevelMultiplier =
		IslandMobScalingConfig
		.GetHealthMultiplier(mobLevel)

	local damageLevelMultiplier =
		IslandMobScalingConfig
		.GetDamageMultiplier(mobLevel)

	local requestedRole =
		tostring(spawnOptions.Role or "")

	local isElite =
		spawnOptions.IsElite == true

	local role =
		requestedRole ~= ""
		and requestedRole
		or (
			isElite
			and "Elite"
			or "Common"
		)

	local roleHealth,
		roleDamage,
		roleSpeed =
		roleMultipliers(role)

	local health =
		baseHealth
		* healthLevelMultiplier
		* cycleMultipliers.Health
		* roleHealth
		* math.max(
			0.1,
			tonumber(
				spawnOptions.HealthMultiplier
			) or 1
		)

	local damage =
		baseDamage
		* damageLevelMultiplier
		* cycleMultipliers.Damage
		* roleDamage
		* math.max(
			0.1,
			tonumber(
				spawnOptions.DamageMultiplier
			) or 1
		)

	local speedMultiplier =
		cycleMultipliers.Speed
		* roleSpeed
		* math.max(
			0.25,
			tonumber(
				spawnOptions.SpeedMultiplier
			) or 1
		)

	local partySize =
		math.clamp(
			math.floor(
				tonumber(
					workspace:GetAttribute(
						"DungeonPartySize"
					)
				) or 1
			),
			1,
			4
		)

	local partyMultipliers

	health,
		damage,
		partyMultipliers =
		PartyScalingService.ScaleValues(
			math.max(
				1,
				math.floor(health + 0.5)
			),
			math.max(
				0,
				math.floor(damage + 0.5)
			),
			partySize,
			false
		)

	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType =
		Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 18
	humanoid.HealthDisplayType =
		Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.HealthDisplayDistance = 18
	humanoid.NameDisplayDistance = 18
	humanoid.BreakJointsOnDeath = false

	humanoid.WalkSpeed =
		math.clamp(
			numberAttribute(
				template,
				"WalkSpeed",
				humanoid.WalkSpeed
			)
			* speedMultiplier,
			4,
			28 * cycleMultipliers.Speed
		)

	local recommended =
		recommendedLevel(island)

	local islandCombatManaged =
		spawnOptions.IslandCombatManaged
		== true

	clone.Name = "Monster_" .. monsterId

	clone:SetAttribute(
		"DisplayName",
		displayName
	)
	clone:SetAttribute(
		"RuntimeMonster",
		true
	)
	clone:SetAttribute(
		"MonsterId",
		monsterId
	)
	clone:SetAttribute(
		"SpawnMode",
		spawnMode
	)

	local skyDrop =
		spawnOptions.SkyDrop == true

	local skyDropHeight =
		skyDrop
		and math.max(
			0,
			tonumber(
				spawnOptions
				.SkyDropHeightStuds
			)
			or IslandMobSpawnConfig
			.SkyDropHeightStuds
		)
		or 0

	clone:SetAttribute(
		"SkyDropSpawn",
		skyDrop
	)
	clone:SetAttribute(
		"SkyDropHeightStuds",
		skyDropHeight
	)
	clone:SetAttribute(
		"SkyDropSurfacePosition",
		cellRecord.SurfacePosition
	)

	-- New difficulty contract.
	clone:SetAttribute("MobLevel", mobLevel)
	clone:SetAttribute("MobLevelInCycle", mobLevel)
	clone:SetAttribute("IslandLevel", recommended)
	clone:SetAttribute(
		"RecommendedLevel",
		recommended
	)
	clone:SetAttribute(
		"GlobalIslandIndex",
		globalIndex
	)
	clone:SetAttribute(
		"IsInitialIslandMob",
		initialIsland
	)
	clone:SetAttribute(
		"InitialIslandModelScale",
		modelScaleMultiplier
	)
	clone:SetAttribute(
		"InitialIslandSizeReductionPercent",
		initialIsland and 40 or 0
	)
	clone:SetAttribute(
		"InitialIslandHealthNormalizedToGreen",
		initialIsland
	)
	clone:SetAttribute(
		"CycleIndex",
		cycleIndex
	)
	clone:SetAttribute(
		"MobDifficultySource",
		"StrongerBaseLevelAndCycleV5"
	)
	clone:SetAttribute(
		"HealthLevelMultiplier",
		healthLevelMultiplier
	)
	clone:SetAttribute(
		"DamageLevelMultiplier",
		damageLevelMultiplier
	)
	clone:SetAttribute(
		"MobCycleHealthMultiplier",
		cycleMultipliers.Health
	)
	clone:SetAttribute(
		"MobCycleDamageMultiplier",
		cycleMultipliers.Damage
	)
	clone:SetAttribute(
		"MobCycleSpeedMultiplier",
		cycleMultipliers.Speed
	)
	clone:SetAttribute(
		"BaseMaxHealth",
		math.max(
			1,
			math.floor(baseHealth + 0.5)
		)
	)
	clone:SetAttribute(
		"BaseAttackDamage",
		math.max(
			0,
			math.floor(baseDamage + 0.5)
		)
	)
	clone:SetAttribute(
		"ScaledMaxHealth",
		health
	)
	clone:SetAttribute(
		"AttackDamage",
		damage
	)
	clone:SetAttribute(
		"PlayerLevelAffectsMobStats",
		false
	)
	clone:SetAttribute(
		"LegacyRoundScalingApplied",
		false
	)

	local rosterDefinition =
		IslandMobRosterConfig.GetVariant(
			slimeVariant
		)

	clone:SetAttribute(
		"MobThreatCost",
		rosterDefinition
			and rosterDefinition.ThreatCost
			or 1
	)
	clone:SetAttribute(
		"MobVariantUnlockLevel",
		rosterDefinition
			and rosterDefinition.UnlockLevel
			or 1
	)
	clone:SetAttribute(
		"MobIsRanged",
		rosterDefinition
			and rosterDefinition.Ranged
			or false
	)
	clone:SetAttribute(
		"MobIsSpecial",
		rosterDefinition
			and rosterDefinition.Special
			or false
	)
	clone:SetAttribute(
		"MobRosterVersion",
		IslandMobRosterConfig.Version
	)

	local slimeVariantName =
		tostring(
			slimeVariant
			or clone:GetAttribute(
				"SlimeVariant"
			)
			or "Green"
		)
	local xpRewardVariant =
		initialIsland and "Green" or slimeVariantName

	local baseXPReward =
		MobXPConfig.GetBaseXP(
			xpRewardVariant
		)

	local xpLevelMultiplier =
		MobXPConfig.GetLevelMultiplier(
			mobLevel
		)

	local xpCycleMultiplier =
		IslandProgressionConfig.GetXPRewardMultiplier(
			cycleIndex
		)

	local initialXPRewardMultiplier =
		initialIsland
		and EarlyGamePacingConfig
		.InitialIslandXPRewardMultiplier
		or 1

	local effectiveXPRewardMultiplier =
		xpCycleMultiplier
		* initialXPRewardMultiplier

	local xpReward =
		MobXPConfig.GetMobXPReward(
			xpRewardVariant,
			mobLevel,
			xpCycleMultiplier
		)

	if initialIsland then
		xpReward = math.max(
			MobXPConfig.MinimumReward,
			math.floor(
				xpReward
					* initialXPRewardMultiplier
					+ 0.5
			)
		)
	end

	clone:SetAttribute(
		"BaseXPReward",
		baseXPReward
	)
	clone:SetAttribute(
		"XPRewardVariant",
		xpRewardVariant
	)
	clone:SetAttribute(
		"XPLevelMultiplier",
		xpLevelMultiplier
	)
	clone:SetAttribute(
		"XPRewardMultiplier",
		effectiveXPRewardMultiplier
	)
	clone:SetAttribute(
		"XPCycleMultiplier",
		xpCycleMultiplier
	)
	clone:SetAttribute(
		"InitialIslandXPRewardMultiplier",
		initialXPRewardMultiplier
	)
	clone:SetAttribute(
		"XPReward",
		xpReward
	)
	clone:SetAttribute(
		"XPRewardVersion",
		MobXPConfig.Version
	)
	clone:SetAttribute(
		"XPRewardPolicy",
		MobXPConfig.AwardPolicy
	)
	clone:SetAttribute(
		"XPRewardClaimed",
		false
	)

	-- Compatibility: old consumers may still read DifficultyTier.
	-- It now mirrors MobLevel and is NOT derived from RoundIndex.
	clone:SetAttribute(
		"DifficultyTier",
		mobLevel
	)

	clone:SetAttribute(
		"RouteIslandIndex",
		island:GetAttribute("IslandIndex")
	)
	clone:SetAttribute(
		"RouteRoundIndex",
		island:GetAttribute("RoundIndex")
	)

	clone:SetAttribute(
		"MonsterRole",
		role
	)
	clone:SetAttribute(
		"IsElite",
		isElite
	)

	clone:SetAttribute(
		"IslandCombatManaged",
		islandCombatManaged
	)

	local encounterId =
		spawnOptions.EncounterId

	clone:SetAttribute(
		"ObjectiveSpawned",
		encounterId ~= nil
	)
	clone:SetAttribute(
		"ObjectiveEncounterId",
		encounterId
	)
	clone:SetAttribute(
		"ObjectiveId",
		spawnOptions.ObjectiveId
	)
	clone:SetAttribute(
		"ObjectiveWaveIndex",
		spawnOptions.WaveIndex
	)
	clone:SetAttribute(
		"ObjectiveSpawnSequence",
		spawnOptions.SpawnSequence
	)

	-- Legacy economy intentionally neutralized for the simplified MVP.
	clone:SetAttribute("ScoreValue", 0)
	clone:SetAttribute("CoinValue", 0)
	clone:SetAttribute(
		"LegacyMobRewardsDisabled",
		true
	)

	if role == "Guard" then
		clone:SetAttribute(
			"Defense",
			math.max(
				3,
				tonumber(
					clone:GetAttribute(
						"Defense"
					)
				) or 0
			)
		)
		clone:SetAttribute(
			"NoKnockback",
			true
		)
		clone:SetAttribute(
			"CanBeKnockedBack",
			false
		)
	end

	PartyScalingService.MarkApplied(
		clone,
		partySize,
		partyMultipliers
	)

	clone:SetAttribute(
		"HomePosition",
		cellRecord.SurfacePosition
	)
	clone:SetAttribute(
		"SpawnSurfacePosition",
		cellRecord.SurfacePosition
	)
	clone:SetAttribute(
		"SpawnGridX",
		cellRecord.Cell.X
	)
	clone:SetAttribute(
		"SpawnGridY",
		cellRecord.Cell.Y
	)
	clone:SetAttribute(
		"SpawnGridZ",
		cellRecord.Cell.Z
	)

	local forcePeaceful =
		spawnOptions.ForcePeaceful == true

	local tutorialEnemyArea =
		cellRecord.TutorialEnemyArea

	if forcePeaceful then
		clone:SetAttribute(
			"TutorialPassive",
			true
		)
		clone:SetAttribute(
			"PermanentPeaceful",
			true
		)
		clone:SetAttribute(
			"CanDamagePlayers",
			false
		)
		clone:SetAttribute(
			"AttackDamage",
			0
		)
		clone:SetAttribute(
			"AggroUserId",
			nil
		)
		clone:SetAttribute(
			"TargetUserId",
			nil
		)

		if tutorialEnemyArea
			and tutorialEnemyArea:IsA(
				"BasePart"
			)
		then
			clone:SetAttribute(
				"TutorialEnemyAreaCFrame",
				tutorialEnemyArea.CFrame
			)
			clone:SetAttribute(
				"TutorialEnemyAreaSize",
				tutorialEnemyArea.Size
			)
			clone:SetAttribute(
				"TutorialEnemyAreaName",
				tutorialEnemyArea.Name
			)
		end
	end

	local forceHostile =
		not forcePeaceful
		and (
			spawnOptions.ForceHostile == true
			or encounterId ~= nil
			or islandCombatManaged
		)

	local initiallyPeaceful =
		template:GetAttribute("Peaceful")
		== true

	if slimeDefinition then
		initiallyPeaceful =
			slimeDefinition.InitiallyPeaceful
			== true
	end

	clone:SetAttribute(
		"Peaceful",
		forcePeaceful
			or not forceHostile
			and initiallyPeaceful
			or false
	)

	local usesSlimeController =
		slimeDefinition ~= nil

	local useCentralAI =
		not usesSlimeController
		and template:GetAttribute(
			"UseCustomAI"
		) ~= true

	if useCentralAI then
		MonsterConfig.ApplyRuntimeDefaults(clone)
	end

	clone:SetAttribute(
		"UseCentralAI",
		useCentralAI
	)
	clone:SetAttribute(
		"AIController",
		usesSlimeController
			and "Slime"
			or (
				useCentralAI
				and "Generic"
				or "Custom"
			)
	)

	clone:SetAttribute(
		"SimulationActive",
		island:GetAttribute(
			"SimulationActive"
		) ~= false
	)

	if slimeVariant then
		marker:SetAttribute(
			"SlimeVariant",
			slimeVariant
		)
		marker:SetAttribute(
			"MonsterId",
			monsterId
		)
	end

	configureRuntimeScripts(
		clone,
		template,
		usesSlimeController,
		useCentralAI
	)

	-- Align the model bottom with the planned surface.
	clone:PivotTo(CFrame.identity)

	local boundingBox,
		boundingSize =
		clone:GetBoundingBox()

	local bottomOffset =
		boundingBox.Position.Y
	- boundingSize.Y / 2

	local desiredBottomY =
		cellRecord.SurfacePosition.Y + 0.15

	local finalSpawnY =
		desiredBottomY
	- bottomOffset
		+ skyDropHeight

	clone:PivotTo(
		CFrame.new(
			cellRecord.SurfacePosition.X,
			finalSpawnY,
			cellRecord.SurfacePosition.Z
		)
			* CFrame.Angles(
				0,
				random:NextNumber(
					0,
					math.pi * 2
				),
				0
			)
	)

	if skyDrop then
		clone:SetAttribute(
			"SpawnAirborne",
			true
		)
		clone:SetAttribute(
			"SpawnAirborneUntil",
			workspace:GetServerTimeNow()
				+ IslandMobSpawnConfig
				.AirborneVisualSeconds
		)

		task.delay(
			IslandMobSpawnConfig
				.AirborneVisualSeconds,
			function()
				if clone.Parent then
					clone:SetAttribute(
						"SpawnAirborne",
						false
					)
				end
			end
		)
	end

	local entry = {
		Model = clone,
		Root = root,
		Humanoid = humanoid,
		Island = island,
		Marker = marker,
		LastDamager = nil,
		DeathParticleColor =
			clone:GetAttribute(
				"DeathParticleColor"
			),
		SlimeDefinition =
			slimeDefinition
			and table.clone(
				slimeDefinition
			)
			or nil,
		IslandCombatManaged =
			islandCombatManaged,
		GlobalIslandIndex =
			globalIndex,
		BaseXPReward =
			baseXPReward,
		XPReward =
			xpReward,
		XPRewardMultiplier =
			effectiveXPRewardMultiplier,
		MobLevel =
			mobLevel,
		PlanAliveCounted =
			islandCombatManaged,
	}

	if entry.SlimeDefinition then
		entry.SlimeDefinition.AttackDamage =
			forcePeaceful and 0 or damage

		local groundEffectBase = tonumber(
			entry.SlimeDefinition.GroundEffectDamage
		)
		if groundEffectBase then
			local totalDamageMultiplier = baseDamage > 0
				and (damage / baseDamage)
				or 0
			entry.SlimeDefinition.GroundEffectDamage = forcePeaceful
				and 0
				or groundEffectBase * totalDamageMultiplier
			clone:SetAttribute(
				"FireGroundBaseDamage",
				groundEffectBase
			)
			clone:SetAttribute(
				"FireGroundDamage",
				entry.SlimeDefinition.GroundEffectDamage
			)
			clone:SetAttribute(
				"FireGroundDamageUsesMobScaling",
				true
			)
		end

		if forcePeaceful then
			entry.SlimeDefinition.InitiallyPeaceful =
				true
		elseif forceHostile then
			entry.SlimeDefinition.InitiallyPeaceful =
				false
		end
	end

	clone.Parent = parent

	activeMonsters[clone] = entry
	monsterCount += 1

	CollectionService:AddTag(
		clone,
		"CombatTarget"
	)

	if islandCombatManaged then
		IslandCombatService.RegisterSpawn(
			clone,
			globalIndex
		)
	end

	humanoid.Died:Connect(function()
		local current =
			activeMonsters[clone]

		if not current then
			return
		end

		local deathPosition =
			root.Parent
			and root.Position
			or cellRecord.SurfacePosition

		local damager =
			getRecordedDamager(
				current,
				clone,
				humanoid
			)

		-- XP is paid before unregister/destroy so all authoritative mob metadata
		-- is still available. Only Task 04/05 managed Combat Island mobs qualify.
		awardManagedMobXP(
			current,
			clone,
			damager
		)

		unregisterMonster(clone)

		for _, descendant in ipairs(
			clone:GetDescendants()
			) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.AssemblyLinearVelocity =
					Vector3.zero
				descendant.AssemblyAngularVelocity =
					Vector3.zero
			end
		end

		-- Keep old objective progression operational during migration.
		ObjectiveSignalBridge.Report(
			"EnemyDefeated",
			{
				Target = clone,
				SourceUserId =
					damager
					and damager.UserId
					or nil,
				GlobalIslandIndex =
					current.GlobalIslandIndex,
				MonsterRole =
					clone:GetAttribute(
						"MonsterRole"
					),
				IsElite =
					clone:GetAttribute(
						"IsElite"
					) == true,
			}
		)

		if damager then
			pcall(
				GameplayAnalytics.RecordEnemyDefeated,
				damager,
				clone,
				damager:GetAttribute(
					"EquippedSword"
				) or "OtherWeapon"
			)
		end

		createDeathParticles(
			root,
			current.DeathParticleColor
		)

		Debris:AddItem(clone, 0.7)

		-- If the global monster cap temporarily delayed some planned mobs,
		-- a death opens a slot. Refill only the same/new active arena plans.
		task.defer(function()
			for _, plan in pairs(plansByIndex) do
				if plan
					and plan.Island
					and plan.Island.Parent
					and plan.Island:IsDescendantOf(workspace)
					and plan.Alive
					< plan.MaxAlive
					and plan.Island:GetAttribute(
						"CombatState"
					) == "Active"
				then
					attemptSpawnPlan(plan)
				end
			end
		end)
	end)

	if entry.SlimeDefinition then
		SlimeController.Start(
			entry,
			entry.SlimeDefinition,
			random,
			{
				OnTeleported = function(destinationIsland)
					entry.Island =
						destinationIsland
				end,
				OnExpired = function()
					if activeMonsters[clone] then
						unregisterMonster(clone)
					end

					if clone.Parent then
						clone:Destroy()
					end
				end,
			}
		)
	end

	AnimeOutline.Apply(clone)
	MobDamageFeedback.Bind(clone)

	clone.AncestryChanged:Connect(
		function(_, newParent)
			if not newParent then
				unregisterMonster(clone)
			end
		end
	)

	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	return true, clone
end

local function planFolders(plan)
	if plan.PointsFolder
		and plan.PointsFolder.Parent
		and plan.MonsterFolder
		and plan.MonsterFolder.Parent
	then
		return
	end

	local island = plan.Island

	local pointsFolder =
		island:FindFirstChild(
			"IslandCombatSpawnPoints"
		)

	if not pointsFolder then
		pointsFolder = Instance.new("Folder")
		pointsFolder.Name =
			"IslandCombatSpawnPoints"
		pointsFolder.Parent = island
	end

	pointsFolder:SetAttribute(
		"SpawnMode",
		"IslandCombat"
	)
	pointsFolder:SetAttribute(
		"MobLevel",
		plan.MobLevel
	)
	pointsFolder:SetAttribute(
		"MobLevelInCycle",
		plan.MobLevel
	)
	pointsFolder:SetAttribute(
		"CycleIndex",
		plan.CycleIndex
	)

	local monsterFolder =
		island:FindFirstChild(
			"IslandCombatMonsters"
		)

	if not monsterFolder then
		monsterFolder = Instance.new("Folder")
		monsterFolder.Name =
			"IslandCombatMonsters"
		monsterFolder.Parent = island
	end

	monsterFolder:SetAttribute(
		"SpawnMode",
		"IslandCombat"
	)
	monsterFolder:SetAttribute(
		"MobLevel",
		plan.MobLevel
	)
	monsterFolder:SetAttribute(
		"MobLevelInCycle",
		plan.MobLevel
	)
	monsterFolder:SetAttribute(
		"CycleIndex",
		plan.CycleIndex
	)

	plan.PointsFolder = pointsFolder
	plan.MonsterFolder = monsterFolder
end

attemptSpawnPlan = function(plan)
	if not plan
		or not plan.Island
		or not plan.Island.Parent
		or not plan.Island:IsDescendantOf(workspace)
	then
		return 0
	end

	if plan.Island:GetAttribute("CombatState")
		~= "Active"
	then
		return 0
	end

	-- Generation/detail population and Task 04 registration are asynchronous.
	-- Re-announce here so a temporary IslandNotRegistered response can never
	-- leave an otherwise valid arena with MobTargetCount=0 forever.
	local targetConfigured =
		IslandCombatService.SetTargetCount(
			plan.GlobalIslandIndex,
			plan.TargetCount
		)

	plan.Island:SetAttribute(
		"MobTargetCountAnnounced",
		targetConfigured == true
	)

	if targetConfigured ~= true then
		return 0
	end

	if plan.Spawning then
		return 0
	end

	if plan.Alive >= plan.MaxAlive then
		publishPlanConcurrency(plan)
		return 0
	end

	plan.Spawning = true
	planFolders(plan)

	local spawnedNow = 0

	while plan.Alive < plan.MaxAlive
		and monsterCount < getSpawnLimit()
	do
		local sequence = plan.Spawned + 1
		local cellIndex = ((sequence - 1) % #plan.Cells) + 1
		local cellRecord = plan.Cells[cellIndex]

		if not cellRecord then
			break
		end

		local marker =
			createMarker(
				plan.PointsFolder,
				cellRecord,
				sequence,
				plan.Template,
				"SkyDrop"
			)

		marker:SetAttribute(
			"SkyDrop",
			true
		)
		marker:SetAttribute(
			"SkyDropHeightStuds",
			IslandMobSpawnConfig
				.SkyDropHeightStuds
		)

		marker:SetAttribute(
			"IslandCombatManaged",
			true
		)
		marker:SetAttribute(
			"MobLevel",
			plan.MobLevel
		)
		marker:SetAttribute(
			"MobLevelInCycle",
			plan.MobLevel
		)
		marker:SetAttribute(
			"GlobalIslandIndex",
			plan.GlobalIslandIndex
		)
		marker:SetAttribute(
			"CycleIndex",
			plan.CycleIndex
		)

		local firstEngagement =
			sequence == 1
			and plan.FirstCombatEngagement
			or nil

		marker:SetAttribute(
			"FirstCombatEngagementPriority",
			firstEngagement ~= nil
		)

		marker:SetAttribute(
			"FirstCombatEngagementDistance",
			firstEngagement
				and firstEngagement.Distance
				or nil
		)

		local monsterRandom =
			Random.new(
				normalizedSeed(
					plan.Seed
					+ sequence * 101
				)
			)

		local rosterIndex = ((sequence - 1) % #plan.Roster) + 1
		local plannedVariant =
			plan.Roster[rosterIndex]
			or "Green"

		local plannedDefinition =
			IslandMobRosterConfig.GetVariant(
				plannedVariant
			)

		marker:SetAttribute(
			"SlimeVariant",
			plannedVariant
		)
		marker:SetAttribute(
			"MobThreatCost",
			plannedDefinition
				and plannedDefinition.ThreatCost
				or 1
		)
		marker:SetAttribute(
			"MobRosterVersion",
			IslandMobRosterConfig.Version
		)

		local success,
			spawnedModel =
			spawnClone(
				plan.Template,
				plan.MonsterFolder,
				plan.Island,
				cellRecord,
				marker,
				monsterRandom,
				"SkyDrop",
				plannedVariant,
				{
					GlobalIslandIndex =
					plan.GlobalIslandIndex,
					IslandCombatManaged = true,
					ForceHostile =
					not plan.InitialIsland,
					ForcePeaceful =
					plan.InitialIsland,
					InitialIsland =
					plan.InitialIsland,
					Role = "Common",
					SkyDrop = true,
					SkyDropHeightStuds =
					IslandMobSpawnConfig
					.SkyDropHeightStuds,
				}
			)

		if not success then
			marker:Destroy()
			break
		end

		if firstEngagement
			and spawnedModel
			and spawnedModel.Parent
		then
			spawnedModel:SetAttribute(
				"FirstCombatEngagementPriority",
				true
			)

			spawnedModel:SetAttribute(
				"FirstCombatEngagementDistance",
				firstEngagement.Distance
			)

			spawnedModel:SetAttribute(
				"FirstCombatEngagementReference",
				firstEngagement.ReferenceName
			)

			plan.Island:SetAttribute(
				"FirstCombatMobSpawnedAt",
				workspace:GetServerTimeNow()
			)

			plan.Island:SetAttribute(
				"FirstCombatMobSpawnedDistance",
				firstEngagement.Distance
			)
		end

		if marker.Parent then
			marker:Destroy()
		end

		plan.Spawned += 1
		plan.Alive += 1
		spawnedNow += 1

		plan.Island:SetAttribute(
			"MonsterSpawnCount",
			plan.Spawned
		)
		plan.Island:SetAttribute(
			"MobPlannedSpawnedCount",
			math.min(plan.Spawned, plan.TargetCount)
		)
		plan.Island:SetAttribute(
			"MobLifetimeSpawnedCount",
			plan.Spawned
		)

		publishPlanConcurrency(plan)

		if plan.YieldCallback then
			plan.YieldCallback()
		end

		if plan.Alive < plan.MaxAlive then
			task.wait(
				plan.SpawnStaggerSeconds
			)
		end
	end

	plan.Spawning = false

	local complete =
		plan.Alive >= plan.MaxAlive

	plan.Island:SetAttribute(
		"MonsterSpawnComplete",
		complete
	)
	plan.Island:SetAttribute(
		"MonsterSpawnDeferred",
		not complete
	)
	plan.Island:SetAttribute("MobInfiniteRespawnEnabled", true)
	plan.Island:SetAttribute(
		"MobRespawnPolicy",
		"RefillToMaxAliveWhileActive"
	)

	publishPlanConcurrency(plan)

	return spawnedNow
end

local function buildPlan(
	island,
	freeCells,
	context
)
	local existing =
		plansByIsland[island]

	if existing then
		return existing
	end

	local globalIndex =
		globalIslandIndex(island)

	if not globalIndex then
		return nil, "GlobalIslandIndexMissing"
	end

	local initialIsland =
		isInitialIsland(island, globalIndex)

	island:SetAttribute("IsInitialIsland", initialIsland)
	island:SetAttribute(
		"NumberedIslandIndex",
		math.max(0, globalIndex - 1)
	)
	island:SetAttribute(
		"IslandDisplayLabel",
		initialIsland
			and "Inicial"
			or string.format(
				"Ilha %d",
				globalIndex - 1
			)
	)
	island:SetAttribute(
		"InitialIslandMobScale",
		initialIsland
			and EarlyGamePacingConfig
			.InitialIslandModelScale
			or nil
	)
	island:SetAttribute(
		"InitialIslandMobXPRewardMultiplier",
		initialIsland
			and EarlyGamePacingConfig
			.InitialIslandXPRewardMultiplier
			or nil
	)

	local size =
		tostring(
			island:GetAttribute("TerrainSize")
			or "Small"
		)

	if not SIZE_RANK[size] then
		size = "Small"
	end

	local level =
		mobLevelInCycle(island, globalIndex)

	local mobCountCyclePosition =
		initialIsland
		and 0
		or IslandProgressionConfig
		.GetIslandIndexInCycle(globalIndex)

	-- A Ilha Inicial tem roster proprio de demonstracao. A numeracao real do
	-- roster comeca na Ilha 1, portanto o indice global precisa descontar a
	-- posicao inicial nao numerada.
	local rosterProgressionLevel =
		initialIsland
		and 0
		or math.max(1, globalIndex - 1)

	local defaultPlanned =
		IslandMobScalingConfig
		.GetPlannedMobCount(
			size,
			level
		)

	local earlyPacingOverride =
		EarlyGamePacingConfig
		.GetOverride(
			globalIndex
		)

	local planned =
		EarlyGamePacingConfig
		.GetTargetCount(
			globalIndex,
			defaultPlanned
		)

	local available =
		validCells(freeCells)
	local tutorialEnemyArea

	if initialIsland then
		local tutorialCells,
			area =
			TutorialIslandTemplateService
			.GetEnemySpawnCells(
				island,
				planned,
				context
				and context.GridSize
				or 5
			)

		if #tutorialCells > 0 then
			available = tutorialCells
			tutorialEnemyArea = area
			island:SetAttribute(
				"MobSpawnAreaSource",
				"TutorialIslandTemplate.areaEnemy"
			)
			island:SetAttribute(
				"TutorialEnemyAreaSpawnEnabled",
				true
			)
		else
			island:SetAttribute(
				"MobSpawnAreaSource",
				"ProceduralFreeCellsFallback"
			)
			island:SetAttribute(
				"TutorialEnemyAreaSpawnEnabled",
				false
			)
		end

		island:SetAttribute(
			"TutorialMobBehaviorPolicy",
			"PassiveNoAggroBoundedToAreaEnemy"
		)
		island:SetAttribute(
			"TutorialMobsCanDamagePlayers",
			false
		)
	end

	local target =
		math.min(
			planned,
			#available
		)

	if target <= 0 then
		island:SetAttribute(
			"MobPlanError",
			"NoFreeSpawnCells"
		)

		return nil, "NoFreeSpawnCells"
	end

	local islandSeed =
		tonumber(
			island:GetAttribute("IslandSeed")
		)

	local terrainId =
		tonumber(
			island:GetAttribute("TerrainId")
		) or 1

	local baseSeed =
		islandSeed
		or tonumber(
			context
			and context.RoundSeed
		)
		or 1

	local seed =
		normalizedSeed(
			baseSeed
			+ terrainId * 7907
			+ globalIndex * 104729
			+ CONFIG.RANDOM_SALT
		)

	local random = Random.new(seed)

	local cells =
		selectSpawnCells(
			available,
			target,
			IslandMobScalingConfig
			.MinimumSpawnSpacingStuds,
			random
		)

	local engagementInfo

	cells,
		engagementInfo =
		prioritizeFirstCombatCell(
			cells,
			island,
			globalIndex
		)

	target = #cells

	if target <= 0 then
		return nil, "SpawnCellSelectionFailed"
	end

	local template =
		regularTemplate()

	if not template then
		return nil, "MonsterTemplateMissing"
	end

	local rosterSnapshot
	if initialIsland then
		rosterSnapshot =
			IslandMobRosterConfig.BuildDemonstrationRoster(
				target,
				seed + 17749
			)
	else
		rosterSnapshot =
			IslandMobRosterConfig.BuildRoster(
				target,
				rosterProgressionLevel,
				seed + 17749
			)
	end

	local plan = {
		Island = island,
		GlobalIslandIndex =
			globalIndex,
		CycleIndex =
			islandCycleIndex(
				island,
				globalIndex
			),

		FirstCombatEngagement =
			engagementInfo,

		TutorialEnemyArea =
			tutorialEnemyArea,

		NavigationCells =
			initialIsland
			and available
			or nil,

		InitialIsland =
			initialIsland,

		MobLevel = level,
		MobCountCyclePosition =
			mobCountCyclePosition,
		RosterProgressionLevel =
			rosterProgressionLevel,
		IslandSize = size,
		Seed = seed,
		Template = template,
		Cells = cells,
		Roster = rosterSnapshot.Roster,
		RosterSnapshot = rosterSnapshot,
		-- TargetCount is the route kill quota, not a lifetime spawn cap.
		TargetCount = target,
		KillQuota = target,
		DefaultTargetCount =
			defaultPlanned,
		EarlyPacingOverride =
			earlyPacingOverride,
		MaxAlive =
			EarlyGamePacingConfig
			.GetMaximumAlive(
				globalIndex,
				IslandMobSpawnConfig
				.GetMaximumAlive(
					target
				),
				target
			),
		SpawnStaggerSeconds =
			EarlyGamePacingConfig
			.GetSpawnStaggerSeconds(
				globalIndex,
				IslandMobSpawnConfig
				.SpawnStaggerSeconds
			),
		Spawned = 0,
		Alive = 0,
		Spawning = false,
		YieldCallback =
			context
			and context.YieldCallback
			or nil,
		StateConnection = nil,
	}

	plansByIsland[island] = plan
	plansByIndex[globalIndex] = plan

	island:SetAttribute(
		"CanSpawnMonster",
		true
	)
	island:SetAttribute(
		"MonsterSpawnGuaranteed",
		true
	)
	island:SetAttribute(
		"MonsterSpawnChance",
		1
	)
	island:SetAttribute(
		"MonsterSpawnMode",
		"SkyDrop"
	)
	island:SetAttribute(
		"MobMaxAlive",
		plan.MaxAlive
	)
	island:SetAttribute(
		"MobSpawnPresentation",
		"SkyDrop"
	)
	island:SetAttribute(
		"MobSpawnStaggerSeconds",
		plan.SpawnStaggerSeconds
	)
	island:SetAttribute(
		"MobSkyDropHeightStuds",
		IslandMobSpawnConfig.SkyDropHeightStuds
	)
	island:SetAttribute(
		"MobLevel",
		level
	)
	island:SetAttribute(
		"MobLevelInCycle",
		level
	)
	island:SetAttribute(
		"MobCycleIndex",
		plan.CycleIndex
	)
	local planCycleMultipliers =
		IslandMobScalingConfig.GetCycleMultipliers(
			plan.CycleIndex
		)
	island:SetAttribute(
		"MobCycleHealthMultiplier",
		planCycleMultipliers.Health
	)
	island:SetAttribute(
		"MobCycleDamageMultiplier",
		planCycleMultipliers.Damage
	)
	island:SetAttribute(
		"MobCycleSpeedMultiplier",
		planCycleMultipliers.Speed
	)
	island:SetAttribute(
		"MobPlannedTargetCount",
		target
	)
	island:SetAttribute(
		"MobCountCyclePosition",
		plan.MobCountCyclePosition
	)
	island:SetAttribute(
		"MobCountProgressionPolicy",
		"ThreePlusOnePerNumberedIsland"
	)
	island:SetAttribute(
		"MobCountResetsEachCycle",
		true
	)
	island:SetAttribute(
		"MobCountBasePerCycle",
		IslandMobScalingConfig.BaseMobsPerCycle
	)
	island:SetAttribute(
		"MobCountIncreasePerIsland",
		IslandMobScalingConfig.ExtraMobsPerIsland
	)
	island:SetAttribute("MobKillQuota", target)
	island:SetAttribute("MobInfiniteRespawnEnabled", true)
	island:SetAttribute(
		"MobRespawnPolicy",
		"RefillToMaxAliveWhileActive"
	)
	island:SetAttribute(
		"MobDefaultTargetCount",
		defaultPlanned
	)
	island:SetAttribute(
		"EarlyGamePacingVersion",
		EarlyGamePacingConfig.Version
	)
	island:SetAttribute(
		"EarlyGamePacingApplied",
		earlyPacingOverride ~= nil
	)
	island:SetAttribute(
		"EarlyGamePacingTargetOverridden",
		earlyPacingOverride ~= nil
			and earlyPacingOverride.TargetCount ~= nil
	)
	island:SetAttribute(
		"EarlyGamePacingExpectedOutcome",
		earlyPacingOverride
			and earlyPacingOverride.ExpectedOutcome
			or nil
	)

	island:SetAttribute(
		"FirstCombatEngagementVersion",
		FirstCombatEngagementConfig.Version
	)

	island:SetAttribute(
		"FirstCombatEngagementApplied",
		engagementInfo ~= nil
	)

	island:SetAttribute(
		"FirstCombatReferenceName",
		engagementInfo
			and engagementInfo.ReferenceName
			or nil
	)

	island:SetAttribute(
		"FirstCombatEnemyPlannedDistance",
		engagementInfo
			and engagementInfo.Distance
			or nil
	)

	island:SetAttribute(
		"FirstCombatEnemyWithinPreferredBand",
		engagementInfo
			and engagementInfo.WithinPreferredBand
			or nil
	)
	island:SetAttribute(
		"MobPlannedSpawnedCount",
		0
	)
	island:SetAttribute(
		"MobPlanVersion",
		IslandMobScalingConfig.Version
	)
	island:SetAttribute(
		"MobRosterVersion",
		IslandMobRosterConfig.Version
	)
	island:SetAttribute(
		"MobRosterProgressionLevel",
		plan.RosterProgressionLevel
	)
	island:SetAttribute(
		"MobThreatBudget",
		rosterSnapshot.ThreatBudget
	)
	island:SetAttribute(
		"MobThreatUsed",
		rosterSnapshot.ThreatUsed
	)
	island:SetAttribute(
		"MobGreenCount",
		rosterSnapshot.GreenCount
	)
	island:SetAttribute(
		"MobAdvancedCount",
		rosterSnapshot.AdvancedCount
	)
	island:SetAttribute(
		"MobAdvancedOnly",
		rosterSnapshot.AdvancedOnly == true
	)
	island:SetAttribute(
		"MobRangedCount",
		rosterSnapshot.RangedCount
	)
	island:SetAttribute(
		"MobSpecialCount",
		rosterSnapshot.SpecialCount
	)
	island:SetAttribute(
		"MobNewestUnlockedVariant",
		rosterSnapshot.NewestUnlockedVariant
	)
	island:SetAttribute(
		"MobNewestVariantGuaranteed",
		rosterSnapshot.NewestVariantGuaranteed
	)
	island:SetAttribute(
		"MobRosterSummary",
		table.concat(
			rosterSnapshot.Roster,
			","
		)
	)
	island:SetAttribute(
		"MobPlanSeed",
		seed
	)
	island:SetAttribute(
		"MobDifficultySource",
		"StrongerBaseLevelAndCycleV5"
	)
	island:SetAttribute(
		"LegacyRoundDifficultyDisabled",
		true
	)

	local configured =
		IslandCombatService.SetTargetCount(
			globalIndex,
			target
		)

	island:SetAttribute(
		"MobTargetCountAnnounced",
		configured == true
	)

	publishPlanConcurrency(plan)

	plan.StateConnection =
		island:GetAttributeChangedSignal(
			"CombatState"
		):Connect(function()
		if island:GetAttribute(
			"CombatState"
			) == "Active"
		then
			task.defer(
				attemptSpawnPlan,
				plan
			)
		end
	end)

	island.Destroying:Connect(function()
		if plan.StateConnection then
			plan.StateConnection:Disconnect()
			plan.StateConnection = nil
		end

		plansByIsland[island] = nil

		if plansByIndex[globalIndex]
			== plan
		then
			plansByIndex[globalIndex] = nil
		end
	end)

	return plan
end

local function objectiveSurfacePosition(
	island,
	spawnMarker,
	sequence
)
	local base = spawnMarker.Position
	local candidates = { base }

	local angleOffset =
		sequence * 2.399963229728653

	for ring = 1, CONFIG.OBJECTIVE_RING_COUNT do
		local radius =
			CONFIG.OBJECTIVE_RING_STEP * ring

		for slot = 1,
			CONFIG.OBJECTIVE_RING_SLOTS
		do
			local angle =
				angleOffset
				+ (
					(slot - 1)
					/ CONFIG.OBJECTIVE_RING_SLOTS
				)
				* math.pi
				* 2

			table.insert(
				candidates,
				base
					+ Vector3.new(
						math.cos(angle) * radius,
						0,
						math.sin(angle) * radius
					)
			)
		end
	end

	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local excluded = {}

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		if player.Character then
			table.insert(
				excluded,
				player.Character
			)
		end
	end

	params.FilterDescendantsInstances =
		excluded

	for _, candidate in ipairs(candidates) do
		local result =
			workspace:Raycast(
				candidate
				+ Vector3.new(0, 18, 0),
				Vector3.new(0, -42, 0),
				params
			)

		if result
			and result.Instance
			and result.Instance:IsDescendantOf(
				island
			)
		then
			local tooClose = false

			for _, player in ipairs(
				Players:GetPlayers()
				) do
				local character =
					player.Character
				local root =
					character
					and character:FindFirstChild(
						"HumanoidRootPart"
					)

				if root
					and horizontalDistance(
						root.Position,
						result.Position
					)
						< CONFIG
						.OBJECTIVE_MIN_PLAYER_SPACING
				then
					tooClose = true
					break
				end
			end

			if not tooClose then
				return result.Position
			end
		end
	end

	return base
end

local function initialize()
	if initialized then
		return
	end

	initialized = true

	workspace:SetAttribute(
		"DungeonMonsterSpawnerVersion",
		IslandMobScalingConfig.Version
	)
	workspace:SetAttribute(
		"DungeonMobDifficultyAuthority",
		"LevelInCycleAndCycleIndex"
	)
	workspace:SetAttribute(
		"DungeonMobUsesPlayerLevel",
		false
	)
	workspace:SetAttribute(
		"DungeonMobUsesRoundDifficulty",
		false
	)
	workspace:SetAttribute(
		"DungeonRegularMobSpawnChance",
		1
	)
	workspace:SetAttribute(
		"DungeonRegularMobRosterPolicy",
		"FirstIslandGreenThenAdvancedOnlyV3"
	)
	workspace:SetAttribute(
		"DungeonMobRosterVersion",
		IslandMobRosterConfig.Version
	)
	workspace:SetAttribute(
		"DungeonMobRosterUnlocks",
		"Green1,Blue2,Red3,Fire4,Ice5,Lightning6"
	)
	workspace:SetAttribute(
		"DungeonGoldenSlimeInRegularRoster",
		false
	)
	workspace:SetAttribute(
		"DungeonMobMinimumGreenRatio",
		IslandMobRosterConfig.MinimumGreenRatio
	)
	workspace:SetAttribute(
		"DungeonMobMaximumRangedRatio",
		IslandMobRosterConfig.MaximumRangedRatio
	)
	workspace:SetAttribute(
		"DungeonMobMaximumSpecialRatio",
		IslandMobRosterConfig.MaximumSpecialRatio
	)
	workspace:SetAttribute(
		"DungeonMobHealthPerLevel",
		IslandMobScalingConfig
			.HealthPerLevel
	)
	workspace:SetAttribute(
		"DungeonMobBaseHealthMultiplier",
		IslandMobScalingConfig.BaseHealthMultiplier
	)
	workspace:SetAttribute(
		"DungeonMobDamagePerLevel",
		IslandMobScalingConfig
			.DamagePerLevel
	)
	workspace:SetAttribute(
		"DungeonMobBaseDamageMultiplier",
		IslandMobScalingConfig.BaseDamageMultiplier
	)
	workspace:SetAttribute(
		"DungeonFireSlimeBaseDamageMultiplier",
		2.5
	)
	workspace:SetAttribute(
		"DungeonFireSlimeGroundUsesMobScaling",
		true
	)
	workspace:SetAttribute(
		"DungeonMobHealthPerCycle",
		IslandMobScalingConfig.HealthPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobDamagePerCycle",
		IslandMobScalingConfig.DamagePerCycle
	)
	workspace:SetAttribute(
		"DungeonMobSpeedPerCycle",
		IslandMobScalingConfig.SpeedPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobCycleScalingPolicy",
		"CompoundedFromCycleIndex"
	)
	workspace:SetAttribute(
		"DungeonMobCountProgressionPolicy",
		"NumberedCycle3To14ThenReset"
	)
	workspace:SetAttribute(
		"DungeonMobCountBasePerCycle",
		IslandMobScalingConfig.BaseMobsPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobCountIncreasePerIsland",
		IslandMobScalingConfig.ExtraMobsPerIsland
	)
	workspace:SetAttribute(
		"DungeonMobCountMaximumPerIsland",
		IslandMobScalingConfig.MaximumMobsPerIsland
	)
	workspace:SetAttribute(
		"DungeonMobXPVersion",
		MobXPConfig.Version
	)
	workspace:SetAttribute(
		"DungeonMobXPPerCycle",
		IslandProgressionConfig.XPRewardPerCycle
	)
	workspace:SetAttribute(
		"DungeonMobXPCyclePolicy",
		"CompoundedFromCycleIndexBeforeRiskBonus"
	)
	workspace:SetAttribute(
		"DungeonMobXPAwardPolicy",
		MobXPConfig.AwardPolicy
	)
	workspace:SetAttribute(
		"DungeonMobXPLevelRewardPerLevel",
		MobXPConfig.LevelRewardPerLevel
	)
	workspace:SetAttribute(
		"DungeonMobXPRiskBonusPerLevel",
		MobXPConfig.RiskBonusPerLevel
	)
	workspace:SetAttribute(
		"DungeonMobXPMaximumRiskBonus",
		MobXPConfig.MaximumRiskBonus
	)
	workspace:SetAttribute(
		"DungeonMobXPLowerLevelPenalty",
		0
	)
	workspace:SetAttribute(
		"DungeonMobSpawnConcurrencyVersion",
		IslandMobSpawnConfig.Version
	)
	workspace:SetAttribute(
		"DungeonMobSpawnPresentation",
		"SkyDrop"
	)
	workspace:SetAttribute(
		"DungeonMobDefaultMaxAlive",
		IslandMobSpawnConfig.DefaultMaximumAlive
	)
	workspace:SetAttribute(
		"DungeonMobSpawnStaggerSeconds",
		IslandMobSpawnConfig.SpawnStaggerSeconds
	)
	workspace:SetAttribute(
		"DungeonMobSkyDropHeightStuds",
		IslandMobSpawnConfig.SkyDropHeightStuds
	)
	workspace:SetAttribute("DungeonInfiniteIslandMobs", true)
	workspace:SetAttribute(
		"DungeonMobRespawnPolicy",
		"RefillToMaxAliveWhileActive"
	)
	workspace:SetAttribute(
		"DungeonMobProgressionPolicy",
		"KillQuotaUnlocksNextIsland"
	)
	workspace:SetAttribute(
		"DungeonInitialIslandIsNumbered",
		false
	)
	workspace:SetAttribute(
		"DungeonFirstNumberedGlobalIslandIndex",
		2
	)
	workspace:SetAttribute(
		"DungeonInitialIslandMobScale",
		EarlyGamePacingConfig.InitialIslandModelScale
	)
	workspace:SetAttribute(
		"DungeonInitialIslandMobXPRewardMultiplier",
		EarlyGamePacingConfig
			.InitialIslandXPRewardMultiplier
	)
	workspace:SetAttribute(
		"DungeonEarlyGamePacingVersion",
		EarlyGamePacingConfig.Version
	)
	workspace:SetAttribute(
		"DungeonEarlyGamePacingPolicy",
		EarlyGamePacingConfig.Policy
	)
	workspace:SetAttribute(
		"DungeonEarlyGameIsland1Target",
		EarlyGamePacingConfig
			.GetTargetCount(1, 3)
	)
	workspace:SetAttribute(
		"DungeonEarlyGameIsland1MaxAlive",
		EarlyGamePacingConfig
			.GetMaximumAlive(
				1,
				7,
				5
			)
	)
	workspace:SetAttribute(
		"DungeonEarlyGameIsland2Target",
		EarlyGamePacingConfig
			.GetTargetCount(2, 3)
	)
	workspace:SetAttribute(
		"DungeonEarlyGameExpectedFirstLevelUp",
		"Island1Clear"
	)
	workspace:SetAttribute(
		"DungeonEarlyGameExpectedSecondLevelUp",
		"Island3FirstKill"
	)

	workspace:SetAttribute(
		"DungeonFirstCombatEngagementVersion",
		FirstCombatEngagementConfig.Version
	)

	workspace:SetAttribute(
		"DungeonFirstCombatEngagementPolicy",
		FirstCombatEngagementConfig.Policy
	)

	workspace:SetAttribute(
		"DungeonFirstCombatPreferredDistance",
		FirstCombatEngagementConfig.PreferredFirstEnemyDistance
	)

	workspace:SetAttribute(
		"DungeonFirstCombatMinimumDistance",
		FirstCombatEngagementConfig.MinimumFirstEnemyDistance
	)

	workspace:SetAttribute(
		"DungeonFirstCombatMaximumDistance",
		FirstCombatEngagementConfig.MaximumFirstEnemyDistance
	)

	workspace:SetAttribute(
		"DungeonCombatFeedbackEventSource",
		"MobXPFeedbackSerial"
	)
	workspace:SetAttribute(
		"DungeonCombatFeedbackLevelUpSource",
		"PlayerLevelUpSerial"
	)

	task.spawn(function()
		while true do
			task.wait(
				IslandMobSpawnConfig
					.RefillCheckSeconds
			)

			for _, plan in pairs(
				plansByIndex
				) do
				if plan
					and plan.Island
					and plan.Island.Parent
					and plan.Island:IsDescendantOf(workspace)
					and plan.Alive
					< plan.MaxAlive
					and plan.Island:GetAttribute(
						"CombatState"
					) == "Active"
				then
					attemptSpawnPlan(plan)
				end
			end
		end
	end)
end

function MonsterSpawner.PopulateIsland(
	island,
	freeCells,
	context
)
	initialize()

	assert(
		island
			and island:IsA("Model"),
		"[MonsterSpawner] Ilha invalida."
	)

	assert(
		typeof(freeCells) == "table",
		"[MonsterSpawner] freeCells precisa ser tabela."
	)

	context =
		type(context) == "table"
		and context
		or {}

	SlimeController.RegisterIsland(
		island,
		freeCells
	)

	if not isLinearCombatIsland(island) then
		return 0
	end

	local plan, errorCode =
		buildPlan(
			island,
			freeCells,
			context
		)

	if not plan then
		island:SetAttribute(
			"MobPlanError",
			tostring(errorCode)
		)

		warn(
			"[MonsterSpawner] Falha ao planejar "
				.. island:GetFullName()
				.. ": "
				.. tostring(errorCode)
		)

		return 0
	end

	if plan.InitialIsland
		and plan.NavigationCells
	then
		SlimeController.RegisterIsland(
			island,
			plan.NavigationCells
		)
	end

	island:SetAttribute(
		"MobPlanError",
		nil
	)

	-- Future islands stay lightweight. Spawn happens only after Task 04 marks
	-- this island Active.
	if island:GetAttribute("CombatState")
		~= "Active"
	then
		island:SetAttribute(
			"MonsterSpawnDeferred",
			true
		)

		return 0
	end

	task.defer(
		attemptSpawnPlan,
		plan
	)

	return 0
end

function MonsterSpawner.SpawnObjectiveMonster(
	island,
	spawnMarker,
	spawnOptions
)
	initialize()

	if not island
		or not island:IsA("Model")
	then
		return nil, "InvalidIsland"
	end

	if not spawnMarker
		or not spawnMarker:IsA("BasePart")
	then
		return nil, "InvalidSpawnMarker"
	end

	spawnOptions =
		type(spawnOptions) == "table"
		and table.clone(spawnOptions)
		or {}

	local encounterId =
		tostring(
			spawnOptions.EncounterId
			or ""
		)

	if encounterId == "" then
		return nil, "EncounterIdMissing"
	end

	if monsterCount >= getSpawnLimit() then
		return nil, "GlobalMonsterLimitReached"
	end

	local template =
		objectiveTemplate(spawnOptions)

	if not template then
		return nil, "MonsterTemplateMissing"
	end

	local content =
		island:FindFirstChild(
			"ObjectiveEncounterContent"
		)

	if not content then
		content = Instance.new("Folder")
		content.Name =
			"ObjectiveEncounterContent"
		content.Parent = island
	end

	local encounterFolder =
		content:FindFirstChild(encounterId)

	if not encounterFolder then
		encounterFolder = Instance.new("Folder")
		encounterFolder.Name = encounterId
		encounterFolder:SetAttribute(
			"ObjectiveEncounterId",
			encounterId
		)
		encounterFolder:SetAttribute(
			"ObjectiveId",
			spawnOptions.ObjectiveId
		)
		encounterFolder.Parent = content
	end

	local pointsFolder =
		encounterFolder:FindFirstChild(
			"SpawnPoints"
		)

	if not pointsFolder then
		pointsFolder = Instance.new("Folder")
		pointsFolder.Name = "SpawnPoints"
		pointsFolder.Parent =
			encounterFolder
	end

	local monsterFolder =
		encounterFolder:FindFirstChild(
			"Monsters"
		)

	if not monsterFolder then
		monsterFolder = Instance.new("Folder")
		monsterFolder.Name = "Monsters"
		monsterFolder.Parent =
			encounterFolder
	end

	local sequence =
		math.max(
			1,
			math.floor(
				tonumber(
					spawnOptions
					.SpawnSequence
				)
				or (
					#pointsFolder:GetChildren()
					+ 1
				)
			)
		)

	local surfacePosition =
		objectiveSurfacePosition(
			island,
			spawnMarker,
			sequence
		)

	local cellRecord = {
		Cell = Vector3.new(
			tonumber(
				spawnMarker:GetAttribute(
					"GridX"
				)
			) or 0,
			tonumber(
				spawnMarker:GetAttribute(
					"GridY"
				)
			) or 0,
			tonumber(
				spawnMarker:GetAttribute(
					"GridZ"
				)
			) or 0
		),
		SurfacePosition =
			surfacePosition,
	}

	local marker =
		createMarker(
			pointsFolder,
			cellRecord,
			sequence,
			template,
			"Solo"
		)

	marker:SetAttribute(
		"ObjectiveEncounterId",
		encounterId
	)
	marker:SetAttribute(
		"ObjectiveId",
		spawnOptions.ObjectiveId
	)
	marker:SetAttribute(
		"MonsterRole",
		spawnOptions.Role
			or "Common"
	)

	local seed =
		normalizedSeed(
			tonumber(spawnOptions.Seed)
			or (
				tonumber(
					island:GetAttribute(
						"IslandSeed"
					)
				) or 1
			)
			+ sequence * 104729
		)

	local variant =
		spawnOptions.SlimeVariant

	if variant == nil then
		variant =
			spawnOptions.Role == "Ranged"
			and "Blue"
			or (
				spawnOptions.Role
				== "Elite"
				and "Red"
				or "Green"
			)
	end

	-- Critical migration rule:
	-- legacy objective mobs do not belong to the new arena target count.
	spawnOptions.IslandCombatManaged = false
	spawnOptions.GlobalIslandIndex =
		spawnOptions.GlobalIslandIndex
		or globalIslandIndex(island)

	local spawned, clone, errorCode =
		spawnClone(
			template,
			monsterFolder,
			island,
			cellRecord,
			marker,
			Random.new(seed),
			"Solo",
			variant,
			spawnOptions
		)

	if not spawned or not clone then
		marker:Destroy()

		return
			nil,
			errorCode
			or "SpawnCloneFailed"
	end

	island:SetAttribute(
		"ObjectiveEncounterManaged",
		true
	)

	return clone
end

function MonsterSpawner.GetObjectiveActiveCount(
	encounterId
)
	local count = 0

	for model, entry in pairs(
		activeMonsters
		) do
		if model.Parent
			and entry.Humanoid.Health > 0
			and model:GetAttribute(
				"ObjectiveSpawned"
			) == true
				and (
					encounterId == nil
					or model:GetAttribute(
						"ObjectiveEncounterId"
					) == encounterId
				)
		then
			count += 1
		end
	end

	return count
end

function MonsterSpawner.SetObjectiveMonstersActive(
	encounterId,
	active
)
	active = active == true

	local changed = 0

	for model, entry in pairs(
		activeMonsters
		) do
		if model.Parent
			and model:GetAttribute(
				"ObjectiveSpawned"
			) == true
				and (
					encounterId == nil
					or model:GetAttribute(
						"ObjectiveEncounterId"
					) == encounterId
				)
		then
			model:SetAttribute(
				"SimulationActive",
				active
			)
			model:SetAttribute(
				"Invulnerable",
				not active
			)

			if not active
				and entry.Root
				and entry.Root.Parent
			then
				entry.Humanoid:MoveTo(
					entry.Root.Position
				)
				entry.Humanoid:Move(
					Vector3.zero
				)
			end

			changed += 1
		end
	end

	return changed
end

function MonsterSpawner.DespawnObjectiveMonsters(
	encounterId
)
	local targets = {}

	for model in pairs(activeMonsters) do
		if model:GetAttribute(
			"ObjectiveSpawned"
			) == true
				and (
					encounterId == nil
					or model:GetAttribute(
						"ObjectiveEncounterId"
					) == encounterId
				)
		then
			table.insert(targets, model)
		end
	end

	for _, model in ipairs(targets) do
		unregisterMonster(model)

		if model.Parent then
			model:Destroy()
		end
	end

	return #targets
end

function MonsterSpawner.DamageMonster(
	player,
	model,
	damage
)
	local runtimeModel = model
	local entry = activeMonsters[runtimeModel]

	while not entry
		and runtimeModel
		and runtimeModel ~= workspace
	do
		runtimeModel = runtimeModel.Parent
		entry =
			runtimeModel
			and activeMonsters[
		runtimeModel
		]
	end

	if not entry
		or entry.Humanoid.Health <= 0
	then
		return false
	end

	entry.LastDamager = player

	return CombatDamageService.ApplyDirectHit(
		player,
		{
			Model = entry.Model,
			Humanoid = entry.Humanoid,
			Root = entry.Root,
		},
		damage,
		"MonsterDamage"
	)
end

function MonsterSpawner.GetActiveCount()
	return monsterCount
end

function MonsterSpawner.GetCombatTargets()
	local targets = {}

	for model, entry in pairs(
		activeMonsters
		) do
		if model.Parent
			and entry.Root
			and entry.Root.Parent
			and entry.Humanoid.Health > 0
		then
			table.insert(
				targets,
				{
					Model = model,
					Humanoid =
						entry.Humanoid,
					Root = entry.Root,
				}
			)
		end
	end

	return targets
end

function MonsterSpawner.GetIslandPlan(
	islandOrIndex
)
	local plan

	if typeof(islandOrIndex) == "Instance" then
		plan =
			plansByIsland[islandOrIndex]
	else
		plan =
			plansByIndex[
		cleanIndex(islandOrIndex)
		]
	end

	if not plan then
		return nil
	end

	return {
		Version =
			IslandMobScalingConfig.Version,
		GlobalIslandIndex =
			plan.GlobalIslandIndex,
		InitialIsland =
			plan.InitialIsland,
		NumberedIslandIndex =
			math.max(
				0,
				plan.GlobalIslandIndex - 1
			),
		CycleIndex =
			plan.CycleIndex,
		MobCountCyclePosition =
			plan.MobCountCyclePosition,
		MobLevel =
			plan.MobLevel,
		MobLevelInCycle =
			plan.MobLevel,
		IslandSize =
			plan.IslandSize,
		TargetCount =
			plan.TargetCount,
		SpawnedCount =
			plan.Spawned,
		Complete =
			plan.Alive >= plan.MaxAlive,
		InfiniteRespawnEnabled = true,
		KillQuota = plan.TargetCount,
		LifetimeSpawnedCount = plan.Spawned,
		Seed =
			plan.Seed,
		Roster =
			table.clone(plan.Roster),
		ThreatBudget =
			plan.RosterSnapshot
			and plan.RosterSnapshot.ThreatBudget
			or nil,
		ThreatUsed =
			plan.RosterSnapshot
			and plan.RosterSnapshot.ThreatUsed
			or nil,
		GreenCount =
			plan.RosterSnapshot
			and plan.RosterSnapshot.GreenCount
			or nil,
		RangedCount =
			plan.RosterSnapshot
			and plan.RosterSnapshot.RangedCount
			or nil,
		SpecialCount =
			plan.RosterSnapshot
			and plan.RosterSnapshot.SpecialCount
			or nil,
		MaximumAlive =
			plan.MaxAlive,
		ActiveAlive =
			plan.Alive,
		PendingSpawnCount =
			math.max(
				0,
				plan.MaxAlive
				- plan.Alive
			),
		SpawnPresentation =
			"SkyDrop",
		SpawnStaggerSeconds =
			plan.SpawnStaggerSeconds,
		DefaultTargetCount =
			plan.DefaultTargetCount,
		EarlyGamePacingApplied =
			plan.EarlyPacingOverride
			~= nil,
		EarlyGamePacingVersion =
			EarlyGamePacingConfig.Version,
	}
end

initialize()

return MonsterSpawner
