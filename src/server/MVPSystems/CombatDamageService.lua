-- ServerScriptService/MVPSystems/CombatDamageService
-- Ponto unico para receber dano, registrar atacante, impacto e impulsao.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local DamageService = {}

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

local function applyKnockback(attackerRoot, model, humanoid, root, attack)
	-- Um unico membro ancorado prende toda a assembly. Mobs de combate precisam
	-- estar fisicos para reagir enquanto vivos, nao apenas depois de morrer.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	-- Garante autoridade do servidor durante o pequeno stun.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

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
	local horizontalForce = math.max(12, tonumber(attack.Knockback) or 12) * 1.8 * comboScale
	local upwardForce = math.max(2, tonumber(attack.UpwardKnockback) or 2) * comboScale

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

	-- Token-based stun: each hit increments a token so consecutive hits
	-- extend the stun instead of ending it prematurely
	local stunTokenId = (model:GetAttribute("CombatStunTokenId") or 0) + 1
	model:SetAttribute("CombatStunTokenId", stunTokenId)
	model:SetAttribute("CombatStunned", true)
	model:SetAttribute("CombatKnockbackUntil", workspace:GetServerTimeNow() + 0.22)

	-- Store original walk speed before zeroing (only if not already stored
	-- from a previous stun that hasn't been cleaned up yet)
	if not model:GetAttribute("CombatOriginalWalkSpeed") then
		model:SetAttribute("CombatOriginalWalkSpeed", humanoid.WalkSpeed)
	end

	-- Disable AI movement
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)

	-- Remove old knockback objects from previous hits
	for _, child in ipairs(root:GetChildren()) do
		if child.Name == "SwordKnockback" or child.Name == "SwordKnockbackAttachment" then
			child:Destroy()
		end
	end

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
	local stunDuration = 0.20

	Debris:AddItem(linearVelocity, velocityDuration + 0.02)
	Debris:AddItem(attachment, velocityDuration + 0.04)

	-- Remove stun after duration, but only if the token hasn't changed.
	-- A newer hit extends the stun and takes over cleanup.
	task.delay(stunDuration, function()
		if not model or not model.Parent then
			return
		end
		if model:GetAttribute("CombatStunTokenId") ~= stunTokenId then
			return -- A newer hit is in charge; let it handle cleanup
		end
		model:SetAttribute("CombatStunned", nil)
		model:SetAttribute("CombatStunTokenId", nil)
		model:SetAttribute("CombatKnockbackUntil", nil)
		if humanoid and humanoid.Parent then
			local originalSpeed = model:GetAttribute("CombatOriginalWalkSpeed")
			if originalSpeed then
				humanoid.WalkSpeed = originalSpeed
			end
			humanoid.AutoRotate = true
		end
		model:SetAttribute("CombatOriginalWalkSpeed", nil)
	end)
end

function DamageService.IsFriendly(attacker, targetModel, friendlyFire)
	if friendlyFire then
		return false
	end
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	return targetPlayer ~= nil
		and attacker.Team ~= nil
		and attacker.Team == targetPlayer.Team
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

	local healthBefore = humanoid.Health
	tagCreator(humanoid, attacker)
	model:SetAttribute("LastDamagedByUserId", attacker.UserId)
	model:SetAttribute("LastSwordDamage", attack.Damage)
	model:SetAttribute("LastSwordScoreMultiplier", attack.ScoreMultiplier)
	model:SetAttribute("LastSwordHitAt", workspace:GetServerTimeNow())

	humanoid:TakeDamage(attack.Damage)
	applyKnockback(attackerRoot, model, humanoid, root, attack)
	createImpact(
		root.Position + Vector3.new(0, math.max(0.5, root.Size.Y * 0.35), 0),
		attack.Heavy and Color3.fromRGB(255, 120, 55) or Color3.fromRGB(255, 235, 170),
		attack.Heavy
	)

	return true, healthBefore > 0 and humanoid.Health <= 0
end

return table.freeze(DamageService)