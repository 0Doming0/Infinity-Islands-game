-- Configuracao compartilhada de corrida e agachamento seguro.

return {
	DoubleTapWindow = 0.30,
	SpeedMultiplier = 1.25,
	MaximumSprintSpeed = 34,
	SprintDuration = 5.0,
	StaminaRegenDelay = 1.0,
	StaminaRegenDuration = 3.5,
	StaminaPublishInterval = 0.05,
	SneakSpeedMultiplier = 0.50,
	RequestRetryInterval = 0.40,
	IdleStopDelay = 0.85,
	TouchButtonPosition = UDim2.fromScale(0.66, 0.74),
	SneakTouchButtonPosition = UDim2.fromScale(0.80, 0.63),
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
	EdgeProbeMargin = 0.15,
	EdgeProbeDepth = 4.25,
	EdgeGroundHeightTolerance = 0.65,
	StaminaBarSize = UDim2.fromOffset(180, 7),
	StaminaBarPosition = UDim2.new(1, -28, 1, -34),
}