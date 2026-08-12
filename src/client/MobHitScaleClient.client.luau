-- Feedback local de impacto dos mobs.
--
-- O servidor continua dono da fisica. Em vez de chamar ScaleTo no mesmo
-- Model que recebe knockback e replicacao, este cliente monta uma copia
-- visual temporaria, esconde o corpo real somente para o atacante e anima a
-- copia. Assim o crescimento permanece visivel mesmo durante o movimento.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local feedbackEvent = RemoteRegistry.Get("Combat", "EnemyDamageFeedback", "RemoteEvent")

local NORMAL_GROWTH = 1.22
local HEAVY_GROWTH = 1.30
local REDUCED_GROWTH = 1.10
local GROW_DURATION = 0.08
local RETURN_DURATION = 0.15
local MIN_VISIBLE_TRANSPARENCY = 0.99

type MeshPair = {
	Source: SpecialMesh,
	Proxy: SpecialMesh,
}

type VisualPart = {
	Source: BasePart,
	Proxy: BasePart,
	OriginalLocalTransparency: number,
	Meshes: { MeshPair },
}

type ScaleState = {
	Token: number,
	CurrentScale: number,
	Parts: { VisualPart },
}

local active: { [Model]: ScaleState } = setmetatable({}, { __mode = "k" })
local warnedModels: { [Model]: boolean } = setmetatable({}, { __mode = "k" })

local oldFolder = workspace:FindFirstChild("LocalMobHitScaleVisuals")
if oldFolder then
	oldFolder:Destroy()
end

local proxyFolder = Instance.new("Folder")
proxyFolder.Name = "LocalMobHitScaleVisuals"
proxyFolder.Parent = workspace

local function reducedEffectsEnabled(): boolean
	return player:GetAttribute("ClientSetting_ReducedEffects") == true
		or player:GetAttribute("ReducedMotion") == true
		or player:GetAttribute("ReduceMotion") == true
end

local function easeOutBack(alpha: number): number
	local overshoot = 1.35
	local shifted = alpha - 1
	return 1 + (overshoot + 1) * shifted * shifted * shifted + overshoot * shifted * shifted
end

local function easeInOutQuad(alpha: number): number
	if alpha < 0.5 then
		return 2 * alpha * alpha
	end
	return 1 - ((-2 * alpha + 2) ^ 2) / 2
end

local function isVisualChild(instance: Instance): boolean
	return instance:IsA("SpecialMesh")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("SurfaceAppearance")
		or instance:IsA("WrapLayer")
		or instance:IsA("WrapTarget")
		or instance:IsA("Bone")
end

local function cloneVisualPart(source: BasePart): BasePart?
	local wasArchivable = source.Archivable
	if not wasArchivable then
		source.Archivable = true
	end

	local success, cloned = pcall(function()
		return source:Clone()
	end)

	if not wasArchivable and source.Parent then
		source.Archivable = false
	end

	if not success or not cloned or not cloned:IsA("BasePart") then
		if cloned then
			cloned:Destroy()
		end
		return nil
	end

	-- Mantem somente a aparencia. Joints, sons, scripts, emissores e qualquer
	-- outra logica continuam exclusivamente no mob real.
	for _, child in ipairs(cloned:GetChildren()) do
		if not isVisualChild(child) then
			child:Destroy()
		end
	end

	cloned.Name = "HitScale_" .. source.Name
	cloned.Anchored = true
	cloned.CanCollide = false
	cloned.CanTouch = false
	cloned.CanQuery = false
	cloned.CastShadow = false
	cloned.Massless = true
	cloned.LocalTransparencyModifier = 0

	return cloned
end

local function pairSpecialMeshes(source: BasePart, proxy: BasePart): { MeshPair }
	local pairs = {}
	local sourceMeshes = {}
	local proxyMeshes = {}

	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("SpecialMesh") then
			table.insert(sourceMeshes, descendant)
		end
	end
	for _, descendant in ipairs(proxy:GetDescendants()) do
		if descendant:IsA("SpecialMesh") then
			table.insert(proxyMeshes, descendant)
		end
	end

	for index, sourceMesh in ipairs(sourceMeshes) do
		local proxyMesh = proxyMeshes[index]
		if proxyMesh then
			table.insert(pairs, {
				Source = sourceMesh,
				Proxy = proxyMesh,
			})
		end
	end

	return pairs
end

local function createVisualState(model: Model): ScaleState?
	local state: ScaleState = {
		Token = 0,
		CurrentScale = 1,
		Parts = {},
	}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < MIN_VISIBLE_TRANSPARENCY then
			local proxy = cloneVisualPart(descendant)
			if proxy then
				local visualPart: VisualPart = {
					Source = descendant,
					Proxy = proxy,
					OriginalLocalTransparency = descendant.LocalTransparencyModifier,
					Meshes = pairSpecialMeshes(descendant, proxy),
				}
				table.insert(state.Parts, visualPart)
			end
		end
	end

	if #state.Parts == 0 then
		return nil
	end

	-- Publica todas as copias juntas para nao mostrar o mob parcialmente.
	for _, visualPart in ipairs(state.Parts) do
		visualPart.Proxy.Parent = proxyFolder
		visualPart.Source.LocalTransparencyModifier = 1
	end

	return state
end

local function cleanupState(model: Model, state: ScaleState)
	for _, visualPart in ipairs(state.Parts) do
		if visualPart.Source.Parent then
			visualPart.Source.LocalTransparencyModifier = visualPart.OriginalLocalTransparency
		end
		if visualPart.Proxy.Parent then
			visualPart.Proxy:Destroy()
		end
	end

	if active[model] == state then
		active[model] = nil
	end
end

local function modelBottomAnchor(model: Model): Vector3?
	local success, boxCFrame, boxSize = pcall(model.GetBoundingBox, model)
	if not success then
		return nil
	end
	return boxCFrame.Position - boxCFrame.UpVector * (boxSize.Y * 0.5)
end

local function updateVisual(model: Model, state: ScaleState, scale: number): boolean
	local anchor = modelBottomAnchor(model)
	if not anchor then
		return false
	end

	for _, visualPart in ipairs(state.Parts) do
		local source = visualPart.Source
		local proxy = visualPart.Proxy
		if not source.Parent or not proxy.Parent then
			return false
		end

		-- Reaplica a ocultacao porque outros controladores locais podem alterar
		-- LocalTransparencyModifier enquanto a reacao ainda esta ativa.
		source.LocalTransparencyModifier = 1

		local sourceCFrame = source.CFrame
		local sourcePosition = sourceCFrame.Position
		local scaledPosition = anchor + (sourcePosition - anchor) * scale
		local rotation = sourceCFrame - sourcePosition

		proxy.CFrame = CFrame.new(scaledPosition) * rotation
		proxy.Size = Vector3.new(
			math.max(0.01, source.Size.X * scale),
			math.max(0.01, source.Size.Y * scale),
			math.max(0.01, source.Size.Z * scale)
		)
		proxy.Transparency = source.Transparency
		proxy.Color = source.Color
		proxy.Material = source.Material

		-- SpecialMesh usa sua propria escala visual, independente do tamanho da
		-- Part. Sem isto, slimes feitos com FileMesh quase nao cresceriam.
		for _, meshPair in ipairs(visualPart.Meshes) do
			if meshPair.Source.Parent and meshPair.Proxy.Parent then
				meshPair.Proxy.Scale = meshPair.Source.Scale * scale
				meshPair.Proxy.Offset = meshPair.Source.Offset * scale
			end
		end
	end

	state.CurrentScale = scale
	return true
end

local function animateScale(
	model: Model,
	state: ScaleState,
	token: number,
	fromScale: number,
	toScale: number,
	duration: number,
	easing: (number) -> number
): boolean
	local startedAt = os.clock()

	while model.Parent and state.Token == token do
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local scale = fromScale + (toScale - fromScale) * easing(alpha)

		if not updateVisual(model, state, scale) then
			return false
		end

		if alpha >= 1 then
			return true
		end
		RunService.RenderStepped:Wait()
	end

	return false
end

local function playScale(model: Model, heavy: boolean)
	if not model.Parent or not model:IsDescendantOf(workspace) then
		return
	end

	local state = active[model]
	if not state then
		state = createVisualState(model)
		if not state then
			if not warnedModels[model] then
				warnedModels[model] = true
				warn("[MobHitScaleClient] Nenhuma parte visual encontrada em ", model:GetFullName())
			end
			return
		end
		active[model] = state
	end

	state.Token += 1
	local token = state.Token
	local fromScale = state.CurrentScale
	local peakScale = if reducedEffectsEnabled() then REDUCED_GROWTH elseif heavy then HEAVY_GROWTH else NORMAL_GROWTH

	task.spawn(function()
		if not animateScale(model, state, token, fromScale, peakScale, GROW_DURATION, easeOutBack) then
			if state.Token == token then
				cleanupState(model, state)
			end
			return
		end

		animateScale(model, state, token, peakScale, 1, RETURN_DURATION, easeInOutQuad)

		if state.Token == token then
			cleanupState(model, state)
		end
	end)
end

feedbackEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local target = payload.Target
	if not target or not target:IsA("Model") then
		return
	end

	playScale(target, payload.Heavy == true)
end)

player:SetAttribute("MobHitScaleClientReady", true)
player:SetAttribute("MobHitScaleClientVersion", "VisualProxyV2")

script.Destroying:Connect(function()
	for model, state in pairs(active) do
		cleanupState(model, state)
	end
	if proxyFolder.Parent then
		proxyFolder:Destroy()
	end
end)
