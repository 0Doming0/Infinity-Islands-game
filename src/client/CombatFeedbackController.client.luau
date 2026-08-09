--[[
	Infinity Islands - Task 18
	CombatFeedbackController V1

	Authored-HUD-only feedback.

	Optional Studio roots:
	Tag: DungeonHUD_KillFeedback
	Tag: DungeonHUD_LevelUpFeedback

	The controller NEVER creates a visual Instance.
	If the optional roots are absent, gameplay is unaffected.

	It also pulses existing PlayerStatus text elements when possible.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("CombatFeedbackConfig")
)

local killRoot
local levelRoot

local killToken = 0
local levelToken = 0
local pulseTokens =
	setmetatable({}, { __mode = "k" })

local function isGuiRoot(instance)
	return instance
		and (
			instance:IsA("ScreenGui")
				or instance:IsA("GuiObject")
		)
end

local function setRootVisible(
	root,
	visible
)
	if not root
		or not root.Parent
	then
		return false
	end

	if root:IsA("ScreenGui") then
		root.Enabled = visible
		return true
	end

	if root:IsA("GuiObject") then
		root.Visible = visible
		return true
	end

	return false
end

local function taggedRoot(tag)
	for _, instance in ipairs(
		CollectionService:GetTagged(tag)
	) do
		if isGuiRoot(instance)
			and instance:IsDescendantOf(
				playerGui
			)
		then
			return instance
		end
	end

	return nil
end

local function namedRoot(names)
	for _, name in ipairs(names) do
		local instance =
			playerGui:FindFirstChild(
				name,
				true
			)

		if isGuiRoot(instance) then
			return instance
		end
	end

	return nil
end

local function resolveKillRoot()
	if killRoot
		and killRoot.Parent
	then
		return killRoot
	end

	killRoot =
		taggedRoot(
			Config.KillFeedbackTag
		)
			or namedRoot(
				Config.KillFeedbackRootNames
			)

	if killRoot then
		setRootVisible(
			killRoot,
			false
		)

		killRoot:SetAttribute(
			"RuntimeCombatFeedbackVersion",
			Config.Version
		)
	end

	player:SetAttribute(
		"DungeonKillFeedbackAuthoredRootFound",
		killRoot ~= nil
	)

	return killRoot
end

local function resolveLevelRoot()
	if levelRoot
		and levelRoot.Parent
	then
		return levelRoot
	end

	levelRoot =
		taggedRoot(
			Config.LevelUpFeedbackTag
		)
			or namedRoot(
				Config.LevelUpFeedbackRootNames
			)

	if levelRoot then
		setRootVisible(
			levelRoot,
			false
		)

		levelRoot:SetAttribute(
			"RuntimeCombatFeedbackVersion",
			Config.Version
		)
	end

	player:SetAttribute(
		"DungeonLevelUpFeedbackAuthoredRootFound",
		levelRoot ~= nil
	)

	return levelRoot
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

local function pulseText(textObject)
	if not textObject
		or not textObject.Parent
		or not (
			textObject:IsA("TextLabel")
				or textObject:IsA("TextButton")
		)
	then
		return
	end

	pulseTokens[textObject] =
		(pulseTokens[textObject] or 0) + 1

	local token =
		pulseTokens[textObject]

	local original =
		textObject.TextSize

	if original <= 0 then
		return
	end

	local enlarged =
		original
			* Config.TextPulseScale

	local up =
		TweenService:Create(
			textObject,
			TweenInfo.new(
				Config.TextPulseUpSeconds,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				TextSize = enlarged,
			}
		)

	up:Play()

	up.Completed:Once(function()
		if pulseTokens[textObject]
			~= token
			or not textObject.Parent
		then
			return
		end

		local down =
			TweenService:Create(
				textObject,
				TweenInfo.new(
					Config.TextPulseDownSeconds,
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				),
				{
					TextSize = original,
				}
			)

		down:Play()
	end)
end

local function resolvePlayerStatus()
	for _, instance in ipairs(
		CollectionService:GetTagged(
			"DungeonHUD_PlayerStatus"
		)
	) do
		if instance:IsDescendantOf(
			playerGui
		)
		then
			return instance
		end
	end

	return playerGui:FindFirstChild(
		"PlayerStatus",
		true
	)
end

local function pulseXPStatus(levelUp)
	local status =
		resolvePlayerStatus()

	if not status then
		return
	end

	local xpText =
		findText(
			status,
			{
				"XPText",
				"ExpText",
				"ExperienceText",
				"XPValue",
			}
		)

	if xpText then
		pulseText(xpText)
	end

	if levelUp then
		local levelText =
			findText(
				status,
				{
					"LevelText",
					"PlayerLevelText",
					"Level",
				}
			)

		if levelText then
			pulseText(levelText)
		end
	end
end

local function variantDisplayName(raw)
	local variant =
		tostring(raw or "Slime")

	return Config.VariantDisplayNames[
		variant
	] or string.upper(variant)
end

local function showKillFeedback()
	local amount =
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute(
						"LastMobXPFinalReward"
					)
				) or 0
			)
		)

	if amount <= 0 then
		return
	end

	killToken += 1
	local token = killToken

	local root =
		resolveKillRoot()

	pulseXPStatus(false)

	player:SetAttribute(
		"DungeonLastKillFeedbackXP",
		amount
	)

	player:SetAttribute(
		"DungeonLastKillFeedbackAt",
		workspace:GetServerTimeNow()
	)

	if not root then
		return
	end

	local xpText =
		findText(
			root,
			{
				"XPText",
				"XPValue",
				"RewardText",
				"AmountText",
			}
		)

	local riskText =
		findText(
			root,
			{
				"RiskText",
				"RiskBonusText",
				"BonusText",
			}
		)

	local variantText =
		findText(
			root,
			{
				"VariantText",
				"MobText",
				"EnemyText",
				"NameText",
			}
		)

	if xpText then
		xpText.Text =
			"+" .. tostring(amount)
				.. " XP"

		pulseText(xpText)
	end

	local risk =
		math.max(
			0,
			tonumber(
				player:GetAttribute(
					"LastMobXPRiskBonus"
				)
			) or 0
		)

	local riskPercent =
		math.floor(
			risk * 100 + 0.5
		)

	if riskText then
		riskText.Visible =
			riskPercent
				>= Config
					.RiskMinimumPercentToShow

		if riskText.Visible then
			riskText.Text =
				"+"
					.. tostring(
						riskPercent
					)
					.. "% RISCO"
		end
	end

	if variantText then
		variantText.Text =
			variantDisplayName(
				player:GetAttribute(
					"LastMobXPVariant"
				)
			)
	end

	root:SetAttribute(
		"RuntimeXP",
		amount
	)
	root:SetAttribute(
		"RuntimeRiskBonus",
		risk
	)
	root:SetAttribute(
		"RuntimeVariant",
		player:GetAttribute(
			"LastMobXPVariant"
		)
	)

	setRootVisible(
		root,
		true
	)

	task.delay(
		Config.KillVisibleSeconds,
		function()
			if token ~= killToken then
				return
			end

			if root.Parent then
				setRootVisible(
					root,
					false
				)
			end
		end
	)
end

local function showLevelUpFeedback()
	local level =
		math.max(
			1,
			math.floor(
				tonumber(
					player:GetAttribute(
						"PlayerLevel"
					)
				) or 1
			)
		)

	levelToken += 1
	local token = levelToken

	local root =
		resolveLevelRoot()

	pulseXPStatus(true)

	player:SetAttribute(
		"DungeonLastLevelUpFeedbackLevel",
		level
	)

	player:SetAttribute(
		"DungeonLastLevelUpFeedbackAt",
		workspace:GetServerTimeNow()
	)

	if not root then
		return
	end

	local title =
		findText(
			root,
			{
				"Title",
				"LevelUpTitle",
				"Header",
			}
		)

	local levelText =
		findText(
			root,
			{
				"LevelText",
				"LevelValue",
				"NewLevelText",
			}
		)

	local powerText =
		findText(
			root,
			{
				"PowerText",
				"StatsText",
				"BonusText",
				"Description",
			}
		)

	if title then
		title.Text = "LEVEL UP!"
	end

	if levelText then
		levelText.Text =
			"NÍVEL "
				.. tostring(level)

		pulseText(levelText)
	end

	local damageMultiplier =
		tonumber(
			player:GetAttribute(
				"PlayerLevelDamageMultiplier"
			)
		) or 1

	local healthMultiplier =
		tonumber(
			player:GetAttribute(
				"PlayerLevelHealthMultiplier"
			)
		) or 1

	if powerText then
		powerText.Text =
			string.format(
				"DANO %.2fx  •  VIDA %.2fx",
				damageMultiplier,
				healthMultiplier
			)
	end

	root:SetAttribute(
		"RuntimePlayerLevel",
		level
	)

	root:SetAttribute(
		"RuntimeDamageMultiplier",
		damageMultiplier
	)

	root:SetAttribute(
		"RuntimeHealthMultiplier",
		healthMultiplier
	)

	setRootVisible(
		root,
		true
	)

	task.delay(
		Config.LevelUpVisibleSeconds,
		function()
			if token ~= levelToken then
				return
			end

			if root.Parent then
				setRootVisible(
					root,
					false
				)
			end
		end
	)
end

player:GetAttributeChangedSignal(
	"MobXPFeedbackSerial"
):Connect(
	showKillFeedback
)

player:GetAttributeChangedSignal(
	"PlayerLevelUpSerial"
):Connect(
	showLevelUpFeedback
)

playerGui.DescendantAdded:Connect(function()
	task.defer(function()
		if not killRoot then
			resolveKillRoot()
		end

		if not levelRoot then
			resolveLevelRoot()
		end
	end)
end)

resolveKillRoot()
resolveLevelRoot()

player:SetAttribute(
	"DungeonCombatFeedbackControllerReady",
	true
)

player:SetAttribute(
	"DungeonCombatFeedbackVersion",
	Config.Version
)

player:SetAttribute(
	"DungeonCombatFeedbackPolicy",
	Config.Policy
)

player:SetAttribute(
	"DungeonCombatFeedbackCreatesVisuals",
	false
)
