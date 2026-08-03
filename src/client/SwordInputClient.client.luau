-- StarterPlayer/StarterPlayerScripts/SwordInputClient
-- Captura clique/toque, toca a animacao imediatamente e envia o pedido para
-- o RemoteEvent individual da Tool. Dano e alvos continuam 100% no servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))

local boundTools = setmetatable({}, { __mode = "k" })
local animationCache = setmetatable({}, { __mode = "k" })
local state = {
	Combo = 0,
	LastAttackAt = -math.huge,
	NextAttackAt = 0,
}

local function normalizeAnimationId(value)
	if typeof(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if typeof(value) ~= "string" or value == "" then
		return ""
	end
	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end
	return value
end

local function getAnimationId(tool, slot)
	local folder = tool:FindFirstChild("Animations")
	local animation = folder and folder:FindFirstChild(slot)
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return normalizeAnimationId(animation.AnimationId)
	end
	local attributeId = normalizeAnimationId(tool:GetAttribute(slot .. "AnimationId"))
	if attributeId ~= "" then
		return attributeId
	end
	return normalizeAnimationId(Config.DefaultAnimationIds[slot])
end

local function getTrack(tool, slot)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local cache = animationCache[tool]
	if not cache or cache.Animator ~= animator then
		cache = { Animator = animator, Tracks = {} }
		animationCache[tool] = cache
	end
	if cache.Tracks[slot] then
		return cache.Tracks[slot]
	end

	local animationId = getAnimationId(tool, slot)
	if animationId == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not success then
		warn("[SwordInputV6] Animacao " .. slot .. " falhou: " .. tostring(track))
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	cache.Tracks[slot] = track
	return track
end

local function playAttackAnimation(tool, comboIndex, speed)
	local track = getTrack(tool, "Attack" .. comboIndex)
	if track then
		track:Play(0.045, 1, Config.Combo[comboIndex].AnimationSpeed * speed)
	end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		local marker = Instance.new("StringValue")
		marker.Name = "toolanim"
		marker.Value = comboIndex == 2 and "Lunge" or "Slash"
		marker.Parent = tool
		Debris:AddItem(marker, 0.25)
	end
end

local function activate(tool)
	local character = player.Character
	if not character
		or tool.Parent ~= character
		or not Config.IsSword(tool)
		or player:GetAttribute("IsDowned") == true
		or character:GetAttribute("MovementLocked") == true
	then
		return
	end

	local now = os.clock()
	if now < state.NextAttackAt then
		return
	end
	if now - state.LastAttackAt > Config.ComboResetTime then
		state.Combo = 1
	else
		state.Combo = state.Combo % Config.ComboCount + 1
	end
	state.LastAttackAt = now

	local speed = Config.GetAttackSpeed(tool)
	local combo = Config.Combo[state.Combo]
	state.NextAttackAt = now + (combo.Windup + combo.Recovery) / speed
	playAttackAnimation(tool, state.Combo, speed)

	local request = tool:FindFirstChild(Config.ToolRemoteName) or tool:WaitForChild(Config.ToolRemoteName, 2)
	if not request or not request:IsA("RemoteEvent") then
		warn("[CLIENTE] SwordAttackRequest nao encontrado dentro de " .. tool:GetFullName())
		return
	end
	request:FireServer()
	if Config.DebugCombat then
		print(string.format("[SwordInputV6] CLICK enviado combo=%d", state.Combo))
	end
end

local function bindTool(tool)
	if not Config.IsSword(tool) or boundTools[tool] then
		return
	end
	boundTools[tool] = true
	tool.Activated:Connect(function()
		activate(tool)
	end)
	if Config.DebugCombat then
		print("[SwordInputV6] Tool vinculada no cliente: " .. tool:GetFullName())
	end
end

local function bindCharacter(character)
	state.Combo = 0
	state.LastAttackAt = -math.huge
	state.NextAttackAt = 0
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
end

local shakeSerial = 0
local function shakeCamera(strength)
	shakeSerial += 1
	local serial = shakeSerial
	local started = os.clock()
	local bindName = "SwordHitShake_" .. player.UserId
	RunService:UnbindFromRenderStep(bindName)
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local alpha = (os.clock() - started) / 0.11
		if serial ~= shakeSerial or alpha >= 1 then
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local camera = workspace.CurrentCamera
		if camera then
			local fade = 1 - alpha
			camera.CFrame *= CFrame.new(
				(math.random() - 0.5) * strength * fade,
				(math.random() - 0.5) * strength * fade,
				0
			)
		end
	end)
end

player:GetAttributeChangedSignal("SwordHitSerial"):Connect(function()
	local heavy = player:GetAttribute("SwordHitHeavy") == true
	shakeCamera(heavy and Config.Visuals.HeavyCameraShake or Config.Visuals.CameraShake)
end)

player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") ~= true then
		return
	end
	state.Combo = 0
	state.LastAttackAt = -math.huge
	state.NextAttackAt = math.huge
	for _, cache in pairs(animationCache) do
		for slot, track in pairs(cache.Tracks or {}) do
			if string.find(slot, "Attack") and track.IsPlaying then
				track:Stop(0.05)
			end
		end
	end
end)

player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") ~= true then
		state.NextAttackAt = 0
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

if Config.DebugCombat then
	print("[SwordInputV6] Cliente iniciado.")
end
