-- HUD-08 — boss completo: fases, ataques, arena e recompensa final
-- Depende da Task 29. Apenas apresenta estado autoritativo do servidor.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("DungeonUnifiedHUD", 20)

if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-08] HUD-01 não encontrado.")
	return
end

local VERSION = "CrystalCelestialBossCombatV2"
local UPDATE_INTERVAL = 0.15
local root = gui:WaitForChild("Root")

local COLORS = {
	Text = Color3.fromRGB(239, 247, 252),
	Muted = Color3.fromRGB(148, 177, 200),
	Cyan = Color3.fromRGB(108, 226, 255),
	CyanSoft = Color3.fromRGB(184, 243, 255),
	Gold = Color3.fromRGB(232, 195, 103),
	GoldSoft = Color3.fromRGB(255, 225, 142),
	Green = Color3.fromRGB(100, 236, 163),
	Orange = Color3.fromRGB(255, 183, 91),
	Red = Color3.fromRGB(255, 104, 117),
	Pink = Color3.fromRGB(255, 99, 176),
	Purple = Color3.fromRGB(198, 142, 255),
	Glass = Color3.fromRGB(13, 27, 42),
	GlassRaised = Color3.fromRGB(23, 48, 65),
}

local old = root:FindFirstChild("BossCombatDetails")
if old then old:Destroy() end

local panel = Instance.new("Frame")
panel.Name = "BossCombatDetails"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 136)
panel.Size = UDim2.fromOffset(700, 102)
panel.BackgroundColor3 = COLORS.Glass
panel.BackgroundTransparency = 0.065
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 36
panel.Parent = root
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Gold
panelStroke.Transparency = 0.22
panelStroke.Thickness = 1.3
panelStroke.Parent = panel

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(21, 57, 73)),
	ColorSequenceKeypoint.new(0.50, COLORS.Glass),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 24, 59)),
})
gradient.Rotation = 6
gradient.Parent = panel

local phaseStrip = Instance.new("Frame")
phaseStrip.Name = "PhaseStrip"
phaseStrip.Position = UDim2.fromOffset(12, 10)
phaseStrip.Size = UDim2.fromOffset(178, 82)
phaseStrip.BackgroundColor3 = Color3.fromRGB(18, 39, 54)
phaseStrip.BackgroundTransparency = 0.08
phaseStrip.BorderSizePixel = 0
phaseStrip.ZIndex = 37
phaseStrip.Parent = panel
Instance.new("UICorner", phaseStrip).CornerRadius = UDim.new(0, 12)

local phaseTitle = Instance.new("TextLabel")
phaseTitle.Position = UDim2.fromOffset(8, 5)
phaseTitle.Size = UDim2.new(1, -16, 0, 18)
phaseTitle.BackgroundTransparency = 1
phaseTitle.Text = "FASE DO BOSS"
phaseTitle.TextColor3 = COLORS.Muted
phaseTitle.Font = Enum.Font.GothamBold
phaseTitle.TextSize = 8
phaseTitle.ZIndex = 38
phaseTitle.Parent = phaseStrip

local pips = {}
for i = 1, 2 do
	local pip = Instance.new("Frame")
	pip.Name = "Phase" .. i
	pip.Position = UDim2.fromOffset(18 + (i - 1) * 76, 28)
	pip.Size = UDim2.fromOffset(64, 29)
	pip.BackgroundColor3 = Color3.fromRGB(31, 48, 60)
	pip.BackgroundTransparency = 0.04
	pip.BorderSizePixel = 0
	pip.ZIndex = 38
	pip.Parent = phaseStrip
	Instance.new("UICorner", pip).CornerRadius = UDim.new(0, 9)

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = COLORS.Muted
	stroke.Transparency = 0.48
	stroke.Parent = pip

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "F" .. i
	label.TextColor3 = COLORS.Muted
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 10
	label.ZIndex = 39
	label.Parent = pip
	pips[i] = pip
end

local phaseStatus = Instance.new("TextLabel")
phaseStatus.Position = UDim2.fromOffset(8, 62)
phaseStatus.Size = UDim2.new(1, -16, 0, 14)
phaseStatus.BackgroundTransparency = 1
phaseStatus.Text = "AGUARDANDO"
phaseStatus.TextColor3 = COLORS.CyanSoft
phaseStatus.Font = Enum.Font.GothamBold
phaseStatus.TextSize = 7
phaseStatus.ZIndex = 38
phaseStatus.Parent = phaseStrip

local attack = Instance.new("Frame")
attack.Name = "Attack"
attack.Position = UDim2.fromOffset(200, 10)
attack.Size = UDim2.new(1, -410, 0, 82)
attack.BackgroundColor3 = COLORS.GlassRaised
attack.BackgroundTransparency = 0.08
attack.BorderSizePixel = 0
attack.ZIndex = 37
attack.Parent = panel
Instance.new("UICorner", attack).CornerRadius = UDim.new(0, 12)

local attackStroke = Instance.new("UIStroke")
attackStroke.Color = COLORS.Cyan
attackStroke.Transparency = 0.27
attackStroke.Thickness = 1.2
attackStroke.Parent = attack

local attackGlyph = Instance.new("TextLabel")
attackGlyph.Position = UDim2.fromOffset(9, 8)
attackGlyph.Size = UDim2.fromOffset(46, 46)
attackGlyph.BackgroundTransparency = 1
attackGlyph.Text = "◆"
attackGlyph.TextColor3 = COLORS.CyanSoft
attackGlyph.Font = Enum.Font.GothamBlack
attackGlyph.TextSize = 24
attackGlyph.ZIndex = 38
attackGlyph.Parent = attack

local attackTitle = Instance.new("TextLabel")
attackTitle.Position = UDim2.fromOffset(57, 8)
attackTitle.Size = UDim2.new(1, -66, 0, 23)
attackTitle.BackgroundTransparency = 1
attackTitle.Text = "PREPARE-SE"
attackTitle.TextColor3 = COLORS.Text
attackTitle.Font = Enum.Font.GothamBlack
attackTitle.TextSize = 12
attackTitle.TextXAlignment = Enum.TextXAlignment.Left
attackTitle.TextTruncate = Enum.TextTruncate.AtEnd
attackTitle.ZIndex = 38
attackTitle.Parent = attack

local attackInstruction = Instance.new("TextLabel")
attackInstruction.Position = UDim2.fromOffset(57, 31)
attackInstruction.Size = UDim2.new(1, -66, 0, 22)
attackInstruction.BackgroundTransparency = 1
attackInstruction.Text = "Observe os telegraphs no chão."
attackInstruction.TextColor3 = COLORS.CyanSoft
attackInstruction.Font = Enum.Font.GothamBold
attackInstruction.TextSize = 9
attackInstruction.TextXAlignment = Enum.TextXAlignment.Left
attackInstruction.TextTruncate = Enum.TextTruncate.AtEnd
attackInstruction.ZIndex = 38
attackInstruction.Parent = attack

local attackTimer = Instance.new("TextLabel")
attackTimer.Position = UDim2.fromOffset(57, 54)
attackTimer.Size = UDim2.new(1, -66, 0, 18)
attackTimer.BackgroundTransparency = 1
attackTimer.Text = ""
attackTimer.TextColor3 = COLORS.Muted
attackTimer.Font = Enum.Font.GothamMedium
attackTimer.TextSize = 8
attackTimer.TextXAlignment = Enum.TextXAlignment.Left
attackTimer.ZIndex = 38
attackTimer.Parent = attack

local arena = Instance.new("Frame")
arena.Name = "ArenaStatus"
arena.AnchorPoint = Vector2.new(1, 0)
arena.Position = UDim2.new(1, -12, 0, 10)
arena.Size = UDim2.fromOffset(190, 82)
arena.BackgroundColor3 = Color3.fromRGB(26, 38, 55)
arena.BackgroundTransparency = 0.08
arena.BorderSizePixel = 0
arena.ZIndex = 37
arena.Parent = panel
Instance.new("UICorner", arena).CornerRadius = UDim.new(0, 12)

local arenaStroke = Instance.new("UIStroke")
arenaStroke.Color = COLORS.Purple
arenaStroke.Transparency = 0.35
arenaStroke.Parent = arena

local arenaTitle = Instance.new("TextLabel")
arenaTitle.Position = UDim2.fromOffset(8, 5)
arenaTitle.Size = UDim2.new(1, -16, 0, 18)
arenaTitle.BackgroundTransparency = 1
arenaTitle.Text = "ARENA"
arenaTitle.TextColor3 = COLORS.Purple
arenaTitle.Font = Enum.Font.GothamBold
arenaTitle.TextSize = 8
arenaTitle.ZIndex = 38
arenaTitle.Parent = arena

local arenaState = Instance.new("TextLabel")
arenaState.Position = UDim2.fromOffset(8, 24)
arenaState.Size = UDim2.new(1, -16, 0, 21)
arenaState.BackgroundTransparency = 1
arenaState.Text = "SELADA"
arenaState.TextColor3 = COLORS.Text
arenaState.Font = Enum.Font.GothamBlack
arenaState.TextSize = 10
arenaState.ZIndex = 38
arenaState.Parent = arena

local minionState = Instance.new("TextLabel")
minionState.Position = UDim2.fromOffset(8, 47)
minionState.Size = UDim2.new(1, -16, 0, 16)
minionState.BackgroundTransparency = 1
minionState.Text = "MINIONS 0"
minionState.TextColor3 = COLORS.Muted
minionState.Font = Enum.Font.GothamBold
minionState.TextSize = 8
minionState.ZIndex = 38
minionState.Parent = arena

local coverState = Instance.new("TextLabel")
coverState.Position = UDim2.fromOffset(8, 63)
coverState.Size = UDim2.new(1, -16, 0, 14)
coverState.BackgroundTransparency = 1
coverState.Text = "4 PILARES DE COBERTURA"
coverState.TextColor3 = COLORS.Muted
coverState.Font = Enum.Font.GothamMedium
coverState.TextSize = 7
coverState.ZIndex = 38
coverState.Parent = arena

local bigWarning = Instance.new("Frame")
bigWarning.Name = "BossDangerWarning"
bigWarning.AnchorPoint = Vector2.new(0.5, 0.5)
bigWarning.Position = UDim2.fromScale(0.5, 0.39)
bigWarning.Size = UDim2.fromOffset(530, 76)
bigWarning.BackgroundColor3 = Color3.fromRGB(49, 20, 31)
bigWarning.BackgroundTransparency = 0.10
bigWarning.BorderSizePixel = 0
bigWarning.Visible = false
bigWarning.ZIndex = 88
bigWarning.Parent = root
Instance.new("UICorner", bigWarning).CornerRadius = UDim.new(0, 16)

local warningStroke = Instance.new("UIStroke")
warningStroke.Color = COLORS.Red
warningStroke.Transparency = 0.08
warningStroke.Thickness = 1.7
warningStroke.Parent = bigWarning

local warningTitle = Instance.new("TextLabel")
warningTitle.Position = UDim2.fromOffset(12, 9)
warningTitle.Size = UDim2.new(1, -24, 0, 29)
warningTitle.BackgroundTransparency = 1
warningTitle.Text = ""
warningTitle.TextColor3 = COLORS.Red
warningTitle.Font = Enum.Font.GothamBlack
warningTitle.TextSize = 17
warningTitle.ZIndex = 89
warningTitle.Parent = bigWarning

local warningDetail = Instance.new("TextLabel")
warningDetail.Position = UDim2.fromOffset(12, 40)
warningDetail.Size = UDim2.new(1, -24, 0, 23)
warningDetail.BackgroundTransparency = 1
warningDetail.Text = ""
warningDetail.TextColor3 = Color3.fromRGB(242, 223, 229)
warningDetail.Font = Enum.Font.GothamBold
warningDetail.TextSize = 10
warningDetail.ZIndex = 89
warningDetail.Parent = bigWarning

local reward = Instance.new("Frame")
reward.Name = "BossRewardStatus"
reward.AnchorPoint = Vector2.new(0.5, 0.5)
reward.Position = UDim2.fromScale(0.5, 0.48)
reward.Size = UDim2.fromOffset(500, 118)
reward.BackgroundColor3 = Color3.fromRGB(40, 35, 17)
reward.BackgroundTransparency = 0.04
reward.BorderSizePixel = 0
reward.Visible = false
reward.ZIndex = 92
reward.Parent = root
Instance.new("UICorner", reward).CornerRadius = UDim.new(0, 18)

local rewardStroke = Instance.new("UIStroke")
rewardStroke.Color = COLORS.Gold
rewardStroke.Transparency = 0.08
rewardStroke.Thickness = 1.8
rewardStroke.Parent = reward

local rewardGlyph = Instance.new("TextLabel")
rewardGlyph.Position = UDim2.fromOffset(15, 16)
rewardGlyph.Size = UDim2.fromOffset(72, 72)
rewardGlyph.BackgroundTransparency = 1
rewardGlyph.Text = "✦"
rewardGlyph.TextColor3 = COLORS.GoldSoft
rewardGlyph.Font = Enum.Font.GothamBlack
rewardGlyph.TextSize = 42
rewardGlyph.ZIndex = 93
rewardGlyph.Parent = reward

local rewardTitle = Instance.new("TextLabel")
rewardTitle.Position = UDim2.fromOffset(88, 14)
rewardTitle.Size = UDim2.new(1, -102, 0, 30)
rewardTitle.BackgroundTransparency = 1
rewardTitle.Text = "BOSS DERROTADO"
rewardTitle.TextColor3 = COLORS.GoldSoft
rewardTitle.Font = Enum.Font.GothamBlack
rewardTitle.TextSize = 17
rewardTitle.TextXAlignment = Enum.TextXAlignment.Left
rewardTitle.ZIndex = 93
rewardTitle.Parent = reward

local rewardDetail = Instance.new("TextLabel")
rewardDetail.Position = UDim2.fromOffset(88, 46)
rewardDetail.Size = UDim2.new(1, -102, 0, 26)
rewardDetail.BackgroundTransparency = 1
rewardDetail.Text = ""
rewardDetail.TextColor3 = COLORS.Text
rewardDetail.Font = Enum.Font.GothamBold
rewardDetail.TextSize = 10
rewardDetail.TextXAlignment = Enum.TextXAlignment.Left
rewardDetail.ZIndex = 93
rewardDetail.Parent = reward

local rewardTimer = Instance.new("TextLabel")
rewardTimer.Position = UDim2.fromOffset(88, 74)
rewardTimer.Size = UDim2.new(1, -102, 0, 22)
rewardTimer.BackgroundTransparency = 1
rewardTimer.Text = ""
rewardTimer.TextColor3 = COLORS.Muted
rewardTimer.Font = Enum.Font.GothamMedium
rewardTimer.TextSize = 9
rewardTimer.TextXAlignment = Enum.TextXAlignment.Left
rewardTimer.ZIndex = 93
rewardTimer.Parent = reward

local intro = Instance.new("Frame")
intro.Name = "BossIntroduction"
intro.AnchorPoint = Vector2.new(0.5, 0.5)
intro.Position = UDim2.fromScale(0.5, 0.43)
intro.Size = UDim2.fromOffset(610, 146)
intro.BackgroundColor3 = Color3.fromRGB(18, 15, 28)
intro.BackgroundTransparency = 0.035
intro.BorderSizePixel = 0
intro.Visible = false
intro.ZIndex = 96
intro.Parent = root
Instance.new("UICorner", intro).CornerRadius = UDim.new(0, 20)
local introStroke = Instance.new("UIStroke")
introStroke.Color = COLORS.Gold
introStroke.Transparency = 0.05
introStroke.Thickness = 2
introStroke.Parent = intro

local introCaption = Instance.new("TextLabel")
introCaption.Position = UDim2.fromOffset(18, 14)
introCaption.Size = UDim2.new(1, -36, 0, 24)
introCaption.BackgroundTransparency = 1
introCaption.Text = "CHEFE FINAL"
introCaption.TextColor3 = COLORS.Red
introCaption.Font = Enum.Font.GothamBlack
introCaption.TextSize = 13
introCaption.ZIndex = 97
introCaption.Parent = intro

local introTitle = Instance.new("TextLabel")
introTitle.Position = UDim2.fromOffset(18, 39)
introTitle.Size = UDim2.new(1, -36, 0, 48)
introTitle.BackgroundTransparency = 1
introTitle.Text = "REI SLIME COLOSSAL"
introTitle.TextColor3 = COLORS.GoldSoft
introTitle.Font = Enum.Font.GothamBlack
introTitle.TextSize = 28
introTitle.ZIndex = 97
introTitle.Parent = intro

local introDetail = Instance.new("TextLabel")
introDetail.Position = UDim2.fromOffset(18, 91)
introDetail.Size = UDim2.new(1, -36, 0, 23)
introDetail.BackgroundTransparency = 1
introDetail.Text = "FASE 1 • aprenda os ataques • aos 50% ele desperta"
introDetail.TextColor3 = COLORS.Text
introDetail.Font = Enum.Font.GothamBold
introDetail.TextSize = 11
introDetail.ZIndex = 97
introDetail.Parent = intro

local introTimer = Instance.new("TextLabel")
introTimer.Position = UDim2.fromOffset(18, 116)
introTimer.Size = UDim2.new(1, -36, 0, 18)
introTimer.BackgroundTransparency = 1
introTimer.Text = ""
introTimer.TextColor3 = COLORS.CyanSoft
introTimer.Font = Enum.Font.GothamBold
introTimer.TextSize = 9
introTimer.ZIndex = 97
introTimer.Parent = intro

local ATTACKS = {
	Idle = {
		Title = "OBSERVE O BOSS",
		Instruction = "Ataque e prepare-se para o próximo movimento.",
		Glyph = "◆",
		Color = COLORS.Cyan,
	},
	BasicSlam = {
		Title = "GOLPE DO REI",
		Instruction = "AFASTE-SE do círculo curto ao redor do Boss.",
		Glyph = "◆",
		Color = COLORS.Orange,
		Danger = true,
	},
	LeapSlam = {
		Title = "SALTO ESMAGADOR",
		Instruction = "SAIA DO CÍRCULO marcado no chão.",
		Glyph = "↓",
		Color = COLORS.Red,
		Danger = true,
	},
	GroundPulse = {
		Title = "PULSO DE SOLO",
		Instruction = "AFASTE-SE do boss antes do impacto.",
		Glyph = "◎",
		Color = COLORS.Orange,
		Danger = true,
	},
	Shockwave = {
		Title = "ONDA DE CHOQUE",
		Instruction = "O centro possui uma zona segura curta — reposicione-se.",
		Glyph = "◉",
		Color = COLORS.Purple,
		Danger = true,
	},
	SummonSlimes = {
		Title = "REFORÇOS INVOCADOS",
		Instruction = "Elimine os slimes para reduzir a pressão da arena.",
		Glyph = "♟",
		Color = COLORS.Cyan,
	},
	SkyfallVolley = {
		Title = "CHUVA CELESTIAL",
		Instruction = "SAIA DAS MARCAS vermelhas antes da queda.",
		Glyph = "✦",
		Color = COLORS.Red,
		Danger = true,
	},
	CrossSweep = {
		Title = "VARREDURA CRUZADA",
		Instruction = "FUJA DAS FAIXAS em cruz marcadas no piso.",
		Glyph = "✕",
		Color = COLORS.Pink,
		Danger = true,
	},
	ArenaCollapse = {
		Title = "COLAPSO DA ARENA",
		Instruction = "VÁ PARA O CENTRO VERDE imediatamente.",
		Glyph = "◉",
		Color = COLORS.Red,
		Danger = true,
	},
	PhaseTransition = {
		Title = "TRANSIÇÃO DE FASE",
		Instruction = "O boss está INVULNERÁVEL. Reposicione-se.",
		Glyph = "▲",
		Color = COLORS.Gold,
		Danger = false,
	},
}

local lastAttack = ""
local attackPulseSerial = 0
local phasePulseSerial = 0

local function serverTime()
	return workspace:GetServerTimeNow()
end

local responsiveScales = {}
local function fitObject(object, baseSize)
	if not object or not object:IsA("GuiObject") then
		return
	end
	local scale = responsiveScales[object]
	if not scale or not scale.Parent then
		scale = object:FindFirstChild("ResponsiveScale")
		if not scale or not scale:IsA("UIScale") then
			scale = Instance.new("UIScale")
			scale.Name = "ResponsiveScale"
			scale.Parent = object
		end
		responsiveScales[object] = scale
	end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(
		math.min(
			1,
			(viewport.X - 18) / baseSize.X,
			(viewport.Y - 18) / baseSize.Y
		),
		0.48,
		1
	)
end

local function updateResponsive()
	fitObject(panel, Vector2.new(700, 102))
	fitObject(bigWarning, Vector2.new(530, 76))
	fitObject(reward, Vector2.new(500, 118))
	-- Existe depois da Tarefa 8. Find por nome mantém esta tarefa compatível
	-- com a branch antes ou depois da aplicação do patch do Boss.
	local intro = root:FindFirstChild("BossIntroduction")
	if intro and intro:IsA("GuiObject") then
		fitObject(intro, Vector2.new(610, 146))
	end
end

local viewportConnection
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

local function bossVisible()
	local state = tostring(workspace:GetAttribute("DungeonBossState") or "Unavailable")
	local director = tostring(workspace:GetAttribute("DungeonBossDirectorState") or "")
	return state == "Active"
		or director == "PhaseTransition"
		or string.sub(director, 1, 16) == "SignatureAttack:"
end

local function bossModel()
	for _, model in ipairs(CollectionService:GetTagged("DungeonBoss")) do
		if model:IsA("Model") and model.Parent then return model end
	end
	return nil
end

local function bossInvulnerable()
	local boss = bossModel()
	return boss and boss:GetAttribute("Invulnerable") == true
		or workspace:GetAttribute("DungeonBossPhaseTransitioning") == true
end

local function countBossMinions()
	local count = 0
	for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if model:IsA("Model")
			and model.Parent
			and model:GetAttribute("ObjectiveId") == "BossMinions"
		then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then count += 1 end
		end
	end
	return count
end

local function updatePips(phase)
	for i, pip in ipairs(pips) do
		local stroke = pip:FindFirstChild("Stroke")
		local label = pip:FindFirstChildOfClass("TextLabel")
		if i < phase then
			pip.BackgroundColor3 = Color3.fromRGB(42, 67, 64)
			if label then label.TextColor3 = COLORS.Green end
			if stroke then stroke.Color = COLORS.Green; stroke.Transparency = 0.18 end
		elseif i == phase then
			local color = phase == 1 and COLORS.Cyan or COLORS.Red
			pip.BackgroundColor3 = phase == 2 and Color3.fromRGB(66, 25, 37) or Color3.fromRGB(37, 61, 70)
			if label then label.TextColor3 = color end
			if stroke then stroke.Color = color; stroke.Transparency = 0.02; stroke.Thickness = 1.7 end
		else
			pip.BackgroundColor3 = Color3.fromRGB(31, 42, 54)
			if label then label.TextColor3 = COLORS.Muted end
			if stroke then stroke.Color = COLORS.Muted; stroke.Transparency = 0.58; stroke.Thickness = 1 end
		end
	end
end

local function flashAttack(definition)
	attackPulseSerial += 1
	local serial = attackPulseSerial
	attack.BackgroundTransparency = 0.01
	TweenService:Create(attack, TweenInfo.new(0.34), { BackgroundTransparency = 0.08 }):Play()

	if definition.Danger then
		bigWarning.Visible = true
		bigWarning.BackgroundTransparency = 0.10
		warningTitle.TextTransparency = 0
		warningDetail.TextTransparency = 0
		warningTitle.Text = definition.Title
		warningDetail.Text = definition.Instruction
		warningTitle.TextColor3 = definition.Color
		warningStroke.Color = definition.Color
		task.delay(1.15, function()
			if attackPulseSerial ~= serial then return end
			local tween = TweenService:Create(bigWarning, TweenInfo.new(0.20), {
				BackgroundTransparency = 1,
			})
			local textTween = TweenService:Create(warningTitle, TweenInfo.new(0.20), { TextTransparency = 1 })
			local detailTween = TweenService:Create(warningDetail, TweenInfo.new(0.20), { TextTransparency = 1 })
			tween:Play()
			textTween:Play()
			detailTween:Play()
			tween.Completed:Wait()
			if attackPulseSerial == serial then bigWarning.Visible = false end
		end)
	end
end

local function phaseTransitionVisual(phase, remaining)
	phasePulseSerial += 1
	local color = COLORS.Red
	phaseStatus.Text = remaining > 0
		and string.format("TRANSIÇÃO • %ds", remaining)
		or "TRANSIÇÃO"
	phaseStatus.TextColor3 = color
	panelStroke.Color = color
	attackTitle.Text = "50% DE VIDA • O REI DESPERTOU"
	attackInstruction.Text = "BOSS INVULNERÁVEL — novos ataques estão chegando."
	attackGlyph.Text = "▲"
	attackGlyph.TextColor3 = color
	attackStroke.Color = color
end

local function refreshAttack()
	local attackName = tostring(workspace:GetAttribute("DungeonBossAttack") or "Idle")
	local definition = ATTACKS[attackName] or ATTACKS.Idle
	local endsAt = tonumber(workspace:GetAttribute("DungeonBossAttackEndsAt")) or 0
	local remaining = math.max(0, endsAt - serverTime())

	attackGlyph.Text = definition.Glyph
	attackGlyph.TextColor3 = definition.Color
	attackStroke.Color = definition.Color
	attackTitle.Text = definition.Title
	attackInstruction.Text = definition.Instruction

	if attackName == "Idle" then
		attackTimer.Text = "Observe os telegraphs da arena."
	elseif remaining > 0 then
		attackTimer.Text = string.format("IMPACTO / FIM EM %.1fs", remaining)
	else
		attackTimer.Text = "EXECUTANDO"
	end

	if attackName ~= lastAttack then
		lastAttack = attackName
		if attackName ~= "Idle" and attackName ~= "PhaseTransition" then
			flashAttack(definition)
		end
	end
end

local function refreshPhase()
	local phase = math.clamp(math.floor(tonumber(workspace:GetAttribute("DungeonBossPhase")) or 1), 1, 2)
	updatePips(phase)

	local transitioning = workspace:GetAttribute("DungeonBossPhaseTransitioning") == true
	local transitionEnds = tonumber(workspace:GetAttribute("DungeonBossPhaseTransitionEndsAt")) or 0
	local remaining = math.max(0, math.ceil(transitionEnds - serverTime()))

	if transitioning then
		local transitionPhase = math.clamp(
			math.floor(tonumber(workspace:GetAttribute("DungeonBossPhaseTransitionPhase")) or phase),
			1,
			2
		)
		phaseTransitionVisual(transitionPhase, remaining)
	elseif bossInvulnerable() then
		phaseStatus.Text = string.format("FASE %d • INVULNERÁVEL", phase)
		phaseStatus.TextColor3 = COLORS.Gold
		panelStroke.Color = COLORS.Gold
	else
		phaseStatus.Text = string.format("FASE %d • COMBATE", phase)
		phaseStatus.TextColor3 = phase == 2 and COLORS.Red or COLORS.Cyan
		panelStroke.Color = phase == 2 and COLORS.Red or COLORS.Cyan
	end
end

local function refreshIntroduction()
	local state = tostring(workspace:GetAttribute("DungeonBossState") or "Unavailable")
	local activating = state == "Activating"
	intro.Visible = activating
	if not activating then
		return
	end
	local name = tostring(workspace:GetAttribute("DungeonBossDisplayName") or "Rei Slime Colossal")
	local endsAt = tonumber(workspace:GetAttribute("DungeonBossActivationEndsAt")) or 0
	local remaining = math.max(0, endsAt - serverTime())
	introTitle.Text = string.upper(name)
	introTimer.Text = remaining > 0
		and string.format("BATALHA COMEÇA EM %.1fs", remaining)
		or "BATALHA COMEÇANDO..."
end

local function refreshArena()
	local directorReady = workspace:GetAttribute("DungeonBossDirectorArenaReady") == true
	local minions = countBossMinions()
	minionState.Text = string.format("MINIONS %d", minions)
	minionState.TextColor3 = minions > 0 and COLORS.Orange or COLORS.Muted

	if not directorReady then
		arenaState.Text = "PREPARANDO"
		arenaState.TextColor3 = COLORS.Muted
	else
		local attackName = tostring(workspace:GetAttribute("DungeonBossAttack") or "Idle")
		if attackName == "ArenaCollapse" then
			arenaState.Text = "COLAPSANDO"
			arenaState.TextColor3 = COLORS.Red
			arenaStroke.Color = COLORS.Red
		elseif attackName == "CrossSweep" then
			arenaState.Text = "VARREDURA"
			arenaState.TextColor3 = COLORS.Pink
			arenaStroke.Color = COLORS.Pink
		elseif attackName == "SkyfallVolley" then
			arenaState.Text = "SKYFALL"
			arenaState.TextColor3 = COLORS.Red
			arenaStroke.Color = COLORS.Red
		else
			arenaState.Text = "SELADA"
			arenaState.TextColor3 = COLORS.Purple
			arenaStroke.Color = COLORS.Purple
		end
	end

	-- O servidor cria e publica o número de coberturas. Evita
	-- workspace:GetDescendants() ~12x/segundo durante toda a luta.
	local covers = math.max(
		0,
		math.floor(tonumber(workspace:GetAttribute("DungeonBossArenaCoverCount")) or 0)
	)
	coverState.Text = covers > 0 and string.format("%d PILARES DE COBERTURA", covers) or "SEM COBERTURA EXTRA"
end

local function refreshReward()
	local victoryPending = workspace:GetAttribute("DungeonBossVictoryPending") == true
	local directorState = tostring(workspace:GetAttribute("DungeonBossDirectorState") or "")
	local collecting = directorState == "BossRewardCollecting" or victoryPending
	reward.Visible = collecting
	if not collecting then return end

	panel.Visible = false
	bigWarning.Visible = false

	local amount = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonBossRewardCoinsPerPlayer")) or 0))
	local drops = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonBossRewardDropCount")) or 0))
	local untilAt = tonumber(workspace:GetAttribute("DungeonBossRewardCollectingUntil")
		or workspace:GetAttribute("DungeonBossVictoryFinalizeAt")) or 0
	local remaining = math.max(0, untilAt - serverTime())

	rewardTitle.Text = "REI SLIME COLOSSAL DERROTADO"
	if amount > 0 then
		rewardDetail.Text = string.format("✦ Essência pessoal do Boss • +%d moedas", amount)
	else
		rewardDetail.Text = "✦ Recompensa pessoal sendo atraída até você"
	end
	rewardTimer.Text = remaining > 0
		and string.format("%d recompensa(s) • vitória finaliza em %.1fs", drops, remaining)
		or "Finalizando vitória..."
end

local function refreshVisibility()
	local visible = bossVisible()
	local victoryPending = workspace:GetAttribute("DungeonBossVictoryPending") == true
	panel.Visible = visible and not victoryPending
	if not visible and not victoryPending then
		bigWarning.Visible = false
	end
end

local function refresh()
	refreshVisibility()
	refreshIntroduction()
	refreshReward()
	if not panel.Visible then return end
	refreshPhase()
	refreshAttack()
	refreshArena()

	player:SetAttribute("DungeonHUDBossAttack", tostring(workspace:GetAttribute("DungeonBossAttack") or "Idle"))
	player:SetAttribute("DungeonHUDBossPhase", tonumber(workspace:GetAttribute("DungeonBossPhase")) or 1)
	player:SetAttribute("DungeonHUDBossInvulnerable", bossInvulnerable())
end

for _, attribute in ipairs({
	"DungeonBossState",
	"DungeonBossHealth",
	"DungeonBossMaxHealth",
	"DungeonBossPhase",
	"DungeonBossAttack",
	"DungeonBossAttackEndsAt",
	"DungeonBossPhaseTransitioning",
	"DungeonBossPhaseTransitionEndsAt",
	"DungeonBossPhaseTransitionPhase",
	"DungeonBossDirectorState",
	"DungeonBossDirectorStateEndsAt",
	"DungeonBossDirectorArenaReady",
	"DungeonBossArenaCoverCount",
	"DungeonBossVictoryPending",
	"DungeonBossVictoryFinalizeAt",
	"DungeonBossRewardDropCount",
	"DungeonBossRewardCoinsPerPlayer",
	"DungeonBossRewardCollectingUntil",
}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	if panel.Visible or reward.Visible or bigWarning.Visible
		or tostring(workspace:GetAttribute("DungeonBossState") or "") == "Activating"
	then
		refresh()
	end
end)

gui:SetAttribute("BossCombatVersion", VERSION)
player:SetAttribute("DungeonHUDBossReady", true)
player:SetAttribute("DungeonHUDBossVersion", VERSION)
workspace:SetAttribute("DungeonHUDBossReady", true)
workspace:SetAttribute("DungeonHUDBossPolicy", "TwoPhaseBossIntroRewardV2")
workspace:SetAttribute("DungeonHUDBossPerformancePolicy", "PublishedCoverCountVisibleOnlyRefreshV2")

refresh()
