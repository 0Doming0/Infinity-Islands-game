--[[
	Infinity Islands - Task 15
	MobileDungeonCameraConfig V2

	Touch Dungeon camera:
	- portrait presentation is already owned by InputProfileController;
	- this config owns only camera framing;
	- desktop/console keep Roblox default camera.

	The camera is deliberately near top-down, not perfectly vertical.
	A small back offset preserves depth perception for jumps/island edges.
]]

local Config = {}

Config.Version = "DungeonMobileArenaCameraV2"

Config.Height = 31
Config.BackDistance = 8.5
Config.FieldOfView = 64

Config.FocusHeight = 2.2

-- Player movement shifts the frame slightly toward where the player is going.
Config.MovementLookAhead = 4.5
Config.LookAheadSmoothSpeed = 8

-- The fixed camera forward is biased slightly ahead of the character.
Config.ForwardBias = 2.5

-- Nearby managed mobs can shift framing toward the fight without rotating,
-- moving, or aiming the player.
Config.CombatFocusEnabled = true
Config.CombatFocusRadius = 20
Config.CombatFocusMaximumShift = 4.5
Config.CombatFocusWeight = 0.42
Config.CombatFocusSmoothSpeed = 7

Config.SmoothSpeed = 10
Config.SnapDistance = 55

Config.OcclusionPadding = 1.4

Config.MinimumHeight = 22
Config.MaximumHeight = 40

Config.MinimumBackDistance = 4
Config.MaximumBackDistance = 16

Config.MinimumFOV = 54
Config.MaximumFOV = 78

return table.freeze(Config)
