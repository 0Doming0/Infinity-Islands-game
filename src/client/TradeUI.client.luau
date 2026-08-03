-- HUD responsivo e autoritativo para troca de slimes.
-- O servidor valida propriedade, distancia, bloqueio, confirmacao e persistencia.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("TradeRequest")
local event = ReplicatedStorage:WaitForChild("TradeEvent")

local COLORS = {
	Panel = Color3.fromRGB(18, 18, 29),
	Card = Color3.fromRGB(35, 32, 48),
	Accent = Color3.fromRGB(181, 126, 255),
	AccentDark = Color3.fromRGB(72, 52, 101),
	Text = Color3.fromRGB(244, 240, 249),
	Muted = Color3.fromRGB(190, 182, 202),
	Good = Color3.fromRGB(65, 188, 126),
	Bad = Color3.fromRGB(183, 73, 83),
	Gold = Color3.fromRGB(244, 195, 89),
}

local gui = Instance.new("ScreenGui")
gui.Name = "TradeUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 31
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "TradeButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -72, 0, 12)
openButton.Size = UDim2.fromOffset(48, 38)
openButton.BackgroundColor3 = Color3.fromRGB(52, 38, 78)
openButton.BackgroundTransparency = 0.06
openButton.Text = ""
openButton.Parent = gui
Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 10)
local openStroke = Instance.new("UIStroke")
openStroke.Color = COLORS.Accent
openStroke.Transparency = 0.35
openStroke.Parent = openButton

local navIcon = Instance.new("TextLabel")
navIcon.Position = UDim2.new(0, 0, 0, 1)
navIcon.Size = UDim2.new(1, 0, 0, 23)
navIcon.BackgroundTransparency = 1
navIcon.Text = "⇄"
navIcon.TextColor3 = Color3.fromRGB(229, 205, 255)
navIcon.Font = Enum.Font.GothamBold
navIcon.TextSize = 21
navIcon.Parent = openButton
local navCaption = Instance.new("TextLabel")
navCaption.AnchorPoint = Vector2.new(0, 1)
navCaption.Position = UDim2.new(0, 0, 1, -3)
navCaption.Size = UDim2.new(1, 0, 0, 12)
navCaption.BackgroundTransparency = 1
navCaption.Text = "TROCA"
navCaption.TextColor3 = Color3.fromRGB(220, 199, 241)
navCaption.Font = Enum.Font.GothamBold
navCaption.TextSize = 8
navCaption.Parent = openButton

local inviteBadge = Instance.new("TextLabel")
inviteBadge.AnchorPoint = Vector2.new(0.5, 0.5)
inviteBadge.Position = UDim2.new(1, -2, 0, 2)
inviteBadge.Size = UDim2.fromOffset(18, 18)
inviteBadge.BackgroundColor3 = Color3.fromRGB(239, 76, 91)
inviteBadge.Text = "0"
inviteBadge.TextColor3 = Color3.new(1, 1, 1)
inviteBadge.Font = Enum.Font.GothamBold
inviteBadge.TextSize = 10
inviteBadge.Visible = false
inviteBadge.ZIndex = 3
inviteBadge.Parent = openButton
Instance.new("UICorner", inviteBadge).CornerRadius = UDim.new(1, 0)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 58)
panel.Size = UDim2.fromOffset(440, 550)
panel.BackgroundColor3 = COLORS.Panel
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 15)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Accent
panelStroke.Transparency = 0.55
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(15, 9)
title.Size = UDim2.new(1, -58, 0, 30)
title.BackgroundTransparency = 1
title.Text = "⇄  TROCA DE SLIMES"
title.TextColor3 = Color3.fromRGB(224, 196, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 9)
close.Size = UDim2.fromOffset(32, 30)
close.BackgroundColor3 = Color3.fromRGB(66, 53, 76)
close.Text = "×"
close.TextColor3 = COLORS.Text
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(15, 43)
status.Size = UDim2.new(1, -30, 0, 45)
status.BackgroundColor3 = Color3.fromRGB(27, 25, 39)
status.BackgroundTransparency = 0.18
status.Text = "Convide um jogador proximo para trocar slimes."
status.TextColor3 = Color3.fromRGB(213, 205, 224)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Center
status.Parent = panel
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 9)
local statusPadding = Instance.new("UIPadding")
statusPadding.PaddingLeft = UDim.new(0, 10)
statusPadding.PaddingRight = UDim.new(0, 10)
statusPadding.Parent = status

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(12, 96)
list.Size = UDim2.new(1, -24, 1, -158)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = COLORS.Accent
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.Parent = list
local listPadding = Instance.new("UIPadding")
listPadding.PaddingRight = UDim.new(0, 5)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.Parent = list

local footer = Instance.new("Frame")
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 12, 1, -9)
footer.Size = UDim2.new(1, -24, 0, 43)
footer.BackgroundTransparency = 1
footer.Parent = panel
local footerLayout = Instance.new("UIListLayout")
footerLayout.FillDirection = Enum.FillDirection.Horizontal
footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
footerLayout.Padding = UDim.new(0, 6)
footerLayout.Parent = footer

local function footerButton(name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(1 / 3, -4, 0, 36)
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = COLORS.Text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 10
	button.Visible = false
	button.Parent = footer
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)
	return button
end

local lockButton = footerButton("Lock", "🔒  TRAVAR", COLORS.AccentDark)
local confirmButton = footerButton("Confirm", "✓  CONFIRMAR", Color3.fromRGB(42, 122, 83))
local cancelButton = footerButton("Cancel", "×  CANCELAR", Color3.fromRGB(121, 52, 61))

-- Toast de convite/resultado: informa sem tomar a tela do jogador.
local toast = Instance.new("Frame")
toast.Name = "TradeToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 76)
toast.Size = UDim2.fromOffset(350, 78)
toast.BackgroundColor3 = Color3.fromRGB(35, 29, 47)
toast.BorderSizePixel = 0
toast.Visible = false
toast.ZIndex = 20
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 13)
local toastStroke = Instance.new("UIStroke")
toastStroke.Color = COLORS.Accent
toastStroke.Thickness = 1.5
toastStroke.Parent = toast
local toastIcon = Instance.new("TextLabel")
toastIcon.Position = UDim2.fromOffset(10, 8)
toastIcon.Size = UDim2.fromOffset(34, 34)
toastIcon.BackgroundTransparency = 1
toastIcon.Text = "⇄"
toastIcon.TextColor3 = COLORS.Accent
toastIcon.Font = Enum.Font.GothamBold
toastIcon.TextSize = 25
toastIcon.ZIndex = 21
toastIcon.Parent = toast
local toastText = Instance.new("TextLabel")
toastText.Position = UDim2.fromOffset(48, 7)
toastText.Size = UDim2.new(1, -58, 0, 38)
toastText.BackgroundTransparency = 1
toastText.Text = ""
toastText.TextColor3 = COLORS.Text
toastText.Font = Enum.Font.GothamMedium
toastText.TextSize = 12
toastText.TextWrapped = true
toastText.TextXAlignment = Enum.TextXAlignment.Left
toastText.ZIndex = 21
toastText.Parent = toast
local toastActions = Instance.new("Frame")
toastActions.Position = UDim2.fromOffset(48, 47)
toastActions.Size = UDim2.new(1, -58, 0, 24)
toastActions.BackgroundTransparency = 1
toastActions.ZIndex = 21
toastActions.Parent = toast
local toastLayout = Instance.new("UIListLayout")
toastLayout.FillDirection = Enum.FillDirection.Horizontal
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toastActions
local function toastButton(name)
	local value = Instance.new("TextButton")
	value.Name = name
	value.Size = UDim2.fromOffset(82, 24)
	value.BackgroundColor3 = COLORS.AccentDark
	value.TextColor3 = COLORS.Text
	value.Font = Enum.Font.GothamBold
	value.TextSize = 9
	value.Visible = false
	value.ZIndex = 22
	value.Parent = toastActions
	Instance.new("UICorner", value).CornerRadius = UDim.new(0, 7)
	return value
end
local toastPrimary = toastButton("Primary")
local toastSecondary = toastButton("Secondary")
local toastSerial = 0
local toastPrimaryConnection
local toastSecondaryConnection

local function showToast(message, tone, primaryText, primaryCallback, secondaryText, secondaryCallback, duration)
	toastSerial += 1
	local serial = toastSerial
	toast.Visible = true
	toastText.Text = tostring(message or "")
	toastStroke.Color = tone or COLORS.Accent
	toastIcon.TextColor3 = tone or COLORS.Accent
	toastPrimary.Visible = primaryText ~= nil
	toastPrimary.Text = tostring(primaryText or "")
	toastPrimary.BackgroundColor3 = tone == COLORS.Bad and COLORS.Bad or Color3.fromRGB(47, 130, 91)
	toastSecondary.Visible = secondaryText ~= nil
	toastSecondary.Text = tostring(secondaryText or "")
	if toastPrimaryConnection then
		toastPrimaryConnection:Disconnect()
	end
	if toastSecondaryConnection then
		toastSecondaryConnection:Disconnect()
	end
	toastPrimaryConnection = primaryCallback and toastPrimary.Activated:Connect(primaryCallback) or nil
	toastSecondaryConnection = secondaryCallback and toastSecondary.Activated:Connect(secondaryCallback) or nil
	task.delay(duration or 5, function()
		if toastSerial == serial then
			toast.Visible = false
		end
	end)
end

local state = {
	Session = nil,
	Invites = {},
	AvailablePlayers = {},
	Inventory = {},
	MaxOffer = 4,
}
local busy = false

local function updateBadge()
	local count = #(state.Invites or {})
	inviteBadge.Visible = count > 0
	inviteBadge.Text = tostring(math.min(9, count))
end

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
		status.Text = "Sistema de troca indisponivel."
		return false
	end
	if type(response.State) == "table" then
		state = response.State
		updateBadge()
	end
	if response.Message then
		status.Text = tostring(response.Message)
	end
	return response.Success == true
end

local function clearRows()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function section(text, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -4, 0, 23)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or COLORS.Accent
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = list
end

local function imageId(value)
	local raw = tostring(value or "")
	if raw == "" or raw == "0" then
		return ""
	end
	if string.match(raw, "^%d+$") then
		return "rbxassetid://" .. raw
	end
	return raw
end

local function petText(entry)
	local upgrades = entry.Upgrades or {}
	local upgradeTotal = 0
	for _, amount in pairs(upgrades) do
		upgradeTotal += tonumber(amount) or 0
	end
	local equipped = entry.Equipped and "  [EM USO]" or ""
	return string.format(
		"%s%s\n%s  •  Nv.%d  •  %d melhoria(s)  •  %d abate(s)",
		tostring(entry.DisplayName or "Slime"),
		equipped,
		tostring(entry.SpeciesName or entry.SpeciesId or ""),
		tonumber(entry.Level) or 1,
		upgradeTotal,
		tonumber(entry.Kills) or 0
	)
end

local function row(text, entry, primaryText, primaryCallback, primaryColor, secondaryText, secondaryCallback)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -4, 0, entry and 60 or 42)
	frame.BackgroundColor3 = COLORS.Card
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.Parent = list
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 9)

	local contentLeft = 10
	if entry then
		local icon = Instance.new("ImageLabel")
		icon.Position = UDim2.fromOffset(8, 8)
		icon.Size = UDim2.fromOffset(44, 44)
		icon.BackgroundColor3 = typeof(entry.Color) == "Color3" and entry.Color or Color3.fromRGB(116, 165, 144)
		icon.BackgroundTransparency = 0.14
		icon.BorderSizePixel = 0
		icon.Image = imageId(entry.ImageId)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = frame
		Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)
		if icon.Image == "" then
			local fallback = Instance.new("TextLabel")
			fallback.Size = UDim2.fromScale(1, 1)
			fallback.BackgroundTransparency = 1
			fallback.Text = "S"
			fallback.TextColor3 = Color3.new(1, 1, 1)
			fallback.Font = Enum.Font.GothamBlack
			fallback.TextSize = 20
			fallback.Parent = icon
		end
		contentLeft = 60
	end

	local actionWidth = secondaryText and 150 or (primaryText and 80 or 0)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(contentLeft, 3)
	label.Size = UDim2.new(1, -(contentLeft + actionWidth + 8), 1, -6)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.Text
	label.Font = Enum.Font.GothamMedium
	label.TextSize = entry and 10 or 11
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = frame

	local function actionButton(caption, callback, position, color)
		local action = Instance.new("TextButton")
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = position
		action.Size = UDim2.fromOffset(70, 29)
		action.BackgroundColor3 = color
		action.Text = caption
		action.TextColor3 = COLORS.Text
		action.Font = Enum.Font.GothamBold
		action.TextSize = 9
		action.Parent = frame
		Instance.new("UICorner", action).CornerRadius = UDim.new(0, 7)
		action.Activated:Connect(callback)
	end
	if secondaryText then
		actionButton(secondaryText, secondaryCallback, UDim2.new(1, -6, 0.5, 0), COLORS.Bad)
	end
	if primaryText then
		actionButton(
			primaryText,
			primaryCallback,
			secondaryText and UDim2.new(1, -82, 0.5, 0) or UDim2.new(1, -6, 0.5, 0),
			primaryColor or COLORS.AccentDark
		)
	end
end

local render
render = function()
	clearRows()
	updateBadge()
	local trade = state.Session
	lockButton.Visible = trade ~= nil
	confirmButton.Visible = trade ~= nil
	cancelButton.Visible = trade ~= nil
	if not trade then
		title.Text = "⇄  TROCA DE SLIMES"
		status.Text = "Convide um jogador proximo. A troca so conclui apos os dois confirmarem."
		if #(state.Invites or {}) > 0 then
			section("CONVITES RECEBIDOS", COLORS.Gold)
			for _, invite in ipairs(state.Invites) do
				row(
					invite.DisplayName .. " quer trocar slimes com voce.",
					nil,
					"ACEITAR",
					function()
						if invoke("Accept", { UserId = invite.UserId }) then
							panel.Visible = true
							playerGui:SetAttribute("SkyDungeonExclusivePanel", "Trade")
						end
						render()
					end,
					COLORS.Good,
					"RECUSAR",
					function()
						invoke("Decline", { UserId = invite.UserId })
						render()
					end
				)
			end
		end
		section("JOGADORES PROXIMOS")
		for _, available in ipairs(state.AvailablePlayers or {}) do
			row(available.DisplayName, nil, "CONVIDAR", function()
				if invoke("Invite", { UserId = available.UserId }) then
					showToast(
						"Convite de troca enviado para " .. available.DisplayName .. ".",
						COLORS.Good,
						nil,
						nil,
						nil,
						nil,
						3
					)
				end
				render()
			end)
		end
		if #(state.AvailablePlayers or {}) == 0 then
			row("Nenhum jogador proximo e disponivel para troca.")
		end
		return
	end

	title.Text = "⇄  TROCA COM " .. string.upper(trade.PartnerDisplayName)
	local ownState = trade.OwnLocked and "SUA OFERTA TRAVADA" or "MONTE SUA OFERTA"
	local partnerState = trade.PartnerLocked and "PARCEIRO TRAVADO" or "PARCEIRO EDITANDO"
	status.Text = ownState .. "   •   " .. partnerState
	section(string.format("SUA OFERTA  %d/%d", #(trade.OwnOffer or {}), state.MaxOffer or 4), COLORS.Gold)
	for _, entry in ipairs(trade.OwnOffer or {}) do
		row(petText(entry), entry, "REMOVER", function()
			invoke("Remove", { InstanceId = entry.InstanceId })
			render()
		end, COLORS.Bad)
	end
	if #(trade.OwnOffer or {}) == 0 then
		row("Adicione pelo menos um slime ou aceite uma troca-presente.")
	end

	section("OFERTA DE " .. string.upper(trade.PartnerDisplayName))
	for _, entry in ipairs(trade.PartnerOffer or {}) do
		row(petText(entry), entry)
	end
	if #(trade.PartnerOffer or {}) == 0 then
		row("O outro jogador ainda nao adicionou nenhum slime.")
	end

	section("SEUS SLIMES  •  EM USO SERAO DESEQUIPADOS")
	for _, entry in ipairs(state.Inventory or {}) do
		local alreadyOffered = false
		for _, offered in ipairs(trade.OwnOffer or {}) do
			if offered.InstanceId == entry.InstanceId then
				alreadyOffered = true
				break
			end
		end
		if not alreadyOffered then
			row(petText(entry), entry, "ADICIONAR", function()
				invoke("Add", { InstanceId = entry.InstanceId })
				render()
			end)
		end
	end
	lockButton.Text = trade.OwnLocked and "🔓  DESTRAVAR" or "🔒  TRAVAR"
	confirmButton.Text = trade.OwnConfirmed and "✓  CONFIRMADO" or "✓  CONFIRMAR"
	confirmButton.Active = trade.OwnLocked and trade.PartnerLocked and not trade.OwnConfirmed
	confirmButton.AutoButtonColor = confirmButton.Active
	confirmButton.BackgroundTransparency = confirmButton.Active and 0 or 0.55
end

local function refresh()
	invoke("Get")
	render()
end

local function openPanel()
	panel.Visible = true
	playerGui:SetAttribute("SkyDungeonExclusivePanel", "Trade")
	refresh()
end

openButton.Activated:Connect(function()
	if panel.Visible then
		panel.Visible = false
	else
		openPanel()
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
	if confirmButton.Active then
		invoke("Confirm")
		render()
	end
end)
cancelButton.Activated:Connect(function()
	invoke("Cancel")
	render()
end)

playerGui:GetAttributeChangedSignal("SkyDungeonExclusivePanel"):Connect(function()
	if playerGui:GetAttribute("SkyDungeonExclusivePanel") ~= "Trade" then
		panel.Visible = false
	end
end)

event.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.State) == "table" then
		state = payload.State
		updateBadge()
	end
	if payload.Message then
		status.Text = tostring(payload.Message)
	end
	if payload.Action == "Invite" then
		local inviterUserId = tonumber(payload.FromUserId)
		local inviterName = tostring(payload.FromDisplayName or "Um jogador")
		if not inviterUserId and state.Invites and state.Invites[1] then
			inviterUserId = state.Invites[1].UserId
			inviterName = state.Invites[1].DisplayName
		end
		showToast(
			inviterName .. " convidou voce para trocar slimes.",
			COLORS.Gold,
			"ACEITAR",
			function()
				if inviterUserId and invoke("Accept", { UserId = inviterUserId }) then
					toast.Visible = false
					openPanel()
				else
					render()
				end
			end,
			"RECUSAR",
			function()
				if inviterUserId then
					invoke("Decline", { UserId = inviterUserId })
				end
				toast.Visible = false
				render()
			end,
			8
		)
	elseif payload.Action == "Completed" then
		panel.Visible = false
		local partnerName = tostring(payload.PartnerDisplayName or "o outro jogador")
		showToast("✓ Troca feita com sucesso com " .. partnerName .. "!", COLORS.Good, nil, nil, nil, nil, 5)
	elseif payload.Action == "Cancelled" then
		showToast(tostring(payload.Message or "Troca cancelada."), COLORS.Bad, nil, nil, nil, nil, 4)
	elseif payload.Action == "Started" then
		panel.Visible = true
		playerGui:SetAttribute("SkyDungeonExclusivePanel", "Trade")
	end
	if panel.Visible then
		render()
	end
end)

RunService.RenderStepped:Connect(function()
	local trade = state.Session
	local endsAt = trade and tonumber(trade.CountdownEndsAt)
	if endsAt then
		local remaining = math.max(0, endsAt - workspace:GetServerTimeNow())
		status.Text = string.format("VERIFICANDO TROCA EM %.1fs  •  qualquer alteracao cancela", remaining)
	end
end)

local function responsive()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local compact = UserInputService.TouchEnabled or viewport.X < 700
	if compact then
		openButton.Position = UDim2.new(1, -10, 0, 154)
		openButton.Size = UDim2.fromOffset(52, 42)
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromOffset(math.max(300, viewport.X - 18), math.max(420, viewport.Y - 76))
		toast.Size = UDim2.fromOffset(math.max(292, math.min(350, viewport.X - 18)), 78)
		title.TextSize = 15
	else
		openButton.Position = UDim2.new(1, -72, 0, 12)
		openButton.Size = UDim2.fromOffset(48, 38)
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -12, 0, 58)
		panel.Size = UDim2.fromOffset(440, math.min(550, viewport.Y - 70))
		toast.Size = UDim2.fromOffset(350, 78)
		title.TextSize = 18
	end
end

local cameraConnection
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(responsive)
	end
	responsive()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

task.spawn(function()
	while true do
		task.wait(panel.Visible and 2.5 or 6)
		refresh()
	end
end)
