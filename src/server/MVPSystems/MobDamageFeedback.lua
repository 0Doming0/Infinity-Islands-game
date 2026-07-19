-- ServerScriptService/MVPSystems/MobDamageFeedback.lua

local TweenService = game:GetService("TweenService")

local MobDamageFeedback = {}

local HIGHLIGHT_NAME = "DamageHighlight"
local FLASH_DURATION = 0.18

local DAMAGE_COLOR = Color3.fromRGB(255, 65, 65)

local activeFlashes: {[Model]: number} = {}

local function getHighlight(mob: Model): Highlight
	local existing = mob:FindFirstChild(HIGHLIGHT_NAME)

	if existing and existing:IsA("Highlight") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = mob

	highlight.DepthMode = Enum.HighlightDepthMode.Occluded

	highlight.FillColor = DAMAGE_COLOR
	highlight.FillTransparency = 1

	highlight.OutlineColor = DAMAGE_COLOR
	highlight.OutlineTransparency = 1

	highlight.Parent = mob

	return highlight
end

function MobDamageFeedback.Play(mob: Model)
	if not mob or not mob:IsA("Model") then
		return
	end

	if not mob.Parent then
		return
	end

	local highlight = getHighlight(mob)

	-- Número único para evitar que flashes antigos
	-- desliguem um flash mais recente.
	local flashId = (activeFlashes[mob] or 0) + 1
	activeFlashes[mob] = flashId

	highlight.FillColor = DAMAGE_COLOR
	highlight.OutlineColor = DAMAGE_COLOR

	highlight.FillTransparency = 0.82
	highlight.OutlineTransparency = 0.05

	local fadeTween = TweenService:Create(
		highlight,
		TweenInfo.new(
			FLASH_DURATION,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			FillTransparency = 1,
			OutlineTransparency = 1,
		}
	)

	fadeTween:Play()

	task.delay(FLASH_DURATION, function()
		if activeFlashes[mob] ~= flashId then
			return
		end

		activeFlashes[mob] = nil

		if highlight.Parent then
			highlight.FillTransparency = 1
			highlight.OutlineTransparency = 1
		end
	end)
end

function MobDamageFeedback.Remove(mob: Model)
	activeFlashes[mob] = nil

	local highlight = mob:FindFirstChild(HIGHLIGHT_NAME)

	if highlight then
		highlight:Destroy()
	end
end

function MobDamageFeedback.Bind(mob: Model?): boolean
	if mob == nil then
		warn("[MobDamageFeedback] Bind chamado sem receber um mob.")
		return false
	end

	if not mob:IsA("Model") then
		warn(
			"[MobDamageFeedback] O objeto recebido não é um Model:",
			mob:GetFullName(),
			mob.ClassName
		)
		return false
	end

	if not mob.Parent then
		warn(
			"[MobDamageFeedback] Mob ainda não foi colocado no jogo:",
			mob.Name
		)
		return false
	end

	if mob:GetAttribute("DamageFeedbackBound") then
		return true
	end

	local humanoid = mob:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		humanoid = mob:FindFirstChildWhichIsA("Humanoid", true)
	end

	if not humanoid then
		warn(
			"[MobDamageFeedback] Mob sem Humanoid:",
			mob:GetFullName()
		)
		return false
	end

	mob:SetAttribute("DamageFeedbackBound", true)

	local previousHealth = humanoid.Health

	humanoid.HealthChanged:Connect(function(currentHealth)
		if currentHealth < previousHealth then
			MobDamageFeedback.Play(mob)
		end

		previousHealth = currentHealth
	end)

	humanoid.Died:Connect(function()
		activeFlashes[mob] = nil
	end)

	mob.Destroying:Connect(function()
		activeFlashes[mob] = nil
	end)

	return true
end

return MobDamageFeedback