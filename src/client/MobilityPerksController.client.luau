-- Controles discretos para beneficios ja possuidos. Nenhum destes botoes abre
-- compra; a aquisicao continua exclusiva do Mercador do Ceu.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")
local event = ReplicatedStorage:WaitForChild("MonetizationEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "MobilityPerksUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local function createButton(name, text, position)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = UDim2.fromOffset(112, 42)
	button.BackgroundColor3 = Color3.fromRGB(24, 38, 54)
	button.BackgroundTransparency = 0.12
	button.TextColor3 = Color3.fromRGB(235, 247, 255)
	button.Text = text
	button.TextSize = 11
	button.Font = Enum.Font.GothamBold
	button.Visible = false
	button.Parent = gui
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 11)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(92, 205, 255)
	stroke.Transparency = 0.35
	stroke.Parent = button
	return button
end

local wingButton = createButton("WingButton", "ASAS  [F]", UDim2.new(1, -18, 1, -174))
local capeButton = createButton("CapeButton", "CAPA  [G]", UDim2.new(1, -18, 1, -126))

local function invoke(action)
	local success, result = pcall(request.InvokeServer, request, action)
	if success and type(result) == "table" and result.Message then
		local button = action == "ActivateWing" and wingButton or capeButton
		local original = button.Text
		button.Text = result.Message
		task.delay(1.5, function()
			if button.Parent then
				button.Text = original
			end
		end)
	end
end

wingButton.Activated:Connect(function()
	invoke("ActivateWing")
end)
capeButton.Activated:Connect(function()
	invoke("ActivateCape")
end)

ContextActionService:BindAction("ActivateOwnedWings", function(_, inputState)
	if inputState == Enum.UserInputState.Begin and wingButton.Visible then
		invoke("ActivateWing")
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.F)

ContextActionService:BindAction("ActivateOwnedCape", function(_, inputState)
	if inputState == Enum.UserInputState.Begin and capeButton.Visible then
		invoke("ActivateCape")
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.G)

local function refreshVisibility(data)
	local wingProductId = data and data.WingProductId or player:GetAttribute("OwnedWingProductId")
	local temporaryUses = data and data.TemporaryWingUses
		or tonumber(player:GetAttribute("TemporaryWingUses")) or 0
	wingButton.Visible = wingProductId ~= nil or temporaryUses > 0
	capeButton.Visible = (data and data.OwnsCape) == true
		or player:GetAttribute("OwnsInvisibilityCape") == true
end

event.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Action == "Entitlements" then
		refreshVisibility(data)
	end
end)

task.spawn(function()
	local success, data = pcall(request.InvokeServer, request, "GetEntitlements")
	if success and type(data) == "table" then
		refreshVisibility(data)
	else
		refreshVisibility()
	end
end)

RunService.RenderStepped:Connect(function()
	local timestamp = workspace:GetServerTimeNow()
	if wingButton.Visible then
		local remaining = math.max(0, math.ceil((tonumber(player:GetAttribute("WingReadyAt")) or 0) - timestamp))
		wingButton.Text = remaining > 0 and ("ASAS  " .. remaining .. "s")
			or UserInputService.TouchEnabled and "ASAS" or "ASAS  [F]"
	end
	if capeButton.Visible then
		local remaining = math.max(0, math.ceil((tonumber(player:GetAttribute("CapeReadyAt")) or 0) - timestamp))
		capeButton.Text = remaining > 0 and ("CAPA  " .. remaining .. "s")
			or UserInputService.TouchEnabled and "CAPA" or "CAPA  [G]"
	end
end)
