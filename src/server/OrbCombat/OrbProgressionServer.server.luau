-- OrbProgressionServer - progressao linear automatica do MVP.
--
-- O Orb nao interrompe mais o combate e nao pede escolha.
-- Jogador novo recebe Fire Orb automaticamente no nivel 3.
-- O Orb principal evolui automaticamente nos niveis 6, 9 e 12 ate Lv.4.
-- Jogadores antigos preservam seus Orbs salvos; o Orb equipado/primeiro possuido
-- vira o Orb principal e continua evoluindo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local PlayerDataService = require(
	ServerScriptService:WaitForChild("BlockParkour"):WaitForChild("PlayerDataService_SkyDungeon_V10")
)

local VERSION = "LinearAutomaticOrbProgressionV1"
local MILESTONES = { 3, 6, 9, 12 }
local DEFAULT_ORB = "Fire"
local saveScheduled = setmetatable({}, { __mode = "k" })

local function claimedAttribute(level)
	return string.format("OrbChoiceLevel%dClaimed", level)
end

local function cleanLevel(value)
	return OrbConfig.CleanLevel(value)
end

local function getOrbLevel(player, orbName)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	return attribute and cleanLevel(player:GetAttribute(attribute)) or 0
end

local function setOrbLevel(player, orbName, level)
	local attribute = OrbConfig.GetLevelAttribute(orbName)
	if attribute then
		player:SetAttribute(attribute, cleanLevel(level))
	end
end

local function getOrbXP(player, orbName)
	local attribute = OrbConfig.GetOrbLevelXPAttribute(orbName)
	return attribute and math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0)) or 0
end

local function setOrbXP(player, orbName, value)
	local attribute = OrbConfig.GetOrbLevelXPAttribute(orbName)
	if attribute then
		player:SetAttribute(attribute, math.max(0, math.floor(tonumber(value) or 0)))
	end
end

local function ensureMilestoneAbilities(player, orbName, level)
	for orbLevel = 2, cleanLevel(level) do
		local ability, rank = OrbConfig.GetMilestoneAbility(orbName, orbLevel)
		if ability then
			local attribute = "OrbUpgrade_" .. ability.Id
			local current = math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
			player:SetAttribute(attribute, math.max(current, rank or 1))
		end
	end
end

local function ownedOrb(player, orbName)
	return OrbConfig.GetOrb(orbName) ~= nil and getOrbLevel(player, orbName) > 0
end

local function primaryOrb(player)
	local equipped = OrbConfig.NormalizeOrb(player:GetAttribute("EquippedOrb"))
	if equipped and ownedOrb(player, equipped) then
		return equipped
	end

	for orbName in string.gmatch(tostring(player:GetAttribute("EquippedOrbs") or ""), "[^,]+") do
		orbName = OrbConfig.NormalizeOrb(orbName)
		if orbName and ownedOrb(player, orbName) then
			return orbName
		end
	end

	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		if ownedOrb(player, orbName) then
			return orbName
		end
	end

	return OrbConfig.GetOrb(DEFAULT_ORB) and DEFAULT_ORB or (OrbConfig.OrbOrder and OrbConfig.OrbOrder[1])
end

local function equipOnlyPrimary(player, orbName)
	if not orbName or not ownedOrb(player, orbName) then
		player:SetAttribute("EquippedOrbs", "")
		player:SetAttribute("EquippedOrb", nil)
		player:SetAttribute("EquippedOrb2", nil)
		return
	end
	player:SetAttribute("EquippedOrbs", orbName)
	player:SetAttribute("EquippedOrb", orbName)
	player:SetAttribute("EquippedOrb2", nil)
end

local function progressionSnapshot(player)
	local orbs = {}
	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		local definition = OrbConfig.GetOrb(orbName)
		local abilities = {}
		for _, upgrade in ipairs((definition and definition.SpecializedUpgrades) or {}) do
			abilities[upgrade.Id] = math.max(
				0,
				math.floor(tonumber(player:GetAttribute("OrbUpgrade_" .. upgrade.Id)) or 0)
			)
		end
		orbs[orbName] = {
			Level = getOrbLevel(player, orbName),
			XP = getOrbXP(player, orbName),
			Abilities = abilities,
		}
	end

	local claimed = {}
	for _, level in ipairs(MILESTONES) do
		claimed[level] = player:GetAttribute(claimedAttribute(level)) == true
	end

	local primary = primaryOrb(player)
	return {
		Version = VERSION,
		Orbs = orbs,
		EquippedOrbs = primary and ownedOrb(player, primary) and { primary } or {},
		ClaimedMilestones = claimed,
		ChoicesCompleted = math.max(0, math.floor(tonumber(player:GetAttribute("OrbChoicesCompleted")) or 0)),
	}
end

local function persist(player)
	if player.Parent ~= Players and not player.UserId then
		return false
	end
	local ok = PlayerDataService.SetOrbProgression(player, progressionSnapshot(player))
	return ok == true
end

local function scheduleSave(player)
	if saveScheduled[player] then
		return
	end
	saveScheduled[player] = true
	task.delay(3, function()
		saveScheduled[player] = nil
		if player.Parent == Players and persist(player) then
			PlayerDataService.Save(player, false)
		end
	end)
end

local function restore(player)
	PlayerDataService.Load(player)
	local saved = PlayerDataService.GetOrbProgression(player)
	if type(saved) ~= "table" then
		return
	end

	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		local record = type(saved.Orbs) == "table" and saved.Orbs[orbName] or nil
		record = type(record) == "table" and record or {}
		setOrbLevel(player, orbName, record.Level)
		setOrbXP(player, orbName, record.XP)

		local definition = OrbConfig.GetOrb(orbName)
		for _, upgrade in ipairs((definition and definition.SpecializedUpgrades) or {}) do
			local count = math.max(
				0,
				math.floor(tonumber(record.Abilities and record.Abilities[upgrade.Id]) or 0)
			)
			player:SetAttribute("OrbUpgrade_" .. upgrade.Id, count)
		end
		ensureMilestoneAbilities(player, orbName, getOrbLevel(player, orbName))
	end

	local claimed = type(saved.ClaimedMilestones) == "table" and saved.ClaimedMilestones or {}
	for _, level in ipairs(MILESTONES) do
		player:SetAttribute(claimedAttribute(level), claimed[level] == true)
	end
	player:SetAttribute("OrbChoicesCompleted", math.max(0, math.floor(tonumber(saved.ChoicesCompleted) or 0)))

	local savedPrimary = type(saved.EquippedOrbs) == "table" and saved.EquippedOrbs[1] or nil
	savedPrimary = OrbConfig.NormalizeOrb(savedPrimary)
	if savedPrimary and ownedOrb(player, savedPrimary) then
		player:SetAttribute("EquippedOrb", savedPrimary)
	end
end

local function initialize(player)
	restore(player)

	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		local levelAttribute = OrbConfig.GetLevelAttribute(orbName)
		local xpAttribute = OrbConfig.GetOrbLevelXPAttribute(orbName)
		if levelAttribute and player:GetAttribute(levelAttribute) == nil then
			setOrbLevel(player, orbName, 0)
		end
		if xpAttribute and player:GetAttribute(xpAttribute) == nil then
			setOrbXP(player, orbName, 0)
		end
		local definition = OrbConfig.GetOrb(orbName)
		for _, upgrade in ipairs((definition and definition.SpecializedUpgrades) or {}) do
			local attribute = "OrbUpgrade_" .. upgrade.Id
			if player:GetAttribute(attribute) == nil then
				player:SetAttribute(attribute, 0)
			end
		end
	end

	for _, level in ipairs(MILESTONES) do
		local attribute = claimedAttribute(level)
		if player:GetAttribute(attribute) == nil then
			player:SetAttribute(attribute, false)
		end
	end

	if player:GetAttribute("OrbChoicesCompleted") == nil then
		player:SetAttribute("OrbChoicesCompleted", 0)
	end

	-- Remove qualquer escolha/modal pendente de versoes anteriores.
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceProtected", false)
	player:SetAttribute("OrbChoiceState", "Automatic")
	player:SetAttribute("OrbChoiceSerial", 0)
	player:SetAttribute("OrbChoiceSafeMomentSerial", 0)
	player:SetAttribute("OrbChoiceLastPresentedSafeMomentSerial", 0)
	player:SetAttribute("OrbChoiceSafeIslandIndex", 0)
	player:SetAttribute("OrbProgressionVersion", VERSION)
	player:SetAttribute("OrbProgressionPolicy", "AutomaticPrimaryOrb")
	player:SetAttribute("OrbAutomaticMilestones", "3,6,9,12")
	player:SetAttribute("OrbFirstChoiceGuaranteed", false)
end

local function grantOrUpgrade(player, milestone)
	if player:GetAttribute(claimedAttribute(milestone)) == true then
		return false
	end

	local orbName = primaryOrb(player)
	if not orbName then
		player:SetAttribute(claimedAttribute(milestone), true)
		return false
	end

	local previous = getOrbLevel(player, orbName)
	local nextLevel = previous
	local kind = "MilestoneConsumed"

	if previous <= 0 then
		nextLevel = 1
		kind = "NewOrb"
	elseif previous < OrbConfig.MaxOrbLevel then
		nextLevel = previous + 1
		kind = "AutomaticUpgrade"
	end

	if nextLevel ~= previous then
		setOrbLevel(player, orbName, nextLevel)
		ensureMilestoneAbilities(player, orbName, nextLevel)
		equipOnlyPrimary(player, orbName)
		player:SetAttribute("LastOrbChoice", orbName)
		player:SetAttribute("LastOrbChoiceKind", kind)
		player:SetAttribute("LastOrbChoiceLevel", nextLevel)
		player:SetAttribute("LastOrbChoiceAt", workspace:GetServerTimeNow())
		player:SetAttribute("LastOrbAutomaticMilestone", milestone)
	end

	player:SetAttribute(claimedAttribute(milestone), true)
	player:SetAttribute(
		"OrbChoicesCompleted",
		math.max(0, math.floor(tonumber(player:GetAttribute("OrbChoicesCompleted")) or 0)) + 1
	)
	player:SetAttribute("PendingOrbChoiceLevel", 0)
	player:SetAttribute("OrbChoiceState", "Automatic")
	scheduleSave(player)
	return nextLevel ~= previous
end

local function synchronize(player)
	if player.Parent ~= Players then
		return
	end
	local playerLevel = math.max(1, math.floor(tonumber(player:GetAttribute("PlayerLevel")) or 1))

	-- Recupera jogadores que ficaram presos em uma escolha antiga antes desta migracao.
	if playerLevel >= MILESTONES[1] then
		local primary = primaryOrb(player)
		if primary and getOrbLevel(player, primary) <= 0 then
			player:SetAttribute(claimedAttribute(MILESTONES[1]), false)
		end
	end

	for _, milestone in ipairs(MILESTONES) do
		if playerLevel >= milestone then
			grantOrUpgrade(player, milestone)
		end
	end

	local primary = primaryOrb(player)
	if primary and ownedOrb(player, primary) then
		equipOnlyPrimary(player, primary)
	end
end

local function bindSaveSignals(player)
	for _, orbName in ipairs(OrbConfig.OrbOrder or {}) do
		local levelAttribute = OrbConfig.GetLevelAttribute(orbName)
		local xpAttribute = OrbConfig.GetOrbLevelXPAttribute(orbName)
		if levelAttribute then
			player:GetAttributeChangedSignal(levelAttribute):Connect(function()
				scheduleSave(player)
			end)
		end
		if xpAttribute then
			player:GetAttributeChangedSignal(xpAttribute):Connect(function()
				scheduleSave(player)
			end)
		end
		local definition = OrbConfig.GetOrb(orbName)
		for _, upgrade in ipairs((definition and definition.SpecializedUpgrades) or {}) do
			player:GetAttributeChangedSignal("OrbUpgrade_" .. upgrade.Id):Connect(function()
				scheduleSave(player)
			end)
		end
	end
end

local function bindPlayer(player)
	initialize(player)
	bindSaveSignals(player)
	player:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
		task.defer(synchronize, player)
	end)
	player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(function()
		task.defer(synchronize, player)
	end)
	task.defer(synchronize, player)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	persist(player)
	PlayerDataService.Save(player, true)
	saveScheduled[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

workspace:SetAttribute("DungeonOrbProgressionReady", true)
workspace:SetAttribute("DungeonOrbProgressionVersion", VERSION)
workspace:SetAttribute("DungeonOrbProgressionPolicy", "AutomaticPrimaryOrb")
workspace:SetAttribute("DungeonOrbAutomaticMilestones", "3,6,9,12")
workspace:SetAttribute("DungeonOrbChoiceUIRequired", false)
