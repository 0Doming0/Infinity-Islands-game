-- Registro compartilhado de fases/níveis.
-- HUD-10 organiza as fases em Universos sem alterar o contrato básico da Dungeon.

local PhaseConfig = {}

PhaseConfig.CatalogDataStoreName = "InfinityIslands_PhaseCatalog_V1"
PhaseConfig.CatalogDataStoreKey = "PublicCatalog"
PhaseConfig.CatalogVersion = 1

local bootstrapDefinitions = {
	Phase01 = {
		PhaseId = "Phase01",
		DisplayName = "Nível 1",
		LevelDisplayName = "Nível 1",
		RequiredLevel = 1,
		MaxPlayers = 4,
		AssetFolder = "Phase01",
		BossId = "GiantBoss",
		BaseIslandCount = 12,
		VictoryCoins = 250,
		ImageId = "",
		SortOrder = 1,
		Enabled = true,

		UniverseId = "Universe01",
		UniverseDisplayName = "Universo 1",
		UniverseDescription = "Primeiro universo da campanha. Complete os níveis em ordem para avançar.",
		UniverseImageId = "",
		UniverseSortOrder = 1,
		LevelNumber = 1,
	},
	Phase02 = {
		PhaseId = "Phase02",
		DisplayName = "Nível 2",
		LevelDisplayName = "Nível 2",
		RequiredLevel = 1,
		MaxPlayers = 4,
		AssetFolder = "Phase02",
		BossId = "GiantBoss",
		BaseIslandCount = 12,
		VictoryCoins = 350,
		ImageId = "",
		SortOrder = 2,
		Enabled = true,

		UniverseId = "Universe01",
		UniverseDisplayName = "Universo 1",
		UniverseDescription = "Primeiro universo da campanha. Complete os níveis em ordem para avançar.",
		UniverseImageId = "",
		UniverseSortOrder = 1,
		LevelNumber = 2,
	},
}

local phases = table.freeze({})
local sourceName = "Empty"

local function parsedLevelNumber(phaseId, fallback)
	local number = tonumber(string.match(tostring(phaseId or ""), "(%d+)$"))
	return math.max(1, math.floor(number or fallback or 1))
end

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
	copy.BaseIslandCount = math.max(1, math.floor(tonumber(copy.BaseIslandCount) or 12))
	copy.VictoryCoins = math.max(0, math.floor(tonumber(copy.VictoryCoins) or 0))
	copy.BossId = tostring(copy.BossId or "GiantBoss")
	copy.ImageId = tostring(copy.ImageId or "")
	copy.SortOrder = math.floor(tonumber(copy.SortOrder) or 0)
	copy.Enabled = copy.Enabled ~= false

	-- Metadados novos. Catálogos V1 antigos continuam válidos e caem no
	-- Universe01 automaticamente.
	copy.UniverseId = tostring(copy.UniverseId or "Universe01")
	if copy.UniverseId == "" then
		copy.UniverseId = "Universe01"
	end
	copy.UniverseDisplayName = tostring(copy.UniverseDisplayName or "Universo 1")
	copy.UniverseDescription = tostring(
		copy.UniverseDescription
			or "Uma campanha composta por vários níveis conectados."
	)
	copy.UniverseImageId = tostring(copy.UniverseImageId or "")
	copy.UniverseSortOrder = math.floor(
		tonumber(copy.UniverseSortOrder) or tonumber(copy.SortOrder) or 1
	)
	copy.LevelNumber = math.max(
		1,
		math.floor(tonumber(copy.LevelNumber) or parsedLevelNumber(phaseId, copy.SortOrder))
	)
	copy.LevelDisplayName = tostring(copy.LevelDisplayName or copy.DisplayName or ("Nível " .. copy.LevelNumber))
	copy.LevelDescription = tostring(
		copy.LevelDescription
			or "Avance pela Dungeon, conclua os rounds e derrote o boss."
	)
	copy.UnlockAfterPhaseId = type(copy.UnlockAfterPhaseId) == "string"
		and copy.UnlockAfterPhaseId ~= ""
		and copy.UnlockAfterPhaseId
		or nil

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

function PhaseConfig.GetPhasesForUniverse(universeId)
	local result = {}
	for phaseId, definition in pairs(phases) do
		if definition.UniverseId == universeId then
			table.insert(result, {
				PhaseId = phaseId,
				Definition = definition,
			})
		end
	end
	table.sort(result, function(left, right)
		if left.Definition.LevelNumber == right.Definition.LevelNumber then
			return left.Definition.SortOrder < right.Definition.SortOrder
		end
		return left.Definition.LevelNumber < right.Definition.LevelNumber
	end)
	return result
end

function PhaseConfig.GetUniverse(universeId)
	local entries = PhaseConfig.GetPhasesForUniverse(universeId)
	local first = entries[1]
	if not first then
		return nil
	end
	local definition = first.Definition
	return {
		UniverseId = universeId,
		DisplayName = definition.UniverseDisplayName,
		Description = definition.UniverseDescription,
		ImageId = definition.UniverseImageId,
		SortOrder = definition.UniverseSortOrder,
		LevelCount = #entries,
	}
end

function PhaseConfig.GetUniversesSorted()
	local seen = {}
	local result = {}
	for _, entry in ipairs(PhaseConfig.GetAllSorted()) do
		local universeId = entry.Definition.UniverseId
		if not seen[universeId] then
			seen[universeId] = true
			local universe = PhaseConfig.GetUniverse(universeId)
			if universe then
				table.insert(result, universe)
			end
		end
	end
	table.sort(result, function(left, right)
		if left.SortOrder == right.SortOrder then
			return left.UniverseId < right.UniverseId
		end
		return left.SortOrder < right.SortOrder
	end)
	return result
end

function PhaseConfig.ToPublicSnapshot(phaseId)
	local phase = PhaseConfig.Get(phaseId)
	if not phase then
		return nil
	end
	return {
		PhaseId = phaseId,
		DisplayName = phase.DisplayName,
		LevelDisplayName = phase.LevelDisplayName,
		LevelDescription = phase.LevelDescription,
		LevelNumber = phase.LevelNumber,
		RequiredLevel = phase.RequiredLevel,
		MaxPlayers = phase.MaxPlayers,
		BaseIslandCount = phase.BaseIslandCount,
		VictoryCoins = phase.VictoryCoins,
		BossId = phase.BossId,
		ImageId = phase.ImageId,
		SortOrder = phase.SortOrder,
		Enabled = true,

		UniverseId = phase.UniverseId,
		UniverseDisplayName = phase.UniverseDisplayName,
		UniverseDescription = phase.UniverseDescription,
		UniverseImageId = phase.UniverseImageId,
		UniverseSortOrder = phase.UniverseSortOrder,
		UnlockAfterPhaseId = phase.UnlockAfterPhaseId,
	}
end

function PhaseConfig.ToUniverseSnapshot(universeId)
	local universe = PhaseConfig.GetUniverse(universeId)
	if not universe then
		return nil
	end
	return table.clone(universe)
end

return table.freeze(PhaseConfig)
