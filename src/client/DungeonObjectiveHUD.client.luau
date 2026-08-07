-- HUD-04 — objetivos, ondas, pacing e mecânicas especiais
-- Camada contextual sobre HUD-01. Consome contratos das Tasks 26 e 27.
-- Não altera progressão; somente apresenta estado replicado pelo servidor.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "CrystalCelestialObjectivesV1"
local HUD_NAME = "DungeonUnifiedHUD"
local UPDATE_INTERVAL = 0.10

local gui = playerGui:WaitForChild(HUD_NAME, 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-04] HUD-01 não encontrado.")
	return
end

local root = gui:WaitForChild("Root")
local objectivePanel = root:WaitForChild("Objective")
local objectiveTitle = objectivePanel:WaitForChild("Title")
local objectiveDetail = objectivePanel:WaitForChild("Detail")
local objectiveProgress = objectivePanel:WaitForChild("ProgressText")

local existing = root:FindFirstChild("ObjectiveContext")
if existing then existing:Destroy() end

local context = Instance.new("Frame")
context.Name = "ObjectiveContext"
context.AnchorPoint = Vector2.new(0.5, 0)
context.Position = UDim2.new(0.5, 0, 0, 136)
context.Size = UDim2.fromOffset(690, 58)
context.BackgroundColor3 = Color3.fromRGB(13, 27, 42)
context.BackgroundTransparency = 0.11
context.BorderSizePixel = 0
context.Visible = false
context.ZIndex = 30
context.Parent = root
Instance.new("UICorner", context).CornerRadius = UDim.new(0, 15)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(225, 190, 101)
stroke.Transparency = 0.30
stroke.Thickness = 1.2
stroke.Parent = context

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 57, 75)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB(13, 27, 42)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 26, 57)),
})
gradient.Rotation = 8
gradient.Parent = context

local icon = Instance.new("TextLabel")
icon.Name = "MechanicIcon"
icon.Position = UDim2.fromOffset(11, 6)
icon.Size = UDim2.fromOffset(42, 42)
icon.BackgroundColor3 = Color3.fromRGB(26, 56, 71)
icon.BackgroundTransparency = 0.08
icon.BorderSizePixel = 0
icon.Text = "◆"
icon.TextColor3 = Color3.fromRGB(159, 235, 255)
icon.Font = Enum.Font.GothamBlack
icon.TextSize = 20
icon.ZIndex = 31
icon.Parent = context
Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 10)
local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(221, 186, 104)
iconStroke.Transparency = 0.25
iconStroke.Parent = icon

local mechanicTitle = Instance.new("TextLabel")
mechanicTitle.Name = "MechanicTitle"
mechanicTitle.Position = UDim2.fromOffset(64, 5)
mechanicTitle.Size = UDim2.new(1, -280, 0, 22)
mechanicTitle.BackgroundTransparency = 1
mechanicTitle.Text = ""
mechanicTitle.TextColor3 = Color3.fromRGB(240, 246, 252)
mechanicTitle.Font = Enum.Font.GothamBold
mechanicTitle.TextSize = 12
mechanicTitle.TextXAlignment = Enum.TextXAlignment.Left
mechanicTitle.TextTruncate = Enum.TextTruncate.AtEnd
mechanicTitle.ZIndex = 31
mechanicTitle.Parent = context

local mechanicDetail = Instance.new("TextLabel")
mechanicDetail.Name = "MechanicDetail"
mechanicDetail.Position = UDim2.fromOffset(64, 27)
mechanicDetail.Size = UDim2.new(1, -280, 0, 23)
mechanicDetail.BackgroundTransparency = 1
mechanicDetail.Text = ""
mechanicDetail.TextColor3 = Color3.fromRGB(174, 202, 222)
mechanicDetail.Font = Enum.Font.GothamMedium
mechanicDetail.TextSize = 10
mechanicDetail.TextXAlignment = Enum.TextXAlignment.Left
mechanicDetail.TextTruncate = Enum.TextTruncate.AtEnd
mechanicDetail.ZIndex = 31
mechanicDetail.Parent = context

local status = Instance.new("Frame")
status.Name = "Status"
status.AnchorPoint = Vector2.new(1, 0.5)
status.Position = UDim2.new(1, -10, 0.5, 0)
status.Size = UDim2.fromOffset(198, 40)
status.BackgroundColor3 = Color3.fromRGB(18, 43, 57)
status.BackgroundTransparency = 0.08
status.BorderSizePixel = 0
status.ZIndex = 31
status.Parent = context
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 10)

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = Color3.fromRGB(99, 216, 246)
statusStroke.Transparency = 0.35
statusStroke.Parent = status

local statusTop = Instance.new("TextLabel")
statusTop.Name = "Top"
statusTop.Position = UDim2.fromOffset(7, 2)
statusTop.Size = UDim2.new(1, -14, 0, 17)
statusTop.BackgroundTransparency = 1
statusTop.Text = ""
statusTop.TextColor3 = Color3.fromRGB(236, 246, 252)
statusTop.Font = Enum.Font.GothamBold
statusTop.TextSize = 9
statusTop.TextXAlignment = Enum.TextXAlignment.Center
statusTop.TextTruncate = Enum.TextTruncate.AtEnd
statusTop.ZIndex = 32
statusTop.Parent = status

local statusBottom = Instance.new("TextLabel")
statusBottom.Name = "Bottom"
statusBottom.Position = UDim2.fromOffset(7, 19)
statusBottom.Size = UDim2.new(1, -14, 0, 17)
statusBottom.BackgroundTransparency = 1
statusBottom.Text = ""
statusBottom.TextColor3 = Color3.fromRGB(147, 219, 239)
statusBottom.Font = Enum.Font.GothamMedium
statusBottom.TextSize = 9
statusBottom.TextXAlignment = Enum.TextXAlignment.Center
statusBottom.TextTruncate = Enum.TextTruncate.AtEnd
statusBottom.ZIndex = 32
statusBottom.Parent = status

local recoveryToast = Instance.new("TextLabel")
recoveryToast.Name = "RecoveryToast"
recoveryToast.AnchorPoint = Vector2.new(0.5, 0)
recoveryToast.Position = UDim2.new(0.5, 0, 0, 201)
recoveryToast.Size = UDim2.fromOffset(360, 38)
recoveryToast.BackgroundColor3 = Color3.fromRGB(60, 39, 18)
recoveryToast.BackgroundTransparency = 0.08
recoveryToast.BorderSizePixel = 0
recoveryToast.Text = "OBJETIVO RECUPERADO — TENTATIVA REINICIADA"
recoveryToast.TextColor3 = Color3.fromRGB(255, 211, 118)
recoveryToast.Font = Enum.Font.GothamBold
recoveryToast.TextSize = 11
recoveryToast.Visible = false
recoveryToast.ZIndex = 40
recoveryToast.Parent = root
Instance.new("UICorner", recoveryToast).CornerRadius = UDim.new(0, 10)
local recoveryStroke = Instance.new("UIStroke")
recoveryStroke.Color = Color3.fromRGB(235, 184, 86)
recoveryStroke.Transparency = 0.2
recoveryStroke.Parent = recoveryToast

local lastRecoveryCount = tonumber(workspace:GetAttribute("DungeonObjectiveRecoveryCount")) or 0
local recoverySerial = 0

local COLORS = {
	Cyan = Color3.fromRGB(111, 223, 255),
	Gold = Color3.fromRGB(236, 197, 102),
	Green = Color3.fromRGB(101, 239, 165),
	Red = Color3.fromRGB(255, 108, 119),
	Orange = Color3.fromRGB(255, 181, 92),
	Purple = Color3.fromRGB(198, 139, 255),
	Muted = Color3.fromRGB(155, 181, 202),
}

local MECHANICS = {
	MarkedOpeningTarget = {
		Icon = "◎",
		Title = "ALVO MARCADO",
		Detail = "Acerte primeiro o inimigo destacado.",
		Color = COLORS.Gold,
	},
	OpenCombat = {
		Icon = "⚔",
		Title = "LIMPE A ILHA",
		Detail = "Elimine os inimigos para liberar a saída.",
		Color = COLORS.Cyan,
	},
	EscalatingRewardWaves = {
		Icon = "▲",
		Title = "BATALHA DE RECOMPENSA",
		Detail = "As ondas ficam mais perigosas até a recompensa.",
		Color = COLORS.Gold,
	},
	HiddenPerimeterAmbush = {
		Icon = "!",
		Title = "EMBOSCADA",
		Detail = "Prepare-se: inimigos cercam a ilha.",
		Color = COLORS.Red,
	},
	PriorityRangedTargets = {
		Icon = "⌖",
		Title = "ALVOS PRIORITÁRIOS",
		Detail = "Elimine primeiro os inimigos de ataque à distância.",
		Color = COLORS.Cyan,
	},
	DestroySpawners = {
		Icon = "✹",
		Title = "DESTRUA OS NINHOS",
		Detail = "Os ninhos continuam gerando inimigos enquanto existirem.",
		Color = COLORS.Purple,
	},
	BreakWardsThenGuards = {
		Icon = "◆",
		Title = "QUEBRE OS CRISTAIS",
		Detail = "Os guardas permanecem protegidos até os cristais caírem.",
		Color = COLORS.Cyan,
	},
	HoldContestedZone = {
		Icon = "◉",
		Title = "MANTENHA O FAROL",
		Detail = "Permaneça dentro da zona para carregar o farol.",
		Color = COLORS.Purple,
	},
	DefeatSupportsThenElite = {
		Icon = "♛",
		Title = "CAÇADA ELITE",
		Detail = "Elimine os protetores antes de atacar o Elite.",
		Color = COLORS.Gold,
	},
}

local PACING_LABELS = {
	ObjectivePreparation = { "PREPARANDO", "Combate começa em", COLORS.Gold },
	CombatActive = { "COMBATE", "Objetivo ativo", COLORS.Red },
	WaveActive = { "ONDA ATIVA", "Elimine os inimigos", COLORS.Red },
	WaveCleared = { "ONDA LIMPA", "Área temporariamente segura", COLORS.Green },
	InterWave = { "INTERVALO", "Próxima onda em", COLORS.Cyan },
	ObjectiveCompletion = { "CONCLUÍDO", "Liberando a rota em", COLORS.Green },
	RouteOpen = { "ROTA ABERTA", "Avance para a próxima ilha", COLORS.Green },
	RewardWindow = { "RECOMPENSA", "Abra sua recompensa", COLORS.Gold },
	RoundTransition = { "ROUND CONCLUÍDO", "Próximo round em", COLORS.Gold },
	NextRoundOpen = { "NOVO ROUND", "Caminho liberado", COLORS.Cyan },
	BossTransition = { "BOSS", "Caminho do chefe abre em", COLORS.Gold },
	BossRouteOpen = { "ROTA DO BOSS", "Avance para a arena", COLORS.Red },
}

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function setStyle(color)
	icon.TextColor3 = color
	iconStroke.Color = color
	stroke.Color = color
	statusStroke.Color = color
end

local function setStatus(top, bottom, color)
	statusTop.Text = top or ""
	statusBottom.Text = bottom or ""
	statusTop.TextColor3 = color or COLORS.Cyan
	statusStroke.Color = color or COLORS.Cyan
end

local function pacingState()
	local state = tostring(workspace:GetAttribute("DungeonPacingState") or "")
	local endsAt = tonumber(workspace:GetAttribute("DungeonPacingStateEndsAt")) or 0
	local remaining = math.max(0, math.ceil(endsAt - serverTime()))
	return state, remaining
end

local function activeBeacon()
	for _, beacon in ipairs(CollectionService:GetTagged("DungeonHoldBeacon")) do
		if beacon:IsA("Model") and beacon.Parent then
			return beacon
		end
	end
	return nil
end

local function localInsideBeacon(beacon)
	if not beacon or not beacon.PrimaryPart then return false end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	local radius = tonumber(beacon:GetAttribute("BeaconRadius")) or 13
	local offset = rootPart.Position - beacon.PrimaryPart.Position
	local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
	return horizontal <= radius and math.abs(offset.Y) <= 10
end

local function livingNests()
	local count = 0
	for _, nest in ipairs(CollectionService:GetTagged("DungeonSlimeNest")) do
		if nest:IsA("Model")
			and nest.Parent
			and nest:GetAttribute("ObjectiveTargetCompleted") ~= true
		then
			local hum = nest:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health > 0 then
				count += 1
			end
		end
	end
	return count
end

local function showRecovery(count)
	recoverySerial += 1
	local serial = recoverySerial
	recoveryToast.Visible = true
	recoveryToast.TextTransparency = 0
	recoveryToast.BackgroundTransparency = 0.08
	task.delay(2.6, function()
		if recoverySerial ~= serial then return end
		local tween = TweenService:Create(recoveryToast, TweenInfo.new(0.25), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		if recoverySerial == serial then
			recoveryToast.Visible = false
		end
	end)
	player:SetAttribute("DungeonHUDLastObjectiveRecoveryCount", count)
end

local function mechanicStatus(mechanic, pacing, pacingRemaining)
	local activeEnemies = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonEncounterActiveEnemies")) or 0))
	local waveIndex = math.max(
		0,
		math.floor(tonumber(workspace:GetAttribute("DungeonPacingWaveIndex")
			or workspace:GetAttribute("DungeonEncounterWaveIndex")) or 0)
	)
	local waveCount = math.max(
		0,
		math.floor(tonumber(workspace:GetAttribute("DungeonPacingWaveCount")
			or workspace:GetAttribute("DungeonEncounterWaveCount")) or 0)
	)

	if pacing == "ObjectivePreparation" or pacing == "InterWave"
		or pacing == "ObjectiveCompletion" or pacing == "RoundTransition"
		or pacing == "BossTransition"
	then
		local definition = PACING_LABELS[pacing]
		if definition then
			return definition[1], pacingRemaining > 0
				and string.format("%s %ds", definition[2], pacingRemaining)
				or definition[2], definition[3]
		end
	end

	if mechanic == "HiddenPerimeterAmbush" then
		local revealAt = tonumber(workspace:GetAttribute("DungeonAmbushRevealAt")) or 0
		if revealAt > serverTime() then
			return "EMBOSCADA OCULTA",
				string.format("Revelação em %ds", math.ceil(revealAt - serverTime())),
				COLORS.Red
		end
		return "INIMIGOS REVELADOS", string.format("%d inimigos ativos", activeEnemies), COLORS.Red
	elseif mechanic == "BreakWardsThenGuards" then
		local wards = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonGuardWardsRemaining")) or 0))
		if wards > 0 then
			return string.format("CRISTAIS %d", wards), "Guardas ainda invulneráveis", COLORS.Cyan
		end
		return "GUARDAS VULNERÁVEIS", string.format("%d inimigos ativos", activeEnemies), COLORS.Green
	elseif mechanic == "DefeatSupportsThenElite" then
		local supports = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonEliteShieldSupportsRemaining")) or 0))
		if supports > 0 then
			return string.format("PROTETORES %d", supports), "Elite ainda protegido", COLORS.Orange
		end
		return "ELITE VULNERÁVEL", "Ataque o alvo principal", COLORS.Gold
	elseif mechanic == "HoldContestedZone" then
		local beacon = activeBeacon()
		if beacon then
			local held = math.max(0, math.floor(tonumber(beacon:GetAttribute("BeaconHeldSeconds")) or 0))
			local target = math.max(1, math.floor(tonumber(beacon:GetAttribute("BeaconTargetSeconds")) or 1))
			local occupants = math.max(0, math.floor(tonumber(beacon:GetAttribute("BeaconOccupantCount")) or 0))
			if localInsideBeacon(beacon) then
				return string.format("FAROL %d/%ds", held, target),
					string.format("%d jogador(es) na área", occupants),
					COLORS.Green
			end
			return string.format("FAROL %d/%ds", held, target), "ENTRE NA ÁREA DO FAROL", COLORS.Red
		end
		return "LOCALIZE O FAROL", "Entre na zona marcada", COLORS.Purple
	elseif mechanic == "DestroySpawners" then
		local nests = livingNests()
		return string.format("NINHOS RESTANTES %d", nests),
			string.format("%d inimigos ativos", activeEnemies),
			COLORS.Purple
	elseif mechanic == "MarkedOpeningTarget" then
		local focus = workspace:GetAttribute("DungeonObjectiveFocusTarget")
		return focus and "ALVO MARCADO" or "LOCALIZANDO ALVO",
			focus and "Ataque somente o alvo destacado" or "Aguarde o alvo aparecer",
			COLORS.Gold
	elseif mechanic == "PriorityRangedTargets" then
		return "PRIORIDADE: DISTÂNCIA", string.format("%d inimigos ativos", activeEnemies), COLORS.Cyan
	end

	if waveCount > 0 then
		return string.format("ONDA %d/%d", math.max(1, waveIndex), waveCount),
			string.format("%d inimigos ativos", activeEnemies),
			waveIndex >= waveCount and COLORS.Gold or COLORS.Red
	end

	if activeEnemies > 0 then
		return "COMBATE", string.format("%d inimigos ativos", activeEnemies), COLORS.Red
	end

	local pacingDefinition = PACING_LABELS[pacing]
	if pacingDefinition then
		return pacingDefinition[1], pacingDefinition[2], pacingDefinition[3]
	end
	return "OBJETIVO ATIVO", "Complete a condição para avançar", COLORS.Cyan
end

local function refresh()
	local objectiveState = tostring(workspace:GetAttribute("DungeonObjectiveState") or "Inactive")
	local bossState = tostring(workspace:GetAttribute("DungeonBossState") or "Unavailable")
	if bossState == "Ready" or bossState == "Activating" or bossState == "Active" then
		context.Visible = false
		return
	end

	if objectiveState == "Inactive" or objectiveState == "Completed" then
		local pacing = tostring(workspace:GetAttribute("DungeonPacingState") or "")
		context.Visible = PACING_LABELS[pacing] ~= nil
	else
		context.Visible = true
	end

	local mechanic = tostring(workspace:GetAttribute("DungeonObjectiveMechanic") or "")
	if mechanic == "" or mechanic == "Idle" then
		local objectiveId = tostring(workspace:GetAttribute("DungeonObjectiveId") or "")
		local fallback = {
			FirstStrike = "MarkedOpeningTarget",
			ClearThePath = "OpenCombat",
			FirstRewardBattle = "EscalatingRewardWaves",
			SkyAmbush = "HiddenPerimeterAmbush",
			RangedThreat = "PriorityRangedTargets",
			BreakTheNests = "DestroySpawners",
			SecondRewardBattle = "EscalatingRewardWaves",
			BreakTheGuard = "BreakWardsThenGuards",
			HoldTheBeacon = "HoldContestedZone",
			NestCluster = "DestroySpawners",
			EliteHunt = "DefeatSupportsThenElite",
			FinalRewardBattle = "EscalatingRewardWaves",
		}
		mechanic = fallback[objectiveId] or "OpenCombat"
	end

	local definition = MECHANICS[mechanic] or MECHANICS.OpenCombat
	icon.Text = definition.Icon
	mechanicTitle.Text = definition.Title
	mechanicDetail.Text = definition.Detail
	setStyle(definition.Color)

	local pacing, pacingRemaining = pacingState()
	local top, bottom, statusColor = mechanicStatus(mechanic, pacing, pacingRemaining)
	setStatus(top, bottom, statusColor)

	-- Mantém o painel principal curto e deixa os detalhes mecânicos neste cartão.
	if pacing == "ObjectivePreparation" and pacingRemaining > 0 then
		objectiveDetail.Text = string.format("Prepare-se — combate começa em %ds", pacingRemaining)
	elseif pacing == "InterWave" and pacingRemaining > 0 then
		objectiveDetail.Text = string.format("Respire — próxima onda em %ds", pacingRemaining)
	elseif pacing == "ObjectiveCompletion" and pacingRemaining > 0 then
		objectiveDetail.Text = string.format("Objetivo concluído — rota abre em %ds", pacingRemaining)
	end

	local waveIndex = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonPacingWaveIndex")
		or workspace:GetAttribute("DungeonEncounterWaveIndex")) or 0))
	local waveCount = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonPacingWaveCount")
		or workspace:GetAttribute("DungeonEncounterWaveCount")) or 0))
	if waveCount > 0 and waveIndex > 0 and mechanic ~= "HoldContestedZone" and mechanic ~= "DestroySpawners" then
		objectiveProgress.Text = string.format(
			"%s   •   ONDA %d/%d",
			objectiveProgress.Text:gsub("%s+•%s+ONDA.*$", ""),
			waveIndex,
			waveCount
		)
	end

	local recoveryCount = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonObjectiveRecoveryCount")) or 0))
	if recoveryCount > lastRecoveryCount then
		lastRecoveryCount = recoveryCount
		showRecovery(recoveryCount)
	end

	player:SetAttribute("DungeonHUDObjectiveMechanic", mechanic)
	player:SetAttribute("DungeonHUDObjectivePacingState", pacing)
end

local watched = {
	"DungeonObjectiveState",
	"DungeonObjectiveId",
	"DungeonObjectiveRevision",
	"DungeonObjectiveRecoveryCount",
	"DungeonObjectiveMechanic",
	"DungeonObjectiveMechanicState",
	"DungeonPacingState",
	"DungeonPacingStateEndsAt",
	"DungeonPacingWaveIndex",
	"DungeonPacingWaveCount",
	"DungeonEncounterWaveIndex",
	"DungeonEncounterWaveCount",
	"DungeonEncounterActiveEnemies",
	"DungeonAmbushRevealAt",
	"DungeonGuardWardsRemaining",
	"DungeonEliteShieldSupportsRemaining",
	"DungeonBossState",
}

for _, attribute in ipairs(watched) do
	workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end

CollectionService:GetInstanceAddedSignal("DungeonHoldBeacon"):Connect(refresh)
CollectionService:GetInstanceRemovedSignal("DungeonHoldBeacon"):Connect(refresh)
CollectionService:GetInstanceAddedSignal("DungeonSlimeNest"):Connect(refresh)
CollectionService:GetInstanceRemovedSignal("DungeonSlimeNest"):Connect(refresh)

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	refresh()
end)

gui:SetAttribute("ObjectiveContextVersion", VERSION)
player:SetAttribute("DungeonHUDObjectivesReady", true)
player:SetAttribute("DungeonHUDObjectivesVersion", VERSION)
workspace:SetAttribute("DungeonHUDObjectivesReady", true)
workspace:SetAttribute("DungeonHUDObjectivesPolicy", "MechanicSpecificObjectivePresentationV1")

refresh()
