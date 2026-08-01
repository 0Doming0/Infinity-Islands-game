-- Ponto único para dano causado por inimigos aos jogadores.
-- Jogadores com tutorial incompleto continuam protegidos em qualquer spawn ou
-- servidor. Perigos ambientais, como a agua, nao passam por este servico.

local Players = game:GetService("Players")
local DownedService = require(script.Parent:WaitForChild("DownedService"))
DownedService.Start()

local PlayerDamageService = {}

local function hasTutorialEnemyProtection(player)
	-- TutorialCompleted e a fonte autoritativa. O valor nil durante o load deve
	-- ser tratado como incompleto para nao abrir uma janela de dano na entrada.
	return player:GetAttribute("TutorialCompleted") ~= true
end

function PlayerDamageService.Apply(player, humanoid, baseDamage, source)
	if not player or player.Parent ~= Players or not humanoid or humanoid.Health <= 0 then
		return 0
	end
	if player:GetAttribute("IsDowned") == true then
		return 0
	end
	if player:GetAttribute("InvisibleToEnemies") == true then
		return 0
	end
	if hasTutorialEnemyProtection(player) then
		player:SetAttribute("TutorialEnemyProtection", true)
		player:SetAttribute("LastTutorialBlockedEnemySource", tostring(source or "Enemy"))
		player:SetAttribute("LastTutorialBlockedEnemyAt", workspace:GetServerTimeNow())
		return 0
	end
	local multiplier = math.max(1, tonumber(player:GetAttribute("RunDamageTakenMultiplier")) or 1)
	local damage = math.max(0, tonumber(baseDamage) or 0) * multiplier
	if damage <= 0 then
		return 0
	end
	player:SetAttribute("LastEnemyDamage", damage)
	player:SetAttribute("LastEnemyDamageSource", tostring(source or "Enemy"))
	player:SetAttribute("LastDamageReceivedAt", workspace:GetServerTimeNow())
	if DownedService.TryInterceptFatal(player, humanoid, damage, source) then
		return damage
	end
	humanoid:TakeDamage(damage)
	return damage
end

function PlayerDamageService.ApplyToHumanoid(humanoid, baseDamage, source)
	local character = humanoid and humanoid.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	return PlayerDamageService.Apply(player, humanoid, baseDamage, source)
end

return table.freeze(PlayerDamageService)
