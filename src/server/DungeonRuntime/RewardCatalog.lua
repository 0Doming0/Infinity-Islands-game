local RewardCatalog = {}

local MAXIMUM_SEED = 2147483647

local CHESTS = table.freeze({
	[1] = table.freeze({
		Core = table.freeze({
			DisplayName = "Core Chest",
			BaseCoins = 40,
			Guaranteed = table.freeze({ Kind = "Companion", Id = "GreenSlime", Amount = 1, DuplicateCoins = 100 }),
		}),
		Bonus = table.freeze({
			DisplayName = "Bonus Chest",
			BaseCoins = 40,
			Guaranteed = table.freeze({ Kind = "Sword", Id = "BronzeSword", Amount = 1, DuplicateCoins = 150 }),
		}),
	}),
	[2] = table.freeze({
		Core = table.freeze({
			DisplayName = "Core Chest",
			BaseCoins = 80,
			Entries = table.freeze({
				table.freeze({ Weight = 42, Reward = table.freeze({ Kind = "Companion", Id = "BlueSlime", Amount = 1, DuplicateCoins = 150 }) }),
				table.freeze({ Weight = 23, Reward = table.freeze({ Kind = "Companion", Id = "RedSlime", Amount = 1, DuplicateCoins = 180 }) }),
				table.freeze({ Weight = 35, Reward = table.freeze({ Kind = "Coins", Amount = 160 }) }),
			}),
		}),
		Bonus = table.freeze({
			DisplayName = "Bonus Chest",
			BaseCoins = 90,
			Entries = table.freeze({
				table.freeze({ Weight = 40, Reward = table.freeze({ Kind = "Item", Id = "HealthPotion", Amount = 2, DuplicateCoins = 50 }) }),
				table.freeze({ Weight = 30, Reward = table.freeze({ Kind = "Item", Id = "SpeedTonic", Amount = 1, DuplicateCoins = 70 }) }),
				table.freeze({ Weight = 30, Reward = table.freeze({ Kind = "Coins", Amount = 180 }) }),
			}),
		}),
	}),
	[3] = table.freeze({
		Core = table.freeze({
			DisplayName = "Core Chest",
			BaseCoins = 140,
			Entries = table.freeze({
				table.freeze({ Weight = 26, Reward = table.freeze({ Kind = "Companion", Id = "FireSlime", Amount = 1, DuplicateCoins = 260 }) }),
				table.freeze({ Weight = 24, Reward = table.freeze({ Kind = "Companion", Id = "IceSlime", Amount = 1, DuplicateCoins = 260 }) }),
				table.freeze({ Weight = 18, Reward = table.freeze({ Kind = "Companion", Id = "LightningSlime", Amount = 1, DuplicateCoins = 320 }) }),
				table.freeze({ Weight = 32, Reward = table.freeze({ Kind = "Coins", Amount = 320 }) }),
			}),
		}),
		Bonus = table.freeze({
			DisplayName = "Bonus Chest",
			BaseCoins = 160,
			Entries = table.freeze({
				table.freeze({ Weight = 36, Reward = table.freeze({ Kind = "Item", Id = "GreaterHealthPotion", Amount = 2, DuplicateCoins = 100 }) }),
				table.freeze({ Weight = 28, Reward = table.freeze({ Kind = "Item", Id = "JumpTonic", Amount = 2, DuplicateCoins = 100 }) }),
				table.freeze({ Weight = 36, Reward = table.freeze({ Kind = "Coins", Amount = 350 }) }),
			}),
		}),
	}),
})

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % MAXIMUM_SEED
	return seed == 0 and 1 or seed
end

local function hashString(value)
	local hash = 2166136261
	for index = 1, #value do
		hash = (hash * 16777619 + string.byte(value, index) * 97) % MAXIMUM_SEED
	end
	return normalizedSeed(hash)
end

local function copyReward(reward)
	return {
		Kind = reward.Kind,
		Id = reward.Id,
		Amount = math.max(1, math.floor(tonumber(reward.Amount) or 1)),
		DuplicateCoins = math.max(0, math.floor(tonumber(reward.DuplicateCoins) or 0)),
	}
end

local function weightedReward(definition, random)
	local entries = definition.Entries
	if not entries or #entries == 0 then
		return nil
	end
	local total = 0
	for _, entry in ipairs(entries) do
		total += math.max(0, tonumber(entry.Weight) or 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = random:NextNumber(0, total)
	local accumulated = 0
	for _, entry in ipairs(entries) do
		accumulated += math.max(0, tonumber(entry.Weight) or 0)
		if roll <= accumulated then
			return copyReward(entry.Reward)
		end
	end
	return copyReward(entries[#entries].Reward)
end

function RewardCatalog.GetDefinition(roundIndex, chestRole)
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 1), 1, 3)
	chestRole = chestRole == "Bonus" and "Bonus" or "Core"
	return CHESTS[roundIndex][chestRole]
end

function RewardCatalog.MakeGrantId(sessionId, userId, roundIndex, chestRole)
	return string.format(
		"DungeonReward:%s:%d:R%d:%s",
		tostring(sessionId or "unknown"),
		math.max(0, math.floor(tonumber(userId) or 0)),
		math.clamp(math.floor(tonumber(roundIndex) or 1), 1, 3),
		chestRole == "Bonus" and "Bonus" or "Core"
	)
end

function RewardCatalog.Roll(sessionId, userId, roundIndex, chestRole)
	roundIndex = math.clamp(math.floor(tonumber(roundIndex) or 1), 1, 3)
	chestRole = chestRole == "Bonus" and "Bonus" or "Core"
	local definition = RewardCatalog.GetDefinition(roundIndex, chestRole)
	local grantId = RewardCatalog.MakeGrantId(sessionId, userId, roundIndex, chestRole)
	local random = Random.new(hashString(grantId))
	local rewards = {}
	if definition.BaseCoins and definition.BaseCoins > 0 then
		table.insert(rewards, { Kind = "Coins", Amount = definition.BaseCoins })
	end
	if definition.Guaranteed then
		table.insert(rewards, copyReward(definition.Guaranteed))
	else
		local selected = weightedReward(definition, random)
		if selected then
			table.insert(rewards, selected)
		end
	end
	return {
		GrantId = grantId,
		RoundIndex = roundIndex,
		ChestRole = chestRole,
		DisplayName = definition.DisplayName,
		Rewards = rewards,
		RolledSeed = hashString(grantId),
	}
end

function RewardCatalog.GetAllDefinitions()
	return CHESTS
end

return table.freeze(RewardCatalog)
