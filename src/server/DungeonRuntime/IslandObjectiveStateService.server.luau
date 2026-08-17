-- Envia o objetivo da ilha diretamente ao HUD do jogador. Isso evita que a UI
-- dependa de Models/atributos do Workspace que podem chegar depois ao cliente.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local MonsterSpawner = require(ServerScriptService.BlockParkour:WaitForChild("MonsterSpawner"))

local stateEvent = RemoteRegistry.Get("Dungeon", "IslandObjectiveState", "RemoteEvent")
local stateRequest = RemoteRegistry.Get("Dungeon", "IslandObjectiveStateRequest", "RemoteFunction")
local signatures = setmetatable({}, { __mode = "k" })

local function cleanIndex(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function snapshotForPlayer(player)
	local islandIndex = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
	if islandIndex <= 0 then
		return { Version = "IslandObjectiveStateV1", Ready = false, IslandIndex = 0, Cleared = false, Variants = {} }
	end

	return MonsterSpawner.GetObjectiveState(islandIndex)
		or { Version = "IslandObjectiveStateV1", Ready = false, IslandIndex = islandIndex, Cleared = false, Variants = {} }
end

local function signatureOf(state)
	local parts = { tostring(state.IslandIndex), tostring(state.Ready), tostring(state.Cleared) }
	for _, entry in ipairs(state.Variants or {}) do
		table.insert(parts, string.format("%s:%s:%s", tostring(entry.Variant), tostring(entry.Initial), tostring(entry.Remaining)))
	end
	return table.concat(parts, "|")
end

local function publishIfChanged(player, force)
	if player.Parent ~= Players then return end
	local state = snapshotForPlayer(player)
	local signature = signatureOf(state)
	if force or signatures[player] ~= signature then
		signatures[player] = signature
		stateEvent:FireClient(player, state)
	end
end

stateRequest.OnServerInvoke = function(player)
	local state = snapshotForPlayer(player)
	signatures[player] = signatureOf(state)
	return state
end

local function bindPlayer(player)
	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		task.defer(publishIfChanged, player, true)
	end)
	publishIfChanged(player, true)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	signatures[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

local elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.15 then return end
	elapsed = 0
	for _, player in ipairs(Players:GetPlayers()) do
		publishIfChanged(player, false)
	end
end)
