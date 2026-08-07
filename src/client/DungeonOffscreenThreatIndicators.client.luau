-- Mobile Dungeon Mode — Task 09: Off-screen Threat Indicators.
--
-- Camada local de leitura visual.
-- Mostra somente ameaças prioritarias que estejam FORA da camera:
-- - projeteis / mortar warnings;
-- - Boss ativo;
-- - Elite;
-- - slimes ranged/mortar em estado de combate.
--
-- Slimes melee comuns nao recebem indicador para evitar poluicao visual.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonOffscreenThreatIndicatorsV1"
local RENDER_STEP = "InfinityIslandsOffscreenThreatIndicators"
local UPDATE_INTERVAL = 0.09
local MAX_INDICATORS = 4
local MAX_MODEL_DISTANCE = 105
local MAX_PROJECTILE_DISTANCE = 90

local PROJECTILE_NAMES = {
	BlueSlimeProjectile = true,
	IceSlimeProjectile = true,
	RedSlimeMortar = true,
	FireSlimeMortar = true,
	SlimeMortarWarning = true,
}

local COLORS = {
	Projectile = Color3.fromRGB(255, 98, 107),
	Mortar = Color3.fromRGB(255, 150, 62),
	Boss = Color3.fromRGB(255, 93, 117),
	Elite = Color3.fromRGB(255, 211, 92),
	Ranged = Color3.fromRGB(100, 218, 255),
	Text = Color3.fromRGB(247, 250, 255),
	Glass = Color3.fromRGB(14, 25, 38),
}

local active = false
local elapsed = 0
local gui
local rootFrame

local projectileThreats = setmetatable({}, { __mode = "k" })
local cards = {}
local visibleCount = 0

local function textScale()
	return math.clamp(
		tonumber(player:GetAttribute("DungeonMobileTextUserScale")) or 1,
		0.90,
		1.25
	)
end

local function scaledText(base)
	return math.max(7, math.floor(base * textScale() + 0.5))
end

local function reducedEffects()
	return player:GetAttribute("ClientSetting_ReducedEffects") == true
		or player:GetAttribute("ReducedMotion") == true
		or player:GetAttribute("ReduceMotion") == true
end

local function worldMarkersEnabled()
	local value = player:GetAttribute("ClientSetting_WorldMarkers")
	if value == nil then
		value = player:GetAttribute("DungeonHUDWorldMarkersEnabled")
	end
	return value ~= false
end

local function currentCamera()
	return workspace.CurrentCamera
end

local function getRoot(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if not instance:IsA("Model") then
		return nil
	end

	local root = instance:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	if instance.PrimaryPart and instance.PrimaryPart:IsA("BasePart") then
		return instance.PrimaryPart
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function livingTarget(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end
	if model:GetAttribute("ObjectiveTargetCompleted") == true
		or model:GetAttribute("ObjectiveAmbushHidden") == true
		or model:GetAttribute("SimulationActive") == false
	then
		return false
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	return humanoid == nil or humanoid.Health > 0
end

local function combatActive(model)
	if model:GetAttribute("Peaceful") == false then
		return true
	end

	local aggroUserId = tonumber(model:GetAttribute("AggroUserId"))
	if aggroUserId and aggroUserId == player.UserId then
		return true
	end

	local state = tostring(model:GetAttribute("AIState") or "")
	return state == "Chase"
		or state == "Strafe"
		or state == "Retreat"
		or state == "Mortar"
		or state == "Melee"
end

local function bossActive(model)
	if model:GetAttribute("BossActive") == true then
		return true
	end
	local state = tostring(workspace:GetAttribute("DungeonBossState") or "")
	return state == "Active" or state == "Activating"
end

local function classifyModel(model)
	if not livingTarget(model) then
		return nil
	end

	if model:GetAttribute("IsBoss") == true
		or CollectionService:HasTag(model, "DungeonBoss")
	then
		if not bossActive(model) then
			return nil
		end
		return {
			Priority = 90,
			Kind = "Boss",
			Label = "BOSS",
			Color = COLORS.Boss,
		}
	end

	if model:GetAttribute("IsElite") == true then
		return {
			Priority = 72,
			Kind = "Elite",
			Label = "ELITE",
			Color = COLORS.Elite,
		}
	end

	local behavior = tostring(model:GetAttribute("SlimeBehavior") or "")
	local isRanged = string.find(behavior, "Ranged", 1, true) ~= nil
	local isMortar = string.find(behavior, "Mortar", 1, true) ~= nil

	if (isRanged or isMortar) and combatActive(model) then
		return {
			Priority = isMortar and 66 or 60,
			Kind = isMortar and "Mortar" or "Ranged",
			Label = isMortar and "MORTEIRO" or "RANGED",
			Color = isMortar and COLORS.Mortar or COLORS.Ranged,
		}
	end

	return nil
end

local function classifyProjectile(instance)
	if not instance
		or not instance:IsA("BasePart")
		or not instance.Parent
		or not PROJECTILE_NAMES[instance.Name]
	then
		return nil
	end

	local mortar = instance.Name == "RedSlimeMortar"
		or instance.Name == "FireSlimeMortar"
		or instance.Name == "SlimeMortarWarning"

	return {
		Priority = instance.Name == "SlimeMortarWarning" and 110 or 100,
		Kind = mortar and "Mortar" or "Projectile",
		Label = instance.Name == "SlimeMortarWarning"
			and "IMPACTO"
			or mortar and "MORTEIRO"
			or "PROJÉTIL",
		Color = mortar and COLORS.Mortar or COLORS.Projectile,
	}
end

local function createGui()
	if gui and gui.Parent then
		return
	end

	local old = playerGui:FindFirstChild("DungeonOffscreenThreatHUD")
	if old then
		old:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "DungeonOffscreenThreatHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 67
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.Parent = gui
end

local function makeCard(index)
	local card = Instance.new("Frame")
	card.Name = "Threat" .. index
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromOffset(82, 42)
	card.BackgroundColor3 = COLORS.Glass
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = 10 + index
	card.Parent = rootFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 11)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Thickness = 1.4
	stroke.Transparency = 0.08
	stroke.Parent = card

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromOffset(18, 16)
	arrow.Size = UDim2.fromOffset(25, 25)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▲"
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 20
	arrow.ZIndex = card.ZIndex + 1
	arrow.Parent = card

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(34, 5)
	label.Size = UDim2.new(1, -38, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = "PERIGO"
	label.TextColor3 = COLORS.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.TextSize = 8
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = card.ZIndex + 1
	label.Parent = card

	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.Position = UDim2.fromOffset(34, 20)
	distance.Size = UDim2.new(1, -38, 0, 14)
	distance.BackgroundTransparency = 1
	distance.Text = ""
	distance.TextColor3 = Color3.fromRGB(198, 215, 228)
	distance.TextXAlignment = Enum.TextXAlignment.Left
	distance.Font = Enum.Font.GothamMedium
	distance.TextSize = 8
	distance.ZIndex = card.ZIndex + 1
	distance.Parent = card

	local scale = Instance.new("UIScale")
	scale.Name = "Pulse"
	scale.Scale = 1
	scale.Parent = card

	cards[index] = {
		Frame = card,
		Stroke = stroke,
		Arrow = arrow,
		Label = label,
		Distance = distance,
		Scale = scale,
		PulseTween = nil,
		LastKind = nil,
	}

	return cards[index]
end

local function ensureCards()
	for index = 1, MAX_INDICATORS do
		if not cards[index] then
			makeCard(index)
		end
	end
end

local function playerRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function isActuallyOnScreen(camera, worldPosition, viewport)
	local point, onScreen = camera:WorldToViewportPoint(worldPosition)
	if not onScreen or point.Z <= 0 then
		return false, point
	end

	-- Pequena margem para nao esconder o indicador quando a ameaca esta
	-- tecnicamente dentro do viewport mas encoberta pelos controles/HUD.
	local horizontalMargin = 10
	local topMargin = 170
	local bottomMargin = 126

	local visible = point.X >= horizontalMargin
		and point.X <= viewport.X - horizontalMargin
		and point.Y >= topMargin
		and point.Y <= viewport.Y - bottomMargin

	return visible, point
end

local function edgeDirection(camera, worldPosition, projectedPoint, viewport)
	local center = viewport * 0.5

	if projectedPoint and projectedPoint.Z > 0 then
		local delta = Vector2.new(projectedPoint.X, projectedPoint.Y) - center
		if delta.Magnitude > 0.001 then
			return delta.Unit
		end
	end

	-- Alvo atras da camera: WorldToViewportPoint pode inverter a intuicao.
	-- Usa a orientacao real da camera para obter um vetor 2D estavel.
	local offset = worldPosition - camera.CFrame.Position
	if offset.Magnitude <= 0.001 then
		return Vector2.new(0, -1)
	end

	local unit = offset.Unit
	local x = camera.CFrame.RightVector:Dot(unit)
	local y = -camera.CFrame.UpVector:Dot(unit)
	local direction = Vector2.new(x, y)

	if projectedPoint and projectedPoint.Z <= 0 then
		direction = -direction
	end
	if direction.Magnitude <= 0.001 then
		return Vector2.new(0, -1)
	end
	return direction.Unit
end

local function edgePosition(direction, viewport)
	local topLeft, bottomRight = Vector2.zero, Vector2.zero
	local success, first, second = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if success then
		topLeft = typeof(first) == "Vector2" and first or Vector2.zero
		bottomRight = typeof(second) == "Vector2" and second or Vector2.zero
	end

	-- Respeita o CombatHeader portrait no topo e os controles na base.
	local minX = 52
	local maxX = math.max(minX + 1, viewport.X - 52)
	local minY = math.max(188, topLeft.Y + 48)
	local maxY = math.max(minY + 1, viewport.Y - math.max(142, bottomRight.Y + 92))

	local center = Vector2.new(
		(minX + maxX) * 0.5,
		(minY + maxY) * 0.5
	)
	local half = Vector2.new(
		(maxX - minX) * 0.5,
		(maxY - minY) * 0.5
	)

	local dx = math.abs(direction.X)
	local dy = math.abs(direction.Y)
	local tx = dx > 0.001 and half.X / dx or math.huge
	local ty = dy > 0.001 and half.Y / dy or math.huge
	local t = math.min(tx, ty)

	return center + direction * t
end

local function candidateFromInstance(instance, definition, maxDistance)
	local root = getRoot(instance)
	local avatarRoot = playerRoot()
	if not root or not avatarRoot then
		return nil
	end

	local distance = (root.Position - avatarRoot.Position).Magnitude
	if distance > maxDistance then
		return nil
	end

	return {
		Instance = instance,
		Root = root,
		Position = root.Position,
		Distance = distance,
		Priority = definition.Priority,
		Kind = definition.Kind,
		Label = definition.Label,
		Color = definition.Color,
	}
end

local function scoreCandidate(candidate)
	-- Prioridade manda; proximidade desempata. Projeteis continuam na frente
	-- de mobs mesmo quando um Elite distante tambem esta fora da camera.
	return candidate.Priority * 1000 - candidate.Distance
end

local function collectCandidates(camera, viewport)
	local result = {}
	local seen = {}

	for instance in pairs(projectileThreats) do
		if not instance.Parent then
			projectileThreats[instance] = nil
		else
			local definition = classifyProjectile(instance)
			local candidate = definition
				and candidateFromInstance(instance, definition, MAX_PROJECTILE_DISTANCE)
			if candidate then
				local onScreen, point = isActuallyOnScreen(
					camera,
					candidate.Position,
					viewport
				)
				if not onScreen then
					candidate.Projected = point
					candidate.Score = scoreCandidate(candidate)
					table.insert(result, candidate)
					seen[instance] = true
				end
			end
		end
	end

	for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if model:IsA("Model") and model.Parent and not seen[model] then
			local definition = classifyModel(model)
			local candidate = definition
				and candidateFromInstance(model, definition, MAX_MODEL_DISTANCE)
			if candidate then
				local onScreen, point = isActuallyOnScreen(
					camera,
					candidate.Position,
					viewport
				)
				if not onScreen then
					candidate.Projected = point
					candidate.Score = scoreCandidate(candidate)
					table.insert(result, candidate)
				end
			end
		end
	end

	table.sort(result, function(a, b)
		if a.Score == b.Score then
			return a.Distance < b.Distance
		end
		return a.Score > b.Score
	end)

	while #result > MAX_INDICATORS do
		table.remove(result)
	end

	return result
end

local function stopPulse(card)
	if card.PulseTween then
		card.PulseTween:Cancel()
		card.PulseTween = nil
	end
	card.Scale.Scale = 1
end

local function updatePulse(card, candidate)
	local dangerous = candidate.Kind == "Projectile"
		or candidate.Kind == "Mortar"
		or candidate.Kind == "Boss"

	if reducedEffects() or not dangerous then
		stopPulse(card)
		return
	end

	if card.LastKind == candidate.Kind and card.PulseTween then
		return
	end

	stopPulse(card)
	card.Scale.Scale = 1

	local tween = TweenService:Create(
		card.Scale,
		TweenInfo.new(
			0.42,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ Scale = 1.08 }
	)
	card.PulseTween = tween
	tween:Play()
end

local function updateCard(card, candidate, camera, viewport)
	local direction = edgeDirection(
		camera,
		candidate.Position,
		candidate.Projected,
		viewport
	)
	local position = edgePosition(direction, viewport)

	card.Frame.Position = UDim2.fromOffset(
		math.floor(position.X + 0.5),
		math.floor(position.Y + 0.5)
	)
	card.Frame.Visible = true
	card.Stroke.Color = candidate.Color
	card.Arrow.TextColor3 = candidate.Color
	card.Label.Text = candidate.Label
	card.Distance.Text = string.format("%dm", math.floor(candidate.Distance + 0.5))
	card.Arrow.TextSize = scaledText(20)
	card.Label.TextSize = scaledText(8)
	card.Distance.TextSize = scaledText(8)

	-- ▲ aponta para cima em Rotation=0.
	card.Arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90

	updatePulse(card, candidate)
	card.LastKind = candidate.Kind
end

local function hideUnused(startIndex)
	for index = startIndex, MAX_INDICATORS do
		local card = cards[index]
		if card then
			card.Frame.Visible = false
			stopPulse(card)
			card.LastKind = nil
		end
	end
end

local function render()
	if not active
		or player:GetAttribute("DungeonMobileMode") ~= true
		or not worldMarkersEnabled()
	then
		hideUnused(1)
		visibleCount = 0
		return
	end

	local camera = currentCamera()
	if not camera then
		hideUnused(1)
		visibleCount = 0
		return
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local candidates = collectCandidates(camera, viewport)
	visibleCount = #candidates

	for index, candidate in ipairs(candidates) do
		updateCard(cards[index], candidate, camera, viewport)
	end
	hideUnused(#candidates + 1)

	player:SetAttribute("DungeonOffscreenThreatVisibleCount", visibleCount)
end

local function registerProjectile(instance)
	if instance:IsA("BasePart") and PROJECTILE_NAMES[instance.Name] then
		projectileThreats[instance] = true
	end
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	createGui()
	ensureCards()
	active = true
	gui.Enabled = true

	player:SetAttribute("DungeonOffscreenThreatReady", true)
	player:SetAttribute("DungeonOffscreenThreatActive", true)
	player:SetAttribute("DungeonOffscreenThreatVersion", VERSION)
	player:SetAttribute(
		"DungeonOffscreenThreatPolicy",
		"ProjectileBossEliteRangedMax4V1"
	)

	render()
end

local function deactivate()
	if not active then
		return
	end

	active = false
	if gui then
		gui.Enabled = false
	end
	hideUnused(1)
	visibleCount = 0

	player:SetAttribute("DungeonOffscreenThreatActive", false)
	player:SetAttribute("DungeonOffscreenThreatVisibleCount", 0)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

for _, instance in ipairs(workspace:GetDescendants()) do
	registerProjectile(instance)
end

workspace.DescendantAdded:Connect(registerProjectile)
workspace.DescendantRemoving:Connect(function(instance)
	projectileThreats[instance] = nil
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

RunService:BindToRenderStep(
	RENDER_STEP,
	Enum.RenderPriority.Last.Value,
	function(deltaTime)
		if not active then
			return
		end

		elapsed += deltaTime
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		render()
	end
)

player:SetAttribute("DungeonOffscreenThreatControllerLoaded", true)
player:SetAttribute("DungeonOffscreenThreatVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(function()
	deactivate()
	RunService:UnbindFromRenderStep(RENDER_STEP)
end)
