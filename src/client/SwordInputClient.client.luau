-- SwordInputClient: executa somente o ataque da espada.
--
-- Responsabilidades:
-- - ouvir Tool.Activated;
-- - controlar combo/buffer/timing local;
-- - tocar animacao;
-- - enviar SwordAttackRequest sem alvo confiado pelo cliente;
-- - feedback leve de camera no hit.
--
-- Selecao de alvo, facing e auto-walk mobile pertencem exclusivamente a
-- MobileControls.client.luau.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(
	ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig")
)

local VERSION = "LinearSwordInputV1"
local boundTools = setmetatable({}, { __mode = "k" })
local animationCache = setmetatable({}, { __mode = "k" })

local state = {
	Combo = 0,
	LastAttackAt = -math.huge,
	NextAttackAt = 0,
	BufferSerial = 0,
	BufferedTool = nil,
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

local function animationId(tool, slot)
	local folder = tool:FindFirstChild("Animations")
	local animation = folder and folder:FindFirstChild(slot)
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return normalizeAnimationId(animation.AnimationId)
	end
	local attribute = normalizeAnimationId(tool:GetAttribute(slot .. "AnimationId"))
	if attribute ~= "" then
		return attribute
	end
	return normalizeAnimationId(Config.DefaultAnimationIds[slot])
end

local function trackFor(tool, slot)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
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

	local id = animationId(tool, slot)
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()
	if not ok or not track then
		warn("[SwordInput] Falha ao carregar " .. tostring(slot) .. ": " .. tostring(track))
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	cache.Tracks[slot] = track
	return track
end

local function playAttackAnimation(tool, comboIndex, speed)
	local track = trackFor(tool, "Attack" .. comboIndex)
	if track then
		track:Play(
			0.045,
			1,
			(Config.Combo[comboIndex].AnimationSpeed or 1) * speed
		)
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

local function canAttack(tool)
	local character = player.Character
	return character ~= nil
		and tool.Parent == character
		and Config.IsSword(tool)
		and player:GetAttribute("IsDowned") ~= true
		and character:GetAttribute("MovementLocked") ~= true
		and player:GetAttribute("DungeonAssistedTransportActive") ~= true
end

local function sendAttack(tool)
	if not canAttack(tool) then
		return false
	end
	local now = os.clock()
	if now < state.NextAttackAt then
		return false
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

	local request = tool:FindFirstChild(Config.ToolRemoteName)
		or tool:WaitForChild(Config.ToolRemoteName, 2)
	if not request or not request:IsA("RemoteEvent") then
		warn("[SwordInput] " .. Config.ToolRemoteName .. " nao encontrado em " .. tool:GetFullName())
		return false
	end

	request:FireServer()
	player:SetAttribute("SwordInputBuffered", false)
	player:SetAttribute("SwordInputLastCombo", state.Combo)
	player:SetAttribute("SwordInputLastAttackAt", workspace:GetServerTimeNow())
	return true
end

local function clearBuffer()
	state.BufferSerial += 1
	state.BufferedTool = nil
	player:SetAttribute("SwordInputBuffered", false)
	player:SetAttribute("SwordInputBufferRemaining", nil)
end

local function bufferAttack(tool, remaining)
	if Config.InputBufferTime <= 0
		or remaining <= 0
		or remaining > Config.InputBufferTime
	then
		return false
	end

	state.BufferSerial += 1
	local serial = state.BufferSerial
	state.BufferedTool = tool
	player:SetAttribute("SwordInputBuffered", true)
	player:SetAttribute("SwordInputBufferRemaining", remaining)

	task.delay(remaining, function()
		if serial ~= state.BufferSerial or state.BufferedTool ~= tool then
			return
		end
		state.BufferedTool = nil
		player:SetAttribute("SwordInputBuffered", false)
		sendAttack(tool)
	end)
	return true
end

local function activate(tool)
	if not canAttack(tool) then
		return
	end
	local now = os.clock()
	if now < state.NextAttackAt then
		bufferAttack(tool, state.NextAttackAt - now)
		return
	end
	clearBuffer()
	sendAttack(tool)
end

local function bindTool(tool)
	if not Config.IsSword(tool) or boundTools[tool] then
		return
	end
	boundTools[tool] = true
	tool.Activated:Connect(function()
		activate(tool)
	end)
end

local function bindCharacter(character)
	clearBuffer()
	state.Combo = 0
	state.LastAttackAt = -math.huge
	state.NextAttackAt = 0

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
end

local shakeSerial = 0
local function shakeCamera(strength)
	shakeSerial += 1
	local serial = shakeSerial
	local startedAt = os.clock()
	local bindName = "SwordHitShake_" .. player.UserId
	RunService:UnbindFromRenderStep(bindName)
	RunService:BindToRenderStep(
		bindName,
		Enum.RenderPriority.Camera.Value + 40,
		function()
			local alpha = (os.clock() - startedAt) / 0.11
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
		end
	)
end

player:GetAttributeChangedSignal("SwordHitSerial"):Connect(function()
	local heavy = player:GetAttribute("SwordHitHeavy") == true
	shakeCamera(
		heavy and Config.Visuals.HeavyCameraShake
			or Config.Visuals.CameraShake
	)
end)

player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") ~= true then
		state.NextAttackAt = 0
		return
	end
	clearBuffer()
	state.Combo = 0
	state.LastAttackAt = -math.huge
	state.NextAttackAt = math.huge
	for _, cache in pairs(animationCache) do
		for slot, track in pairs(cache.Tracks or {}) do
			if string.find(slot, "Attack", 1, true) and track.IsPlaying then
				track:Stop(0.05)
			end
		end
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

player:SetAttribute("SwordInputVersion", VERSION)
player:SetAttribute("MobileMeleeAssistEnabled", false)
player:SetAttribute("MobileMeleeAssistPolicy", "OwnedByMobileControls")
player:SetAttribute("MobileMeleeAutoAttack", false)
player:SetAttribute("MobileMeleeAutoMovement", false)
