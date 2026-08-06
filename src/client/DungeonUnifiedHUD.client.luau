local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local shared = ReplicatedStorage:WaitForChild("Shared")
local dungeonRemotes = shared:WaitForChild("Remotes"):WaitForChild("Dungeon")
local objectiveEvent = dungeonRemotes:WaitForChild("ObjectiveState")
local rewardEvent = dungeonRemotes:WaitForChild("RewardState")
local lifeEvent = dungeonRemotes:WaitForChild("LifeState")
local bossEvent = dungeonRemotes:WaitForChild("BossState")
local coinRewardEvent = ReplicatedStorage:FindFirstChild("CoinReward")

local LEGACY_PLAYER_SCRIPTS = {
	SurvivalUI = true,
	DownedUI = true,
	DeathScreen = true,
	DungeonBossHUD = true,
	SessionFloodHUD = true,
	CoinRewardUI = true,
	StaminaRewardUI = true,
	StartScreen = true,
	MobileHUDLayout = true,
	PartyUI = true,
	TradeUI = true,
	GlobalStoreUI = true,
	RewardWheelUI = true,
	VillagerUI = true,
	PersonalSkyMerchant = true,
	TutorialUI = true,
	WorldEventUI = true,
	SanctuaryStatusUI = true,
	SanctuaryRescueTransition = true,
	GenerationCloudClient = true,
	MysteryDistance = true,
	LeaderboardUI = true,
	MonetizationUI = true,
	CollectibleBlenderAnimation = true,
	MimicAnimationClient_ContinuousLoop_V7 = true,
}

local LEGACY_SCREEN_GUIS = {
	SurvivalUI = true,
	DownedUI = true,
	DeathScreen = true,
	DungeonBossHUD = true,
	SessionFloodHUD = true,
	CoinRewardUI = true,
	StaminaRewardUI = true,
	StartScreen = true,
	RespawnTransition = true,
	PartyUI = true,
	TradeUI = true,
	GlobalStoreUI = true,
	RewardWheelUI = true,
	VillagerUI = true,
	PersonalSkyMerchant = true,
	TutorialUI = true,
	WorldEventUI = true,
	SanctuaryStatusUI = true,
	LeaderboardUI = true,
	MonetizationUI = true,
}

local function suppressLegacyScript(instance)
	if instance:IsA("LocalScript") and LEGACY_PLAYER_SCRIPTS[instance.Name] then
		instance.Disabled = true
	end
end

local function suppressLegacyGui(instance)
	if instance:IsA("ScreenGui") and LEGACY_SCREEN_GUIS[instance.Name] then
		instance.Enabled = false
		if instance:GetAttribute("SuppressedByDungeonUnifiedHUD") ~= true then
			instance:SetAttribute("SuppressedByDungeonUnifiedHUD", true)
			instance:GetPropertyChangedSignal("Enabled"):Connect(function()
				if instance.Parent and instance.Enabled then
					instance.Enabled = false
				end
			end)
		end
	end
end

for _, child in ipairs(playerScripts:GetChildren()) do
	suppressLegacyScript(child)
end
for _, child in ipairs(playerGui:GetChildren()) do
	suppressLegacyGui(child)
end
playerScripts.ChildAdded:Connect(suppressLegacyScript)
playerGui.ChildAdded:Connect(suppressLegacyGui)

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonUnifiedHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 48
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local palette = {
	Panel = Color3.fromRGB(14, 18, 27),
	PanelSoft = Color3.fromRGB(23, 29, 41),
	Stroke = Color3.fromRGB(104, 124, 158),
	Text = Color3.fromRGB(242, 245, 250),
	Muted = Color3.fromRGB(174, 184, 202),
	Accent = Color3.fromRGB(103, 184, 255),
	Success = Color3.fromRGB(88, 211, 126),
	Warning = Color3.fromRGB(255, 191, 79),
	Danger = Color3.fromRGB(255, 100, 100),
	Purple = Color3.fromRGB(180, 122, 255),
}

local function rounded(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = instance
end

local function stroked(instance, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.Stroke
	stroke.Transparency = transparency or 0.55
	stroke.Thickness = 1
	stroke.Parent = instance
end

local function label(parent, name, text, position, size, textSize, font, color, alignment)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Position = position
	item.Size = size
	item.Text = text
	item.TextColor3 = color or palette.Text
	item.TextSize = textSize or 14
	item.Font = font or Enum.Font.GothamMedium
	item.TextXAlignment = alignment or Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function panel(name, position, size, anchor)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor or Vector2.zero
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = palette.Panel
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = gui
	rounded(frame, 13)
	stroked(frame, 0.58)
	return frame
end

local resources = panel("Resources", UDim2.fromOffset(12, 12), UDim2.fromOffset(224, 94))
local coinsLabel = label(resources, "Coins", "MOEDAS  0", UDim2.fromOffset(13, 7), UDim2.new(1, -26, 0, 26), 15, Enum.Font.GothamBold, palette.Warning)
local pendingCoinsLabel = label(resources, "PendingCoins", "PENDENTES  +0", UDim2.fromOffset(13, 34), UDim2.new(1, -26, 0, 23), 13, Enum.Font.GothamMedium, palette.Success)
local essenceLabel = label(resources, "Essence", "ESSÊNCIA  0", UDim2.fromOffset(13, 59), UDim2.new(1, -26, 0, 23), 13, Enum.Font.GothamMedium, palette.Purple)

local objectivePanel = panel("Objective", UDim2.fromScale(0.5, 0), UDim2.fromOffset(560, 126), Vector2.new(0.5, 0))
objectivePanel.Position = UDim2.new(0.5, 0, 0, 12)
local routeLabel = label(objectivePanel, "Route", "RODADA 1  •  ILHA 1/12", UDim2.fromOffset(16, 7), UDim2.new(1, -32, 0, 20), 12, Enum.Font.GothamBold, palette.Accent)
local objectiveTitle = label(objectivePanel, "Title", "PREPARANDO EXPEDIÇÃO", UDim2.fromOffset(16, 28), UDim2.new(1, -32, 0, 29), 19, Enum.Font.GothamBold)
local objectiveDescription = label(objectivePanel, "Description", "Aguarde a geração da rota.", UDim2.fromOffset(16, 57), UDim2.new(1, -32, 0, 21), 13, Enum.Font.GothamMedium, palette.Muted)

local objectiveBarBack = Instance.new("Frame")
objectiveBarBack.Name = "ProgressBack"
objectiveBarBack.Position = UDim2.fromOffset(16, 84)
objectiveBarBack.Size = UDim2.new(1, -138, 0, 17)
objectiveBarBack.BackgroundColor3 = Color3.fromRGB(42, 49, 63)
objectiveBarBack.BorderSizePixel = 0
objectiveBarBack.ClipsDescendants = true
objectiveBarBack.Parent = objectivePanel
rounded(objectiveBarBack, 7)
local objectiveBarFill = Instance.new("Frame")
objectiveBarFill.Name = "ProgressFill"
objectiveBarFill.Size = UDim2.fromScale(0, 1)
objectiveBarFill.BackgroundColor3 = palette.Accent
objectiveBarFill.BorderSizePixel = 0
objectiveBarFill.Parent = objectiveBarBack
rounded(objectiveBarFill, 7)
local objectiveProgress = label(objectivePanel, "Progress", "0 / 1", UDim2.new(1, -116, 0, 80), UDim2.fromOffset(100, 25), 13, Enum.Font.GothamBold, palette.Text, Enum.TextXAlignment.Right)
local waypointLabel = label(objectivePanel, "Waypoint", "ALVO --m", UDim2.fromOffset(16, 103), UDim2.new(1, -32, 0, 18), 11, Enum.Font.GothamMedium, palette.Muted)

local bossPanel = panel("Boss", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(620, 102), Vector2.new(0.5, 0))
bossPanel.Visible = false
local bossName = label(bossPanel, "Name", "REI SLIME COLOSSAL", UDim2.fromOffset(16, 7), UDim2.new(1, -150, 0, 25), 18, Enum.Font.GothamBold)
local bossPhase = label(bossPanel, "Phase", "FASE 1", UDim2.new(1, -130, 0, 7), UDim2.fromOffset(114, 25), 14, Enum.Font.GothamBold, palette.Warning, Enum.TextXAlignment.Right)
local bossBarBack = Instance.new("Frame")
bossBarBack.Position = UDim2.fromOffset(16, 39)
bossBarBack.Size = UDim2.new(1, -32, 0, 20)
bossBarBack.BackgroundColor3 = Color3.fromRGB(47, 51, 62)
bossBarBack.BorderSizePixel = 0
bossBarBack.ClipsDescendants = true
bossBarBack.Parent = bossPanel
rounded(bossBarBack, 8)
local bossBarFill = Instance.new("Frame")
bossBarFill.Size = UDim2.fromScale(1, 1)
bossBarFill.BackgroundColor3 = palette.Success
bossBarFill.BorderSizePixel = 0
bossBarFill.Parent = bossBarBack
rounded(bossBarFill, 8)
local bossHealth = label(bossBarBack, "Health", "0 / 0", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 12, Enum.Font.GothamBold, palette.Text, Enum.TextXAlignment.Center)
bossHealth.ZIndex = 2
local bossWarning = label(bossPanel, "Warning", "ENTRE NA ARENA PARA INICIAR", UDim2.fromOffset(16, 67), UDim2.new(1, -32, 0, 25), 13, Enum.Font.GothamBold, palette.Warning, Enum.TextXAlignment.Center)

local partyPanel = panel("Party", UDim2.new(1, -12, 0, 12), UDim2.fromOffset(250, 154), Vector2.new(1, 0))
label(partyPanel, "Header", "EQUIPE", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 22), 12, Enum.Font.GothamBold, palette.Muted)
local partyRows = {}
for index = 1, 4 do
	local row = Instance.new("Frame")
	row.Name = "Player" .. index
	row.Position = UDim2.fromOffset(10, 28 + (index - 1) * 29)
	row.Size = UDim2.new(1, -20, 0, 26)
	row.BackgroundColor3 = palette.PanelSoft
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0
	row.Visible = false
	row.Parent = partyPanel
	rounded(row, 7)
	local name = label(row, "Name", "Jogador", UDim2.fromOffset(8, 0), UDim2.new(1, -88, 1, 0), 12, Enum.Font.GothamMedium)
	local state = label(row, "State", "ATIVO", UDim2.new(1, -82, 0, 0), UDim2.fromOffset(74, 26), 10, Enum.Font.GothamBold, palette.Success, Enum.TextXAlignment.Right)
	partyRows[index] = { Frame = row, Name = name, State = state }
end

local healthPanel = panel("Health", UDim2.new(0, 12, 1, -12), UDim2.fromOffset(224, 57), Vector2.new(0, 1))
local healthText = label(healthPanel, "Text", "VIDA  100 / 100", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 21), 13, Enum.Font.GothamBold)
local healthBack = Instance.new("Frame")
healthBack.Position = UDim2.fromOffset(12, 32)
healthBack.Size = UDim2.new(1, -24, 0, 12)
healthBack.BackgroundColor3 = Color3.fromRGB(49, 53, 64)
healthBack.BorderSizePixel = 0
healthBack.ClipsDescendants = true
healthBack.Parent = healthPanel
rounded(healthBack, 6)
local healthFill = Instance.new("Frame")
healthFill.Size = UDim2.fromScale(1, 1)
healthFill.BackgroundColor3 = palette.Success
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBack
rounded(healthFill, 6)

local rewardPanel = panel("Reward", UDim2.new(0.5, 0, 1, -14), UDim2.fromOffset(420, 82), Vector2.new(0.5, 1))
rewardPanel.Visible = false
local rewardTitle = label(rewardPanel, "Title", "RECOMPENSA DA RODADA", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 22), 14, Enum.Font.GothamBold, palette.Warning, Enum.TextXAlignment.Center)
local rewardStatus = label(rewardPanel, "Status", "CORE: DISPONÍVEL   •   BÔNUS: DISPONÍVEL", UDim2.fromOffset(12, 29), UDim2.new(1, -24, 0, 20), 12, Enum.Font.GothamMedium, palette.Text, Enum.TextXAlignment.Center)
local rewardTimer = label(rewardPanel, "Timer", "Abra os dois baús", UDim2.fromOffset(12, 52), UDim2.new(1, -24, 0, 20), 11, Enum.Font.GothamMedium, palette.Muted, Enum.TextXAlignment.Center)

local stateBanner = panel("StateBanner", UDim2.fromScale(0.5, 0.56), UDim2.fromOffset(440, 96), Vector2.new(0.5, 0.5))
stateBanner.Visible = false
stateBanner.BackgroundTransparency = 0.02
local stateTitle = label(stateBanner, "Title", "DERRUBADO", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 34), 24, Enum.Font.GothamBold, palette.Danger, Enum.TextXAlignment.Center)
local stateDetail = label(stateBanner, "Detail", "Um aliado pode reviver você.", UDim2.fromOffset(14, 45), UDim2.new(1, -28, 0, 34), 14, Enum.Font.GothamMedium, palette.Text, Enum.TextXAlignment.Center)

local waypointArrow = Instance.new("TextLabel")
waypointArrow.Name = "WaypointArrow"
waypointArrow.AnchorPoint = Vector2.new(0.5, 0.5)
waypointArrow.Size = UDim2.fromOffset(50, 50)
waypointArrow.BackgroundColor3 = palette.Panel
waypointArrow.BackgroundTransparency = 0.15
waypointArrow.BorderSizePixel = 0
waypointArrow.Text = "▲"
waypointArrow.TextColor3 = palette.Warning
waypointArrow.TextSize = 26
waypointArrow.Font = Enum.Font.GothamBold
waypointArrow.Visible = false
waypointArrow.Parent = gui
rounded(waypointArrow, 25)
stroked(waypointArrow, 0.35)

local scaleTargets = { resources, objectivePanel, bossPanel, partyPanel, healthPanel, rewardPanel, stateBanner }
for _, target in ipairs(scaleTargets) do
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = target
end

local currentObjective = {}
local currentBoss = { State = "Unavailable" }
local currentReward = { Active = false }
local lifeRecords = {}
local objectiveTween
local bossTween
local healthTween

local attackNames = {
	LeapSlam = "SALTO ESMAGADOR — SAIA DO CÍRCULO",
	GroundPulse = "IMPACTO PRÓXIMO — AFASTE-SE",
	Shockwave = "ONDA DE CHOQUE — FIQUE NO CENTRO",
	SummonSlimes = "REFORÇOS CHEGANDO",
}

local claimNames = {
	Available = "DISPONÍVEL",
	Granting = "ABRINDO",
	Saving = "SALVANDO",
	RetryPending = "REPETINDO",
	Claimed = "ABERTO",
}

local function tweenSize(target, ratio, currentTweenName)
	ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
	local tween = TweenService:Create(target, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
	})
	if currentTweenName == "Objective" then
		if objectiveTween then objectiveTween:Cancel() end
		objectiveTween = tween
	elseif currentTweenName == "Boss" then
		if bossTween then bossTween:Cancel() end
		bossTween = tween
	else
		if healthTween then healthTween:Cancel() end
		healthTween = tween
	end
	tween:Play()
end

local function workspaceObjectiveSnapshot()
	return {
		State = workspace:GetAttribute("DungeonObjectiveState") or "Inactive",
		Id = workspace:GetAttribute("DungeonObjectiveId"),
		Title = workspace:GetAttribute("DungeonObjectiveTitle"),
		Description = workspace:GetAttribute("DungeonObjectiveDescription"),
		RoundIndex = workspace:GetAttribute("DungeonObjectiveRoundIndex"),
		IslandIndex = workspace:GetAttribute("DungeonObjectiveIslandIndex"),
		GlobalIslandIndex = workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex"),
		Progress = workspace:GetAttribute("DungeonObjectiveProgress") or 0,
		Target = workspace:GetAttribute("DungeonObjectiveTarget") or 1,
		WaypointEscalated = workspace:GetAttribute("DungeonObjectiveWaypointEscalated") == true,
	}
end

local function workspaceBossSnapshot()
	local health = tonumber(workspace:GetAttribute("DungeonBossHealth")) or 0
	local maximum = math.max(1, tonumber(workspace:GetAttribute("DungeonBossMaxHealth")) or 1)
	return {
		State = workspace:GetAttribute("DungeonBossState") or "Unavailable",
		DisplayName = "Rei Slime Colossal",
		Health = health,
		MaxHealth = maximum,
		HealthRatio = health / maximum,
		Phase = workspace:GetAttribute("DungeonBossPhase") or 1,
		Attack = workspace:GetAttribute("DungeonBossAttack"),
		AttackEndsAt = workspace:GetAttribute("DungeonBossAttackEndsAt"),
	}
end

local function readNumberAttribute(instance, name, fallback)
	local value = instance:GetAttribute(name)
	return typeof(value) == "number" and value or fallback
end

local function confirmedCoins()
	local attribute = localPlayer:GetAttribute("Coins")
	if typeof(attribute) == "number" then
		return math.max(0, math.floor(attribute))
	end
	local leaderstats = localPlayer:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Coins")
	return value and math.max(0, value.Value) or 0
end

local function essenceAmount()
	for _, name in ipairs({ "SlimeEssence", "Essence" }) do
		local attribute = localPlayer:GetAttribute(name)
		if typeof(attribute) == "number" then
			return math.max(0, math.floor(attribute))
		end
		local leaderstats = localPlayer:FindFirstChild("leaderstats")
		local value = leaderstats and leaderstats:FindFirstChild(name)
		if value and value:IsA("ValueBase") then
			return math.max(0, math.floor(tonumber(value.Value) or 0))
		end
	end
	return 0
end

local function applyObjective(snapshot)
	currentObjective = type(snapshot) == "table" and snapshot or workspaceObjectiveSnapshot()
	local roundIndex = math.clamp(math.floor(tonumber(currentObjective.RoundIndex) or 1), 1, 3)
	local islandIndex = math.max(1, math.floor(tonumber(currentObjective.IslandIndex) or 1))
	local globalIndex = math.clamp(math.floor(tonumber(currentObjective.GlobalIslandIndex) or 1), 1, 12)
	routeLabel.Text = string.format("RODADA %d  •  ILHA %d  •  ROTA %d/12", roundIndex, islandIndex, globalIndex)
	objectiveTitle.Text = string.upper(tostring(currentObjective.Title or "PREPARANDO EXPEDIÇÃO"))
	objectiveDescription.Text = tostring(currentObjective.Description or "Aguarde a geração da rota.")
	local progress = math.max(0, tonumber(currentObjective.Progress) or 0)
	local target = math.max(1, tonumber(currentObjective.Target) or 1)
	objectiveProgress.Text = string.format("%d / %d", math.floor(progress), math.floor(target))
	tweenSize(objectiveBarFill, progress / target, "Objective")
end

local function applyBoss(snapshot)
	currentBoss = type(snapshot) == "table" and snapshot or workspaceBossSnapshot()
	local state = tostring(currentBoss.State or "Unavailable")
	local visible = state == "Ready" or state == "Activating" or state == "Active"
	bossPanel.Visible = visible
	objectivePanel.Visible = not visible
	if not visible then
		return
	end
	bossName.Text = string.upper(tostring(currentBoss.DisplayName or "REI SLIME COLOSSAL"))
	bossPhase.Text = string.format("FASE %d", math.max(1, math.floor(tonumber(currentBoss.Phase) or 1)))
	local health = math.max(0, math.floor(tonumber(currentBoss.Health) or 0))
	local maximum = math.max(1, math.floor(tonumber(currentBoss.MaxHealth) or 1))
	bossHealth.Text = string.format("%d / %d", health, maximum)
	tweenSize(bossBarFill, currentBoss.HealthRatio or health / maximum, "Boss")
	if state == "Ready" then
		bossWarning.Text = "ENTRE NA ARENA PARA INICIAR"
	elseif state == "Activating" then
		bossWarning.Text = "A ARENA FOI SELADA"
	else
		bossWarning.Text = attackNames[currentBoss.Attack] or "DERROTE O CHEFE"
	end
end

local function stateColor(state)
	if state == "Active" then return palette.Success end
	if state == "Downed" then return palette.Warning end
	if state == "Eliminated" then return palette.Danger end
	return palette.Muted
end

local function displayState(record, player)
	local state = tostring(record and record.State or player and player:GetAttribute("DungeonLifeState") or "Disconnected")
	if state == "Downed" then
		local expiresAt = tonumber(record and record.DownedExpiresAt or player and player:GetAttribute("DungeonDownedExpiresAt")) or 0
		return string.format("CAÍDO %ds", math.max(0, math.ceil(expiresAt - workspace:GetServerTimeNow()))), state
	elseif state == "Eliminated" then
		return "ESPECTADOR", state
	elseif state == "Disconnected" then
		return "AUSENTE", state
	end
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth > 0 then
		return string.format("%d%%", math.floor(humanoid.Health / humanoid.MaxHealth * 100 + 0.5)), "Active"
	end
	return "ATIVO", "Active"
end

local function updateParty()
	local entries = {}
	local seen = {}
	for userId, record in pairs(lifeRecords) do
		local numericId = tonumber(userId) or tonumber(record.UserId)
		if numericId and numericId > 0 then
			seen[numericId] = true
			table.insert(entries, { UserId = numericId, Record = record, Player = Players:GetPlayerByUserId(numericId) })
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local sameSession = localPlayer:GetAttribute("DungeonSessionId") == nil
			or player:GetAttribute("DungeonSessionId") == localPlayer:GetAttribute("DungeonSessionId")
		if sameSession and not seen[player.UserId] then
			table.insert(entries, { UserId = player.UserId, Player = player })
		end
	end
	table.sort(entries, function(left, right)
		if left.UserId == localPlayer.UserId then return true end
		if right.UserId == localPlayer.UserId then return false end
		return left.UserId < right.UserId
	end)
	for index, row in ipairs(partyRows) do
		local entry = entries[index]
		row.Frame.Visible = entry ~= nil
		if entry then
			local player = entry.Player
			row.Name.Text = player and player.DisplayName or ("Jogador " .. tostring(entry.UserId))
			local text, state = displayState(entry.Record, player)
			row.State.Text = text
			row.State.TextColor3 = stateColor(state)
		end
	end
end

local function applyLife(payload)
	if type(payload) == "table" and type(payload.Participants) == "table" then
		lifeRecords = payload.Participants
	end
	updateParty()
end

local function applyReward(payload)
	if type(payload) == "table" then
		currentReward = payload
	else
		currentReward.Active = workspace:GetAttribute("DungeonRewardIslandActive") == true
	end
	local active = currentReward.Active == true or workspace:GetAttribute("DungeonRewardIslandActive") == true
	rewardPanel.Visible = active
	if not active then
		return
	end
	local roundIndex = tonumber(currentReward.RoundIndex) or tonumber(workspace:GetAttribute("DungeonRewardIslandRound")) or 1
	rewardTitle.Text = string.format("RECOMPENSA DA RODADA %d", roundIndex)
	local coreState = currentReward.Core and currentReward.Core.State or "Available"
	local bonusState = currentReward.Bonus and currentReward.Bonus.State or "Available"
	rewardStatus.Text = string.format("CORE: %s   •   BÔNUS: %s", claimNames[coreState] or coreState, claimNames[bonusState] or bonusState)
end

local function updateResponsiveLayout()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local compact = viewport.X < 900
	local scaleValue = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.68, 1)
	for _, target in ipairs(scaleTargets) do
		local scale = target:FindFirstChild("ResponsiveScale")
		if scale then scale.Scale = scaleValue end
	end
	if compact then
		resources.Position = UDim2.fromOffset(8, 8)
		partyPanel.Position = UDim2.new(1, -8, 0, 8)
		objectivePanel.Position = UDim2.new(0.5, 0, 0, 112)
		bossPanel.Position = UDim2.new(0.5, 0, 0, 112)
		partyPanel.Size = UDim2.fromOffset(225, 154)
	else
		resources.Position = UDim2.fromOffset(12, 12)
		partyPanel.Position = UDim2.new(1, -12, 0, 12)
		objectivePanel.Position = UDim2.new(0.5, 0, 0, 12)
		bossPanel.Position = UDim2.new(0.5, 0, 0, 12)
		partyPanel.Size = UDim2.fromOffset(250, 154)
	end
end

local function updateHealth()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local health = humanoid and math.max(0, humanoid.Health) or 0
	local maximum = humanoid and math.max(1, humanoid.MaxHealth) or 100
	healthText.Text = string.format("VIDA  %d / %d", math.floor(health), math.floor(maximum))
	local ratio = health / maximum
	healthFill.BackgroundColor3 = ratio <= 0.3 and palette.Danger or ratio <= 0.6 and palette.Warning or palette.Success
	tweenSize(healthFill, ratio, "Health")
end

local function updateStateBanner()
	local phaseState = tostring(workspace:GetAttribute("DungeonPhaseState") or "")
	local lifeState = tostring(localPlayer:GetAttribute("DungeonLifeState") or "Active")
	local downed = lifeState == "Downed" or localPlayer:GetAttribute("IsDowned") == true
	local spectating = lifeState == "Eliminated" or localPlayer:GetAttribute("DungeonSpectating") == true
	local wipe = workspace:GetAttribute("DungeonWipePending") == true
	if downed then
		local expiresAt = tonumber(localPlayer:GetAttribute("DungeonDownedExpiresAt") or localPlayer:GetAttribute("DownedExpiresAt")) or 0
		stateBanner.Visible = true
		stateTitle.Text = string.format("DERRUBADO — %ds", math.max(0, math.ceil(expiresAt - workspace:GetServerTimeNow())))
		stateTitle.TextColor3 = palette.Danger
		stateDetail.Text = "Um aliado pode segurar o botão de revive perto de você."
	elseif spectating then
		stateBanner.Visible = true
		stateTitle.Text = "ESPECTANDO"
		stateTitle.TextColor3 = palette.Muted
		stateDetail.Text = "Você retornará gratuitamente na próxima ilha de recompensa."
	elseif wipe then
		stateBanner.Visible = true
		stateTitle.Text = "EQUIPE DERRUBADA"
		stateTitle.TextColor3 = palette.Warning
		stateDetail.Text = "Aguardando uma recuperação antes da derrota."
	elseif phaseState == "Victory" then
		stateBanner.Visible = true
		stateTitle.Text = "VITÓRIA"
		stateTitle.TextColor3 = palette.Success
		stateDetail.Text = "Recompensas sendo confirmadas."
	elseif phaseState == "Defeat" then
		stateBanner.Visible = true
		stateTitle.Text = "EXPEDIÇÃO ENCERRADA"
		stateTitle.TextColor3 = palette.Danger
		stateDetail.Text = "Preparando o retorno ao Lobby."
	else
		stateBanner.Visible = false
	end
end

local function updateWaypoint()
	local target = workspace:GetAttribute("DungeonObjectiveWaypointPosition")
	local escalated = currentObjective.WaypointEscalated == true
		or workspace:GetAttribute("DungeonObjectiveWaypointEscalated") == true
	local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if typeof(target) ~= "Vector3" or not root then
		waypointLabel.Text = "ALVO --m"
		waypointArrow.Visible = false
		return
	end
	local distance = math.floor((target - root.Position).Magnitude + 0.5)
	waypointLabel.Text = escalated and string.format("WAYPOINT ATIVO  •  %dm", distance) or string.format("ALVO  %dm", distance)
	waypointLabel.TextColor3 = escalated and palette.Warning or palette.Muted
	if not escalated then
		waypointArrow.Visible = false
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewportPoint, onScreen = camera:WorldToViewportPoint(target)
	if onScreen and viewportPoint.Z > 0 then
		waypointArrow.Visible = true
		waypointArrow.Rotation = 0
		waypointArrow.Position = UDim2.fromOffset(viewportPoint.X, math.max(155, viewportPoint.Y - 44))
	else
		local viewport = camera.ViewportSize
		local direction = camera.CFrame:VectorToObjectSpace((target - camera.CFrame.Position).Unit)
		local angle = math.atan2(direction.X, -direction.Z)
		local radiusX = math.max(80, viewport.X * 0.42)
		local radiusY = math.max(80, viewport.Y * 0.35)
		waypointArrow.Visible = true
		waypointArrow.Rotation = math.deg(angle)
		waypointArrow.Position = UDim2.fromOffset(
			viewport.X * 0.5 + math.sin(angle) * radiusX,
			viewport.Y * 0.52 - math.cos(angle) * radiusY
		)
	end
end

objectiveEvent.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.Action == "ObjectiveSnapshot" then
		applyObjective(payload.Objective)
	end
end)
rewardEvent.OnClientEvent:Connect(applyReward)
lifeEvent.OnClientEvent:Connect(applyLife)
bossEvent.OnClientEvent:Connect(applyBoss)
if coinRewardEvent and coinRewardEvent:IsA("RemoteEvent") then
	coinRewardEvent.OnClientEvent:Connect(function()
		pendingCoinsLabel.TextColor3 = palette.Success
	end)
end

Players.PlayerAdded:Connect(function()
	task.defer(updateParty)
end)
Players.PlayerRemoving:Connect(function()
	task.defer(updateParty)
end)

workspace:GetAttributeChangedSignal("DungeonObjectiveRevision"):Connect(function()
	applyObjective(workspaceObjectiveSnapshot())
end)
workspace:GetAttributeChangedSignal("DungeonBossState"):Connect(function()
	applyBoss(workspaceBossSnapshot())
end)
workspace:GetAttributeChangedSignal("DungeonRewardIslandActive"):Connect(function()
	applyReward(nil)
end)
workspace:GetAttributeChangedSignal("DungeonPhaseState"):Connect(updateStateBanner)
workspace:GetAttributeChangedSignal("DungeonWipePending"):Connect(updateStateBanner)
localPlayer:GetAttributeChangedSignal("DungeonLifeState"):Connect(updateStateBanner)
localPlayer:GetAttributeChangedSignal("DungeonSpectating"):Connect(updateStateBanner)
localPlayer:GetAttributeChangedSignal("IsDowned"):Connect(updateStateBanner)

localPlayer.CharacterAdded:Connect(function()
	task.defer(updateHealth)
end)

local viewportConnection
local function bindViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end
	updateResponsiveLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
bindViewport()

local nextSlowUpdate = 0
RunService.RenderStepped:Connect(function()
	updateWaypoint()
	updateStateBanner()
	local nowClock = os.clock()
	if nowClock < nextSlowUpdate then
		return
	end
	nextSlowUpdate = nowClock + 0.2
	coinsLabel.Text = string.format("MOEDAS  %d", confirmedCoins())
	pendingCoinsLabel.Text = string.format("PENDENTES  +%d", math.max(0, math.floor(readNumberAttribute(localPlayer, "PendingRoundCoins", 0))))
	essenceLabel.Text = string.format("ESSÊNCIA  %d", essenceAmount())
	updateHealth()
	updateParty()
	if rewardPanel.Visible then
		local autoAt = tonumber(currentReward.AutoResolveAt) or tonumber(workspace:GetAttribute("DungeonRewardIslandAutoResolveAt")) or 0
		local remaining = math.max(0, math.ceil(autoAt - workspace:GetServerTimeNow()))
		rewardTimer.Text = remaining > 0 and string.format("Abra os dois baús  •  automático em %ds", remaining) or "Confirmando recompensas..."
	end
end)

localPlayer:SetAttribute("DungeonUnifiedHUDReady", true)
applyObjective(workspaceObjectiveSnapshot())
applyBoss(workspaceBossSnapshot())
applyReward(nil)
updateResponsiveLayout()
updateParty()
updateHealth()
updateStateBanner()
