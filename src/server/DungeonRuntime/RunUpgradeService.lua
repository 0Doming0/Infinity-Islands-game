local Players = game:GetService("Players")

local RunUpgradeService = {}

local AUTO_PICK_SECONDS = 12
local MAXIMUM_SEED = 2147483647

local UPGRADES = table.freeze({
	{
		Id = "SharpenedEdge",
		Title = "Lâmina Afiada",
		Description = "+20% de dano durante esta expedição.",
		Glyph = "⚔",
		MaxStacks = 3,
	},
	{
		Id = "VitalCore",
		Title = "Núcleo Vital",
		Description = "+20% de vida máxima e cura a vida adicional.",
		Glyph = "♥",
		MaxStacks = 3,
	},
	{
		Id = "SkyImpact",
		Title = "Impacto Celestial",
		Description = "+30% de força de knockback nos seus golpes.",
		Glyph = "✦",
		MaxStacks = 3,
	},
	{
		Id = "SoulMend",
		Title = "Cura do Slime",
		Description = "Recupere 4% da vida máxima ao derrotar um inimigo.",
		Glyph = "+",
		MaxStacks = 3,
	},
	{
		Id = "TreasurePulse",
		Title = "Pulso do Tesouro",
		Description = "+20% de moedas derrubadas por inimigos.",
		Glyph = "◆",
		MaxStacks = 3,
	},
})

local BY_ID = {}
for _, definition in ipairs(UPGRADES) do
	BY_ID[definition.Id] = definition
end

local started = false
local options = {}
local participantSet = {}
local recordsByUserId = {}
local remoteConnection
local playerAddedConnection
local characterConnections = setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % MAXIMUM_SEED
	return seed == 0 and 1 or seed
end

local function hashString(value)
	local hash = 2166136261
	value = tostring(value or "")
	for index = 1, #value do
		hash = (hash * 16777619 + string.byte(value, index) * 97) % MAXIMUM_SEED
	end
	return normalizedSeed(hash)
end

local function recordFor(userId)
	local record = recordsByUserId[userId]
	if not record then
		record = {
			Stacks = {},
			Rounds = {},
			TotalChosen = 0,
		}
		recordsByUserId[userId] = record
	end
	return record
end

local function stackCount(record, upgradeId)
	return math.max(0, math.floor(tonumber(record.Stacks[upgradeId]) or 0))
end

local function totalStacks(record)
	local total = 0
	for _, amount in pairs(record.Stacks) do
		total += math.max(0, math.floor(tonumber(amount) or 0))
	end
	return total
end

local function copyStacks(record)
	local result = {}
	for upgradeId, amount in pairs(record.Stacks) do
		result[upgradeId] = math.max(0, math.floor(tonumber(amount) or 0))
	end
	return result
end

local function applyHealthUpgrade(player, multiplier)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local baseMaxHealth = tonumber(humanoid:GetAttribute("RunUpgradeBaseMaxHealth"))
	if not baseMaxHealth or baseMaxHealth <= 0 then
		baseMaxHealth = math.max(1, humanoid.MaxHealth)
		humanoid:SetAttribute("RunUpgradeBaseMaxHealth", baseMaxHealth)
	end
	local desiredMaxHealth = math.max(1, math.floor(baseMaxHealth * multiplier + 0.5))
	if desiredMaxHealth == humanoid.MaxHealth then
		return
	end
	local oldMaxHealth = math.max(1, humanoid.MaxHealth)
	local oldHealth = humanoid.Health
	humanoid.MaxHealth = desiredMaxHealth
	if oldHealth > 0 then
		local gainedMaximum = math.max(0, desiredMaxHealth - oldMaxHealth)
		humanoid.Health = math.min(desiredMaxHealth, oldHealth + gainedMaximum)
	end
end

local function applyRecordToPlayer(player)
	if not player or player.Parent ~= Players then
		return false
	end
	local record = recordFor(player.UserId)
	local damageStacks = stackCount(record, "SharpenedEdge")
	local vitalityStacks = stackCount(record, "VitalCore")
	local impactStacks = stackCount(record, "SkyImpact")
	local mendStacks = stackCount(record, "SoulMend")
	local treasureStacks = stackCount(record, "TreasurePulse")

	local damageMultiplier = 1 + damageStacks * 0.20
	local maxHealthMultiplier = 1 + vitalityStacks * 0.20
	local knockbackMultiplier = 1 + impactStacks * 0.30
	local healOnKillPercent = mendStacks * 0.04
	local coinMultiplier = 1 + treasureStacks * 0.20

	player:SetAttribute("RunDamageDealtMultiplier", damageMultiplier)
	player:SetAttribute("RunMaxHealthMultiplier", maxHealthMultiplier)
	player:SetAttribute("RunKnockbackMultiplier", knockbackMultiplier)
	player:SetAttribute("RunHealOnKillPercent", healOnKillPercent)
	player:SetAttribute("RunCoinRewardMultiplier", coinMultiplier)
	player:SetAttribute("DungeonRunUpgradeCount", totalStacks(record))
	player:SetAttribute("DungeonRunUpgradePolicy", "RewardChoiceOneOfThreeV1")

	applyHealthUpgrade(player, maxHealthMultiplier)
	return true
end

local function publicDefinition(definition, record)
	local current = stackCount(record, definition.Id)
	return {
		Id = definition.Id,
		Title = definition.Title,
		Description = definition.Description,
		Glyph = definition.Glyph,
		CurrentStack = current,
		NextStack = current + 1,
		MaxStacks = definition.MaxStacks,
	}
end

local function choicesFor(userId, roundIndex)
	local record = recordFor(userId)
	local candidates = {}
	for _, definition in ipairs(UPGRADES) do
		if stackCount(record, definition.Id) < definition.MaxStacks then
			table.insert(candidates, definition)
		end
	end
	local random = Random.new(hashString(string.format(
		"%s:%d:R%d:RunUpgrade",
		tostring(options.SessionId or "unknown"),
		userId,
		roundIndex
	)))
	for index = #candidates, 2, -1 do
		local swapIndex = random:NextInteger(1, index)
		candidates[index], candidates[swapIndex] = candidates[swapIndex], candidates[index]
	end
	local result = {}
	for index = 1, math.min(3, #candidates) do
		result[index] = publicDefinition(candidates[index], record)
	end
	return result
end

local function fireClient(player, payload)
	local remote = options.RemoteEvent
	if remote and player and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function roundPayload(player, roundIndex, action)
	local record = recordFor(player.UserId)
	local round = record.Rounds[roundIndex]
	return {
		Action = action or "RunUpgradeSnapshot",
		RoundIndex = roundIndex,
		Resolved = round and round.Resolved == true or false,
		SelectedUpgradeId = round and round.SelectedUpgradeId or nil,
		Automatic = round and round.Automatic == true or false,
		AutoPickAt = round and round.AutoPickAt or nil,
		Choices = round and round.Choices or {},
		Stacks = copyStacks(record),
		TotalChosen = record.TotalChosen,
	}
end

local function choiceContains(round, upgradeId)
	for _, choice in ipairs(round.Choices or {}) do
		if choice.Id == upgradeId then
			return true
		end
	end
	return false
end

local resolveChoice

local function scheduleAutoPick(userId, roundIndex, round)
	local delaySeconds = math.max(0, (tonumber(round.AutoPickAt) or now()) - now())
	task.delay(delaySeconds, function()
		if not started then
			return
		end
		local currentRecord = recordsByUserId[userId]
		local currentRound = currentRecord and currentRecord.Rounds[roundIndex]
		if not currentRound or currentRound ~= round or currentRound.Resolved then
			return
		end
		local currentPlayer = Players:GetPlayerByUserId(userId)
		if not currentPlayer then
			return
		end
		local defaultChoice = currentRound.Choices[1]
		if defaultChoice then
			resolveChoice(currentPlayer, roundIndex, defaultChoice.Id, true)
		else
			currentRound.Resolved = true
			currentRound.Automatic = true
			currentRound.ResolvedAt = now()
		end
	end)
end

resolveChoice = function(player, roundIndex, upgradeId, automatic)
	if not started
		or not player
		or player.Parent ~= Players
		or not participantSet[player.UserId]
	then
		return false, "PlayerNotEligible"
	end
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 0), 1, 3)
	local record = recordFor(player.UserId)
	local round = record.Rounds[roundIndex]
	if not round then
		return false, "ChoiceNotOffered"
	end
	if round.Resolved then
		fireClient(player, roundPayload(player, roundIndex, "RunUpgradeChoiceResolved"))
		return true, "AlreadyResolved"
	end
	if type(upgradeId) ~= "string" or not choiceContains(round, upgradeId) then
		return false, "UpgradeNotOffered"
	end
	local definition = BY_ID[upgradeId]
	if not definition then
		return false, "UpgradeMissing"
	end
	local currentStack = stackCount(record, upgradeId)
	if currentStack >= definition.MaxStacks then
		return false, "UpgradeMaxStack"
	end

	record.Stacks[upgradeId] = currentStack + 1
	record.TotalChosen += 1
	round.Resolved = true
	round.SelectedUpgradeId = upgradeId
	round.Automatic = automatic == true
	round.ResolvedAt = now()
	applyRecordToPlayer(player)

	player:SetAttribute("DungeonRunLastUpgradeId", upgradeId)
	player:SetAttribute("DungeonRunLastUpgradeRound", roundIndex)
	player:SetAttribute("DungeonRunLastUpgradeAt", round.ResolvedAt)
	player:SetAttribute("DungeonRunUpgradeChoicePending", false)
	workspace:SetAttribute("DungeonRunLastUpgradeUserId", player.UserId)
	workspace:SetAttribute("DungeonRunLastUpgradeId", upgradeId)
	workspace:SetAttribute("DungeonRunLastUpgradeAt", round.ResolvedAt)

	fireClient(player, roundPayload(player, roundIndex, "RunUpgradeChoiceResolved"))
	if type(options.OnChoiceResolved) == "function" then
		local ok, errorMessage = pcall(
			options.OnChoiceResolved,
			player,
			roundIndex,
			upgradeId,
			automatic == true
		)
		if not ok then
			warn("[RunUpgradeService] OnChoiceResolved falhou: " .. tostring(errorMessage))
		end
	end
	return true, upgradeId
end

local function bindPlayer(player)
	if not participantSet[player.UserId] then
		return
	end
	local old = characterConnections[player]
	if old then
		old:Disconnect()
	end
	characterConnections[player] = player.CharacterAdded:Connect(function()
		task.defer(applyRecordToPlayer, player)
	end)
	task.defer(applyRecordToPlayer, player)
end

function RunUpgradeService.Start(startOptions)
	if started then
		return true
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	participantSet = {}
	recordsByUserId = {}
	for _, rawUserId in ipairs(options.ParticipantUserIds or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId > 0 then
			participantSet[userId] = true
			recordFor(userId)
		end
	end
	local remote = options.RemoteEvent
	if remote then
		remoteConnection = remote.OnServerEvent:Connect(function(player, payload)
			if type(payload) ~= "table" or payload.Action ~= "ChooseRunUpgrade" then
				return
			end
			resolveChoice(player, payload.RoundIndex, payload.UpgradeId, false)
		end)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	workspace:SetAttribute("DungeonRunUpgradeServiceReady", true)
	workspace:SetAttribute("DungeonRunUpgradePolicy", "RewardChoiceOneOfThreeV1")
	workspace:SetAttribute("DungeonRunUpgradeAutoPickSeconds", AUTO_PICK_SECONDS)
	return true
end

function RunUpgradeService.Stop()
	started = false
	if remoteConnection then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	for player, connection in pairs(characterConnections) do
		connection:Disconnect()
		if player.Parent == Players then
			player:SetAttribute("RunDamageDealtMultiplier", nil)
			player:SetAttribute("RunMaxHealthMultiplier", nil)
			player:SetAttribute("RunKnockbackMultiplier", nil)
			player:SetAttribute("RunHealOnKillPercent", nil)
			player:SetAttribute("RunCoinRewardMultiplier", nil)
			player:SetAttribute("DungeonRunUpgradeChoicePending", false)
		end
	end
	characterConnections = setmetatable({}, { __mode = "k" })
	options = {}
	participantSet = {}
	recordsByUserId = {}
	workspace:SetAttribute("DungeonRunUpgradeServiceReady", false)
end

function RunUpgradeService.BeginChoice(player, roundIndex)
	if not started or not player or player.Parent ~= Players or not participantSet[player.UserId] then
		return false, "PlayerNotEligible"
	end
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 0), 1, 3)
	local record = recordFor(player.UserId)
	local existing = record.Rounds[roundIndex]
	if existing then
		fireClient(
			player,
			roundPayload(
				player,
				roundIndex,
				existing.Resolved and "RunUpgradeChoiceResolved" or "RunUpgradeChoiceOffered"
			)
		)
		return true, existing.Resolved and "AlreadyResolved" or "AlreadyOffered"
	end

	local choices = choicesFor(player.UserId, roundIndex)
	if #choices == 0 then
		record.Rounds[roundIndex] = {
			Choices = {},
			Resolved = true,
			Automatic = true,
			ResolvedAt = now(),
		}
		return true, "NoAvailableUpgrades"
	end

	local round = {
		Choices = choices,
		OfferedAt = now(),
		AutoPickAt = now() + AUTO_PICK_SECONDS,
		Resolved = false,
	}
	record.Rounds[roundIndex] = round
	player:SetAttribute("DungeonRunUpgradeChoicePending", true)
	player:SetAttribute("DungeonRunUpgradeChoiceRound", roundIndex)
	player:SetAttribute("DungeonRunUpgradeChoiceAutoPickAt", round.AutoPickAt)
	fireClient(player, roundPayload(player, roundIndex, "RunUpgradeChoiceOffered"))

	scheduleAutoPick(player.UserId, roundIndex, round)
	return true, roundPayload(player, roundIndex, "RunUpgradeChoiceOffered")
end

function RunUpgradeService.IsResolved(playerOrUserId, roundIndex)
	local userId = typeof(playerOrUserId) == "Instance"
		and playerOrUserId.UserId
		or math.floor(tonumber(playerOrUserId) or 0)
	if userId <= 0 then
		return false
	end
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 0), 1, 3)
	local record = recordsByUserId[userId]
	local round = record and record.Rounds[roundIndex]
	return round ~= nil and round.Resolved == true
end

function RunUpgradeService.SyncPlayer(player)
	if not started or not player or player.Parent ~= Players or not participantSet[player.UserId] then
		return false
	end
	bindPlayer(player)
	local record = recordFor(player.UserId)
	for roundIndex = 1, 3 do
		local round = record.Rounds[roundIndex]
		if round and not round.Resolved then
			fireClient(player, roundPayload(player, roundIndex, "RunUpgradeChoiceOffered"))
			scheduleAutoPick(player.UserId, roundIndex, round)
			break
		end
	end
	return true
end

function RunUpgradeService.GetSnapshot(playerOrUserId)
	local userId = typeof(playerOrUserId) == "Instance"
		and playerOrUserId.UserId
		or math.floor(tonumber(playerOrUserId) or 0)
	local record = userId > 0 and recordsByUserId[userId] or nil
	return {
		Ready = started,
		UserId = userId,
		Stacks = record and copyStacks(record) or {},
		TotalChosen = record and record.TotalChosen or 0,
	}
end

return RunUpgradeService
