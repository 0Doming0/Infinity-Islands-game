-- V17: dano autoritativo com janela anti-stunlock para os monstros.
-- Preserva dano, impactos, som dos companheiros e efeitos de reliquias.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local GameplayAnalytics = require(script.Parent.Parent:WaitForChild("GameplayAnalyticsService"))

local DamageService = {}

local DEFAULT_STUN_REACTION_WINDOW = 1.1
local MIN_STUN_REACTION_WINDOW = 0.35
local MAX_STUN_REACTION_WINDOW = 3

local function mitigatedDamage(model, rawAmount)
	local raw = math.max(0, tonumber(rawAmount) or 0)
	local defense = math.max(0, tonumber(model:GetAttribute("Defense")) or 0)
	local multiplier = math.max(0, tonumber(model:GetAttribute("DamageMultiplier")) or 1)
	if raw <= 0 or multiplier <= 0 then
		return 0
	end
	return math.max(1, (raw - defense) * multiplier)
end

local function tagCreator(humanoid, player)
	local old = humanoid:FindFirstChild("creator")
	if old then
		old:Destroy()
	end

	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"
	creator.Value = player
	creator.Parent = humanoid
	Debris:AddItem(creator, 3)
end

DamageService.TagCreator = tagCreator

local function playHitSound(model)
	local hitSound = model:FindFirstChild("hit", true)

	if not hitSound or not hitSound:IsA("Sound") then
		return
	end

	hitSound:Stop()
	hitSound.TimePosition = 0
	hitSound:Play()
end

local function createImpact(position, color, heavy)
	local anchor = Instance.new("Part")
	anchor.Name = "SwordImpact"
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = heavy and Vector3.new(0.85, 0.85, 0.85) or Vector3.new(0.55, 0.55, 0.55)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Material = Enum.Material.Neon
	anchor.Color = color
	anchor.Transparency = 0.08
	anchor.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = heavy and 2.5 or 1.6
	light.Range = heavy and 10 or 7
	light.Parent = anchor

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "SwordImpactParticles"
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 0.85
	particles.Lifetime = NumberRange.new(0.12, 0.28)
	particles.Speed = heavy and NumberRange.new(10, 17) or NumberRange.new(7, 12)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Drag = 5
	particles.Rate = 0
	particles.Parent = anchor
	particles:Emit(heavy and 16 or 10)

	task.delay(0.05, function()
		if anchor.Parent then
			anchor.Transparency = 0.55
			light.Brightness *= 0.35
		end
	end)
	Debris:AddItem(anchor, 0.30)
end

local RELIC_IMPACT_COLORS = {
	LightningRelic = Color3.fromRGB(255, 231, 70),
	FireRelic = Color3.fromRGB(255, 92, 45),
}

local function applyCombatStun(model, humanoid, attack)
	if model:GetAttribute("CanBeStunned") == false then
		return
	end
	local resistance = math.clamp(tonumber(model:GetAttribute("StunResistance")) or 0, 0, 1)
	if resistance >= 1 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local immunityUntil = tonumber(model:GetAttribute("CombatStunImmunityUntil")) or 0
	if now < immunityUntil then
		-- O dano e o feedback do golpe continuam normais. Somente um novo stun
		-- e uma nova interrupcao sao bloqueados durante a janela de reacao.
		return
	end
	local stunTokenId = (model:GetAttribute("CombatStunTokenId") or 0) + 1
	local interruptSerial = (model:GetAttribute("CombatInterruptSerial") or 0) + 1
	local stunDuration = math.clamp((tonumber(attack.StunDuration) or 0.45) * (1 - resistance), 0.05, 1.25)
	local reactionWindow = math.clamp(
		tonumber(model:GetAttribute("StunReactionWindow")) or DEFAULT_STUN_REACTION_WINDOW,
		MIN_STUN_REACTION_WINDOW,
		MAX_STUN_REACTION_WINDOW
	)
	local newImmunityUntil = now + stunDuration + reactionWindow

	model:SetAttribute("CombatStunTokenId", stunTokenId)
	-- Nao e apagado no fim do stun: ataques com windup usam este serial para
	-- saber que foram interrompidos, mesmo se uma task atrasada rodar depois.
	model:SetAttribute("CombatInterruptSerial", interruptSerial)
	model:SetAttribute("CombatStunned", true)
	model:SetAttribute("CombatStunnedUntil", now + stunDuration)
	model:SetAttribute("CombatStunImmunityUntil", newImmunityUntil)

	-- O primeiro golpe guarda o estado original. Golpes seguintes apenas
	-- renovam o token e a duracao, sem substituir os valores verdadeiros.
	if model:GetAttribute("CombatOriginalWalkSpeed") == nil then
		model:SetAttribute("CombatOriginalWalkSpeed", humanoid.WalkSpeed)
	end
	if model:GetAttribute("CombatOriginalAutoRotate") == nil then
		model:SetAttribute("CombatOriginalAutoRotate", humanoid.AutoRotate)
	end

	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)

	task.delay(stunDuration, function()
		if not model.Parent or model:GetAttribute("CombatStunTokenId") ~= stunTokenId then
			return
		end
		if (tonumber(model:GetAttribute("RelicFrozenUntil")) or 0) > workspace:GetServerTimeNow() then
			return
		end
		model:SetAttribute("CombatStunned", nil)
		model:SetAttribute("CombatStunTokenId", nil)
		model:SetAttribute("CombatStunnedUntil", nil)
		model:SetAttribute("CombatKnockbackUntil", nil)
		if humanoid.Parent and humanoid.Health > 0 then
			local originalSpeed = model:GetAttribute("CombatOriginalWalkSpeed")
			local originalAutoRotate = model:GetAttribute("CombatOriginalAutoRotate")
			if typeof(originalSpeed) == "number" then
				humanoid.WalkSpeed = originalSpeed
			end
			if typeof(originalAutoRotate) == "boolean" then
				humanoid.AutoRotate = originalAutoRotate
			end
		end
		model:SetAttribute("CombatOriginalWalkSpeed", nil)
		model:SetAttribute("CombatOriginalAutoRotate", nil)
	end)

	task.delay(stunDuration + reactionWindow, function()
		if
			model.Parent
			and tonumber(model:GetAttribute("CombatStunImmunityUntil")) == newImmunityUntil
		then
			model:SetAttribute("CombatStunImmunityUntil", nil)
		end
	end)
end

function DamageService.ApplyEffectDamage(attacker, target, amount, source)
	if not attacker or attacker.Parent ~= Players or typeof(target) ~= "table" then
		return false, false
	end
	local model = target.Model
	local humanoid = target.Humanoid
	if
		not model
		or not model.Parent
		or not humanoid
		or humanoid.Health <= 0
		or model:GetAttribute("Invulnerable") == true
		or model:GetAttribute("NoSwordDamage") == true
		or Players:GetPlayerFromCharacter(model)
	then
		return false, false
	end
	local damage = mitigatedDamage(model, amount)
	if damage <= 0 then
		return false, false
	end
	local healthBefore = humanoid.Health
	local effectPosition = target.Root and target.Root:IsA("BasePart") and target.Root.Position
		or model:GetPivot().Position
	tagCreator(humanoid, attacker)
	model:SetAttribute("LastDamagedByUserId", attacker.UserId)
	model:SetAttribute("LastRelicDamageSource", tostring(source or "Relic"))
	model:SetAttribute("LastRelicDamage", damage)
	humanoid:TakeDamage(damage)
	local defeated = healthBefore > 0 and humanoid.Health <= 0
	GameplayAnalytics.RecordEnemyAttacked(attacker, model, source or "Relic")
	if defeated then
		GameplayAnalytics.RecordEnemyDefeated(attacker, model, source or "Relic")
	end
	createImpact(
		effectPosition,
		RELIC_IMPACT_COLORS[source] or Color3.fromRGB(190, 130, 255),
		false
	)
	return true, defeated
end

local function applyKnockback(attackerRoot, model, humanoid, root, attack)
	-- Consecutive hit tracking for knockback scaling
	local now = os.clock()
	local lastHitAt = model:GetAttribute("CombatLastHitAt") or 0
	local hitCount = model:GetAttribute("CombatHitCount") or 0
	if now - lastHitAt > 1.5 then
		hitCount = 0
	end
	hitCount += 1
	model:SetAttribute("CombatLastHitAt", now)
	model:SetAttribute("CombatHitCount", hitCount)

	local comboScale = 1 + math.min(2, hitCount - 1) * 0.18
	local resistanceScale = 1 - math.clamp(tonumber(model:GetAttribute("KnockbackResistance")) or 0, 0, 1)
	local horizontalForce = math.max(0, tonumber(attack.Knockback) or 12) * 1.8 * comboScale * resistanceScale
	local upwardForce = math.max(0, tonumber(attack.UpwardKnockback) or 2) * comboScale * resistanceScale
	if resistanceScale <= 0 or horizontalForce <= 0 then
		return
	end

	-- Direction: knock the mob away from the attacker
	local direction = Vector3.new(
		root.Position.X - attackerRoot.Position.X,
		0,
		root.Position.Z - attackerRoot.Position.Z
	)
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(attackerRoot.CFrame.LookVector.X, 0, attackerRoot.CFrame.LookVector.Z)
	else
		direction = direction.Unit
	end

	local velocity = direction * horizontalForce + Vector3.new(0, upwardForce, 0)

	model:SetAttribute("CombatKnockbackUntil", workspace:GetServerTimeNow() + 0.22)

	-- Remove old knockback objects from previous hits
	for _, child in ipairs(root:GetChildren()) do
		if child.Name == "SwordKnockback" or child.Name == "SwordKnockbackAttachment" then
			child:Destroy()
		end
	end

	-- O Mimico e movido por PivotTo e precisa continuar ancorado. Desancorar e
	-- aplicar LinearVelocity faria a fisica disputar com o controlador, causando
	-- tombos, teleporte e impulso acumulado. O recuo e enviado como deslocamento
	-- horizontal para o proprio MimicAI validar contra paredes e bordas.
	if model:GetAttribute("KinematicMovement") == true then
		local displacement = math.clamp(horizontalForce * 0.065, 0.9, 2.4)
		model:SetAttribute("KinematicKnockbackRequest", direction * displacement)
		model:SetAttribute(
			"KinematicKnockbackSerial",
			(model:GetAttribute("KinematicKnockbackSerial") or 0) + 1
		)
		return
	end

	-- Mobs fisicos comuns continuam usando o comportamento original.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Massless then
			descendant.Anchored = false
		end
	end

	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- Apply velocity directly for the initial burst
	root.AssemblyLinearVelocity = velocity

	-- Maintain velocity with LinearVelocity for a short duration so the
	-- knockback is not instantly cancelled by friction / gravity
	local attachment = Instance.new("Attachment")
	attachment.Name = "SwordKnockbackAttachment"
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "SwordKnockback"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = velocity
	linearVelocity.MaxForce = math.clamp(root.AssemblyMass * 10000, 20000, 300000)
	linearVelocity.Parent = root

	local velocityDuration = 0.15

	Debris:AddItem(linearVelocity, velocityDuration + 0.02)
	Debris:AddItem(attachment, velocityDuration + 0.04)
end

function DamageService.IsFriendly(attacker, targetModel, friendlyFire)
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	-- O MVP e cooperativo. FriendlyFire permanece na assinatura apenas para
	-- compatibilidade; nenhum personagem de jogador recebe dano ou knockback.
	return targetPlayer ~= nil
end

function DamageService.ApplySwordHit(attacker, attackerRoot, target, attack)
	if not attacker or attacker.Parent ~= Players then
		return false, false
	end
	if typeof(target) ~= "table" or typeof(attack) ~= "table" then
		return false, false
	end

	local model = target.Model
	local humanoid = target.Humanoid
	local root = target.Root
	if not model or not model.Parent or not humanoid or humanoid.Health <= 0 or not root or not root.Parent then
		return false, false
	end
	-- Defesa final: mesmo que uma hitbox futura resolva o alvo incorretamente,
	-- terreno procedural jamais pode receber dano ou ser desancorado pelo combate.
	if model:GetAttribute("IsSkyIsland") == true then
		warn("[SwordCombatV6] Tentativa de atingir uma ilha foi bloqueada: " .. model:GetFullName())
		return false, false
	end
	if model:GetAttribute("Invulnerable") == true or model:GetAttribute("NoSwordDamage") == true then
		return false, false
	end
	if Players:GetPlayerFromCharacter(model) then
		return false, false
	end

	local damage = mitigatedDamage(model, attack.Damage)
	if damage <= 0 then
		return false, false
	end
	local healthBefore = humanoid.Health
	tagCreator(humanoid, attacker)
	model:SetAttribute("LastDamagedByUserId", attacker.UserId)
	model:SetAttribute("LastSwordDamage", damage)
	model:SetAttribute("LastSwordScoreMultiplier", attack.ScoreMultiplier)
	model:SetAttribute("LastSwordHitAt", workspace:GetServerTimeNow())

	humanoid:TakeDamage(damage)
	local defeated = healthBefore > 0 and humanoid.Health <= 0
	local swordId = attacker:GetAttribute("EquippedSword") or "Sword"
	GameplayAnalytics.RecordEnemyAttacked(attacker, model, swordId)
	if defeated then
		GameplayAnalytics.RecordEnemyDefeated(attacker, model, swordId)
	end
	if humanoid.Health > 0 then
		-- Stun e knockback sao independentes. Assim bosses ou modelos marcados
		-- com NoKnockback ainda têm o ataque interrompido durante o combo.
		applyCombatStun(model, humanoid, attack)
	end
	if model:GetAttribute("NoKnockback") ~= true and model:GetAttribute("CanBeKnockedBack") ~= false then
		applyKnockback(attackerRoot, model, humanoid, root, attack)
	end
	createImpact(
		root.Position + Vector3.new(0, math.max(0.5, root.Size.Y * 0.35), 0),
		attack.Heavy and Color3.fromRGB(255, 120, 55) or Color3.fromRGB(255, 235, 170),
		attack.Heavy
	)
	playHitSound(model)

	return true, defeated
end

function DamageService.ApplyDirectHit(attacker, target, amount, source, alreadyRunScaled)
	if not attacker or attacker.Parent ~= Players or typeof(target) ~= "table" then
		return false, false
	end
	local model = target.Model
	local humanoid = target.Humanoid
	if
		not model
		or not model.Parent
		or not humanoid
		or humanoid.Health <= 0
		or model:GetAttribute("Invulnerable") == true
		or Players:GetPlayerFromCharacter(model)
	then
		return false, false
	end
	local runMultiplier = alreadyRunScaled == true and 1
		or math.clamp(
			tonumber(attacker:GetAttribute("RunDamageDealtMultiplier")) or 1,
			0.05,
			1
		)
	local damage = mitigatedDamage(model, math.max(0, tonumber(amount) or 0) * runMultiplier)
	if damage <= 0 then
		return false, false
	end
	local healthBefore = humanoid.Health
	tagCreator(humanoid, attacker)
	model:SetAttribute("LastDamagedByUserId", attacker.UserId)
	model:SetAttribute("LastDamageSource", tostring(source or "Direct"))
	humanoid:TakeDamage(damage)
	local defeated = healthBefore > 0 and humanoid.Health <= 0
	GameplayAnalytics.RecordEnemyAttacked(attacker, model, source or "Direct")
	if defeated then
		GameplayAnalytics.RecordEnemyDefeated(attacker, model, source or "Direct")
	end
	return true, defeated
end

function DamageService.ApplyCompanionHit(owner, target, amount, source)
	local success, defeated = DamageService.ApplyDirectHit(
		owner,
		target,
		amount,
		source or "Companion",
		false
	)
	if success and target.Model then
		-- Companheiros usam o mesmo feedback sonoro dos golpes da espada.
		-- O som so toca depois que o servidor realmente aceitou o dano.
		playHitSound(target.Model)
	end
	return success, defeated
end

return table.freeze(DamageService)
