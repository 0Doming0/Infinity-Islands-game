-- DungeonCameraController: unica autoridade da camera mobile durante gameplay.
--
-- Regra normal: enquadra a ILHA e a direcao da rota.
-- Excecao curta da ilha inicial: enquanto InstantOnboardingController publicar
-- DungeonInitialGuideTarget E a SITUAÇÃO ATUAL ainda estiver pendente, a POSICAO
-- continua sendo a camera inteligente da ilha, mas o FOCO aponta suavemente
-- para o slime orientado. A conclusao do objetivo tem prioridade sobre a
-- existencia de mobs restantes na ilha.
--
-- Durante o transporte este controller cede a camera ao controller do voo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "IslandSmartMobileCameraV4_ObjectiveCompleteAuthority"
local BIND_NAME = "DungeonCameraController"
local CAMERA_HEIGHT = 28
local CAMERA_DISTANCE = 22
local CAMERA_FOV = 70
local POSITION_SPEED = 7
local ROTATION_SPEED = 8
local FOV_SPEED = 6
local FOCUS_TOWARD_EXIT = 0.20
local OBSTRUCTION_PADDING = 1.5

local active = false
local bound = false
local cameraCFrame
local focusPosition
local savedType
local savedSubject
local savedFov
local cachedIsland
local cachedIslandIndex
local lastRouteDirection
local lastRouteSideCenter

local function isMobile()
	return player:GetAttribute("DungeonMobileMode") == true
		or UserInputService.TouchEnabled == true
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

local function horizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return flat.Magnitude > 0.05 and flat.Unit or nil
end

local function currentIslandIndex()
	local value = tonumber(player:GetAttribute("CurrentGlobalIslandIndex"))
		or tonumber(Workspace:GetAttribute("DungeonObjectiveGlobalIslandIndex"))
		or tonumber(Workspace:GetAttribute("DungeonCurrentObjectiveIsland"))
	return value and math.max(1, math.floor(value)) or 1
end

local function initialSituationComplete()
	if currentIslandIndex() ~= 1 then
		return true
	end

	return player:GetAttribute("DungeonCurrentObjectiveComplete") == true
		or player:GetAttribute("DungeonLinearObjectiveComplete") == true
		or player:GetAttribute("DungeonInitialCombatGuideComplete") == true
		or player:GetAttribute("DungeonManualAdvanceReady") == true
end

local function findAnchor(container, names)
	if not container then
		return nil
	end
	for _, name in ipairs(names) do
		local instance = container:FindFirstChild(name, true)
		if instance and instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

local function findIsland(index, root)
	if cachedIsland
		and cachedIsland.Parent
		and cachedIslandIndex == index
	then
		return cachedIsland
	end

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
				if root then
					local bounds = instance:GetBoundingBox()
					local distance = (bounds.Position - root.Position).Magnitude
					if distance < nearestDistance then
						nearest = instance
						nearestDistance = distance
					end
				end
			end
		end
	end

	cachedIsland = exact or nearest
	cachedIslandIndex = index
	return cachedIsland
end

local function exitSide(island)
	if not island then
		return nil
	end

	local exit = findAnchor(island, { "ExitAnchor", "Exit" })
	if not exit then
		return nil
	end

	local boundsCFrame, boundsSize = island:GetBoundingBox()
	local localExit = boundsCFrame:PointToObjectSpace(exit.Position)
	local half = boundsSize * 0.5
	local candidates = {
		{ math.abs(half.X - localExit.X), Vector3.new(1, 0, 0), Vector3.new(half.X, 0, 0) },
		{ math.abs(-half.X - localExit.X), Vector3.new(-1, 0, 0), Vector3.new(-half.X, 0, 0) },
		{ math.abs(half.Z - localExit.Z), Vector3.new(0, 0, 1), Vector3.new(0, 0, half.Z) },
		{ math.abs(-half.Z - localExit.Z), Vector3.new(0, 0, -1), Vector3.new(0, 0, -half.Z) },
	}

	local closest = candidates[1]
	for index = 2, #candidates do
		if candidates[index][1] < closest[1] then
			closest = candidates[index]
		end
	end

	local direction = horizontalUnit(boundsCFrame:VectorToWorldSpace(closest[2]))
	local sideCenter = boundsCFrame:PointToWorldSpace(closest[3])
	return direction, sideCenter
end

local function routeFrame(root)
	local island = findIsland(currentIslandIndex(), root)
	local direction, sideCenter = exitSide(island)

	if direction and sideCenter then
		lastRouteDirection = direction
		lastRouteSideCenter = sideCenter
	else
		direction = lastRouteDirection
		sideCenter = lastRouteSideCenter
	end

	if not direction then
		if island then
			local bounds = island:GetBoundingBox()
			direction = horizontalUnit(bounds.Position - root.Position)
		end
		direction = direction
			or horizontalUnit(root.CFrame.LookVector)
			or Vector3.new(0, 0, -1)
	end

	if not sideCenter then
		if island then
			local bounds = island:GetBoundingBox()
			sideCenter = bounds.Position
		else
			sideCenter = root.Position + direction * 8
		end
	end

	local focus = Vector3.new(
		root.Position.X + (sideCenter.X - root.Position.X) * FOCUS_TOWARD_EXIT,
		root.Position.Y + (sideCenter.Y - root.Position.Y) * FOCUS_TOWARD_EXIT,
		root.Position.Z + (sideCenter.Z - root.Position.Z) * FOCUS_TOWARD_EXIT
	)
	return direction, focus, sideCenter
end

local function guideTargetPosition()
	-- A conclusao da SITUAÇÃO ATUAL e a autoridade principal. Mobs extras vivos
	-- nao podem manter a camera presa ao tutorial depois que o objetivo terminou.
	if initialSituationComplete()
		or player:GetAttribute("DungeonInitialCombatGuideActive") ~= true
	then
		return nil
	end

	local holder = playerGui:FindFirstChild("DungeonInitialGuideTarget")
	local target = holder and holder:IsA("ObjectValue") and holder.Value or nil
	if not target or not target:IsA("Model") or not target:IsDescendantOf(Workspace) then
		return nil
	end

	local humanoid = target:FindFirstChildWhichIsA("Humanoid", true)
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local targetRoot = target:FindFirstChild("HumanoidRootPart", true)
		or target.PrimaryPart
		or target:FindFirstChildWhichIsA("BasePart", true)
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return nil
	end

	return targetRoot.Position + Vector3.new(0, math.max(1, targetRoot.Size.Y * 0.35), 0), target
end

local function humanoidModel(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildWhichIsA("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function desiredCameraPosition(root, direction, focus)
	local desired = root.Position - direction * CAMERA_DISTANCE
		+ Vector3.new(0, CAMERA_HEIGHT, 0)
	local ray = desired - focus
	if ray.Magnitude <= 0.1 then
		return desired
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}
	if player.Character then
		table.insert(excluded, player.Character)
	end
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true

	-- Mobs nunca devem empurrar a camera para frente. Ignoramos modelos com
	-- Humanoid e somente usamos geometria da ilha/mundo como obstrucao real.
	for _ = 1, 24 do
		local hit = Workspace:Raycast(focus, ray, params)
		if not hit then
			break
		end
		local model = humanoidModel(hit.Instance)
		if model then
			table.insert(excluded, model)
			params.FilterDescendantsInstances = excluded
		else
			desired = hit.Position - ray.Unit * OBSTRUCTION_PADDING
			break
		end
	end
	return desired
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
	if not active or player:GetAttribute("DungeonAssistedTransportActive") == true then
		return
	end

	local camera = Workspace.CurrentCamera
	local _, _, root = characterParts()
	if not camera or not root then
		return
	end

	capture(camera)
	camera.CameraType = Enum.CameraType.Scriptable

	local direction, desiredFocus, sideCenter = routeFrame(root)
	local guideFocus, guideTarget = guideTargetPosition()
	local cameraMode = "IslandRouteFollow"
	if guideFocus then
		desiredFocus = guideFocus
		cameraMode = "InitialAttackGuide"
	end

	local desiredPosition = desiredCameraPosition(root, direction, desiredFocus)
	local positionAlpha = 1 - math.exp(-POSITION_SPEED * math.max(dt, 0))
	local rotationAlpha = 1 - math.exp(-ROTATION_SPEED * math.max(dt, 0))
	local fovAlpha = 1 - math.exp(-FOV_SPEED * math.max(dt, 0))

	cameraCFrame = cameraCFrame or camera.CFrame
	focusPosition = focusPosition or desiredFocus
	local position = cameraCFrame.Position:Lerp(desiredPosition, positionAlpha)
	focusPosition = focusPosition:Lerp(desiredFocus, rotationAlpha)
	if (focusPosition - position).Magnitude < 0.1 then
		focusPosition = position + direction * CAMERA_DISTANCE
	end

	cameraCFrame = CFrame.lookAt(position, focusPosition, Vector3.yAxis)
	camera.CFrame = cameraCFrame
	camera.Focus = CFrame.new(focusPosition)
	camera.FieldOfView += (CAMERA_FOV - camera.FieldOfView) * fovAlpha

	player:SetAttribute("DungeonMobileCameraActive", true)
	player:SetAttribute("DungeonMobileCameraPolicy", VERSION)
	player:SetAttribute("DungeonMobileCameraMode", cameraMode)
	player:SetAttribute("DungeonMobileCameraForward", direction)
	player:SetAttribute("DungeonMobileCameraFocusWorld", focusPosition)
	player:SetAttribute("DungeonMobileCameraSideCenterWorld", sideCenter)
	player:SetAttribute(
		"DungeonMobileCameraGuideTarget",
		guideTarget and guideTarget.Name or nil
	)
end

local function eligible()
	return isMobile() and player:GetAttribute("DungeonMVPVictory") ~= true
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

local function invalidateIslandCache()
	cachedIsland = nil
	cachedIslandIndex = nil
	lastRouteDirection = nil
	lastRouteSideCenter = nil
end

local function resetGuideFocusIfComplete()
	if not initialSituationComplete() then
		return
	end
	-- No proximo render, routeFrame reassume imediatamente o foco. A posicao
	-- continua suave, mas a camera deixa de olhar para o mob sem esperar ele morrer.
	cameraCFrame = nil
	focusPosition = nil
	player:SetAttribute("DungeonMobileCameraGuideTarget", nil)
end

player.CharacterAdded:Connect(function()
	cameraCFrame = nil
	focusPosition = nil
	invalidateIslandCache()
	task.defer(refresh)
end)
player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(refresh)
player:GetAttributeChangedSignal("CurrentGlobalIslandIndex"):Connect(function()
	invalidateIslandCache()
	refresh()
end)
player:GetAttributeChangedSignal("DungeonMVPVictory"):Connect(refresh)
player:GetAttributeChangedSignal("DungeonAssistedTransportActive"):Connect(function()
	cameraCFrame = nil
	focusPosition = nil
end)
for _, attributeName in ipairs({
	"DungeonCurrentObjectiveComplete",
	"DungeonLinearObjectiveComplete",
	"DungeonInitialCombatGuideComplete",
	"DungeonManualAdvanceReady",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(resetGuideFocusIfComplete)
end
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
