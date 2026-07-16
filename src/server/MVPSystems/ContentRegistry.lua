--[[
	BlockParkour MVP - ContentRegistry

	Descobre assets em ServerStorage/MVPAssets uma vez por execucao de Play.
	Assets invalidos sao ignorados individualmente e relatados no Output.
]]

local ServerStorage = game:GetService("ServerStorage")

local ContentValidator = require(script.Parent.ContentValidator)

local ContentRegistry = {}

local CATEGORY_ORDER = {
	"Collectibles",
	"Houses",
	"Villagers",
	"Monsters",
	"Items",
	"Shops",
	"Tools",
}

local started = false
local rootFolder = nil
local entriesByCategory = {}
local entriesById = {}

local function copyCategory(category)
	local source = entriesByCategory[category] or {}
	local copy = table.create(#source)
	for index, template in ipairs(source) do
		copy[index] = template
	end
	return copy
end

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(
			existing:IsA("Folder"),
			string.format("[MVP ContentRegistry] %s deve ser Folder", existing:GetFullName())
		)
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function registerCategory(category, folder)
	local ordered = {}
	local byId = {}

	for _, template in ipairs(folder:GetChildren()) do
		local enabled = template:GetAttribute("Enabled")
		if enabled == false then
			continue
		end

		local valid, errors = ContentValidator.Validate(category, template)
		local contentId = ContentValidator.GetContentId(category, template)
		if valid and (typeof(contentId) ~= "string" or contentId == "") then
			valid = false
			table.insert(errors, "ID vazio ou invalido")
		end
		if valid and byId[contentId] then
			valid = false
			table.insert(
				errors,
				string.format("ID duplicado %s; primeiro asset: %s", contentId, byId[contentId]:GetFullName())
			)
		end

		if valid then
			byId[contentId] = template
			table.insert(ordered, template)
		else
			ContentValidator.Warn(category, template, errors)
		end
	end

	table.sort(ordered, function(left, right)
		return ContentValidator.GetContentId(category, left) < ContentValidator.GetContentId(category, right)
	end)
	entriesByCategory[category] = ordered
	entriesById[category] = byId
end

local function removeEntry(category, template, message)
	local contentId = ContentValidator.GetContentId(category, template)
	entriesById[category][contentId] = nil
	local index = table.find(entriesByCategory[category], template)
	if index then
		table.remove(entriesByCategory[category], index)
	end
	ContentValidator.Warn(category, template, { message })
end

local function validateReferences()
	-- Produtos e drops somente podem apontar para itens validos do servidor.
	for _, shop in ipairs(copyCategory("Shops")) do
		local invalidItemId = nil
		for _, product in ipairs(shop:GetChildren()) do
			local itemId = product:GetAttribute("ItemId")
			if not entriesById.Items[itemId] then
				invalidItemId = itemId
				break
			end
		end
		if invalidItemId then
			removeEntry("Shops", shop, "produto referencia ItemId inexistente: " .. tostring(invalidItemId))
		end
	end

	for _, villager in ipairs(copyCategory("Villagers")) do
		local shopId = villager:GetAttribute("ShopId")
		if not entriesById.Shops[shopId] then
			removeEntry("Villagers", villager, "ShopId inexistente ou invalido: " .. tostring(shopId))
		end
	end

	for _, house in ipairs(copyCategory("Houses")) do
		local missingVillagerId = nil
		for _, descendant in ipairs(house:GetDescendants()) do
			if descendant:IsA("Attachment") and string.match(descendant.Name, "^VillagerSpawn_") then
				local villagerId = descendant:GetAttribute("VillagerId")
				if not entriesById.Villagers[villagerId] then
					missingVillagerId = villagerId
					break
				end
			end
		end
		if missingVillagerId then
			removeEntry(
				"Houses",
				house,
				"VillagerSpawn referencia VillagerId inexistente ou invalido: " .. tostring(missingVillagerId)
			)
		end
	end

	for _, monster in ipairs(copyCategory("Monsters")) do
		local missingItemId = nil
		local lootTable = monster:FindFirstChild("LootTable")
		for _, entry in ipairs(lootTable:GetChildren()) do
			local itemId = entry:GetAttribute("ItemId")
			if not entriesById.Items[itemId] then
				missingItemId = itemId
				break
			end
		end
		if missingItemId then
			removeEntry("Monsters", monster, "LootTable referencia ItemId inexistente: " .. tostring(missingItemId))
		end
	end
end

function ContentRegistry.Start()
	if started then
		return
	end

	rootFolder = ensureFolder(ServerStorage, "MVPAssets")
	for _, category in ipairs(CATEGORY_ORDER) do
		local folder = ensureFolder(rootFolder, category)
		registerCategory(category, folder)
	end
	validateReferences()

	started = true
	local count = 0
	for _, entries in pairs(entriesByCategory) do
		count += #entries
	end
	print(string.format("[MVP ContentRegistry] %d asset(s) valido(s) registrados", count))
end

function ContentRegistry.IsStarted()
	return started
end

function ContentRegistry.GetRootFolder()
	assert(started, "[MVP ContentRegistry] Start deve ser chamado primeiro")
	return rootFolder
end

function ContentRegistry.GetAll(category)
	assert(started, "[MVP ContentRegistry] Start deve ser chamado primeiro")
	return copyCategory(category)
end

function ContentRegistry.GetById(category, contentId)
	assert(started, "[MVP ContentRegistry] Start deve ser chamado primeiro")
	return entriesById[category] and entriesById[category][contentId] or nil
end

function ContentRegistry.GetCategoryNames()
	local copy = table.create(#CATEGORY_ORDER)
	for index, name in ipairs(CATEGORY_ORDER) do
		copy[index] = name
	end
	return copy
end

return ContentRegistry
