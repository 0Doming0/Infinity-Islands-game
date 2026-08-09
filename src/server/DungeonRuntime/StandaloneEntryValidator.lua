--[[
	Infinity Islands - Task 20
	StandaloneEntryValidator V1

	Verifies the direct-entry contract without changing gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntryConfig = require(
	ReplicatedStorage.Shared.Configs.StandaloneEntryConfig
)

local Validator = {}

local function add(list, code, detail)
	table.insert(
		list,
		code .. ": " .. tostring(detail)
	)
end

function Validator.Validate()
	local errors = {}
	local warnings = {}

	if workspace:GetAttribute(
		"DungeonStandaloneMode"
	) ~= true
	then
		add(
			errors,
			"StandaloneModeDisabled",
			"DungeonStandaloneMode ~= true"
		)
	end

	if workspace:GetAttribute(
		"DungeonLobbyEnabled"
	) ~= false
	then
		add(
			errors,
			"LobbyStillEnabled",
			"DungeonLobbyEnabled precisa ser false"
		)
	end

	if workspace:GetAttribute(
		"DungeonTeleportDataRequired"
	) ~= false
	then
		add(
			errors,
			"TeleportDataStillRequired",
			"DungeonTeleportDataRequired precisa ser false"
		)
	end

	if workspace:GetAttribute(
		"DungeonGuideEnabled"
	) ~= false
	then
		add(
			errors,
			"GuideStillEnabled",
			"DungeonGuideEnabled precisa ser false"
		)
	end

	if workspace:GetAttribute(
		"DungeonAutoReturnToLobby"
	) ~= false
	then
		add(
			errors,
			"AutoLobbyReturnStillEnabled",
			"DungeonAutoReturnToLobby precisa ser false"
		)
	end

	local checkpoint =
		tonumber(
			workspace:GetAttribute(
				"DungeonCheckpointIslandIndex"
			)
		)

	if workspace:GetAttribute(
		"DungeonRuntimeReady"
	) == true
		and checkpoint == nil
	then
		add(
			errors,
			"CheckpointMissing",
			"runtime pronto sem DungeonCheckpointIslandIndex"
		)
	end

	for _, player in ipairs(
		Players:GetPlayers()
	) do
		if player:GetAttribute(
			"DungeonStandaloneSession"
		) ~= true
		then
			add(
				errors,
				"PlayerNotStandalone",
				player.Name
			)
		end

		if player:GetAttribute(
			"DungeonLobbyUsed"
		) ~= false
		then
			add(
				errors,
				"PlayerLobbyFlag",
				player.Name
			)
		end

		if player:GetAttribute(
			"DungeonGuideEnabled"
		) ~= false
		then
			add(
				errors,
				"PlayerGuideFlag",
				player.Name
			)
		end

		local island =
			tonumber(
				player:GetAttribute(
					"CurrentGlobalIslandIndex"
				)
			)

		if workspace:GetAttribute(
			"DungeonRuntimeReady"
		) == true
			and island == nil
		then
			add(
				warnings,
				"PlayerIslandNotReplicatedYet",
				player.Name
			)
		end

		local positionSerial =
			tonumber(
				player:GetAttribute(
					"DungeonStandalonePositionSerial"
				)
			) or 0

		if positionSerial > 1
			and player:GetAttribute(
				"DungeonStandalonePositionReason"
			) == "LateJoinCurrentCheckpoint"
		then
			add(
				warnings,
				"LateJoinPositionedMultipleTimes",
				player.Name
					.. " serial="
					.. tostring(
						positionSerial
					)
			)
		end
	end

	local ready = #errors == 0

	workspace:SetAttribute(
		"DungeonStandaloneEntryHealthy",
		ready
	)

	workspace:SetAttribute(
		"DungeonStandaloneEntryErrorCount",
		#errors
	)

	workspace:SetAttribute(
		"DungeonStandaloneEntryWarningCount",
		#warnings
	)

	workspace:SetAttribute(
		"DungeonStandaloneEntryIssues",
		table.concat(
			errors,
			" | "
		)
	)

	workspace:SetAttribute(
		"DungeonStandaloneEntryWarnings",
		table.concat(
			warnings,
			" | "
		)
	)

	workspace:SetAttribute(
		"DungeonStandaloneEntryValidatedAt",
		workspace:GetServerTimeNow()
	)

	return {
		Ready = ready,
		Errors = errors,
		Warnings = warnings,
	}
end

function Validator.Start()
	workspace:SetAttribute(
		"DungeonStandaloneEntryValidatorVersion",
		EntryConfig.Version
	)

	task.spawn(function()
		while true do
			task.wait(3)

			local ok,
				result =
					pcall(
						Validator.Validate
					)

			if not ok then
				workspace:SetAttribute(
					"DungeonStandaloneEntryHealthy",
					false
				)

				workspace:SetAttribute(
					"DungeonStandaloneEntryIssues",
					tostring(result)
				)
			end
		end
	end)

	return true
end

return Validator
