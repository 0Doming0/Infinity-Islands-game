--[[
	Infinity Islands - ProgressionUnblockGuard V1

	Conservative live-MVP recovery for two progression deadlocks:
	1. A player still personally needs an island that another player already
	   cleared in the shared server. The shared world stays cleared, but the
	   player's personal checkpoint is caught up so AVANCAR remains persistent.
	2. An active island has no announced mob target because normal encounter
	   planning failed. After a short grace period, create one stationary,
	   server-authoritative emergency CombatTarget so the normal kill/clear/XP
	   pipeline can finish the island instead of leaving the player stuck.

	This script never resets a cleared shared arena and never replaces normal
	MonsterSpawner behavior. It only acts on impossible/stalled states.
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

local VERSION = "ProgressionUnblockGuardV1"
local CHECK_SECONDS = 0.75
local ZERO_TARGET_GRACE_SECONDS = 5
local EMERGENCY_TARGET_LIFETIME_SECONDS = 120

local emergencyTargetByIndex = {}
local zeroTargetSince = {}
local sharedClearRecovered = setmetatable({}, { __mode = "k" })

local sharedClearRecoveryCount = 0
local emergencySpawnCount = 0
local blockedNoMobsCount = 0

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
	if not ok then
		return 2
	end
	return math.max(
		2,
		math.floor(tonumber(plan and plan.TotalIslandCount) or 2)
	)
end

local function applyProgressAttributes(player, progress)
	if not player or player.Parent ~= Players or type(progress) ~= "table" then
		return
	end

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

local function playerNeedsCurrentIsland(player, islandIndex)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute("IslandProgressPersistenceReady") ~= true
	then
		return false
	end

	local current = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	local resume = cleanIndex(player:GetAttribute("SavedResumeIslandIndex"))

	return current == islandIndex
		and resume == islandIndex
		and player:GetAttribute("LastPersonalIslandCompleted") ~= islandIndex
end

local function catchupXPForSharedClear(player, islandIndex)
	local plan = MonsterSpawner.GetIslandPlan(islandIndex)
	if type(plan) ~= "table" then
		return 0
	end

	local roster = plan.Roster
	if type(roster) ~= "table" or #roster <= 0 then
		return 0
	end

	local mobLevel = math.max(
		1,
		math.floor(
			tonumber(plan.MobLevel)
				or IslandProgressionConfig.GetLevelInCycle(islandIndex)
		)
	)
	local cycleIndex = math.max(
		1,
		math.floor(
			tonumber(plan.CycleIndex)
				or IslandProgressionConfig.GetCycleIndex(islandIndex)
		)
	)
	local recommendedLevel = math.max(
		1,
		math.floor(IslandProgressionConfig.GetIslandLevel(islandIndex))
	)
	local playerLevel = math.max(
		1,
		math.floor(tonumber(player:GetAttribute("PlayerLevel")) or 1)
	)
	local cycleXP = IslandProgressionConfig.GetXPRewardMultiplier(cycleIndex)

	local total = 0
	for _, variant in ipairs(roster) do
		local reward = MobXPConfig.GetMobXPReward(
			tostring(variant or "Green"),
			mobLevel,
			cycleXP
		)
		local amount = MobXPConfig.GetAwardForPlayer(
			reward,
			recommendedLevel,
			playerLevel
		)
		total += math.max(0, tonumber(amount) or 0)
	end

	return math.max(0, math.floor(total + 0.5))
end

local function recoverSharedClearedIsland(player, islandIndex)
	-- Global index 1 is the unnumbered initial island. Existing persistence
	-- intentionally commits 1 -> 2 only after the player physically enters 2.
	if islandIndex < 2 then
		return false
	end

	if not playerNeedsCurrentIsland(player, islandIndex) then
		return false
	end

	sharedClearRecovered[player] = sharedClearRecovered[player] or {}
	if sharedClearRecovered[player][islandIndex] then
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

	sharedClearRecovered[player][islandIndex] = true
	applyProgressAttributes(player, progress)

	player:SetAttribute("LastPersonalIslandCompleted", islandIndex)
	player:SetAttribute("LastPersonalIslandCompletedAt", now())
	player:SetAttribute(
		"LastPersonalIslandCompletionPolicy",
		"SharedClearRecovery"
	)

	local catchupXP = catchupXPForSharedClear(player, islandIndex)
	local xpGranted = false
	if catchupXP > 0 then
		local xpOk, xpResult = pcall(
			PlayerLevelService.AwardXP,
			player,
			catchupXP,
			"ProgressionRecovery:SharedClearedIsland"
		)
		xpGranted = xpOk and xpResult == true
	end

	player:SetAttribute("ProgressionUnblockRecovered", true)
	player:SetAttribute("ProgressionUnblockLastReason", "SharedIslandAlreadyCleared")
	player:SetAttribute("ProgressionUnblockLastIsland", islandIndex)
	player:SetAttribute("ProgressionUnblockLastAt", now())
	player:SetAttribute("ProgressionUnblockCatchupXP", catchupXP)
	player:SetAttribute("ProgressionUnblockCatchupXPGranted", xpGranted)
	player:SetAttribute(
		"ProgressionUnblockRecoverySerial",
		(tonumber(player:GetAttribute("ProgressionUnblockRecoverySerial")) or 0) + 1
	)

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

local function emergencySurface(snapshot)
	local floor = snapshot and snapshot.Floor
	if floor and floor:IsA("BasePart") and floor.Parent then
		return floor.Position + Vector3.new(0, floor.Size.Y * 0.5 + 2.2, 0)
	end

	local islandModel = snapshot and snapshot.IslandModel
	if islandModel and islandModel:IsA("Model") and islandModel.Parent then
		local boxCFrame, boxSize = islandModel:GetBoundingBox()
		return boxCFrame.Position + Vector3.new(0, boxSize.Y * 0.5 + 2.2, 0)
	end

	local node = snapshot and snapshot.Node
	if node and node:IsA("Model") and node.Parent then
		local boxCFrame, boxSize = node:GetBoundingBox()
		return boxCFrame.Position + Vector3.new(0, boxSize.Y * 0.5 + 2.2, 0)
	end

	return nil
end

local function emergencyParent(snapshot)
	local islandModel = snapshot and snapshot.IslandModel
	if islandModel and islandModel.Parent then
		local folder = islandModel:FindFirstChild("IslandCombatMonsters")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "IslandCombatMonsters"
			folder.Parent = islandModel
		end
		return folder
	end

	return snapshot and snapshot.Node or workspace
end

local function createEmergencyTarget(islandIndex, snapshot)
	local existing = emergencyTargetByIndex[islandIndex]
	if existing and existing.Parent then
		return false, "AlreadyExists"
	end

	local surface = emergencySurface(snapshot)
	if not surface then
		return false, "NoSafeSurface"
	end

	local configured, configError = IslandCombatService.SetTargetCount(islandIndex, 1)
	if configured ~= true then
		return false, tostring(configError or "TargetCountRejected")
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

	local mobLevel = IslandProgressionConfig.GetLevelInCycle(islandIndex)
	local cycleIndex = IslandProgressionConfig.GetCycleIndex(islandIndex)
	local recommendedLevel = IslandProgressionConfig.GetIslandLevel(islandIndex)
	local cycleXP = IslandProgressionConfig.GetXPRewardMultiplier(cycleIndex)
	local xpReward = MobXPConfig.GetMobXPReward("Green", mobLevel, cycleXP)

	model:SetAttribute("MobLevel", mobLevel)
	model:SetAttribute("MobLevelInCycle", mobLevel)
	model:SetAttribute("CycleIndex", cycleIndex)
	model:SetAttribute("IslandLevel", recommendedLevel)
	model:SetAttribute("RecommendedLevel", recommendedLevel)
	model:SetAttribute("XPReward", xpReward)
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
	root.CastShadow = true
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
	model.Parent = emergencyParent(snapshot)

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
		if playerNeedsCurrentIsland(player, islandIndex) then
			return true
		end
	end
	return false
end

local function inspectPlayer(player)
	if player.Parent ~= Players
		or player:GetAttribute("IslandProgressPersistenceReady") ~= true
		or workspace:GetAttribute("DungeonStandaloneWorldReady") ~= true
	then
		return
	end

	local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if not index or not playerNeedsCurrentIsland(player, index) then
		return
	end

	local snapshot = IslandCombatService.GetIslandSnapshot(index)
	if type(snapshot) ~= "table" then
		return
	end

	if snapshot.Cleared == true or snapshot.State == "Cleared" then
		recoverSharedClearedIsland(player, index)
		zeroTargetSince[index] = nil
		return
	end

	local targetCount = math.max(0, math.floor(tonumber(snapshot.MobTargetCount) or 0))
	local aliveCount = math.max(0, math.floor(tonumber(snapshot.MobAliveCount) or 0))

	if snapshot.State == "Active" and targetCount <= 0 and aliveCount <= 0 then
		if zeroTargetSince[index] == nil then
			zeroTargetSince[index] = now()
			blockedNoMobsCount += 1
			workspace:SetAttribute("DungeonProgressionBlockedNoMobsCount", blockedNoMobsCount)
			workspace:SetAttribute("DungeonProgressionBlockedNoMobsIsland", index)
			workspace:SetAttribute("DungeonProgressionBlockedNoMobsAt", now())
		end

		if now() - zeroTargetSince[index] >= ZERO_TARGET_GRACE_SECONDS then
			local spawned, spawnError = createEmergencyTarget(index, snapshot)
			if spawned then
				zeroTargetSince[index] = nil
				player:SetAttribute("ProgressionUnblockLastReason", "EmergencyMobSpawned")
				player:SetAttribute("ProgressionUnblockLastIsland", index)
				player:SetAttribute("ProgressionUnblockLastAt", now())
			else
				player:SetAttribute("ProgressionUnblockLastError", tostring(spawnError))
			end
		end
	else
		zeroTargetSince[index] = nil
	end
end

workspace:SetAttribute("DungeonProgressionUnblockGuardVersion", VERSION)
workspace:SetAttribute(
	"DungeonProgressionUnblockPolicy",
	"CatchUpSharedClear_RescueZeroTarget"
)
workspace:SetAttribute("DungeonProgressionSharedClearRecoveryCount", 0)
workspace:SetAttribute("DungeonProgressionEmergencyMobCount", 0)
workspace:SetAttribute("DungeonProgressionBlockedNoMobsCount", 0)

while true do
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, errorMessage = pcall(inspectPlayer, player)
		if not ok then
			player:SetAttribute("ProgressionUnblockLastError", tostring(errorMessage))
			workspace:SetAttribute("DungeonProgressionUnblockLastError", tostring(errorMessage))
		end
	end

	for islandIndex in pairs(zeroTargetSince) do
		if not anyPlayerNeedsIsland(islandIndex) then
			zeroTargetSince[islandIndex] = nil
		end
	end

	task.wait(CHECK_SECONDS)
end
