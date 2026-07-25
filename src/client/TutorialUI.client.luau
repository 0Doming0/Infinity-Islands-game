-- Interface do tutorial contextual. A validacao dos objetivos permanece no
-- servidor; este script adapta os textos ao controle e desenha o marcador local.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local tutorialEvent = ReplicatedStorage:WaitForChild("TutorialEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 24
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, -180)
card.Size = UDim2.new(1, -24, 0, 132)
card.BackgroundColor3 = Color3.fromRGB(19, 24, 39)
card.BackgroundTransparency = 0.12
card.BorderSizePixel = 0
card.Visible = false
card.Parent = gui

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(86, 205, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.25
stroke.Parent = card

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(280, 132)
sizeConstraint.MaxSize = Vector2.new(410, 132)
sizeConstraint.Parent = card

local header = Instance.new("TextLabel")
header.Name = "Header"
header.Position = UDim2.fromOffset(14, 9)
header.Size = UDim2.new(1, -120, 0, 18)
header.BackgroundTransparency = 1
header.Text = "TUTORIAL"
header.TextColor3 = Color3.fromRGB(86, 205, 255)
header.Font = Enum.Font.GothamBold
header.TextSize = 14
header.TextXAlignment = Enum.TextXAlignment.Left
header.Parent = card

local stepLabel = Instance.new("TextLabel")
stepLabel.Name = "Step"
stepLabel.AnchorPoint = Vector2.new(1, 0)
stepLabel.Position = UDim2.new(1, -14, 0, 9)
stepLabel.Size = UDim2.fromOffset(92, 18)
stepLabel.BackgroundTransparency = 1
stepLabel.Text = "ETAPA 1/5"
stepLabel.TextColor3 = Color3.fromRGB(172, 187, 210)
stepLabel.Font = Enum.Font.GothamMedium
stepLabel.TextSize = 12
stepLabel.TextXAlignment = Enum.TextXAlignment.Right
stepLabel.Parent = card

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(14, 31)
title.Size = UDim2.new(1, -28, 0, 21)
title.BackgroundTransparency = 1
title.Text = "MOVIMENTO"
title.TextColor3 = Color3.fromRGB(255, 231, 142)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = card

local instruction = Instance.new("TextLabel")
instruction.Name = "Instruction"
instruction.Position = UDim2.fromOffset(14, 53)
instruction.Size = UDim2.new(1, -28, 0, 24)
instruction.BackgroundTransparency = 1
instruction.Text = ""
instruction.TextColor3 = Color3.fromRGB(243, 246, 252)
instruction.Font = Enum.Font.GothamMedium
instruction.TextSize = 14
instruction.TextWrapped = true
instruction.TextXAlignment = Enum.TextXAlignment.Left
instruction.TextYAlignment = Enum.TextYAlignment.Top
instruction.Parent = card

local controlHint = Instance.new("TextLabel")
controlHint.Name = "ControlHint"
controlHint.Position = UDim2.fromOffset(14, 79)
controlHint.Size = UDim2.new(1, -92, 0, 39)
controlHint.BackgroundTransparency = 1
controlHint.Text = ""
controlHint.TextColor3 = Color3.fromRGB(172, 187, 210)
controlHint.Font = Enum.Font.Gotham
controlHint.TextSize = 12
controlHint.TextWrapped = true
controlHint.TextXAlignment = Enum.TextXAlignment.Left
controlHint.TextYAlignment = Enum.TextYAlignment.Top
controlHint.Parent = card

local progress = Instance.new("TextLabel")
progress.Name = "Progress"
progress.AnchorPoint = Vector2.new(1, 1)
progress.Position = UDim2.new(1, -14, 1, -10)
progress.Size = UDim2.fromOffset(52, 20)
progress.BackgroundColor3 = Color3.fromRGB(37, 48, 68)
progress.BorderSizePixel = 0
progress.Text = "0/1"
progress.TextColor3 = Color3.fromRGB(255, 231, 142)
progress.Font = Enum.Font.GothamBold
progress.TextSize = 12
progress.Parent = card
Instance.new("UICorner", progress).CornerRadius = UDim.new(1, 0)

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AnchorPoint = Vector2.new(0, 1)
skipButton.Position = UDim2.new(0, 14, 1, -8)
skipButton.Size = UDim2.fromOffset(64, 22)
skipButton.BackgroundTransparency = 1
skipButton.Text = "PULAR"
skipButton.TextColor3 = Color3.fromRGB(148, 162, 184)
skipButton.Font = Enum.Font.GothamBold
skipButton.TextSize = 11
skipButton.TextXAlignment = Enum.TextXAlignment.Left
skipButton.Parent = card

-- Abaixo do aviso de evento e do popup de moeda (+1 ¤), para que a etapa de
-- coleta mostre as duas informacoes sem sobreposicao em telas estreitas.
local shownPosition = UDim2.new(0.5, 0, 0, 145)
local hiddenPosition = UDim2.new(0.5, 0, 0, -180)
local currentStageId = ""
local stageSerial = 0
local helpRevealed = false
local waypoint
local waypointBasePosition
local waypointLabel
local animationStartedAt = 0
local tutorialHighlight

local function clearTutorialHighlight()
	if tutorialHighlight then
		tutorialHighlight:Destroy()
	end
	tutorialHighlight = nil
end

local function highlightCombatControl()
	clearTutorialHighlight()
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local sword
	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and (child:GetAttribute("IsSword") == true or child:GetAttribute("WeaponType") == "Sword") then
					sword = child
					break
				end
			end
		end
		if sword then
			break
		end
	end
	local handle = sword and sword:FindFirstChild("Handle")
	if handle and not handle:IsDescendantOf(workspace) and character then
		local backDisplay = character:FindFirstChild("EquippedSwordBackDisplay")
		handle = backDisplay and backDisplay:FindFirstChild("Handle", true) or handle
	end
	if handle and handle:IsA("BasePart") then
		tutorialHighlight = Instance.new("Highlight")
		tutorialHighlight.Name = "TutorialSwordHighlight"
		tutorialHighlight.Adornee = handle
		tutorialHighlight.FillColor = Color3.fromRGB(255, 214, 80)
		tutorialHighlight.OutlineColor = Color3.new(1, 1, 1)
		tutorialHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		tutorialHighlight.Parent = handle
	end
end

local function destroyWaypoint()
	if waypoint then
		waypoint:Destroy()
	end
	waypoint = nil
	waypointLabel = nil
	waypointBasePosition = nil
	clearTutorialHighlight()
end

local function createWaypoint(position)
	destroyWaypoint()
	if typeof(position) ~= "Vector3" then
		return
	end
	waypointBasePosition = position
	animationStartedAt = os.clock()

	waypoint = Instance.new("Part")
	waypoint.Name = "LocalTutorialWaypoint"
	waypoint.Shape = Enum.PartType.Ball
	waypoint.Size = Vector3.new(1.5, 1.5, 1.5)
	waypoint.CFrame = CFrame.new(position)
	waypoint.Anchored = true
	waypoint.CanCollide = false
	waypoint.CanTouch = false
	waypoint.CanQuery = false
	waypoint.CastShadow = false
	waypoint.Material = Enum.Material.Neon
	waypoint.Color = Color3.fromRGB(86, 205, 255)
	waypoint.Transparency = 0.18
	waypoint.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = waypoint.Color
	light.Brightness = 1.3
	light.Range = 9
	light.Parent = waypoint

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ObjectiveLabel"
	billboard.Adornee = waypoint
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
	billboard.Parent = waypoint

	waypointLabel = Instance.new("TextLabel")
	waypointLabel.Size = UDim2.fromScale(1, 1)
	waypointLabel.BackgroundTransparency = 1
	waypointLabel.Text = "OBJETIVO"
	waypointLabel.TextColor3 = Color3.fromRGB(225, 247, 255)
	waypointLabel.TextStrokeColor3 = Color3.fromRGB(8, 17, 31)
	waypointLabel.TextStrokeTransparency = 0.15
	waypointLabel.Font = Enum.Font.GothamBold
	waypointLabel.TextSize = 13
	waypointLabel.Parent = billboard
end

local function controlFamily()
	local input = UserInputService:GetLastInputType()
	if string.find(input.Name, "Gamepad") then
		return "Gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

local CONTROL_HINTS = {
	Movement = {
		Keyboard = "Use WASD para se mover.",
		Touch = "Use o direcional na tela para se mover.",
		Gamepad = "Use o analógico esquerdo para se mover.",
	},
	Jump = {
		Keyboard = "Pressione Espaço enquanto avança.",
		Touch = "Toque no botão de pulo enquanto avança.",
		Gamepad = "Pressione o botão de pulo enquanto avança.",
	},
	Collectible = {
		Keyboard = "Aproxime-se do fragmento para coletá-lo.",
		Touch = "Aproxime-se do fragmento para coletá-lo.",
		Gamepad = "Aproxime-se do fragmento para coletá-lo.",
	},
	Combat = {
		Keyboard = "Selecione a espada na barra e clique para atacar.",
		Touch = "Selecione a espada na barra e toque para atacar.",
		Gamepad = "Equipe a espada e use o botão de ataque.",
	},
	Water = {
		Keyboard = "Procure sempre os blocos mais altos.",
		Touch = "Procure sempre os blocos mais altos.",
		Gamepad = "Procure sempre os blocos mais altos.",
	},
}

local function updateControlHint()
	if not helpRevealed then
		controlHint.Text = ""
		return
	end
	local hints = CONTROL_HINTS[currentStageId]
	if hints then
		controlHint.Text = hints[controlFamily()] or hints.Keyboard
	end
end

local function showCard()
	card.Visible = true
	TweenService:Create(card, TweenInfo.new(0.32, Enum.EasingStyle.Back), {
		Position = shownPosition,
	}):Play()
end

local function hideCard(delaySeconds)
	task.delay(delaySeconds or 0, function()
		destroyWaypoint()
		local tween = TweenService:Create(card, TweenInfo.new(0.24), {
			Position = hiddenPosition,
		})
		tween:Play()
		tween.Completed:Once(function()
			card.Visible = false
		end)
	end)
end

skipButton.Activated:Connect(function()
	skipButton.Active = false
	tutorialEvent:FireServer({ Action = "Skip" })
end)

UserInputService.LastInputTypeChanged:Connect(function()
	updateControlHint()
end)

RunService.RenderStepped:Connect(function()
	if not waypoint or not waypoint.Parent or not waypointBasePosition then
		return
	end
	local elapsed = os.clock() - animationStartedAt
	local pulse = (math.sin(elapsed * 4) + 1) * 0.5
	local size = 1.35 + pulse * 0.4
	waypoint.Size = Vector3.new(size, size, size)
	waypoint.CFrame = CFrame.new(waypointBasePosition + Vector3.new(0, math.sin(elapsed * 2.5) * 0.35, 0))
	waypoint.Transparency = 0.12 + pulse * 0.22
	if waypointLabel then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			waypointLabel.Text = string.format("OBJETIVO  |  %d STUDS", math.floor((root.Position - waypointBasePosition).Magnitude))
		else
			waypointLabel.Text = "OBJETIVO"
		end
	end
end)

tutorialEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "Show" then
		stageSerial += 1
		local shownSerial = stageSerial
		helpRevealed = false
		currentStageId = tostring(data.StageId or "")
		header.Text = "TUTORIAL"
		stepLabel.Text = string.format("ETAPA %d/%d", tonumber(data.Stage) or 1, tonumber(data.TotalStages) or 5)
		title.Text = tostring(data.Title or "OBJETIVO")
		instruction.Text = tostring(data.Instruction or "")
		if data.WaitingForContext == true then
			instruction.Text ..= " Procurando um ponto seguro..."
		end
		progress.Text = string.format("%d/%d", tonumber(data.Progress) or 0, tonumber(data.Goal) or 1)
		skipButton.Visible = true
		skipButton.Active = true
		updateControlHint()
		if currentStageId == "Combat" then
			highlightCombatControl()
		end
		task.delay(tonumber(data.ShowHintAfterSeconds) or 6, function()
			if shownSerial == stageSerial and card.Visible then
				helpRevealed = true
				updateControlHint()
			end
		end)
		createWaypoint(data.TargetPosition)
		showCard()
	elseif data.Action == "Complete" or data.Action == "Skipped" then
		stageSerial += 1
		helpRevealed = false
		currentStageId = ""
		header.Text = data.Action == "Complete" and "TUTORIAL CONCLUÍDO" or "TUTORIAL"
		stepLabel.Text = ""
		title.Text = tostring(data.Title or "VOCÊ ESTÁ PRONTO!")
		instruction.Text = tostring(data.Instruction or "Continue subindo!")
		controlHint.Text = ""
		progress.Text = "OK"
		skipButton.Visible = false
		destroyWaypoint()
		showCard()
		hideCard(data.Action == "Complete" and 4 or 2.5)
	elseif data.Action == "Hide" then
		stageSerial += 1
		helpRevealed = false
		hideCard(0)
	end
end)

tutorialEvent:FireServer({ Action = "Ready" })
