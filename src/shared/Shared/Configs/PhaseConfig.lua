-- Registro em memoria compartilhado pelos servicos do Lobby e da Dungeon.
-- As definicoes reais sao instaladas em runtime pelo PhaseRegistry (Dungeon)
-- ou pelo LobbyPhaseCatalogService (Lobby). Nao adicione fases neste arquivo.

local PhaseConfig = {}

PhaseConfig.CatalogDataStoreName = "InfinityIslands_PhaseCatalog_V1"
PhaseConfig.CatalogDataStoreKey = "PublicCatalog"
PhaseConfig.CatalogVersion = 1

local bootstrapDefinitions = {
	Phase01 = {
		PhaseId = "Phase01",
		DisplayName = "Fase 1",
		RequiredLevel = 1,
		MaxPlayers = 4,
		AssetFolder = "Phase01",
		BossId = "GiantBoss",
		BaseIslandCount = 10,
		VictoryCoins = 250,
		ImageId = "",
		SortOrder = 1,
		Enabled = true,
	},
	Phase02 = {
		PhaseId = "Phase02",
		DisplayName = "Fase 2",
		RequiredLevel = 1,
		MaxPlayers = 4,
		AssetFolder = "Phase02",
		BossId = "GiantBoss",
		BaseIslandCount = 12,
		VictoryCoins = 350,
		ImageId = "",
		SortOrder = 2,
		Enabled = true,
	},
}

local phases = table.freeze({})
local sourceName = "Empty"

local function copyDefinition(phaseId, source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	copy.PhaseId = phaseId
	copy.AssetFolder = tostring(copy.AssetFolder or phaseId)
	copy.DisplayName = tostring(copy.DisplayName or phaseId)
	copy.RequiredLevel = math.max(1, math.floor(tonumber(copy.RequiredLevel) or 1))
	copy.MaxPlayers = math.clamp(math.floor(tonumber(copy.MaxPlayers) or 4), 1, 4)
	copy.BaseIslandCount = math.max(1, math.floor(tonumber(copy.BaseIslandCount) or 10))
	copy.VictoryCoins = math.max(0, math.floor(tonumber(copy.VictoryCoins) or 0))
	copy.BossId = tostring(copy.BossId or "GiantBoss")
	copy.ImageId = tostring(copy.ImageId or "")
	copy.SortOrder = math.floor(tonumber(copy.SortOrder) or 0)
	copy.Enabled = copy.Enabled ~= false
	return table.freeze(copy)
end

function PhaseConfig.Install(definitions, source)
	assert(type(definitions) == "table", "PhaseConfig.Install requer definicoes")
	local installed = {}
	for key, definition in pairs(definitions) do
		if type(definition) == "table" then
			local phaseId = tostring(definition.PhaseId or key)
			if phaseId ~= "" and definition.Enabled ~= false then
				installed[phaseId] = copyDefinition(phaseId, definition)
			end
		end
	end
	phases = table.freeze(installed)
	sourceName = tostring(source or "Runtime")
	return PhaseConfig.Count()
end

function PhaseConfig.UseBootstrapDefaults(source)
	return PhaseConfig.Install(bootstrapDefinitions, source or "BootstrapDefaults")
end

function PhaseConfig.Get(phaseId)
	return type(phaseId) == "string" and phases[phaseId] or nil
end

function PhaseConfig.IsValid(phaseId)
	return PhaseConfig.Get(phaseId) ~= nil
end

function PhaseConfig.GetAll()
	return phases
end

function PhaseConfig.GetAllSorted()
	local result = {}
	for phaseId, definition in pairs(phases) do
		table.insert(result, {
			PhaseId = phaseId,
			Definition = definition,
		})
	end
	table.sort(result, function(left, right)
		if left.Definition.SortOrder == right.Definition.SortOrder then
			return left.PhaseId < right.PhaseId
		end
		return left.Definition.SortOrder < right.Definition.SortOrder
	end)
	return result
end

function PhaseConfig.GetDefaultId()
	local sorted = PhaseConfig.GetAllSorted()
	return sorted[1] and sorted[1].PhaseId or nil
end

function PhaseConfig.Count()
	local count = 0
	for _ in pairs(phases) do
		count += 1
	end
	return count
end

function PhaseConfig.GetSource()
	return sourceName
end

function PhaseConfig.ToPublicSnapshot(phaseId)
	local phase = PhaseConfig.Get(phaseId)
	if not phase then
		return nil
	end
	return {
		PhaseId = phaseId,
		DisplayName = phase.DisplayName,
		RequiredLevel = phase.RequiredLevel,
		MaxPlayers = phase.MaxPlayers,
		BaseIslandCount = phase.BaseIslandCount,
		ImageId = phase.ImageId,
		SortOrder = phase.SortOrder,
		Enabled = true,
	}
end

return table.freeze(PhaseConfig)
