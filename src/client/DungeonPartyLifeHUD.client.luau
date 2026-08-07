-- HUD-06 — party, aliados derrubados, revive e espectador
-- Enriquece o painel Party do HUD-01 sem decidir estados de vida no cliente.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("DungeonUnifiedHUD", 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-06] DungeonUnifiedHUD não encontrado.")
	return
end

local VERSION = "CrystalCelestialPartyLifeV1"
local root = gui:WaitForChild("Root")
local partyPanel = root:WaitForChild("Party")
local UPDATE_INTERVAL = 0.08

local COLORS = {
	Text = Color3.fromRGB(239, 247, 252),
	Muted = Color3.fromRGB(147, 176, 199),
	Cyan = Color3.fromRGB(109, 225, 255),
	CyanSoft = Color3.fromRGB(183, 243, 255),
	Gold = Color3.fromRGB(233, 196, 104),
	Green = Color3.fromRGB(99, 236, 161),
	Orange = Color3.fromRGB(255, 184, 92),
	Red = Color3.fromRGB(255, 105, 117),
	Purple = Color3.fromRGB(198, 143, 255),
	Glass = Color3.fromRGB(13, 27, 42),
	GlassRaised = Color3.fromRGB(23, 49, 65),
}

local function serverTime()
	return workspace:GetServerTimeNow()
end

-- A GUI antiga continua executando sua limpeza de ragdoll, porém sem duplicar o visual.
local function suppressLegacyDownedUI(child)
	if child:IsA("ScreenGui") and child.Name == "DownedUI" then
		child.Enabled = false
		child:SetAttribute("VisualSuppressedByHUD06", true)
	end
end
for _, child in ipairs(playerGui:GetChildren()) do
	suppressLegacyDownedUI(child)
end
playerGui.ChildAdded:Connect(suppressLegacyDownedUI)

-- Enriquece as quatro linhas já existentes do HUD-01.
local rows = {}
for index = 1, 4 do
	local row = partyPanel:WaitForChild("Member" .. index)
	local distance = row:FindFirstChild("Distance")
	if not distance then
		distance = Instance.new("TextLabel")
		distance.Name = "Distance"
		distance.AnchorPoint = Vector2.new(1, 1)
		distance.Position = UDim2.new(1, -7, 1, -3)
		distance.Size = UDim2.fromOffset(58, 13)
		distance.BackgroundTransparency = 1
		distance.Text = "--m"
		distance.TextColor3 = COLORS.Muted
		distance.Font = Enum.Font.GothamMedium
		distance.TextSize = 8
		distance.TextXAlignment = Enum.TextXAlignment.Right
		distance.ZIndex = row.ZIndex + 4
		distance.Parent = row
	end

	local downedTimer = row:FindFirstChild("DownedTimer")
	if not downedTimer then
		downedTimer = Instance.new("TextLabel")
		downedTimer.Name = "DownedTimer"
		downedTimer.AnchorPoint = Vector2.new(1, 0)
		downedTimer.Position = UDim2.new(1, -7, 0, 20)
		downedTimer.Size = UDim2.fromOffset(72, 15)
		downedTimer.BackgroundTransparency = 1
		downedTimer.Text = ""
		downedTimer.TextColor3 = COLORS.Red
		downedTimer.Font = Enum.Font.GothamBold
		downedTimer.TextSize = 8
		downedTimer.TextXAlignment = Enum.TextXAlignment.Right
		downedTimer.Visible = false
		downedTimer.ZIndex = row.ZIndex + 4
		downedTimer.Parent = row
	end

	local portrait = row:FindFirstChild("Portrait")
	local image = portrait and portrait:FindFirstChild("Avatar")
	if portrait and not image then
		image = Instance.new("ImageLabel")
		image.Name = "Avatar"
		image.Position = UDim2.fromOffset(2, 2)
		image.Size = UDim2.new(1, -4, 1, -4)
		image.BackgroundTransparency = 1
		image.Image = ""
		image.ScaleType = Enum.ScaleType.Crop
		image.Visible = false
		image.ZIndex = portrait.ZIndex + 3
		image.Parent = portrait
		Instance.new("UICorner", image).CornerRadius = UDim.new(1, 0)
	end

	rows[index] = {
		Frame = row,
		Name = row:WaitForChild("Name"),
		State = row:WaitForChild("State"),
		Health = row:WaitForChild("Health"),
		Percent = row:WaitForChild("Percent"),
		Leader = row:WaitForChild("Leader"),
		Initial = portrait and portrait:FindFirstChild("Initial"),
		Avatar = image,
		Distance = distance,
		DownedTimer = downedTimer,
		UserId = nil,
	}
end

local thumbnailCache = {}
local thumbnailLoading = {}

local function requestThumbnail(userId)
	if thumbnailCache[userId] or thumbnailLoading[userId] then
		return
	end
	thumbnailLoading[userId] = true
	task.spawn(function()
		local success, image = pcall(function()
			local content, ready = Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
			return ready and content or nil
		end)
		if success and image then
			thumbnailCache[userId] = image
		end
		thumbnailLoading[userId] = nil
	end)
end

local function sameSession(other)
	local session = localPlayer:GetAttribute("DungeonSessionId")
	if session == nil then
		local partyId = localPlayer:GetAttribute("PartyId")
		return partyId == nil or other:GetAttribute("PartyId") == partyId or other == localPlayer
	end
	return other:GetAttribute("DungeonSessionId") == session
end

local function participants()
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if sameSession(other) then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		if a == localPlayer then return true end
		if b == localPlayer then return false end
		local aLeader = a:GetAttribute("PartyLeaderUserId") == a.UserId
		local bLeader = b:GetAttribute("PartyLeaderUserId") == b.UserId
		if aLeader ~= bLeader then return aLeader end
		return a.UserId < b.UserId
	end)
	return list
end

local function playerState(other)
	local life = tostring(other:GetAttribute("DungeonLifeState") or "Active")
	if other:GetAttribute("IsDowned") == true or life == "Downed" then
		return "Downed"
	elseif other:GetAttribute("DungeonSpectating") == true or life == "Eliminated" then
		return "Eliminated"
	elseif life == "Disconnected" then
		return "Disconnected"
	end
	return "Active"
end

local function healthRatio(other)
	local character = other.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth > 0 then
		return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), humanoid.Health, humanoid.MaxHealth
	end
	return 0, 0, 0
end

local function distanceFromLocal(other)
	local localRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot or not otherRoot then return nil end
	return (otherRoot.Position - localRoot.Position).Magnitude
end

local function applyRow(record, other)
	record.Frame.Visible = other ~= nil
	if not other then
		record.UserId = nil
		return
	end
	record.UserId = other.UserId
	record.Frame:SetAttribute("ParticipantUserId", other.UserId)
	record.Name.Text = other.DisplayName
	record.Leader.Visible = other:GetAttribute("PartyLeaderUserId") == other.UserId
	if record.Initial then
		record.Initial.Text = string.upper(string.sub(other.DisplayName, 1, 1))
	end

	requestThumbnail(other.UserId)
	local thumb = thumbnailCache[other.UserId]
	if record.Avatar then
		record.Avatar.Visible = thumb ~= nil
		if thumb then record.Avatar.Image = thumb end
	end

	local state = playerState(other)
	local ratio = healthRatio(other)
	local distance = distanceFromLocal(other)
	record.Distance.Text = other == localPlayer and "VOCÊ" or (distance and string.format("%dm", math.floor(distance + 0.5)) or "--m")

	record.DownedTimer.Visible = false
	if state == "Downed" then
		local expires = tonumber(other:GetAttribute("DungeonDownedExpiresAt") or other:GetAttribute("DownedExpiresAt")) or serverTime()
		local remaining = math.max(0, math.ceil(expires - serverTime()))
		record.State.Text = "CAÍDO"
		record.State.TextColor3 = COLORS.Red
		record.DownedTimer.Text = string.format("%ds", remaining)
		record.DownedTimer.Visible = true
		record.Health.Fill.BackgroundColor3 = COLORS.Red
		record.Health.Fill.Size = UDim2.fromScale(math.max(0.04, remaining / 10), 1)
		record.Percent.Text = "AJUDE"
		record.Percent.TextColor3 = COLORS.Red
		record.Frame.BackgroundColor3 = Color3.fromRGB(59, 26, 37)
	elseif state == "Eliminated" then
		record.State.Text = "ESPECTADOR"
		record.State.TextColor3 = COLORS.Purple
		record.Health.Fill.Size = UDim2.fromScale(0, 1)
		record.Percent.Text = "--"
		record.Percent.TextColor3 = COLORS.Muted
		record.Frame.BackgroundColor3 = Color3.fromRGB(34, 30, 52)
	elseif state == "Disconnected" then
		record.State.Text = "AUSENTE"
		record.State.TextColor3 = COLORS.Muted
		record.Health.Fill.Size = UDim2.fromScale(0, 1)
		record.Percent.Text = "--"
		record.Percent.TextColor3 = COLORS.Muted
		record.Frame.BackgroundColor3 = Color3.fromRGB(31, 36, 45)
	else
		record.State.Text = other == localPlayer and "VOCÊ" or "ATIVO"
		record.State.TextColor3 = COLORS.Green
		record.Health.Fill.Size = UDim2.fromScale(ratio, 1)
		record.Health.Fill.BackgroundColor3 = ratio <= 0.30 and COLORS.Red or ratio <= 0.60 and COLORS.Orange or COLORS.Green
		record.Percent.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
		record.Percent.TextColor3 = COLORS.Text
		record.Frame.BackgroundColor3 = Color3.fromRGB(17, 36, 49)
	end
end

-- Marcadores no mundo para aliados derrubados.
local markerFolder = gui:FindFirstChild("PartyLifeWorldMarkers")
if markerFolder then markerFolder:Destroy() end
markerFolder = Instance.new("Folder")
markerFolder.Name = "PartyLifeWorldMarkers"
markerFolder.Parent = gui

local downedMarkers = {}

local function removeMarker(other)
	local marker = downedMarkers[other]
	if marker then marker:Destroy() end
	downedMarkers[other] = nil
end

local function ensureDownedMarker(other)
	if other == localPlayer or playerState(other) ~= "Downed" then
		removeMarker(other)
		return
	end
	local character = other.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		removeMarker(other)
		return
	end

	local marker = downedMarkers[other]
	if marker and marker.Adornee ~= rootPart then
		removeMarker(other)
		marker = nil
	end
	if not marker then
		marker = Instance.new("BillboardGui")
		marker.Name = "CrystalCelestialDownedMarker"
		marker.Adornee = rootPart
		marker.Size = UDim2.fromOffset(176, 58)
		marker.StudsOffsetWorldSpace = Vector3.new(0, 4.1, 0)
		marker.AlwaysOnTop = true
		marker.MaxDistance = 10000
		marker.LightInfluence = 0
		marker.Parent = markerFolder

		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromRGB(47, 20, 31)
		card.BackgroundTransparency = 0.06
		card.BorderSizePixel = 0
		card.Parent = marker
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 11)
		local s = Instance.new("UIStroke")
		s.Color = COLORS.Red
		s.Transparency = 0.12
		s.Thickness = 1.4
		s.Parent = card

		local cross = Instance.new("TextLabel")
		cross.Position = UDim2.fromOffset(5, 4)
		cross.Size = UDim2.fromOffset(42, 42)
		cross.BackgroundTransparency = 1
		cross.Text = "+"
		cross.TextColor3 = COLORS.Red
		cross.Font = Enum.Font.GothamBlack
		cross.TextSize = 28
		cross.Parent = card

		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.Position = UDim2.fromOffset(47, 5)
		name.Size = UDim2.new(1, -53, 0, 22)
		name.BackgroundTransparency = 1
		name.TextColor3 = COLORS.Text
		name.Font = Enum.Font.GothamBold
		name.TextSize = 10
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card

		local timer = Instance.new("TextLabel")
		timer.Name = "Timer"
		timer.Position = UDim2.fromOffset(47, 27)
		timer.Size = UDim2.new(1, -53, 0, 20)
		timer.BackgroundTransparency = 1
		timer.TextColor3 = COLORS.Red
		timer.Font = Enum.Font.GothamBold
		timer.TextSize = 10
		timer.TextXAlignment = Enum.TextXAlignment.Left
		timer.Parent = card
		downedMarkers[other] = marker
	end

	local expires = tonumber(other:GetAttribute("DungeonDownedExpiresAt") or other:GetAttribute("DownedExpiresAt")) or serverTime()
	local remaining = math.max(0, math.ceil(expires - serverTime()))
	marker.Card.Name.Text = other.DisplayName
	marker.Card.Timer.Text = string.format("REVIVA AGORA • %ds", remaining)
end

-- Barra local de revive usa o ProximityPrompt real.
local revivePanel = Instance.new("Frame")
revivePanel.Name = "ReviveProgress"
revivePanel.AnchorPoint = Vector2.new(0.5, 1)
revivePanel.Position = UDim2.new(0.5, 0, 1, -118)
revivePanel.Size = UDim2.fromOffset(370, 60)
revivePanel.BackgroundColor3 = COLORS.Glass
revivePanel.BackgroundTransparency = 0.06
revivePanel.BorderSizePixel = 0
revivePanel.Visible = false
revivePanel.ZIndex = 80
revivePanel.Parent = root
Instance.new("UICorner", revivePanel).CornerRadius = UDim.new(0, 14)
local reviveStroke = Instance.new("UIStroke")
reviveStroke.Color = COLORS.Cyan
reviveStroke.Transparency = 0.18
reviveStroke.Thickness = 1.4
reviveStroke.Parent = revivePanel

local reviveTitle = Instance.new("TextLabel")
reviveTitle.Position = UDim2.fromOffset(13, 5)
reviveTitle.Size = UDim2.new(1, -26, 0, 22)
reviveTitle.BackgroundTransparency = 1
reviveTitle.Text = "REVIVENDO ALIADO"
reviveTitle.TextColor3 = COLORS.CyanSoft
reviveTitle.Font = Enum.Font.GothamBold
reviveTitle.TextSize = 11
reviveTitle.Parent = revivePanel

local reviveTrack = Instance.new("Frame")
reviveTrack.Position = UDim2.fromOffset(14, 33)
reviveTrack.Size = UDim2.new(1, -28, 0, 12)
reviveTrack.BackgroundColor3 = Color3.fromRGB(31, 48, 59)
reviveTrack.BorderSizePixel = 0
reviveTrack.ClipsDescendants = true
reviveTrack.Parent = revivePanel
Instance.new("UICorner", reviveTrack).CornerRadius = UDim.new(1, 0)

local reviveFill = Instance.new("Frame")
reviveFill.Size = UDim2.fromScale(0, 1)
reviveFill.BackgroundColor3 = COLORS.Cyan
reviveFill.BorderSizePixel = 0
reviveFill.Parent = reviveTrack
Instance.new("UICorner", reviveFill).CornerRadius = UDim.new(1, 0)

local heldPrompt
local heldStartedAt = 0
local heldDuration = 0
local heldTarget

local function downedPlayerForPrompt(prompt)
	if not prompt then return nil end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= localPlayer and playerState(other) == "Downed" and other.Character and prompt:IsDescendantOf(other.Character) then
			return other
		end
	end
	return nil
end

local function beginRevive(prompt)
	local target = downedPlayerForPrompt(prompt)
	if not target then return end
	heldPrompt = prompt
	heldTarget = target
	heldStartedAt = os.clock()
	heldDuration = math.max(0.05, tonumber(prompt.HoldDuration) or 3)
	revivePanel.Visible = true
	reviveFill.Size = UDim2.fromScale(0, 1)
	reviveFill.BackgroundColor3 = COLORS.Cyan
	reviveTitle.Text = "REVIVENDO " .. string.upper(target.DisplayName)
	localPlayer:SetAttribute("DungeonHUDReviveTargetUserId", target.UserId)
	localPlayer:SetAttribute("DungeonHUDReviveState", "Holding")
end

local function cancelRevive(state)
	heldPrompt = nil
	heldTarget = nil
	heldStartedAt = 0
	heldDuration = 0
	if state == "Completed" then
		reviveFill.Size = UDim2.fromScale(1, 1)
		reviveFill.BackgroundColor3 = COLORS.Green
		reviveTitle.Text = "ALIADO REVIVIDO"
		task.delay(0.55, function()
			if not heldPrompt then revivePanel.Visible = false end
		end)
	else
		revivePanel.Visible = false
	end
	localPlayer:SetAttribute("DungeonHUDReviveTargetUserId", nil)
	localPlayer:SetAttribute("DungeonHUDReviveState", state or "Idle")
end

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	beginRevive(prompt)
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	if prompt == heldPrompt then
		cancelRevive("Interrupted")
	end
end)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt == heldPrompt then
		cancelRevive("Completed")
	end
end)

-- Estado local derrubado.
local localDowned = Instance.new("Frame")
localDowned.Name = "LocalDowned"
localDowned.AnchorPoint = Vector2.new(0.5, 1)
localDowned.Position = UDim2.new(0.5, 0, 1, -42)
localDowned.Size = UDim2.fromOffset(440, 82)
localDowned.BackgroundColor3 = Color3.fromRGB(48, 19, 29)
localDowned.BackgroundTransparency = 0.04
localDowned.BorderSizePixel = 0
localDowned.Visible = false
localDowned.ZIndex = 85
localDowned.Parent = root
Instance.new("UICorner", localDowned).CornerRadius = UDim.new(0, 16)
local downedStroke = Instance.new("UIStroke")
downedStroke.Color = COLORS.Red
downedStroke.Transparency = 0.12
downedStroke.Thickness = 1.6
downedStroke.Parent = localDowned

local downedTitle = Instance.new("TextLabel")
downedTitle.Position = UDim2.fromOffset(14, 8)
downedTitle.Size = UDim2.new(1, -28, 0, 29)
downedTitle.BackgroundTransparency = 1
downedTitle.Text = "VOCÊ ESTÁ CAÍDO"
downedTitle.TextColor3 = COLORS.Red
downedTitle.Font = Enum.Font.GothamBlack
downedTitle.TextSize = 16
downedTitle.Parent = localDowned

local downedDetail = Instance.new("TextLabel")
downedDetail.Position = UDim2.fromOffset(14, 39)
downedDetail.Size = UDim2.new(1, -28, 0, 29)
downedDetail.BackgroundTransparency = 1
downedDetail.Text = ""
downedDetail.TextColor3 = Color3.fromRGB(238, 217, 222)
downedDetail.Font = Enum.Font.GothamMedium
downedDetail.TextSize = 10
downedDetail.TextWrapped = true
downedDetail.Parent = localDowned

-- Espectador.
local spectator = Instance.new("Frame")
spectator.Name = "SpectatorControls"
spectator.AnchorPoint = Vector2.new(0.5, 1)
spectator.Position = UDim2.new(0.5, 0, 1, -38)
spectator.Size = UDim2.fromOffset(490, 86)
spectator.BackgroundColor3 = COLORS.Glass
spectator.BackgroundTransparency = 0.05
spectator.BorderSizePixel = 0
spectator.Visible = false
spectator.ZIndex = 86
spectator.Parent = root
Instance.new("UICorner", spectator).CornerRadius = UDim.new(0, 16)
local spectatorStroke = Instance.new("UIStroke")
spectatorStroke.Color = COLORS.Purple
spectatorStroke.Transparency = 0.18
spectatorStroke.Thickness = 1.4
spectatorStroke.Parent = spectator

local spectatorLabel = Instance.new("TextLabel")
spectatorLabel.Position = UDim2.fromOffset(80, 7)
spectatorLabel.Size = UDim2.new(1, -160, 0, 22)
spectatorLabel.BackgroundTransparency = 1
spectatorLabel.Text = "ESPECTANDO"
spectatorLabel.TextColor3 = COLORS.Purple
spectatorLabel.Font = Enum.Font.GothamBold
spectatorLabel.TextSize = 10
spectatorLabel.Parent = spectator

local targetName = Instance.new("TextLabel")
targetName.Position = UDim2.fromOffset(80, 28)
targetName.Size = UDim2.new(1, -160, 0, 27)
targetName.BackgroundTransparency = 1
targetName.Text = "PROCURANDO ALIADO..."
targetName.TextColor3 = COLORS.Text
targetName.Font = Enum.Font.GothamBlack
targetName.TextSize = 15
targetName.Parent = spectator

local targetHealth = Instance.new("TextLabel")
targetHealth.Position = UDim2.fromOffset(80, 55)
targetHealth.Size = UDim2.new(1, -160, 0, 19)
targetHealth.BackgroundTransparency = 1
targetHealth.Text = ""
targetHealth.TextColor3 = COLORS.Green
targetHealth.Font = Enum.Font.GothamBold
targetHealth.TextSize = 9
targetHealth.Parent = spectator

local function navButton(text, left)
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(left and 0 or 1, 0.5)
	button.Position = left and UDim2.new(0, 13, 0.5, 0) or UDim2.new(1, -13, 0.5, 0)
	button.Size = UDim2.fromOffset(54, 54)
	button.BackgroundColor3 = Color3.fromRGB(29, 46, 65)
	button.BackgroundTransparency = 0.04
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = COLORS.CyanSoft
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 22
	button.ZIndex = 87
	button.Parent = spectator
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 13)
	local s = Instance.new("UIStroke")
	s.Color = COLORS.Gold
	s.Transparency = 0.35
	s.Parent = button
	return button
end
local previousButton = navButton("‹", true)
local nextButton = navButton("›", false)

local controlEvent = playerGui:WaitForChild("DungeonSpectatorControl", 20)

local function requestSpectator(action)
	if controlEvent and controlEvent:IsA("BindableEvent") then
		controlEvent:Fire(action)
	end
end
previousButton.Activated:Connect(function() requestSpectator("Previous") end)
nextButton.Activated:Connect(function() requestSpectator("Next") end)

local function refreshSpectator()
	local life = tostring(localPlayer:GetAttribute("DungeonLifeState") or "Active")
	local active = life == "Eliminated" or localPlayer:GetAttribute("DungeonSpectating") == true
	spectator.Visible = active
	if not active then return end

	local targetId = tonumber(localPlayer:GetAttribute("DungeonSpectatorTargetUserId"))
	local target = targetId and Players:GetPlayerByUserId(targetId)
	if not target then
		targetName.Text = "PROCURANDO ALIADO..."
		targetHealth.Text = "Você retorna na próxima Reward Island."
		targetHealth.TextColor3 = COLORS.Muted
		return
	end
	local ratio, hp, maxHp = healthRatio(target)
	targetName.Text = target.DisplayName
	targetHealth.Text = string.format("VIDA %d/%d • %d%%", math.floor(hp + 0.5), math.floor(maxHp + 0.5), math.floor(ratio * 100 + 0.5))
	targetHealth.TextColor3 = ratio <= 0.3 and COLORS.Red or ratio <= 0.6 and COLORS.Orange or COLORS.Green
end

local function refreshLocalDowned()
	local life = tostring(localPlayer:GetAttribute("DungeonLifeState") or "Active")
	local downed = life == "Downed" or localPlayer:GetAttribute("IsDowned") == true
	localDowned.Visible = downed
	if not downed then return end
	local expires = tonumber(localPlayer:GetAttribute("DungeonDownedExpiresAt") or localPlayer:GetAttribute("DownedExpiresAt")) or serverTime()
	local remaining = math.max(0, math.ceil(expires - serverTime()))
	downedTitle.Text = string.format("VOCÊ ESTÁ CAÍDO • %ds", remaining)

	local activeAllies = 0
	for _, other in ipairs(participants()) do
		if other ~= localPlayer and playerState(other) == "Active" then activeAllies += 1 end
	end
	if activeAllies > 0 then
		downedDetail.Text = string.format("%d aliado(s) ainda podem salvar você. Aguarde o revive.", activeAllies)
	else
		downedDetail.Text = "Nenhum aliado está ativo. A equipe pode entrar em estado de derrota."
	end
end

local function refreshWipe()
	local wipe = workspace:GetAttribute("DungeonWipePending") == true
	if wipe and not localDowned.Visible and not spectator.Visible then
		localDowned.Visible = true
		downedTitle.Text = "EQUIPE SEM JOGADORES ATIVOS"
		downedDetail.Text = "Aguardando recuperação automática ou confirmação da derrota."
		downedStroke.Color = COLORS.Orange
	elseif not wipe then
		downedStroke.Color = COLORS.Red
	end
end

local function refreshParty()
	local list = participants()
	for index, record in ipairs(rows) do
		applyRow(record, list[index])
	end
	for _, other in ipairs(list) do
		ensureDownedMarker(other)
	end
	for other in pairs(downedMarkers) do
		if not other.Parent or playerState(other) ~= "Downed" then
			removeMarker(other)
		end
	end
end

local function refreshReviveProgress()
	if not heldPrompt or not heldPrompt.Parent or not heldTarget or playerState(heldTarget) ~= "Downed" then
		if heldPrompt then cancelRevive("Cancelled") end
		return
	end
	local ratio = math.clamp((os.clock() - heldStartedAt) / math.max(0.05, heldDuration), 0, 1)
	reviveFill.Size = UDim2.fromScale(ratio, 1)
	reviveTitle.Text = string.format("REVIVENDO %s • %d%%", string.upper(heldTarget.DisplayName), math.floor(ratio * 100 + 0.5))
end

Players.PlayerRemoving:Connect(removeMarker)

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	refreshParty()
	refreshLocalDowned()
	refreshSpectator()
	refreshWipe()
	refreshReviveProgress()
end)

localPlayer:SetAttribute("DungeonHUDPartyLifeReady", true)
localPlayer:SetAttribute("DungeonHUDPartyLifeVersion", VERSION)
workspace:SetAttribute("DungeonHUDPartyLifeReady", true)
workspace:SetAttribute("DungeonHUDPartyLifePolicy", "PartyDownedReviveSpectatorV1")

refreshParty()
refreshLocalDowned()
refreshSpectator()
refreshWipe()
