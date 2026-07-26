local HttpService = game:GetService("HttpService")

local MonsterLoot = {}

local function normalize(raw, fallbackId)
	if type(raw) ~= "table" then
		return nil
	end
	local itemId = raw.ItemId or raw.Id or fallbackId
	if type(itemId) ~= "string" or itemId == "" then
		return nil
	end
	local minimum = math.max(1, math.floor(tonumber(raw.MinAmount) or 1))
	local maximum = math.max(minimum, math.floor(tonumber(raw.MaxAmount) or minimum))
	return {
		ItemId = itemId,
		Weight = math.max(0, tonumber(raw.Weight) or 1),
		Chance = math.clamp(tonumber(raw.Chance) or 1, 0, 1),
		MinAmount = minimum,
		MaxAmount = maximum,
	}
end

function MonsterLoot.Read(template)
	local definitions = {}
	local folder = template:FindFirstChild("LootTable")
	if folder and folder:IsA("Folder") then
		for _, child in ipairs(folder:GetChildren()) do
			local definition = normalize({
				ItemId = child:GetAttribute("ItemId") or (child:IsA("StringValue") and child.Value or nil),
				Weight = child:GetAttribute("Weight"),
				Chance = child:GetAttribute("Chance"),
				MinAmount = child:GetAttribute("MinAmount"),
				MaxAmount = child:GetAttribute("MaxAmount"),
			}, child.Name)
			if definition then
				table.insert(definitions, definition)
			end
		end
	end
	local encoded = template:GetAttribute("LootTable")
	if typeof(encoded) == "string" and encoded ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
		if ok and type(decoded) == "table" then
			for _, raw in ipairs(decoded) do
				local definition = normalize(raw)
				if definition then
					table.insert(definitions, definition)
				end
			end
		end
	end
	if #definitions == 0 then
		local legacyId = template:GetAttribute("DropItemId")
		if typeof(legacyId) == "string" and legacyId ~= "" then
			table.insert(definitions, {
				ItemId = legacyId,
				Weight = 1,
				Chance = math.clamp(tonumber(template:GetAttribute("DropChance")) or 0, 0, 1),
				MinAmount = 1,
				MaxAmount = 1,
			})
		end
	end
	return definitions
end

function MonsterLoot.Roll(definitions, rolls, random)
	local results = {}
	local totalWeight = 0
	for _, definition in ipairs(definitions) do
		totalWeight += definition.Weight
	end
	if totalWeight <= 0 then
		return results
	end
	for _ = 1, math.max(1, math.floor(tonumber(rolls) or 1)) do
		local roll = random:NextNumber(0, totalWeight)
		local accumulated = 0
		for _, definition in ipairs(definitions) do
			accumulated += definition.Weight
			if roll <= accumulated then
				if random:NextNumber() <= definition.Chance then
					table.insert(results, {
						ItemId = definition.ItemId,
						Amount = random:NextInteger(definition.MinAmount, definition.MaxAmount),
					})
				end
				break
			end
		end
	end
	return results
end

return table.freeze(MonsterLoot)
