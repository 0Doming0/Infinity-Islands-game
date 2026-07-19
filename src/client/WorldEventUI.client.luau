
-- Aviso compacto para eventos aleatórios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage:WaitForChild("WorldEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "WorldEventUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 18
gui.IgnoreGuiInset = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0)

-- Posição temporária até o Roblox calcular o tamanho real.
card.Position = UDim2.new(0.5, 0, 0, -1000)

card.Size = UDim2.new(1, -32, 0, 62)
card.BackgroundColor3 = Color3.fromRGB(27, 25, 40)
card.BackgroundTransparency = 0.42
card.BorderSizePixel = 0
card.Parent = gui

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

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
text.Position = UDim2.fromOffset(10, 7)
text.Size = UDim2.new(1, -20, 1, -14)
text.BackgroundTransparency = 1
text.Text = ""
text.TextColor3 = Color3.fromRGB(255, 226, 110)
text.Font = Enum.Font.GothamMedium
text.TextSize = 14
text.TextWrapped = true
text.Parent = card

-- Espaço adicional entre o card escondido e o topo da tela.
local HIDDEN_MARGIN = 16

local function getHiddenPosition()
	local cardHeight = card.AbsoluteSize.Y

	-- Proteção para o primeiro frame, antes de AbsoluteSize ser calculado.
	if cardHeight <= 0 then
		cardHeight = card.Size.Y.Offset
	end

	return UDim2.new(
		0.5,
		0,
		0,
		-(cardHeight + HIDDEN_MARGIN)
	)
end

-- Ajusta a posição inicial depois que o tamanho real da UI for calculado.
task.defer(function()
	card.Position = getHiddenPosition()
end)

local token = 0

remote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Action ~= "Start" then
		return
	end

	token += 1
	local current = token

	text.Text = string.format(
		"%s\n%s",
		data.Title or "EVENTO",
		data.Message or ""
	)
	local eventColor = typeof(data.Color) == "Color3" and data.Color or Color3.fromRGB(255, 226, 110)
	text.TextColor3 = eventColor
	cardStroke.Color = eventColor

	TweenService:Create(
		card,
		TweenInfo.new(0.3, Enum.EasingStyle.Back),
		{
			Position = UDim2.new(0.5, 0, 0, 34),
		}
	):Play()

	task.delay(5, function()
		if token ~= current then
			return
		end

		TweenService:Create(
			card,
			TweenInfo.new(0.25),
			{
				Position = getHiddenPosition(),
			}
		):Play()
	end)
end)

