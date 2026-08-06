-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

-- Tutorial visual e contextual executado no mapa procedural compartilhado.
--
-- Cada iniciante recebe objetivos pessoais, mas continua jogando no mesmo mundo
-- que os demais jogadores. O servidor valida toda a progressao e recria o
-- objetivo quando a ilha muda, a agua se aproxima ou o personagem renasce.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local blockParkour = script.Parent:WaitForChild("BlockParkour")
local mvpSystems = script.Parent:WaitForChild("MVPSystems")
local PlayerDataService = require(blockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local ScoreService = require(blockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local CollectibleService = require(mvpSystems:WaitForChild("CollectibleService"))
local RewardWheelService = require(mvpSystems:WaitForChild("RewardWheelService"))
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

ScoreService.Start()
CollectibleService.Start()
RewardWheelService.Start()

local tutorialEvent = ReplicatedStorage:FindFirstChild("TutorialEvent")
if tutorialEvent and not tutorialEvent:IsA("RemoteEvent") then
	tutorialEvent:Destroy()
	tutorialEvent = nil
end
if not tutorialEvent then
	tutorialEvent = Instance.new("RemoteEvent")
	tutorialEvent.Name = "TutorialEvent"
	tutorialEvent.Parent = ReplicatedStorage
end

local TOTAL_STAGES = 5
local CHECK_INTERVAL = 0.12
local TARGET_RADIUS = 5.75
local SAFE_WATER_CLEARANCE = 10
local CONTEXT_RECHECK_SECONDS = 0.8
local CONTEXT_CHANGE_GRACE_SECONDS = 1.25
local MAX_LOCAL_TARGET_DISTANCE = 62
local TRAINING_HIT_GOAL = 3
local ENEMY_PROTECTION_MAX_SECONDS = 150
local COMPLETION_WHEEL_SOURCE = "TutorialCompletion"
local COMPLETION_WHEEL_DELAY_SECONDS = 1.15
local PROTECTION_VERSION = "SharedWorldVisualTutorialCelebrationV3"

workspace:SetAttribute("TutorialProtectionSystemVersion", PROTECTION_VERSION)
workspace:SetAttribute("TutorialSystemVersion", PROTECTION_VERSION)

local STAGES = {
	[1] = {
		Id = "Movement",
		ActionText = "SIGA A LUZ",
		Instruction = "Mova-se até o ponto brilhante.",
		Hint = "Use o direcional para avançar.",
	},
	[2] = {
		Id = "Jump",
		ActionText = "PULE",
		Instruction = "Alcance o próximo ponto.",
		Hint = "Pule enquanto avança.",
	},
	[3] = {
		Id = "Collectible",
		ActionText = "PEGUE O FRAGMENTO",
		Instruction = "Encoste no objeto brilhante.",
		Hint = "Fragmentos concedem moedas e pontos.",
	},
	[4] = {
		Id = "Combat",
		ActionText = "ATAQUE",
		Instruction = "Acerte o alvo de treino 3 vezes.",
		Hint = "Equipe a espada e use o ataque.",
	},
	[5] = {
		Id = "Water",
		ActionText = "SUBA!",
		Instruction = "A água está subindo.",
		Hint = "Procure sempre plataformas mais altas.",
		Danger = true,
	},
}

local states = {}
local setupStarted = {}

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function setTutorialEnemyProtection(player, active)
	local enabled = active == true
	player:SetAttribute("TutorialEnemyProtection", enabled)
	player:SetAttribute("TutorialWaterProtection", false)

	local character = player.Character
	if character then
		character:SetAttribute("TutorialEnemyProtected", enabled)
		character:SetAttribute("TutorialProtectionVersion", PROTECTION_VERSION)
	end
end

local function forceTutorialForTesting()
	local config = MVPConfig.Tutorial or {}
	if config.ForceForAllPlayers ~= true and config.Audience ~= "AllPlayers" then
		return false
	end
	return config.ForceForAllPlayersOnlyInStudio ~= true or RunService:IsStudio()
end

local function getLivingRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, humanoid
end

local function getWaterSurfaceY()
	local water = workspace:FindFirstChild("Water")
	return water and tonumber(water:GetAttribute("SurfaceY")) or -math.huge
end

local function getCurrentRound(positionY)
	for _, round in ipairs(CollectionService:GetTagged("SkyDungeonRound")) do
		local bottom = tonumber(round:GetAttribute("RoundBottomWorldY") or round:GetAttribute("BottomWorldY"))
		local top = tonumber(round:GetAttribute("RoundTopWorldY") or round:GetAttribute("TopWorldY"))
		if bottom and top and positionY >= bottom and positionY <= top then
			return tonumber(round:GetAttribute("RoundIndex")) or 0
		end
	end
	return 0
end

local function isTutorialSurface(part)
	return part:IsA("BasePart")
		and part.CanCollide
		and (part:GetAttribute("IsRoundConnector") == true or part.Name == "IslandFloor")
end

local function horizontalDistance(left, right)
	return Vector2.new(left.X - right.X, left.Z - right.Z).Magnitude
end

local function forwardDirection(root)
	local direction = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if direction.Magnitude < 0.05 then
		return Vector3.new(0, 0, -1)
	end
	return direction.Unit
end

local function surfacePoint(part, root, stage)
	local topY = part.Position.Y + part.Size.Y / 2
	if part.Name ~= "IslandFloor" then
		return Vector3.new(part.Position.X, topY, part.Position.Z)
	end

	local offsets = {
		[1] = 11,
		[2] = 7,
		[3] = 8,
		[4] = 10,
		[5] = 8,
	}
	local desired = root.Position + forwardDirection(root) * (offsets[stage] or 8)
	local margin = 3
	local halfX = math.max(0, part.Size.X / 2 - margin)
	local halfZ = math.max(0, part.Size.Z / 2 - margin)
	return Vector3.new(
		math.clamp(desired.X, part.Position.X - halfX, part.Position.X + halfX),
		topY,
		math.clamp(desired.Z, part.Position.Z - halfZ, part.Position.Z + halfZ)
	)
end

local function candidateScore(stage, rootPosition, candidate, currentRound)
	local horizontal = horizontalDistance(rootPosition, candidate.SurfacePosition)
	local rise = candidate.SurfacePosition.Y - rootPosition.Y
	local absoluteRise = math.abs(rise)
	local sameRoundBonus = candidate.RoundIndex == currentRound and -10 or 0

	if stage == 1 then
		if horizontal < 7 or horizontal > 24 or absoluteRise > 8 then
			return nil
		end
		return horizontal + absoluteRise * 2 + sameRoundBonus
	elseif stage == 2 then
		if horizontal < 3 or horizontal > 24 or rise < 1.5 or rise > 14 then
			return nil
		end
		return horizontal + math.abs(rise - 5) * 2 + sameRoundBonus
	elseif stage == 3 or stage == 4 then
		if horizontal < 5 or horizontal > 24 or absoluteRise > 8 then
			return nil
		end
		return horizontal + absoluteRise * 2 + sameRoundBonus
	elseif stage == 5 then
		if horizontal < 4 or horizontal > 45 or rise < 4 or rise > 24 then
			return nil
		end
		return horizontal + math.abs(rise - 9) * 1.5 + sameRoundBonus
	end
	return nil
end

local function findContextTarget(root, stage)
	local waterY = getWaterSurfaceY()
	local currentRound = getCurrentRound(root.Position.Y)
	local preferred
	local preferredScore
	local nearest
	local nearestDistance = math.huge

	for _, round in ipairs(CollectionService:GetTagged("SkyDungeonRound")) do
		local roundIndex = tonumber(round:GetAttribute("RoundIndex")) or 0
		for _, descendant in ipairs(round:GetDescendants()) do
			if not isTutorialSurface(descendant) then
				continue
			end

			local surface = surfacePoint(descendant, root, stage)
			if surface.Y <= waterY + SAFE_WATER_CLEARANCE then
				continue
			end

			local candidate = {
				SourcePart = descendant,
				SurfacePosition = surface,
				TargetPosition = surface + Vector3.new(0, 2.8, 0),
				RoundIndex = roundIndex,
			}
			local distance = (candidate.TargetPosition - root.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearest = candidate
			end

			local score = candidateScore(stage, root.Position, candidate, currentRound)
			if score and (not preferredScore or score < preferredScore) then
				preferredScore = score
				preferred = candidate
			end
		end
	end

	local selected = preferred
	if not selected and stage ~= 5 and nearestDistance <= MAX_LOCAL_TARGET_DISTANCE then
		selected = nearest
	end
	if selected then
		selected.IsLocal = root.Position.Y > waterY + 1
			and (selected.TargetPosition - root.Position).Magnitude <= MAX_LOCAL_TARGET_DISTANCE
	end
	return selected
end

local function ensureRuntimeFolder()
	local folder = workspace:FindFirstChild("TutorialRuntime")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TutorialRuntime"
		folder.Parent = workspace
	end
	return folder
end

local function createTrainingTarget(player, surfacePosition, token, onProgress, onDefeated)
	local model = Instance.new("Model")
	model.Name = "TutorialTarget_" .. player.UserId
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("MonsterId", "TrainingSlime")
	model:SetAttribute("DisplayName", "Alvo de " .. player.DisplayName)
	model:SetAttribute("TutorialTargetUserId", player.UserId)
	model:SetAttribute("TutorialTrainingTarget", true)
	model:SetAttribute("TutorialHitsRemaining", TRAINING_HIT_GOAL)
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("UseCustomAI", true)
	model:SetAttribute("AIController", "TrainingTarget")
	model:SetAttribute("CanBecomeCompanion", false)
	model:SetAttribute("Peaceful", true)
	model:SetAttribute("NoKnockback", true)
	model:SetAttribute("CanBeKnockedBack", false)
	model:SetAttribute("CanBeStunned", false)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(3.6, 3.2, 3.6)
	root.CFrame = CFrame.new(surfacePosition + Vector3.new(0, 2.05, 0))
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.CastShadow = false
	root.Material = Enum.Material.SmoothPlastic
	root.Color = Color3.fromRGB(255, 171, 55)
	root.Parent = model
	model.PrimaryPart = root

	local face = Instance.new("Decal")
	face.Name = "Face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = root

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 207, 90)
	light.Brightness = 1.6
	light.Range = 12
	light.Parent = root

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "TrainingSparkles"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 205, 85))
	particles.LightEmission = 0.8
	particles.Lifetime = NumberRange.new(0.35, 0.7)
	particles.Speed = NumberRange.new(0.4, 1.4)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rate = 7
	particles.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 1_000_000_000
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayName = ""
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = 0
	humanoid.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TrainingLabel"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(220, 52)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("ALVO DE %s  •  %d GOLPES", string.upper(player.DisplayName), TRAINING_HIT_GOAL)
	label.TextColor3 = Color3.fromRGB(255, 240, 190)
	label.TextStrokeColor3 = Color3.fromRGB(25, 13, 4)
	label.TextStrokeTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextWrapped = true
	label.Parent = billboard

	model.Parent = ensureRuntimeFolder()
	CollectionService:AddTag(model, "CombatTarget")

	local hitsRemaining = TRAINING_HIT_GOAL
	local lastAcceptedHitAt = tonumber(model:GetAttribute("LastSwordHitAt")) or 0
	local completed = false

	model:GetAttributeChangedSignal("LastSwordHitAt"):Connect(function()
		if completed or not model.Parent then
			return
		end
		local hitAt = tonumber(model:GetAttribute("LastSwordHitAt")) or 0
		if hitAt <= lastAcceptedHitAt then
			return
		end
		lastAcceptedHitAt = hitAt
		if tonumber(model:GetAttribute("LastDamagedByUserId")) ~= player.UserId then
			return
		end

		hitsRemaining -= 1
		model:SetAttribute("TutorialHitsRemaining", hitsRemaining)
		label.Text = hitsRemaining > 0
			and string.format("ALVO DE %s  •  %d GOLPES", string.upper(player.DisplayName), hitsRemaining)
			or "ALVO DERROTADO"
		onProgress(token, TRAINING_HIT_GOAL - hitsRemaining, TRAINING_HIT_GOAL)

		root.Color = Color3.fromRGB(255, 238, 155)
		task.delay(0.1, function()
			if root.Parent and not completed then
				root.Color = Color3.fromRGB(255, 171, 55)
			end
		end)

		if hitsRemaining <= 0 then
			completed = true
			model:SetAttribute("TutorialTargetDefeated", true)
			ScoreService.AwardRewards(player, 5, 5, "TutorialTarget", root.Position)
			particles:Emit(28)
			onDefeated(token)
			Debris:AddItem(model, 0.45)
		end
	end)

	local restoringHealth = false
	humanoid.HealthChanged:Connect(function(health)
		if completed or restoringHealth or health >= humanoid.MaxHealth then
			return
		end
		restoringHealth = true
		task.defer(function()
			if humanoid.Parent and humanoid.Health > 0 and not completed then
				humanoid.Health = humanoid.MaxHealth
			end
			restoringHealth = false
		end)
	end)

	return model, root
end

local function destroyStageAssets(player, state)
	CollectibleService.RemoveTutorialCollectible(player)
	if state.StageAsset and state.StageAsset.Parent then
		state.StageAsset:Destroy()
	end
	state.StageAsset = nil
	state.TargetPart = nil
	state.TargetPosition = nil
	state.TargetSurfaceY = nil
end

local function stageProgress(state)
	if state.Stage == 4 and state.StageAsset then
		local remaining = math.max(0, tonumber(state.StageAsset:GetAttribute("TutorialHitsRemaining")) or TRAINING_HIT_GOAL)
		return TRAINING_HIT_GOAL - remaining, TRAINING_HIT_GOAL
	end
	return 0, 1
end

local function sendStage(player, state)
	local definition = STAGES[state.Stage]
	if not definition or not state.Active then
		return
	end
	local progress, goal = stageProgress(state)
	tutorialEvent:FireClient(player, {
		Action = "Show",
		Stage = state.Stage,
		TotalStages = TOTAL_STAGES,
		StageId = definition.Id,
		ActionText = definition.ActionText,
		Instruction = definition.Instruction,
		Hint = definition.Hint,
		Danger = definition.Danger == true,
		TargetPosition = state.TargetPosition,
		TargetInstance = state.TargetPart,
		WaitingForContext = state.WaitingForContext == true,
		Progress = progress,
		Goal = goal,
		ShowHintAfterSeconds = (MVPConfig.Tutorial or {}).HelpDelaySeconds or 5,
	})
end

local finishTutorial
local setupStage

local function advanceStage(player, state)
	if not state.Active or state.Advancing then
		return
	end
	state.Advancing = true
	local completedStage = state.Stage
	state.Token += 1
	tutorialEvent:FireClient(player, {
		Action = "StageComplete",
		Stage = completedStage,
		StageId = STAGES[completedStage].Id,
	})
	destroyStageAssets(player, state)

	if completedStage >= TOTAL_STAGES then
		task.delay(0.3, function()
			if player.Parent == Players and state.Active then
				finishTutorial(player, state, false)
			end
		end)
		return
	end

	state.Stage += 1
	player:SetAttribute("TutorialStage", state.Stage)
	if not state.ForcedForTesting or (MVPConfig.Tutorial or {}).PersistForcedCompletion == true then
		PlayerDataService.SetTutorialProgress(player, state.Stage, false)
		task.spawn(PlayerDataService.Save, player, false)
	end

	task.delay(0.42, function()
		if player.Parent == Players and state.Active then
			state.Advancing = false
			setupStage(player, state, false)
		end
	end)
end

finishTutorial = function(player, state, skipped)
	state.Active = false
	state.Advancing = false
	state.Token += 1
	destroyStageAssets(player, state)
	player:SetAttribute("TutorialActive", false)
	player:SetAttribute("TutorialCompleted", true)
	player:SetAttribute("TutorialStage", TOTAL_STAGES)
	player:SetAttribute("TutorialEnemyProtectionExpiresAt", nil)
	setTutorialEnemyProtection(player, false)

	local persistCompletion = not state.ForcedForTesting
		or (MVPConfig.Tutorial or {}).PersistForcedCompletion == true
	if persistCompletion then
		PlayerDataService.SetTutorialProgress(player, TOTAL_STAGES, true)
	end

	local rewardEligible = not skipped and persistCompletion
	player:SetAttribute("TutorialCompletionRewardPending", rewardEligible)
	tutorialEvent:FireClient(player, {
		Action = skipped and "Skipped" or "Complete",
		ActionText = skipped and "TUTORIAL ENCERRADO" or "TUTORIAL CONCLUÍDO!",
		Instruction = skipped
			and "Você pode aprender enquanto joga."
			or "Uma roleta especial será aberta como prêmio.",
		RewardPending = rewardEligible,
	})

	if rewardEligible then
		local completionToken = state.Token
		task.delay(COMPLETION_WHEEL_DELAY_SECONDS, function()
			if player.Parent ~= Players or state.Token ~= completionToken then
				return
			end

			local level = math.max(
				1,
				math.floor(tonumber(player:GetAttribute("RunLevel")) or 1)
			)
			local success, resultOrMessage = RewardWheelService.Spin(
				player,
				COMPLETION_WHEEL_SOURCE,
				{
					Level = level,
					DeferSave = true,
				}
			)
			player:SetAttribute("TutorialCompletionRewardPending", false)
			player:SetAttribute("TutorialCompletionRewardGranted", success == true)
			player:SetAttribute("TutorialCompletionRewardGrantedAt", serverTime())
			if success and type(resultOrMessage) == "table" then
				player:SetAttribute(
					"TutorialCompletionRewardName",
					tostring(resultOrMessage.DisplayName or "Recompensa")
				)
			else
				tutorialEvent:FireClient(player, {
					Action = "RewardError",
					Instruction = tostring(
						resultOrMessage
							or "Não foi possível abrir a recompensa."
					),
				})
			end
			task.spawn(PlayerDataService.Save, player, false)
		end)
	elseif persistCompletion then
		task.spawn(PlayerDataService.Save, player, false)
	end
end

setupStage = function(player, state, preserveBaselines)
	if not state.Active or state.Advancing then
		return
	end
	local root, humanoid = getLivingRoot(player)
	if not root then
		state.StageReady = false
		return
	end

	state.Token += 1
	local token = state.Token
	destroyStageAssets(player, state)
	state.StageReady = true
	state.WaitingForContext = false
	state.Jumped = false
	state.LandedAfterJump = false
	state.ContextRound = getCurrentRound(root.Position.Y)
	state.LastContextSetupAt = os.clock()
	state.LastContextCheckAt = os.clock()
	if not preserveBaselines then
		state.StartPosition = root.Position
	end

	local candidate = findContextTarget(root, state.Stage)
	if not candidate or not candidate.IsLocal then
		state.WaitingForContext = true
		sendStage(player, state)
		return
	end

	state.TargetPart = candidate.SourcePart
	state.TargetPosition = candidate.TargetPosition
	state.TargetSurfaceY = candidate.SurfacePosition.Y
	state.ContextRound = candidate.RoundIndex ~= 0 and candidate.RoundIndex or state.ContextRound

	if state.Stage == 3 then
		local hitbox, runtime = CollectibleService.EnsureTutorialCollectible(player, candidate.SurfacePosition)
		if hitbox then
			state.TargetPart = hitbox
			state.TargetPosition = hitbox.Position
			state.StageAsset = runtime
		else
			state.WaitingForContext = true
		end
	elseif state.Stage == 4 then
		local target, targetRoot = createTrainingTarget(
			player,
			candidate.SurfacePosition,
			token,
			function(progressToken, progress, goal)
				local current = states[player]
				if current == state and current.Active and current.Stage == 4 and current.Token == progressToken then
					tutorialEvent:FireClient(player, {
						Action = "Progress",
						Stage = 4,
						StageId = "Combat",
						Progress = progress,
						Goal = goal,
					})
				end
			end,
			function(defeatedToken)
				local current = states[player]
				if current == state and current.Active and current.Stage == 4 and current.Token == defeatedToken then
					advanceStage(player, current)
				end
			end
		)
		state.StageAsset = target
		state.TargetPart = targetRoot
		state.TargetPosition = targetRoot.Position
	end

	if humanoid then
		state.Jumped = humanoid:GetState() == Enum.HumanoidStateType.Jumping
	end
	sendStage(player, state)
end

local function bindCharacter(player, state, character)
	state.StageReady = false
	state.Token += 1
	destroyStageAssets(player, state)

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not state.Active then
		return
	end

	character:SetAttribute("TutorialEnemyProtected", player:GetAttribute("TutorialEnemyProtection") == true)
	character:SetAttribute("TutorialProtectionVersion", PROTECTION_VERSION)

	humanoid.StateChanged:Connect(function(_, nextState)
		if states[player] ~= state or not state.Active then
			return
		end
		if nextState == Enum.HumanoidStateType.Jumping then
			state.Jumped = true
		elseif state.Jumped and (
			nextState == Enum.HumanoidStateType.Landed
			or nextState == Enum.HumanoidStateType.Running
			or nextState == Enum.HumanoidStateType.RunningNoPhysics
		) then
			state.LandedAfterJump = true
		end
	end)

	humanoid.Died:Connect(function()
		if states[player] == state and state.Active then
			state.StageReady = false
			state.Token += 1
			destroyStageAssets(player, state)
		end
	end)

	task.delay(0.75, function()
		if player.Parent == Players and state.Active and player.Character == character then
			setupStage(player, state, false)
		end
	end)
end

local function setupPlayer(player)
	if setupStarted[player] then
		return
	end
	setupStarted[player] = true

	setTutorialEnemyProtection(player, true)
	local data = PlayerDataService.Load(player)
	local stage, completed = PlayerDataService.GetTutorialProgress(player)
	local forcedForTesting = forceTutorialForTesting()

	if completed and not forcedForTesting then
		player:SetAttribute("TutorialActive", false)
		player:SetAttribute("TutorialCompleted", true)
		player:SetAttribute("TutorialStage", TOTAL_STAGES)
		setTutorialEnemyProtection(player, false)
		return
	end

	local state = {
		Active = true,
		Advancing = false,
		Stage = forcedForTesting and 1
			or math.clamp(tonumber(stage) or data.TutorialStage or 1, 1, TOTAL_STAGES),
		ForcedForTesting = forcedForTesting,
		Token = 0,
		StageReady = false,
		Jumped = false,
		LandedAfterJump = false,
		LastContextCheckAt = 0,
		LastContextSetupAt = 0,
	}
	states[player] = state

	player:SetAttribute("TutorialActive", true)
	player:SetAttribute("TutorialCompleted", false)
	player:SetAttribute("TutorialStage", state.Stage)
	player:SetAttribute("TutorialEnemyProtectionExpiresAt", serverTime() + ENEMY_PROTECTION_MAX_SECONDS)
	setTutorialEnemyProtection(player, true)

	local protectionToken = state.Token
	task.delay(ENEMY_PROTECTION_MAX_SECONDS, function()
		local current = states[player]
		if current == state and current.Active and player.Parent == Players then
			setTutorialEnemyProtection(player, false)
			player:SetAttribute("TutorialEnemyProtectionExpired", true)
			player:SetAttribute("TutorialEnemyProtectionExpiresAt", nil)
			tutorialEvent:FireClient(player, {
				Action = "ProtectionEnded",
				Instruction = "A proteção inicial terminou. Continue seguindo os objetivos.",
				Token = protectionToken,
			})
		end
	end)

	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, state, character)
	end)
	if player.Character then
		task.spawn(bindCharacter, player, state, player.Character)
	end
end

tutorialEvent.OnServerEvent:Connect(function(player, request)
	if type(request) ~= "table" then
		return
	end
	local state = states[player]
	if request.Action == "Ready" then
		if state and state.Active then
			sendStage(player, state)
		elseif player:GetAttribute("TutorialCompleted") == true then
			tutorialEvent:FireClient(player, { Action = "Hide" })
		end
	elseif request.Action == "Skip" and state and state.Active then
		finishTutorial(player, state, true)
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state then
		state.Active = false
		destroyStageAssets(player, state)
		states[player] = nil
	end
	setupStarted[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		for player, state in pairs(states) do
			if not state.Active or not state.StageReady or state.Advancing then
				continue
			end

			local root, humanoid = getLivingRoot(player)
			if not root then
				continue
			end

			local reached = state.TargetPosition
				and (root.Position - state.TargetPosition).Magnitude <= TARGET_RADIUS

			if state.Stage == 1 and reached then
				advanceStage(player, state)
				continue
			elseif state.Stage == 2 then
				local grounded = humanoid and humanoid.FloorMaterial ~= Enum.Material.Air
				if reached and state.Jumped and state.LandedAfterJump and grounded then
					advanceStage(player, state)
					continue
				end
			elseif state.Stage == 3 then
				if state.StageAsset and state.StageAsset:GetAttribute("Claimed") == true then
					advanceStage(player, state)
					continue
				end
			elseif state.Stage == 5 then
				local climbed = state.StartPosition and root.Position.Y >= state.StartPosition.Y + 9
				if reached or climbed then
					advanceStage(player, state)
					continue
				end
			end

			local now = os.clock()
			if now - state.LastContextCheckAt < CONTEXT_RECHECK_SECONDS then
				continue
			end
			state.LastContextCheckAt = now

			local waterSurfaceY = getWaterSurfaceY()
			local targetInvalid = not state.TargetPart
				or not state.TargetPart.Parent
				or (state.TargetSurfaceY and state.TargetSurfaceY <= waterSurfaceY + SAFE_WATER_CLEARANCE)
			local unsafePlayerSituation = root.Position.Y <= waterSurfaceY + 1
			local currentRound = getCurrentRound(root.Position.Y)
			local changedRound = currentRound > 0 and state.ContextRound > 0 and currentRound ~= state.ContextRound

			if (
				targetInvalid
				or unsafePlayerSituation
				or changedRound
				or state.WaitingForContext
			) and now - state.LastContextSetupAt >= CONTEXT_CHANGE_GRACE_SECONDS then
				setupStage(player, state, true)
			end
		end
	end
end)
