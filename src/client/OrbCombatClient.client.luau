local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local orbFolder = ReplicatedStorage:WaitForChild("OrbCombat")
local OrbConfig = require(orbFolder:WaitForChild("OrbConfig"))
local attackConfirmed = orbFolder:WaitForChild("OrbAttackConfirmed")

local HIT_STOP_DURATION = 0.045
local SHAKE_DURATION = 0.12
local SHAKE_MAGNITUDE = 0.12
local IMPACT_SOUNDS = {
	Fire = {Volume = 0.22, PlaybackSpeed = 0.78, Id = "rbxassetid://91870890930509"},
	Ice = {Volume = 0.12, PlaybackSpeed = 1.28, Id = "rbxassetid://98205232642582"},
	Shadow = {Volume = 0.18, PlaybackSpeed = 0.58, Id = "rbxassetid://608971830"},
}
local shakeRemaining = 0
local shakeStrength = 0
local hitStopUntil = 0
local hitStopCFrame
local camera = Workspace.CurrentCamera

local function renderLaser(orbName, origin, endPosition)
	local orb = OrbConfig.GetOrb(orbName)
	if not orb or typeof(origin) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return
	end
	local distance = (endPosition - origin).Magnitude
	if distance <= 0.05 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "OrbLaserClient"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = orb.LaserMaterial
	part.Color = orb.LaserColor
	part.Size = Vector3.new(orb.LaserWidth, orb.LaserWidth, distance)
	part.CFrame = CFrame.lookAt((origin + endPosition) * 0.5, endPosition)
	part.Transparency = 0.1
	part.Parent = workspace
	Debris:AddItem(part, 0.08)
end

local function playImpactSound(orbName)
	local settings = IMPACT_SOUNDS[orbName]
	if not settings then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "OrbImpact_" .. orbName
	sound.SoundId = settings.Id
	sound.Volume = settings.Volume
	sound.PlaybackSpeed = settings.PlaybackSpeed
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 2)
end

local function triggerImpactFeedback()
	shakeRemaining = math.max(shakeRemaining, SHAKE_DURATION)
	shakeStrength = math.max(shakeStrength, SHAKE_MAGNITUDE)
	hitStopUntil = math.max(hitStopUntil, os.clock() + HIT_STOP_DURATION)
end

RunService:BindToRenderStep("OrbCombatFeedback", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	if not camera or not camera.Parent then
		camera = Workspace.CurrentCamera
	end
	if not camera then
		return
	end
	if os.clock() < hitStopUntil then
		if not hitStopCFrame then
			hitStopCFrame = camera.CFrame
		else
			camera.CFrame = hitStopCFrame
		end
		return
	end
	hitStopCFrame = nil
	if shakeRemaining <= 0 then
		shakeStrength = 0
		return
	end
	shakeRemaining = math.max(0, shakeRemaining - deltaTime)
	local fade = shakeRemaining / SHAKE_DURATION
	local offset = Vector3.new(
		(math.random() * 2 - 1) * shakeStrength * fade,
		(math.random() * 2 - 1) * shakeStrength * fade,
		0
	)
	camera.CFrame = camera.CFrame * CFrame.new(offset)
end)

attackConfirmed.OnClientEvent:Connect(function(_, orbName, origin, endPosition)
	renderLaser(orbName, origin, endPosition)
	playImpactSound(orbName)
	triggerImpactFeedback()
end)

print("[OrbCombatClient] Automatic laser renderer ready")