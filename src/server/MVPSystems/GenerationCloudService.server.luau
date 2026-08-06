--[[
	Sky Dungeon - GenerationCloudService

	Cria uma camada de nuvens acima do último round disponível para esconder
	a geração procedural. Quando HighestGeneratedY aumenta, a camada antiga
	se dissolve e reaparece acima do novo limite do mapa.

	Não exige alterações no ChunkManager.
]]

local TweenService = game:GetService("TweenService")

local BlockParkourFolder = script.Parent.Parent:WaitForChild("BlockParkour")
local MapConfig = require(BlockParkourFolder:WaitForChild("Config_SkyDungeon_V10"))

if not MapConfig.ENABLE_DYNAMIC_CHUNKS then
	return
end

local CONFIG = {
	MODEL_NAME = "GenerationClouds",

	-- Tempo máximo para esperar o mundo procedural começar.
	STARTUP_TIMEOUT_SECONDS = 45,

	-- Tamanho da cobertura.
	MIN_COVERAGE_SIZE = 720,
	COVERAGE_PADDING_STUDS = 160,

	-- Posição das nuvens em relação ao topo do round.
	CLOUD_BASE_OFFSET_STUDS = -18,

	-- Camadas sobrepostas para não deixar buracos.
	LAYER_OFFSETS = {
		-12,
	0,
	12,
	24,
	},

	LAYER_THICKNESS = 12,

	LAYER_TRANSPARENCIES = {
	0.48,
	0.56,
	0.64,
	0.73,
},

LAYER_COLORS = {
	Color3.fromRGB(195, 210, 220),
	Color3.fromRGB(210, 222, 231),
	Color3.fromRGB(225, 234, 240),
	Color3.fromRGB(238, 243, 247),
},

PARTICLE_RATES = {
	14,
	11,
	8,
	5,
},

DRIFT_DISTANCES = {
	14,
	19,
	11,
	16,
},

DRIFT_SPEEDS = {
	0.08,
	-0.055,
	0.04,
	-0.032,
},

ROTATION_SPEEDS = {
	0.35,
	-0.22,
	0.16,
	-0.1,
}, CURTAIN_ENABLED = true,
CURTAIN_HEIGHT = 80,
CURTAIN_THICKNESS = 10,
CURTAIN_TRANSPARENCY = 0.54,
CURTAIN_OFFSET_STUDS = -5,

	FADE_OUT_TIME = 2.4,
	FADE_IN_TIME = 1.35,
	PARTICLE_CLEAR_DELAY = 0.75,

    FOG_CORE_ENABLED = true,

-- Procura um trecho da rota principal próximo do topo atual para ancorar o bloco.
FOG_CORE_ROUTE_SEARCH_BELOW_STUDS = 42,

-- Posição do bloco em relação à superfície da rota principal encontrada.
FOG_CORE_OFFSET_Y = 12,

-- Tamanho do "miolo" de névoa.
FOG_CORE_WIDTH = 150,
FOG_CORE_DEPTH = 150,
FOG_CORE_HEIGHT = 24,

-- Aparência.
FOG_CORE_COLOR = Color3.fromRGB(226, 234, 240),
FOG_CORE_TRANSPARENCY = 0.34,

-- Textura para disfarçar bem.
FOG_CORE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds",
FOG_CORE_TEXTURE_TRANSPARENCY = 0.52,
FOG_CORE_TEXTURE_STUDS_PER_TILE = 24,

-- Partículas suaves para misturar com o restante.
FOG_CORE_PARTICLE_RATE = 10,

	-- Parede invisível que impede o jogador de passar da área gerada.
	BLOCK_PLAYER_PROGRESS = true,
	BARRIER_OFFSET_STUDS = 10,
	BARRIER_THICKNESS = 6,

	PRINT_DEBUG = true,
}

local coverageSize = math.max(
	CONFIG.MIN_COVERAGE_SIZE,
	MapConfig.MAX_RADIUS_STUDS * 2 + CONFIG.COVERAGE_PADDING_STUDS
)

local worldCenter = MapConfig.CENTER_WORLD

local cloudModel
local visualsFolder
local barrier
local layers = {}
local curtains = {}
local fogCore

local visualHighestY = MapConfig.CENTER_WORLD.Y
local pendingHighestY
local revealBusy = false
local shuttingDown = false

local function debugPrint(message)
	if CONFIG.PRINT_DEBUG then
		print("[GenerationClouds] " .. message)
	end
end

local function createParticleEmitter(parent, layerIndex)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CloudMist"

	-- Textura interna do Roblox; não exige upload de asset.
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"

	emitter.Rate = CONFIG.PARTICLE_RATES[layerIndex]
	emitter.Lifetime = NumberRange.new(8, 12)
	emitter.Speed = NumberRange.new(0.4, 1.3)
	emitter.Drag = 0.8

	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-4, 4)

	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.EmissionDirection = Enum.NormalId.Top

	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 34),
		NumberSequenceKeypoint.new(0.4, 62),
		NumberSequenceKeypoint.new(1, 88),
	})

	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.42),
		NumberSequenceKeypoint.new(0.72, 0.56),
		NumberSequenceKeypoint.new(1, 1),
	})

	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CONFIG.LAYER_COLORS[layerIndex]),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(248, 250, 252)),
	})

	emitter.LightInfluence = 0.75
	emitter.LightEmission = 0.05
	emitter.LockedToPart = false

	-- Espalha as partículas por toda a área da camada.
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward

	emitter:SetAttribute(
		"VisibleRate",
		CONFIG.PARTICLE_RATES[layerIndex]
	)

	emitter.Parent = parent

	return emitter
end

local function getLayerPosition(highestY, layerIndex)
	local baseY = highestY + CONFIG.CLOUD_BASE_OFFSET_STUDS

	return Vector3.new(
		worldCenter.X,
		baseY + CONFIG.LAYER_OFFSETS[layerIndex],
		worldCenter.Z
	)
end

local function createCloudLayer(layerIndex, highestY)
	local layer = Instance.new("Part")
	layer.Name = string.format("CloudLayer_%02d", layerIndex)

	layer.Size = Vector3.new(
		coverageSize,
		CONFIG.LAYER_THICKNESS,
		coverageSize
	)

	layer.Anchored = true
	layer.CanCollide = false
	layer.CanTouch = false
	layer.CanQuery = false
	layer.CastShadow = false
	layer.Locked = true

	layer.Material = Enum.Material.SmoothPlastic
	layer.Color = CONFIG.LAYER_COLORS[layerIndex]
	layer.Transparency = CONFIG.LAYER_TRANSPARENCIES[layerIndex]

	local origin = getLayerPosition(highestY, layerIndex)

	layer.CFrame = CFrame.new(origin)

	layer:SetAttribute("IsGenerationCloudLayer", true)
	layer:SetAttribute("LayerIndex", layerIndex)
	layer:SetAttribute("CloudOriginPosition", origin)

	layer:SetAttribute(
		"VisibleTransparency",
		CONFIG.LAYER_TRANSPARENCIES[layerIndex]
	)

	layer:SetAttribute(
		"DriftDistance",
		CONFIG.DRIFT_DISTANCES[layerIndex]
	)

	layer:SetAttribute(
		"DriftSpeed",
		CONFIG.DRIFT_SPEEDS[layerIndex]
	)

	layer:SetAttribute(
		"RotationSpeed",
		CONFIG.ROTATION_SPEEDS[layerIndex]
	)

	layer:SetAttribute(
		"DriftPhase",
		(layerIndex - 1) * math.pi * 0.73
	)

	createParticleEmitter(layer, layerIndex)

	layer.Parent = visualsFolder

	return layer
end

local function createBarrier(highestY)
	local blocker = Instance.new("Part")
	blocker.Name = "GenerationBarrier"

	blocker.Size = Vector3.new(
		coverageSize,
		CONFIG.BARRIER_THICKNESS,
		coverageSize
	)

	blocker.Anchored = true
	blocker.Transparency = 1
	blocker.CastShadow = false

	blocker.CanCollide = CONFIG.BLOCK_PLAYER_PROGRESS
	blocker.CanTouch = false
	blocker.CanQuery = false
	blocker.Locked = true

	blocker.Position = Vector3.new(
		worldCenter.X,
		highestY + CONFIG.BARRIER_OFFSET_STUDS,
		worldCenter.Z
	)

	blocker:SetAttribute("IsGenerationBarrier", true)
	blocker.Parent = cloudModel

	return blocker
end

local function createFogCurtains(highestY)
	table.clear(curtains)

	if not CONFIG.CURTAIN_ENABLED then
		return
	end

	local curtainY =
		highestY
		+ CONFIG.CURTAIN_OFFSET_STUDS
		- CONFIG.CURTAIN_HEIGHT / 2

	local curtainDefinitions = {
		{
			name = "CurtainNorth",
			size = Vector3.new(
				coverageSize,
				CONFIG.CURTAIN_HEIGHT,
				CONFIG.CURTAIN_THICKNESS
			),
			position = Vector3.new(
				worldCenter.X,
				curtainY,
				worldCenter.Z - coverageSize / 2
			),
		},
		{
			name = "CurtainSouth",
			size = Vector3.new(
				coverageSize,
				CONFIG.CURTAIN_HEIGHT,
				CONFIG.CURTAIN_THICKNESS
			),
			position = Vector3.new(
				worldCenter.X,
				curtainY,
				worldCenter.Z + coverageSize / 2
			),
		},
		{
			name = "CurtainWest",
			size = Vector3.new(
				CONFIG.CURTAIN_THICKNESS,
				CONFIG.CURTAIN_HEIGHT,
				coverageSize
			),
			position = Vector3.new(
				worldCenter.X - coverageSize / 2,
				curtainY,
				worldCenter.Z
			),
		},
		{
			name = "CurtainEast",
			size = Vector3.new(
				CONFIG.CURTAIN_THICKNESS,
				CONFIG.CURTAIN_HEIGHT,
				coverageSize
			),
			position = Vector3.new(
				worldCenter.X + coverageSize / 2,
				curtainY,
				worldCenter.Z
			),
		},
	}

	for _, definition in ipairs(curtainDefinitions) do
		local curtain = Instance.new("Part")
		curtain.Name = definition.name
		curtain.Size = definition.size
		curtain.Position = definition.position

		curtain.Anchored = true
		curtain.CanCollide = false
		curtain.CanTouch = false
		curtain.CanQuery = false
		curtain.CastShadow = false

		curtain.Material = Enum.Material.SmoothPlastic
		curtain.Color = Color3.fromRGB(211, 224, 233)
		curtain.Transparency = CONFIG.CURTAIN_TRANSPARENCY

		curtain:SetAttribute("IsGenerationCloudCurtain", true)
		curtain:SetAttribute(
			"VisibleTransparency",
			CONFIG.CURTAIN_TRANSPARENCY
		)

		curtain.Parent = visualsFolder

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "CurtainMist"
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Rate = 10
		emitter.Lifetime = NumberRange.new(7, 11)
		emitter.Speed = NumberRange.new(0.2, 0.8)
		emitter.Drag = 1
		emitter.SpreadAngle = Vector2.new(180, 180)

		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 22),
			NumberSequenceKeypoint.new(0.5, 48),
			NumberSequenceKeypoint.new(1, 68),
		})

		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.35),
			NumberSequenceKeypoint.new(0.8, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})

		emitter:SetAttribute("VisibleRate", 10)
		emitter.Parent = curtain

		table.insert(curtains, curtain)
	end
end

local function findFogCoreAnchorPosition(highestY)
	local generatedWorld = workspace:FindFirstChild(MapConfig.WORLD_MODEL_NAME, true)

	if not generatedWorld then
		return Vector3.new(worldCenter.X, highestY + CONFIG.FOG_CORE_OFFSET_Y, worldCenter.Z)
	end

	local bestPart
	local bestSurfaceY = -math.huge
	local minimumSurfaceY = highestY - CONFIG.FOG_CORE_ROUTE_SEARCH_BELOW_STUDS
	local maximumSurfaceY = highestY + 10

	for _, descendant in ipairs(generatedWorld:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("IsMainRoute") == true then
			local surfaceY = descendant.Position.Y + descendant.Size.Y / 2

			if surfaceY >= minimumSurfaceY and surfaceY <= maximumSurfaceY then
				if surfaceY > bestSurfaceY then
					bestPart = descendant
					bestSurfaceY = surfaceY
				end
			end
		end
	end

	if bestPart then
		return Vector3.new(
			bestPart.Position.X,
			bestSurfaceY + CONFIG.FOG_CORE_OFFSET_Y,
			bestPart.Position.Z
		)
	end

	return Vector3.new(worldCenter.X, highestY + CONFIG.FOG_CORE_OFFSET_Y, worldCenter.Z)
end

local function addFogCoreTextures(part)
	local faces = {
		Enum.NormalId.Top,
		Enum.NormalId.Bottom,
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	}

	for _, face in ipairs(faces) do
		local texture = Instance.new("Texture")
		texture.Name = "FogCoreTexture"
		texture.Face = face
		texture.Texture = CONFIG.FOG_CORE_TEXTURE
		texture.Transparency = CONFIG.FOG_CORE_TEXTURE_TRANSPARENCY
		texture.StudsPerTileU = CONFIG.FOG_CORE_TEXTURE_STUDS_PER_TILE
		texture.StudsPerTileV = CONFIG.FOG_CORE_TEXTURE_STUDS_PER_TILE
		texture.Parent = part
	end
end

local function createFogCore(highestY)
	

	if not CONFIG.FOG_CORE_ENABLED then
		return
	end

	local anchorPosition = findFogCoreAnchorPosition(highestY)

	fogCore = Instance.new("Part")
	fogCore.Name = "FogCoreBlock"
	fogCore.Size = Vector3.new(
		CONFIG.FOG_CORE_WIDTH,
		CONFIG.FOG_CORE_HEIGHT,
		CONFIG.FOG_CORE_DEPTH
	)

	fogCore.Position = anchorPosition
	fogCore.Anchored = true
	fogCore.CanCollide = false
	fogCore.CanTouch = false
	fogCore.CanQuery = false
	fogCore.CastShadow = false
	fogCore.Locked = true

	fogCore.Material = Enum.Material.SmoothPlastic
	fogCore.Color = CONFIG.FOG_CORE_COLOR
	fogCore.Transparency = CONFIG.FOG_CORE_TRANSPARENCY

	fogCore:SetAttribute("IsFogCoreBlock", true)
	fogCore:SetAttribute("VisibleTransparency", CONFIG.FOG_CORE_TRANSPARENCY)
	fogCore:SetAttribute("FogCoreTextureTransparency", CONFIG.FOG_CORE_TEXTURE_TRANSPARENCY)

	addFogCoreTextures(fogCore)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FogCoreMist"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = CONFIG.FOG_CORE_PARTICLE_RATE
	emitter.Lifetime = NumberRange.new(8, 12)
	emitter.Speed = NumberRange.new(0.15, 0.7)
	emitter.Drag = 1
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-3, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 18),
		NumberSequenceKeypoint.new(0.5, 42),
		NumberSequenceKeypoint.new(1, 64),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.32),
		NumberSequenceKeypoint.new(0.78, 0.56),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CONFIG.FOG_CORE_COLOR),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(245, 248, 250)),
	})
	emitter:SetAttribute("VisibleRate", CONFIG.FOG_CORE_PARTICLE_RATE)
	emitter.Parent = fogCore

	fogCore.Parent = visualsFolder
end

local function positionFogCore(highestY)
	if not fogCore or not fogCore.Parent then
		return
	end

	local anchorPosition = findFogCoreAnchorPosition(highestY)
	fogCore.Position = anchorPosition
end

local function buildCloudModel(highestY)
	local oldModel = workspace:FindFirstChild(CONFIG.MODEL_NAME)

	if oldModel then
		oldModel:Destroy()
	end

	cloudModel = Instance.new("Model")
	cloudModel.Name = CONFIG.MODEL_NAME

	cloudModel:SetAttribute("State", "Covering")
	cloudModel:SetAttribute("CoveredThroughY", highestY)
	cloudModel:SetAttribute("CoverageSize", coverageSize)

	visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "Visuals"
	visualsFolder.Parent = cloudModel

	table.clear(layers)

	for layerIndex = 1, #CONFIG.LAYER_OFFSETS do
		local layer = createCloudLayer(layerIndex, highestY)
		table.insert(layers, layer)
	end
    createFogCurtains(highestY)
    createFogCore(highestY)
    
	barrier = createBarrier(highestY)

	-- Só coloca no Workspace depois de tudo estar configurado.
	cloudModel.Parent = workspace

	for _, descendant in ipairs(cloudModel:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local rate = descendant:GetAttribute("VisibleRate") or 5

			pcall(function()
				descendant:Emit(math.ceil(rate * 1.5))
			end)
		end
	end

	return cloudModel
end

local function positionCurtains(highestY)
	local curtainY =
		highestY
		+ CONFIG.CURTAIN_OFFSET_STUDS
		- CONFIG.CURTAIN_HEIGHT / 2

	for _, curtain in ipairs(curtains) do
		if not curtain.Parent then
			continue
		end

		if curtain.Name == "CurtainNorth" then
			curtain.Position = Vector3.new(
				worldCenter.X,
				curtainY,
				worldCenter.Z - coverageSize / 2
			)

		elseif curtain.Name == "CurtainSouth" then
			curtain.Position = Vector3.new(
				worldCenter.X,
				curtainY,
				worldCenter.Z + coverageSize / 2
			)

		elseif curtain.Name == "CurtainWest" then
			curtain.Position = Vector3.new(
				worldCenter.X - coverageSize / 2,
				curtainY,
				worldCenter.Z
			)

		elseif curtain.Name == "CurtainEast" then
			curtain.Position = Vector3.new(
				worldCenter.X + coverageSize / 2,
				curtainY,
				worldCenter.Z
			)
		end
	end
end

local function positionBarrier(highestY)
	if not barrier or not barrier.Parent then
		return
	end

	local barrierY = highestY + CONFIG.BARRIER_OFFSET_STUDS

	barrier.Position = Vector3.new(
		worldCenter.X,
		barrierY,
		worldCenter.Z
	)

	barrier.CanCollide = CONFIG.BLOCK_PLAYER_PROGRESS

	cloudModel:SetAttribute("BarrierY", barrierY)
end

local function positionVisuals(highestY)
	for layerIndex, layer in ipairs(layers) do
		if layer.Parent then
			local origin = getLayerPosition(highestY, layerIndex)

			layer:SetAttribute("CloudOriginPosition", origin)
			layer.CFrame = CFrame.new(origin)
		end
	end
    positionCurtains(highestY)
    positionFogCore(highestY)
	cloudModel:SetAttribute("CoveredThroughY", highestY)
end

local function fadeOutClouds()
	if not cloudModel or not cloudModel.Parent then
		return
	end

	cloudModel:SetAttribute("State", "Dissolving")

	for _, layer in ipairs(layers) do
		if layer.Parent then
			TweenService:Create(
				layer,
				TweenInfo.new(
					CONFIG.FADE_OUT_TIME,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				),
				{
					Transparency = 1,
				}
			):Play()

			local emitter = layer:FindFirstChildOfClass("ParticleEmitter")

			if emitter then
				emitter.Rate = 0

				task.delay(CONFIG.PARTICLE_CLEAR_DELAY, function()
					if emitter.Parent then
						pcall(function()
							emitter:Clear()
						end)
					end
				end)
			end
		end
	end
    for _, curtain in ipairs(curtains) do
	if curtain.Parent then
		TweenService:Create(
			curtain,
			TweenInfo.new(
				CONFIG.FADE_OUT_TIME,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			{
				Transparency = 1,
			}
		):Play()

		local emitter = curtain:FindFirstChildOfClass("ParticleEmitter")

		if emitter then
			emitter.Rate = 0
		end
	end
end
if fogCore and fogCore.Parent then
	TweenService:Create(
		fogCore,
		TweenInfo.new(
			CONFIG.FADE_OUT_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			Transparency = 1,
		}
	):Play()

	for _, child in ipairs(fogCore:GetChildren()) do
		if child:IsA("Texture") then
			TweenService:Create(
				child,
				TweenInfo.new(
					CONFIG.FADE_OUT_TIME,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				),
				{
					Transparency = 1,
				}
			):Play()

		elseif child:IsA("ParticleEmitter") then
			child.Rate = 0
		end
	end
end
	task.wait(CONFIG.FADE_OUT_TIME)
end

local function fadeInClouds()
	if not cloudModel or not cloudModel.Parent then
		return
	end

	cloudModel:SetAttribute("State", "Reforming")

	for _, layer in ipairs(layers) do
		if layer.Parent then
			layer.Transparency = 1

			local visibleTransparency =
				layer:GetAttribute("VisibleTransparency") or 0.82

			local emitter = layer:FindFirstChildOfClass("ParticleEmitter")

			if emitter then
				local visibleRate =
					emitter:GetAttribute("VisibleRate") or 5

				emitter.Enabled = true
				emitter.Rate = visibleRate

				pcall(function()
					emitter:Clear()
					emitter:Emit(math.ceil(visibleRate * 1.7))
				end)
			end

			TweenService:Create(
				layer,
				TweenInfo.new(
					CONFIG.FADE_IN_TIME,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.Out
				),
				{
					Transparency = visibleTransparency,
				}
			):Play()
		end
	end
    for _, curtain in ipairs(curtains) do
	if curtain.Parent then
		curtain.Transparency = 1

		local visibleTransparency =
			curtain:GetAttribute("VisibleTransparency")
			or CONFIG.CURTAIN_TRANSPARENCY

		local emitter = curtain:FindFirstChildOfClass("ParticleEmitter")

		if emitter then
			emitter.Rate =
				emitter:GetAttribute("VisibleRate")
				or 10
		end

		TweenService:Create(
			curtain,
			TweenInfo.new(
				CONFIG.FADE_IN_TIME,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out
			),
			{
				Transparency = visibleTransparency,
			}
		):Play()
	end
end
    if fogCore and fogCore.Parent then
	fogCore.Transparency = 1

	local visibleTransparency =
		fogCore:GetAttribute("VisibleTransparency")
		or CONFIG.FOG_CORE_TRANSPARENCY

	TweenService:Create(
		fogCore,
		TweenInfo.new(
			CONFIG.FADE_IN_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		),
		{
			Transparency = visibleTransparency,
		}
	):Play()

	for _, child in ipairs(fogCore:GetChildren()) do
		if child:IsA("Texture") then
			child.Transparency = 1

			TweenService:Create(
				child,
				TweenInfo.new(
					CONFIG.FADE_IN_TIME,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.Out
				),
				{
					Transparency =
						fogCore:GetAttribute("FogCoreTextureTransparency")
						or CONFIG.FOG_CORE_TEXTURE_TRANSPARENCY,
				}
			):Play()

		elseif child:IsA("ParticleEmitter") then
			local visibleRate =
				child:GetAttribute("VisibleRate")
				or CONFIG.FOG_CORE_PARTICLE_RATE

			child.Enabled = true
			child.Rate = visibleRate

			pcall(function()
				child:Clear()
				child:Emit(math.ceil(visibleRate * 1.5))
			end)
		end
	end
end
	task.wait(CONFIG.FADE_IN_TIME)

	if cloudModel and cloudModel.Parent then
		cloudModel:SetAttribute("State", "Covering")
	end
end

local function processRevealQueue()
	if revealBusy or shuttingDown then
		return
	end

	revealBusy = true

	task.spawn(function()
		while
			not shuttingDown
			and pendingHighestY
			and pendingHighestY > visualHighestY + 0.01
		do
			local targetHighestY = pendingHighestY
			pendingHighestY = nil

			debugPrint(
				string.format(
					"Revelando continuação até Y %.1f.",
					targetHighestY
				)
			)

			fadeOutClouds()

			-- Caso mais de um round tenha terminado durante a dissipação,
			-- move diretamente para o limite mais alto.
			if pendingHighestY and pendingHighestY > targetHighestY then
				targetHighestY = pendingHighestY
				pendingHighestY = nil
			end

			if shuttingDown then
				break
			end

			positionVisuals(targetHighestY)
			visualHighestY = targetHighestY

			fadeInClouds()
		end

		revealBusy = false

		-- Evita perder uma atualização que chegue exatamente no final do ciclo.
		if
			not shuttingDown
			and pendingHighestY
			and pendingHighestY > visualHighestY + 0.01
		then
			processRevealQueue()
		end
	end)
end

local function queueNewHighestY(newHighestY)
	if type(newHighestY) ~= "number" then
		return
	end

	if newHighestY <= visualHighestY + 0.01 then
		return
	end

	-- O bloqueador sobe imediatamente. Assim, durante a animação de revelação,
	-- o jogador já pode explorar o novo round, mas não ultrapassar o novo topo.
	positionBarrier(newHighestY)

	pendingHighestY = math.max(
		pendingHighestY or newHighestY,
		newHighestY
	)

	processRevealQueue()
end

local worldModel = workspace:FindFirstChild(MapConfig.WORLD_MODEL_NAME, true)
local worldDeadline = os.clock() + CONFIG.STARTUP_TIMEOUT_SECONDS
while not worldModel and os.clock() < worldDeadline do
	task.wait(0.1)
	worldModel = workspace:FindFirstChild(MapConfig.WORLD_MODEL_NAME, true)
end

if not worldModel then
	warn(
		string.format(
			"[GenerationClouds] Mundo %s não foi encontrado.",
			MapConfig.WORLD_MODEL_NAME
		)
	)

	return
end

-- Aguarda o buffer inicial de chunks. Isso evita cobrir o mapa inicial
-- enquanto ele ainda está sendo montado.
local startupDeadline = os.clock() + CONFIG.STARTUP_TIMEOUT_SECONDS

while
	worldModel.Parent
	and (worldModel:GetAttribute("ChunkCount") or 0)
		< MapConfig.INITIAL_CHUNK_COUNT
	and os.clock() < startupDeadline
do
	task.wait(0.1)
end

if not worldModel.Parent then
	return
end

visualHighestY =
	worldModel:GetAttribute("HighestGeneratedY")
	or MapConfig.CENTER_WORLD.Y

buildCloudModel(visualHighestY)

debugPrint(
	string.format(
		"Camada criada em Y %.1f com cobertura de %.0f studs.",
		visualHighestY,
		coverageSize
	)
)

local highestChangedConnection

highestChangedConnection =
	worldModel:GetAttributeChangedSignal("HighestGeneratedY"):Connect(function()
		local newHighestY = worldModel:GetAttribute("HighestGeneratedY")
		queueNewHighestY(newHighestY)
	end)

worldModel.Destroying:Connect(function()
	shuttingDown = true

	if highestChangedConnection then
		highestChangedConnection:Disconnect()
	end

	if cloudModel then
		cloudModel:Destroy()
	end
end)
