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
		RunLevel = {
			FirstLevelEndDistance = 150,
			SecondLevelEndDistance = 300,
			DistanceIncreaseAfterSecond = 300,
			DistanceGrowthAfterSecond = 0.10,
			DamageTakenPerLevel = 0.10,
			DamageDealtRetentionPerLevel = 0.90,
			RewardPerLevel = 0.10,
			UpgradeSeedSalt = 982451653,
			TemporaryUpgrades = {
				{
					Id = "Haste",
					DisplayName = "Golpes ageis",
					AttackSpeedMultiplier = 1.08,
				},
				{
					Id = "Mobility",
					DisplayName = "Passos leves",
					WalkSpeed = 1.5,
				},
				{
					Id = "Impact",
					DisplayName = "Impacto maior",
					KnockbackMultiplier = 1.15,
				},
				{
					Id = "Critical",
					DisplayName = "Olho critico",
					CriticalChance = 0.03,
				},
				{
					Id = "Vitality",
					DisplayName = "Vitalidade",
					MaxHealth = 10,
				},
			},
		},
	},

	Rewards = {
		Daily = {
			{ Coins = 50, Score = 10 },
			{ Coins = 75, Score = 15 },
			{ Coins = 105, Score = 20 },
			{ Coins = 140, Score = 25 },
			{ Coins = 185, Score = 30 },
			{ Coins = 240, Score = 40 },
			{ Coins = 350, Score = 60 },
		},
		Playtime = {
			{ Minutes = 5, Coins = 20, Score = 10 },
			{ Minutes = 10, Coins = 35, Score = 15 },
			{ Minutes = 20, Coins = 60, Score = 25 },
			{ Minutes = 30, Coins = 90, Score = 35 },
			{ Minutes = 60, Coins = 180, Score = 60 },
		},
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
		MinimumBuildingCount = 1,
		MaximumBuildingCount = 2,
		-- O MVP usa somente um tipo de NPC e uma instancia dele por vila.
		MinimumVillagerCount = 1,
		MaximumVillagerCount = 1,
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
		-- A escalada normal agora acontece no próprio jogador via RunLevel.
		-- Elites continuam sendo encontros especiais deliberadamente mais fortes.
		HealthPerTier = 0,
		DamagePerTier = 0,
		RewardPerTier = 0,
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

	Social = {
		Downed = {
			DurationSeconds = 15,
			ReviveHoldSeconds = 3,
			ReviveHealthRatio = 0.35,
			ProtectionSeconds = 3,
			WeaknessSeconds = 60,
			ReviveDistanceStuds = 10,
		},
		Trade = {
			MaximumCompanionsPerOffer = 4,
			InviteLifetimeSeconds = 30,
			MaximumDistanceStuds = 60,
			ConfirmationCountdownSeconds = 3,
		},
	},

	Tutorial = {
		-- "NewPlayers" usa o progresso salvo; "AllPlayers" repete para todos.
		-- Por seguranca, AllPlayers so funciona no Studio por padrao.
		Audience = "NewPlayers",
		ForceForAllPlayers = false,
		ForceForAllPlayersOnlyInStudio = true,
		PersistForcedCompletion = false,
		HelpDelaySeconds = 6,
	},

	Death = {
		PauseSeconds = 8,
		FreeRespawnDelaySeconds = 4,
	},

	Monetization = {
		-- O algoritmo apenas prepara uma recomendacao dentro do mercador.
		-- Nunca abre uma janela de compra sozinho.
		FirstOfferDelaySeconds = 180,
		OfferEvaluationSeconds = 20,
		OfferCooldownSeconds = 6 * 60,
		RefusedProductCooldownSeconds = 15 * 60,
		MaximumOffersPerSession = 2,
		CombatQuietSeconds = 12,
		MinimumWaterGapStuds = 30,
		-- Pontuacao final normalizada (0-100):
		-- 60% comportamento/contexto, 25% intencao observada na sessao e
		-- 15% Platform Spender Status. Quando o segmento nao esta disponivel,
		-- os primeiros dois pesos sao normalizados para 70,6% e 29,4%.
		BehaviorContextWeight = 0.60,
		SessionIntentWeight = 0.25,
		PlatformSpenderWeight = 0.15,
		MinimumOfferScore = 42,
		StoreOpenIntentDebounceSeconds = 5,
		TemporaryWingUsesPerPurchase = 3,
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
		MimicChance = 1,
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

local RunLevel = Config.Progression.RunLevel

function RunLevel.GetLevelLength(level)
	level = math.max(1, math.floor(tonumber(level) or 1))
	if level == 1 then
		return RunLevel.FirstLevelEndDistance
	elseif level == 2 then
		return RunLevel.SecondLevelEndDistance - RunLevel.FirstLevelEndDistance
	end
	return RunLevel.DistanceIncreaseAfterSecond * (1 + RunLevel.DistanceGrowthAfterSecond) ^ (level - 2)
end

function RunLevel.GetLevelBounds(level)
	level = math.max(1, math.floor(tonumber(level) or 1))
	if level == 1 then
		return 0, RunLevel.FirstLevelEndDistance
	elseif level == 2 then
		return RunLevel.FirstLevelEndDistance, RunLevel.SecondLevelEndDistance
	end

	local rangeStart = RunLevel.SecondLevelEndDistance
	for currentLevel = 3, level - 1 do
		rangeStart += RunLevel.GetLevelLength(currentLevel)
	end
	return rangeStart, rangeStart + RunLevel.GetLevelLength(level)
end

function RunLevel.GetLevelFromDistance(distance)
	distance = math.max(0, tonumber(distance) or 0)
	if distance < RunLevel.FirstLevelEndDistance then
		return 1
	elseif distance < RunLevel.SecondLevelEndDistance then
		return 2
	end

	local level = 3
	local _, rangeEnd = RunLevel.GetLevelBounds(level)
	while distance >= rangeEnd do
		level += 1
		rangeEnd += RunLevel.GetLevelLength(level)
	end
	return level
end

return table.freeze(Config)
