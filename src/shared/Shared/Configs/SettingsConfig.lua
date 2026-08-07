-- Configuração compartilhada das preferências locais do jogador.
-- O servidor valida e persiste; o cliente aplica somente efeitos locais.

local SettingsConfig = {}

SettingsConfig.DataStoreName = "SkyDungeonUserSettings_V1"
SettingsConfig.DataStoreVersion = 1

SettingsConfig.Defaults = table.freeze({
	MasterVolume = 1.00,
	MusicVolume = 0.70,
	SFXVolume = 1.00,
	ReducedEffects = false,
	DamageNumbers = true,
	ObjectiveHints = true,
	WorldMarkers = true,
	HighContrast = false,
	TextScale = "Normal",
})

SettingsConfig.Order = table.freeze({
	"MasterVolume",
	"MusicVolume",
	"SFXVolume",
	"ReducedEffects",
	"DamageNumbers",
	"ObjectiveHints",
	"WorldMarkers",
	"HighContrast",
	"TextScale",
})

SettingsConfig.TextScaleValues = table.freeze({
	Small = 0.90,
	Normal = 1.00,
	Large = 1.15,
})

local function nearestVolume(value)
	local clean = math.clamp(tonumber(value) or 1, 0, 1)
	local steps = { 0, 0.25, 0.50, 0.75, 1.00 }
	local best = steps[1]
	local bestDistance = math.huge
	for _, candidate in ipairs(steps) do
		local distance = math.abs(clean - candidate)
		if distance < bestDistance then
			best = candidate
			bestDistance = distance
		end
	end
	return best
end

function SettingsConfig.NormalizeValue(key, value)
	if key == "MasterVolume" or key == "MusicVolume" or key == "SFXVolume" then
		return nearestVolume(value)
	elseif key == "ReducedEffects"
		or key == "DamageNumbers"
		or key == "ObjectiveHints"
		or key == "WorldMarkers"
		or key == "HighContrast"
	then
		return value == true
	elseif key == "TextScale" then
		local requested = tostring(value or "Normal")
		return SettingsConfig.TextScaleValues[requested] and requested or "Normal"
	end
	return nil
end

function SettingsConfig.IsKnown(key)
	return SettingsConfig.Defaults[key] ~= nil
end

function SettingsConfig.Sanitize(source)
	local result = {}
	for _, key in ipairs(SettingsConfig.Order) do
		local raw = type(source) == "table" and source[key] or nil
		if raw == nil then
			result[key] = SettingsConfig.Defaults[key]
		else
			local normalized = SettingsConfig.NormalizeValue(key, raw)
			result[key] = normalized == nil and SettingsConfig.Defaults[key] or normalized
		end
	end
	return result
end

function SettingsConfig.CloneDefaults()
	return SettingsConfig.Sanitize(nil)
end

return table.freeze(SettingsConfig)
