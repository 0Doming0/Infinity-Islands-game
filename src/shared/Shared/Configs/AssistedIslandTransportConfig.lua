-- Configuracao do avanco assistido entre ilhas.

local Config = {}

Config.Version = "AssistedIslandEarlyLearningV6"
Config.Enabled = true

-- Cada indice de ilha pode iniciar apenas este numero de voos automaticos
-- durante a sessao. Novos level ups na mesma ilha mostram somente a seta.
Config.AutomaticFlightsPerSourceIsland = 1
Config.GuidanceIndicatorEnabled = true

-- O voo automatico e uma ajuda de aprendizado, nao um atalho permanente.
-- Somente nas primeiras ilhas, depois de o jogador ter tempo para entender
-- que subir de nivel libera o caminho, o jogo o leva para a proxima arena.
Config.EarlyIslandAutomaticTransportMaxIndex = 5
Config.EarlyIslandIdleSeconds = 35

-- O aviso comeca no level up e o voo so pode iniciar ao final deste prazo.
Config.LevelUpDelaySeconds = 8
Config.FlightDurationSeconds = 2
Config.LandingCountdownSeconds = 3
Config.ReleaseProtectionSeconds = 0.25
-- Nao precisa de cooldown adicional: um novo transporte exige outro level up
-- e ja possui seu proprio aviso de 8 segundos.
Config.CooldownSeconds = 0
Config.DestinationReadyTimeoutSeconds = 5
Config.EligibilityPollSeconds = 0.2

-- Mantem o loop limpar arena -> avancar. O contador pode acontecer durante o
-- combate, mas o voo espera a conclusao da ilha caso ainda existam inimigos.
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
-- Se os Parts de entrada/saida ainda nao tiverem sido replicados, a seta
-- continua visivel e aponta diretamente para a posicao da proxima ilha.
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
	assert(Config.EarlyIslandAutomaticTransportMaxIndex >= 1, "Limite de ilhas iniciais invalido")
	assert(Config.EarlyIslandIdleSeconds >= 0, "EarlyIslandIdleSeconds precisa ser >= 0")
	assert(Config.LevelUpDelaySeconds >= 0, "LevelUpDelaySeconds precisa ser >= 0")
	assert(Config.FlightDurationSeconds > 0, "FlightDurationSeconds precisa ser > 0")
	assert(Config.LandingCountdownSeconds >= 0, "LandingCountdownSeconds precisa ser >= 0")
	assert(Config.MaximumArcHeightStuds >= Config.MinimumArcHeightStuds, "Altura maxima do arco invalida")
	return true
end

return table.freeze(Config)
