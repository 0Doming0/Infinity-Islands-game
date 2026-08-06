-- Publica o loadout persistente para os sistemas funcionais da dungeon.
-- Espadas e companheiros continuam sendo materializados pelos serviços existentes.

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.Parent.BlockParkour.PlayerDataService_SkyDungeon_V10)

local function publish(player)
	local data = PlayerDataService.Load(player)
	player:SetAttribute("EquippedSword", data.EquippedSword)
	player:SetAttribute("EquippedWings", data.EquippedWings)
	player:SetAttribute("EquippedAbility", data.EquippedAbility)
	player:SetAttribute("LobbyCombatDisabled", false)
	player:SetAttribute("AbilitiesDisabled", false)
	player:SetAttribute("CompanionCombatDisabled", false)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(publish, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(publish, player)
end
