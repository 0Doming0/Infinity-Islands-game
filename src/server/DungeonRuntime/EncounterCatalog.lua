local PartyScalingService = require(script.Parent.PartyScalingService)

local EncounterCatalog = {}

local PROFILE_BUILDERS = {}

local function copyEnemy(role, count, options)
	options = type(options) == "table" and options or {}
	return {
		Role = role,
		Count = math.max(0, math.floor(tonumber(count) or 0)),
		SlimeVariant = options.SlimeVariant,
		IsElite = options.IsElite == true,
		HealthMultiplier = options.HealthMultiplier,
		DamageMultiplier = options.DamageMultiplier,
		SpeedMultiplier = options.SpeedMultiplier,
	}
end

local function distribute(total, waveCount)
	total = math.max(0, math.floor(tonumber(total) or 0))
	waveCount = math.max(1, math.floor(tonumber(waveCount) or 1))
	local result = table.create(waveCount, 0)
	for index = 1, total do
		result[((index - 1) % waveCount) + 1] += 1
	end
	return result
end

local function scaledDelay(delaySeconds, partySize)
	return PartyScalingService.ScaleWaveDelay(delaySeconds, partySize)
end

local function wave(delaySeconds, enemies, waitForClear, partySize)
	return {
		DelaySeconds = scaledDelay(delaySeconds, partySize),
		Enemies = enemies,
		WaitForClear = waitForClear ~= false,
	}
end

local function mixedWave(amount, rangedRatio, guardCount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	guardCount = math.clamp(math.floor(tonumber(guardCount) or 0), 0, amount)
	local remaining = amount - guardCount
	local rangedCount = math.clamp(math.floor(remaining * (tonumber(rangedRatio) or 0) + 0.5), 0, remaining)
	local commonCount = remaining - rangedCount
	local enemies = {}
	if commonCount > 0 then
		table.insert(enemies, copyEnemy("Common", commonCount, { SlimeVariant = "Green" }))
	end
	if rangedCount > 0 then
		table.insert(enemies, copyEnemy("Ranged", rangedCount, { SlimeVariant = "Blue" }))
	end
	if guardCount > 0 then
		table.insert(enemies, copyEnemy("Guard", guardCount, { SlimeVariant = "Green" }))
	end
	return enemies
end

local function buildDefeatWaves(target, waveCount, rangedRatio, guardsPerWave, partySize)
	local amounts = distribute(target, waveCount)
	local waves = {}
	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(
			index == 1 and 0.25 or 0.8,
			mixedWave(amount, rangedRatio, math.min(amount, guardsPerWave or 0)),
			true,
			partySize
		))
	end
	return waves
end

local function maxAlive(raw, partySize, minimum, maximum)
	return PartyScalingService.ScaleEncounterMaxAlive(raw, partySize, minimum, maximum)
end

PROFILE_BUILDERS.FirstStrike = function(_, partySize)
	-- FirstStrike is the onboarding proof-of-loop. Exactly one objective slime
	-- is created so the player cannot kill a visually similar "wrong" slime
	-- and remain stuck at 0/1.
	return {
		Mode = "Waves",
		Mechanic = "MarkedOpeningTarget",
		MaxAlive = 1,
		Waves = {
			wave(0.15, {
				copyEnemy("Common", 1, {
					SlimeVariant = "Green",
					HealthMultiplier = 0.80,
					DamageMultiplier = 0.65,
				}),
			}, false, partySize),
		},
	}
end

PROFILE_BUILDERS.CommonWave = function(target, partySize)
	-- ClearThePath é a segunda lição da run: três alvos claros, simultâneos,
	-- sem uma segunda onda escondida e sem depender de mobs ambientais.
	local amount = math.max(1, math.floor(tonumber(target) or 3))
	return {
		Mode = "Waves",
		Mechanic = "OpenCombat",
		MaxAlive = amount,
		Waves = {
			wave(0.20, {
				copyEnemy("Common", amount, {
					SlimeVariant = "Green",
					HealthMultiplier = 0.90,
					DamageMultiplier = 0.75,
					SpeedMultiplier = 0.92,
				}),
			}, false, partySize),
		},
	}
end

PROFILE_BUILDERS.RewardWave01 = function(target, partySize)
	-- Primeira recompensa: sempre exatamente duas ondas e exatamente Target
	-- inimigos. Nenhum mob adicional é criado fora dessa contagem.
	target = math.max(2, math.floor(tonumber(target) or 5))

	local firstWaveCount = math.ceil(target * 0.60)
	local secondWaveCount = target - firstWaveCount

	return {
		Mode = "Waves",
		Mechanic = "EscalatingRewardWaves",
		MaxAlive = math.max(firstWaveCount, secondWaveCount),
		Waves = {
			wave(0.20, {
				copyEnemy("Common", firstWaveCount, {
					SlimeVariant = "Green",
					HealthMultiplier = 0.92,
					DamageMultiplier = 0.78,
					SpeedMultiplier = 0.94,
				}),
			}, true, partySize),
			wave(0.70, {
				copyEnemy("Common", secondWaveCount, {
					SlimeVariant = "Green",
					HealthMultiplier = 1.00,
					DamageMultiplier = 0.86,
					SpeedMultiplier = 0.96,
				}),
			}, true, partySize),
		},
	}
end

PROFILE_BUILDERS.SkyAmbush = function(target, partySize)
	-- Uma emboscada deve parecer um único evento, não duas waves tradicionais.
	-- Todos os atacantes são criados escondidos. O delay cresce com o Target
	-- para o último spawn também estar oculto antes da revelação.
	target = math.max(1, math.floor(tonumber(target) or 5))

	local revealDelay = math.clamp(
		0.75 + target * 0.16,
		1.45,
		2.60
	)

	return {
		Mode = "Waves",
		Mechanic = "HiddenPerimeterAmbush",
		AmbushRevealDelaySeconds = revealDelay,
		MaxAlive = target,
		SpawnFromPerimeter = true,
		Waves = {
			wave(0.15, {
				copyEnemy("Common", target, {
					SlimeVariant = "Green",
					HealthMultiplier = 0.95,
					DamageMultiplier = 0.82,
					SpeedMultiplier = 1.04,
				}),
			}, false, partySize),
		},
	}
end

PROFILE_BUILDERS.RangedThreat = function(target, partySize)
	-- Introdução controlada ao inimigo à distância.
	-- Sempre cria exatamente Target atiradores e nunca mistura Common/Guard.
	target = math.max(1, math.floor(tonumber(target) or 3))

	local firstWaveCount
	if partySize <= 1 then
		-- Solo: 2 + 1 para ensinar o telegraph sem três projéteis simultâneos.
		firstWaveCount = math.min(2, target)
	else
		-- Party: aproximadamente metade primeiro, restante depois.
		firstWaveCount = math.max(1, math.ceil(target * 0.55))
	end

	local secondWaveCount = math.max(0, target - firstWaveCount)
	local waves = {
		wave(0.20, {
			copyEnemy("Ranged", firstWaveCount, {
				SlimeVariant = "Blue",
				HealthMultiplier = 0.92,
				DamageMultiplier = 0.72,
				SpeedMultiplier = 0.88,
			}),
		}, true, partySize),
	}

	if secondWaveCount > 0 then
		table.insert(waves, wave(0.75, {
			copyEnemy("Ranged", secondWaveCount, {
				SlimeVariant = "Blue",
				HealthMultiplier = 1.00,
				DamageMultiplier = 0.80,
				SpeedMultiplier = 0.90,
			}),
		}, true, partySize))
	end

	return {
		Mode = "Waves",
		Mechanic = "PriorityRangedTargets",
		MaxAlive = math.max(firstWaveCount, secondWaveCount, 1),
		Waves = waves,
	}
end

PROFILE_BUILDERS.NestPair = function(target, partySize)
	-- Primeira introdução aos spawners: dois alvos claros e pouca distração.
	-- NestCount permanece exatamente igual ao Target do objetivo.
	target = math.max(1, math.floor(tonumber(target) or 2))

	return {
		Mode = "Nests",
		Mechanic = "DestroySpawners",
		NestCount = target,

		-- Menos HP na primeira aparição da mecânica. PartyScaling ainda aplica
		-- o ajuste cooperativo depois deste valor-base.
		NestHealth = PartyScalingService.ScaleNestHealth(
			55 + partySize * 10,
			partySize
		),

		-- Dá tempo para o jogador identificar/atacar os ninhos antes do primeiro
		-- spawn. Também reduz o risco de lotar a ilha enquanto aprende a regra.
		NestSpawnInterval = PartyScalingService.ScaleNestSpawnInterval(
			10.5,
			partySize
		),

		NestMonsterRole = "Common",
		NestMonsterVariant = "Green",

		-- Os minions são ameaça secundária; não devem dominar a primeira
		-- experiência de destruir spawners.
		MaxAlive = maxAlive(2 + partySize, partySize, 2, 5),

		-- Um único slime inicial mantém pressão sem esconder o objetivo real.
		OpeningWave = {
			copyEnemy("Common", 1, {
				SlimeVariant = "Green",
				HealthMultiplier = 0.90,
				DamageMultiplier = 0.75,
				SpeedMultiplier = 0.92,
			}),
		},
	}
end

PROFILE_BUILDERS.RewardWave02 = function(target, partySize)
	-- Segunda Reward Battle: reutiliza apenas inimigos já ensinados.
	-- Guard fica reservado para BreakTheGuard, a próxima introdução mecânica.
	target = math.max(2, math.floor(tonumber(target) or 7))

	local firstWaveCount = math.ceil(target * 0.57)
	local secondWaveCount = math.max(1, target - firstWaveCount)

	-- A segunda onda mistura um pequeno número de Ranged com Common.
	local rangedSecond = math.clamp(
		math.floor(secondWaveCount * 0.34 + 0.5),
		1,
		math.max(1, secondWaveCount - 1)
	)
	local commonSecond = math.max(0, secondWaveCount - rangedSecond)

	local secondEnemies = {}
	if commonSecond > 0 then
		table.insert(secondEnemies, copyEnemy("Common", commonSecond, {
			SlimeVariant = "Green",
			HealthMultiplier = 1.00,
			DamageMultiplier = 0.90,
			SpeedMultiplier = 0.98,
		}))
	end
	if rangedSecond > 0 then
		table.insert(secondEnemies, copyEnemy("Ranged", rangedSecond, {
			SlimeVariant = "Blue",
			HealthMultiplier = 0.96,
			DamageMultiplier = 0.82,
			SpeedMultiplier = 0.90,
		}))
	end

	return {
		Mode = "Waves",
		Mechanic = "EscalatingRewardWaves",
		MaxAlive = math.max(firstWaveCount, secondWaveCount),
		Waves = {
			wave(0.20, {
				copyEnemy("Common", firstWaveCount, {
					SlimeVariant = "Green",
					HealthMultiplier = 0.96,
					DamageMultiplier = 0.84,
					SpeedMultiplier = 0.96,
				}),
			}, true, partySize),
			wave(0.75, secondEnemies, true, partySize),
		},
	}
end

PROFILE_BUILDERS.GuardLine = function(target, partySize)
	-- Primeira introdução ao Guard:
	-- 1) quebrar exatamente 2 cristais;
	-- 2) derrotar exatamente Target Guards.
	target = math.max(1, math.floor(tonumber(target) or 2))

	local waveCount = partySize >= 3 and 2 or 1
	local amounts = distribute(target, waveCount)
	local waves = {}

	for index, amount in ipairs(amounts) do
		table.insert(waves, wave(index == 1 and 0.20 or 0.75, {
			copyEnemy("Guard", amount, {
				SlimeVariant = "Green",
				HealthMultiplier = partySize == 1 and 1.05 or 1.18,
				DamageMultiplier = partySize == 1 and 0.72 or 0.82,
				SpeedMultiplier = 0.94,
			}),
		}, true, partySize))
	end

	return {
		Mode = "Waves",
		Mechanic = "BreakWardsThenGuards",

		-- Dois cristais em qualquer tamanho de party: a mecânica continua
		-- simples de entender e o scaling fica nos Guards.
		GuardWardCount = 2,
		GuardWardHealth = 45 + partySize * 10,

		-- A quantidade de Guards é baixa nesta introdução; permitir todos os
		-- alvos da wave evita spawn pendente enquanto o jogador aprende a regra.
		MaxAlive = target,
		Waves = waves,
	}
end

PROFILE_BUILDERS.BeaconDefense = function(_, partySize)
	-- HoldTheBeacon mede tempo real dentro da zona; kills não avançam o objetivo.
	-- A pressão existe para manter a arena viva, mas não deve expulsar o jogador
	-- constantemente da área, especialmente no mobile.
	local openingAmount = partySize == 1 and 1 or math.clamp(partySize, 2, 4)
	local continuousAmount = partySize == 1 and 2 or math.clamp(2 + partySize, 3, 5)

	return {
		Mode = "Beacon",
		Mechanic = "HoldContestedZone",

		-- Um pouco maior que o raio antigo de 13 studs para tolerar esquiva,
		-- knockback e controle touch sem sair da zona por centímetros.
		BeaconRadius = 15,

		MaxAlive = maxAlive(
			partySize == 1 and 4 or 4 + partySize,
			partySize,
			3,
			8
		),

		-- Mais espaço entre reforços. Os 25 segundos continuam inalterados.
		ContinuousInterval = PartyScalingService.ScaleContinuousInterval(
			partySize == 1 and 8.5 or math.max(6.5, 8.5 - partySize * 0.35),
			partySize
		),

		ContinuousWave = mixedWave(
			continuousAmount,
			partySize == 1 and 0.25 or 0.30,
			partySize >= 4 and 1 or 0
		),

		-- Solo começa com apenas um Common para o jogador primeiro identificar
		-- a zona e perceber que ficar dentro dela é a condição de progresso.
		OpeningWave = mixedWave(
			openingAmount,
			partySize == 1 and 0 or 0.20,
			0
		),
	}
end

PROFILE_BUILDERS.NestCluster = function(target, partySize)
	-- Segunda aparição da mecânica de ninhos: mantém três objetivos fixos,
	-- mas aumenta a pressão comparada ao BreakTheNests.
	target = math.max(1, math.floor(tonumber(target) or 3))

	return {
		Mode = "Nests",
		Mechanic = "DestroySpawners",

		-- O catálogo fixa Target = 3 para qualquer party.
		NestCount = target,

		-- Mais resistentes que os dois primeiros ninhos, porém sem virar
		-- uma parede de HP no solo. PartyScaling cuida do cooperativo.
		NestHealth = PartyScalingService.ScaleNestHealth(
			75 + partySize * 14,
			partySize
		),

		-- Pressão maior que BreakTheNests (10.5s), mas ainda com janela
		-- suficiente para focar um ninho antes de a arena lotar.
		NestSpawnInterval = PartyScalingService.ScaleNestSpawnInterval(
			8.0,
			partySize
		),

		NestMonsterRole = "Common",
		NestMonsterVariant = partySize >= 3 and "Red" or "Green",

		-- Mais pressão que a primeira mecânica de ninhos, com teto seguro.
		MaxAlive = maxAlive(
			partySize == 1 and 5 or 4 + partySize,
			partySize,
			4,
			8
		),

		-- Solo começa com dois inimigos: pressão visível, mas o jogador ainda
		-- consegue identificar imediatamente os três ninhos como prioridade.
		OpeningWave = mixedWave(
			partySize == 1 and 2 or math.clamp(partySize + 1, 3, 5),
			partySize == 1 and 0.25 or 0.30,
			0
		),
	}
end

PROFILE_BUILDERS.EliteHunt = function(_, partySize)
	-- MVP determinístico: o objetivo é derrotar o primeiro Elite.
	--
	-- O MonsterSpawner também considera IslandType == "Elite" ao definir
	-- IsElite. Como a rota procedural não fixa a classificação física da ilha
	-- 11, suportes Common poderiam ser promovidos a Elite e confundir a lógica
	-- de escudo/suportes. Nesta primeira versão não usamos essa dependência.
	--
	-- O ObjectiveMechanicService continua usando DefeatSupportsThenElite, mas
	-- EliteSupportCount = 0 faz o Elite nascer imediatamente vulnerável e
	-- marcado como prioridade, sem alterar o HUD/contexto já existente.
	return {
		Mode = "Waves",
		Mechanic = "DefeatSupportsThenElite",
		EliteSupportCount = 0,
		MaxAlive = 1,
		Waves = {
			wave(0.35, {
				copyEnemy("Elite", 1, {
					SlimeVariant = partySize >= 3 and "Lightning" or "Red",
					IsElite = true,
					HealthMultiplier = partySize == 1 and 1.12 or 1.18,
					DamageMultiplier = partySize == 1 and 0.82 or 0.88,
					SpeedMultiplier = partySize == 1 and 0.96 or 1.00,
				}),
			}, true, partySize),
		},
	}
end

PROFILE_BUILDERS.FinalRewardWave = function(target, partySize)
	-- Última batalha antes do boss: três ondas previsíveis usando somente
	-- mecânicas já ensinadas (Common, Ranged e Guard).
	--
	-- A soma das três ondas é sempre exatamente Target.
	target = math.max(1, math.floor(tonumber(target) or 8))
	local amounts = distribute(target, 3)
	local waves = {}

	for waveIndex, amount in ipairs(amounts) do
		if amount > 0 then
			local guardCount = 0
			local rangedCount = 0

			-- Onda 1: leitura simples.
			-- Onda 2: introduz Ranged.
			-- Onda 3: combinação final com Guard + Ranged.
			if waveIndex == 2 then
				rangedCount = math.clamp(math.floor(amount * 0.34 + 0.5), 1, amount)
			elseif waveIndex == 3 then
				guardCount = amount >= 2 and 1 or 0
				local remainingAfterGuard = amount - guardCount
				if remainingAfterGuard > 0 then
					rangedCount = math.clamp(
						math.floor(remainingAfterGuard * 0.40 + 0.5),
						1,
						remainingAfterGuard
					)
				end
			end

			local commonCount = math.max(0, amount - guardCount - rangedCount)
			local enemies = {}

			if commonCount > 0 then
				table.insert(enemies, copyEnemy("Common", commonCount, {
					SlimeVariant = "Green",
					HealthMultiplier = waveIndex == 1 and 0.96 or 1.00,
					DamageMultiplier = waveIndex == 1 and 0.86 or 0.92,
					SpeedMultiplier = 0.98,
				}))
			end

			if rangedCount > 0 then
				table.insert(enemies, copyEnemy("Ranged", rangedCount, {
					SlimeVariant = "Blue",
					HealthMultiplier = 1.00,
					DamageMultiplier = 0.86,
					SpeedMultiplier = 0.92,
				}))
			end

			if guardCount > 0 then
				table.insert(enemies, copyEnemy("Guard", guardCount, {
					SlimeVariant = "Green",
					HealthMultiplier = 1.05,
					DamageMultiplier = 0.82,
					SpeedMultiplier = 0.94,
				}))
			end

			table.insert(
				waves,
				wave(waveIndex == 1 and 0.25 or 0.80, enemies, true, partySize)
			)
		end
	end

	local largestWave = 1
	for _, amount in ipairs(amounts) do
		largestWave = math.max(largestWave, amount)
	end

	return {
		Mode = "Waves",
		Mechanic = "EscalatingRewardWaves",
		MaxAlive = largestWave,
		Waves = waves,
	}
end

function EncounterCatalog.Build(definition, partySize, remainingTarget)
	assert(type(definition) == "table", "EncounterCatalog.Build requer definicao")
	partySize = math.clamp(math.floor(tonumber(partySize) or 1), 1, 4)
	local target = math.max(1, math.floor(tonumber(remainingTarget or definition.Target) or 1))
	local profileName = tostring(definition.SpawnProfile or "")
	local builder = PROFILE_BUILDERS[profileName]
	assert(builder, "SpawnProfile desconhecido: " .. profileName)
	local plan = builder(target, partySize)
	local balance = PartyScalingService.GetEncounterMultipliers(partySize)
	plan.ProfileName = profileName
	plan.ObjectiveId = definition.Id
	plan.GlobalIslandIndex = definition.GlobalIslandIndex
	plan.RoundIndex = definition.RoundIndex
	plan.PartySize = partySize
	plan.RequiredProgressTarget = target
	plan.Mechanic = tostring(plan.Mechanic or definition.GameplayIdentity or "StandardCombat")
	plan.MaxAlive = math.max(1, math.floor(tonumber(plan.MaxAlive) or 6))
	plan.PartyBalanceVersion = 2
	plan.Balance = balance

	workspace:SetAttribute("DungeonPartyBalanceVersion", 2)
	workspace:SetAttribute("DungeonEncounterBalancedPartySize", partySize)
	workspace:SetAttribute("DungeonEnemyHealthMultiplier", balance.Health)
	workspace:SetAttribute("DungeonEnemyDamageMultiplier", balance.Damage)
	workspace:SetAttribute("DungeonEncounterMaxAliveMultiplier", balance.MaxAlive)
	workspace:SetAttribute("DungeonEncounterWaveDelayMultiplier", balance.WaveDelay)
	workspace:SetAttribute("DungeonEncounterNestHealthMultiplier", balance.NestHealth)
	workspace:SetAttribute("DungeonEncounterNestIntervalMultiplier", balance.NestSpawnInterval)
	return plan
end

function EncounterCatalog.Validate()
	for _, profileName in ipairs({
		"FirstStrike",
		"CommonWave",
		"RewardWave01",
		"SkyAmbush",
		"RangedThreat",
		"NestPair",
		"RewardWave02",
		"GuardLine",
		"BeaconDefense",
		"NestCluster",
		"EliteHunt",
		"FinalRewardWave",
	}) do
		assert(type(PROFILE_BUILDERS[profileName]) == "function", "Perfil ausente: " .. profileName)
	end
	return true
end

EncounterCatalog.Validate()

return table.freeze(EncounterCatalog)
