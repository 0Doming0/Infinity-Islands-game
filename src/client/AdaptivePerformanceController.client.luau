--[[
	Sky Dungeon - desempenho adaptativo local.

	Mede o FPS real com janelas de um segundo e aplica qualidade com histerese:
	0 = Normal, 1 = Reduzido, 2 = Extremo.

	Toda decisao e local. Combate, hitboxes, IA e salvamento nao sao alterados.
	Outros LocalScripts podem ler PerformanceLevel e PerformanceMode no jogador.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local terrain = Workspace.Terrain

local LEVEL_NORMAL = 0
local LEVEL_REDUCED = 1
local LEVEL_EXTREME = 2

local SAMPLE_SECONDS = 1
local MOBILE_WARMUP_SECONDS = 7
local DESKTOP_WARMUP_SECONDS = 5
local REDUCE_BELOW_FPS = 45
local EXTREME_BELOW_FPS = 29
local EXTREME_SUSTAINED_BELOW_FPS = 35
local RECOVER_FROM_EXTREME_FPS = 43
local RECOVER_TO_NORMAL_FPS = 54

local REDUCE_AFTER_SECONDS = 5
local EXTREME_AFTER_SECONDS = 3
local EXTREME_SUSTAINED_AFTER_SECONDS = 8
local RECOVER_FROM_EXTREME_SECONDS = 16
local RECOVER_TO_NORMAL_SECONDS = 20

local LEVEL_NAMES = {
	[LEVEL_NORMAL] = "Normal",
	[LEVEL_REDUCED] = "Reduzido",
	[LEVEL_EXTREME] = "Extremo",
}

local originalEffectEnabled = setmetatable({}, { __mode = "k" })
local originalCloudSettings = setmetatable({}, { __mode = "k" })
local originalGlobalShadows = Lighting.GlobalShadows

local currentLevel = UserInputService.TouchEnabled and LEVEL_REDUCED or LEVEL_NORMAL
local currentReason = UserInputService.TouchEnabled and "InicializacaoMobile" or "Inicializacao"
local startedAt = os.clock()
local frameCount = 0
local sampleElapsed = 0
local smoothedFPS

local belowReducedSeconds = 0
local belowExtremeSeconds = 0
local belowExtremeSustainedSeconds = 0
local aboveReducedSeconds = 0
local aboveNormalSeconds = 0

local function isManagedPostEffect(instance)
	return instance:IsA("BloomEffect")
		or instance:IsA("DepthOfFieldEffect")
		or instance:IsA("SunRaysEffect")
end

local function rememberEffect(instance)
	if originalEffectEnabled[instance] == nil then
		originalEffectEnabled[instance] = instance.Enabled
	end
end

local function applyPostEffect(instance, level)
	if not isManagedPostEffect(instance) then
		return
	end

	rememberEffect(instance)
	local originalEnabled = originalEffectEnabled[instance]

	if level == LEVEL_NORMAL then
		instance.Enabled = originalEnabled
	elseif level == LEVEL_REDUCED then
		instance.Enabled = originalEnabled and instance:IsA("BloomEffect")
	else
		instance.Enabled = false
	end
end

local function rememberTerrainCloud(cloud)
	if originalCloudSettings[cloud] == nil then
		originalCloudSettings[cloud] = {
			Enabled = cloud.Enabled,
			Density = cloud.Density,
			Cover = cloud.Cover,
		}
	end
end

local function applyTerrainCloud(cloud, level)
	if not cloud:IsA("Clouds") then
		return
	end

	rememberTerrainCloud(cloud)
	local original = originalCloudSettings[cloud]

	if level == LEVEL_NORMAL then
		cloud.Enabled = original.Enabled
		cloud.Density = original.Density
		cloud.Cover = original.Cover
	elseif level == LEVEL_REDUCED then
		cloud.Enabled = original.Enabled
		cloud.Density = original.Density * 0.5
		cloud.Cover = original.Cover * 0.75
	else
		cloud.Enabled = false
	end
end

local function publishLevel(level, reason)
	currentLevel = level
	currentReason = reason

	player:SetAttribute("PerformanceLevel", level)
	player:SetAttribute("PerformanceTier", LEVEL_NAMES[level])
	player:SetAttribute("PerformanceMode", level >= LEVEL_REDUCED)
	player:SetAttribute("ExtremePerformanceMode", level >= LEVEL_EXTREME)
	player:SetAttribute("PerformanceAutoReason", reason)
end

local function applyLevel(level, reason)
	level = math.clamp(math.floor(level), LEVEL_NORMAL, LEVEL_EXTREME)

	for _, descendant in ipairs(Lighting:GetDescendants()) do
		applyPostEffect(descendant, level)
	end
	for _, descendant in ipairs(terrain:GetDescendants()) do
		applyTerrainCloud(descendant, level)
	end

	Lighting.GlobalShadows = level < LEVEL_EXTREME and originalGlobalShadows or false
	publishLevel(level, reason)
end

local function resetDecisionTimers()
	belowReducedSeconds = 0
	belowExtremeSeconds = 0
	belowExtremeSustainedSeconds = 0
	aboveReducedSeconds = 0
	aboveNormalSeconds = 0
end

local function isForced()
	return player:GetAttribute("ForcePerformanceMode") == true
end

local function setLevel(level, reason)
	if level == currentLevel and reason == currentReason then
		return
	end
	resetDecisionTimers()
	applyLevel(level, reason)
end

local function updateTimer(condition, current, seconds)
	if condition then
		return current + seconds
	end
	return 0
end

local function evaluateFPS(fps, seconds)
	if isForced() then
		setLevel(LEVEL_EXTREME, "ForcadoPeloJogador")
		return
	end

	local warmupSeconds = UserInputService.TouchEnabled
		and MOBILE_WARMUP_SECONDS
		or DESKTOP_WARMUP_SECONDS
	if os.clock() - startedAt < warmupSeconds then
		return
	end

	belowReducedSeconds = updateTimer(fps < REDUCE_BELOW_FPS, belowReducedSeconds, seconds)
	belowExtremeSeconds = updateTimer(fps < EXTREME_BELOW_FPS, belowExtremeSeconds, seconds)
	belowExtremeSustainedSeconds =
		updateTimer(fps < EXTREME_SUSTAINED_BELOW_FPS, belowExtremeSustainedSeconds, seconds)
	aboveReducedSeconds =
		updateTimer(fps >= RECOVER_FROM_EXTREME_FPS, aboveReducedSeconds, seconds)
	aboveNormalSeconds =
		updateTimer(fps >= RECOVER_TO_NORMAL_FPS, aboveNormalSeconds, seconds)

	if
		belowExtremeSeconds >= EXTREME_AFTER_SECONDS
		or belowExtremeSustainedSeconds >= EXTREME_SUSTAINED_AFTER_SECONDS
	then
		setLevel(LEVEL_EXTREME, "FPSMuitoBaixo")
	elseif currentLevel == LEVEL_NORMAL and belowReducedSeconds >= REDUCE_AFTER_SECONDS then
		setLevel(LEVEL_REDUCED, "FPSBaixo")
	elseif currentLevel == LEVEL_EXTREME and aboveReducedSeconds >= RECOVER_FROM_EXTREME_SECONDS then
		setLevel(LEVEL_REDUCED, "FPSRecuperado")
	elseif currentLevel == LEVEL_REDUCED and aboveNormalSeconds >= RECOVER_TO_NORMAL_SECONDS then
		setLevel(LEVEL_NORMAL, "FPSEstavel")
	end
end

player:GetAttributeChangedSignal("ForcePerformanceMode"):Connect(function()
	if isForced() then
		setLevel(LEVEL_EXTREME, "ForcadoPeloJogador")
	else
		-- Ao voltar para automatico, evita elevar a qualidade antes de uma nova
		-- medicao estavel. O nivel reduzido e um ponto seguro de reavaliacao.
		setLevel(LEVEL_REDUCED, "AutomaticoReavaliando")
	end
end)

Lighting.DescendantAdded:Connect(function(descendant)
	if isManagedPostEffect(descendant) then
		task.defer(function()
			if descendant.Parent then
				applyPostEffect(descendant, currentLevel)
			end
		end)
	end
end)

terrain.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Clouds") then
		task.defer(function()
			if descendant.Parent then
				applyTerrainCloud(descendant, currentLevel)
			end
		end)
	end
end)

if player:GetAttribute("ForcePerformanceMode") == nil then
	player:SetAttribute("ForcePerformanceMode", false)
end

applyLevel(
	isForced() and LEVEL_EXTREME or currentLevel,
	isForced() and "ForcadoPeloJogador" or currentReason
)
player:SetAttribute("MeasuredFPS", 60)
player:SetAttribute("PerformanceControllerReady", true)

RunService.RenderStepped:Connect(function(deltaTime)
	frameCount += 1
	sampleElapsed += deltaTime

	if sampleElapsed < SAMPLE_SECONDS then
		return
	end

	local rawFPS = frameCount / sampleElapsed
	if smoothedFPS == nil then
		smoothedFPS = rawFPS
	else
		smoothedFPS = smoothedFPS * 0.65 + rawFPS * 0.35
	end

	player:SetAttribute("MeasuredFPS", math.floor(smoothedFPS + 0.5))
	evaluateFPS(smoothedFPS, sampleElapsed)

	frameCount = 0
	sampleElapsed = 0
end)
