--[[
	Misterio a longa distancia sem neblina.

	O efeito e local: mantem o espaco jogavel proximo nitido e desfoca somente o
	horizonte. Nao usa FogStart/FogEnd, particulas ou pecas transparentes e nao
	interfere no culling automatico do Roblox.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WORLD_MODEL_NAME = "GeneratedBlockWorld"
local EFFECT_NAME = "SkyDungeonMysteryDistance"
local DEFAULT_ENABLED = true
local DEFAULT_FOCUS_DISTANCE = 90
local DEFAULT_IN_FOCUS_RADIUS = 105
local DEFAULT_FAR_INTENSITY = 0.72
local player = Players.LocalPlayer

local effect = Lighting:FindFirstChild(EFFECT_NAME)
if effect and not effect:IsA("DepthOfFieldEffect") then
	effect:Destroy()
	effect = nil
end
if not effect then
	effect = Instance.new("DepthOfFieldEffect")
	effect.Name = EFFECT_NAME
	effect.Parent = Lighting
end

effect.NearIntensity = 0

local currentWorld
local attributeConnections = {}

local function disconnectWorld()
	for _, connection in ipairs(attributeConnections) do
		connection:Disconnect()
	end
	table.clear(attributeConnections)
	currentWorld = nil
end

local function numberAttribute(world, name, fallback)
	local value = world and world:GetAttribute(name)
	return typeof(value) == "number" and value or fallback
end

local function applySettings()
	local world = currentWorld
	local enabled = world and world:GetAttribute("MysteryDistanceEnabled")
	if typeof(enabled) ~= "boolean" then
		enabled = DEFAULT_ENABLED
	end
	effect.Enabled = enabled and player:GetAttribute("PerformanceMode") ~= true
	effect.FocusDistance = math.max(0, numberAttribute(world, "MysteryFocusDistanceStuds", DEFAULT_FOCUS_DISTANCE))
	effect.InFocusRadius = math.max(0, numberAttribute(world, "MysteryInFocusRadiusStuds", DEFAULT_IN_FOCUS_RADIUS))
	effect.FarIntensity = math.clamp(numberAttribute(world, "MysteryFarIntensity", DEFAULT_FAR_INTENSITY), 0, 1)
end

player:GetAttributeChangedSignal("PerformanceMode"):Connect(applySettings)

local function attachWorld(world)
	if currentWorld == world then
		return
	end
	disconnectWorld()
	currentWorld = world
	if world then
		for _, attributeName in ipairs({
			"MysteryDistanceEnabled",
			"MysteryFocusDistanceStuds",
			"MysteryInFocusRadiusStuds",
			"MysteryFarIntensity",
		}) do
			table.insert(attributeConnections, world:GetAttributeChangedSignal(attributeName):Connect(applySettings))
		end
		table.insert(attributeConnections, world.Destroying:Connect(function()
			attachWorld(nil)
		end))
	end
	applySettings()
end

Workspace.DescendantAdded:Connect(function(child)
	if child.Name == WORLD_MODEL_NAME then
		attachWorld(child)
	end
end)

Workspace.DescendantRemoving:Connect(function(child)
	if child == currentWorld then
		attachWorld(nil)
	end
end)

attachWorld(Workspace:FindFirstChild(WORLD_MODEL_NAME, true))
