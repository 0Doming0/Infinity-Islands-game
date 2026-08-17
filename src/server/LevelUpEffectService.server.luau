local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local EFFECT_LIFETIME = 3
local EFFECT_PARTICLE_COUNT = 45

local function activateLevelUpEffect(player)
	local effectsFolder = ServerStorage:FindFirstChild("Effects")
	local effectTemplate = effectsFolder and effectsFolder:FindFirstChild("LevelUp")
	local character = player.Character
	local rootPart = character and (
		character:FindFirstChild("HumanoidRootPart")
		or character.PrimaryPart
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChildWhichIsA("BasePart")
	)
	if not effectTemplate or not rootPart then
		warn(string.format(
			"[LevelUpEffectService] LevelUp effect or character anchor was not found (effect=%s, anchor=%s)",
			tostring(effectTemplate ~= nil),
			tostring(rootPart ~= nil)
		))
		return
	end

	local effect = effectTemplate:Clone()
	effect.Parent = character
	local effectPart
	if effect:IsA("BasePart") then
		effectPart = effect
	elseif effect:IsA("Model") then
		effectPart = effect.PrimaryPart or effect:FindFirstChildWhichIsA("BasePart", true)
	end
	if not effectPart then
		effect:Destroy()
		return
	end

	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	if effect:IsA("Model") then
		effect:PivotTo(rootPart.CFrame)
	else
		effect.CFrame = rootPart.CFrame
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = effectPart
	weld.Part1 = rootPart
	weld.Parent = effectPart

	local emitter = effect:FindFirstChild("ExpSwoosh", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(EFFECT_PARTICLE_COUNT)
	end

	local sound = effect:FindFirstChild("Levelup SFX", true)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end

	Debris:AddItem(effect, EFFECT_LIFETIME)
end

local function bindPlayer(player)
	local lastSerial
	player:GetAttributeChangedSignal("PlayerLevelUpSerial"):Connect(function()
		local serial = player:GetAttribute("PlayerLevelUpSerial")
		if serial == nil or serial == lastSerial then
			return
		end

		lastSerial = serial
		activateLevelUpEffect(player)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

print("[LevelUpEffectService] ativo")