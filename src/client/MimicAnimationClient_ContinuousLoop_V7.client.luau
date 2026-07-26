-- Coloque este LocalScript em StarterPlayer/StarterPlayerScripts.
-- Compatibilidade para o rig antigo de varias pecas. O rig atual usa o
-- MeshPart skinned Cube.002 e recebe a animacao de Bones pelo Animator.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FPS = 24
-- O ultimo keyframe e o frame 24; como o frame 1 ocorre no tempo zero,
-- o ciclo completo possui 23 intervalos. Usar exatamente esse tempo evita
-- uma pausa entre o ultimo frame e o reinicio do loop.
local LOOP_DURATION
local POSITION_SCALE = 0.167
local AXIS_CONVERSION = CFrame.Angles(math.rad(-90), 0, 0)
local states = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local player = Players.LocalPlayer
local updateAccumulator = 0

local NORMAL_UPDATE_FPS = 24
local REDUCED_UPDATE_FPS = 12
local EXTREME_UPDATE_FPS = 8
local NORMAL_MAX_DISTANCE = 240
local REDUCED_MAX_DISTANCE = 140
local EXTREME_MAX_DISTANCE = 80
local FORCE_ACTIVE_DISTANCE = 42

local function frameTime(frame)
	return (frame - 1) / FPS
end

LOOP_DURATION = frameTime(24)

local function key(frame, position, rotation, easing)
	return {
		time = frameTime(frame),
		position = position,
		rotation = rotation,
		easing = easing or "Linear",
	}
end

local lidKeys = {
	key(1, Vector3.new(-0.00000006, 5.607004, 5.674905), Vector3.new(-1.701455, 0, 0)),
	key(6, Vector3.new(-0.00000006, 5.607097, 5.674956), Vector3.new(-0.750946, 0, 0)),
	key(12, Vector3.new(-0.00000006, 5.607032, 5.674984), Vector3.new(-1.701455, 0, 0)),
	key(18, Vector3.new(-0.00000006, 5.607033, 5.674914), Vector3.new(-0.750946, 0, 0)),
	key(24, Vector3.new(-0.00000006, 5.607004, 5.674905), Vector3.new(-1.701455, 0, 0)),
}

local bodyKeys = {
	key(1, Vector3.new(-0.254433, -0.169848, -0.031713), Vector3.new(1.570796, 0, 0)),
	key(3, Vector3.new(-0.169622, -0.113232, 2.394112), Vector3.new(1.012827, 0, 0), "Bezier"),
	key(7, Vector3.new(0, 0, 7.245760), Vector3.new(1.570796, 0, 0), "Bounce"),
	key(24, Vector3.new(-0.254433, -0.169848, -0.031713), Vector3.new(1.570796, 0, 0)),
}

local leftFootKeys = {
	key(1, Vector3.new(-9.483703, -5.735260, 0.353310), Vector3.new(-0.315635, -0.139641, -0.437495), "Bezier"),
	key(12, Vector3.new(-8.377901, -3.726990, -1.497150), Vector3.new(0.216174, -0.038365, -0.461635), "Bezier"),
	key(24, Vector3.new(-9.483703, -5.735260, 0.353310), Vector3.new(-0.315635, -0.139641, -0.437495), "Bezier"),
}

local rightFootKeys = {
	key(1, Vector3.new(8.710766, -4.867133, -0.621880), Vector3.new(0.329491, 0.253619, -0.431920), "Bezier"),
	key(12, Vector3.new(8.956598, -6.300814, -0.308060), Vector3.new(-0.150771, -0.119214, -0.460897), "Bezier"),
	key(24, Vector3.new(8.710766, -4.867133, -0.621880), Vector3.new(0.329491, 0.253619, -0.431920), "Bezier"),
}

local function easingValue(style, alpha)
	alpha = math.clamp(alpha, 0, 1)
	if style == "Bezier" then
		return TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	elseif style == "Bounce" then
		return TweenService:GetValue(alpha, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	end
	return alpha
end

local function blenderCFrame(position, rotation)
	local robloxPosition = Vector3.new(
		position.X * POSITION_SCALE,
		-position.Y * POSITION_SCALE,
		position.Z * POSITION_SCALE
	)
	local blenderRotation = CFrame.fromEulerAnglesXYZ(rotation.X, rotation.Y, rotation.Z)
	local robloxRotation = AXIS_CONVERSION * blenderRotation * AXIS_CONVERSION:Inverse()
	return CFrame.new(robloxPosition) * robloxRotation
end

local function sampleAnimation(keys, timePosition)
	local firstTransform = blenderCFrame(keys[1].position, keys[1].rotation)
	local selectedA = keys[#keys]
	local selectedB = keys[#keys]
	for index = 1, #keys - 1 do
		local a = keys[index]
		local b = keys[index + 1]
		if timePosition >= a.time and timePosition <= b.time then
			selectedA = a
			selectedB = b
			break
		end
	end
	local duration = selectedB.time - selectedA.time
	local alpha = duration > 0 and (timePosition - selectedA.time) / duration or 0
	alpha = easingValue(selectedA.easing, alpha)
	local position = selectedA.position:Lerp(selectedB.position, alpha)
	local rotation = selectedA.rotation:Lerp(selectedB.rotation, alpha)
	return firstTransform:Inverse() * blenderCFrame(position, rotation)
end

local function findMotor(model, name)
	local motor = model:FindFirstChild(name, true)
	return motor and motor:IsA("Motor6D") and motor or nil
end

local function resetPose(state)
	if state.BodyMotor.Parent then state.BodyMotor.Transform = CFrame.identity end
	if state.LidMotor.Parent then state.LidMotor.Transform = CFrame.identity end
	if state.LeftFootMotor.Parent then state.LeftFootMotor.Transform = CFrame.identity end
	if state.RightFootMotor.Parent then state.RightFootMotor.Transform = CFrame.identity end
	for _, entry in ipairs(state.TongueBones) do
		if entry.Bone.Parent then
			entry.Bone.CFrame = entry.OriginalCFrame
		end
	end
end

local function tryRegister(model)
	if states[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	if model:GetAttribute("IsMimic") ~= true and model:GetAttribute("MonsterId") ~= "MimicChest" then
		return
	end
	local skinnedRoot = model:FindFirstChild("Cube.002", true)
	if skinnedRoot and skinnedRoot:IsA("BasePart") then
		-- MimicAI carrega a AnimationTrack no servidor, que replica para todos os
		-- clientes. Nao aplique os Motor6D procedurais do rig antigo por cima.
		return
	end
	if model:GetAttribute("MimicRigReady") ~= true then
		if not pending[model] then
			pending[model] = model:GetAttributeChangedSignal("MimicRigReady"):Connect(function()
				if model:GetAttribute("MimicRigReady") == true then
					local connection = pending[model]
					pending[model] = nil
					if connection then connection:Disconnect() end
					tryRegister(model)
				end
			end)
		end
		return
	end

	local bodyMotor = findMotor(model, "BodyMotor")
	local lidMotor = findMotor(model, "LidMotor")
	local leftFootMotor = findMotor(model, "LeftFootMotor")
	local rightFootMotor = findMotor(model, "RightFootMotor")
	local tongueModel = model:FindFirstChild("lingua chest mimic", true)
	local tongueMesh = tongueModel and tongueModel:FindFirstChild("BézierCurve")
	if not (bodyMotor and lidMotor and leftFootMotor and rightFootMotor and tongueMesh) then
		warn("[MimicAnimationClient] Rig incompleto: " .. model:GetFullName())
		return
	end

	local tongueBones = {}
	for _, name in ipairs({"FIRST_BONE", "SECOND_BONE", "THIRD_BONE", "FOUR_BONE", "FIVE_BONE"}) do
		local bone = tongueMesh:FindFirstChild(name, true)
		if bone and bone:IsA("Bone") then
			table.insert(tongueBones, { Bone = bone, OriginalCFrame = bone.CFrame })
		end
	end
	states[model] = {
		BodyMotor = bodyMotor,
		LidMotor = lidMotor,
		LeftFootMotor = leftFootMotor,
		RightFootMotor = rightFootMotor,
		TongueBones = tongueBones,
		RootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true),
		Elapsed = 0,
		WasAnimating = false,
	}
	print("[MimicAnimationClient] Mimico registrado: " .. model:GetFullName())
end

local function shouldRenderModel(model, state, camera, maxDistance)
	local root = state.RootPart
	if not root or not root:IsDescendantOf(model) then
		root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		state.RootPart = root
	end
	if not root or not camera then
		return false
	end

	local offset = root.Position - camera.CFrame.Position
	local distanceSquared = offset:Dot(offset)
	if distanceSquared <= FORCE_ACTIVE_DISTANCE * FORCE_ACTIVE_DISTANCE then
		return true
	end
	if distanceSquared > maxDistance * maxDistance then
		return false
	end
	local projected, onScreen = camera:WorldToViewportPoint(root.Position)
	return onScreen and projected.Z > 0
end

local function considerTagged(instance)
	if instance:IsA("Model") then
		task.defer(tryRegister, instance)
	end
end

CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(considerTagged)
for _, instance in ipairs(CollectionService:GetTagged("CombatTarget")) do
	considerTagged(instance)
end

RunService.RenderStepped:Connect(function(deltaTime)
	local performanceLevel = tonumber(player:GetAttribute("PerformanceLevel")) or 0
	local targetFPS = NORMAL_UPDATE_FPS
	local maxDistance = NORMAL_MAX_DISTANCE
	if performanceLevel >= 2 then
		targetFPS = EXTREME_UPDATE_FPS
		maxDistance = EXTREME_MAX_DISTANCE
	elseif performanceLevel >= 1 then
		targetFPS = REDUCED_UPDATE_FPS
		maxDistance = REDUCED_MAX_DISTANCE
	end

	updateAccumulator += deltaTime
	if updateAccumulator < 1 / targetFPS then
		return
	end
	local updateDelta = updateAccumulator
	updateAccumulator %= 1 / targetFPS
	local camera = workspace.CurrentCamera

	for model, state in pairs(states) do
		if not model:IsDescendantOf(workspace) then
			resetPose(state)
			states[model] = nil
			continue
		end
		local mimicState = model:GetAttribute("MimicState")
		-- SimulationActive controla apenas a IA/otimizacao do servidor. Ele nao
		-- deve interromper a animacao visual de um mimico que ainda esta visivel.
		-- O loop so para quando o modelo realmente entra no disfarce Dormant.
		local shouldAnimate = model:GetAttribute("Enabled") ~= false
			and mimicState ~= "Dormant"
			and shouldRenderModel(model, state, camera, maxDistance)
		if not shouldAnimate then
			if state.WasAnimating then
				resetPose(state)
			end
			state.WasAnimating = false
			continue
		end

		if not state.WasAnimating then
			-- Reinicia o ciclo ao despertar, igual em todos os clientes.
			state.Elapsed = 0
		end
		state.WasAnimating = true
		-- Mantem o contador pequeno e garante um loop continuo por tempo indefinido.
		state.Elapsed = (state.Elapsed + updateDelta) % LOOP_DURATION
		local loopTime = state.Elapsed % LOOP_DURATION
		state.BodyMotor.Transform = sampleAnimation(bodyKeys, loopTime)
		state.LidMotor.Transform = sampleAnimation(lidKeys, loopTime)
		state.LeftFootMotor.Transform = sampleAnimation(leftFootKeys, loopTime)
		state.RightFootMotor.Transform = sampleAnimation(rightFootKeys, loopTime)

		local boneCount = #state.TongueBones
		if boneCount > 0 then
			local phase = (loopTime / LOOP_DURATION) * math.pi * 2
			for index, entry in ipairs(state.TongueBones) do
				local phaseOffset = (index - 1) * 0.6
				local amplitude = 0.2 * index / boneCount
				local wiggleZ = math.sin(phase + phaseOffset) * amplitude
				local wiggleX = math.sin(phase + phaseOffset + math.pi / 2) * amplitude * 0.3
				entry.Bone.CFrame = entry.OriginalCFrame * CFrame.Angles(wiggleX, 0, wiggleZ)
			end
		end
	end
end)
