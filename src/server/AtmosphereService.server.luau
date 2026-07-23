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

local furyColor = Lighting:FindFirstChild("SkyDungeonWildFuryColor") or Instance.new("ColorCorrectionEffect")
furyColor.Name = "SkyDungeonWildFuryColor"
furyColor.Brightness = 0
furyColor.Contrast = 0
furyColor.Saturation = 0
furyColor.TintColor = Color3.new(1, 1, 1)
furyColor.Parent = Lighting

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

local musicContainer = folder:FindFirstChild(MVPConfig.Atmosphere.AmbientMusicName)
if not musicContainer then
	musicContainer = Instance.new("Folder")
	musicContainer.Name = MVPConfig.Atmosphere.AmbientMusicName
	musicContainer.Parent = folder
	for index = 1, 2 do
		local placeholder = Instance.new("Sound")
		placeholder.Name = string.format("Track%02d", index)
		placeholder.Volume = 0.30
		placeholder:SetAttribute("PrototypeAsset", true)
		placeholder.Parent = musicContainer
	end
	warn("[Atmosphere] Adicione Sounds licenciados em ServerStorage/MVPAssets/Atmosphere/AmbientMusic.")
end

local function getAmbientTracks()
	local tracks = {}
	-- Compatibilidade com o formato antigo: AmbientMusic podia ser um unico Sound.
	if musicContainer:IsA("Sound") then
		if musicContainer.SoundId ~= "" then
			table.insert(tracks, musicContainer)
		end
	elseif musicContainer:IsA("Folder") then
		for _, child in ipairs(musicContainer:GetChildren()) do
			if child:IsA("Sound") and child.SoundId ~= "" then
				table.insert(tracks, child)
			end
		end
	end
	table.sort(tracks, function(left, right)
		return left.Name < right.Name
	end)
	return tracks
end

for _, child in ipairs(SoundService:GetChildren()) do
	if child:IsA("Sound")
		and (child.Name == "SkyDungeonAmbientMusic"
			or child.Name == "SkyDungeonForestLoop"
			or string.find(child.Name, "SkyDungeonAmbient_", 1, true) == 1
			or string.find(child.Name, "SkyDungeonBird_", 1, true) == 1)
	then
		child:Destroy()
	end
end

local function isDangerousWorldEvent()
	return workspace:GetAttribute("ActiveWorldEvent") == "RisingTide"
		or workspace:GetAttribute("ActiveWorldEvent") == "MonsterHunt"
		or workspace:GetAttribute("ActiveWorldEvent") == "WildFury"
end

local ambientMusic
local ambientDangerous = isDangerousWorldEvent()
local lastTrack
local random = Random.new()

local musicGroup = SoundService:FindFirstChild("SkyDungeonMusic")
if musicGroup and not musicGroup:IsA("SoundGroup") then
	musicGroup:Destroy()
	musicGroup = nil
end
if not musicGroup then
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "SkyDungeonMusic"
	musicGroup.Parent = SoundService
end

local forestContainer = folder:FindFirstChild(MVPConfig.Atmosphere.ForestAmbienceName)
if not forestContainer then
	forestContainer = Instance.new("Folder")
	forestContainer.Name = MVPConfig.Atmosphere.ForestAmbienceName
	forestContainer.Parent = folder

	local forestPlaceholder = Instance.new("Sound")
	forestPlaceholder.Name = MVPConfig.Atmosphere.ForestLoopName
	forestPlaceholder.Volume = 0.18
	forestPlaceholder:SetAttribute("PrototypeAsset", true)
	forestPlaceholder.Parent = forestContainer

	local birdFolder = Instance.new("Folder")
	birdFolder.Name = MVPConfig.Atmosphere.BirdCallsFolderName
	birdFolder.Parent = forestContainer
	for index = 1, 3 do
		local birdPlaceholder = Instance.new("Sound")
		birdPlaceholder.Name = string.format("Bird%02d", index)
		birdPlaceholder.Volume = 0.22
		birdPlaceholder:SetAttribute("PrototypeAsset", true)
		birdPlaceholder.Parent = birdFolder
	end
	warn("[Atmosphere] Adicione ForestLoop e sons de passaros em MVPAssets/Atmosphere/ForestAmbience.")
end

local natureGroup = SoundService:FindFirstChild("SkyDungeonNature")
if natureGroup and not natureGroup:IsA("SoundGroup") then
	natureGroup:Destroy()
	natureGroup = nil
end
if not natureGroup then
	natureGroup = Instance.new("SoundGroup")
	natureGroup.Name = "SkyDungeonNature"
	natureGroup.Parent = SoundService
end

local function targetNatureVolume()
	local master = math.clamp(tonumber(MVPConfig.Atmosphere.ForestMasterVolume) or 1, 0, 1)
	if ambientDangerous then
		return master * math.clamp(
			tonumber(MVPConfig.Atmosphere.ForestDangerVolumeMultiplier) or 0.55,
			0,
			1
		)
	end
	return master
end

local function tweenNatureVolume(duration)
	TweenService:Create(natureGroup, TweenInfo.new(duration), {
		Volume = targetNatureVolume(),
	}):Play()
end

local function startForestLoop()
	if not MVPConfig.Atmosphere.ForestAmbienceEnabled or not forestContainer:IsA("Folder") then
		return
	end
	local template = forestContainer:FindFirstChild(MVPConfig.Atmosphere.ForestLoopName)
	if not template or not template:IsA("Sound") or template.SoundId == "" then
		return
	end
	local sound = template:Clone()
	sound.Name = "SkyDungeonForestLoop"
	sound.Looped = true
	sound.SoundGroup = natureGroup
	sound.Parent = SoundService
	sound:Play()
end

local function getBirdTemplates()
	local templates = {}
	if not forestContainer:IsA("Folder") then
		return templates
	end
	local birdFolder = forestContainer:FindFirstChild(MVPConfig.Atmosphere.BirdCallsFolderName)
	if not birdFolder or not birdFolder:IsA("Folder") then
		return templates
	end
	for _, child in ipairs(birdFolder:GetChildren()) do
		if child:IsA("Sound") and child.SoundId ~= "" then
			table.insert(templates, child)
		end
	end
	table.sort(templates, function(left, right)
		return left.Name < right.Name
	end)
	return templates
end

local lastBirdTemplate
local function playRandomBirdCall()
	local templates = getBirdTemplates()
	if #templates == 0 then
		return
	end
	local template = templates[random:NextInteger(1, #templates)]
	if #templates > 1 and template == lastBirdTemplate then
		local currentIndex = table.find(templates, template) or 1
		template = templates[currentIndex % #templates + 1]
	end
	lastBirdTemplate = template

	local sound = template:Clone()
	sound.Name = "SkyDungeonBird_" .. template.Name
	sound.Looped = false
	sound.SoundGroup = natureGroup
	sound.Parent = SoundService
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	sound:Play()
	task.delay(45, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

natureGroup.Volume = 0
startForestLoop()
tweenNatureVolume(MVPConfig.Atmosphere.ForestFadeSeconds)

if MVPConfig.Atmosphere.ForestAmbienceEnabled then
	task.spawn(function()
		while true do
			local minimum = math.max(
				1,
				tonumber(MVPConfig.Atmosphere.BirdCallMinimumIntervalSeconds) or 8
			)
			local maximum = math.max(
				minimum,
				tonumber(MVPConfig.Atmosphere.BirdCallMaximumIntervalSeconds) or minimum
			)
			task.wait(random:NextNumber(minimum, maximum))
			playRandomBirdCall()
		end
	end)
end

local function targetAmbientVolume(sound)
	local baseVolume = tonumber(sound:GetAttribute("BaseVolume")) or 0.30
	return ambientDangerous and baseVolume * 0.4 or baseVolume
end

local function shuffleTracks(tracks)
	for index = #tracks, 2, -1 do
		local other = random:NextInteger(1, index)
		tracks[index], tracks[other] = tracks[other], tracks[index]
	end
	if #tracks > 1 and tracks[1] == lastTrack then
		tracks[1], tracks[2] = tracks[2], tracks[1]
	end
end

local function playAmbientTrack(template)
	if ambientMusic then
		ambientMusic:Destroy()
	end
	local music = template:Clone()
	music.Name = "SkyDungeonAmbient_" .. template.Name
	music.Looped = false
	music:SetAttribute("BaseVolume", math.clamp(template.Volume, 0, 1))
	music.Volume = 0
	music.SoundGroup = musicGroup
	music.Parent = SoundService
	ambientMusic = music

	local finished = false
	local endedConnection = music.Ended:Connect(function()
		finished = true
	end)
	music:Play()
	TweenService:Create(
		music,
		TweenInfo.new(MVPConfig.Atmosphere.AmbientFadeSeconds),
		{ Volume = targetAmbientVolume(music) }
	):Play()

	local startedAt = os.clock()
	while music.Parent and not finished do
		task.wait(0.5)
		-- Um ID sem permissao ou indisponivel nao pode travar toda a playlist.
		if not music.Playing and os.clock() - startedAt >= 10 then
			break
		end
	end
	endedConnection:Disconnect()
	if ambientMusic == music then
		ambientMusic = nil
	end
	music:Destroy()
	return finished
end

task.spawn(function()
	while true do
		local tracks = getAmbientTracks()
		if #tracks == 0 then
			task.wait(MVPConfig.Atmosphere.AmbientRetrySeconds)
		else
			shuffleTracks(tracks)
			for _, template in ipairs(tracks) do
				lastTrack = template
				local endedNormally = playAmbientTrack(template)
				if endedNormally then
					local minimum = math.max(
						0,
						tonumber(MVPConfig.Atmosphere.AmbientSilenceMinimumSeconds) or 0
					)
					local maximum = math.max(
						minimum,
						tonumber(MVPConfig.Atmosphere.AmbientSilenceMaximumSeconds) or minimum
					)
					task.wait(random:NextNumber(minimum, maximum))
				end
			end
		end
	end
end)

local dangerTemplate = folder:FindFirstChild(MVPConfig.Atmosphere.DangerMusicName)
local dangerMusic
if dangerTemplate and dangerTemplate:IsA("Sound") and dangerTemplate.SoundId ~= "" then
	dangerMusic = SoundService:FindFirstChild("SkyDungeonDangerMusic") or dangerTemplate:Clone()
	dangerMusic.Name = "SkyDungeonDangerMusic"
	dangerMusic.Looped = true
	dangerMusic.Volume = 0
	dangerMusic.SoundGroup = musicGroup
	dangerMusic.Parent = SoundService
	if not dangerMusic.Playing then
		dangerMusic:Play()
	end
end

workspace:GetAttributeChangedSignal("ActiveWorldEvent"):Connect(function()
	local dangerous = isDangerousWorldEvent()
	local wildFury = workspace:GetAttribute("ActiveWorldEvent") == "WildFury"
	ambientDangerous = dangerous
	tweenNatureVolume(0.8)
	if ambientMusic then
		TweenService:Create(ambientMusic, TweenInfo.new(0.8), {
			Volume = targetAmbientVolume(ambientMusic),
		}):Play()
	end
	if dangerMusic then
		TweenService:Create(dangerMusic, TweenInfo.new(0.8), { Volume = dangerous and 0.34 or 0 }):Play()
	end
	TweenService:Create(furyColor, TweenInfo.new(0.8), {
		Contrast = wildFury and 0.14 or 0,
		Saturation = wildFury and -0.08 or 0,
		TintColor = wildFury and Color3.fromRGB(255, 172, 172) or Color3.new(1, 1, 1),
	}):Play()
end)
