-- Estado intermediario antes da morte. Dano fatal de combate derruba o jogador
-- por alguns segundos e cria um ProximityPrompt que outro jogador pode segurar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PlayerStatusService = require(script.Parent:WaitForChild("PlayerStatusService"))

local DownedService = {}
local CONFIG = MVPConfig.Social.Downed
local DEFAULT_DOWNED_SECONDS = tonumber(CONFIG.DurationSeconds) or 15
local REVIVE_HOLD_SECONDS = tonumber(CONFIG.ReviveHoldSeconds) or 3
local REVIVE_HEALTH_RATIO = tonumber(CONFIG.ReviveHealthRatio) or 0.35
local REVIVE_PROTECTION_SECONDS = tonumber(CONFIG.ProtectionSeconds) or 3
local DEFAULT_RESCUE_WEAKNESS_SECONDS = tonumber(CONFIG.WeaknessSeconds) or 60
local REVIVE_DISTANCE = tonumber(CONFIG.ReviveDistanceStuds) or 10

local function downedDurationSeconds()
	if workspace:GetAttribute("DungeonRuntimeManaged") == true then
		return math.clamp(
			tonumber(workspace:GetAttribute("DungeonDownedDurationSeconds")) or 10,
			5,
			30
		)
	end
	return DEFAULT_DOWNED_SECONDS
end

local function rescueWeaknessSeconds()
	if workspace:GetAttribute("DungeonRuntimeManaged") == true then
		return math.clamp(
			tonumber(workspace:GetAttribute("DungeonReviveWeaknessSeconds")) or 12,
			0,
			60
		)
	end
	return DEFAULT_RESCUE_WEAKNESS_SECONDS
end

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

local function isRootMotor(motor, root)
	return motor.Part0 == root or motor.Part1 == root
end

local function trackRagdollInstance(state, instance)
	table.insert(state.RagdollInstances, instance)
	return instance
end

local function createRagdollJoint(state, folder, motor)
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return
	end

	local attachment0 = trackRagdollInstance(state, Instance.new("Attachment"))
	attachment0.Name = "DownedRagdoll_" .. motor.Name .. "_A0"
	attachment0.CFrame = motor.C0
	attachment0.Parent = part0

	local attachment1 = trackRagdollInstance(state, Instance.new("Attachment"))
	attachment1.Name = "DownedRagdoll_" .. motor.Name .. "_A1"
	attachment1.CFrame = motor.C1
	attachment1.Parent = part1

	local socket = trackRagdollInstance(state, Instance.new("BallSocketConstraint"))
	socket.Name = "DownedRagdoll_" .. motor.Name
	socket.Attachment0 = attachment0
	socket.Attachment1 = attachment1
	socket.LimitsEnabled = true
	socket.UpperAngle = 55
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -45
	socket.TwistUpperAngle = 45
	socket.Restitution = 0
	socket.Parent = folder

	local noCollision = trackRagdollInstance(state, Instance.new("NoCollisionConstraint"))
	noCollision.Name = "DownedRagdoll_NoCollision_" .. motor.Name
	noCollision.Part0 = part0
	noCollision.Part1 = part1
	noCollision.Parent = folder

	motor.Enabled = false
end

local function activateRagdoll(state)
	local character = state.Character
	local humanoid = state.Humanoid
	local root = state.Root
	if
		not character
		or not character.Parent
		or not humanoid
		or not humanoid.Parent
		or character:GetAttribute("IsDownedRagdoll") == true
	then
		return false
	end

	character:SetAttribute("IsDownedRagdoll", true)
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	local folder = Instance.new("Folder")
	folder.Name = "DownedRagdoll"
	folder.Parent = character
	state.RagdollFolder = folder
	state.RagdollInstances = {}
	state.MotorStates = {}
	state.PartStates = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(state.PartStates, {
				Part = descendant,
				Anchored = descendant.Anchored,
				CanCollide = descendant.CanCollide,
			})
			descendant.Anchored = false
			descendant.CanCollide = descendant ~= root
				and descendant:FindFirstAncestorOfClass("Accessory") == nil
			-- Durante o ragdoll o servidor precisa ser o dono da simulacao. Se a
			-- vitima continuar com network ownership, ela pode levantar localmente
			-- enquanto os demais clientes ainda recebem a pose caida.
			pcall(descendant.SetNetworkOwner, descendant, nil)
		elseif
			descendant:IsA("Motor6D")
			and descendant.Part0
			and descendant.Part1
			and descendant.Part0:IsDescendantOf(character)
			and descendant.Part1:IsDescendantOf(character)
			and not isRootMotor(descendant, root)
		then
			table.insert(state.MotorStates, {
				Motor = descendant,
				Enabled = descendant.Enabled,
			})
			createRagdollJoint(state, folder, descendant)
		end
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	return true
end

local function stabilizeRevivedCharacter(player, state)
	local character = state.Character
	local humanoid = state.Humanoid
	local root = state.Root
	if not character or not character.Parent or not humanoid or not root or not root.Parent then
		return
	end

	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		elseif descendant:IsA("Motor6D") then
			descendant.Transform = CFrame.identity
		end
	end

	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.1 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local floor = workspace:Raycast(root.Position + Vector3.new(0, 5, 0), Vector3.new(0, -14, 0), params)
	local minimumY = floor and floor.Position.Y + humanoid.HipHeight + root.Size.Y / 2 or root.Position.Y
	local uprightPosition = Vector3.new(root.Position.X, math.max(root.Position.Y, minimumY), root.Position.Z)
	root.CFrame = CFrame.lookAt(uprightPosition, uprightPosition + flatLook)

	humanoid.PlatformStand = false
	humanoid.AutoRotate = state.AutoRotate
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	RunService.Heartbeat:Wait()
	if root.Parent and humanoid.Health > 0 then
		root.Anchored = state.RootAnchored
		pcall(root.SetNetworkOwner, root, player)
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
end

local function deactivateRagdoll(state)
	local character = state.Character
	if character then
		character:SetAttribute("IsDownedRagdoll", nil)
	end

	for _, motorState in ipairs(state.MotorStates or {}) do
		local motor = motorState.Motor
		if motor and motor.Parent then
			motor.Enabled = motorState.Enabled
		end
	end
	if state.RagdollFolder and state.RagdollFolder.Parent then
		state.RagdollFolder:Destroy()
	end
	for _, instance in ipairs(state.RagdollInstances or {}) do
		if instance.Parent then
			instance:Destroy()
		end
	end
	for _, partState in ipairs(state.PartStates or {}) do
		local part = partState.Part
		if part and part.Parent then
			part.Anchored = partState.Anchored
			part.CanCollide = partState.CanCollide
		end
	end

	state.RagdollFolder = nil
	state.RagdollInstances = nil
	state.MotorStates = nil
	state.PartStates = nil
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
	player:SetAttribute("DungeonDownedResolution", "Eliminated")
	clearState(player, state)
	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		if state.Root and state.Root.Parent then
			state.Root.Anchored = state.RootAnchored
		end
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

	target:SetAttribute("DungeonDownedResolution", "Revived")
	clearState(target, state)
	deactivateRagdoll(state)
	restoreMovement(target, state)
	state.Humanoid.Health = math.max(1, state.Humanoid.MaxHealth * REVIVE_HEALTH_RATIO)
	stabilizeRevivedCharacter(target, state)
	target:SetAttribute("RescueWeakUntil", serverTime() + rescueWeaknessSeconds())
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

	local durationSeconds = downedDurationSeconds()
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
		ExpiresAt = serverTime() + durationSeconds,
	}
	states[player] = state
	state.RagdollSerial = (tonumber(character:GetAttribute("DownedRagdollSerial")) or 0) + 1
	character:SetAttribute("DownedRagdollSerial", state.RagdollSerial)
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
	root.Anchored = false
	humanoid:Move(Vector3.zero)
	activateRagdoll(state)

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
	task.delay(durationSeconds, function()
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

function DownedService.ForceRevive(target, reason)
	local state = states[target]
	if not state
		or not target
		or target.Parent ~= Players
		or not state.Character
		or not state.Character.Parent
		or not state.Humanoid
		or not state.Humanoid.Parent
		or state.Humanoid.Health <= 0
	then
		return false
	end
	target:SetAttribute(
		"DungeonDownedResolution",
		tostring(reason or "DungeonRevive")
	)
	clearState(target, state)
	deactivateRagdoll(state)
	restoreMovement(target, state)
	state.Humanoid.Health = math.max(1, state.Humanoid.MaxHealth * REVIVE_HEALTH_RATIO)
	stabilizeRevivedCharacter(target, state)
	local weaknessSeconds = tostring(reason or "") == "SkyBlessing"
		and 0
		or rescueWeaknessSeconds()
	target:SetAttribute("RescueWeakUntil", serverTime() + weaknessSeconds)
	local forceField = Instance.new("ForceField")
	forceField.Name = tostring(reason or "DungeonRevive") .. "Protection"
	forceField.Visible = false
	forceField.Parent = state.Character
	task.delay(REVIVE_PROTECTION_SECONDS, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
	if event then
		event:FireAllClients({
			Action = "Revived",
			UserId = target.UserId,
			RescuerUserId = nil,
			Reason = tostring(reason or "DungeonRevive"),
		})
	end
	return true
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
