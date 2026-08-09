--[[
	Infin­ity Islands - Task 03
	ActiveWorldWindowService V1

	Goal:
	Keep only a small horizontal/vertical route window replicated in Workspace:

		[previous 1] [current] [future 1] [future 2] [future 3]

	This version is intentionally additive. It does NOT mutate the internal
	ChunkManager tables. Instead it soft-unloads old/far route geometry into
	ServerStorage and restores it when it becomes relevant again.

	Why:
	- preserves ChunkManager record references;
	- removes unloaded parts from Workspace physics/replication;
	- avoids a fragile large-file patch;
	- supports party members occupying different route indices;
	- protects the current spawn checkpoint;
	- future Task(s) can replace this with hard recycling after the new
	  progression core fully owns world lifecycle.

	Dungeon-only: src/server is mapped by dungeon.project.json, while Lobby
	does not import this bootstrap.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(
	script.Parent.Parent.BlockParkour.Config_SkyDungeon_V10
)

local ActiveWorldWindowService = {}

local ISLAND_TAG = "SkyDungeonIslandNode"
local CONNECTION_TAG = "SkyDungeonFrontierConnection"

local DEFAULT_PREVIOUS = 1
local DEFAULT_FUTURE = 3
local UPDATE_SECONDS = 0.25

local started = false
local generation = 0

local poolRoot
local islandPool
local connectionPool

local originalParents = setmetatable({}, { __mode = "k" })
local lastWindowMin = 1
local lastWindowMax = 1
local softUnloadedIslands = 0
local softUnloadedConnections = 0
local restoredIslands = 0
local restoredConnections = 0

local function ensurePool()
	if poolRoot and poolRoot.Parent then
		return
	end

	poolRoot = ServerStorage:FindFirstChild("SkyDungeonActiveWindowPool")
	if not poolRoot then
		poolRoot = Instance.new("Folder")
		poolRoot.Name = "SkyDungeonActiveWindowPool"
		poolRoot.Parent = ServerStorage
	end

	islandPool = poolRoot:FindFirstChild("Islands")
	if not islandPool then
		islandPool = Instance.new("Folder")
		islandPool.Name = "Islands"
		islandPool.Parent = poolRoot
	end

	connectionPool = poolRoot:FindFirstChild("Connections")
	if not connectionPool then
		connectionPool = Instance.new("Folder")
		connectionPool.Name = "Connections"
		connectionPool.Parent = poolRoot
	end
end

local function isInWorkspace(instance)
	return instance
		and instance.Parent
		and instance:IsDescendantOf(workspace)
end

local function routeIndex(instance)
	if not instance then
		return nil
	end

	local value = tonumber(
		instance:GetAttribute("GlobalIslandIndex")
			or instance:GetAttribute("ProtectionGlobalIslandIndex")
	)

	if not value then
		return nil
	end

	return math.max(1, math.floor(value))
end

local function currentPartyWindow()
	local minimumCurrent = math.huge
	local maximumCurrent = -math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local current = tonumber(
			player:GetAttribute("CurrentGlobalIslandIndex")
		)

		if current then
			current = math.max(1, math.floor(current))
			minimumCurrent = math.min(minimumCurrent, current)
			maximumCurrent = math.max(maximumCurrent, current)
		end
	end

	if minimumCurrent == math.huge then
		local fallback = math.max(
			1,
			math.floor(
				tonumber(
					workspace:GetAttribute("DungeonCurrentObjectiveIsland")
				) or 1
			)
		)

		minimumCurrent = fallback
		maximumCurrent = fallback
	end

	local routePlanPrevious = tonumber(
		workspace:GetAttribute("DungeonActiveRouteWindowPreviousCount")
	)
	local routePlanFuture = tonumber(
		workspace:GetAttribute("DungeonActiveRouteWindowFutureCount")
	)

	local previous = math.max(
		0,
		math.floor(routePlanPrevious or DEFAULT_PREVIOUS)
	)

	local future = math.max(
		1,
		math.floor(routePlanFuture or DEFAULT_FUTURE)
	)

	local minimumIndex = math.max(1, minimumCurrent - previous)
	local maximumIndex = maximumCurrent + future

	lastWindowMin = minimumIndex
	lastWindowMax = maximumIndex

	return minimumIndex, maximumIndex, minimumCurrent, maximumCurrent
end

local function checkpointMatches(island)
	if not island then
		return false
	end

	local checkpointKey = workspace:GetAttribute("DungeonCheckpointNodeKey")
	if typeof(checkpointKey) == "string"
		and checkpointKey ~= ""
	then
		local islandKey = tostring(
			island:GetAttribute("NodeKey")
				or island:GetAttribute("IslandKey")
				or ""
		)

		if islandKey ~= "" and islandKey == checkpointKey then
			return true
		end

		if island.Name == checkpointKey then
			return true
		end
	end

	local checkpointIndex = tonumber(
		workspace:GetAttribute("DungeonCheckpointIslandIndex")
	)

	local index = routeIndex(island)

	return checkpointIndex ~= nil
		and index ~= nil
		and math.floor(checkpointIndex) == index
end

local function playerNearModel(model)
	if not model or not model.Parent then
		return false
	end

	local pivot = model:GetPivot().Position
	local radius = math.max(Config.GRID_SIZE * 2.5, 80)

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character
			and character:FindFirstChildOfClass("Humanoid")
		local root = character
			and character:FindFirstChild("HumanoidRootPart")

		if humanoid
			and humanoid.Health > 0
			and root
			and (root.Position - pivot).Magnitude <= radius
		then
			return true
		end
	end

	return false
end

local function rememberParent(instance)
	if not instance or originalParents[instance] then
		return
	end

	if instance.Parent
		and instance.Parent ~= islandPool
		and instance.Parent ~= connectionPool
	then
		originalParents[instance] = instance.Parent
	end
end

local function findLiveWorldFolder(folderName)
	for _, tagged in ipairs(CollectionService:GetTagged(ISLAND_TAG)) do
		if tagged.Parent
			and tagged:IsDescendantOf(workspace)
		then
			local parent = tagged.Parent
			if parent and parent.Name == folderName then
				return parent
			end
		end
	end

	local generated = workspace:FindFirstChild("GeneratedIslands")
	if generated then
		local world = generated:FindFirstChildWhichIsA("Model")
		if world then
			return world:FindFirstChild(folderName)
		end
	end

	return nil
end

local function restoreToOriginal(instance, fallbackFolderName)
	if not instance or not instance.Parent then
		return false
	end

	local parent = originalParents[instance]

	if not parent or not parent.Parent then
		parent = findLiveWorldFolder(fallbackFolderName)
	end

	if not parent then
		return false
	end

	instance.Parent = parent
	return true
end

local function setIslandWindowState(island, active, reason)
	if not island then
		return
	end

	island:SetAttribute("ActiveWorldWindow", active == true)
	island:SetAttribute("ActiveWorldWindowReason", reason)
	island:SetAttribute(
		"ActiveWorldWindowUpdatedAt",
		workspace:GetServerTimeNow()
	)

	local terrainAreas = island:FindFirstChild("TerrainAreas")
	if terrainAreas then
		for _, child in ipairs(terrainAreas:GetChildren()) do
			if child:IsA("Model") then
				child:SetAttribute("ActiveWorldWindow", active == true)
			end
		end
	end
end

local function softUnloadIsland(island, reason)
	if not island
		or not island.Parent
		or island.Parent == islandPool
	then
		return false
	end

	if playerNearModel(island)
		or checkpointMatches(island)
		or island:GetAttribute("IsBossSanctuary") == true
	then
		return false
	end

	rememberParent(island)
	setIslandWindowState(island, false, reason)

	island.Parent = islandPool
	softUnloadedIslands += 1

	return true
end

local function restoreIsland(island, reason)
	if not island
		or not island.Parent
		or island.Parent ~= islandPool
	then
		if island and island.Parent then
			setIslandWindowState(island, true, reason)
		end
		return false
	end

	if restoreToOriginal(island, "IslandNodes") then
		setIslandWindowState(island, true, reason)
		restoredIslands += 1
		return true
	end

	return false
end

local function modelVerticalBounds(model)
	if not model or not model.Parent then
		return nil
	end

	local minimumY = math.huge
	local maximumY = -math.huge
	local found = false

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			found = true
			local half = descendant.Size.Y * 0.5
			minimumY = math.min(minimumY, descendant.Position.Y - half)
			maximumY = math.max(maximumY, descendant.Position.Y + half)
		end
	end

	if not found then
		return nil
	end

	return minimumY, maximumY
end

local function floorYForIndex(index)
	for _, island in ipairs(CollectionService:GetTagged(ISLAND_TAG)) do
		if routeIndex(island) == index and island.Parent then
			local floor = island:FindFirstChild("IslandFloor", true)
			if floor and floor:IsA("BasePart") then
				return floor.Position.Y
			end

			local model = island:FindFirstChildWhichIsA("Model", true)
			if model and model.PrimaryPart then
				return model.PrimaryPart.Position.Y
			end

			return island:GetPivot().Position.Y
		end
	end

	return nil
end

local function shouldKeepConnection(connection, minimumIndex, maximumIndex)
	local minimumFloorY = floorYForIndex(minimumIndex)
	local maximumFloorY = floorYForIndex(maximumIndex)

	if not minimumFloorY and not maximumFloorY then
		return true
	end

	local minY, maxY = modelVerticalBounds(connection)
	if not minY then
		return true
	end

	local centerY = (minY + maxY) * 0.5
	local margin = Config.GRID_SIZE * 0.75

	if minimumFloorY and centerY < minimumFloorY - margin then
		return false
	end

	if maximumFloorY and centerY > maximumFloorY + margin then
		return false
	end

	return true
end

local function softUnloadConnection(connection)
	if not connection
		or not connection.Parent
		or connection.Parent == connectionPool
	then
		return false
	end

	rememberParent(connection)
	connection:SetAttribute("ActiveWorldWindow", false)
	connection.Parent = connectionPool
	softUnloadedConnections += 1
	return true
end

local function restoreConnection(connection)
	if not connection
		or not connection.Parent
		or connection.Parent ~= connectionPool
	then
		if connection and connection.Parent then
			connection:SetAttribute("ActiveWorldWindow", true)
		end
		return false
	end

	if restoreToOriginal(connection, "IslandConnections") then
		connection:SetAttribute("ActiveWorldWindow", true)
		restoredConnections += 1
		return true
	end

	return false
end

local function reconcileIslands(minimumIndex, maximumIndex)
	local activeCount = 0
	local pooledCount = 0

	for _, island in ipairs(CollectionService:GetTagged(ISLAND_TAG)) do
		if not island:IsA("Model") or not island.Parent then
			continue
		end

		local index = routeIndex(island)

		if not index then
			if island.Parent == islandPool then
				restoreIsland(island, "NoRouteIndex")
			end
			continue
		end

		local shouldBeActive =
			(index >= minimumIndex and index <= maximumIndex)
			or checkpointMatches(island)
			or playerNearModel(island)

		if shouldBeActive then
			restoreIsland(island, "InsideActiveWindow")
		else
			softUnloadIsland(island, "OutsideActiveWindow")
		end

		if island.Parent == islandPool then
			pooledCount += 1
		elseif isInWorkspace(island) then
			activeCount += 1
		end
	end

	workspace:SetAttribute("DungeonActiveWindowWorkspaceIslands", activeCount)
	workspace:SetAttribute("DungeonActiveWindowPooledIslands", pooledCount)
end

local function reconcileConnections(minimumIndex, maximumIndex)
	local activeCount = 0
	local pooledCount = 0

	for _, connection in ipairs(CollectionService:GetTagged(CONNECTION_TAG)) do
		if not connection:IsA("Model") or not connection.Parent then
			continue
		end

		if shouldKeepConnection(connection, minimumIndex, maximumIndex) then
			restoreConnection(connection)
		else
			softUnloadConnection(connection)
		end

		if connection.Parent == connectionPool then
			pooledCount += 1
		elseif isInWorkspace(connection) then
			activeCount += 1
		end
	end

	workspace:SetAttribute("DungeonActiveWindowWorkspaceConnections", activeCount)
	workspace:SetAttribute("DungeonActiveWindowPooledConnections", pooledCount)
end

local function publish(
	minimumIndex,
	maximumIndex,
	minimumCurrent,
	maximumCurrent
)
	workspace:SetAttribute("DungeonActiveRouteWindowReady", started)
	workspace:SetAttribute("DungeonActiveRouteWindowVersion", "SoftUnloadV1")
	workspace:SetAttribute("DungeonActiveRouteWindowPolicy", "Previous1_Current_Future3")
	workspace:SetAttribute("DungeonActiveRouteWindowMinIndex", minimumIndex)
	workspace:SetAttribute("DungeonActiveRouteWindowMaxIndex", maximumIndex)
	workspace:SetAttribute("DungeonActiveRouteWindowPartyMinCurrent", minimumCurrent)
	workspace:SetAttribute("DungeonActiveRouteWindowPartyMaxCurrent", maximumCurrent)
	workspace:SetAttribute("DungeonActiveRouteWindowPreviousCount", DEFAULT_PREVIOUS)
	workspace:SetAttribute("DungeonActiveRouteWindowFutureCount", DEFAULT_FUTURE)
	workspace:SetAttribute("DungeonActiveWindowSoftUnloadedIslands", softUnloadedIslands)
	workspace:SetAttribute("DungeonActiveWindowSoftUnloadedConnections", softUnloadedConnections)
	workspace:SetAttribute("DungeonActiveWindowRestoredIslands", restoredIslands)
	workspace:SetAttribute("DungeonActiveWindowRestoredConnections", restoredConnections)
end

local function reconcile()
	if not started then
		return
	end

	if workspace:GetAttribute("DungeonRouteArchitecture")
		~= "LinearCombatRouteV1"
	then
		return
	end

	ensurePool()

	local minimumIndex,
		maximumIndex,
		minimumCurrent,
		maximumCurrent =
			currentPartyWindow()

	reconcileIslands(minimumIndex, maximumIndex)
	reconcileConnections(minimumIndex, maximumIndex)

	publish(
		minimumIndex,
		maximumIndex,
		minimumCurrent,
		maximumCurrent
	)
end

local function restoreEverything()
	ensurePool()

	for _, child in ipairs(islandPool:GetChildren()) do
		restoreIsland(child, "ServiceStopped")
	end

	for _, child in ipairs(connectionPool:GetChildren()) do
		restoreConnection(child)
	end
end

function ActiveWorldWindowService.Start()
	if started then
		return false, "AlreadyStarted"
	end

	started = true
	generation += 1

	local token = generation

	ensurePool()

	workspace:SetAttribute("DungeonActiveRouteWindowReady", true)
	workspace:SetAttribute("DungeonActiveRouteWindowVersion", "SoftUnloadV1")
	workspace:SetAttribute("DungeonActiveRouteWindowPreviousCount", DEFAULT_PREVIOUS)
	workspace:SetAttribute("DungeonActiveRouteWindowFutureCount", DEFAULT_FUTURE)

	task.spawn(function()
		while started and generation == token do
			local ok, err = pcall(reconcile)

			if not ok then
				workspace:SetAttribute(
					"DungeonActiveRouteWindowError",
					tostring(err)
				)
				warn(
					"[ActiveWorldWindowService] reconcile falhou: "
						.. tostring(err)
				)
			else
				workspace:SetAttribute("DungeonActiveRouteWindowError", nil)
			end

			task.wait(UPDATE_SECONDS)
		end
	end)

	return true
end

function ActiveWorldWindowService.Stop()
	if not started then
		return false
	end

	started = false
	generation += 1

	restoreEverything()

	workspace:SetAttribute("DungeonActiveRouteWindowReady", false)

	return true
end

function ActiveWorldWindowService.Refresh()
	reconcile()
end

function ActiveWorldWindowService.GetSnapshot()
	return {
		Ready = started,
		Version = "SoftUnloadV1",
		MinimumIndex = lastWindowMin,
		MaximumIndex = lastWindowMax,
		PreviousCount = DEFAULT_PREVIOUS,
		FutureCount = DEFAULT_FUTURE,
		SoftUnloadedIslands = softUnloadedIslands,
		SoftUnloadedConnections = softUnloadedConnections,
		RestoredIslands = restoredIslands,
		RestoredConnections = restoredConnections,
	}
end

return ActiveWorldWindowService
