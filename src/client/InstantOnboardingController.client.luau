--[[
	Infinity Islands - Direct Island Start Controller

	Purpose:
	- never block gameplay behind Start/Tutorial/Loading legacy screens;
	- stay compatible with the simplified InstantOnboardingConfig;
	- never create HUD;
	- preserve the authored DungeonHUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("InstantOnboardingConfig")
)

local BLOCKED_GUI_NAMES = {
	StartScreen = true,
	StartUI = true,
	DungeonStartScreen = true,
	DungeonStartUI = true,
	ReadyScreen = true,
	ReadyUI = true,
	TutorialScreen = true,
	TutorialUI = true,
	InitialScreen = true,
	InitialUI = true,
	SpawnScreen = true,
	SpawnUI = true,
	LoadingScreen = true,
	LoadingUI = true,
	DungeonLoadingScreen = true,
	DungeonLoadingUI = true,
	StartMenu = true,
	DungeonStartMenu = true,
}

local BLOCKED_SCRIPT_NAMES = {
	DungeonSpectator = true,
	WorldEventUI = true,
	VillagerUI = true,
	TutorialUI = true,
	MonetizationUI = true,
	LeaderboardUI = true,
	RewardWheelUI = true,
	DungeonPartyLifeHUD = true,
	DungeonUnifiedHUD = true,
	DungeonObjectiveHUD = true,
	DungeonRewardsHUD = true,
}

local function setHidden(instance)
	if instance:IsA("ScreenGui") then
		instance.Enabled = false
		return true
	end

	if instance:IsA("GuiObject") then
		instance.Visible = false
		return true
	end

	return false
end

local function suppress(instance)
	if not instance or not instance.Parent then
		return
	end

	if BLOCKED_GUI_NAMES[instance.Name] then
		if setHidden(instance) then
			instance:SetAttribute(
				"SuppressedByDirectIslandStart",
				true
			)

			if instance:IsA("ScreenGui") then
				if instance:GetAttribute(
					"DirectIslandStartBound"
				) ~= true then
					instance:SetAttribute(
						"DirectIslandStartBound",
						true
					)

					instance:GetPropertyChangedSignal(
						"Enabled"
					):Connect(function()
						if instance.Parent and instance.Enabled then
							instance.Enabled = false
						end
					end)
				end
			elseif instance:IsA("GuiObject") then
				if instance:GetAttribute(
					"DirectIslandStartBound"
				) ~= true then
					instance:SetAttribute(
						"DirectIslandStartBound",
						true
					)

					instance:GetPropertyChangedSignal(
						"Visible"
					):Connect(function()
						if instance.Parent and instance.Visible then
							instance.Visible = false
						end
					end)
				end
			end
		end
	end

	if instance:IsA("LocalScript")
		and BLOCKED_SCRIPT_NAMES[instance.Name]
	then
		instance.Disabled = true
		instance:SetAttribute(
			"DisabledByDirectIslandStart",
			true
		)
	end
end

local function suppressAll()
	for _, instance in ipairs(playerGui:GetDescendants()) do
		suppress(instance)
	end

	for _, instance in ipairs(playerGui:GetChildren()) do
		suppress(instance)
	end

	local playerScripts = player:FindFirstChildOfClass(
		"PlayerScripts"
	)

	if playerScripts then
		for _, instance in ipairs(
			playerScripts:GetDescendants()
		) do
			suppress(instance)
		end
	end
end

local function forceDirectStartAttributes()
	player:SetAttribute("DungeonRuntimeAutoStart", true)
	player:SetAttribute("InitialGameStarted", true)
	player:SetAttribute(
		"DungeonStartConfirmationRequired",
		false
	)
	player:SetAttribute("DungeonTutorialBlocking", false)
	player:SetAttribute("DungeonGuideEnabled", false)
	player:SetAttribute(
		"DungeonOnboardingBlocksGameplay",
		false
	)
	player:SetAttribute(
		"DungeonInstantOnboardingClientReady",
		true
	)
	player:SetAttribute(
		"DungeonInstantOnboardingVersion",
		Config.Version
	)
	player:SetAttribute(
		"DungeonInstantOnboardingPolicy",
		Config.Policy
	)
end

suppressAll()
forceDirectStartAttributes()

playerGui.DescendantAdded:Connect(function(instance)
	task.defer(suppress, instance)
end)

local playerScripts = player:FindFirstChildOfClass(
	"PlayerScripts"
)

if playerScripts then
	playerScripts.DescendantAdded:Connect(function(instance)
		task.defer(suppress, instance)
	end)
end

for _, attributeName in ipairs({
	"InitialGameStarted",
	"DungeonStartConfirmationRequired",
	"DungeonTutorialBlocking",
	"DungeonGuideEnabled",
}) do
	player:GetAttributeChangedSignal(
		attributeName
	):Connect(function()
		task.defer(forceDirectStartAttributes)
	end)
end

task.delay(
	math.max(
		0.5,
		tonumber(Config.TargetTimeToControlSeconds) or 2.5
	),
	function()
		suppressAll()
		forceDirectStartAttributes()
	end
)

print(
	"[DirectIslandStart] Client ready; legacy start/tutorial/loading blockers suppressed."
)
