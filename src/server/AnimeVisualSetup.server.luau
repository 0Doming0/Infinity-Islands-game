-- ServerScriptService/AnimeVisualSetup.server.lua
-- Configuração visual estilizada/anime para todo o jogo.

local Lighting = game:GetService("Lighting")

local EFFECT_FOLDER_NAME = "AnimeVisualEffects"

local function getOrCreateFolder(): Folder
	local existing = Lighting:FindFirstChild(EFFECT_FOLDER_NAME)

	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = EFFECT_FOLDER_NAME
	folder.Parent = Lighting

	return folder
end

local function replaceEffect(
	parent: Instance,
	className: string,
	name: string
): Instance
	local existing = parent:FindFirstChild(name)

	if existing then
		existing:Destroy()
	end

	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = parent

	return effect
end

local effectsFolder = getOrCreateFolder()

-- Iluminação global.
Lighting.GlobalShadows = true
Lighting.Brightness = 2
Lighting.ExposureCompensation = 0.05
Lighting.ShadowSoftness = 0.35

-- Luz ambiente levemente colorida.
Lighting.Ambient = Color3.fromRGB(105, 105, 125)
Lighting.OutdoorAmbient = Color3.fromRGB(145, 150, 175)

-- Reduz reflexos realistas para deixar os materiais mais chapados.
Lighting.EnvironmentDiffuseScale = 0.55
Lighting.EnvironmentSpecularScale = 0.2

-- Correção de cores: aumenta contraste e saturação.
local colorCorrection = replaceEffect(
	effectsFolder,
	"ColorCorrectionEffect",
	"AnimeColorCorrection"
) :: ColorCorrectionEffect

colorCorrection.Enabled = true
colorCorrection.Brightness = 0.015
colorCorrection.Contrast = 0.12
colorCorrection.Saturation = 0.18
colorCorrection.TintColor = Color3.fromRGB(255, 248, 240)

-- Bloom muito leve.
local bloom = replaceEffect(
	effectsFolder,
	"BloomEffect",
	"AnimeBloom"
) :: BloomEffect

bloom.Enabled = true
bloom.Intensity = 0.12
bloom.Size = 18
bloom.Threshold = 1.5

-- Raios solares discretos.
local sunRays = replaceEffect(
	effectsFolder,
	"SunRaysEffect",
	"AnimeSunRays"
) :: SunRaysEffect

sunRays.Enabled = true
sunRays.Intensity = 0.035
sunRays.Spread = 0.7

-- Atmosfera estilizada.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

atmosphere.Name = "AnimeAtmosphere"
atmosphere.Density = 0.2
atmosphere.Offset = 0.05
atmosphere.Color = Color3.fromRGB(205, 225, 255)
atmosphere.Decay = Color3.fromRGB(115, 125, 160)
atmosphere.Glare = 0.05
atmosphere.Haze = 0.8

print("[AnimeVisualSetup] Visual estilizado configurado.")