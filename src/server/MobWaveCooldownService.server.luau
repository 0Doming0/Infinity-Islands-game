--[[
	Infinity Islands - MobWaveCooldownService V1

	Por que existe:
	O MonsterSpawner legado faz refill imediato quando plan.Alive < MaxAlive.
	Ele so faz isso quando CombatState == "Active".

	Este servico:
	1) deixa a primeira leva nascer normalmente;
	2) ao primeiro mob morto, bloqueia refill individual;
	3) deixa os mobs restantes da leva continuarem vivos/atacando;
	4) quando Alive chega a 0, entra em RespawnCooldown;
	5) espera WaveRespawnCooldownSeconds;
	6) devolve CombatState = Active para o MonsterSpawner gerar a proxima leva.

	Nao altera XP, dano, IA ou RecommendedLevel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("IslandMobSpawnConfig")
)

local records = setmetatable({}, { __mode = "k" })

local function now()
	return workspace:GetServerTimeNow()
end

local function cleanIndex(value)
	local n = tonumber(value)
	if not n then
		return nil
	end

	n = math.floor(n)
	return n >= 1 and n or nil
end

local function isCombatIsland(island)
	return island
		and island:IsA("Model")
		and island:GetAttribute("IsSkyIsland") == true
		and island:GetAttribute("IsSanctuary") ~= true
		and island:GetAttribute("IsRewardIsland") ~= true
		and island:GetAttribute("IsBossSanctuary") ~= true
end

local function islandIndex(island)
	return cleanIndex(
		island:GetAttribute("GlobalIslandIndex")
			or island:GetAttribute("ProgressionIslandIndex")
	)
end

local function occupied(index)
	if not index then
		return false
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if cleanIndex(
			player:GetAttribute("CurrentGlobalIslandIndex")
		) == index
		then
			return true
		end
	end

	return false
end

local function setWaveAttributes(island, record)
	island:SetAttribute(
		"MobWaveRespawnCooldownSeconds",
		Config.WaveRespawnCooldownSeconds
	)
	island:SetAttribute(
		"MobRespawnPolicy",
		"FullWaveAfterCooldown"
	)
	island:SetAttribute(
		"MobIndividualRefillEnabled",
		false
	)
	island:SetAttribute(
		"MobWaveRefillLocked",
		record.RefillLocked == true
	)
	island:SetAttribute(
		"MobWaveCooldownActive",
		record.CooldownActive == true
	)
	island:SetAttribute(
		"MobWaveNumber",
		record.WaveNumber
	)
end

local function desiredBlockedState(record)
	if record.CooldownActive then
		return "RespawnCooldown"
	end

	if record.RefillLocked then
		return "WaveActive"
	end

	return nil
end

local function enforceBlockedState(island, record)
	if record.Enforcing then
		return
	end

	local desired = desiredBlockedState(record)

	if not desired then
		return
	end

	if island:GetAttribute("CombatState") == desired then
		return
	end

	record.Enforcing = true
	island:SetAttribute("CombatState", desired)
	record.Enforcing = false
end

local function finishCooldown(island, record, token)
	if not island.Parent
		or records[island] ~= record
		or record.CooldownToken ~= token
	then
		return
	end

	record.CooldownActive = false
	record.RefillLocked = false
	record.WaveNumber += 1

	island:SetAttribute("MobWaveCooldownEndsAt", nil)
	island:SetAttribute("MobWaveLastRespawnAt", now())

	setWaveAttributes(island, record)

	-- So ativa a nova leva se ainda houver jogador nessa ilha.
	-- Caso contrario, IslandCombatService ativa novamente quando alguem retornar.
	if occupied(record.Index) then
		island:SetAttribute("CombatState", "Active")
	end
end

local function beginCooldown(island, record)
	if record.CooldownActive then
		return
	end

	record.CooldownActive = true
	record.RefillLocked = true
	record.CooldownToken += 1

	local token = record.CooldownToken
	local seconds = math.max(
		1,
		tonumber(Config.WaveRespawnCooldownSeconds) or 4
	)

	island:SetAttribute(
		"MobWaveCooldownStartedAt",
		now()
	)
	island:SetAttribute(
		"MobWaveCooldownEndsAt",
		now() + seconds
	)

	setWaveAttributes(island, record)
	enforceBlockedState(island, record)

	task.delay(seconds, function()
		finishCooldown(island, record, token)
	end)
end

local function onDefeatedChanged(island, record)
	local defeated = math.max(
		0,
		math.floor(
			tonumber(
				island:GetAttribute("MobDefeatedCount")
			) or 0
		)
	)

	if defeated <= record.LastDefeatedCount then
		return
	end

	record.LastDefeatedCount = defeated

	-- Assim que a leva comeca a morrer, bloqueia qualquer refill por vaga.
	-- Os mobs que ainda estao vivos continuam normalmente.
	if not record.CooldownActive then
		record.RefillLocked = true
		setWaveAttributes(island, record)
		enforceBlockedState(island, record)
	end
end

local function onAliveChanged(island, record)
	local alive = math.max(
		0,
		math.floor(
			tonumber(
				island:GetAttribute("MobAliveCount")
					or island:GetAttribute("MobActiveAliveCount")
			) or 0
		)
	)

	local lifetimeSpawned = math.max(
		0,
		math.floor(
			tonumber(
				island:GetAttribute("MobLifetimeSpawnedCount")
					or island:GetAttribute("MobSpawnedCount")
			) or 0
		)
	)

	-- Primeira leva detectada.
	if alive > 0 and lifetimeSpawned > 0 then
		if record.WaveNumber <= 0 then
			record.WaveNumber = 1
		end

		setWaveAttributes(island, record)
		return
	end

	-- So inicia cooldown depois que houve morte nesta leva.
	if alive == 0
		and lifetimeSpawned > 0
		and record.RefillLocked
		and not record.CooldownActive
	then
		beginCooldown(island, record)
	end
end

local function trackIsland(island)
	if records[island] or not isCombatIsland(island) then
		return
	end

	local record = {
		Index = islandIndex(island),
		RefillLocked = false,
		CooldownActive = false,
		CooldownToken = 0,
		WaveNumber = 0,
		LastDefeatedCount = math.max(
			0,
			math.floor(
				tonumber(
					island:GetAttribute("MobDefeatedCount")
				) or 0
			)
		),
		Enforcing = false,
		Connections = {},
	}

	records[island] = record
	setWaveAttributes(island, record)

	table.insert(
		record.Connections,
		island:GetAttributeChangedSignal(
			"MobDefeatedCount"
		):Connect(function()
			onDefeatedChanged(island, record)
		end)
	)

	for _, name in ipairs({
		"MobAliveCount",
		"MobActiveAliveCount",
	}) do
		table.insert(
			record.Connections,
			island:GetAttributeChangedSignal(name):Connect(function()
				onAliveChanged(island, record)
			end)
		)
	end

	table.insert(
		record.Connections,
		island:GetAttributeChangedSignal(
			"CombatState"
		):Connect(function()
			-- IslandCombatService pode republicar "Active".
			-- Enquanto a leva estiver travada/cooldown, trocamos de volta
			-- de forma sincrona antes do task.defer do MonsterSpawner rodar.
			enforceBlockedState(island, record)
		end)
	)

	table.insert(
		record.Connections,
		island.AncestryChanged:Connect(function(_, parent)
			if not parent then
				for _, connection in ipairs(record.Connections) do
					connection:Disconnect()
				end
				records[island] = nil
			end
		end)
	)

	task.defer(function()
		onAliveChanged(island, record)
	end)
end

local function scan()
	for _, instance in ipairs(workspace:GetDescendants()) do
		if isCombatIsland(instance) then
			trackIsland(instance)
		end
	end
end

workspace.DescendantAdded:Connect(function(instance)
	if not instance:IsA("Model") then
		return
	end

	task.defer(function()
		for _ = 1, 20 do
			if not instance.Parent then
				return
			end

			if isCombatIsland(instance) then
				trackIsland(instance)
				return
			end

			task.wait(0.05)
		end
	end)
end)

scan()

workspace:SetAttribute(
	"DungeonMobWaveCooldownServiceReady",
	true
)
workspace:SetAttribute(
	"DungeonMobWaveRespawnPolicy",
	"FullWaveAfterCooldown"
)
workspace:SetAttribute(
	"DungeonMobWaveRespawnCooldownSeconds",
	Config.WaveRespawnCooldownSeconds
)

print(
	"[MobWaveCooldown] Ready - full wave cooldown = "
		.. tostring(Config.WaveRespawnCooldownSeconds)
		.. "s"
)
