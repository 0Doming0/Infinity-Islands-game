--[[
	Infinity Islands - Progression Unblock Guard V2

	Conservative recovery authority for live-MVP progression deadlocks.

	Covers:
	1. Shared island already Cleared while a player still personally needs it.
	   Index 1 restores only missing tutorial XP; index 2+ also catches up the
	   player's personal checkpoint.
	2. Active required island with no announced target and no mobs.
	3. Active required island with an announced quota, zero living mobs and
	   DefeatedCount still below TargetCount.

	Normal MonsterSpawner/IslandCombatService behavior always gets a grace
	period first. Recovery mobs are outside the island hierarchy so the finite
	lifetime hard-cap cannot reject a replacement for a mob that disappeared.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(
	ServerScriptService.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local MonsterSpawner = require(
	ServerScriptService.BlockParkour:WaitForChild("MonsterSpawner")
)
local DungeonGenerator = require(
	ServerScriptService.DungeonRuntime:WaitForChild("DungeonGenerator")
)
local IslandCombatService = require(
	ServerScriptService.DungeonRuntime:WaitForChild("IslandCombatService")
)
local PlayerLevelService = require(
	ServerScriptService.DungeonRuntime:WaitForChild("PlayerLevelService")
)

local IslandProgressionConfig = require(
	ReplicatedStorage.Shared.Configs.IslandProgressionConfig
)
local MobXPConfig = require(
	ReplicatedStorage.Shared.Configs.MobXPConfig
)

local VERSION = "ProgressionUnblockGuardV2"
local CHECK_SECONDS = 0.75
local STALL_GRACE_SECONDS = 5
local SHARED_CLEAR_GRACE_SECONDS = 1.5
local INITIAL_SHARED_CLEAR_GRACE_SECONDS = 2.5
local EMERGENCY_TARGET_LIFETIME_SECONDS = 90

local emergencyTargetByIndex = {}
local stalledSince = {}
local clearSeenAt = setmetatable({}, { __mode = "k" })
local recovered = setmetatable({}, { __mode = "k" })
local entryXP = setmetatable({}, { __mode = "k" })

local sharedClearRecoveryCount = 0
local initialSharedClearRecoveryCount = 0
local emergencySpawnCount = 0
local blockedNoMobsCount = 0
local stalledQuotaRecoveryCount = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return math.max(1, math.floor(number))
end

local function routeCap()
	local ok, plan = pcall(DungeonGenerator.GetRoutePlan)
	return ok
		and math.max(2, math.floor(tonumber(plan and plan.TotalIslandCount) or 2))
		or 2
end

local function playerNeedsIsland(player, islandIndex)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute("IslandProgressPersistenceReady") ~= true
	then
		return false
	end

	return cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex")) == islandIndex
		and cleanIndex(player:GetAttribute("SavedResumeIslandIndex")) == islandIndex
		and player:GetAttribute("LastPersonalIslandCompleted") ~= islandIndex
end

local function rememberEntryXP(player, islandIndex)
	if not playerNeedsIsland(player, islandIndex) then
		return
	end
	local perIsland = entryXP[player]
	if not perIsland then
		perIsland = {}
		entryXP[player] = perIsland
	end
	if perIsland[islandIndex] == nil then
		perIsland[islandIndex] = math.max(
			0,
			math.floor(tonumber(player:GetAttribute("PlayerTotalXP")) or 0)
		)
	end
end

local function expectedIslandXP(player, islandIndex)
	local plan = MonsterSpawner.GetIslandPlan(islandIndex)
	if type(plan) ~= "table"
		or type(plan.Roster) ~= "table"
		or #plan.Roster <= 0
	then
		-- Current early-game contract: the unnumbered initial island pays 18 XP.
		return islandIndex == 1 and 18 or 0
	end

	local mobLevel = math.max(
		1,
		math.floor(tonumber(plan.MobLevel)
			or IslandProgressionConfig.GetLevelInCycle(islandIndex))
	)
	local cycleIndex = math.max(
		1,
		math.floor(tonumber(plan.CycleIndex)
			or IslandProgressionConfig.GetCycleIndex(islandIndex))
	)
	local riskLevel = math.max(
		1,
		math.floor(IslandProgressionConfig.GetIslandLevel(islandIndex))
	)
	local playerLevel = math.max(
		1,
		math.floor(tonumber(player:GetAttribute("PlayerLevel")) or 1)
	)
	local cycleXP = IslandProgressionConfig.GetXPRewardMultiplier(cycleIndex)
	local total = 0

	for _, variant in ipairs(plan.Roster) do
		local reward = MobXPConfig.GetMobXPReward(
			tostring(variant or "Green"),
			mobLevel,
			cycleXP
		)
		if islandIndex == 1 then
			reward = math.max(
				MobXPConfig.MinimumReward,
				math.floor(reward * 0.5 + 0.5)
			)
		end
		local amount = MobXPConfig.GetAwardForPlayer(
			reward,
			riskLevel,
			playerLevel
		)
		total += math.max(0, tonumber(amount) or 0)
	end

	return math.max(0, math.floor(total + 0.5))
end

local function missingIslandXP(player, islandIndex)
	rememberEntryXP(player, islandIndex)
	local perIsland = entryXP[player]
	local baseline = perIsland and perIsland[islandIndex]
		or math.max(0, math.floor(tonumber(player:GetAttribute("PlayerTotalXP")) or 0))
	local current = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("PlayerTotalXP")) or 0)
	)
	local earned = math.max(0, current - baseline)
	local expected = expectedIslandXP(player, islandIndex)
	return math.max(0, expected - earned), expected, earned
end

local function seenClearLongEnough(player, islandIndex)
	local perIsland = clearSeenAt[player]
	if not perIsland then
		perIsland = {}
		clearSeenAt[player] = perIsland
	end
	if not perIsland[islandIndex] then
		perIsland[islandIndex] = now()
		return false
	end
	local grace = islandIndex == 1
		and INITIAL_SHARED_CLEAR_GRACE_SECONDS
		or SHARED_CLEAR_GRACE_SECONDS
	return now() - perIsland[islandIndex] >= grace
end

local function wasRecovered(player, islandIndex)
	return recovered[player] and recovered[player][islandIndex] == true
end

local function markRecovered(player, islandIndex)
	recovered[player] = recovered[player] or {}
	recovered[player][islandIndex] = true
end

local function applyProgressAttributes(player, progress)
	local highest = math.max(
		0,
		math.floor(tonumber(progress.HighestCompletedGlobalIslandIndex) or 0)
	)
	local resume = cleanIndex(progress.ResumeGlobalIslandIndex) or 1
	player:SetAttribute("SavedHighestCompletedIslandIndex", highest)
	player:SetAttribute("SavedResumeIslandIndex", resume)
	player:SetAttribute(
		"SavedResumeCycleIndex",
		IslandProgressionConfig.GetCycleIndex(resume)
	)
	player:SetAttribute("IslandProgressPersistenceReady", true)
end

local function grantMissingXP(player, islandIndex, reason)
	local missing, expected, earned = missingIslandXP(player, islandIndex)
	local granted = missing <= 0
	if missing > 0 then
		local ok, result = pcall(PlayerLevelService.AwardXP, player, missing, reason)
		granted = ok and result == true
		if not granted then
			player:SetAttribute("ProgressionUnblockLastError", tostring(result))
		end
	end
	player:SetAttribute("ProgressionUnblockCatchupXP", missing)
	player:SetAttribute("ProgressionUnblockExpectedIslandXP", expected)
	player:SetAttribute("ProgressionUnblockEarnedSinceEntryXP", earned)
	player:SetAttribute("ProgressionUnblockCatchupXPGranted", granted)
	return granted, missing
end

local function recoverSharedClear(player, islandIndex)
	if not playerNeedsIsland(player, islandIndex)
		or wasRecovered(player, islandIndex)
		or not seenClearLongEnough(player, islandIndex)
		or math.max(0, tonumber(player:GetAttribute("PendingXPCollectibles")) or 0) > 0
	then
		return false
	end

	if islandIndex == 1 then
		local granted, missing = grantMissingXP(
			player,
			1,
			"ProgressionRecovery:InitialSharedClear"
		)
		if not granted then
			return false
		end
		markRecovered(player, 1)
		initialSharedClearRecoveryCount += 1
		player:SetAttribute("ProgressionUnblockRecovered", true)
		player:SetAttribute("ProgressionUnblockLastReason", "InitialSharedIslandAlreadyCleared")
		player:SetAttribute("ProgressionUnblockLastIsland", 1)
		player:SetAttribute("ProgressionUnblockLastAt", now())
		player:SetAttribute("ProgressionUnblockInitialMissingXP", missing)
		workspace:SetAttribute(
			"DungeonProgressionInitialSharedClearRecoveryCount",
			initialSharedClearRecoveryCount
		)
		task.spawn(PlayerDataService.Save, player, false)
		return true
	end

	-- Reward recovery precedes checkpoint recovery. If persistence retries, the
	-- next pass sees no missing XP and cannot duplicate the reward.
	local granted = grantMissingXP(
		player,
		islandIndex,
		"ProgressionRecovery:SharedClearedIsland"
	)
	if not granted then
		return false
	end

	local nextIndex = math.min(routeCap(), islandIndex + 1)
	local ok, success, progress = pcall(
		PlayerDataService.SetIslandProgress,
		player,
		islandIndex,
		nextIndex
	)
	if not ok or success ~= true or type(progress) ~= "table" then
		player:SetAttribute("ProgressionUnblockLastError", tostring(progress or success))
		return false
	end

	markRecovered(player, islandIndex)
	applyProgressAttributes(player, progress)
	player:SetAttribute("LastPersonalIslandCompleted", islandIndex)
	player:SetAttribute("LastPersonalIslandCompletedAt", now())
	player:SetAttribute("LastPersonalIslandCompletionPolicy", "SharedClearRecovery")
	player:SetAttribute("ProgressionUnblockRecovered", true)
	player:SetAttribute("ProgressionUnblockLastReason", "SharedIslandAlreadyCleared")
	player:SetAttribute("ProgressionUnblockLastIsland", islandIndex)
	player:SetAttribute("ProgressionUnblockLastAt", now())

	sharedClearRecoveryCount += 1
	workspace:SetAttribute(
		"DungeonProgressionSharedClearRecoveryCount",
		sharedClearRecoveryCount
	)
	workspace:SetAttribute("DungeonProgressionLastRecoveredIsland", islandIndex)
	workspace:SetAttribute("DungeonProgressionLastRecoveredAt", now())
	task.spawn(PlayerDataService.Save, player, false)
	return true
end

local function emergencyFolder()
	local folder = workspace:FindFirstChild("DungeonEmergencyProgressionTargets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DungeonEmergencyProgressionTargets"
		folder.Parent = workspace
	end
	return folder
end

local function emergencySurface(snapshot)
	local floor = snapshot and snapshot.Floor
	if floor and floor:IsA("BasePart") and floor.Parent then
		return floor.Position + Vector3.new(0, floor.Size.Y * 0.5 + 2.2, 0)
	end
	local island = snapshot and snapshot.IslandModel
	if island and island:IsA("Model") and island.Parent then
		local cf, size = island:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y * 0.5 + 2.2, 0)
	end
	local node = snapshot and snapshot.Node
	if node and node:IsA("Model") and node.Parent then
		local cf, size = node:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y * 0.5 + 2.2, 0)
	end
	return nil
end

local function createEmergencyTarget(islandIndex, snapshot, announcedTargetCount)
	local existing = emergencyTargetByIndex[islandIndex]
	if existing and existing.Parent then
		local humanoid = existing:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return false, "AlreadyExists"
		end
	end

	local surface = emergencySurface(snapshot)
	if not surface then
		return false, "NoSafeSurface"
	end

	-- Only invent a quota when encounter planning failed before announcing one.
	if announcedTargetCount <= 0 then
		local configured, configError = IslandCombatService.SetTargetCount(islandIndex, 1)
		if configured ~= true then
			return false, tostring(configError or "TargetCountRejected")
		end
	end

	local model = Instance.new("Model")
	model.Name = "EmergencyProgressionSlime"
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("EmergencyProgressionTarget", true)
	model:SetAttribute("IslandCombatManaged", true)
	model:SetAttribute("GlobalIslandIndex", islandIndex)
	model:SetAttribute("MonsterId", "EmergencyProgressionSlime")
	model:SetAttribute("SlimeVariant", "Green")
	model:SetAttribute("DisplayName", "Slime")
	model:SetAttribute("Peaceful", false)
	model:SetAttribute("CanDamagePlayers", false)
	model:SetAttribute("NoKnockback", true)
	model:SetAttribute("CanBeKnockedBack", false)
	model:SetAttribute("CanBeStunned", false)
	model:SetAttribute("XPRewardClaimed", false)
	model:SetAttribute("ProgressionRecoverySpawnedAt", now())
	model:SetAttribute("ProgressionRecoveryOriginalTargetCount", announcedTargetCount)

	local mobLevel = math.max(1, IslandProgressionConfig.GetLevelInCycle(islandIndex))
	local cycleIndex = math.max(1, IslandProgressionConfig.GetCycleIndex(islandIndex))
	local riskLevel = math.max(1, IslandProgressionConfig.GetIslandLevel(islandIndex))
	local cycleXP = IslandProgressionConfig.GetXPRewardMultiplier(cycleIndex)
	model:SetAttribute("MobLevel", mobLevel)
	model:SetAttribute("MobLevelInCycle", mobLevel)
	model:SetAttribute("CycleIndex", cycleIndex)
	model:SetAttribute("IslandLevel", riskLevel)
	model:SetAttribute("RecommendedLevel", riskLevel)
	model:SetAttribute("XPReward", MobXPConfig.GetMobXPReward("Green", mobLevel, cycleXP))
	model:SetAttribute("XPRewardMultiplier", cycleXP)
	model:SetAttribute("XPRewardVersion", MobXPConfig.Version)
	model:SetAttribute("XPRewardPolicy", MobXPConfig.AwardPolicy)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(3.2, 2.7, 3.2)
	root.Material = Enum.Material.SmoothPlastic
	root.Color = Color3.fromRGB(82, 205, 92)
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = true
	root.CanQuery = true
	root.CFrame = CFrame.new(surface)
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 35
	humanoid.Health = 35
	humanoid.DisplayName = "Slime"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.NameDisplayDistance = 18
	humanoid.HealthDisplayDistance = 18
	humanoid.Parent = model

	model.PrimaryPart = root
	model:SetAttribute("HomePosition", surface)
	model:SetAttribute("SpawnSurfacePosition", surface)
	-- Outside the island on purpose: the finite hard-cap only rejects managed
	-- descendants of the island, while IslandCombatService owns the forced index.
	model.Parent = emergencyFolder()

	CollectionService:AddTag(model, "CombatTarget")
	local registered, registerError = IslandCombatService.RegisterSpawn(model, islandIndex)
	if registered ~= true then
		CollectionService:RemoveTag(model, "CombatTarget")
		model:Destroy()
		return false, tostring(registerError or "RegisterSpawnRejected")
	end

	emergencyTargetByIndex[islandIndex] = model
	emergencySpawnCount += 1
	workspace:SetAttribute("DungeonProgressionEmergencyMobCount", emergencySpawnCount)
	workspace:SetAttribute("DungeonProgressionLastEmergencyMobIsland", islandIndex)
	workspace:SetAttribute("DungeonProgressionLastEmergencyMobAt", now())

	humanoid.Died:Connect(function()
		if emergencyTargetByIndex[islandIndex] == model then
			emergencyTargetByIndex[islandIndex] = nil
		end
		stalledSince[islandIndex] = now() - STALL_GRACE_SECONDS
		Debris:AddItem(model, 1.5)
	end)
	model.Destroying:Connect(function()
		if emergencyTargetByIndex[islandIndex] == model then
			emergencyTargetByIndex[islandIndex] = nil
		end
	end)
	Debris:AddItem(model, EMERGENCY_TARGET_LIFETIME_SECONDS)
	return true
end

local function anyPlayerNeedsIsland(islandIndex)
	for _, player in ipairs(Players:GetPlayers()) do
		if playerNeedsIsland(player, islandIndex) then
			return true
		end
	end
	return false
end

local function noteBlocked(index, reason)
	if stalledSince[index] ~= nil then
		return
	end
	stalledSince[index] = now()
	blockedNoMobsCount += 1
	workspace:SetAttribute("DungeonProgressionBlockedNoMobsCount", blockedNoMobsCount)
	workspace:SetAttribute("DungeonProgressionBlockedNoMobsIsland", index)
	workspace:SetAttribute("DungeonProgressionBlockedNoMobsReason", reason)
	workspace:SetAttribute("DungeonProgressionBlockedNoMobsAt", now())
end

local function inspectPlayer(player)
	if player.Parent ~= Players
		or player:GetAttribute("IslandProgressPersistenceReady") ~= true
		or workspace:GetAttribute("DungeonStandaloneWorldReady") ~= true
	then
		return
	end

	local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if not index then
		return
	end
	rememberEntryXP(player, index)

	local snapshot = IslandCombatService.GetIslandSnapshot(index)
	if type(snapshot) ~= "table" then
		return
	end

	if snapshot.Cleared == true or snapshot.State == "Cleared" then
		recoverSharedClear(player, index)
		stalledSince[index] = nil
		return
	end

	if not playerNeedsIsland(player, index) then
		stalledSince[index] = nil
		return
	end

	local targetCount = math.max(0, math.floor(tonumber(snapshot.MobTargetCount) or 0))
	local defeatedCount = math.max(0, math.floor(tonumber(snapshot.MobDefeatedCount) or 0))
	local aliveCount = math.max(0, math.floor(tonumber(snapshot.MobAliveCount) or 0))
	local blockedReason

	if snapshot.State == "Active" and aliveCount <= 0 then
		if targetCount <= 0 then
			blockedReason = "ZeroTarget"
		elseif defeatedCount < targetCount then
			blockedReason = "QuotaIncompleteNoMobs"
		end
	end

	if not blockedReason then
		stalledSince[index] = nil
		return
	end

	noteBlocked(index, blockedReason)
	if now() - stalledSince[index] < STALL_GRACE_SECONDS then
		return
	end

	local spawned, spawnError = createEmergencyTarget(index, snapshot, targetCount)
	if spawned then
		stalledSince[index] = nil
		player:SetAttribute("ProgressionUnblockLastReason", "EmergencyMobSpawned:" .. blockedReason)
		player:SetAttribute("ProgressionUnblockLastIsland", index)
		player:SetAttribute("ProgressionUnblockLastAt", now())
		if blockedReason == "QuotaIncompleteNoMobs" then
			stalledQuotaRecoveryCount += 1
			workspace:SetAttribute(
				"DungeonProgressionStalledQuotaRecoveryCount",
				stalledQuotaRecoveryCount
			)
		end
	elseif spawnError ~= "AlreadyExists" then
		player:SetAttribute("ProgressionUnblockLastError", tostring(spawnError))
	end
end

workspace:SetAttribute("DungeonProgressionUnblockGuardVersion", VERSION)
workspace:SetAttribute(
	"DungeonProgressionUnblockPolicy",
	"MissingXPSharedClear_ZeroTarget_StalledQuotaRecovery"
)
workspace:SetAttribute("DungeonProgressionSharedClearRecoveryCount", 0)
workspace:SetAttribute("DungeonProgressionInitialSharedClearRecoveryCount", 0)
workspace:SetAttribute("DungeonProgressionEmergencyMobCount", 0)
workspace:SetAttribute("DungeonProgressionBlockedNoMobsCount", 0)
workspace:SetAttribute("DungeonProgressionStalledQuotaRecoveryCount", 0)

while true do
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, errorMessage = pcall(inspectPlayer, player)
		if not ok then
			player:SetAttribute("ProgressionUnblockLastError", tostring(errorMessage))
			workspace:SetAttribute("DungeonProgressionUnblockLastError", tostring(errorMessage))
		end
	end
	for islandIndex in pairs(stalledSince) do
		if not anyPlayerNeedsIsland(islandIndex) then
			stalledSince[islandIndex] = nil
		end
	end
	task.wait(CHECK_SECONDS)
end