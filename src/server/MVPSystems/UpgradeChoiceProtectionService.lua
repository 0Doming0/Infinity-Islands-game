-- Compatibilidade para sistemas antigos de escolha de upgrade.
--
-- No MVP linear nenhuma melhoria deve pausar/proteger o jogador. Begin/End sao
-- mantidos para preservar a API dos sistemas antigos, mas nunca criam ForceField
-- nem alteram combate/movimento.

local Players = game:GetService("Players")

local Service = {}

local function publishInactive(player)
	if not player or player.Parent ~= Players then
		return
	end
	local character = player.Character
	local old = character and character:FindFirstChild("DungeonUpgradeChoiceProtection")
	if old and old:IsA("ForceField") then
		old:Destroy()
	end
	player:SetAttribute("DungeonUpgradeProtectionActive", false)
	player:SetAttribute("DungeonUpgradeProtectionCount", 0)
	player:SetAttribute("DungeonUpgradeProtectionReason", nil)
end

function Service.Begin(player, _source)
	publishInactive(player)
	return player ~= nil and player.Parent == Players
end

function Service.End(player, _source)
	publishInactive(player)
	return player ~= nil
end

function Service.BeginTimed(player, _source, _duration)
	publishInactive(player)
	return player ~= nil and player.Parent == Players
end

function Service.Clear(player)
	publishInactive(player)
end

Players.PlayerAdded:Connect(function(player)
	task.defer(publishInactive, player)
end)
Players.PlayerRemoving:Connect(Service.Clear)
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(publishInactive, player)
end

workspace:SetAttribute("DungeonUpgradeChoiceProtectionDisabled", true)
workspace:SetAttribute("DungeonUpgradeChoicePolicy", "NeverInterruptCombat")

return Service
