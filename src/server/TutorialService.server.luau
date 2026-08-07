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

-- Tutorial dinamico integrado ao mapa procedural compartilhado.
--
-- O jogador escolhe livremente a rota, a ilha, o inimigo e a recompensa.
-- O servidor apenas observa conquistas naturais e recomenda a oportunidade
-- mais util no contexto atual. Nenhum waypoint, mob ou coletavel artificial
-- e criado pelo tutorial.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local blockParkour = script.Parent:WaitForChild("BlockParkour")
local mvpSystems = script.Parent:WaitForChild("MVPSystems")
local PlayerDataService = require(blockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local RewardWheelService = require(mvpSystems:WaitForChild("RewardWheelService"))
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

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

local CHECK_INTERVAL = 0.15
local CONTEXT_SCAN_INTERVAL = 0.65
local GUIDANCE_REFRESH_SECONDS = 2.5
local MOVEMENT_DISTANCE_GOAL = 12
local EXPLORATION_HEIGHT_GOAL = 12
local WATER_RISE_TO_OBSERVE = 0.75
local WATER_DANGER_GAP = 24
local WATER_SAFE_GAP = 18
local WATER_SAFE_SECONDS = 2.5
local WATER_RESPONSE_DISTANCE = 14
local ENEMY_PROTECTION_MAX_SECONDS = 150
local COMPLETION_WHEEL_SOURCE = "TutorialCompletion"
local COMPLETION_WHEEL_DELAY_SECONDS = 1.15
local SYSTEM_VERSION = "DynamicWorldTutorialV4"

local GOALS = table.freeze({
	{
		Id = "Mobility",
		Label = "MOVIMENTAÇÃO",
	},
	{
		Id = "Exploration",
		Label = "EXPLORAÇÃO",
	},
	{
		Id = "Combat",
		Label = "COMBATE",
	},
	{
		Id = "Reward",
		Label = "RECOMPENSA",
	},
	{
		Id = "Survival",
		Label = "SOBREVIVÊNCIA",
	},
})

local GOAL_INDEX = {}
for index, definition in ipairs(GOALS) do
	GOAL_INDEX[definition.Id] = index
end

local states = setmetatable({}, { __mode = "k" })
local setupStarted = setmetatable({}, { __mode = "k" })
local boundCombatTargets = setmetatable({}, { __mode = "k" })
local boundHumanoids = setmetatable({}, { __mode = "k" })
local boundChests = setmetatable({}, { __mode = "k" })
local boundPrompts = setmetatable({}, { __mode = "k" })

workspace:SetAttribute("TutorialProtectionSystemVersion", SYSTEM_VERSION)
workspace:SetAttribute("TutorialSystemVersion", SYSTEM_VERSION)
workspace:SetAttribute("TutorialDesign", "DynamicContextualNoForcedTargets")
workspace:SetAttribute("TutorialGoalCount", #GOALS)

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function forceTutorialForTesting()
	local config = MVPConfig.Tutorial or {}
	if config.ForceForAllPlayers ~= true and config.Audience ~= "AllPlayers" then
		return false
	end
	return config.ForceForAllPlayersOnlyInStudio ~= true or RunService:IsStudio()
end

local function setTutorialEnemyProtection(player, active)
	local enabled = active == true
	player:SetAttribute("TutorialEnemyProtection", enabled)
	player:SetAttribute("TutorialWaterProtection", false)

	local character = player.Character
	if character then
		character:SetAttribute("TutorialEnemyProtected", enabled)
		character:SetAttribute("TutorialProtectionVersion", SYSTEM_VERSION)
	end
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
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	return surfaceY
end

local function completedCount(state)
	local count = 0
	for _, definition in ipairs(GOALS) do
		if state.Completed[definition.Id] then
			count += 1
		end
	end
	return count
end

local function goalMask(state)
	local mask = 0
	for index, definition in ipairs(GOALS) do
		if state.Completed[definition.Id] then
			mask += 2 ^ (index - 1)
		end
	end
	return mask
end

local function isNaturalEnemy(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return false
	end
	if Players:GetPlayerFromCharacter(model) then
		return false
	end
	if model:GetAttribute("IsCompanion") == true
		or model:GetAttribute("TutorialTrainingTarget") == true
		or model:GetAttribute("EntityType") == "StaticObject"
		or model:GetAttribute("Targetable") == false
	then
		return false
	end
	return model:FindFirstChildWhichIsA("Humanoid", true) ~= nil
end

local function creditedPlayer(model, humanoid)
	local creator = humanoid and humanoid:FindFirstChild("creator")
	if creator and creator:IsA("ObjectValue") and creator.Value and creator.Value:IsA("Player") then
		return creator.Value
	end
	local userId = tonumber(model and model:GetAttribute("LastDamagedByUserId"))
	if userId and userId > 0 then
		return Players:GetPlayerByUserId(userId)
	end
	return nil
end

local sendGuidance
local finishTutorial

local function completeGoal(player, state, goalId, source)
	if not state.Active or state.Completed[goalId] or not GOAL_INDEX[goalId] then
		return false
	end

	state.Completed[goalId] = true
	local count = completedCount(state)
	local definition = GOALS[GOAL_INDEX[goalId]]
	player:SetAttribute("TutorialGoal_" .. goalId, true)
	player:SetAttribute("TutorialCompletedGoalCount", count)
	player:SetAttribute("TutorialDynamicGoalMask", goalMask(state))
	player:SetAttribute("TutorialStage", count)
	player:SetAttribute("TutorialLastCompletedGoal", goalId)
	player:SetAttribute("TutorialLastCompletedGoalAt", serverTime())
	player:SetAttribute("TutorialLastCompletedGoalSource", tostring(source or "ServerValidated"))

	tutorialEvent:FireClient(player, {
		Action = "StageComplete",
		GoalId = goalId,
		GoalLabel = definition.Label,
		CompletedCount = count,
		TotalGoals = #GOALS,
	})

	if count >= #GOALS then
		state.Finishing = true
		task.delay(0.35, function()
			if player.Parent == Players and states[player] == state and state.Active then
				finishTutorial(player, state, false)
			end
		end)
	else
		task.delay(0.4, function()
			if player.Parent == Players and states[player] == state and state.Active then
				sendGuidance(player, state, true)
			end
		end)
	end
	return true
end

local function bindCombatHumanoid(model, humanoid)
	if boundHumanoids[humanoid] then
		return
	end
	boundHumanoids[humanoid] = true

	humanoid.Died:Connect(function()
		if not isNaturalEnemy(model) then
			return
		end
		local player = creditedPlayer(model, humanoid)
		local state = player and states[player]
		if state and state.Active then
			completeGoal(player, state, "Combat", tostring(model:GetAttribute("MonsterId") or model.Name))
		end
	end)
end

local function bindCombatTarget(instance)
	if not instance or not instance:IsA("Model") or boundCombatTargets[instance] then
		return
	end
	boundCombatTargets[instance] = true

	local humanoid = instance:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		bindCombatHumanoid(instance, humanoid)
	end
	instance.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Humanoid") then
			bindCombatHumanoid(instance, descendant)
		end
	end)
end

local function bindChestPrompt(chest, prompt)
	if boundPrompts[prompt] then
		return
	end
	boundPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		local state = states[player]
		if state and state.Active and chest:IsDescendantOf(workspace) then
			completeGoal(player, state, "Reward", "Chest:" .. tostring(chest.Name))
		end
	end)
end

local function bindChest(instance)
	if not instance or not instance:IsA("Model") or boundChests[instance] then
		return
	end
	boundChests[instance] = true
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			bindChestPrompt(instance, descendant)
		end
	end
	instance.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			bindChestPrompt(instance, descendant)
		end
	end)
end

for _, target in ipairs(CollectionService:GetTagged("CombatTarget")) do
	bindCombatTarget(target)
end
CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(bindCombatTarget)

for _, chest in ipairs(CollectionService:GetTagged("AnalyticsChest")) do
	bindChest(chest)
end
CollectionService:GetInstanceAddedSignal("AnalyticsChest"):Connect(bindChest)

local function taggedAncestor(instance, tagName)
	local current = instance
	while current and current ~= workspace do
		if CollectionService:HasTag(current, tagName) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function scanNearbyContext(player, state, root)
	state.EnemyNearby = false
	state.ChestNearby = false

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.MaxParts = 80

	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, 34, params)) do
		if not state.Completed.Combat and not state.EnemyNearby then
			local enemy = taggedAncestor(part, "CombatTarget")
			if enemy and isNaturalEnemy(enemy) then
				local humanoid = enemy:FindFirstChildWhichIsA("Humanoid", true)
				if humanoid and humanoid.Health > 0 then
					state.EnemyNearby = true
				end
			end
		end
		if not state.Completed.Reward and not state.ChestNearby then
			local chest = taggedAncestor(part, "AnalyticsChest")
			if chest and chest:IsDescendantOf(workspace) and chest:GetAttribute("Opened") ~= true then
				state.ChestNearby = true
			end
		end
		if state.EnemyNearby and state.ChestNearby then
			break
		end
	end
end

local function mobilityProgress(state)
	local progress = 0
	if state.MovedEnough then
		progress += 1
	end
	if state.Jumped then
		progress += 1
	end
	return progress, 2
end

local function currentGuidance(player, state)
	local root = getLivingRoot(player)
	local waterY = getWaterSurfaceY()
	local waterGap = root and waterY and root.Position.Y - waterY or math.huge

	if not state.Completed.Survival and waterGap <= WATER_DANGER_GAP then
		return {
			Key = "WaterDanger",
			GoalId = "Survival",
			ActionText = "A ÁGUA ESTÁ PRÓXIMA!",
			Instruction = "Escolha rapidamente qualquer rota para uma área mais alta.",
			Hint = "Não existe caminho obrigatório: continue subindo pela rota mais segura para você.",
			ControlKind = "Climb",
			Danger = true,
			Progress = 0,
			Goal = 1,
		}
	end

	if not state.Completed.Reward and state.ChestNearby then
		return {
			Key = "ChestNearby",
			GoalId = "Reward",
			ActionText = "RECOMPENSA POR PERTO",
			Instruction = "Abra qualquer baú que encontrar — você escolhe a rota.",
			Hint = "Aproxime-se de um baú e use o botão de interação.",
			ControlKind = "Interact",
			Progress = 0,
			Goal = 1,
		}
	end

	if not state.Completed.Combat and state.EnemyNearby then
		return {
			Key = "EnemyNearby",
			GoalId = "Combat",
			ActionText = "COMBATE À FRENTE",
			Instruction = "Derrote qualquer inimigo real que você preferir enfrentar.",
			Hint = "Equipe sua espada e ataque. Qualquer inimigo válido conclui este objetivo.",
			ControlKind = "Combat",
			Progress = 0,
			Goal = 1,
		}
	end

	if not state.Completed.Mobility then
		local progress, goal = mobilityProgress(state)
		return {
			Key = "Mobility:" .. tostring(progress),
			GoalId = "Mobility",
			ActionText = "CONHEÇA OS CONTROLES",
			Instruction = "Mova-se e pule enquanto decide para onde quer avançar.",
			Hint = "Explore livremente. O tutorial acompanha suas escolhas, sem definir um destino.",
			ControlKind = "MoveJump",
			Progress = progress,
			Goal = goal,
		}
	end

	if not state.Completed.Exploration then
		return {
			Key = "Exploration",
			GoalId = "Exploration",
			ActionText = "ESCOLHA SEU CAMINHO",
			Instruction = "Continue subindo por qualquer rota e alcance uma nova ilha.",
			Hint = "Você pode mudar de direção a qualquer momento. Toda progressão natural conta.",
			ControlKind = "Explore",
			Progress = 0,
			Goal = 1,
		}
	end

	if not state.Completed.Combat then
		return {
			Key = "SearchCombat",
			GoalId = "Combat",
			ActionText = "CONTINUE EXPLORANDO",
			Instruction = "Quando encontrar inimigos, escolha qual deles deseja enfrentar.",
			Hint = "Nenhum inimigo específico é obrigatório.",
			ControlKind = "Combat",
			Progress = 0,
			Goal = 1,
		}
	end

	if not state.Completed.Reward then
		return {
			Key = "SearchReward",
			GoalId = "Reward",
			ActionText = "DESCUBRA RECOMPENSAS",
			Instruction = "Baús, moedas e companheiros encontrados durante sua jornada contam.",
			Hint = "Continue explorando normalmente; use as oportunidades que surgirem no mapa.",
			ControlKind = "Reward",
			Progress = 0,
			Goal = 1,
		}
	end

	return {
		Key = "WaterSafe",
		GoalId = "Survival",
		ActionText = "MANTENHA-SE NAS ALTURAS",
		Instruction = "Continue avançando e permaneça acima da água enquanto ela sobe.",
		Hint = "Escolha qualquer plataforma ou ilha que mantenha uma boa distância da água.",
		ControlKind = "Climb",
		Progress = 0,
		Goal = 1,
	}
end

sendGuidance = function(player, state, force)
	if not state.Active or state.Finishing or player.Parent ~= Players then
		return
	end
	local guidance = currentGuidance(player, state)
	local count = completedCount(state)
	local signature = table.concat({
		guidance.Key,
		tostring(count),
		tostring(guidance.Progress or 0),
		tostring(guidance.Danger == true),
	}, "|")
	local now = os.clock()
	if not force
		and signature == state.LastGuidanceSignature
		and now - state.LastGuidanceSentAt < GUIDANCE_REFRESH_SECONDS
	then
		return
	end
	state.LastGuidanceSignature = signature
	state.LastGuidanceSentAt = now

	player:SetAttribute("TutorialCurrentRecommendation", guidance.GoalId)
	tutorialEvent:FireClient(player, {
		Action = "Show",
		GoalId = guidance.GoalId,
		ActionText = guidance.ActionText,
		Instruction = guidance.Instruction,
		Hint = guidance.Hint,
		ControlKind = guidance.ControlKind,
		Danger = guidance.Danger == true,
		CompletedCount = count,
		TotalGoals = #GOALS,
		Progress = guidance.Progress,
		Goal = guidance.Goal,
		ShowHintAfterSeconds = (MVPConfig.Tutorial or {}).HelpDelaySeconds or 5,
	})
end

finishTutorial = function(player, state, skipped)
	if not state.Active then
		return
	end
	state.Active = false
	state.Finishing = false
	state.CharacterToken += 1
	state.CompletionSerial += 1

	player:SetAttribute("TutorialActive", false)
	player:SetAttribute("TutorialCompleted", true)
	player:SetAttribute("TutorialSkipped", skipped == true)
	player:SetAttribute("TutorialCompletionOutcome", skipped and "Skipped" or "Completed")
	player:SetAttribute("TutorialFinishedAt", serverTime())
	player:SetAttribute("TutorialStage", #GOALS)
	player:SetAttribute("TutorialCompletedGoalCount", completedCount(state))
	player:SetAttribute("TutorialEnemyProtectionExpiresAt", nil)
	setTutorialEnemyProtection(player, false)

	local persistCompletion = not state.ForcedForTesting
		or (MVPConfig.Tutorial or {}).PersistForcedCompletion == true
	if persistCompletion then
		PlayerDataService.SetTutorialProgress(player, #GOALS, true)
	end

	local rewardEligible = not skipped and persistCompletion
	player:SetAttribute("TutorialCompletionRewardPending", rewardEligible)
	tutorialEvent:FireClient(player, {
		Action = skipped and "Skipped" or "Complete",
		ActionText = skipped and "TUTORIAL ENCERRADO" or "TUTORIAL CONCLUÍDO!",
		Instruction = skipped
			and "Você continuará aprendendo enquanto joga."
			or "Você aprendeu o ciclo principal jogando do seu próprio jeito.",
		RewardPending = rewardEligible,
		CompletedCount = completedCount(state),
		TotalGoals = #GOALS,
	})

	if rewardEligible then
		local completionToken = state.CompletionSerial
		task.delay(COMPLETION_WHEEL_DELAY_SECONDS, function()
			if player.Parent ~= Players or states[player] ~= state or state.CompletionSerial ~= completionToken then
				return
			end
			local level = math.max(1, math.floor(tonumber(player:GetAttribute("RunLevel")) or 1))
			local success, resultOrMessage = RewardWheelService.Spin(player, COMPLETION_WHEEL_SOURCE, {
				Level = level,
				DeferSave = true,
			})
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
					Instruction = tostring(resultOrMessage or "Não foi possível abrir a recompensa."),
				})
			end
			task.spawn(PlayerDataService.Save, player, false)
		end)
	elseif persistCompletion then
		task.spawn(PlayerDataService.Save, player, false)
	end
end

local function bindCharacter(player, state, character)
	state.CharacterToken += 1
	local token = state.CharacterToken
	state.LastRootPosition = nil

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not state.Active or token ~= state.CharacterToken then
		return
	end

	character:SetAttribute("TutorialEnemyProtected", player:GetAttribute("TutorialEnemyProtection") == true)
	character:SetAttribute("TutorialProtectionVersion", SYSTEM_VERSION)
	state.LastRootPosition = root.Position
	state.InitialY = state.InitialY or root.Position.Y
	state.MaxY = math.max(state.MaxY or root.Position.Y, root.Position.Y)

	humanoid.StateChanged:Connect(function(_, nextState)
		if states[player] ~= state or not state.Active or token ~= state.CharacterToken then
			return
		end
		if nextState == Enum.HumanoidStateType.Jumping then
			state.Jumped = true
			if state.MovedEnough then
				completeGoal(player, state, "Mobility", "NaturalMovementAndJump")
			else
				sendGuidance(player, state, true)
			end
		end
	end)

	humanoid.Died:Connect(function()
		if states[player] == state and state.Active and token == state.CharacterToken then
			state.LastRootPosition = nil
		end
	end)

	task.delay(0.4, function()
		if player.Parent == Players and states[player] == state and state.Active then
			sendGuidance(player, state, true)
		end
	end)
end

local function setupPlayer(player)
	if setupStarted[player] then
		return
	end
	setupStarted[player] = true

	local data = PlayerDataService.Load(player)
	local _, completed = PlayerDataService.GetTutorialProgress(player)
	local forcedForTesting = forceTutorialForTesting()

	if completed and not forcedForTesting then
		player:SetAttribute("TutorialActive", false)
		player:SetAttribute("TutorialCompleted", true)
		player:SetAttribute("TutorialSkipped", false)
		player:SetAttribute("TutorialCompletionOutcome", "PreviouslyCompleted")
		player:SetAttribute("TutorialStage", #GOALS)
		player:SetAttribute("TutorialCompletedGoalCount", #GOALS)
		setTutorialEnemyProtection(player, false)
		return
	end

	local initialCoins = PlayerDataService.GetCoins(player)
	local state = {
		Active = true,
		Finishing = false,
		ForcedForTesting = forcedForTesting,
		Completed = {},
		CharacterToken = 0,
		CompletionSerial = 0,
		AccumulatedDistance = 0,
		MovedEnough = false,
		Jumped = false,
		InitialY = nil,
		MaxY = nil,
		InitialIslandKey = nil,
		InitialLogicalLevel = nil,
		InitialCoins = initialCoins,
		InitialRewardWheelSerial = math.max(0, tonumber(player:GetAttribute("LastRewardWheelSerial")) or 0),
		InitialCompanionInstanceId = player:GetAttribute("LastCapturedCompanionInstanceId"),
		InitialWaterY = getWaterSurfaceY(),
		WaterObserved = false,
		WaterObservedY = nil,
		WaterObservedDistance = 0,
		WaterObservedLogicalLevel = nil,
		WaterSafeFor = 0,
		EnemyNearby = false,
		ChestNearby = false,
		LastContextScanAt = 0,
		LastGuidanceSignature = nil,
		LastGuidanceSentAt = 0,
	}
	states[player] = state

	for _, definition in ipairs(GOALS) do
		player:SetAttribute("TutorialGoal_" .. definition.Id, false)
	end
	player:SetAttribute("TutorialActive", true)
	player:SetAttribute("TutorialCompleted", false)
	player:SetAttribute("TutorialSkipped", false)
	player:SetAttribute("TutorialCompletionOutcome", "InProgress")
	player:SetAttribute("TutorialStartedAt", serverTime())
	player:SetAttribute("TutorialFinishedAt", nil)
	player:SetAttribute("TutorialStage", 0)
	player:SetAttribute("TutorialCompletedGoalCount", 0)
	player:SetAttribute("TutorialDynamicGoalMask", 0)
	player:SetAttribute("TutorialCurrentRecommendation", "Mobility")
	player:SetAttribute("TutorialEnemyProtectionExpiresAt", serverTime() + ENEMY_PROTECTION_MAX_SECONDS)
	player:SetAttribute("TutorialDataVersion", SYSTEM_VERSION)
	setTutorialEnemyProtection(player, true)

	-- Progresso parcial da versão antiga era sequencial e não representa as
	-- conquistas independentes deste tutorial. Apenas a conclusão total persiste.
	if data.TutorialCompleted ~= true and tonumber(data.TutorialStage) ~= 1 then
		PlayerDataService.SetTutorialProgress(player, 1, false)
		task.spawn(PlayerDataService.Save, player, false)
	end

	local protectionState = state
	task.delay(ENEMY_PROTECTION_MAX_SECONDS, function()
		if states[player] == protectionState and protectionState.Active and player.Parent == Players then
			setTutorialEnemyProtection(player, false)
			player:SetAttribute("TutorialEnemyProtectionExpired", true)
			player:SetAttribute("TutorialEnemyProtectionExpiresAt", nil)
			tutorialEvent:FireClient(player, {
				Action = "ProtectionEnded",
				Instruction = "A proteção inicial terminou. Continue explorando com cuidado.",
			})
		end
	end)

	player:GetAttributeChangedSignal("LastCapturedCompanionInstanceId"):Connect(function()
		if states[player] ~= state or not state.Active then
			return
		end
		local current = player:GetAttribute("LastCapturedCompanionInstanceId")
		if current ~= nil and current ~= state.InitialCompanionInstanceId then
			completeGoal(player, state, "Reward", "CompanionObtained")
		end
	end)

	player:GetAttributeChangedSignal("LastRewardWheelSerial"):Connect(function()
		if states[player] ~= state or not state.Active then
			return
		end
		local serial = math.max(0, tonumber(player:GetAttribute("LastRewardWheelSerial")) or 0)
		if serial > state.InitialRewardWheelSerial then
			completeGoal(player, state, "Reward", "RewardWheel")
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
			sendGuidance(player, state, true)
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
		state.CharacterToken += 1
		states[player] = nil
	end
	setupStarted[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

task.spawn(function()
	while true do
		local deltaTime = task.wait(CHECK_INTERVAL)
		for player, state in pairs(states) do
			if not state.Active or state.Finishing then
				continue
			end

			local root = getLivingRoot(player)
			if not root then
				continue
			end

			local position = root.Position
			state.InitialY = state.InitialY or position.Y
			state.MaxY = math.max(state.MaxY or position.Y, position.Y)

			if state.LastRootPosition then
				local offset = position - state.LastRootPosition
				local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
				if horizontal <= 35 then
					state.AccumulatedDistance += horizontal
				end
			end
			state.LastRootPosition = position

			if not state.MovedEnough and state.AccumulatedDistance >= MOVEMENT_DISTANCE_GOAL then
				state.MovedEnough = true
				sendGuidance(player, state, true)
			end
			if state.MovedEnough and state.Jumped then
				completeGoal(player, state, "Mobility", "NaturalMovementAndJump")
			end

			local islandKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
			if islandKey ~= "" and not state.InitialIslandKey then
				state.InitialIslandKey = islandKey
			elseif not state.Completed.Exploration
				and islandKey ~= ""
				and state.InitialIslandKey
				and islandKey ~= state.InitialIslandKey
			then
				completeGoal(player, state, "Exploration", "VisitedAnotherIsland")
			end

			local logicalLevel = tonumber(player:GetAttribute("CurrentLogicalLevel"))
			if logicalLevel and not state.InitialLogicalLevel then
				state.InitialLogicalLevel = logicalLevel
			elseif not state.Completed.Exploration
				and logicalLevel
				and state.InitialLogicalLevel
				and logicalLevel > state.InitialLogicalLevel
			then
				completeGoal(player, state, "Exploration", "LogicalLevelAdvanced")
			end

			if not state.Completed.Exploration
				and state.InitialY
				and state.MaxY - state.InitialY >= EXPLORATION_HEIGHT_GOAL
				and state.AccumulatedDistance >= 6
			then
				completeGoal(player, state, "Exploration", "NaturalHeightProgress")
			end

			if not state.Completed.Reward then
				local coins = PlayerDataService.GetCoins(player)
				if coins >= state.InitialCoins + 10 then
					completeGoal(player, state, "Reward", "CoinsEarned")
				end
			end

			local waterY = getWaterSurfaceY()
			if waterY then
				state.InitialWaterY = state.InitialWaterY or waterY
				local waterGap = position.Y - waterY
				if not state.WaterObserved
					and (
						waterY >= state.InitialWaterY + WATER_RISE_TO_OBSERVE
						or waterGap <= WATER_DANGER_GAP
					)
				then
					state.WaterObserved = true
					state.WaterObservedY = position.Y
					state.WaterObservedDistance = state.AccumulatedDistance
					state.WaterObservedLogicalLevel = logicalLevel
					sendGuidance(player, state, true)
				end

				if state.WaterObserved and not state.Completed.Survival then
					local rose = position.Y >= (state.WaterObservedY or position.Y) + 6
					local traveled = state.AccumulatedDistance
						>= (state.WaterObservedDistance or state.AccumulatedDistance) + WATER_RESPONSE_DISTANCE
					local advanced = logicalLevel
						and state.WaterObservedLogicalLevel
						and logicalLevel > state.WaterObservedLogicalLevel
					if waterGap >= WATER_SAFE_GAP and (rose or traveled or advanced) then
						state.WaterSafeFor += deltaTime
					else
						state.WaterSafeFor = 0
					end
					if state.WaterSafeFor >= WATER_SAFE_SECONDS then
						completeGoal(player, state, "Survival", "StayedAheadOfRisingWater")
					end
				end
			end

			local now = os.clock()
			if now - state.LastContextScanAt >= CONTEXT_SCAN_INTERVAL then
				state.LastContextScanAt = now
				scanNearbyContext(player, state, root)
			end
			sendGuidance(player, state, false)
		end
	end
end)
