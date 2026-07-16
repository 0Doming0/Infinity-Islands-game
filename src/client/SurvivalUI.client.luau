--[[
	SurvivalUI - Client Script (Optimized)
	Displays water level, score, height, and survival info.
	Receives updates at throttled intervals from server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local waterEvent = ReplicatedStorage:WaitForChild("WaterEvent")

-- ========================
-- CREATE UI
-- ========================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- HUD container (top center)
local hudFrame = Instance.new("Frame")
hudFrame.Name = "HUD"
hudFrame.Size = UDim2.new(0, 320, 0, 100)
hudFrame.Position = UDim2.new(0.5, -160, 0, 15)
hudFrame.BackgroundColor3 = Color3.fromRGB(15, 25, 40)
hudFrame.BackgroundTransparency = 0.15
hudFrame.BorderSizePixel = 0
hudFrame.Parent = screenGui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 12)
hudCorner.Parent = hudFrame

-- Score label
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Name = "ScoreLabel"
scoreLabel.Size = UDim2.new(0.5, -10, 0, 30)
scoreLabel.Position = UDim2.new(0, 10, 0, 8)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Text = "Score: 0"
scoreLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.TextScaled = true
scoreLabel.Parent = hudFrame

-- Height label
local heightLabel = Instance.new("TextLabel")
heightLabel.Name = "HeightLabel"
heightLabel.Size = UDim2.new(0.5, -10, 0, 30)
heightLabel.Position = UDim2.new(0.5, 0, 0, 8)
heightLabel.BackgroundTransparency = 1
heightLabel.Text = "Altura: 0m"
heightLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
heightLabel.Font = Enum.Font.GothamBold
heightLabel.TextScaled = true
heightLabel.Parent = hudFrame

-- Water level bar
local waterBarLabel = Instance.new("TextLabel")
waterBarLabel.Name = "WaterBarLabel"
waterBarLabel.Size = UDim2.new(1, -20, 0, 16)
waterBarLabel.Position = UDim2.new(0, 10, 0, 42)
waterBarLabel.BackgroundTransparency = 1
waterBarLabel.Text = "Nivel da Agua"
waterBarLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
waterBarLabel.Font = Enum.Font.Gotham
waterBarLabel.TextScaled = true
waterBarLabel.Parent = hudFrame

local waterBarContainer = Instance.new("Frame")
waterBarContainer.Name = "WaterBar"
waterBarContainer.Size = UDim2.new(1, -20, 0, 14)
waterBarContainer.Position = UDim2.new(0, 10, 0, 62)
waterBarContainer.BackgroundColor3 = Color3.fromRGB(40, 50, 70)
waterBarContainer.BorderSizePixel = 0
waterBarContainer.Parent = hudFrame

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = waterBarContainer

local waterBarFill = Instance.new("Frame")
waterBarFill.Name = "Fill"
waterBarFill.Size = UDim2.new(0, 0, 1, 0)
waterBarFill.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
waterBarFill.BorderSizePixel = 0
waterBarFill.Parent = waterBarContainer

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = waterBarFill

-- Water level value
local waterYLabel = Instance.new("TextLabel")
waterYLabel.Name = "WaterYLabel"
waterYLabel.Size = UDim2.new(1, -20, 0, 16)
waterYLabel.Position = UDim2.new(0, 10, 0, 80)
waterYLabel.BackgroundTransparency = 1
waterYLabel.Text = "Agua: 0m"
waterYLabel.TextColor3 = Color3.fromRGB(100, 180, 255)
waterYLabel.Font = Enum.Font.Gotham
waterYLabel.TextScaled = true
waterYLabel.Parent = hudFrame

-- Warning label (below HUD)
local warningLabel = Instance.new("TextLabel")
warningLabel.Name = "WarningLabel"
warningLabel.Size = UDim2.new(0, 400, 0, 30)
warningLabel.Position = UDim2.new(0.5, -200, 0, 125)
warningLabel.BackgroundTransparency = 1
warningLabel.Text = ""
warningLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
warningLabel.Font = Enum.Font.GothamBold
warningLabel.TextScaled = true
warningLabel.Parent = screenGui

-- Instructions (bottom left)
local instructions = Instance.new("TextLabel")
instructions.Name = "Instructions"
instructions.Size = UDim2.new(0, 280, 0, 70)
instructions.Position = UDim2.new(0, 10, 1, -80)
instructions.BackgroundColor3 = Color3.fromRGB(15, 25, 40)
instructions.BackgroundTransparency = 0.3
instructions.Text = "SUBA para nao se afogar!\nA agua sobe sem parar.\nSobreviva para ganhar pontos!"
instructions.TextColor3 = Color3.fromRGB(255, 255, 255)
instructions.Font = Enum.Font.Gotham
instructions.TextScaled = true
instructions.Parent = screenGui

local instCorner = Instance.new("UICorner")
instCorner.CornerRadius = UDim.new(0, 10)
instCorner.Parent = instructions

-- Death overlay
local deathFrame = Instance.new("Frame")
deathFrame.Name = "DeathFrame"
deathFrame.Size = UDim2.new(1, 0, 1, 0)
deathFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
deathFrame.BackgroundTransparency = 1
deathFrame.BorderSizePixel = 0
deathFrame.ZIndex = 10
deathFrame.Parent = screenGui

local deathText = Instance.new("TextLabel")
deathText.Size = UDim2.new(0, 500, 0, 120)
deathText.Position = UDim2.new(0.5, -250, 0.4, 0)
deathText.BackgroundTransparency = 1
deathText.Text = ""
deathText.TextColor3 = Color3.fromRGB(255, 50, 50)
deathText.Font = Enum.Font.GothamBlack
deathText.TextScaled = true
deathText.ZIndex = 11
deathText.Parent = deathFrame

-- ========================
-- STATE
-- ========================
local lastWaterY = -100
local wasAlive = true

-- ========================
-- HANDLE SERVER UPDATES
-- ========================

waterEvent.OnClientEvent:Connect(function(data)
	local waterY = data.waterY or 0
	local score = data.score or 0
	local height = data.height or 0
	local alive = data.alive
	
	-- Update score and height
	scoreLabel.Text = "Score: " .. tostring(score)
	heightLabel.Text = "Altura: " .. tostring(height) .. "m"
	waterYLabel.Text = "Agua: " .. tostring(waterY) .. "m"
	
	-- Update water bar (relative to player height)
	local barPercent = 0
	if height > 0 then
		barPercent = math.clamp(waterY / (height + 50), 0, 1)
	end
	TweenService:Create(waterBarFill, TweenInfo.new(0.5), {
		Size = UDim2.new(barPercent, 0, 1, 0)
	}):Play()
	
	-- Warning when water is close or above player
	local diff = height - waterY
	if alive and diff <= 0 then
		warningLabel.Text = "💀 VOCE ESTA NA AGUA! SUBA! 💀"
		warningLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
	elseif alive and diff > 0 and diff < 15 then
		warningLabel.Text = "⚠ A AGUA ESTA CHEGANDO! SUBA! ⚠"
		warningLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
	elseif alive and diff >= 15 and diff < 30 then
		warningLabel.Text = "Cuidado, a agua esta subindo!"
		warningLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	elseif alive then
		warningLabel.Text = ""
	end
	
	-- Death/respawn handling
	if not alive and wasAlive then
		wasAlive = false
		deathText.Text = "VOCE SE AFOGOU!\nScore: " .. tostring(score)
		TweenService:Create(deathFrame, TweenInfo.new(0.5), {
			BackgroundTransparency = 0.5
		}):Play()
	elseif alive and not wasAlive then
		wasAlive = true
		TweenService:Create(deathFrame, TweenInfo.new(0.5), {
			BackgroundTransparency = 1
		}):Play()
	end
	
	lastWaterY = waterY
end)