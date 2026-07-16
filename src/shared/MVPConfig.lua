-- ReplicatedStorage/MVPConfig
-- Valores centrais do MVP. IDs marcados como exemplo devem ser substituidos
-- pelos assets publicados pelo dono ou grupo da experiencia antes do lancamento.

local Config = {
	Water = {
		StartSurfaceY = -15,
		WarmupSeconds = 12,
		BaseSpeed = 1,
		MinimumSpeedMultiplier = 0.30,
		MaximumSpeedMultiplier = 2.50,
		DangerGap = 24,
		TargetGap = 68,
		FastGap = 175,
		DifficultyMinutesToMaximum = 12,
		MaximumDifficultyMultiplier = 1.35,
		SpeedSmoothing = 2.8,
		DamagePerSecond = 12,
		ScorePerSecond = 1,
		HeightBonusStuds = 15,
	},

	Village = {
		MinimumRound = 2,
		GuaranteedEveryRounds = 3,
		MediumChance = 0.22,
		LargeChance = 0.52,
		MinimumBuildingCount = 2,
		MaximumBuildingCount = 3,
		RandomSalt = 73428767,
		ShopTag = "ProceduralSwordVillager",
		PromptDistance = 13,
	},

	ExampleAssets = {
		-- IDs publicos/provisorios. Troque por animacoes do proprietario do jogo.
		Animations = {
			Equip = "rbxassetid://507768375",
			Idle = "rbxassetid://507768375",
			Attack1 = "rbxassetid://522635514",
			Attack2 = "rbxassetid://522638767",
			Attack3 = "rbxassetid://522635514",
		},
		Sounds = {
			Equip = "rbxasset://sounds/unsheath.wav",
			Swing = "rbxasset://sounds/swordslash.wav",
			HeavySwing = "rbxasset://sounds/swordlunge.wav",
			Hit = "rbxasset://sounds/electronicpingshort.wav",
			Purchase = "rbxasset://sounds/electronicpingshort.wav",
		},
	},
}

return table.freeze(Config)
