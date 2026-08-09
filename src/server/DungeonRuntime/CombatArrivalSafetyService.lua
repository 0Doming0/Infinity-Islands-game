--[[
	Infinity Islands - Task 22
	CombatArrivalSafetyService V1

	Goal:
	avoid "spawned and instantly got hit" frustration.

	Protection is server authoritative and short.

	Two protection layers are used:
	1. an invisible ForceField, covering Humanoid:TakeDamage;
	2. a HealthChanged guard, covering legacy code that writes Humanoid.Health.

	The service never heals above the health the player had when protection began.

	No HUD is created.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.CombatArrivalSafetyConfig
)

local Service = {}

local started = false

local states =
	setmetatable({}, { __mode = "k" })

local function now()
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

local function telemetryElapsed(player)
	local baseline =
		telemetryBaseline(player)

	if not baseline then
		return nil
	end

	return math.max(
		0,
		now() - baseline
	)
end

local function insideTelemetryWindow(player)
	local elapsed =
		telemetryElapsed(player)

	return elapsed ~= nil
		and elapsed
			<= Config.TelemetryWindowSeconds
end

local function setProtectionAttributes(
	player,
	character,
	protected,
	reason,
	untilAt
)
	player:SetAttribute(
		"DungeonDamageProtected",
		protected
	)

	player:SetAttribute(
		"DungeonDamageProtectionReason",
		protected
			and tostring(reason)
			or nil
	)

	player:SetAttribute(
		"DungeonDamageProtectedUntil",
		protected
			and untilAt
			or nil
	)

	if character
		and character.Parent
	then
		character:SetAttribute(
			"DungeonDamageProtected",
			protected
		)

		character:SetAttribute(
			"DungeonDamageProtectionReason",
			protected
				and tostring(reason)
				or nil
		)

		character:SetAttribute(
			"DungeonDamageProtectedUntil",
			protected
				and untilAt
				or nil
		)
	end
end

local function destroyOwnedForceField(state)
	local forceField =
		state.ForceField

	if forceField
		and forceField.Parent
	then
		forceField:Destroy()
	end

	state.ForceField = nil
end

local function ensureForceField(
	state,
	character
)
	if state.ForceField
		and state.ForceField.Parent
			== character
	then
		return state.ForceField
	end

	destroyOwnedForceField(state)

	local forceField =
		Instance.new("ForceField")

	forceField.Name =
		Config.ForceFieldName

	forceField.Visible =
		Config.ForceFieldVisible

	forceField:SetAttribute(
		"DungeonArrivalSafetyOwned",
		true
	)

	forceField.Parent =
		character

	state.ForceField =
		forceField

	return forceField
end

local function endProtection(
	player,
	state,
	token
)
	if not state
		or state.ProtectionToken
			~= token
	then
		return
	end

	if now()
		< (state.ProtectedUntil or 0)
	then
		local remaining =
			state.ProtectedUntil - now()

		task.delay(
			math.max(
				0.02,
				remaining
			),
			function()
				endProtection(
					player,
					state,
					token
				)
			end
		)

		return
	end

	state.ProtectedUntil = 0
	state.ProtectedHealth = nil

	destroyOwnedForceField(state)

	setProtectionAttributes(
		player,
		state.Character,
		false,
		nil,
		nil
	)
end

local function beginProtection(
	player,
	reason,
	seconds
)
	local state =
		states[player]

	if not state
		or not state.Character
		or not state.Character.Parent
	then
		return false,
			"CharacterUnavailable"
	end

	local humanoid =
		state.Humanoid

	if not humanoid
		or not humanoid.Parent
		or humanoid.Health <= 0
	then
		return false,
			"HumanoidUnavailable"
	end

	local duration =
		math.clamp(
			tonumber(seconds) or 0,
			Config.MinimumProtectionSeconds,
			Config.MaximumProtectionSeconds
		)

	local timestamp = now()
	local requestedUntil =
		timestamp + duration

	-- Extend, never shorten, a protection already in progress.
	state.ProtectedUntil =
		math.max(
			state.ProtectedUntil or 0,
			requestedUntil
		)

	state.ProtectedHealth =
		math.max(
			0,
			humanoid.Health
		)

	state.ProtectionToken =
		(state.ProtectionToken or 0) + 1

	local token =
		state.ProtectionToken

	ensureForceField(
		state,
		state.Character
	)

	setProtectionAttributes(
		player,
		state.Character,
		true,
		reason,
		state.ProtectedUntil
	)

	player:SetAttribute(
		"DungeonDamageProtectionCount",
		(
			tonumber(
				player:GetAttribute(
					"DungeonDamageProtectionCount"
				)
			) or 0
		) + 1
	)

	player:SetAttribute(
		"DungeonLastDamageProtectionAt",
		timestamp
	)

	task.delay(
		duration,
		function()
			endProtection(
				player,
				state,
				token
			)
		end
	)

	return true
end

local function protectionActive(state)
	return state ~= nil
		and state.ProtectedUntil ~= nil
		and state.ProtectedUntil > now()
end

local function recordUnprotectedDamage(
	player,
	amount
)
	if amount <= 0 then
		return
	end

	player:SetAttribute(
		"DungeonLastDamageTaken",
		amount
	)

	player:SetAttribute(
		"DungeonLastDamageTakenAt",
		now()
	)

	if not insideTelemetryWindow(
		player
	) then
		return
	end

	player:SetAttribute(
		"EarlyCombatDamageTaken90s",
		(
			tonumber(
				player:GetAttribute(
					"EarlyCombatDamageTaken90s"
				)
			) or 0
		) + amount
	)

	local elapsed =
		telemetryElapsed(player)

	if player:GetAttribute(
		"EarlyCombatFirstDamageSeconds"
	) == nil
		and elapsed ~= nil
	then
		player:SetAttribute(
			"EarlyCombatFirstDamageSeconds",
			elapsed
		)
	end
end

local function recordBlockedDamage(
	player,
	amount,
	reason
)
	if amount <= 0 then
		return
	end

	player:SetAttribute(
		"DungeonArrivalSafetyBlockedDamage",
		(
			tonumber(
				player:GetAttribute(
					"DungeonArrivalSafetyBlockedDamage"
				)
			) or 0
		) + amount
	)

	player:SetAttribute(
		"DungeonArrivalSafetyLastBlockedDamage",
		amount
	)

	player:SetAttribute(
		"DungeonArrivalSafetyLastBlockedAt",
		now()
	)

	player:SetAttribute(
		"DungeonArrivalSafetyLastBlockedReason",
		tostring(reason or "Protected")
	)
end

local function bindHumanoid(
	player,
	state,
	character,
	humanoid
)
	state.Character =
		character

	state.Humanoid =
		humanoid

	state.LastHealth =
		humanoid.Health

	state.HealthConnection =
		humanoid.HealthChanged:Connect(
			function(newHealth)
				if state.Humanoid ~= humanoid
					or humanoid.Parent == nil
				then
					return
				end

				local previous =
					tonumber(
						state.LastHealth
					) or newHealth

				local decrease =
					math.max(
						0,
						previous - newHealth
					)

				if decrease > 0
					and protectionActive(
						state
					)
				then
					local restoreTo =
						math.max(
							newHealth,
							tonumber(
								state.ProtectedHealth
							) or previous
						)

					restoreTo =
						math.min(
							restoreTo,
							humanoid.MaxHealth
						)

					recordBlockedDamage(
						player,
						restoreTo - newHealth,
						player:GetAttribute(
							"DungeonDamageProtectionReason"
						)
					)

					if humanoid.Health
						< restoreTo
					then
						humanoid.Health =
							restoreTo
					end

					state.LastHealth =
						restoreTo

					state.ProtectedHealth =
						restoreTo

					return
				end

				if decrease > 0 then
					recordUnprotectedDamage(
						player,
						decrease
					)
				end

				state.LastHealth =
					newHealth

				if protectionActive(
					state
				) then
					-- Legitimate healing during protection increases the
					-- protected health floor; protection itself never heals.
					state.ProtectedHealth =
						math.max(
							tonumber(
								state.ProtectedHealth
							) or 0,
							newHealth
						)
				end
			end
		)

	state.DiedConnection =
		humanoid.Died:Connect(function()
			if insideTelemetryWindow(
				player
			) then
				player:SetAttribute(
					"EarlyCombatDeaths90s",
					(
						tonumber(
							player:GetAttribute(
								"EarlyCombatDeaths90s"
							)
						) or 0
					) + 1
				)

				if player:GetAttribute(
					"EarlyCombatFirstDeathSeconds"
				) == nil
				then
					local elapsed =
						telemetryElapsed(
							player
						)

					if elapsed ~= nil then
						player:SetAttribute(
							"EarlyCombatFirstDeathSeconds",
							elapsed
						)
					end
				end
			end
		end)
end

local function disconnectCharacterState(
	state
)
	if state.HealthConnection then
		state.HealthConnection:Disconnect()
		state.HealthConnection = nil
	end

	if state.DiedConnection then
		state.DiedConnection:Disconnect()
		state.DiedConnection = nil
	end

	destroyOwnedForceField(state)

	state.Character = nil
	state.Humanoid = nil
	state.LastHealth = nil
	state.ProtectedHealth = nil
	state.ProtectedUntil = 0
end

local function onCharacterAdded(
	player,
	character
)
	local state =
		states[player]

	if not state then
		return
	end

	disconnectCharacterState(
		state
	)

	local humanoid =
		character:WaitForChild(
			"Humanoid",
			10
		)

	if not humanoid then
		return
	end

	bindHumanoid(
		player,
		state,
		character,
		humanoid
	)

	state.CharacterSpawnCount =
		(state.CharacterSpawnCount or 0) + 1

	local isInitial =
		state.CharacterSpawnCount == 1

	beginProtection(
		player,
		isInitial
			and "InitialSpawn"
			or "Respawn",
		isInitial
			and Config.InitialSpawnSeconds
			or Config.RespawnSeconds
	)
end

local function onIslandChanged(player)
	local state =
		states[player]

	if not state then
		return
	end

	local island =
		math.floor(
			tonumber(
				player:GetAttribute(
					"CurrentGlobalIslandIndex"
				)
			) or 0
		)

	if island <= 0 then
		return
	end

	local previousHighest =
		math.floor(
			tonumber(
				state.HighestProtectedIsland
			) or 0
		)

	if Config
			.NewIslandProtectionOnlyWhenProgressingForward
		and island <= previousHighest
	then
		return
	end

	state.HighestProtectedIsland =
		math.max(
			previousHighest,
			island
		)

	player:SetAttribute(
		"DungeonArrivalSafetyHighestIsland",
		state.HighestProtectedIsland
	)

	-- Initial spawn protection already covers the first island.
	if island <= 1 then
		return
	end

	beginProtection(
		player,
		"NewIsland:"
			.. tostring(island),
		Config.NewIslandSeconds
	)
end

local function bindPlayer(player)
	if states[player] then
		return
	end

	local state = {
		CharacterSpawnCount = 0,
		HighestProtectedIsland = 0,
		ProtectionToken = 0,
		ProtectedUntil = 0,
	}

	states[player] = state

	player:SetAttribute(
		"DungeonArrivalSafetyVersion",
		Config.Version
	)

	player:SetAttribute(
		"DungeonArrivalSafetyPolicy",
		Config.Policy
	)

	player:SetAttribute(
		"DungeonArrivalSafetyBlockedDamage",
		0
	)

	player:SetAttribute(
		"EarlyCombatDamageTaken90s",
		0
	)

	player:SetAttribute(
		"EarlyCombatDeaths90s",
		0
	)

	state.CharacterConnection =
		player.CharacterAdded:Connect(
			function(character)
				onCharacterAdded(
					player,
					character
				)
			end
		)

	state.IslandConnection =
		player:GetAttributeChangedSignal(
			"CurrentGlobalIslandIndex"
		):Connect(function()
			onIslandChanged(player)
		end)

	if player.Character then
		task.spawn(
			onCharacterAdded,
			player,
			player.Character
		)
	end

	task.defer(
		onIslandChanged,
		player
	)
end

local function unbindPlayer(player)
	local state =
		states[player]

	if not state then
		return
	end

	disconnectCharacterState(
		state
	)

	if state.CharacterConnection then
		state.CharacterConnection:Disconnect()
	end

	if state.IslandConnection then
		state.IslandConnection:Disconnect()
	end

	states[player] = nil
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonArrivalSafetyReady",
		true
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyVersion",
		Config.Version
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyPolicy",
		Config.Policy
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyInitialSpawnSeconds",
		Config.InitialSpawnSeconds
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyRespawnSeconds",
		Config.RespawnSeconds
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyNewIslandSeconds",
		Config.NewIslandSeconds
	)

	workspace:SetAttribute(
		"DungeonArrivalSafetyBacktrackProtection",
		false
	)

	Players.PlayerAdded:Connect(
		bindPlayer
	)

	Players.PlayerRemoving:Connect(
		unbindPlayer
	)

	for _, player in ipairs(
		Players:GetPlayers()
	) do
		bindPlayer(player)
	end

	return true
end

return Service
