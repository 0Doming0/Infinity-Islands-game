local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local attackConfirmed = orbFolder:WaitForChild("OrbAttackConfirmed")

local HIT_STOP_DURATION = 0.045
local SHAKE_DURATION = 0.12
local SHAKE_MAGNITUDE = 0.12
local IMPACT_SOUNDS = {
	Fire = {Volume = 0.22, PlaybackSpeed = 0.78, Id = "rbxassetid://91870890930509"},
	Ice = {Volume = 0.12, PlaybackSpeed = 1.28, Id = "rbxassetid://98205232642582"},
	Shadow = {Volume = 0.18, PlaybackSpeed = 0.58, Id = "rbxassetid://608971830"},
}
local FIRE_EFFECT_SOUNDS = {
	Projectile = {Volume = 0.08, PlaybackSpeed = 1.18, Id = "rbxassetid://91870890930509"},
	AreaExplosion = {Volume = 0.3, PlaybackSpeed = 0.68, Id = "rbxassetid://91870890930509"},
	BurnSpread = {Volume = 0.14, PlaybackSpeed = 1.05, Id = "rbxassetid://91870890930509"},
	Execute = {Volume = 0.36, PlaybackSpeed = 0.58, Id = "rbxassetid://91870890930509"},
	Nebula = {Volume = 0.26, PlaybackSpeed = 0.5, Id = "rbxassetid://91870890930509"},
	NebulaLoop = {Volume = 0.07, PlaybackSpeed = 0.72, Id = "rbxassetid://91870890930509"},
	BurnStart = {Volume = 0.18, PlaybackSpeed = 1.32, Id = "rbxassetid://91870890930509"},
}
local shakeRemaining = 0
local shakeStrength = 0
local hitStopUntil = 0
local hitStopCFrame
local camera = Workspace.CurrentCamera
local frozenVisuals = {}
local burnVisuals = {}
local slowVisuals = {}
local shadowMarkVisuals = {}
local shadowDisorientVisuals = {}
local slowFieldVisuals = {}
local shatterSerials = {}
local localPlayer = Players.LocalPlayer
local shadowMarkAttribute = "OrbShadowMark_" .. localPlayer.UserId
local MAX_EFFECT_DISTANCE = 160
local REDUCED_EFFECT_DISTANCE = 105
local EXTREME_EFFECT_DISTANCE = 70
local EFFECT_UPDATE_INTERVAL = 0.06
local emitIceImpactBurst

local function getPerformanceLevel()
	return math.clamp(tonumber(localPlayer:GetAttribute("PerformanceLevel")) or 0, 0, 2)
end

local function getEffectDistance(root)
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera or not root then
		return math.huge
	end
	return (root.Position - currentCamera.CFrame.Position).Magnitude
end

local function shouldRenderEffect(root)
	local level = getPerformanceLevel()
	local maxDistance = level >= 2 and EXTREME_EFFECT_DISTANCE or level >= 1 and REDUCED_EFFECT_DISTANCE or MAX_EFFECT_DISTANCE
	return getEffectDistance(root) <= maxDistance
end

local function clearFrozenVisual(model)
	local visual = frozenVisuals[model]
	if visual then
		if visual.Attachment then
			visual.Attachment:Destroy()
		end
		visual.Container:Destroy()
		frozenVisuals[model] = nil
	end
end

local function emitFreezeApplicationBurst(position)
	local anchor = Instance.new("Part")
	anchor.Name = "IceFreezeBurstClient"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FreezeShatterParticles"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 185, 255)),
	})
	emitter.LightEmission = 0.9
	emitter.Lifetime = NumberRange.new(0.25, 0.55)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-260, 260)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(0.5, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
	emitter:Emit(18)
	Debris:AddItem(anchor, 0.8)
end

local function updateFrozenCrystals(model, visual)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	local elapsed = os.clock() * 2.6
	for index, crystal in ipairs(visual.Crystals) do
		local angle = elapsed + (index - 1) * math.pi * 2 / #visual.Crystals
		local height = 1.4 + math.sin(elapsed * 1.7 + index) * 0.45
		crystal.CFrame = root.CFrame * CFrame.new(math.cos(angle) * 1.45, height, math.sin(angle) * 1.45) * CFrame.Angles(angle, angle * 0.7, angle * 0.4)
	end
	local ringPulse = (math.sin(os.clock() * 5) + 1) * 0.5
	for index, segment in ipairs(visual.Ring) do
		local angle = os.clock() * 1.2 + (index - 1) * math.pi * 2 / #visual.Ring
		local radius = 1.55 + ringPulse * 0.12
		segment.CFrame = CFrame.new(root.Position - Vector3.new(0, root.Size.Y * 0.5 + 0.04, 0)) * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
		segment.Transparency = 0.28 + (1 - visual.Remaining) * 0.5 + ringPulse * 0.08
	end
end

local function updateFrozenVisual(model)
	if not model or not model:IsDescendantOf(workspace) then
		clearFrozenVisual(model)
		return
	end
	local frozenUntil = tonumber(model:GetAttribute("OrbFrozenUntil")) or 0
	if frozenUntil <= Workspace:GetServerTimeNow() then
		clearFrozenVisual(model)
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	if not shouldRenderEffect(root) then
		clearFrozenVisual(model)
		return
	end
	local visual = frozenVisuals[model]
	local isNewFreeze = not visual
	if not visual then
		local container = Instance.new("Folder")
		container.Name = "IceFreezeVisualClient"
		container.Parent = model
		local highlight = Instance.new("Highlight")
		highlight.Name = "FreezeHighlight"
		highlight.FillColor = Color3.fromRGB(110, 225, 255)
		highlight.OutlineColor = Color3.fromRGB(220, 250, 255)
		highlight.FillTransparency = 0.55
		highlight.OutlineTransparency = 0.05
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = container
		local attachment = Instance.new("Attachment")
		attachment.Name = "FreezeMistAttachment"
		attachment.Position = Vector3.new(0, 0.7, 0)
		attachment.Parent = root
		local mist = Instance.new("ParticleEmitter")
		mist.Name = "FreezeMist"
		mist.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 190, 255)),
		})
		mist.LightEmission = 0.55
		mist.LightInfluence = 0
		mist.Lifetime = NumberRange.new(0.55, 1.1)
		mist.Rate = 12
		mist.Speed = NumberRange.new(0.3, 1.1)
		mist.SpreadAngle = Vector2.new(360, 360)
		mist.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.55, 0.65),
			NumberSequenceKeypoint.new(1, 0),
		})
		mist.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.7, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		mist.Parent = attachment
		local ring = {}
		for index = 1, 8 do
			local segment = Instance.new("Part")
			segment.Name = "FreezeRingSegment" .. index
			segment.Size = Vector3.new(0.12, 0.06, 0.42)
			segment.Material = Enum.Material.Neon
			segment.Color = Color3.fromRGB(150, 235, 255)
			segment.Transparency = 0.3
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanTouch = false
			segment.CanQuery = false
			segment.Parent = container
			table.insert(ring, segment)
		end
		local crystals = {}
		for index = 1, 4 do
			local crystal = Instance.new("Part")
			crystal.Name = "OrbitingCrystal" .. index
			crystal.Shape = Enum.PartType.Wedge
			crystal.Size = Vector3.new(0.28, 0.85, 0.28)
			crystal.Material = Enum.Material.Neon
			crystal.Color = Color3.fromRGB(125, 230, 255)
			crystal.Transparency = 0.08
			crystal.Anchored = true
			crystal.CanCollide = false
			crystal.CanTouch = false
			crystal.CanQuery = false
			crystal.Parent = container
			table.insert(crystals, crystal)
		end
		local cracks = {}
		local crackOffsets = {
			CFrame.new(0, 1.35, -0.72) * CFrame.Angles(0, 0, math.rad(18)),
			CFrame.new(-0.42, 0.95, -0.48) * CFrame.Angles(0, math.rad(20), math.rad(-32)),
			CFrame.new(0.42, 0.95, -0.48) * CFrame.Angles(0, math.rad(-20), math.rad(32)),
		}
		for index, offset in ipairs(crackOffsets) do
			local crack = Instance.new("Part")
			crack.Name = "FreezeCrack" .. index
			crack.Size = Vector3.new(0.05, 0.72, 0.025)
			crack.Material = Enum.Material.Neon
			crack.Color = Color3.fromRGB(240, 255, 255)
			crack.Transparency = 1
			crack.CanCollide = false
			crack.CanTouch = false
			crack.CanQuery = false
			crack.Massless = true
			crack.CFrame = root.CFrame * offset
			crack.Parent = container
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = crack
			weld.Parent = crack
			table.insert(cracks, crack)
		end
		local bodyCrystals = {}
		local bodyOffsets = {
			CFrame.new(0, 1.45, -0.55) * CFrame.Angles(math.rad(-18), 0, 0),
			CFrame.new(-0.52, 1.1, -0.25) * CFrame.Angles(0, math.rad(35), math.rad(-20)),
			CFrame.new(0.52, 1.1, -0.25) * CFrame.Angles(0, math.rad(-35), math.rad(20)),
			CFrame.new(-0.35, 0.15, -0.35) * CFrame.Angles(math.rad(-12), math.rad(25), 0),
			CFrame.new(0.35, 0.15, -0.35) * CFrame.Angles(math.rad(-12), math.rad(-25), 0),
		}
		for index, offset in ipairs(bodyOffsets) do
			local shard = Instance.new("Part")
			shard.Name = "FrozenBodyCrystal" .. index
			shard.Shape = Enum.PartType.Wedge
			shard.Size = Vector3.new(0.42, 0.95, 0.22)
			shard.Material = Enum.Material.Glass
			shard.Color = Color3.fromRGB(175, 245, 255)
			shard.Transparency = 0.35
			shard.CanCollide = false
			shard.CanTouch = false
			shard.CanQuery = false
			shard.Massless = true
			shard.CFrame = root.CFrame * offset
			shard.Parent = container
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = shard
			weld.Parent = shard
			table.insert(bodyCrystals, shard)
		end
		visual = {Container = container, Attachment = attachment, Mist = mist, Crystals = crystals, BodyCrystals = bodyCrystals, Cracks = cracks, Ring = ring, Remaining = 1}
		frozenVisuals[model] = visual
	end
	local remaining = math.clamp((frozenUntil - Workspace:GetServerTimeNow()) / 3, 0, 1)
	local crackProgress = math.clamp((0.42 - remaining) / 0.42, 0, 1)
	for index, crack in ipairs(visual.Cracks or {}) do
		local pulse = (math.sin(os.clock() * 12 + index) + 1) * 0.5
		crack.Transparency = 1 - crackProgress * (0.68 + pulse * 0.2)
		crack.Size = Vector3.new(0.05 + crackProgress * 0.04, 0.72 + crackProgress * 0.22, 0.025)
	end
	visual.Remaining = remaining
	visual.Mist.Rate = 4 + 12 * remaining
	for index, shard in ipairs(visual.BodyCrystals or {}) do
		local pulse = (math.sin(os.clock() * 5 + index) + 1) * 0.5
		shard.Transparency = 0.2 + (1 - remaining) * 0.68 + pulse * 0.06
	end
	if isNewFreeze then
		emitFreezeApplicationBurst(root.Position + Vector3.new(0, 1, 0))
	end
	updateFrozenCrystals(model, visual)
end

local function clearBurnVisual(model)
	local visual = burnVisuals[model]
	if visual then
		if visual.Attachment then
			visual.Attachment:Destroy()
		end
		visual.Container:Destroy()
		burnVisuals[model] = nil
	end
end

local function updateBurnVisual(model)
	if not model or not model:IsDescendantOf(workspace) then
		clearBurnVisual(model)
		return
	end
	local burnUntil = tonumber(model:GetAttribute("OrbBurnUntil")) or 0
	if burnUntil <= Workspace:GetServerTimeNow() then
		clearBurnVisual(model)
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	if not shouldRenderEffect(root) then
		clearBurnVisual(model)
		return
	end
	local visual = burnVisuals[model]
	if not visual then
		local container = Instance.new("Folder")
		container.Name = "FireBurnVisualClient"
		container.Parent = model
		local attachment = Instance.new("Attachment")
		attachment.Name = "BurnAttachment"
		attachment.Position = Vector3.new(0, 1.15, 0)
		attachment.Parent = root
		local flames = Instance.new("ParticleEmitter")
		flames.Name = "BurnFlames"
		flames.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 120)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 120, 25)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 35, 10)),
		})
		flames.LightEmission = 0.75
		flames.LightInfluence = 0
		flames.Lifetime = NumberRange.new(0.35, 0.7)
		flames.Rate = 18
		flames.Speed = NumberRange.new(1.5, 4)
		flames.SpreadAngle = Vector2.new(35, 35)
		flames.Rotation = NumberRange.new(0, 360)
		flames.RotSpeed = NumberRange.new(-90, 90)
		flames.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.42),
			NumberSequenceKeypoint.new(0.6, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		flames.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.75, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		flames.Parent = attachment
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "BurnSmoke"
		smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70))
		smoke.LightInfluence = 1
		smoke.Lifetime = NumberRange.new(0.6, 1.1)
		smoke.Rate = 5
		smoke.Speed = NumberRange.new(0.5, 1.5)
		smoke.SpreadAngle = Vector2.new(25, 25)
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 0.8),
		})
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.7, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Parent = attachment
		local embers = Instance.new("ParticleEmitter")
		embers.Name = "BurnEmbers"
		embers.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 145)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 125, 18)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(145, 22, 5)),
		})
		embers.LightEmission = 1
		embers.LightInfluence = 0
		embers.Lifetime = NumberRange.new(0.35, 0.85)
		embers.Rate = 12
		embers.Speed = NumberRange.new(2, 5.5)
		embers.SpreadAngle = Vector2.new(360, 360)
		embers.Rotation = NumberRange.new(0, 360)
		embers.RotSpeed = NumberRange.new(-320, 320)
		embers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.16),
			NumberSequenceKeypoint.new(0.35, 0.09),
			NumberSequenceKeypoint.new(1, 0),
		})
		embers.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.02),
			NumberSequenceKeypoint.new(0.65, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		embers.Parent = attachment
		local light = Instance.new("PointLight")
		light.Name = "BurnLight"
		light.Color = Color3.fromRGB(255, 95, 25)
		light.Brightness = 1.2
		light.Range = 6
		light.Shadows = false
		light.Parent = attachment
		visual = {Container = container, Attachment = attachment, Flames = flames, Smoke = smoke, Embers = embers, Light = light}
		burnVisuals[model] = visual
	end
	local remaining = math.clamp((burnUntil - Workspace:GetServerTimeNow()) / 3, 0, 1)
	visual.Flames.Rate = 8 + 18 * remaining
	visual.Smoke.Rate = 2 + 5 * remaining
	visual.Embers.Rate = 5 + 14 * remaining
	visual.Light.Brightness = 0.45 + 1.2 * remaining
	visual.Light.Range = 4 + 4 * remaining
end

local function clearShadowMarkVisual(model)
	local visual = shadowMarkVisuals[model]
	if visual then
		visual.Container:Destroy()
		shadowMarkVisuals[model] = nil
	end
end

local function emitShadowMarkBurst(position)
	local anchor = Instance.new("Part")
	anchor.Name = "ShadowMarkBurstClient"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ThirdMarkBurst"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 125, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(55, 5, 95)),
	})
	emitter.LightEmission = 0.9
	emitter.Lifetime = NumberRange.new(0.25, 0.55)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.45, 0.11),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
	emitter:Emit(24)
	Debris:AddItem(anchor, 0.9)
end

local function updateShadowMarkVisual(model)
	if not model or not model:IsDescendantOf(workspace) then
		clearShadowMarkVisual(model)
		return
	end
	local markCount = math.clamp(tonumber(model:GetAttribute(shadowMarkAttribute)) or 0, 0, 3)
	local markUntil = tonumber(model:GetAttribute(shadowMarkAttribute .. "Until")) or 0
	if markCount <= 0 or markUntil <= Workspace:GetServerTimeNow() then
		clearShadowMarkVisual(model)
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	if not shouldRenderEffect(root) then
		clearShadowMarkVisual(model)
		return
	end
	local visual = shadowMarkVisuals[model]
	if not visual then
		local container = Instance.new("Folder")
		container.Name = "ShadowMarkVisualClient"
		container.Parent = model
		local marks = {}
		local attachments = {}
		for index = 1, 3 do
			local mark = Instance.new("Part")
			mark.Name = "ShadowMarkClient" .. index
			mark.Shape = Enum.PartType.Ball
			mark.Size = Vector3.new(0.38, 0.38, 0.38)
			mark.Material = Enum.Material.Neon
			mark.Color = Color3.fromRGB(190, 55, 255)
			mark.Anchored = true
			mark.CanCollide = false
			mark.CanTouch = false
			mark.CanQuery = false
			mark.Parent = container
			local attachment = Instance.new("Attachment")
			attachment.Parent = mark
			marks[index] = mark
			attachments[index] = attachment
		end
		local beams = {}
		for index = 1, 3 do
			local beam = Instance.new("Beam")
			beam.Name = "ShadowMarkLink" .. index
			beam.Attachment0 = attachments[index]
			beam.Attachment1 = attachments[index % 3 + 1]
			beam.Color = ColorSequence.new(Color3.fromRGB(145, 35, 220))
			beam.LightEmission = 0.75
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Width0 = 0.045
			beam.Width1 = 0.02
			beam.Transparency = NumberSequence.new(0.25)
			beam.Parent = container
			beams[index] = beam
		end
		visual = {Container = container, Marks = marks, Beams = beams, PreviousCount = 0, Remaining = 1}
		shadowMarkVisuals[model] = visual
	end
	local remaining = math.clamp((markUntil - Workspace:GetServerTimeNow()) / 2.5, 0, 1)
	visual.Remaining = remaining
	local pulse = (math.sin(os.clock() * 7) + 1) * 0.5
	local elapsed = os.clock() * 1.8
	for index, mark in ipairs(visual.Marks) do
		local angle = elapsed + (index - 1) * math.pi * 2 / 3
		local radius = 0.72 + pulse * 0.08
		mark.CFrame = root.CFrame * CFrame.new(math.cos(angle) * radius, 2.45 + math.sin(elapsed * 2 + index) * 0.12, math.sin(angle) * radius)
		mark.Size = Vector3.new(0.3 + pulse * 0.12, 0.3 + pulse * 0.12, 0.3 + pulse * 0.12)
		mark.Transparency = 0.05 + (1 - remaining) * 0.7
		mark.Color = index <= markCount and Color3.fromRGB(205, 70, 255) or Color3.fromRGB(55, 15, 80)
	end
	for index, beam in ipairs(visual.Beams) do
		beam.Enabled = index <= markCount and markCount >= 2
		beam.Transparency = NumberSequence.new(0.2 + (1 - remaining) * 0.7)
	end
	if visual.PreviousCount < 3 and markCount == 3 then
		emitShadowMarkBurst(root.Position + Vector3.new(0, 2.45, 0))
	end
	visual.PreviousCount = markCount
end

local function clearShadowDisorientVisual(model)
	local visual = shadowDisorientVisuals[model]
	if visual then
		visual.Container:Destroy()
		shadowDisorientVisuals[model] = nil
	end
end

local function updateShadowDisorientVisual(model)
	if not model or not model:IsDescendantOf(workspace) then
		clearShadowDisorientVisual(model)
		return
	end
	local statusEffect = model:GetAttribute("OrbStatusEffect")
	local disorientedUntil = tonumber(model:GetAttribute("OrbDisorientedUntil")) or 0
	if statusEffect ~= "SlowDisorient" or disorientedUntil <= Workspace:GetServerTimeNow() then
		clearShadowDisorientVisual(model)
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	if not shouldRenderEffect(root) then
		clearShadowDisorientVisual(model)
		return
	end
	local visual = shadowDisorientVisuals[model]
	if not visual then
		local container = Instance.new("Folder")
		container.Name = "ShadowDisorientVisualClient"
		container.Parent = model
		local halo = Instance.new("Part")
		halo.Name = "ShadowDisorientHalo"
		halo.Shape = Enum.PartType.Cylinder
		halo.Size = Vector3.new(0.06, 2.15, 2.15)
		halo.Material = Enum.Material.Neon
		halo.Color = Color3.fromRGB(95, 20, 150)
		halo.Transparency = 0.42
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanTouch = false
		halo.CanQuery = false
		halo.Parent = container
		local highlight = Instance.new("Highlight")
		highlight.Name = "ShadowDisorientHighlight"
		highlight.FillColor = Color3.fromRGB(80, 15, 130)
		highlight.OutlineColor = Color3.fromRGB(205, 90, 255)
		highlight.FillTransparency = 0.9
		highlight.OutlineTransparency = 0.3
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = container
		local wisps = {}
		for index = 1, 4 do
			local wisp = Instance.new("Part")
			wisp.Name = "ShadowWisp" .. index
			wisp.Shape = Enum.PartType.Ball
			wisp.Size = Vector3.new(0.2, 0.2, 0.2)
			wisp.Material = Enum.Material.Neon
			wisp.Color = Color3.fromRGB(180, 55, 255)
			wisp.Transparency = 0.12
			wisp.Anchored = true
			wisp.CanCollide = false
			wisp.CanTouch = false
			wisp.CanQuery = false
			wisp.Parent = container
			table.insert(wisps, wisp)
		end
		visual = {Container = container, Halo = halo, Highlight = highlight, Wisps = wisps}
		shadowDisorientVisuals[model] = visual
	end
	local remaining = math.clamp((disorientedUntil - Workspace:GetServerTimeNow()) / 2.5, 0, 1)
	local pulse = (math.sin(os.clock() * 9) + 1) * 0.5
	visual.Halo.CFrame = CFrame.new(root.Position + Vector3.new(0, 2.65, 0)) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, os.clock() * 2.4, 0)
	visual.Halo.Transparency = 0.28 + (1 - remaining) * 0.55 + pulse * 0.08
	visual.Halo.Size = Vector3.new(0.06, 1.95 + pulse * 0.35, 1.95 + pulse * 0.35)
	visual.Highlight.OutlineTransparency = 0.22 + (1 - remaining) * 0.55
	for index, wisp in ipairs(visual.Wisps) do
		local angle = os.clock() * (2.1 + index * 0.12) + index * math.pi * 0.5
		local radius = 0.82 + pulse * 0.08
		local height = 2.25 + math.sin(os.clock() * 4 + index) * 0.32
		wisp.CFrame = root.CFrame * CFrame.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		wisp.Transparency = 0.08 + (1 - remaining) * 0.78
	end
end

local function clearSlowVisual(model)
	local visual = slowVisuals[model]
	if visual then
		visual.Container:Destroy()
		slowVisuals[model] = nil
	end
end

local function clearSlowFieldVisual(id)
	local visual = slowFieldVisuals[id]
	if visual then
		visual.Ring:Destroy()
		visual.Container:Destroy()
		slowFieldVisuals[id] = nil
	end
end

local function renderSlowField(center, radius, expiresAt)
	local level = getPerformanceLevel()
	if level >= 2 then
		return
	end
	local id = tostring(center) .. ":" .. tostring(expiresAt)
	if slowFieldVisuals[id] then
		clearSlowFieldVisual(id)
	end
	local container = Instance.new("Folder")
	container.Name = "IceSlowFieldClient"
	container.Parent = workspace
	local ring = Instance.new("Part")
	ring.Name = "SlowFieldRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(center - Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(75, 190, 255)
	ring.Transparency = 0.28
	ring.Parent = container
	local attachment = Instance.new("Attachment")
	attachment.Parent = ring
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "SnowFieldParticles"
	particles.Color = ColorSequence.new(Color3.fromRGB(180, 245, 255))
	particles.LightEmission = 0.8
	particles.Lifetime = NumberRange.new(0.5, 1)
	particles.Rate = math.max(8, radius * 3)
	particles.Speed = NumberRange.new(0.2, 1)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Size = NumberSequence.new(0.16)
	particles.Parent = attachment
	local crystals = {}
	local crystalLimit = level >= 1 and 10 or 18
	local crystalCount = math.clamp(math.floor(radius * 1.25), 6, crystalLimit)
	for index = 1, crystalCount do
		local angle = (index - 1) * math.pi * 2 / crystalCount
		local crystal = Instance.new("Part")
		crystal.Name = "SlowFieldCrystal" .. index
		crystal.Shape = Enum.PartType.Wedge
		crystal.Size = Vector3.new(0.22, 0.75 + (index % 3) * 0.18, 0.22)
		crystal.Material = Enum.Material.Neon
		crystal.Color = Color3.fromRGB(135, 230, 255)
		crystal.Transparency = 0.18
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.CanTouch = false
		crystal.CanQuery = false
		crystal.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * radius, -0.65, math.sin(angle) * radius)) * CFrame.Angles(0, -angle, math.rad(-12))
		crystal.Parent = container
		table.insert(crystals, crystal)
	end
	slowFieldVisuals[id] = {Container = container, Ring = ring, Crystals = crystals, Radius = radius, Center = center, ExpiresAt = expiresAt}
	task.delay(math.max(0.1, expiresAt - Workspace:GetServerTimeNow()), function()
		clearSlowFieldVisual(id)
	end)
end

local function updateSlowVisual(model)
	if not model or not model:IsDescendantOf(workspace) then
		clearSlowVisual(model)
		return
	end
	local slowedUntil = tonumber(model:GetAttribute("OrbSlowedUntil")) or 0
	local statusEffect = model:GetAttribute("OrbStatusEffect")
	if statusEffect ~= "SlowField" and statusEffect ~= "SlowDisorient" then
		clearSlowVisual(model)
		return
	end
	if slowedUntil <= Workspace:GetServerTimeNow() then
		clearSlowVisual(model)
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	if not shouldRenderEffect(root) then
		clearSlowVisual(model)
		return
	end
	local visual = slowVisuals[model]
	if not visual then
		local container = Instance.new("Folder")
		container.Name = "OrbSlowVisualClient"
		container.Parent = model
		local ring = Instance.new("Part")
		ring.Name = "SlowRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.08, 3.4, 3.4)
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(90, 205, 255)
		ring.Transparency = 0.38
		ring.CanCollide = false
		ring.CanTouch = false
		ring.CanQuery = false
		ring.Anchored = true
		ring.Parent = container
		local highlight = Instance.new("Highlight")
		highlight.Name = "SlowHighlight"
		highlight.FillColor = Color3.fromRGB(35, 125, 185)
		highlight.OutlineColor = Color3.fromRGB(145, 235, 255)
		highlight.FillTransparency = 0.86
		highlight.OutlineTransparency = 0.42
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = container
		visual = {Container = container, Ring = ring, Highlight = highlight}
		slowVisuals[model] = visual
	end
	local remaining = math.clamp((slowedUntil - Workspace:GetServerTimeNow()) / 2.5, 0, 1)
	local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
	visual.Ring.CFrame = CFrame.new(root.Position - Vector3.new(0, root.Size.Y * 0.5 + 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, os.clock() * 1.8, 0)
	visual.Ring.Transparency = 0.28 + (1 - remaining) * 0.45 + pulse * 0.08
	visual.Ring.Size = Vector3.new(0.08, 3.1 + pulse * 0.45, 3.1 + pulse * 0.45)
	visual.Highlight.OutlineTransparency = 0.28 + (1 - remaining) * 0.5
end

local function bindFrozenTarget(model)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("OrbFrozenUntil"):Connect(function()
		updateFrozenVisual(model)
	end)
	model:GetAttributeChangedSignal("OrbBurnUntil"):Connect(function()
		updateBurnVisual(model)
	end)
	model:GetAttributeChangedSignal("OrbSlowedUntil"):Connect(function()
		updateSlowVisual(model)
	end)
	model:GetAttributeChangedSignal("OrbStatusEffect"):Connect(function()
		updateSlowVisual(model)
		updateShadowDisorientVisual(model)
	end)
	model:GetAttributeChangedSignal("OrbDisorientedUntil"):Connect(function()
		updateShadowDisorientVisual(model)
	end)
	model:GetAttributeChangedSignal("OrbShatterSerial"):Connect(function()
		local serial = tonumber(model:GetAttribute("OrbShatterSerial")) or 0
		if serial > (shatterSerials[model] or 0) then
			shatterSerials[model] = serial
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if root then
				local shatterPosition = root.Position + Vector3.new(0, 1, 0)
				emitIceImpactBurst(shatterPosition, 3, false)
				emitIceCrystalBurst(shatterPosition, Color3.fromRGB(220, 250, 255))
				emitIceShatterBurst(shatterPosition)
			end
		end
	end)
	model:GetAttributeChangedSignal(shadowMarkAttribute):Connect(function()
		updateShadowMarkVisual(model)
	end)
	model:GetAttributeChangedSignal(shadowMarkAttribute .. "Until"):Connect(function()
		updateShadowMarkVisual(model)
	end)
	updateFrozenVisual(model)
	updateBurnVisual(model)
	updateSlowVisual(model)
	updateShadowDisorientVisual(model)
	updateShadowMarkVisual(model)
end

for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
	bindFrozenTarget(model)
end
CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(bindFrozenTarget)
CollectionService:GetInstanceRemovedSignal("CombatTarget"):Connect(function(model)
	clearFrozenVisual(model)
	clearBurnVisual(model)
	clearSlowVisual(model)
	clearShadowDisorientVisual(model)
	clearShadowMarkVisual(model)
end)

task.spawn(function()
	while true do
		task.wait(EFFECT_UPDATE_INTERVAL)
		local now = Workspace:GetServerTimeNow()
			for id, field in pairs(slowFieldVisuals) do
			if field.Container.Parent then
				if now >= field.ExpiresAt then
					clearSlowFieldVisual(id)
					continue
				end
				local remaining = math.clamp((field.ExpiresAt - now) / 3, 0, 1)
				local pulse = (math.sin(os.clock() * 7) + 1) * 0.5
				for index, crystal in ipairs(field.Crystals or {}) do
					local angle = (index - 1) * math.pi * 2 / #field.Crystals + os.clock() * 0.35
					local radiusOffset = math.sin(os.clock() * 4 + index) * 0.08
					crystal.CFrame = CFrame.new(field.Center + Vector3.new(math.cos(angle) * (field.Radius + radiusOffset), -0.65 + pulse * 0.08, math.sin(angle) * (field.Radius + radiusOffset))) * CFrame.Angles(0, -angle, math.rad(-12))
					crystal.Transparency = 0.18 + (1 - remaining) * 0.72 + pulse * 0.08
				end
			end
		end
		for model in pairs(frozenVisuals) do
			updateFrozenVisual(model)
		end
		for model in pairs(burnVisuals) do
			updateBurnVisual(model)
		end
		for model in pairs(slowVisuals) do
			updateSlowVisual(model)
		end
		for model in pairs(shadowDisorientVisuals) do
			updateShadowDisorientVisual(model)
		end
		for model in pairs(shadowMarkVisuals) do
			updateShadowMarkVisual(model)
		end
		for model in pairs(shatterSerials) do
			if not model:IsDescendantOf(workspace) then
				shatterSerials[model] = nil
			end
		end
	end
end)

local function emitIceShatterBurst(position)
	local container = Instance.new("Folder")
	container.Name = "IceShatterBurstClient"
	container.Parent = workspace
	local ring = Instance.new("Part")
	ring.Name = "ShatterShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, 0.7, 0.7)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(220, 250, 255)
	ring.Transparency = 0.05
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = container
	TweenService:Create(ring, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, 5.5, 5.5),
		Transparency = 1,
	}):Play()
	local flash = Instance.new("Part")
	flash.Name = "ShatterFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.1, 1.1, 1.1)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(245, 255, 255)
	flash.Transparency = 0.08
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.CFrame = CFrame.new(position)
	flash.Parent = container
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 230, 255)
	light.Brightness = 5
	light.Range = 10
	light.Shadows = false
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3.2, 3.2, 3.2),
		Transparency = 1,
	}):Play()
	local attachment = Instance.new("Attachment")
	attachment.Parent = flash
	local shards = Instance.new("ParticleEmitter")
	shards.Name = "ShatterFragments"
	shards.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 230, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 120, 220)),
	})
	shards.LightEmission = 1
	shards.Lifetime = NumberRange.new(0.35, 0.8)
	shards.Rate = 0
	shards.Speed = NumberRange.new(12, 24)
	shards.SpreadAngle = Vector2.new(360, 360)
	shards.Rotation = NumberRange.new(0, 360)
	shards.RotSpeed = NumberRange.new(-420, 420)
	shards.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.4, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	shards.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	shards.Parent = attachment
	shards:Emit(34)
	Debris:AddItem(container, 0.9)
end

emitIceImpactBurst = function(position, radius, prison)
	local anchor = Instance.new("Part")
	anchor.Name = prison and "IcePrisonBurstClient" or "IceImpactBurstClient"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = prison and "PrisonCrystalBurst" or "IceImpactCrystals"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 255, 255)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(90, 220, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 100, 210)),
	})
	emitter.LightEmission = 0.95
	emitter.Lifetime = NumberRange.new(0.3, 0.75)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(prison and 5 or 9, prison and 11 or 18)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-300, 300)
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, prison and 0.3 or 0.22), NumberSequenceKeypoint.new(0.45, 0.12), NumberSequenceKeypoint.new(1, 0)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.02), NumberSequenceKeypoint.new(0.75, 0.3), NumberSequenceKeypoint.new(1, 1)})
	emitter.Parent = attachment
	emitter:Emit(prison and 30 or 24)
	local ring = Instance.new("Part")
	ring.Name = "IceImpactWave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, 0.8, 0.8)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 0.85, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(130, 235, 255)
	ring.Transparency = 0.15
	ring.Parent = workspace
	local expand = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(0.08, math.max(2.5, radius * 2), math.max(2.5, radius * 2)), Transparency = 1})
	expand:Play()
	Debris:AddItem(ring, 0.4)
	local flash = Instance.new("Part")
	flash.Name = "IceImpactFlashClient"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.7, 0.7, 0.7)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(220, 255, 255)
	flash.Transparency = 0.1
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.CFrame = CFrame.new(position)
	flash.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(100, 220, 255)
	light.Brightness = 3
	light.Range = 8
	light.Parent = flash
	Debris:AddItem(flash, 0.12)
	Debris:AddItem(anchor, 1)
end

local function emitIcePrisonCage(position, radius)
	local container = Instance.new("Folder")
	container.Name = "IceCrystalPrisonClient"
	container.Parent = workspace
	local count = 8
	local cageRadius = math.clamp((tonumber(radius) or 3) * 0.28, 0.9, 2.2)
	local crystals = {}
	for index = 1, count do
		local angle = (index - 1) * math.pi * 2 / count
		local crystal = Instance.new("Part")
		crystal.Name = "PrisonCrystal" .. index
		crystal.Shape = Enum.PartType.Wedge
		crystal.Size = Vector3.new(0.42, 2.4, 0.42)
		crystal.Material = Enum.Material.Neon
		crystal.Color = Color3.fromRGB(120, 225, 255)
		crystal.Transparency = 0.12
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.CanTouch = false
		crystal.CanQuery = false
		crystal.CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * cageRadius, -1.2, math.sin(angle) * cageRadius)) * CFrame.Angles(0, -angle, math.rad(-12))
		crystal.Parent = container
		table.insert(crystals, crystal)
		local rise = TweenService:Create(crystal, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {CFrame = crystal.CFrame + Vector3.new(0, 1.2, 0), Size = Vector3.new(0.55, 3.5, 0.55)})
		rise:Play()
	end
	local cageRing = Instance.new("Part")
	cageRing.Name = "PrisonCageRing"
	cageRing.Shape = Enum.PartType.Cylinder
	cageRing.Size = Vector3.new(0.1, cageRadius * 2.4, cageRadius * 2.4)
	cageRing.CFrame = CFrame.new(position - Vector3.new(0, 1.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	cageRing.Material = Enum.Material.Neon
	cageRing.Color = Color3.fromRGB(185, 250, 255)
	cageRing.Transparency = 0.2
	cageRing.Anchored = true
	cageRing.CanCollide = false
	cageRing.CanTouch = false
	cageRing.CanQuery = false
	cageRing.Parent = container
	local pulse = TweenService:Create(cageRing, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true), {Transparency = 0.62, Size = Vector3.new(0.1, cageRadius * 2.8, cageRadius * 2.8)})
	pulse:Play()
	task.delay(1.65, function()
		if not container.Parent then return end
		for _, crystal in ipairs(crystals) do
			TweenService:Create(crystal, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1, Size = Vector3.new(0.1, 0.2, 0.1)}):Play()
		end
		TweenService:Create(cageRing, TweenInfo.new(0.22), {Transparency = 1}):Play()
		Debris:AddItem(container, 0.3)
	end)
end

local function emitIceCrystalBurst(position, color)
	local anchor = Instance.new("Part")
	anchor.Name = "IceCrystalBurstClient"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CrystalParticles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.28, 0.6)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 15)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.18),
	NumberSequenceKeypoint.new(0.35, 0.1),
	NumberSequenceKeypoint.new(1, 0),
})
	emitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(0.75, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
	emitter.Parent = attachment
	emitter:Emit(12)
	Debris:AddItem(anchor, 0.8)
end

local function renderIceComet(origin, endPosition)
	local travelTime = math.clamp((endPosition - origin).Magnitude / 110, 0.1, 0.28)
	local projectile = Instance.new("Part")
	projectile.Name = "IceCometClient"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(0.72, 0.72, 0.72)
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(225, 255, 255)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.CFrame = CFrame.new(origin)
	projectile.Parent = workspace
	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -0.32)
	front.Parent = projectile
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, 0.32)
	back.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Name = "IceCometTrail"
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 100, 220))})
	trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.Parent = projectile
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(100, 220, 255)
	light.Brightness = 3
	light.Range = 8
	light.Parent = projectile
	task.spawn(function()
		local started = os.clock()
		while projectile.Parent do
			local alpha = math.clamp((os.clock() - started) / travelTime, 0, 1)
			local position = origin:Lerp(endPosition, alpha)
			projectile.CFrame = CFrame.lookAt(position, endPosition)
			if alpha >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		if projectile.Parent then
			emitIceImpactBurst(endPosition, 4, false)
			projectile:Destroy()
		end
	end)
end

local function renderShadowProjectile(origin, endPosition)
	local travelTime = math.clamp((endPosition - origin).Magnitude / 90, 0.08, 0.22)
	local projectile = Instance.new("Part")
	projectile.Name = "ShadowProjectileClient"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(0.48, 0.48, 0.48)
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(105, 35, 190)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.CFrame = CFrame.new(origin)
	projectile.Parent = workspace
	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Name = "ShadowTrailFront"
	frontAttachment.Position = Vector3.new(0, 0, -0.18)
	frontAttachment.Parent = projectile
	local backAttachment = Instance.new("Attachment")
	backAttachment.Name = "ShadowTrailBack"
	backAttachment.Position = Vector3.new(0, 0, 0.18)
	backAttachment.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Name = "ShadowProjectileTrail"
	trail.Attachment0 = frontAttachment
	trail.Attachment1 = backAttachment
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(185, 75, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(95, 20, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 5, 45)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.65, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.Parent = projectile
	local glow = Instance.new("PointLight")
	glow.Name = "ShadowProjectileGlow"
	glow.Color = Color3.fromRGB(135, 45, 255)
	glow.Brightness = 1.8
	glow.Range = 5
	glow.Shadows = false
	glow.Parent = projectile
	task.spawn(function()
		local started = os.clock()
		while projectile.Parent do
			local alpha = math.clamp((os.clock() - started) / travelTime, 0, 1)
			local position = origin:Lerp(endPosition, alpha)
			projectile.CFrame = CFrame.lookAt(position, endPosition)
			glow.Brightness = 0.8 + (1 - alpha) * 1.6
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		if projectile.Parent then
			projectile.CFrame = CFrame.new(endPosition)
		end
		Debris:AddItem(projectile, 0.2)
	end)
end

local function emitEnemyImpactVisual(position, color, burstSize)
	if typeof(position) ~= "Vector3" then
		return
	end
	local level = getPerformanceLevel()
	if level >= 2 then
		return
	end
	local container = Instance.new("Folder")
	container.Name = "OrbEnemyImpactClient"
	container.Parent = workspace
	local flash = Instance.new("Part")
	flash.Name = "ImpactFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.35, 0.35, 0.35)
	flash.CFrame = CFrame.new(position)
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Transparency = 0.08
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Parent = container
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2.5
	light.Range = 7
	light.Shadows = false
	light.Parent = flash
	local ring = Instance.new("Part")
	ring.Name = "ImpactRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, 0.5, 0.5)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.12
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = container
	local attachment = Instance.new("Attachment")
	attachment.Parent = flash
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "ImpactSparks"
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 1
	particles.Lifetime = NumberRange.new(0.18, 0.38)
	particles.Rate = 0
	particles.Speed = NumberRange.new(5, 10)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.65, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = attachment
	particles:Emit(level >= 1 and 10 or 18)
	local duration = level >= 1 and 0.18 or 0.28
	TweenService:Create(flash, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(burstSize, burstSize, burstSize),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Brightness = 0}):Play()
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, burstSize * 2.5, burstSize * 2.5),
		Transparency = 1,
	}):Play()
	Debris:AddItem(container, 0.65)
end

local function emitFireAreaExplosion(position, radius)
	local level = getPerformanceLevel()
	if level >= 2 then
		return
	end
	local safeRadius = math.clamp(tonumber(radius) or 4, 3, 18)
	local container = Instance.new("Folder")
	container.Name = "FireAreaExplosionClient"
	container.Parent = workspace
	local ring = Instance.new("Part")
	ring.Name = "FireExplosionRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 105, 20)
	ring.Transparency = 0.08
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = container
	TweenService:Create(ring, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, safeRadius * 2, safeRadius * 2),
		Transparency = 1,
	}):Play()
	local flash = Instance.new("Part")
	flash.Name = "FireExplosionFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.1, 1.1, 1.1)
	flash.CFrame = CFrame.new(position + Vector3.new(0, 0.8, 0))
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 185, 55)
	flash.Transparency = 0.05
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Parent = container
	local light = Instance.new("PointLight")
	light.Name = "FireExplosionLight"
	light.Color = Color3.fromRGB(255, 90, 20)
	light.Brightness = 5
	light.Range = safeRadius * 1.3
	light.Shadows = false
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(safeRadius * 0.85, safeRadius * 0.85, safeRadius * 0.85),
		Transparency = 1,
	}):Play()
	local attachment = Instance.new("Attachment")
	attachment.Parent = flash
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "FireExplosionSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 150)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 105, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 20, 5)),
	})
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.25, 0.65)
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(8, 18)
	sparks.SpreadAngle = Vector2.new(360, 360)
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-360, 360)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.24),
		NumberSequenceKeypoint.new(0.4, 0.13),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = attachment
	sparks:Emit(level >= 1 and 18 or 30)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "FireExplosionSmoke"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 45, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 20, 18)),
	})
	smoke.LightInfluence = 1
	smoke.Lifetime = NumberRange.new(0.5, 1.05)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(360, 360)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.55, 1.15),
		NumberSequenceKeypoint.new(1, 1.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.62),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = attachment
	smoke:Emit(level >= 1 and 5 or 9)
	Debris:AddItem(container, 1.2)
end

local function emitFireNebula(position, radius)
	local level = getPerformanceLevel()
	if level >= 2 then
		return
	end
	local safeRadius = math.clamp(tonumber(radius) or 5, 5, 20)
	local container = Instance.new("Folder")
	container.Name = "FireNebulaClient"
	container.Parent = workspace
	local function makeLayer(name, color, size, transparency, offset)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Ball
		part.Size = size
		part.CFrame = CFrame.new(position + offset)
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = container
		return part
	end
	local core = makeLayer("FireNebulaCore", Color3.fromRGB(255, 238, 160), Vector3.one * 0.35, 0.02, Vector3.zero)
	local hotLayer = makeLayer("FireNebulaHotLayer", Color3.fromRGB(255, 104, 12), Vector3.one * 0.7, 0.28, Vector3.new(0.08, 0, 0))
	local darkHaze = makeLayer("FireNebulaDarkHaze", Color3.fromRGB(76, 18, 30), Vector3.one * 1.1, 0.82, Vector3.new(0, 0.2, 0.3))
	local cloudData = {
		{Color3.fromRGB(255, 194, 45), 0.34, Vector3.new(-0.24, 0.12, 0.1), Vector3.new(0.75, 0.45, 0.62)},
		{Color3.fromRGB(255, 116, 18), 0.42, Vector3.new(0.32, 0.2, -0.12), Vector3.new(0.64, 0.58, 0.48)},
		{Color3.fromRGB(255, 225, 112), 0.3, Vector3.new(-0.08, 0.42, -0.3), Vector3.new(0.5, 0.76, 0.44)},
		{Color3.fromRGB(196, 42, 14), 0.5, Vector3.new(0.08, -0.28, 0.28), Vector3.new(0.72, 0.4, 0.52)},
		{Color3.fromRGB(118, 24, 35), 0.58, Vector3.new(-0.44, -0.08, -0.2), Vector3.new(0.42, 0.52, 0.4)},
	}
	local clouds = {}
	for index, data in ipairs(cloudData) do
		local cloud = makeLayer("FireNebulaCloud" .. index, data[1], data[4], data[2], data[3])
		cloud.CFrame *= CFrame.Angles(index * 0.37, index * 0.61, index * 0.23)
		table.insert(clouds, {Part = cloud, BaseTransparency = data[2], BaseSize = data[4], Phase = index * 1.23})
	end
	local light = Instance.new("PointLight")
	light.Name = "FireNebulaLight"
	light.Color = Color3.fromRGB(255, 80, 20)
	light.Brightness = 8
	light.Range = safeRadius * 1.4
	light.Shadows = false
	light.Parent = core
	local attachment = Instance.new("Attachment")
	attachment.Parent = core
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "NebulaFlames"
	flames.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 245, 145), Color3.fromRGB(166, 24, 8))
	flames.LightEmission = 1
	flames.Lifetime = NumberRange.new(0.35, 0.85)
	flames.Rate = level >= 1 and 10 or 20
	flames.Speed = NumberRange.new(2, 7)
	flames.SpreadAngle = Vector2.new(360, 360)
	flames.Rotation = NumberRange.new(0, 360)
	flames.RotSpeed = NumberRange.new(-180, 180)
	flames.Size = NumberSequence.new(0.18 * safeRadius / 5, 0.55 * safeRadius / 5)
	flames.Transparency = NumberSequence.new(0.08, 1)
	flames.Parent = attachment
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "NebulaSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(132, 24, 28), Color3.fromRGB(24, 12, 25))
	smoke.Lifetime = NumberRange.new(0.9, 1.7)
	smoke.Rate = level >= 1 and 5 or 10
	smoke.Speed = NumberRange.new(1, 3.5)
	smoke.SpreadAngle = Vector2.new(360, 360)
	smoke.Size = NumberSequence.new(0.7 * safeRadius / 5, 2.4 * safeRadius / 5)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Parent = attachment
	local ring = Instance.new("Part")
	ring.Name = "FireNebulaRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, safeRadius * 0.7, safeRadius * 0.7)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 1.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 75, 15)
	ring.Transparency = 0.18
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Parent = container
	local shockwave = ring:Clone()
	shockwave.Name = "FireNebulaShockwave"
	shockwave.Color = Color3.fromRGB(255, 224, 110)
	shockwave.Transparency = 0.3
	shockwave.Size = Vector3.new(0.05, safeRadius * 0.35, safeRadius * 0.35)
	shockwave.Parent = container
	local loopSettings = FIRE_EFFECT_SOUNDS.NebulaLoop
	local loopSound = Instance.new("Sound")
	loopSound.Name = "FireOrbNebulaCombustion"
	loopSound.SoundId = loopSettings.Id
	loopSound.Volume = 0
	loopSound.PlaybackSpeed = loopSettings.PlaybackSpeed * (0.96 + math.random() * 0.08)
	loopSound.Looped = true
	loopSound.RollOffMode = Enum.RollOffMode.InverseTapered
	loopSound.RollOffMinDistance = 12
	loopSound.RollOffMaxDistance = 90
	loopSound.Parent = core
	loopSound:Play()
	local loopVolume = loopSettings.Volume * (0.94 + math.random() * 0.12)
	TweenService:Create(loopSound, TweenInfo.new(0.22), {Volume = loopVolume}):Play()
	TweenService:Create(core, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.one * safeRadius * 0.42}):Play()
	TweenService:Create(hotLayer, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.one * safeRadius * 0.86, Transparency = 0.5}):Play()
	TweenService:Create(darkHaze, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.one * safeRadius * 1.25}):Play()
	TweenService:Create(ring, TweenInfo.new(0.62, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(0.08, safeRadius * 1.55, safeRadius * 1.55), Transparency = 0.72}):Play()
	TweenService:Create(shockwave, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(0.05, safeRadius * 1.8, safeRadius * 1.8), Transparency = 1}):Play()
	flames:Emit(level >= 1 and 14 or 28)
	smoke:Emit(level >= 1 and 8 or 16)
	task.delay(0.72, function()
		if not container.Parent then
			return
		end
		local fadeInfo = TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(core, fadeInfo, {Transparency = 1}):Play()
		TweenService:Create(hotLayer, fadeInfo, {Transparency = 1}):Play()
		TweenService:Create(darkHaze, fadeInfo, {Transparency = 1}):Play()
		for _, cloud in ipairs(clouds) do
			TweenService:Create(cloud.Part, fadeInfo, {Transparency = 1}):Play()
		end
		TweenService:Create(light, fadeInfo, {Brightness = 0}):Play()
		local fadeOut = TweenService:Create(loopSound, TweenInfo.new(0.25), {Volume = 0})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if loopSound.Parent then
				loopSound:Stop()
			end
		end)
		flames.Enabled = false
		smoke.Enabled = false
		Debris:AddItem(container, 0.55)
	end)
end

local function emitFireBurnSpread(origin, endPosition)
	local level = getPerformanceLevel()
	if level >= 2 or typeof(origin) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return
	end
	local startPart = Instance.new("Part")
	startPart.Name = "FireSpreadStartClient"
	startPart.Size = Vector3.new(0.1, 0.1, 0.1)
	startPart.Transparency = 1
	startPart.Anchored = true
	startPart.CanCollide = false
	startPart.CanTouch = false
	startPart.CanQuery = false
	startPart.Position = origin
	startPart.Parent = workspace
	local endPart = startPart:Clone()
	endPart.Name = "FireSpreadEndClient"
	endPart.Position = endPosition
	endPart.Parent = workspace
	local startAttachment = Instance.new("Attachment")
	startAttachment.Parent = startPart
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = endPart
	local beam = Instance.new("Beam")
	beam.Name = "FireSpreadBeam"
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 80, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 20, 5)),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 0.14
	beam.Width1 = 0.08
	beam.CurveSize0 = 0.8
	beam.CurveSize1 = -0.8
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = startPart
	local attachment = Instance.new("Attachment")
	attachment.Parent = endPart
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "FireSpreadSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 125, 25))
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.2, 0.42)
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(360, 360)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(0.6, 0.07),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = attachment
	sparks:Emit(level >= 1 and 8 or 14)
	TweenService:Create(beam, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Width0 = 0.02,
		Width1 = 0.02,
	}):Play()
	Debris:AddItem(startPart, 0.35)
	Debris:AddItem(endPart, 0.35)
end

local function emitFireExecute(position)
	local level = getPerformanceLevel()
	if level >= 2 then
		return
	end
	local container = Instance.new("Folder")
	container.Name = "FireExecuteClient"
	container.Parent = workspace
	local ring = Instance.new("Part")
	ring.Name = "ExecuteRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 1.2, 1.2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 55, 10)
	ring.Transparency = 0.05
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = container
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 6, 6),
		Transparency = 1,
	}):Play()
	local flash = Instance.new("Part")
	flash.Name = "ExecuteFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.8, 0.8, 0.8)
	flash.CFrame = CFrame.new(position)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 210, 70)
	flash.Transparency = 0.05
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Parent = container
	local light = Instance.new("PointLight")
	light.Name = "ExecuteLight"
	light.Color = Color3.fromRGB(255, 70, 15)
	light.Brightness = 6
	light.Range = 12
	light.Shadows = false
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3.4, 3.4, 3.4),
		Transparency = 1,
	}):Play()
	local attachment = Instance.new("Attachment")
	attachment.Parent = flash
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "ExecuteFlameBurst"
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 150)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 95, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 10, 4)),
	})
	particles.LightEmission = 1
	particles.Lifetime = NumberRange.new(0.3, 0.7)
	particles.Rate = 0
	particles.Speed = NumberRange.new(10, 20)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-420, 420)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.26),
		NumberSequenceKeypoint.new(0.45, 0.14),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = attachment
	particles:Emit(level >= 1 and 20 or 34)
	Debris:AddItem(container, 0.9)
end

local function emitShadowImpactBurst(position)
	local anchor = Instance.new("Part")
	anchor.Name = "ShadowImpactBurstClient"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ShadowImpactSmoke"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(135, 45, 220)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(45, 10, 75)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 3, 15)),
	})
	smoke.LightEmission = 0.35
	smoke.LightInfluence = 0
	smoke.Lifetime = NumberRange.new(0.45, 0.9)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(360, 360)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-140, 140)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.45, 0.8),
		NumberSequenceKeypoint.new(1, 1.15),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.65, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = attachment
	smoke:Emit(16)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "ShadowImpactSparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(190, 75, 255))
	sparks.LightEmission = 0.9
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(360, 360)
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-260, 260)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.45, 0.09),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = attachment
	sparks:Emit(14)
	local flash = Instance.new("Part")
	flash.Name = "ShadowImpactFlashClient"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.75, 0.75, 0.75)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(155, 50, 255)
	flash.Transparency = 0.18
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.CFrame = CFrame.new(position)
	flash.Parent = workspace
	local light = Instance.new("PointLight")
	light.Name = "ShadowImpactLight"
	light.Color = Color3.fromRGB(120, 35, 255)
	light.Brightness = 3
	light.Range = 8
	light.Shadows = false
	light.Parent = flash
	Debris:AddItem(flash, 0.12)
	Debris:AddItem(anchor, 1.1)
end

local function renderBounceCounter(position, index, total)
	local gui = Instance.new("BillboardGui")
	gui.Name = "IceBounceCounterClient"
	gui.Size = UDim2.fromOffset(92, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 100
	gui.Adornee = nil
	gui.Parent = workspace
	local anchor = Instance.new("Part")
	anchor.Name = "IceBounceCounterAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Position = position
	anchor.Parent = workspace
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("ICE BOUNCE  %d/%d", index, total)
	label.TextColor3 = Color3.fromRGB(210, 250, 255)
	label.TextStrokeColor3 = Color3.fromRGB(25, 90, 150)
	label.TextStrokeTransparency = 0.15
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.Parent = gui
	TweenService:Create(label, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
	Debris:AddItem(gui, 0.35)
	Debris:AddItem(anchor, 0.35)
end

local function renderIceBounce(origin, endPosition, extra)
	if extra and extra.Index and extra.Total then
		renderBounceCounter(endPosition, extra.Index, extra.Total)
	end
	local midpoint = (origin + endPosition) * 0.5
	local direction = endPosition - origin
	local distance = direction.Magnitude
	if distance <= 0.05 then return end
	local anchor0 = Instance.new("Part")
	anchor0.Name = "IceBounceArcStart"
	anchor0.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor0.Transparency = 1
	anchor0.Anchored = true
	anchor0.CanCollide = false
	anchor0.CanTouch = false
	anchor0.CanQuery = false
	anchor0.Position = origin
	anchor0.Parent = workspace
	local anchor1 = anchor0:Clone()
	anchor1.Name = "IceBounceArcEnd"
	anchor1.Position = endPosition
	anchor1.Parent = workspace
	local attachment0 = Instance.new("Attachment")
	attachment0.Parent = anchor0
	local attachment1 = Instance.new("Attachment")
	attachment1.Parent = anchor1
	local beam = Instance.new("Beam")
	beam.Name = "IceBounceArc"
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(75, 205, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 115, 230))})
	beam.LightEmission = 0.9
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 0.16
	beam.Width1 = 0.08
	beam.CurveSize0 = math.clamp(distance * 0.25, 1.5, 5)
	beam.CurveSize1 = -math.clamp(distance * 0.25, 1.5, 5)
	beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.4)})
	beam.Parent = anchor0
	local projectile = Instance.new("Part")
	projectile.Name = "IceBounceProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(0.38, 0.38, 0.38)
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(190, 250, 255)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Position = origin
	projectile.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(85, 205, 255)
	light.Brightness = 1.8
	light.Range = 5
	light.Parent = projectile
	local travelTime = math.clamp(distance / 100, 0.08, 0.2)
	task.spawn(function()
		local started = os.clock()
		while projectile.Parent do
			local alpha = math.clamp((os.clock() - started) / travelTime, 0, 1)
			local arc = math.sin(alpha * math.pi) * math.clamp(distance * 0.25, 1.5, 5)
			projectile.Position = origin:Lerp(endPosition, alpha) + Vector3.new(0, arc, 0)
			if alpha >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		if projectile.Parent then
			emitIceCrystalBurst(endPosition, Color3.fromRGB(75, 205, 255))
			projectile:Destroy()
		end
		Debris:AddItem(anchor0, 0.18)
		Debris:AddItem(anchor1, 0.18)
	end)
end

local function renderFireProjectile(origin, endPosition)
	local level = getPerformanceLevel()
	local offset = endPosition - origin
	local distance = offset.Magnitude
	if distance <= 0.05 then
		return
	end
	local travelTime = math.clamp(distance / 105, 0.1, 0.26)
	local laser = Instance.new("Part")
	laser.Name = "FireAttackLaserClient"
	laser.Size = Vector3.new(0.24, 0.24, distance)
	laser.CFrame = CFrame.lookAt((origin + endPosition) * 0.5, endPosition)
	laser.Material = Enum.Material.Neon
	laser.Color = Color3.fromRGB(255, 92, 25)
	laser.Transparency = 0.08
	laser.Anchored = true
	laser.CanCollide = false
	laser.CanTouch = false
	laser.CanQuery = false
	laser.Parent = workspace
	Debris:AddItem(laser, math.min(0.2, travelTime + 0.04))
	local projectile = Instance.new("Part")
	projectile.Name = "FireProjectileClient"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(0.56, 0.56, 0.56)
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(255, 105, 18)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.CFrame = CFrame.new(origin)
	projectile.Parent = workspace
	local front = Instance.new("Attachment")
	front.Name = "FireTrailFront"
	front.Position = Vector3.new(0, 0, -0.24)
	front.Parent = projectile
	local back = Instance.new("Attachment")
	back.Name = "FireTrailBack"
	back.Position = Vector3.new(0, 0, 0.24)
	back.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Name = "FireEmberTrail"
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 115)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 90, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 12, 5)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.65, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = level >= 1 and 0.12 or 0.2
	trail.MinLength = 0.05
	trail.LightEmission = 0.9
	trail.FaceCamera = true
	trail.Parent = projectile
	local attachment = Instance.new("Attachment")
	attachment.Name = "FireProjectileParticles"
	attachment.Parent = projectile
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "EmberTrailParticles"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 110)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 85, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 15, 5)),
	})
	embers.LightEmission = 1
	embers.Lifetime = NumberRange.new(0.18, 0.42)
	embers.Rate = level >= 1 and 12 or 22
	embers.Speed = NumberRange.new(0.8, 2.8)
	embers.SpreadAngle = Vector2.new(35, 35)
	embers.Rotation = NumberRange.new(0, 360)
	embers.RotSpeed = NumberRange.new(-220, 220)
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.13),
		NumberSequenceKeypoint.new(0.45, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Parent = attachment
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ProjectileSmoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(75, 48, 38))
	smoke.Lifetime = NumberRange.new(0.35, 0.7)
	smoke.Rate = level >= 1 and 3 or 6
	smoke.Speed = NumberRange.new(0.2, 0.8)
	smoke.SpreadAngle = Vector2.new(35, 35)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.7, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = attachment
	local glow = Instance.new("PointLight")
	glow.Name = "FireProjectileGlow"
	glow.Color = Color3.fromRGB(255, 80, 15)
	glow.Brightness = 2.2
	glow.Range = 6
	glow.Shadows = false
	glow.Parent = projectile
	task.spawn(function()
		local started = os.clock()
		while projectile.Parent do
			local alpha = math.clamp((os.clock() - started) / travelTime, 0, 1)
			local position = origin:Lerp(endPosition, alpha)
			projectile.CFrame = CFrame.lookAt(position, endPosition)
			glow.Brightness = 0.8 + (1 - alpha) * 1.8
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		if projectile.Parent then
			embers.Enabled = false
			smoke.Enabled = false
			projectile:Destroy()
		end
	end)
end

local function renderLaser(orbName, origin, endPosition, extra)
	if orbName == "IceBounce" then
		renderIceBounce(origin, endPosition, extra)
		return
	end
	if orbName == "Fire" then
		renderFireProjectile(origin, endPosition)
		return
	end
	if orbName == "IceComet" then
		renderIceComet(origin, endPosition)
		return
	end
	if orbName == "Shadow" then
		renderShadowProjectile(origin, endPosition)
		emitShadowImpactBurst(endPosition)
		return
	end
	local orb = OrbConfig.GetOrb(orbName)
	if orbName == "IceBounce" then
		orb = OrbConfig.GetOrb("Ice")
	end
	if not orb or typeof(origin) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return
	end
	local distance = (endPosition - origin).Magnitude
	if distance <= 0.05 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "OrbLaserClient"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = orb.LaserMaterial
	part.Color = orb.LaserColor
	local width = orbName == "IceBounce" and orb.LaserWidth * 1.35 or orb.LaserWidth
	part.Size = Vector3.new(width, width, distance)
	part.CFrame = CFrame.lookAt((origin + endPosition) * 0.5, endPosition)
	part.Transparency = orbName == "IceBounce" and 0.02 or 0.1
	part.Parent = workspace
	Debris:AddItem(part, orbName == "IceBounce" and 0.14 or 0.08)
	if orbName == "IceBounce" then
		local flash = Instance.new("Part")
		flash.Name = "IceBounceFlashClient"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(0.45, 0.45, 0.45)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanTouch = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = orb.LaserColor
		flash.CFrame = CFrame.new(endPosition)
		flash.Parent = workspace
		Debris:AddItem(flash, 0.12)
		emitIceCrystalBurst(endPosition, orb.LaserColor)
	end
end

local function playImpactSound(orbName)
	local settings = IMPACT_SOUNDS[orbName]
	if not settings then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "OrbImpact_" .. orbName
	sound.SoundId = settings.Id
	sound.Volume = settings.Volume
	sound.PlaybackSpeed = settings.PlaybackSpeed
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 2)
end

local function playFireEffectSound(effectName)
	local settings = FIRE_EFFECT_SOUNDS[effectName]
	if not settings then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "FireOrbEffect_" .. effectName
	sound.SoundId = settings.Id
	sound.Volume = settings.Volume * (0.94 + math.random() * 0.12)
	sound.PlaybackSpeed = settings.PlaybackSpeed * (0.96 + math.random() * 0.08)
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 2)
end

local function triggerImpactFeedback()
	shakeRemaining = math.max(shakeRemaining, SHAKE_DURATION)
	shakeStrength = math.max(shakeStrength, SHAKE_MAGNITUDE)
	hitStopUntil = math.max(hitStopUntil, os.clock() + HIT_STOP_DURATION)
end

RunService:BindToRenderStep("OrbCombatFeedback", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	if not camera or not camera.Parent then
		camera = Workspace.CurrentCamera
	end
	if not camera then
		return
	end
	if os.clock() < hitStopUntil then
		if not hitStopCFrame then
			hitStopCFrame = camera.CFrame
		else
			camera.CFrame = hitStopCFrame
		end
		return
	end
	hitStopCFrame = nil
	if shakeRemaining <= 0 then
		shakeStrength = 0
		return
	end
	shakeRemaining = math.max(0, shakeRemaining - deltaTime)
	local fade = shakeRemaining / SHAKE_DURATION
	local offset = Vector3.new(
		(math.random() * 2 - 1) * shakeStrength * fade,
		(math.random() * 2 - 1) * shakeStrength * fade,
		0
	)
	camera.CFrame = camera.CFrame * CFrame.new(offset)
end)

attackConfirmed.OnClientEvent:Connect(function(_, orbName, origin, endPosition, extra)
	if orbName == "IceSlowField" then
		renderSlowField(origin, endPosition, extra)
		return
	elseif orbName == "IcePrison" then
		emitIceImpactBurst(origin, endPosition, true)
		emitIcePrisonCage(origin, endPosition)
		return
	elseif orbName == "IceShatter" then
		emitIceImpactBurst(origin, 3, false)
		emitIceCrystalBurst(origin, Color3.fromRGB(220, 250, 255))
		return
	elseif orbName == "FireAreaExplosion" then
		emitFireAreaExplosion(origin, endPosition)
		playFireEffectSound("AreaExplosion")
		triggerImpactFeedback()
		return
	elseif orbName == "FireBurnStart" then
		emitEnemyImpactVisual(origin, Color3.fromRGB(255, 105, 20), 1.4)
		playFireEffectSound("BurnStart")
		return
	elseif orbName == "FireBurnSpread" then
		emitEnemyImpactVisual(endPosition, Color3.fromRGB(255, 145, 25), 1.2)
		emitFireBurnSpread(origin, endPosition)
		playFireEffectSound("BurnSpread")
		return
	elseif orbName == "FireExecute" then
		emitFireExecute(origin)
		playFireEffectSound("Execute")
		triggerImpactFeedback()
		return
	elseif orbName == "FireNebula" then
		emitFireNebula(origin, endPosition)
		playFireEffectSound("Nebula")
		triggerImpactFeedback()
		return
	end
	renderLaser(orbName, origin, endPosition, extra)
	if orbName == "Ice" then
		emitIceImpactBurst(endPosition, 3, false)
	elseif orbName == "Shadow" then
		emitEnemyImpactVisual(endPosition, Color3.fromRGB(190, 70, 255), 1.35)
	end
	playImpactSound(orbName)
	triggerImpactFeedback()
end)

print("[OrbCombatClient] Automatic laser renderer ready")