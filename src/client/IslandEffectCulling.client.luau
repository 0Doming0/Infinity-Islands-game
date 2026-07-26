--[[
	Culling complementar por ilha.

	O Roblox ja decide quais Parts desenhar. Este script nao esconde geometria e
	nao percorre blocos por frame; ele pausa somente particulas, feixes, luzes e
	sons locais quando a ilha esta distante ou fora da margem da camera.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local WORLD_MODEL_NAME = "GeneratedBlockWorld"
local NODES_FOLDER_NAME = "IslandNodes"
local DEFAULT_UPDATE_SECONDS = 0.2
local DEFAULT_MAX_DISTANCE = 230
local DEFAULT_FORCE_ACTIVE_DISTANCE = 45
local DEFAULT_SCREEN_MARGIN = 96
local PERFORMANCE_UPDATE_SECONDS = 0.32
local PERFORMANCE_MAX_DISTANCE = 125
local PERFORMANCE_FORCE_ACTIVE_DISTANCE = 34
local PERFORMANCE_SCREEN_MARGIN = 24
local EXTREME_UPDATE_SECONDS = 0.5
local EXTREME_MAX_DISTANCE = 85
local EXTREME_FORCE_ACTIVE_DISTANCE = 28
local EXTREME_SCREEN_MARGIN = 0

local player = Players.LocalPlayer

local tracked = {}
local folderConnections = {}
local currentFolder

local function disconnectFolder()
	for _, connection in ipairs(folderConnections) do
		connection:Disconnect()
	end
	table.clear(folderConnections)
	currentFolder = nil
end

local function isToggleEffect(instance)
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Light")
		or instance:IsA("Fire")
		or instance:IsA("Smoke")
		or instance:IsA("Sparkles")
end

local function registerEffect(state, instance)
	if state.Effects[instance] then
		return
	end
	if isToggleEffect(instance) then
		state.Effects[instance] = {
			Kind = "Enabled",
			Original = instance.Enabled,
		}
		if not state.Active then
			instance.Enabled = false
		end
	elseif instance:IsA("Sound") then
		state.Effects[instance] = {
			Kind = "Volume",
			Original = instance.Volume,
		}
		if not state.Active then
			instance.Volume = 0
		end
	end
end

local function unregisterNode(model)
	local state = tracked[model]
	if not state then
		return
	end
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	tracked[model] = nil
end

local function registerNode(model)
	if not model:IsA("Model") or tracked[model] then
		return
	end
	local state = {
		Effects = {},
		Connections = {},
		Active = true,
	}
	tracked[model] = state
	for _, descendant in ipairs(model:GetDescendants()) do
		registerEffect(state, descendant)
	end
	table.insert(state.Connections, model.DescendantAdded:Connect(function(descendant)
		registerEffect(state, descendant)
	end))
	table.insert(state.Connections, model.DescendantRemoving:Connect(function(descendant)
		state.Effects[descendant] = nil
	end))
	table.insert(state.Connections, model.Destroying:Connect(function()
		unregisterNode(model)
	end))
end

local function attachFolder(folder)
	if currentFolder == folder then
		return
	end
	disconnectFolder()
	for model in pairs(tracked) do
		unregisterNode(model)
	end
	currentFolder = folder
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		registerNode(child)
	end
	table.insert(folderConnections, folder.ChildAdded:Connect(registerNode))
	table.insert(folderConnections, folder.ChildRemoved:Connect(unregisterNode))
end

local function findNodesFolder()
	local world = Workspace:FindFirstChild(WORLD_MODEL_NAME)
	local folder = world and world:FindFirstChild(NODES_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder, world
	end
	return nil, world
end

local function setStateActive(state, active)
	if state.Active == active then
		return
	end
	state.Active = active
	for instance, saved in pairs(state.Effects) do
		if not instance.Parent then
			state.Effects[instance] = nil
		elseif saved.Kind == "Enabled" then
			instance.Enabled = active and saved.Original or false
		elseif saved.Kind == "Volume" then
			instance.Volume = active and saved.Original or 0
		end
	end
end

local function getNodeCenterAndRadius(model)
	local primary = model.PrimaryPart
	if primary and primary.Parent then
		local radius = Vector2.new(primary.Size.X, primary.Size.Z).Magnitude * 0.5
		return primary.Position, math.max(8, radius)
	end
	local ok, pivot = pcall(model.GetPivot, model)
	if ok then
		return pivot.Position, 20
	end
	return nil, 0
end

local function isInsideCameraMargin(camera, center, radius, forceDistance, maxDistance, marginPixels)
	local offset = center - camera.CFrame.Position
	local distance = offset.Magnitude
	if distance <= forceDistance then
		return true
	end
	if distance - radius > maxDistance then
		return false
	end
	local screenPoint = camera:WorldToViewportPoint(center)
	if screenPoint.Z < -radius then
		return false
	end
	local depth = math.max(1, screenPoint.Z)
	local projectedRadius = radius / depth
		* camera.ViewportSize.Y
		/ (2 * math.tan(math.rad(camera.FieldOfView) * 0.5))
	local margin = marginPixels + projectedRadius
	return screenPoint.X >= -margin
		and screenPoint.X <= camera.ViewportSize.X + margin
		and screenPoint.Y >= -margin
		and screenPoint.Y <= camera.ViewportSize.Y + margin
end

while true do
	local folder, world = findNodesFolder()
	attachFolder(folder)
	local enabled = not world or world:GetAttribute("EffectCullingEnabled") ~= false
	local updateSeconds = world and world:GetAttribute("EffectCullingUpdateSeconds") or DEFAULT_UPDATE_SECONDS
	local maxDistance = world and world:GetAttribute("EffectCullingMaxDistanceStuds") or DEFAULT_MAX_DISTANCE
	local forceDistance = world and world:GetAttribute("EffectCullingForceActiveDistanceStuds")
		or DEFAULT_FORCE_ACTIVE_DISTANCE
	local marginPixels = world and world:GetAttribute("EffectCullingScreenMarginPixels") or DEFAULT_SCREEN_MARGIN
	local performanceLevel = tonumber(player:GetAttribute("PerformanceLevel")) or 0
	if performanceLevel >= 2 then
		updateSeconds = math.max(updateSeconds, EXTREME_UPDATE_SECONDS)
		maxDistance = math.min(maxDistance, EXTREME_MAX_DISTANCE)
		forceDistance = math.min(forceDistance, EXTREME_FORCE_ACTIVE_DISTANCE)
		marginPixels = math.min(marginPixels, EXTREME_SCREEN_MARGIN)
	elseif performanceLevel >= 1 then
		updateSeconds = math.max(updateSeconds, PERFORMANCE_UPDATE_SECONDS)
		maxDistance = math.min(maxDistance, PERFORMANCE_MAX_DISTANCE)
		forceDistance = math.min(forceDistance, PERFORMANCE_FORCE_ACTIVE_DISTANCE)
		marginPixels = math.min(marginPixels, PERFORMANCE_SCREEN_MARGIN)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		for model, state in pairs(tracked) do
			if not model.Parent then
				unregisterNode(model)
			else
				local center, radius = getNodeCenterAndRadius(model)
				local active = not enabled
					or (center ~= nil and isInsideCameraMargin(
						camera,
						center,
						radius,
						forceDistance,
						maxDistance,
						marginPixels
					))
				setStateActive(state, active)
			end
		end
	end
	task.wait(math.max(0.1, updateSeconds))
end
