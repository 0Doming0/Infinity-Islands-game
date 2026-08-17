-- Configuracao do avanco assistido entre ilhas.

local Config = {}

Config.Version = "ManualAdvanceIslandTransitV8"

-- O servico automatico legado fica desligado. ManualIslandAdvance.server.luau
-- passa a ser a autoridade do avanco normal entre arenas: limpa a missao,
-- aparece AVANCAR, o jogador confirma e entao o transporte automatico inicia.
Config.Enabled = false
Config.ManualAdvanceEnabled = true

Config.AutomaticFlightsPerSourceIsland = 99
Config.GuidanceIndicatorEnabled = true
Config.EarlyIslandAutomaticTransportMaxIndex = 1000000
Config.EarlyIslandIdleSeconds = 0.25

-- Depois que o jogador toca em AVANCAR, usamos apenas um aviso curto antes do voo.
Config.LevelUpDelaySeconds = 0.45
Config.FlightDurationSeconds = 1.35
Config.LandingCountdownSeconds = 0.35
Config.ReleaseProtectionSeconds = 0.25
Config.CooldownSeconds = 0
Config.DestinationReadyTimeoutSeconds = 5
Config.EligibilityPollSeconds = 0.15
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

Config.ReleaseWhistleSoundId = "rbxasset://sounds/electronicpingshort.wav"
Config.ReleaseWhistleVolume = 0.8
Config.ReleaseWhistlePlaybackSpeed = 1.25

function Config.Validate()
	assert(Config.AutomaticFlightsPerSourceIsland >= 1, "AutomaticFlightsPerSourceIsland precisa ser >= 1")
	assert(Config.EarlyIslandAutomaticTransportMaxIndex >= 1, "Limite de ilhas automaticas invalido")
	assert(Config.EarlyIslandIdleSeconds >= 0, "EarlyIslandIdleSeconds precisa ser >= 0")
	assert(Config.LevelUpDelaySeconds >= 0, "LevelUpDelaySeconds precisa ser >= 0")
	assert(Config.FlightDurationSeconds > 0, "FlightDurationSeconds precisa ser > 0")
	assert(Config.LandingCountdownSeconds >= 0, "LandingCountdownSeconds precisa ser >= 0")
	assert(Config.MaximumArcHeightStuds >= Config.MinimumArcHeightStuds, "Altura maxima do arco invalida")
	return true
end

return table.freeze(Config)
