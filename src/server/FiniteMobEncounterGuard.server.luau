--[[
	Infinity Islands - Finite Mob Encounter Guard

	Autoridade de seguranca para a populacao finita do MVP.

	Contrato:
	- cada ilha linear aceita no maximo MobTargetCount mobs gerenciados;
	- a contagem e de lifetime spawn, nao de mobs vivos simultaneamente;
	- morte, respawn, reentrada e co-op nunca criam uma nova cota;
	- assim que a cota inteira foi materializada uma vez, CombatState deixa de
	  ser "Active" publicamente para impedir o refill legado do MonsterSpawner;
	- se o spawner legado tentar materializar um mob acima da cota, o servidor
	  rejeita e destroi esse clone imediatamente;
	- IslandCombatService continua com seu estado interno e segue contando kills.

	Este arquivo substitui o antigo MobWaveCooldownService: nao existem waves ou
	cooldown de respawn no loop linear atual.
]]

local Players = game:GetService("Players")

local VERSION = "FiniteMobEncounterHardCapV2"
local FINITE_ACTIVE_STATE = "FiniteActive"

local records = setmetatable({}, { __mode = "k" })

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	number = math.floor(number)
	return number >= 1 and number or nil
end

local function islandIndex(island)
	return cleanIndex(
		island:GetAttribute("GlobalIslandIndex")
			or island:GetAttribute("ProgressionIslandIndex")
	)
end

local function targetCount(island)
	return math.max(
		0,
		math.floor(tonumber(island:GetAttribute("MobTargetCount")) or 0)
	)
end

local function defeatedCount(island)
	return math.max(
		0,
		math.floor(tonumber(island:GetAttribute("MobDefeatedCount")) or 0)
	)
end

local function rawSpawnerCount(island)
	return math.max(
		0,
		math.floor(tonumber(
			island:GetAttribute("MobLifetimeSpawnedCount")
				or island:GetAttribute("MobSpawnedCount")
		) or 0)
	)
end

local function isCombatIsland(island)
	if not island or not island:IsA("Model") then
		return false
	end
	if island:GetAttribute("RuntimeMonster") == true
		or island:GetAttribute("IslandCombatManaged") == true
	then
		return false
	end
	if not islandIndex(island) then
		return false
	end
	if island:GetAttribute("IsSanctuary") == true
		or island:GetAttribute("IsRewardIsland") == true
		or island:GetAttribute("IsBossSanctuary") == true
		or island:GetAttribute("IsOptionalRoute") == true
		or island:GetAttribute("IsMandatoryRoute") == false
	then
		return false
	end

	-- Nao dependemos somente de IsSkyIsland: a ilha inicial/template tambem
	-- pertence ao encontro linear e precisa da mesma protecao de quantidade.
	return island:GetAttribute("IsSkyIsland") == true
		or island:GetAttribute("IsInitialIsland") == true
		or island:GetAttribute("IslandRole") == "CombatEntry"
		or island:GetAttribute("MobTargetCount") ~= nil
		or island:FindFirstChild("IslandCombatMonsters") ~= nil
end

local function isManagedMobForRecord(model, record)
	return model
		and model:IsA("Model")
		and model.Parent ~= nil
		and model:GetAttribute("RuntimeMonster") == true
		and model:GetAttribute("IslandCombatManaged") == true
		and cleanIndex(model:GetAttribute("GlobalIslandIndex")) == record.Index
		and model:IsDescendantOf(record.Island)
end

local function publish(island, record)
	if not island.Parent then
		return
	end

	local target = targetCount(island)
	local defeated = defeatedCount(island)
	local raw = rawSpawnerCount(island)
	local accepted = record.AcceptedSpawnCount
	local rejected = record.RejectedSpawnCount
	local spawnBudgetRemaining = target > 0
		and math.max(0, target - accepted)
		or 0

	island:SetAttribute("MobIndividualRefillEnabled", false)
	island:SetAttribute("MobInfiniteRespawnEnabled", false)
	island:SetAttribute("InfiniteMobRespawnEnabled", false)
	island:SetAttribute("MobWaveCooldownActive", false)
	island:SetAttribute("MobWaveRefillLocked", record.Locked == true)
	island:SetAttribute("MobRespawnPendingCount", 0)
	island:SetAttribute("MobRespawnPolicy", "FixedFiniteLifetimeQuota")
	island:SetAttribute("MobFiniteEncounter", true)
	island:SetAttribute("MobFiniteHardCapEnabled", true)
	island:SetAttribute("MobFiniteHardCapVersion", VERSION)
	island:SetAttribute("MobFiniteTargetCount", target)
	island:SetAttribute("MobFiniteDefeatedCount", defeated)
	island:SetAttribute("MobFiniteSpawnedCount", accepted)
	island:SetAttribute("MobFiniteAcceptedSpawnCount", accepted)
	island:SetAttribute("MobFiniteRejectedSpawnCount", rejected)
	island:SetAttribute("MobFiniteRawSpawnerCount", raw)
	island:SetAttribute("MobFiniteSpawnBudgetRemaining", spawnBudgetRemaining)
	island:SetAttribute("MobFiniteSpawnCapReached", target > 0 and accepted >= target)
	island:SetAttribute(
		"MobFiniteRemainingCount",
		math.max(0, target - defeated)
	)

	if rejected > 0 or (target > 0 and raw > target) then
		island:SetAttribute("MobFiniteOverSpawnDetected", true)
		island:SetAttribute(
			"MobFiniteOverSpawnCount",
			math.max(rejected, math.max(0, raw - target))
		)
	else
		island:SetAttribute("MobFiniteOverSpawnDetected", false)
		island:SetAttribute("MobFiniteOverSpawnCount", 0)
	end
end

local function refreshLock(record)
	local island = record.Island
	local target = targetCount(island)

	if island:GetAttribute("Cleared") == true then
		record.Completed = true
		record.Locked = true
		return
	end

	-- O refill so deve ser bloqueado quando a cota inteira ja apareceu pelo
	-- menos uma vez. Assim um limite global temporario nao torna o objetivo
	-- impossivel deixando mobs planejados sem nascer.
	record.Locked = target > 0 and record.AcceptedSpawnCount >= target
end

local function enforce(island, record)
	if not island.Parent or record.Enforcing then
		return
	end

	refreshLock(record)
	publish(island, record)

	if island:GetAttribute("Cleared") == true then
		if island:GetAttribute("CombatState") ~= "Cleared" then
			record.Enforcing = true
			island:SetAttribute("CombatState", "Cleared")
			record.Enforcing = false
		end
		return
	end

	-- MonsterSpawner legado so executa refill se o atributo for exatamente
	-- "Active". FiniteActive e apenas um gate de spawn; nao substitui o estado
	-- interno do IslandCombatService.
	if record.Locked and island:GetAttribute("CombatState") == "Active" then
		record.Enforcing = true
		island:SetAttribute("CombatState", FINITE_ACTIVE_STATE)
		record.Enforcing = false
	end
end

local function observeManagedSpawn(record, model)
	if record.SeenModels[model] then
		return
	end
	if not isManagedMobForRecord(model, record) then
		return
	end

	record.SeenModels[model] = true
	local target = targetCount(record.Island)

	if target > 0 and record.AcceptedSpawnCount >= target then
		record.RejectedSpawnCount += 1
		model:SetAttribute("RejectedByFiniteMobHardCap", true)
		model:SetAttribute("FiniteMobHardCapVersion", VERSION)
		publish(record.Island, record)

		if not record.WarnedOverSpawn then
			record.WarnedOverSpawn = true
			warn(string.format(
				"[FiniteMobEncounter] Spawn excedente rejeitado na ilha %d (cota=%d)",
				record.Index,
				target
			))
		end

		-- O clone ja recebeu seus atributos antes de ser parentado pelo spawner.
		-- Destruir no primeiro callback de DescendantAdded impede que ele vire um
		-- inimigo jogavel e fecha caminhos legados de refill.
		task.defer(function()
			if model.Parent then
				model:Destroy()
			end
		end)
		return
	end

	record.AcceptedSpawnCount += 1
	model:SetAttribute("FiniteMobSpawnAccepted", true)
	model:SetAttribute("FiniteMobHardCapVersion", VERSION)
	enforce(record.Island, record)
end

local function scanManagedMobs(record)
	for _, descendant in ipairs(record.Island:GetDescendants()) do
		if descendant:IsA("Model") then
			observeManagedSpawn(record, descendant)
		end
	end
end

local function trackIsland(island)
	if records[island] or not isCombatIsland(island) then
		return
	end

	local record = {
		Island = island,
		Index = islandIndex(island),
		AcceptedSpawnCount = 0,
		RejectedSpawnCount = 0,
		Locked = false,
		Completed = island:GetAttribute("Cleared") == true,
		Enforcing = false,
		WarnedOverSpawn = false,
		SeenModels = setmetatable({}, { __mode = "k" }),
		Connections = {},
	}
	records[island] = record

	table.insert(record.Connections, island.DescendantAdded:Connect(function(instance)
		if instance:IsA("Model") then
			task.defer(observeManagedSpawn, record, instance)
		end
	end))

	for _, attributeName in ipairs({
		"MobTargetCount",
		"MobDefeatedCount",
		"MobLifetimeSpawnedCount",
		"MobSpawnedCount",
		"MobActiveAliveCount",
		"MobRespawnPendingCount",
		"MobInfiniteRespawnEnabled",
		"InfiniteMobRespawnEnabled",
	}) do
		table.insert(
			record.Connections,
			island:GetAttributeChangedSignal(attributeName):Connect(function()
				scanManagedMobs(record)
				enforce(island, record)
			end)
		)
	end

	table.insert(record.Connections, island:GetAttributeChangedSignal("Cleared"):Connect(function()
		enforce(island, record)
	end))

	table.insert(record.Connections, island:GetAttributeChangedSignal("CombatState"):Connect(function()
		if not record.Enforcing then
			enforce(island, record)
		end
	end))

	table.insert(record.Connections, island.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		for _, connection in ipairs(record.Connections) do
			connection:Disconnect()
		end
		records[island] = nil
	end))

	scanManagedMobs(record)
	enforce(island, record)
end

local function tryTrack(instance)
	if not instance:IsA("Model") then
		return
	end

	-- A identidade/atributos da ilha podem chegar alguns frames depois da
	-- instancia durante geracao procedural e sync do Studio.
	task.defer(function()
		for _ = 1, 40 do
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
end

local function scanIslands()
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("Model") and isCombatIsland(instance) then
			trackIsland(instance)
		end
	end
end

workspace.DescendantAdded:Connect(tryTrack)

local function bindPlayer(player)
	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
		if not index then
			return
		end
		for island, record in pairs(records) do
			if record.Index == index then
				scanManagedMobs(record)
				task.defer(enforce, island, record)
			end
		end
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

scanIslands()

workspace:SetAttribute("DungeonFiniteMobEncounterReady", true)
workspace:SetAttribute("DungeonFiniteMobEncounterVersion", VERSION)
workspace:SetAttribute("DungeonMobWaveCooldownServiceReady", false)
workspace:SetAttribute("DungeonMobWaveRespawnPolicy", "FixedFiniteLifetimeQuota")
workspace:SetAttribute("DungeonMobWaveRespawnCooldownSeconds", 0)
workspace:SetAttribute("DungeonMobInfiniteRespawnEnabled", false)
workspace:SetAttribute("DungeonInfiniteIslandMobs", false)
workspace:SetAttribute("DungeonMobRespawnPolicy", "FixedFiniteLifetimeQuota")
workspace:SetAttribute("DungeonMobFiniteHardCapPolicy", "AcceptedLifetimeSpawns<=MobTargetCount")

print("[FiniteMobEncounter] Ready - hard cap por ilha ativo")
