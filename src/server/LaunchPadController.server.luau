--[[
	LaunchPadController.server.lua

	Coloque este Script em ServerScriptService junto do ProceduralGenerator.
	Ele controla qualquer BasePart com a tag "ProceduralLaunchPad".

	O gerador grava TargetPosition, ApexHeight e Cooldown em cada pad.
	A velocidade e calculada no servidor para a trajetoria atingir o destino.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TAG_NAME = "ProceduralLaunchPad"
local DEFAULT_APEX_HEIGHT = 11
local DEFAULT_COOLDOWN = 1.35
local MAX_HORIZONTAL_SPEED = 85
local MAX_VERTICAL_SPEED = 115

local boundPads = {}
local lastLaunchByHumanoid = setmetatable({}, { __mode = "k" })

local function clampHorizontalVelocity(velocity)
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontal.Magnitude <= MAX_HORIZONTAL_SPEED then
		return velocity
	end

	local clamped = horizontal.Unit * MAX_HORIZONTAL_SPEED
	return Vector3.new(clamped.X, velocity.Y, clamped.Z)
end

local function calculateLaunchVelocity(startPosition, targetPosition, apexExtraHeight)
	local gravity = Workspace.Gravity
	local apexY = math.max(startPosition.Y, targetPosition.Y) + apexExtraHeight
	local riseToApex = math.max(0.1, apexY - startPosition.Y)
	local fallFromApex = math.max(0.1, apexY - targetPosition.Y)

	local verticalVelocity = math.sqrt(2 * gravity * riseToApex)
	local timeUp = verticalVelocity / gravity
	local timeDown = math.sqrt(2 * fallFromApex / gravity)
	local totalTime = math.max(0.25, timeUp + timeDown)
	local horizontalDelta = Vector3.new(
		targetPosition.X - startPosition.X,
		0,
		targetPosition.Z - startPosition.Z
	)
	local horizontalVelocity = horizontalDelta / totalTime
	local velocity = Vector3.new(
		horizontalVelocity.X,
		math.min(verticalVelocity, MAX_VERTICAL_SPEED),
		horizontalVelocity.Z
	)

	return clampHorizontalVelocity(velocity)
end

local function getCharacterFromHit(hit)
	if not hit or not hit.Parent then
		return nil
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local player = Players:GetPlayerFromCharacter(character)

	if not player or not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil
	end

	return character, humanoid, rootPart
end

local function launchCharacter(pad, hit)
	if pad:GetAttribute("Enabled") == false then
		return
	end

	local _, humanoid, rootPart = getCharacterFromHit(hit)
	if not humanoid then
		return
	end

	local targetPosition = pad:GetAttribute("TargetPosition")
	if typeof(targetPosition) ~= "Vector3" then
		warn(string.format("[LaunchPadController] %s nao possui TargetPosition.", pad:GetFullName()))
		return
	end

	local now = os.clock()
	local cooldown = pad:GetAttribute("Cooldown") or DEFAULT_COOLDOWN
	local lastLaunch = lastLaunchByHumanoid[humanoid] or -math.huge
	if now - lastLaunch < cooldown then
		return
	end
	lastLaunchByHumanoid[humanoid] = now

	local apexHeight = pad:GetAttribute("ApexHeight") or DEFAULT_APEX_HEIGHT
	local velocity = calculateLaunchVelocity(rootPart.Position, targetPosition, apexHeight)

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	rootPart.AssemblyLinearVelocity = velocity
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function unbindPad(pad)
	local connections = boundPads[pad]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end
	boundPads[pad] = nil
end

local function bindPad(pad)
	if boundPads[pad] or not pad:IsA("BasePart") then
		return
	end

	boundPads[pad] = {
		pad.Touched:Connect(function(hit)
			launchCharacter(pad, hit)
		end),
		pad.Destroying:Connect(function()
			unbindPad(pad)
		end),
	}
end

for _, pad in CollectionService:GetTagged(TAG_NAME) do
	bindPad(pad)
end

CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(bindPad)
CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(unbindPad)
