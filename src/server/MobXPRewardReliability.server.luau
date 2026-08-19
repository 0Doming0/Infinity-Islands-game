--[[
	Infinity Islands - Mob XP Reward Reliability V1

	Additive safety layer around the canonical MobXPCollectibleService.

	Guarantees:
	1. Every player who actually damaged a managed mob receives their own
	   physical XP burst. The final hitter keeps the canonical burst and is not
	   duplicated here.
	2. If a managed mob dies without a resolvable last hitter, XP is recovered
	   for recorded contributors, or for the nearest eligible player on that
	   island when no contributor survived attribution.
	3. A physical XP piece that is still uncollected shortly before its normal
	   lifetime expires is paid directly once, then removed. Earned XP is never
	   silently discarded because the visual collectible timed out.

	This script does not replace damage, XP calculation, level progression or
	physical collectible presentation. It only closes reward-loss paths.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerLevelService = require(
	ServerScriptService.DungeonRuntime:WaitForChild("PlayerLevelService")
)
local MobXPCollectibleService = require(
	ServerScriptService.DungeonRuntime:WaitForChild("MobXPCollectibleService")
)
local MobXPConfig = require(
	ReplicatedStorage.Shared.Configs.MobXPConfig
)
local CollectibleConfig = require(
	ReplicatedStorage.Shared.Configs.MobXPCollectibleConfig
)

local VERSION = "MobXPRewardReliabilityV1"
local TARGET_TAG = "CombatTarget"
local EXPIRY_LEAD_SECONDS = 0.7
local RECENT_COLLECTION_RACE_SECONDS = 0.24

local records = setmetatable({}, { __mode = "k" })
local watchedCollectibles = setmetatable({}, { __mode = "k" })

local contributorBurstCount = 0
local noLastHitterRecoveryCount = 0
local expiryFallbackCount = 0
local directFallbackCount = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function validPlayer(player)
	return player
		and player:IsA("Player")
		and player.Parent == Players
end

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return math.max(1, math.floor(number))
end

local function finalHitter(model, humanoid)
	local userId = model:GetAttribute("LastDamagedByUserId")
		or model:GetAttribute("LastHitUserId")
	if typeof(userId) == "number" then
		local player = Players:GetPlayerByUserId(userId)
		if validPlayer(player) then
			return player
		end
	end

	local creator = humanoid and humanoid:FindFirstChild("creator")
	if creator
		and creator:IsA("ObjectValue")
		and validPlayer(creator.Value)
	then
		return creator.Value
	end
	return nil
end

local function rewardForPlayer(model, player)
	local mobLevel = math.max(
		1,
		math.floor(tonumber(model:GetAttribute("MobLevel")) or 1)
	)
	local riskLevel = math.max(
		1,
		math.floor(tonumber(model:GetAttribute("RecommendedLevel")) or mobLevel)
	)
	local baseReward = math.max(
		1,
		math.floor(
			tonumber(model:GetAttribute("XPReward"))
				or MobXPConfig.GetMobXPReward(
					model:GetAttribute("SlimeVariant"),
					mobLevel,
					model:GetAttribute("XPRewardMultiplier")
				)
		)
	)
	local playerLevel = math.max(
		1,
		math.floor(tonumber(player:GetAttribute("PlayerLevel")) or 1)
	)
	local amount, riskBonus = MobXPConfig.GetAwardForPlayer(
		baseReward,
		riskLevel,
		playerLevel
	)
	return math.max(1, math.floor(tonumber(amount) or 1)), riskBonus, mobLevel, riskLevel
end

local function rewardMetadata(model, mobLevel, riskLevel, riskBonus)
	return {
		MonsterId = model:GetAttribute("MonsterId") or model.Name,
		MobLevel = mobLevel,
		RecommendedLevel = riskLevel,
		GlobalIslandIndex = model:GetAttribute("GlobalIslandIndex"),
		CycleIndex = model:GetAttribute("CycleIndex"),
		XPRewardMultiplier = model:GetAttribute("XPRewardMultiplier"),
		RiskBonus = riskBonus,
	}
end

local function directAward(player, amount, source)
	if not validPlayer(player) or amount <= 0 then
		return false
	end
	local ok, result = pcall(
		PlayerLevelService.AwardXP,
		player,
		amount,
		"XPCollectible:ReliabilityFallback:" .. tostring(source or "Unknown")
	)
	if ok and result == true then
		directFallbackCount += 1
		workspace:SetAttribute("DungeonXPDirectReliabilityFallbackCount", directFallbackCount)
		player:SetAttribute("LastXPReliabilityFallbackAt", now())
		player:SetAttribute("LastXPReliabilityFallbackValue", amount)
		return true
	end
	return false
end

local function spawnReliableBurst(player, model, source)
	if not validPlayer(player) then
		return false
	end

	local amount, riskBonus, mobLevel, riskLevel = rewardForPlayer(model, player)
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	local position = root and root.Position or model:GetPivot().Position
	local metadata = rewardMetadata(model, mobLevel, riskLevel, riskBonus)
	metadata.SourceId = source

	local ok, spawned, errorMessage = pcall(
		MobXPCollectibleService.SpawnXPBurst,
		player,
		position,
		amount,
		metadata
	)
	if ok and spawned == true then
		player:SetAttribute("MobXPDeliveryPolicy", "DamageContributorPhysicalXPV1")
		player:SetAttribute("LastMobXPContributorBurstAt", now())
		player:SetAttribute("LastMobXPContributorBurstValue", amount)
		return true
	end

	local awarded = directAward(player, amount, source)
	if not awarded then
		player:SetAttribute("LastXPReliabilityError", tostring(errorMessage or spawned))
	end
	return awarded
end

local function recordContributor(model)
	local record = records[model]
	if not record then
		return
	end
	local userId = model:GetAttribute("LastDamagedByUserId")
		or model:GetAttribute("LastHitUserId")
	if typeof(userId) ~= "number" then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not validPlayer(player) then
		return
	end
	record.Contributors[userId] = true
	record.LastContributorUserId = userId

	local count = 0
	for _ in pairs(record.Contributors) do
		count += 1
	end
	model:SetAttribute("XPContributorCount", count)
end

local function nearestEligiblePlayer(model)
	local islandIndex = cleanIndex(model:GetAttribute("GlobalIslandIndex"))
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	local origin = root and root.Position or model:GetPivot().Position
	local nearest
	local bestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex")) == islandIndex then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and playerRoot then
				local distance = (playerRoot.Position - origin).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					nearest = player
				end
			end
		end
	end
	return nearest
end

local function handleMobDeath(model, humanoid, record)
	if record.DeathHandled then
		return
	end
	record.DeathHandled = true
	recordContributor(model)

	-- Give the canonical death listener the current scheduler turn first. The
	-- final hitter is deliberately excluded below to avoid a duplicate burst.
	task.defer(function()
		if not model.Parent then
			return
		end

		local killer = finalHitter(model, humanoid)
		local finalUserId = killer and killer.UserId or nil
		local contributorPlayers = {}
		for userId in pairs(record.Contributors) do
			local player = Players:GetPlayerByUserId(userId)
			if validPlayer(player) then
				table.insert(contributorPlayers, player)
			end
		end

		local recovered = 0
		if finalUserId then
			for _, player in ipairs(contributorPlayers) do
				if player.UserId ~= finalUserId
					and spawnReliableBurst(player, model, "DamageContributor")
				then
					recovered += 1
					contributorBurstCount += 1
				end
			end
		else
			-- Canonical service cannot create a burst without attribution. Every
			-- recorded contributor is therefore paid here. If attribution was
			-- entirely lost, recover for the nearest live player on that island.
			if #contributorPlayers > 0 then
				for _, player in ipairs(contributorPlayers) do
					if spawnReliableBurst(player, model, "NoLastHitterContributor") then
						recovered += 1
						contributorBurstCount += 1
					end
				end
			else
				local fallback = nearestEligiblePlayer(model)
				if fallback and spawnReliableBurst(fallback, model, "NoLastHitterNearestPlayer") then
					recovered += 1
				end
			end

			if recovered > 0 then
				noLastHitterRecoveryCount += 1
				workspace:SetAttribute(
					"DungeonXPNoLastHitterRecoveryCount",
					noLastHitterRecoveryCount
				)
			end
		end

		model:SetAttribute("XPRewardReliabilityContributorCount", #contributorPlayers)
		model:SetAttribute("XPRewardReliabilityExtraRecipientCount", recovered)
		model:SetAttribute(
			"XPRewardReliabilityStatus",
			recovered > 0 and "RecoveryApplied" or "CanonicalOnly"
		)
		workspace:SetAttribute("DungeonXPContributorBurstCount", contributorBurstCount)
	end)
end

local function bindMob(model)
	if records[model]
		or not model:IsA("Model")
		or model:GetAttribute("IslandCombatManaged") ~= true
	then
		return
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if not humanoid then
		return
	end

	local record = {
		Contributors = {},
		LastContributorUserId = nil,
		DeathHandled = false,
	}
	records[model] = record
	recordContributor(model)
	model:GetAttributeChangedSignal("LastDamagedByUserId"):Connect(function()
		recordContributor(model)
	end)
	model:GetAttributeChangedSignal("LastHitUserId"):Connect(function()
		recordContributor(model)
	end)
	humanoid.Died:Connect(function()
		handleMobDeath(model, humanoid, record)
	end)
end

local function tryBindMob(instance)
	if not instance:IsA("Model") then
		return
	end
	task.defer(function()
		for _ = 1, 10 do
			if not instance.Parent then
				return
			end
			if instance:GetAttribute("IslandCombatManaged") == true
				and instance:FindFirstChildWhichIsA("Humanoid", true)
			then
				bindMob(instance)
				return
			end
			task.wait(0.05)
		end
	end)
end

local function decrementPending(player)
	if not validPlayer(player) then
		return
	end
	player:SetAttribute(
		"PendingXPCollectibles",
		math.max(
			0,
			math.floor(tonumber(player:GetAttribute("PendingXPCollectibles")) or 0) - 1
		)
	)
end

local function bindCollectible(runtime)
	if watchedCollectibles[runtime]
		or not runtime:IsA("Model")
		or runtime:GetAttribute("IsXPCollectible") ~= true
	then
		return
	end
	watchedCollectibles[runtime] = true

	local lifetime = math.max(1, tonumber(CollectibleConfig.MaximumLifetime) or 14)
	task.delay(math.max(0.1, lifetime - EXPIRY_LEAD_SECONDS), function()
		if not runtime.Parent
			or runtime:GetAttribute("XPExpiryFallbackGranted") == true
		then
			return
		end

		local userId = tonumber(runtime:GetAttribute("TargetUserId"))
		local xpValue = math.max(0, math.floor(tonumber(runtime:GetAttribute("XPValue")) or 0))
		local player = userId and Players:GetPlayerByUserId(userId) or nil
		if not validPlayer(player) or xpValue <= 0 then
			return
		end

		-- Canonical collection leaves the visual around for roughly 0.18s after
		-- awarding. If a same-value collection just happened, wait past that
		-- window and re-check before paying the timeout fallback.
		local lastAt = tonumber(player:GetAttribute("LastXPCollectibleAt")) or 0
		local lastValue = tonumber(player:GetAttribute("LastXPCollectibleValue")) or -1
		if now() - lastAt <= RECENT_COLLECTION_RACE_SECONDS
			and lastValue == xpValue
		then
			task.wait(RECENT_COLLECTION_RACE_SECONDS)
			if not runtime.Parent then
				return
			end
		end

		if runtime:GetAttribute("XPExpiryFallbackGranted") == true then
			return
		end
		runtime:SetAttribute("XPExpiryFallbackGranted", true)

		local source = runtime:GetAttribute("SourceMonsterId")
			or runtime:GetAttribute("MonsterId")
			or runtime.Name
		local ok, result = pcall(
			PlayerLevelService.AwardXP,
			player,
			xpValue,
			"XPCollectible:ExpiryFallback:" .. tostring(source)
		)
		if not ok or result ~= true then
			runtime:SetAttribute("XPExpiryFallbackGranted", nil)
			return
		end

		decrementPending(player)
		expiryFallbackCount += 1
		workspace:SetAttribute("DungeonXPExpiryFallbackCount", expiryFallbackCount)
		player:SetAttribute("LastXPExpiryFallbackAt", now())
		player:SetAttribute("LastXPExpiryFallbackValue", xpValue)
		runtime:Destroy()
	end)
end

local function scanCollectibles()
	local folder = workspace:FindFirstChild(CollectibleConfig.RuntimeFolderName)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		bindCollectible(child)
	end
end

while workspace:GetAttribute("DungeonXPCollectibleServiceReady") ~= true do
	task.wait(0.1)
end

CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(tryBindMob)
for _, target in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
	tryBindMob(target)
end

workspace:SetAttribute("DungeonXPRewardReliabilityReady", true)
workspace:SetAttribute("DungeonXPRewardReliabilityVersion", VERSION)
workspace:SetAttribute(
	"DungeonXPRewardReliabilityPolicy",
	"AllDamageContributors_PhysicalBursts_NoLastHitterFallback_ExpiryProtection"
)
workspace:SetAttribute("DungeonXPContributorBurstCount", 0)
workspace:SetAttribute("DungeonXPNoLastHitterRecoveryCount", 0)
workspace:SetAttribute("DungeonXPExpiryFallbackCount", 0)
workspace:SetAttribute("DungeonXPDirectReliabilityFallbackCount", 0)

while true do
	scanCollectibles()
	task.wait(0.35)
end