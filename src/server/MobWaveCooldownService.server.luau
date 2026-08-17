--[[
	Infinity Islands - Finite Mob Encounter Guard

	The legacy MonsterSpawner still tries to refill plan.Alive back to MaxAlive
	whenever CombatState == "Active". For the linear MVP that is undesirable.

	Rule:
	- the initial fixed quota spawns once;
	- after the first defeated mob, this guard changes the public CombatState
	  away from "Active" so MonsterSpawner cannot refill killed mobs;
	- IslandCombatService keeps its own authoritative record Active internally,
	  so kill counting and clear still work;
	- if another service republishes "Active" after a death/respawn, the guard
	  immediately restores the finite state;
	- once Cleared, the final state stays Cleared.

	No cooldown and no second wave exist in the MVP.
]]

local Players = game:GetService("Players")

local records = setmetatable({}, { __mode = "k" })
local FINITE_ACTIVE_STATE = "FiniteActive"

local function cleanIndex(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	number = math.floor(number)
	return number >= 1 and number or nil
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

local function spawnedCount(island)
	return math.max(
		0,
		math.floor(tonumber(
			island:GetAttribute("MobLifetimeSpawnedCount")
				or island:GetAttribute("MobSpawnedCount")
		) or 0)
	)
end

local function publish(island, record)
	if not island.Parent then
		return
	end

	local target = targetCount(island)
	local defeated = defeatedCount(island)
	local spawned = spawnedCount(island)

	-- These compatibility attributes are deliberately reasserted whenever the
	-- legacy spawner republishes its concurrency data. That keeps diagnostics
	-- consistent with the actual finite policy instead of briefly advertising
	-- a refill that will never be allowed to happen.
	island:SetAttribute("MobIndividualRefillEnabled", false)
	island:SetAttribute("MobInfiniteRespawnEnabled", false)
	island:SetAttribute("InfiniteMobRespawnEnabled", false)
	island:SetAttribute("MobWaveCooldownActive", false)
	island:SetAttribute("MobWaveRefillLocked", record.Locked == true)
	island:SetAttribute("MobRespawnPendingCount", 0)
	island:SetAttribute("MobRespawnPolicy", "FixedFiniteQuota")
	island:SetAttribute("MobFiniteEncounter", true)
	island:SetAttribute("MobFiniteTargetCount", target)
	island:SetAttribute("MobFiniteDefeatedCount", defeated)
	island:SetAttribute("MobFiniteSpawnedCount", spawned)
	island:SetAttribute(
		"MobFiniteRemainingCount",
		math.max(0, target - defeated)
	)
end

local function enforce(island, record)
	if not island.Parent or record.Enforcing then
		return
	end

	if island:GetAttribute("Cleared") == true then
		record.Completed = true
		record.Locked = true
		publish(island, record)
		if island:GetAttribute("CombatState") ~= "Cleared" then
			record.Enforcing = true
			island:SetAttribute("CombatState", "Cleared")
			record.Enforcing = false
		end
		return
	end

	if not record.Locked then
		publish(island, record)
		return
	end

	publish(island, record)

	-- MonsterSpawner only refills while the attribute is exactly "Active".
	-- IslandCombatService's internal record remains Active and keeps counting
	-- deaths, so this is only a spawn gate, not a second combat state machine.
	if island:GetAttribute("CombatState") == "Active" then
		record.Enforcing = true
		island:SetAttribute("CombatState", FINITE_ACTIVE_STATE)
		record.Enforcing = false
	end
end

local function onDefeatedChanged(island, record)
	if island:GetAttribute("Cleared") == true then
		enforce(island, record)
		return
	end

	local defeated = defeatedCount(island)
	if defeated > record.LastDefeatedCount then
		record.LastDefeatedCount = defeated
		record.Locked = true
	end

	enforce(island, record)
end

local function trackIsland(island)
	if records[island] or not isCombatIsland(island) then
		return
	end

	local record = {
		Index = islandIndex(island),
		Locked = defeatedCount(island) > 0,
		Completed = island:GetAttribute("Cleared") == true,
		LastDefeatedCount = defeatedCount(island),
		Enforcing = false,
		Connections = {},
	}
	records[island] = record

	for _, attributeName in ipairs({
		"MobDefeatedCount",
		"MobTargetCount",
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
				if attributeName == "MobDefeatedCount" then
					onDefeatedChanged(island, record)
				else
					publish(island, record)
				end
			end)
		)
	end

	table.insert(
		record.Connections,
		island:GetAttributeChangedSignal("Cleared"):Connect(function()
			enforce(island, record)
		end)
	)

	table.insert(
		record.Connections,
		island:GetAttributeChangedSignal("CombatState"):Connect(function()
			if not record.Enforcing then
				enforce(island, record)
			end
		end)
	)

	table.insert(
		record.Connections,
		island.AncestryChanged:Connect(function(_, parent)
			if parent then
				return
			end
			for _, connection in ipairs(record.Connections) do
				connection:Disconnect()
			end
			records[island] = nil
		end)
	)

	task.defer(enforce, island, record)
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

-- If a player dies and returns, IslandCombatService can publish Active again.
-- The island record above survives normal soft-unloads; this extra listener
-- makes the intent explicit and re-enforces the finite gate on re-entry.
local function bindPlayer(player)
	player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
		local index = cleanIndex(player:GetAttribute("CurrentGlobalIslandIndex"))
		if not index then
			return
		end
		for island, record in pairs(records) do
			if record.Index == index then
				task.defer(enforce, island, record)
			end
		end
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

scan()

workspace:SetAttribute("DungeonMobWaveCooldownServiceReady", true)
workspace:SetAttribute("DungeonMobWaveRespawnPolicy", "FixedFiniteQuota")
workspace:SetAttribute("DungeonMobWaveRespawnCooldownSeconds", 0)
workspace:SetAttribute("DungeonMobInfiniteRespawnEnabled", false)

print("[FiniteMobEncounter] Ready - mobs mortos nao sao repostos")
