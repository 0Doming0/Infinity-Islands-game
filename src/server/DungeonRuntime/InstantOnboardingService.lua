--[[
	Infinity Islands - Task 19
	Direct Island Start guard.

	This is NOT a tutorial system.

	It only prevents old AwaitingStart states from returning after the standalone
	Dungeon runtime has accepted the Player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.InstantOnboardingConfig
)

local Service = {}

local started = false
local playerConnections =
	setmetatable({}, { __mode = "k" })

local BLOCKED_STATES = {
	AwaitingStart = true,
	WaitingForStart = true,
	ReadyScreen = true,
	StartScreen = true,
	Tutorial = true,
	AwaitingTutorial = true,
}

local function enforce(player)
	if not player
		or player.Parent ~= Players
		or player:GetAttribute(
			"DungeonSessionId"
		) == nil
	then
		return
	end

	player:SetAttribute(
		"DungeonRuntimeAutoStart",
		true
	)
	player:SetAttribute(
		"InitialGameStarted",
		true
	)
	player:SetAttribute(
		"TutorialEnemyProtection",
		false
	)
	player:SetAttribute(
		"DungeonStartConfirmationRequired",
		false
	)
	player:SetAttribute(
		"DungeonTutorialBlocking",
		false
	)
	player:SetAttribute(
		"DungeonGuideEnabled",
		false
	)
	player:SetAttribute(
		"DungeonEntryPolicy",
		Config.Policy
	)

	local current =
		tostring(
			player:GetAttribute(
				"InitialStartState"
			) or ""
		)

	if BLOCKED_STATES[current] then
		player:SetAttribute(
			"InitialStartState",
			player:GetAttribute(
				"InitialSpawnPositioned"
			) == true
				and "Playing"
				or "Positioning"
		)
	end

	if player:GetAttribute(
		"InitialSpawnPositioned"
	) == true
	then
		player:SetAttribute(
			"InitialStartState",
			"Playing"
		)

		if player:GetAttribute(
			"DungeonInstantControlReadyAt"
		) == nil
		then
			local readyAt =
				workspace:GetServerTimeNow()

			player:SetAttribute(
				"DungeonInstantControlReadyAt",
				readyAt
			)

			local joinedAt =
				tonumber(
					player:GetAttribute(
						"DungeonDirectEntryStartedAt"
					)
				)

			if joinedAt then
				player:SetAttribute(
					"DungeonTimeToControlSeconds",
					math.max(
						0,
						readyAt - joinedAt
					)
				)
			end
		end
	end
end

local function bind(player)
	if playerConnections[player] then
		return
	end

	if player:GetAttribute(
		"DungeonDirectEntryStartedAt"
	) == nil
	then
		player:SetAttribute(
			"DungeonDirectEntryStartedAt",
			workspace:GetServerTimeNow()
		)
	end

	local connections = {}

	for _, name in ipairs({
		"DungeonSessionId",
		"InitialStartState",
		"InitialGameStarted",
		"InitialSpawnPositioned",
	}) do
		table.insert(
			connections,
			player:GetAttributeChangedSignal(
				name
			):Connect(function()
				task.defer(
					enforce,
					player
				)
			end)
		)
	end

	playerConnections[player] =
		connections

	task.defer(
		enforce,
		player
	)
end

function Service.Start()
	if started then
		return false, "AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonInstantOnboardingReady",
		true
	)
	workspace:SetAttribute(
		"DungeonInstantOnboardingVersion",
		Config.Version
	)
	workspace:SetAttribute(
		"DungeonOnboardingPolicy",
		Config.Policy
	)
	workspace:SetAttribute(
		"DungeonStartConfirmationRequired",
		false
	)
	workspace:SetAttribute(
		"DungeonTutorialBlocking",
		false
	)
	workspace:SetAttribute(
		"DungeonGuideEnabled",
		false
	)

	Players.PlayerAdded:Connect(bind)

	for _, player in ipairs(
		Players:GetPlayers()
	) do
		bind(player)
	end

	return true
end

return Service
