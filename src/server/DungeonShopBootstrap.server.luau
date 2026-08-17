-- Loja permanente do Dungeon. A interface apenas abre prompts; toda compra e
-- todo recibo continuam validados por MonetizationService no servidor.

local MonetizationService = require(script.Parent.MVPSystems.MonetizationService)

local success, err = pcall(MonetizationService.Start)
workspace:SetAttribute("DungeonShopReady", success)
workspace:SetAttribute("DungeonShopVersion", "DungeonShopV1CoreBenefits")
if not success then
	warn("[DungeonShopBootstrap] " .. tostring(err))
end
