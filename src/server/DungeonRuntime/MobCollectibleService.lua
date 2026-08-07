-- Tarefa 28: economia física por essências deixadas pelos mobs.
-- As moedas só entram no ledger quando o coletável alcança um participante.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local GameplayAnalytics = require(script.Parent.Parent:WaitForChild("GameplayAnalyticsService"))
local RunRewardLedgerService = require(script.Parent:WaitForChild("RunRewardLedgerService"))

local MobCollectibleService = {}

local POLICY = "PhysicalMobEssenceTargetedBossRewardV2"
local CONFIG = {
	PickupRadius = 5.5,
	NormalLifetimeSeconds = 120,
	RoundMagnetLifetimeSeconds = 18,
	BaseMagnetSpeed = 42,
	MaximumMagnetSpeed = 92,
	MagnetAcceleration = 54,
	HoverHeight = 1.25,
	HoverAmplitude = 0.22,
	HoverSpeed = 2.6,
	MaximumActive = 160,
	MergeRadius = 5.5,
	UpdateInterval = 1 / 30,
	PickupBurstCount = 46,
}

local started = false
local participantSet = {}
local sessionId = ""
local active = {}
local activeCount = 0
local serial = 0
local heartbeatConnection
local accumulatedDelta = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function getRuntimeFolder()
	local folder = workspace:FindFirstChild("DungeonMobCollectibles")
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DungeonMobCollectibles"
		folder.Parent = workspace
	end
	return folder
end

local function isEligiblePlayer(player, allowDowned)
	if not player or player.Parent ~= Players then
		return false
	end
	if next(participantSet) ~= nil and participantSet[player.UserId] ~= true then
		return false
	end
	if player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
		or (player:GetAttribute("IsDowned") == true and allowDowned ~= true)
	then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart")
end

local function playerRoot(player, allowDowned)
	if not isEligiblePlayer(player, allowDowned) then
		return nil
	end
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function nearestEligiblePlayer(position, targetUserId, allowDowned)
	local selected
	local selectedRoot
	local selectedDistance = math.huge
	targetUserId = math.floor(tonumber(targetUserId) or 0)
	for _, player in ipairs(Players:GetPlayers()) do
		if targetUserId > 0 and player.UserId ~= targetUserId then
			continue
		end
		local root = playerRoot(player, allowDowned)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < selectedDistance then
				selected = player
				selectedRoot = root
				selectedDistance = distance
			end
		end
	end
	return selected, selectedRoot, selectedDistance
end

local function updateWorkspaceCounters()
	workspace:SetAttribute("DungeonMobCollectibleReady", started)
	workspace:SetAttribute("DungeonMobCollectiblePolicy", POLICY)
	workspace:SetAttribute("DungeonMobCollectibleActiveCount", activeCount)
	workspace:SetAttribute(
		"DungeonMobCollectibleSpawnedCount",
		math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonMobCollectibleSpawnedCount")) or 0))
	)
	workspace:SetAttribute(
		"DungeonMobCollectibleClaimedCount",
		math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonMobCollectibleClaimedCount")) or 0))
	)
end

local function scaleForAmount(amount)
	return math.clamp(0.95 + math.log(math.max(1, amount) + 1) * 0.18, 1, 2.15)
end

local function updateVisualScale(entry)
	if not entry.Root or not entry.Root.Parent then
		return
	end
	local scale = scaleForAmount(entry.Amount)
	entry.Root.Size = Vector3.new(1.25, 1.25, 1.25) * scale
	entry.Root:SetAttribute("CoinValue", entry.Amount)
	entry.Model:SetAttribute("CoinValue", entry.Amount)
	if entry.Light then
		entry.Light.Range = 8 + scale * 3
		entry.Light.Brightness = 1.5 + math.min(2.5, entry.Amount * 0.025)
	end
end

local function createVisual(position, amount, isElite)
	serial += 1
	local model = Instance.new("Model")
	model.Name = string.format("MobEssence_%04d", serial)
	model:SetAttribute("IsMobCoinCollectible", true)
	model:SetAttribute("CollectiblePolicy", POLICY)
	model:SetAttribute("Claimed", false)
	model:SetAttribute("AutoAttracting", false)

	local root = Instance.new("Part")
	root.Name = "EssenceRoot"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(1.25, 1.25, 1.25) * scaleForAmount(amount)
	root.CFrame = CFrame.new(position + Vector3.new(0, CONFIG.HoverHeight, 0))
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Material = Enum.Material.Neon
	root.Color = isElite and Color3.fromRGB(255, 116, 226) or Color3.fromRGB(104, 225, 255)
	root.Parent = model
	model.PrimaryPart = root

	local attachmentA = Instance.new("Attachment")
	attachmentA.Name = "TrailTop"
	attachmentA.Position = Vector3.new(0, root.Size.Y * 0.38, 0)
	attachmentA.Parent = root
	local attachmentB = Instance.new("Attachment")
	attachmentB.Name = "TrailBottom"
	attachmentB.Position = Vector3.new(0, -root.Size.Y * 0.38, 0)
	attachmentB.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "EssenceTrail"
	trail.Attachment0 = attachmentA
	trail.Attachment1 = attachmentB
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, root.Color),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.28
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = root

	local ambient = Instance.new("ParticleEmitter")
	ambient.Name = "AmbientEssence"
	ambient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, root.Color),
	})
	ambient.LightEmission = 1
	ambient.Lifetime = NumberRange.new(0.35, 0.75)
	ambient.Speed = NumberRange.new(0.4, 1.7)
	ambient.SpreadAngle = Vector2.new(180, 180)
	ambient.Rate = isElite and 18 or 11
	ambient.RotSpeed = NumberRange.new(-160, 160)
	ambient.Parent = root

	local light = Instance.new("PointLight")
	light.Name = "EssenceLight"
	light.Color = root.Color
	light.Brightness = isElite and 3.4 or 2.1
	light.Range = isElite and 13 or 10
	light.Shadows = false
	light.Parent = root

	local highlight = Instance.new("Highlight")
	highlight.Name = "EssenceOutline"
	highlight.FillTransparency = 0.72
	highlight.FillColor = root.Color
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0.08
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	model.Parent = getRuntimeFolder()
	return model, root, ambient, trail, light
end

local function removeEntry(entry, destroyModel)
	if not entry or active[entry.Model] ~= entry then
		return
	end
	active[entry.Model] = nil
	activeCount = math.max(0, activeCount - 1)
	if destroyModel and entry.Model.Parent then
		entry.Model:Destroy()
	end
	updateWorkspaceCounters()
end

local function syncCoinBalance(player, value)
	player:SetAttribute("Coins", value)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		coins.Value = value
	end
end

local function grantCoins(player, entry)
	local amount = math.max(0, math.floor(tonumber(entry.Amount) or 0))
	if amount <= 0 then
		return false, "EmptyCollectible"
	end
	if workspace:GetAttribute("DungeonRewardLedgerEnabled") == true then
		local sourceType = tostring(entry.SourceType or "MobCollectible")
		local queued, pending = RunRewardLedgerService.AddPendingCoins(
			player,
			amount,
			sourceType,
			entry.Root.Position,
			entry.RoundIndex
		)
		if queued then
			player:SetAttribute("LastCoinSource", "Pending:" .. sourceType)
			player:SetAttribute("LastCoinAward", amount)
			player:SetAttribute("LastPendingCoinBalance", pending)
			player:SetAttribute("LastCoinSerial", (player:GetAttribute("LastCoinSerial") or 0) + 1)
			return true, pending
		end
	end
	local success, balance = PlayerDataService.AddCoins(player, amount)
	if not success then
		return false, balance
	end
	syncCoinBalance(player, balance)
	GameplayAnalytics.RecordCoinsEarned(player, tostring(entry.SourceType or "MobCollectible"), amount)
	return true, balance
end

local function pickupBurst(entry)
	local root = entry.Root
	if not root or not root.Parent then
		return
	end
	entry.Ambient.Enabled = false
	entry.Trail.Enabled = false
	root.Transparency = 1
	entry.Light.Brightness = 4.5
	entry.Light.Range = 16

	local burst = Instance.new("ParticleEmitter")
	burst.Name = "PickupBurst"
	burst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.35, root.Color),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(116, 255, 205)),
	})
	burst.LightEmission = 1
	burst.Lifetime = NumberRange.new(0.28, 0.62)
	burst.Speed = NumberRange.new(8, 18)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 4
	burst.Rate = 0
	burst.Rotation = NumberRange.new(0, 360)
	burst.RotSpeed = NumberRange.new(-220, 220)
	burst.Parent = root
	burst:Emit(CONFIG.PickupBurstCount + math.min(30, math.floor(entry.Amount / 2)))

	local sound = Instance.new("Sound")
	sound.Name = "EssencePickup"
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.72
	sound.PlaybackSpeed = math.clamp(1 + entry.Amount * 0.002, 1, 1.25)
	sound.RollOffMaxDistance = 70
	sound.Parent = root
	sound:Play()

	Debris:AddItem(entry.Model, 0.75)
end

local function claim(entry, player, reason)
	if not entry or entry.Claimed or not entry.Model.Parent or not isEligiblePlayer(player, entry.AllowDownedTarget) then
		return false
	end
	if entry.ExclusiveToTarget and entry.TargetUserId > 0 and player.UserId ~= entry.TargetUserId then
		return false
	end
	entry.Claimed = true
	entry.Model:SetAttribute("Claimed", true)
	entry.Model:SetAttribute("ClaimedByUserId", player.UserId)
	entry.Model:SetAttribute("ClaimReason", tostring(reason or "Proximity"))
	local granted, result = grantCoins(player, entry)
	if not granted then
		entry.Claimed = false
		entry.Model:SetAttribute("Claimed", false)
		entry.Model:SetAttribute("ClaimError", tostring(result))
		return false
	end

	player:SetAttribute(
		"DungeonMobCollectibleClaimedCount",
		math.max(0, math.floor(tonumber(player:GetAttribute("DungeonMobCollectibleClaimedCount")) or 0)) + 1
	)
	player:SetAttribute(
		"DungeonMobCollectibleCoinTotal",
		math.max(0, math.floor(tonumber(player:GetAttribute("DungeonMobCollectibleCoinTotal")) or 0))
			+ entry.Amount
	)
	player:SetAttribute("DungeonLastMobCollectibleAmount", entry.Amount)
	player:SetAttribute("DungeonLastMobCollectibleRound", entry.RoundIndex)
	player:SetAttribute("DungeonLastMobCollectibleReason", tostring(reason or "Proximity"))
	player:SetAttribute("DungeonLastMobCollectibleAt", now())
	workspace:SetAttribute(
		"DungeonMobCollectibleClaimedCount",
		math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonMobCollectibleClaimedCount")) or 0)) + 1
	)
	pickupBurst(entry)
	removeEntry(entry, false)
	return true
end

local function mergeNearby(position, roundIndex, amount)
	local selected
	local selectedDistance = CONFIG.MergeRadius
	for _, entry in pairs(active) do
		if not entry.Claimed and entry.RoundIndex == roundIndex and entry.Model.Parent then
			local distance = (entry.Root.Position - position).Magnitude
			if distance <= selectedDistance then
				selected = entry
				selectedDistance = distance
			end
		end
	end
	if selected then
		selected.Amount += amount
		selected.ExpiresAt = math.max(selected.ExpiresAt, now() + CONFIG.NormalLifetimeSeconds)
		updateVisualScale(selected)
		selected.Model:SetAttribute("MergedDropCount", (selected.Model:GetAttribute("MergedDropCount") or 1) + 1)
		return selected
	end
	return nil
end

function MobCollectibleService.Drop(options)
	options = type(options) == "table" and options or {}
	local amount = math.max(0, math.floor(tonumber(options.Amount) or 0))
	local position = options.Position
	if amount <= 0 or typeof(position) ~= "Vector3" then
		return nil, "InvalidDrop"
	end
	if not started then
		MobCollectibleService.Start({})
	end
	local roundIndex = math.clamp(math.floor(tonumber(options.RoundIndex) or 1), 1, 3)
	if activeCount >= CONFIG.MaximumActive then
		local merged = mergeNearby(position, roundIndex, amount)
		if merged then
			return merged.Model, "Merged"
		end
	end

	local model, root, ambient, trail, light = createVisual(position, amount, options.IsElite == true)
	local entry = {
		Model = model,
		Root = root,
		Ambient = ambient,
		Trail = trail,
		Light = light,
		Amount = amount,
		RoundIndex = roundIndex,
		PreferredUserId = math.floor(tonumber(options.PreferredUserId) or 0),
		TargetUserId = math.floor(tonumber(options.TargetUserId) or 0),
		ExclusiveToTarget = options.ExclusiveToTarget == true,
		AllowDownedTarget = options.AllowDownedTarget == true,
		SourceType = tostring(options.SourceType or "MobCollectible"),
		SourceMonsterId = tostring(options.SourceMonsterId or "Unknown"),
		IsElite = options.IsElite == true,
		SpawnedAt = now(),
		ExpiresAt = now() + CONFIG.NormalLifetimeSeconds,
		BasePosition = root.Position,
		Phase = serial * 0.73,
		Attracting = false,
		AttractReason = nil,
		TargetPlayer = nil,
		MagnetSpeed = CONFIG.BaseMagnetSpeed,
		Claimed = false,
	}
	active[model] = entry
	activeCount += 1
	for _, instance in ipairs({ model, root }) do
		instance:SetAttribute("CoinValue", amount)
		instance:SetAttribute("RoundIndex", roundIndex)
		instance:SetAttribute("PreferredUserId", entry.PreferredUserId > 0 and entry.PreferredUserId or nil)
		instance:SetAttribute("TargetUserId", entry.TargetUserId > 0 and entry.TargetUserId or nil)
		instance:SetAttribute("ExclusiveToTarget", entry.ExclusiveToTarget)
		instance:SetAttribute("AllowDownedTarget", entry.AllowDownedTarget)
		instance:SetAttribute("SourceType", entry.SourceType)
		instance:SetAttribute("SourceMonsterId", entry.SourceMonsterId)
		instance:SetAttribute("IsEliteDrop", entry.IsElite)
	end
	workspace:SetAttribute(
		"DungeonMobCollectibleSpawnedCount",
		math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonMobCollectibleSpawnedCount")) or 0)) + 1
	)
	updateWorkspaceCounters()
	return model
end

local function beginAttraction(entry, targetPlayer, reason)
	if not entry or entry.Claimed or not entry.Model.Parent then
		return false
	end
	entry.Attracting = true
	entry.TargetPlayer = targetPlayer
	entry.AttractReason = tostring(reason or "RoundCompleted")
	entry.MagnetSpeed = CONFIG.BaseMagnetSpeed
	entry.ExpiresAt = math.max(entry.ExpiresAt, now() + CONFIG.RoundMagnetLifetimeSeconds)
	entry.Trail.Enabled = true
	entry.Model:SetAttribute("AutoAttracting", true)
	entry.Model:SetAttribute("AttractReason", entry.AttractReason)
	entry.Model:SetAttribute("AttractTargetUserId", targetPlayer and targetPlayer.UserId or nil)
	return true
end

function MobCollectibleService.AttractRound(roundIndex, reason)
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 0), 1, 3)
	local count = 0
	for _, entry in pairs(active) do
		if entry.RoundIndex == roundIndex and not entry.Claimed and entry.Model.Parent then
			local player = nearestEligiblePlayer(
				entry.Root.Position,
				entry.ExclusiveToTarget and entry.TargetUserId or nil,
				entry.AllowDownedTarget
			)
			if beginAttraction(entry, player, reason or "RoundCompleted") then
				count += 1
			end
		end
	end
	workspace:SetAttribute("DungeonMobCollectibleMagnetRound", roundIndex)
	workspace:SetAttribute("DungeonMobCollectibleMagnetCount", count)
	workspace:SetAttribute("DungeonMobCollectibleMagnetAt", now())
	workspace:SetAttribute("DungeonMobCollectibleMagnetReason", tostring(reason or "RoundCompleted"))
	return count
end

function MobCollectibleService.AttractAll(reason)
	local count = 0
	for _, entry in pairs(active) do
		if not entry.Claimed and entry.Model.Parent then
			local player = nearestEligiblePlayer(
				entry.Root.Position,
				entry.ExclusiveToTarget and entry.TargetUserId or nil,
				entry.AllowDownedTarget
			)
			if beginAttraction(entry, player, reason or "RunEnding") then
				count += 1
			end
		end
	end
	return count
end

local function stepEntry(entry, deltaTime, timestamp)
	if not entry.Model.Parent or not entry.Root.Parent then
		removeEntry(entry, false)
		return
	end
	if timestamp >= entry.ExpiresAt then
		if entry.Attracting then
			local fallback = nearestEligiblePlayer(
				entry.Root.Position,
				entry.ExclusiveToTarget and entry.TargetUserId or nil,
				entry.AllowDownedTarget
			)
			if fallback then
				entry.TargetPlayer = fallback
				entry.ExpiresAt = timestamp + 5
			else
				removeEntry(entry, true)
			end
		else
			removeEntry(entry, true)
		end
		return
	end

	if entry.Attracting then
		local targetRoot = playerRoot(entry.TargetPlayer, entry.AllowDownedTarget)
		if not targetRoot then
			local player, root = nearestEligiblePlayer(
				entry.Root.Position,
				entry.ExclusiveToTarget and entry.TargetUserId or nil,
				entry.AllowDownedTarget
			)
			entry.TargetPlayer = player
			targetRoot = root
			entry.Model:SetAttribute("AttractTargetUserId", player and player.UserId or nil)
		end
		if targetRoot then
			local destination = targetRoot.Position + Vector3.new(0, 1.6, 0)
			local offset = destination - entry.Root.Position
			local distance = offset.Magnitude
			if distance <= CONFIG.PickupRadius then
				claim(entry, entry.TargetPlayer, entry.AttractReason or "RoundMagnet")
				return
			end
			entry.MagnetSpeed = math.min(
				CONFIG.MaximumMagnetSpeed,
				entry.MagnetSpeed + CONFIG.MagnetAcceleration * deltaTime
			)
			local step = math.min(distance, entry.MagnetSpeed * deltaTime)
			local nextPosition = entry.Root.Position + offset.Unit * step
			entry.Model:PivotTo(CFrame.new(nextPosition) * CFrame.Angles(0, timestamp * 7, 0))
		end
		return
	end

	local hover = math.sin(timestamp * CONFIG.HoverSpeed + entry.Phase) * CONFIG.HoverAmplitude
	entry.Model:PivotTo(
		CFrame.new(entry.BasePosition + Vector3.new(0, hover, 0))
			* CFrame.Angles(0, timestamp * 2.1 + entry.Phase, 0)
	)
	local player, _, distance = nearestEligiblePlayer(
		entry.Root.Position,
		entry.ExclusiveToTarget and entry.TargetUserId or nil,
		entry.AllowDownedTarget
	)
	if player and distance <= CONFIG.PickupRadius then
		claim(entry, player, "Proximity")
	end
end

local function heartbeat(deltaTime)
	accumulatedDelta += deltaTime
	if accumulatedDelta < CONFIG.UpdateInterval then
		return
	end
	local stepDelta = accumulatedDelta
	accumulatedDelta = 0
	local timestamp = now()
	local snapshot = {}
	for _, entry in pairs(active) do
		table.insert(snapshot, entry)
	end
	for _, entry in ipairs(snapshot) do
		stepEntry(entry, stepDelta, timestamp)
	end
end

function MobCollectibleService.Start(options)
	if started then
		return
	end
	options = type(options) == "table" and options or {}
	started = true
	sessionId = tostring(options.SessionId or "")
	participantSet = {}
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
		end
	end
	workspace:SetAttribute("DungeonMobCollectibleVersion", 2)
	workspace:SetAttribute("DungeonMobCollectiblePickupRadius", CONFIG.PickupRadius)
	workspace:SetAttribute("DungeonMobCollectibleRoundMagnetEnabled", true)
	workspace:SetAttribute("DungeonMobCollectibleGUIAnimationDisabled", true)
	workspace:SetAttribute("DungeonBossRewardCollectibleSupported", true)
	workspace:SetAttribute("DungeonMobCollectibleSpawnedCount", 0)
	workspace:SetAttribute("DungeonMobCollectibleClaimedCount", 0)
	updateWorkspaceCounters()
	heartbeatConnection = RunService.Heartbeat:Connect(heartbeat)
end

function MobCollectibleService.Stop()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	for _, entry in pairs(active) do
		if entry.Model.Parent then
			entry.Model:Destroy()
		end
	end
	active = {}
	activeCount = 0
	participantSet = {}
	sessionId = ""
	started = false
	workspace:SetAttribute("DungeonMobCollectibleReady", false)
	workspace:SetAttribute("DungeonMobCollectibleActiveCount", 0)
end

function MobCollectibleService.GetSnapshot()
	local byRound = { [1] = 0, [2] = 0, [3] = 0 }
	local coinValue = 0
	for _, entry in pairs(active) do
		if entry.Model.Parent and not entry.Claimed then
			byRound[entry.RoundIndex] = (byRound[entry.RoundIndex] or 0) + 1
			coinValue += entry.Amount
		end
	end
	return {
		Started = started,
		SessionId = sessionId,
		Policy = POLICY,
		ActiveCount = activeCount,
		PendingCoinValue = coinValue,
		ByRound = byRound,
	}
end

return MobCollectibleService
