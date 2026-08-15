local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local fireVisuals = {}

local function getEquippedOrbNames()
	local names = {}
	local serialized = player:GetAttribute("EquippedOrbs")
	if typeof(serialized) == "string" then
		for orbName in string.gmatch(serialized, "[^,]+") do
			local normalized = OrbConfig.NormalizeOrb(orbName)
			if normalized and not names[normalized] then
				names[normalized] = true
			end
		end
	end
	if next(names) == nil then
		local primary = OrbConfig.NormalizeOrb(player:GetAttribute("EquippedOrb"))
		if primary then
			names[primary] = true
		end
		local secondary = OrbConfig.NormalizeOrb(player:GetAttribute("EquippedOrb2"))
		if secondary then
			names[secondary] = true
		end
	end
	return names
end

local function removeDuplicateVisuals(character)
	local expectedNames = {}
	for orbName in pairs(getEquippedOrbNames()) do
		local definition = OrbConfig.GetOrb(orbName)
		if definition then
			expectedNames[definition.AssetName or (orbName .. "Orb")] = true
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrbVisual") == true and not expectedNames[child.Name] then
			child:Destroy()
		end
	end
end

local function getOrbRoot(orb)
	if orb:IsA("BasePart") then
		return orb
	end
	if orb:IsA("Model") then
		return orb.PrimaryPart or orb:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function clearFireVisual(orb)
	local visual = fireVisuals[orb]
	if visual then
		if visual.Container then
			visual.Container:Destroy()
		end
		fireVisuals[orb] = nil
	end
end

local function createFlamePart(parent, name, color, size)
	local flame = Instance.new("Part")
	flame.Name = name
	flame.Shape = Enum.PartType.Ball
	flame.Size = size
	flame.Material = Enum.Material.Neon
	flame.Color = color
	flame.Transparency = 0.12
	flame.Anchored = true
	flame.CanCollide = false
	flame.CanTouch = false
	flame.CanQuery = false
	flame.CastShadow = false
	flame.Parent = parent
	return flame
end

local function createFireVisual(orb, root)
	local container = Instance.new("Folder")
	container.Name = "ProceduralFireOrbVFX"
	container.Parent = orb

	local core = createFlamePart(container, "FireCoreGlow", Color3.fromRGB(255, 92, 12), Vector3.new(1.35, 1.35, 1.35))
	core.Transparency = 0.42
	local innerCore = createFlamePart(container, "FireInnerCore", Color3.fromRGB(255, 225, 92), Vector3.new(0.82, 0.82, 0.82))
	innerCore.Transparency = 0.08

	local light = Instance.new("PointLight")
	light.Name = "ProceduralFireLight"
	light.Color = Color3.fromRGB(255, 78, 12)
	light.Brightness = 2.8
	light.Range = 9
	light.Shadows = false
	light.Parent = root

	local flames = {}
	local flameData = {
		{Angle = 0, Height = 1.35, Radius = 0.52, Width = 0.3, Color = Color3.fromRGB(255, 105, 18)},
		{Angle = 0.9, Height = 1.05, Radius = 0.58, Width = 0.24, Color = Color3.fromRGB(255, 185, 38)},
		{Angle = 1.8, Height = 1.5, Radius = 0.5, Width = 0.26, Color = Color3.fromRGB(255, 78, 10)},
		{Angle = 2.7, Height = 1.12, Radius = 0.62, Width = 0.22, Color = Color3.fromRGB(255, 205, 55)},
		{Angle = 3.6, Height = 1.42, Radius = 0.55, Width = 0.28, Color = Color3.fromRGB(255, 92, 12)},
		{Angle = 4.5, Height = 1.02, Radius = 0.63, Width = 0.23, Color = Color3.fromRGB(255, 190, 35)},
		{Angle = 5.4, Height = 1.3, Radius = 0.54, Width = 0.25, Color = Color3.fromRGB(255, 72, 8)},
	}
	for index, data in ipairs(flameData) do
		local flame = createFlamePart(container, "FlameTongue" .. index, data.Color, Vector3.new(data.Width, data.Height, data.Width))
		table.insert(flames, {Part = flame, Data = data})
	end

	local embers = {}
	for index = 1, 9 do
		local ember = createFlamePart(container, "FloatingEmber" .. index, Color3.fromRGB(255, 170, 42), Vector3.new(0.09, 0.09, 0.09))
		table.insert(embers, ember)
	end

	local rings = {}
	for index = 1, 2 do
		local ring = Instance.new("Part")
		ring.Name = "FireEnergyRing" .. index
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.035, 1.65, 1.65)
		ring.Material = Enum.Material.Neon
		ring.Color = index == 1 and Color3.fromRGB(255, 125, 15) or Color3.fromRGB(255, 220, 75)
		ring.Transparency = 0.28
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanTouch = false
		ring.CanQuery = false
		ring.CastShadow = false
		ring.Parent = container
		table.insert(rings, ring)
	end

	local cracks = {}
	local crackData = {
		{Offset = Vector3.new(0.28, 0.35, -0.58), Length = 0.52, Angle = math.rad(18)},
		{Offset = Vector3.new(-0.38, 0.18, -0.54), Length = 0.68, Angle = math.rad(-28)},
		{Offset = Vector3.new(0.05, -0.3, -0.61), Length = 0.46, Angle = math.rad(-12)},
		{Offset = Vector3.new(-0.1, 0.52, -0.47), Length = 0.38, Angle = math.rad(35)},
		{Offset = Vector3.new(0.57, -0.08, -0.18), Length = 0.42, Angle = math.rad(72)},
		{Offset = Vector3.new(-0.5, -0.45, -0.2), Length = 0.34, Angle = math.rad(-58)},
	}
	for index, data in ipairs(crackData) do
		local crack = Instance.new("Part")
		crack.Name = "LavaCrack" .. index
		crack.Size = Vector3.new(0.035, data.Length, 0.035)
		crack.Material = Enum.Material.Neon
		crack.Color = index % 2 == 0 and Color3.fromRGB(255, 115, 12) or Color3.fromRGB(255, 225, 82)
		crack.Transparency = 0.18
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanTouch = false
		crack.CanQuery = false
		crack.CastShadow = false
		crack.Parent = container
		table.insert(cracks, {Part = crack, Data = data})
	end

	return {Container = container, Root = root, Core = core, InnerCore = innerCore, Light = light, Flames = flames, Embers = embers, Rings = rings, Cracks = cracks}
end

local function updateFireVisual(orb, visual, now)
	if not orb:IsDescendantOf(workspace) or not visual.Root:IsDescendantOf(workspace) then
		clearFireVisual(orb)
		return
	end
	local rootCFrame = visual.Root.CFrame
	local pulse = (math.sin(now * 7) + 1) * 0.5
	visual.Core.CFrame = rootCFrame * CFrame.new(0, 0, 0)
	visual.Core.Size = Vector3.new(1.2 + pulse * 0.16, 1.2 + pulse * 0.16, 1.2 + pulse * 0.16)
	visual.InnerCore.CFrame = rootCFrame * CFrame.new(0, 0, 0)
	visual.InnerCore.Size = Vector3.new(0.75 + pulse * 0.1, 0.75 + pulse * 0.1, 0.75 + pulse * 0.1)
	visual.Light.Brightness = 2.2 + pulse * 1.6
	visual.Light.Range = 8 + pulse * 2

	for index, flame in ipairs(visual.Flames) do
		local data = flame.Data
		local wave = math.sin(now * (4.2 + index * 0.18) + index * 1.7)
		local angle = data.Angle + now * (0.45 + index * 0.035)
		local radius = data.Radius + wave * 0.08
		local height = data.Height + wave * 0.16
		local position = Vector3.new(math.cos(angle) * radius, height * 0.5, math.sin(angle) * radius)
		flame.Part.CFrame = rootCFrame * CFrame.new(position) * CFrame.Angles(0, angle, wave * 0.45)
		flame.Part.Size = Vector3.new(data.Width * (0.85 + pulse * 0.2), height, data.Width * (0.85 + pulse * 0.2))
		flame.Part.Transparency = 0.12 + (1 - pulse) * 0.12
	end

	for index, ember in ipairs(visual.Embers) do
		local phase = now * (0.8 + index * 0.07) + index * 2.1
		local radius = 0.7 + (index % 3) * 0.16
		local height = 0.7 + ((phase * 0.55) % 1.7)
		local position = Vector3.new(math.cos(phase) * radius, height, math.sin(phase) * radius)
		ember.CFrame = rootCFrame * CFrame.new(position)
		ember.Size = Vector3.new(0.07 + pulse * 0.05, 0.07 + pulse * 0.05, 0.07 + pulse * 0.05)
		ember.Transparency = 0.1 + ((index % 3) * 0.12)
	end

	for index, ring in ipairs(visual.Rings) do
		local angle = now * (index == 1 and 1.5 or -1.1)
		local scale = 1.4 + math.sin(now * 4 + index) * 0.15
		ring.CFrame = rootCFrame * CFrame.new(0, -0.55 + index * 0.18, 0) * CFrame.Angles(0, angle, math.rad(90))
		ring.Size = Vector3.new(0.035, scale, scale)
		ring.Transparency = 0.22 + (1 - pulse) * 0.25
	end

	for index, crack in ipairs(visual.Cracks) do
		local data = crack.Data
		local flicker = (math.sin(now * (8 + index) + index * 1.4) + 1) * 0.5
		local offset = data.Offset + Vector3.new(0, math.sin(now * 2.5 + index) * 0.015, 0)
		crack.Part.CFrame = rootCFrame * CFrame.new(offset) * CFrame.Angles(0, 0, data.Angle)
		crack.Part.Transparency = 0.12 + (1 - pulse) * 0.24 + flicker * 0.12
		crack.Part.Size = Vector3.new(0.035 + pulse * 0.018, data.Length * (0.9 + flicker * 0.12), 0.035)
	end
end

local function updateCharacterFireVisuals(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrbVisual") == true and child:GetAttribute("OrbType") == "Fire" then
			local root = getOrbRoot(child)
			if root and not fireVisuals[child] then
				fireVisuals[child] = createFireVisual(child, root)
			end
		end
	end
end

local function observeCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:GetAttribute("OrbVisual") == true then
			task.defer(removeDuplicateVisuals, character)
			task.defer(updateCharacterFireVisuals, character)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		clearFireVisual(child)
	end)
	task.spawn(function()
		for _ = 1, 20 do
			if not character.Parent then
				return
			end
			removeDuplicateVisuals(character)
			updateCharacterFireVisuals(character)
			task.wait(0.5)
		end
	end)
end

local function refreshOrbVisuals()
	if player.Character then
		removeDuplicateVisuals(player.Character)
		updateCharacterFireVisuals(player.Character)
	end
end

player:GetAttributeChangedSignal("EquippedOrb"):Connect(refreshOrbVisuals)
player:GetAttributeChangedSignal("EquippedOrb2"):Connect(refreshOrbVisuals)
player:GetAttributeChangedSignal("EquippedOrbs"):Connect(refreshOrbVisuals)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for orb, visual in pairs(fireVisuals) do
		updateFireVisual(orb, visual, now)
	end
end)

player.CharacterAdded:Connect(observeCharacter)
if player.Character then
	observeCharacter(player.Character)
end