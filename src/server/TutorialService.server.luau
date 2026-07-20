-- Tutorial contextual para iniciantes. O progresso e autoritativo no servidor e
-- continua valido quando o jogador morre, reconecta ou entra no meio de um round.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local blockParkour = script.Parent:WaitForChild("BlockParkour")
local mvpSystems = script.Parent:WaitForChild("MVPSystems")
local PlayerDataService = require(blockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local CollectibleService = require(mvpSystems:WaitForChild("CollectibleService"))

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
local CHECK_INTERVAL = 0.15
local TARGET_RADIUS = 6
local SAFE_WATER_CLEARANCE = 9
local CONTEXT_RECHECK_SECONDS = 1
local CONTEXT_CHANGE_GRACE_SECONDS = 2
local MAX_LOCAL_TARGET_DISTANCE = 58

local STAGES = {
	[1] = {
		Id = "Movement",
		Title = "MOVIMENTO",
		Instruction = "Vá até o ponto iluminado.",
	},
	[2] = {
		Id = "Jump",
		Title = "PULO",
		Instruction = "Pule para alcançar o próximo bloco.",
	},
	[3] = {
		Id = "Collectible",
		Title = "COLETÁVEL",
		Instruction = "Pegue o fragmento brilhante.",
	},
	[4] = {
		Id = "Combat",
		Title = "COMBATE",
		Instruction = "Equipe sua espada e derrote o alvo de treino.",
	},
	[5] = {
		Id = "Water",
		Title = "ÁGUA",
		Instruction = "Continue subindo para escapar da água.",
	},
}

local states = {}
local setupStarted = {}

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

local function surfacePoint(part, root, stage)
	local topY = part.Position.Y + part.Size.Y / 2
	if part.Name ~= "IslandFloor" then
		return Vector3.new(part.Position.X, topY, part.Position.Z)
	end

	local direction = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end
	local offset = (stage == 1 and 10) or (stage == 3 and 7) or (stage == 4 and 9) or 6
	local desired = root.Position + direction * offset
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
	local sameRoundBonus = candidate.RoundIndex == currentRound and -8 or 0

	if stage == 1 then
		if horizontal < 7 or horizontal > 42 or absoluteRise > 12 then
			return nil
		end
		return horizontal + absoluteRise * 2 + sameRoundBonus
	elseif stage == 2 then
		if horizontal < 3 or horizontal > 28 or rise < 1.5 or rise > 18 then
			return nil
		end
		return horizontal + math.abs(rise - 5) * 2 + sameRoundBonus
	elseif stage == 3 or stage == 4 then
		if horizontal < 4 or horizontal > 28 or absoluteRise > 10 then
			return nil
		end
		return horizontal + absoluteRise * 2 + sameRoundBonus
	elseif stage == 5 then
		if horizontal > 55 or rise < 4 or rise > 26 then
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
				TargetPosition = surface + Vector3.new(0, 3, 0),
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

	local selected = preferred or (stage ~= 5 and nearest)
	if selected then
		local currentSituationValid = root.Position.Y > waterY + 1
		selected.IsLocal = currentSituationValid
			and (preferred ~= nil
				or (selected.TargetPosition - root.Position).Magnitude <= MAX_LOCAL_TARGET_DISTANCE)
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

local function createTrainingTarget(player, surfacePosition, token, onDefeated)
	local model = Instance.new("Model")
	model.Name = "TutorialTarget_" .. player.UserId
	model:SetAttribute("RuntimeMonster", true)
	model:SetAttribute("MonsterId", "TrainingWisp")
	model:SetAttribute("TutorialTargetUserId", player.UserId)
	model:SetAttribute("UseCentralAI", false)
	model:SetAttribute("Peaceful", true)
	model:SetAttribute("NoKnockback", true)
	model:SetAttribute("HomePosition", surfacePosition)
	model:SetAttribute("MovementBoundsCenter", surfacePosition)
	model:SetAttribute("MovementBoundsHalfSize", Vector3.new(4, 0, 4))
	model:SetAttribute("FallRecoveryY", surfacePosition.Y - 8)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(3.2, 3.2, 3.2)
	root.CFrame = CFrame.new(surfacePosition + Vector3.new(0, 2.1, 0))
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.Material = Enum.Material.Neon
	root.Color = Color3.fromRGB(255, 190, 62)
	root.Parent = model
	model.PrimaryPart = root

	local light = Instance.new("PointLight")
	light.Color = root.Color
	light.Brightness = 1.4
	light.Range = 10
	light.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 30
	humanoid.Health = 30
	humanoid.DisplayName = "ALVO DE TREINO"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.HealthDisplayDistance = 35
	humanoid.NameDisplayDistance = 35
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = 0
	humanoid.Parent = model

	model.Parent = ensureRuntimeFolder()
	CollectionService:AddTag(model, "CombatTarget")
	humanoid.Died:Connect(function()
		local creator = humanoid:FindFirstChild("creator")
		if creator and creator:IsA("ObjectValue") and creator.Value == player then
			onDefeated(token)
		end
		task.delay(0.6, function()
			if model.Parent then
				model:Destroy()
			end
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
end

local function sendStage(player, state)
	local definition = STAGES[state.Stage]
	if not definition or not state.Active then
		return
	end
	tutorialEvent:FireClient(player, {
		Action = "Show",
		Stage = state.Stage,
		TotalStages = TOTAL_STAGES,
		StageId = definition.Id,
		Title = definition.Title,
		Instruction = definition.Instruction,
		TargetPosition = state.TargetPosition,
		WaitingForContext = state.WaitingForContext == true,
		Progress = 0,
		Goal = 1,
	})
end

local finishTutorial
local setupStage

local function advanceStage(player, state)
	if not state.Active or state.Advancing then
		return
	end
	state.Advancing = true
	state.Token += 1
	destroyStageAssets(player, state)
	if state.Stage >= TOTAL_STAGES then
		finishTutorial(player, state, false)
		return
	end

	state.Stage += 1
	PlayerDataService.SetTutorialProgress(player, state.Stage, false)
	player:SetAttribute("TutorialStage", state.Stage)
	task.spawn(PlayerDataService.Save, player, false)
	task.delay(0.45, function()
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
	player:SetAttribute("TutorialWaterProtection", false)
	player:SetAttribute("TutorialCompleted", true)
	player:SetAttribute("TutorialStage", TOTAL_STAGES)
	PlayerDataService.SetTutorialProgress(player, TOTAL_STAGES, true)
	tutorialEvent:FireClient(player, {
		Action = skipped and "Skipped" or "Complete",
		Title = skipped and "TUTORIAL ENCERRADO" or "VOCÊ ESTÁ PRONTO!",
		Instruction = skipped and "Continue subindo e sobreviva." or "Continue subindo!",
	})
	task.spawn(PlayerDataService.Save, player, false)
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
	state.ContextRound = getCurrentRound(root.Position.Y)
	state.LastContextSetupAt = os.clock()
	state.LastContextCheckAt = os.clock()
	if not preserveBaselines then
		state.StartPosition = root.Position
		state.CoinSerial = tonumber(player:GetAttribute("LastCoinSerial")) or 0
		state.HitSerial = tonumber(player:GetAttribute("SwordHitSerial")) or 0
	end

	local candidate = findContextTarget(root, state.Stage)
	if not candidate then
		state.WaitingForContext = true
		sendStage(player, state)
		return
	end

	-- Um reposicionamento so ocorre quando nao ha objetivo local utilizavel. Isso
	-- recupera entradas no vazio ou em um round ja removido sem interromper quem
	-- entrou em uma situacao valida.
	if not candidate.IsLocal then
		root.CFrame = CFrame.new(candidate.TargetPosition)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		state.StartPosition = root.Position
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
		local target, targetRoot = createTrainingTarget(player, candidate.SurfacePosition, token, function(defeatedToken)
			local current = states[player]
			if current == state and current.Active and current.Stage == 4 and current.Token == defeatedToken then
				advanceStage(player, current)
			end
		end)
		state.StageAsset = target
		state.TargetPart = targetRoot
		state.TargetPosition = targetRoot.Position
	end

	if humanoid then
		-- A conexao permanente do personagem registra o pulo; esta leitura cobre
		-- uma troca de etapa durante o proprio salto.
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
	humanoid.StateChanged:Connect(function(_, nextState)
		if states[player] == state and state.Active and nextState == Enum.HumanoidStateType.Jumping then
			state.Jumped = true
		end
	end)
	humanoid.Died:Connect(function()
		if states[player] == state and state.Active then
			state.StageReady = false
			state.Token += 1
			destroyStageAssets(player, state)
		end
	end)
	task.delay(0.8, function()
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
	-- Protege a entrada enquanto o DataStore decide se este jogador ainda e
	-- iniciante. Perfis concluidos perdem a protecao assim que o load termina.
	player:SetAttribute("TutorialWaterProtection", true)
	local data = PlayerDataService.Load(player)
	local stage, completed = PlayerDataService.GetTutorialProgress(player)
	if completed then
		player:SetAttribute("TutorialActive", false)
		player:SetAttribute("TutorialWaterProtection", false)
		player:SetAttribute("TutorialCompleted", true)
		player:SetAttribute("TutorialStage", TOTAL_STAGES)
		return
	end

	local state = {
		Active = true,
		Advancing = false,
		Stage = math.clamp(tonumber(stage) or data.TutorialStage or 1, 1, TOTAL_STAGES),
		Token = 0,
		StageReady = false,
		Jumped = false,
		LastContextCheckAt = 0,
		LastContextSetupAt = 0,
	}
	states[player] = state
	player:SetAttribute("TutorialActive", true)
	player:SetAttribute("TutorialWaterProtection", true)
	player:SetAttribute("TutorialCompleted", false)
	player:SetAttribute("TutorialStage", state.Stage)

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

CollectibleService.Start()

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		for player, state in pairs(states) do
			if not state.Active or not state.StageReady or state.Advancing then
				continue
			end
			local root = getLivingRoot(player)
			if not root then
				continue
			end

			local reached = state.TargetPosition
				and (root.Position - state.TargetPosition).Magnitude <= TARGET_RADIUS
			if state.Stage == 1 and reached then
				advanceStage(player, state)
				continue
			elseif state.Stage == 2 and reached and state.Jumped then
				advanceStage(player, state)
				continue
			elseif state.Stage == 3 then
				local coinSerial = tonumber(player:GetAttribute("LastCoinSerial")) or 0
				local coinSource = tostring(player:GetAttribute("LastCoinSource") or "")
				if coinSerial > state.CoinSerial and string.find(coinSource, "Collectible:", 1, true) == 1 then
					advanceStage(player, state)
					continue
				end
			elseif state.Stage == 4 then
				local hitSerial = tonumber(player:GetAttribute("SwordHitSerial")) or 0
				if hitSerial > state.HitSerial and (tonumber(player:GetAttribute("SwordKillCount")) or 0) > 0 then
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
			if
				(targetInvalid or unsafePlayerSituation or changedRound or state.WaitingForContext)
				and now - state.LastContextSetupAt >= CONTEXT_CHANGE_GRACE_SECONDS
			then
				setupStage(player, state, true)
			end
		end
	end
end)
