--[[
	Infinity Islands - Combat Arrival Safety

	Protecao curta e autoritativa contra dano injusto ao chegar em combate.
	O servico usa ForceField invisivel + guarda de Health para tambem cobrir
	codigo legado que escreve Humanoid.Health diretamente.
]]

local Config = {}

Config.Version = "CombatArrivalSafetyV2_ThreeSecondLanding"
Config.Policy = "ShortArrivalProtection"

Config.InitialSpawnSeconds = 3.0
Config.RespawnSeconds = 2.0
-- Toda entrada progressiva em uma nova ilha recebe 3 segundos de protecao.
Config.NewIslandSeconds = 3.0

Config.MinimumProtectionSeconds = 0.25
Config.MaximumProtectionSeconds = 4.0

-- Impede atravessar para tras/frente repetidamente para farmar imunidade.
Config.NewIslandProtectionOnlyWhenProgressingForward = true

Config.TelemetryWindowSeconds = 90
Config.ForceFieldName = "_DungeonArrivalSafety"
Config.ForceFieldVisible = false

return table.freeze(Config)
