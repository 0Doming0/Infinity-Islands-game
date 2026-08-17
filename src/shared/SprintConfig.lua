-- Configuracao compartilhada de corrida e agachamento seguro.
-- Posicoes dos controles touch pertencem ao layout authored no Roblox Studio.

local SprintConfig = {
	Version = "V27_AUTHORED_MOBILE_CONTROL_LAYOUT",
	DoubleTapWindow = 0.30,
	SpeedMultiplier = 1.25,
	MaximumSprintSpeed = 34,
	SprintDuration = 5.0,
	StaminaPerDurationUpgrade = 80,
	SprintDurationPerUpgrade = 0.5,
	MaximumSprintDuration = 15.0,
	StaminaRegenDelay = 1.0,
	StaminaRegenDuration = 3.5,
	StaminaPublishInterval = 0.05,
	MovementStamina = {
		DistancePerReward = 20,
		WalkReward = 0.5,
		SprintReward = 1,
		MaximumCountedSpeed = 45,
		SpeedToleranceMultiplier = 1.35,
		PositionTolerance = 0.75,
		MaximumSampleTime = 0.5,
	},
	SneakSpeedMultiplier = 0.50,
	RequestRetryInterval = 0.40,
	IdleStopDelay = 0.85,
	JoystickSprintPushPixels = 52,
	JoystickSprintHorizontalTolerance = 1.15,
	SneakCameraDrop = 1.15,
	-- Deixe qualquer campo vazio para nao usar a animacao daquele estado.
	-- Aceita somente o numero ("123456789") ou "rbxassetid://123456789".
	SneakIdleAnimationId = "112464321457722",
	SneakWalkAnimationId = "71788126576681",
	SneakIdleAnimationSpeed = 1.0,
	SneakWalkAnimationSpeed = 1.0,
	SneakWalkMinimumSpeed = 0.25,
	SneakAnimationFadeTime = 0.15,
	SneakAnimationPriority = Enum.AnimationPriority.Action,
	EdgeProbeDepth = 4.25,
	EdgeGroundHeightTolerance = 0.65,
	SneakEdgeFootprintInset = 0.08,
	SneakEdgeForwardProbeDistance = 1.2,
	SneakEdgeForwardProbeMargin = 0.18,
	SneakEdgeBarrierWidth = 4,
	SneakEdgeBarrierHeight = 6,
	SneakEdgeBarrierThickness = 0.35,
	SneakEdgeBarrierMinimumDistance = 1.15,
	StaminaBarSize = UDim2.fromOffset(180, 7),
	StaminaBarPosition = UDim2.new(1, -28, 1, -34),
}

function SprintConfig.GetMaximumSprintDuration(permanentStamina)
	local cleanStamina = math.max(0, tonumber(permanentStamina) or 0)
	local upgradeCount = math.floor(cleanStamina / SprintConfig.StaminaPerDurationUpgrade)
	local duration = SprintConfig.SprintDuration + upgradeCount * SprintConfig.SprintDurationPerUpgrade
	return math.min(SprintConfig.MaximumSprintDuration, duration)
end

return SprintConfig
