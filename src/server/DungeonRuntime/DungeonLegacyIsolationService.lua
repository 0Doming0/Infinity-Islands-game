local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local DungeonLegacyIsolationService = {}

local BLOCKED_SERVER_SCRIPTS = table.freeze({
	WaterRiseSystem_SkyDungeon_V10 = true,
	DeathReviveBootstrap = true,
	PlayerSpawnSystem = true,
	SafeZoneProtection_V2 = true,
	WorldEventService = true,
	PersonalSkyMerchantWorld = true,
	GlobalLeaderboardService = true,
	TutorialService = true,
	StartScreenPreviewAssets = true,
	VillagerAI = true,
	VillagerSystem = true,
	PartyBootstrap = true,
	RewardBootstrap = true,
	MonetizationBootstrap = true,
	ItemPickupController = true,
	MonsterAIService = true,
	GenerationCloudService = true,
	MVPHouses = true,
	PersonalSkyMerchantTargetService = true,
})

local BLOCKED_CLIENT_SCRIPTS = table.freeze({
	SurvivalUI = true,
	DownedUI = true,
	DeathScreen = true,
	DungeonBossHUD = true,
	SessionFloodHUD = true,
	CoinRewardUI = true,
	StaminaRewardUI = true,
	StartScreen = true,
	MobileHUDLayout = true,
	PartyUI = true,
	TradeUI = true,
	GlobalStoreUI = true,
	RewardWheelUI = true,
	VillagerUI = true,
	PersonalSkyMerchant = true,
	TutorialUI = true,
	WorldEventUI = true,
	SanctuaryStatusUI = true,
	SanctuaryRescueTransition = true,
	GenerationCloudClient = true,
	MysteryDistance = true,
	LeaderboardUI = true,
	MonetizationUI = true,
	CollectibleBlenderAnimation = true,
	MimicAnimationClient_ContinuousLoop_V7 = true,
})

local BLOCKED_SCREEN_GUIS = table.freeze({
	SurvivalUI = true,
	DownedUI = true,
	DeathScreen = true,
	DungeonBossHUD = true,
	SessionFloodHUD = true,
	CoinRewardUI = true,
	StaminaRewardUI = true,
	StartScreen = true,
	RespawnTransition = true,
	PartyUI = true,
	TradeUI = true,
	GlobalStoreUI = true,
	RewardWheelUI = true,
	VillagerUI = true,
	PersonalSkyMerchant = true,
	TutorialUI = true,
	WorldEventUI = true,
	SanctuaryStatusUI = true,
	LeaderboardUI = true,
	MonetizationUI = true,
})

local LEGACY_WORKSPACE_OBJECTS = table.freeze({
	Water = true,
	WaterTiles = true,
	SafeRespawnPlatforms = true,
	PersonalSkyMerchants = true,
	PersonalSkyMerchantTargets = true,
	WorldEventRuntime = true,
	MVPVillagers = true,
	MVPHouses = true,
})

local started = false
local connections = {}
local disabledServerCount = 0
local disabledClientCount = 0
local suppressedGuiCount = 0
local removedWorkspaceCount = 0

local function markDisabled(instance, reason)
	instance:SetAttribute("DisabledByDungeonRuntime", true)
	instance:SetAttribute("DungeonDisableReason", reason)
end

local function suppressServerScript(instance)
	if not instance:IsA("BaseScript") or not BLOCKED_SERVER_SCRIPTS[instance.Name] then
		return false
	end
	if instance.Disabled ~= true then
		instance.Disabled = true
		disabledServerCount += 1
	end
	markDisabled(instance, "LegacyServerSystem")
	return true
end

local function suppressClientScript(instance)
	if not instance:IsA("LocalScript") or not BLOCKED_CLIENT_SCRIPTS[instance.Name] then
		return false
	end
	if instance.Disabled ~= true then
		instance.Disabled = true
		disabledClientCount += 1
	end
	markDisabled(instance, "LegacyClientSystem")
	return true
end

local function suppressGui(instance)
	if not instance:IsA("ScreenGui") or not BLOCKED_SCREEN_GUIS[instance.Name] then
		return false
	end
	if instance.Enabled ~= false then
		instance.Enabled = false
		suppressedGuiCount += 1
	end
	instance:SetAttribute("SuppressedByDungeonRuntime", true)
	return true
end

local function removeLegacyWorkspaceObject(instance)
	if instance.Parent ~= workspace or not LEGACY_WORKSPACE_OBJECTS[instance.Name] then
		return false
	end
	removedWorkspaceCount += 1
	instance:Destroy()
	return true
end

local function bindPlayer(player)
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	if playerScripts then
		for _, descendant in ipairs(playerScripts:GetDescendants()) do
			suppressClientScript(descendant)
		end
		connections[playerScripts] = playerScripts.DescendantAdded:Connect(suppressClientScript)
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, child in ipairs(playerGui:GetChildren()) do
			suppressGui(child)
		end
		connections[playerGui] = playerGui.ChildAdded:Connect(suppressGui)
	end
end

local function publishDiagnostics()
	workspace:SetAttribute("DungeonLegacyIsolationReady", true)
	workspace:SetAttribute("DungeonLegacyServerScriptsDisabled", disabledServerCount)
	workspace:SetAttribute("DungeonLegacyClientScriptsDisabled", disabledClientCount)
	workspace:SetAttribute("DungeonLegacyGuisSuppressed", suppressedGuiCount)
	workspace:SetAttribute("DungeonLegacyWorkspaceObjectsRemoved", removedWorkspaceCount)
	workspace:SetAttribute("DungeonLegacyWaterRiseDisabled", true)
	workspace:SetAttribute("DungeonLegacyDynamicExpansionDisabled", true)
	workspace:SetAttribute("DungeonLegacyDeathFlowDisabled", true)
	workspace:SetAttribute("DungeonLegacyMerchantsDisabled", true)
	workspace:SetAttribute("DungeonLegacyWorldEventsDisabled", true)
	workspace:SetAttribute("DungeonLegacyTutorialDisabled", true)
end

function DungeonLegacyIsolationService.Start()
	if started then
		return DungeonLegacyIsolationService.GetSnapshot()
	end
	started = true

	-- Publicados antes de qualquer varredura. Os scripts que possuem o guard
	-- estatico podem encerrar antes mesmo de serem desativados por esta camada.
	workspace:SetAttribute("GamePlaceType", "Dungeon")
	workspace:SetAttribute("DungeonRuntimeManaged", true)
	workspace:SetAttribute("DungeonLegacyIsolationStarting", true)

	for _, descendant in ipairs(ServerScriptService:GetDescendants()) do
		suppressServerScript(descendant)
	end
	connections.ServerDescendantAdded = ServerScriptService.DescendantAdded:Connect(suppressServerScript)

	local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starterScripts then
		for _, descendant in ipairs(starterScripts:GetDescendants()) do
			suppressClientScript(descendant)
		end
		connections.StarterDescendantAdded = starterScripts.DescendantAdded:Connect(suppressClientScript)
	end

	for _, child in ipairs(workspace:GetChildren()) do
		removeLegacyWorkspaceObject(child)
	end
	connections.WorkspaceChildAdded = workspace.ChildAdded:Connect(function(child)
		task.defer(removeLegacyWorkspaceObject, child)
	end)

	connections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
		task.defer(bindPlayer, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(bindPlayer, player)
	end

	workspace:SetAttribute("DungeonLegacyIsolationStarting", false)
	publishDiagnostics()
	return DungeonLegacyIsolationService.GetSnapshot()
end

function DungeonLegacyIsolationService.IsServerScriptBlocked(name)
	return BLOCKED_SERVER_SCRIPTS[tostring(name or "")] == true
end

function DungeonLegacyIsolationService.IsClientScriptBlocked(name)
	return BLOCKED_CLIENT_SCRIPTS[tostring(name or "")] == true
end

function DungeonLegacyIsolationService.GetSnapshot()
	return {
		Ready = started,
		DisabledServerScripts = disabledServerCount,
		DisabledClientScripts = disabledClientCount,
		SuppressedGuis = suppressedGuiCount,
		RemovedWorkspaceObjects = removedWorkspaceCount,
		WaterRiseDisabled = true,
		DynamicExpansionDisabled = true,
	}
end

return DungeonLegacyIsolationService
