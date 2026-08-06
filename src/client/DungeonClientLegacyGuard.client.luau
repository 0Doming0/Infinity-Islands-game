local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local playerGui = player:WaitForChild("PlayerGui")

local BLOCKED_LOCAL_SCRIPTS = table.freeze({
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

local BLOCKED_GUIS = table.freeze({
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

local disabledCount = 0
local guiCount = 0

local function disableScript(instance)
	if instance == script
		or not instance:IsA("LocalScript")
		or not BLOCKED_LOCAL_SCRIPTS[instance.Name]
	then
		return
	end
	if not instance.Disabled then
		instance.Disabled = true
		disabledCount += 1
	end
	instance:SetAttribute("DisabledByDungeonClientGuard", true)
end

local function suppressGui(instance)
	if not instance:IsA("ScreenGui") or not BLOCKED_GUIS[instance.Name] then
		return
	end
	if instance.Enabled then
		instance.Enabled = false
		guiCount += 1
	end
	instance:SetAttribute("SuppressedByDungeonClientGuard", true)
end

for _, descendant in ipairs(playerScripts:GetDescendants()) do
	disableScript(descendant)
end
for _, child in ipairs(playerGui:GetChildren()) do
	suppressGui(child)
end

playerScripts.DescendantAdded:Connect(disableScript)
playerGui.ChildAdded:Connect(suppressGui)

player:SetAttribute("DungeonClientLegacyGuardReady", true)
player:SetAttribute("DungeonClientLegacyScriptsDisabled", disabledCount)
player:SetAttribute("DungeonClientLegacyGuisSuppressed", guiCount)
