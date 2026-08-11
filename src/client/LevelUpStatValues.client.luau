local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local PlayerLevelConfig = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("PlayerLevelConfig")
)

local DAMAGE_BASE_FALLBACK = 20
local lastSerial

local function findPanel()
	local hud = playerGui:FindFirstChild("DungeonHUD")
	return hud and hud:FindFirstChild("LevelUpPanel", true)
end

local function findStatValue(panel, upgradeName)
	local upgrade = panel
		and panel:FindFirstChild(upgradeName, true)
	return upgrade and upgrade:FindFirstChild("StatValue", true)
end

local function getDamageBase()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local damage = tool and tool:GetAttribute("BaseDamage")
	if typeof(damage) == "number" and damage > 0 then
		return damage
	end
	return DAMAGE_BASE_FALLBACK
end

local function getHealthBase()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return 100
	end

	local base = humanoid:GetAttribute("PlayerLevelBaseMaxHealth")
	if typeof(base) == "number" and base > 0 then
		return base
	end
	return math.max(1, humanoid.MaxHealth)
end

local function formatGain(value)
	local rounded = math.floor(value + 0.5)
	if rounded < 1 and value > 0 then
		rounded = 1
	end
	return string.format("+%d", rounded)
end

local function updateValues(fromLevel, toLevel)
	local panel = findPanel()
	if not panel then
		return
	end

	local previousDamageMultiplier = PlayerLevelConfig.GetDamageMultiplier(fromLevel)
	local currentDamageMultiplier = PlayerLevelConfig.GetDamageMultiplier(toLevel)
	local previousHealthMultiplier = PlayerLevelConfig.GetHealthMultiplier(fromLevel)
	local currentHealthMultiplier = PlayerLevelConfig.GetHealthMultiplier(toLevel)

	local damageGain = getDamageBase()
		* (currentDamageMultiplier - previousDamageMultiplier)
	local healthGain = getHealthBase()
		* (currentHealthMultiplier - previousHealthMultiplier)

	local healthValue = findStatValue(panel, "Upgrade1")
	local damageValue = findStatValue(panel, "Upgrade2")
	if healthValue then
		healthValue.Text = formatGain(healthGain)
	end
	if damageValue then
		damageValue.Text = formatGain(damageGain)
	end
end

local function updateFromAttributes()
	local serial = player:GetAttribute("PlayerLevelUpSerial")
	if serial == nil or serial == lastSerial then
		return
	end

	lastSerial = serial
	local fromLevel = tonumber(player:GetAttribute("LastLevelUpFrom")) or 1
	local toLevel = tonumber(player:GetAttribute("LastLevelUpTo")) or fromLevel + 1
	updateValues(fromLevel, toLevel)
end

player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(updateFromAttributes)
player.CharacterAdded:Connect(function()
	task.defer(updateFromAttributes)
end)

task.defer(updateFromAttributes)
