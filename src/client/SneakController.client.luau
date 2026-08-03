-- Shift segura; R3/botao de toque alternam o agachamento no estilo Minecraft.
-- Um raycast acompanha a direcao do input. Quando nao existe piso adiante,
-- uma barreira invisivel criada somente neste cliente impede a queda sem
-- cancelar o input, teleportar ou alterar a velocidade do personagem.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local SprintConfig = require(ReplicatedStorage:WaitForChild("SprintConfig"))
local sprintRemote = ReplicatedStorage:WaitForChild("SprintRequest")
local sneakRemote = ReplicatedStorage:WaitForChild("SneakRequest")

local VERSION = "V7_CLIENT_EDGE_BARRIER"
local ACTION_NAME = "SkyDungeonSneak"
script:SetAttribute("ControllerVersion", VERSION)
local crouchWanted = false
local lastRequestAt = -math.huge
local character
local humanoid
local root
local raycastParams
local sneakGroundY
local footprintOffsets = { Vector3.zero }
local edgeBarrier
local cameraTween
local sneakIdleAnimation
local sneakWalkAnimation
local sneakIdleTrack
local sneakWalkTrack
local sneakButton

local function updateSneakButton()
	if not sneakButton then
		return
	end
	sneakButton.BackgroundColor3 = crouchWanted and Color3.fromRGB(72, 177, 139) or Color3.fromRGB(88, 108, 126)
	local caption = sneakButton:FindFirstChild("CompactCaption")
	if caption and caption:IsA("TextLabel") then
		caption.Text = crouchWanted and "AGACHADO" or "AGACHAR"
	end
end

local function removeEdgeBarrier()
	if edgeBarrier then
		edgeBarrier:Destroy()
		edgeBarrier = nil
	end
end

local function getEdgeBarrier()
	if edgeBarrier then
		return edgeBarrier
	end

	local barrier = Instance.new("Part")
	barrier.Name = "SneakEdgeBarrier_V7_LocalOnly"
	barrier.Anchored = true
	barrier.CanCollide = true
	barrier.CanQuery = false
	barrier.CanTouch = false
	barrier.CastShadow = false
	barrier.Massless = true
	barrier.Transparency = 1
	barrier.Size = Vector3.new(
		SprintConfig.SneakEdgeBarrierWidth,
		SprintConfig.SneakEdgeBarrierHeight,
		SprintConfig.SneakEdgeBarrierThickness
	)
	edgeBarrier = barrier
	return barrier
end

local function hideEdgeBarrier()
	if edgeBarrier then
		-- Fora do Workspace a peca deixa de participar da fisica, mas pode ser
		-- reutilizada no proximo frame sem criar outra Instance.
		edgeBarrier.Parent = nil
	end
end

local function destroyAnimationTrack(track)
	if track then
		track:Stop(SprintConfig.SneakAnimationFadeTime)
		track:Destroy()
	end
end

local function stopSneakAnimations()
	destroyAnimationTrack(sneakIdleTrack)
	destroyAnimationTrack(sneakWalkTrack)
	sneakIdleTrack = nil
	sneakWalkTrack = nil

	if sneakIdleAnimation then
		sneakIdleAnimation:Destroy()
		sneakIdleAnimation = nil
	end
	if sneakWalkAnimation then
		sneakWalkAnimation:Destroy()
		sneakWalkAnimation = nil
	end
end

local function getAnimationAssetId(configuredValue)
	local configuredId = tostring(configuredValue or "")
	local numericId = string.match(configuredId, "%d+")
	if not numericId then
		return nil
	end
	return "rbxassetid://" .. numericId
end

local function loadAnimationTrack(animator, name, configuredId, speed)
	local assetId = getAnimationAssetId(configuredId)
	if not assetId then
		return nil, nil
	end

	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = assetId

	local success, loadedTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not success or not loadedTrack then
		warn("[SneakController] Nao foi possivel carregar " .. name .. ":", loadedTrack)
		animation:Destroy()
		return nil, nil
	end

	loadedTrack.Looped = true
	loadedTrack.Priority = SprintConfig.SneakAnimationPriority
	loadedTrack:AdjustSpeed(speed)
	return animation, loadedTrack
end

local function loadSneakAnimations()
	stopSneakAnimations()
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", 5)
	end
	if not animator then
		warn("[SneakController] Animator nao encontrado; animacoes de agachamento nao foram carregadas.")
		return
	end

	sneakIdleAnimation, sneakIdleTrack = loadAnimationTrack(
		animator,
		"SkyDungeonSneakIdle",
		SprintConfig.SneakIdleAnimationId,
		SprintConfig.SneakIdleAnimationSpeed
	)
	sneakWalkAnimation, sneakWalkTrack = loadAnimationTrack(
		animator,
		"SkyDungeonSneakWalk",
		SprintConfig.SneakWalkAnimationId,
		SprintConfig.SneakWalkAnimationSpeed
	)
end

local function canPlaySneakAnimation()
	if not crouchWanted or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end

	local state = humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Jumping
		and state ~= Enum.HumanoidStateType.Freefall
		and state ~= Enum.HumanoidStateType.Climbing
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Dead
end

local function playOnlySneakTrack(desiredTrack, desiredSpeed)
	local function updateTrack(track)
		if not track then
			return
		end
		if track == desiredTrack then
			if not track.IsPlaying then
				track:Play(SprintConfig.SneakAnimationFadeTime)
			end
			track:AdjustSpeed(desiredSpeed)
		elseif track and track.IsPlaying then
			track:Stop(SprintConfig.SneakAnimationFadeTime)
		end
	end

	updateTrack(sneakIdleTrack)
	updateTrack(sneakWalkTrack)
end

local function updateSneakAnimation()
	if not canPlaySneakAnimation() then
		playOnlySneakTrack(nil, 1)
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local isWalking = humanoid.MoveDirection.Magnitude > 0.05 and horizontalSpeed >= SprintConfig.SneakWalkMinimumSpeed

	if isWalking then
		playOnlySneakTrack(sneakWalkTrack, SprintConfig.SneakWalkAnimationSpeed)
	else
		playOnlySneakTrack(sneakIdleTrack, SprintConfig.SneakIdleAnimationSpeed)
	end
end

local function setCameraCrouched(enabled)
	if not humanoid then
		return
	end
	if cameraTween then
		cameraTween:Cancel()
	end
	cameraTween = TweenService:Create(
		humanoid,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CameraOffset = enabled and Vector3.new(0, -SprintConfig.SneakCameraDrop, 0) or Vector3.zero }
	)
	cameraTween:Play()
end

local function requestCrouch(enabled, force)
	if not force and enabled == crouchWanted and os.clock() - lastRequestAt < SprintConfig.RequestRetryInterval then
		return
	end

	crouchWanted = enabled
	updateSneakButton()
	lastRequestAt = os.clock()
	if enabled then
		-- O servidor tambem garante exclusao mutua, mas isto elimina atraso visual.
		sprintRemote:FireServer(false)
	end
	sneakRemote:FireServer(enabled)
	setCameraCrouched(enabled)
	if not enabled then
		hideEdgeBarrier()
	end
	updateSneakAnimation()
end

local function getGround(position)
	if not raycastParams or not root then
		return nil
	end

	local origin = position + Vector3.new(0, 0.5, 0)
	local avatarGroundDepth = humanoid and (humanoid.HipHeight + root.Size.Y * 0.5 + 1.25) or 0
	local probeDepth = math.max(SprintConfig.EdgeProbeDepth, avatarGroundDepth)
	local result = workspace:Raycast(origin, Vector3.new(0, -probeDepth, 0), raycastParams)
	if not result or result.Normal.Y < 0.55 then
		return nil
	end
	if result.Instance:IsA("BasePart") then
		return result.Instance.CanCollide and result or nil
	end
	return result.Instance == workspace.Terrain and result or nil
end

local function rebuildFootprintOffsets()
	if not root then
		footprintOffsets = { Vector3.zero }
		return
	end

	-- O pequeno recuo permite que parte do corpo fique para fora, como no
	-- Minecraft, sem exigir que o centro do personagem continue sobre o piso.
	local radius = math.max(0.15, math.max(root.Size.X, root.Size.Z) * 0.5 - SprintConfig.SneakEdgeFootprintInset)
	footprintOffsets = {
		Vector3.zero,
		Vector3.new(radius, 0, 0),
		Vector3.new(-radius, 0, 0),
		Vector3.new(0, 0, radius),
		Vector3.new(0, 0, -radius),
		Vector3.new(radius, 0, radius),
		Vector3.new(radius, 0, -radius),
		Vector3.new(-radius, 0, radius),
		Vector3.new(-radius, 0, -radius),
	}
end

local function findFootSupport(position, expectedGroundY)
	for _, offset in ipairs(footprintOffsets) do
		local result = getGround(position + offset)
		if
			result
			and (
				expectedGroundY == nil
				-- Subir continua permitido. Apenas uma queda maior que a
				-- tolerancia e tratada como uma borda sem apoio.
				or result.Position.Y >= expectedGroundY - SprintConfig.EdgeGroundHeightTolerance
			)
		then
			return result
		end
	end
	return nil
end

local function hasGroundInMovementDirection(position, direction, expectedGroundY)
	local rootRadius = math.max(root.Size.X, root.Size.Z) * 0.5
	local probeDistance =
		math.max(SprintConfig.SneakEdgeForwardProbeDistance, rootRadius + SprintConfig.SneakEdgeForwardProbeMargin)
	local probePosition = position + direction * probeDistance
	local result = getGround(probePosition)
	if not result then
		return false
	end

	return expectedGroundY == nil or result.Position.Y >= expectedGroundY - SprintConfig.EdgeGroundHeightTolerance
end

local function getDistanceToPartEdge(part, position, direction)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	local localPosition = part.CFrame:PointToObjectSpace(position)
	local localDirection = part.CFrame:VectorToObjectSpace(direction)
	local halfSize = part.Size * 0.5
	local distances = {}

	if math.abs(localDirection.X) > 0.0001 then
		local boundaryX = localDirection.X > 0 and halfSize.X or -halfSize.X
		local distanceX = (boundaryX - localPosition.X) / localDirection.X
		if distanceX >= 0 then
			table.insert(distances, distanceX)
		end
	end
	if math.abs(localDirection.Z) > 0.0001 then
		local boundaryZ = localDirection.Z > 0 and halfSize.Z or -halfSize.Z
		local distanceZ = (boundaryZ - localPosition.Z) / localDirection.Z
		if distanceZ >= 0 then
			table.insert(distances, distanceZ)
		end
	end

	if #distances == 0 then
		return nil
	end
	return math.min(table.unpack(distances))
end

local function showEdgeBarrier(direction, groundResult)
	local barrier = getEdgeBarrier()
	local rootRadius = math.max(root.Size.X, root.Size.Z) * 0.5
	local edgeDistance = getDistanceToPartEdge(groundResult.Instance, root.Position, direction)
	local fallbackDistance = math.max(SprintConfig.SneakEdgeBarrierMinimumDistance, rootRadius + barrier.Size.Z * 0.5)
	local wallDistance = edgeDistance and (edgeDistance + barrier.Size.Z * 0.5) or fallbackDistance
	local center = Vector3.new(root.Position.X, groundResult.Position.Y + barrier.Size.Y * 0.5, root.Position.Z)
		+ direction * wallDistance

	-- O eixo Z (espessura) aponta para a direcao bloqueada. A largura fica
	-- perpendicular ao input, permitindo que a fisica deslize pela parede.
	barrier.CFrame = CFrame.lookAt(center, center + direction, Vector3.yAxis)
	barrier.Parent = workspace
end

local function bindCharacter(newCharacter)
	removeEdgeBarrier()
	stopSneakAnimations()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	root = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end

	raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { newCharacter }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	rebuildFootprintOffsets()
	local initialGround = findFootSupport(root.Position, nil)
	sneakGroundY = initialGround and initialGround.Position.Y or nil
	loadSneakAnimations()

	humanoid.Died:Connect(function()
		if character ~= newCharacter then
			return
		end
		crouchWanted = false
		sneakGroundY = nil
		hideEdgeBarrier()
		updateSneakAnimation()
	end)

	humanoid.StateChanged:Connect(function(_, newState)
		if character ~= newCharacter then
			return
		end
		updateSneakAnimation()
	end)
end

local function setSneakFromKeyboard(enabled)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	requestCrouch(enabled, true)
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSneakFromKeyboard(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		requestCrouch(false, true)
	end
end)

local function sneakAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		-- R3 e toque sao toggle. Teclado continua com comportamento segurar via
		-- InputBegan/InputEnded acima.
		requestCrouch(not crouchWanted, true)
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_NAME, sneakAction, true, Enum.KeyCode.ButtonR3)
ContextActionService:SetTitle(ACTION_NAME, "◢")
ContextActionService:SetPosition(ACTION_NAME, SprintConfig.SneakTouchButtonPosition)

local button = ContextActionService:GetButton(ACTION_NAME)
if button then
	sneakButton = button
	button.Name = "SneakButton"
	button.Size = UDim2.fromOffset(58, 58)
	button.BackgroundColor3 = Color3.fromRGB(88, 108, 126)
	button.BackgroundTransparency = 0.14
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 232, 241)
	stroke.Transparency = 0.34
	stroke.Thickness = 1.5
	stroke.Parent = button
	local caption = Instance.new("TextLabel")
	caption.Name = "CompactCaption"
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -5)
	caption.Size = UDim2.new(1, -6, 0, 10)
	caption.BackgroundTransparency = 1
	caption.Text = "AGACHAR"
	caption.TextColor3 = Color3.fromRGB(243, 248, 252)
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = 8
	caption.Parent = button
end

player:GetAttributeChangedSignal("IsDowned"):Connect(function()
	if player:GetAttribute("IsDowned") == true and crouchWanted then
		requestCrouch(false, true)
	end
end)

RunService.PreSimulation:Connect(function()
	if not crouchWanted or not character or not humanoid or not root or humanoid.Health <= 0 then
		hideEdgeBarrier()
		return
	end

	local currentPosition = root.Position
	local velocity = root.AssemblyLinearVelocity
	local humanoidState = humanoid:GetState()

	-- Assim como no Minecraft, agachar nao impede um salto deliberado nem
	-- interfere em escalada ou natacao.
	if
		velocity.Y > 2
		or humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.Climbing
		or humanoidState == Enum.HumanoidStateType.Swimming
	then
		hideEdgeBarrier()
		return
	end

	local movement = humanoid.MoveDirection
	if movement.Magnitude <= 0.01 then
		hideEdgeBarrier()
		local stationarySupport = findFootSupport(currentPosition, sneakGroundY)
		if stationarySupport then
			sneakGroundY = stationarySupport.Position.Y
		end
		return
	end

	local currentSupport = findFootSupport(currentPosition, sneakGroundY)
	if not currentSupport then
		-- O personagem ja nao possui apoio (queda, impulso ou plataforma
		-- removida). Nao o puxa de volta artificialmente.
		hideEdgeBarrier()
		return
	end
	sneakGroundY = currentSupport.Position.Y

	local horizontalMovement = Vector3.new(movement.X, 0, movement.Z)
	if horizontalMovement.Magnitude <= 0.01 then
		hideEdgeBarrier()
		return
	end

	local direction = horizontalMovement.Unit
	if hasGroundInMovementDirection(currentPosition, direction, sneakGroundY) then
		hideEdgeBarrier()
	else
		showEdgeBarrier(direction, currentSupport)
	end
end)

RunService.Heartbeat:Connect(function()
	updateSneakAnimation()

	if crouchWanted and character and humanoid and humanoid.Health > 0 then
		if
			character:GetAttribute("Crouching") ~= true
			and os.clock() - lastRequestAt >= SprintConfig.RequestRetryInterval
		then
			lastRequestAt = os.clock()
			sneakRemote:FireServer(true)
		end
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end
