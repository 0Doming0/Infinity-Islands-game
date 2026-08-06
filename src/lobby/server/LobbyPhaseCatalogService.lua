local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)

local LobbyPhaseCatalogService = {}

local function definitionsFromCatalog(catalog)
	if type(catalog) ~= "table" or catalog.Version ~= PhaseConfig.CatalogVersion then
		return nil
	end
	local entries = catalog.Phases
	if type(entries) ~= "table" and type(catalog.Content) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, catalog.Content)
		entries = ok and decoded or nil
	end
	if type(entries) ~= "table" then
		return nil
	end
	local definitions = {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.PhaseId) == "string" and entry.Enabled ~= false then
			definitions[entry.PhaseId] = entry
		end
	end
	return next(definitions) and definitions or nil
end

function LobbyPhaseCatalogService.Load()
	local store = DataStoreService:GetDataStore(PhaseConfig.CatalogDataStoreName)
	local ok, catalog = pcall(store.GetAsync, store, PhaseConfig.CatalogDataStoreKey)
	local definitions = ok and definitionsFromCatalog(catalog) or nil
	if definitions then
		PhaseConfig.Install(definitions, "PublishedDungeonCatalog")
		workspace:SetAttribute("LobbyPhaseCatalogSource", "PublishedDungeonCatalog")
		workspace:SetAttribute("LobbyPhaseCatalogUpdatedAt", tonumber(catalog.UpdatedAt) or 0)
	else
		PhaseConfig.UseBootstrapDefaults("BootstrapDefaults")
		workspace:SetAttribute("LobbyPhaseCatalogSource", "BootstrapDefaults")
		if not ok then
			warn("[LobbyPhaseCatalog] Falha ao ler catalogo: " .. tostring(catalog))
		else
			warn("[LobbyPhaseCatalog] Catalogo ainda nao publicado; usando Phase01 e Phase02 temporariamente.")
		end
	end
	workspace:SetAttribute("LobbyRegisteredPhaseCount", PhaseConfig.Count())
	return PhaseConfig.Count() > 0
end

return LobbyPhaseCatalogService
