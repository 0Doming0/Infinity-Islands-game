-- Centraliza Analytics de onboarding e gameplay. Todas as chamadas ao
-- AnalyticsService partem do servidor e sao isoladas por pcall.

local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local PlayerDataService = require(
	script.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local CONFIG = MVPConfig.Analytics or {}
local SAFE_CONFIG = MVPConfig.SafeZones or {}

local GameplayAnalytics = {}
local started = false
local states = setmetatable({}, { __mode = "k" })

local ONBOARDING_STEPS = table.freeze({
	"PlayerJoined",
	"EnteredFirstSanctuary",
	"ExitedFirstSanctuary",
	"ReachedFirstIsland",
	"FirstEnemyEncountered",
	"FirstEnemyAttacked",
	"FirstEnemyDefeated",
	"FirstChestFound",
	"FirstChestOpened",
	"FirstCoinsEarned",
	"FirstCompanionObtained",
	"FirstCompanionEquipped",
	"ReachedSecondIsland",
	"ReturnedToSanctuary",
	"ReachedNextSanctuary",
	"FirstExpeditionCompleted",
})

local STEP_INDEX = {}
for index, name in ipairs(ONBOARDING_STEPS) do
	STEP_INDEX[name] = index
end

local VALID_DEATH_CAUSES = table.freeze({
	RisingWater = true,
	Slime = true,
	EliteEnemy = true,
	MimicChest = true,
	Void = true,
	Fall = true,
	PlayerCombat = true,
	Unknown = true,
})

local function debugLog(message)
	if CONFIG.DebugLogs == true or SAFE_CONFIG.DebugLogs == true then
		print("[GameplayAnalytics] " .. message)
	end
end

local function stateFor(player)
	return states[player]
end

local function elapsedSince(timestamp)
	return math.max(0, math.floor(os.clock() - (timestamp or os.clock()) + 0.5))
end

local function cleanField(value, fallback)
	local text = tostring(value or fallback or "Unknown")
	text = string.gsub(text, "[%c]", "")
	if #text > 50 then
		text = string.sub(text, 1, 50)
	end
	return text ~= "" and text or tostring(fallback or "Unknown")
end

local function customFields(first, second, third)
	return {
		CustomField01 = cleanField(first),
		CustomField02 = cleanField(second),
		CustomField03 = cleanField(third),
	}
end

local function safeAnalyticsCall(label, callback)
	if CONFIG.Enabled == false then
		return false
	end
	debugLog("evento solicitado: " .. label)
	local success, errorMessage = pcall(callback)
	if not success then
		if CONFIG.DebugLogs == true or SAFE_CONFIG.DebugLogs == true then
			warn(string.format("[GameplayAnalytics] %s falhou: %s", label, tostring(errorMessage)))
		end
		return false
	end
	return true
end

local function logCustom(player, eventName, value, fields, essential)
	local state = stateFor(player)
	if not state or player.Parent ~= Players then
		return false
	end
	local now = os.clock()
	if essential ~= true then
		local cooldown = math.max(
			0,
			tonumber(CONFIG.NonEssentialCooldownSeconds)
				or tonumber(SAFE_CONFIG.NonEssentialAnalyticsCooldownSeconds)
				or 5
		)
		if now - (state.EventCooldowns[eventName] or -math.huge) < cooldown then
			return false
		end
		state.EventCooldowns[eventName] = now
	end
	return safeAnalyticsCall(eventName, function()
		AnalyticsService:LogCustomEvent(
			player,
			eventName,
			math.max(0, tonumber(value) or 0),
			fields or customFields("Unknown", "Unknown", "Unknown")
		)
	end)
end

local function normalizeDeathCause(rawCause)
	local raw = string.lower(tostring(rawCause or ""))
	if string.find(raw, "water", 1, true) or string.find(raw, "flood", 1, true) then
		return "RisingWater"
	elseif string.find(raw, "mimic", 1, true) then
		return "MimicChest"
	elseif string.find(raw, "elite", 1, true) or string.find(raw, "boss", 1, true) then
		return "EliteEnemy"
	elseif string.find(raw, "slime", 1, true) or string.find(raw, "monster", 1, true) then
		return "Slime"
	elseif string.find(raw, "player", 1, true) or string.find(raw, "pvp", 1, true) then
		return "PlayerCombat"
	elseif string.find(raw, "void", 1, true) then
		return "Void"
	elseif raw ~= "combatorfall" and string.find(raw, "fall", 1, true) then
		return "Fall"
	end
	return VALID_DEATH_CAUSES[rawCause] and rawCause or "Unknown"
end

local function islandCategory(level, isSanctuary)
	level = math.max(0, math.floor(tonumber(level) or 0))
	if isSanctuary and level == 0 then
		return "FirstSanctuary"
	elseif level == 0 then
		return "StartIsland"
	elseif level == 1 then
		return "FirstIsland"
	elseif level == 2 then
		return "SecondIsland"
	elseif level <= 4 then
		return "EarlyIslands"
	elseif level <= 10 then
		return "MidIslands"
	end
	return "HighIslands"
end

local function sanctuaryCategory(level, isEmergency)
	if isEmergency == true then
		return "EmergencySanctuary"
	elseif (tonumber(level) or 0) <= 0 then
		return "FirstSanctuary"
	end
	return "IntermediateSanctuary"
end

local function currentRegionCategory(player)
	return islandCategory(
		player:GetAttribute("CurrentLogicalLevel"),
		player:GetAttribute("InSocialSanctuary") == true
	)
end

local function currentStage(state)
	return state.LastStage ~= "" and state.LastStage or "BeforeFirstIsland"
end

local function initializePlayer(player)
	if states[player] then
		return states[player]
	end
	local now = os.clock()
	local state = {
		JoinedAt = now,
		LifeStartedAt = now,
		ExpeditionStartedAt = now,
		CurrentRegion = "StartIsland",
		CurrentSanctuary = nil,
		LastStage = "PlayerJoined",
		LastDamageCause = nil,
		LastDamageAt = nil,
		Deaths = 0,
		Rescues = 0,
		FirstSent = {},
		AchievedSteps = {},
		HighestOnboardingStep = 0,
		InsideSanctuary = false,
		FirstWaterDamage = false,
		FirstWaterDeath = false,
		FirstCycleCompleted = false,
		EventCooldowns = {},
		LastDeathCharacter = nil,
		FirstSanctuaryKey = nil,
		HasExitedFirstSanctuary = false,
		PersistenceResolved = false,
	}
	states[player] = state
	GameplayAnalytics.RecordOnboardingStep(player, "PlayerJoined", customFields(
		"SessionStart",
		"UnknownRegion",
		"NewSession"
	))
	task.spawn(function()
		PlayerDataService.Load(player)
		if player.Parent ~= Players or states[player] ~= state then
			return
		end
		local persistedOnboardingComplete = PlayerDataService.GetAnalyticsOnboardingCompleted(player)
		state.PersistenceResolved = true
		if persistedOnboardingComplete then
			for _, stepName in ipairs(ONBOARDING_STEPS) do
				state.FirstSent[stepName] = true
				state.AchievedSteps[stepName] = true
			end
			state.HighestOnboardingStep = #ONBOARDING_STEPS
			state.FirstCycleCompleted = true
			state.LastStage = "FirstExpeditionCompleted"
			player:SetAttribute("AnalyticsOnboardingStep", #ONBOARDING_STEPS)
			player:SetAttribute("AnalyticsOnboardingStage", "FirstExpeditionCompleted")
		else
			GameplayAnalytics.RecordOnboardingStep(player, "PlayerJoined", customFields(
				"SessionStart",
				"UnknownRegion",
				"NewSession"
			))
		end
	end)
	return state
end

local function drainOnboarding(player, state)
	if state.PersistenceResolved ~= true then
		return
	end
	while state.HighestOnboardingStep < #ONBOARDING_STEPS do
		local nextIndex = state.HighestOnboardingStep + 1
		local stepName = ONBOARDING_STEPS[nextIndex]
		local fields = state.AchievedSteps[stepName]
		if not fields then
			break
		end
		state.HighestOnboardingStep = nextIndex
		state.FirstSent[stepName] = true
		state.LastStage = stepName
		player:SetAttribute("AnalyticsOnboardingStep", nextIndex)
		player:SetAttribute("AnalyticsOnboardingStage", stepName)
		safeAnalyticsCall("Onboarding:" .. stepName, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, nextIndex, stepName, fields)
		end)
		logCustom(player, stepName, elapsedSince(state.JoinedAt), fields, true)
	end
end

function GameplayAnalytics.RecordOnboardingStep(player, stepName, fields)
	local state = stateFor(player) or initializePlayer(player)
	if not state or not STEP_INDEX[stepName] or state.FirstSent[stepName] then
		return false
	end
	if not state.AchievedSteps[stepName] then
		state.AchievedSteps[stepName] = fields or customFields(
			currentRegionCategory(player),
			currentStage(state),
			"ServerValidated"
		)
	end
	drainOnboarding(player, state)
	return true
end

local function tryCompleteFirstCycle(player)
	local state = stateFor(player)
	if not state
		or state.FirstCycleCompleted
		or not state.AchievedSteps.ReachedNextSanctuary
	then
		return false
	end
	-- Persistimos a conclusao apenas quando todo o caminho 1-15 foi realmente
	-- observado. Isso impede que uma acao fora de ordem esconda um funil parcial.
	for index = 1, #ONBOARDING_STEPS - 1 do
		local requirement = ONBOARDING_STEPS[index]
		if not state.AchievedSteps[requirement] then
			return false
		end
	end
	state.FirstCycleCompleted = true
	local recorded = GameplayAnalytics.RecordOnboardingStep(
		player,
		"FirstExpeditionCompleted",
		customFields(currentRegionCategory(player), "CoreLoopComplete", "ServerValidated")
	)
	task.spawn(function()
		while player.Parent == Players
			and states[player] == state
			and state.PersistenceResolved ~= true
		do
			task.wait(0.1)
		end
		if player.Parent == Players
			and states[player] == state
			and state.HighestOnboardingStep >= #ONBOARDING_STEPS
		then
			PlayerDataService.SetAnalyticsOnboardingCompleted(player)
			PlayerDataService.Save(player, false)
		end
	end)
	return recorded
end

function GameplayAnalytics.RecordCustom(player, eventName, value, first, second, third, essential)
	return logCustom(player, eventName, value, customFields(first, second, third), essential)
end

function GameplayAnalytics.UpdateStage(player, stageName, regionCategory)
	local state = stateFor(player) or initializePlayer(player)
	state.LastStage = cleanField(stageName, state.LastStage)
	state.CurrentRegion = cleanField(regionCategory, state.CurrentRegion)
	player:SetAttribute("AnalyticsGameplayStage", state.LastStage)
end

function GameplayAnalytics.MarkDamageCause(player, rawCause)
	local state = stateFor(player) or initializePlayer(player)
	local cause = normalizeDeathCause(rawCause)
	state.LastDamageCause = cause
	state.LastDamageAt = workspace:GetServerTimeNow()
	player:SetAttribute("AnalyticsLastDamageCause", cause)
	player:SetAttribute("AnalyticsLastDamageAt", state.LastDamageAt)
	return cause
end

function GameplayAnalytics.RecordDeath(player, character, suggestedCause)
	local state = stateFor(player) or initializePlayer(player)
	if state.LastDeathCharacter == character then
		return false
	end
	state.LastDeathCharacter = character
	state.Deaths += 1
	local now = workspace:GetServerTimeNow()
	local window = math.clamp(tonumber(SAFE_CONFIG.DeathCauseWindowSeconds) or 9, 1, 30)
	local cause = normalizeDeathCause(suggestedCause)
	if state.LastDamageCause and state.LastDamageAt and now - state.LastDamageAt <= window then
		cause = state.LastDamageCause
	elseif cause == "Unknown" then
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local water = workspace:FindFirstChild("Water")
		local waterY = water and tonumber(water:GetAttribute("SurfaceY"))
		if root and waterY and root.Position.Y <= waterY + 2 then
			cause = "RisingWater"
		elseif root and root.AssemblyLinearVelocity.Y < -35 then
			cause = "Fall"
		end
	end
	if not VALID_DEATH_CAUSES[cause] then
		cause = "Unknown"
	end
	local survived = elapsedSince(state.LifeStartedAt)
	logCustom(player, "PlayerDeath", survived, customFields(
		cause,
		currentRegionCategory(player),
		currentStage(state)
	), true)
	if cause == "RisingWater" and not state.FirstWaterDeath then
		state.FirstWaterDeath = true
		logCustom(player, "FirstWaterDeath", survived, customFields(
			currentRegionCategory(player),
			currentStage(state),
			"RisingWater"
		), true)
	end
	state.LifeStartedAt = os.clock()
	state.LastDamageCause = nil
	state.LastDamageAt = nil
	player:SetAttribute("AnalyticsDeathCount", state.Deaths)
	return true, cause
end

function GameplayAnalytics.RecordSanctuaryEntered(player, context, isRescue)
	local state = stateFor(player) or initializePlayer(player)
	local key = context and context.IslandKey or "Unknown"
	local category = sanctuaryCategory(context and context.LogicalLevel, context and context.IsEmergency)
	local wasInside = state.InsideSanctuary
	local previousKey = state.CurrentSanctuary
	state.InsideSanctuary = true
	state.CurrentSanctuary = key
	state.CurrentRegion = category
	if wasInside and previousKey == key then
		return false
	end
	logCustom(player, "PlayerEnteredSanctuary", elapsedSince(state.ExpeditionStartedAt), customFields(
		category,
		currentStage(state),
		isRescue and "Rescue" or "Exploration"
	), true)
	if not state.FirstSanctuaryKey then
		state.FirstSanctuaryKey = key
		GameplayAnalytics.RecordOnboardingStep(player, "EnteredFirstSanctuary", customFields(
			"FirstSanctuary",
			"SessionStart",
			"ServerZone"
		))
	elseif not isRescue and state.HasExitedFirstSanctuary then
		GameplayAnalytics.RecordOnboardingStep(player, "ReturnedToSanctuary", customFields(
			category,
			currentStage(state),
			"ExplorationReturn"
		))
		if key ~= state.FirstSanctuaryKey then
			GameplayAnalytics.RecordOnboardingStep(player, "ReachedNextSanctuary", customFields(
				category,
				currentStage(state),
				"NaturalProgress"
			))
			tryCompleteFirstCycle(player)
		end
	end
	return true
end

function GameplayAnalytics.RecordSanctuaryExited(player, context)
	local state = stateFor(player) or initializePlayer(player)
	if not state.InsideSanctuary then
		return false
	end
	local category = sanctuaryCategory(context and context.LogicalLevel, context and context.IsEmergency)
	state.InsideSanctuary = false
	state.HasExitedFirstSanctuary = true
	state.ExpeditionStartedAt = os.clock()
	logCustom(player, "PlayerExitedSanctuary", elapsedSince(state.JoinedAt), customFields(
		category,
		currentStage(state),
		"ExplorationStart"
	), true)
	GameplayAnalytics.RecordOnboardingStep(player, "ExitedFirstSanctuary", customFields(
		category,
		"ExplorationStart",
		"ServerZone"
	))
	return true
end

function GameplayAnalytics.RecordSanctuarySubmerged(players, context)
	local category = sanctuaryCategory(context and context.LogicalLevel, context and context.IsEmergency)
	for _, player in ipairs(players or {}) do
		local state = stateFor(player) or initializePlayer(player)
		logCustom(player, "SanctuarySubmerged", elapsedSince(state.JoinedAt), customFields(
			category,
			currentStage(state),
			"RisingWater"
		), true)
	end
end

function GameplayAnalytics.RecordPlayerRescued(player, origin, destination)
	local state = stateFor(player) or initializePlayer(player)
	state.Rescues += 1
	logCustom(player, "PlayerRescuedFromSanctuary", elapsedSince(state.ExpeditionStartedAt), customFields(
		sanctuaryCategory(origin and origin.LogicalLevel, origin and origin.IsEmergency),
		sanctuaryCategory(destination and destination.LogicalLevel, destination and destination.IsEmergency),
		currentStage(state)
	), true)
	player:SetAttribute("AnalyticsRescueCount", state.Rescues)
end

function GameplayAnalytics.RecordEmergencySanctuaryCreated(player, context)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "EmergencySanctuaryCreated", elapsedSince(state.JoinedAt), customFields(
		"EmergencySanctuary",
		islandCategory(context and context.LogicalLevel, true),
		currentStage(state)
	), true)
end

function GameplayAnalytics.RecordRescueTeleportFailed(player, reason, destination)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "RescueTeleportFailed", elapsedSince(state.JoinedAt), customFields(
		cleanField(reason, "Unknown"),
		sanctuaryCategory(destination and destination.LogicalLevel, destination and destination.IsEmergency),
		currentStage(state)
	), true)
end

function GameplayAnalytics.RecordSanctuaryIdle(player, context)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "PlayerIdleInSanctuary", elapsedSince(state.JoinedAt), customFields(
		sanctuaryCategory(context and context.LogicalLevel, context and context.IsEmergency),
		currentStage(state),
		"SafeIdle"
	), false)
end

function GameplayAnalytics.RecordWaterWarning(player)
	local state = stateFor(player) or initializePlayer(player)
	if state.FirstSent.WaterWarningShown then
		return
	end
	state.FirstSent.WaterWarningShown = true
	logCustom(player, "WaterWarningShown", elapsedSince(state.JoinedAt), customFields(
		currentRegionCategory(player), currentStage(state), "Warning"
	), true)
end

function GameplayAnalytics.RecordWaterStarted(player)
	local state = stateFor(player) or initializePlayer(player)
	if state.FirstSent.WaterStarted then
		return
	end
	state.FirstSent.WaterStarted = true
	logCustom(player, "WaterStarted", elapsedSince(state.JoinedAt), customFields(
		currentRegionCategory(player), currentStage(state), "RisingWater"
	), true)
end

function GameplayAnalytics.RecordWaterDamage(player)
	local state = stateFor(player) or initializePlayer(player)
	GameplayAnalytics.MarkDamageCause(player, "RisingWater")
	if state.FirstWaterDamage then
		return
	end
	state.FirstWaterDamage = true
	logCustom(player, "FirstWaterDamage", elapsedSince(state.ExpeditionStartedAt), customFields(
		currentRegionCategory(player), currentStage(state), "RisingWater"
	), true)
end

local function enemyCategory(enemy)
	if not enemy then
		return "UnknownEnemy"
	end
	local monsterId = tostring(enemy:GetAttribute("MonsterId") or enemy.Name)
	if enemy:GetAttribute("IsMimic") == true or string.find(monsterId, "Mimic", 1, true) then
		return "MimicChest"
	elseif enemy:GetAttribute("IsElite") == true then
		return "EliteEnemy"
	elseif string.find(string.lower(monsterId), "slime", 1, true) then
		return "Slime"
	end
	return "OtherEnemy"
end

function GameplayAnalytics.RecordEnemyEncountered(player, enemy)
	local state = stateFor(player) or initializePlayer(player)
	GameplayAnalytics.RecordOnboardingStep(player, "FirstEnemyEncountered", customFields(
		enemyCategory(enemy), currentRegionCategory(player), currentStage(state)
	))
end

function GameplayAnalytics.RecordEnemyAttacked(player, enemy, weapon)
	local state = stateFor(player) or initializePlayer(player)
	if not state.AchievedSteps.FirstEnemyEncountered then
		GameplayAnalytics.RecordEnemyEncountered(player, enemy)
	end
	GameplayAnalytics.RecordOnboardingStep(player, "FirstEnemyAttacked", customFields(
		enemyCategory(enemy), currentRegionCategory(player), cleanField(weapon, "Sword")
	))
end

function GameplayAnalytics.RecordEnemyDefeated(player, enemy, weapon)
	local state = stateFor(player) or initializePlayer(player)
	if not state.AchievedSteps.FirstEnemyAttacked then
		GameplayAnalytics.RecordEnemyAttacked(player, enemy, weapon)
	end
	GameplayAnalytics.RecordOnboardingStep(player, "FirstEnemyDefeated", customFields(
		enemyCategory(enemy), currentRegionCategory(player), cleanField(weapon, "UnknownWeapon")
	))
	tryCompleteFirstCycle(player)
end

function GameplayAnalytics.RecordPlayerDamagedByEnemy(player, source)
	local state = stateFor(player) or initializePlayer(player)
	GameplayAnalytics.MarkDamageCause(player, source)
	if state.FirstSent.PlayerDamagedByFirstEnemy then
		return
	end
	state.FirstSent.PlayerDamagedByFirstEnemy = true
	logCustom(player, "PlayerDamagedByFirstEnemy", elapsedSince(state.ExpeditionStartedAt), customFields(
		normalizeDeathCause(source), currentRegionCategory(player), currentStage(state)
	), true)
end

function GameplayAnalytics.RecordChestFound(player, chestType)
	local state = stateFor(player) or initializePlayer(player)
	GameplayAnalytics.RecordOnboardingStep(player, "FirstChestFound", customFields(
		cleanField(chestType, "NormalChest"), currentRegionCategory(player), currentStage(state)
	))
end

function GameplayAnalytics.RecordChestOpened(player, chestType, rewardCategory)
	local state = stateFor(player) or initializePlayer(player)
	if not state.AchievedSteps.FirstChestFound then
		GameplayAnalytics.RecordChestFound(player, chestType)
	end
	local fields = customFields(
		cleanField(chestType, "NormalChest"),
		currentRegionCategory(player),
		cleanField(rewardCategory, "Coins")
	)
	logCustom(player, "ChestOpened", elapsedSince(state.ExpeditionStartedAt), fields, true)
	GameplayAnalytics.RecordOnboardingStep(player, "FirstChestOpened", fields)
	tryCompleteFirstCycle(player)
end

function GameplayAnalytics.RecordMimicTriggered(player)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "MimicChestTriggered", elapsedSince(state.ExpeditionStartedAt), customFields(
		"MimicChest", currentRegionCategory(player), currentStage(state)
	), true)
end

function GameplayAnalytics.RecordChestRewardCollected(player, rewardCategory)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "ChestRewardCollected", elapsedSince(state.ExpeditionStartedAt), customFields(
		cleanField(rewardCategory, "Coins"), currentRegionCategory(player), currentStage(state)
	), true)
end

function GameplayAnalytics.RecordCoinsEarned(player, source, amount)
	local state = stateFor(player) or initializePlayer(player)
	GameplayAnalytics.RecordOnboardingStep(player, "FirstCoinsEarned", customFields(
		cleanField(source, "Gameplay"), currentRegionCategory(player), currentStage(state)
	))
end

local function recordFirstGameplayEvent(player, eventName, first, second, third)
	local state = stateFor(player) or initializePlayer(player)
	if state.FirstSent[eventName] then
		return false
	end
	state.FirstSent[eventName] = true
	return logCustom(player, eventName, elapsedSince(state.ExpeditionStartedAt), customFields(
		first,
		second,
		third
	), true)
end

function GameplayAnalytics.RecordItemObtained(player, itemCategory, source)
	return recordFirstGameplayEvent(
		player,
		"FirstItemObtained",
		cleanField(itemCategory, "OtherItem"),
		cleanField(source, "Gameplay"),
		currentRegionCategory(player)
	)
end

function GameplayAnalytics.RecordWeaponEquipped(player, weaponCategory)
	return recordFirstGameplayEvent(
		player,
		"FirstWeaponEquipped",
		cleanField(weaponCategory, "Sword"),
		currentRegionCategory(player),
		"ServerEquip"
	)
end

function GameplayAnalytics.RecordUpgradePurchased(player, upgradeCategory, source)
	return recordFirstGameplayEvent(
		player,
		"FirstUpgradePurchased",
		cleanField(upgradeCategory, "OtherUpgrade"),
		cleanField(source, "Merchant"),
		currentRegionCategory(player)
	)
end

function GameplayAnalytics.RecordMerchantOpened(player, merchantCategory)
	return recordFirstGameplayEvent(
		player,
		"FirstMerchantOpened",
		cleanField(merchantCategory, "Merchant"),
		currentRegionCategory(player),
		"ServerPrompt"
	)
end

function GameplayAnalytics.RecordMerchantPurchase(player, itemCategory, merchantCategory)
	return recordFirstGameplayEvent(
		player,
		"FirstMerchantPurchase",
		cleanField(itemCategory, "OtherItem"),
		cleanField(merchantCategory, "Merchant"),
		currentRegionCategory(player)
	)
end

function GameplayAnalytics.RecordCompanionObtained(player, companionType, origin)
	local state = stateFor(player) or initializePlayer(player)
	local fields = customFields(
		cleanField(companionType, "OtherCompanion"),
		cleanField(origin, "Other"),
		currentStage(state)
	)
	logCustom(player, "CompanionObtained", elapsedSince(state.ExpeditionStartedAt), fields, true)
	GameplayAnalytics.RecordOnboardingStep(player, "FirstCompanionObtained", fields)
	tryCompleteFirstCycle(player)
end

function GameplayAnalytics.RecordCompanionEquipped(player, companionType)
	local state = stateFor(player) or initializePlayer(player)
	local fields = customFields(
		cleanField(companionType, "OtherCompanion"), currentRegionCategory(player), currentStage(state)
	)
	logCustom(player, "CompanionEquipped", elapsedSince(state.ExpeditionStartedAt), fields, true)
	GameplayAnalytics.RecordOnboardingStep(player, "FirstCompanionEquipped", fields)
	tryCompleteFirstCycle(player)
end

function GameplayAnalytics.RecordCompanionUnequipped(player, companionType)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "CompanionUnequipped", elapsedSince(state.ExpeditionStartedAt), customFields(
		cleanField(companionType, "OtherCompanion"), currentRegionCategory(player), currentStage(state)
	), true)
end

function GameplayAnalytics.RecordCompanionUpgrade(player, companionType, statName)
	local state = stateFor(player) or initializePlayer(player)
	logCustom(player, "CompanionUpgradeCompleted", elapsedSince(state.ExpeditionStartedAt), customFields(
		cleanField(companionType, "OtherCompanion"), cleanField(statName, "OtherUpgrade"), currentStage(state)
	), true)
end

function GameplayAnalytics.RecordIslandReached(player, logicalLevel, isSanctuary, isRescue)
	if isRescue then
		return
	end
	local state = stateFor(player) or initializePlayer(player)
	local level = math.max(0, math.floor(tonumber(logicalLevel) or 0))
	local category = islandCategory(level, isSanctuary)
	state.CurrentRegion = category
	logCustom(player, "ExplorationProgress", elapsedSince(state.ExpeditionStartedAt), customFields(
		category, currentStage(state), isSanctuary and "Sanctuary" or "Island"
	), false)
	if level == 1 then
		GameplayAnalytics.RecordOnboardingStep(player, "ReachedFirstIsland", customFields(
			"FirstIsland", currentStage(state), "NaturalProgress"
		))
	elseif level >= 2 then
		GameplayAnalytics.RecordOnboardingStep(player, "ReachedSecondIsland", customFields(
			"SecondIsland", currentStage(state), "NaturalProgress"
		))
		if not state.FirstSent.FirstIslandCompleted then
			state.FirstSent.FirstIslandCompleted = true
			logCustom(player, "FirstIslandCompleted", elapsedSince(state.ExpeditionStartedAt), customFields(
				"FirstIsland", category, currentStage(state)
			), true)
			safeAnalyticsCall("Progression:FirstIsland", function()
				AnalyticsService:LogProgressionCompleteEvent(
					player,
					"IslandExploration",
					1,
					"FirstIsland",
					customFields(category, currentStage(state), "NaturalProgress")
				)
			end)
		end
	end
end

local function findTaggedAncestor(instance, tagName)
	local current = instance
	while current and current ~= workspace do
		if CollectionService:HasTag(current, tagName) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function observeFirstDiscoveries(player)
	local state = stateFor(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not humanoid or humanoid.Health <= 0 or not root then
		return
	end
	if (state.FirstSent.FirstEnemyEncountered or state.AchievedSteps.FirstEnemyEncountered)
		and (state.FirstSent.FirstChestFound or state.AchievedSteps.FirstChestFound)
	then
		return
	end
	local radius = math.max(
		tonumber(CONFIG.EnemyEncounterDistanceStuds) or 36,
		tonumber(CONFIG.ChestFoundDistanceStuds) or 18
	)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, radius, params)) do
		if not state.FirstSent.FirstEnemyEncountered and not state.AchievedSteps.FirstEnemyEncountered then
			local enemy = findTaggedAncestor(part, "CombatTarget")
			if enemy
				and enemy:GetAttribute("IsCompanion") ~= true
				and (part.Position - root.Position).Magnitude
					<= (tonumber(CONFIG.EnemyEncounterDistanceStuds) or 36)
			then
				GameplayAnalytics.RecordEnemyEncountered(player, enemy)
			end
		end
		if not state.FirstSent.FirstChestFound and not state.AchievedSteps.FirstChestFound then
			local chest = findTaggedAncestor(part, "AnalyticsChest")
			if chest
				and (part.Position - root.Position).Magnitude
					<= (tonumber(CONFIG.ChestFoundDistanceStuds) or 18)
			then
				local chestType = chest:GetAttribute("IsRareChest") == true and "RareChest"
					or (chest:GetAttribute("IsDormantMimicChest") == true and "MimicChest" or "NormalChest")
				GameplayAnalytics.RecordChestFound(player, chestType)
			end
		end
		if (state.FirstSent.FirstEnemyEncountered or state.AchievedSteps.FirstEnemyEncountered)
			and (state.FirstSent.FirstChestFound or state.AchievedSteps.FirstChestFound)
		then
			break
		end
	end
end

local function bindCharacter(player, character)
	local state = stateFor(player) or initializePlayer(player)
	state.LifeStartedAt = os.clock()
	state.LastDamageCause = nil
	state.LastDamageAt = nil
	state.LastDeathCharacter = nil
	character:SetAttribute("AnalyticsLifeStartedAt", workspace:GetServerTimeNow())
end

function GameplayAnalytics.GetSessionState(player)
	local state = stateFor(player)
	if not state then
		return nil
	end
	return {
		JoinedAt = state.JoinedAt,
		LifeStartedAt = state.LifeStartedAt,
		ExpeditionStartedAt = state.ExpeditionStartedAt,
		CurrentRegion = state.CurrentRegion,
		CurrentSanctuary = state.CurrentSanctuary,
		LastStage = state.LastStage,
		LastDamageCause = state.LastDamageCause,
		LastDamageAt = state.LastDamageAt,
		Deaths = state.Deaths,
		Rescues = state.Rescues,
		InsideSanctuary = state.InsideSanctuary,
		FirstWaterDamage = state.FirstWaterDamage,
		FirstCycleCompleted = state.FirstCycleCompleted,
		HighestOnboardingStep = state.HighestOnboardingStep,
	}
end

function GameplayAnalytics.Start()
	if started then
		return
	end
	started = true
	local function onPlayerAdded(player)
		initializePlayer(player)
		player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end)
		if player.Character then
			bindCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	task.spawn(function()
		local interval = math.max(0.2, tonumber(CONFIG.ObservationIntervalSeconds) or 0.5)
		while started do
			for _, player in ipairs(Players:GetPlayers()) do
				observeFirstDiscoveries(player)
			end
			task.wait(interval)
		end
	end)
end

return table.freeze(GameplayAnalytics)
