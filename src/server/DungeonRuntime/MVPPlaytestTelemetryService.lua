--[[
	Infinity Islands - Task 29
	MVPPlaytestTelemetryService V1

	The game is now simple enough that the next useful step is measurement.

	This service observes each Player from direct Dungeon entry and publishes
	a compact diagnosis for a 5-10 minute playtest.

	It never:
	- changes Humanoid properties;
	- grants XP;
	- changes Island progression;
	- spawns mobs;
	- teleports;
	- creates GUI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.MVPPlaytestTelemetryConfig
)

local Service = {}

local started = false

local states =
	setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function baseline(player)
	return tonumber(
		player:GetAttribute(
			"DungeonInstantControlReadyAt"
		)
			or player:GetAttribute(
				"DungeonDirectEntryStartedAt"
			)
	)
end

local function elapsed(player)
	local startedAt =
		baseline(player)

	if not startedAt then
		return nil
	end

	return math.max(
		0,
		now() - startedAt
	)
end

local function numberAttr(
	instance,
	name,
	fallback
)
	local value =
		instance:GetAttribute(
			name
		)

	if typeof(value) == "number"
		and value == value
	then
		return value
	end

	return fallback
end

local function integerAttr(
	instance,
	name,
	fallback
)
	return math.floor(
		numberAttr(
			instance,
			name,
			fallback or 0
		)
	)
end

local function boolAttr(
	instance,
	name
)
	return instance:GetAttribute(name)
		== true
end

local function setOnce(
	player,
	name,
	value
)
	if player:GetAttribute(name)
		== nil
	then
		player:SetAttribute(
			name,
			value
		)
	end
end

local function refreshMilestoneFlags(player)
	local firstXP =
		numberAttr(
			player,
			"EarlyPacingFirstXPSeconds",
			nil
		)

	if firstXP ~= nil then
		player:SetAttribute(
			"PlaytestFirstXPHealthy",
			firstXP
				<= Config
					.FirstXPHealthySeconds
		)
	end

	local firstLevelUp =
		numberAttr(
			player,
			"EarlyPacingFirstLevelUpSeconds",
			nil
		)

	if firstLevelUp ~= nil then
		player:SetAttribute(
			"PlaytestFirstLevelUpHealthy",
			firstLevelUp
				<= Config
					.FirstLevelUpHealthySeconds
		)
	end

	local island2 =
		numberAttr(
			player,
			"EarlyPacingIsland2Seconds",
			nil
		)

	if island2 ~= nil then
		player:SetAttribute(
			"PlaytestIsland2Healthy",
			island2
				<= Config
					.Island2HealthySeconds
		)
	end

	local island3 =
		numberAttr(
			player,
			"EarlyPacingIsland3Seconds",
			nil
		)

	if island3 ~= nil then
		player:SetAttribute(
			"PlaytestIsland3Healthy",
			island3
				<= Config
					.Island3HealthySeconds
		)
	end

	local firstKillTTK =
		numberAttr(
			player,
			"EarlyCombatFirstKillTTKSeconds",
			nil
		)

	if firstKillTTK ~= nil then
		player:SetAttribute(
			"PlaytestFirstKillTTKHealthy",
			firstKillTTK
				<= Config
					.FirstKillTTKHealthySeconds
		)
	end
end

local function diagnosticSummary(
	player,
	state
)
	local currentIsland =
		integerAttr(
			player,
			"CurrentGlobalIslandIndex",
			0
		)

	local playerLevel =
		integerAttr(
			player,
			"PlayerLevel",
			1
		)

	local deaths =
		integerAttr(
			player,
			"EarlyCombatDeaths90s",
			0
		)

	local firstXP =
		numberAttr(
			player,
			"EarlyPacingFirstXPSeconds",
			nil
		)

	local firstLevel =
		numberAttr(
			player,
			"EarlyPacingFirstLevelUpSeconds",
			nil
		)

	local firstTTK =
		numberAttr(
			player,
			"EarlyCombatFirstKillTTKSeconds",
			nil
		)

	local parts = {
		"Island="
			.. tostring(currentIsland),

		"Level="
			.. tostring(playerLevel),

		"Deaths90s="
			.. tostring(deaths),
	}

	if firstXP ~= nil then
		table.insert(
			parts,
			string.format(
				"FirstXP=%.1fs",
				firstXP
			)
		)
	else
		table.insert(
			parts,
			"FirstXP=missing"
		)
	end

	if firstLevel ~= nil then
		table.insert(
			parts,
			string.format(
				"FirstLevel=%.1fs",
				firstLevel
			)
		)
	else
		table.insert(
			parts,
			"FirstLevel=missing"
		)
	end

	if firstTTK ~= nil then
		table.insert(
			parts,
			string.format(
				"FirstTTK=%.2fs",
				firstTTK
			)
		)
	end

	if state.StallSeconds
		and state.StallSeconds > 0
	then
		table.insert(
			parts,
			string.format(
				"Stall=%.0fs",
				state.StallSeconds
			)
		)
	end

	return table.concat(
		parts,
		" | "
	)
end

local function snapshot(
	player,
	prefix
)
	local elapsedSeconds =
		elapsed(player)

	player:SetAttribute(
		prefix .. "Captured",
		true
	)

	player:SetAttribute(
		prefix .. "CapturedAt",
		now()
	)

	player:SetAttribute(
		prefix .. "ElapsedSeconds",
		elapsedSeconds
	)

	player:SetAttribute(
		prefix .. "Island",
		integerAttr(
			player,
			"CurrentGlobalIslandIndex",
			0
		)
	)

	player:SetAttribute(
		prefix .. "Level",
		integerAttr(
			player,
			"PlayerLevel",
			1
		)
	)

	player:SetAttribute(
		prefix .. "XP",
		numberAttr(
			player,
			"PlayerXP",
			0
		)
	)

	player:SetAttribute(
		prefix .. "TotalXP",
		numberAttr(
			player,
			"PlayerTotalXP",
			numberAttr(
				player,
				"EarlyPacing90SecondTotalXP",
				0
			)
		)
	)

	player:SetAttribute(
		prefix .. "Deaths",
		integerAttr(
			player,
			"EarlyCombatDeaths90s",
			0
		)
	)

	player:SetAttribute(
		prefix .. "DamageTaken90s",
		numberAttr(
			player,
			"EarlyCombatDamageTaken90s",
			0
		)
	)

	player:SetAttribute(
		prefix .. "AcceptedEnemyHits90s",
		integerAttr(
			player,
			"EarlyCombatAcceptedHits90s",
			0
		)
	)

	player:SetAttribute(
		prefix .. "BlockedEnemyHits90s",
		integerAttr(
			player,
			"EarlyCombatCadenceBlockedHits90s",
			0
		)
	)

	player:SetAttribute(
		prefix .. "AverageTTK90s",
		numberAttr(
			player,
			"EarlyCombatTTKAverageSeconds90s",
			0
		)
	)

	player:SetAttribute(
		prefix .. "ClearRecovery90s",
		numberAttr(
			player,
			"EarlyCombatClearRecovery90s",
			0
		)
	)

	player:SetAttribute(
		prefix .. "WeaponReadySeconds",
		numberAttr(
			player,
			"DungeonWeaponReadyFromEntrySeconds",
			-1
		)
	)

	player:SetAttribute(
		prefix .. "RouteComplete",
		boolAttr(
			player,
			"DungeonMVPVictory"
		)
			or workspace:GetAttribute(
				"DungeonMVPVictory"
			) == true
	)
end

local function updateProgressClock(
	player,
	state
)
	local currentIsland =
		integerAttr(
			player,
			"CurrentGlobalIslandIndex",
			0
		)

	local currentXP =
		numberAttr(
			player,
			"PlayerXP",
			0
		)

	local currentLevel =
		integerAttr(
			player,
			"PlayerLevel",
			1
		)

	local killSerial =
		integerAttr(
			player,
			"MobXPFeedbackSerial",
			0
		)

	local progressChanged =
		currentIsland
			~= state.LastIsland
		or currentXP
			~= state.LastXP
		or currentLevel
			~= state.LastLevel
		or killSerial
			~= state.LastKillSerial

	if progressChanged then
		state.LastProgressAt = now()
		state.LastIsland = currentIsland
		state.LastXP = currentXP
		state.LastLevel = currentLevel
		state.LastKillSerial =
			killSerial
	end

	state.StallSeconds =
		math.max(
			0,
			now()
				- state.LastProgressAt
		)

	player:SetAttribute(
		"PlaytestSecondsWithoutProgress",
		state.StallSeconds
	)

	player:SetAttribute(
		"PlaytestStallWarning",
		state.StallSeconds
			>= Config.StallWarningSeconds
	)

	player:SetAttribute(
		"PlaytestSevereStall",
		state.StallSeconds
			>= Config.SevereStallSeconds
	)

	if state.StallSeconds
		>= Config.StallWarningSeconds
	then
		setOnce(
			player,
			"PlaytestFirstStallAt",
			now()
		)

		setOnce(
			player,
			"PlaytestFirstStallIsland",
			currentIsland
		)
	end
end

local function updateHealthClassification(
	player
)
	local failures = 0

	local firstXP =
		player:GetAttribute(
			"PlaytestFirstXPHealthy"
		)

	if firstXP == false then
		failures += 1
	end

	local firstLevel =
		player:GetAttribute(
			"PlaytestFirstLevelUpHealthy"
		)

	if firstLevel == false then
		failures += 1
	end

	local island2 =
		player:GetAttribute(
			"PlaytestIsland2Healthy"
		)

	if island2 == false then
		failures += 1
	end

	local island3 =
		player:GetAttribute(
			"PlaytestIsland3Healthy"
		)

	if island3 == false then
		failures += 1
	end

	local ttk =
		player:GetAttribute(
			"PlaytestFirstKillTTKHealthy"
		)

	if ttk == false then
		failures += 1
	end

	local deaths =
		integerAttr(
			player,
			"EarlyCombatDeaths90s",
			0
		)

	local tooManyDeaths =
		deaths
			>= Config
				.EarlyDeathWarningCount

	if tooManyDeaths then
		failures += 1
	end

	player:SetAttribute(
		"PlaytestEarlyDeathWarning",
		tooManyDeaths
	)

	player:SetAttribute(
		"PlaytestHealthFailureCount",
		failures
	)

	local classification

	if failures == 0 then
		classification =
			"HealthySoFar"
	elseif failures <= 2 then
		classification =
			"NeedsReview"
	else
		classification =
			"HighFriction"
	end

	player:SetAttribute(
		"PlaytestHealthClassification",
		classification
	)
end

local function updatePlayer(
	player,
	state
)
	local elapsedSeconds =
		elapsed(player)

	if elapsedSeconds == nil then
		player:SetAttribute(
			"PlaytestTelemetryWaitingForBaseline",
			true
		)

		return
	end

	player:SetAttribute(
		"PlaytestTelemetryWaitingForBaseline",
		false
	)

	player:SetAttribute(
		"PlaytestElapsedSeconds",
		elapsedSeconds
	)

	refreshMilestoneFlags(player)

	updateProgressClock(
		player,
		state
	)

	updateHealthClassification(
		player
	)

	if elapsedSeconds
		>= Config.FiveMinuteSeconds
		and player:GetAttribute(
			"Playtest5mCaptured"
		) ~= true
	then
		snapshot(
			player,
			"Playtest5m"
		)
	end

	if elapsedSeconds
		>= Config.TenMinuteSeconds
		and player:GetAttribute(
			"Playtest10mCaptured"
		) ~= true
	then
		snapshot(
			player,
			"Playtest10m"
		)
	end

	player:SetAttribute(
		"PlaytestDiagnosticSummary",
		diagnosticSummary(
			player,
			state
		)
	)
end

local function bindPlayer(player)
	if states[player] then
		return
	end

	local timestamp = now()

	local state = {
		LastProgressAt = timestamp,
		LastIsland =
			integerAttr(
				player,
				"CurrentGlobalIslandIndex",
				0
			),

		LastXP =
			numberAttr(
				player,
				"PlayerXP",
				0
			),

		LastLevel =
			integerAttr(
				player,
				"PlayerLevel",
				1
			),

		LastKillSerial =
			integerAttr(
				player,
				"MobXPFeedbackSerial",
				0
			),

		StallSeconds = 0,
	}

	states[player] = state

	player:SetAttribute(
		"PlaytestTelemetryReady",
		true
	)

	player:SetAttribute(
		"PlaytestTelemetryVersion",
		Config.Version
	)

	player:SetAttribute(
		"PlaytestTelemetryPolicy",
		Config.Policy
	)

	player:SetAttribute(
		"PlaytestHealthFailureCount",
		0
	)

	player:SetAttribute(
		"PlaytestHealthClassification",
		"WaitingForData"
	)

	task.spawn(function()
		while started
			and player.Parent == Players
			and states[player] == state
		do
			local ok,
				result =
					pcall(
						updatePlayer,
						player,
						state
					)

			if not ok then
				player:SetAttribute(
					"PlaytestTelemetryLastError",
					tostring(result)
				)

				player:SetAttribute(
					"PlaytestTelemetryLastErrorAt",
					now()
				)
			else
				player:SetAttribute(
					"PlaytestTelemetryLastError",
					nil
				)
			end

			task.wait(
				Config.UpdateIntervalSeconds
			)
		end
	end)
end

local function unbindPlayer(player)
	states[player] = nil
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonPlaytestTelemetryReady",
		true
	)

	workspace:SetAttribute(
		"DungeonPlaytestTelemetryVersion",
		Config.Version
	)

	workspace:SetAttribute(
		"DungeonPlaytestTelemetryPolicy",
		Config.Policy
	)

	workspace:SetAttribute(
		"DungeonPlaytestFirstXPHealthySeconds",
		Config.FirstXPHealthySeconds
	)

	workspace:SetAttribute(
		"DungeonPlaytestFirstLevelUpHealthySeconds",
		Config.FirstLevelUpHealthySeconds
	)

	workspace:SetAttribute(
		"DungeonPlaytestIsland2HealthySeconds",
		Config.Island2HealthySeconds
	)

	workspace:SetAttribute(
		"DungeonPlaytestIsland3HealthySeconds",
		Config.Island3HealthySeconds
	)

	workspace:SetAttribute(
		"DungeonPlaytestFirstKillTTKHealthySeconds",
		Config.FirstKillTTKHealthySeconds
	)

	workspace:SetAttribute(
		"DungeonPlaytestStallWarningSeconds",
		Config.StallWarningSeconds
	)

	workspace:SetAttribute(
		"DungeonPlaytestSevereStallSeconds",
		Config.SevereStallSeconds
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
