local Players = game:GetService("Players")

local DungeonHealthRecoveryService = {}

local DEFAULT_REGEN_DELAY_SECONDS = 5
local DEFAULT_REGEN_PERCENT_PER_SECOND = 0.04
local DEFAULT_OBJECTIVE_HEAL_PERCENT = 0.15
local DEFAULT_REWARD_HEAL_PERCENT = 0.40
local DEFAULT_BOSS_HEAL_PERCENT = 1
local DEFAULT_TICK_SECONDS = 0.25
local HEALTH_EPSILON = 0.01

local started = false
local generation = 0
local settings = {}
local participantSet = {}
local playerBindings = setmetatable({}, { __mode = "k" })
local characterBindings = setmetatable({}, { __mode = "k" })
local lastHealthByPlayer = setmetatable({}, { __mode = "k" })
local lastDamageAtByPlayer = setmetatable({}, { __mode = "k" })
local serviceConnections = {}

local function now()
	return workspace:GetServerTimeNow()
end

local function disconnect(connection)
	if connection then
		connection:Disconnect()
	end
end

local function participantPlayer(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Parent == Players then
		return player
	end
	return nil
end

local function isParticipant(player)
	return player ~= nil
		and player.Parent == Players
		and participantSet[player.UserId] == true
end

local function livingHumanoid(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and humanoid.MaxHealth > 0 then
		return humanoid, character
	end
	return nil, character
end

local function isActiveForRecovery(player)
	if not isParticipant(player) then
		return false
	end
	if player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
	then
		return false
	end
	local lifeState = player:GetAttribute("DungeonLifeState")
	if lifeState ~= nil and lifeState ~= "Active" then
		return false
	end
	local humanoid = livingHumanoid(player)
	return humanoid ~= nil
end

local function publishPlayerRecoveryState(player, regenerating)
	if not player or player.Parent ~= Players then
		return
	end
	player:SetAttribute("DungeonHealthRegenerating", regenerating == true)
	player:SetAttribute("DungeonHealthRecoveryBound", characterBindings[player] ~= nil)
end

local function recordDamage(player, currentHealth, previousHealth)
	local timestamp = now()
	lastDamageAtByPlayer[player] = timestamp
	player:SetAttribute("DungeonLastDamageAt", timestamp)
	player:SetAttribute("DungeonLastDamageAmount", math.max(0, previousHealth - currentHealth))
	player:SetAttribute("DungeonHealthRegenStartsAt", timestamp + settings.RegenDelaySeconds)
	publishPlayerRecoveryState(player, false)
end

local function clearCharacterBinding(player)
	local binding = characterBindings[player]
	if binding then
		disconnect(binding.HealthChanged)
		disconnect(binding.AncestryChanged)
		characterBindings[player] = nil
	end
	lastHealthByPlayer[player] = nil
	publishPlayerRecoveryState(player, false)
end

local function bindCharacter(player, character)
	if not started or not isParticipant(player) or player.Character ~= character then
		return false
	end
	clearCharacterBinding(player)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or player.Character ~= character then
		return false
	end
	lastHealthByPlayer[player] = humanoid.Health
	lastDamageAtByPlayer[player] = lastDamageAtByPlayer[player] or now()
	player:SetAttribute("DungeonHealthRegenStartsAt", lastDamageAtByPlayer[player] + settings.RegenDelaySeconds)
	characterBindings[player] = {
		Humanoid = humanoid,
		Character = character,
	}
	characterBindings[player].HealthChanged = humanoid.HealthChanged:Connect(function(currentHealth)
		local previousHealth = lastHealthByPlayer[player]
		lastHealthByPlayer[player] = currentHealth
		if previousHealth ~= nil and currentHealth + HEALTH_EPSILON < previousHealth then
			recordDamage(player, currentHealth, previousHealth)
		end
	end)
	characterBindings[player].AncestryChanged = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and characterBindings[player]
			and characterBindings[player].Character == character
		then
			clearCharacterBinding(player)
		end
	end)
	publishPlayerRecoveryState(player, false)
	return true
end

local function clearPlayerBinding(player)
	local binding = playerBindings[player]
	if binding then
		disconnect(binding.CharacterAdded)
		disconnect(binding.CharacterRemoving)
		playerBindings[player] = nil
	end
	clearCharacterBinding(player)
	lastDamageAtByPlayer[player] = nil
	if player and player.Parent == Players then
		player:SetAttribute("DungeonHealthRecoveryBound", false)
		player:SetAttribute("DungeonHealthRegenerating", false)
	end
end

function DungeonHealthRecoveryService.BindPlayer(player)
	if not started or not isParticipant(player) then
		return false, "NotRecoveryParticipant"
	end
	if playerBindings[player] then
		if player.Character and not characterBindings[player] then
			task.spawn(bindCharacter, player, player.Character)
		end
		return true
	end
	playerBindings[player] = {
		CharacterAdded = player.CharacterAdded:Connect(function(character)
			task.spawn(bindCharacter, player, character)
		end),
		CharacterRemoving = player.CharacterRemoving:Connect(function(character)
			local binding = characterBindings[player]
			if binding and binding.Character == character then
				clearCharacterBinding(player)
			end
		end),
	}
	player:SetAttribute("DungeonHealthRecoveryVersion", "MVP1")
	if player.Character then
		task.spawn(bindCharacter, player, player.Character)
	end
	return true
end

local function applyHeal(player, percent, reason, forceFull)
	if not isActiveForRecovery(player) then
		return false, 0, "PlayerNotActive"
	end
	local humanoid = livingHumanoid(player)
	if not humanoid then
		return false, 0, "HumanoidUnavailable"
	end
	local before = humanoid.Health
	local target
	if forceFull == true or percent >= 1 then
		target = humanoid.MaxHealth
	else
		target = math.min(humanoid.MaxHealth, before + humanoid.MaxHealth * math.max(0, percent))
	end
	if target <= before + HEALTH_EPSILON then
		return true, 0, "AlreadyFull"
	end
	humanoid.Health = target
	lastHealthByPlayer[player] = target
	local amount = target - before
	player:SetAttribute("DungeonLastHealAt", now())
	player:SetAttribute("DungeonLastHealReason", tostring(reason or "DungeonHeal"))
	player:SetAttribute("DungeonLastHealAmount", amount)
	player:SetAttribute("DungeonLastHealPercent", forceFull == true and 1 or percent)
	return true, amount
end

function DungeonHealthRecoveryService.HealPlayer(player, percent, reason, forceFull)
	percent = math.clamp(tonumber(percent) or 0, 0, 1)
	return applyHeal(player, percent, reason, forceFull == true)
end

function DungeonHealthRecoveryService.HealParticipants(percent, reason, forceFull)
	if not started then
		return false, {
			Reason = "HealthRecoveryNotStarted",
			PlayerCount = 0,
			TotalAmount = 0,
		}
	end
	percent = math.clamp(tonumber(percent) or 0, 0, 1)
	local healedPlayers = 0
	local totalAmount = 0
	for userId in pairs(participantSet) do
		local player = participantPlayer(userId)
		if player then
			local success, amount = applyHeal(player, percent, reason, forceFull == true)
			if success and amount > 0 then
				healedPlayers += 1
				totalAmount += amount
			end
		end
	end
	workspace:SetAttribute("DungeonLastPartyHealAt", now())
	workspace:SetAttribute("DungeonLastPartyHealReason", tostring(reason or "DungeonPartyHeal"))
	workspace:SetAttribute("DungeonLastPartyHealPercent", forceFull == true and 1 or percent)
	workspace:SetAttribute("DungeonLastPartyHealPlayerCount", healedPlayers)
	workspace:SetAttribute("DungeonLastPartyHealAmount", totalAmount)
	return true, {
		Reason = tostring(reason or "DungeonPartyHeal"),
		PlayerCount = healedPlayers,
		TotalAmount = totalAmount,
		Percent = forceFull == true and 1 or percent,
	}
end

local function regeneratePlayer(player, elapsed, timestamp)
	if not isActiveForRecovery(player) then
		publishPlayerRecoveryState(player, false)
		return 0
	end
	local humanoid = livingHumanoid(player)
	if not humanoid or humanoid.Health >= humanoid.MaxHealth - HEALTH_EPSILON then
		publishPlayerRecoveryState(player, false)
		return 0
	end
	local lastDamageAt = lastDamageAtByPlayer[player] or timestamp
	local startsAt = lastDamageAt + settings.RegenDelaySeconds
	player:SetAttribute("DungeonHealthRegenStartsAt", startsAt)
	if timestamp < startsAt then
		publishPlayerRecoveryState(player, false)
		return 0
	end
	local before = humanoid.Health
	local amount = humanoid.MaxHealth * settings.RegenPercentPerSecond * elapsed
	humanoid.Health = math.min(humanoid.MaxHealth, before + amount)
	lastHealthByPlayer[player] = humanoid.Health
	local restored = humanoid.Health - before
	publishPlayerRecoveryState(player, restored > 0)
	if restored > 0 then
		player:SetAttribute("DungeonLastRegenerationAt", timestamp)
		player:SetAttribute("DungeonLastRegenerationAmount", restored)
	end
	return restored
end

local function startWorker(token)
	task.spawn(function()
		local lastTickAt = now()
		while started and token == generation do
			task.wait(settings.TickSeconds)
			local timestamp = now()
			local elapsed = math.clamp(timestamp - lastTickAt, 0, settings.TickSeconds * 2)
			lastTickAt = timestamp
			local regeneratingPlayers = 0
			for userId in pairs(participantSet) do
				local player = participantPlayer(userId)
				if player and regeneratePlayer(player, elapsed, timestamp) > 0 then
					regeneratingPlayers += 1
				end
			end
			workspace:SetAttribute("DungeonHealthRegeneratingPlayerCount", regeneratingPlayers)
		end
	end)
end

function DungeonHealthRecoveryService.Start(startOptions)
	if started then
		return true
	end
	startOptions = type(startOptions) == "table" and startOptions or {}
	settings = {
		RegenDelaySeconds = math.max(0.5, tonumber(startOptions.RegenDelaySeconds) or DEFAULT_REGEN_DELAY_SECONDS),
		RegenPercentPerSecond = math.clamp(
			tonumber(startOptions.RegenPercentPerSecond) or DEFAULT_REGEN_PERCENT_PER_SECOND,
			0.001,
			1
		),
		ObjectiveHealPercent = math.clamp(
			tonumber(startOptions.ObjectiveHealPercent) or DEFAULT_OBJECTIVE_HEAL_PERCENT,
			0,
			1
		),
		RewardHealPercent = math.clamp(
			tonumber(startOptions.RewardHealPercent) or DEFAULT_REWARD_HEAL_PERCENT,
			0,
			1
		),
		BossHealPercent = math.clamp(
			tonumber(startOptions.BossHealPercent) or DEFAULT_BOSS_HEAL_PERCENT,
			0,
			1
		),
		TickSeconds = math.clamp(tonumber(startOptions.TickSeconds) or DEFAULT_TICK_SECONDS, 0.1, 1),
	}
	participantSet = {}
	for _, rawUserId in ipairs(startOptions.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
		end
	end
	started = true
	generation += 1
	workspace:SetAttribute("DungeonHealthRecoveryReady", true)
	workspace:SetAttribute("DungeonHealthRecoveryPolicy", "FiveSecondOutOfCombat")
	workspace:SetAttribute("DungeonHealthRegenDelaySeconds", settings.RegenDelaySeconds)
	workspace:SetAttribute("DungeonHealthRegenPercentPerSecond", settings.RegenPercentPerSecond)
	workspace:SetAttribute("DungeonObjectiveHealPercent", settings.ObjectiveHealPercent)
	workspace:SetAttribute("DungeonRewardIslandHealPercent", settings.RewardHealPercent)
	workspace:SetAttribute("DungeonBossPreparationHealPercent", settings.BossHealPercent)
	workspace:SetAttribute("DungeonHealthRecoveryTickSeconds", settings.TickSeconds)
	workspace:SetAttribute("DungeonHealthRegeneratingPlayerCount", 0)
	serviceConnections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
		if participantSet[player.UserId] then
			DungeonHealthRecoveryService.BindPlayer(player)
		end
	end)
	serviceConnections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
		clearPlayerBinding(player)
	end)
	for userId in pairs(participantSet) do
		local player = participantPlayer(userId)
		if player then
			DungeonHealthRecoveryService.BindPlayer(player)
		end
	end
	startWorker(generation)
	return true
end

function DungeonHealthRecoveryService.Stop()
	if not started then
		return
	end
	started = false
	generation += 1
	for _, connection in pairs(serviceConnections) do
		disconnect(connection)
	end
	serviceConnections = {}
	local players = {}
	for player in pairs(playerBindings) do
		table.insert(players, player)
	end
	for _, player in ipairs(players) do
		clearPlayerBinding(player)
	end
	participantSet = {}
	workspace:SetAttribute("DungeonHealthRecoveryReady", false)
	workspace:SetAttribute("DungeonHealthRegeneratingPlayerCount", 0)
end

function DungeonHealthRecoveryService.GetSettings()
	return table.clone(settings)
end

function DungeonHealthRecoveryService.GetSnapshot()
	local participants = 0
	for _ in pairs(participantSet) do
		participants += 1
	end
	return {
		Ready = started,
		ParticipantCount = participants,
		RegeneratingPlayerCount = tonumber(workspace:GetAttribute("DungeonHealthRegeneratingPlayerCount")) or 0,
		Settings = table.clone(settings),
	}
end

return DungeonHealthRecoveryService
