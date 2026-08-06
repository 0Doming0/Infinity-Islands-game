local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local event = RemoteRegistry.Get("Notifications", "DungeonResult", "RemoteEvent")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonResultUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(430, 235)
panel.BackgroundColor3 = Color3.fromRGB(15, 24, 31)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(20, 24)
title.Size = UDim2.new(1, -40, 0, 52)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(105, 235, 170)
title.Parent = panel

local details = Instance.new("TextLabel")
details.Position = UDim2.fromOffset(20, 85)
details.Size = UDim2.new(1, -40, 0, 105)
details.BackgroundTransparency = 1
details.Font = Enum.Font.Gotham
details.TextSize = 17
details.TextWrapped = true
details.TextColor3 = Color3.fromRGB(225, 235, 240)
details.Parent = panel

event.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Action ~= "Result" then
		return
	end
	local victory = data.Result == "Victory"
	title.Text = victory and "FASE CONCLUIDA!" or "FASE FRACASSADA"
	title.TextColor3 = victory and Color3.fromRGB(105, 235, 170) or Color3.fromRGB(245, 105, 105)
	details.Text = victory
		and string.format(
			"%s\n+%d moedas\nRetornando ao lobby em %d segundos...",
			tostring(data.PhaseName or data.PhaseId),
			math.floor(tonumber(data.RewardCoins) or 0),
			math.floor(tonumber(data.ReturnDelay) or 7)
		)
		or string.format(
			"Todos os jogadores foram derrotados.\nRetornando ao lobby em %d segundos...",
			math.floor(tonumber(data.ReturnDelay) or 7)
		)
	panel.Visible = true
end)
