-- Camera inteligente complementar para a primeira ilha no mobile.
-- A camera principal DungeonCameraController assume a partir da ilha 2.
-- Durante a apresentacao cinematografica inicial, este controller cede prioridade.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))

local VERSION = "InitialIslandMobileSmartCameraV1"
local BIND = "InitialIslandMobileSmartCamera"
local CAMERA_HEIGHT = 24
local CAMERA_DISTANCE = 19
local FOV = 70
local SMOOTH = 7.5
local TARGET_MAX_DISTANCE = 70

local active = false
local saved
local cameraCFrame
local cameraFocus

local function characterParts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return character, humanoid, root
end

local function targetRoot(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function nearestCombatTarget(root)
	local best
	local bestDistance = TARGET_MAX_DISTANCE
	local seen = {}
	for _, tagged in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = tagged:IsA("Model") and tagged or tagged:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
			local targetPart = targetRoot(model)
			if humanoid and humanoid.Health > 0 and targetPart
				and model:GetAttribute("ObjectiveTargetCompleted") ~= true
				and model:GetAttribute("Invulnerable") ~= true
			then
				local offset = targetPart.Position - root.Position
				local distance = Vector2.new(offset.X, offset.Z).Magnitude
				if distance < bestDistance and math.abs(offset.Y) <= 18 then
					best = targetPart
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function currentIsland()
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") and tonumber(instance:GetAttribute("GlobalIslandIndex")) == 1 then
			return instance
		end
	end
	return nil
end

local function exitAnchor()
	local island = currentIsland()
	if not island then
		return nil
	end
	local anchor = island:FindFirstChild("ExitAnchor", true) or island:FindFirstChild("Exit", true)
	return anchor and anchor:IsA("BasePart") and anchor or nil
end

local function eligible()
	if player:GetAttribute("DungeonMobileMode") ~= true then
		return false
	end
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		return false
	end
	if player:GetAttribute("DungeonInitialCameraIntroState") == "Playing" then
		return false
	end
	local index = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
	return index ~= nil and math.floor(index) == 1
end

local function capture(camera)
	if saved then
		return
	end
	saved = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView,
	}
	cameraCFrame = camera.CFrame
	cameraFocus = camera.Focus.Position
end

local function restore()
	local camera = Workspace.CurrentCamera
	if saved and camera then
		camera.CameraType = saved.CameraType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or saved.CameraType
		if saved.CameraSubject and saved.CameraSubject.Parent then
			camera.CameraSubject = saved.CameraSubject
		else
			local _, humanoid = characterParts()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		camera.FieldOfView = saved.FieldOfView
	end
	saved = nil
	cameraCFrame = nil
	cameraFocus = nil
	player:SetAttribute("DungeonInitialMobileSmartCameraActive", false)
end

local function update(dt)
	if not active or not eligible() then
		return
	end
	local camera = Workspace.CurrentCamera
	local _, _, root = characterParts()
	if not camera or not root then
		return
	end
	capture(camera)
	camera.CameraType = Enum.CameraType.Scriptable

	local combatTarget = nearestCombatTarget(root)
	local fallback = exitAnchor()
	local focusPoint = combatTarget and combatTarget.Position
		or (fallback and fallback.Position)
		or (root.Position + root.CFrame.LookVector * 12)
	focusPoint = Vector3.new(focusPoint.X, root.Position.Y + 2.2, focusPoint.Z)

	local horizontal = Vector3.new(focusPoint.X - root.Position.X, 0, focusPoint.Z - root.Position.Z)
	local forward = horizontal.Magnitude > 0.1 and horizontal.Unit
		or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local desiredPosition = root.Position - forward * CAMERA_DISTANCE + Vector3.new(0, CAMERA_HEIGHT, 0)
	local desiredFocus = root.Position:Lerp(focusPoint, combatTarget and 0.42 or 0.25) + Vector3.new(0, 1.5, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.IgnoreWater = true
	local ray = Workspace:Raycast(desiredFocus, desiredPosition - desiredFocus, params)
	if ray and not ray.Instance:FindFirstAncestorWhichIsA("Model") then
		desiredPosition = ray.Position + (desiredFocus - desiredPosition).Unit * 1.2
	end

	local alpha = 1 - math.exp(-SMOOTH * math.max(dt, 0))
	cameraCFrame = (cameraCFrame or camera.CFrame):Lerp(CFrame.lookAt(desiredPosition, desiredFocus), alpha)
	cameraFocus = (cameraFocus or desiredFocus):Lerp(desiredFocus, alpha)
	camera.CFrame = cameraCFrame
	camera.Focus = CFrame.new(cameraFocus)
	camera.FieldOfView += (FOV - camera.FieldOfView) * alpha

	player:SetAttribute("DungeonInitialMobileSmartCameraActive", true)
	player:SetAttribute("DungeonMobileCameraActive", true)
	player:SetAttribute("DungeonMobileCameraMode", combatTarget and "CombatTargetFollow" or "InitialRouteFollow")
	player:SetAttribute("DungeonMobileCameraPolicy", VERSION)
end

local function activate()
	if active then
		return
	end
	active = true
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 2, update)
end

local function deactivate()
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(BIND)
	restore()
end

local function refresh()
	if eligible() then
		activate()
	else
		deactivate()
	end
end

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refresh)
player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonAssistedTransportActive"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonInitialCameraIntroState"):Connect(refresh)
player.CharacterAdded:Connect(function()
	cameraCFrame = nil
	cameraFocus = nil
	task.defer(refresh)
end)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	cameraCFrame = nil
	cameraFocus = nil
end)

player:SetAttribute("DungeonInitialMobileSmartCameraReady", true)
player:SetAttribute("DungeonInitialMobileSmartCameraVersion", VERSION)
refresh()
