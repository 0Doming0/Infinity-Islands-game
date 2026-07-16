-- ReplicatedStorage/SwordCombat/CombatConfig
-- Valores compartilhados pelo cliente e pelo servidor.
-- O servidor sempre limita atributos vindos das Tools aos limites abaixo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local Config = {}

Config.ToolRemoteName = "SwordAttackRequest"
Config.TargetTag = "CombatTarget"
Config.ComboCount = 3
Config.ComboResetTime = 0.95
Config.InputBufferTime = 0.16
Config.ServerTimingTolerance = 0.055

-- AttackSpeed divide Windup e Recovery. Ex.: 1.25 = 25% mais rápido.
Config.AttackSpeedLimits = {
	Min = 0.55,
	Max = 2.00,
}

Config.DamageLimits = {
	Min = 1,
	Max = 250,
}

Config.MaxTargetsPerSwing = 7
Config.MaxHitboxDimension = 14
-- Desativado por padrao: em mapas procedurais, grama, decoracoes e mobs baixos
-- podem fazer o raycast tocar o piso antes do alvo. A hitbox curta ja limita o golpe.
Config.RequireLineOfSight = false
Config.FriendlyFire = false
Config.DebugHitboxes = false
Config.DebugCombat = false

-- CFrame usa -Z como direção para frente.
Config.Combo = {
	[1] = {
		DamageMultiplier = 1.00,
		Windup = 0.12,
		Recovery = 0.26,
		HitboxSize = Vector3.new(6.5, 5.0, 7.0),
		HitboxOffset = CFrame.new(0, 0, -3.65),
		Knockback = 7,
		UpwardKnockback = 1.5,
		TrailStart = 0.035,
		TrailDuration = 0.19,
		AnimationSpeed = 1.08,
		Heavy = false,
	},
	[2] = {
		DamageMultiplier = 1.12,
		Windup = 0.14,
		Recovery = 0.29,
		HitboxSize = Vector3.new(7.0, 5.2, 7.5),
		HitboxOffset = CFrame.new(0, 0, -3.90),
		Knockback = 9,
		UpwardKnockback = 2.0,
		TrailStart = 0.045,
		TrailDuration = 0.21,
		AnimationSpeed = 1.10,
		Heavy = false,
	},
	[3] = {
		DamageMultiplier = 1.55,
		Windup = 0.21,
		Recovery = 0.43,
		HitboxSize = Vector3.new(8.0, 5.8, 8.5),
		HitboxOffset = CFrame.new(0, 0, -4.25),
		Knockback = 22,
		UpwardKnockback = 6.0,
		TrailStart = 0.075,
		TrailDuration = 0.27,
		AnimationSpeed = 1.00,
		Heavy = true,
	},
}

Config.DefaultWeapon = {
	BaseDamage = 20,
	AttackSpeed = 1.0,
	KnockbackMultiplier = 1.0,
	ScoreMultiplier = 1.0,
}

-- Animações clássicas temporárias do Roblox para R15.
-- Substitua por animações publicadas pelo dono/grupo da experiência.
-- Uma Tool também pode sobrescrever cada slot usando a pasta "Animations".
Config.DefaultAnimationIds = {
	Equip = MVPConfig.ExampleAssets.Animations.Equip,
	Idle = MVPConfig.ExampleAssets.Animations.Idle,
	Attack1 = MVPConfig.ExampleAssets.Animations.Attack1,
	Attack2 = MVPConfig.ExampleAssets.Animations.Attack2,
	Attack3 = MVPConfig.ExampleAssets.Animations.Attack3,
}

Config.Visuals = {
	TrailColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 205, 255)),
	}),
	TrailLifetime = 0.12,
	TrailWidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.0),
	}),
	HitColor = Color3.fromRGB(255, 235, 170),
	HeavyHitColor = Color3.fromRGB(255, 125, 65),
	CameraShake = 0.10,
	HeavyCameraShake = 0.19,
}

-- Conteúdo local que não precisa de upload de asset.
Config.Sounds = {
	Equip = MVPConfig.ExampleAssets.Sounds.Equip,
	Swing = MVPConfig.ExampleAssets.Sounds.Swing,
	HeavySwing = MVPConfig.ExampleAssets.Sounds.HeavySwing,
	Hit = MVPConfig.ExampleAssets.Sounds.Hit,
}

function Config.IsSword(tool)
	return tool
		and tool:IsA("Tool")
		and (
			tool.Name == "ClassicSword"
			or tool:GetAttribute("IsSword") == true
			or tool:GetAttribute("WeaponType") == "Sword"
		)
end

function Config.GetClampedNumber(instance, attributeName, fallback, minimum, maximum)
	local value = instance and instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		value = fallback
	end
	return math.clamp(value, minimum, maximum)
end

function Config.GetAttackSpeed(tool)
	return Config.GetClampedNumber(
		tool,
		"AttackSpeed",
		Config.DefaultWeapon.AttackSpeed,
		Config.AttackSpeedLimits.Min,
		Config.AttackSpeedLimits.Max
	)
end

return table.freeze(Config)
