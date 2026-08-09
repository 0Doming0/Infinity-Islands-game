--[[
	Infinity Islands - Task 13
	MVPIntegrationValidator V1

	Runtime smoke validator for the migrated Combat MVP.

	It DOES NOT:
	- create HUD;
	- change balance;
	- spawn mobs;
	- grant XP;
	- move players;
	- alter route progression.

	It only inspects the live state and publishes diagnostics.

	Main checks:
	- LinearCombatRouteV1 is active;
	- new IslandLevel / IslandCombat / PlayerLevel services are running;
	- legacy Reward/Boss/Optional systems are disabled;
	- no route node is Reward/Optional/Boss;
	- IslandLevel == RecommendedLevel;
	- managed mobs use IslandLevel, XP, Threat roster, SkyDrop and no Coins;
	- PlayerLevel attributes exist and own damage scaling;
	- Combat gates do not contain code-created UI;
	- no stale ObjectiveGate gameplay remains;
	- MaxAlive never exceeds MVP limit.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(
	ReplicatedStorage.Shared.Configs.MVPIntegrationValidatorConfig
)

local Validator = {}

local ISLAND_TAG = "SkyDungeonIslandNode"
local COMBAT_TARGET_TAG = "CombatTarget"
local COMBAT_GATE_TAG = "DungeonCombatGate"
local LEGACY_GATE_TAG = "DungeonObjectiveGate"

local started = false
local generation = 0
local validationSerial = 0

local function cleanText(value)
	local text = tostring(value or "")

	if #text > Config.MaximumIssueTextLength then
		text =
			string.sub(
				text,
				1,
				Config.MaximumIssueTextLength
			)
				.. "..."
	end

	return text
end

local function addIssue(
	list,
	code,
	message,
	instance
)
	table.insert(
		list,
		{
			Code = code,
			Message = cleanText(message),
			Path =
				instance
					and instance.Parent
					and instance:GetFullName()
					or nil,
		}
	)
end

local function attr(instance, name)
	return instance
		and instance:GetAttribute(name)
end

local function numberAttr(instance, name)
	local value = attr(instance, name)

	return typeof(value) == "number"
		and value
		or tonumber(value)
end

local function boolIs(instance, name, expected)
	return attr(instance, name) == expected
end

local function validateWorkspace(
	errors,
	warnings
)
	for _, name in ipairs(
		Config.RequiredWorkspaceAttributes
	) do
		if workspace:GetAttribute(name) == nil then
			addIssue(
				errors,
				"MissingWorkspaceAttribute",
				name .. " ausente"
			)
		end
	end

	if workspace:GetAttribute(
		"DungeonRouteArchitecture"
	) ~= Config.ExpectedRouteArchitecture
	then
		addIssue(
			errors,
			"WrongRouteArchitecture",
			"Esperado "
				.. Config.ExpectedRouteArchitecture
				.. ", recebido "
				.. tostring(
					workspace:GetAttribute(
						"DungeonRouteArchitecture"
					)
				)
		)
	end

	if workspace:GetAttribute(
		"DungeonRouteProgressionAuthority"
	) ~= Config.ExpectedProgressionAuthority
	then
		addIssue(
			errors,
			"WrongProgressionAuthority",
			"Autoridade esperada: "
				.. Config.ExpectedProgressionAuthority
		)
	end

	for _, item in ipairs({
		{
			Attribute =
				"DungeonIslandProgressionReady",
			Name = "IslandProgression",
		},
		{
			Attribute =
				"DungeonIslandCombatReady",
			Name = "IslandCombat",
		},
		{
			Attribute =
				"DungeonPlayerLevelReady",
			Name = "PlayerLevel",
		},
		{
			Attribute =
				"DungeonCombatRouteCompletionReady",
			Name = "CombatRouteCompletion",
		},
	}) do
		if workspace:GetAttribute(
			item.Attribute
		) ~= true
		then
			addIssue(
				warnings,
				"ServiceNotReady",
				item.Name
					.. " ainda nao publicou Ready=true"
			)
		end
	end

	if workspace:GetAttribute(
		"DungeonBossProgressionEnabled"
	) == true
	then
		addIssue(
			errors,
			"BossStillEnabled",
			"Boss progression precisa estar desativada"
		)
	end

	if workspace:GetAttribute(
		"DungeonRouteUsesRewardIslands"
	) == true
	then
		addIssue(
			errors,
			"RewardRouteStillEnabled",
			"Reward Islands ainda aparecem como ativas"
		)
	end

	if workspace:GetAttribute(
		"DungeonRouteUsesOptionalIslands"
	) == true
	then
		addIssue(
			errors,
			"OptionalRouteStillEnabled",
			"Optional Islands ainda aparecem como ativas"
		)
	end

	if workspace:GetAttribute(
		"DungeonRecommendedLevelIsHardGate"
	) == true
	then
		addIssue(
			errors,
			"RecommendedLevelHardGate",
			"RecommendedLevel nao pode bloquear entrada"
		)
	end

	for _, legacy in ipairs({
		"DungeonLegacyObjectiveSystemDisabled",
		"DungeonLegacyRewardProgressionDisabled",
		"DungeonLegacyBossProgressionDisabled",
	}) do
		if workspace:GetAttribute(legacy) ~= true then
			addIssue(
				warnings,
				"LegacyDisableFlagMissing",
				legacy .. " deveria ser true"
			)
		end
	end
end

local function validateIsland(
	island,
	errors,
	warnings,
	indexSeen
)
	if not island:IsA("Model") then
		return
	end

	local globalIndex =
		math.floor(
			numberAttr(
				island,
				"GlobalIslandIndex"
			) or 0
		)

	if globalIndex <= 0 then
		-- Compatibility/sanctuary models should no longer be part of route.
		if attr(
			island,
			"IsBossSanctuary"
		) == true
		then
			addIssue(
				errors,
				"BossIslandFound",
				"BossSanctuary ainda existe",
				island
			)
		end

		return
	end

	if indexSeen[globalIndex]
		and indexSeen[globalIndex] ~= island
	then
		addIssue(
			errors,
			"DuplicateGlobalIslandIndex",
			"GlobalIslandIndex duplicado: "
				.. tostring(globalIndex),
			island
		)
	else
		indexSeen[globalIndex] = island
	end

	if attr(
		island,
		"IsOptionalRoute"
	) == true
	then
		addIssue(
			errors,
			"OptionalCombatIsland",
			"Combat route nao pode conter Optional Island",
			island
		)
	end

	if attr(
		island,
		"IsRewardIsland"
	) == true
	then
		addIssue(
			errors,
			"RewardCombatIsland",
			"Combat route nao pode conter Reward Island",
			island
		)
	end

	if attr(
		island,
		"IsBossSanctuary"
	) == true
	then
		addIssue(
			errors,
			"BossCombatIsland",
			"Combat route nao pode conter Boss Sanctuary",
			island
		)
	end

	local islandLevel =
		math.floor(
			numberAttr(
				island,
				"IslandLevel"
			) or 0
		)

	local recommended =
		math.floor(
			numberAttr(
				island,
				"RecommendedLevel"
			) or 0
		)

	if islandLevel <= 0 then
		addIssue(
			errors,
			"MissingIslandLevel",
			"IslandLevel ausente/invalido",
			island
		)
	elseif recommended ~= islandLevel then
		addIssue(
			errors,
			"RecommendedLevelMismatch",
			string.format(
				"IslandLevel=%d RecommendedLevel=%d",
				islandLevel,
				recommended
			),
			island
		)
	end

	local maxAlive =
		math.floor(
			numberAttr(
				island,
				"MobMaxAlive"
			) or 0
		)

	if maxAlive > Config.MaximumAlivePerIsland then
		addIssue(
			errors,
			"MaxAliveExceeded",
			"MobMaxAlive="
				.. tostring(maxAlive)
				.. " > "
				.. tostring(
					Config.MaximumAlivePerIsland
				),
			island
		)
	end

	local targetCount =
		math.floor(
			numberAttr(
				island,
				"MobTargetCount"
			) or 0
		)

	local spawnedCount =
		math.floor(
			numberAttr(
				island,
				"MobSpawnedCount"
			) or 0
		)

	local aliveCount =
		math.floor(
			numberAttr(
				island,
				"MobAliveCount"
			) or 0
		)

	if targetCount > 0 then
		if spawnedCount > targetCount then
			addIssue(
				errors,
				"SpawnedAboveTarget",
				string.format(
					"Spawned=%d Target=%d",
					spawnedCount,
					targetCount
				),
				island
			)
		end

		if maxAlive > 0
			and aliveCount > maxAlive
		then
			addIssue(
				errors,
				"AliveAboveMax",
				string.format(
					"Alive=%d MaxAlive=%d",
					aliveCount,
					maxAlive
				),
				island
			)
		end
	end

	local combatState =
		tostring(
			attr(
				island,
				"CombatState"
			) or ""
		)

	local cleared =
		attr(
			island,
			"Cleared"
		) == true

	if combatState == "Cleared"
		and not cleared
	then
		addIssue(
			errors,
			"ClearStateMismatch",
			"CombatState=Cleared mas Cleared ~= true",
			island
		)
	end

	if cleared
		and combatState ~= "Cleared"
	then
		addIssue(
			warnings,
			"ClearAttributeMismatch",
			"Cleared=true mas CombatState="
				.. combatState,
			island
		)
	end
end

local function validateIslands(
	errors,
	warnings
)
	local indexSeen = {}
	local count = 0
	local workspaceCount = 0
	local pooledCount = 0

	for _, island in ipairs(
		CollectionService:GetTagged(
			ISLAND_TAG
		)
	) do
		if island:IsA("Model")
			and island.Parent
		then
			count += 1

			if island:IsDescendantOf(
				workspace
			) then
				workspaceCount += 1
			else
				pooledCount += 1
			end

			validateIsland(
				island,
				errors,
				warnings,
				indexSeen
			)
		end
	end

	if count == 0 then
		addIssue(
			warnings,
			"NoRouteIslandsYet",
			"Nenhuma SkyDungeonIslandNode materializada"
		)
	end

	workspace:SetAttribute(
		"DungeonMVPValidatorTaggedIslandCount",
		count
	)
	workspace:SetAttribute(
		"DungeonMVPValidatorWorkspaceIslandCount",
		workspaceCount
	)
	workspace:SetAttribute(
		"DungeonMVPValidatorPooledIslandCount",
		pooledCount
	)
end

local function validateManagedMob(
	mob,
	errors,
	warnings
)
	if not mob:IsA("Model")
		or not mob.Parent
		or attr(
			mob,
			"IslandCombatManaged"
		) ~= true
	then
		return
	end

	local mobLevel =
		math.floor(
			numberAttr(
				mob,
				"MobLevel"
			) or 0
		)

	local islandLevel =
		math.floor(
			numberAttr(
				mob,
				"IslandLevel"
			) or 0
		)

	if mobLevel <= 0 then
		addIssue(
			errors,
			"ManagedMobMissingLevel",
			"MobLevel ausente",
			mob
		)
	elseif islandLevel ~= mobLevel then
		addIssue(
			errors,
			"MobIslandLevelMismatch",
			string.format(
				"MobLevel=%d IslandLevel=%d",
				mobLevel,
				islandLevel
			),
			mob
		)
	end

	if attr(
		mob,
		"PlayerLevelAffectsMobStats"
	) ~= false
	then
		addIssue(
			errors,
			"PlayerLevelAffectsMob",
			"Mob precisa publicar PlayerLevelAffectsMobStats=false",
			mob
		)
	end

	if (numberAttr(
		mob,
		"CoinValue"
	) or 0) ~= 0
	then
		addIssue(
			errors,
			"ManagedMobCoinReward",
			"CoinValue precisa ser 0 no MVP",
			mob
		)
	end

	if (numberAttr(
		mob,
		"XPReward"
	) or 0) <= 0
	then
		addIssue(
			errors,
			"ManagedMobMissingXP",
			"XPReward precisa ser > 0",
			mob
		)
	end

	if attr(
		mob,
		"SkyDropSpawn"
	) ~= true
	then
		addIssue(
			warnings,
			"ManagedMobNotSkyDrop",
			"Mob managed nao publicou SkyDropSpawn=true",
			mob
		)
	end

	if attr(
		mob,
		"MobRosterVersion"
	) == nil
	then
		addIssue(
			warnings,
			"ManagedMobMissingRoster",
			"MobRosterVersion ausente",
			mob
		)
	end

	if numberAttr(
		mob,
		"GlobalIslandIndex"
	) == nil
	then
		addIssue(
			errors,
			"ManagedMobMissingIslandIndex",
			"GlobalIslandIndex ausente",
			mob
		)
	end
end

local function validateMobs(
	errors,
	warnings
)
	local managedCount = 0

	for _, mob in ipairs(
		CollectionService:GetTagged(
			COMBAT_TARGET_TAG
		)
	) do
		if attr(
			mob,
			"IslandCombatManaged"
		) == true
		then
			managedCount += 1
		end

		validateManagedMob(
			mob,
			errors,
			warnings
		)
	end

	workspace:SetAttribute(
		"DungeonMVPValidatorManagedMobCount",
		managedCount
	)
end

local function containsGui(instance)
	for _, descendant in ipairs(
		instance:GetDescendants()
	) do
		if descendant:IsA("GuiObject")
			or descendant:IsA("LayerCollector")
		then
			return true,
				descendant
		end
	end

	return false
end

local function validateGates(
	errors,
	warnings
)
	local combatGateCount = 0

	for _, gate in ipairs(
		CollectionService:GetTagged(
			COMBAT_GATE_TAG
		)
	) do
		if gate.Parent then
			combatGateCount += 1

			local hasGui,
				gui =
					containsGui(gate)

			if hasGui then
				addIssue(
					errors,
					"CombatGateContainsUI",
					"CombatGate nao pode conter UI criada por codigo",
					gui
				)
			end
		end
	end

	local staleLegacy = 0

	for _, gate in ipairs(
		CollectionService:GetTagged(
			LEGACY_GATE_TAG
		)
	) do
		if gate.Parent then
			staleLegacy += 1
		end
	end

	if staleLegacy > 0 then
		addIssue(
			warnings,
			"LegacyObjectiveGateStillPresent",
			tostring(staleLegacy)
				.. " DungeonObjectiveGate ainda presentes"
		)
	end

	workspace:SetAttribute(
		"DungeonMVPValidatorCombatGateCount",
		combatGateCount
	)
	workspace:SetAttribute(
		"DungeonMVPValidatorLegacyGateCount",
		staleLegacy
	)
end

local function validatePlayer(
	player,
	errors,
	warnings
)
	local level =
		math.floor(
			numberAttr(
				player,
				"PlayerLevel"
			) or 0
		)

	if level <= 0 then
		addIssue(
			errors,
			"PlayerMissingLevel",
			"PlayerLevel ausente",
			player
		)
	end

	local xp =
		numberAttr(
			player,
			"PlayerXP"
		)

	local xpToNext =
		numberAttr(
			player,
			"PlayerXPToNextLevel"
		)

	if xp == nil
		or xpToNext == nil
	then
		addIssue(
			errors,
			"PlayerMissingXPContract",
			"PlayerXP/PlayerXPToNextLevel ausente",
			player
		)
	end

	if attr(
		player,
		"PlayerLevelVersion"
	) ~= "PlayerLevelV1"
	then
		addIssue(
			warnings,
			"PlayerLevelVersionMismatch",
			"PlayerLevelVersion="
				.. tostring(
					attr(
						player,
						"PlayerLevelVersion"
					)
				),
			player
		)
	end

	if attr(
		player,
		"RunDamageDealtMultiplierSource"
	) ~= "PlayerLevelV1"
	then
		addIssue(
			warnings,
			"PlayerDamageAuthorityNotApplied",
			"RunDamageDealtMultiplierSource ainda nao e PlayerLevelV1",
			player
		)
	end

	local currentIsland =
		math.floor(
			numberAttr(
				player,
				"CurrentGlobalIslandIndex"
			) or 0
		)

	local checkpoint =
		math.floor(
			numberAttr(
				player,
				"DungeonCheckpointIslandIndex"
			) or 0
		)

	if currentIsland > 0
		and checkpoint > currentIsland
	then
		-- This can be valid while backtracking.
	elseif currentIsland > 0
		and checkpoint > 0
		and checkpoint < currentIsland - 1
	then
		addIssue(
			warnings,
			"CheckpointTooFarBehind",
			string.format(
				"Current=%d Checkpoint=%d",
				currentIsland,
				checkpoint
			),
			player
		)
	end
end

local function validatePlayers(
	errors,
	warnings
)
	for _, player in ipairs(
		Players:GetPlayers()
	) do
		validatePlayer(
			player,
			errors,
			warnings
		)
	end
end

local function issueText(issue)
	local text =
		issue.Code
			.. ": "
			.. issue.Message

	if issue.Path then
		text =
			text
				.. " @ "
				.. issue.Path
	end

	return cleanText(text)
end

local function publishIssues(
	errors,
	warnings
)
	validationSerial += 1

	workspace:SetAttribute(
		"DungeonMVPIntegrationReady",
		#errors == 0
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationVersion",
		Config.Version
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationValidationSerial",
		validationSerial
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationLastValidatedAt",
		workspace:GetServerTimeNow()
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationErrorCount",
		#errors
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationWarningCount",
		#warnings
	)

	local published = {}

	for _, issue in ipairs(errors) do
		if #published
			>= Config.MaximumPublishedIssues
		then
			break
		end

		table.insert(
			published,
			"ERROR "
				.. issueText(issue)
		)
	end

	for _, issue in ipairs(warnings) do
		if #published
			>= Config.MaximumPublishedIssues
		then
			break
		end

		table.insert(
			published,
			"WARN "
				.. issueText(issue)
		)
	end

	workspace:SetAttribute(
		"DungeonMVPIntegrationIssues",
		table.concat(
			published,
			" | "
		)
	)

	workspace:SetAttribute(
		"DungeonMVPIntegrationSummary",
		string.format(
			"%d error(s), %d warning(s)",
			#errors,
			#warnings
		)
	)

	if #errors > 0 then
		warn(
			"[MVPIntegrationValidator] "
				.. tostring(#errors)
				.. " erro(s): "
				.. table.concat(
					published,
					" | "
				)
		)
	elseif RunService:IsStudio()
		and #warnings > 0
	then
		warn(
			"[MVPIntegrationValidator] "
				.. tostring(#warnings)
				.. " warning(s): "
				.. table.concat(
					published,
					" | "
				)
		)
	end
end

function Validator.Validate()
	local errors = {}
	local warnings = {}

	validateWorkspace(
		errors,
		warnings
	)

	validateIslands(
		errors,
		warnings
	)

	validateMobs(
		errors,
		warnings
	)

	validateGates(
		errors,
		warnings
	)

	validatePlayers(
		errors,
		warnings
	)

	publishIssues(
		errors,
		warnings
	)

	return {
		Ready = #errors == 0,
		Version = Config.Version,
		Errors = errors,
		Warnings = warnings,
		ValidationSerial =
			validationSerial,
	}
end

function Validator.Start()
	if started then
		return false,
			"AlreadyStarted"
	end

	started = true
	generation += 1

	local token = generation

	workspace:SetAttribute(
		"DungeonMVPIntegrationValidatorRunning",
		true
	)
	workspace:SetAttribute(
		"DungeonMVPIntegrationVersion",
		Config.Version
	)

	task.spawn(function()
		task.wait(
			Config.InitialDelaySeconds
		)

		while started
			and generation == token
		do
			local ok,
				result =
					pcall(
						Validator.Validate
					)

			if not ok then
				workspace:SetAttribute(
					"DungeonMVPIntegrationReady",
					false
				)
				workspace:SetAttribute(
					"DungeonMVPIntegrationValidatorError",
					tostring(result)
				)

				warn(
					"[MVPIntegrationValidator] falha interna: "
						.. tostring(result)
				)
			else
				workspace:SetAttribute(
					"DungeonMVPIntegrationValidatorError",
					nil
				)
			end

			task.wait(
				RunService:IsStudio()
					and Config.StudioIntervalSeconds
					or Config.LiveIntervalSeconds
			)
		end
	end)

	return true
end

function Validator.Stop()
	if not started then
		return false
	end

	started = false
	generation += 1

	workspace:SetAttribute(
		"DungeonMVPIntegrationValidatorRunning",
		false
	)

	return true
end

return Validator
