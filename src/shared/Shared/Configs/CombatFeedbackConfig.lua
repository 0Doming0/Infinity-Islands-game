--[[
	Infinity Islands - Task 18
	CombatFeedbackConfig V1

	Presentation only.
	No gameplay stats are changed here.
	No HUD is created here.
]]

local Config = {}

Config.Version = "CombatFeedbackV1"
Config.Policy = "AuthoredFeedbackOnly"

Config.KillFeedbackTag =
	"DungeonHUD_KillFeedback"

Config.LevelUpFeedbackTag =
	"DungeonHUD_LevelUpFeedback"

Config.KillFeedbackRootNames =
	table.freeze({
		"KillFeedback",
		"KillFeedbackPanel",
		"XPFeedback",
		"XPToast",
	})

Config.LevelUpFeedbackRootNames =
	table.freeze({
		"LevelUpFeedback",
		"LevelUpBanner",
		"LevelUp",
	})

Config.KillVisibleSeconds = 0.75
Config.LevelUpVisibleSeconds = 1.65

Config.TextPulseScale = 1.18
Config.TextPulseUpSeconds = 0.10
Config.TextPulseDownSeconds = 0.18

Config.RiskMinimumPercentToShow = 1

Config.VariantDisplayNames =
	table.freeze({
		Green = "GREEN SLIME",
		Blue = "BLUE SLIME",
		Red = "RED SLIME",
		Fire = "FIRE SLIME",
		Ice = "ICE SLIME",
		Lightning = "LIGHTNING SLIME",
	})

return table.freeze(Config)
