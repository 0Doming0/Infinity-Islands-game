--[[
	Sky Dungeon V10 - WaterRiseSystem (Server Script)

	A agua e o relogio do dungeon. Ela solicita rounds completos quando se
	aproxima do topo seguro, remove apenas rounds totalmente submersos e envia
	o estado do andar para a interface.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(script.Parent.Config_SkyDungeon_V10)
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local ChunkManager = require(script.Parent.ChunkManager_SkyDungeon_V10)
local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)
local CollectibleService = require(script.Parent.Parent:FindFirstChild("MVPSystems"):FindFirstChild("CollectibleService"))


local waterEvent = ReplicatedStorage:FindFirstChild("WaterEvent")
if not waterEvent then
	waterEvent = Instance.new("RemoteEvent")
	waterEvent.Name = "WaterEvent"
	waterEvent.Parent = ReplicatedStorage
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
	MIN_ACTIVE_CHUNKS = MapConfig.MIN_ACTIVE_CHUNKS,

	SAFE_RESPAWN_CLEARANCE = 15,
	SAFE_RESPAWN_HRP_OFFSET = 3,
	SAFE_RESPAWN_SEARCH_RETRIES = 10,
	SAFE_RESPAWN_RETRY_DELAY = 0.1,
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
	water.Size = Vector3.new(800, 200, 800)
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = false
	water.CastShadow = false
	water.Material = Enum.Material.SmoothPlastic
	water.Transparency = 0.55
	water.Color = Color3.fromRGB(0, 105, 180)
	water.Reflectance = 0.2
	water.Parent = workspace
end

local currentWaterY = CONFIG.WATER_START_SURFACE_Y
local currentWaterSpeed = 0
local systemStartedAt = os.clock()
local waterHalfHeight = water.Size.Y / 2
water.Position = Vector3.new(MapConfig.CENTER_WORLD.X, currentWaterY - waterHalfHeight, MapConfig.CENTER_WORLD.Z)
water:SetAttribute("SurfaceY", currentWaterY)
water:SetAttribute("GenerationUnit", "Round")
water:SetAttribute("RiseSpeed", currentWaterSpeed)

local function calculateTargetWaterSpeed()
	if #Players:GetPlayers() == 0 then
		return 0, "Waiting", 0
	end

	local elapsedSeconds = os.clock() - systemStartedAt
	if elapsedSeconds < CONFIG.WATER_WARMUP_SECONDS then
		local warmupAlpha = math.clamp(elapsedSeconds / math.max(1, CONFIG.WATER_WARMUP_SECONDS), 0, 1)
		return CONFIG.WATER_RISE_SPEED * CONFIG.WATER_MIN_SPEED_MULTIPLIER * warmupAlpha, "Warmup", 0
	end

	local groupProgressY = ChunkManager.GetGroupProgressY()
	if not groupProgressY then
		return CONFIG.WATER_RISE_SPEED, "Normal", 0
	end

	local gap = groupProgressY - currentWaterY
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
	return CONFIG.WATER_RISE_SPEED * speedMultiplier * difficultyMultiplier * eventMultiplier, mode, gap
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
		if descendant:IsA("BasePart") and descendant:GetAttribute("IsMainRoute") == true then
			local surfaceY = descendant.Position.Y + descendant.Size.Y / 2
			if surfaceY >= minimumSurfaceY and surfaceY < bestSurfaceY then
				bestPart = descendant
				bestSurfaceY = surfaceY
			end
		end
	end
	return bestPart
end

local function getSafeRespawnCFrame()
	if CONFIG.RESPAWN_HEIGHT >= currentWaterY + CONFIG.SAFE_RESPAWN_CLEARANCE then
		return CFrame.new(MapConfig.CENTER_WORLD.X, CONFIG.RESPAWN_HEIGHT, MapConfig.CENTER_WORLD.Z)
	end

	ChunkManager.EnsureRoundsAheadOfWater(currentWaterY, CONFIG.SAFE_ROUND_BUFFER, CONFIG.MAX_ROUNDS_PER_REQUEST)
	for _ = 1, CONFIG.SAFE_RESPAWN_SEARCH_RETRIES do
		local routePart = findSafeRoutePart()
		if routePart then
			local position = routePart.Position
				+ Vector3.new(0, routePart.Size.Y / 2 + CONFIG.SAFE_RESPAWN_HRP_OFFSET, 0)
			return CFrame.new(position)
		end
		task.wait(CONFIG.SAFE_RESPAWN_RETRY_DELAY)
	end

	warn("[WaterRiseSystem] Nenhuma superficie segura encontrada; usando respawn temporario.")
	return CFrame.new(
		MapConfig.CENTER_WORLD.X,
		currentWaterY + CONFIG.SAFE_RESPAWN_CLEARANCE + CONFIG.SAFE_RESPAWN_HRP_OFFSET,
		MapConfig.CENTER_WORLD.Z
	)
end

local playerData = {}

local function onCharacterAdded(player, character)
	playerData[player] = {
		alive = true,
		inWater = false,
		highestHeightCheckpoint = 0,
		nextSurvivalScoreAt = os.clock() + CONFIG.SURVIVAL_SCORE_INTERVAL,
	}
	ScoreService.ResetRun(player)

	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			if playerData[player] then
				playerData[player].alive = false
			end
		end)
	end
	if rootPart then
		task.wait(0.5)
		if rootPart.Parent and player.Parent then
			rootPart.CFrame = getSafeRespawnCFrame()
		end
	end
end

local function onPlayerAdded(player)
	playerData[player] = {
		alive = true,
		inWater = false,
		highestHeightCheckpoint = 0,
		nextSurvivalScoreAt = os.clock() + CONFIG.SURVIVAL_SCORE_INTERVAL,
	}
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
local currentWaterMode = "Waiting"
local currentProgressGap = 0

while true do
	local elapsed = task.wait(CONFIG.WATER_UPDATE_RATE)
	local dt = math.min(elapsed, 0.5)
	local targetSpeed, mode, progressGap = calculateTargetWaterSpeed()
	local smoothingAlpha = 1 - math.exp(-CONFIG.WATER_SPEED_SMOOTHING * dt)
	currentWaterSpeed += (targetSpeed - currentWaterSpeed) * smoothingAlpha
	currentWaterMode = mode
	currentProgressGap = progressGap
	currentWaterY += currentWaterSpeed * dt
	water.Position = Vector3.new(MapConfig.CENTER_WORLD.X, currentWaterY - waterHalfHeight, MapConfig.CENTER_WORLD.Z)

	local now = os.clock()
	if now - lastRoundGenerationCheck >= CONFIG.ROUND_GENERATION_CHECK_RATE and #Players:GetPlayers() > 0 then
		lastRoundGenerationCheck = now
		ChunkManager.EnsureRoundsAheadOfWater(currentWaterY, CONFIG.SAFE_ROUND_BUFFER, CONFIG.MAX_ROUNDS_PER_REQUEST)
	end

	if now - lastChunkCleanup >= CONFIG.CHUNK_CLEANUP_CHECK_RATE and #Players:GetPlayers() > 0 then
		lastChunkCleanup = now
		ChunkManager.CleanupBelowWater(currentWaterY, CONFIG.CHUNK_CLEANUP_MARGIN_STUDS, CONFIG.MIN_ACTIVE_CHUNKS)
	end

	for player, data in pairs(playerData) do
		if not data.alive then
			continue
		end
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid or humanoid.Health <= 0 then
			continue
		end

		local playerY = rootPart.Position.Y
		if playerY < currentWaterY then
			data.inWater = true
			if player:GetAttribute("TutorialWaterProtection") ~= true then
				humanoid:TakeDamage(CONFIG.DAMAGE_PER_SECOND * dt)
			end
		else
			data.inWater = false
		end

		if now >= data.nextSurvivalScoreAt then
			data.nextSurvivalScoreAt = now + CONFIG.SURVIVAL_SCORE_INTERVAL
			if player:GetAttribute("TutorialActive") ~= true then
				ScoreService.Award(player, CONFIG.SURVIVAL_SCORE_AMOUNT, "SurvivalTime")
			end
		end
		local height = math.max(0, playerY - 0.5)
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
		water:SetAttribute("RiseSpeed", currentWaterSpeed)
		water:SetAttribute("TargetRiseSpeed", targetSpeed)
		water:SetAttribute("AdaptiveMode", currentWaterMode)
		water:SetAttribute("ProgressGap", currentProgressGap)
		local waterRoundStatus = ChunkManager.GetRoundStatus(currentWaterY)
		water:SetAttribute("GeneratedRounds", waterRoundStatus.GeneratedRounds)
		water:SetAttribute("SafeRoundsAhead", waterRoundStatus.SafeRoundsAhead)

		for player, data in pairs(playerData) do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local height = rootPart and math.max(0, math.floor(rootPart.Position.Y - 0.5)) or 0
			local playerRoundStatus = ChunkManager.GetRoundStatus(rootPart and rootPart.Position.Y or currentWaterY)
			waterEvent:FireClient(player, {
				waterY = math.floor(currentWaterY),
				waterSpeed = currentWaterSpeed,
				waterMode = currentWaterMode,
				waterGap = math.floor(currentProgressGap),
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
				currentRound = playerRoundStatus.CurrentRound,
				generatedRounds = waterRoundStatus.GeneratedRounds,
				safeRoundsAhead = waterRoundStatus.SafeRoundsAhead,
				groupProgressY = math.floor(waterRoundStatus.GroupProgressY or 0),
				worldEvent = workspace:GetAttribute("ActiveWorldEvent"),
			})
		end
	end
end
