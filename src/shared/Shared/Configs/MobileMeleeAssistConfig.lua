--[[
	Infinity Islands - Task 14
	MobileMeleeAssistConfig V1

	Goal:
	make manual sword attacks substantially easier on touch devices without
	turning combat into auto-combat.

	The client may rotate its own character toward a nearby valid combat target.
	The server still owns:
	- attack timing validation;
	- hitbox;
	- target validation;
	- damage;
	- death / XP.

	No target is trusted by the server.
]]

local Config = {}

Config.Version = "MobileMeleeAssistV1"

Config.Enabled = true

-- Assistance only runs when Roblox reports a touch-capable device.
Config.TouchOnly = true

-- The player still has to get close. This does not pull/teleport the character.
Config.MaximumTargetDistance = 10.5

-- Half-angle around movement/facing direction.
-- 82 degrees makes melee forgiving while still rejecting enemies clearly behind.
Config.MaximumAssistAngleDegrees = 82

-- How strongly one tap rotates toward the selected target.
-- 1 = snap fully. Keep below 1 so the player still feels in control.
Config.FacingStrength = 0.90

-- Briefly suppress Humanoid.AutoRotate so movement does not instantly undo
-- the assisted facing before the server-side melee windup resolves.
Config.FacingHoldSeconds = 0.10

-- Candidate scoring. Lower = better.
Config.DistanceWeight = 0.68
Config.AngleWeight = 0.32

-- Prefer the player's movement direction while actively moving.
Config.UseMoveDirection = true
Config.MoveDirectionThreshold = 0.12

-- Only new MVP combat targets are assistable.
Config.RequireIslandCombatManaged = true
Config.RequireSameCombatIsland = true

-- The existing CombatConfig already exposes InputBufferTime=0.16.
Config.UseExistingSwordInputBuffer = true

return table.freeze(Config)
