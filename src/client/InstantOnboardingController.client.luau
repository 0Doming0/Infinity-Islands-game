--[[
	Infinity Islands - Task 16
	InstantOnboardingController V1

	Client presentation guarantee:
	- suppress legacy blocking Start/Tutorial screens;
	- optionally control a Studio-authored BasicControls panel;
	- never create HUD;
	- never wait for user confirmation;
	- gameplay remains live underneath the controls hint.

	Authored optional root:
	Tag: DungeonHUD_BasicControls

	Accepted fallback names:
	BasicControls
	BasicControlsPanel
	ControlsPanel
	ControlsHint
	GameplayControls
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("InstantOnboardingConfig")
)

local startedAt = os.clock()
local controlsRoot
local controlsHidden = false
local suppressCount = 0

local function setGuiVisible(instance, visible)
	if instance:IsA("ScreenGui") then
		instance.Enabled = visible
		return true
	end

	if instance:IsA("GuiObject") then
		instance.Visible = visible
		return true
	end

	return false
end

local function suppressLegacy(instance)
	if not instance
		or not instance.Parent
	then
		return false
	end

	local blocked =
		Config.BlockedGuiNames[instance.Name]
			== true

	if blocked then
		if setGuiVisible(
			instance,
			false
		)
		then
			suppressCount += 1

			instance:SetAttribute(
				"SuppressedByInstantOnboarding",
				true
			)

			player:SetAttribute(
				"DungeonInstantOnboardingSuppressedCount",
				suppressCount
			)

			-- If some old controller tries to reopen it, keep it suppressed.
			if instance:GetAttribute(
				"InstantOnboardingSuppressionBound"
			) ~= true
			then
				instance:SetAttribute(
					"InstantOnboardingSuppressionBound",
					true
				)

				if instance:IsA("ScreenGui") then
					instance:GetPropertyChangedSignal(
						"Enabled"
					):Connect(function()
						if instance.Parent
							and instance.Enabled
						then
							instance.Enabled = false
						end
					end)
				elseif instance:IsA("GuiObject") then
					instance:GetPropertyChangedSignal(
						"Visible"
					):Connect(function()
						if instance.Parent
							and instance.Visible
						then
							instance.Visible = false
						end
					end)
				end
			end
		end

		return true
	end

	if instance:IsA("LocalScript")
		and Config.BlockedScriptNames[
			instance.Name
		] == true
	then
		instance.Disabled = true

		instance:SetAttribute(
			"DisabledByInstantOnboarding",
			true
		)

		return true
	end

	return false
end

local function suppressExistingLegacy()
	for _, descendant in ipairs(
		playerGui:GetDescendants()
	) do
		suppressLegacy(descendant)
	end

	for _, child in ipairs(
		playerGui:GetChildren()
	) do
		suppressLegacy(child)
	end

	local playerScripts =
		player:FindFirstChildOfClass(
			"PlayerScripts"
		)

	if playerScripts then
		for _, descendant in ipairs(
			playerScripts:GetDescendants()
		) do
			suppressLegacy(descendant)
		end
	end
end

local function isGuiRoot(instance)
	return instance
		and (
			instance:IsA("ScreenGui")
				or instance:IsA("GuiObject")
		)
end

local function findControlsRoot()
	for _, tagged in ipairs(
		CollectionService:GetTagged(
			Config.BasicControlsTag
		)
	) do
		if isGuiRoot(tagged)
			and tagged:IsDescendantOf(
				playerGui
			)
		then
			return tagged
		end
	end

	for _, name in ipairs(
		Config.BasicControlsRootNames
	) do
		local candidate =
			playerGui:FindFirstChild(
				name,
				true
			)

		if isGuiRoot(candidate) then
			return candidate
		end
	end

	return nil
end

local function findText(
	root,
	names
)
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local candidate =
			root:FindFirstChild(
				name,
				true
			)

		if candidate
			and (
				candidate:IsA("TextLabel")
					or candidate:IsA("TextButton")
			)
		then
			return candidate
		end
	end

	return nil
end

local function inputProfile()
	local profile =
		tostring(
			player:GetAttribute(
				"DungeonCurrentInputProfile"
			)
				or player:GetAttribute(
					"DungeonEntryInputProfile"
				)
				or ""
		)

	if profile == "Touch"
		or (
			profile == ""
				and UserInputService.TouchEnabled
		)
	then
		return "Touch"
	end

	if profile == "Gamepad"
		or UserInputService.GamepadEnabled
			and not UserInputService.KeyboardEnabled
	then
		return "Gamepad"
	end

	return "Keyboard"
end

local function copyForProfile()
	local profile = inputProfile()

	if profile == "Touch" then
		return Config.TouchCopy,
			profile
	elseif profile == "Gamepad" then
		return Config.GamepadCopy,
			profile
	end

	return Config.KeyboardCopy,
		profile
end

local function applyControlsCopy(root)
	local copy,
		profile =
			copyForProfile()

	local movement =
		findText(
			root,
			{
				"MovementText",
				"MoveText",
				"Movement",
				"Move",
			}
		)

	local attack =
		findText(
			root,
			{
				"AttackText",
				"Attack",
				"PrimaryActionText",
			}
		)

	local sprint =
		findText(
			root,
			{
				"SprintText",
				"RunText",
				"Sprint",
				"Run",
			}
		)

	local hint =
		findText(
			root,
			{
				"HintText",
				"ObjectiveText",
				"InstructionText",
				"Description",
			}
		)

	if movement then
		movement.Text =
			copy.Movement
	end

	if attack then
		attack.Text =
			copy.Attack
	end

	if sprint then
		sprint.Text =
			copy.Sprint
	end

	if hint then
		hint.Text =
			copy.Hint
	end

	root:SetAttribute(
		"RuntimeInputProfile",
		profile
	)

	root:SetAttribute(
		"RuntimeOnboardingVersion",
		Config.Version
	)
end

local function showControls()
	if controlsHidden then
		return
	end

	controlsRoot =
		controlsRoot
			or findControlsRoot()

	if not controlsRoot then
		player:SetAttribute(
			"DungeonBasicControlsAuthoredRootFound",
			false
		)

		return
	end

	player:SetAttribute(
		"DungeonBasicControlsAuthoredRootFound",
		true
	)

	applyControlsCopy(
		controlsRoot
	)

	setGuiVisible(
		controlsRoot,
		true
	)

	player:SetAttribute(
		"DungeonBasicControlsVisible",
		true
	)
end

local function hideControls(reason)
	if controlsHidden then
		return
	end

	controlsHidden = true

	if controlsRoot
		and controlsRoot.Parent
	then
		setGuiVisible(
			controlsRoot,
			false
		)
	end

	player:SetAttribute(
		"DungeonBasicControlsVisible",
		false
	)

	player:SetAttribute(
		"DungeonBasicControlsHiddenReason",
		reason
	)

	player:SetAttribute(
		"DungeonBasicControlsHiddenAt",
		workspace:GetServerTimeNow()
	)
end

local function enoughMinimumTime()
	return os.clock() - startedAt
		>= Config.BasicControlsMinimumVisibleSeconds
end

local function evaluateEarlyHide()
	if controlsHidden
		or not enoughMinimumTime()
	then
		return
	end

	if Config.HideBasicControlsAfterFirstXP
		and (
			tonumber(
				player:GetAttribute(
					"PlayerTotalXP"
				)
			) or 0
		) > 0
	then
		hideControls(
			"FirstXP"
		)

		return
	end

	if Config.HideBasicControlsAfterLeavingFirstIsland
		and (
			tonumber(
				player:GetAttribute(
					"CurrentGlobalIslandIndex"
				)
			) or 1
		) > 1
	then
		hideControls(
			"LeftFirstIsland"
		)
	end
end

-- Initial hard guarantee against blockers already copied into PlayerGui.
suppressExistingLegacy()

playerGui.DescendantAdded:Connect(
	function(descendant)
		task.defer(
			suppressLegacy,
			descendant
		)

		if not controlsRoot then
			task.defer(
				showControls
			)
		end
	end
)

local playerScripts =
	player:FindFirstChildOfClass(
		"PlayerScripts"
	)

if playerScripts then
	playerScripts.DescendantAdded:Connect(
		function(descendant)
			task.defer(
				suppressLegacy,
				descendant
			)
		end
	)
end

for _, attribute in ipairs({
	"PlayerTotalXP",
	"CurrentGlobalIslandIndex",
}) do
	player:GetAttributeChangedSignal(
		attribute
	):Connect(
		evaluateEarlyHide
	)
end

player:GetAttributeChangedSignal(
	"DungeonCurrentInputProfile"
):Connect(function()
	if controlsRoot
		and controlsRoot.Parent
		and not controlsHidden
	then
		applyControlsCopy(
			controlsRoot
		)
	end
end)

-- Never wait for the controls panel before gameplay.
task.defer(showControls)

task.delay(
	Config.BasicControlsMinimumVisibleSeconds,
	evaluateEarlyHide
)

task.delay(
	Config.BasicControlsVisibleSeconds,
	function()
		hideControls(
			"Timeout"
		)
	end
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

player:SetAttribute(
	"DungeonOnboardingBlocksGameplay",
	false
)

player:SetAttribute(
	"DungeonStartConfirmationRequired",
	false
)
