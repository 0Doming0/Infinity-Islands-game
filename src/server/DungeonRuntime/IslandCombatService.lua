--[[
	Infinity Islands - Task 04
	IslandCombatService V1 + Task05 managed-target integration

	Authoritative arena state machine:

		Dormant -> Ready -> Active -> Cleared

	Responsibilities in this task:
	- register materialized Combat Islands;
	- detect accepted player entry through CurrentGlobalIslandIndex;
	- activate an island once a player is actually on it;
	- track CombatTarget mobs by GlobalIslandIndex;
	- track MobTargetCount / MobSpawnedCount / MobAliveCount;
	- mark Cleared ONLY when:
		* state is Active;
		* MobTargetCount > 0;
		* MobSpawnedCount >= MobTargetCount;
		* MobAliveCount == 0.
	- publish server-authoritative Attributes.

	This task intentionally DOES NOT:
	- spawn mobs;
	- scale HP/damage;
	- award XP;
	- unlock gates;
	- replace old Objective services yet.

	Task 05 will make MonsterSpawner consume this contract.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandCombatConfig = require(
	ReplicatedStorage.Shared.Configs.IslandCombatConfig
)

local IslandCombatService = {}

local ISLAND_TAG = "SkyDungeonIslandNode"
local TARGET_TAG = "CombatTarget"

local States = IslandCombatConfig.States

local started = false
local generation = 0
local options = {}

local islandsByIndex = {}
local recordsByIndex = {}
local countedTargets = setmetatable({}, { __mode = "k" })
local targetDeathConnections = setmetatable({}, { __mode = "k" })
local playerConnections = setmetatable({}, { __mode = "k" })

local islandAddedConnection
local islandRemovedConnection
local targetAddedConnection
local targetRemovedConnection
local playerAddedConnection
local playerRemovingConnection

local clearSerial = 0
local activationSerial = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return nil
	end

	number = math.floor(number)
	return number >= 1 and number or nil
end

local function isCombatIsland(node)
	return node
		and node:IsA("Model")
		and node:GetAttribute("IsMandatoryRoute") == true
		and node:GetAttribute("IsOptionalRoute") ~= true
		and node:GetAttribute("IsRewardIsland") ~= true
		and node:GetAttribute("IsBossSanctuary") ~= true
end

local function getIndexFromIsland(node)
	return cleanIndex(
		node
			and (
				node:GetAttribute("GlobalIslandIndex")
				or node:GetAttribute("ProgressionIslandIndex")
			)
	)
end

local function getIslandModel(node)
	if not node then
		return nil
	end

	local terrainAreas = node:FindFirstChild("TerrainAreas")
	if terrainAreas then
		for _, child in ipairs(terrainAreas:GetChildren()) do
			if child:IsA("Model")
				and child:GetAttribute("IsSkyIsland") == true
			then
				return child
			end
		end

		local fallback = terrainAreas:FindFirstChildWhichIsA("Model")
		if fallback then
			return fallback
		end
	end

	return nil
end

local function setOnIslandHierarchy(record, name, value)
	if not record then
		return
	end

	for _, instance in ipairs({
		record.Node,
		record.IslandModel,
		record.Floor,
	}) do
		if instance and instance.Parent then
			instance:SetAttribute(name, value)
		end
	end
end

local function publishRecord(record)
	if not record then
		return
	end

	setOnIslandHierarchy(record, "CombatState", record.State)
	setOnIslandHierarchy(record, "Cleared", record.ProgressionCleared == true)
	setOnIslandHierarchy(record, "MobTargetCount", record.TargetCount)
	setOnIslandHierarchy(record, "MobKillQuota", record.TargetCount)
	setOnIslandHierarchy(record, "MobDefeatedCount", record.DefeatedCount)
	setOnIslandHierarchy(
		record,
		"MobRemainingForUnlock",
		math.max(0, record.TargetCount - record.DefeatedCount)
	)
	setOnIslandHierarchy(record, "MobSpawnedCount", record.SpawnedCount)
	setOnIslandHierarchy(record, "MobAliveCount", record.AliveCount)
	setOnIslandHierarchy(record, "InfiniteMobRespawnEnabled", true)
	setOnIslandHierarchy(record, "CombatActivationSerial", record.ActivationSerial)
	setOnIslandHierarchy(record, "CombatActivatedAt", record.ActivatedAt)
	setOnIslandHierarchy(record, "CombatClearedAt", record.ClearedAt)
	setOnIslandHierarchy(record, "IslandCombatVersion", IslandCombatConfig.Version)
end

local function newRecord(index, node)
	local islandModel = getIslandModel(node)

	return {
		Index = index,
		Node = node,
		IslandModel = islandModel,
		Floor = islandModel and (
			islandModel.PrimaryPart
				or islandModel:FindFirstChild("IslandFloor")
		) or nil,

		State = States.Dormant,

		TargetCount = math.max(
			0,
			math.floor(
				tonumber(node:GetAttribute("MobTargetCount")) or 0
			)
		),

		SpawnedCount = math.max(
			0,
			math.floor(
				tonumber(node:GetAttribute("MobSpawnedCount")) or 0
			)
		),

		AliveCount = 0,
		DefeatedCount = math.max(
			0,
			math.floor(
				tonumber(node:GetAttribute("MobDefeatedCount")) or 0
			)
		),
		ProgressionCleared = node:GetAttribute("Cleared") == true,

		ActivationSerial = 0,
		ActivatedAt = nil,
		ClearedAt = nil,

		LastReason = "Registered",
	}
end

local function registerIsland(node)
	if not isCombatIsland(node) then
		return nil
	end

	local index = getIndexFromIsland(node)
	if not index then
		return nil
	end

	local existing = recordsByIndex[index]
	if existing and existing.Node == node then
		return existing
	end

	if existing
		and existing.Node
		and existing.Node.Parent
	then
		-- Linear route must not have two live mandatory islands with one index.
		workspace:SetAttribute(
			"DungeonIslandCombatDuplicateIndex",
			index
		)
		return existing
	end

	local record = newRecord(index, node)

	recordsByIndex[index] = record
	islandsByIndex[index] = node

	node:SetAttribute("CombatState", States.Dormant)
	node:SetAttribute("Cleared", record.ProgressionCleared == true)

	publishRecord(record)

	return record
end

local function unregisterIsland(node)
	local index = getIndexFromIsland(node)
	if not index then
		return
	end

	local record = recordsByIndex[index]
	if record and record.Node == node then
		-- Keep the record if the Task 03 soft-unload merely moved the model to
		-- ServerStorage. CollectionService does not remove the tag in that case.
		if node.Parent then
			return
		end

		recordsByIndex[index] = nil
		islandsByIndex[index] = nil
	end
end

local function targetIslandIndex(target)
	if not target then
		return nil
	end

	local direct = cleanIndex(
		target:GetAttribute("GlobalIslandIndex")
			or target:GetAttribute("ProgressionIslandIndex")
	)

	if direct then
		return direct
	end

	local cursor = target.Parent

	while cursor do
		if CollectionService:HasTag(cursor, ISLAND_TAG) then
			return getIndexFromIsland(cursor)
		end

		cursor = cursor.Parent
	end

	return nil
end

local function targetAlive(target)
	if not target
		or not target.Parent
		or target:GetAttribute("Peaceful") == true
		or target:GetAttribute("IslandCombatManaged") ~= true
	then
		return false
	end

	local humanoid = target:FindFirstChildWhichIsA("Humanoid", true)

	return humanoid ~= nil
		and humanoid.Health > 0
end

local function recomputeAlive(index)
	local record = recordsByIndex[index]
	if not record then
		return 0
	end

	local alive = 0

	for _, target in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if target:IsA("Model")
			and targetAlive(target)
			and targetIslandIndex(target) == index
		then
			alive += 1
		end
	end

	record.AliveCount = alive
	publishRecord(record)

	return alive
end

local function safeCallback(name, ...)
	local callback = options[name]
	if type(callback) ~= "function" then
		return true
	end

	local ok, result = pcall(callback, ...)

	if not ok then
		workspace:SetAttribute(
			"DungeonIslandCombatCallbackError",
			name .. ": " .. tostring(result)
		)
		warn(
			"[IslandCombatService] callback "
				.. name
				.. " falhou: "
				.. tostring(result)
		)
		return false
	end

	return result ~= false
end

local function tryClear(index, reason)
	local record = recordsByIndex[index]

	if not record
		or record.State ~= States.Active
	then
		return false, "IslandNotActive"
	end

	if record.ProgressionCleared == true then
		return false, "AlreadyCompleted"
	end

	if IslandCombatConfig.RequireTargetCountBeforeClear
		and record.TargetCount <= 0
	then
		return false, "TargetCountNotAnnounced"
	end

	if record.DefeatedCount < record.TargetCount then
		return false, "KillQuotaPending"
	end

	record.ProgressionCleared = true
	record.ClearedAt = now()
	record.LastReason = reason or "KillQuotaReached"

	clearSerial += 1

	-- Do not set CombatState to Cleared.
	-- Active combat must continue after progression completion.
	publishRecord(record)

	workspace:SetAttribute("DungeonLastClearedIslandIndex", index)
	workspace:SetAttribute("DungeonLastClearedIslandAt", record.ClearedAt)
	workspace:SetAttribute("DungeonIslandCombatClearSerial", clearSerial)
	workspace:SetAttribute(
		"DungeonIslandCombatCompletionPolicy",
		"KillQuotaDoesNotStopCombat"
	)

	safeCallback(
		"OnIslandCleared",
		IslandCombatService.GetIslandSnapshot(index)
	)

	return true
end

local function onTargetDied(target, index)
	local record = recordsByIndex[index]
	if not record then
		return
	end

	record.DefeatedCount += 1

	recomputeAlive(index)

	workspace:SetAttribute("DungeonIslandCombatLastDeathIsland", index)
	workspace:SetAttribute("DungeonIslandCombatLastDeathAt", now())
	workspace:SetAttribute(
		"DungeonIslandCombatLastDefeatedCount",
		record.DefeatedCount
	)

	publishRecord(record)
	tryClear(index, "KillQuotaReached")
end

local function registerTarget(target, forcedIndex)
	if not target
		or not target:IsA("Model")
		or target:GetAttribute("Peaceful") == true
		or target:GetAttribute("IslandCombatManaged") ~= true
	then
		return false
	end

	local index = cleanIndex(forcedIndex)
		or targetIslandIndex(target)

	if not index then
		return false
	end

	local record = recordsByIndex[index]
	if not record then
		return false
	end

	if target:GetAttribute("GlobalIslandIndex") == nil then
		target:SetAttribute("GlobalIslandIndex", index)
	end

	if not countedTargets[target] then
		countedTargets[target] = true

		record.SpawnedCount += 1

		target:SetAttribute("IslandCombatSpawnCounted", true)
		target:SetAttribute("IslandCombatIslandIndex", index)
		target:SetAttribute("IslandCombatVersion", IslandCombatConfig.Version)
	end

	local humanoid = target:FindFirstChildWhichIsA("Humanoid", true)

	if humanoid
		and not targetDeathConnections[target]
	then
		targetDeathConnections[target] =
			humanoid.Died:Connect(function()
				onTargetDied(target, index)
			end)
	end

	recomputeAlive(index)

	return true
end

local function unregisterTarget(target)
	local index = targetIslandIndex(target)

	local connection = targetDeathConnections[target]
	if connection then
		connection:Disconnect()
		targetDeathConnections[target] = nil
	end

	if index and recordsByIndex[index] then
		task.defer(function()
			if started then
				recomputeAlive(index)
			end
		end)
	end
end

local function setState(record, state, reason)
	if not record then
		return false
	end

	if record.State == States.Cleared
		and state ~= States.Cleared
	then
		return false
	end

	if record.State == state then
		return true
	end

	record.State = state
	record.LastReason = reason or state

	if state == States.Active then
		activationSerial += 1
		record.ActivationSerial = activationSerial
		record.ActivatedAt = now()

		workspace:SetAttribute(
			"DungeonLastActivatedCombatIsland",
			record.Index
		)
		workspace:SetAttribute(
			"DungeonLastActivatedCombatIslandAt",
			record.ActivatedAt
		)
	elseif state == States.Cleared then
		record.ClearedAt = record.ClearedAt or now()
	end

	publishRecord(record)

	return true
end

local function currentIndexes()
	local result = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local index = cleanIndex(
			player:GetAttribute("CurrentGlobalIslandIndex")
		)

		if index then
			result[index] = (result[index] or 0) + 1
		end
	end

	return result
end

local function reconcileIslandStates()
	local occupied = currentIndexes()
	local highestCurrent = 0

	for index in pairs(occupied) do
		highestCurrent = math.max(highestCurrent, index)
	end

	for index, record in pairs(recordsByIndex) do
		if record.State == States.Cleared then
			publishRecord(record)
			continue
		end

		if occupied[index] then
			setState(
				record,
				States.Active,
				"PlayerEnteredCombatIsland"
			)

			recomputeAlive(index)
			tryClear(index, "ReconcileClear")
		else
			if highestCurrent > 0
				and index > highestCurrent
				and index <= highestCurrent
					+ IslandCombatConfig.ReadyLookahead
			then
				setState(
					record,
					States.Ready,
					"NextCombatIsland"
				)
			else
				setState(
					record,
					States.Dormant,
					"OutsideCombatFocus"
				)
			end
		end
	end

	workspace:SetAttribute(
		"DungeonCombatCurrentIsland",
		highestCurrent > 0 and highestCurrent or nil
	)
end

local function bindPlayer(player)
	if playerConnections[player] then
		return
	end

	playerConnections[player] =
		player:GetAttributeChangedSignal(
			"CurrentGlobalIslandIndex"
		):Connect(function()
			task.defer(reconcileIslandStates)
		end)

	task.defer(reconcileIslandStates)
end

local function unbindPlayer(player)
	local connection = playerConnections[player]
	if connection then
		connection:Disconnect()
		playerConnections[player] = nil
	end

	task.defer(reconcileIslandStates)
end

local function publishService()
	workspace:SetAttribute("DungeonIslandCombatReady", started)
	workspace:SetAttribute(
		"DungeonIslandCombatVersion",
		IslandCombatConfig.Version
	)
	workspace:SetAttribute(
		"DungeonIslandCombatStateMachine",
		"Dormant>Ready>Active"
	)
	workspace:SetAttribute(
		"DungeonIslandCombatTargetPolicy",
		"IslandCombatManagedOnly"
	)
	workspace:SetAttribute(
		"DungeonIslandCombatProgressionPolicy",
		"KillQuotaDoesNotStopCombat"
	)
	workspace:SetAttribute("DungeonInfiniteIslandMobs", true)

	local registered = 0
	local active = 0
	local cleared = 0

	for _, record in pairs(recordsByIndex) do
		registered += 1

		if record.State == States.Active then
			active += 1
		end

		if record.ProgressionCleared == true then
			cleared += 1
		end
	end

	workspace:SetAttribute(
		"DungeonIslandCombatRegisteredCount",
		registered
	)
	workspace:SetAttribute(
		"DungeonIslandCombatActiveCount",
		active
	)
	workspace:SetAttribute(
		"DungeonIslandCombatClearedCount",
		cleared
	)
end

local function initialScan()
	for _, node in ipairs(CollectionService:GetTagged(ISLAND_TAG)) do
		registerIsland(node)
	end

	for _, target in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		registerTarget(target)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	reconcileIslandStates()
	publishService()
end

function IslandCombatService.Start(startOptions)
	if started then
		return false, "AlreadyStarted"
	end

	started = true
	generation += 1
	options = type(startOptions) == "table"
		and startOptions
		or {}

	local token = generation

	islandAddedConnection =
		CollectionService
			:GetInstanceAddedSignal(ISLAND_TAG)
			:Connect(function(node)
				task.defer(function()
					registerIsland(node)
					reconcileIslandStates()
					publishService()
				end)
			end)

	islandRemovedConnection =
		CollectionService
			:GetInstanceRemovedSignal(ISLAND_TAG)
			:Connect(unregisterIsland)

	targetAddedConnection =
		CollectionService
			:GetInstanceAddedSignal(TARGET_TAG)
			:Connect(function(target)
				task.defer(function()
					registerTarget(target)
					publishService()
				end)
			end)

	targetRemovedConnection =
		CollectionService
			:GetInstanceRemovedSignal(TARGET_TAG)
			:Connect(unregisterTarget)

	playerAddedConnection =
		Players.PlayerAdded:Connect(bindPlayer)

	playerRemovingConnection =
		Players.PlayerRemoving:Connect(unbindPlayer)

	initialScan()

	task.spawn(function()
		while started and generation == token do
			reconcileIslandStates()
			publishService()

			task.wait(
				IslandCombatConfig.ReconcileSeconds
			)
		end
	end)

	return true
end

function IslandCombatService.Stop()
	if not started then
		return false
	end

	started = false
	generation += 1

	for _, connection in ipairs({
		islandAddedConnection,
		islandRemovedConnection,
		targetAddedConnection,
		targetRemovedConnection,
		playerAddedConnection,
		playerRemovingConnection,
	}) do
		if connection then
			connection:Disconnect()
		end
	end

	islandAddedConnection = nil
	islandRemovedConnection = nil
	targetAddedConnection = nil
	targetRemovedConnection = nil
	playerAddedConnection = nil
	playerRemovingConnection = nil

	for target, connection in pairs(targetDeathConnections) do
		connection:Disconnect()
		targetDeathConnections[target] = nil
	end

	for player, connection in pairs(playerConnections) do
		connection:Disconnect()
		playerConnections[player] = nil
	end

	options = {}

	publishService()

	return true
end

function IslandCombatService.SetTargetCount(
	islandOrIndex,
	targetCount
)
	local index

	if typeof(islandOrIndex) == "Instance" then
		index = getIndexFromIsland(islandOrIndex)
	else
		index = cleanIndex(islandOrIndex)
	end

	local record = index and recordsByIndex[index]
	if not record then
		return false, "IslandNotRegistered"
	end

	targetCount = math.max(
		0,
		math.floor(tonumber(targetCount) or 0)
	)

	record.TargetCount = targetCount
	record.LastReason = "TargetCountConfigured"

	publishRecord(record)

	tryClear(index, "TargetCountSatisfied")

	return true, targetCount
end

function IslandCombatService.RegisterSpawn(
	target,
	islandOrIndex
)
	local index

	if typeof(islandOrIndex) == "Instance" then
		index = getIndexFromIsland(islandOrIndex)
	else
		index = cleanIndex(islandOrIndex)
	end

	return registerTarget(target, index)
end

function IslandCombatService.ActivateIsland(
	islandOrIndex,
	reason
)
	local index

	if typeof(islandOrIndex) == "Instance" then
		index = getIndexFromIsland(islandOrIndex)
	else
		index = cleanIndex(islandOrIndex)
	end

	local record = index and recordsByIndex[index]
	if not record then
		return false, "IslandNotRegistered"
	end

	setState(
		record,
		States.Active,
		reason or "ExplicitActivation"
	)

	recomputeAlive(index)

	return true, IslandCombatService.GetIslandSnapshot(index)
end

function IslandCombatService.GetIslandSnapshot(
	islandOrIndex
)
	local index

	if typeof(islandOrIndex) == "Instance" then
		index = getIndexFromIsland(islandOrIndex)
	else
		index = cleanIndex(islandOrIndex)
	end

	local record = index and recordsByIndex[index]
	if not record then
		return nil
	end

	return {
		Version = IslandCombatConfig.Version,
		GlobalIslandIndex = index,
		State = record.State,
		Cleared = record.ProgressionCleared == true,
		MobTargetCount = record.TargetCount,
		MobKillQuota = record.TargetCount,
		MobDefeatedCount = record.DefeatedCount,
		MobRemainingForUnlock = math.max(
			0,
			record.TargetCount - record.DefeatedCount
		),
		MobSpawnedCount = record.SpawnedCount,
		MobAliveCount = record.AliveCount,
		InfiniteMobRespawnEnabled = true,
		ActivationSerial = record.ActivationSerial,
		ActivatedAt = record.ActivatedAt,
		ClearedAt = record.ClearedAt,
		LastReason = record.LastReason,
		Node = record.Node,
		IslandModel = record.IslandModel,
		Floor = record.Floor,
	}
end

function IslandCombatService.GetSnapshot()
	local islands = {}

	for index in pairs(recordsByIndex) do
		islands[index] =
			IslandCombatService.GetIslandSnapshot(index)
	end

	return {
		Ready = started,
		Version = IslandCombatConfig.Version,
		ClearSerial = clearSerial,
		ActivationSerial = activationSerial,
		Islands = islands,
	}
end

return IslandCombatService
