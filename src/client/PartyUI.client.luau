-- HUD responsivo de grupo, convites acionaveis e indicadores de aliados.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local request = RemoteRegistry.Get("Party", "Request", "RemoteFunction")
local event = RemoteRegistry.Get("Party", "Event", "RemoteEvent")

local COLORS = {
	Panel = Color3.fromRGB(14, 24, 27),
	Card = Color3.fromRGB(27, 43, 46),
	Accent = Color3.fromRGB(93, 235, 193),
	AccentDark = Color3.fromRGB(35, 102, 84),
	Text = Color3.fromRGB(238, 247, 246),
	Muted = Color3.fromRGB(184, 205, 204),
	Good = Color3.fromRGB(65, 188, 126),
	Bad = Color3.fromRGB(174, 69, 79),
	Gold = Color3.fromRGB(247, 201, 96),
}

local gui = Instance.new("ScreenGui")
gui.Name = "PartyUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "PartyButton"
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -128, 0, 12)
button.Size = UDim2.fromOffset(48, 38)
button.BackgroundColor3 = Color3.fromRGB(23, 54, 49)
button.BackgroundTransparency = 0.06
button.Text = ""
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = COLORS.Accent
buttonStroke.Transparency = 0.38
buttonStroke.Parent = button

-- Icone de duas pessoas construido com GuiObjects, sem depender de asset ID.
local peopleIcon = Instance.new("Frame")
peopleIcon.Position = UDim2.new(0.5, -15, 0, 4)
peopleIcon.Size = UDim2.fromOffset(30, 20)
peopleIcon.BackgroundTransparency = 1
peopleIcon.Parent = button
for index, x in ipairs({ 6, 18 }) do
	local head = Instance.new("Frame")
	head.Position = UDim2.fromOffset(x, index == 1 and 0 or 2)
	head.Size = UDim2.fromOffset(8, 8)
	head.BackgroundColor3 = index == 1 and COLORS.Accent or Color3.fromRGB(202, 255, 238)
	head.BorderSizePixel = 0
	head.Parent = peopleIcon
	Instance.new("UICorner", head).CornerRadius = UDim.new(1, 0)
	local body = Instance.new("Frame")
	body.Position = UDim2.fromOffset(x - 3, index == 1 and 9 or 11)
	body.Size = UDim2.fromOffset(14, 8)
	body.BackgroundColor3 = head.BackgroundColor3
	body.BorderSizePixel = 0
	body.Parent = peopleIcon
	Instance.new("UICorner", body).CornerRadius = UDim.new(1, 0)
end
local navCaption = Instance.new("TextLabel")
navCaption.AnchorPoint = Vector2.new(0, 1)
navCaption.Position = UDim2.new(0, 0, 1, -3)
navCaption.Size = UDim2.new(1, 0, 0, 11)
navCaption.BackgroundTransparency = 1
navCaption.Text = "GRUPO"
navCaption.TextColor3 = Color3.fromRGB(205, 244, 232)
navCaption.Font = Enum.Font.GothamBold
navCaption.TextSize = 8
navCaption.Parent = button

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
inviteBadge.Parent = button
Instance.new("UICorner", inviteBadge).CornerRadius = UDim.new(1, 0)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 58)
panel.Size = UDim2.fromOffset(350, 470)
panel.BackgroundColor3 = COLORS.Panel
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Accent
panelStroke.Transparency = 0.6
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(14, 9)
title.Size = UDim2.new(1, -58, 0, 28)
title.BackgroundTransparency = 1
title.Text = "GRUPO"
title.TextColor3 = COLORS.Accent
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 8)
close.Size = UDim2.fromOffset(32, 30)
close.BackgroundColor3 = Color3.fromRGB(48, 65, 66)
close.Text = "×"
close.TextColor3 = COLORS.Text
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(12, 43)
status.Size = UDim2.new(1, -24, 0, 58)
status.BackgroundColor3 = Color3.fromRGB(22, 36, 39)
status.BackgroundTransparency = 0.12
status.Text = "Convide um jogador ou aceite um convite."
status.TextColor3 = COLORS.Muted
status.Font = Enum.Font.Gotham
status.TextSize = 11
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
list.Position = UDim2.fromOffset(12, 108)
list.Size = UDim2.new(1, -24, 1, -157)
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
listPadding.Parent = list

local leaveButton = Instance.new("TextButton")
leaveButton.AnchorPoint = Vector2.new(0.5, 1)
leaveButton.Position = UDim2.new(0.5, 0, 1, -9)
leaveButton.Size = UDim2.new(1, -24, 0, 34)
leaveButton.BackgroundColor3 = Color3.fromRGB(105, 43, 48)
leaveButton.Text = "SAIR DO GRUPO"
leaveButton.TextColor3 = Color3.fromRGB(255, 225, 227)
leaveButton.Font = Enum.Font.GothamBold
leaveButton.TextSize = 11
leaveButton.Visible = false
leaveButton.Parent = panel
Instance.new("UICorner", leaveButton).CornerRadius = UDim.new(0, 9)

local toast = Instance.new("Frame")
toast.Name = "PartyToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 160)
toast.Size = UDim2.fromOffset(350, 78)
toast.BackgroundColor3 = Color3.fromRGB(21, 43, 39)
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
toastIcon.Position = UDim2.fromOffset(11, 8)
toastIcon.Size = UDim2.fromOffset(32, 34)
toastIcon.BackgroundTransparency = 1
toastIcon.Text = "●●"
toastIcon.TextColor3 = COLORS.Accent
toastIcon.Font = Enum.Font.GothamBold
toastIcon.TextSize = 15
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
local primaryConnection
local secondaryConnection

local function showToast(message, tone, primaryText, primaryCallback, secondaryText, secondaryCallback, duration)
	toastSerial += 1
	local serial = toastSerial
	toast.Visible = true
	toastText.Text = tostring(message or "")
	toastStroke.Color = tone or COLORS.Accent
	toastIcon.TextColor3 = tone or COLORS.Accent
	toastPrimary.Visible = primaryText ~= nil
	toastPrimary.Text = tostring(primaryText or "")
	toastPrimary.BackgroundColor3 = tone == COLORS.Bad and COLORS.Bad or COLORS.AccentDark
	toastSecondary.Visible = secondaryText ~= nil
	toastSecondary.Text = tostring(secondaryText or "")
	if primaryConnection then
		primaryConnection:Disconnect()
	end
	if secondaryConnection then
		secondaryConnection:Disconnect()
	end
	primaryConnection = primaryCallback and toastPrimary.Activated:Connect(primaryCallback) or nil
	secondaryConnection = secondaryCallback and toastSecondary.Activated:Connect(secondaryCallback) or nil
	task.delay(duration or 5, function()
		if toastSerial == serial then
			toast.Visible = false
		end
	end)
end

local currentState
local markers = {}
local busy = false

local function updateBadge()
	local count = currentState and #(currentState.Invites or {}) or 0
	inviteBadge.Visible = count > 0
	inviteBadge.Text = tostring(math.min(9, count))
end

local function invoke(action, payload)
	if busy then
		return false
	end
	busy = true
	local success, accepted, message, state = pcall(function()
		return request:InvokeServer(action, payload)
	end)
	busy = false
	if not success then
		status.Text = "Servico de grupo indisponivel."
		return false
	end
	if type(state) == "table" then
		currentState = state
		updateBadge()
	end
	if message then
		status.Text = tostring(message)
	end
	return accepted == true
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

local function row(text, primaryText, primaryCallback, danger, secondaryText, secondaryCallback)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -4, 0, 44)
	frame.BackgroundColor3 = COLORS.Card
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = list
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 9)
	local avatar = Instance.new("TextLabel")
	avatar.Position = UDim2.fromOffset(7, 7)
	avatar.Size = UDim2.fromOffset(30, 30)
	avatar.BackgroundColor3 = COLORS.AccentDark
	avatar.Text = string.sub(string.upper(text), 1, 1)
	avatar.TextColor3 = COLORS.Text
	avatar.Font = Enum.Font.GothamBold
	avatar.TextSize = 13
	avatar.Parent = frame
	Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)
	local actionWidth = secondaryText and 150 or (primaryText and 80 or 0)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(45, 2)
	label.Size = UDim2.new(1, -(53 + actionWidth), 1, -4)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.Text
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame
	local function actionButton(caption, callback, position, color)
		local action = Instance.new("TextButton")
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = position
		action.Size = UDim2.fromOffset(70, 28)
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
			danger and COLORS.Bad or COLORS.AccentDark
		)
	end
end

local render
render = function()
	clearRows()
	updateBadge()
	local state = currentState or {}
	local party = state.Party
	leaveButton.Visible = party ~= nil
	if party then
		title.Text = string.format("GRUPO  %d/%d", #(party.Members or {}), state.MaxMembers or 4)
		local mission = party.Mission or {}
		status.Text = string.format(
			"PONTOS %d  •  %s\nMOBS %d/%d   •   ILHAS %d/%d%s",
			party.SharedScore or 0,
			mission.Title or "MISSAO",
			mission.MobDefeated or 0,
			mission.MobDefeatedGoal or 5,
			mission.IslandVisited or 0,
			mission.IslandVisitedGoal or 3,
			mission.Completed and "   ✓ CONCLUIDA" or ""
		)
		section("MEMBROS", COLORS.Gold)
		local isLeader = party.LeaderUserId == player.UserId
		for _, member in ipairs(party.Members or {}) do
			local suffix = member.IsLeader and "  ★ LIDER" or ""
			local canKick = isLeader and member.UserId ~= player.UserId
			row(member.DisplayName .. suffix, canKick and "REMOVER" or nil, function()
				invoke("Kick", { UserId = member.UserId })
				render()
			end, true)
		end
		if isLeader and #(party.Members or {}) < (state.MaxMembers or 4) then
			section("CONVIDAR JOGADORES")
			for _, available in ipairs(state.AvailablePlayers or {}) do
				row(available.DisplayName, "CONVIDAR", function()
					if invoke("Invite", { UserId = available.UserId }) then
						showToast(
							"Convite de grupo enviado para " .. available.DisplayName .. ".",
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
		end
	else
		title.Text = "GRUPO"
		status.Text = "Jogue em equipe, compartilhe pontos e complete a expedicao do grupo."
		if #(state.Invites or {}) > 0 then
			section("CONVITES RECEBIDOS", COLORS.Gold)
			for _, invite in ipairs(state.Invites) do
				row(
					invite.DisplayName .. " convidou voce.",
					"ACEITAR",
					function()
						invoke("Accept", { UserId = invite.UserId })
						render()
					end,
					false,
					"RECUSAR",
					function()
						invoke("Decline", { UserId = invite.UserId })
						render()
					end
				)
			end
		end
		section("JOGADORES NO SERVIDOR")
		for _, available in ipairs(state.AvailablePlayers or {}) do
			row(available.DisplayName, "CONVIDAR", function()
				if invoke("Invite", { UserId = available.UserId }) then
					showToast(
						"Convite de grupo enviado para " .. available.DisplayName .. ".",
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
	end
end

local function refresh()
	invoke("GetState")
	render()
end

local function openPanel()
	panel.Visible = true
	playerGui:SetAttribute("SkyDungeonExclusivePanel", "Party")
	refresh()
end

button.Activated:Connect(function()
	if panel.Visible then
		panel.Visible = false
	else
		openPanel()
	end
end)
close.Activated:Connect(function()
	panel.Visible = false
end)
leaveButton.Activated:Connect(function()
	invoke("Leave")
	render()
end)
playerGui:GetAttributeChangedSignal("SkyDungeonExclusivePanel"):Connect(function()
	if playerGui:GetAttribute("SkyDungeonExclusivePanel") ~= "Party" then
		panel.Visible = false
	end
end)

event.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if type(data.State) == "table" then
		currentState = data.State
		updateBadge()
	end
	if data.Message then
		status.Text = tostring(data.Message)
	end
	if data.Action == "Invite" then
		local inviterUserId = tonumber(data.FromUserId)
		local inviterName = tostring(data.FromDisplayName or "Um jogador")
		if not inviterUserId and currentState and currentState.Invites and currentState.Invites[1] then
			inviterUserId = currentState.Invites[1].UserId
			inviterName = currentState.Invites[1].DisplayName
		end
		showToast(
			inviterName .. " convidou voce para o grupo.",
			COLORS.Gold,
			"ACEITAR",
			function()
				if inviterUserId then
					invoke("Accept", { UserId = inviterUserId })
				end
				toast.Visible = false
				render()
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
	elseif data.Action == "MemberJoined" then
		showToast(tostring(data.Message or "Novo jogador entrou no grupo."), COLORS.Good, nil, nil, nil, nil, 4)
	elseif data.Action == "MissionComplete" then
		showToast("✓ Missao do grupo concluida!", COLORS.Gold, nil, nil, nil, nil, 5)
	elseif data.Action == "Left" or data.Action == "Dissolved" then
		showToast(tostring(data.Message or "O grupo foi encerrado."), COLORS.Bad, nil, nil, nil, nil, 4)
	end
	if panel.Visible then
		render()
	end
end)

local function getMarker(userId)
	local marker = markers[userId]
	if marker then
		return marker
	end
	marker = Instance.new("TextLabel")
	marker.Name = "PartyMarker_" .. tostring(userId)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(164, 28)
	marker.BackgroundColor3 = Color3.fromRGB(12, 30, 34)
	marker.BackgroundTransparency = 0.18
	marker.BorderSizePixel = 0
	marker.TextColor3 = COLORS.Accent
	marker.TextStrokeTransparency = 0.55
	marker.Font = Enum.Font.GothamBold
	marker.TextSize = 10
	marker.Visible = false
	marker.Parent = gui
	Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)
	markers[userId] = marker
	return marker
end

RunService.RenderStepped:Connect(function()
	local party = currentState and currentState.Party
	local camera = workspace.CurrentCamera
	local ownRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local activeIds = {}
	if party and camera and ownRoot then
		local viewport = camera.ViewportSize
		for _, member in ipairs(party.Members or {}) do
			if member.UserId == player.UserId then
				continue
			end
			activeIds[member.UserId] = true
			local marker = getMarker(member.UserId)
			local other = Players:GetPlayerByUserId(member.UserId)
			local root = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if not root then
				marker.Visible = false
				continue
			end
			local distance = (root.Position - ownRoot.Position).Magnitude
			if distance < (currentState.IndicatorDistanceStuds or 70) then
				marker.Visible = false
				continue
			end
			local projected = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
			local point = Vector2.new(projected.X, projected.Y)
			local center = viewport * 0.5
			if projected.Z < 0 then
				point = center - (point - center)
			end
			point = Vector2.new(
				math.clamp(point.X, 88, math.max(88, viewport.X - 88)),
				math.clamp(point.Y, 30, math.max(30, viewport.Y - 30))
			)
			marker.Position = UDim2.fromOffset(point.X, point.Y)
			marker.Text = string.format("GRUPO  •  %s  •  %dm", member.DisplayName, math.floor(distance))
			marker.Visible = true
		end
	end
	for userId, marker in pairs(markers) do
		if not activeIds[userId] then
			marker.Visible = false
		end
	end
end)

local function responsive()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local compact = UserInputService.TouchEnabled or viewport.X < 700
	if compact then
		button.Position = UDim2.new(1, -10, 0, 106)
		button.Size = UDim2.fromOffset(52, 42)
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromOffset(math.max(300, viewport.X - 18), math.max(390, viewport.Y - 76))
		toast.Position = UDim2.new(0.5, 0, 0, 70)
		toast.Size = UDim2.fromOffset(math.max(292, math.min(350, viewport.X - 18)), 78)
	else
		button.Position = UDim2.new(1, -128, 0, 12)
		button.Size = UDim2.fromOffset(48, 38)
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -12, 0, 58)
		panel.Size = UDim2.fromOffset(350, math.min(470, viewport.Y - 70))
		toast.Position = UDim2.new(0.5, 0, 0, 160)
		toast.Size = UDim2.fromOffset(350, 78)
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
