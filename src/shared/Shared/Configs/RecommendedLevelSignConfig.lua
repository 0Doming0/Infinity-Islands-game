--[[
	Infinity Islands - Recommended Level Sign Config V3

	LevelText recebe SOMENTE O NUMERO.

	Posicionamento:
	- usa GameplayMarkers.Entry como referencia;
	- fica no canto DIREITO para quem vem da ilha inferior;
	- olha para a ilha/rota inferior.
]]

local Config = {}

Config.Version = "RecommendedLevelSignsV3"

Config.TemplateRoot = { "DungeonTemplates", "RecommendedSigns" }
Config.SignName = "RecommendedLevelSign"
Config.LevelTextName = "LevelText"
Config.LevelShadowName = "LevelShadow"

-- Quanto a placa entra na ilha a partir da borda/Entry.
Config.EntryInsetStuds = 4

-- Distancia restante ate a borda lateral direita.
Config.RightCornerMarginStuds = 4

Config.HeightAboveFloorStuds = 0.15

-- SurfaceGui esperado em Face.Front.
Config.YawOffsetDegrees = 0

Config.Families = table.freeze({
	{ Name = "Slimes", MinimumLevel = 1, MaximumLevel = 2 },
	{ Name = "AdvancedSlimes", MinimumLevel = 3, MaximumLevel = 4 },
	{ Name = "Skeletons", MinimumLevel = 5, MaximumLevel = 7 },
	{ Name = "Ogres", MinimumLevel = 8, MaximumLevel = 10 },
	{ Name = "Elementals", MinimumLevel = 11, MaximumLevel = math.huge },
})

function Config.ResolveFamily(level)
	level = math.max(1, math.floor(tonumber(level) or 1))

	for _, definition in ipairs(Config.Families) do
		if level >= definition.MinimumLevel
			and level <= definition.MaximumLevel
		then
			return definition.Name
		end
	end

	return "Slimes"
end

return table.freeze(Config)
