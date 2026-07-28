-- Inventario persistente e uso autoritativo de consumiveis.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage:WaitForChild("ItemCatalog"))
local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)
local MarketingOfferService = require(script.Parent:WaitForChild("MarketingOfferService"))

local InventoryService = {}
local started = false
local event
local request

local function ensureRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = name
		existing.Parent = ReplicatedStorage
	end
	return existing
end

function InventoryService.GetSnapshot(player)
	local inventory = PlayerDataService.GetInventory(player)
	local entries = {}
	for _, definition in ipairs(ItemCatalog.GetAll()) do
		local amount = inventory[definition.ItemId] or 0
		if amount > 0 then
			table.insert(entries, {
				ItemId = definition.ItemId,
				DisplayName = definition.DisplayName,
				Description = definition.Description,
				Amount = amount,
				Color = definition.Color,
			})
		end
	end
	return {
		Entries = entries,
		Capacity = 24,
	}
end

function InventoryService.Push(player, message, success)
	if event and player.Parent == Players then
		event:FireClient(player, {
			Action = "Update",
			Inventory = InventoryService.GetSnapshot(player),
			Message = message,
			Success = success,
		})
	end
end

function InventoryService.GrantItem(player, itemId, amount)
	local definition = ItemCatalog.Get(itemId)
	if not definition then
		return false, "Item invalido."
	end
	local success = PlayerDataService.AddItem(player, itemId, amount or 1, definition.MaximumStack)
	if not success then
		return false, "Voce atingiu o limite deste item."
	end
	InventoryService.Push(player, definition.DisplayName .. " adicionado!", true)
	return true
end

local function getLivingHumanoid(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function applyTimedModifier(player, humanoid, definition)
	local untilName = definition.Effect .. "BuffUntil"
	player:SetAttribute(untilName, workspace:GetServerTimeNow() + definition.Duration)
	if definition.Effect == "Speed" then
		humanoid.WalkSpeed += definition.Amount
	elseif humanoid.UseJumpPower then
		humanoid.JumpPower += definition.Amount
	else
		humanoid.JumpHeight += definition.HeightAmount
	end
	task.delay(definition.Duration, function()
		if humanoid.Parent == nil then
			return
		end
		if definition.Effect == "Speed" then
			humanoid.WalkSpeed = math.max(16, humanoid.WalkSpeed - definition.Amount)
		elseif humanoid.UseJumpPower then
			humanoid.JumpPower = math.max(50, humanoid.JumpPower - definition.Amount)
		else
			humanoid.JumpHeight = math.max(7.2, humanoid.JumpHeight - definition.HeightAmount)
		end
		player:SetAttribute(untilName, nil)
	end)
end

function InventoryService.UseItem(player, itemId)
	local definition = ItemCatalog.Get(itemId)
	local humanoid = getLivingHumanoid(player)
	if not definition or not humanoid then
		return false, "Item indisponivel agora."
	end
	if PlayerDataService.GetItemAmount(player, itemId) <= 0 then
		return false, "Voce nao possui este item."
	end
	if definition.Effect == "Heal" and humanoid.Health >= humanoid.MaxHealth then
		return false, "Sua vida ja esta cheia."
	end
	if (definition.Effect == "Speed" or definition.Effect == "Jump")
		and (tonumber(player:GetAttribute(definition.Effect .. "BuffUntil")) or 0) > workspace:GetServerTimeNow()
	then
		return false, "Este efeito ainda esta ativo."
	end
	local removed = PlayerDataService.RemoveItem(player, itemId, 1)
	if not removed then
		return false, "Item indisponivel."
	end

	if definition.Effect == "Heal" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + definition.Amount)
		MarketingOfferService.Record(player, "HealUsed", 1)
	elseif definition.Effect == "Speed" or definition.Effect == "Jump" then
		applyTimedModifier(player, humanoid, definition)
	else
		return false, "Efeito nao configurado."
	end
	InventoryService.Push(player, definition.DisplayName .. " usado!", true)
	return true
end

function InventoryService.Start()
	if started then
		return
	end
	started = true
	event = ensureRemote("RemoteEvent", "InventoryEvent")
	request = ensureRemote("RemoteFunction", "InventoryRequest")
	request.OnServerInvoke = function(player, action, itemId)
		if action == "Get" then
			return InventoryService.GetSnapshot(player)
		elseif action == "Use" and type(itemId) == "string" then
			local success, message = InventoryService.UseItem(player, itemId)
			return { Success = success, Message = message, Inventory = InventoryService.GetSnapshot(player) }
		end
		return { Success = false, Message = "Pedido invalido." }
	end

	local function setup(player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("SpeedBuffUntil", nil)
			player:SetAttribute("JumpBuffUntil", nil)
		end)
		task.spawn(function()
			PlayerDataService.Load(player)
			InventoryService.Push(player)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
end

return InventoryService
