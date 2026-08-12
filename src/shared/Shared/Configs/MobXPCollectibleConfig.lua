--[[
	Infinity Islands - Mob XP Collectible Config V1

	Mob defeated -> strong death knockback -> XP fragments scatter ->
	short ground pause -> fragments magnet toward the last hitter ->
	XP is granted only when each fragment is collected.
]]

local Config = {}

Config.Version = "MobXPCollectiblesV4StaggeredSpawn"
Config.AwardPolicy = "LastHitPhysicalXPCollectiblesV1"

-- Complex collectible models are intentionally created a little at a time.
-- Publishing an entire XP burst in one Heartbeat causes a noticeable cold-start
-- frame spike on mobile devices when meshes, bones, trails and highlights are
-- seen for the first time.
Config.MaxPieceCreationsPerHeartbeat = 1

Config.MinimumPieces = 5
Config.MaximumPieces = 9
Config.XPPerExtraPiece = 9

Config.ScatterDuration = 1.15
Config.MinimumScatterSpeed = 8
Config.MaximumScatterSpeed = 17
Config.MinimumScatterUpwardSpeed = 11
Config.MaximumScatterUpwardSpeed = 19
Config.ScatterGravity = 48

Config.GroundHoverHeight = 0.55
-- Collection is NOT awarded by radius anymore.
-- This is only the distance at which we begin the precise overlap test.
Config.ContactCheckDistance = 5.0
Config.MaximumLifetime = 14

Config.MagnetStartSpeed = 18
Config.MagnetMaximumSpeed = 82
Config.MagnetAcceleration = 95
Config.MagnetTargetHeight = 1.35

Config.TrailLifetime = 0.22
Config.TrailWidth = 0.42

Config.DeathKnockbackDelay = 0.035
Config.DeathHorizontalSpeed = 68
Config.DeathUpwardSpeed = 27
Config.DeathAngularSpeed = 8

Config.RuntimeFolderName = "DungeonXPCollectibles"

-- Visual presentation.
Config.VisualScale = 0.75
Config.FixedRotation = true

-- Match the old AnimeOutline defaults used by the original collectibles.
Config.OutlineColor = Color3.fromRGB(30, 27, 40)
Config.OutlineTransparency = 0.15
Config.FillTransparency = 1

Config.TemplateIds = table.freeze({
	"BlueCrystal",
	"GoldenOrb",
	"RubyShard",
})

Config.FallbackColors = table.freeze({
	BlueCrystal = Color3.fromRGB(48, 170, 255),
	GoldenOrb = Color3.fromRGB(255, 196, 45),
	RubyShard = Color3.fromRGB(235, 55, 92),
})

function Config.GetPieceCount(totalXP)
	totalXP = math.max(
		1,
		math.floor(tonumber(totalXP) or 1)
	)

	return math.clamp(
		Config.MinimumPieces
			+ math.floor(
				totalXP
					/ Config.XPPerExtraPiece
			),
		Config.MinimumPieces,
		Config.MaximumPieces
	)
end

return table.freeze(Config)
