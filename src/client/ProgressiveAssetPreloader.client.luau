--[[
	Sky Dungeon - pre-carregamento progressivo.

	Carrega malhas, texturas, sons e animacoes recorrentes em lotes pequenos.
	Nao bloqueia a entrada do jogador e reduz automaticamente o lote quando o
	aparelho ja esta em modo de desempenho.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MANIFEST_NAME = "SkyDungeonAssetPreloadManifest"
local INITIAL_DELAY_SECONDS = 1.5
local NORMAL_BATCH_SIZE = 5
local REDUCED_BATCH_SIZE = 3
local EXTREME_BATCH_SIZE = 1
local NORMAL_BATCH_PAUSE_SECONDS = 0.08
local REDUCED_BATCH_PAUSE_SECONDS = 0.18
local EXTREME_BATCH_PAUSE_SECONDS = 0.35

local player = Players.LocalPlayer

local function waitForManifest()
	local manifest = ReplicatedStorage:WaitForChild(MANIFEST_NAME, 10)
	if not manifest then
		return nil
	end
	while manifest.Parent and manifest:GetAttribute("Ready") ~= true do
		manifest:GetAttributeChangedSignal("Ready"):Wait()
	end
	return manifest.Parent and manifest or nil
end

local function getPacing()
	local level = tonumber(player:GetAttribute("PerformanceLevel")) or 0
	if level >= 2 then
		return EXTREME_BATCH_SIZE, EXTREME_BATCH_PAUSE_SECONDS
	elseif level >= 1 then
		return REDUCED_BATCH_SIZE, REDUCED_BATCH_PAUSE_SECONDS
	end
	return NORMAL_BATCH_SIZE, NORMAL_BATCH_PAUSE_SECONDS
end

local function readContentIds(manifest)
	local entries = manifest:GetChildren()
	table.sort(entries, function(a, b)
		return a.Name < b.Name
	end)
	local result = {}
	for _, entry in ipairs(entries) do
		if entry:IsA("StringValue") and entry.Value ~= "" then
			table.insert(result, entry.Value)
		end
	end
	return result
end

task.wait(INITIAL_DELAY_SECONDS)
local manifest = waitForManifest()
if not manifest then
	player:SetAttribute("AssetPreloadState", "ManifestUnavailable")
	return
end

local contentIds = readContentIds(manifest)
player:SetAttribute("AssetPreloadState", "Loading")
player:SetAttribute("AssetPreloadTotal", #contentIds)
player:SetAttribute("AssetPreloadCompleted", 0)

local cursor = 1
while cursor <= #contentIds do
	local batchSize, pauseSeconds = getPacing()
	local batch = {}
	for _ = 1, batchSize do
		if cursor > #contentIds then
			break
		end
		table.insert(batch, contentIds[cursor])
		cursor += 1
	end
	local success, errorMessage = pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
	if not success then
		warn("[SkyDungeon] Preload parcial falhou: " .. tostring(errorMessage))
	end
	player:SetAttribute("AssetPreloadCompleted", cursor - 1)
	if cursor <= #contentIds then
		task.wait(pauseSeconds)
		RunService.Heartbeat:Wait()
	end
end

player:SetAttribute("AssetPreloadState", "Complete")
