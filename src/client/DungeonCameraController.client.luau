-- DungeonCameraController: unica autoridade da camera mobile durante gameplay.
-- Ativa desde a primeira ilha e continua pela rota inteira.
--
-- Prioridade:
-- 1. alvo que o MobileControls esta perseguindo;
-- 2. mob vivo mais proximo da arena atual;
-- 3. saida/direcao da ilha como fallback.
--
-- Durante transporte este controller apenas cede a camera ao controller do voo.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CombatConfig = require(
	ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig")
)

local VERSION = "LinearMobileCameraV1"
local BIND_NAME = "DungeonCameraController"
local HEIGHT = 25
local DISTANCE = 20
local FOV = 70
local POSITION_SPEED = 8
local ROTATION_SPEED = 9
local TARGET_RADIUS = 85
local OBSTRUCTION_PADDING = 1.4

local active = false
local bound = false
local cameraCFrame
local focusPosition
local savedType
local savedSubject
local savedFov

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
end

local function currentIslandIndex()
	local value = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
		or tonumber(Workspace:GetAttribute("DungeonCurrentObjectiveIsland"))
	if not value or value <= 0 then
		return 1
	end
	return math.max(1, math.floor(value))
end

local function characterParts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character
		or not character:IsDescendantOf(Workspace)
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return nil
	end
	return character, humanoid, root
end

local function rootOf(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function alive(model)
	local humanoid = model and model:FindFirstChildWhichIsA("Humanoid", true)
	return humanoid ~= nil and humanoid.Health > 0
end

local function targetIsland(model)
	local value = tonumber(model:GetAttribute("GlobalIslandIndex"))
		or tonumber(model:GetAttribute("ProgressionIslandIndex"))
		or tonumber(model:GetAttribute("CombatIslandIndex"))
	if not value then
		return nil
	end
	if value <= 0 and model:GetAttribute("IsInitialIslandMob") == true then
		return 1
	end
	return math.floor(value)
end

local function validCameraTarget(model, root)
	if not model
		or not model:IsA("Model")
		or not model.Parent
		or model:GetAttribute("ObjectiveTargetCompleted") == true
		or not alive(model)
	then
		return false
	end
	local targetRoot = rootOf(model)
	if not targetRoot then
		return false
	end
	local index = targetIsland(model)
	if index and index > 0 and index ~= currentIslandIndex() then
		return false
	end
	local offset = targetRoot.Position - root.Position
	return Vector2.new(offset.X, offset.Z).Magnitude <= TARGET_RADIUS
		and math.abs(offset.Y) <= 24
end

local function mobileCombatTarget(root)
	local value = playerGui:FindFirstChild("DungeonMobileCombatTarget")
	local selected = value and value:IsA("ObjectValue") and value.Value or nil
	if validCameraTarget(selected, root) then
		return selected
	end

	local best
	local bestDistance = TARGET_RADIUS
	local seen = {}
	for _, tagged in ipairs(CollectionService:GetTagged(CombatConfig.TargetTag)) do
		local model = tagged:IsA("Model") and tagged
			or tagged:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			if validCameraTarget(model, root) then
				local targetRoot = rootOf(model)
				local offset = targetRoot.Position - root.Position
				local distance = Vector2.new(offset.X, offset.Z).Magnitude
				if distance < bestDistance then
					best = model
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function islandModel(index, root)
	local exact
	local nearest
	local nearestDistance = math.huge
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") then
			local candidate = tonumber(instance:GetAttribute("GlobalIslandIndex"))
			if candidate then
				candidate = math.floor(candidate)
				if candidate == index then
					exact = instance
					break
				end
				local bounds = instance:GetBoundingBox()
				local distance = (bounds.Position - root.Position).Magnitude
				if distance < nearestDistance then
					nearest = instance
					nearestDistance = distance
				end
			end
		end
	end
	return exact or nearest
end

local function routeFocus(root)
	local island = islandModel(currentIslandIndex(), root)
	if island then
		for _, name in ipairs({ "ExitAnchor", "Exit", "ObjectiveAnchor" }) do
			local anchor = island:FindFirstChild(name, true)
			if anchor and anchor:IsA("BasePart") then
				return anchor.Position
			end
		end
		local bounds = island:GetBoundingBox()
		return bounds.Position
	end
	return root.Position + root.CFrame.LookVector * 12
end

local function desiredFrame(root)
	local target = mobileCombatTarget(root)
	local targetRoot = target and rootOf(target)
	local rawFocus = targetRoot and targetRoot.Position or routeFocus(root)
	local horizontal = Vector3.new(
		rawFocus.X - root.Position.X,
		0,
		rawFocus.Z - root.Position.Z
	)
	local forward
	if horizontal.Magnitude > 0.1 then
		forward = horizontal.Unit
	else
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		forward = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	end

	local blendToTarget = targetRoot and 0.42 or 0.22
	local focus = root.Position:Lerp(
		Vector3.new(rawFocus.X, root.Position.Y + 2, rawFocus.Z),
		blendToTarget
	) + Vector3.new(0, 1.5, 0)
	local desiredPosition = root.Position - forward * DISTANCE + Vector3.new(0, HEIGHT, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.IgnoreWater = true
	local rayDirection = desiredPosition - focus
	if rayDirection.Magnitude > 0.1 then
		local hit = Workspace:Raycast(focus, rayDirection, params)
		if hit and not hit.Instance:FindFirstAncestorWhichIsA("Model") then
			desiredPosition = hit.Position - rayDirection.Unit * OBSTRUCTION_PADDING
		end
	end

	return CFrame.lookAt(desiredPosition, focus, Vector3.yAxis), focus, target
end

local function capture(camera)
	if savedType ~= nil then
		return
	end
	savedType = camera.CameraType
	savedSubject = camera.CameraSubject
	savedFov = camera.FieldOfView
	cameraCFrame = camera.CFrame
	focusPosition = camera.Focus.Position
end

local function restore()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = savedType or Enum.CameraType.Custom
		if savedSubject and savedSubject.Parent then
			camera.CameraSubject = savedSubject
		else
			local _, humanoid = characterParts()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		if savedFov then
			camera.FieldOfView = savedFov
		end
	end
	savedType = nil
	savedSubject = nil
	savedFov = nil
	cameraCFrame = nil
	focusPosition = nil
end

local function update(dt)
	if not active then
		return
	end
	if player:GetAttribute("DungeonAssistedTransportActive") == true then
		cameraCFrame = nil
		focusPosition = nil
		return
	end

	local camera = Workspace.CurrentCamera
	local _, _, root = characterParts()
	if not camera or not root then
		return
	end
	capture(camera)
	camera.CameraType = Enum.CameraType.Scriptable

	local desired, desiredFocus, target = desiredFrame(root)
	local positionAlpha = 1 - math.exp(-POSITION_SPEED * math.max(dt, 0))
	local rotationAlpha = 1 - math.exp(-ROTATION_SPEED * math.max(dt, 0))
	cameraCFrame = (cameraCFrame or camera.CFrame):Lerp(desired, positionAlpha)
	focusPosition = (focusPosition or desiredFocus):Lerp(desiredFocus, rotationAlpha)
	camera.CFrame = CFrame.lookAt(cameraCFrame.Position, focusPosition, Vector3.yAxis)
	camera.Focus = CFrame.new(focusPosition)
	camera.FieldOfView += (FOV - camera.FieldOfView) * positionAlpha

	player:SetAttribute("DungeonMobileCameraActive", true)
	player:SetAttribute("DungeonMobileCameraPolicy", VERSION)
	player:SetAttribute(
		"DungeonMobileCameraMode",
		target and "CombatFollow" or "RouteFollow"
	)
end

local function eligible()
	return isMobile()
		and player:GetAttribute("DungeonMVPVictory") ~= true
end

local function refresh()
	if eligible() and not active then
		active = true
		if not bound then
			RunService:BindToRenderStep(
				BIND_NAME,
				Enum.RenderPriority.Camera.Value + 10,
				update
			)
			bound = true
		end
		player:SetAttribute("DungeonMobileCameraReady", true)
		player:SetAttribute("DungeonMobileCameraVersion", VERSION)
	elseif not eligible() and active then
		active = false
		restore()
		player:SetAttribute("DungeonMobileCameraActive", false)
		player:SetAttribute("DungeonMobileCameraMode", "RobloxDefault")
	end
end

player.CharacterAdded:Connect(function()
	cameraCFrame = nil
	focusPosition = nil
	task.defer(refresh)
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonMVPVictory"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonAssistedTransportActive"):Connect(function()
	cameraCFrame = nil
	focusPosition = nil
end)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	savedType = nil
	savedSubject = nil
	savedFov = nil
	cameraCFrame = nil
	focusPosition = nil
end)

player:SetAttribute("DungeonMobileCameraControllerLoaded", true)
refresh()

script.Destroying:Connect(function()
	if bound then
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
	restore()
end)
