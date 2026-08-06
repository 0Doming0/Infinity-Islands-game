local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local event = RemoteRegistry.Get("Notifications", "DungeonResult", "RemoteEvent")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonResultUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 500
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(5, 7, 12)
shade.BackgroundTransparency = 0.12
shade.BorderSizePixel = 0
shade.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "ResultPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(560, 500)
panel.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
panel.BorderSizePixel = 0
panel.Parent = shade
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 22)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(99, 124, 165)
panelStroke.Transparency = 0.45
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 7)
accent.BackgroundColor3 = Color3.fromRGB(99, 233, 166)
accent.BorderSizePixel = 0
accent.Parent = panel
Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 22)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(28, 30)
title.Size = UDim2.new(1, -56, 0, 48)
title.BackgroundTransparency = 1
title.Text = "RESULTADO"
title.TextColor3 = Color3.fromRGB(242, 247, 252)
title.Font = Enum.Font.GothamBlack
title.TextSize = 31
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name = "Phase"
phaseLabel.Position = UDim2.fromOffset(30, 78)
phaseLabel.Size = UDim2.new(1, -60, 0, 28)
phaseLabel.BackgroundTransparency = 1
phaseLabel.Text = "FASE"
phaseLabel.TextColor3 = Color3.fromRGB(173, 188, 212)
phaseLabel.Font = Enum.Font.GothamMedium
phaseLabel.TextSize = 15
phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
phaseLabel.Parent = panel

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(28, 116)
divider.Size = UDim2.new(1, -56, 0, 1)
divider.BackgroundColor3 = Color3.fromRGB(74, 89, 116)
divider.BackgroundTransparency = 0.35
divider.BorderSizePixel = 0
divider.Parent = panel

local stats = Instance.new("Frame")
stats.Name = "Stats"
stats.Position = UDim2.fromOffset(28, 132)
stats.Size = UDim2.new(1, -56, 0, 145)
stats.BackgroundTransparency = 1
stats.Parent = panel

local statGrid = Instance.new("UIGridLayout")
statGrid.CellPadding = UDim2.fromOffset(10, 10)
statGrid.CellSize = UDim2.new(0.5, -5, 0, 67)
statGrid.FillDirectionMaxCells = 2
statGrid.SortOrder = Enum.SortOrder.LayoutOrder
statGrid.Parent = stats

local function createStat(name, labelText, valueText, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = layoutOrder
	card.BackgroundColor3 = Color3.fromRGB(23, 30, 44)
	card.BackgroundTransparency = 0.04
	card.BorderSizePixel = 0
	card.Parent = stats
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(13, 8)
	label.Size = UDim2.new(1, -26, 0, 19)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(150, 166, 191)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = card
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.fromOffset(13, 27)
	value.Size = UDim2.new(1, -26, 0, 31)
	value.BackgroundTransparency = 1
	value.Text = valueText
	value.TextColor3 = Color3.fromRGB(239, 243, 250)
	value.Font = Enum.Font.GothamBold
	value.TextSize = 18
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Parent = card
	return value
end

local rewardValue = createStat("Reward", "RECOMPENSA", "+0 MOEDAS", 1)
local balanceValue = createStat("Balance", "SALDO", "0", 2)
local timeValue = createStat("Time", "TEMPO", "00:00", 3)
local recordValue = createStat("Record", "MELHOR TEMPO", "--:--", 4)

local saveBox = Instance.new("Frame")
saveBox.Name = "SaveStatus"
saveBox.Position = UDim2.fromOffset(28, 292)
saveBox.Size = UDim2.new(1, -56, 0, 62)
saveBox.BackgroundColor3 = Color3.fromRGB(25, 43, 38)
saveBox.BorderSizePixel = 0
saveBox.Parent = panel
Instance.new("UICorner", saveBox).CornerRadius = UDim.new(0, 12)

local saveTitle = Instance.new("TextLabel")
saveTitle.Position = UDim2.fromOffset(14, 8)
saveTitle.Size = UDim2.new(1, -28, 0, 21)
saveTitle.BackgroundTransparency = 1
saveTitle.Text = "PROGRESSO SALVO"
saveTitle.TextColor3 = Color3.fromRGB(112, 235, 170)
saveTitle.Font = Enum.Font.GothamBold
saveTitle.TextSize = 13
saveTitle.TextXAlignment = Enum.TextXAlignment.Left
saveTitle.Parent = saveBox

local saveDetails = Instance.new("TextLabel")
saveDetails.Position = UDim2.fromOffset(14, 29)
saveDetails.Size = UDim2.new(1, -28, 0, 25)
saveDetails.BackgroundTransparency = 1
saveDetails.Text = "As recompensas foram confirmadas."
saveDetails.TextColor3 = Color3.fromRGB(191, 204, 218)
saveDetails.Font = Enum.Font.Gotham
saveDetails.TextSize = 12
saveDetails.TextXAlignment = Enum.TextXAlignment.Left
saveDetails.TextWrapped = true
saveDetails.Parent = saveBox

local returnStatus = Instance.new("TextLabel")
returnStatus.Name = "ReturnStatus"
returnStatus.Position = UDim2.fromOffset(30, 368)
returnStatus.Size = UDim2.new(1, -60, 0, 24)
returnStatus.BackgroundTransparency = 1
returnStatus.Text = "RETORNANDO AO LOBBY..."
returnStatus.TextColor3 = Color3.fromRGB(187, 199, 219)
returnStatus.Font = Enum.Font.GothamMedium
returnStatus.TextSize = 13
returnStatus.TextXAlignment = Enum.TextXAlignment.Center
returnStatus.Parent = panel

local returnButton = Instance.new("TextButton")
returnButton.Name = "ReturnButton"
returnButton.Position = UDim2.fromOffset(28, 402)
returnButton.Size = UDim2.new(1, -56, 0, 58)
returnButton.BackgroundColor3 = Color3.fromRGB(67, 127, 232)
returnButton.BorderSizePixel = 0
returnButton.Text = "VOLTAR AO LOBBY AGORA"
returnButton.TextColor3 = Color3.new(1, 1, 1)
returnButton.Font = Enum.Font.GothamBold
returnButton.TextSize = 16
returnButton.AutoButtonColor = true
returnButton.Parent = panel
Instance.new("UICorner", returnButton).CornerRadius = UDim.new(0, 13)

local footer = Instance.new("TextLabel")
footer.Position = UDim2.fromOffset(30, 466)
footer.Size = UDim2.new(1, -60, 0, 22)
footer.BackgroundTransparency = 1
footer.Text = ""
footer.TextColor3 = Color3.fromRGB(129, 143, 166)
footer.Font = Enum.Font.Gotham
footer.TextSize = 10
footer.TextXAlignment = Enum.TextXAlignment.Center
footer.TextTruncate = Enum.TextTruncate.AtEnd
footer.Parent = panel

local currentResult
local currentReturnState = "Pending"
local returnRequestPending = false
local retryAt

local function formatTime(seconds)
	local value = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%02d:%02d", math.floor(value / 60), value % 60)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(
		math.min((viewport.X - 24) / 560, (viewport.Y - 24) / 500),
		0.62,
		1
	)
end

local function setSaveState(saved, errorMessage)
	if saved then
		saveBox.BackgroundColor3 = Color3.fromRGB(25, 43, 38)
		saveTitle.Text = "PROGRESSO SALVO"
		saveTitle.TextColor3 = Color3.fromRGB(112, 235, 170)
		saveDetails.Text = "As recompensas e a conclusão foram confirmadas."
	else
		saveBox.BackgroundColor3 = Color3.fromRGB(53, 39, 26)
		saveTitle.Text = "SALVAMENTO NÃO CONFIRMADO"
		saveTitle.TextColor3 = Color3.fromRGB(255, 194, 101)
		saveDetails.Text = "O servidor tentará novamente antes do retorno. "
			.. tostring(errorMessage or "")
	end
end

local function suppressGameplayHud()
	for _, name in ipairs({
		"DungeonUnifiedHUD",
		"DungeonSpectator",
		"DungeonBossHUD",
		"SurvivalUI",
		"DownedUI",
		"DeathScreen",
	}) do
		local screenGui = playerGui:FindFirstChild(name)
		if screenGui and screenGui:IsA("ScreenGui") and screenGui ~= gui then
			screenGui.Enabled = false
		end
	end
end

local function setReturnButton(enabled, text, color)
	returnButton.Active = enabled
	returnButton.AutoButtonColor = enabled
	returnButton.Text = text
	returnButton.BackgroundColor3 = color or (enabled
		and Color3.fromRGB(67, 127, 232)
		or Color3.fromRGB(61, 71, 91))
end

local function applyReturnState(data)
	currentReturnState = tostring(data.State or currentReturnState)
	local attempts = math.max(0, math.floor(tonumber(data.Attempts) or 0))
	if currentReturnState == "Teleporting" then
		returnRequestPending = true
		returnStatus.Text = "CONECTANDO AO LOBBY..."
		setReturnButton(false, "CONECTANDO...", Color3.fromRGB(61, 71, 91))
	elseif currentReturnState == "RetryScheduled" then
		returnRequestPending = false
		returnStatus.Text = string.format("FALHA NO RETORNO — NOVA TENTATIVA %d", attempts + 1)
		setReturnButton(false, "TENTANDO NOVAMENTE...", Color3.fromRGB(118, 83, 45))
	elseif currentReturnState == "Failed" then
		returnRequestPending = false
		returnStatus.Text = "NÃO FOI POSSÍVEL VOLTAR AUTOMATICAMENTE"
		setReturnButton(true, "TENTAR VOLTAR NOVAMENTE", Color3.fromRGB(198, 116, 57))
	elseif currentReturnState == "StudioPreview" then
		returnRequestPending = false
		returnStatus.Text = "TELEPORTE INDISPONÍVEL NO PLAYTEST DO STUDIO"
		setReturnButton(false, "TESTE NO JOGO PUBLICADO", Color3.fromRGB(61, 71, 91))
	elseif currentReturnState == "ConfigurationError" then
		returnRequestPending = false
		returnStatus.Text = "LOBBYPLACEID NÃO CONFIGURADO"
		setReturnButton(false, "CONFIGURE O LOBBY", Color3.fromRGB(121, 65, 65))
	elseif currentReturnState == "Left" then
		setReturnButton(false, "SAINDO...", Color3.fromRGB(61, 71, 91))
	else
		returnRequestPending = false
		local manualReturnAt = tonumber(data.ManualReturnAt)
			or (currentResult and tonumber(currentResult.ManualReturnAt))
			or workspace:GetServerTimeNow()
		local resultSaved = data.ResultSaved == true
			or (currentResult and currentResult.Saved == true)
		if resultSaved or workspace:GetServerTimeNow() >= manualReturnAt then
			setReturnButton(true, "VOLTAR AO LOBBY AGORA")
		else
			setReturnButton(false, "SALVANDO RESULTADO...", Color3.fromRGB(118, 83, 45))
		end
	end
	footer.Text = data.LastError and tostring(data.LastError) or ""
end

local function showResult(data)
	currentResult = table.clone(data)
	local victory = data.Result == "Victory"
	gui.Enabled = true
	suppressGameplayHud()
	accent.BackgroundColor3 = victory
		and Color3.fromRGB(99, 233, 166)
		or Color3.fromRGB(239, 103, 108)
	title.Text = victory and "FASE CONCLUÍDA!" or "EXPEDIÇÃO ENCERRADA"
	title.TextColor3 = victory
		and Color3.fromRGB(125, 245, 185)
		or Color3.fromRGB(255, 128, 132)
	local phaseName = string.upper(tostring(data.PhaseName or data.PhaseId or "DUNGEON"))
	local completions = math.max(0, math.floor(tonumber(data.Completions) or 0))
	phaseLabel.Text = completions > 0
		and string.format("%s  •  %d CONCLUSÃO(ÕES)", phaseName, completions)
		or phaseName
	local rewardCoins = math.max(0, math.floor(tonumber(data.RewardCoins) or 0))
	rewardValue.Text = rewardCoins > 0 and string.format("+%d MOEDAS", rewardCoins) or "SEM BÔNUS"
	balanceValue.Text = tostring(math.max(0, math.floor(tonumber(data.Balance) or 0)))
	timeValue.Text = formatTime(data.ElapsedSeconds)
	recordValue.Text = data.BestTime and formatTime(data.BestTime) or "--:--"
	if victory and data.EligibleForBossReward ~= true then
		rewardValue.Text = "NÃO ELEGÍVEL"
	end
	setSaveState(data.Saved == true, data.SaveError)
	currentReturnState = "Pending"
	returnRequestPending = false
	local manualReturnAt = tonumber(data.ManualReturnAt) or workspace:GetServerTimeNow()
	if data.Saved == true or workspace:GetServerTimeNow() >= manualReturnAt then
		setReturnButton(true, "VOLTAR AO LOBBY AGORA")
	else
		setReturnButton(false, "SALVANDO RESULTADO...", Color3.fromRGB(118, 83, 45))
	end
	returnStatus.Text = "PREPARANDO RETORNO..."
	footer.Text = data.ResultId and ("RESULTADO: " .. tostring(data.ResultId)) or ""
	panel.Position = UDim2.fromScale(0.5, 0.54)
	panel.BackgroundTransparency = 1
	TweenService:Create(
		panel,
		TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 0 }
	):Play()
end

returnButton.Activated:Connect(function()
	if not currentResult or returnRequestPending then
		return
	end
	returnRequestPending = true
	setReturnButton(false, "SOLICITANDO RETORNO...", Color3.fromRGB(61, 71, 91))
	returnStatus.Text = "SOLICITANDO CONEXÃO AO LOBBY..."
	event:FireServer({ Action = "ReturnToLobby" })
	task.delay(8, function()
		if currentResult and returnRequestPending and currentReturnState ~= "Teleporting" then
			returnRequestPending = false
			setReturnButton(true, "TENTAR VOLTAR NOVAMENTE", Color3.fromRGB(198, 116, 57))
		end
	end)
end)

event.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Action == "Result" then
		showResult(data)
	elseif data.Action == "ResultSaveUpdated" and currentResult then
		currentResult.Saved = data.Saved == true
		currentResult.SaveError = data.SaveError
		if currentResult.Saved then
			currentResult.ManualReturnAt = workspace:GetServerTimeNow()
			if currentReturnState == "Pending" then
				setReturnButton(true, "VOLTAR AO LOBBY AGORA")
			end
		end
		currentResult.RewardCoins = data.RewardCoins or currentResult.RewardCoins
		currentResult.Balance = data.Balance or currentResult.Balance
		currentResult.Completions = data.Completions or currentResult.Completions
		currentResult.BestTime = data.BestTime or currentResult.BestTime
		local phaseName = string.upper(tostring(currentResult.PhaseName or currentResult.PhaseId or "DUNGEON"))
		local completions = math.max(0, math.floor(tonumber(currentResult.Completions) or 0))
		phaseLabel.Text = completions > 0
			and string.format("%s  •  %d CONCLUSÃO(ÕES)", phaseName, completions)
			or phaseName
		rewardValue.Text = math.max(0, math.floor(tonumber(currentResult.RewardCoins) or 0)) > 0
			and string.format("+%d MOEDAS", math.floor(tonumber(currentResult.RewardCoins) or 0))
			or rewardValue.Text
		balanceValue.Text = tostring(math.max(0, math.floor(tonumber(currentResult.Balance) or 0)))
		recordValue.Text = currentResult.BestTime and formatTime(currentResult.BestTime) or "--:--"
		setSaveState(currentResult.Saved, currentResult.SaveError)
	elseif data.Action == "ReturnBlocked" and currentResult then
		currentResult.ManualReturnAt = tonumber(data.AvailableAt) or currentResult.ManualReturnAt
		returnRequestPending = false
		returnStatus.Text = "AGUARDANDO CONFIRMAÇÃO DO SALVAMENTO..."
		setReturnButton(false, "SALVANDO RESULTADO...", Color3.fromRGB(118, 83, 45))
	elseif data.Action == "ReturnStatus" and currentResult then
		if data.ManualReturnAt then
			currentResult.ManualReturnAt = data.ManualReturnAt
		end
		if data.ResultSaved == true then
			currentResult.Saved = true
		end
		applyReturnState(data)
	elseif data.Action == "ReturnRetryScheduled" and currentResult then
		retryAt = workspace:GetServerTimeNow() + math.max(0, tonumber(data.DelaySeconds) or 0)
		returnStatus.Text = string.format(
			"NOVA TENTATIVA EM %d SEGUNDOS",
			math.ceil(math.max(0, retryAt - workspace:GetServerTimeNow()))
		)
	end
end)

RunService.RenderStepped:Connect(function()
	if not gui.Enabled or not currentResult then
		return
	end
	if currentReturnState == "Pending" then
		local now = workspace:GetServerTimeNow()
		local manualReturnAt = tonumber(currentResult.ManualReturnAt) or now
		if not returnRequestPending and (currentResult.Saved == true or now >= manualReturnAt) then
			setReturnButton(true, "VOLTAR AO LOBBY AGORA")
		elseif not returnRequestPending then
			setReturnButton(false, "SALVANDO RESULTADO...", Color3.fromRGB(118, 83, 45))
		end
		local returnAt = tonumber(currentResult.ReturnAt)
		if not returnAt then
			returnAt = workspace:GetServerTimeNow() + math.max(0, tonumber(currentResult.ReturnDelay) or 0)
			currentResult.ReturnAt = returnAt
		end
		local remaining = math.max(0, math.ceil(returnAt - workspace:GetServerTimeNow()))
		returnStatus.Text = remaining > 0
			and string.format("RETORNO AUTOMÁTICO EM %d SEGUNDOS", remaining)
			or "INICIANDO RETORNO AO LOBBY..."
	elseif currentReturnState == "RetryScheduled" and retryAt then
		local remaining = math.max(0, math.ceil(retryAt - workspace:GetServerTimeNow()))
		returnStatus.Text = remaining > 0
			and string.format("NOVA TENTATIVA EM %d SEGUNDOS", remaining)
			or "TENTANDO NOVAMENTE..."
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
event:FireServer({ Action = "GetResult" })
updateScale()
