-- Roteador único de Developer Products.
-- MarketplaceService.ProcessReceipt só pode possuir um callback; cada sistema
-- registra aqui seu ProductId sem sobrescrever as compras dos demais.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DeveloperProductService = {}
local handlers = {}
local started = false

function DeveloperProductService.Register(productId, name, callback)
	local cleanId = math.max(0, math.floor(tonumber(productId) or 0))
	if cleanId <= 0 then
		return false
	end
	assert(type(callback) == "function", "Callback de Developer Product inválido.")
	local existing = handlers[cleanId]
	if existing and existing.Callback ~= callback then
		warn(string.format(
			"[DeveloperProductService] ProductId %d já pertence a %s; %s foi ignorado.",
			cleanId,
			existing.Name,
			tostring(name)
		))
		return false
	end
	handlers[cleanId] = {
		Name = tostring(name or cleanId),
		Callback = callback,
	}
	return true
end

local function processReceipt(receipt)
	local handler = handlers[receipt.ProductId]
	if not handler then
		warn(string.format(
			"[DeveloperProductService] Nenhum handler para ProductId %s.",
			tostring(receipt.ProductId)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local success, granted = pcall(handler.Callback, player, receipt)
	if not success then
		warn(string.format(
			"[DeveloperProductService] Falha em %s: %s",
			handler.Name,
			tostring(granted)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return granted == true
		and Enum.ProductPurchaseDecision.PurchaseGranted
		or Enum.ProductPurchaseDecision.NotProcessedYet
end

function DeveloperProductService.Start()
	if started then
		return
	end
	started = true
	MarketplaceService.ProcessReceipt = processReceipt
end

return DeveloperProductService
