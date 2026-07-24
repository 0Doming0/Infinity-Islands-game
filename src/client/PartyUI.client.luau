-- Painel de grupo e indicadores de tela para companheiros distantes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("PartyRequest")
local event = ReplicatedStorage:WaitForChild("PartyEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "PartyUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 18
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "PartyButton"
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -68, 0, 12)
button.Size = UDim2.fromOffset(48, 38)
button.BackgroundColor3 = Color3.fromRGB(23, 48, 45)
button.BackgroundTransparency = 0.12
button.Text = "GRP"
button.TextColor3 = Color3.fromRGB(111, 245, 206)
button.Font = Enum.Font.GothamBold
button.TextSize = 12
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 58)
panel.Size = UDim2.fromOffset(330, 440)
panel.BackgroundColor3 = Color3.fromRGB(14, 24, 27)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 13)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(14, 9)
title.Size = UDim2.new(1, -28, 0, 28)
title.BackgroundTransparency = 1
title.Text = "GRUPO"
title.TextColor3 = Color3.fromRGB(111, 245, 206)
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(14, 38)
status.Size = UDim2.new(1, -28, 0, 42)
status.BackgroundTransparency = 1
status.Text = "Crie um grupo convidando outro jogador."
status.TextColor3 = Color3.fromRGB(191, 207, 211)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(12, 84)
list.Size = UDim2.new(1, -24, 1, -132)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local leaveButton = Instance.new("TextButton")
leaveButton.AnchorPoint = Vector2.new(0.5, 1)
leaveButton.Position = UDim2.new(0.5, 0, 1, -10)
leaveButton.Size = UDim2.new(1, -28, 0, 34)
leaveButton.BackgroundColor3 = Color3.fromRGB(105, 43, 48)
leaveButton.Text = "SAIR DO GRUPO"
leaveButton.TextColor3 = Color3.fromRGB(255, 218, 220)
leaveButton.Font = Enum.Font.GothamBold
leaveButton.TextSize = 12
leaveButton.Visible = false
leaveButton.Parent = panel
Instance.new("UICorner", leaveButton).CornerRadius = UDim.new(0, 9)

local currentState
local markers = {}

local function invoke(action, payload)
	local success, accepted, message, state = pcall(function()
		return request:InvokeServer(action, payload)
	end)
	if not success then
		status.Text = "Servico de grupo indisponivel."
		return false
	end
	if type(state) == "table" then
		currentState = state
	end
	if message then
		status.Text = tostring(message)
	end
	return accepted == true
end

local function clearRows()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function createSection(text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -4, 0, 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(111, 245, 206)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = list
end

local function createRow(text, actionText, callback, danger)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 38)
	row.BackgroundColor3 = Color3.fromRGB(27, 42, 46)
	row.BackgroundTransparency = 0.12
	row.BorderSizePixel = 0
	row.Parent = list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(1, actionText and -98 or -20, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(237, 244, 245)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row
	if actionText then
		local action = Instance.new("TextButton")
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -6, 0.5, 0)
		action.Size = UDim2.fromOffset(82, 28)
		action.BackgroundColor3 = danger and Color3.fromRGB(111, 48, 54) or Color3.fromRGB(37, 96, 82)
		action.Text = actionText
		action.TextColor3 = Color3.fromRGB(235, 255, 249)
		action.Font = Enum.Font.GothamBold
		action.TextSize = 10
		action.Parent = row
		Instance.new("UICorner", action).CornerRadius = UDim.new(0, 7)
		action.Activated:Connect(callback)
	end
	return row
end

local render
render = function()
	clearRows()
	local state = currentState or {}
	local party = state.Party
	leaveButton.Visible = party ~= nil
	if party then
		title.Text = string.format("GRUPO  %d/%d", #(party.Members or {}), state.MaxMembers or 4)
		local mission = party.Mission or {}
		status.Text = string.format(
			"PONTUACAO COMPARTILHADA: %d\n%s  |  MOBS %d/%d  •  ILHAS %d/%d%s",
			party.SharedScore or 0,
			mission.Title or "MISSAO",
			mission.MobDefeated or 0,
			mission.MobDefeatedGoal or 5,
			mission.IslandVisited or 0,
			mission.IslandVisitedGoal or 3,
			mission.Completed and "  CONCLUIDA!" or ""
		)
		createSection("MEMBROS")
		local isLeader = party.LeaderUserId == player.UserId
		for _, member in ipairs(party.Members or {}) do
			local suffix = member.IsLeader and "  [LIDER]" or ""
			local canKick = isLeader and member.UserId ~= player.UserId
			createRow(member.DisplayName .. suffix, canKick and "REMOVER" or nil, function()
				invoke("Kick", { UserId = member.UserId })
				render()
			end, true)
		end
		if isLeader and #(party.Members or {}) < (state.MaxMembers or 4) then
			createSection("CONVIDAR")
			for _, available in ipairs(state.AvailablePlayers or {}) do
				createRow(available.DisplayName, "CONVIDAR", function()
					invoke("Invite", { UserId = available.UserId })
					render()
				end)
			end
		end
	else
		title.Text = "GRUPO"
		status.Text = "Convide um jogador ou aceite um convite."
		if #(state.Invites or {}) > 0 then
			createSection("CONVITES")
			for _, invite in ipairs(state.Invites) do
				createRow(invite.DisplayName, "ACEITAR", function()
					invoke("Accept", { UserId = invite.UserId })
					render()
				end)
			end
		end
		createSection("JOGADORES NO SERVIDOR")
		for _, available in ipairs(state.AvailablePlayers or {}) do
			createRow(available.DisplayName, "CONVIDAR", function()
				invoke("Invite", { UserId = available.UserId })
				render()
			end)
		end
	end
end

local function refresh()
	invoke("GetState")
	render()
end

button.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		playerGui:SetAttribute("SkyDungeonExclusivePanel", "Party")
		refresh()
	end
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
	end
	if data.Message then
		status.Text = tostring(data.Message)
	end
	if panel.Visible or data.Action == "Invite" or data.Action == "MissionComplete" then
		panel.Visible = true
		playerGui:SetAttribute("SkyDungeonExclusivePanel", "Party")
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
	marker.Size = UDim2.fromOffset(170, 30)
	marker.BackgroundColor3 = Color3.fromRGB(12, 30, 34)
	marker.BackgroundTransparency = 0.18
	marker.BorderSizePixel = 0
	marker.TextColor3 = Color3.fromRGB(111, 245, 206)
	marker.TextStrokeTransparency = 0.55
	marker.Font = Enum.Font.GothamBold
	marker.TextSize = 11
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
			local threshold = currentState.IndicatorDistanceStuds or 70
			if distance < threshold then
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
				math.clamp(point.X, 92, math.max(92, viewport.X - 92)),
				math.clamp(point.Y, 32, math.max(32, viewport.Y - 32))
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

task.spawn(function()
	while true do
		task.wait(4)
		if panel.Visible then
			refresh()
		end
	end
end)

refresh()
