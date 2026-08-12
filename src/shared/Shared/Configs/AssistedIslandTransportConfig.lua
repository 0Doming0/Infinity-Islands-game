-- Configuracao do avanco assistido entre ilhas.

local Config = {}

Config.Version = "AssistedIslandTransportV1"
Config.Enabled = true

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

-- Um Sound chamado AssistedTransportWhistle em ReplicatedStorage tem
-- prioridade. Este som interno e apenas o fallback para Studio.
Config.ReleaseWhistleSoundId = "rbxasset://sounds/electronicpingshort.wav"
Config.ReleaseWhistleVolume = 0.8
Config.ReleaseWhistlePlaybackSpeed = 1.25

function Config.Validate()
	assert(Config.LevelUpDelaySeconds >= 0, "LevelUpDelaySeconds precisa ser >= 0")
	assert(Config.FlightDurationSeconds > 0, "FlightDurationSeconds precisa ser > 0")
	assert(Config.LandingCountdownSeconds >= 0, "LandingCountdownSeconds precisa ser >= 0")
	assert(Config.MaximumArcHeightStuds >= Config.MinimumArcHeightStuds, "Altura maxima do arco invalida")
	return true
end

return table.freeze(Config)
