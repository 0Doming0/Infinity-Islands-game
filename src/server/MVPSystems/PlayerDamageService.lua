--[[
	Infinity Islands - Task 23
	PlayerDamageService V4 - Enemy Hit Cadence

	Single authoritative point for enemy -> player damage.

	Preserved responsibilities:
	- DownedService fatal interception;
	- safe/rescue protection;
	- tutorial compatibility;
	- respawn / ForceField protection;
	- ranged area line-of-sight guard;
	- analytics.

	New:
	- Task 22 CombatArrivalSafety attribute awareness;
	- short global damage i-frame;
	- minimum accepted interval by attack source;
	- early-session cadence telemetry.

	The existing SlimeController still owns wind-up/attack animation/timing.
	This service only decides whether a completed enemy hit may deal damage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DownedService = require(
	script.Parent:WaitForChild("DownedService")
)

local GameplayAnalytics = require(
	script.Parent.Parent:WaitForChild("GameplayAnalyticsService")
)

local EnemyHitCadenceConfig = require(
	ReplicatedStorage.Shared.Configs.EnemyHitCadenceConfig
)

DownedService.Start()

local PlayerDamageService = {}

local VERSION =
	"AuthoritativeProtectionCadenceV4"

local playerCadence =
	setmetatable({}, { __mode = "k" })

workspace:SetAttribute(
	"PlayerDamageProtectionVersion",
	VERSION
)

workspace:SetAttribute(
	"DungeonEnemyHitCadenceVersion",
	EnemyHitCadenceConfig.Version
)

workspace:SetAttribute(
	"DungeonEnemyHitCadencePolicy",
	EnemyHitCadenceConfig.Policy
)

workspace:SetAttribute(
	"DungeonEnemyGlobalHitIFrameSeconds",
	EnemyHitCadenceConfig.GlobalHitIFrameSeconds
)

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function telemetryBaseline(player)
	return tonumber(
		player:GetAttribute(
			"DungeonInstantControlReadyAt"
		)
			or player:GetAttribute(
				"DungeonDirectEntryStartedAt"
			)
	)
end

local function insideTelemetryWindow(player)
	local baseline =
		telemetryBaseline(player)

	if not baseline then
		return false
	end

	return serverTime() - baseline
		<= EnemyHitCadenceConfig
			.TelemetryWindowSeconds
end

local function hasTutorialEnemyProtection(player)
	-- New standalone runtime explicitly publishes false.
	-- Compatibility fallback remains for old test servers.
	local explicitProtection =
		player:GetAttribute(
			"TutorialEnemyProtection"
		)

	if typeof(explicitProtection)
		== "boolean"
	then
		return explicitProtection == true
			and player:GetAttribute(
				"TutorialCompleted"
			) ~= true
	end

	return player:GetAttribute(
		"TutorialCompleted"
	) ~= true
end

local function activeForceField(character)
	if not character then
		return nil
	end

	for _, child in ipairs(
		character:GetChildren()
	) do
		if child:IsA("ForceField") then
			return child
		end
	end

	return nil
end

local function hasArrivalSafetyProtection(
	player
)
	if player:GetAttribute(
		"DungeonDamageProtected"
	) ~= true
	then
		return false,
			nil
	end

	local untilAt =
		tonumber(
			player:GetAttribute(
				"DungeonDamageProtectedUntil"
			)
		) or 0

	if untilAt > serverTime() then
		return true,
			"CombatArrivalSafety"
	end

	return false,
		nil
end

local function hasSafeZoneOrRescueProtection(
	player
)
	local rescueState =
		tostring(
			player:GetAttribute(
				"SanctuaryRescueState"
			) or "Idle"
		)

	local rescueProtectionUntil =
		tonumber(
			player:GetAttribute(
				"SanctuaryRescueProtectionUntil"
			)
		) or 0

	local rescueProtected =
		rescueState == "Searching"
			or rescueState == "Teleporting"
			or rescueState == "Stabilizing"
			or serverTime()
				< rescueProtectionUntil

	if player:GetAttribute(
		"InSafeZone"
	) == true
	then
		return true,
			"SafeZone"
	end

	if rescueProtected then
		return true,
			"SanctuaryRescue:"
				.. rescueState
	end

	return false,
		nil
end

local function hasRespawnProtection(
	player,
	character
)
	local protectionUntil =
		tonumber(
			player:GetAttribute(
				"RespawnProtectionUntil"
			)
		) or 0

	if player:GetAttribute(
		"RespawnProtectionActive"
	) == true
		and protectionUntil
			> serverTime()
	then
		return true,
			"RespawnProtectionAttribute"
	end

	local forceField =
		activeForceField(character)

	if forceField then
		return true,
			"ForceField:"
				.. forceField.Name
	end

	return false,
		nil
end

local function rangedAreaAttackIsBlocked(
	player,
	source
)
	-- SlimeArea = mortar/area impact.
	if tostring(source or "")
		~= "SlimeArea"
	then
		return false
	end

	local visibleThreatCount =
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"RangedVisibleThreatCount"
					)
				) or 0
			)
		)

	return visibleThreatCount <= 0
end

local function recordBlockedDamage(
	player,
	source,
	amount,
	reason
)
	local timestamp =
		serverTime()

	player:SetAttribute(
		"LastProtectedDamageSource",
		tostring(
			source or "Enemy"
		)
	)

	player:SetAttribute(
		"LastProtectedDamageAmount",
		math.max(
			0,
			tonumber(amount) or 0
		)
	)

	player:SetAttribute(
		"LastProtectedDamageReason",
		tostring(
			reason or "Protected"
		)
	)

	player:SetAttribute(
		"LastProtectedDamageAt",
		timestamp
	)

	player:SetAttribute(
		"ProtectedDamageBlockedCount",
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"ProtectedDamageBlockedCount"
					)
				) or 0
			)
		) + 1
	)
end

local function recordSpecialProtection(
	player,
	source,
	reason
)
	local timestamp =
		serverTime()

	local sourceName =
		tostring(
			source or "Enemy"
		)

	if reason
		== "TutorialEnemyProtection"
	then
		player:SetAttribute(
			"TutorialEnemyProtection",
			true
		)

		player:SetAttribute(
			"LastTutorialBlockedEnemySource",
			sourceName
		)

		player:SetAttribute(
			"LastTutorialBlockedEnemyAt",
			timestamp
		)
	elseif reason == "SafeZone"
		or string.sub(
			reason,
			1,
			#"SanctuaryRescue:"
		) == "SanctuaryRescue:"
	then
		player:SetAttribute(
			"LastSafeZoneBlockedEnemySource",
			sourceName
		)

		player:SetAttribute(
			"LastSafeZoneBlockedEnemyAt",
			timestamp
		)
	end
end

local function cadenceState(player)
	local state =
		playerCadence[player]

	if state then
		return state
	end

	state = {
		LastAcceptedAt = -math.huge,
		LastBySource = {},
	}

	playerCadence[player] =
		state

	return state
end

local function recordCadenceBlock(
	player,
	source,
	reason,
	remaining
)
	local sourceName =
		tostring(
			source or "Enemy"
		)

	player:SetAttribute(
		"LastEnemyCadenceBlockedSource",
		sourceName
	)

	player:SetAttribute(
		"LastEnemyCadenceBlockedReason",
		reason
	)

	player:SetAttribute(
		"LastEnemyCadenceBlockedAt",
		serverTime()
	)

	player:SetAttribute(
		"LastEnemyCadenceBlockedRemaining",
		math.max(
			0,
			tonumber(remaining) or 0
		)
	)

	player:SetAttribute(
		"EnemyCadenceBlockedHitCount",
		(
			tonumber(
				player:GetAttribute(
					"EnemyCadenceBlockedHitCount"
				)
			) or 0
		) + 1
	)

	if insideTelemetryWindow(player) then
		player:SetAttribute(
			"EarlyCombatCadenceBlockedHits90s",
			(
				tonumber(
					player:GetAttribute(
						"EarlyCombatCadenceBlockedHits90s"
					)
				) or 0
			) + 1
		)
	end
end

local function cadenceAllows(
	player,
	source
)
	local timestamp =
		serverTime()

	local state =
		cadenceState(player)

	local globalInterval =
		EnemyHitCadenceConfig
			.GlobalHitIFrameSeconds

	local sinceAny =
		timestamp
			- state.LastAcceptedAt

	if sinceAny < globalInterval then
		recordCadenceBlock(
			player,
			source,
			"GlobalHitIFrame",
			globalInterval - sinceAny
		)

		return false
	end

	local sourceName =
		tostring(
			source or "Enemy"
		)

	local sourceInterval =
		EnemyHitCadenceConfig
			.GetSourceInterval(
				sourceName
			)

	local lastSourceAt =
		state.LastBySource[sourceName]
			or -math.huge

	local sinceSource =
		timestamp
			- lastSourceAt

	if sinceSource < sourceInterval then
		recordCadenceBlock(
			player,
			sourceName,
			"SourceInterval",
			sourceInterval - sinceSource
		)

		return false
	end

	return true
end

local function commitCadenceHit(
	player,
	source
)
	local timestamp =
		serverTime()

	local sourceName =
		tostring(
			source or "Enemy"
		)

	local state =
		cadenceState(player)

	state.LastAcceptedAt =
		timestamp

	state.LastBySource[sourceName] =
		timestamp

	player:SetAttribute(
		"EnemyCadenceLastAcceptedAt",
		timestamp
	)

	player:SetAttribute(
		"EnemyCadenceLastAcceptedSource",
		sourceName
	)

	player:SetAttribute(
		"EnemyCadenceAcceptedHitCount",
		(
			tonumber(
				player:GetAttribute(
					"EnemyCadenceAcceptedHitCount"
				)
			) or 0
		) + 1
	)

	if insideTelemetryWindow(player) then
		player:SetAttribute(
			"EarlyCombatAcceptedHits90s",
			(
				tonumber(
					player:GetAttribute(
						"EarlyCombatAcceptedHits90s"
					)
				) or 0
			) + 1
		)
	end
end

function PlayerDamageService.IsProtected(
	player,
	humanoid
)
	if not player
		or player.Parent ~= Players
	then
		return true,
			"InvalidPlayer"
	end

	local character =
		humanoid
			and humanoid.Parent
			or player.Character

	if player:GetAttribute(
		"IsDowned"
	) == true
	then
		return true,
			"AlreadyDowned"
	end

	if player:GetAttribute(
		"InvisibleToEnemies"
	) == true
	then
		return true,
			"InvisibleToEnemies"
	end

	if (
		tonumber(
			player:GetAttribute(
				"DungeonEntryProtectionUntil"
			)
		) or 0
	) > serverTime()
	then
		return true,
			"DungeonEntryProtection"
	end

	local protected,
		reason =
			hasArrivalSafetyProtection(
				player
			)

	if protected then
		return true,
			reason
	end

	protected,
		reason =
			hasSafeZoneOrRescueProtection(
				player
			)

	if protected then
		return true,
			reason
	end

	if hasTutorialEnemyProtection(
		player
	) then
		return true,
			"TutorialEnemyProtection"
	end

	protected,
		reason =
			hasRespawnProtection(
				player,
				character
			)

	if protected then
		return true,
			reason
	end

	return false,
		nil
end

function PlayerDamageService.Apply(
	player,
	humanoid,
	baseDamage,
	source
)
	if not player
		or player.Parent ~= Players
		or not humanoid
		or humanoid.Health <= 0
	then
		return 0
	end

	local protected,
		protectionReason =
			PlayerDamageService.IsProtected(
				player,
				humanoid
			)

	if protected then
		if protectionReason
			~= "AlreadyDowned"
			and protectionReason
				~= "InvisibleToEnemies"
			and protectionReason
				~= "InvalidPlayer"
		then
			recordSpecialProtection(
				player,
				source,
				protectionReason
			)

			recordBlockedDamage(
				player,
				source,
				baseDamage,
				protectionReason
			)
		end

		return 0
	end

	if rangedAreaAttackIsBlocked(
		player,
		source
	) then
		recordBlockedDamage(
			player,
			source,
			baseDamage,
			"RangedLineOfSightBlocked"
		)

		return 0
	end

	if not cadenceAllows(
		player,
		source
	) then
		-- A cadence block is not reported as protection. It is combat fairness,
		-- not immunity/safe-zone state.
		return 0
	end

	local multiplier =
		math.max(
			1,
			tonumber(
				player:GetAttribute(
					"RunDamageTakenMultiplier"
				)
			) or 1
		)

	local damage =
		math.max(
			0,
			tonumber(baseDamage) or 0
		) * multiplier

	if damage <= 0 then
		return 0
	end

	-- Reserve the cadence BEFORE any fatal/downed callbacks.
	-- A single attack cannot re-enter and deal another hit in the same frame.
	commitCadenceHit(
		player,
		source
	)

	player:SetAttribute(
		"LastEnemyDamage",
		damage
	)

	player:SetAttribute(
		"LastEnemyDamageSource",
		tostring(
			source or "Enemy"
		)
	)

	player:SetAttribute(
		"LastDamageReceivedAt",
		serverTime()
	)

	GameplayAnalytics
		.RecordEnemyEncountered(
			player,
			nil
		)

	GameplayAnalytics
		.RecordPlayerDamagedByEnemy(
			player,
			source
		)

	if DownedService.TryInterceptFatal(
		player,
		humanoid,
		damage,
		source
	) then
		return damage
	end

	humanoid:TakeDamage(
		damage
	)

	return damage
end

function PlayerDamageService.ApplyToHumanoid(
	humanoid,
	baseDamage,
	source
)
	local character =
		humanoid
			and humanoid.Parent

	local player =
		character
			and Players
				:GetPlayerFromCharacter(
					character
				)

	return PlayerDamageService.Apply(
		player,
		humanoid,
		baseDamage,
		source
	)
end

return table.freeze(
	PlayerDamageService
)
