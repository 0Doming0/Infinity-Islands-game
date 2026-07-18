-- Inventario compacto no canto inferior esquerdo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("InventoryEvent")
local request = ReplicatedStorage:WaitForChild("InventoryRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "QuickInventory"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 12, 1, -12)
panel.Size = UDim2.fromOffset(252, 52)
panel.BackgroundColor3 = Color3.fromRGB(15, 21, 32)
panel.BackgroundTransparency = 0.20
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 11)

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(72, 40)
toggle.Position = UDim2.fromOffset(6, 6)
toggle.BackgroundColor3 = Color3.fromRGB(48, 61, 84)
toggle.Text = "ITENS"
toggle.TextColor3 = Color3.fromRGB(225, 231, 242)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 12
toggle.Parent = panel
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

local summary = Instance.new("TextLabel")
summary.Position = UDim2.fromOffset(86, 6)
summary.Size = UDim2.new(1, -92, 1, -12)
summary.BackgroundTransparency = 1
summary.Text = "Inventario vazio"
summary.TextColor3 = Color3.fromRGB(180, 192, 210)
summary.Font = Enum.Font.GothamMedium
summary.TextSize = 12
summary.TextWrapped = true
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.Parent = panel

local drawer = Instance.new("Frame")
drawer.AnchorPoint = Vector2.new(0, 1)
drawer.Position = UDim2.new(0, 12, 1, -70)
drawer.Size = UDim2.new(1, -24, 0, 260)
drawer.BackgroundColor3 = Color3.fromRGB(14, 19, 29)
drawer.BackgroundTransparency = 0.06
drawer.BorderSizePixel = 0
drawer.Visible = false
drawer.Parent = gui
Instance.new("UICorner", drawer).CornerRadius = UDim.new(0, 12)
local drawerConstraint = Instance.new("UISizeConstraint")
drawerConstraint.MaxSize = Vector2.new(320, 260)
drawerConstraint.MinSize = Vector2.new(250, 220)
drawerConstraint.Parent = drawer

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(8, 8)
list.Size = UDim2.new(1, -16, 1, -16)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = drawer
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local current = { Entries = {} }

local function render(snapshot)
	current = snapshot or { Entries = {} }
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local pieces = {}
	for index, entry in ipairs(current.Entries or {}) do
		if index <= 2 then
			table.insert(pieces, string.format("%s x%d", entry.DisplayName, entry.Amount))
		end
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -4, 0, 54)
		row.BackgroundColor3 = entry.Color or Color3.fromRGB(45, 55, 70)
		row.BackgroundTransparency = 0.72
		row.BorderSizePixel = 0
		row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromOffset(10, 4)
		label.Size = UDim2.new(1, -100, 1, -8)
		label.BackgroundTransparency = 1
		label.Text = string.format("%s  x%d\n%s", entry.DisplayName, entry.Amount, entry.Description or "")
		label.TextColor3 = Color3.fromRGB(240, 242, 247)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 12
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = row

		local use = Instance.new("TextButton")
		use.AnchorPoint = Vector2.new(1, 0.5)
		use.Position = UDim2.new(1, -7, 0.5, 0)
		use.Size = UDim2.fromOffset(76, 38)
		use.BackgroundColor3 = Color3.fromRGB(65, 130, 92)
		use.Text = "USAR"
		use.TextColor3 = Color3.new(1, 1, 1)
		use.Font = Enum.Font.GothamBold
		use.TextSize = 12
		use.Parent = row
		Instance.new("UICorner", use).CornerRadius = UDim.new(0, 8)
		use.MouseButton1Click:Connect(function()
			local success, response = pcall(function()
				return request:InvokeServer("Use", entry.ItemId)
			end)
			if success and type(response) == "table" and response.Inventory then
				render(response.Inventory)
			end
		end)
	end
	summary.Text = #pieces > 0 and table.concat(pieces, "  |  ") or "Inventario vazio"
end

toggle.MouseButton1Click:Connect(function()
	drawer.Visible = not drawer.Visible
	if drawer.Visible then
		local success, snapshot = pcall(function()
			return request:InvokeServer("Get")
		end)
		if success then
			render(snapshot)
		end
	end
end)

event.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Inventory then
		render(data.Inventory)
	end
end)

task.defer(function()
	local success, snapshot = pcall(function()
		return request:InvokeServer("Get")
	end)
	if success then
		render(snapshot)
	end
end)
