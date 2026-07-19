-- SkyDungeon - HUD minimalista para computador, controle e celular.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local waterEvent = ReplicatedStorage:WaitForChild("WaterEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Position = UDim2.fromOffset(12, 12)
hud.Size = UDim2.fromOffset(230, 72)
hud.BackgroundColor3 = Color3.fromRGB(12, 18, 29)
hud.BackgroundTransparency = 0.28
hud.BorderSizePixel = 0
hud.Parent = screenGui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 11)
hudCorner.Parent = hud

local hudStroke = Instance.new("UIStroke")
hudStroke.Color = Color3.fromRGB(118, 151, 184)
hudStroke.Transparency = 0.68
hudStroke.Thickness = 1
hudStroke.Parent = hud

local function createLabel(name, position, size, text, color, font, textSize, alignment)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Position = position
	item.Size = size
	item.BackgroundTransparency = 1
	item.Text = text
	item.TextColor3 = color
	item.Font = font
	item.TextSize = textSize
	item.TextXAlignment = alignment or Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = hud
	return item
end

local scoreLabel = createLabel(
	"Score",
	UDim2.fromOffset(12, 7),
	UDim2.fromOffset(112, 25),
	"⭐ 0",
	Color3.fromRGB(255, 220, 102),
	Enum.Font.GothamMedium,
	16
)

local coinLabel = createLabel(
	"Coins",
	UDim2.fromOffset(122, 7),
	UDim2.fromOffset(96, 25),
	"🪙 0",
	Color3.fromRGB(255, 196, 66),
	Enum.Font.GothamMedium,
	13,
	Enum.TextXAlignment.Right
)

local waterLabel = createLabel(
	"WaterDistance",
	UDim2.fromOffset(12, 34),
	UDim2.fromOffset(206, 22),
	"🌊  --m abaixo",
	Color3.fromRGB(139, 207, 255),
	Enum.Font.GothamMedium,
	13
)

local barBackground = Instance.new("Frame")
barBackground.Name = "WaterDanger"
barBackground.Position = UDim2.fromOffset(12, 61)
barBackground.Size = UDim2.fromOffset(206, 3)
barBackground.BackgroundColor3 = Color3.fromRGB(54, 68, 88)
barBackground.BackgroundTransparency = 0.25
barBackground.BorderSizePixel = 0
barBackground.ClipsDescendants = true
barBackground.Parent = hud

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBackground

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(72, 177, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

local warning = Instance.new("TextLabel")
warning.Name = "Warning"
warning.Position = UDim2.fromOffset(12, 91)
warning.Size = UDim2.fromOffset(230, 34)
warning.BackgroundColor3 = Color3.fromRGB(138, 44, 42)
warning.BackgroundTransparency = 0.18
warning.BorderSizePixel = 0
warning.Text = ""
warning.TextColor3 = Color3.fromRGB(255, 243, 238)
warning.Font = Enum.Font.GothamBold
warning.TextSize = 13
warning.TextWrapped = true
warning.Visible = false
warning.Parent = screenGui

local warningCorner = Instance.new("UICorner")
warningCorner.CornerRadius = UDim.new(0, 9)
warningCorner.Parent = warning

local resultCard = Instance.new("Frame")
resultCard.Name = "ResultCard"
resultCard.Position = UDim2.fromOffset(12, 132)
resultCard.Size = UDim2.fromOffset(230, 58)
resultCard.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
resultCard.BackgroundTransparency = 0.12
resultCard.BorderSizePixel = 0
resultCard.Visible = false
resultCard.Parent = screenGui

local resultCorner = Instance.new("UICorner")
resultCorner.CornerRadius = UDim.new(0, 10)
resultCorner.Parent = resultCard

local resultStroke = Instance.new("UIStroke")
resultStroke.Color = Color3.fromRGB(255, 104, 104)
resultStroke.Transparency = 0.38
resultStroke.Parent = resultCard

local resultText = Instance.new("TextLabel")
resultText.Name = "Text"
resultText.Position = UDim2.fromOffset(10, 5)
resultText.Size = UDim2.new(1, -20, 1, -10)
resultText.BackgroundTransparency = 1
resultText.Text = ""
resultText.TextColor3 = Color3.fromRGB(255, 225, 225)
resultText.Font = Enum.Font.GothamBold
resultText.TextSize = 14
resultText.TextWrapped = true
resultText.TextXAlignment = Enum.TextXAlignment.Left
resultText.TextYAlignment = Enum.TextYAlignment.Center
resultText.Parent = resultCard

local currentBarTween
local wasAlive = true

local function updateWaterDisplay(gap)
	local roundedGap = math.floor(gap)
	if gap <= 0 then
		waterLabel.Text = "🌊 SUBA!"
	elseif gap < 18 then
		waterLabel.Text = string.format("🌊 %dm", roundedGap)
	else
		waterLabel.Text = string.format("🌊 %dm abaixo", roundedGap)
	end

	local danger = 1 - math.clamp(gap / 80, 0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(
		72 + math.floor(183 * danger),
		177 - math.floor(105 * danger),
		255 - math.floor(165 * danger)
	)

	if currentBarTween then
		currentBarTween:Cancel()
	end
	currentBarTween = TweenService:Create(
		barFill,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(danger, 0, 1, 0) }
	)
	currentBarTween:Play()
end

waterEvent.OnClientEvent:Connect(function(data)
	local waterY = tonumber(data.waterY) or 0
	local height = tonumber(data.height) or 0
	local gap = height - waterY
	local alive = data.alive ~= false

	scoreLabel.Text = "⭐ " .. tostring(data.runScore or data.score or 0)
	coinLabel.Text = "🪙 " .. tostring(data.coins or 0)
	updateWaterDisplay(gap)

	if alive and gap <= 0 then
		warning.Visible = true
		warning.Text = "🌊 VOCE ESTA NA AGUA! SUBA!"
	elseif alive and gap < 18 then
		warning.Visible = true
		warning.Text = "🌊 A AGUA ESTA CHEGANDO"
	else
		warning.Visible = false
	end

	if not alive and wasAlive then
		wasAlive = false
		warning.Visible = false
		local cause = data.inWater and "VOCE SE AFOGOU" or "VOCE MORREU"
		resultText.Text = string.format(
			"%s\n⭐ %d perdidos  •  🪙 %d perdidas",
			cause,
			tonumber(data.lastDeathRunScore) or 0,
			tonumber(data.lastDeathCoinsLost) or 0
		)
		resultCard.BackgroundTransparency = 1
		resultCard.Visible = true
		TweenService:Create(resultCard, TweenInfo.new(0.2), { BackgroundTransparency = 0.12 }):Play()
	elseif alive and not wasAlive then
		wasAlive = true
		resultCard.Visible = false
	end
end)
