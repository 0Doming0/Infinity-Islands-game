-- Fundo e musica. Assets reais, quando existirem, ficam em
-- ServerStorage/MVPAssets/Atmosphere e substituem os placeholders.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Terrain = workspace.Terrain

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

Lighting.ClockTime = 15.4
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(92, 105, 130)
Lighting.OutdoorAmbient = Color3.fromRGB(128, 143, 167)
Lighting.EnvironmentDiffuseScale = 0.38
Lighting.EnvironmentSpecularScale = 0.52

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Name = "SkyDungeonAtmosphere"
atmosphere.Density = 0.32
atmosphere.Offset = 0.12
atmosphere.Color = Color3.fromRGB(177, 207, 232)
atmosphere.Decay = Color3.fromRGB(87, 101, 139)
atmosphere.Glare = 0.18
atmosphere.Haze = 1.55
atmosphere.Parent = Lighting

local color = Lighting:FindFirstChild("SkyDungeonColor") or Instance.new("ColorCorrectionEffect")
color.Name = "SkyDungeonColor"
color.Brightness = 0.02
color.Contrast = 0.08
color.Saturation = -0.04
color.TintColor = Color3.fromRGB(235, 244, 255)
color.Parent = Lighting

local bloom = Lighting:FindFirstChild("SkyDungeonBloom") or Instance.new("BloomEffect")
bloom.Name = "SkyDungeonBloom"
bloom.Intensity = 0.24
bloom.Size = 20
bloom.Threshold = 1.25
bloom.Parent = Lighting

local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
clouds.Name = "SkyDungeonClouds"
clouds.Cover = 0.38
clouds.Density = 0.34
clouds.Color = Color3.fromRGB(226, 235, 244)
clouds.Parent = Terrain

local assets = ServerStorage:FindFirstChild("MVPAssets") or Instance.new("Folder")
assets.Name = "MVPAssets"
assets.Parent = ServerStorage
local folder = assets:FindFirstChild(MVPConfig.Atmosphere.AssetFolder) or Instance.new("Folder")
folder.Name = MVPConfig.Atmosphere.AssetFolder
folder.Parent = assets

local skyTemplate = folder:FindFirstChild("Sky")
if skyTemplate and skyTemplate:IsA("Sky") then
	local current = Lighting:FindFirstChildOfClass("Sky")
	if current then
		current:Destroy()
	end
	skyTemplate:Clone().Parent = Lighting
end

local musicTemplate = folder:FindFirstChild(MVPConfig.Atmosphere.AmbientMusicName)
if not musicTemplate then
	musicTemplate = Instance.new("Sound")
	musicTemplate.Name = MVPConfig.Atmosphere.AmbientMusicName
	musicTemplate.Looped = true
	musicTemplate.Volume = 0.30
	musicTemplate:SetAttribute("PrototypeAsset", true)
	musicTemplate.Parent = folder
	warn("[Atmosphere] Adicione um Sound licenciado em ServerStorage/MVPAssets/Atmosphere/AmbientMusic.")
end
local ambientMusic
if musicTemplate:IsA("Sound") and musicTemplate.SoundId ~= "" then
	local music = SoundService:FindFirstChild("SkyDungeonAmbientMusic") or musicTemplate:Clone()
	music.Name = "SkyDungeonAmbientMusic"
	music.Looped = true
	music.Parent = SoundService
	if not music.Playing then
		music:Play()
	end
	ambientMusic = music
end

local dangerTemplate = folder:FindFirstChild(MVPConfig.Atmosphere.DangerMusicName)
local dangerMusic
if dangerTemplate and dangerTemplate:IsA("Sound") and dangerTemplate.SoundId ~= "" then
	dangerMusic = SoundService:FindFirstChild("SkyDungeonDangerMusic") or dangerTemplate:Clone()
	dangerMusic.Name = "SkyDungeonDangerMusic"
	dangerMusic.Looped = true
	dangerMusic.Volume = 0
	dangerMusic.Parent = SoundService
	if not dangerMusic.Playing then
		dangerMusic:Play()
	end
end

workspace:GetAttributeChangedSignal("ActiveWorldEvent"):Connect(function()
	local dangerous = workspace:GetAttribute("ActiveWorldEvent") == "RisingTide"
		or workspace:GetAttribute("ActiveWorldEvent") == "MonsterHunt"
	if ambientMusic then
		TweenService:Create(ambientMusic, TweenInfo.new(0.8), { Volume = dangerous and 0.12 or 0.30 }):Play()
	end
	if dangerMusic then
		TweenService:Create(dangerMusic, TweenInfo.new(0.8), { Volume = dangerous and 0.34 or 0 }):Play()
	end
end)
