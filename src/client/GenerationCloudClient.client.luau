--[[
	Sky Dungeon - GenerationCloudClient

	Move as camadas de nuvens localmente para evitar que o servidor precise
	replicar mudanças de posição constantemente.

	Cada jogador vê um movimento suave e independente.
]]

local RunService = game:GetService("RunService")

local CLOUD_MODEL_NAME = "GenerationClouds"

local trackedLayers = {}
local modelConnections = {}
local currentModel

local function disconnectModelConnections()
	for _, connection in ipairs(modelConnections) do
		connection:Disconnect()
	end

	table.clear(modelConnections)
end

local function registerLayer(instance)
	if
		instance:IsA("BasePart")
		and instance:GetAttribute("IsGenerationCloudLayer") == true
	then
		trackedLayers[instance] = true
	end
end

local function unregisterLayer(instance)
	trackedLayers[instance] = nil
end

local function attachToModel(model)
	if currentModel == model then
		return
	end

	disconnectModelConnections()
	table.clear(trackedLayers)

	currentModel = model

	if not currentModel then
		return
	end

	for _, descendant in ipairs(currentModel:GetDescendants()) do
		registerLayer(descendant)
	end

	table.insert(
		modelConnections,
		currentModel.DescendantAdded:Connect(registerLayer)
	)

	table.insert(
		modelConnections,
		currentModel.DescendantRemoving:Connect(unregisterLayer)
	)

	table.insert(
		modelConnections,
		currentModel.Destroying:Connect(function()
			attachToModel(nil)
		end)
	)
end

local function findCloudModel()
	local model = workspace:FindFirstChild(CLOUD_MODEL_NAME)

	if model and model:IsA("Model") then
		return model
	end

	return nil
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

RunService.RenderStepped:Connect(function()
	local elapsed = os.clock()

	for layer in pairs(trackedLayers) do
		if not layer.Parent then
			trackedLayers[layer] = nil
			continue
		end

		local origin =
			layer:GetAttribute("CloudOriginPosition")

		if typeof(origin) ~= "Vector3" then
			continue
		end

		local distance =
			layer:GetAttribute("DriftDistance") or 10

		local speed =
			layer:GetAttribute("DriftSpeed") or 0.05

		local rotationSpeed =
			layer:GetAttribute("RotationSpeed") or 0.2

		local phase =
			layer:GetAttribute("DriftPhase") or 0

		local absoluteSpeed = math.max(math.abs(speed), 0.001)
		local direction = speed >= 0 and 1 or -1

		local offsetX =
			math.sin(elapsed * absoluteSpeed * math.pi * 2 + phase)
			* distance
			* direction

		local offsetZ =
			math.cos(
				elapsed
					* absoluteSpeed
					* math.pi
					* 1.62
					+ phase
			)
			* distance
			* 0.58

		local rotationY =
			math.rad(elapsed * rotationSpeed * direction)

		layer.CFrame =
			CFrame.new(
				origin + Vector3.new(offsetX, 0, offsetZ)
			)
			* CFrame.Angles(0, rotationY, 0)
	end
end)