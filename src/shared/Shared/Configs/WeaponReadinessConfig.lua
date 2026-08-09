--[[
	Infinity Islands - Task 25
	WeaponReadinessConfig V1

	Direct-to-Dungeon MVP:
	the starter sword should be ready without requiring inventory friction.

	Rules:
	- auto-equip ClassicSword once per character spawn;
	- never replace another equipped Tool;
	- never repeatedly re-equip after the player manually unequips/switches;
	- respawn may auto-equip once again.
]]

local Config = {}

Config.Version = "WeaponReadinessV1"
Config.Policy = "AutoEquipStarterOncePerCharacter"

Config.AutoEquipEnabled = true
Config.AutoEquipWindowSeconds = 8.0
Config.ReadinessCheckTimeoutSeconds = 10.0

Config.StarterSwordNames = table.freeze({
	ClassicSword = true,
})

Config.StarterSwordIds = table.freeze({
	ClassicSword = true,
})

return table.freeze(Config)
