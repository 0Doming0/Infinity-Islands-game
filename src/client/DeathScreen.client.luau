-- Tela de morte responsiva. A compra é solicitada ao servidor e validada por
-- ProcessReceipt; o cliente nunca concede moedas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local deathEvent = ReplicatedStorage:WaitForChild("DeathReviveEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "DeathScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
shade.BackgroundTransparency = 0.18
shade.BorderSizePixel = 0
shade.Parent = gui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(430, 300)
card.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
card.BorderSizePixel = 0
card.Parent = shade
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)

local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(300, 260)
constraint.MaxSize = Vector2.new(430, 300)
constraint.Parent = card

local cardScale = Instance.new("UIScale")
cardScale.Parent = card
local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	cardScale.Scale = math.clamp(math.min((viewport.X - 24) / 430, (viewport.Y - 24) / 300), 0.68, 1)
end
updateScale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(20, 20)
title.Size = UDim2.new(1, -40, 0, 44)
title.BackgroundTransparency = 1
title.Text = "VOCÊ MORREU"
title.TextColor3 = Color3.fromRGB(255, 104, 104)
title.Font = Enum.Font.GothamBold
title.TextSize = 28
title.Parent = card

local result = Instance.new("TextLabel")
result.Position = UDim2.fromOffset(24, 75)
result.Size = UDim2.new(1, -48, 0, 68)
result.BackgroundTransparency = 1
result.Text = ""
result.TextColor3 = Color3.fromRGB(225, 229, 239)
result.Font = Enum.Font.GothamMedium
result.TextSize = 18
result.TextWrapped = true
result.Parent = card

local robuxButton = Instance.new("TextButton")
robuxButton.Position = UDim2.fromOffset(24, 158)
robuxButton.Size = UDim2.new(1, -48, 0, 55)
robuxButton.BackgroundColor3 = Color3.fromRGB(52, 166, 94)
robuxButton.Text = "RENASCER SEM PERDER MOEDAS"
robuxButton.TextColor3 = Color3.new(1, 1, 1)
robuxButton.Font = Enum.Font.GothamBold
robuxButton.TextSize = 16
robuxButton.Parent = card
Instance.new("UICorner", robuxButton).CornerRadius = UDim.new(0, 12)

local freeButton = Instance.new("TextButton")
freeButton.Position = UDim2.fromOffset(24, 226)
freeButton.Size = UDim2.new(1, -48, 0, 48)
freeButton.BackgroundColor3 = Color3.fromRGB(61, 68, 84)
freeButton.Text = "AGUARDE..."
freeButton.TextColor3 = Color3.fromRGB(225, 229, 239)
freeButton.Font = Enum.Font.GothamBold
freeButton.TextSize = 15
freeButton.Parent = card
Instance.new("UICorner", freeButton).CornerRadius = UDim.new(0, 11)

local current

robuxButton.Activated:Connect(function()
	if not current or current.ProductId <= 0 then
		return
	end
	robuxButton.Active = false
	robuxButton.Text = "ABRINDO COMPRA..."
	deathEvent:FireServer({ Action = "Purchase", Serial = current.Serial })
end)

freeButton.Activated:Connect(function()
	if current and os.clock() >= current.FreeAt then
		freeButton.Active = false
		deathEvent:FireServer({ Action = "FreeRespawn", Serial = current.Serial })
	end
end)

RunService.RenderStepped:Connect(function()
	if not current or not gui.Enabled then
		return
	end
	local remaining = math.max(0, math.ceil(current.FreeAt - os.clock()))
	freeButton.Active = remaining <= 0
	freeButton.AutoButtonColor = remaining <= 0
	freeButton.Text = remaining <= 0 and "RENASCER" or string.format("RENASCER EM %ds", remaining)
end)

deathEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "Show" then
		current = {
			Serial = data.Serial,
			ProductId = tonumber(data.ProductId) or 0,
			FreeAt = os.clock() + (tonumber(data.FreeRespawnDelaySeconds) or 4),
		}
		local cause = data.Cause == "Water" and "A água alcançou você." or "Sua tentativa terminou."
		result.Text = string.format(
			"%s\nPontuação: %d  •  Moedas perdidas: %d",
			cause,
			tonumber(data.RunScore) or 0,
			tonumber(data.LostCoins) or 0
		)
		robuxButton.Active = current.ProductId > 0
		robuxButton.AutoButtonColor = current.ProductId > 0
		robuxButton.Text = current.ProductId > 0 and "RENASCER SEM PERDER MOEDAS" or "CONFIGURE O PRODUTO ROBUX"
		gui.Enabled = true
	elseif data.Action == "Granted" then
		result.Text =
			string.format("Renascimento confirmado!\n%d moedas devolvidas.", tonumber(data.CoinsRefunded) or 0)
		robuxButton.Text = "CONFIRMADO"
	elseif data.Action == "Error" then
		result.Text = tostring(data.Message or "Não foi possível abrir a compra.")
		robuxButton.Active = current ~= nil and current.ProductId > 0
	end
end)

player.CharacterAdded:Connect(function()
	gui.Enabled = false
	current = nil
end)
