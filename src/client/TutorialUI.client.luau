-- Interface visual e minimalista do tutorial compartilhado.
--
-- A validacao permanece no servidor. O cliente mostra apenas a acao atual,
-- destaca o objetivo no mundo e adapta o controle para teclado, toque ou gamepad.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialEvent = ReplicatedStorage:WaitForChild("TutorialEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 72
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local warningEdges = {}
for name, properties in pairs({
	Top = { Size = UDim2.fromScale(1, 0.012), Position = UDim2.fromScale(0, 0) },
	Bottom = { Size = UDim2.fromScale(1, 0.012), Position = UDim2.fromScale(0, 0.988) },
	Left = { Size = UDim2.fromScale(0.008, 1), Position = UDim2.fromScale(0, 0) },
	Right = { Size = UDim2.fromScale(0.008, 1), Position = UDim2.fromScale(0.992, 0) },
}) do
	local edge = Instance.new("Frame")
	edge.Name = "WaterWarning" .. name
	edge.Size = properties.Size
	edge.Position = properties.Position
	edge.BackgroundColor3 = Color3.fromRGB(58, 188, 255)
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 2
	edge.Parent = gui
	warningEdges[name] = edge
end

local objective = Instance.new("CanvasGroup")
objective.Name = "Objective"
objective.AnchorPoint = Vector2.new(0.5, 1)
objective.Position = UDim2.new(0.5, 0, 1, 120)
objective.Size = UDim2.fromOffset(430, 92)
objective.BackgroundColor3 = Color3.fromRGB(17, 22, 34)
objective.BackgroundTransparency = 0.08
objective.GroupTransparency = 0
objective.BorderSizePixel = 0
objective.Visible = false
objective.ZIndex = 10
objective.Parent = gui
Instance.new("UICorner", objective).CornerRadius = UDim.new(0, 16)

local objectiveStroke = Instance.new("UIStroke")
objectiveStroke.Color = Color3.fromRGB(85, 205, 255)
objectiveStroke.Thickness = 1.5
objectiveStroke.Transparency = 0.2
objectiveStroke.Parent = objective

local objectiveScale = Instance.new("UIScale")
objectiveScale.Parent = objective

local actionLabel = Instance.new("TextLabel")
actionLabel.Name = "Action"
actionLabel.Position = UDim2.fromOffset(18, 12)
actionLabel.Size = UDim2.new(1, -154, 0, 30)
actionLabel.BackgroundTransparency = 1
actionLabel.Text = "SIGA A LUZ"
actionLabel.TextColor3 = Color3.fromRGB(255, 236, 155)
actionLabel.Font = Enum.Font.GothamBold
actionLabel.TextSize = 21
actionLabel.TextXAlignment = Enum.TextXAlignment.Left
actionLabel.ZIndex = 11
actionLabel.Parent = objective

local instructionLabel = Instance.new("TextLabel")
instructionLabel.Name = "Instruction"
instructionLabel.Position = UDim2.fromOffset(18, 45)
instructionLabel.Size = UDim2.new(1, -150, 0, 30)
instructionLabel.BackgroundTransparency = 1
instructionLabel.Text = ""
instructionLabel.TextColor3 = Color3.fromRGB(225, 232, 244)
instructionLabel.Font = Enum.Font.GothamMedium
instructionLabel.TextSize = 13
instructionLabel.TextWrapped = true
instructionLabel.TextXAlignment = Enum.TextXAlignment.Left
instructionLabel.TextYAlignment = Enum.TextYAlignment.Top
instructionLabel.ZIndex = 11
instructionLabel.Parent = objective

local controlChip = Instance.new("TextLabel")
controlChip.Name = "Control"
controlChip.AnchorPoint = Vector2.new(1, 0)
controlChip.Position = UDim2.new(1, -16, 0, 14)
controlChip.Size = UDim2.fromOffset(112, 36)
controlChip.BackgroundColor3 = Color3.fromRGB(38, 51, 72)
controlChip.BorderSizePixel = 0
controlChip.Text = "WASD"
controlChip.TextColor3 = Color3.fromRGB(231, 246, 255)
controlChip.Font = Enum.Font.GothamBold
controlChip.TextSize = 14
controlChip.ZIndex = 11
controlChip.Parent = objective
Instance.new("UICorner", controlChip).CornerRadius = UDim.new(0, 10)

local chipStroke = Instance.new("UIStroke")
chipStroke.Color = Color3.fromRGB(94, 206, 255)
chipStroke.Thickness = 1
chipStroke.Transparency = 0.45
chipStroke.Parent = controlChip

local progressTrack = Instance.new("Frame")
progressTrack.Name = "ProgressTrack"
progressTrack.AnchorPoint = Vector2.new(1, 1)
progressTrack.Position = UDim2.new(1, -16, 1, -13)
progressTrack.Size = UDim2.fromOffset(112, 9)
progressTrack.BackgroundColor3 = Color3.fromRGB(38, 51, 72)
progressTrack.BorderSizePixel = 0
progressTrack.Visible = false
progressTrack.ZIndex = 11
progressTrack.Parent = objective
Instance.new("UICorner", progressTrack).CornerRadius = UDim.new(1, 0)

local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = Color3.fromRGB(255, 196, 64)
progressFill.BorderSizePixel = 0
progressFill.ZIndex = 12
progressFill.Parent = progressTrack
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

local stageDots = Instance.new("Frame")
stageDots.Name = "Stages"
stageDots.AnchorPoint = Vector2.new(0.5, 1)
stageDots.Position = UDim2.new(0.5, 0, 0, -8)
stageDots.Size = UDim2.fromOffset(98, 8)
stageDots.BackgroundTransparency = 1
stageDots.ZIndex = 11
stageDots.Parent = objective

local stageLayout = Instance.new("UIListLayout")
stageLayout.FillDirection = Enum.FillDirection.Horizontal
stageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
stageLayout.VerticalAlignment = Enum.VerticalAlignment.Center
stageLayout.Padding = UDim.new(0, 8)
stageLayout.Parent = stageDots

local dots = {}
for index = 1, 5 do
	local dot = Instance.new("Frame")
	dot.Name = "Stage" .. index
	dot.Size = UDim2.fromOffset(10, 5)
	dot.BackgroundColor3 = Color3.fromRGB(82, 94, 116)
	dot.BorderSizePixel = 0
	dot.ZIndex = 11
	dot.Parent = stageDots
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	dots[index] = dot
end

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -18, 0, -8)
skipButton.Size = UDim2.fromOffset(74, 25)
skipButton.BackgroundTransparency = 1
skipButton.Text = "PULAR"
skipButton.TextColor3 = Color3.fromRGB(157, 171, 192)
skipButton.Font = Enum.Font.GothamBold
skipButton.TextSize = 11
skipButton.ZIndex = 11
skipButton.Parent = objective

local successLabel = Instance.new("TextLabel")
successLabel.Name = "Success"
successLabel.AnchorPoint = Vector2.new(0.5, 0.5)
successLabel.Position = UDim2.fromScale(0.5, 0.5)
successLabel.Size = UDim2.fromOffset(300, 90)
successLabel.BackgroundTransparency = 1
successLabel.Text = "✓"
successLabel.TextColor3 = Color3.fromRGB(118, 255, 169)
successLabel.TextStrokeColor3 = Color3.fromRGB(10, 25, 18)
successLabel.TextStrokeTransparency = 0.2
successLabel.Font = Enum.Font.GothamBlack
successLabel.TextSize = 64
successLabel.TextTransparency = 1
successLabel.Visible = false
successLabel.ZIndex = 30
successLabel.Parent = gui

local offscreenArrow = Instance.new("TextLabel")
offscreenArrow.Name = "ObjectiveArrow"
offscreenArrow.AnchorPoint = Vector2.new(0.5, 0.5)
offscreenArrow.Size = UDim2.fromOffset(54, 54)
offscreenArrow.BackgroundColor3 = Color3.fromRGB(18, 31, 48)
offscreenArrow.BackgroundTransparency = 0.15
offscreenArrow.BorderSizePixel = 0
offscreenArrow.Text = "▲"
offscreenArrow.TextColor3 = Color3.fromRGB(103, 220, 255)
offscreenArrow.TextStrokeColor3 = Color3.fromRGB(5, 12, 20)
offscreenArrow.TextStrokeTransparency = 0.2
offscreenArrow.Font = Enum.Font.GothamBlack
offscreenArrow.TextSize = 30
offscreenArrow.Visible = false
offscreenArrow.ZIndex = 20
offscreenArrow.Parent = gui
Instance.new("UICorner", offscreenArrow).CornerRadius = UDim.new(1, 0)

local toast = Instance.new("TextLabel")
toast.Name = "TutorialToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, -70)
toast.Size = UDim2.fromOffset(390, 50)
toast.BackgroundColor3 = Color3.fromRGB(21, 29, 43)
toast.BackgroundTransparency = 0.08
toast.BorderSizePixel = 0
toast.Text = ""
toast.TextColor3 = Color3.fromRGB(234, 240, 249)
toast.Font = Enum.Font.GothamMedium
toast.TextSize = 13
toast.TextWrapped = true
toast.Visible = false
toast.ZIndex = 25
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 12)

local confirmationSound = Instance.new("Sound")
confirmationSound.Name = "TutorialConfirm"
confirmationSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
confirmationSound.Volume = 0.55
confirmationSound.Parent = gui

local warningSound = Instance.new("Sound")
warningSound.Name = "TutorialWaterWarning"
warningSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
warningSound.Volume = 0.7
warningSound.PlaybackSpeed = 0.72
warningSound.Parent = gui

local celebrationSound = Instance.new("Sound")
celebrationSound.Name = "TutorialCelebration"
celebrationSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
celebrationSound.Volume = 0.8
celebrationSound.PlaybackSpeed = 1.3
celebrationSound.Parent = gui

local FIREWORK_COLORS = {
	Color3.fromRGB(255, 203, 66),
	Color3.fromRGB(82, 213, 255),
	Color3.fromRGB(119, 255, 168),
	Color3.fromRGB(255, 111, 174),
	Color3.fromRGB(190, 128, 255),
}

local currentStage = 0
local currentStageId = ""
local currentTargetPosition
local currentTargetInstance
local stageSerial = 0
local helpRevealed = false
local dangerActive = false
local objectiveVisible = false
local waterWarningPlayed = false
local waypoint
local waypointBasePosition
local waypointAttachment
local rootAttachment
local beam
local targetHighlight
local animationStartedAt = 0
local toastSerial = 0
local successSerial = 0

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	objectiveScale.Scale = math.clamp(math.min((viewport.X - 24) / 430, (viewport.Y - 120) / 650), 0.72, 1)
end

local function updateStageDots(stage)
	for index, dot in ipairs(dots) do
		if index < stage then
			dot.BackgroundColor3 = Color3.fromRGB(103, 225, 155)
			dot.Size = UDim2.fromOffset(10, 5)
		elseif index == stage then
			dot.BackgroundColor3 = Color3.fromRGB(91, 210, 255)
			dot.Size = UDim2.fromOffset(22, 5)
		else
			dot.BackgroundColor3 = Color3.fromRGB(82, 94, 116)
			dot.Size = UDim2.fromOffset(10, 5)
		end
	end
end

local function inputFamily()
	local inputType = UserInputService:GetLastInputType()
	if string.find(inputType.Name, "Gamepad") then
		return "Gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

local CONTROL_TEXT = {
	Movement = { Keyboard = "WASD", Touch = "DIRECIONAL", Gamepad = "ANALÓGICO" },
	Jump = { Keyboard = "ESPAÇO", Touch = "PULO", Gamepad = "BOTÃO A" },
	Collectible = { Keyboard = "APROXIME-SE", Touch = "APROXIME-SE", Gamepad = "APROXIME-SE" },
	Combat = { Keyboard = "CLIQUE", Touch = "ATAQUE", Gamepad = "ATAQUE" },
	Water = { Keyboard = "SUBA", Touch = "SUBA", Gamepad = "SUBA" },
}

local DETAILED_HINTS = {
	Movement = { Keyboard = "Use WASD para seguir a luz.", Touch = "Use o direcional da tela.", Gamepad = "Use o analógico esquerdo." },
	Jump = { Keyboard = "Pressione Espaço enquanto avança.", Touch = "Toque no botão de pulo.", Gamepad = "Pressione o botão A." },
	Collectible = { Keyboard = "Encoste no fragmento brilhante.", Touch = "Encoste no fragmento brilhante.", Gamepad = "Encoste no fragmento brilhante." },
	Combat = { Keyboard = "Equipe a espada e clique no alvo.", Touch = "Equipe a espada e toque no ataque.", Gamepad = "Equipe a espada e use o ataque." },
	Water = { Keyboard = "Continue procurando plataformas mais altas.", Touch = "Continue procurando plataformas mais altas.", Gamepad = "Continue procurando plataformas mais altas." },
}

local function updateControlText()
	local family = inputFamily()
	local controls = CONTROL_TEXT[currentStageId]
	controlChip.Text = controls and (controls[family] or controls.Keyboard) or "OBJETIVO"
	if helpRevealed then
		local hints = DETAILED_HINTS[currentStageId]
		if hints then
			instructionLabel.Text = hints[family] or hints.Keyboard
		end
	end
end

local function clearTargetVisuals()
	if targetHighlight then
		targetHighlight:Destroy()
	end
	targetHighlight = nil

	if beam then
		beam:Destroy()
	end
	beam = nil
	if rootAttachment then
		rootAttachment:Destroy()
	end
	rootAttachment = nil
	if waypoint then
		waypoint:Destroy()
	end
	waypoint = nil
	waypointAttachment = nil
	waypointBasePosition = nil
	currentTargetPosition = nil
	currentTargetInstance = nil
	offscreenArrow.Visible = false
end

local function targetAdornee(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function createTargetVisual(position, targetInstance)
	clearTargetVisuals()
	if typeof(position) ~= "Vector3" then
		return
	end

	currentTargetPosition = position
	currentTargetInstance = targetInstance
	waypointBasePosition = position
	animationStartedAt = os.clock()

	waypoint = Instance.new("Part")
	waypoint.Name = "LocalTutorialWaypoint"
	waypoint.Shape = Enum.PartType.Ball
	waypoint.Size = Vector3.new(1.55, 1.55, 1.55)
	waypoint.CFrame = CFrame.new(position)
	waypoint.Anchored = true
	waypoint.CanCollide = false
	waypoint.CanTouch = false
	waypoint.CanQuery = false
	waypoint.CastShadow = false
	waypoint.Material = Enum.Material.Neon
	waypoint.Color = dangerActive and Color3.fromRGB(77, 196, 255) or Color3.fromRGB(94, 220, 255)
	waypoint.Transparency = 0.12
	waypoint.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = waypoint.Color
	light.Brightness = 1.5
	light.Range = 11
	light.Parent = waypoint

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "GuideParticles"
	particles.Color = ColorSequence.new(waypoint.Color)
	particles.LightEmission = 0.85
	particles.Lifetime = NumberRange.new(0.45, 0.8)
	particles.Speed = NumberRange.new(0.5, 1.8)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rate = 10
	particles.Parent = waypoint

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ObjectiveLabel"
	billboard.Adornee = waypoint
	billboard.Size = UDim2.fromOffset(190, 42)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	billboard.Parent = waypoint

	local label = Instance.new("TextLabel")
	label.Name = "Distance"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "OBJETIVO"
	label.TextColor3 = Color3.fromRGB(228, 249, 255)
	label.TextStrokeColor3 = Color3.fromRGB(5, 15, 25)
	label.TextStrokeTransparency = 0.12
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Parent = billboard

	waypointAttachment = Instance.new("Attachment")
	waypointAttachment.Name = "TutorialBeamEnd"
	waypointAttachment.Parent = waypoint

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = "LocalTutorialBeamStart"
		rootAttachment.Position = Vector3.new(0, -1.5, 0)
		rootAttachment.Parent = root

		beam = Instance.new("Beam")
		beam.Name = "LocalTutorialGuideBeam"
		beam.Attachment0 = rootAttachment
		beam.Attachment1 = waypointAttachment
		beam.Color = ColorSequence.new(waypoint.Color)
		beam.Width0 = 0.08
		beam.Width1 = 0.28
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.65),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		beam.FaceCamera = true
		beam.LightEmission = 0.8
		beam.Segments = 12
		beam.Parent = waypoint
	end

	local adornee = targetAdornee(targetInstance)
	if adornee then
		targetHighlight = Instance.new("Highlight")
		targetHighlight.Name = "LocalTutorialTargetHighlight"
		targetHighlight.Adornee = targetInstance
		targetHighlight.FillColor = currentStageId == "Combat"
			and Color3.fromRGB(255, 179, 65)
			or Color3.fromRGB(85, 210, 255)
		targetHighlight.OutlineColor = Color3.new(1, 1, 1)
		targetHighlight.FillTransparency = 0.58
		targetHighlight.OutlineTransparency = 0.05
		targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		targetHighlight.Parent = adornee
	end
end

local function showObjective()
	objective.Visible = true
	objectiveVisible = true
	objective.GroupTransparency = 0
	TweenService:Create(
		objective,
		TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 1, -24) }
	):Play()
end

local function hideObjective(delaySeconds)
	stageSerial += 1
	local serial = stageSerial
	task.delay(delaySeconds or 0, function()
		if serial ~= stageSerial then
			return
		end
		objectiveVisible = false
		clearTargetVisuals()
		local tween = TweenService:Create(
			objective,
			TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 1, 120), GroupTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Connect(function()
			if serial == stageSerial then
				objective.Visible = false
			end
		end)
	end)
end

local function updateProgress(progress, goal)
	goal = math.max(1, tonumber(goal) or 1)
	progress = math.clamp(tonumber(progress) or 0, 0, goal)
	progressTrack.Visible = goal > 1
	TweenService:Create(
		progressFill,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(progress / goal, 1) }
	):Play()
end

local function showToast(message, duration)
	toastSerial += 1
	local serial = toastSerial
	toast.Text = tostring(message or "")
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 0, -70)
	TweenService:Create(toast, TweenInfo.new(0.28, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0, 28),
	}):Play()
	task.delay(duration or 3, function()
		if serial ~= toastSerial or not toast.Visible then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.22), {
			Position = UDim2.new(0.5, 0, 0, -70),
		})
		tween:Play()
		tween.Completed:Connect(function()
			if serial == toastSerial then
				toast.Visible = false
			end
		end)
	end)
end

local function createFireworkBurst(position, color, scale)
	local anchor = Instance.new("Part")
	anchor.Name = "LocalTutorialFireworkBurst"
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3.5 * scale
	light.Range = 15 * scale
	light.Parent = anchor

	local burst = Instance.new("ParticleEmitter")
	burst.Name = "FireworkBurst"
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(color)
	burst.LightEmission = 1
	burst.Lifetime = NumberRange.new(0.65, 1.15)
	burst.Speed = NumberRange.new(13 * scale, 22 * scale)
	burst.Acceleration = Vector3.new(0, -16, 0)
	burst.Drag = 1.5
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.RotSpeed = NumberRange.new(-180, 180)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32 * scale),
		NumberSequenceKeypoint.new(0.65, 0.18 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.72, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Parent = anchor
	burst:Emit(math.floor(28 * scale))

	TweenService:Create(
		light,
		TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0, Range = 4 }
	):Play()
	Debris:AddItem(anchor, 1.6)
end

local function launchFirework(origin, offset, color, scale, delaySeconds)
	task.delay(delaySeconds or 0, function()
		local rocket = Instance.new("Part")
		rocket.Name = "LocalTutorialFireworkRocket"
		rocket.Shape = Enum.PartType.Ball
		rocket.Size = Vector3.one * (0.34 * scale)
		rocket.CFrame = CFrame.new(origin + offset)
		rocket.Material = Enum.Material.Neon
		rocket.Color = color
		rocket.Anchored = true
		rocket.CanCollide = false
		rocket.CanTouch = false
		rocket.CanQuery = false
		rocket.CastShadow = false
		rocket.Parent = workspace

		local attachment0 = Instance.new("Attachment")
		attachment0.Position = Vector3.new(0, -0.4, 0)
		attachment0.Parent = rocket
		local attachment1 = Instance.new("Attachment")
		attachment1.Position = Vector3.new(0, 0.4, 0)
		attachment1.Parent = rocket

		local trail = Instance.new("Trail")
		trail.Attachment0 = attachment0
		trail.Attachment1 = attachment1
		trail.Color = ColorSequence.new(color)
		trail.LightEmission = 1
		trail.Lifetime = 0.22
		trail.Transparency = NumberSequence.new(0.08, 1)
		trail.Parent = rocket

		local targetPosition = origin + offset + Vector3.new(0, 9 + scale * 3, 0)
		local rise = TweenService:Create(
			rocket,
			TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition }
		)
		rise:Play()
		rise.Completed:Connect(function()
			if rocket.Parent then
				createFireworkBurst(rocket.Position, color, scale)
				rocket:Destroy()
			end
		end)
		Debris:AddItem(rocket, 1)
	end)
end

local function playTutorialFireworks(finalCelebration)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	celebrationSound.PlaybackSpeed = finalCelebration and 1.08 or 1.3
	celebrationSound:Play()
	local origin = root.Position + Vector3.new(0, 1, 0)
	local burstCount = finalCelebration and 6 or 3
	for index = 1, burstCount do
		local angle = (index / burstCount) * math.pi * 2
		local radius = finalCelebration and 6.5 or 4.5
		local offset = Vector3.new(
			math.cos(angle) * radius,
			0,
			math.sin(angle) * radius
		)
		local color = FIREWORK_COLORS[((index - 1) % #FIREWORK_COLORS) + 1]
		launchFirework(
			origin,
			offset,
			color,
			finalCelebration and 1.2 or 0.9,
			(index - 1) * (finalCelebration and 0.11 or 0.08)
		)
	end
end

local function showSuccess(message, finalCelebration)
	successSerial += 1
	local serial = successSerial
	confirmationSound:Play()
	successLabel.Text = tostring(message or "✓")
	successLabel.TextSize = finalCelebration and 34 or 30
	successLabel.Visible = true
	successLabel.TextTransparency = 1
	successLabel.Size = UDim2.fromOffset(230, 60)
	TweenService:Create(
		successLabel,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextTransparency = 0, Size = UDim2.fromOffset(520, 100) }
	):Play()
	playTutorialFireworks(finalCelebration == true)
	task.delay(finalCelebration and 0.9 or 0.55, function()
		if serial ~= successSerial then
			return
		end
		TweenService:Create(successLabel, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		task.delay(0.26, function()
			if serial == successSerial then
				successLabel.Visible = false
			end
		end)
	end)
end

skipButton.Activated:Connect(function()
	skipButton.Active = false
	tutorialEvent:FireServer({ Action = "Skip" })
end)

UserInputService.LastInputTypeChanged:Connect(updateControlText)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
updateScale()

player.CharacterAdded:Connect(function()
	if objectiveVisible and currentTargetPosition then
		task.delay(0.4, function()
			if objectiveVisible and currentTargetPosition then
				createTargetVisual(currentTargetPosition, currentTargetInstance)
			end
		end)
	end
end)

RunService.RenderStepped:Connect(function()
	local elapsed = os.clock() - animationStartedAt

	if objectiveVisible then
		local chipPulse = (math.sin(elapsed * 4.2) + 1) * 0.5
		controlChip.BackgroundTransparency = 0.02 + chipPulse * 0.16
		objectiveStroke.Transparency = 0.12 + chipPulse * 0.2
	end

	for _, edge in pairs(warningEdges) do
		if dangerActive and objectiveVisible then
			edge.Visible = true
			edge.BackgroundTransparency = 0.35 + (math.sin(elapsed * 5) + 1) * 0.22
		else
			edge.Visible = false
			edge.BackgroundTransparency = 1
		end
	end

	if not waypoint or not waypoint.Parent or not waypointBasePosition then
		offscreenArrow.Visible = false
		return
	end

	local pulse = (math.sin(elapsed * 4) + 1) * 0.5
	local size = 1.4 + pulse * 0.45
	waypoint.Size = Vector3.new(size, size, size)
	waypoint.CFrame = CFrame.new(waypointBasePosition + Vector3.new(0, math.sin(elapsed * 2.6) * 0.35, 0))
	waypoint.Transparency = 0.08 + pulse * 0.2

	local billboard = waypoint:FindFirstChild("ObjectiveLabel")
	local distanceLabel = billboard and billboard:FindFirstChild("Distance")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and distanceLabel then
		distanceLabel.Text = string.format("OBJETIVO  •  %d STUDS", math.floor((root.Position - waypointBasePosition).Magnitude))
	end

	local camera = workspace.CurrentCamera
	if not camera then
		offscreenArrow.Visible = false
		return
	end
	local viewportPoint, onScreen = camera:WorldToViewportPoint(waypointBasePosition)
	if onScreen and viewportPoint.Z > 0 then
		offscreenArrow.Visible = false
		return
	end

	local viewport = camera.ViewportSize
	local center = viewport * 0.5
	local direction = Vector2.new(viewportPoint.X, viewportPoint.Y) - center
	if viewportPoint.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 0.01 then
		direction = Vector2.new(0, -1)
	else
		direction = direction.Unit
	end
	local margin = 58
	local scaleX = (viewport.X * 0.5 - margin) / math.max(0.01, math.abs(direction.X))
	local scaleY = (viewport.Y * 0.5 - margin) / math.max(0.01, math.abs(direction.Y))
	local edgeDistance = math.min(scaleX, scaleY)
	local position = center + direction * edgeDistance
	offscreenArrow.Position = UDim2.fromOffset(position.X, position.Y)
	offscreenArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	offscreenArrow.Visible = true
end)

tutorialEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end

	if data.Action == "Show" then
		stageSerial += 1
		local serial = stageSerial
		helpRevealed = false
		currentStage = tonumber(data.Stage) or 1
		currentStageId = tostring(data.StageId or "")
		dangerActive = data.Danger == true
		actionLabel.Text = tostring(data.ActionText or "OBJETIVO")
		instructionLabel.Text = data.WaitingForContext == true
			and "Encontrando um caminho seguro no mapa..."
			or tostring(data.Instruction or "")
		controlChip.Visible = data.WaitingForContext ~= true
		skipButton.Visible = true
		skipButton.Active = true
		updateStageDots(currentStage)
		updateProgress(data.Progress, data.Goal)
		updateControlText()

		if dangerActive and not waterWarningPlayed then
			waterWarningPlayed = true
			warningSound:Play()
			showToast("A ÁGUA ESTÁ SUBINDO — PROCURE UM LUGAR MAIS ALTO!", 3.2)
		end

		if data.WaitingForContext == true then
			clearTargetVisuals()
		else
			createTargetVisual(data.TargetPosition, data.TargetInstance)
		end
		showObjective()

		task.delay(tonumber(data.ShowHintAfterSeconds) or 5, function()
			if serial == stageSerial and objectiveVisible then
				helpRevealed = true
				updateControlText()
			end
		end)
	elseif data.Action == "Progress" then
		updateProgress(data.Progress, data.Goal)
		confirmationSound:Play()
	elseif data.Action == "StageComplete" then
		local stage = math.clamp(math.floor(tonumber(data.Stage) or currentStage), 1, 5)
		showSuccess(string.format("ETAPA %d CONCLUÍDA!", stage), false)
		clearTargetVisuals()
	elseif data.Action == "Complete" or data.Action == "Skipped" then
		stageSerial += 1
		currentStageId = ""
		dangerActive = false
		clearTargetVisuals()
		actionLabel.Text = tostring(data.ActionText or "CONTINUE SUBINDO")
		instructionLabel.Text = tostring(data.Instruction or "Sobreviva e alcance novas ilhas.")
		controlChip.Visible = false
		progressTrack.Visible = false
		skipButton.Visible = false
		updateStageDots(6)
		showObjective()
		if data.Action == "Complete" then
			showSuccess("TUTORIAL CONCLUÍDO!", true)
			if data.RewardPending == true then
				showToast("PRÊMIO LIBERADO — PREPARE-SE PARA A ROLETA!", 2.8)
			end
		else
			showSuccess("TUTORIAL ENCERRADO", false)
		end
		hideObjective(data.Action == "Complete" and 3.5 or 2.5)
	elseif data.Action == "RewardError" then
		showToast(data.Instruction or "Não foi possível abrir a recompensa.", 4)
	elseif data.Action == "ProtectionEnded" then
		showToast(data.Instruction or "A proteção inicial terminou.", 4)
	elseif data.Action == "Hide" then
		dangerActive = false
		hideObjective(0)
	end
end)

tutorialEvent:FireServer({ Action = "Ready" })
