--[[
	Infinity Islands - Task 17
	EarlyGamePacingTelemetryService V1

	Measures the first 90 seconds without affecting gameplay.

	Baseline:
	DungeonInstantControlReadyAt from Task 16.

	Milestones:
	- first XP;
	- first level-up;
	- Island 2 entry;
	- Island 3 entry;
	- 90 second snapshot.

	The values stay on Player Attributes so Studio and real-session analytics
	can inspect them without adding HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.EarlyGamePacingConfig
)

local Service = {}

local started = false
local playerConnections =
	setmetatable({}, { __mode = "k" })

local snapshotTokens =
	setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function baseline(player)
	return tonumber(
		player:GetAttribute(
			"DungeonInstantControlReadyAt"
		)
	)
end

local function elapsed(player, timestamp)
	local startAt = baseline(player)

	if not startAt then
		return nil
	end

	return math.max(
		0,
		(tonumber(timestamp) or now())
			- startAt
	)
end

local function record(
	player,
	attribute,
	onTargetAttribute,
	seconds,
	targetSeconds
)
	if player:GetAttribute(attribute) ~= nil
		or seconds == nil
	then
		return false
	end

	player:SetAttribute(
		attribute,
		seconds
	)

	player:SetAttribute(
		onTargetAttribute,
		seconds <= targetSeconds
	)

	return true
end

local function evaluate(player)
	if not player
		or player.Parent ~= Players
	then
		return
	end

	local startAt = baseline(player)

	if not startAt then
		return
	end

	player:SetAttribute(
		"EarlyGamePacingVersion",
		Config.Version
	)
	player:SetAttribute(
		"EarlyGamePacingBaselineAt",
		startAt
	)

	local totalXP =
		math.max(
			0,
			tonumber(
				player:GetAttribute(
					"PlayerTotalXP"
				)
			) or 0
		)

	if totalXP > 0 then
		local firstXPAt =
			tonumber(
				player:GetAttribute(
					"LastXPGainAt"
				)
			)
				or now()

		record(
			player,
			"EarlyPacingFirstXPSeconds",
			"EarlyPacingFirstXPOnTarget",
			elapsed(
				player,
				firstXPAt
			),
			Config.TelemetryTargets
				.FirstXPSeconds
		)
	end

	local level =
		math.max(
			1,
			math.floor(
				tonumber(
					player:GetAttribute(
						"PlayerLevel"
					)
				) or 1
			)
		)

	if level >= 2 then
		local levelUpAt =
			tonumber(
				player:GetAttribute(
					"LastLevelUpAt"
				)
			)
				or now()

		record(
			player,
			"EarlyPacingFirstLevelUpSeconds",
			"EarlyPacingFirstLevelUpOnTarget",
			elapsed(
				player,
				levelUpAt
			),
			Config.TelemetryTargets
				.FirstLevelUpSeconds
		)
	end

	local island =
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"CurrentGlobalIslandIndex"
					)
				) or 0
			)
		)

	if island >= 2 then
		local entryAt =
			tonumber(
				player:GetAttribute(
					"DungeonCombatRouteEntryAt"
				)
			)
				or now()

		record(
			player,
			"EarlyPacingIsland2Seconds",
			"EarlyPacingIsland2OnTarget",
			elapsed(
				player,
				entryAt
			),
			Config.TelemetryTargets
				.Island2EntrySeconds
		)
	end

	if island >= 3 then
		local entryAt =
			tonumber(
				player:GetAttribute(
					"DungeonCombatRouteEntryAt"
				)
			)
				or now()

		record(
			player,
			"EarlyPacingIsland3Seconds",
			"EarlyPacingIsland3OnTarget",
			elapsed(
				player,
				entryAt
			),
			Config.TelemetryTargets
				.Island3EntrySeconds
		)
	end
end

local function schedule90SecondSnapshot(player)
	snapshotTokens[player] =
		(snapshotTokens[player] or 0) + 1

	local token =
		snapshotTokens[player]

	local startAt = baseline(player)

	if not startAt then
		return
	end

	local remaining =
		math.max(
			0,
			startAt
				+ Config.CalibrationWindowSeconds
				- now()
		)

	task.delay(
		remaining,
		function()
			if not started
				or player.Parent ~= Players
				or snapshotTokens[player]
					~= token
				or player:GetAttribute(
					"EarlyPacing90SecondSnapshotTaken"
				) == true
			then
				return
			end

			evaluate(player)

			player:SetAttribute(
				"EarlyPacing90SecondSnapshotTaken",
				true
			)
			player:SetAttribute(
				"EarlyPacing90SecondLevel",
				math.max(
					1,
					math.floor(
						tonumber(
							player:GetAttribute(
								"PlayerLevel"
							)
						) or 1
					)
				)
			)
			player:SetAttribute(
				"EarlyPacing90SecondXP",
				math.max(
					0,
					math.floor(
						tonumber(
							player:GetAttribute(
								"PlayerXP"
							)
						) or 0
					)
				)
			)
			player:SetAttribute(
				"EarlyPacing90SecondIsland",
				math.max(
					0,
					math.floor(
						tonumber(
							player:GetAttribute(
								"CurrentGlobalIslandIndex"
							)
						) or 0
					)
				)
			)
			player:SetAttribute(
				"EarlyPacing90SecondTotalXP",
				math.max(
					0,
					math.floor(
						tonumber(
							player:GetAttribute(
								"PlayerTotalXP"
							)
						) or 0
					)
				)
			)
		end
	)
end

local function bindPlayer(player)
	if playerConnections[player] then
		return
	end

	local connections = {}

	local function bind(name)
		table.insert(
			connections,
			player:GetAttributeChangedSignal(
				name
			):Connect(function()
				evaluate(player)

				if name
					== "DungeonInstantControlReadyAt"
				then
					schedule90SecondSnapshot(
						player
					)
				end
			end)
		)
	end

	for _, name in ipairs({
		"DungeonInstantControlReadyAt",
		"PlayerTotalXP",
		"PlayerLevel",
		"CurrentGlobalIslandIndex",
		"DungeonCombatRouteEntryAt",
	}) do
		bind(name)
	end

	playerConnections[player] =
		connections

	task.defer(function()
		evaluate(player)

		if baseline(player) then
			schedule90SecondSnapshot(
				player
			)
		end
	end)
end

local function unbindPlayer(player)
	local connections =
		playerConnections[player]

	if connections then
		for _, connection in ipairs(
			connections
		) do
			connection:Disconnect()
		end

		playerConnections[player] = nil
	end

	snapshotTokens[player] =
		(snapshotTokens[player] or 0) + 1
end

function Service.Start()
	if started then
		return false, "AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonEarlyGamePacingTelemetryReady",
		true
	)
	workspace:SetAttribute(
		"DungeonEarlyGamePacingTelemetryVersion",
		Config.Version
	)
	workspace:SetAttribute(
		"DungeonEarlyPacingTargetFirstXPSeconds",
		Config.TelemetryTargets
			.FirstXPSeconds
	)
	workspace:SetAttribute(
		"DungeonEarlyPacingTargetFirstLevelUpSeconds",
		Config.TelemetryTargets
			.FirstLevelUpSeconds
	)
	workspace:SetAttribute(
		"DungeonEarlyPacingTargetIsland2Seconds",
		Config.TelemetryTargets
			.Island2EntrySeconds
	)
	workspace:SetAttribute(
		"DungeonEarlyPacingTargetIsland3Seconds",
		Config.TelemetryTargets
			.Island3EntrySeconds
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
