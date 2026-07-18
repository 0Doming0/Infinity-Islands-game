-- Aviso compacto para eventos aleatorios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage:WaitForChild("WorldEvent")
local gui = Instance.new("ScreenGui")
gui.Name = "WorldEventUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 18
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, -90)
card.Size = UDim2.new(1, -24, 0, 70)
card.BackgroundColor3 = Color3.fromRGB(27, 25, 40)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
local cardConstraint = Instance.new("UISizeConstraint")
cardConstraint.MaxSize = Vector2.new(360, 70)
cardConstraint.MinSize = Vector2.new(280, 70)
cardConstraint.Parent = card

local text = Instance.new("TextLabel")
text.Position = UDim2.fromOffset(10, 7)
text.Size = UDim2.new(1, -20, 1, -14)
text.BackgroundTransparency = 1
text.Text = ""
text.TextColor3 = Color3.fromRGB(255, 226, 110)
text.Font = Enum.Font.GothamBold
text.TextSize = 15
text.TextWrapped = true
text.Parent = card

local token = 0
remote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Action ~= "Start" then
		return
	end
	token += 1
	local current = token
	text.Text = string.format("%s\n%s", data.Title or "EVENTO", data.Message or "")
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0, 14),
	}):Play()
	task.delay(5, function()
		if token == current then
			TweenService:Create(card, TweenInfo.new(0.25), {
				Position = UDim2.new(0.5, 0, 0, -90),
			}):Play()
		end
	end)
end)
