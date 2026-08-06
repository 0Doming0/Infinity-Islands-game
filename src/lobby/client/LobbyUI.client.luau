local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local phaseRequest = RemoteRegistry.Get("PhaseSelection", "Request", "RemoteFunction")
local phaseEvent = RemoteRegistry.Get("PhaseSelection", "Event", "RemoteEvent")
local rouletteRequest = RemoteRegistry.Get("Roulette", "Request", "RemoteFunction")
local rouletteEvent = RemoteRegistry.Get("Roulette", "Event", "RemoteEvent")
local equipmentRequest = RemoteRegistry.Get("Equipment", "Request", "RemoteFunction")
local equipmentEvent = RemoteRegistry.Get("Equipment", "Event", "RemoteEvent")
local notificationEvent = RemoteRegistry.Get("Notifications", "Lobby", "RemoteEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.42
overlay.Visible = false
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(500, 480)
panel.BackgroundColor3 = Color3.fromRGB(14, 24, 31)
panel.Parent = overlay
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(18, 12)
title.Size = UDim2.new(1, -70, 0, 38)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(102, 231, 190)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -12, 0, 10)
close.Size = UDim2.fromOffset(38, 34)
close.BackgroundColor3 = Color3.fromRGB(53, 63, 70)
close.Text = "×"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 20
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 9)

local content = Instance.new("ScrollingFrame")
content.Position = UDim2.fromOffset(16, 58)
content.Size = UDim2.new(1, -32, 1, -74)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 6
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 9)
layout.Parent = content

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 65)
toast.Size = UDim2.fromOffset(430, 52)
toast.BackgroundColor3 = Color3.fromRGB(23, 39, 47)
toast.TextColor3 = Color3.new(1, 1, 1)
toast.TextWrapped = true
toast.Font = Enum.Font.GothamBold
toast.TextSize = 15
toast.Visible = false
toast.ZIndex = 20
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 12)

local toastSerial = 0
local function showToast(message, good)
	toastSerial += 1
	local serial = toastSerial
	toast.Text = tostring(message or "")
	toast.BackgroundColor3 = good == false and Color3.fromRGB(116, 49, 55) or Color3.fromRGB(23, 70, 61)
	toast.Visible = true
	task.delay(4, function()
		if toastSerial == serial then
			toast.Visible = false
		end
	end)
end

local function clearContent()
	for _, child in ipairs(content:GetChildren()) do
		if child ~= layout then
			child:Destroy()
		end
	end
end

local function label(text, height, bold)
	local item = Instance.new("TextLabel")
	item.Size = UDim2.new(1, -4, 0, height or 42)
	item.BackgroundColor3 = Color3.fromRGB(25, 39, 47)
	item.BackgroundTransparency = 0.1
	item.Text = text
	item.TextWrapped = true
	item.TextColor3 = Color3.fromRGB(226, 238, 242)
	item.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	item.TextSize = 15
	item.Parent = content
	Instance.new("UICorner", item).CornerRadius = UDim.new(0, 10)
	return item
end

local function button(text, callback, color)
	local item = Instance.new("TextButton")
	item.Size = UDim2.new(1, -4, 0, 44)
	item.BackgroundColor3 = color or Color3.fromRGB(42, 121, 98)
	item.Text = text
	item.TextColor3 = Color3.new(1, 1, 1)
	item.Font = Enum.Font.GothamBold
	item.TextSize = 15
	item.Parent = content
	Instance.new("UICorner", item).CornerRadius = UDim.new(0, 10)
	item.Activated:Connect(callback)
	return item
end

local function invoke(remote, ...)
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		showToast("Falha de comunicacao com o servidor.", false)
		return nil
	end
	return result
end

local function open(titleText)
	title.Text = titleText
	clearContent()
	overlay.Visible = true
end

close.Activated:Connect(function()
	overlay.Visible = false
end)

local currentPhaseId
local function renderPhase(data)
	local phase = data.Phase
	if not phase then
		return
	end
	currentPhaseId = phase.PhaseId
	open(phase.DisplayName)
	label(string.format(
		"Ate %d jogadores • %d ilhas • boss obrigatorio",
		phase.MaxPlayers,
		phase.BaseIslandCount
	), 54)
	local isLeader = data.IsLeader == true
	if isLeader then
		button("SELECIONAR E INICIAR", function()
			local result = invoke(phaseRequest, "Start", { PhaseId = currentPhaseId })
			if result then
				showToast(result.Message, result.Success)
			end
		end)
		button("CANCELAR INICIO", function()
			local result = invoke(phaseRequest, "Cancel", { PhaseId = currentPhaseId })
			if result then
				showToast(result.Message, result.Success)
			end
		end, Color3.fromRGB(96, 67, 58))
	else
		label("Somente o lider do grupo pode selecionar e iniciar a fase.", 62, true)
	end
end

phaseEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "Open" then
		renderPhase(data)
	elseif data.Action == "TeleportCountdown" then
		showToast(string.format("Entrando na %s em %d segundos...", data.PhaseId, data.Seconds), true)
	elseif data.Action == "TeleportCancelled" then
		showToast(data.Message or "Inicio cancelado.", false)
	end
end)

local currentWheelId
local function renderRoulette(snapshot)
	currentWheelId = snapshot.WheelId
	open(snapshot.DisplayName or "Roleta")
	label(string.format(
		"Custo: %d %s\nSeu saldo: %d moedas",
		snapshot.CostAmount or 0,
		snapshot.CostType or "Coins",
		snapshot.Coins or 0
	), 72)
	button("GIRAR", function()
		local result = invoke(rouletteRequest, "Spin", currentWheelId)
		if result and not result.Success then
			showToast(result.Message, false)
		end
	end, Color3.fromRGB(169, 113, 38))
end

rouletteEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "Open" then
		renderRoulette(data.Snapshot)
	elseif data.Action == "SpinResult" then
		local result = data.Result
		showToast(string.format(
			"Premio: %s x%d%s",
			tostring(result.RewardId),
			result.Amount or 1,
			result.ConvertedDuplicate and " (convertido em moedas)" or ""
		), true)
		task.delay(0.3, function()
			renderRoulette(data.Snapshot)
		end)
	end
end)

local function renderEquipment(snapshot)
	open("EQUIPAMENTOS")
	for _, category in ipairs({ "Swords", "Wings", "Companions", "Abilities" }) do
		label(string.upper(category), 34, true)
		local entries = snapshot[category] or {}
		local shown = 0
		for _, entry in ipairs(entries) do
			if entry.Owned then
				shown += 1
				local caption = entry.Equipped and ("✓ " .. entry.DisplayName) or entry.DisplayName
				button(caption, function()
					local result = invoke(equipmentRequest, "Set", category, entry.EquipmentId)
					if result then
						showToast(result.Message, result.Success)
						if result.Snapshot then
							renderEquipment(result.Snapshot)
						end
					end
				end, entry.Equipped and Color3.fromRGB(36, 101, 79) or Color3.fromRGB(47, 62, 72))
			end
		end
		if shown == 0 then
			label("Nenhum item desbloqueado.", 38)
		end
	end
end

equipmentEvent.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Action == "Open" and data.Snapshot then
		renderEquipment(data.Snapshot)
	end
end)

notificationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "ReturnToLobby" then
		if data.ReturnReason == "Victory" then
			showToast("Vitoria registrada. Bem-vindo de volta ao lobby!", true)
		elseif data.ReturnReason == "Defeat" then
			showToast("A expedicao terminou. Prepare-se e tente novamente.", false)
		else
			showToast("Voce retornou ao lobby.", true)
		end
	end
end)
