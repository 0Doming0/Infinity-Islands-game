-- Roleta autoritativa e reutilizavel para altura, baus raros e bosses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RewardWheelCatalog = require(ReplicatedStorage:WaitForChild("RewardWheelCatalog"))
local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))
local SwordCatalog = require(ReplicatedStorage:WaitForChild("SwordCatalog"))
local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))

local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PlayerDataService = require(BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local ScoreService = require(BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local CompanionService = require(script.Parent:WaitForChild("CompanionService"))
local MarketingOfferService = require(script.Parent:WaitForChild("MarketingOfferService"))

local RewardWheelService = {}
local random = Random.new()
local started = false
local event
local spinSerial = 0

local function ensureRemote()
	local existing = ReplicatedStorage:FindFirstChild("RewardWheelEvent")
	if existing and not existing:IsA("RemoteEvent") then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new("RemoteEvent")
		existing.Name = "RewardWheelEvent"
		existing.Parent = ReplicatedStorage
	end
	return existing
end

local function weightedChoice(entries, getWeight)
	local total = 0
	for key, entry in pairs(entries) do
		total += math.max(0, tonumber(getWeight(entry, key)) or 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = random:NextNumber(0, total)
	local accumulated = 0
	for key, entry in pairs(entries) do
		accumulated += math.max(0, tonumber(getWeight(entry, key)) or 0)
		if roll <= accumulated then
			return entry, key
		end
	end
	return nil
end

local function isImageId(value)
	return type(value) == "string"
		and value ~= ""
		and (string.match(value, "^rbxassetid://%d+$") ~= nil or string.match(value, "^rbxasset://") ~= nil)
end

local function assetImageId(folderName, itemId, catalogImage, identityAttribute)
	if isImageId(catalogImage) then
		return catalogImage
	end
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local folder = assets and assets:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(itemId, true)
	if not template and folder and identityAttribute then
		for _, candidate in ipairs(folder:GetDescendants()) do
			if candidate:GetAttribute(identityAttribute) == itemId then
				template = candidate
				break
			end
		end
	end
	if not template then
		return ""
	end
	for _, attributeName in ipairs({ "RewardImageId", "ImageId", "CompanionImageId" }) do
		local attributeImage = template:GetAttribute(attributeName)
		if isImageId(attributeImage) then
			return attributeImage
		end
	end
	if template:IsA("Tool") and isImageId(template.TextureId) then
		return template.TextureId
	end
	return ""
end

local function companionImageId(monsterId)
	return assetImageId("Monsters", monsterId, CompanionCatalog.GetImageId(monsterId), "MonsterId")
end

local function swordImageId(definition)
	return assetImageId("Swords", definition.SwordId, definition.ImageId, "SwordId")
end

local function relicImageId(definition)
	return assetImageId("Relics", definition.RelicId, definition.ImageId, "RelicId")
end

local function countOwned(dictionary)
	local count = 0
	for _, owned in pairs(dictionary or {}) do
		if owned == true then
			count += 1
		end
	end
	return count
end

local function reduceWheelCoins(amount)
	local multiplier = math.clamp(
		tonumber(RewardWheelCatalog.CoinPayoutMultiplier) or 1,
		0,
		1
	)
	return math.max(1, math.floor(math.max(0, tonumber(amount) or 0) * multiplier))
end

local function duplicateCoins(price)
	local originalCompensation = math.max(
		RewardWheelCatalog.MinimumDuplicateCompensation,
		math.floor(math.max(0, tonumber(price) or 0) * RewardWheelCatalog.DuplicateCompensationRatio)
	)
	return reduceWheelCoins(originalCompensation)
end

local function awardCoins(player, amount, sourceId, isCompensation)
	local cleanAmount = math.max(1, math.floor(tonumber(amount) or 1))
	if isCompensation then
		local success = ScoreService.RefundCoins(player, cleanAmount, "RewardWheelDuplicate")
		return success and cleanAmount or 0
	end
	return ScoreService.AwardCoins(player, cleanAmount, "RewardWheel_" .. sourceId)
end

local function grantCoins(player, sourceId, source, context)
	local level = math.max(1, math.floor(tonumber(context and context.Level) or 1))
	local minimum = source.CoinMinimum + math.max(0, level - 1) * source.CoinPerLevel
	local maximum = source.CoinMaximum + math.max(0, level - 1) * source.CoinPerLevel
	local amount = awardCoins(player, reduceWheelCoins(random:NextInteger(minimum, maximum)), sourceId, false)
	if amount <= 0 then
		return nil
	end
	return {
		Category = "Coins",
		RewardId = "Coins",
		DisplayName = string.format("%d moedas", amount),
		Amount = amount,
		IsDuplicate = false,
	}
end

local function grantRelic(player, sourceId)
	local entry = weightedChoice(RewardWheelCatalog.RewardPools.Relic, function(candidate)
		return candidate.Weight
	end)
	local definition = entry and RelicCatalog.Get(entry.Id)
	if not definition then
		return nil
	end
	if PlayerDataService.HasRelic(player, definition.RelicId) then
		local amount = awardCoins(player, duplicateCoins(definition.Price), sourceId, true)
		if amount <= 0 then
			return nil
		end
		return {
			Category = "Coins",
			OriginalCategory = "Relic",
			RewardId = "Coins",
			OriginalRewardId = definition.RelicId,
			DisplayName = string.format("%d moedas", amount),
			OriginalDisplayName = definition.DisplayName,
			Amount = amount,
			IsDuplicate = true,
		}
	end
	if not PlayerDataService.GrantRelic(player, definition.RelicId) then
		return nil
	end
	local data = PlayerDataService.Get(player)
	player:SetAttribute("OwnedRelicCount", countOwned(data and data.OwnedRelics))
	return {
		Category = "Relic",
		RewardId = definition.RelicId,
		DisplayName = definition.DisplayName,
		ImageId = relicImageId(definition),
		Icon = definition.Icon,
		Color = definition.Color,
		IsDuplicate = false,
	}
end

local function grantSword(player, sourceId)
	local entry = weightedChoice(RewardWheelCatalog.RewardPools.Sword, function(candidate)
		return candidate.Weight
	end)
	local definition = entry and SwordCatalog.Get(entry.Id)
	if not definition then
		return nil
	end
	if PlayerDataService.HasSword(player, definition.SwordId) then
		local amount = awardCoins(player, duplicateCoins(definition.Price), sourceId, true)
		if amount <= 0 then
			return nil
		end
		return {
			Category = "Coins",
			OriginalCategory = "Sword",
			RewardId = "Coins",
			OriginalRewardId = definition.SwordId,
			DisplayName = string.format("%d moedas", amount),
			OriginalDisplayName = definition.DisplayName,
			Amount = amount,
			IsDuplicate = true,
		}
	end
	if not PlayerDataService.GrantSword(player, definition.SwordId) then
		return nil
	end
	local data = PlayerDataService.Get(player)
	player:SetAttribute("OwnedSwordCount", countOwned(data and data.OwnedSwords))
	return {
		Category = "Sword",
		RewardId = definition.SwordId,
		DisplayName = definition.DisplayName,
		ImageId = swordImageId(definition),
		Icon = definition.Icon,
		Color = definition.Color,
		IsDuplicate = false,
	}
end

local function grantCompanion(player, sourceId)
	local entry = weightedChoice(RewardWheelCatalog.RewardPools.Companion, function(candidate)
		return candidate.Weight
	end)
	if not entry or not CompanionCatalog.Entries[entry.Id] then
		return nil
	end
	local _, equippedBefore = PlayerDataService.GetCompanions(player)
	local success, unlocked, instanceId = PlayerDataService.UnlockCompanion(
		player,
		entry.Id,
		entry.DisplayName
	)
	if not success or not unlocked then
		return nil
	end
	-- O primeiro companheiro e equipado automaticamente pelo dado persistente;
	-- esta chamada tambem cria seu modelo no mundo imediatamente.
	if #equippedBefore == 0 then
		CompanionService.SetEquipped(player, instanceId, true)
	end
	local companionEvent = ReplicatedStorage:FindFirstChild("CompanionEvent")
	if companionEvent and companionEvent:IsA("RemoteEvent") then
		companionEvent:FireClient(player, {
			Action = "Update",
			Snapshot = CompanionService.GetSnapshot(player),
			Message = "Novo companheiro: " .. entry.DisplayName .. "!",
			Success = true,
		})
	end
	return {
		Category = "Companion",
		RewardId = entry.Id,
		CompanionInstanceId = instanceId,
		DisplayName = entry.DisplayName,
		ImageId = companionImageId(entry.Id),
		IsDuplicate = false,
	}
end

local GRANTERS = {
	Coins = grantCoins,
	Relic = grantRelic,
	Sword = grantSword,
	Companion = grantCompanion,
}

local function visualEntry(category, rewardId, displayName, icon, color, imageId)
	local categoryInfo = RewardWheelCatalog.GetCategoryInfo(category)
	return {
		Category = category,
		RewardId = rewardId,
		DisplayName = displayName or (categoryInfo and categoryInfo.DisplayName) or "Recompensa",
		Icon = icon or (categoryInfo and categoryInfo.Icon) or "🎁",
		Color = color or (categoryInfo and categoryInfo.Color) or Color3.fromRGB(255, 255, 255),
		ImageId = isImageId(imageId) and imageId or "",
	}
end

local function randomVisualEntry(source)
	local _, category = weightedChoice(source.CategoryWeights, function(weight)
		return weight
	end)
	if category == "Relic" then
		local entry = weightedChoice(RewardWheelCatalog.RewardPools.Relic, function(candidate)
			return candidate.Weight
		end)
		local definition = entry and RelicCatalog.Get(entry.Id)
		if definition then
			return visualEntry(
				"Relic",
				definition.RelicId,
				definition.DisplayName,
				definition.Icon,
				definition.Color,
				relicImageId(definition)
			)
		end
	elseif category == "Sword" then
		local entry = weightedChoice(RewardWheelCatalog.RewardPools.Sword, function(candidate)
			return candidate.Weight
		end)
		local definition = entry and SwordCatalog.Get(entry.Id)
		if definition then
			return visualEntry(
				"Sword",
				definition.SwordId,
				definition.DisplayName,
				definition.Icon,
				definition.Color,
				swordImageId(definition)
			)
		end
	elseif category == "Companion" then
		local entry = weightedChoice(RewardWheelCatalog.RewardPools.Companion, function(candidate)
			return candidate.Weight
		end)
		if entry then
			return visualEntry("Companion", entry.Id, entry.DisplayName, nil, nil, companionImageId(entry.Id))
		end
	end
	return visualEntry("Coins", "Coins", "Moedas")
end

local function resultVisualEntry(result)
	return visualEntry(result.Category, result.RewardId, result.DisplayName, result.Icon, result.Color, result.ImageId)
end

local function buildWheel(source, result)
	local slotCount = math.clamp(math.floor(tonumber(RewardWheelCatalog.WheelSlotCount) or 10), 8, 12)
	local winningSlot = random:NextInteger(1, slotCount)
	local slots = table.create(slotCount)
	for index = 1, slotCount do
		slots[index] = if index == winningSlot then resultVisualEntry(result) else randomVisualEntry(source)
	end
	return slots, winningSlot
end

function RewardWheelService.Start()
	if started then
		return
	end
	started = true
	event = ensureRemote()
	ScoreService.Start()
	CompanionService.Start()
end

function RewardWheelService.Spin(player, sourceId, context)
	if not started then
		RewardWheelService.Start()
	end
	if not player or player.Parent ~= Players then
		return false, "Jogador inválido."
	end
	local source = RewardWheelCatalog.GetSource(sourceId)
	if not source then
		return false, "Origem de roleta inválida."
	end
	PlayerDataService.Load(player)
	local _, category = weightedChoice(source.CategoryWeights, function(weight)
		return weight
	end)
	local granter = category and GRANTERS[category]
	local result = granter and granter(player, sourceId, source, context or nil)
	if not result then
		result = grantCoins(player, sourceId, source, context or nil)
	end
	if not result then
		return false, "Não foi possível conceder a recompensa."
	end
	local categoryInfo = RewardWheelCatalog.GetCategoryInfo(result.Category)
	result.Icon = result.Icon or (categoryInfo and categoryInfo.Icon) or "🎁"
	result.Color = result.Color or (categoryInfo and categoryInfo.Color) or Color3.fromRGB(255, 255, 255)
	result.SourceId = sourceId
	result.SourceName = source.DisplayName
	spinSerial += 1
	result.SpinId = spinSerial
	local wheelEntries, winningSlot = buildWheel(source, result)
	local minimumRotations = math.max(3, math.floor(tonumber(RewardWheelCatalog.MinimumFullRotations) or 5))
	local maximumRotations =
		math.max(minimumRotations, math.floor(tonumber(RewardWheelCatalog.MaximumFullRotations) or 7))

	player:SetAttribute("LastRewardWheelSource", sourceId)
	player:SetAttribute("LastRewardWheelCategory", result.Category)
	player:SetAttribute("LastRewardWheelRewardId", result.RewardId)
	player:SetAttribute("LastRewardWheelOriginalRewardId", result.OriginalRewardId)
	player:SetAttribute("LastRewardWheelReward", result.DisplayName)
	player:SetAttribute("LastRewardWheelSerial", spinSerial)
	local spinAgainAvailable = RewardWheelCatalog.IsSpinAgainSource(sourceId)
	if spinAgainAvailable then
		player:SetAttribute("SpinAgainOfferSource", sourceId)
		player:SetAttribute("SpinAgainOfferLevel", math.max(
			1,
			math.floor(tonumber(context and context.Level) or 1)
		))
		player:SetAttribute("SpinAgainOfferSerial", spinSerial)
		player:SetAttribute(
			"SpinAgainOfferUntil",
			workspace:GetServerTimeNow() + RewardWheelCatalog.AnimationDuration + 15
		)
	else
		player:SetAttribute("SpinAgainOfferSource", nil)
		player:SetAttribute("SpinAgainOfferLevel", nil)
		player:SetAttribute("SpinAgainOfferSerial", nil)
		player:SetAttribute("SpinAgainOfferUntil", nil)
	end
	local uiMode = source.UiMode or "Modal"
	player:SetAttribute("LastRewardWheelUiMode", uiMode)
	player:SetAttribute("LastRewardWheelUiProtocolVersion", RewardWheelCatalog.UiProtocolVersion)
	event:FireClient(player, {
		Action = "Spin",
		Duration = RewardWheelCatalog.AnimationDuration,
		UiMode = uiMode,
		UiProtocolVersion = RewardWheelCatalog.UiProtocolVersion,
		Result = result,
		SpinAgainAvailable = spinAgainAvailable,
		WheelEntries = wheelEntries,
		WinningSlot = winningSlot,
		FullRotations = random:NextInteger(minimumRotations, maximumRotations),
	})
	if sourceId ~= "PaidSpin" and sourceId ~= "RewardedAd" then
		MarketingOfferService.Record(player, "WheelSpin", 1)
	end
	if not (context and context.DeferSave == true) then
		task.spawn(PlayerDataService.Save, player, false)
	end
	return true, result
end

return RewardWheelService
