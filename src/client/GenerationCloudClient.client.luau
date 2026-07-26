--[[
	Sky Dungeon - GenerationCloudClient adaptativo.

	Move as camadas localmente e reduz overdraw conforme PerformanceLevel:
	Normal: quatro camadas e movimento suave.
	Reduzido: duas camadas, poucas particulas e movimento a 12 FPS.
	Extremo: visuais ocultos; a barreira de progresso continua intacta.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CLOUD_MODEL_NAME = "GenerationClouds"
local NORMAL_UPDATE_FPS = 60
local REDUCED_UPDATE_FPS = 12

local player = Players.LocalPlayer
local trackedLayers = {}
local trackedVisualParts = {}
local trackedEmitters = {}
local trackedTextures = {}
local modelConnections = {}
local currentModel
local updateAccumulator = 0

local function getPerformanceLevel()
	return tonumber(player:GetAttribute("PerformanceLevel")) or 0
end

local function disconnectModelConnections()
	for _, connection in ipairs(modelConnections) do
		connection:Disconnect()
	end
	table.clear(modelConnections)
end

local function isCloudVisualPart(instance)
	return instance:IsA("BasePart")
		and (
			instance:GetAttribute("IsGenerationCloudLayer") == true
			or instance:GetAttribute("IsGenerationCloudCurtain") == true
			or instance:GetAttribute("IsFogCoreBlock") == true
		)
end

local function registerVisual(instance)
	if instance:IsA("BasePart") and instance:GetAttribute("IsGenerationCloudLayer") == true then
		trackedLayers[instance] = true
	end
	if isCloudVisualPart(instance) then
		trackedVisualParts[instance] = true
	elseif instance:IsA("ParticleEmitter") then
		trackedEmitters[instance] = true
	elseif instance:IsA("Texture") and instance.Name == "FogCoreTexture" then
		trackedTextures[instance] = true
	end
end

local function unregisterVisual(instance)
	trackedLayers[instance] = nil
	trackedVisualParts[instance] = nil
	trackedEmitters[instance] = nil
	trackedTextures[instance] = nil
end

local function shouldKeepReducedPart(part)
	if part:GetAttribute("IsGenerationCloudLayer") ~= true then
		return false
	end
	return (tonumber(part:GetAttribute("LayerIndex")) or 99) <= 2
end

local function applyVisualQuality()
	local level = getPerformanceLevel()
	local covering = currentModel and currentModel:GetAttribute("State") == "Covering"

	for part in pairs(trackedVisualParts) do
		if not part.Parent then
			trackedVisualParts[part] = nil
		elseif level >= 2 then
			part.LocalTransparencyModifier = 1
		elseif level >= 1 and not shouldKeepReducedPart(part) then
			part.LocalTransparencyModifier = 1
		else
			part.LocalTransparencyModifier = 0
		end
	end

	for emitter in pairs(trackedEmitters) do
		if not emitter.Parent then
			trackedEmitters[emitter] = nil
		else
			local visibleRate = tonumber(emitter:GetAttribute("VisibleRate")) or emitter.Rate
			if level >= 2 then
				emitter.Rate = 0
			elseif level >= 1 then
				local host = emitter.Parent
				emitter.Rate = covering
					and host:IsA("BasePart")
					and shouldKeepReducedPart(host)
					and math.max(1, math.floor(visibleRate * 0.3 + 0.5))
					or 0
			elseif covering then
				emitter.Rate = visibleRate
			end
		end
	end

	for texture in pairs(trackedTextures) do
		if not texture.Parent then
			trackedTextures[texture] = nil
		elseif level >= 1 then
			texture.Transparency = 1
		elseif currentModel and currentModel:GetAttribute("State") == "Covering" then
			local fogCore = texture.Parent
			texture.Transparency =
				tonumber(fogCore:GetAttribute("FogCoreTextureTransparency"))
				or texture.Transparency
		end
	end
end

local function attachToModel(model)
	if currentModel == model then
		return
	end

	disconnectModelConnections()
	table.clear(trackedLayers)
	table.clear(trackedVisualParts)
	table.clear(trackedEmitters)
	table.clear(trackedTextures)
	currentModel = model

	if not currentModel then
		return
	end

	for _, descendant in ipairs(currentModel:GetDescendants()) do
		registerVisual(descendant)
	end

	table.insert(modelConnections, currentModel.DescendantAdded:Connect(function(descendant)
		registerVisual(descendant)
		task.defer(applyVisualQuality)
	end))
	table.insert(modelConnections, currentModel.DescendantRemoving:Connect(unregisterVisual))
	table.insert(modelConnections, currentModel:GetAttributeChangedSignal("State"):Connect(function()
		task.defer(applyVisualQuality)
	end))
	table.insert(modelConnections, currentModel.Destroying:Connect(function()
		attachToModel(nil)
	end))

	applyVisualQuality()
end

local function findCloudModel()
	local model = workspace:FindFirstChild(CLOUD_MODEL_NAME)
	return model and model:IsA("Model") and model or nil
end

attachToModel(findCloudModel())

workspace.ChildAdded:Connect(function(child)
	if child.Name == CLOUD_MODEL_NAME and child:IsA("Model") then
		attachToModel(child)
	end
end)

workspace.ChildRemoved:Connect(function(child)
	if child == currentModel then
		attachToModel(nil)
	end
end)

player:GetAttributeChangedSignal("PerformanceLevel"):Connect(applyVisualQuality)

task.spawn(function()
	while true do
		task.wait(getPerformanceLevel() >= 2 and 1.5 or 0.8)
		if getPerformanceLevel() >= 1 then
			-- Garante a reducao mesmo quando o servidor reforma as nuvens e
			-- replica novamente os Rates originais durante o tween.
			applyVisualQuality()
		end
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	local level = getPerformanceLevel()
	if level >= 2 then
		return
	end

	local targetFPS = level >= 1 and REDUCED_UPDATE_FPS or NORMAL_UPDATE_FPS
	updateAccumulator += deltaTime
	if updateAccumulator < 1 / targetFPS then
		return
	end
	updateAccumulator %= 1 / targetFPS

	local elapsed = os.clock()
	for layer in pairs(trackedLayers) do
		if not layer.Parent then
			trackedLayers[layer] = nil
			continue
		end
		if level >= 1 and not shouldKeepReducedPart(layer) then
			continue
		end

		local origin = layer:GetAttribute("CloudOriginPosition")
		if typeof(origin) ~= "Vector3" then
			continue
		end

		local distance = layer:GetAttribute("DriftDistance") or 10
		local speed = layer:GetAttribute("DriftSpeed") or 0.05
		local rotationSpeed = layer:GetAttribute("RotationSpeed") or 0.2
		local phase = layer:GetAttribute("DriftPhase") or 0
		local absoluteSpeed = math.max(math.abs(speed), 0.001)
		local direction = speed >= 0 and 1 or -1

		local offsetX =
			math.sin(elapsed * absoluteSpeed * math.pi * 2 + phase)
			* distance
			* direction
		local offsetZ =
			math.cos(elapsed * absoluteSpeed * math.pi * 1.62 + phase)
			* distance
			* 0.58
		local rotationY = math.rad(elapsed * rotationSpeed * direction)

		layer.CFrame =
			CFrame.new(origin + Vector3.new(offsetX, 0, offsetZ))
			* CFrame.Angles(0, rotationY, 0)
	end
end)
