-- Ranking global de BestScore. Atualizacoes sao limitadas a morte/saida e o
-- resultado de leitura fica em cache para respeitar o orcamento do DataStore.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))

local STORE_NAME = "SkyDungeonGlobalBestScore_V1"
local store = DataStoreService:GetOrderedDataStore(STORE_NAME)
local cache = { ExpiresAt = 0, Entries = {} }
local publishedBest = setmetatable({}, { __mode = "k" })

local remote = ReplicatedStorage:FindFirstChild("GlobalLeaderboardRequest")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "GlobalLeaderboardRequest"
	remote.Parent = ReplicatedStorage
end

ScoreService.Start()

local function publishPlayer(player)
	local bestScore = ScoreService.GetBestScore(player)
	if bestScore <= 0 or bestScore <= (publishedBest[player] or 0) then
		return
	end
	local success, err = pcall(function()
		store:UpdateAsync(tostring(player.UserId), function(previous)
			return math.max(math.floor(tonumber(previous) or 0), bestScore)
		end)
	end)
	if not success then
		warn("[GlobalLeaderboard] Falha ao publicar " .. player.Name .. ": " .. tostring(err))
	else
		publishedBest[player] = bestScore
		cache.ExpiresAt = 0
	end
end

local function resolveName(userId)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.DisplayName, online.Name
	end
	local success, username = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return success and username or ("Jogador " .. tostring(userId)), success and username or tostring(userId)
end

local function readLeaderboard()
	if os.clock() < cache.ExpiresAt then
		return cache.Entries
	end
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, MVPConfig.Progression.GlobalLeaderboardSize)
	end)
	if not success then
		warn("[GlobalLeaderboard] Leitura falhou: " .. tostring(pages))
		return cache.Entries
	end

	local entries = {}
	for rank, row in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(row.key)
		if userId then
			local displayName, username = resolveName(userId)
			table.insert(entries, {
				Rank = rank,
				UserId = userId,
				DisplayName = displayName,
				Username = username,
				BestScore = math.max(0, math.floor(tonumber(row.value) or 0)),
			})
		end
	end
	cache.Entries = entries
	cache.ExpiresAt = os.clock() + MVPConfig.Progression.GlobalLeaderboardRefreshSeconds
	return entries
end

remote.OnServerInvoke = function(player)
	return {
		Entries = readLeaderboard(),
		PersonalBest = ScoreService.GetBestScore(player),
		UpdatedAt = os.time(),
	}
end

local function bindPlayer(player)
	local function bindCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				task.delay(0.15, publishPlayer, player)
			end)
		end
	end
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	publishPlayer(player)
	publishedBest[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		publishPlayer(player)
	end
end)
