-- Compatibilidade para sistemas MVP antigos.
-- A unica fonte de verdade fica em BlockParkour/PlayerDataService_SkyDungeon_V10.

local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local Canonical = require(BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local ScoreService = require(BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))

local Compatibility = {}

function Compatibility.Start()
	ScoreService.Start()
end

function Compatibility.IsLoaded(player)
	return Canonical.Get(player) ~= nil
end

function Compatibility.GetSnapshot(player)
	return Canonical.GetSnapshot(player)
end

function Compatibility.AddCoins(player, amount)
	return ScoreService.AwardCoins(player, amount, "LegacyMVP") > 0, ScoreService.GetCoins(player)
end

function Compatibility.TrySpendCoins(player, amount)
	return ScoreService.TrySpendCoins(player, amount)
end

function Compatibility.AddScore(player, amount)
	local awarded = ScoreService.Award(player, amount, "LegacyMVP")
	return awarded > 0, ScoreService.GetRunScore(player), ScoreService.GetBestScore(player)
end

function Compatibility.GrantAttemptRewards(player, scoreAmount, coinAmount)
	local score, coins = ScoreService.AwardRewards(player, scoreAmount, coinAmount, "LegacyMVP")
	return score > 0 or coins > 0, ScoreService.GetRunScore(player), ScoreService.GetCoins(player), ScoreService.GetBestScore(player)
end

function Compatibility.AddOwnedItem(player, itemId, amount, _stackable)
	return Canonical.AddItem(player, itemId, amount)
end

function Compatibility.SetEquipped(_player, _slot, _itemId)
	return false, "UseInventoryService"
end

return Compatibility
