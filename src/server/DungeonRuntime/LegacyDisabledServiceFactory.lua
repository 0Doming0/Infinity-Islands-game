--[[
	Infinity Islands - Task 12
	LegacyDisabledServiceFactory

	Keeps old module paths callable while removing old gameplay behavior.

	The large DungeonRuntimeService still imports a few legacy paths because it
	also owns session/reconnect/wipe/return infrastructure. Rewriting that large
	service is unnecessary risk for the MVP.

	These shells make those imports inert.
]]

local Factory = {}

local function snapshot(serviceName)
	return {
		Ready = false,
		Disabled = true,
		Service = serviceName,
		Reason = "SimplifiedCombatMVP",
	}
end

function Factory.Create(
	serviceName,
	readyAttribute
)
	local Service = {}

	local function publish()
		workspace:SetAttribute(
			"DungeonLegacy"
				.. serviceName
				.. "Disabled",
			true
		)

		if readyAttribute then
			workspace:SetAttribute(
				readyAttribute,
				false
			)
		end
	end

	function Service.Start(_options)
		publish()
		return true,
			"LegacyDisabled"
	end

	function Service.Stop()
		publish()
		return true
	end

	function Service.GetSnapshot(_player)
		return snapshot(serviceName)
	end

	function Service.SetCombatEnabled(_enabled)
		return true,
			"LegacyDisabled"
	end

	function Service.SetParticipantConnected(
		_userId,
		_connected
	)
		return true
	end

	function Service.SyncPlayer(_player)
		return false,
			"LegacyDisabled"
	end

	function Service.BeginChoice(
		_player,
		_roundIndex
	)
		return false,
			"RunUpgradesDisabled"
	end

	function Service.IsResolved(
		_player,
		_roundIndex
	)
		return true
	end

	function Service.BeginRound(
		_result,
		_context
	)
		return false,
			"RewardIslandsDisabled"
	end

	function Service.Claim(
		_player,
		_role
	)
		return false,
			"RewardIslandsDisabled"
	end

	function Service.AttractRound(
		_roundIndex,
		_reason
	)
		return 0
	end

	function Service.HandleIslandEntered(
		_player,
		_context
	)
		return false,
			"OptionalIslandsDisabled"
	end

	function Service.BeginObjective(
		_definition,
		_context
	)
		return false,
			"LegacyObjectivesDisabled"
	end

	function Service.CompleteObjective(_id)
		return true
	end

	function Service.Recover(...)
		return false,
			"LegacyObjectivesDisabled"
	end

	function Service.Create(_options)
		return false,
			"BossDisabled"
	end

	function Service.Attach(
		_bossState,
		_options
	)
		return false,
			"BossDisabled"
	end

	function Service.HandleDefeated(
		_boss,
		_snapshot
	)
		return 0
	end

	function Service.GetEligibleUserIds()
		return {}
	end

	function Service.ActivateForTesting(_player)
		return false,
			"BossDisabled"
	end

	function Service.FinishRun(_reason)
		return true
	end

	function Service.MarkBossActive(_snapshot)
		return true
	end

	function Service.MarkBossReady(_context)
		return true
	end

	function Service.SetObjective(_definition)
		return false,
			"LegacyObjectivesDisabled"
	end

	function Service.AddProgress(...)
		return false,
			"LegacyObjectivesDisabled"
	end

	setmetatable(
		Service,
		{
			__index = function(_, methodName)
				return function(...)
					publish()
					return false,
						"LegacyDisabled:"
							.. tostring(
								methodName
							)
				end
			end,
		}
	)

	publish()

	return Service
end

return Factory
