--[[
	Reproducao procedural da animacao exportada do Blender.

	Dados de origem:
	- 24 FPS
	- frames 1 ate 72
	- Bone.location.Y: 0 -> 2.6445155 -> 0
	- subida: Back
	- descida: Bounce
	- rotacao: identidade
	- escala: 1, 1, 1

	Este e um LocalScript porque Bone.Transform nao replica pela rede. Coloque-o
	em StarterPlayer > StarterPlayerScripts. Com Rojo, mantenha este arquivo em
	src/client.

	O jogo reconhece automaticamente os Models com IsScoreCollectible = true.
	Para testar um modelo colocado manualmente no Workspace, adicione nele o
	atributo booleano UseBlenderProceduralAnimation = true.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local BONE_NAME = "Bone"

local FPS = 24
local FRAME_START = 1
local PEAK_FRAME = 36
local FRAME_END = 72
local PEAK_DISTANCE = 2.6445155143737793 * 0.512

-- A location de PoseBone e local ao osso. Por isso, o Y local do Blender e
-- aplicado ao Y local do Bone importado, cuja orientacao de repouso ja foi
-- convertida pelo importador do Roblox.
local ROBLOX_LOCAL_AXIS = Vector3.new(0, 1, 0)

-- Se o modelo foi redimensionado depois de importado, defina o atributo
-- BlenderAnimationScale no Model do coletavel ou no Model Visual.
local DEFAULT_POSITION_SCALE = 1

local FRAME_SPAN = FRAME_END - FRAME_START
local LOOP_DURATION = FRAME_SPAN / FPS
local NORMAL_UPDATE_FPS = 24
local PERFORMANCE_UPDATE_FPS = 15
local EXTREME_UPDATE_FPS = 10
local NORMAL_MAX_DISTANCE = 240
local PERFORMANCE_MAX_DISTANCE = 150
local EXTREME_MAX_DISTANCE = 90
local FORCE_ACTIVE_DISTANCE = 55
local NORMAL_VISIBILITY_INTERVAL = 0.25
local PERFORMANCE_VISIBILITY_INTERVAL = 0.4
local EXTREME_VISIBILITY_INTERVAL = 0.6

local activeBones = {}
local pendingBones = setmetatable({}, { __mode = "k" })
local player = Players.LocalPlayer
local updateAccumulator = 0

local function findRuntimeModel(bone)
	local current = bone.Parent
	while current and current ~= workspace do
		if
			current:IsA("Model")
			and (
				current:GetAttribute("IsScoreCollectible") == true
				or current:GetAttribute("UseBlenderProceduralAnimation") == true
			)
		then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getPositionScale(runtime)
	local value = runtime:GetAttribute("BlenderAnimationScale")
	if typeof(value) == "number" then
		return value
	end

	local visual = runtime:FindFirstChild("Visual")
	value = visual and visual:GetAttribute("BlenderAnimationScale")
	if typeof(value) == "number" then
		return value
	end

	return DEFAULT_POSITION_SCALE
end

local function stopRobloxAnimationTracks(runtime)
	for _, descendant in ipairs(runtime:GetDescendants()) do
		if descendant:IsA("Animator") then
			for _, track in ipairs(descendant:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end
end

local function rootOf(runtime)
	return runtime.PrimaryPart or runtime:FindFirstChildWhichIsA("BasePart", true)
end

local function registerBone(bone)
	if activeBones[bone] or pendingBones[bone] or bone.Name ~= BONE_NAME then
		return
	end

	pendingBones[bone] = true
	task.spawn(function()
		-- O modelo e seus atributos podem chegar ao cliente em pacotes separados.
		local runtime
		for _ = 1, 20 do
			if not bone:IsDescendantOf(workspace) then
				pendingBones[bone] = nil
				return
			end

			runtime = findRuntimeModel(bone)
			if runtime then
				break
			end
			task.wait(0.05)
		end

		pendingBones[bone] = nil
		if not runtime or activeBones[bone] then
			return
		end

		stopRobloxAnimationTracks(runtime)
		bone.Transform = CFrame.identity
		activeBones[bone] = {
			Runtime = runtime,
			Root = rootOf(runtime),
			StartedAt = os.clock(),
			PositionScale = getPositionScale(runtime),
			Visible = true,
			NextVisibilityCheck = 0,
		}
	end)
end

local function evaluateBlenderPosition(frame)
	if frame <= PEAK_FRAME then
		local alpha = (frame - FRAME_START) / (PEAK_FRAME - FRAME_START)
		local eased = TweenService:GetValue(math.clamp(alpha, 0, 1), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		return PEAK_DISTANCE * eased
	end

	local alpha = (frame - PEAK_FRAME) / (FRAME_END - PEAK_FRAME)
	local eased = TweenService:GetValue(math.clamp(alpha, 0, 1), Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	return PEAK_DISTANCE * (1 - eased)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Bone") then
		registerBone(descendant)
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Bone") then
		registerBone(descendant)
	end
end)

local function isCollectibleVisible(state, camera, performanceLevel)
	local root = state.Root
	if not root or not root:IsDescendantOf(workspace) then
		root = rootOf(state.Runtime)
		state.Root = root
	end
	if not root or not camera then
		return false
	end

	local offset = root.Position - camera.CFrame.Position
	local distanceSquared = offset:Dot(offset)
	if distanceSquared <= FORCE_ACTIVE_DISTANCE * FORCE_ACTIVE_DISTANCE then
		return true
	end
	local maxDistance = NORMAL_MAX_DISTANCE
	if performanceLevel >= 2 then
		maxDistance = EXTREME_MAX_DISTANCE
	elseif performanceLevel >= 1 then
		maxDistance = PERFORMANCE_MAX_DISTANCE
	end
	if distanceSquared > maxDistance * maxDistance then
		return false
	end

	local viewportPoint, onScreen = camera:WorldToViewportPoint(root.Position)
	return onScreen and viewportPoint.Z > 0
end

RunService.RenderStepped:Connect(function(dt)
	local performanceLevel = tonumber(player:GetAttribute("PerformanceLevel")) or 0
	local targetFPS = NORMAL_UPDATE_FPS
	if performanceLevel >= 2 then
		targetFPS = EXTREME_UPDATE_FPS
	elseif performanceLevel >= 1 then
		targetFPS = PERFORMANCE_UPDATE_FPS
	end
	local updateInterval = 1 / targetFPS
	updateAccumulator += dt
	if updateAccumulator < updateInterval then
		return
	end
	updateAccumulator %= updateInterval

	local now = os.clock()
	local camera = workspace.CurrentCamera
	local visibilityInterval = NORMAL_VISIBILITY_INTERVAL
	if performanceLevel >= 2 then
		visibilityInterval = EXTREME_VISIBILITY_INTERVAL
	elseif performanceLevel >= 1 then
		visibilityInterval = PERFORMANCE_VISIBILITY_INTERVAL
	end

	for bone, state in pairs(activeBones) do
		if
			not bone:IsDescendantOf(workspace)
			or not state.Runtime.Parent
			or state.Runtime:GetAttribute("Claimed") == true
		then
			activeBones[bone] = nil
			continue
		end

		if now >= state.NextVisibilityCheck then
			state.Visible = isCollectibleVisible(state, camera, performanceLevel)
			state.NextVisibilityCheck = now + visibilityInterval
		end
		if not state.Visible then
			continue
		end

		local elapsed = (now - state.StartedAt) % LOOP_DURATION
		local frame = FRAME_START + elapsed * FPS
		local blenderPosition = evaluateBlenderPosition(frame)
		local offset = ROBLOX_LOCAL_AXIS * (blenderPosition * state.PositionScale)

		-- Os dados exportados nao possuem rotacao nem escala animadas.
		bone.Transform = CFrame.new(offset)
	end
end)
