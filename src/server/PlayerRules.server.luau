-- Regras principais do jogador.
-- A regeneracao passiva padrao do Roblox permanece habilitada.
-- Agachar concede uma recuperacao adicional controlada pelo servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local RunLevelService = require(script.Parent.BlockParkour:WaitForChild("RunLevelService"))
local DownedService = require(script.Parent.MVPSystems:WaitForChild("DownedService"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))

ScoreService.Start()
DownedService.Start()

-- Recuperacao intencionalmente perceptivel: serve como opcao de recuo/defesa.
local CROUCH_HEAL_RATE = 0.16 -- +16% da vida maxima por segundo (2x a taxa anterior).
local CROUCH_WARMUP_SECONDS = 0.40
local CROUCH_DAMAGE_DELAY_SECONDS = 1.25
local CROUCH_MAX_HORIZONTAL_SPEED = 10
local CROUCH_HEAL_STEP = 0.10
local CROUCH_EFFECT_POLICY = "PhysicalNeonRingCoreV1"

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

local function configureEffectPart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(85, 255, 135)
end

local function weldToRoot(root, part)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "HealingEffectWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

local function createCrouchHealEffect(character, root)
	local old = character:FindFirstChild("DungeonCrouchHealEffect")
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "DungeonCrouchHealEffect"
	folder.Parent = character

	-- Disco fisico Neon sob os pes. Ele e uma Part real replicada pelo servidor,
	-- mas sem colisao/toque/query para nunca interferir no movimento.
	local ring = Instance.new("Part")
	ring.Name = "HealingRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, 4.6, 4.6)
	configureEffectPart(ring)
	ring.Transparency = 1
	ring.CFrame = root.CFrame
		* CFrame.new(0, -2.75, 0)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	weldToRoot(root, ring)

	-- Pequeno nucleo luminoso acompanhando o personagem deixa a recuperacao
	-- legivel mesmo quando o chao/ilha tem cores fortes.
	local core = Instance.new("Part")
	core.Name = "HealingCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(0.75, 0.75, 0.75)
	configureEffectPart(core)
	core.Transparency = 1
	core.CFrame = root.CFrame * CFrame.new(0, -1.8, 0)
	core.Parent = folder
	weldToRoot(root, core)

	local light = Instance.new("PointLight")
	light.Name = "HealingGlow"
	light.Color = Color3.fromRGB(105, 255, 145)
	light.Brightness = 1.25
	light.Range = 7
	light.Enabled = false
	light.Parent = core

	local attachment = Instance.new("Attachment")
	attachment.Name = "DungeonCrouchHealAttachment"
	attachment.Position = Vector3.new(0, -1.4, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DungeonCrouchHealParticles"
	emitter.Enabled = false
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 255, 125)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 255, 225)),
	})
	emitter.LightEmission = 0.75
	emitter.Rate = 24
	emitter.Lifetime = NumberRange.new(0.65, 1.05)
	emitter.Speed = NumberRange.new(1.2, 2.4)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-70, 70)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(0.55, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Acceleration = Vector3.new(0, 3.2, 0)
	emitter.Parent = attachment

	local highlight = Instance.new("Highlight")
	highlight.Name = "HealingHighlight"
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(85, 255, 135)
	highlight.FillTransparency = 0.88
	highlight.OutlineColor = Color3.fromRGB(180, 255, 195)
	highlight.OutlineTransparency = 0.38
	highlight.Enabled = false
	highlight.Parent = folder

	local ringTween = TweenService:Create(
		ring,
		TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Size = Vector3.new(0.12, 5.5, 5.5),
			Transparency = 0.72,
		}
	)
	local coreTween = TweenService:Create(
		core,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Size = Vector3.new(1.15, 1.15, 1.15),
			Transparency = 0.58,
		}
	)

	return {
		Folder = folder,
		Ring = ring,
		Core = core,
		Attachment = attachment,
		Emitter = emitter,
		Light = light,
		Highlight = highlight,
		RingTween = ringTween,
		CoreTween = coreTween,
	}
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

	local effect = state.Effect
	if effect then
		if effect.Emitter and effect.Emitter.Parent then
			effect.Emitter.Enabled = active
		end
		if effect.Light and effect.Light.Parent then
			effect.Light.Enabled = active
		end
		if effect.Highlight and effect.Highlight.Parent then
			effect.Highlight.Enabled = active
		end
		if active then
			if effect.Ring and effect.Ring.Parent then
				effect.Ring.Size = Vector3.new(0.12, 4.6, 4.6)
				effect.Ring.Transparency = 0.42
			end
			if effect.Core and effect.Core.Parent then
				effect.Core.Size = Vector3.new(0.75, 0.75, 0.75)
				effect.Core.Transparency = 0.20
			end
			if effect.RingTween then
				effect.RingTween:Play()
			end
			if effect.CoreTween then
				effect.CoreTween:Play()
			end
		else
			if effect.RingTween then
				effect.RingTween:Cancel()
			end
			if effect.CoreTween then
				effect.CoreTween:Cancel()
			end
			if effect.Ring and effect.Ring.Parent then
				effect.Ring.Transparency = 1
				effect.Ring.Size = Vector3.new(0.12, 4.6, 4.6)
			end
			if effect.Core and effect.Core.Parent then
				effect.Core.Transparency = 1
				effect.Core.Size = Vector3.new(0.75, 0.75, 0.75)
			end
		end
	end

	if state.Character and state.Character.Parent then
		state.Character:SetAttribute("DungeonCrouchHealingActive", active)
	end
	if player and player.Parent == Players then
		player:SetAttribute("DungeonCrouchHealingActive", active)
		player:SetAttribute("DungeonCrouchHealingPhysicalEffectActive", active)
		if active then
			player:SetAttribute("DungeonCrouchHealingActivationSerial", (player:GetAttribute("DungeonCrouchHealingActivationSerial") or 0) + 1)
		end
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
	if state.Effect then
		if state.Effect.RingTween then
			state.Effect.RingTween:Cancel()
		end
		if state.Effect.CoreTween then
			state.Effect.CoreTween:Cancel()
		end
		if state.Effect.Folder and state.Effect.Folder.Parent then
			state.Effect.Folder:Destroy()
		end
		if state.Effect.Attachment and state.Effect.Attachment.Parent then
			state.Effect.Attachment:Destroy()
		end
	end
	crouchStates[player] = nil
end

local function bindCrouchRecovery(player, character, humanoid)
	clearCrouchState(player)

	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local effect = createCrouchHealEffect(character, root)
	local state = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Effect = effect,
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
	player:SetAttribute("DungeonCrouchHealingWarmupSeconds", CROUCH_WARMUP_SECONDS)
	player:SetAttribute("DungeonCrouchHealingDamageDelaySeconds", CROUCH_DAMAGE_DELAY_SECONDS)
	player:SetAttribute("DungeonCrouchHealingReady", true)
	player:SetAttribute("DungeonCrouchHealingPhysicalEffect", CROUCH_EFFECT_POLICY)
	player:SetAttribute("DungeonCrouchHealingPhysicalEffectActive", false)
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

	player:SetAttribute("DungeonLastCrouchRequestAt", workspace:GetServerTimeNow())
	player:SetAttribute("DungeonLastCrouchRequestValue", requested)
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
			player:SetAttribute("DungeonLastCrouchHealAmount", amount)
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
