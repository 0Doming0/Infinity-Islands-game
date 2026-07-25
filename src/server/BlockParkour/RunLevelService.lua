-- Progressão temporária da tentativa. O nível usa somente a maior altitude
-- lógica conquistada desde o spawn; voltar ou correr em círculos não gera nível.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CONFIG = MVPConfig.Progression.RunLevel

local RunLevelService = {}
local states = setmetatable({}, { __mode = "k" })

local function setMultipliers(player, level)
	local extraLevels = math.max(0, level - 1)
	player:SetAttribute("RunDamageTakenMultiplier", 1 + extraLevels * CONFIG.DamageTakenPerLevel)
	player:SetAttribute("RunDamageDealtMultiplier", CONFIG.DamageDealtRetentionPerLevel ^ extraLevels)
	player:SetAttribute("RunRewardMultiplier", 1 + extraLevels * CONFIG.RewardPerLevel)
end

local function getLivingHumanoid(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0 and humanoid or nil
end

local function applyUpgrade(player, state, level)
	local upgrades = CONFIG.TemporaryUpgrades
	if type(upgrades) ~= "table" or #upgrades == 0 then
		return
	end
	local seed = math.abs(player.UserId * 97 + level * CONFIG.UpgradeSeedSalt + state.RunSerial * 7919)
	local random = Random.new(seed % 2147483647)
	local index = random:NextInteger(1, #upgrades)
	if #upgrades > 1 and index == state.LastUpgradeIndex then
		index = index % #upgrades + 1
	end
	state.LastUpgradeIndex = index
	local upgrade = upgrades[index]
	table.insert(state.Upgrades, upgrade.DisplayName)

	if upgrade.AttackSpeedMultiplier then
		state.AttackSpeedMultiplier *= upgrade.AttackSpeedMultiplier
	elseif upgrade.KnockbackMultiplier then
		state.KnockbackMultiplier *= upgrade.KnockbackMultiplier
	elseif upgrade.CriticalChance then
		state.CriticalChance += upgrade.CriticalChance
	elseif upgrade.WalkSpeed then
		local humanoid = getLivingHumanoid(player)
		if humanoid then
			humanoid.WalkSpeed += upgrade.WalkSpeed
		end
	elseif upgrade.MaxHealth then
		local humanoid = getLivingHumanoid(player)
		if humanoid then
			humanoid.MaxHealth += upgrade.MaxHealth
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + upgrade.MaxHealth)
		end
	end

	player:SetAttribute("RunAttackSpeedMultiplier", state.AttackSpeedMultiplier)
	player:SetAttribute("RunKnockbackMultiplier", state.KnockbackMultiplier)
	player:SetAttribute("RunCriticalBonus", state.CriticalChance)
	player:SetAttribute("RunLastUpgrade", upgrade.DisplayName)
	player:SetAttribute("RunUpgradeSummary", table.concat(state.Upgrades, ", "))
	player:SetAttribute("RunUpgradeSerial", (player:GetAttribute("RunUpgradeSerial") or 0) + 1)
end

function RunLevelService.Reset(player, character)
	local previous = states[player]
	local runSerial = previous and previous.RunSerial + 1 or 1
	states[player] = {
		RunSerial = runSerial,
		Level = 1,
		Distance = 0,
		AttackSpeedMultiplier = 1,
		KnockbackMultiplier = 1,
		CriticalChance = 0,
		Upgrades = {},
		LastUpgradeIndex = nil,
	}
	player:SetAttribute("RunLevel", 1)
	player:SetAttribute("RunDistance", 0)
	local levelStart, levelEnd = CONFIG.GetLevelBounds(1)
	player:SetAttribute("RunLevelStartDistance", levelStart)
	player:SetAttribute("RunLevelEndDistance", levelEnd)
	player:SetAttribute("RunDistanceToNextLevel", levelEnd)
	player:SetAttribute("RunStartLogicalHeight", nil)
	player:SetAttribute("RunAttackSpeedMultiplier", 1)
	player:SetAttribute("RunKnockbackMultiplier", 1)
	player:SetAttribute("RunCriticalBonus", 0)
	player:SetAttribute("RunLastUpgrade", "")
	player:SetAttribute("RunUpgradeSummary", "")
	setMultipliers(player, 1)

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute("RunLevelReset", true)
	end
end

function RunLevelService.UpdateProgress(player, logicalHeight)
	local state = states[player]
	if not state then
		RunLevelService.Reset(player, player.Character)
		state = states[player]
	end
	local startHeight = tonumber(player:GetAttribute("RunStartLogicalHeight"))
	if not startHeight then
		player:SetAttribute("RunStartLogicalHeight", logicalHeight)
		startHeight = logicalHeight
	end
	local distance = math.max(state.Distance, math.max(0, logicalHeight - startHeight))
	state.Distance = distance
	local nextLevel = CONFIG.GetLevelFromDistance(distance)
	if nextLevel > state.Level then
		for level = state.Level + 1, nextLevel do
			applyUpgrade(player, state, level)
		end
		state.Level = nextLevel
		setMultipliers(player, nextLevel)
		player:SetAttribute("RunLevelUpSerial", (player:GetAttribute("RunLevelUpSerial") or 0) + 1)
	end
	local levelStart, levelEnd = CONFIG.GetLevelBounds(state.Level)
	player:SetAttribute("RunLevel", state.Level)
	player:SetAttribute("RunDistance", math.floor(distance))
	player:SetAttribute("RunLevelStartDistance", levelStart)
	player:SetAttribute("RunLevelEndDistance", levelEnd)
	player:SetAttribute("RunDistanceToNextLevel", math.max(0, math.ceil(levelEnd - distance)))
	return state.Level, distance
end

function RunLevelService.Remove(player)
	states[player] = nil
end

return RunLevelService