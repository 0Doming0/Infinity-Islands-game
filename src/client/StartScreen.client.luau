-- Tela inicial segura: o personagem real só existe depois do clique em INICIAR.
-- A vitrine usa um modelo local, portanto não pode receber dano da água ou mobs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
if player:GetAttribute("InitialGameStarted") == true then
	return
end

local request = ReplicatedStorage:WaitForChild("StartGameRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "StartScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 5000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(4, 9, 12)
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local backdropGradient = Instance.new("UIGradient")
backdropGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 28, 32)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(5, 13, 18)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 10, 27)),
})
backdropGradient.Rotation = 25
backdropGradient.Parent = backdrop

local panel = Instance.new("Frame")
panel.Name = "Main"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(940, 560)
panel.BackgroundColor3 = Color3.fromRGB(11, 19, 23)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = backdrop

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 24)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(73, 157, 133)
panelStroke.Transparency = 0.45
panelStroke.Thickness = 2
panelStroke.Parent = panel

local scale = Instance.new("UIScale")
scale.Parent = panel

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / 1020, viewport.Y / 640), 0.58, 1)
end
updateScale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local preview = Instance.new("ViewportFrame")
preview.Name = "CharacterPreview"
preview.Position = UDim2.fromOffset(0, 0)
preview.Size = UDim2.fromOffset(520, 560)
preview.BackgroundColor3 = Color3.fromRGB(13, 34, 35)
preview.BorderSizePixel = 0
preview.Ambient = Color3.fromRGB(145, 166, 170)
preview.LightColor = Color3.fromRGB(255, 244, 220)
preview.LightDirection = Vector3.new(-1, -0.5, -1)
preview.Parent = panel

local previewGradient = Instance.new("UIGradient")
previewGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 67, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 20, 27)),
})
previewGradient.Rotation = 90
previewGradient.Parent = preview

local worldModel = Instance.new("WorldModel")
worldModel.Parent = preview
local previewCamera = Instance.new("Camera")
previewCamera.FieldOfView = 34
previewCamera.CFrame = CFrame.lookAt(Vector3.new(8, 3.8, 12), Vector3.new(0, 2.7, 0))
previewCamera.Parent = preview
preview.CurrentCamera = previewCamera

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(30, 26)
title.Size = UDim2.new(1, -60, 0, 54)
title.BackgroundTransparency = 1
title.Text = "SKY DUNGEON"
title.TextColor3 = Color3.fromRGB(234, 255, 246)
title.Font = Enum.Font.GothamBlack
title.TextSize = 34
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 5
title.Parent = preview

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(32, 78)
subtitle.Size = UDim2.new(1, -64, 0, 28)
subtitle.BackgroundTransparency = 1
subtitle.Text = "SEU PROGRESSO ESTÁ PRONTO PARA A PRÓXIMA SUBIDA"
subtitle.TextColor3 = Color3.fromRGB(144, 218, 187)
subtitle.Font = Enum.Font.GothamBold
subtitle.TextSize = 10
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 5
subtitle.Parent = preview

local info = Instance.new("Frame")
info.Position = UDim2.fromOffset(520, 0)
info.Size = UDim2.new(1, -520, 1, 0)
info.BackgroundColor3 = Color3.fromRGB(10, 17, 22)
info.BorderSizePixel = 0
info.Parent = panel

local function label(parent, text, position, size, textSize, color, font)
	local item = Instance.new("TextLabel")
	item.Position = position
	item.Size = size
	item.BackgroundTransparency = 1
	item.Text = text
	item.TextColor3 = color or Color3.fromRGB(234, 244, 240)
	item.Font = font or Enum.Font.Gotham
	item.TextSize = textSize
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextWrapped = true
	item.Parent = parent
	return item
end

label(
	info,
	"SEU AVENTUREIRO",
	UDim2.fromOffset(32, 28),
	UDim2.new(1, -64, 0, 28),
	18,
	Color3.fromRGB(238, 248, 244),
	Enum.Font.GothamBold
)

local recordValue = label(
	info,
	"RECORDE  —",
	UDim2.fromOffset(32, 65),
	UDim2.new(1, -64, 0, 40),
	24,
	Color3.fromRGB(255, 214, 94),
	Enum.Font.GothamBlack
)

local coinsValue = label(
	info,
	"MOEDAS  —",
	UDim2.fromOffset(32, 101),
	UDim2.new(1, -64, 0, 24),
	12,
	Color3.fromRGB(176, 194, 187),
	Enum.Font.GothamBold
)

local equipmentTitle = label(
	info,
	"EQUIPAMENTOS ATUAIS",
	UDim2.fromOffset(32, 145),
	UDim2.new(1, -64, 0, 20),
	10,
	Color3.fromRGB(111, 191, 158),
	Enum.Font.GothamBold
)
equipmentTitle.TextTransparency = 0.05

local function equipmentCard(y, heading)
	local card = Instance.new("Frame")
	card.Position = UDim2.fromOffset(28, y)
	card.Size = UDim2.new(1, -56, 0, 64)
	card.BackgroundColor3 = Color3.fromRGB(19, 31, 35)
	card.BorderSizePixel = 0
	card.Parent = info
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(64, 105, 94)
	stroke.Transparency = 0.58
	stroke.Parent = card
	label(
		card,
		heading,
		UDim2.fromOffset(15, 7),
		UDim2.new(1, -30, 0, 16),
		9,
		Color3.fromRGB(130, 159, 149),
		Enum.Font.GothamBold
	)
	return label(
		card,
		"—",
		UDim2.fromOffset(15, 23),
		UDim2.new(1, -30, 0, 32),
		13,
		Color3.fromRGB(235, 245, 241),
		Enum.Font.GothamBold
	)
end

local swordValue = equipmentCard(174, "ESPADA")
local relicValue = equipmentCard(246, "RELÍQUIA")
local companionsValue = equipmentCard(318, "COMPANHEIROS EQUIPADOS")
companionsValue.TextSize = 11

local status = label(
	info,
	"CARREGANDO DADOS...",
	UDim2.fromOffset(32, 405),
	UDim2.new(1, -64, 0, 26),
	10,
	Color3.fromRGB(137, 172, 159),
	Enum.Font.GothamBold
)
status.TextXAlignment = Enum.TextXAlignment.Center

local startButton = Instance.new("TextButton")
startButton.AnchorPoint = Vector2.new(0.5, 0)
startButton.Position = UDim2.new(0.5, 0, 0, 442)
startButton.Size = UDim2.new(1, -64, 0, 66)
startButton.BackgroundColor3 = Color3.fromRGB(42, 76, 64)
startButton.BorderSizePixel = 0
startButton.Text = "AGUARDE..."
startButton.TextColor3 = Color3.fromRGB(159, 184, 174)
startButton.Font = Enum.Font.GothamBlack
startButton.TextSize = 20
startButton.AutoButtonColor = false
startButton.Active = false
startButton.Parent = info
local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 16)
buttonCorner.Parent = startButton
local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(122, 225, 176)
buttonStroke.Transparency = 0.7
buttonStroke.Thickness = 2
buttonStroke.Parent = startButton

local hint = label(
	info,
	"Seu personagem só aparecerá no mapa depois deste clique.",
	UDim2.fromOffset(32, 515),
	UDim2.new(1, -64, 0, 24),
	9,
	Color3.fromRGB(101, 127, 118),
	Enum.Font.Gotham
)
hint.TextXAlignment = Enum.TextXAlignment.Center

local previewCharacter

local function createFallbackCharacter()
	local model = Instance.new("Model")
	model.Name = "PreviewCharacter"
	local colors = {
		{ "Torso", Vector3.new(2.2, 2.6, 1.1), CFrame.new(0, 2.9, 0), Color3.fromRGB(55, 115, 156) },
		{ "Head", Vector3.new(1.65, 1.65, 1.65), CFrame.new(0, 5.0, 0), Color3.fromRGB(210, 162, 125) },
		{ "LeftArm", Vector3.new(0.8, 2.5, 0.8), CFrame.new(-1.55, 3.0, 0), Color3.fromRGB(210, 162, 125) },
		{ "RightArm", Vector3.new(0.8, 2.5, 0.8), CFrame.new(1.55, 3.0, 0), Color3.fromRGB(210, 162, 125) },
		{ "LeftLeg", Vector3.new(0.9, 2.6, 0.9), CFrame.new(-0.62, 0.35, 0), Color3.fromRGB(32, 49, 70) },
		{ "RightLeg", Vector3.new(0.9, 2.6, 0.9), CFrame.new(0.62, 0.35, 0), Color3.fromRGB(32, 49, 70) },
	}
	for _, spec in ipairs(colors) do
		local part = Instance.new("Part")
		part.Name = spec[1]
		part.Size = spec[2]
		part.CFrame = spec[3]
		part.Color = spec[4]
		part.Anchored = true
		part.CanCollide = false
		part.Parent = model
	end
	return model
end

local function loadPreviewCharacter()
	local success, model = pcall(Players.CreateHumanoidModelFromUserId, Players, player.UserId)
	if not success or not model then
		model = createFallbackCharacter()
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	model.Name = "PreviewCharacter"
	model.Parent = worldModel
	model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(-18), 0))
	previewCharacter = model
end
task.spawn(loadPreviewCharacter)

local equipmentFolder = Instance.new("Folder")
equipmentFolder.Name = "PreviewEquipment"
equipmentFolder.Parent = worldModel

local function clearEquipment()
	for _, child in ipairs(equipmentFolder:GetChildren()) do
		child:Destroy()
	end
end

local function makePart(name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Parent = equipmentFolder
	return part
end

local function renderEquipment(snapshot)
	clearEquipment()
	local sword = snapshot.Sword
	if sword then
		makePart(
			"SwordBlade",
			Vector3.new(0.28, 4.2, 0.45),
			CFrame.new(2.1, 2.4, 0.25) * CFrame.Angles(0, 0, math.rad(-18)),
			sword.Color or Color3.fromRGB(205, 215, 225),
			Enum.Material.Neon
		)
		makePart(
			"SwordHandle",
			Vector3.new(0.45, 1.2, 0.55),
			CFrame.new(1.72, 0.2, 0.25) * CFrame.Angles(0, 0, math.rad(-18)),
			sword.AccentColor or Color3.fromRGB(91, 62, 39),
			Enum.Material.Metal
		)
	end
	if snapshot.Relic then
		local orb = makePart(
			"Relic",
			Vector3.new(0.85, 0.85, 0.85),
			CFrame.new(-1.9, 4.7, 0),
			snapshot.Relic.Color or Color3.fromRGB(180, 110, 255),
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		local light = Instance.new("PointLight")
		light.Color = orb.Color
		light.Brightness = 1.8
		light.Range = 7
		light.Parent = orb
	end
	for index, companion in ipairs(snapshot.Companions or {}) do
		local x = (index - 1.5) * 2.2
		if #snapshot.Companions == 1 then
			x = -2.5
		end
		local slime = makePart(
			"Companion_" .. index,
			Vector3.new(1.5, 1.25, 1.5),
			CFrame.new(x, -0.35, 1.6),
			companion.Color or Color3.fromRGB(91, 219, 128),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
		for direction = -1, 1, 2 do
			makePart(
				"Eye",
				Vector3.new(0.18, 0.25, 0.12),
				slime.CFrame * CFrame.new(direction * 0.28, 0.12, -0.72),
				Color3.fromRGB(20, 30, 30),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Ball
			)
		end
	end
end

local ready = false
local starting = false

local function applySnapshot(snapshot)
	recordValue.Text = string.format("RECORDE  %d", math.max(0, tonumber(snapshot.BestScore) or 0))
	coinsValue.Text = string.format("MOEDAS  %d ¤", math.max(0, tonumber(snapshot.Coins) or 0))
	swordValue.Text = snapshot.Sword and snapshot.Sword.DisplayName or "Espada inicial"
	relicValue.Text = snapshot.Relic and snapshot.Relic.DisplayName or "Nenhuma equipada"
	local names = {}
	for _, companion in ipairs(snapshot.Companions or {}) do
		table.insert(names, string.format("%s Nv.%d", companion.DisplayName, companion.Level))
	end
	companionsValue.Text = #names > 0 and table.concat(names, "  •  ") or "Nenhum equipado"
	renderEquipment(snapshot)
end

local function setReady()
	ready = true
	status.Text = "MUNDO PRONTO"
	status.TextColor3 = Color3.fromRGB(117, 225, 168)
	startButton.Text = "INICIAR"
	startButton.BackgroundColor3 = Color3.fromRGB(36, 159, 93)
	startButton.TextColor3 = Color3.fromRGB(247, 255, 251)
	startButton.AutoButtonColor = true
	startButton.Active = true
	buttonStroke.Transparency = 0.2
end

task.spawn(function()
	while gui.Parent and not ready and not starting do
		local success, response = pcall(request.InvokeServer, request, "Get")
		if success and response then
			if response.Snapshot then
				applySnapshot(response.Snapshot)
			end
			if response.Ready then
				setReady()
				return
			end
			if response.State == "PreparingWorld" then
				status.Text = "PREPARANDO O MUNDO..."
			else
				status.Text = "CARREGANDO SEU PROGRESSO..."
			end
		end
		task.wait(0.4)
	end
end)

local function finishStart()
	local tween = TweenService:Create(
		backdrop,
		TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	for _, descendant in ipairs(backdrop:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			TweenService:Create(descendant, TweenInfo.new(0.42), {
				BackgroundTransparency = 1,
			}):Play()
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				TweenService:Create(descendant, TweenInfo.new(0.35), {
					TextTransparency = 1,
				}):Play()
			end
		end
	end
	tween:Play()
	tween.Completed:Wait()
	gui:Destroy()
end

startButton.Activated:Connect(function()
	if not ready or starting then
		return
	end
	starting = true
	startButton.Active = false
	startButton.AutoButtonColor = false
	startButton.Text = "POSICIONANDO..."
	status.Text = "CRIANDO PERSONAGEM EM ÁREA SEGURA"
	local success, response = pcall(request.InvokeServer, request, "Start")
	if not success or not response or response.Success ~= true then
		starting = false
		status.Text = response and response.Message or "NÃO FOI POSSÍVEL INICIAR"
		setReady()
		return
	end
	local deadline = os.clock() + 20
	while
		gui.Parent
		and os.clock() < deadline
		and (
			not player.Character
			or not player.Character:FindFirstChild("HumanoidRootPart")
			or player:GetAttribute("InitialSpawnPositioned") ~= true
		)
	do
		RunService.Heartbeat:Wait()
	end
	if player.Character and player:GetAttribute("InitialSpawnPositioned") == true then
		status.Text = "BOA SUBIDA!"
		finishStart()
	else
		starting = false
		status.Text = "O MAPA DEMOROU PARA RESPONDER. TENTE NOVAMENTE."
		setReady()
	end
end)
