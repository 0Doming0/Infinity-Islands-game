--[[
	PlayerSpawnSystem.server.lua

	Sistema de spawn aleatorio para o jogo de exploracao nos ceus.
	Apos o novo mundo procedural possuir ilhas ativas, teleporta cada jogador
	para uma das ilhas iniciais mais baixas.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(
	script.Parent:WaitForChild("BlockParkour"):WaitForChild("Config_SkyDungeon_V10")
)

local SPAWN_POSITION_TIMEOUT_SECONDS = 20
local SPAWN_RETRY_INTERVAL_SECONDS = 0.2

local function getGeneratedWorld()
	local generatedWorld = Workspace:FindFirstChild(Config.WORLD_MODEL_NAME)
	if not generatedWorld then
		return nil
	end

	local requiredChunkCount = math.max(
		1,
		math.floor(tonumber(Config.INITIAL_CHUNK_COUNT) or 1)
	)
	local chunkCount = tonumber(generatedWorld:GetAttribute("ChunkCount")) or 0
	local activeChunkCount = tonumber(generatedWorld:GetAttribute("ActiveChunkCount")) or 0
	if chunkCount < requiredChunkCount or activeChunkCount <= 0 then
		return nil
	end

	return generatedWorld
end

local function getSpawnPosition()
	local generatedWorld = getGeneratedWorld()
	if not generatedWorld then
		return nil
	end

	-- As tags novas apontam para Models. O PrimaryPart de cada node e o IslandFloor.
	local validNodes = {}
	local sanctuaryNodes = {}
	for _, node in CollectionService:GetTagged("SkyDungeonIslandNode") do
		if node:IsA("Model") and node:IsDescendantOf(generatedWorld) then
			local floor = node.PrimaryPart
			if floor and floor:IsA("BasePart") and floor.CanCollide then
				local candidate = {
					Node = node,
					Floor = floor,
				}
				table.insert(validNodes, candidate)
				if
					CollectionService:HasTag(node, "SkyDungeonSanctuary")
					or node:GetAttribute("IsSanctuary") == true
				then
					table.insert(sanctuaryNodes, candidate)
				end
			end
		end
	end

	if #validNodes == 0 then
		return nil
	end

	local candidates = #sanctuaryNodes > 0 and sanctuaryNodes or validNodes
	table.sort(candidates, function(a, b)
		if a.Floor.Position.Y ~= b.Floor.Position.Y then
			return a.Floor.Position.Y < b.Floor.Position.Y
		end
		return a.Node:GetFullName() < b.Node:GetFullName()
	end)

	-- Entre as ilhas seguras mais baixas, preserve uma pequena variacao sem
	-- mandar o jogador para uma ilha perigosa distante.
	local safeBand = math.min(#candidates, 3)
	local floor = candidates[math.random(1, safeBand)].Floor

	-- Posicao aleatoria na area central da ilha para evitar as bordas.
	local halfX = floor.Size.X * 0.4
	local halfZ = floor.Size.Z * 0.4
	local offsetX = math.random() * (halfX * 2) - halfX
	local offsetZ = math.random() * (halfZ * 2) - halfZ

	return floor.CFrame:PointToWorldSpace(
		Vector3.new(offsetX, floor.Size.Y * 0.5 + 3, offsetZ)
	)
end

local function spawnPlayer(player, character)
	local position = getSpawnPosition()
	if not position then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(position)
	elseif character:IsA("Model") then
		character:PivotTo(CFrame.new(position))
	end
	player:SetAttribute("InitialSpawnPositioned", true)
	player:SetAttribute("InitialStartState", "Playing")
	player:SetAttribute("RespawnState", "Ready")
	return true
end

local function positionCharacterWhenWorldIsReady(player, character)
	local deadline = os.clock() + SPAWN_POSITION_TIMEOUT_SECONDS
	while player.Parent and character.Parent and os.clock() < deadline do
		if spawnPlayer(player, character) then
			return
		end
		task.wait(SPAWN_RETRY_INTERVAL_SECONDS)
	end

	if player.Parent and character.Parent then
		player:SetAttribute("InitialStartState", "SpawnPositionTimeout")
		warn(string.format(
			"[PlayerSpawnSystem] Nao foi possivel posicionar %s em uma ilha ativa.",
			player.Name
		))
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			-- Pequeno delay para garantir que o character esta totalmente carregado.
			task.wait(0.1)
			positionCharacterWhenWorldIsReady(player, character)
		end)
	end)

	-- Se o character ja existe (caso raro).
	if player.Character then
		task.spawn(positionCharacterWhenWorldIsReady, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
