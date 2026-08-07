-- HUD-05 — navegação, rounds, bifurcações, opcionais, RoundExit e checkpoint
-- Depende das Tasks 14-18/24 e HUD-01..04.
-- A progressão permanece 100% autoritativa no servidor; esta camada só apresenta dados.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "CrystalCelestialRouteNavigationV1"
local HUD_NAME = "DungeonUnifiedHUD"
local UPDATE_INTERVAL = 0.10
local EXIT_REFRESH_INTERVAL = 0.35
local MAX_EXIT_GROUP_DISTANCE = 145
local ROUND_LENGTHS = { 3, 4, 5 }
local ROUND_EXIT_GLOBALS = { [3] = 1, [7] = 2, [12] = 3 }

local COLORS = {
	Glass = Color3.fromRGB(13, 27, 42),
	GlassRaised = Color3.fromRGB(22, 48, 65),
	Text = Color3.fromRGB(239, 247, 252),
	Muted = Color3.fromRGB(145, 174, 197),
	Cyan = Color3.fromRGB(107, 225, 255),
	CyanSoft = Color3.fromRGB(176, 241, 255),
	Gold = Color3.fromRGB(231, 194, 104),
	GoldSoft = Color3.fromRGB(255, 224, 143),
	Green = Color3.fromRGB(99, 235, 160),
	Purple = Color3.fromRGB(193, 139, 255),
	Red = Color3.fromRGB(255, 108, 119),
	Locked = Color3.fromRGB(115, 127, 145),
}

local gui = playerGui:WaitForChild(HUD_NAME, 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-05] HUD-01 não encontrado.")
	return
end
local root = gui:WaitForChild("Root")

local old = root:FindFirstChild("RouteOverview")
if old then old:Destroy() end

local routePanel = Instance.new("Frame")
routePanel.Name = "RouteOverview"
routePanel.AnchorPoint = Vector2.new(0.5, 0)
routePanel.Position = UDim2.new(0.5, 0, 0, 203)
routePanel.Size = UDim2.fromOffset(720, 96)
routePanel.BackgroundColor3 = COLORS.Glass
routePanel.BackgroundTransparency = 0.10
routePanel.BorderSizePixel = 0
routePanel.ZIndex = 27
routePanel.Parent = root
Instance.new("UICorner", routePanel).CornerRadius = UDim.new(0, 16)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.Gold
panelStroke.Transparency = 0.35
panelStroke.Thickness = 1.2
panelStroke.Parent = routePanel

local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 52, 69)),
	ColorSequenceKeypoint.new(0.5, COLORS.Glass),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 25, 55)),
})
panelGradient.Rotation = 8
panelGradient.Parent = routePanel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(14, 4)
title.Size = UDim2.fromOffset(210, 20)
title.BackgroundTransparency = 1
title.Text = "MAPA DA EXPEDIÇÃO"
title.TextColor3 = COLORS.GoldSoft
title.Font = Enum.Font.GothamBold
title.TextSize = 10
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 28
title.Parent = routePanel

local summary = Instance.new("TextLabel")
summary.AnchorPoint = Vector2.new(1, 0)
summary.Position = UDim2.new(1, -12, 0, 4)
summary.Size = UDim2.fromOffset(360, 20)
summary.BackgroundTransparency = 1
summary.Text = "12 OBJETIVOS • 30 ILHAS • 18 ILHAS DE ROTA"
summary.TextColor3 = COLORS.Muted
summary.Font = Enum.Font.GothamMedium
summary.TextSize = 9
summary.TextXAlignment = Enum.TextXAlignment.Right
summary.ZIndex = 28
summary.Parent = routePanel

local track = Instance.new("Frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(14, 27)
track.Size = UDim2.new(1, -28, 0, 39)
track.BackgroundTransparency = 1
track.ZIndex = 28
track.Parent = routePanel

local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.Position = UDim2.fromOffset(14, 68)
footer.Size = UDim2.new(1, -28, 0, 22)
footer.BackgroundTransparency = 1
footer.ZIndex = 28
footer.Parent = routePanel

local routeState = Instance.new("TextLabel")
routeState.Size = UDim2.new(0.57, 0, 1, 0)
routeState.BackgroundTransparency = 1
routeState.Text = "ROTA SENDO PREPARADA"
routeState.TextColor3 = COLORS.CyanSoft
routeState.Font = Enum.Font.GothamBold
routeState.TextSize = 9
routeState.TextXAlignment = Enum.TextXAlignment.Left
routeState.TextTruncate = Enum.TextTruncate.AtEnd
routeState.ZIndex = 29
routeState.Parent = footer

local checkpointState = Instance.new("TextLabel")
checkpointState.AnchorPoint = Vector2.new(1, 0)
checkpointState.Position = UDim2.new(1, 0, 0, 0)
checkpointState.Size = UDim2.new(0.42, 0, 1, 0)
checkpointState.BackgroundTransparency = 1
checkpointState.Text = "CHECKPOINT INICIAL"
checkpointState.TextColor3 = COLORS.Gold
checkpointState.Font = Enum.Font.GothamBold
checkpointState.TextSize = 9
checkpointState.TextXAlignment = Enum.TextXAlignment.Right
checkpointState.TextTruncate = Enum.TextTruncate.AtEnd
checkpointState.ZIndex = 29
checkpointState.Parent = footer

local optionalCard = Instance.new("Frame")
optionalCard.Name = "OptionalRouteCard"
optionalCard.AnchorPoint = Vector2.new(0.5, 0)
optionalCard.Position = UDim2.new(0.5, 0, 0, 304)
optionalCard.Size = UDim2.fromOffset(490, 48)
optionalCard.BackgroundColor3 = Color3.fromRGB(31, 24, 51)
optionalCard.BackgroundTransparency = 0.08
optionalCard.BorderSizePixel = 0
optionalCard.Visible = false
optionalCard.ZIndex = 30
optionalCard.Parent = root
Instance.new("UICorner", optionalCard).CornerRadius = UDim.new(0, 13)
local optionalStroke = Instance.new("UIStroke")
optionalStroke.Color = COLORS.Purple
optionalStroke.Transparency = 0.22
optionalStroke.Thickness = 1.2
optionalStroke.Parent = optionalCard

local optionalIcon = Instance.new("TextLabel")
optionalIcon.Position = UDim2.fromOffset(8, 5)
optionalIcon.Size = UDim2.fromOffset(38, 38)
optionalIcon.BackgroundTransparency = 1
optionalIcon.Text = "✦"
optionalIcon.TextColor3 = COLORS.Purple
optionalIcon.Font = Enum.Font.GothamBlack
optionalIcon.TextSize = 20
optionalIcon.ZIndex = 31
optionalIcon.Parent = optionalCard

local optionalTitle = Instance.new("TextLabel")
optionalTitle.Position = UDim2.fromOffset(48, 5)
optionalTitle.Size = UDim2.new(1, -150, 0, 19)
optionalTitle.BackgroundTransparency = 1
optionalTitle.Text = "ROTA OPCIONAL"
optionalTitle.TextColor3 = COLORS.Text
optionalTitle.Font = Enum.Font.GothamBold
optionalTitle.TextSize = 10
optionalTitle.TextXAlignment = Enum.TextXAlignment.Left
optionalTitle.ZIndex = 31
optionalTitle.Parent = optionalCard

local optionalDetail = Instance.new("TextLabel")
optionalDetail.Position = UDim2.fromOffset(48, 24)
optionalDetail.Size = UDim2.new(1, -150, 0, 18)
optionalDetail.BackgroundTransparency = 1
optionalDetail.Text = ""
optionalDetail.TextColor3 = COLORS.Muted
optionalDetail.Font = Enum.Font.GothamMedium
optionalDetail.TextSize = 9
optionalDetail.TextXAlignment = Enum.TextXAlignment.Left
optionalDetail.TextTruncate = Enum.TextTruncate.AtEnd
optionalDetail.ZIndex = 31
optionalDetail.Parent = optionalCard

local optionalReward = Instance.new("TextLabel")
optionalReward.AnchorPoint = Vector2.new(1, 0.5)
optionalReward.Position = UDim2.new(1, -9, 0.5, 0)
optionalReward.Size = UDim2.fromOffset(110, 30)
optionalReward.BackgroundColor3 = Color3.fromRGB(23, 48, 60)
optionalReward.BackgroundTransparency = 0.14
optionalReward.BorderSizePixel = 0
optionalReward.Text = ""
optionalReward.TextColor3 = COLORS.CyanSoft
optionalReward.Font = Enum.Font.GothamBold
optionalReward.TextSize = 9
optionalReward.ZIndex = 31
optionalReward.Parent = optionalCard
Instance.new("UICorner", optionalReward).CornerRadius = UDim.new(0, 9)

local checkpointToast = Instance.new("TextLabel")
checkpointToast.Name = "CheckpointToast"
checkpointToast.AnchorPoint = Vector2.new(0.5, 0.5)
checkpointToast.Position = UDim2.fromScale(0.5, 0.36)
checkpointToast.Size = UDim2.fromOffset(390, 54)
checkpointToast.BackgroundColor3 = Color3.fromRGB(23, 48, 58)
checkpointToast.BackgroundTransparency = 0.06
checkpointToast.BorderSizePixel = 0
checkpointToast.Text = "◆ CHECKPOINT SALVO"
checkpointToast.TextColor3 = COLORS.GoldSoft
checkpointToast.Font = Enum.Font.GothamBlack
checkpointToast.TextSize = 15
checkpointToast.Visible = false
checkpointToast.ZIndex = 90
checkpointToast.Parent = root
Instance.new("UICorner", checkpointToast).CornerRadius = UDim.new(0, 14)
local checkpointToastStroke = Instance.new("UIStroke")
checkpointToastStroke.Color = COLORS.Gold
checkpointToastStroke.Transparency = 0.15
checkpointToastStroke.Thickness = 1.5
checkpointToastStroke.Parent = checkpointToast

local nodes = {}
local lines = {}
local totalMandatory = 12
local startX = 10
local endX = 682
local spacing = (endX - startX) / (totalMandatory - 1)

for index = 1, totalMandatory do
	if index > 1 then
		local connection = Instance.new("Frame")
		connection.Name = "Connection" .. index
		connection.Position = UDim2.fromOffset(startX + (index - 2) * spacing + 13, 18)
		connection.Size = UDim2.fromOffset(math.max(4, spacing - 24), 3)
		connection.BackgroundColor3 = COLORS.Locked
		connection.BackgroundTransparency = 0.32
		connection.BorderSizePixel = 0
		connection.ZIndex = 28
		connection.Parent = track
		lines[index] = connection
	end

	local node = Instance.new("TextLabel")
	node.Name = "Node" .. index
	node.AnchorPoint = Vector2.new(0.5, 0.5)
	node.Position = UDim2.fromOffset(startX + (index - 1) * spacing + 12, 19)
	node.Size = UDim2.fromOffset(28, 28)
	node.BackgroundColor3 = COLORS.GlassRaised
	node.BorderSizePixel = 0
	node.Text = tostring(index)
	node.TextColor3 = COLORS.Muted
	node.Font = Enum.Font.GothamBold
	node.TextSize = 9
	node.ZIndex = 29
	node.Parent = track
	Instance.new("UICorner", node).CornerRadius = UDim.new(1, 0)
	local nodeStroke = Instance.new("UIStroke")
	nodeStroke.Name = "Stroke"
	nodeStroke.Color = ROUND_EXIT_GLOBALS[index] and COLORS.Gold or COLORS.Cyan
	nodeStroke.Transparency = 0.55
	nodeStroke.Thickness = ROUND_EXIT_GLOBALS[index] and 1.8 or 1.1
	nodeStroke.Parent = node
	if ROUND_EXIT_GLOBALS[index] then
		node.Text = "◆"
	end
	nodes[index] = node
end

-- Divisores de round.
for _, globalIndex in ipairs({ 3, 7 }) do
	local x = startX + (globalIndex - 0.5) * spacing + 12
	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromOffset(x, 0)
	divider.Size = UDim2.fromOffset(1, 38)
	divider.BackgroundColor3 = COLORS.Gold
	divider.BackgroundTransparency = 0.64
	divider.BorderSizePixel = 0
	divider.ZIndex = 28
	divider.Parent = track
end

local roundLabels = {
	{ Text = "R1", Start = 1, Finish = 3 },
	{ Text = "R2", Start = 4, Finish = 7 },
	{ Text = "R3", Start = 8, Finish = 12 },
}
for _, info in ipairs(roundLabels) do
	local centerIndex = (info.Start + info.Finish) / 2
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(startX + (centerIndex - 1) * spacing - 18, 29)
	label.Size = UDim2.fromOffset(48, 10)
	label.BackgroundTransparency = 1
	label.Text = info.Text
	label.TextColor3 = COLORS.Muted
	label.Font = Enum.Font.GothamBold
	label.TextSize = 7
	label.ZIndex = 29
	label.Parent = track
end

local markerFolder = playerGui:FindFirstChild("DungeonRouteWorldMarkers")
if markerFolder then markerFolder:Destroy() end
markerFolder = Instance.new("Folder")
markerFolder.Name = "DungeonRouteWorldMarkers"
markerFolder.Parent = playerGui

local knownExitMarkers = setmetatable({}, { __mode = "k" })
local activeBillboards = {}
local lastExitRefresh = 0
local lastCheckpointSerial = tonumber(player:GetAttribute("DungeonCheckpointSerial"))
	or tonumber(workspace:GetAttribute("DungeonCheckpointSerial"))
	or 0
local checkpointToastSerial = 0
local optionalEntryGlobal
local lastOptionalEntryAt = tonumber(player:GetAttribute("DungeonOptionalLastEnteredAt")) or 0

local PROFILE_NAMES = {
	SupplyCache = "CACHE DE SUPRIMENTOS",
	AmbushCache = "EMBOSCADA DO CÉU",
	EliteCache = "DESAFIO DE ELITE",
}

local PROFILE_DETAILS = {
	SupplyCache = "Sem combate obrigatório • suprimentos pessoais",
	AmbushCache = "Emboscada compartilhada • recompensa pessoal",
	EliteCache = "Elite + reforços • recompensa superior",
}

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function currentGlobalIndex()
	return math.clamp(math.floor(tonumber(player:GetAttribute("CurrentGlobalIslandIndex")
		or workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
		or 1) or 1), 1, 12)
end

local function roundForGlobal(index)
	if index <= 3 then return 1 end
	if index <= 7 then return 2 end
	return 3
end

local function roundIslandIndex(index)
	if index <= 3 then return index end
	if index <= 7 then return index - 3 end
	return index - 7
end

local function clearBillboards()
	for _, billboard in ipairs(activeBillboards) do
		if billboard.Parent then billboard:Destroy() end
	end
	table.clear(activeBillboards)
end

local function registerExitMarker(instance)
	if instance:IsA("BasePart") and instance:GetAttribute("ConnectionTargetKey") ~= nil then
		knownExitMarkers[instance] = true
	end
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	registerExitMarker(descendant)
end
workspace.DescendantAdded:Connect(function(instance)
	registerExitMarker(instance)
	if instance:IsA("BasePart") then
		task.delay(0.1, function()
			if instance.Parent then registerExitMarker(instance) end
		end)
	end
end)
workspace.DescendantRemoving:Connect(function(instance)
	knownExitMarkers[instance] = nil
end)

local function currentExitGroup()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return {} end

	local groups = {}
	for marker in pairs(knownExitMarkers) do
		if marker.Parent then
			local sourceKey = tostring(marker:GetAttribute("ConnectionSourceKey") or "")
			local distance = (marker.Position - rootPart.Position).Magnitude
			if sourceKey ~= "" and distance <= MAX_EXIT_GROUP_DISTANCE then
				local group = groups[sourceKey]
				if not group then
					group = { Markers = {}, Distance = distance }
					groups[sourceKey] = group
				end
				table.insert(group.Markers, marker)
				group.Distance = math.min(group.Distance, distance)
			end
		end
	end

	local best
	for _, group in pairs(groups) do
		if not best or group.Distance < best.Distance then
			best = group
		end
	end
	if not best then return {} end
	table.sort(best.Markers, function(left, right)
		return (tonumber(left:GetAttribute("ConnectionIndex")) or 1)
			< (tonumber(right:GetAttribute("ConnectionIndex")) or 1)
	end)
	return best.Markers
end

local function makeExitBillboard(marker, index, count)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DungeonRouteExitMarker"
	billboard.Adornee = marker
	billboard.Size = UDim2.fromOffset(168, 58)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 180
	billboard.LightInfluence = 0
	billboard.Parent = markerFolder

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = COLORS.Glass
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Parent = billboard
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = COLORS.Cyan
	cardStroke.Transparency = 0.20
	cardStroke.Thickness = 1.2
	cardStroke.Parent = card

	local glyph = Instance.new("TextLabel")
	glyph.Position = UDim2.fromOffset(7, 6)
	glyph.Size = UDim2.fromOffset(32, 32)
	glyph.BackgroundTransparency = 1
	glyph.Text = "◆"
	glyph.TextColor3 = COLORS.Cyan
	glyph.Font = Enum.Font.GothamBlack
	glyph.TextSize = 19
	glyph.Parent = card

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(40, 5)
	label.Size = UDim2.new(1, -46, 0, 21)
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.Text
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = card

	local detail = Instance.new("TextLabel")
	detail.Position = UDim2.fromOffset(40, 26)
	detail.Size = UDim2.new(1, -46, 0, 20)
	detail.BackgroundTransparency = 1
	detail.TextColor3 = COLORS.Muted
	detail.Font = Enum.Font.GothamMedium
	detail.TextSize = 8
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.Parent = card

	local locked = workspace:GetAttribute("DungeonObjectiveExitLocked") == true
	local globalIndex = currentGlobalIndex()
	if locked then
		label.Text = "ROTA BLOQUEADA"
		detail.Text = "Conclua o objetivo atual"
		glyph.Text = "◇"
		glyph.TextColor3 = COLORS.Locked
		cardStroke.Color = COLORS.Locked
	elseif count >= 2 then
		local branchId = tostring(marker:GetAttribute("ConnectionBranchId") or "")
		local suffix = string.match(branchId, "_([AB])$") or string.char(64 + index)
		label.Text = "CAMINHO " .. suffix
		detail.Text = "Rota alternativa • converge adiante"
		glyph.TextColor3 = index == 1 and COLORS.Cyan or COLORS.Purple
		cardStroke.Color = glyph.TextColor3
	elseif ROUND_EXIT_GLOBALS[globalIndex] then
		if globalIndex == 12 then
			label.Text = "CAMINHO DO BOSS"
			detail.Text = "Arena final da fase"
			glyph.TextColor3 = COLORS.Red
			cardStroke.Color = COLORS.Red
		else
			label.Text = "PRÓXIMO ROUND"
			detail.Text = "Checkpoint confirmado para avançar"
			glyph.TextColor3 = COLORS.Gold
			cardStroke.Color = COLORS.Gold
		end
	else
		label.Text = "PRÓXIMA ILHA"
		detail.Text = "Continue a expedição"
	end

	table.insert(activeBillboards, billboard)
end

local function refreshExitMarkers()
	clearBillboards()
	local markers = currentExitGroup()
	for index, marker in ipairs(markers) do
		makeExitBillboard(marker, index, #markers)
	end
	player:SetAttribute("DungeonHUDVisibleExitCount", #markers)
end

local function refreshOptionalCard()
	local enteredAt = tonumber(player:GetAttribute("DungeonOptionalLastEnteredAt")) or 0
	local profile = tostring(player:GetAttribute("DungeonCurrentOptionalProfile") or "")
	local key = tostring(player:GetAttribute("DungeonCurrentOptionalIslandKey") or "")
	local globalIndex = currentGlobalIndex()

	if enteredAt > lastOptionalEntryAt then
		lastOptionalEntryAt = enteredAt
		optionalEntryGlobal = globalIndex
	elseif optionalEntryGlobal == nil and enteredAt > 0 and profile ~= "" then
		optionalEntryGlobal = globalIndex
	end

	local active = profile ~= ""
		and key ~= ""
		and optionalEntryGlobal == globalIndex

	optionalCard.Visible = active
	if not active then return end

	optionalTitle.Text = PROFILE_NAMES[profile] or "ROTA ALTERNATIVA"
	optionalDetail.Text = PROFILE_DETAILS[profile] or "Conteúdo adicional da rota"
	local rewardAvailable = player:GetAttribute("DungeonOptionalRewardAvailable") == true
	if rewardAvailable then
		optionalReward.Text = "RECOMPENSA PRONTA"
		optionalReward.TextColor3 = COLORS.GoldSoft
		optionalStroke.Color = COLORS.Gold
	else
		optionalReward.Text = "EXPLORANDO"
		optionalReward.TextColor3 = COLORS.CyanSoft
		optionalStroke.Color = COLORS.Purple
	end
end

local function refreshNodes()
	local current = currentGlobalIndex()
	local committedRound = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("DungeonCheckpointCommittedRound")
			or workspace:GetAttribute("DungeonCheckpointCommittedRound")
			or 0) or 0)
	)
	local highestCompleted = math.max(
		committedRound,
		math.floor(tonumber(workspace:GetAttribute("DungeonHighestCompletedRound") or 0) or 0)
	)

	for index, node in ipairs(nodes) do
		local round = roundForGlobal(index)
		local completed = round <= highestCompleted
			or index < current
		local isCurrent = index == current
		local future = index > current and not completed
		local nodeStroke = node:FindFirstChild("Stroke")

		if completed then
			node.BackgroundColor3 = Color3.fromRGB(30, 83, 69)
			node.TextColor3 = ROUND_EXIT_GLOBALS[index] and COLORS.GoldSoft or COLORS.Green
			if nodeStroke then
				nodeStroke.Color = ROUND_EXIT_GLOBALS[index] and COLORS.Gold or COLORS.Green
				nodeStroke.Transparency = 0.12
			end
		elseif isCurrent then
			node.BackgroundColor3 = Color3.fromRGB(26, 73, 88)
			node.TextColor3 = ROUND_EXIT_GLOBALS[index] and COLORS.GoldSoft or COLORS.CyanSoft
			if nodeStroke then
				nodeStroke.Color = ROUND_EXIT_GLOBALS[index] and COLORS.Gold or COLORS.Cyan
				nodeStroke.Transparency = 0.02
				nodeStroke.Thickness = 2
			end
		elseif future then
			node.BackgroundColor3 = Color3.fromRGB(27, 38, 51)
			node.TextColor3 = COLORS.Locked
			if nodeStroke then
				nodeStroke.Transparency = 0.62
				nodeStroke.Thickness = ROUND_EXIT_GLOBALS[index] and 1.7 or 1
			end
		end

		if index > 1 and lines[index] then
			lines[index].BackgroundColor3 = index <= current and COLORS.Green or COLORS.Locked
			lines[index].BackgroundTransparency = index <= current and 0.18 or 0.58
		end
	end

	local physical = math.max(1, math.floor(tonumber(workspace:GetAttribute("DungeonPhysicalIslandCount")) or 30))
	local optionalCount = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonOptionalIslandCount")) or 18))
	local mandatory = math.max(1, math.floor(tonumber(workspace:GetAttribute("DungeonRouteIslandCount")) or 12))
	summary.Text = string.format("%d OBJETIVOS • %d ILHAS • %d ILHAS DE ROTA", mandatory, physical, optionalCount)

	local round = tonumber(workspace:GetAttribute("DungeonCurrentRoundIndex")) or roundForGlobal(current)
	local island = tonumber(workspace:GetAttribute("DungeonObjectiveIslandIndex")) or roundIslandIndex(current)
	local isRoundExit = workspace:GetAttribute("DungeonCurrentIslandIsRoundExit") == true
	local committed = workspace:GetAttribute("DungeonCurrentRoundExitCommitted") == true
	local rewardPendingRound = tonumber(workspace:GetAttribute("DungeonRewardPendingRound"))

	if isRoundExit then
		if committed then
			routeState.Text = string.format("ROUND %d • SAÍDA CONFIRMADA • CAMINHO LIBERADO", round)
			routeState.TextColor3 = COLORS.Green
		elseif rewardPendingRound == round then
			routeState.Text = string.format("ROUND %d • RECOMPENSA PENDENTE • CONFIRME PARA SALVAR", round)
			routeState.TextColor3 = COLORS.GoldSoft
		else
			routeState.Text = string.format("ROUND %d • ROUND EXIT • CONCLUA O OBJETIVO", round)
			routeState.TextColor3 = COLORS.Gold
		end
	else
		routeState.Text = string.format(
			"ROUND %d • OBJETIVO %d/%d • PROGRESSO GERAL %d/12",
			round,
			island,
			ROUND_LENGTHS[math.clamp(round, 1, 3)] or 1,
			current
		)
		routeState.TextColor3 = COLORS.CyanSoft
	end

	if committedRound > 0 then
		checkpointState.Text = string.format("◆ CHECKPOINT SALVO • ROUND %d", committedRound)
		checkpointState.TextColor3 = COLORS.GoldSoft
	else
		checkpointState.Text = "◇ CHECKPOINT INICIAL"
		checkpointState.TextColor3 = COLORS.Muted
	end
end

local function showCheckpointToast(serial)
	checkpointToastSerial += 1
	local toastSerial = checkpointToastSerial
	local committedRound = math.max(0, math.floor(tonumber(
		player:GetAttribute("DungeonCheckpointCommittedRound")
			or workspace:GetAttribute("DungeonCheckpointCommittedRound")
			or 0
	) or 0))
	checkpointToast.Text = committedRound > 0
		and string.format("◆ CHECKPOINT SALVO — ROUND %d", committedRound)
		or "◆ CHECKPOINT INICIAL DEFINIDO"
	checkpointToast.Visible = true
	checkpointToast.TextTransparency = 0
	checkpointToast.BackgroundTransparency = 0.06
	checkpointToast.Position = UDim2.fromScale(0.5, 0.33)
	TweenService:Create(
		checkpointToast,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.36) }
	):Play()

	task.delay(2.0, function()
		if checkpointToastSerial ~= toastSerial then return end
		local tween = TweenService:Create(checkpointToast, TweenInfo.new(0.25), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		if checkpointToastSerial == toastSerial then
			checkpointToast.Visible = false
		end
	end)
	player:SetAttribute("DungeonHUDLastCheckpointSerialShown", serial)
end

local function refreshCheckpointSerial()
	local serial = tonumber(player:GetAttribute("DungeonCheckpointSerial"))
		or tonumber(workspace:GetAttribute("DungeonCheckpointSerial"))
		or 0
	if serial > lastCheckpointSerial then
		lastCheckpointSerial = serial
		showCheckpointToast(serial)
	end
end

local function refreshVisibility()
	local bossState = tostring(workspace:GetAttribute("DungeonBossState") or "Unavailable")
	local resultVisible = playerGui:FindFirstChild("DungeonResultUI")
		and playerGui.DungeonResultUI:IsA("ScreenGui")
		and playerGui.DungeonResultUI.Enabled
	local hide = bossState == "Active" or bossState == "Activating" or resultVisible
	routePanel.Visible = not hide
	if hide then
		optionalCard.Visible = false
	end
end

for _, attribute in ipairs({
	"CurrentGlobalIslandIndex",
	"DungeonCheckpointCommittedRound",
	"DungeonCheckpointSerial",
	"DungeonCurrentOptionalProfile",
	"DungeonCurrentOptionalIslandKey",
	"DungeonOptionalRewardAvailable",
	"DungeonOptionalLastEnteredAt",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		refreshNodes()
		refreshOptionalCard()
		refreshCheckpointSerial()
	end)
end

for _, attribute in ipairs({
	"DungeonRouteIslandCount",
	"DungeonPhysicalIslandCount",
	"DungeonOptionalIslandCount",
	"DungeonCurrentRoundIndex",
	"DungeonHighestCompletedRound",
	"DungeonRewardPendingRound",
	"DungeonCurrentIslandIsRoundExit",
	"DungeonCurrentRoundExitCommitted",
	"DungeonObjectiveIslandIndex",
	"DungeonObjectiveExitLocked",
	"DungeonCheckpointCommittedRound",
	"DungeonCheckpointSerial",
	"DungeonBossState",
}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(function()
		refreshNodes()
		refreshCheckpointSerial()
	end)
end

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	refreshNodes()
	refreshOptionalCard()
	refreshCheckpointSerial()
	refreshVisibility()

	if clock - lastExitRefresh >= EXIT_REFRESH_INTERVAL then
		lastExitRefresh = clock
		refreshExitMarkers()
	end
end)

gui:SetAttribute("RouteNavigationVersion", VERSION)
player:SetAttribute("DungeonHUDRouteNavigationReady", true)
player:SetAttribute("DungeonHUDRouteNavigationVersion", VERSION)
workspace:SetAttribute("DungeonHUDRouteNavigationReady", true)
workspace:SetAttribute("DungeonHUDRouteNavigationPolicy", "BranchedRoundsWorldExitMarkersV1")

refreshNodes()
refreshOptionalCard()
refreshCheckpointSerial()
refreshExitMarkers()
refreshVisibility()
