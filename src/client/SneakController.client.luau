-- Shift/R3/botao de toque: agachamento com protecao contra queda de bordas.

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

local ACTION_NAME = "SkyDungeonSneak"
local crouchWanted = false
local lastRequestAt = -math.huge
local character
local humanoid
local root
local raycastParams
local lastSafePosition
local lastSafeGroundY
local cameraTween
local sneakIdleAnimation
local sneakWalkAnimation
local sneakIdleTrack
local sneakWalkTrack

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
	lastRequestAt = os.clock()
	if enabled then
		-- O servidor tambem garante exclusao mutua, mas isto elimina atraso visual.
		sprintRemote:FireServer(false)
	end
	sneakRemote:FireServer(enabled)
	setCameraCrouched(enabled)
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

local function hasSameLevelGround(position, expectedGroundY)
	local result = getGround(position)
	return result ~= nil
		and expectedGroundY ~= nil
		and math.abs(result.Position.Y - expectedGroundY) <= SprintConfig.EdgeGroundHeightTolerance
end

local function bindCharacter(newCharacter)
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
	lastSafePosition = root.Position
	local initialGround = getGround(root.Position)
	lastSafeGroundY = initialGround and initialGround.Position.Y or nil
	loadSneakAnimations()

	humanoid.Died:Connect(function()
		if character ~= newCharacter then
			return
		end
		crouchWanted = false
		lastSafePosition = nil
		lastSafeGroundY = nil
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
		requestCrouch(true, true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		requestCrouch(false, true)
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_NAME, sneakAction, true, Enum.KeyCode.ButtonR3)
ContextActionService:SetTitle(ACTION_NAME, "AGACHAR")
ContextActionService:SetPosition(ACTION_NAME, SprintConfig.SneakTouchButtonPosition)

local button = ContextActionService:GetButton(ACTION_NAME)
if button then
	button.Name = "SneakButton"
	button.Size = UDim2.fromOffset(82, 82)
	button.BackgroundColor3 = Color3.fromRGB(88, 108, 126)
	button.BackgroundTransparency = 0.14
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
end

RunService.PreSimulation:Connect(function()
	if not crouchWanted or not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local currentPosition = root.Position
	local velocity = root.AssemblyLinearVelocity
	local humanoidState = humanoid:GetState()

	-- Um salto iniciado pelo jogador pode sair da borda normalmente.
	if
		velocity.Y > 2
		or humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.Climbing
		or humanoidState == Enum.HumanoidStateType.Swimming
	then
		return
	end

	local currentGround = getGround(currentPosition)
	if currentGround and lastSafeGroundY == nil then
		lastSafeGroundY = currentGround.Position.Y
	end

	local movement = humanoid.MoveDirection
	if movement.Magnitude <= 0.01 then
		if
			currentGround
			and (
				lastSafeGroundY == nil
				or math.abs(currentGround.Position.Y - lastSafeGroundY) <= SprintConfig.EdgeGroundHeightTolerance
			)
		then
			lastSafePosition = currentPosition
			lastSafeGroundY = currentGround.Position.Y
		end
		return
	end

	local forward = Vector3.new(movement.X, 0, movement.Z).Unit
	local rootRadius = math.max(root.Size.X, root.Size.Z) * 0.5
	local probeDistance = rootRadius + SprintConfig.EdgeProbeMargin
	local expectedGroundY = currentGround and currentGround.Position.Y or lastSafeGroundY
	local probePosition = currentPosition + forward * probeDistance

	if currentGround and hasSameLevelGround(probePosition, expectedGroundY) then
		lastSafePosition = currentPosition
		lastSafeGroundY = currentGround.Position.Y
		return
	end

	-- Cancela o passo antes de a capsula do personagem ultrapassar a borda.
	humanoid:Move(Vector3.zero, false)
	root.AssemblyLinearVelocity = Vector3.new(0, math.min(velocity.Y, 0), 0)

	if lastSafePosition then
		local rotation = root.CFrame.Rotation
		root.CFrame = CFrame.new(lastSafePosition.X, currentPosition.Y, lastSafePosition.Z) * rotation
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
