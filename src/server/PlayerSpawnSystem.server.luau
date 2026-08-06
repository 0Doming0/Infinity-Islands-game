-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

--[[
	PlayerSpawnSystem.server.luau

	Compatibilidade do fluxo de spawn.

	O WaterRiseSystem e o unico responsavel por escolher uma ilha segura,
	ancorar, posicionar e liberar o personagem. Este script nao teleporta mais
	o jogador: manter dois posicionadores causava corridas entre a ilha inicial
	e a ilha acima da agua.

	Os atributos abaixo sao espelhados somente como defesa para interfaces
	antigas. A autoridade continua sendo RespawnState, publicado pelo servidor.
]]

local Players = game:GetService("Players")

local function synchronizeLifecycle(player)
	local respawnState = player:GetAttribute("RespawnState")
	if respawnState == "Ready" then
		player:SetAttribute("PlayerLifecycleState", "Playing")
		if
			player:GetAttribute("InitialGameStarted") == true
			and player:GetAttribute("InitialSpawnPositioned") ~= true
		then
			player:SetAttribute("InitialSpawnPositioned", true)
			player:SetAttribute("InitialStartState", "Playing")
		end
	elseif respawnState == "Failed" then
		player:SetAttribute("PlayerLifecycleState", "Failed")
		if player:GetAttribute("InitialSpawnPositioned") ~= true then
			player:SetAttribute("InitialStartState", "SpawnFailed")
		end
	end
end

local function onPlayerAdded(player)
	player:GetAttributeChangedSignal("RespawnState"):Connect(function()
		synchronizeLifecycle(player)
	end)
	synchronizeLifecycle(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
