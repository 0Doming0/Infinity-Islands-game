-- ReplicatedStorage/MVPConfig
-- Valores centrais do MVP. IDs marcados como exemplo devem ser substituidos
-- pelos assets publicados pelo dono ou grupo da experiencia antes do lancamento.

local Config = {
	Currency = {
		-- Simbolo monetario antigo e compativel com as fontes do Roblox.
		-- Evita emojis recentes que podem aparecer como quadrados em alguns aparelhos.
		Symbol = "¤",
	},

	Progression = {
		DeathCoinLossPercent = 0.20,
		LegacyScoreDivisor = 1000,
		GlobalLeaderboardSize = 25,
		GlobalLeaderboardRefreshSeconds = 60,
		SurvivalScoreIntervalSeconds = 5,
		SurvivalScorePerInterval = 1,
		HeightCheckpointStuds = 15,
		ScorePerHeightCheckpoint = 5,
	},

	Water = {
		StartSurfaceY = -15,
		WarmupSeconds = 10,
		BaseSpeed = 0.95,
		MinimumSpeedMultiplier = 0.58,
		MaximumSpeedMultiplier = 3.10,
		DangerGap = 20,
		TargetGap = 58,
		FastGap = 135,
		DifficultyMinutesToMaximum = 10,
		MaximumDifficultyMultiplier = 1.65,
		SpeedSmoothing = 3.4,
		DamagePerSecond = 18,
		EventMultiplierAttribute = "WaterSpeedEventMultiplier",
	},

	Village = {
		MinimumRound = 3,
		GuaranteedEveryRounds = 6,
		MediumChance = 0.08,
		LargeChance = 0.16,
		SoloMerchantChance = 0.07,
		MinimumBuildingCount = 2,
		MaximumBuildingCount = 3,
		MinimumVillagerCount = 1,
		MaximumVillagerCount = 3,
		RandomSalt = 73428767,
		ShopTag = "ProceduralSwordVillager",
		PromptDistance = 13,
		EmptyStockChance = 0.25,
		MinimumOfferTypes = 1,
		MaximumOfferTypes = 2,
		MinimumStockPerOffer = 1,
		MaximumStockPerOffer = 2,
		InventoryRandomSalt = 526133,
	},

	SafeZones = {
		Enabled = true,
		CheckIntervalSeconds = 0.10,
		HorizontalPaddingStuds = 0.75,
		VerticalPaddingStuds = 12,
		WaterContactFootOffsetStuds = 0.5,
		ShieldVisible = true,
	},

	Difficulty = {
		RoundsPerTier = 4,
		MaximumTier = 8,
		HealthPerTier = 0.18,
		DamagePerTier = 0.12,
		RewardPerTier = 0.10,
		EliteHealthMultiplier = 3.6,
		EliteDamageMultiplier = 1.65,
		EliteRewardMultiplier = 3,
		EliteSpeedMultiplier = 1.28,
		EliteAttackCooldownMultiplier = 0.72,
	},

	Party = {
		MaxMembers = 4,
		InviteLifetimeSeconds = 30,
		IndicatorDistanceStuds = 70,
		Mission = {
			Id = "PartyExpedition",
			Title = "EXPEDIÇÃO EM GRUPO",
			MobDefeatedGoal = 5,
			IslandVisitedGoal = 3,
		},
	},

	Tutorial = {
		-- Ative para repetir o tutorial para todos durante testes. Por padrao,
		-- a opcao so tem efeito no Studio e nao altera o progresso persistente.
		ForceForAllPlayers = false,
		ForceForAllPlayersOnlyInStudio = true,
		PersistForcedCompletion = false,
	},

	SpecialIslands = {
		MinimumEliteRound = 2,
		EliteChance = 0.12,
		MinimumTreasureRound = 4,
		TreasureChance = 0.02,
		MinimumTreasureRoundGap = 8,
		RandomSalt = 191983,
	},

	Chests = {
		NormalIslandChance = 0.18,
		MimicChance = 0.1,
		NormalMinimumCoins = 15,
		NormalMaximumCoins = 40,
		MimicMinimumCoins = 40,
		MimicMaximumCoins = 90,
		TreasureMinimumChests = 4,
		TreasureMaximumChests = 7,
		TreasureMaximumMimics = 2,
		MinimumChestSpacing = 6,
		PromptDistance = 11,
		RandomSalt = 887503,
	},

	Events = {
		FirstEventDelaySeconds = 105,
		MinimumIntervalSeconds = 180,
		MaximumIntervalSeconds = 300,
		RisingTideDurationSeconds = 25,
		RisingTideMultiplier = 1.55,
		CoinRushDurationSeconds = 35,
		CoinRushMultiplier = 2,
		MonsterHuntDurationSeconds = 30,
		WildFuryDurationSeconds = 35,
	},

	Atmosphere = {
		AssetFolder = "Atmosphere",
		AmbientMusicName = "AmbientMusic",
		AmbientFadeSeconds = 1.25,
		AmbientSilenceMinimumSeconds = 12,
		AmbientSilenceMaximumSeconds = 25,
		AmbientRetrySeconds = 3,
		ForestAmbienceEnabled = true,
		ForestAmbienceName = "ForestAmbience",
		ForestLoopName = "ForestLoop",
		BirdCallsFolderName = "BirdCalls",
		ForestMasterVolume = 1,
		ForestDangerVolumeMultiplier = 0.55,
		ForestFadeSeconds = 2,
		BirdCallMinimumIntervalSeconds = 8,
		BirdCallMaximumIntervalSeconds = 20,
		DangerMusicName = "DangerMusic",
	},

	ExampleAssets = {
		-- IDs publicos/provisorios. Troque por animacoes do proprietario do jogo.
		Animations = {
			Equip = "rbxassetid://507768375",
			Idle = "rbxassetid://507768375",
			Attack1 = "rbxassetid://137981608525978",
			Attack2 = "rbxassetid://128834898913145",
			Attack3 = "rbxassetid://134725485403964"
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
