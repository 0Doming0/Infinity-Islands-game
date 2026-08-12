--[[
	Infinity Islands - Recommended Level Sign Config V4

	LevelText recebe SOMENTE O NUMERO.

	Posicionamento:
	- usa GameplayMarkers.Entry como referencia;
	- fica no canto DIREITO para quem vem da ilha inferior;
	- olha para a ilha/rota inferior.

	Familias do MVP:
	- a Ilha Inicial nao recebe placa;
	- todas as ilhas numeradas usam AdvancedSlimes;
	- Skeletons, Ogres e Elementals foram removidos da progressao ativa.
]]

local Config = {}

Config.Version = "RecommendedLevelSignsSlimeOnlyV4"

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
	{ Name = "Slimes", MinimumLevel = 1, MaximumLevel = 1 },
	{ Name = "AdvancedSlimes", MinimumLevel = 2, MaximumLevel = math.huge },
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

function Config.Validate()
	assert(
		#Config.Families == 2,
		"Somente Slimes e AdvancedSlimes podem permanecer ativos"
	)
	assert(
		Config.ResolveFamily(1) == "Slimes",
		"Level 1 precisa usar a placa Slimes"
	)
	assert(
		Config.ResolveFamily(2) == "AdvancedSlimes"
			and Config.ResolveFamily(999) == "AdvancedSlimes",
		"Levels avancados precisam usar somente AdvancedSlimes"
	)

	return true
end

Config.Validate()

return table.freeze(Config)
