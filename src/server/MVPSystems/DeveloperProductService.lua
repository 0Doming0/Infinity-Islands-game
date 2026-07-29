-- Roteador único de Developer Products.
-- MarketplaceService.ProcessReceipt só pode possuir um callback; cada sistema
-- registra aqui seu go sem sobrescrever as compras dos demais.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local PlayerDataService = require(
	script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)

local DeveloperProductService = {}
local handlers = {}
local processing = {}
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
	local purchaseId = tostring(receipt.PurchaseId or "")
	if purchaseId == "" then
		warn(string.format(
			"[DeveloperProductService] Recibo do produto %s chegou sem PurchaseId.",
			tostring(receipt.ProductId)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if processing[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processing[purchaseId] = true

	local loaded, loadError = pcall(PlayerDataService.Load, player)
	if not loaded or not PlayerDataService.CanSave(player) then
		processing[purchaseId] = nil
		warn(string.format(
			"[DeveloperProductService] Dados persistentes indisponiveis para %s: %s",
			player.Name,
			tostring(loadError)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if PlayerDataService.HasProcessedPurchase(player, purchaseId) then
		local saved = PlayerDataService.Save(player, true)
		processing[purchaseId] = nil
		return saved
			and Enum.ProductPurchaseDecision.PurchaseGranted
			or Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local success, granted = pcall(handler.Callback, player, receipt)
	if not success then
		processing[purchaseId] = nil
		warn(string.format(
			"[DeveloperProductService] Falha em %s: %s",
			handler.Name,
			tostring(granted)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted ~= true
		or not PlayerDataService.MarkProcessedPurchase(player, purchaseId)
	then
		processing[purchaseId] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- A recompensa e o PurchaseId fazem parte do mesmo snapshot. O recibo so
	-- e confirmado depois que ambos foram persistidos.
	local saved = PlayerDataService.Save(player, true)
	processing[purchaseId] = nil
	if not saved then
		warn(string.format(
			"[DeveloperProductService] Recibo %s concedido em memoria, mas ainda nao salvo.",
			purchaseId
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function DeveloperProductService.Start()
	if started then
		return
	end
	started = true
	MarketplaceService.ProcessReceipt = processReceipt
end

return DeveloperProductService
