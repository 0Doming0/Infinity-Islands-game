-- Mobile Dungeon Mode — Task 03: portrait combat HUD shell.
--
-- Depende das Tasks 01 e 02.
-- Esta camada e somente de apresentacao:
-- - nao concede dano;
-- - nao altera aim;
-- - nao altera cooldown;
-- - nao altera geracao;
-- - nao altera a logica autoritativa dos objetivos.
--
-- Quando DungeonMobileMode == true, substitui apenas a leitura visual do HUD
-- de combate por um shell compacto para portrait.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonPortraitCombatHUDV1"
local RENDER_STEP = "InfinityIslandsPortraitCombatHUD"
local ACTION_ATTACK = "SkyDungeonAttack"

local COLORS = {
	Glass = Color3.fromRGB(13, 27, 42),
	GlassRaised = Color3.fromRGB(23, 48, 65),
	Text = Color3.fromRGB(239, 247, 252),
	Muted = Color3.fromRGB(146, 176, 199),
	Cyan = Color3.fromRGB(107, 225, 255),
	CyanSoft = Color3.fromRGB(181, 241, 255),
	Gold = Color3.fromRGB(232, 195, 104),
	GoldSoft = Color3.fromRGB(255, 225, 143),
	Green = Color3.fromRGB(100, 236, 162),
	Health = Color3.fromRGB(255, 102, 122),
	Stamina = Color3.fromRGB(92, 226, 170),
	Red = Color3.fromRGB(255, 106, 118),
	Dim = Color3.fromRGB(80, 105, 126),
}

local active = false
local gui
local root
local topPanel
local objectiveTitle
local objectiveDetail
local objectiveProgress
local objectiveFill
local healthValue
local healthFill
local staminaValue
local staminaFill
local stageNodes = {}
local abilitySlot
local abilityName
local shellScale
local viewportConnection

local suppressed = setmetatable({}, { __mode = "k" })
local suppressConnections = setmetatable({}, { __mode = "k" })
local suppressionActive = false

local function getViewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(390, 844)
end

local function getInsets()
	local topLeft = Vector2.zero
	local bottomRight = Vector2.zero
	local success, first, second = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if success then
		topLeft = typeof(first) == "Vector2" and first or Vector2.zero
		bottomRight = typeof(second) == "Vector2" and second or Vector2.zero
	end
	return topLeft, bottomRight
end

local function round(value)
	return math.floor(value + 0.5)
end

local function accessibilityScale(attributeName, fallback, minimum, maximum)
	local value = tonumber(player:GetAttribute(attributeName))
	if value == nil then
		value = fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
	return corner
end

local function addStroke(instance, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = instance
	return stroke
end

local function label(parent, name, text, position, size, options)
	options = options or {}
	local object = Instance.new("TextLabel")
	object.Name = name
	object.Position = position
	object.Size = size
	object.BackgroundTransparency = 1
	object.Text = text
	object.TextColor3 = options.Color or COLORS.Text
	object.Font = options.Font or Enum.Font.GothamMedium
	object.TextSize = options.TextSize or 11
	object.TextXAlignment = options.XAlignment or Enum.TextXAlignment.Left
	object.TextYAlignment = options.YAlignment or Enum.TextYAlignment.Center
	object.TextWrapped = options.TextWrapped == true
	object.TextTruncate = options.TextTruncate or Enum.TextTruncate.AtEnd
	object.ZIndex = options.ZIndex or (parent.ZIndex + 1)
	object.Parent = parent
	return object
end

local function bar(parent, name, position, size, color)
	local background = Instance.new("Frame")
	background.Name = name
	background.Position = position
	background.Size = size
	background.BackgroundColor3 = Color3.fromRGB(28, 46, 60)
	background.BackgroundTransparency = 0.10
	background.BorderSizePixel = 0
	background.ClipsDescendants = true
	background.ZIndex = parent.ZIndex + 1
	background.Parent = parent
	addCorner(background, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = background.ZIndex + 1
	fill.Parent = background
	addCorner(fill, 5)

	return background, fill
end

local function currentRound()
	return math.clamp(
		math.floor(tonumber(
			workspace:GetAttribute("DungeonCurrentRoundIndex")
				or workspace:GetAttribute("DungeonObjectiveRoundIndex")
				or 1
		) or 1),
		1,
		3
	)
end

local function currentIslandInRound(roundIndex)
	local explicit = tonumber(workspace:GetAttribute("DungeonObjectiveIslandIndex"))
	if explicit then
		return math.max(1, math.floor(explicit))
	end

	local globalIndex = math.max(
		1,
		math.floor(tonumber(
			workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
				or workspace:GetAttribute("DungeonCurrentObjectiveIsland")
				or 1
		) or 1)
	)

	if roundIndex == 1 then
		return math.clamp(globalIndex, 1, 3)
	elseif roundIndex == 2 then
		return math.clamp(globalIndex - 3, 1, 4)
	end
	return math.clamp(globalIndex - 7, 1, 5)
end

local function completedRound()
	return math.clamp(
		math.floor(math.max(
			tonumber(workspace:GetAttribute("DungeonHighestCompletedRound")) or 0,
			tonumber(player:GetAttribute("DungeonCheckpointCommittedRound")) or 0
		)),
		0,
		3
	)
end

local function ratio(value, maximum)
	maximum = math.max(1, tonumber(maximum) or 1)
	return math.clamp((tonumber(value) or 0) / maximum, 0, 1)
end

local function setFill(fill, value)
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
	end
end

local function createStageStrip(parent)
	local strip = Instance.new("Frame")
	strip.Name = "RunStages"
	strip.Position = UDim2.fromOffset(12, 9)
	strip.Size = UDim2.new(1, -24, 0, 28)
	strip.BackgroundTransparency = 1
	strip.ZIndex = parent.ZIndex + 1
	strip.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 5)
	layout.Parent = strip

	for index, text in ipairs({ "R1", "R2", "R3", "BOSS" }) do
		local node = Instance.new("Frame")
		node.Name = text
		node.Size = index == 4
			and UDim2.new(0.28, -4, 1, 0)
			or UDim2.new(0.20, -4, 1, 0)
		node.BackgroundColor3 = COLORS.GlassRaised
		node.BackgroundTransparency = 0.08
		node.BorderSizePixel = 0
		node.ZIndex = strip.ZIndex + 1
		node.Parent = strip
		addCorner(node, 8)

		local stroke = addStroke(
			node,
			index == 4 and COLORS.Red or COLORS.Cyan,
			0.62,
			1
		)

		local textLabel = label(
			node,
			"Text",
			text,
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			{
				TextSize = index == 4 and 9 or 10,
				Font = Enum.Font.GothamBold,
				Color = COLORS.Muted,
				XAlignment = Enum.TextXAlignment.Center,
			}
		)

		stageNodes[index] = {
			Frame = node,
			Stroke = stroke,
			Label = textLabel,
		}
	end
end

local function createHud()
	if gui and gui.Parent then
		return
	end

	local existing = playerGui:FindFirstChild("DungeonPortraitCombatHUD")
	if existing then
		existing:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "DungeonPortraitCombatHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 58
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	topPanel = Instance.new("Frame")
	topPanel.Name = "CombatHeader"
	topPanel.AnchorPoint = Vector2.new(0.5, 0)
	topPanel.Position = UDim2.new(0.5, 0, 0, 8)
	topPanel.Size = UDim2.new(1, -20, 0, 154)
	topPanel.BackgroundColor3 = COLORS.Glass
	topPanel.BackgroundTransparency = 0.055
	topPanel.BorderSizePixel = 0
	topPanel.ZIndex = 20
	topPanel.Parent = root
	addCorner(topPanel, 16)
	addStroke(topPanel, COLORS.Gold, 0.40, 1.1)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(270, 138)
	constraint.MaxSize = Vector2.new(520, 168)
	constraint.Parent = topPanel

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 52, 69)),
		ColorSequenceKeypoint.new(0.58, COLORS.Glass),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 25, 55)),
	})
	gradient.Rotation = 8
	gradient.Parent = topPanel

	createStageStrip(topPanel)

	objectiveTitle = label(
		topPanel,
		"ObjectiveTitle",
		"PREPARANDO EXPEDIÇÃO",
		UDim2.fromOffset(13, 42),
		UDim2.new(1, -26, 0, 24),
		{
			TextSize = 14,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	objectiveDetail = label(
		topPanel,
		"ObjectiveDetail",
		"Aguarde o objetivo.",
		UDim2.fromOffset(13, 66),
		UDim2.new(1, -26, 0, 19),
		{
			TextSize = 9,
			Color = COLORS.CyanSoft,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	local progressBar
	progressBar, objectiveFill = bar(
		topPanel,
		"ObjectiveProgress",
		UDim2.fromOffset(14, 88),
		UDim2.new(1, -28, 0, 9),
		COLORS.Cyan
	)

	objectiveProgress = label(
		topPanel,
		"ObjectiveProgressText",
		"0 / 1",
		UDim2.fromOffset(14, 99),
		UDim2.new(1, -28, 0, 17),
		{
			TextSize = 8,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Muted,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	local vitals = Instance.new("Frame")
	vitals.Name = "Vitals"
	vitals.Position = UDim2.fromOffset(13, 119)
	vitals.Size = UDim2.new(1, -26, 0, 28)
	vitals.BackgroundTransparency = 1
	vitals.ZIndex = topPanel.ZIndex + 1
	vitals.Parent = topPanel

	label(
		vitals,
		"HealthGlyph",
		"♥",
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(17, 13),
		{
			TextSize = 10,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Health,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	local _, healthBarFill = bar(
		vitals,
		"Health",
		UDim2.fromOffset(19, 2),
		UDim2.new(0.42, -20, 0, 8),
		COLORS.Health
	)
	healthFill = healthBarFill

	healthValue = label(
		vitals,
		"HealthValue",
		"100%",
		UDim2.fromOffset(19, 12),
		UDim2.new(0.42, -20, 0, 13),
		{
			TextSize = 8,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	label(
		vitals,
		"StaminaGlyph",
		"⚡",
		UDim2.new(0.52, 0, 0, 0),
		UDim2.fromOffset(18, 13),
		{
			TextSize = 9,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Stamina,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	local _, staminaBarFill = bar(
		vitals,
		"Stamina",
		UDim2.new(0.52, 20, 0, 2),
		UDim2.new(0.48, -20, 0, 8),
		COLORS.Stamina
	)
	staminaFill = staminaBarFill

	staminaValue = label(
		vitals,
		"StaminaValue",
		"100%",
		UDim2.new(0.52, 20, 0, 12),
		UDim2.new(0.48, -20, 0, 13),
		{
			TextSize = 8,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	-- Slot visual reservado para uma habilidade real.
	-- Fica oculto ate um sistema futuro publicar DungeonActiveAbilityName.
	abilitySlot = Instance.new("Frame")
	abilitySlot.Name = "AbilitySlot"
	abilitySlot.AnchorPoint = Vector2.new(0.5, 0.5)
	abilitySlot.Size = UDim2.fromOffset(62, 62)
	abilitySlot.BackgroundColor3 = Color3.fromRGB(45, 34, 67)
	abilitySlot.BackgroundTransparency = 0.10
	abilitySlot.BorderSizePixel = 0
	abilitySlot.Visible = false
	abilitySlot.ZIndex = 30
	abilitySlot.Parent = root
	addCorner(abilitySlot, 31)
	addStroke(abilitySlot, COLORS.Gold, 0.25, 1.5)

	label(
		abilitySlot,
		"Glyph",
		"✦",
		UDim2.fromOffset(0, 3),
		UDim2.new(1, 0, 0, 34),
		{
			TextSize = 23,
			Font = Enum.Font.GothamBlack,
			Color = COLORS.GoldSoft,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	abilityName = label(
		abilitySlot,
		"Name",
		"HABILIDADE",
		UDim2.fromOffset(4, 37),
		UDim2.new(1, -8, 0, 18),
		{
			TextSize = 7,
			Font = Enum.Font.GothamBold,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Center,
		}
	)

	shellScale = Instance.new("UIScale")
	shellScale.Name = "PortraitScale"
	shellScale.Scale = 1
	shellScale.Parent = topPanel
end

local function setNodeStyle(index, state)
	local node = stageNodes[index]
	if not node then
		return
	end

	if state == "Completed" then
		node.Frame.BackgroundColor3 = Color3.fromRGB(29, 73, 63)
		node.Stroke.Color = COLORS.Green
		node.Stroke.Transparency = 0.12
		node.Stroke.Thickness = 1.4
		node.Label.TextColor3 = COLORS.Green
		node.Label.Text = index <= 3 and ("✓ R" .. index) or "✓ BOSS"
	elseif state == "Current" then
		node.Frame.BackgroundColor3 = Color3.fromRGB(23, 69, 84)
		node.Stroke.Color = COLORS.Cyan
		node.Stroke.Transparency = 0.04
		node.Stroke.Thickness = 1.8
		node.Label.TextColor3 = COLORS.CyanSoft
		node.Label.Text = "R" .. index
	elseif state == "Reward" then
		node.Frame.BackgroundColor3 = Color3.fromRGB(75, 59, 24)
		node.Stroke.Color = COLORS.Gold
		node.Stroke.Transparency = 0.05
		node.Stroke.Thickness = 1.8
		node.Label.TextColor3 = COLORS.GoldSoft
		node.Label.Text = "R" .. index
	elseif state == "Boss" then
		node.Frame.BackgroundColor3 = Color3.fromRGB(79, 35, 43)
		node.Stroke.Color = COLORS.Red
		node.Stroke.Transparency = 0.04
		node.Stroke.Thickness = 1.9
		node.Label.TextColor3 = COLORS.GoldSoft
		node.Label.Text = "BOSS"
	else
		node.Frame.BackgroundColor3 = COLORS.GlassRaised
		node.Stroke.Color = index == 4 and COLORS.Red or COLORS.Cyan
		node.Stroke.Transparency = 0.68
		node.Stroke.Thickness = 1
		node.Label.TextColor3 = COLORS.Muted
		node.Label.Text = index <= 3 and ("R" .. index) or "BOSS"
	end
end

local function updateStages()
	local roundIndex = currentRound()
	local doneRound = completedRound()
	local bossState = tostring(workspace:GetAttribute("DungeonBossState") or "")
	local phaseState = tostring(workspace:GetAttribute("DungeonPhaseState") or "")
	local rewardPending = tonumber(workspace:GetAttribute("DungeonRewardPendingRound"))

	for index = 1, 3 do
		if doneRound >= index then
			setNodeStyle(index, "Completed")
		elseif rewardPending == index then
			setNodeStyle(index, "Reward")
		elseif index == roundIndex and phaseState ~= "Victory" and phaseState ~= "Defeat" then
			setNodeStyle(index, "Current")
		else
			setNodeStyle(index, "Future")
		end
	end

	if phaseState == "Victory" or bossState == "Defeated" then
		setNodeStyle(4, "Completed")
	elseif bossState == "Active" or bossState == "Activating" or bossState == "Ready"
		or workspace:GetAttribute("DungeonFinalRewardCommitted") == true
	then
		setNodeStyle(4, "Boss")
	else
		setNodeStyle(4, "Future")
	end
end

local function pacingDescription()
	local pacing = tostring(workspace:GetAttribute("DungeonPacingState") or "")
	if pacing == "ObjectivePreparation" then
		return "Prepare-se para o desafio."
	elseif pacing == "InterWave" then
		return "Próxima onda chegando."
	elseif pacing == "WaveActive" then
		return "Elimine os inimigos desta onda."
	elseif pacing == "RewardWindow" then
		return "Recompensa liberada."
	elseif pacing == "RoundTransition" then
		return "Round concluído."
	elseif pacing == "BossTransition" then
		return "O Boss está adiante."
	elseif pacing == "BossRouteOpen" then
		return "Avance para o Boss."
	end
	return nil
end

local function updateObjective()
	if not objectiveTitle then
		return
	end

	local bossState = tostring(workspace:GetAttribute("DungeonBossState") or "")
	if bossState == "Ready" or bossState == "Activating" or bossState == "Active" then
		local bossHealth = math.max(0, tonumber(workspace:GetAttribute("DungeonBossHealth")) or 0)
		local bossMax = math.max(1, tonumber(workspace:GetAttribute("DungeonBossMaxHealth")) or 1)
		local bossPhase = math.max(1, math.floor(tonumber(workspace:GetAttribute("DungeonBossPhase")) or 1))

		objectiveTitle.Text = "BOSS • REI SLIME COLOSSAL"
		objectiveDetail.Text = string.format("FASE %d • desvie dos ataques e mantenha pressão", bossPhase)
		objectiveProgress.Text = string.format("%d / %d", math.floor(bossHealth), math.floor(bossMax))
		objectiveFill.BackgroundColor3 = COLORS.Red
		setFill(objectiveFill, ratio(bossHealth, bossMax))
		return
	end

	local titleText = tostring(
		workspace:GetAttribute("DungeonObjectiveTitle")
			or "PREPARANDO EXPEDIÇÃO"
	)
	local description = pacingDescription()
		or tostring(workspace:GetAttribute("DungeonObjectiveDescription") or "Aguarde o objetivo.")

	local progress = math.max(0, tonumber(workspace:GetAttribute("DungeonObjectiveProgress")) or 0)
	local target = math.max(1, tonumber(workspace:GetAttribute("DungeonObjectiveTarget")) or 1)
	local roundIndex = currentRound()
	local islandIndex = currentIslandInRound(roundIndex)
	local roundLength = ({ 3, 4, 5 })[roundIndex] or 1

	objectiveTitle.Text = string.upper(titleText)
	objectiveDetail.Text = string.format(
		"R%d • ILHA %d/%d  •  %s",
		roundIndex,
		islandIndex,
		roundLength,
		description
	)
	objectiveProgress.Text = string.format("%d / %d", math.floor(progress), math.floor(target))
	objectiveFill.BackgroundColor3 =
		tonumber(workspace:GetAttribute("DungeonRewardPendingRound")) == roundIndex
			and COLORS.Gold
			or COLORS.Cyan
	setFill(objectiveFill, ratio(progress, target))
end

local function updateVitals()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local health = humanoid and humanoid.Health or 0
	local maxHealth = humanoid and humanoid.MaxHealth or 100
	local healthRatio = ratio(health, maxHealth)
	setFill(healthFill, healthRatio)
	if healthValue then
		healthValue.Text = string.format("%d%%", math.floor(healthRatio * 100 + 0.5))
	end

	local stamina = character and tonumber(character:GetAttribute("SprintStamina"))
	local maxStamina = character and tonumber(character:GetAttribute("SprintStaminaMax"))
	stamina = stamina or maxStamina or 100
	maxStamina = maxStamina or 100
	local staminaRatio = ratio(stamina, maxStamina)
	setFill(staminaFill, staminaRatio)
	if staminaValue then
		staminaValue.Text = string.format("%d%%", math.floor(staminaRatio * 100 + 0.5))
	end
end

local function modalOrRewardVisible()
	if player:GetAttribute("DungeonMobileAccessibilityPanelOpen") == true then
		return true
	end
	if workspace:GetAttribute("DungeonRewardIslandActive") == true then
		return true
	end

	local result = playerGui:FindFirstChild("DungeonResultUI")
	if result and result:IsA("ScreenGui") and result.Enabled then
		return true
	end

	local unified = playerGui:FindFirstChild("DungeonUnifiedHUD")
	local unifiedRoot = unified and unified:FindFirstChild("Root")
	local rewardPanel = unifiedRoot and unifiedRoot:FindFirstChild("RewardIslandPanel")
	if rewardPanel and rewardPanel:IsA("GuiObject") and rewardPanel.Visible then
		return true
	end

	local upgradeGui = playerGui:FindFirstChild("DungeonRunUpgradeUI")
	if upgradeGui and upgradeGui:IsA("ScreenGui") and upgradeGui.Enabled then
		return true
	end

	return false
end

local function updateAbilitySlot()
	if not abilitySlot then
		return
	end

	local rawName = player:GetAttribute("DungeonActiveAbilityName")
	local enabled = player:GetAttribute("DungeonMobileAbilityEnabled") == true
		or (type(rawName) == "string" and rawName ~= "")

	abilitySlot.Visible = active and enabled and not modalOrRewardVisible()
	if type(rawName) == "string" and rawName ~= "" then
		abilityName.Text = string.upper(rawName)
	else
		abilityName.Text = "HABILIDADE"
	end
end

local function shouldSuppress(object)
	if not object or not object:IsA("GuiObject") then
		return false
	end

	local parent = object.Parent
	local parentName = parent and parent.Name or ""
	local name = object.Name

	-- HUD unificado de desktop/tablet: mantemos Notification, StateBanner,
	-- WaypointArrow, InventoryDrawer e modais; escondemos apenas o bloco
	-- permanente de combate que seria duplicado no portrait.
	if parentName == "Root" and parent.Parent and parent.Parent.Name == "DungeonUnifiedHUD" then
		return name == "Currencies"
			or name == "Objective"
			or name == "Party"
			or name == "Vitals"
			or name == "Hotbar"
	end

	-- Progressao legada por altura/nivel.
	if name == "RunLevelRace" then
		return true
	end
	if name == "RunProgressPill" and parentName == "MobileHUDCoordinatorUI" then
		return true
	end
	if name == "RunProgress" and parentName == "Root"
		and parent.Parent and parent.Parent.Name == "CoreLoopClarityHUD"
	then
		return true
	end

	-- Elementos permanentes duplicados do SurvivalUI. Alertas e resultados nao.
	if parentName == "HUD" and parent.Parent and parent.Parent.Name == "SurvivalUI" then
		return true
	end
	if name == "HUD" and parentName == "SurvivalUI" then
		return true
	end
	if name == "EquippedRelic" and parentName == "SurvivalUI" then
		return true
	end

	-- A stamina compacta do shell substitui somente a barra permanente antiga.
	if name == "Background" and parentName == "SprintStaminaGui" then
		return true
	end

	return false
end

local function suppressObject(object)
	if not shouldSuppress(object) or suppressed[object] ~= nil then
		return
	end

	suppressed[object] = object.Visible
	if suppressionActive then
		object.Visible = false
	end

	suppressConnections[object] = object:GetPropertyChangedSignal("Visible"):Connect(function()
		if suppressionActive and object.Parent and object.Visible then
			object.Visible = false
		end
	end)
end

local function scanSuppressions()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		suppressObject(descendant)
	end
end

local function enableSuppressions()
	suppressionActive = true
	scanSuppressions()
	for object in pairs(suppressed) do
		if object.Parent then
			object.Visible = false
		end
	end
end

local function disableSuppressions()
	suppressionActive = false
	for object, wasVisible in pairs(suppressed) do
		if object.Parent then
			object.Visible = wasVisible == true
		end
	end
end

local function attackButton()
	local button = ContextActionService:GetButton(ACTION_ATTACK)
	return button and button:IsA("GuiButton") and button or nil
end

local function styleAttackButton(button, center, size)
	if not button then
		return
	end

	local parentPosition = button.Parent and button.Parent.AbsolutePosition or Vector2.zero
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	button.Position = UDim2.fromOffset(
		round(center.X - parentPosition.X),
		round(center.Y - parentPosition.Y)
	)
	button.ZIndex = math.max(button.ZIndex, 30)
	button.BackgroundColor3 = Color3.fromRGB(111, 55, 166)
	button.BackgroundTransparency = 0.08

	local corner = button:FindFirstChild("PortraitCorner")
		or button:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Name = "PortraitCorner"
		corner.Parent = button
	end
	corner.CornerRadius = UDim.new(1, 0)

	local stroke = button:FindFirstChild("PortraitStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "PortraitStroke"
		stroke.Parent = button
	end
	stroke.Color = COLORS.GoldSoft
	stroke.Transparency = 0.10
	stroke.Thickness = 2

	local caption = button:FindFirstChild("PortraitCaption")
	if not caption then
		caption = Instance.new("TextLabel")
		caption.Name = "PortraitCaption"
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.new(0.5, 0, 1, -7)
		caption.Size = UDim2.new(1, -10, 0, 15)
		caption.BackgroundTransparency = 1
		caption.Font = Enum.Font.GothamBold
		caption.Text = "ATACAR"
		caption.TextColor3 = COLORS.Text
		caption.ZIndex = button.ZIndex + 2
		caption.Parent = button
	end
	caption.TextSize = math.clamp(round(size * 0.11), 9, 13)
end

local function updateLayout()
	if not gui or not root then
		return
	end

	local viewport = getViewport()
	local topLeft, bottomRight = getInsets()
	local shortest = math.min(viewport.X, viewport.Y)

	local scale = 1
	if viewport.X < 340 then
		scale = 0.82
	elseif viewport.X < 390 then
		scale = 0.90
	elseif viewport.X > 520 then
		scale = math.min(1.08, viewport.X / 520)
	end

	local uiUserScale = accessibilityScale(
		"DungeonMobileUIUserScale",
		1,
		0.90,
		1.15
	)
	scale *= uiUserScale
	shellScale.Scale = scale

	topPanel.Position = UDim2.new(0.5, 0, 0, 8)

	local touchUserScale = accessibilityScale(
		"DungeonMobileTouchUserScale",
		1,
		0.90,
		1.22
	)
	local attackSize = math.clamp(
		round(shortest * 0.235 * touchUserScale),
		82,
		118
	)
	local attackCenter = Vector2.new(
		viewport.X - bottomRight.X - attackSize / 2 - 13,
		viewport.Y - bottomRight.Y - attackSize / 2 - 24
	)

	styleAttackButton(attackButton(), attackCenter, attackSize)

	local abilitySize = math.clamp(round(attackSize * 0.72), 58, 74)
	abilitySlot.Size = UDim2.fromOffset(abilitySize, abilitySize)
	abilitySlot.Position = UDim2.fromOffset(
		attackCenter.X,
		attackCenter.Y - attackSize / 2 - abilitySize / 2 - 14 - topLeft.Y * 0
	)

	playerGui:SetAttribute(
		"DungeonMobileHUDAttackCenter",
		Vector2.new(round(attackCenter.X), round(attackCenter.Y))
	)
	playerGui:SetAttribute(
		"DungeonMobileHUDAbilityCenter",
		Vector2.new(
			round(attackCenter.X),
			round(attackCenter.Y - attackSize / 2 - abilitySize / 2 - 14)
		)
	)
	playerGui:SetAttribute("DungeonMobileHUDAttackSize", attackSize)
	playerGui:SetAttribute("DungeonMobileHUDScale", scale)
	playerGui:SetAttribute("DungeonMobileHUDTouchScale", touchUserScale)
	playerGui:SetAttribute("DungeonMobileHUDCenterClear", true)
end

local function updateVisibility()
	if not gui then
		return
	end

	local show = active and not modalOrRewardVisible()
	gui.Enabled = active
	if topPanel then
		topPanel.Visible = show
	end

	updateAbilitySlot()
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	createHud()
	active = true
	gui.Enabled = true
	enableSuppressions()
	updateLayout()
	updateObjective()
	updateVitals()
	updateStages()
	updateVisibility()

	player:SetAttribute("DungeonMobileCombatHUDReady", true)
	player:SetAttribute("DungeonMobileCombatHUDActive", true)
	player:SetAttribute("DungeonMobileCombatHUDVersion", VERSION)
	player:SetAttribute("DungeonMobileCombatHUDPolicy", "PortraitMinimalCombatShellV1")
	playerGui:SetAttribute("DungeonMobileCombatHUDReady", true)
	playerGui:SetAttribute("DungeonMobileCombatHUDActive", true)
end

local function deactivate()
	if not active then
		return
	end

	active = false
	if gui then
		gui.Enabled = false
	end
	disableSuppressions()

	player:SetAttribute("DungeonMobileCombatHUDActive", false)
	playerGui:SetAttribute("DungeonMobileCombatHUDActive", false)
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

playerGui.DescendantAdded:Connect(function(instance)
	if suppressionActive then
		task.defer(suppressObject, instance)
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

local function bindCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if active then
				updateLayout()
			end
		end)
	end

	if active then
		updateLayout()
	end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

RunService:BindToRenderStep(
	RENDER_STEP,
	Enum.RenderPriority.Last.Value,
	function()
		if not active then
			return
		end
		updateObjective()
		updateVitals()
		updateStages()
		updateVisibility()
		updateLayout()
	end
)

player:SetAttribute("DungeonMobileCombatHUDControllerLoaded", true)
player:SetAttribute("DungeonMobileCombatHUDVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal("DungeonInputProfileReady"):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(function()
	deactivate()
	RunService:UnbindFromRenderStep(RENDER_STEP)
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	for object, connection in pairs(suppressConnections) do
		connection:Disconnect()
		suppressConnections[object] = nil
	end
end)
