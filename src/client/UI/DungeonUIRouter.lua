local DungeonUIRouter = {}
local bound = false

DungeonUIRouter.Version = 1
DungeonUIRouter.Policy = "CrystalCelestialOwnershipV1"

local SUPPRESSED_LOCAL_SCRIPTS = table.freeze({
	SurvivalUI = true,
	DungeonBossHUD = true,
	CoinRewardUI = true,
	StaminaRewardUI = true,
	StartScreen = true,
	PartyUI = true,
	TradeUI = true,
	GlobalStoreUI = true,
	RewardWheelUI = true,
	LeaderboardUI = true,
	CompanionUI = true,
	InventoryUI = true,
})

local SUPPRESSED_SCREEN_GUIS = table.freeze({
	SurvivalUI = true,
	DungeonBossHUD = true,
	CoinRewardUI = true,
	StaminaRewardUI = true,
	StartScreen = true,
	PartyUI = true,
	TradeUI = true,
	GlobalStoreUI = true,
	RewardWheelUI = true,
	GlobalLeaderboardUI = true,
	CompanionUI = true,
	InventoryUI = true,
})

-- Estes sistemas devem continuar ativos na Dungeon. Eles possuem funcionalidade
-- que o HUD especial ainda nao absorveu ou nem sequer sao interfaces.
DungeonUIRouter.PreservedSystems = table.freeze({
	DeathScreen = true,
	DownedUI = true,
	MobileHUDLayout = true,
	TutorialUI = true,
	WorldEventUI = true,
	SessionFloodHUD = true,
	SanctuaryStatusUI = true,
	SanctuaryRescueTransition = true,
	GenerationCloudClient = true,
	MysteryDistance = true,
	VillagerUI = true,
	PersonalSkyMerchant = true,
	MonetizationUI = true,
	SettingsController = true,
	StatusEffectsUI = true,
	CollectibleBlenderAnimation = true,
	MimicAnimationClient_ContinuousLoop_V7 = true,
})

function DungeonUIRouter.ShouldSuppressScript(instance)
	return instance
		and instance:IsA("LocalScript")
		and SUPPRESSED_LOCAL_SCRIPTS[instance.Name] == true
end

function DungeonUIRouter.ShouldSuppressGui(instance)
	return instance
		and instance:IsA("ScreenGui")
		and SUPPRESSED_SCREEN_GUIS[instance.Name] == true
end

function DungeonUIRouter.ApplyScriptPolicy(instance)
	if not DungeonUIRouter.ShouldSuppressScript(instance) then
		return false
	end
	instance.Disabled = true
	instance:SetAttribute("DisabledByDungeonUIRouter", true)
	return true
end

function DungeonUIRouter.ApplyGuiPolicy(instance)
	if not DungeonUIRouter.ShouldSuppressGui(instance) then
		return false
	end
	instance.Enabled = false
	if instance:GetAttribute("SuppressedByDungeonUIRouter") ~= true then
		instance:SetAttribute("SuppressedByDungeonUIRouter", true)
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if instance.Parent and instance.Enabled then
				instance.Enabled = false
			end
		end)
	end
	return true
end

function DungeonUIRouter.Bind(playerScripts, playerGui)
	local disabledCount = 0
	local suppressedCount = 0
	for _, descendant in ipairs(playerScripts:GetDescendants()) do
		if DungeonUIRouter.ApplyScriptPolicy(descendant) then
			disabledCount += 1
		end
	end
	for _, child in ipairs(playerGui:GetChildren()) do
		if DungeonUIRouter.ApplyGuiPolicy(child) then
			suppressedCount += 1
		end
	end
	if not bound then
		bound = true
		playerScripts.DescendantAdded:Connect(DungeonUIRouter.ApplyScriptPolicy)
		playerGui.ChildAdded:Connect(DungeonUIRouter.ApplyGuiPolicy)
	end
	return disabledCount, suppressedCount
end

return table.freeze(DungeonUIRouter)
