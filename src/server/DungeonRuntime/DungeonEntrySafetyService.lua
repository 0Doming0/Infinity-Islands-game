local Players = game:GetService("Players")

local DungeonEntrySafetyService = {}

local FORCE_FIELD_NAME = "DungeonEntryProtection"
local DEFAULT_PROTECTION_SECONDS = 3

local started = false
local options = {}
local participantSet = {}
local protectionTokens = setmetatable({}, { __mode = "k" })
local protectionSerial = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function updateActiveCount()
	local count = 0
	for player, token in pairs(protectionTokens) do
		if token
			and player.Parent == Players
			and player:GetAttribute("DungeonEntryProtectionActive") == true
			and (tonumber(player:GetAttribute("DungeonEntryProtectionUntil")) or 0) > now()
		then
			count += 1
		end
	end
	workspace:SetAttribute("DungeonEntryProtectionActiveCount", count)
	return count
end

local function normalizeUserIds(raw)
	local result = {}
	for _, value in ipairs(type(raw) == "table" and raw or {}) do
		local userId = math.floor(tonumber(value) or 0)
		if userId > 0 then
			result[userId] = true
		end
	end
	return result
end

local function eligible(player)
	if not player or player.Parent ~= Players or not participantSet[player.UserId] then
		return false
	end
	if player:GetAttribute("DungeonEliminated") == true
		or player:GetAttribute("DungeonSpectating") == true
		or player:GetAttribute("IsDowned") == true
	then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function removeOwnedForceField(character)
	local forceField = character and character:FindFirstChild(FORCE_FIELD_NAME)
	if forceField and forceField:IsA("ForceField") then
		forceField:Destroy()
	end
end

local function clearPlayer(player, token, reason)
	if not player or protectionTokens[player] ~= token then
		return false
	end
	protectionTokens[player] = nil
	removeOwnedForceField(player.Character)
	if player.Character then
		player.Character:SetAttribute("DungeonEntryProtected", nil)
	end
	player:SetAttribute("DungeonEntryProtectionActive", false)
	player:SetAttribute("DungeonEntryProtectionUntil", nil)
	player:SetAttribute("DungeonEntryProtectionEndedAt", now())
	player:SetAttribute("DungeonEntryProtectionEndReason", tostring(reason or "Expired"))
	updateActiveCount()
	return true
end

local function protectPlayer(player, context, reason, durationSeconds)
	if not eligible(player) then
		return false, "PlayerNotEligible"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, "CharacterUnavailable"
	end

	protectionSerial += 1
	local token = protectionSerial
	protectionTokens[player] = token
	local duration = math.max(0.5, tonumber(durationSeconds) or DEFAULT_PROTECTION_SECONDS)
	local expiresAt = now() + duration

	removeOwnedForceField(character)
	local forceField = Instance.new("ForceField")
	forceField.Name = FORCE_FIELD_NAME
	forceField.Visible = false
	forceField.Parent = character

	character:SetAttribute("DungeonEntryProtected", true)
	player:SetAttribute("DungeonEntryProtectionActive", true)
	player:SetAttribute("DungeonEntryProtectionUntil", expiresAt)
	player:SetAttribute("DungeonEntryProtectionReason", tostring(reason or "IslandEntered"))
	player:SetAttribute("DungeonEntryProtectionIslandIndex", context and context.GlobalIslandIndex or nil)
	player:SetAttribute("DungeonEntryProtectionRoundIndex", context and context.RoundIndex or nil)
	player:SetAttribute("DungeonEntryProtectionNodeKey", context and context.Key or nil)
	player:SetAttribute("DungeonEntryProtectionStartedAt", now())
	updateActiveCount()

	task.delay(duration, function()
		clearPlayer(player, token, "Expired")
	end)
	return true, expiresAt
end

function DungeonEntrySafetyService.Start(startOptions)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	participantSet = normalizeUserIds(options.ParticipantUserIds)
	workspace:SetAttribute("DungeonEntrySafetyReady", true)
	workspace:SetAttribute("DungeonEntrySafetyVersion", 1)
	workspace:SetAttribute(
		"DungeonEntryProtectionSeconds",
		math.max(0.5, tonumber(options.ProtectionSeconds) or DEFAULT_PROTECTION_SECONDS)
	)
	workspace:SetAttribute("DungeonEntrySafetyPolicy", "IgnoreAndBlockDamage")
end

function DungeonEntrySafetyService.Stop()
	if not started then
		return
	end
	started = false
	for _, player in ipairs(Players:GetPlayers()) do
		local token = protectionTokens[player]
		if token then
			clearPlayer(player, token, "ServiceStopped")
		else
			removeOwnedForceField(player.Character)
		end
	end
	participantSet = {}
	options = {}
	workspace:SetAttribute("DungeonEntrySafetyReady", false)
	workspace:SetAttribute("DungeonEntryProtectionActiveCount", 0)
end

function DungeonEntrySafetyService.ProtectParticipants(context, reason, durationSeconds)
	if not started then
		return false, "EntrySafetyNotStarted"
	end
	local duration = math.max(
		0.5,
		tonumber(durationSeconds)
			or tonumber(options.ProtectionSeconds)
			or DEFAULT_PROTECTION_SECONDS
	)
	local protectedCount = 0
	for userId in pairs(participantSet) do
		local player = Players:GetPlayerByUserId(userId)
		local protected = protectPlayer(player, context, reason, duration)
		if protected then
			protectedCount += 1
		end
	end
	updateActiveCount()
	workspace:SetAttribute("DungeonEntryProtectionLastIsland", context and context.GlobalIslandIndex or nil)
	workspace:SetAttribute("DungeonEntryProtectionLastRound", context and context.RoundIndex or nil)
	workspace:SetAttribute("DungeonEntryProtectionLastStartedAt", now())
	workspace:SetAttribute("DungeonEntryProtectionLastReason", tostring(reason or "IslandEntered"))
	return true, protectedCount
end

function DungeonEntrySafetyService.IsPlayerProtected(player)
	return player ~= nil
		and player.Parent == Players
		and player:GetAttribute("DungeonEntryProtectionActive") == true
		and (tonumber(player:GetAttribute("DungeonEntryProtectionUntil")) or 0) > now()
end

function DungeonEntrySafetyService.GetSnapshot()
	local protectedCount = 0
	for player, token in pairs(protectionTokens) do
		if token and DungeonEntrySafetyService.IsPlayerProtected(player) then
			protectedCount += 1
		end
	end
	return {
		Ready = started,
		ProtectionSeconds = math.max(
			0.5,
			tonumber(options.ProtectionSeconds) or DEFAULT_PROTECTION_SECONDS
		),
		ProtectedPlayerCount = protectedCount,
		Policy = "IgnoreAndBlockDamage",
	}
end

return DungeonEntrySafetyService
