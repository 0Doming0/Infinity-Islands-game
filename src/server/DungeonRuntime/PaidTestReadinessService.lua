local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local BossConfig = require(ReplicatedStorage.Shared.Configs.BossConfig)
local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local PlaceConfig = require(ReplicatedStorage.Shared.Configs.PlaceConfig)

local ContentResolver = require(script.Parent.ContentResolver)
local EncounterCatalog = require(script.Parent.EncounterCatalog)
local ObjectiveCatalog = require(script.Parent.ObjectiveCatalog)

local PaidTestReadinessService = {}

local EXPECTED_OBJECTIVES = table.freeze({
	{ Id = "FirstStrike", Target = 1, Event = "EnemyDefeated" },
	{ Id = "ClearThePath", Target = 3, Event = "EnemyDefeated" },
	{ Id = "FirstRewardBattle", Reward = true },
	{ Id = "SkyAmbush" },
	{ Id = "RangedThreat" },
	{ Id = "BreakTheNests" },
	{ Id = "SecondRewardBattle", Reward = true },
	{ Id = "BreakTheGuard" },
	{ Id = "HoldTheBeacon", Target = 25, Event = "BeaconHoldSeconds" },
	{ Id = "NestCluster" },
	{ Id = "EliteHunt" },
	{ Id = "FinalRewardBattle", Reward = true },
})

local REQUIRED_SERVER_MODULES = table.freeze({
	"ObjectiveService",
	"ObjectiveSequenceService",
	"ObjectiveEncounterService",
	"RewardIslandService",
	"RunUpgradeService",
	"BossService",
	"DungeonReturnService",
	"DungeonRunAnalyticsService",
})

local REQUIRED_CLIENT_SCRIPTS = table.freeze({
	"DungeonUnifiedHUD",
	"DungeonObjectiveHUD",
	"DungeonRewardsHUD",
	"DungeonRunUpgradeHUD",
	"DungeonBossCombatHUD",
	"DungeonResultHUD",
	"DungeonHealthFeedback",
	"EnemyCombatFeedback",
})

local function add(list, code, detail)
	table.insert(list, string.format("%s:%s", tostring(code), tostring(detail or "")))
end

local function hasClientScript(name)
	local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	return starterScripts and starterScripts:FindFirstChild(name) ~= nil
end

local function validateObjectiveContract(errors)
	local definitions = ObjectiveCatalog.GetAll(1)
	if #definitions ~= #EXPECTED_OBJECTIVES then
		add(errors, "ObjectiveCount", #definitions)
		return
	end

	for index, expected in ipairs(EXPECTED_OBJECTIVES) do
		local definition = definitions[index]
		if not definition or definition.Id ~= expected.Id then
			add(
				errors,
				"ObjectiveOrder",
				string.format("%d=%s", index, definition and definition.Id or "nil")
			)
			continue
		end
		if definition.GlobalIslandIndex ~= index then
			add(errors, "ObjectiveGlobalIndex", expected.Id)
		end
		if expected.Target and definition.Target ~= expected.Target then
			add(
				errors,
				"ObjectiveTarget",
				string.format("%s=%s", expected.Id, tostring(definition.Target))
			)
		end
		if expected.Event and definition.ProgressEvent ~= expected.Event then
			add(
				errors,
				"ObjectiveProgressEvent",
				string.format("%s=%s", expected.Id, tostring(definition.ProgressEvent))
			)
		end
		if expected.Reward and definition.IsRewardIsland ~= true then
			add(errors, "RewardObjectiveFlag", expected.Id)
		end
	end
end

local function validateRewardWaves(errors)
	for index, expectedCount in pairs({ [3] = 2, [7] = 2, [12] = 3 }) do
		local definition = ObjectiveCatalog.GetByGlobalIndex(index, 1)
		local ok, planOrError = pcall(EncounterCatalog.Build, definition, 1)
		if not ok then
			add(errors, "EncounterBuild", tostring(planOrError))
		elseif type(planOrError.Waves) ~= "table" or #planOrError.Waves ~= expectedCount then
			add(
				errors,
				"RewardWaveCount",
				string.format("%d=%s", index, tostring(planOrError.Waves and #planOrError.Waves))
			)
		end
	end
end

local function validateBossContract(errors, warnings, phaseId)
	local boss = BossConfig.GiantBoss
	if type(boss) ~= "table" then
		add(errors, "BossConfig", "GiantBossMissing")
		return
	end
	if math.floor(tonumber(boss.PhaseCount) or 0) ~= 2 then
		add(errors, "BossPhaseCount", tostring(boss.PhaseCount))
	end
	local threshold = type(boss.PhaseThresholds) == "table"
		and tonumber(boss.PhaseThresholds[1])
		or nil
	if not threshold or math.abs(threshold - 0.50) > 0.001 then
		add(errors, "BossPhaseThreshold", tostring(threshold))
	end

	local template = phaseId and ContentResolver.FindBoss(phaseId, "GiantBoss") or nil
	if not template then
		add(warnings, "BossTemplate", "UsingFallbackGiantBoss")
	end

	local configuredMusic = tostring(boss.MusicSoundId or "")
	local templateMusic = template and template:FindFirstChild("BossMusic", true)
	if configuredMusic == "" and not (templateMusic and templateMusic:IsA("Sound")) then
		add(warnings, "BossMusic", "MissingAsset")
	end
end

local function validatePhase(errors, warnings, requestedPhaseId)
	local phaseId = requestedPhaseId or PhaseConfig.GetDefaultId()
	if not phaseId or not PhaseConfig.IsValid(phaseId) then
		add(errors, "Phase", tostring(phaseId or "NoRegisteredPhase"))
		return nil
	end
	local phase = PhaseConfig.Get(phaseId)
	if math.floor(tonumber(phase.BaseIslandCount) or 0) < 12 then
		add(errors, "BaseIslandCount", tostring(phase.BaseIslandCount))
	end
	if phase.AllowPrototypeContent == true then
		add(warnings, "PrototypeContent", phaseId)
	end
	if not ContentResolver.FindBossArena(phaseId) then
		add(warnings, "BossArena", "UsingRuntimeFallback")
	end
	return phaseId
end

local function publish(report, scope)
	scope = tostring(scope or "Static")
	workspace:SetAttribute("DungeonPaidTestReadinessScope", scope)
	workspace:SetAttribute("DungeonPaidTestReadinessCheckedAt", workspace:GetServerTimeNow())
	workspace:SetAttribute("DungeonPaidTestReadinessChecks", report.Checks)
	workspace:SetAttribute("DungeonPaidTestErrorCount", #report.Errors)
	workspace:SetAttribute("DungeonPaidTestWarningCount", #report.Warnings)
	workspace:SetAttribute("DungeonPaidTestErrors", table.concat(report.Errors, " | "))
	workspace:SetAttribute("DungeonPaidTestWarnings", table.concat(report.Warnings, " | "))
	if scope == "LiveWorld" then
		workspace:SetAttribute("DungeonPaidTestLiveReady", report.Ready)
	else
		workspace:SetAttribute("DungeonPaidTestStaticReady", report.Ready)
	end
	workspace:SetAttribute("DungeonPaidTestReady", report.Ready)
end

function PaidTestReadinessService.ValidateStatic(requestedPhaseId)
	local errors = {}
	local warnings = {}
	local checks = 0
	local function checked()
		checks += 1
	end

	checked()
	if PlaceConfig.LobbyPlaceId <= 0 or PlaceConfig.DungeonPlaceId <= 0 then
		add(errors, "PlaceIds", "NotConfigured")
	elseif PlaceConfig.LobbyPlaceId == PlaceConfig.DungeonPlaceId then
		add(errors, "PlaceIds", "LobbyEqualsDungeon")
	end

	checked()
	if not RunService:IsStudio()
		and game.PlaceId > 0
		and game.PlaceId ~= PlaceConfig.DungeonPlaceId
	then
		add(errors, "WrongPlace", tostring(game.PlaceId))
	end

	checked()
	local phaseId = validatePhase(errors, warnings, requestedPhaseId)

	checked()
	local objectiveOk, objectiveError = pcall(ObjectiveCatalog.Validate)
	if not objectiveOk then
		add(errors, "ObjectiveCatalogValidate", objectiveError)
	else
		validateObjectiveContract(errors)
	end

	checked()
	local encounterOk, encounterError = pcall(EncounterCatalog.Validate)
	if not encounterOk then
		add(errors, "EncounterCatalogValidate", encounterError)
	else
		validateRewardWaves(errors)
	end

	checked()
	validateBossContract(errors, warnings, phaseId)

	checked()
	local deathLoss = tonumber(MVPConfig.Progression and MVPConfig.Progression.DeathCoinLossPercent) or 0
	if deathLoss > 0 then
		add(errors, "DeathCoinLossPercent", tostring(deathLoss))
	end

	checked()
	if not MVPConfig.Analytics or MVPConfig.Analytics.Enabled == false then
		add(errors, "Analytics", "Disabled")
	end

	checked()
	for _, moduleName in ipairs(REQUIRED_SERVER_MODULES) do
		if not script.Parent:FindFirstChild(moduleName) then
			add(errors, "MissingServerModule", moduleName)
		end
	end

	checked()
	for _, scriptName in ipairs(REQUIRED_CLIENT_SCRIPTS) do
		if not hasClientScript(scriptName) then
			add(errors, "MissingClientScript", scriptName)
		end
	end

	local report = {
		Ready = #errors == 0,
		Checks = checks,
		PhaseId = phaseId,
		Errors = errors,
		Warnings = warnings,
	}
	publish(report, "Static")
	return report
end

function PaidTestReadinessService.ValidateLiveWorld(phaseId, initialContext)
	local static = PaidTestReadinessService.ValidateStatic(phaseId)
	local errors = table.clone(static.Errors)
	local warnings = table.clone(static.Warnings)
	local checks = static.Checks
	local function requireAttribute(name)
		checks += 1
		if workspace:GetAttribute(name) ~= true then
			add(errors, "RuntimeAttribute", name)
		end
	end

	checks += 1
	if type(initialContext) ~= "table" then
		add(errors, "InitialIsland", "MissingContext")
	else
		for _, field in ipairs({ "IslandModel", "SafeSpawn", "ObjectiveAnchor", "Exit" }) do
			if not initialContext[field] or not initialContext[field].Parent then
				add(errors, "InitialIslandMarker", field)
			end
		end
	end

	requireAttribute("DungeonLegacyIsolationReady")
	requireAttribute("DungeonRuntimeReady")
	requireAttribute("DungeonObjectiveServiceReady")
	requireAttribute("DungeonObjectiveSequenceReady")
	requireAttribute("DungeonLifeServiceReady")
	requireAttribute("DungeonRunAnalyticsReady")

	checks += 1
	if workspace:GetAttribute("DungeonRouteReady") ~= true then
		add(warnings, "RouteReady", "NotPublishedAtLiveCheck")
	end

	local report = {
		Ready = #errors == 0,
		Checks = checks,
		PhaseId = static.PhaseId,
		Errors = errors,
		Warnings = warnings,
	}
	publish(report, "LiveWorld")
	return report
end

return table.freeze(PaidTestReadinessService)
