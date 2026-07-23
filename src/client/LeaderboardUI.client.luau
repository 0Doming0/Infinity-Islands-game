-- Botao discreto e painel do ranking global.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("GlobalLeaderboardRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "GlobalLeaderboardUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "RankingButton"
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -12, 0, 12)
button.Size = UDim2.fromOffset(48, 38)
button.BackgroundColor3 = Color3.fromRGB(23, 31, 48)
button.BackgroundTransparency = 0.18
button.Text = "🏆"
button.TextColor3 = Color3.fromRGB(255, 220, 93)
button.Font = Enum.Font.GothamMedium
button.TextSize = 13
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 58)
panel.Size = UDim2.fromOffset(300, 420)
panel.BackgroundColor3 = Color3.fromRGB(14, 19, 30)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 13)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 48)
title.Position = UDim2.fromOffset(10, 2)
title.BackgroundTransparency = 1
title.Text = "🏆 MELHORES ESCALADORES"
title.TextColor3 = Color3.fromRGB(255, 220, 93)
title.Font = Enum.Font.GothamMedium
title.TextSize = 16
title.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(10, 50)
list.Size = UDim2.new(1, -20, 1, -92)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = list

local personal = Instance.new("TextLabel")
personal.AnchorPoint = Vector2.new(0, 1)
personal.Position = UDim2.new(0, 10, 1, -6)
personal.Size = UDim2.new(1, -20, 0, 32)
personal.BackgroundTransparency = 1
personal.Text = "⭐ Seu recorde: 0"
personal.TextColor3 = Color3.fromRGB(135, 210, 255)
personal.Font = Enum.Font.GothamMedium
personal.TextSize = 14
personal.Parent = panel

local function clearRows()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function render(data)
	clearRows()
	personal.Text = "⭐ Seu recorde: " .. tostring(data.PersonalBest or 0)
	for _, entry in ipairs(data.Entries or {}) do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = entry.Rank or 999
		row.Size = UDim2.new(1, -4, 0, 31)
		row.BackgroundColor3 = entry.UserId == player.UserId and Color3.fromRGB(47, 81, 112)
			or Color3.fromRGB(28, 35, 50)
		row.BackgroundTransparency = 0.18
		row.Text = string.format("  #%d  %s", entry.Rank or 0, entry.DisplayName or "Jogador")
		row.TextColor3 = Color3.fromRGB(235, 239, 246)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = list
		local score = Instance.new("TextLabel")
		score.AnchorPoint = Vector2.new(1, 0)
		score.Position = UDim2.new(1, -8, 0, 0)
		score.Size = UDim2.fromOffset(75, 31)
		score.BackgroundTransparency = 1
		score.Text = "⭐ " .. tostring(entry.BestScore or 0)
		score.TextColor3 = Color3.fromRGB(255, 220, 93)
		score.Font = Enum.Font.GothamMedium
		score.TextSize = 13
		score.TextXAlignment = Enum.TextXAlignment.Right
		score.Parent = row
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)
	end
end

button.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		playerGui:SetAttribute("SkyDungeonExclusivePanel", "Leaderboard")
		title.Text = "⌛ CARREGANDO..."
		local success, data = pcall(function()
			return remote:InvokeServer()
		end)
		title.Text = "🏆 MELHORES ESCALADORES"
		if success and type(data) == "table" then
			render(data)
		else
			personal.Text = "Ranking indisponivel agora"
		end
	end
end)

playerGui:GetAttributeChangedSignal("SkyDungeonExclusivePanel"):Connect(function()
	if playerGui:GetAttribute("SkyDungeonExclusivePanel") ~= "Leaderboard" then
		panel.Visible = false
	end
end)
