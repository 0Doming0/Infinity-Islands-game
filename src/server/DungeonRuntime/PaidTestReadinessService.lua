--[[
	Infinity Islands - Task 12
	PaidTestReadinessService - Simplified Combat MVP

	Legacy readiness used to validate removed Objective/Reward/Boss content.
	This validator only protects what the current MVP actually needs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaidTestReadinessService = {}

local REQUIRED_CONFIGS = {
	"IslandProgressionConfig",
	"IslandMobScalingConfig",
	"IslandMobRosterConfig",
	"IslandMobSpawnConfig",
	"MobXPConfig",
	"PlayerLevelConfig",
	"CombatRouteProgressionConfig",
}

local function result(errors, warnings)
	return {
		Ready = #errors == 0,
		Errors = errors,
		Warnings = warnings,
		Version = "SimplifiedCombatMVPV1",
	}
end

function PaidTestReadinessService.ValidateStatic(_phaseId)
	local errors = {}
	local warnings = {}

	local shared =
		ReplicatedStorage:FindFirstChild(
			"Shared"
		)

	local configs =
		shared
			and shared:FindFirstChild(
				"Configs"
			)

	if not configs then
		table.insert(
			errors,
			"ReplicatedStorage.Shared.Configs ausente"
		)
	else
		for _, name in ipairs(
			REQUIRED_CONFIGS
		) do
			if not configs:FindFirstChild(
				name
			)
			then
				table.insert(
					errors,
					"Config ausente: "
						.. name
				)
			end
		end
	end

	return result(
		errors,
		warnings
	)
end

function PaidTestReadinessService.ValidateLiveWorld(
	_phaseId,
	initialContext
)
	local errors = {}
	local warnings = {}

	if type(initialContext) ~= "table" then
		table.insert(
			errors,
			"Initial route context ausente"
		)
	else
		if not initialContext.IslandModel
			or not initialContext.IslandModel.Parent
		then
			table.insert(
				errors,
				"Initial Combat Island ausente"
			)
		end

		if not initialContext.SafeSpawn
			or not initialContext.SafeSpawn.Parent
		then
			table.insert(
				errors,
				"Initial SafeSpawn ausente"
			)
		end
	end

	if workspace:GetAttribute(
		"DungeonRouteArchitecture"
	) ~= "LinearCombatRouteV1"
	then
		table.insert(
			errors,
			"LinearCombatRouteV1 nao ativa"
		)
	end

	for _, check in ipairs({
		{
			Name = "IslandLevel",
			Attribute =
				"DungeonIslandProgressionReady",
		},
		{
			Name = "IslandCombat",
			Attribute =
				"DungeonIslandCombatReady",
		},
		{
			Name = "PlayerLevel",
			Attribute =
				"DungeonPlayerLevelReady",
		},
	}) do
		if workspace:GetAttribute(
			check.Attribute
		) ~= true
		then
			table.insert(
				warnings,
				check.Name
					.. " ainda inicializando"
			)
		end
	end

	return result(
		errors,
		warnings
	)
end

return PaidTestReadinessService
