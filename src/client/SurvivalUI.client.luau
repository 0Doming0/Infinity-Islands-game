-- SkyDungeon - HUD responsiva para computador, controle e celular.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 12)
hud.Size = UDim2.fromOffset(470, 142)
hud.BackgroundColor3 = Color3.fromRGB(14, 20, 32)
hud.BackgroundTransparency = 0.10
hud.BorderSizePixel = 0
hud.Parent = screenGui
local hudScale = Instance.new("UIScale")
hudScale.Parent = hud
local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 15)
hudCorner.Parent = hud
local hudStroke = Instance.new("UIStroke")
hudStroke.Color = Color3.fromRGB(68, 121, 173)
hudStroke.Transparency = 0.25
hudStroke.Parent = hud

local function label(name, position, size, text, color, font, textSize, alignment)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Position = position
	item.Size = size
	item.BackgroundTransparency = 1
	item.Text = text
	item.TextColor3 = color
	item.Font = font or Enum.Font.GothamBold
	item.TextSize = textSize or 17
	item.TextXAlignment = alignment or Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = hud
	return item
end

local scoreLabel = label("Score", UDim2.fromOffset(14, 8), UDim2.fromOffset(210, 28), "Pontos: 0", Color3.fromRGB(255, 218, 82), Enum.Font.GothamBlack, 19)
local runLabel = label("RunScore", UDim2.fromOffset(246, 8), UDim2.fromOffset(210, 28), "Tentativa: 0", Color3.fromRGB(125, 225, 255), Enum.Font.GothamBold, 17, Enum.TextXAlignment.Right)
local heightLabel = label("Height", UDim2.fromOffset(14, 38), UDim2.fromOffset(150, 24), "Altura: 0m", Color3.fromRGB(110, 255, 155), Enum.Font.GothamBold, 16)
local swordLabel = label("Sword", UDim2.fromOffset(164, 38), UDim2.fromOffset(292, 24), "Espada: Classica • 1.00x", Color3.fromRGB(218, 184, 255), Enum.Font.GothamBold, 15, Enum.TextXAlignment.Right)

local waterText = label("Water", UDim2.fromOffset(14, 68), UDim2.fromOffset(442, 22), "Agua: -15m • 0.00/s", Color3.fromRGB(125, 196, 255), Enum.Font.GothamMedium, 15)
local barBackground = Instance.new("Frame")
barBackground.Name = "WaterDanger"
barBackground.Position = UDim2.fromOffset(14, 94)
barBackground.Size = UDim2.fromOffset(442, 18)
barBackground.BackgroundColor3 = Color3.fromRGB(38, 49, 67)
barBackground.BorderSizePixel = 0
barBackground.Parent = hud
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBackground
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(55, 165, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill
local modeLabel = label("Mode", UDim2.fromOffset(14, 116), UDim2.fromOffset(442, 20), "A agua esta se adaptando ao grupo", Color3.fromRGB(170, 183, 202), Enum.Font.Gotham, 13, Enum.TextXAlignment.Center)

local warning = Instance.new("TextLabel")
warning.Name = "Warning"
warning.AnchorPoint = Vector2.new(0.5, 0)
warning.Position = UDim2.new(0.5, 0, 0, 162)
warning.Size = UDim2.fromOffset(520, 42)
warning.BackgroundColor3 = Color3.fromRGB(90, 24, 30)
warning.BackgroundTransparency = 0.18
warning.Text = ""
warning.TextColor3 = Color3.new(1, 1, 1)
warning.Font = Enum.Font.GothamBlack
warning.TextSize = 20
warning.Visible = false
warning.Parent = screenGui
local warningCorner = Instance.new("UICorner")
warningCorner.CornerRadius = UDim.new(0, 12)
warningCorner.Parent = warning

local instructions = Instance.new("TextLabel")
instructions.AnchorPoint = Vector2.new(0, 1)
instructions.Position = UDim2.new(0, 12, 1, -12)
instructions.Size = UDim2.fromOffset(300, 58)
instructions.BackgroundColor3 = Color3.fromRGB(14, 20, 32)
instructions.BackgroundTransparency = 0.22
instructions.Text = UserInputService.TouchEnabled
	and "SUBA E FUJA DA AGUA\nEquipe a espada e toque em ATACAR"
	or "SUBA E FUJA DA AGUA\nClique ou pressione F/R2 para atacar"
instructions.TextColor3 = Color3.fromRGB(232, 238, 248)
instructions.Font = Enum.Font.GothamBold
instructions.TextSize = 14
instructions.Parent = screenGui
local instructionsCorner = Instance.new("UICorner")
instructionsCorner.CornerRadius = UDim.new(0, 10)
instructionsCorner.Parent = instructions

local deathFrame = Instance.new("Frame")
deathFrame.Size = UDim2.fromScale(1, 1)
deathFrame.BackgroundColor3 = Color3.new(0, 0, 0)
deathFrame.BackgroundTransparency = 1
deathFrame.Visible = false
deathFrame.ZIndex = 30
deathFrame.Parent = screenGui
local deathText = Instance.new("TextLabel")
deathText.AnchorPoint = Vector2.new(0.5, 0.5)
deathText.Position = UDim2.fromScale(0.5, 0.46)
deathText.Size = UDim2.new(0.8, 0, 0, 150)
deathText.BackgroundTransparency = 1
deathText.Text = ""
deathText.TextColor3 = Color3.fromRGB(255, 92, 92)
deathText.Font = Enum.Font.GothamBlack
deathText.TextScaled = true
deathText.TextWrapped = true
deathText.ZIndex = 31
deathText.Parent = deathFrame
local deathConstraint = Instance.new("UITextSizeConstraint")
deathConstraint.MaxTextSize = 44
deathConstraint.MinTextSize = 22
deathConstraint.Parent = deathText

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	hudScale.Scale = math.clamp(viewport.X / 900, 0.62, 1)
	warning.Size = UDim2.fromOffset(math.min(520, viewport.X - 30), 42)
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local modeText = {
	Waiting = "A agua espera jogadores",
	Warmup = "Aquecimento: prepare-se para subir",
	Mercy = "A agua desacelerou: o grupo esta em perigo",
	Recovery = "A agua esta recuperando o ritmo",
	Normal = "Ritmo normal da agua",
	Hunting = "O grupo esta muito adiantado: a agua acelerou!",
}

local wasAlive = true
waterEvent.OnClientEvent:Connect(function(data)
	local waterY = tonumber(data.waterY) or 0
	local height = tonumber(data.height) or 0
	local gap = height - waterY
	local speed = tonumber(data.waterSpeed) or 0
	local multiplier = tonumber(data.scoreMultiplier) or 1
	local alive = data.alive ~= false

	scoreLabel.Text = "Pontos: " .. tostring(data.score or 0)
	runLabel.Text = "Tentativa: " .. tostring(data.runScore or 0)
	heightLabel.Text = "Altura: " .. tostring(height) .. "m"
	swordLabel.Text = string.format("%s • %.2fx", player:GetAttribute("EquippedSwordName") or "Espada Classica", multiplier)
	waterText.Text = string.format("Agua: %dm  •  %.2f studs/s  •  distancia %dm", waterY, speed, math.floor(gap))
	modeLabel.Text = modeText[data.waterMode] or "A agua esta se adaptando ao grupo"

	local danger = 1 - math.clamp(gap / 80, 0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(55 + math.floor(200 * danger), 165 - math.floor(100 * danger), 255 - math.floor(170 * danger))
	TweenService:Create(barFill, TweenInfo.new(0.30), { Size = UDim2.new(danger, 0, 1, 0) }):Play()

	if alive and gap <= 0 then
		warning.Visible = true
		warning.Text = "VOCE ESTA NA AGUA! SUBA!"
	elseif alive and gap < 18 then
		warning.Visible = true
		warning.Text = "A AGUA ESTA CHEGANDO!"
	elseif alive and data.waterMode == "Hunting" then
		warning.Visible = true
		warning.Text = "A AGUA ACELEROU PORQUE O GRUPO ESTA ADIANTADO"
	else
		warning.Visible = false
	end

	if not alive and wasAlive then
		wasAlive = false
		deathFrame.Visible = true
		deathText.Text = string.format("VOCE SE AFOGOU!\nTentativa: %s pontos", tostring(data.runScore or 0))
		TweenService:Create(deathFrame, TweenInfo.new(0.35), { BackgroundTransparency = 0.35 }):Play()
	elseif alive and not wasAlive then
		wasAlive = true
		local tween = TweenService:Create(deathFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			if wasAlive then
				deathFrame.Visible = false
			end
		end)
	end
end)
