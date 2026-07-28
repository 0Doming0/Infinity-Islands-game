-- Interface compacta de troca de companheiros. O cliente apenas monta ofertas;
-- propriedade, distância, confirmação e persistência são validadas no servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("TradeRequest")
local event = ReplicatedStorage:WaitForChild("TradeEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "TradeUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 31
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "TradeButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -72, 0, 12)
openButton.Size = UDim2.fromOffset(48, 38)
openButton.BackgroundColor3 = Color3.fromRGB(52, 38, 78)
openButton.BackgroundTransparency = 0.08
openButton.Text = "TRD"
openButton.TextColor3 = Color3.fromRGB(220, 188, 255)
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 12
openButton.Parent = gui
Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 10)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 58)
panel.Size = UDim2.fromOffset(430, 540)
panel.BackgroundColor3 = Color3.fromRGB(19, 17, 28)
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
local function updateScale()
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(math.min((size.X - 24) / 430, (size.Y - 70) / 540), 0.7, 1)
end
updateScale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(15, 9)
title.Size = UDim2.new(1, -58, 0, 30)
title.BackgroundTransparency = 1
title.Text = "TROCA DE SLIMES"
title.TextColor3 = Color3.fromRGB(220, 188, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 9)
close.Size = UDim2.fromOffset(32, 30)
close.BackgroundColor3 = Color3.fromRGB(58, 49, 69)
close.Text = "×"
close.TextColor3 = Color3.fromRGB(240, 230, 245)
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(15, 43)
status.Size = UDim2.new(1, -30, 0, 45)
status.BackgroundTransparency = 1
status.Text = "Convide um jogador próximo para trocar companheiros."
status.TextColor3 = Color3.fromRGB(207, 199, 218)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(12, 92)
list.Size = UDim2.new(1, -24, 1, -154)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local footer = Instance.new("Frame")
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 12, 1, -10)
footer.Size = UDim2.new(1, -24, 0, 46)
footer.BackgroundTransparency = 1
footer.Parent = panel
local footerLayout = Instance.new("UIListLayout")
footerLayout.FillDirection = Enum.FillDirection.Horizontal
footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
footerLayout.Padding = UDim.new(0, 7)
footerLayout.Parent = footer

local function createFooterButton(name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(126, 38)
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = Color3.fromRGB(247, 242, 250)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.Visible = false
	button.Parent = footer
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)
	return button
end

local lockButton = createFooterButton("Lock", "TRAVAR OFERTA", Color3.fromRGB(76, 61, 112))
local confirmButton = createFooterButton("Confirm", "CONFIRMAR TROCA", Color3.fromRGB(45, 118, 83))
local cancelButton = createFooterButton("Cancel", "CANCELAR", Color3.fromRGB(116, 49, 58))

local state = {
	Session = nil,
	Invites = {},
	AvailablePlayers = {},
	Inventory = {},
	MaxOffer = 4,
}
local busy = false

local function invoke(action, payload)
	if busy then
		return false
	end
	busy = true
	local ok, response = pcall(function()
		return request:InvokeServer(action, payload or {})
	end)
	busy = false
	if not ok or type(response) ~= "table" then
		status.Text = "Sistema de troca indisponível."
		return false
	end
	if type(response.State) == "table" then
		state = response.State
	end
	if response.Message then
		status.Text = tostring(response.Message)
	end
	return response.Success == true
end

local function clearRows()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function section(text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -4, 0, 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(220, 188, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = list
end

local function petText(entry)
	local upgrades = entry.Upgrades or {}
	local upgradeTotal = 0
	for _, amount in pairs(upgrades) do
		upgradeTotal += tonumber(amount) or 0
	end
	return string.format(
		"%s  •  %s  •  Nv.%d\nXP %d  |  %d melhoria(s)  |  %d abate(s)",
		tostring(entry.DisplayName or "Slime"),
		tostring(entry.SpeciesName or entry.SpeciesId or ""),
		tonumber(entry.Level) or 1,
		tonumber(entry.XP) or 0,
		upgradeTotal,
		tonumber(entry.Kills) or 0
	)
end

local function row(text, actionText, callback, color)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -4, 0, string.find(text, "\n", 1, true) and 54 or 40)
	frame.BackgroundColor3 = Color3.fromRGB(35, 31, 47)
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.Parent = list
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 9)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(10, 3)
	label.Size = UDim2.new(1, actionText and -104 or -20, 1, -6)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(239, 234, 244)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame
	if actionText then
		local action = Instance.new("TextButton")
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -6, 0.5, 0)
		action.Size = UDim2.fromOffset(88, 30)
		action.BackgroundColor3 = color or Color3.fromRGB(76, 61, 112)
		action.Text = actionText
		action.TextColor3 = Color3.fromRGB(248, 242, 252)
		action.Font = Enum.Font.GothamBold
		action.TextSize = 10
		action.Parent = frame
		Instance.new("UICorner", action).CornerRadius = UDim.new(0, 8)
		action.Activated:Connect(callback)
	end
end

local render
render = function()
	clearRows()
	local trade = state.Session
	lockButton.Visible = trade ~= nil
	confirmButton.Visible = trade ~= nil
	cancelButton.Visible = trade ~= nil
	if not trade then
		title.Text = "TROCA DE SLIMES"
		status.Text = "Convide um jogador próximo. Trocas são permanentes."
		if #(state.Invites or {}) > 0 then
			section("CONVITES RECEBIDOS")
			for _, invite in ipairs(state.Invites) do
				row(invite.DisplayName, "ACEITAR", function()
					invoke("Accept", { UserId = invite.UserId })
					render()
				end, Color3.fromRGB(45, 118, 83))
			end
		end
		section("JOGADORES NO SERVIDOR")
		for _, available in ipairs(state.AvailablePlayers or {}) do
			row(available.DisplayName, "CONVIDAR", function()
				invoke("Invite", { UserId = available.UserId })
				render()
			end)
		end
		if #(state.AvailablePlayers or {}) == 0 then
			row("Nenhum jogador disponível para troca.")
		end
		return
	end

	title.Text = "TROCA COM " .. string.upper(trade.PartnerDisplayName)
	local lockState = trade.OwnLocked and "SUA OFERTA TRAVADA" or "SUA OFERTA ABERTA"
	local partnerState = trade.PartnerLocked and "PARCEIRO TRAVADO" or "PARCEIRO EDITANDO"
	status.Text = lockState .. "  •  " .. partnerState
	section(string.format("SUA OFERTA  %d/%d", #(trade.OwnOffer or {}), state.MaxOffer or 4))
	for _, entry in ipairs(trade.OwnOffer or {}) do
		row(petText(entry), "REMOVER", function()
			invoke("Remove", { InstanceId = entry.InstanceId })
			render()
		end, Color3.fromRGB(116, 49, 58))
	end
	if #(trade.OwnOffer or {}) == 0 then
		row("Você ainda não adicionou nenhum slime.")
	end
	section("OFERTA DE " .. string.upper(trade.PartnerDisplayName))
	for _, entry in ipairs(trade.PartnerOffer or {}) do
		row(petText(entry))
	end
	if #(trade.PartnerOffer or {}) == 0 then
		row("O outro jogador ainda não adicionou nenhum slime.")
	end
	section("SEUS SLIMES DESEQUIPADOS")
	for _, entry in ipairs(state.Inventory or {}) do
		local alreadyOffered = false
		for _, offered in ipairs(trade.OwnOffer or {}) do
			if offered.InstanceId == entry.InstanceId then
				alreadyOffered = true
				break
			end
		end
		if not alreadyOffered then
			row(petText(entry), "ADICIONAR", function()
				invoke("Add", { InstanceId = entry.InstanceId })
				render()
			end)
		end
	end
	lockButton.Text = trade.OwnLocked and "DESTRAVAR" or "TRAVAR OFERTA"
	confirmButton.Text = trade.OwnConfirmed and "CONFIRMADO" or "CONFIRMAR TROCA"
	confirmButton.Active = trade.OwnLocked and trade.PartnerLocked and not trade.OwnConfirmed
	confirmButton.AutoButtonColor = confirmButton.Active
end

local function refresh()
	invoke("Get")
	render()
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		playerGui:SetAttribute("SkyDungeonExclusivePanel", "Trade")
		refresh()
	end
end)
close.Activated:Connect(function()
	panel.Visible = false
end)
lockButton.Activated:Connect(function()
	invoke("Lock")
	render()
end)
confirmButton.Activated:Connect(function()
	invoke("Confirm")
	render()
end)
cancelButton.Activated:Connect(function()
	invoke("Cancel")
	render()
end)

event.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.State) == "table" then
		state = payload.State
	end
	if payload.Message then
		status.Text = tostring(payload.Message)
	end
	if payload.Action == "Invite" then
		panel.Visible = true
	end
	render()
end)

RunService.RenderStepped:Connect(function()
	local trade = state.Session
	local endsAt = trade and tonumber(trade.CountdownEndsAt)
	if endsAt then
		local remaining = math.max(0, endsAt - workspace:GetServerTimeNow())
		status.Text = string.format("TROCA EM %.1fs — qualquer alteração cancela a confirmação.", remaining)
	end
end)
