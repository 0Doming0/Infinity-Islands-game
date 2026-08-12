local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local choiceEvent = orbFolder:WaitForChild("OrbChoiceEvent")
local choiceRequest = orbFolder:WaitForChild("OrbChoiceRequest")

local queues = setmetatable({}, { __mode = "k" })
local queuedMilestones = setmetatable({}, { __mode = "k" })
local selecting = setmetatable({}, { __mode = "k" })

local function claimedAttribute(level)
	return string.format("OrbChoiceLevel%dClaimed", level)
end

local function getOrbLevel(player, orbName)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	return attribute and OrbConfig.CleanLevel(player:GetAttribute(attribute)) or 0
end

local function setOrbLevel(player, orbName, level)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	if attribute then
		player:SetAttribute(attribute, OrbConfig.CleanLevel(level))
	end
end

local function clearEquippedOrb(player)
	player:SetAttribute("EquippedOrb", nil)
	local character = player.Character
	if character then
		character:SetAttribute("EquippedOrb", nil)
	end
end

local function initializePlayer(player)
	-- Orb progression is scoped to the current dungeon run. Every player must
	-- enter a new server without an Orb, even when stale attributes from an
	-- earlier version or Studio test are still present on the Player.
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		setOrbLevel(player, orbName, 0)
	end
	for _, level in ipairs(OrbConfig.ChoiceLevels) do
		player:SetAttribute(claimedAttribute(level), false)
	end
	player:SetAttribute("OrbChoicesCompleted", 0)
	player:SetAttribute("OrbChoiceSerial", 0)
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceState", "None")
	clearEquippedOrb(player)

	player:SetAttribute("OrbProgressionVersion", OrbConfig.Version)
	player:SetAttribute("OrbProgressionPolicy", "RunScoped")
end

local function buildOptions(player)
	local result = {}
	for _, orbName in ipairs(OrbConfig.OrbOrder) do
		local definition = OrbConfig.GetOrb(orbName)
		local currentLevel = getOrbLevel(player, orbName)
		table.insert(result, {
			Orb = orbName,
			AssetName = definition.AssetName,
			DisplayName = definition.DisplayName,
			Description = definition.Description,
			CurrentLevel = currentLevel,
			NextLevel = math.min(currentLevel + 1, OrbConfig.MaxOrbLevel),
			Kind = currentLevel == 0 and "NEW" or "UPGRADE",
			UpgradeInfo = OrbConfig.GetUpgradeSummary(orbName, currentLevel),
			Available = currentLevel < OrbConfig.MaxOrbLevel,
		})
	end
	return result
end

local function presentNext(player)
	if player.Parent ~= Players then
		return
	end
	if (tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0) > 0 then
		return
	end

	local queue = queues[player]
	local milestone = queue and table.remove(queue, 1)
	if not milestone then
		return
	end

	local serial = (tonumber(player:GetAttribute("OrbChoiceSerial")) or 0) + 1
	player:SetAttribute("PendingOrbChoiceLevel", milestone)
	player:SetAttribute("OrbChoiceSerial", serial)
	player:SetAttribute("OrbChoiceState", "WaitingForSelection")
	choiceEvent:FireClient(player, {
		Action = "Offer",
		MilestoneLevel = milestone,
		Serial = serial,
		Options = buildOptions(player),
	})
end

local function enqueueMilestone(player, milestone)
	if player:GetAttribute(claimedAttribute(milestone)) == true then
		return
	end
	local set = queuedMilestones[player]
	if not set then
		set = {}
		queuedMilestones[player] = set
	end
	if set[milestone] then
		return
	end
	set[milestone] = true

	local queue = queues[player]
	if not queue then
		queue = {}
		queues[player] = queue
	end
	table.insert(queue, milestone)
	table.sort(queue)
	presentNext(player)
end

local function synchronizeMilestones(player)
	local currentLevel = math.max(1, math.floor(tonumber(player:GetAttribute("PlayerLevel")) or 1))
	for _, milestone in ipairs(OrbConfig.ChoiceLevels) do
		if currentLevel >= milestone then
			enqueueMilestone(player, milestone)
		end
	end
end

local function bindPlayer(player)
	initializePlayer(player)
	queues[player] = {}
	queuedMilestones[player] = {}
	local pending = math.floor(tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0)
	if pending > 0 and OrbConfig.IsChoiceLevel(pending) and player:GetAttribute(claimedAttribute(pending)) ~= true then
		queuedMilestones[player][pending] = true
	elseif pending > 0 then
		player:SetAttribute("PendingOrbChoiceLevel", 0)
	end

	player:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
		synchronizeMilestones(player)
	end)
	player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(function()
		synchronizeMilestones(player)
	end)

	task.defer(synchronizeMilestones, player)
end

choiceRequest.OnServerEvent:Connect(function(player, request)
	if selecting[player] or type(request) ~= "table" then
		return
	end
	selecting[player] = true

	local pendingLevel = math.floor(tonumber(player:GetAttribute("PendingOrbChoiceLevel")) or 0)
	local serial = math.floor(tonumber(player:GetAttribute("OrbChoiceSerial")) or 0)
	local requestedLevel = math.floor(tonumber(request.MilestoneLevel) or 0)
	local requestedSerial = math.floor(tonumber(request.Serial) or 0)
	local orbName = OrbConfig.NormalizeOrb(request.Orb)

	if pendingLevel <= 0 or requestedLevel ~= pendingLevel or requestedSerial ~= serial or not orbName then
		choiceEvent:FireClient(player, { Action = "Rejected", Reason = "InvalidOrExpiredChoice" })
		selecting[player] = nil
		return
	end

	local currentLevel = getOrbLevel(player, orbName)
	if currentLevel >= OrbConfig.MaxOrbLevel then
		choiceEvent:FireClient(player, { Action = "Rejected", Reason = "OrbAlreadyMaxLevel" })
		selecting[player] = nil
		return
	end

	local nextLevel = currentLevel + 1
	setOrbLevel(player, orbName, nextLevel)
	player:SetAttribute("EquippedOrb", orbName)
	player:SetAttribute(claimedAttribute(pendingLevel), true)
	player:SetAttribute("OrbChoicesCompleted", (tonumber(player:GetAttribute("OrbChoicesCompleted")) or 0) + 1)
	player:SetAttribute("LastOrbChoice", orbName)
	player:SetAttribute("LastOrbChoiceKind", currentLevel == 0 and "NEW" or "UPGRADE")
	player:SetAttribute("LastOrbChoiceLevel", nextLevel)
	player:SetAttribute("LastOrbChoiceAt", workspace:GetServerTimeNow())
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceState", "Selected")

	local set = queuedMilestones[player]
	if set then
		set[pendingLevel] = nil
	end

	choiceEvent:FireClient(player, {
		Action = "Selected",
		Orb = orbName,
		OrbLevel = nextLevel,
		MilestoneLevel = pendingLevel,
	})

	selecting[player] = nil
	task.defer(presentNext, player)
end)

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	queues[player] = nil
	queuedMilestones[player] = nil
	selecting[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

workspace:SetAttribute("DungeonOrbProgressionReady", true)
workspace:SetAttribute("DungeonOrbProgressionVersion", OrbConfig.Version)
workspace:SetAttribute("DungeonOrbChoiceLevels", table.concat(OrbConfig.ChoiceLevels, ","))

print("[OrbProgression] Choices ready at levels 3, 6, 9 and 12")
