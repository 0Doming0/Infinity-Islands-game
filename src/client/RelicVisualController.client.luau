-- Efeitos visuais locais para todas as reliquias do MVP.
-- O dano e os estados continuam sendo controlados pelo servidor em RelicService.
--
-- Efeitos personalizados opcionais:
-- ReplicatedStorage/RelicVisuals/<RelicId>/SwordEffect
-- ReplicatedStorage/RelicVisuals/<RelicId>/EnemyEffect
--
-- SwordEffect e EnemyEffect podem ser Attachments, ParticleEmitters, luzes,
-- Highlights ou pastas contendo esses objetos. Quando um efeito personalizado
-- existe, ele substitui o efeito padrao correspondente.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))

local TARGET_TAG = "CombatTarget"
local REFRESH_INTERVAL = 0.35
local RUNTIME_ATTRIBUTE = "RelicVisualRuntime"
local RUNTIME_STATE_ATTRIBUTE = "RelicVisualState"
local SWORD_EFFECT_NAME = "__RelicSwordEffect"
local TARGET_EFFECT_PREFIX = "__RelicTargetEffect_"

local RELIC_IDS = {
	Lightning = "LightningRelic",
	Fire = "FireRelic",
	Ice = "IceRelic",
	Stone = "StoneRelic",
}

local targetConnections = setmetatable({}, { __mode = "k" })
local lastSwordRelic = setmetatable({}, { __mode = "k" })
local runtimeInstances = setmetatable({}, { __mode = "k" })
local localPlayer = Players.LocalPlayer
local applyRuntimeQualityToInstance

local function getPerformanceLevel()
	return tonumber(localPlayer:GetAttribute("PerformanceLevel")) or 0
end

local function getParticleMultiplier()
	local level = getPerformanceLevel()
	if level >= 2 then
		return 0.18
	elseif level >= 1 then
		return 0.55
	end
	return 1
end

local function markRuntime(instance, stateName)
	instance:SetAttribute(RUNTIME_ATTRIBUTE, true)
	if stateName then
		instance:SetAttribute(RUNTIME_STATE_ATTRIBUTE, stateName)
	end
	runtimeInstances[instance] = true
	if applyRuntimeQualityToInstance then
		applyRuntimeQualityToInstance(instance)
	end
	return instance
end

applyRuntimeQualityToInstance = function(instance)
	if not instance or not instance.Parent then
		return
	end

	local level = getPerformanceLevel()
	if instance:IsA("ParticleEmitter") then
		local originalRate = instance:GetAttribute("RelicVisualOriginalRate")
		if typeof(originalRate) ~= "number" then
			originalRate = instance.Rate
			instance:SetAttribute("RelicVisualOriginalRate", originalRate)
			instance:SetAttribute("RelicVisualOriginalEnabled", instance.Enabled)
		end
		local originalEnabled = instance:GetAttribute("RelicVisualOriginalEnabled") ~= false
		instance.Enabled = originalEnabled
		instance.Rate = originalRate * getParticleMultiplier()
	elseif instance:IsA("Light") then
		local originalBrightness = instance:GetAttribute("RelicVisualOriginalBrightness")
		if typeof(originalBrightness) ~= "number" then
			originalBrightness = instance.Brightness
			instance:SetAttribute("RelicVisualOriginalBrightness", originalBrightness)
			instance:SetAttribute("RelicVisualOriginalEnabled", instance.Enabled)
		end
		local originalEnabled = instance:GetAttribute("RelicVisualOriginalEnabled") ~= false
		instance.Enabled = originalEnabled and level < 2
		instance.Brightness = originalBrightness * (level >= 1 and 0.5 or 1)
	elseif instance:IsA("Beam") or instance:IsA("Trail") then
		if instance:GetAttribute("RelicVisualOriginalEnabled") == nil then
			instance:SetAttribute("RelicVisualOriginalEnabled", instance.Enabled)
		end
		instance.Enabled =
			instance:GetAttribute("RelicVisualOriginalEnabled") ~= false
			and level < 2
	end
end

local function applyRuntimeQuality()
	for instance in pairs(runtimeInstances) do
		if not instance.Parent then
			runtimeInstances[instance] = nil
		else
			applyRuntimeQualityToInstance(instance)
		end
	end
end

local function destroyRuntimeChildren(root, stateName)
	if not root then
		return
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			descendant:GetAttribute(RUNTIME_ATTRIBUTE) == true
			and (not stateName or descendant:GetAttribute(RUNTIME_STATE_ATTRIBUTE) == stateName)
		then
			descendant:Destroy()
		end
	end
end

local function hasRuntimeState(root, stateName)
	if not root then
		return false
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			descendant:GetAttribute(RUNTIME_ATTRIBUTE) == true
			and descendant:GetAttribute(RUNTIME_STATE_ATTRIBUTE) == stateName
		then
			return true
		end
	end
	return false
end

local function findEffectPart(root)
	if not root then
		return nil
	end
	local preferredNames = {
		"Blade",
		"Lamina",
		"Lâmina",
		"SwordBlade",
		"Espada",
		"Handle",
		"HumanoidRootPart",
	}
	for _, name in ipairs(preferredNames) do
		local candidate = root:FindFirstChild(name, true)
		if candidate and candidate:IsA("BasePart") then
			return candidate
		end
	end
	if root:IsA("BasePart") then
		return root
	end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function isSwordTool(instance)
	return instance
		and instance:IsA("Tool")
		and (
			instance.Name == "ClassicSword"
			or instance:GetAttribute("IsSword") == true
			or instance:GetAttribute("WeaponType") == "Sword"
		)
end

local function getTemplate(relicId, effectName)
	local visuals = ReplicatedStorage:FindFirstChild("RelicVisuals")
	local relicFolder = visuals and visuals:FindFirstChild(relicId)
	return relicFolder and relicFolder:FindFirstChild(effectName) or nil
end

local function cloneCustomObject(source, hostPart, hostModel, stateName, fallbackAttachment, results)
	if source:IsA("Folder") or source:IsA("Configuration") then
		for _, child in ipairs(source:GetChildren()) do
			cloneCustomObject(child, hostPart, hostModel, stateName, fallbackAttachment, results)
		end
		return
	end

	local clone = source:Clone()
	clone.Name = string.format("%s%s_%s", TARGET_EFFECT_PREFIX, stateName, source.Name)
	markRuntime(clone, stateName)

	if clone:IsA("Highlight") then
		clone.Adornee = hostModel
		clone.Parent = hostModel
	elseif clone:IsA("Attachment") then
		clone.Parent = hostPart
	elseif clone:IsA("ParticleEmitter") or clone:IsA("Beam") or clone:IsA("Trail") then
		clone.Parent = fallbackAttachment
	elseif clone:IsA("Light") then
		clone.Parent = hostPart
	else
		clone.Parent = hostPart
	end
	applyRuntimeQualityToInstance(clone)

	table.insert(results, clone)
end

local function installCustomEffect(template, hostPart, hostModel, stateName)
	if not template or not hostPart then
		return false, {}
	end

	local results = {}
	local fallbackAttachment = Instance.new("Attachment")
	fallbackAttachment.Name = TARGET_EFFECT_PREFIX .. stateName .. "_CustomHost"
	markRuntime(fallbackAttachment, stateName)
	fallbackAttachment.Parent = hostPart
	table.insert(results, fallbackAttachment)

	cloneCustomObject(template, hostPart, hostModel, stateName, fallbackAttachment, results)
	if #fallbackAttachment:GetChildren() == 0 then
		fallbackAttachment:Destroy()
	end
	return true, results
end

local function newEmitter(parent, properties)
	local emitter = Instance.new("ParticleEmitter")
	for key, value in pairs(properties) do
		emitter[key] = value
	end
	emitter.Parent = parent
	markRuntime(emitter, parent:GetAttribute(RUNTIME_STATE_ATTRIBUTE))
	applyRuntimeQualityToInstance(emitter)
	return emitter
end

local function newLight(parent, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	markRuntime(light, parent:GetAttribute(RUNTIME_STATE_ATTRIBUTE))
	applyRuntimeQualityToInstance(light)
	return light
end

local function createSwordDefault(relicId, blade)
	local attachment = Instance.new("Attachment")
	attachment.Name = SWORD_EFFECT_NAME
	markRuntime(attachment, "Sword")
	attachment.Parent = blade

	if relicId == RELIC_IDS.Lightning then
		newEmitter(attachment, {
			Name = "ElectricSparks",
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 239, 77), Color3.fromRGB(117, 213, 255)),
			LightEmission = 1,
			Lifetime = NumberRange.new(0.08, 0.20),
			Rate = 28,
			Speed = NumberRange.new(1.5, 4),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 2, 0),
			Drag = 3,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.17),
				NumberSequenceKeypoint.new(0.35, 0.08),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
		newLight(attachment, Color3.fromRGB(255, 231, 72), 1.1, 7)
	elseif relicId == RELIC_IDS.Fire then
		newEmitter(attachment, {
			Name = "Flames",
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 238, 102)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 105, 30)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(145, 24, 8)),
			}),
			LightEmission = 0.75,
			Lifetime = NumberRange.new(0.22, 0.42),
			Rate = 24,
			Speed = NumberRange.new(1.2, 2.8),
			SpreadAngle = Vector2.new(16, 16),
			Acceleration = Vector3.new(0, 5, 0),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.24),
				NumberSequenceKeypoint.new(0.45, 0.38),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
		newEmitter(attachment, {
			Name = "Embers",
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 194, 61), Color3.fromRGB(255, 68, 20)),
			LightEmission = 1,
			Lifetime = NumberRange.new(0.25, 0.65),
			Rate = 10,
			Speed = NumberRange.new(1, 3.5),
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = Vector3.new(0, 4, 0),
			Size = NumberSequence.new(0.07),
		})
		newLight(attachment, Color3.fromRGB(255, 91, 30), 1.25, 8)
	elseif relicId == RELIC_IDS.Ice then
		newEmitter(attachment, {
			Name = "Frost",
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(235, 255, 255), Color3.fromRGB(80, 195, 255)),
			LightEmission = 0.9,
			Lifetime = NumberRange.new(0.3, 0.7),
			Rate = 18,
			Speed = NumberRange.new(0.3, 1.8),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -1.5, 0),
			Drag = 2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.12),
				NumberSequenceKeypoint.new(0.6, 0.18),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
		newLight(attachment, Color3.fromRGB(111, 220, 255), 0.9, 7)
	elseif relicId == RELIC_IDS.Stone then
		newEmitter(attachment, {
			Name = "StoneDust",
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(198, 166, 119), Color3.fromRGB(87, 70, 52)),
			LightEmission = 0.05,
			Lifetime = NumberRange.new(0.22, 0.5),
			Rate = 9,
			Speed = NumberRange.new(0.4, 1.6),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -2.5, 0),
			Drag = 4,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-55, 55),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.55, 0.22),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
		newLight(attachment, Color3.fromRGB(197, 151, 96), 0.45, 5)
	end
end

local function applySwordEffect(swordRoot, relicId)
	local blade = findEffectPart(swordRoot)
	if not blade then
		return
	end

	local currentRelic = lastSwordRelic[swordRoot]
	if currentRelic == relicId and hasRuntimeState(swordRoot, "Sword") then
		return
	end

	destroyRuntimeChildren(swordRoot, "Sword")
	lastSwordRelic[swordRoot] = relicId
	if not RelicCatalog.Get(relicId) then
		return
	end

	local custom = getTemplate(relicId, "SwordEffect")
	local installed = custom and installCustomEffect(custom, blade, swordRoot, "Sword")
	if not installed then
		createSwordDefault(relicId, blade)
	end
end

local function newTargetAttachment(rootPart, stateName)
	local attachment = Instance.new("Attachment")
	attachment.Name = TARGET_EFFECT_PREFIX .. stateName
	markRuntime(attachment, stateName)
	attachment.Parent = rootPart
	return attachment
end

local function newTargetHighlight(model, stateName, fillColor, outlineColor, fillTransparency)
	local highlight = Instance.new("Highlight")
	highlight.Name = TARGET_EFFECT_PREFIX .. stateName .. "_Highlight"
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = fillColor
	highlight.FillTransparency = fillTransparency
	highlight.OutlineColor = outlineColor
	highlight.OutlineTransparency = 0.15
	markRuntime(highlight, stateName)
	highlight.Parent = model
	return highlight
end

local function createFireTarget(model, rootPart)
	local stateName = "Fire"
	if getTemplate(RELIC_IDS.Fire, "EnemyEffect") then
		installCustomEffect(getTemplate(RELIC_IDS.Fire, "EnemyEffect"), rootPart, model, stateName)
		return
	end
	local attachment = newTargetAttachment(rootPart, stateName)
	newEmitter(attachment, {
		Name = "BurningFlames",
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 224, 80), Color3.fromRGB(230, 42, 12)),
		LightEmission = 0.8,
		Lifetime = NumberRange.new(0.28, 0.55),
		Rate = 38,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 7, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.45, 0.65),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
	newEmitter(attachment, {
		Name = "BurningEmbers",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 205, 65), Color3.fromRGB(255, 65, 18)),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.35, 0.85),
		Rate = 16,
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, 4, 0),
		Size = NumberSequence.new(0.09),
	})
	newLight(attachment, Color3.fromRGB(255, 85, 25), 1.8, 10)
	newTargetHighlight(model, stateName, Color3.fromRGB(255, 85, 20), Color3.fromRGB(255, 191, 75), 0.82)
end

local function createIceTarget(model, rootPart)
	local stateName = "Ice"
	if getTemplate(RELIC_IDS.Ice, "EnemyEffect") then
		installCustomEffect(getTemplate(RELIC_IDS.Ice, "EnemyEffect"), rootPart, model, stateName)
		return
	end
	local attachment = newTargetAttachment(rootPart, stateName)
	newEmitter(attachment, {
		Name = "FrozenMist",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 255, 255), Color3.fromRGB(73, 178, 255)),
		LightEmission = 0.55,
		Lifetime = NumberRange.new(0.45, 0.9),
		Rate = 22,
		Speed = NumberRange.new(0.4, 2),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -0.7, 0),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-35, 35),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.7, 0.75),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.58),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	newEmitter(attachment, {
		Name = "IceCrystals",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(90, 207, 255)),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.35, 0.7),
		Rate = 18,
		Speed = NumberRange.new(0.5, 2.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -1.5, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.16),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
	newLight(attachment, Color3.fromRGB(98, 205, 255), 1.25, 9)
	newTargetHighlight(model, stateName, Color3.fromRGB(92, 205, 255), Color3.fromRGB(220, 252, 255), 0.6)
end

local function createStoneChargeTarget(model, rootPart)
	local stateName = "StoneCharge"
	if getTemplate(RELIC_IDS.Stone, "EnemyEffect") then
		installCustomEffect(getTemplate(RELIC_IDS.Stone, "EnemyEffect"), rootPart, model, stateName)
		return
	end
	local attachment = newTargetAttachment(rootPart, stateName)
	newEmitter(attachment, {
		Name = "ChargedStoneDust",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(226, 188, 127), Color3.fromRGB(92, 70, 45)),
		LightEmission = 0.15,
		Lifetime = NumberRange.new(0.3, 0.65),
		Rate = 15,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -3, 0),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-80, 80),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.6, 0.38),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
	newLight(attachment, Color3.fromRGB(205, 157, 95), 0.75, 7)
	newTargetHighlight(model, stateName, Color3.fromRGB(133, 101, 67), Color3.fromRGB(235, 193, 122), 0.8)
end

local function reconcilePersistentTargetState(model, stateName, active, createEffect)
	local existing = hasRuntimeState(model, stateName)

	if active and not existing then
		local rootPart = findEffectPart(model)
		if rootPart then
			createEffect(model, rootPart)
		end
	elseif not active and existing then
		destroyRuntimeChildren(model, stateName)
	end
end

local function refreshTarget(model)
	if not model or not model.Parent then
		return
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local alive = not humanoid or humanoid.Health > 0
	reconcilePersistentTargetState(
		model,
		"Fire",
		alive and model:GetAttribute("RelicBurning") == true,
		createFireTarget
	)
	reconcilePersistentTargetState(
		model,
		"Ice",
		alive and model:GetAttribute("RelicFrozen") == true,
		createIceTarget
	)
	reconcilePersistentTargetState(
		model,
		"StoneCharge",
		alive and typeof(model:GetAttribute("StoneRelicChargedBy")) == "number",
		createStoneChargeTarget
	)
end

local function createBurstAnchor(position, color, stateName)
	local anchor = Instance.new("Part")
	anchor.Name = TARGET_EFFECT_PREFIX .. stateName .. "_Burst"
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.new(0.22, 0.22, 0.22)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Material = Enum.Material.Neon
	anchor.Color = color
	anchor.Transparency = 0.2
	markRuntime(anchor, stateName)
	anchor.Parent = workspace
	Debris:AddItem(anchor, 0.75)
	return anchor
end

local function emitDefaultProc(model, effect)
	local rootPart = findEffectPart(model)
	if not rootPart then
		return
	end

	local relicId = effect .. "Relic"
	local custom = getTemplate(relicId, "EnemyEffect")
	if custom and effect ~= "Fire" and effect ~= "Ice" then
		local _, clones = installCustomEffect(custom, rootPart, model, "Proc_" .. effect)
		task.delay(0.8, function()
			for _, clone in ipairs(clones) do
				if clone.Parent then
					clone:Destroy()
				end
			end
		end)
		for _, clone in ipairs(clones) do
			if clone:IsA("ParticleEmitter") then
				local originalRate =
					tonumber(clone:GetAttribute("RelicVisualOriginalRate"))
					or clone.Rate
				clone:Emit(
					math.max(3, math.floor(originalRate * 0.4 * getParticleMultiplier()))
				)
			end
		end
		return
	end

	local color = Color3.fromRGB(255, 255, 255)
	local particleCount = 18
	if effect == "Lightning" then
		color = Color3.fromRGB(255, 235, 65)
		particleCount = 34
	elseif effect == "Stone" then
		color = Color3.fromRGB(188, 145, 92)
		particleCount = 26
	elseif effect == "Ice" then
		color = Color3.fromRGB(111, 222, 255)
	elseif effect == "Fire" then
		color = Color3.fromRGB(255, 86, 25)
	end

	local anchor = createBurstAnchor(rootPart.Position, color, "Proc_" .. effect)
	local emitter = newEmitter(anchor, {
		Name = effect .. "ProcBurst",
		Texture = effect == "Stone"
			and "rbxasset://textures/particles/smoke_main.dds"
			or "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(color),
		LightEmission = effect == "Stone" and 0.15 or 1,
		Lifetime = NumberRange.new(0.14, 0.38),
		Rate = 0,
		Speed = effect == "Lightning" and NumberRange.new(12, 24) or NumberRange.new(7, 15),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = effect == "Stone" and Vector3.new(0, -18, 0) or Vector3.zero,
		Drag = effect == "Lightning" and 2 or 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-150, 150),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, effect == "Stone" and 0.32 or 0.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
	emitter:Emit(math.max(4, math.floor(particleCount * getParticleMultiplier() + 0.5)))
	local light = newLight(anchor, color, effect == "Lightning" and 3.5 or 2.2, effect == "Lightning" and 14 or 10)
	TweenService:Create(light, TweenInfo.new(0.28), { Brightness = 0, Range = 2 }):Play()
	TweenService:Create(anchor, TweenInfo.new(0.22), { Transparency = 1, Size = Vector3.new(1.2, 1.2, 1.2) }):Play()
end

local function watchTarget(model)
	if targetConnections[model] or not model:IsA("Model") then
		return
	end
	local connections = {}
	targetConnections[model] = connections

	for _, attributeName in ipairs({ "RelicBurning", "RelicFrozen", "StoneRelicChargedBy" }) do
		table.insert(connections, model:GetAttributeChangedSignal(attributeName):Connect(function()
			refreshTarget(model)
		end))
	end
	table.insert(connections, model:GetAttributeChangedSignal("LastRelicEffectAt"):Connect(function()
		local effect = model:GetAttribute("LastRelicEffect")
		if type(effect) == "string" then
			emitDefaultProc(model, effect)
		end
	end))
	table.insert(connections, model.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		targetConnections[model] = nil
	end))

	refreshTarget(model)
end

local function clearCharacterSwordEffects(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:GetAttribute(RUNTIME_ATTRIBUTE) == true and descendant:GetAttribute(RUNTIME_STATE_ATTRIBUTE) == "Sword" then
			descendant:Destroy()
		end
	end
end

local function refreshPlayerSwords(player)
	local character = player.Character
	if not character then
		return
	end
	local relicId = player:GetAttribute("EquippedRelic")
	if type(relicId) ~= "string" or not RelicCatalog.Get(relicId) then
		clearCharacterSwordEffects(character)
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if isSwordTool(child) then
			applySwordEffect(child, relicId)
		elseif child:IsA("Model") and child.Name == "EquippedSwordBackDisplay" then
			applySwordEffect(child, relicId)
		end
	end
end

CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(watchTarget)
for _, model in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
	watchTarget(model)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	accumulator += deltaTime
	local performanceLevel = getPerformanceLevel()
	local refreshInterval = performanceLevel >= 2
		and 0.8
		or (performanceLevel >= 1 and 0.55 or REFRESH_INTERVAL)
	if accumulator < refreshInterval then
		return
	end
	accumulator = 0

	for _, player in ipairs(Players:GetPlayers()) do
		refreshPlayerSwords(player)
	end
	for model in pairs(targetConnections) do
		refreshTarget(model)
	end
end)

localPlayer:GetAttributeChangedSignal("PerformanceLevel"):Connect(applyRuntimeQuality)
