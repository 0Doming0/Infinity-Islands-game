-- Sky Dungeon WaterRiseSystem V27 - aviso antes da inundacao e perigo da agua.
-- A agua usa a media protegida do coletivo. Sua superficie visual e dividida
-- em tiles proximos aos jogadores, pois a fronteira pode crescer em qualquer X/Z.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(script.Parent.Config_SkyDungeon_V10)
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local ChunkManager = require(script.Parent.ChunkManager_SkyDungeon_V10)
local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local RunLevelService = require(script.Parent.RunLevelService)
local CollectibleService = require(script.Parent.Parent:FindFirstChild("MVPSystems"):FindFirstChild("CollectibleService"))


local waterEvent = ReplicatedStorage:FindFirstChild("WaterEvent")
if not waterEvent then
	waterEvent = Instance.new("RemoteEvent")
	waterEvent.Name = "WaterEvent"
	waterEvent.Parent = ReplicatedStorage
end

local function setRespawnState(player, state)
	local sequence = tonumber(player:GetAttribute("RespawnSequence")) or 0
	player:SetAttribute("RespawnState", state)
	if state == "Ready" then
		player:SetAttribute("RespawnReadySequence", sequence)
		local event = ReplicatedStorage:FindFirstChild("DeathReviveEvent")
		if event and event:IsA("RemoteEvent") then
			event:FireClient(player, {
				Action = "RespawnReady",
				RespawnSequence = sequence,
			})
		end
	end
end

local CONFIG = {
	WATER_START_SURFACE_Y = MVPConfig.Water.StartSurfaceY,
	WATER_RISE_SPEED = MVPConfig.Water.BaseSpeed,
	WATER_MIN_SPEED_MULTIPLIER = MVPConfig.Water.MinimumSpeedMultiplier,
	WATER_MAX_SPEED_MULTIPLIER = MVPConfig.Water.MaximumSpeedMultiplier,
	WATER_DANGER_GAP = MVPConfig.Water.DangerGap,
	WATER_TARGET_GAP = MVPConfig.Water.TargetGap,
	WATER_FAST_GAP = MVPConfig.Water.FastGap,
	WATER_WARMUP_SECONDS = MVPConfig.Water.WarmupSeconds,
	WATER_DIFFICULTY_MINUTES = MVPConfig.Water.DifficultyMinutesToMaximum,
	WATER_MAX_DIFFICULTY_MULTIPLIER = MVPConfig.Water.MaximumDifficultyMultiplier,
	WATER_SPEED_SMOOTHING = MVPConfig.Water.SpeedSmoothing,
	WATER_UPDATE_RATE = 0.1,
	UI_UPDATE_RATE = 0.5,
	DAMAGE_PER_SECOND = MVPConfig.Water.DamagePerSecond,
	SURVIVAL_SCORE_INTERVAL = MVPConfig.Progression.SurvivalScoreIntervalSeconds,
	SURVIVAL_SCORE_AMOUNT = MVPConfig.Progression.SurvivalScorePerInterval,
	HEIGHT_CHECKPOINT_STUDS = MVPConfig.Progression.HeightCheckpointStuds,
	HEIGHT_CHECKPOINT_SCORE = MVPConfig.Progression.ScorePerHeightCheckpoint,
	RESPAWN_HEIGHT = 5,

	-- O mapa nasce por rounds conforme a agua consome o buffer seguro.
	ROUND_GENERATION_CHECK_RATE = 0.5,
	SAFE_ROUND_BUFFER = 2,
	MAX_ROUNDS_PER_REQUEST = 1,

	CHUNK_CLEANUP_CHECK_RATE = 2,
	CHUNK_CLEANUP_MARGIN_STUDS = 15,
	MIN_ACTIVE_CYCLES = MapConfig.MIN_ACTIVE_CYCLES,

	SAFE_RESPAWN_CLEARANCE = 15,
	SAFE_RESPAWN_HRP_OFFSET = 3,
	SAFE_RESPAWN_SEARCH_RETRIES = 10,
	SAFE_RESPAWN_RETRY_DELAY = 0.1,
	RESCUE_ISLAND_WAIT_SECONDS = 12,
	RESCUE_ISLAND_POLL_SECONDS = 0.25,
	SAFE_RESPAWN_PROTECTION_SECONDS = 3,
	SANCTUARY_FLOOD_GRACE_SECONDS = 5,
	TEMP_RESPAWN_PLATFORM_SIZE = Vector3.new(18, 1, 18),
	TEMP_RESPAWN_EXTRA_CLEARANCE = 8,
	TEMP_RESPAWN_RESCUE_RETRIES = 20,
	TEMP_RESPAWN_RESCUE_DELAY = 0.5,
	WATER_TILE_SIZE = 1024,
	WATER_TILE_OVERLAP = 8,
	WATER_TILE_UPDATE_RATE = 0.5,
}

ScoreService.Start()

if not ChunkManager.IsRunning() then
	ChunkManager.Start()
end
CollectibleService.Start()


local water = workspace:FindFirstChild("Water")
if not water then
	water = Instance.new("Part")
	water.Name = "Water"
	water.Size = Vector3.new(1, 200, 1)
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = false
	water.CastShadow = false
	water.Material = Enum.Material.SmoothPlastic
	water.Transparency = 1
	water.Color = Color3.fromRGB(0, 105, 180)
	water.Reflectance = 0.2
	water.Parent = workspace
end

water.Size = Vector3.new(1, math.max(200, water.Size.Y), 1)
water.Transparency = 1
local oldTiles = workspace:FindFirstChild("WaterTiles")
if oldTiles then
	oldTiles:Destroy()
end
local waterTilesFolder = Instance.new("Folder")
waterTilesFolder.Name = "WaterTiles"
waterTilesFolder.Parent = workspace
local waterTiles = {}

local safeRespawnFolder = workspace:FindFirstChild("SafeRespawnPlatforms")
if not safeRespawnFolder then
	safeRespawnFolder = Instance.new("Folder")
	safeRespawnFolder.Name = "SafeRespawnPlatforms"
	safeRespawnFolder.Parent = workspace
end

local currentWaterY = CONFIG.WATER_START_SURFACE_Y
local currentWaterSpeed = 0
local systemStartedAt = os.clock()
local observedWorldRebaseSerial = tonumber(workspace:GetAttribute("WorldRebaseSerial")) or 0
local waterHalfHeight = water.Size.Y / 2
water.Position = Vector3.new(MapConfig.CENTER_WORLD.X, currentWaterY - waterHalfHeight, MapConfig.CENTER_WORLD.Z)
water:SetAttribute("SurfaceY", currentWaterY)
water:SetAttribute("GenerationUnit", "IslandFrontier")
water:SetAttribute("RiseSpeed", currentWaterSpeed)

local function waterTileKey(position)
	local size = CONFIG.WATER_TILE_SIZE
	local x = math.floor(position.X / size + 0.5)
	local z = math.floor(position.Z / size + 0.5)
	return string.format("%d,%d", x, z), x, z
end

local function createWaterTile(key, tileX, tileZ)
	local tile = Instance.new("Part")
	tile.Name = "WaterTile_" .. key
	tile.Size = Vector3.new(
		CONFIG.WATER_TILE_SIZE + CONFIG.WATER_TILE_OVERLAP,
		water.Size.Y,
		CONFIG.WATER_TILE_SIZE + CONFIG.WATER_TILE_OVERLAP
	)
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanTouch = false
	tile.CanQuery = false
	tile.CastShadow = false
	tile.Material = Enum.Material.SmoothPlastic
	tile.Transparency = 0.55
	tile.Color = Color3.fromRGB(0, 105, 180)
	tile.Reflectance = 0.2
	tile:SetAttribute("WaterTileKey", key)
	tile:SetAttribute("TileX", tileX)
	tile:SetAttribute("TileZ", tileZ)
	tile.Parent = waterTilesFolder
	waterTiles[key] = tile
	return tile
end

local function updateWaterTiles()
	local desired = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local key, tileX, tileZ = waterTileKey(root.Position)
			desired[key] = { X = tileX, Z = tileZ }
		end
	end
	if next(desired) == nil then
		desired["0,0"] = { X = 0, Z = 0 }
	end
	for key, coordinate in pairs(desired) do
		local tile = waterTiles[key] or createWaterTile(key, coordinate.X, coordinate.Z)
		tile.Position = Vector3.new(
			coordinate.X * CONFIG.WATER_TILE_SIZE,
			currentWaterY - tile.Size.Y / 2,
			coordinate.Z * CONFIG.WATER_TILE_SIZE
		)
	end
	for key, tile in pairs(waterTiles) do
		if not desired[key] then
			tile:Destroy()
			waterTiles[key] = nil
		end
	end
end

local function logicalAltitude(physicalY)
	return physicalY + (tonumber(workspace:GetAttribute("LogicalAltitudeOffsetStuds")) or 0)
end

local function removeSafeZoneProtection(player, character)
	local forceField = character and character:FindFirstChild("SafeZoneProtection")
	if forceField then
		forceField:Destroy()
	end
	if character then
		character:SetAttribute("SafeZoneProtected", false)
		character:SetAttribute("SafeZoneType", nil)
	end
	player:SetAttribute("InSafeZone", false)
	player:SetAttribute("SafeZoneType", nil)
	player:SetAttribute("SafeZoneIslandKey", nil)
end

local FLOOD_COUNTDOWN_ATTRIBUTE = "SanctuaryFloodCountdownEnd"
local FLOODED_ISLAND_ATTRIBUTE = "FloodedSafeZoneIslandKey"
local WATER_DAMAGE_ACTIVE_ATTRIBUTE = "WaterDamageActive"

local function setWaterDamageActive(player, active)
	if player:GetAttribute(WATER_DAMAGE_ACTIVE_ATTRIBUTE) ~= active then
		player:SetAttribute(WATER_DAMAGE_ACTIVE_ATTRIBUTE, active)
	end
end

local function clearSanctuaryFloodState(player, data)
	if data then
		data.sanctuaryFloodDeadline = nil
		data.sanctuaryFloodIslandKey = nil
	end
	player:SetAttribute(FLOOD_COUNTDOWN_ATTRIBUTE, nil)
	player:SetAttribute(FLOODED_ISLAND_ATTRIBUTE, nil)
end

local function hasSanctuaryFloodGrace(player, data, canStart)
	local serverNow = workspace:GetServerTimeNow()
	local deadline = data.sanctuaryFloodDeadline
	if deadline then
		if serverNow < deadline then
			return true
		end

		player:SetAttribute(FLOODED_ISLAND_ATTRIBUTE, data.sanctuaryFloodIslandKey)
		player:SetAttribute(FLOOD_COUNTDOWN_ATTRIBUTE, nil)
		data.sanctuaryFloodDeadline = nil
		return false
	end

	if not canStart then
		return false
	end

	if player:GetAttribute("InSafeZone") ~= true
		or player:GetAttribute("SafeZoneType") ~= "Sanctuary"
	then
		return false
	end

	local islandKey = player:GetAttribute("SafeZoneIslandKey")
	if islandKey == nil or player:GetAttribute(FLOODED_ISLAND_ATTRIBUTE) == islandKey then
		return false
	end

	deadline = serverNow + CONFIG.SANCTUARY_FLOOD_GRACE_SECONDS
	data.sanctuaryFloodDeadline = deadline
	data.sanctuaryFloodIslandKey = islandKey
	player:SetAttribute(FLOOD_COUNTDOWN_ATTRIBUTE, deadline)
	return true
end

local function calculateTargetWaterSpeed()
	if #Players:GetPlayers() == 0 then
		return 0, "Waiting", 0, 0, 0
	end

	local elapsedSeconds = os.clock() - systemStartedAt
	if elapsedSeconds < CONFIG.WATER_WARMUP_SECONDS then
		local warmupAlpha = math.clamp(elapsedSeconds / math.max(1, CONFIG.WATER_WARMUP_SECONDS), 0, 1)
		return CONFIG.WATER_RISE_SPEED * CONFIG.WATER_MIN_SPEED_MULTIPLIER * warmupAlpha, "Warmup", 0, 0, 0
	end

	local collective = ChunkManager.GetCollectiveProgress()
	local groupProgressY = collective.MeanY
	if not groupProgressY then
		return CONFIG.WATER_RISE_SPEED, "Normal", 0, 0, 0
	end

	local gap = groupProgressY - currentWaterY
	local lowerGap = (collective.LowerGroupY or groupProgressY) - currentWaterY
	local speedMultiplier
	local mode
	if gap <= CONFIG.WATER_DANGER_GAP then
		speedMultiplier = CONFIG.WATER_MIN_SPEED_MULTIPLIER
		mode = "Mercy"
	elseif gap < CONFIG.WATER_TARGET_GAP then
		local alpha = (gap - CONFIG.WATER_DANGER_GAP)
			/ math.max(1, CONFIG.WATER_TARGET_GAP - CONFIG.WATER_DANGER_GAP)
		speedMultiplier = CONFIG.WATER_MIN_SPEED_MULTIPLIER
			+ (1 - CONFIG.WATER_MIN_SPEED_MULTIPLIER) * alpha
		mode = "Recovery"
	else
		local alpha = math.clamp(
			(gap - CONFIG.WATER_TARGET_GAP) / math.max(1, CONFIG.WATER_FAST_GAP - CONFIG.WATER_TARGET_GAP),
			0,
			1
		)
		speedMultiplier = 1 + (CONFIG.WATER_MAX_SPEED_MULTIPLIER - 1) * alpha
		mode = alpha > 0.55 and "Hunting" or "Normal"
	end

	local difficultyAlpha = math.clamp(
		elapsedSeconds / math.max(60, CONFIG.WATER_DIFFICULTY_MINUTES * 60),
		0,
		1
	)
	local difficultyMultiplier = 1
		+ (CONFIG.WATER_MAX_DIFFICULTY_MULTIPLIER - 1) * difficultyAlpha
	local eventMultiplier = math.max(0.25, tonumber(workspace:GetAttribute(MVPConfig.Water.EventMultiplierAttribute)) or 1)
	if lowerGap < CONFIG.WATER_DANGER_GAP and collective.Count >= 2 then
		speedMultiplier *= MapConfig.COLLECTIVE_MERCY_MULTIPLIER
		mode = "GroupMercy"
	end
	return CONFIG.WATER_RISE_SPEED * speedMultiplier * difficultyMultiplier * eventMultiplier,
		mode,
		gap,
		lowerGap,
		collective.Count
end

local function findSafeRoutePart()
	local worldModel = ChunkManager.GetWorldModel() or workspace:FindFirstChild(MapConfig.WORLD_MODEL_NAME)
	if not worldModel then
		return nil
	end
	local minimumSurfaceY = currentWaterY + CONFIG.SAFE_RESPAWN_CLEARANCE
	local bestPart
	local bestSurfaceY = math.huge
	for _, descendant in ipairs(worldModel:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Anchored
			and descendant.CanCollide
			and descendant:GetAttribute("IsMainRoute") == true
		then
			local surfaceY = descendant.Position.Y + descendant.Size.Y / 2
			if surfaceY >= minimumSurfaceY and surfaceY < bestSurfaceY then
				bestPart = descendant
				bestSurfaceY = surfaceY
			end
		end
	end
	return bestPart
end

local function validateSpawnCFrame(candidateCFrame, character, allowTemporaryPlatform)
	if not candidateCFrame then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludedInstances = { water, waterTilesFolder }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(excludedInstances, player.Character)
		end
	end
	if character and not table.find(excludedInstances, character) then
		table.insert(excludedInstances, character)
	end
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = true

	local rayOrigin = candidateCFrame.Position + Vector3.new(0, 6, 0)
	local rayDistance = 6 + CONFIG.SAFE_RESPAWN_HRP_OFFSET + 30
	local result = workspace:Raycast(rayOrigin, Vector3.new(0, -rayDistance, 0), raycastParams)
	if not result
		or not result.Instance:IsA("BasePart")
		or not result.Instance.Anchored
		or not result.Instance.CanCollide
	then
		return nil
	end
	if result.Instance:GetAttribute("TemporarySafeRespawn") == true and not allowTemporaryPlatform then
		return nil
	end

	local minimumSurfaceY = currentWaterY + CONFIG.SAFE_RESPAWN_CLEARANCE
	if result.Position.Y < minimumSurfaceY then
		return nil
	end

	return CFrame.new(result.Position + Vector3.new(0, CONFIG.SAFE_RESPAWN_HRP_OFFSET, 0))
end

local function findPermanentSafeRespawn(character, allowRetries)
	local initialCFrame = CFrame.new(MapConfig.CENTER_WORLD.X, CONFIG.RESPAWN_HEIGHT, MapConfig.CENTER_WORLD.Z)
	local validatedInitial = validateSpawnCFrame(initialCFrame, character)
	if validatedInitial then
		return validatedInitial
	end

	local sanctuaryCFrame = ChunkManager.GetSafeRespawnCFrame(
		currentWaterY,
		CONFIG.SAFE_RESPAWN_CLEARANCE,
		CONFIG.SAFE_RESPAWN_HRP_OFFSET
	)
	local validatedSanctuary = validateSpawnCFrame(sanctuaryCFrame, character)
	if validatedSanctuary then
		return validatedSanctuary
	end

	ChunkManager.EnsureRoundsAheadOfWater(currentWaterY, CONFIG.SAFE_ROUND_BUFFER, CONFIG.MAX_ROUNDS_PER_REQUEST)
	local attempts = allowRetries and CONFIG.SAFE_RESPAWN_SEARCH_RETRIES or 1
	for attempt = 1, attempts do
		local routePart = findSafeRoutePart()
		if routePart then
			local position = routePart.Position
				+ Vector3.new(0, routePart.Size.Y / 2 + CONFIG.SAFE_RESPAWN_HRP_OFFSET, 0)
			local validatedRoute = validateSpawnCFrame(CFrame.new(position), character)
			if validatedRoute then
				return validatedRoute
			end
		end
		if attempt < attempts then
			task.wait(CONFIG.SAFE_RESPAWN_RETRY_DELAY)
		end
	end
	return nil
end

local function createTemporaryRespawnPlatform(player)
	local platform = Instance.new("Part")
	platform.Name = string.format("EmergencySpawn_%d", player.UserId)
	platform.Size = CONFIG.TEMP_RESPAWN_PLATFORM_SIZE
	platform.Anchored = true
	platform.CanCollide = true
	platform.CanTouch = false
	platform.CanQuery = true
	platform.CastShadow = false
	platform.Transparency = 0.35
	platform.Material = Enum.Material.ForceField
	platform.Color = Color3.fromRGB(90, 210, 255)
	platform:SetAttribute("TemporarySafeRespawn", true)

	local surfaceY = currentWaterY
		+ CONFIG.SAFE_RESPAWN_CLEARANCE
		+ CONFIG.TEMP_RESPAWN_EXTRA_CLEARANCE
	platform.Position = Vector3.new(
		MapConfig.CENTER_WORLD.X,
		surfaceY - platform.Size.Y / 2,
		MapConfig.CENTER_WORLD.Z
	)
	platform.Parent = safeRespawnFolder

	local spawnCFrame = CFrame.new(platform.Position + Vector3.new(
		0,
		platform.Size.Y / 2 + CONFIG.SAFE_RESPAWN_HRP_OFFSET,
		0
	))
	return platform, spawnCFrame
end

local function getSafeRespawnCFrame(player, character)
	local permanentCFrame = findPermanentSafeRespawn(character, true)
	if permanentCFrame then
		return permanentCFrame, nil
	end

	local deadline = os.clock() + CONFIG.RESCUE_ISLAND_WAIT_SECONDS
	local lastRequestReason
	repeat
		local _, reason = ChunkManager.RequestSafeRespawnIsland(
			currentWaterY,
			CONFIG.SAFE_RESPAWN_CLEARANCE
		)
		lastRequestReason = reason
		task.wait(CONFIG.RESCUE_ISLAND_POLL_SECONDS)
		permanentCFrame = findPermanentSafeRespawn(character, false)
	until permanentCFrame or os.clock() >= deadline or player.Character ~= character

	if permanentCFrame then
		print("[WaterRiseSystem] Ilha de resgate pronta para " .. player.Name)
		return permanentCFrame, nil
	end

	warn(string.format(
		"[WaterRiseSystem] Geracao da ilha de resgate excedeu o limite (%s); usando plataforma temporaria para %s",
		tostring(lastRequestReason),
		player.Name
	))
	local platform, temporaryCFrame = createTemporaryRespawnPlatform(player)
	return temporaryCFrame, platform
end

local playerData = {}

local function addSpawnProtection(character)
	local existing = character:FindFirstChild("SafeRespawnProtection")
	if existing then
		existing:Destroy()
	end
	local forceField = Instance.new("ForceField")
	forceField.Name = "SafeRespawnProtection"
	forceField.Visible = false
	forceField.Parent = character
	task.delay(CONFIG.SAFE_RESPAWN_PROTECTION_SECONDS, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
end

local function rescueFromTemporaryPlatform(player, character, platform)
	task.spawn(function()
		local attempts = 0
		while platform.Parent and player.Character == character do
			task.wait(CONFIG.TEMP_RESPAWN_RESCUE_DELAY)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not rootPart then
				break
			end

			local platformSurfaceY = platform.Position.Y + platform.Size.Y / 2
			local requiredSurfaceY = currentWaterY
				+ CONFIG.SAFE_RESPAWN_CLEARANCE
				+ CONFIG.TEMP_RESPAWN_EXTRA_CLEARANCE
			if platformSurfaceY < requiredSurfaceY then
				local rise = requiredSurfaceY - platformSurfaceY
				platform.Position += Vector3.new(0, rise, 0)
				if math.abs(rootPart.Position.X - platform.Position.X) <= platform.Size.X / 2
					and math.abs(rootPart.Position.Z - platform.Position.Z) <= platform.Size.Z / 2
				then
					rootPart.CFrame += Vector3.new(0, rise, 0)
				end
			end

			local safeCFrame = findPermanentSafeRespawn(character, false)
			if safeCFrame then
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
				rootPart.CFrame = safeCFrame
				addSpawnProtection(character)
				local data = playerData[player]
				if data then
					local spawnHeight = math.max(0, logicalAltitude(rootPart.Position.Y) - 0.5)
					data.highestHeightCheckpoint = math.floor(spawnHeight / CONFIG.HEIGHT_CHECKPOINT_STUDS)
					player:SetAttribute("RunStartLogicalHeight", math.floor(spawnHeight))
				end
				platform:Destroy()
				return
			end

			ChunkManager.RequestSafeRespawnIsland(currentWaterY, CONFIG.SAFE_RESPAWN_CLEARANCE)

			attempts += 1
			if attempts == CONFIG.TEMP_RESPAWN_RESCUE_RETRIES then
				warn("[WaterRiseSystem] Aguardando geracao de ilha segura para " .. player.Name)
			end
		end

		if platform.Parent then
			platform:Destroy()
		end
	end)
end

local function requestRescueIslandAfterPartyWipe()
	for _, data in pairs(playerData) do
		if data.alive then
			return
		end
	end

	if ChunkManager.GetSafeRespawnCFrame(
		currentWaterY,
		CONFIG.SAFE_RESPAWN_CLEARANCE,
		CONFIG.SAFE_RESPAWN_HRP_OFFSET
	) then
		return
	end

	local requested, reason = ChunkManager.RequestSafeRespawnIsland(
		currentWaterY,
		CONFIG.SAFE_RESPAWN_CLEARANCE
	)
	if requested then
		print("[WaterRiseSystem] Party wipe: geracao antecipada da ilha de resgate (" .. tostring(reason) .. ")")
	else
		warn("[WaterRiseSystem] Party wipe: nao foi possivel solicitar ilha de resgate (" .. tostring(reason) .. ")")
	end
end

local function onCharacterAdded(player, character)
	setRespawnState(player, "Positioning")
	playerData[player] = {
		alive = true,
		inWater = false,
		respawning = true,
		highestHeightCheckpoint = 0,
		nextSurvivalScoreAt = os.clock() + CONFIG.SURVIVAL_SCORE_INTERVAL,
	}
	clearSanctuaryFloodState(player, playerData[player])
	player:SetAttribute("WaterContacting", false)
	setWaterDamageActive(player, false)
	ScoreService.ResetRun(player)

	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			if playerData[player] then
				playerData[player].alive = false
			end
			setWaterDamageActive(player, false)
			task.defer(requestRescueIslandAfterPartyWipe)
		end)
	end
	if rootPart then
		local data = playerData[player]
		if data then
			data.respawning = true
		end
		addSpawnProtection(character)
		local wasAnchored = rootPart.Anchored
		rootPart.Anchored = true
		task.wait(0.5)
		if rootPart.Parent and player.Parent and humanoid and humanoid.Health > 0 then
			local spawnCFrame, temporaryPlatform = getSafeRespawnCFrame(player, character)
			local confirmedCFrame = validateSpawnCFrame(spawnCFrame, character, temporaryPlatform ~= nil)
			if confirmedCFrame then
				spawnCFrame = confirmedCFrame
			else
				if temporaryPlatform and temporaryPlatform.Parent then
					temporaryPlatform:Destroy()
				end
				temporaryPlatform, spawnCFrame = createTemporaryRespawnPlatform(player)
			end
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			rootPart.CFrame = spawnCFrame
			rootPart.Anchored = wasAnchored
			addSpawnProtection(character)
			if temporaryPlatform then
				rescueFromTemporaryPlatform(player, character, temporaryPlatform)
			end
			if data then
				local spawnHeight = math.max(0, logicalAltitude(rootPart.Position.Y) - 0.5)
				data.highestHeightCheckpoint = math.floor(spawnHeight / CONFIG.HEIGHT_CHECKPOINT_STUDS)
				player:SetAttribute("RunStartLogicalHeight", math.floor(spawnHeight))
				data.respawning = false
			end
			if player.Character == character and humanoid.Health > 0 then
				character:SetAttribute("RespawnReady", true)
				setRespawnState(player, "Ready")
			end
		elseif rootPart.Parent then
			rootPart.Anchored = wasAnchored
			setRespawnState(player, "Failed")
		end
	else
		setRespawnState(player, "Failed")
	end
end

local function onPlayerAdded(player)
	playerData[player] = {
		alive = true,
		inWater = false,
		respawning = false,
		highestHeightCheckpoint = 0,
		nextSurvivalScoreAt = os.clock() + CONFIG.SURVIVAL_SCORE_INTERVAL,
	}
	clearSanctuaryFloodState(player, playerData[player])
	setWaterDamageActive(player, false)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

local lastUIUpdate = 0
local lastRoundGenerationCheck = 0
local lastChunkCleanup = 0
local lastWaterTileUpdate = 0
local currentWaterMode = "Waiting"
local currentProgressGap = 0
local currentLowerGroupGap = 0
local currentCollectiveCount = 0

while true do
	local elapsed = task.wait(CONFIG.WATER_UPDATE_RATE)
	local dt = math.min(elapsed, 0.5)
	local rebaseSerial = tonumber(workspace:GetAttribute("WorldRebaseSerial")) or 0
	if rebaseSerial ~= observedWorldRebaseSerial then
		currentWaterY -= tonumber(workspace:GetAttribute("LastWorldRebaseShiftStuds")) or 0
		observedWorldRebaseSerial = rebaseSerial
	end
	local targetSpeed, mode, progressGap, lowerGroupGap, collectiveCount = calculateTargetWaterSpeed()
	local smoothingAlpha = 1 - math.exp(-CONFIG.WATER_SPEED_SMOOTHING * dt)
	currentWaterSpeed += (targetSpeed - currentWaterSpeed) * smoothingAlpha
	currentWaterMode = mode
	currentProgressGap = progressGap
	currentLowerGroupGap = lowerGroupGap
	currentCollectiveCount = collectiveCount
	currentWaterY += currentWaterSpeed * dt
	water.Position = Vector3.new(MapConfig.CENTER_WORLD.X, currentWaterY - waterHalfHeight, MapConfig.CENTER_WORLD.Z)
	for _, tile in pairs(waterTiles) do
		tile.Position = Vector3.new(tile.Position.X, currentWaterY - tile.Size.Y / 2, tile.Position.Z)
	end

	local now = os.clock()
	if now - lastWaterTileUpdate >= CONFIG.WATER_TILE_UPDATE_RATE then
		lastWaterTileUpdate = now
		updateWaterTiles()
	end
	if now - lastRoundGenerationCheck >= CONFIG.ROUND_GENERATION_CHECK_RATE and #Players:GetPlayers() > 0 then
		lastRoundGenerationCheck = now
		ChunkManager.EnsureRoundsAheadOfWater(currentWaterY, CONFIG.SAFE_ROUND_BUFFER, CONFIG.MAX_ROUNDS_PER_REQUEST)
	end

	if now - lastChunkCleanup >= CONFIG.CHUNK_CLEANUP_CHECK_RATE and #Players:GetPlayers() > 0 then
		lastChunkCleanup = now
		ChunkManager.CleanupBelowWater(currentWaterY, CONFIG.CHUNK_CLEANUP_MARGIN_STUDS, CONFIG.MIN_ACTIVE_CYCLES)
	end

	for player, data in pairs(playerData) do
		if not data.alive or data.respawning then
			setWaterDamageActive(player, false)
			continue
		end
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid or humanoid.Health <= 0 then
			setWaterDamageActive(player, false)
			continue
		end

		local playerY = rootPart.Position.Y
		local feetY = playerY - humanoid.HipHeight - rootPart.Size.Y / 2
			+ math.max(0, tonumber(MVPConfig.SafeZones.WaterContactFootOffsetStuds) or 0.5)
		local touchingWater = feetY <= currentWaterY
		local sanctuaryGraceActive = hasSanctuaryFloodGrace(player, data, touchingWater)
		if touchingWater then
			data.inWater = true
			player:SetAttribute("WaterContacting", true)
			if not sanctuaryGraceActive then
				removeSafeZoneProtection(player, character)
			end
			local waterCanDamage = not sanctuaryGraceActive
				and player:GetAttribute("TutorialWaterProtection") ~= true
				and character:FindFirstChildOfClass("ForceField") == nil
			setWaterDamageActive(player, waterCanDamage)
			if waterCanDamage then
				humanoid:TakeDamage(CONFIG.DAMAGE_PER_SECOND * dt)
			end
		else
			data.inWater = false
			player:SetAttribute("WaterContacting", false)
			setWaterDamageActive(player, false)
		end

		if now >= data.nextSurvivalScoreAt then
			data.nextSurvivalScoreAt = now + CONFIG.SURVIVAL_SCORE_INTERVAL
			if player:GetAttribute("TutorialActive") ~= true then
				ScoreService.Award(player, CONFIG.SURVIVAL_SCORE_AMOUNT, "SurvivalTime")
			end
		end
		local height = math.max(0, logicalAltitude(playerY) - 0.5)
		RunLevelService.UpdateProgress(player, height)
		local checkpoint = math.floor(height / CONFIG.HEIGHT_CHECKPOINT_STUDS)
		if checkpoint > data.highestHeightCheckpoint then
			local crossed = checkpoint - data.highestHeightCheckpoint
			data.highestHeightCheckpoint = checkpoint
			ScoreService.Award(player, crossed * CONFIG.HEIGHT_CHECKPOINT_SCORE, "HeightCheckpoint")
		end
	end

	if now - lastUIUpdate >= CONFIG.UI_UPDATE_RATE then
		lastUIUpdate = now
		water:SetAttribute("SurfaceY", currentWaterY)
		water:SetAttribute("LogicalSurfaceY", logicalAltitude(currentWaterY))
		water:SetAttribute("RiseSpeed", currentWaterSpeed)
		water:SetAttribute("TargetRiseSpeed", targetSpeed)
		water:SetAttribute("AdaptiveMode", currentWaterMode)
		water:SetAttribute("ProgressGap", currentProgressGap)
		water:SetAttribute("LowerGroupGap", currentLowerGroupGap)
		water:SetAttribute("CollectivePlayerCount", currentCollectiveCount)
		local waterRoundStatus = ChunkManager.GetRoundStatus(currentWaterY)
		water:SetAttribute("GeneratedRounds", waterRoundStatus.GeneratedRounds)
		water:SetAttribute("SafeRoundsAhead", waterRoundStatus.SafeRoundsAhead)

		for player, data in pairs(playerData) do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local height = rootPart and math.max(0, math.floor(logicalAltitude(rootPart.Position.Y) - 0.5)) or 0
			local playerRoundStatus = ChunkManager.GetRoundStatus(rootPart and rootPart.Position.Y or currentWaterY)
			local playerContext = rootPart and ChunkManager.GetPlayerWorldContext(rootPart.Position) or nil
			waterEvent:FireClient(player, {
				waterY = math.floor(logicalAltitude(currentWaterY)),
				waterSpeed = currentWaterSpeed,
				waterMode = currentWaterMode,
				waterGap = math.floor(currentProgressGap),
				lowerGroupGap = math.floor(currentLowerGroupGap),
				collectivePlayerCount = currentCollectiveCount,
				score = ScoreService.GetScore(player),
				runScore = ScoreService.GetRunScore(player),
				bestScore = ScoreService.GetBestScore(player),
				coins = ScoreService.GetCoins(player),
				lastDeathRunScore = player:GetAttribute("LastDeathRunScore") or 0,
				lastDeathCoinsLost = player:GetAttribute("LastDeathCoinsLost") or 0,
				scoreMultiplier = ScoreService.GetMultiplier(player),
				height = height,
				alive = data.alive,
				inWater = data.inWater,
				currentRound = playerContext and playerContext.LogicalLevel or playerRoundStatus.CurrentRound,
				currentCycle = playerContext and playerContext.CycleIndex or playerRoundStatus.CurrentCycle,
				currentRoute = playerContext and playerContext.RouteId or nil,
				currentRouteProfile = playerContext and playerContext.RouteProfile or nil,
				inSocialSanctuary = playerContext and playerContext.IsSanctuary or false,
				currentIslandKey = playerContext and playerContext.IslandKey or nil,
				currentLaneX = playerContext and playerContext.LaneX or nil,
				currentLaneZ = playerContext and playerContext.LaneZ or nil,
				inConvergenceIsland = playerContext and playerContext.IsConvergence or false,
				generatedRounds = waterRoundStatus.GeneratedRounds,
				safeRoundsAhead = waterRoundStatus.SafeRoundsAhead,
				groupProgressY = waterRoundStatus.GroupProgressY
					and math.floor(logicalAltitude(waterRoundStatus.GroupProgressY))
					or 0,
				worldEvent = workspace:GetAttribute("ActiveWorldEvent"),
			})
		end
	end
end
