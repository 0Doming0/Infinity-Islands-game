-- Aviso compacto para eventos aleatórios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("WorldEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "WorldEventUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 18
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "EventCard"
card.AnchorPoint = Vector2.new(0.5, 0)

-- Posição temporária até o Roblox calcular o tamanho real.
card.Position = UDim2.new(0.5, 0, 0, -1000)

card.Size = UDim2.new(1, -32, 0, 62)
card.BackgroundColor3 = Color3.fromRGB(27, 25, 40)
card.BackgroundTransparency = 0.42
card.BorderSizePixel = 0
card.Visible = true
card.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = card

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = Color3.fromRGB(255, 226, 110)
cardStroke.Thickness = 1
cardStroke.Transparency = 0.72
cardStroke.Parent = card

local cardConstraint = Instance.new("UISizeConstraint")
cardConstraint.MaxSize = Vector2.new(340, 62)
cardConstraint.MinSize = Vector2.new(240, 62)
cardConstraint.Parent = card

local text = Instance.new("TextLabel")
text.Name = "EventText"
text.Position = UDim2.fromOffset(10, 7)
text.Size = UDim2.new(1, -20, 1, -14)
text.BackgroundTransparency = 1
text.Text = ""
text.TextColor3 = Color3.fromRGB(255, 226, 110)
text.Font = Enum.Font.GothamMedium
text.TextSize = 14
text.TextWrapped = true
text.Parent = card

-- Configurações da animação.
local TOP_MARGIN = 138
local HIDDEN_MARGIN = 60

local CENTER_DISPLAY_TIME = 3
local ENTER_DURATION = 0.45
local MOVE_TO_TOP_DURATION = 0.35
local EXIT_DURATION = 0.3

local activeTween: Tween? = nil
local animationToken = 0
local eventActive = false

local function waitForCardSize()
	-- Aguarda o Roblox calcular AbsoluteSize.
	while card.AbsoluteSize.Y <= 0 do
		RunService.RenderStepped:Wait()
	end
end

local function getCardHeight()
	local height = card.AbsoluteSize.Y

	if height <= 0 then
		height = card.Size.Y.Offset
	end

	return height
end

local function getHiddenPosition()
	local cardHeight = getCardHeight()

	return UDim2.new(
		0.5,
		0,
		0,
		-(cardHeight + HIDDEN_MARGIN)
	)
end

local function getCenterPosition()
	local cardHeight = getCardHeight()

	-- Como AnchorPoint.Y é 0, descontamos metade da altura
	-- para que o centro visual do card fique no meio da tela.
	return UDim2.new(
		0.5,
		0,
		0.5,
		-math.floor(cardHeight / 2) + TOP_MARGIN
	)
end

local function getTopPosition()
	return UDim2.new(
		0.5,
		0,
		0,
		TOP_MARGIN
	)
end

local function cancelActiveTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function playTween(
	targetPosition: UDim2,
	duration: number,
	easingStyle: Enum.EasingStyle?,
	easingDirection: Enum.EasingDirection?
)
	cancelActiveTween()

	activeTween = TweenService:Create(
		card,
		TweenInfo.new(
			duration,
			easingStyle or Enum.EasingStyle.Quad,
			easingDirection or Enum.EasingDirection.Out
		),
		{
			Position = targetPosition,
		}
	)

	activeTween:Play()

	return activeTween
end

local function hideCard()
	animationToken += 1
	eventActive = false

	playTween(
		getHiddenPosition(),
		EXIT_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
end

local function showEvent(data)
	animationToken += 1

	local currentToken = animationToken
	eventActive = true

	text.Text = string.format(
		"%s\n%s",
		data.Title or "EVENTO",
		data.Message or ""
	)

	local eventColor =
		typeof(data.Color) == "Color3"
		and data.Color
		or Color3.fromRGB(255, 226, 110)

	text.TextColor3 = eventColor
	cardStroke.Color = eventColor

	waitForCardSize()

	-- Sempre começa completamente escondido.
	cancelActiveTween()
	card.Position = getHiddenPosition()

	-- Etapa 1: desce até o centro.
	local centerTween = playTween(
		getCenterPosition(),
		ENTER_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)

	centerTween.Completed:Wait()

	if animationToken ~= currentToken or not eventActive then
		return
	end

	-- Etapa 2: fica alguns segundos no centro.
	task.wait(CENTER_DISPLAY_TIME)

	if animationToken ~= currentToken or not eventActive then
		return
	end

	-- Etapa 3: sobe e permanece no topo enquanto o evento estiver ativo.
	playTween(
		getTopPosition(),
		MOVE_TO_TOP_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
end

-- Define corretamente a posição inicial após o cálculo do layout.
task.defer(function()
	waitForCardSize()
	card.Position = getHiddenPosition()
end)

remote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end

	if data.Action == "Start" then
		task.spawn(showEvent, data)
		return
	end

	if data.Action == "End"
		or data.Action == "Stop"
		or data.Action == "Finish"
	then
		hideCard()
	end
end)
