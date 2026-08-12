-- Mobile Dungeon Mode — Task 12: Next-Island Camera Guidance.
--
-- Alimenta o seam criado na Task 02:
--   workspace.DungeonMobileCameraForwardOverride
--
-- Esta camada NAO move o jogador e NAO altera Camera.CFrame diretamente.
-- Ela apenas sugere uma direcao horizontal para o DungeonCameraController
-- durante janelas de navegacao/transicao.
--
-- Em combate normal a override e removida e a camera volta ao comportamento
-- semi-fixo da Task 02.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local VERSION = "DungeonNextIslandCameraGuidanceV1"
local UPDATE_INTERVAL = 0.10

local DEFAULTS = {
	MaxMarkerDistance = 125,
	MinMarkerDistance = 5,
	DirectionSmoothSpeed = 5.5,
	SwitchAdvantageStuds = 10,
	OptionalRoutePenaltyStuds = 38,
	RecentRewardGuidanceSeconds = 4.0,
}

local exitMarkers = setmetatable({}, { __mode = "k" })

local active = false
local elapsed = 0
local currentMarker
local currentMarkerScore = math.huge
local smoothedDirection
local lastRewardActive = false
local lastRewardCommittedAt = -math.huge

local NAVIGATION_PACING = {
	RoundTransition = true,
	BossTransition = true,
	BossRouteOpen = true,
}

local function numberSetting(name, defaultValue, minimum, maximum)
	local value = tonumber(player:GetAttribute(name))
	if value == nil then
		value = defaultValue
	end
	return math.clamp(value, minimum, maximum)
end

local function ensureTuningAttributes()
	local attributes = {
		DungeonMobileCameraGuidanceMaxDistance = DEFAULTS.MaxMarkerDistance,
		DungeonMobileCameraGuidanceSmoothSpeed = DEFAULTS.DirectionSmoothSpeed,
		DungeonMobileCameraGuidanceSwitchAdvantage = DEFAULTS.SwitchAdvantageStuds,
	}

	for name, value in pairs(attributes) do
		if player:GetAttribute(name) == nil then
			player:SetAttribute(name, value)
		end
	end
end

local function horizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end
	return horizontal.Unit
end

local function playerRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function currentGlobalIndex()
	local value = tonumber(
		player:GetAttribute("CurrentGlobalIslandIndex")
			or workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex")
			or workspace:GetAttribute("DungeonCurrentObjectiveIsland")
	)
	if not value then
		return nil
	end
	return math.max(1, math.floor(value))
end

local function ancestorGlobalIndex(instance)
	local cursor = instance
	while cursor and cursor ~= workspace do
		for _, name in ipairs({
			"GlobalIslandIndex",
			"IslandGlobalIndex",
			"SourceGlobalIslandIndex",
			"RouteGlobalIndex",
		}) do
			local value = tonumber(cursor:GetAttribute(name))
			if value then
				return math.floor(value)
			end
		end
		cursor = cursor.Parent
	end
	return nil
end

local function markerIsOptional(marker)
	if marker:GetAttribute("IsOptional") == true
		or marker:GetAttribute("OptionalRoute") == true
		or marker:GetAttribute("IsOptionalRoute") == true
	then
		return true
	end

	for _, name in ipairs({
		"ConnectionKind",
		"RouteKind",
		"ConnectionType",
		"RouteType",
	}) do
		local value = string.lower(tostring(marker:GetAttribute(name) or ""))
		if string.find(value, "optional", 1, true) then
			return true
		end
	end

	local targetKey = string.lower(tostring(
		marker:GetAttribute("ConnectionTargetKey") or ""
	))
	return string.find(targetKey, "optional", 1, true) ~= nil
end

local function markerLooksLikeRoundExit(marker)
	for _, name in ipairs({
		"IsRoundExit",
		"RoundExit",
		"ConnectionIsRoundExit",
	}) do
		if marker:GetAttribute(name) == true then
			return true
		end
	end

	for _, name in ipairs({
		"ConnectionKind",
		"RouteKind",
		"ConnectionType",
	}) do
		local value = string.lower(tostring(marker:GetAttribute(name) or ""))
		if string.find(value, "roundexit", 1, true)
			or string.find(value, "round exit", 1, true)
		then
			return true
		end
	end

	local targetKey = string.lower(tostring(
		marker:GetAttribute("ConnectionTargetKey") or ""
	))
	return string.find(targetKey, "roundexit", 1, true) ~= nil
end

local function markerStillValid(marker)
	return marker
		and marker.Parent
		and marker:IsA("BasePart")
		and marker:GetAttribute("ConnectionTargetKey") ~= nil
end

local function registerMarker(instance)
	if instance:IsA("BasePart")
		and instance:GetAttribute("ConnectionTargetKey") ~= nil
	then
		exitMarkers[instance] = true
	end
end

local function scanInitialMarkers()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		registerMarker(descendant)
	end
end

local function objectiveComplete()
	local explicit = workspace:GetAttribute("DungeonObjectiveCompleted")
	if explicit == true then
		return true
	end

	local state = string.lower(tostring(
		workspace:GetAttribute("DungeonObjectiveState")
			or workspace:GetAttribute("DungeonObjectiveStatus")
			or ""
	))
	if state == "completed"
		or state == "complete"
		or state == "resolved"
		or state == "succeeded"
	then
		return true
	end

	local progress = tonumber(workspace:GetAttribute("DungeonObjectiveProgress"))
	local target = tonumber(workspace:GetAttribute("DungeonObjectiveTarget"))
	return progress ~= nil
		and target ~= nil
		and target > 0
		and progress >= target
end

local function bossOwnsCameraSoon()
	local state = tostring(workspace:GetAttribute("DungeonBossState") or "")
	return state == "Activating" or state == "Active"
end

local function navigationWindow()
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		return false, "AssistedTransportOwnsCamera"
	end

	if player:GetAttribute("DungeonMobileMode") ~= true then
		return false, "NotMobile"
	end
	if player:GetAttribute("IsDowned") == true then
		return false, "Downed"
	end
	if workspace:GetAttribute("DungeonRewardIslandActive") == true then
		return false, "RewardIsland"
	end
	if bossOwnsCameraSoon() then
		return false, "BossOwnsCamera"
	end

	local pacing = tostring(workspace:GetAttribute("DungeonPacingState") or "")
	if NAVIGATION_PACING[pacing] then
		return true, pacing
	end

	if objectiveComplete() then
		return true, "ObjectiveComplete"
	end

	if workspace:GetServerTimeNow() - lastRewardCommittedAt
		<= DEFAULTS.RecentRewardGuidanceSeconds
	then
		return true, "RewardCommitted"
	end

	return false, "Combat"
end

local function scoreMarker(marker, root, mode)
	local offset = marker.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontal.Magnitude

	local maxDistance = numberSetting(
		"DungeonMobileCameraGuidanceMaxDistance",
		DEFAULTS.MaxMarkerDistance,
		45,
		220
	)

	if distance < DEFAULTS.MinMarkerDistance or distance > maxDistance then
		return nil
	end

	local currentIndex = currentGlobalIndex()
	local markerIndex = ancestorGlobalIndex(marker)

	-- Quando o marker carrega identidade de ilha, so aceitamos a ilha atual.
	-- Marcadores sem esse metadado continuam validos por proximidade.
	if currentIndex and markerIndex and markerIndex ~= currentIndex then
		return nil
	end

	local score = distance

	-- Em bifurcacoes, a rota obrigatoria e preferida. A opcional continua
	-- possivel: o jogador pode andar ate ela e assumir naturalmente a camera.
	if markerIsOptional(marker) then
		score += DEFAULTS.OptionalRoutePenaltyStuds
	end

	if mode == "RoundTransition"
		or mode == "BossTransition"
		or mode == "BossRouteOpen"
		or mode == "RewardCommitted"
	then
		if markerLooksLikeRoundExit(marker) then
			score -= 24
		end
	end

	return {
		Marker = marker,
		Score = score,
		Distance = distance,
		Direction = horizontal.Unit,
	}
end

local function chooseMarker(root, mode)
	local best

	for marker in pairs(exitMarkers) do
		if not markerStillValid(marker) then
			exitMarkers[marker] = nil
		else
			local candidate = scoreMarker(marker, root, mode)
			if candidate and (not best or candidate.Score < best.Score) then
				best = candidate
			end
		end
	end

	if currentMarker and markerStillValid(currentMarker) then
		local sticky = scoreMarker(currentMarker, root, mode)
		if sticky then
			if not best or best.Marker == currentMarker then
				best = sticky
			else
				local advantage = numberSetting(
					"DungeonMobileCameraGuidanceSwitchAdvantage",
					DEFAULTS.SwitchAdvantageStuds,
					0,
					40
				)
				-- Mantem a rota atual ate outra saida ser claramente melhor.
				if best.Score + advantage >= sticky.Score then
					best = sticky
				end
			end
		end
	end

	return best
end

local function clearOverride(reason)
	currentMarker = nil
	currentMarkerScore = math.huge
	smoothedDirection = nil

	workspace:SetAttribute("DungeonMobileCameraForwardOverride", nil)

	player:SetAttribute("DungeonMobileCameraGuidanceActive", false)
	player:SetAttribute("DungeonMobileCameraGuidanceMode", reason)
	player:SetAttribute("DungeonMobileCameraGuidanceMarkerName", nil)
	player:SetAttribute("DungeonMobileCameraGuidanceTargetKey", nil)
	player:SetAttribute("DungeonMobileCameraGuidanceDistance", nil)
	player:SetAttribute("DungeonMobileCameraGuidanceDirection", nil)
end

local function publishCandidate(candidate, mode, deltaTime)
	currentMarker = candidate.Marker
	currentMarkerScore = candidate.Score

	if not smoothedDirection then
		smoothedDirection = candidate.Direction
	else
		local speed = numberSetting(
			"DungeonMobileCameraGuidanceSmoothSpeed",
			DEFAULTS.DirectionSmoothSpeed,
			1.5,
			14
		)
		local alpha = 1 - math.exp(-speed * math.max(0, deltaTime))
		local blended = smoothedDirection:Lerp(candidate.Direction, alpha)
		smoothedDirection = horizontalUnit(blended) or candidate.Direction
	end

	workspace:SetAttribute(
		"DungeonMobileCameraForwardOverride",
		smoothedDirection
	)

	player:SetAttribute("DungeonMobileCameraGuidanceActive", true)
	player:SetAttribute("DungeonMobileCameraGuidanceMode", mode)
	player:SetAttribute(
		"DungeonMobileCameraGuidanceMarkerName",
		candidate.Marker.Name
	)
	player:SetAttribute(
		"DungeonMobileCameraGuidanceTargetKey",
		tostring(candidate.Marker:GetAttribute("ConnectionTargetKey"))
	)
	player:SetAttribute(
		"DungeonMobileCameraGuidanceDistance",
		candidate.Distance
	)
	player:SetAttribute(
		"DungeonMobileCameraGuidanceDirection",
		smoothedDirection
	)
end

local function updateRewardTransition()
	local rewardActive = workspace:GetAttribute("DungeonRewardIslandActive") == true
	if lastRewardActive and not rewardActive then
		lastRewardCommittedAt = workspace:GetServerTimeNow()
	end
	lastRewardActive = rewardActive
end

local function update(deltaTime)
	if not active then
		return
	end

	updateRewardTransition()

	local allowed, mode = navigationWindow()
	if not allowed then
		if currentMarker or smoothedDirection then
			clearOverride(mode)
		end
		return
	end

	local root = playerRoot()
	if not root then
		clearOverride("NoCharacter")
		return
	end

	local candidate = chooseMarker(root, mode)
	if not candidate then
		clearOverride("NoRouteMarker")
		return
	end

	publishCandidate(candidate, mode, deltaTime)
end

local function activate()
	if active or player:GetAttribute("DungeonMobileMode") ~= true then
		return
	end

	active = true
	ensureTuningAttributes()
	lastRewardActive = workspace:GetAttribute("DungeonRewardIslandActive") == true

	player:SetAttribute("DungeonMobileCameraGuidanceReady", true)
	player:SetAttribute("DungeonMobileCameraGuidanceActive", false)
	player:SetAttribute("DungeonMobileCameraGuidanceVersion", VERSION)
	player:SetAttribute(
		"DungeonMobileCameraGuidancePolicy",
		"ContextualNearestMandatoryExitStickyV1"
	)
end

local function deactivate()
	if not active then
		return
	end

	active = false
	clearOverride("Inactive")
end

local function refreshActivation()
	if player:GetAttribute("DungeonMobileMode") == true then
		activate()
	else
		deactivate()
	end
end

scanInitialMarkers()

workspace.DescendantAdded:Connect(function(instance)
	registerMarker(instance)
end)

workspace.DescendantRemoving:Connect(function(instance)
	exitMarkers[instance] = nil
	if instance == currentMarker then
		clearOverride("MarkerRemoved")
	end
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refreshActivation)

RunService.Heartbeat:Connect(function(deltaTime)
	if not active then
		return
	end

	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end

	local step = elapsed
	elapsed = 0
	update(step)
end)

player:SetAttribute("DungeonMobileCameraGuidanceControllerLoaded", true)
player:SetAttribute("DungeonMobileCameraGuidanceVersion", VERSION)

if player:GetAttribute("DungeonInputProfileReady") == true
	or player:GetAttribute("DungeonMobileMode") ~= nil
then
	refreshActivation()
else
	local readyConnection
	readyConnection = player:GetAttributeChangedSignal(
		"DungeonInputProfileReady"
	):Connect(function()
		if player:GetAttribute("DungeonInputProfileReady") == true then
			if readyConnection then
				readyConnection:Disconnect()
				readyConnection = nil
			end
			refreshActivation()
		end
	end)
end

script.Destroying:Connect(deactivate)
