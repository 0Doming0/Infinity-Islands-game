local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RouletteConfig = require(ReplicatedStorage.Shared.Configs.RouletteConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PlayerDataService = require(script.Parent.LobbyPlayerDataService)

local LobbyRouletteService = {}
local random = Random.new()
local spinning = setmetatable({}, { __mode = "k" })
local request
local event
local started = false

local function chooseReward(rewards)
	local total = 0
	for _, reward in ipairs(rewards) do
		total += math.max(0, tonumber(reward.Weight) or 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = random:NextNumber(0, total)
	local accumulated = 0
	for _, reward in ipairs(rewards) do
		accumulated += math.max(0, tonumber(reward.Weight) or 0)
		if roll <= accumulated then
			return reward
		end
	end
	return rewards[#rewards]
end

local function hasCompanionSpecies(player, speciesId)
	local owned = PlayerDataService.GetCompanions(player)
	for _, record in pairs(owned) do
		if record.SpeciesId == speciesId then
			return true
		end
	end
	return false
end

local function compensation(player, wheel, reward)
	local amount = math.max(1, math.floor(tonumber(wheel.DuplicateCompensation) or 1))
	PlayerDataService.AddCoins(player, amount)
	return {
		RewardType = "Coins",
		RewardId = "Coins",
		Amount = amount,
		DuplicateOf = reward.RewardId,
		ConvertedDuplicate = true,
	}
end

local function grantReward(player, wheel, reward)
	local amount = math.max(1, math.floor(tonumber(reward.Amount) or 1))
	if reward.RewardType == "Coins" then
		PlayerDataService.AddCoins(player, amount)
	elseif reward.RewardType == "Sword" then
		if PlayerDataService.HasSword(player, reward.RewardId) then
			return compensation(player, wheel, reward)
		end
		if not PlayerDataService.GrantSword(player, reward.RewardId) then
			return nil
		end
	elseif reward.RewardType == "Companion" then
		if hasCompanionSpecies(player, reward.RewardId) then
			return compensation(player, wheel, reward)
		end
		local success = PlayerDataService.UnlockCompanion(player, reward.RewardId, reward.RewardId)
		if not success then
			return nil
		end
	elseif reward.RewardType == "Ticket" then
		if not PlayerDataService.AddTicket(player, reward.RewardId, amount) then
			return nil
		end
	else
		return nil
	end
	return {
		RewardType = reward.RewardType,
		RewardId = reward.RewardId,
		Amount = amount,
		ConvertedDuplicate = false,
	}
end

local function snapshot(player, wheelId)
	local data = PlayerDataService.Get(player)
	local wheel = RouletteConfig[wheelId]
	return {
		WheelId = wheelId,
		DisplayName = wheel and wheel.DisplayName or wheelId,
		CostType = wheel and wheel.CostType,
		CostAmount = wheel and wheel.CostAmount,
		Coins = data and data.Coins or 0,
		Tickets = data and table.clone(data.Tickets) or {},
		TotalSpins = data and data.Roulette.TotalSpins or 0,
	}
end

local function removeCost(player, wheel)
	if wheel.CostType == "Coins" then
		return PlayerDataService.TrySpendCoins(player, wheel.CostAmount)
	elseif wheel.CostType == "Ticket" then
		return PlayerDataService.RemoveTicket(player, wheel.CostId, wheel.CostAmount)
	end
	return false
end

local function refundCost(player, wheel)
	if wheel.CostType == "Coins" then
		PlayerDataService.AddCoins(player, wheel.CostAmount)
	elseif wheel.CostType == "Ticket" then
		PlayerDataService.AddTicket(player, wheel.CostId, wheel.CostAmount)
	end
end

local function spin(player, wheelId)
	if spinning[player] then
		return { Success = false, Message = "Aguarde o giro atual terminar." }
	end
	local wheel = RouletteConfig[wheelId]
	if not wheel then
		return { Success = false, Message = "Roleta invalida." }
	end
	PlayerDataService.Load(player)
	spinning[player] = true
	local paid = removeCost(player, wheel)
	if not paid then
		spinning[player] = nil
		return { Success = false, Message = "Saldo insuficiente.", Snapshot = snapshot(player, wheelId) }
	end
	local selected = chooseReward(wheel.Rewards)
	local result = selected and grantReward(player, wheel, selected)
	if not result then
		refundCost(player, wheel)
		spinning[player] = nil
		return { Success = false, Message = "Nao foi possivel conceder o premio." }
	end
	PlayerDataService.RecordRouletteSpin(player)
	local saved = PlayerDataService.Save(player, true)
	local payload = {
		Action = "SpinResult",
		WheelId = wheelId,
		Result = result,
		Duration = 3.5,
		Saved = saved == true,
		Snapshot = snapshot(player, wheelId),
	}
	event:FireClient(player, payload)
	task.delay(3.5, function()
		spinning[player] = nil
	end)
	return { Success = true, Result = result, Snapshot = payload.Snapshot }
end

function LobbyRouletteService.Open(player, wheelId)
	if not RouletteConfig[wheelId] then
		return false
	end
	event:FireClient(player, { Action = "Open", Snapshot = snapshot(player, wheelId) })
	return true
end

function LobbyRouletteService.Start()
	if started then
		return
	end
	started = true
	request = RemoteRegistry.Get("Roulette", "Request", "RemoteFunction")
	event = RemoteRegistry.Get("Roulette", "Event", "RemoteEvent")
	request.OnServerInvoke = function(player, action, wheelId)
		if action == "Get" then
			return { Success = RouletteConfig[wheelId] ~= nil, Snapshot = snapshot(player, wheelId) }
		elseif action == "Spin" then
			return spin(player, wheelId)
		end
		return { Success = false, Message = "Acao invalida." }
	end
	Players.PlayerRemoving:Connect(function(player)
		spinning[player] = nil
	end)
end

return LobbyRouletteService
