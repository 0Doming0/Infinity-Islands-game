-- HUD-09 — resultado da run, salvamento e retorno ao Lobby
-- Usa o contrato real de Notifications/DungeonResult.
-- Não salva dados nem teleporta diretamente no cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local resultEvent = RemoteRegistry.Get("Notifications", "DungeonResult", "RemoteEvent")

local HUD_NAME = "DungeonUnifiedHUD"
local VERSION = "CrystalCelestialResultsReplayV2"
local UPDATE_INTERVAL = 0.20

local COLORS = {
	Text = Color3.fromRGB(240, 247, 252),
	Muted = Color3.fromRGB(147, 176, 199),
	Cyan = Color3.fromRGB(108, 226, 255),
	CyanSoft = Color3.fromRGB(183, 243, 255),
	Gold = Color3.fromRGB(233, 196, 103),
	GoldSoft = Color3.fromRGB(255, 225, 143),
	Green = Color3.fromRGB(99, 236, 161),
	Orange = Color3.fromRGB(255, 184, 91),
	Red = Color3.fromRGB(255, 104, 117),
	Purple = Color3.fromRGB(198, 142, 255),
	Glass = Color3.fromRGB(12, 25, 40),
	GlassRaised = Color3.fromRGB(22, 47, 64),
	Backdrop = Color3.fromRGB(4, 8, 15),
}

local gui = playerGui:WaitForChild(HUD_NAME, 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-09] DungeonUnifiedHUD não encontrado.")
	return
end

local root = gui:WaitForChild("Root")
local old = root:FindFirstChild("ResultOverlay")
if old then old:Destroy() end

local overlay = Instance.new("Frame")
overlay.Name = "ResultOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = COLORS.Backdrop
overlay.BackgroundTransparency = 0.18
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.ZIndex = 300
overlay.Parent = root

local backdropGradient = Instance.new("UIGradient")
backdropGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 15, 29)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(9, 15, 28)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(23, 12, 31)),
})
backdropGradient.Rotation = 10
backdropGradient.Parent = overlay

local card = Instance.new("Frame")
card.Name = "ResultCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.50)
card.Size = UDim2.fromOffset(760, 548)
card.BackgroundColor3 = COLORS.Glass
card.BackgroundTransparency = 0.025
card.BorderSizePixel = 0
card.ZIndex = 301
card.Parent = overlay
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 22)
local cardScale = Instance.new("UIScale")
cardScale.Name = "ResponsiveScale"
cardScale.Scale = 1
cardScale.Parent = card

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = COLORS.Gold
cardStroke.Transparency = 0.10
cardStroke.Thickness = 1.7
cardStroke.Parent = card

local topGlow = Instance.new("Frame")
topGlow.Size = UDim2.new(1, -30, 0, 3)
topGlow.Position = UDim2.fromOffset(15, 10)
topGlow.BackgroundColor3 = COLORS.Gold
topGlow.BackgroundTransparency = 0.20
topGlow.BorderSizePixel = 0
topGlow.ZIndex = 302
topGlow.Parent = card
Instance.new("UICorner", topGlow).CornerRadius = UDim.new(1, 0)

local resultGlyph = Instance.new("TextLabel")
resultGlyph.AnchorPoint = Vector2.new(0.5, 0)
resultGlyph.Position = UDim2.new(0.5, 0, 0, 28)
resultGlyph.Size = UDim2.fromOffset(86, 64)
resultGlyph.BackgroundTransparency = 1
resultGlyph.Text = "✦"
resultGlyph.TextColor3 = COLORS.GoldSoft
resultGlyph.Font = Enum.Font.GothamBlack
resultGlyph.TextSize = 45
resultGlyph.ZIndex = 302
resultGlyph.Parent = card

local resultTitle = Instance.new("TextLabel")
resultTitle.Position = UDim2.fromOffset(26, 91)
resultTitle.Size = UDim2.new(1, -52, 0, 43)
resultTitle.BackgroundTransparency = 1
resultTitle.Text = "RESULTADO DA EXPEDIÇÃO"
resultTitle.TextColor3 = COLORS.GoldSoft
resultTitle.Font = Enum.Font.GothamBlack
resultTitle.TextSize = 25
resultTitle.ZIndex = 302
resultTitle.Parent = card

local phaseName = Instance.new("TextLabel")
phaseName.Position = UDim2.fromOffset(26, 133)
phaseName.Size = UDim2.new(1, -52, 0, 27)
phaseName.BackgroundTransparency = 1
phaseName.Text = "Carregando resultado..."
phaseName.TextColor3 = COLORS.CyanSoft
phaseName.Font = Enum.Font.GothamBold
phaseName.TextSize = 12
phaseName.ZIndex = 302
phaseName.Parent = card

local stats = Instance.new("Frame")
stats.Name = "Stats"
stats.Position = UDim2.fromOffset(26, 176)
stats.Size = UDim2.new(1, -52, 0, 142)
stats.BackgroundTransparency = 1
stats.ZIndex = 302
stats.Parent = card

local function statCard(name, column, row, labelText, glyph)
	local width = 220
	local height = 62
	local x = (column - 1) * 234
	local y = (row - 1) * 74

	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = COLORS.GlassRaised
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.ZIndex = 303
	frame.Parent = stats
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 13)

	local s = Instance.new("UIStroke")
	s.Color = COLORS.Cyan
	s.Transparency = 0.52
	s.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Position = UDim2.fromOffset(8, 7)
	icon.Size = UDim2.fromOffset(40, 40)
	icon.BackgroundTransparency = 1
	icon.Text = glyph
	icon.TextColor3 = COLORS.GoldSoft
	icon.Font = Enum.Font.GothamBlack
	icon.TextSize = 18
	icon.ZIndex = 304
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(49, 7)
	label.Size = UDim2.new(1, -58, 0, 19)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = COLORS.Muted
	label.Font = Enum.Font.GothamBold
	label.TextSize = 8
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 304
	label.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.fromOffset(49, 25)
	value.Size = UDim2.new(1, -58, 0, 28)
	value.BackgroundTransparency = 1
	value.Text = "--"
	value.TextColor3 = COLORS.Text
	value.Font = Enum.Font.GothamBlack
	value.TextSize = 14
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.ZIndex = 304
	value.Parent = frame
	return value, s
end

local elapsedValue = statCard("Elapsed", 1, 1, "TEMPO DA RUN", "◷")
local rewardValue = statCard("Reward", 2, 1, "MOEDAS DA VITÓRIA", "●")
local balanceValue = statCard("Balance", 3, 1, "SALDO FINAL", "◆")
local bestValue = statCard("Best", 1, 2, "MELHOR TEMPO", "★")
local completionsValue = statCard("Completions", 2, 2, "CONCLUSÕES", "✓")
local progressValue = statCard("Progress", 3, 2, "PROGRESSO DA EXPEDIÇÃO", "▲")

local savePanel = Instance.new("Frame")
savePanel.Name = "SaveStatus"
savePanel.Position = UDim2.fromOffset(26, 333)
savePanel.Size = UDim2.new(1, -52, 0, 72)
savePanel.BackgroundColor3 = Color3.fromRGB(18, 39, 53)
savePanel.BackgroundTransparency = 0.07
savePanel.BorderSizePixel = 0
savePanel.ZIndex = 302
savePanel.Parent = card
Instance.new("UICorner", savePanel).CornerRadius = UDim.new(0, 14)

local saveStroke = Instance.new("UIStroke")
saveStroke.Color = COLORS.Cyan
saveStroke.Transparency = 0.28
saveStroke.Thickness = 1.2
saveStroke.Parent = savePanel

local saveGlyph = Instance.new("TextLabel")
saveGlyph.Position = UDim2.fromOffset(11, 8)
saveGlyph.Size = UDim2.fromOffset(48, 48)
saveGlyph.BackgroundTransparency = 1
saveGlyph.Text = "◇"
saveGlyph.TextColor3 = COLORS.Cyan
saveGlyph.Font = Enum.Font.GothamBlack
saveGlyph.TextSize = 25
saveGlyph.ZIndex = 303
saveGlyph.Parent = savePanel

local saveTitle = Instance.new("TextLabel")
saveTitle.Position = UDim2.fromOffset(61, 7)
saveTitle.Size = UDim2.new(1, -74, 0, 25)
saveTitle.BackgroundTransparency = 1
saveTitle.Text = "CONFIRMANDO RESULTADO..."
saveTitle.TextColor3 = COLORS.CyanSoft
saveTitle.Font = Enum.Font.GothamBold
saveTitle.TextSize = 11
saveTitle.TextXAlignment = Enum.TextXAlignment.Left
saveTitle.ZIndex = 303
saveTitle.Parent = savePanel

local saveDetail = Instance.new("TextLabel")
saveDetail.Position = UDim2.fromOffset(61, 32)
saveDetail.Size = UDim2.new(1, -74, 0, 28)
saveDetail.BackgroundTransparency = 1
saveDetail.Text = "Não feche o jogo enquanto o resultado estiver sendo salvo."
saveDetail.TextColor3 = COLORS.Muted
saveDetail.Font = Enum.Font.GothamMedium
saveDetail.TextSize = 9
saveDetail.TextXAlignment = Enum.TextXAlignment.Left
saveDetail.TextWrapped = true
saveDetail.ZIndex = 303
saveDetail.Parent = savePanel

local returnInfo = Instance.new("TextLabel")
returnInfo.Position = UDim2.fromOffset(26, 421)
returnInfo.Size = UDim2.new(1, -52, 0, 24)
returnInfo.BackgroundTransparency = 1
returnInfo.Text = "Retorno ao Lobby sendo preparado..."
returnInfo.TextColor3 = COLORS.Muted
returnInfo.Font = Enum.Font.GothamMedium
returnInfo.TextSize = 10
returnInfo.ZIndex = 302
returnInfo.Parent = card

local replayButton = Instance.new("TextButton")
replayButton.Name = "ReplayButton"
replayButton.AnchorPoint = Vector2.new(0, 1)
replayButton.Position = UDim2.new(0, 26, 1, -25)
replayButton.Size = UDim2.fromOffset(444, 68)
replayButton.BackgroundColor3 = Color3.fromRGB(35, 94, 74)
replayButton.BackgroundTransparency = 0.01
replayButton.BorderSizePixel = 0
replayButton.Text = "JOGAR NOVAMENTE"
replayButton.TextColor3 = COLORS.Green
replayButton.Font = Enum.Font.GothamBlack
replayButton.TextSize = 14
replayButton.AutoButtonColor = true
replayButton.ZIndex = 303
replayButton.Parent = card
Instance.new("UICorner", replayButton).CornerRadius = UDim.new(0, 15)
local replayStroke = Instance.new("UIStroke")
replayStroke.Color = COLORS.Gold
replayStroke.Transparency = 0.12
replayStroke.Thickness = 1.4
replayStroke.Parent = replayButton

local returnButton = Instance.new("TextButton")
returnButton.Name = "LobbyButton"
returnButton.AnchorPoint = Vector2.new(1, 1)
returnButton.Position = UDim2.new(1, -26, 1, -25)
returnButton.Size = UDim2.fromOffset(238, 68)
returnButton.BackgroundColor3 = Color3.fromRGB(29, 71, 83)
returnButton.BackgroundTransparency = 0.02
returnButton.BorderSizePixel = 0
returnButton.Text = "LOBBY"
returnButton.TextColor3 = COLORS.CyanSoft
returnButton.Font = Enum.Font.GothamBlack
returnButton.TextSize = 14
returnButton.AutoButtonColor = true
returnButton.ZIndex = 303
returnButton.Parent = card
Instance.new("UICorner", returnButton).CornerRadius = UDim.new(0, 15)

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = COLORS.Gold
buttonStroke.Transparency = 0.22
buttonStroke.Thickness = 1.3
buttonStroke.Parent = returnButton

local currentResult
local returnSnapshot
local shown = false
local returnRequested = false
local replayRequested = false
local lastRequestAt = 0

local viewportConnection
local function updateResponsive()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	cardScale.Scale = math.clamp(
		math.min(
			1,
			(viewport.X - 20) / 760,
			(viewport.Y - 20) / 548
		),
		0.38,
		1
	)
	player:SetAttribute("DungeonHUDResultScale", cardScale.Scale)
end

local function bindViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)
	end
	updateResponsive()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
bindViewport()

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function formatTime(seconds)
	if typeof(seconds) ~= "number" then return "--:--" end
	seconds = math.max(0, seconds)
	local whole = math.floor(seconds + 0.5)
	local minutes = math.floor(whole / 60)
	local secs = whole % 60
	if minutes >= 60 then
		local hours = math.floor(minutes / 60)
		minutes %= 60
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%02d:%02d", minutes, secs)
end

local function resultIsVictory()
	return currentResult and currentResult.Result == "Victory"
end

local function setOtherHudHidden(hidden)
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("GuiObject") and child ~= overlay then
			if hidden then
				if child:GetAttribute("HUD09PreviousVisible") == nil then
					child:SetAttribute("HUD09PreviousVisible", child.Visible)
				end
				child.Visible = false
			else
				local previous = child:GetAttribute("HUD09PreviousVisible")
				if previous ~= nil then
					child.Visible = previous == true
					child:SetAttribute("HUD09PreviousVisible", nil)
				end
			end
		end
	end
end

local function show()
	if shown then return end
	shown = true
	setOtherHudHidden(true)
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	card.Position = UDim2.fromScale(0.5, 0.54)
	card.BackgroundTransparency = 1
	TweenService:Create(overlay, TweenInfo.new(0.32), { BackgroundTransparency = 0.18 }):Play()
	TweenService:Create(
		card,
		TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.50), BackgroundTransparency = 0.025 }
	):Play()
end

local function updateHeader()
	if not currentResult then
		resultTitle.Text = "RESULTADO DA EXPEDIÇÃO"
		phaseName.Text = "Aguardando dados do servidor..."
		resultGlyph.Text = "◇"
		resultGlyph.TextColor3 = COLORS.Cyan
		cardStroke.Color = COLORS.Cyan
		return
	end

	local victory = resultIsVictory()
	local result = tostring(currentResult.Result or "")
	if victory then
		resultTitle.Text = "VITÓRIA!"
		resultGlyph.Text = "✦"
		resultGlyph.TextColor3 = COLORS.GoldSoft
		resultTitle.TextColor3 = COLORS.GoldSoft
		cardStroke.Color = COLORS.Gold
	elseif result == "Defeat" then
		resultTitle.Text = "EXPEDIÇÃO ENCERRADA"
		resultGlyph.Text = "◆"
		resultGlyph.TextColor3 = COLORS.Red
		resultTitle.TextColor3 = COLORS.Red
		cardStroke.Color = COLORS.Red
	elseif result == "Disconnected" then
		resultTitle.Text = "EQUIPE DESCONECTADA"
		resultGlyph.Text = "◇"
		resultGlyph.TextColor3 = COLORS.Orange
		resultTitle.TextColor3 = COLORS.Orange
		cardStroke.Color = COLORS.Orange
	else
		resultTitle.Text = "EXPEDIÇÃO FINALIZADA"
		resultGlyph.Text = "◆"
		resultGlyph.TextColor3 = COLORS.Cyan
		resultTitle.TextColor3 = COLORS.CyanSoft
		cardStroke.Color = COLORS.Cyan
	end

	local name = tostring(currentResult.PhaseName or currentResult.PhaseId or "Dungeon")
	phaseName.Text = victory
		and ("Mundo concluído • " .. name)
		or ("Você chegou até • " .. name)
end

local FAILURE_LABELS = {
	AllParticipantsEliminated = "A equipe inteira foi eliminada.",
	AllParticipantsDisconnected = "A equipe saiu da expedição.",
	Water = "Você caiu na água antes de concluir a run.",
	SlimeMelee = "Um ataque corpo a corpo encerrou sua tentativa.",
	SlimeProjectile = "Um projétil inimigo encerrou sua tentativa.",
	BossGroundPulse = "O Pulso de Solo do Boss encerrou a tentativa.",
	BossLeapSlam = "O Salto Esmagador do Boss encerrou a tentativa.",
	BossShockwave = "A Onda de Choque do Boss encerrou a tentativa.",
	BossBasicSlam = "O golpe do Boss encerrou sua tentativa.",
}

local function defeatSummary()
	if not currentResult or resultIsVictory() then
		return nil
	end
	local objectiveTitle = tostring(currentResult.EndObjectiveTitle or "")
	local progress = math.max(0, math.floor(tonumber(currentResult.EndObjectiveProgress) or 0))
	local target = math.max(0, math.floor(tonumber(currentResult.EndObjectiveTarget) or 0))
	local source = tostring(currentResult.LastDamageSource or currentResult.DefeatReason or "")
	local cause = FAILURE_LABELS[source]
		or FAILURE_LABELS[tostring(currentResult.DefeatReason or "")]
		or "A expedição terminou, mas seu progresso anterior continua seguro."
	if objectiveTitle ~= "" then
		if target > 0 then
			return string.format(
				"%s • Último objetivo: %s (%d/%d)",
				cause,
				objectiveTitle,
				progress,
				target
			)
		end
		return cause .. " • Último objetivo: " .. objectiveTitle
	end
	return cause
end

local function updateStats()
	if not currentResult then return end

	elapsedValue.Text = formatTime(tonumber(currentResult.ElapsedSeconds))
	rewardValue.Text = string.format("+%d", math.max(0, math.floor(tonumber(currentResult.RewardCoins) or 0)))
	balanceValue.Text = tostring(math.max(0, math.floor(tonumber(currentResult.Balance) or 0)))
	completionsValue.Text = tostring(math.max(0, math.floor(tonumber(currentResult.Completions) or 0)))
	bestValue.Text = currentResult.BestTime and formatTime(tonumber(currentResult.BestTime)) or "--:--"

	local globalIndex = math.max(0, math.floor(tonumber(
		player:GetAttribute("CurrentGlobalIslandIndex")
			or workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or 0
	) or 0))
	local committedRound = math.max(0, math.floor(tonumber(
		player:GetAttribute("DungeonCheckpointCommittedRound")
			or workspace:GetAttribute("DungeonCheckpointCommittedRound")
			or workspace:GetAttribute("DungeonLastCommittedRewardRound")
			or 0
	) or 0))

	if resultIsVictory() then
		progressValue.Text = "3/3 ROUNDS • BOSS"
	elseif tonumber(currentResult.CommittedRound) and tonumber(currentResult.CommittedRound) > 0 then
		progressValue.Text = string.format(
			"ROUND %d CONCLUÍDO",
			math.clamp(math.floor(tonumber(currentResult.CommittedRound) or 0), 1, 3)
		)
	elseif tonumber(currentResult.EndGlobalIslandIndex) and tonumber(currentResult.EndGlobalIslandIndex) > 0 then
		progressValue.Text = string.format(
			"OBJETIVO %d/12",
			math.clamp(math.floor(tonumber(currentResult.EndGlobalIslandIndex) or 0), 1, 12)
		)
	elseif committedRound > 0 then
		progressValue.Text = string.format("ROUND %d SALVO", committedRound)
	elseif globalIndex > 0 then
		progressValue.Text = string.format("OBJETIVO %d/12", math.clamp(globalIndex, 1, 12))
	else
		progressValue.Text = "RUN ENCERRADA"
	end
end

local function updateSave()
	if not currentResult then
		saveGlyph.Text = "◇"
		saveGlyph.TextColor3 = COLORS.Cyan
		saveTitle.Text = "CONFIRMANDO RESULTADO..."
		saveTitle.TextColor3 = COLORS.CyanSoft
		saveDetail.Text = "Aguardando o resumo final do servidor."
		saveStroke.Color = COLORS.Cyan
		return
	end

	local saved = currentResult.Saved == true
	if saved then
		saveGlyph.Text = "✓"
		saveGlyph.TextColor3 = COLORS.Green
		saveTitle.Text = "PROGRESSO SALVO"
		saveTitle.TextColor3 = COLORS.Green
		saveDetail.Text = currentResult.AlreadyProcessed == true
			and "Este resultado já havia sido processado com segurança."
			or "Recompensas, conclusão e melhor tempo foram confirmados."
		local failure = defeatSummary()
		if failure then
			saveDetail.Text = failure
		end
		saveStroke.Color = COLORS.Green
	else
		local errorText = tostring(currentResult.SaveError or workspace:GetAttribute("DungeonResultSaveError") or "")
		saveGlyph.Text = "↻"
		saveGlyph.TextColor3 = COLORS.Orange
		saveTitle.Text = "SALVAMENTO AINDA PENDENTE"
		saveTitle.TextColor3 = COLORS.Orange
		if errorText ~= "" and errorText ~= "nil" then
			saveDetail.Text = "O servidor está tentando novamente. " .. errorText
		else
			saveDetail.Text = "O servidor está tentando confirmar seu progresso antes do retorno."
		end
		saveStroke.Color = COLORS.Orange
	end
end

local function manualAvailableAt()
	if returnSnapshot and tonumber(returnSnapshot.ManualReturnAt) then
		return tonumber(returnSnapshot.ManualReturnAt)
	end
	return currentResult and tonumber(currentResult.ManualReturnAt) or 0
end

local function automaticReturnAt()
	if returnSnapshot and tonumber(returnSnapshot.ReturnAt) then
		return tonumber(returnSnapshot.ReturnAt)
	end
	return currentResult and tonumber(currentResult.ReturnAt) or 0
end

local function updateReturn()
	if not currentResult then
		returnInfo.Text = "Retorno ao Lobby sendo preparado..."
		returnButton.Active = false
		returnButton.AutoButtonColor = false
		returnButton.Text = "AGUARDANDO RESULTADO"
		returnButton.BackgroundColor3 = Color3.fromRGB(39, 51, 60)
		buttonStroke.Color = COLORS.Muted
		replayButton.Active = false
		replayButton.AutoButtonColor = false
		replayButton.Text = "AGUARDANDO RESULTADO"
		replayButton.BackgroundColor3 = Color3.fromRGB(39, 51, 60)
		replayStroke.Color = COLORS.Muted
		return
	end

	local now = serverTime()
	local manualAt = manualAvailableAt()
	local returnAt = automaticReturnAt()
	local manualRemaining = math.max(0, manualAt - now)
	local autoRemaining = math.max(0, returnAt - now)
	local state = tostring((returnSnapshot and returnSnapshot.State)
		or player:GetAttribute("DungeonReturnState")
		or "Pending")

	if state == "Teleporting" then
		local replaying = returnSnapshot and returnSnapshot.Reason == "ReplayRequest"
		returnInfo.Text = replaying and "Abrindo uma nova expedição..." or "Teleportando para o Lobby..."
		returnButton.Text = replaying and "AGUARDE" or "RETORNANDO..."
		returnButton.Active = false
		returnButton.AutoButtonColor = false
		returnButton.BackgroundColor3 = Color3.fromRGB(39, 67, 70)
		buttonStroke.Color = COLORS.Green
		replayButton.Text = replaying and "INICIANDO NOVA RUN..." or "AGUARDE"
		replayButton.Active = false
		replayButton.AutoButtonColor = false
		replayButton.BackgroundColor3 = Color3.fromRGB(39, 67, 70)
		replayStroke.Color = COLORS.Green
		return
	elseif state == "RetryScheduled" then
		returnInfo.Text = "O teleporte falhou temporariamente. Nova tentativa automática foi agendada."
		returnButton.Text = "NOVA TENTATIVA EM ANDAMENTO"
		returnButton.Active = false
		returnButton.AutoButtonColor = false
		returnButton.BackgroundColor3 = Color3.fromRGB(73, 54, 32)
		buttonStroke.Color = COLORS.Orange
		return
	elseif state == "Failed" then
		returnInfo.Text = "O retorno automático falhou. Você pode tentar novamente."
		returnButton.Text = "TENTAR RETORNAR AO LOBBY"
		returnButton.Active = true
		returnButton.AutoButtonColor = true
		returnButton.BackgroundColor3 = Color3.fromRGB(76, 48, 29)
		buttonStroke.Color = COLORS.Orange
		return
	elseif state == "StudioPreview" then
		returnInfo.Text = "Roblox Studio não executa o teleporte real desta tela."
		returnButton.Text = "TELEPORTE INDISPONÍVEL NO STUDIO"
		returnButton.Active = false
		returnButton.AutoButtonColor = false
		returnButton.BackgroundColor3 = Color3.fromRGB(45, 48, 57)
		buttonStroke.Color = COLORS.Muted
		return
	elseif state == "ConfigurationError" then
		returnInfo.Text = "LobbyPlaceId não está configurado corretamente."
		returnButton.Text = "RETORNO INDISPONÍVEL"
		returnButton.Active = false
		returnButton.AutoButtonColor = false
		returnButton.BackgroundColor3 = Color3.fromRGB(67, 35, 40)
		buttonStroke.Color = COLORS.Red
		return
	end

	if autoRemaining > 0 then
		returnInfo.Text = string.format("Retorno automático ao Lobby em %ds.", math.ceil(autoRemaining))
	else
		returnInfo.Text = "Retorno automático sendo iniciado..."
	end

	if manualRemaining > 0 then
		returnButton.Text = string.format("AGUARDE O SALVAMENTO • %ds", math.ceil(manualRemaining))
		returnButton.Active = false
		returnButton.AutoButtonColor = false
		returnButton.BackgroundColor3 = Color3.fromRGB(45, 55, 63)
		buttonStroke.Color = COLORS.Muted
		replayButton.Text = string.format("SALVANDO • %ds", math.ceil(manualRemaining))
		replayButton.Active = false
		replayButton.AutoButtonColor = false
		replayButton.BackgroundColor3 = Color3.fromRGB(45, 55, 63)
		replayStroke.Color = COLORS.Muted
	else
		returnButton.Text = returnRequested and "RETORNANDO..." or "LOBBY"
		returnButton.Active = not returnRequested
		returnButton.AutoButtonColor = not returnRequested
		returnButton.BackgroundColor3 = Color3.fromRGB(29, 71, 83)
		buttonStroke.Color = currentResult.Saved == true and COLORS.Green or COLORS.Gold
		local replayAvailable = currentResult.ReplayAvailable ~= false
		replayButton.Text = replayRequested and "INICIANDO..." or "JOGAR NOVAMENTE"
		replayButton.Active = replayAvailable and not replayRequested and not returnRequested
		replayButton.AutoButtonColor = replayButton.Active
		replayButton.BackgroundColor3 = replayButton.Active
			and Color3.fromRGB(35, 94, 74)
			or Color3.fromRGB(45, 55, 63)
		replayStroke.Color = replayButton.Active and COLORS.Gold or COLORS.Muted
	end
end

local function applyResult(payload)
	currentResult = currentResult or {}
	for key, value in pairs(payload) do
		if key ~= "Action" then
			currentResult[key] = value
		end
	end
	show()
	updateHeader()
	updateStats()
	updateSave()
	updateReturn()
	player:SetAttribute("DungeonHUDResultReceived", true)
	player:SetAttribute("DungeonHUDResultType", tostring(currentResult.Result or ""))
end

local function applyReturnSnapshot(payload)
	returnSnapshot = returnSnapshot or {}
	for key, value in pairs(payload) do
		if key ~= "Action" then
			returnSnapshot[key] = value
		end
	end
	if payload.State ~= "Pending" then
		returnRequested = false
	end
	updateReturn()
end

resultEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local action = tostring(payload.Action or "")

	if action == "Result" then
		applyResult(payload)
	elseif action == "ResultSaveUpdated" then
		currentResult = currentResult or {}
		currentResult.Saved = payload.Saved == true
		currentResult.SaveError = payload.SaveError
		currentResult.RewardCoins = payload.RewardCoins
		currentResult.Balance = payload.Balance
		currentResult.Completions = payload.Completions
		currentResult.BestTime = payload.BestTime
		currentResult.ElapsedSeconds = payload.ElapsedSeconds
		show()
		updateStats()
		updateSave()
		updateReturn()
	elseif action == "ReturnStatus" then
		applyReturnSnapshot(payload)
	elseif action == "ReturnBlocked" then
		returnRequested = false
		if tonumber(payload.AvailableAt) then
			currentResult = currentResult or {}
			currentResult.ManualReturnAt = tonumber(payload.AvailableAt)
		end
		saveDetail.Text = "O resultado ainda está sendo salvo. O retorno será liberado assim que for seguro."
		saveStroke.Color = COLORS.Orange
		updateReturn()
	elseif action == "ReturnRetryScheduled" then
		returnRequested = false
		returnSnapshot = returnSnapshot or {}
		returnSnapshot.State = "RetryScheduled"
		returnInfo.Text = string.format(
			"Nova tentativa de retorno em %ds • tentativa %d.",
			math.ceil(tonumber(payload.DelaySeconds) or 0),
			math.floor(tonumber(payload.Attempt) or 0)
		)
		updateReturn()
	elseif action == "ReplayBlocked" then
		replayRequested = false
		if tonumber(payload.AvailableAt) then
			currentResult = currentResult or {}
			currentResult.ManualReturnAt = tonumber(payload.AvailableAt)
		end
		saveDetail.Text = "A nova run será liberada assim que o resultado atual estiver seguro."
		saveStroke.Color = COLORS.Orange
		updateReturn()
	elseif action == "ReplayFailed" then
		replayRequested = false
		returnInfo.Text = "Não foi possível abrir a nova run. Você pode tentar novamente ou voltar ao Lobby."
		replayStroke.Color = COLORS.Orange
		updateReturn()
	end
end)

replayButton.Activated:Connect(function()
	if not currentResult or not replayButton.Active then return end
	if os.clock() - lastRequestAt < 1.3 then return end
	lastRequestAt = os.clock()
	replayRequested = true
	returnRequested = false
	updateReturn()
	resultEvent:FireServer({
		Action = "ReplayDungeon",
	})
	task.delay(3, function()
		if replayRequested then
			replayRequested = false
			updateReturn()
		end
	end)
end)

returnButton.Activated:Connect(function()
	if not currentResult or not returnButton.Active then return end
	if os.clock() - lastRequestAt < 1.3 then return end
	lastRequestAt = os.clock()
	returnRequested = true
	replayRequested = false
	updateReturn()
	resultEvent:FireServer({
		Action = "ReturnToLobby",
	})
	task.delay(2.5, function()
		if returnRequested then
			returnRequested = false
			updateReturn()
		end
	end)
end)

workspace:GetAttributeChangedSignal("DungeonPhaseState"):Connect(function()
	local state = tostring(workspace:GetAttribute("DungeonPhaseState") or "")
	if (state == "Victory" or state == "Defeat") and not shown then
		show()
		updateHeader()
		updateSave()
		updateReturn()
		resultEvent:FireServer({ Action = "GetResult" })
	end
end)

player:GetAttributeChangedSignal("DungeonResultShown"):Connect(function()
	if player:GetAttribute("DungeonResultShown") == true and not currentResult then
		show()
		resultEvent:FireServer({ Action = "GetResult" })
	end
end)

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	if shown then
		updateReturn()
		updateSave()
	end
end)

gui:SetAttribute("ResultReturnVersion", VERSION)
player:SetAttribute("DungeonHUDResultReady", true)
player:SetAttribute("DungeonHUDResultVersion", VERSION)
workspace:SetAttribute("DungeonHUDResultReady", true)
workspace:SetAttribute("DungeonHUDResultPolicy", "SavedResultFastReplayV2")
workspace:SetAttribute("DungeonHUDResultPerformancePolicy", "ResponsiveResult5HzV2")

if player:GetAttribute("DungeonResultShown") == true
	or workspace:GetAttribute("DungeonPhaseState") == "Victory"
	or workspace:GetAttribute("DungeonPhaseState") == "Defeat"
then
	show()
	resultEvent:FireServer({ Action = "GetResult" })
end
