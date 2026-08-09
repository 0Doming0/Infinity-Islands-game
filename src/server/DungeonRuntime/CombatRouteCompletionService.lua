--[[
	Infinity Islands - Task 19
	CombatRouteCompletionService - Standalone

	Last Combat Island cleared
		-> publishes MVP victory
		-> no result modal requirement
		-> no Lobby teleport
		-> no forced movement lock
		-> players remain in the finished Dungeon server

	A restart/replay flow can be designed later after the MVP proves retention.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage.Shared.Configs.CombatRouteCompletionConfig
)

local Service = {}

local started = false
local connection
local completed = false

local function finish()
	if completed
		or workspace:GetAttribute(
			"DungeonLinearRouteComplete"
		) ~= true
	then
		return
	end

	completed = true

	local timestamp =
		workspace:GetServerTimeNow()

	workspace:SetAttribute(
		"DungeonMVPVictory",
		true
	)

	workspace:SetAttribute(
		"DungeonMVPVictoryAt",
		timestamp
	)

	workspace:SetAttribute(
		"DungeonMVPVictoryReason",
		"CombatRouteCleared"
	)

	workspace:SetAttribute(
		"DungeonPhaseState",
		"Victory"
	)

	workspace:SetAttribute(
		"DungeonStandaloneRunComplete",
		true
	)

	workspace:SetAttribute(
		"DungeonStandaloneRunCompletedAt",
		timestamp
	)

	workspace:SetAttribute(
		"DungeonCombatRouteCompletionPolicy",
		Config.Policy
	)

	workspace:SetAttribute(
		"DungeonAutoReturnToLobby",
		false
	)

	workspace:SetAttribute(
		"DungeonLobbyEnabled",
		false
	)

	workspace:SetAttribute(
		"DungeonCombatRouteReturnState",
		"Disabled"
	)

	for _, player in ipairs(
		Players:GetPlayers()
	) do
		player:SetAttribute(
			"DungeonMVPVictory",
			true
		)

		player:SetAttribute(
			"DungeonMVPVictoryAt",
			timestamp
		)

		player:SetAttribute(
			"DungeonVictoryAction",
			"StayInDungeon"
		)

		-- Explicitly preserve control.
		if player.Character then
			player.Character:SetAttribute(
				"MovementLocked",
				nil
			)

			local humanoid =
				player.Character
					:FindFirstChildOfClass(
						"Humanoid"
					)

			if humanoid
				and humanoid.Health > 0
			then
				humanoid.AutoRotate = true

				if humanoid.WalkSpeed <= 0 then
					humanoid.WalkSpeed = 16
				end
			end
		end
	end
end

function Service.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true

	workspace:SetAttribute(
		"DungeonCombatRouteCompletionReady",
		true
	)

	workspace:SetAttribute(
		"DungeonCombatRouteCompletionVersion",
		Config.Version
	)

	workspace:SetAttribute(
		"DungeonCombatRouteCompletionPolicy",
		Config.Policy
	)

	workspace:SetAttribute(
		"DungeonAutoReturnToLobby",
		false
	)

	connection =
		workspace
			:GetAttributeChangedSignal(
				"DungeonLinearRouteComplete"
			)
			:Connect(
				finish
			)

	task.defer(
		finish
	)

	return true
end

function Service.Stop()
	if not started then
		return false
	end

	started = false

	if connection then
		connection:Disconnect()
		connection = nil
	end

	workspace:SetAttribute(
		"DungeonCombatRouteCompletionReady",
		false
	)

	return true
end

return Service
