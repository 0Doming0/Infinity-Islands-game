-- Concede progresso permanente de estamina pela distancia horizontal percorrida.
-- Toda medicao e recompensa acontece no servidor; o cliente recebe apenas o visual.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SprintConfig = require(ReplicatedStorage:WaitForChild("SprintConfig"))
local PlayerDataService =
	require(script.Parent:WaitForChild("BlockParkour"):WaitForChild("PlayerDataService_SkyDungeon_V10"))

local CONFIG = SprintConfig.MovementStamina

local rewardRemote = ReplicatedStorage:FindFirstChild("StaminaReward")
if rewardRemote and not rewardRemote:IsA("RemoteEvent") then
	rewardRemote:Destroy()
	rewardRemote = nil
end
if not rewardRemote then
	rewardRemote = Instance.new("RemoteEvent")
	rewardRemote.Name = "StaminaReward"
	rewardRemote.Parent = ReplicatedStorage
end

local states = {}

local function horizontalDistance(fromPosition, toPosition)
	local delta = toPosition - fromPosition
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function syncTotal(player, total)
	player:SetAttribute("Stamina", total)
end

local function award(player, amount, mode, worldPosition)
	local success, total = PlayerDataService.AddStamina(player, amount)
	if not success then
		return
	end
	syncTotal(player, total)
	player:SetAttribute("LastStaminaAward", amount)
	player:SetAttribute("LastStaminaSource", mode)
	player:SetAttribute("LastStaminaSerial", (player:GetAttribute("LastStaminaSerial") or 0) + 1)
	rewardRemote:FireClient(player, {
		Amount = amount,
		Total = total,
		Mode = mode,
		WorldPosition = worldPosition,
	})
end

local function clearCharacterState(player)
	local state = states[player]
	if not state then
		return
	end
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	states[player] = nil
end

local function bindCharacter(player, character)
	clearCharacterState(player)

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not character.Parent then
		return
	end

	local state = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		LastPosition = root.Position,
		WalkDistance = 0,
		SprintDistance = 0,
		Connections = {},
	}
	states[player] = state

	table.insert(
		state.Connections,
		humanoid.Died:Connect(function()
			state.LastPosition = root.Position
			state.WalkDistance = 0
			state.SprintDistance = 0
		end)
	)
end

local function setupPlayer(player)
	local data = PlayerDataService.Load(player)
	syncTotal(player, data.Stamina)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		task.spawn(bindCharacter, player, player.Character)
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	for player, state in pairs(states) do
		local character = state.Character
		local humanoid = state.Humanoid
		local root = state.Root
		if not character.Parent or not humanoid.Parent or not root.Parent then
			clearCharacterState(player)
			continue
		end

		local currentPosition = root.Position
		local distance = horizontalDistance(state.LastPosition, currentPosition)
		state.LastPosition = currentPosition

		if
			deltaTime <= 0
			or deltaTime > CONFIG.MaximumSampleTime
			or humanoid.Health <= 0
			or humanoid.Sit
			or humanoid.MoveDirection.Magnitude <= 0.05
			or humanoid.FloorMaterial == Enum.Material.Air
		then
			continue
		end

		local allowedSpeed =
			math.min(CONFIG.MaximumCountedSpeed, math.max(16, humanoid.WalkSpeed * CONFIG.SpeedToleranceMultiplier))
		local maximumDistance = allowedSpeed * deltaTime + CONFIG.PositionTolerance
		if distance <= 0 or distance > maximumDistance then
			continue
		end

		local sprinting = character:GetAttribute("Sprinting") == true
		local accumulatorName = sprinting and "SprintDistance" or "WalkDistance"
		local rewardAmount = sprinting and CONFIG.SprintReward or CONFIG.WalkReward
		local rewardMode = sprinting and "Sprint" or "Walk"
		state[accumulatorName] += distance

		local rewardCount = math.min(5, math.floor(state[accumulatorName] / CONFIG.DistancePerReward))
		if rewardCount > 0 then
			state[accumulatorName] -= rewardCount * CONFIG.DistancePerReward
			award(player, rewardAmount * rewardCount, rewardMode, currentPosition)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	clearCharacterState(player)
end)

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end
