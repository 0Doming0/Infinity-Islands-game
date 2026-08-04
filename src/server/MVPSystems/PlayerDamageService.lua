-- Ponto unico para dano causado por inimigos aos jogadores.
--
-- Reune todas as protecoes autoritativas antes do DownedService:
-- santuarios, resgate, tutorial, respawn, ForceField e linha de visao.
-- O tutorial agora controla explicitamente quando a protecao de iniciante esta
-- ativa, evitando imunidade ilimitada no mapa procedural compartilhado.

local Players = game:GetService("Players")

local DownedService = require(script.Parent:WaitForChild("DownedService"))
local GameplayAnalytics = require(
	script.Parent.Parent:WaitForChild("GameplayAnalyticsService")
)

DownedService.Start()

local PlayerDamageService = {}
local VERSION = "AuthoritativeProtectionAnalyticsV3"

workspace:SetAttribute("PlayerDamageProtectionVersion", VERSION)

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function hasTutorialEnemyProtection(player)
	-- TutorialService publica um booleano autoritativo. Durante o carregamento de
	-- servidores antigos, a ausencia do atributo preserva o comportamento seguro.
	local explicitProtection = player:GetAttribute("TutorialEnemyProtection")
	if typeof(explicitProtection) == "boolean" then
		return explicitProtection == true
			and player:GetAttribute("TutorialCompleted") ~= true
	end
	return player:GetAttribute("TutorialCompleted") ~= true
end

local function activeForceField(character)
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("ForceField") then
			return child
		end
	end
	return nil
end

local function hasSafeZoneOrRescueProtection(player)
	local rescueState = tostring(
		player:GetAttribute("SanctuaryRescueState") or "Idle"
	)
	local rescueProtectionUntil = tonumber(
		player:GetAttribute("SanctuaryRescueProtectionUntil")
	) or 0

	local rescueProtected = rescueState == "Searching"
		or rescueState == "Teleporting"
		or rescueState == "Stabilizing"
		or serverTime() < rescueProtectionUntil

	if player:GetAttribute("InSafeZone") == true then
		return true, "SafeZone"
	end
	if rescueProtected then
		return true, "SanctuaryRescue:" .. rescueState
	end
	return false, nil
end

local function hasRespawnProtection(player, character)
	local protectionUntil = tonumber(
		player:GetAttribute("RespawnProtectionUntil")
	) or 0

	if
		player:GetAttribute("RespawnProtectionActive") == true
		and protectionUntil > serverTime()
	then
		return true, "RespawnProtectionAttribute"
	end

	local forceField = activeForceField(character)
	if forceField then
		return true, "ForceField:" .. forceField.Name
	end

	return false, nil
end

local function rangedAreaAttackIsBlocked(player, source)
	-- Atualmente SlimeArea e o dano de impacto dos morteiros.
	-- O sistema de raycast publica quantos atacantes a distancia possuem
	-- linha de visao real para este jogador no momento da explosao.
	if tostring(source or "") ~= "SlimeArea" then
		return false
	end

	local visibleThreatCount = math.max(
		0,
		math.floor(
			tonumber(player:GetAttribute("RangedVisibleThreatCount")) or 0
		)
	)
	return visibleThreatCount <= 0
end

local function recordBlockedDamage(player, source, amount, reason)
	local timestamp = serverTime()

	player:SetAttribute(
		"LastProtectedDamageSource",
		tostring(source or "Enemy")
	)
	player:SetAttribute(
		"LastProtectedDamageAmount",
		math.max(0, tonumber(amount) or 0)
	)
	player:SetAttribute(
		"LastProtectedDamageReason",
		tostring(reason or "Protected")
	)
	player:SetAttribute("LastProtectedDamageAt", timestamp)
	player:SetAttribute(
		"ProtectedDamageBlockedCount",
		math.max(
			0,
			math.floor(
				tonumber(
					player:GetAttribute("ProtectedDamageBlockedCount")
				) or 0
			)
		) + 1
	)
end

local function recordSpecialProtection(player, source, reason)
	local timestamp = serverTime()
	local sourceName = tostring(source or "Enemy")

	if reason == "TutorialEnemyProtection" then
		player:SetAttribute("TutorialEnemyProtection", true)
		player:SetAttribute(
			"LastTutorialBlockedEnemySource",
			sourceName
		)
		player:SetAttribute("LastTutorialBlockedEnemyAt", timestamp)
	elseif reason == "SafeZone"
		or string.sub(reason, 1, #"SanctuaryRescue:") == "SanctuaryRescue:"
	then
		player:SetAttribute(
			"LastSafeZoneBlockedEnemySource",
			sourceName
		)
		player:SetAttribute("LastSafeZoneBlockedEnemyAt", timestamp)
	end
end

function PlayerDamageService.IsProtected(player, humanoid)
	if not player or player.Parent ~= Players then
		return true, "InvalidPlayer"
	end

	local character = humanoid and humanoid.Parent or player.Character

	if player:GetAttribute("IsDowned") == true then
		return true, "AlreadyDowned"
	end
	if player:GetAttribute("InvisibleToEnemies") == true then
		return true, "InvisibleToEnemies"
	end

	local protected, reason = hasSafeZoneOrRescueProtection(player)
	if protected then
		return true, reason
	end

	if hasTutorialEnemyProtection(player) then
		return true, "TutorialEnemyProtection"
	end

	protected, reason = hasRespawnProtection(player, character)
	if protected then
		return true, reason
	end

	return false, nil
end

function PlayerDamageService.Apply(player, humanoid, baseDamage, source)
	if
		not player
		or player.Parent ~= Players
		or not humanoid
		or humanoid.Health <= 0
	then
		return 0
	end

	local protected, protectionReason =
		PlayerDamageService.IsProtected(player, humanoid)

	if protected then
		-- Estados passivos como ja estar derrubado ou invisivel nao precisam
		-- incrementar telemetria de dano bloqueado a cada tentativa da IA.
		if
			protectionReason ~= "AlreadyDowned"
			and protectionReason ~= "InvisibleToEnemies"
			and protectionReason ~= "InvalidPlayer"
		then
			recordSpecialProtection(
				player,
				source,
				protectionReason
			)
			recordBlockedDamage(
				player,
				source,
				baseDamage,
				protectionReason
			)
		end
		return 0
	end

	-- Camada final para morteiros que ja estavam em voo quando o jogador
	-- entrou atras de uma parede. O guardiao de raycast publica a contagem
	-- de ameacas que realmente possuem linha de visao para este jogador.
	if rangedAreaAttackIsBlocked(player, source) then
		recordBlockedDamage(
			player,
			source,
			baseDamage,
			"RangedLineOfSightBlocked"
		)
		return 0
	end

	local multiplier = math.max(
		1,
		tonumber(
			player:GetAttribute("RunDamageTakenMultiplier")
		) or 1
	)
	local damage = math.max(0, tonumber(baseDamage) or 0) * multiplier

	if damage <= 0 then
		return 0
	end

	player:SetAttribute("LastEnemyDamage", damage)
	player:SetAttribute(
		"LastEnemyDamageSource",
		tostring(source or "Enemy")
	)
	player:SetAttribute("LastDamageReceivedAt", serverTime())

	-- Analytics representa somente encontros que realmente chegaram a causar
	-- dano. Ataques bloqueados por protecao ou cobertura nao poluem a metrica.
	GameplayAnalytics.RecordEnemyEncountered(player, nil)
	GameplayAnalytics.RecordPlayerDamagedByEnemy(player, source)

	-- Toda protecao ja foi resolvida antes desta chamada. Assim um ataque fatal
	-- nunca transforma o jogador em derrubado durante respawn ou ForceField.
	if DownedService.TryInterceptFatal(
		player,
		humanoid,
		damage,
		source
	) then
		return damage
	end

	humanoid:TakeDamage(damage)
	return damage
end

function PlayerDamageService.ApplyToHumanoid(
	humanoid,
	baseDamage,
	source
)
	local character = humanoid and humanoid.Parent
	local player = character
		and Players:GetPlayerFromCharacter(character)

	return PlayerDamageService.Apply(
		player,
		humanoid,
		baseDamage,
		source
	)
end

return table.freeze(PlayerDamageService)
