-- Regras principais do jogador.
-- A regeneracao passiva padrao do Roblox permanece habilitada.
-- Agachar concede uma recuperacao adicional controlada pelo servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local RunLevelService = require(script.Parent.BlockParkour:WaitForChild("RunLevelService"))
local DownedService = require(script.Parent.MVPSystems:WaitForChild("DownedService"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))

ScoreService.Start()
DownedService.Start()

local CROUCH_HEAL_RATE = 0.04 -- +4% da vida maxima por segundo.
local CROUCH_WARMUP_SECONDS = 0.75
local CROUCH_DAMAGE_DELAY_SECONDS = 2.0
local CROUCH_MAX_HORIZONTAL_SPEED = 12
local CROUCH_HEAL_STEP = 0.20

local crouchRemote = ReplicatedStorage:FindFirstChild("CrouchStateRequest")
if crouchRemote and not crouchRemote:IsA("RemoteEvent") then
	crouchRemote:Destroy()
	crouchRemote = nil
end
if not crouchRemote then
	crouchRemote = Instance.new("RemoteEvent")
	crouchRemote.Name = "CrouchStateRequest"
	crouchRemote.Parent = ReplicatedStorage
end

local crouchStates = {}
local healAccumulator = 0

local function detectDeathCause(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and water:GetAttribute("SurfaceY")
	if root and typeof(surfaceY) == "number" and root.Position.Y <= surfaceY + 1 then
		local waterBottom = water.Position.Y - water.Size.Y / 2
		if root.Position.Y < waterBottom - 10 then
			return "Void"
		end
		return "RisingWater"
	end
	if root and root.AssemblyLinearVelocity.Y < -35 then
		return "Fall"
	end
	return "Unknown"
end

local function setCrouchHealingActive(player, state, active)
	if not state then
		return
	end
	active = active == true
	if state.HealingActive == active then
		return
	end
	state.HealingActive = active
	if state.Emitter and state.Emitter.Parent then
		state.Emitter.Enabled = active
	end
	if state.Character and state.Character.Parent then
		state.Character:SetAttribute("DungeonCrouchHealingActive", active)
	end
	if player and player.Parent == Players then
		player:SetAttribute("DungeonCrouchHealingActive", active)
	end
end

local function clearCrouchState(player)
	local state = crouchStates[player]
	if not state then
		return
	end
	setCrouchHealingActive(player, state, false)
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	crouchStates[player] = nil
end

local function createCrouchHealEffect(root)
	local old = root:FindFirstChild("DungeonCrouchHealAttachment")
	if old then
		old:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DungeonCrouchHealAttachment"
	attachment.Position = Vector3.new(0, -1.2, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DungeonCrouchHealParticles"
	emitter.Enabled = false
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(125, 255, 155)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 255, 220)),
	})
	emitter.LightEmission = 0.45
	emitter.Rate = 7
	emitter.Lifetime = NumberRange.new(0.55, 0.9)
	emitter.Speed = NumberRange.new(0.6, 1.35)
	emitter.SpreadAngle = Vector2.new(28, 28)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-45, 45)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.55, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.75, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Acceleration = Vector3.new(0, 1.8, 0)
	emitter.Parent = attachment

	return attachment, emitter
end

local function bindCrouchRecovery(player, character, humanoid)
	clearCrouchState(player)

	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local attachment, emitter = createCrouchHealEffect(root)
	local state = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Attachment = attachment,
		Emitter = emitter,
		Requested = false,
		CrouchSince = nil,
		LastDamageAt = -math.huge,
		LastHealth = humanoid.Health,
		HealingActive = false,
		Connections = {},
	}
	crouchStates[player] = state

	player:SetAttribute("DungeonCrouching", false)
	player:SetAttribute("DungeonCrouchHealingActive", false)
	player:SetAttribute("DungeonCrouchHealingRate", CROUCH_HEAL_RATE)
	player:SetAttribute("DungeonCrouchHealingReady", true)
	character:SetAttribute("DungeonCrouching", false)
	character:SetAttribute("DungeonCrouchHealingActive", false)

	table.insert(state.Connections, humanoid.HealthChanged:Connect(function(health)
		if health < state.LastHealth - 0.01 then
			state.LastDamageAt = os.clock()
			setCrouchHealingActive(player, state, false)
		end
		state.LastHealth = health
	end))

	table.insert(state.Connections, humanoid.Died:Connect(function()
		state.Requested = false
		state.CrouchSince = nil
		player:SetAttribute("DungeonCrouching", false)
		character:SetAttribute("DungeonCrouching", false)
		setCrouchHealingActive(player, state, false)
	end))
end

local function canCrouchHeal(player, state, now)
	local character = state.Character
	local humanoid = state.Humanoid
	local root = state.Root
	if not state.Requested
		or not character.Parent
		or player.Character ~= character
		or not humanoid.Parent
		or humanoid.Health <= 0
		or humanoid.Health >= humanoid.MaxHealth - 0.01
		or player:GetAttribute("IsDowned") == true
		or character:GetAttribute("Sprinting") == true
		or humanoid.FloorMaterial == Enum.Material.Air
		or not state.CrouchSince
		or now - state.CrouchSince < CROUCH_WARMUP_SECONDS
		or now - state.LastDamageAt < CROUCH_DAMAGE_DELAY_SECONDS
	then
		return false
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector2.new(velocity.X, velocity.Z).Magnitude
	return horizontalSpeed <= CROUCH_MAX_HORIZONTAL_SPEED
end

crouchRemote.OnServerEvent:Connect(function(player, requested)
	if typeof(requested) ~= "boolean" then
		return
	end
	local state = crouchStates[player]
	if not state or player.Character ~= state.Character then
		return
	end

	if state.Requested == requested then
		return
	end
	state.Requested = requested
	state.CrouchSince = requested and os.clock() or nil
	player:SetAttribute("DungeonCrouching", requested)
	state.Character:SetAttribute("DungeonCrouching", requested)
	if not requested then
		setCrouchHealingActive(player, state, false)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	healAccumulator += dt
	if healAccumulator < CROUCH_HEAL_STEP then
		return
	end
	local step = healAccumulator
	healAccumulator = 0
	local now = os.clock()

	for player, state in pairs(crouchStates) do
		if player.Parent ~= Players or not state.Character.Parent then
			clearCrouchState(player)
			continue
		end

		local active = canCrouchHeal(player, state, now)
		setCrouchHealingActive(player, state, active)
		if active then
			local humanoid = state.Humanoid
			local amount = math.max(1, humanoid.MaxHealth * CROUCH_HEAL_RATE) * step
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
			state.LastHealth = humanoid.Health
			player:SetAttribute("DungeonLastCrouchHealAt", workspace:GetServerTimeNow())
		end
	end
end)

local function bindCharacter(player, character)
	player:SetAttribute("ShopOpen", false)

	-- Regeneracao automatica continua fazendo parte da experiencia normal.
	-- O bonus de agachar e adicional e nao substitui o script Health do Roblox.
	character:SetAttribute("PassiveHealingDisabled", false)
	player:SetAttribute("DungeonPassiveHealingEnabled", true)

	ScoreService.ResetRun(player)
	RunLevelService.Reset(player, character)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	bindCrouchRecovery(player, character, humanoid)

	-- O estado inconsciente usa ragdoll antes da morte real. As juntas precisam
	-- sobreviver caso o tempo de resgate termine e a vida finalmente chegue a zero.
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	local processed = false
	humanoid.Died:Connect(function()
		if processed then
			return
		end
		processed = true
		local cause = detectDeathCause(character)
		GameplayAnalytics.RecordDeath(player, character, cause)
		ScoreService.HandleDeath(player, cause)
		RunLevelService.Reset(player, nil)
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		bindCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	clearCrouchState(player)
	RunLevelService.Remove(player)
end)
