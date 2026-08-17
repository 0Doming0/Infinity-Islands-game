-- Configuracao do avanco assistido entre ilhas.

local Config = {}

Config.Version = "AutomaticIslandTransitV7"
Config.Enabled = true

-- O transporte automatico agora e o metodo oficial de transicao entre arenas.
-- Cada ilha pode disparar novamente caso o jogador retorne a ela durante a
-- mesma sessao; o limite alto existe apenas como protecao contra loops.
Config.AutomaticFlightsPerSourceIsland = 99
Config.GuidanceIndicatorEnabled = true

-- O transporte vale para toda a rota, nao apenas para as primeiras ilhas.
Config.EarlyIslandAutomaticTransportMaxIndex = 1000000
-- Assim que a arena estiver limpa e o proximo nivel estiver elegivel, a
-- transicao comeca quase imediatamente.
Config.EarlyIslandIdleSeconds = 0.25

-- Pequeno aviso para o jogador perceber que a arena terminou sem interromper o
-- ritmo do combate.
Config.LevelUpDelaySeconds = 1.25
Config.FlightDurationSeconds = 1.35
Config.LandingCountdownSeconds = 0.35
Config.ReleaseProtectionSeconds = 0.25
Config.CooldownSeconds = 0
Config.DestinationReadyTimeoutSeconds = 5
Config.EligibilityPollSeconds = 0.15

-- Mantem o loop limpar arena -> avancar. Nunca transporta enquanto ainda houver
-- inimigos obrigatorios na ilha atual.
Config.RequireCurrentIslandCleared = true

Config.MinimumArcHeightStuds = 24
Config.MaximumArcHeightStuds = 70
Config.ArcHeightPerHorizontalStud = 0.22
Config.LateralCurvePerHorizontalStud = 0.1
Config.MaximumLateralCurveStuds = 24
Config.SafeSpawnHeightStuds = 3

Config.CameraBlendSpeed = 3.6
Config.CameraDistanceStuds = 22
Config.CameraHeightStuds = 12
Config.CameraFieldOfView = 74

Config.GuidancePulseSpeed = 4.6
Config.GuidancePulseAmount = 0.08
Config.GuidanceBobStuds = 0.45
Config.GuidanceHeightStuds = 6.5
Config.GuidanceWaypointArrivalRadiusStuds = 8
Config.GuidanceArrowScale = 1.35
Config.GuidanceFallbackToDestination = true

-- Um Sound chamado AssistedTransportWhistle em ReplicatedStorage tem
-- prioridade. Este som interno e apenas o fallback para Studio.
Config.ReleaseWhistleSoundId = "rbxasset://sounds/electronicpingshort.wav"
Config.ReleaseWhistleVolume = 0.8
Config.ReleaseWhistlePlaybackSpeed = 1.25

function Config.Validate()
	assert(
		Config.AutomaticFlightsPerSourceIsland >= 1,
		"AutomaticFlightsPerSourceIsland precisa ser >= 1"
	)
	assert(Config.EarlyIslandAutomaticTransportMaxIndex >= 1, "Limite de ilhas automaticas invalido")
	assert(Config.EarlyIslandIdleSeconds >= 0, "EarlyIslandIdleSeconds precisa ser >= 0")
	assert(Config.LevelUpDelaySeconds >= 0, "LevelUpDelaySeconds precisa ser >= 0")
	assert(Config.FlightDurationSeconds > 0, "FlightDurationSeconds precisa ser > 0")
	assert(Config.LandingCountdownSeconds >= 0, "LandingCountdownSeconds precisa ser >= 0")
	assert(Config.MaximumArcHeightStuds >= Config.MinimumArcHeightStuds, "Altura maxima do arco invalida")
	return true
end

return table.freeze(Config)
