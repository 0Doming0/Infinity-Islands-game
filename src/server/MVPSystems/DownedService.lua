-- Estado intermediario antes da morte. Dano fatal de combate derruba o jogador
-- por alguns segundos e cria um ProximityPrompt que outro jogador pode segurar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PlayerStatusService = require(script.Parent:WaitForChild("PlayerStatusService"))

local DownedService = {}
local CONFIG = MVPConfig.Social.Downed
local DOWNED_SECONDS = tonumber(CONFIG.DurationSeconds) or 15
local REVIVE_HOLD_SECONDS = tonumber(CONFIG.ReviveHoldSeconds) or 3
local REVIVE_HEALTH_RATIO = tonumber(CONFIG.ReviveHealthRatio) or 0.35
local REVIVE_PROTECTION_SECONDS = tonumber(CONFIG.ProtectionSeconds) or 3
local RESCUE_WEAKNESS_SECONDS = tonumber(CONFIG.WeaknessSeconds) or 60
local REVIVE_DISTANCE = tonumber(CONFIG.ReviveDistanceStuds) or 10

local states = setmetatable({}, { __mode = "k" })
local started = false
local event

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function ensureRemote()
	local remote = ReplicatedStorage:FindFirstChild("DownedEvent")
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "DownedEvent"
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local function hasSafeFloor(character, root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local result = workspace:Raycast(root.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	return result ~= nil
		and result.Instance:IsA("BasePart")
		and result.Instance.CanCollide
		and result.Normal.Y >= 0.55
end

local function restoreMovement(player, state)
	local character = state.Character
	local humanoid = state.Humanoid
	if character and character.Parent then
		character:SetAttribute("MovementLocked", nil)
	end
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = state.WalkSpeed
		humanoid.JumpPower = state.JumpPower
		humanoid.JumpHeight = state.JumpHeight
		humanoid.AutoRotate = state.AutoRotate
	end
	if state.Root and state.Root.Parent then
		state.Root.Anchored = state.RootAnchored
	end
end

local function clearState(player, state)
	if states[player] ~= state then
		return
	end
	states[player] = nil
	if state.Prompt and state.Prompt.Parent then
		state.Prompt:Destroy()
	end
	player:SetAttribute("IsDowned", nil)
	player:SetAttribute("DownedExpiresAt", nil)
	player:SetAttribute("DownedBySource", nil)
end

local function finishDowned(player, state, cause)
	if states[player] ~= state then
		return
	end
	clearState(player, state)
	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		if state.Root and state.Root.Parent then
			state.Root.Anchored = state.RootAnchored
		end
		humanoid.PlatformStand = false
		humanoid.Health = 0
	end
	if event and player.Parent == Players then
		event:FireAllClients({
			Action = "Removed",
			UserId = player.UserId,
			Cause = cause or "Expired",
		})
	end
end

local function revive(rescuer, target, state)
	if
		states[target] ~= state
		or rescuer == target
		or rescuer.Parent ~= Players
		or rescuer:GetAttribute("IsDowned") == true
		or target:GetAttribute("WaterContacting") == true
	then
		return false
	end
	local rescuerCharacter = rescuer.Character
	local rescuerHumanoid = rescuerCharacter and rescuerCharacter:FindFirstChildOfClass("Humanoid")
	local rescuerRoot = rescuerCharacter and rescuerCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = state.Character and state.Character:FindFirstChild("HumanoidRootPart")
	if
		not rescuerHumanoid
		or rescuerHumanoid.Health <= 0
		or not rescuerRoot
		or not targetRoot
		or (rescuerRoot.Position - targetRoot.Position).Magnitude > REVIVE_DISTANCE
		or not hasSafeFloor(state.Character, targetRoot)
	then
		return false
	end

	clearState(target, state)
	restoreMovement(target, state)
	state.Humanoid.Health = math.max(1, state.Humanoid.MaxHealth * REVIVE_HEALTH_RATIO)
	target:SetAttribute("RescueWeakUntil", serverTime() + RESCUE_WEAKNESS_SECONDS)
	local forceField = Instance.new("ForceField")
	forceField.Name = "RescueProtection"
	forceField.Visible = false
	forceField.Parent = state.Character
	task.delay(REVIVE_PROTECTION_SECONDS, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
	event:FireAllClients({
		Action = "Revived",
		UserId = target.UserId,
		RescuerUserId = rescuer.UserId,
	})
	return true
end

function DownedService.TryInterceptFatal(player, humanoid, damage, source)
	if
		not player
		or player.Parent ~= Players
		or not humanoid
		or humanoid.Health <= 0
		or damage < humanoid.Health
		or states[player]
		or player:GetAttribute("InitialGameStarted") ~= true
		or serverTime() < (tonumber(player:GetAttribute("RescueWeakUntil")) or 0)
	then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
		or humanoid.Parent ~= character
		or not root
		or player:GetAttribute("WaterContacting") == true
		or not hasSafeFloor(character, root)
	then
		return false
	end

	PlayerStatusService.Clear(player)
	humanoid.Health = 1
	humanoid:UnequipTools()
	local state = {
		Character = character,
		Humanoid = humanoid,
		WalkSpeed = math.max(0, humanoid.WalkSpeed),
		JumpPower = math.max(0, humanoid.JumpPower),
		JumpHeight = math.max(0, humanoid.JumpHeight),
		AutoRotate = humanoid.AutoRotate,
		Root = root,
		RootAnchored = root.Anchored,
		ExpiresAt = serverTime() + DOWNED_SECONDS,
	}
	states[player] = state
	player:SetAttribute("IsDowned", true)
	player:SetAttribute("DownedExpiresAt", state.ExpiresAt)
	player:SetAttribute("DownedBySource", tostring(source or "Combat"))
	character:SetAttribute("MovementLocked", true)
	character:SetAttribute("Sprinting", nil)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	root.Anchored = true
	humanoid:Move(Vector3.zero)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ReviveAllyPrompt"
	prompt.ActionText = "REVIVER"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = REVIVE_HOLD_SECONDS
	prompt.MaxActivationDistance = REVIVE_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = root
	state.Prompt = prompt
	prompt.Triggered:Connect(function(rescuer)
		revive(rescuer, player, state)
	end)
	event:FireAllClients({
		Action = "Downed",
		UserId = player.UserId,
		ExpiresAt = state.ExpiresAt,
	})
	task.delay(DOWNED_SECONDS, function()
		finishDowned(player, state, "Expired")
	end)
	return true
end

function DownedService.ForceDeath(player, cause)
	local state = states[player]
	if state then
		finishDowned(player, state, cause)
		return true
	end
	return false
end

function DownedService.IsDowned(player)
	return states[player] ~= nil
end

function DownedService.Start()
	if started then
		return
	end
	started = true
	event = ensureRemote()
	local function setup(player)
		player:SetAttribute("IsDowned", nil)
		player.CharacterAdded:Connect(function()
			local state = states[player]
			if state then
				clearState(player, state)
			end
		end)
		player:GetAttributeChangedSignal("WaterContacting"):Connect(function()
			if player:GetAttribute("WaterContacting") == true then
				DownedService.ForceDeath(player, "Water")
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
end

return DownedService
