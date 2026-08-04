-- SkyDungeon - transicao do resgate de santuario.
--
-- Reutiliza diretamente a ScreenGui RespawnTransition criada por
-- DeathScreen.client.luau. Dessa forma, o teleporte para o ponto seguro usa
-- exatamente as mesmas cortinas, spinner, timing, streaming e animacao de
-- abertura do renascimento, alterando somente os textos do contexto.
--
-- Estados esperados do servidor:
-- Idle -> Searching -> Teleporting -> Stabilizing -> Idle
--
-- O personagem atual e preservado. Este script nao chama LoadCharacter,
-- nao concede recompensas e nao altera progresso.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "RespawnVisualParityV1"
local ACTIVE_STATES = {
	Searching = true,
	Teleporting = true,
	Stabilizing = true,
}
local SUCCESS_STATES = {
	Idle = true,
	Ready = true,
	Complete = true,
	Completed = true,
	Finished = true,
}
local FAILURE_STATES = {
	Failed = true,
	Error = true,
	Cancelled = true,
	Canceled = true,
}

local STREAMING_TIMEOUT_SECONDS = 20
local SERVER_WATCHDOG_SECONDS = 30
local STABLE_FRAME_GOAL = 2
local INPUT_ACTION = "SanctuaryRescueTransitionInputBlock"

local transitionGui = playerGui:WaitForChild("RespawnTransition")
local topCurtain = transitionGui:WaitForChild("TopCurtain")
local bottomCurtain = transitionGui:WaitForChild("BottomCurtain")
local loadingGroup = transitionGui:WaitForChild("Loading")

local loadingMark = loadingGroup:FindFirstChildWhichIsA("Frame")
local loadingText = loadingGroup:FindFirstChildWhichIsA("TextLabel")

assert(topCurtain:IsA("GuiObject"), "RespawnTransition.TopCurtain precisa ser GuiObject")
assert(bottomCurtain:IsA("GuiObject"), "RespawnTransition.BottomCurtain precisa ser GuiObject")
assert(loadingGroup:IsA("CanvasGroup"), "RespawnTransition.Loading precisa ser CanvasGroup")
assert(loadingMark, "RespawnTransition.Loading nao possui o marcador")
assert(loadingText, "RespawnTransition.Loading nao possui o texto")

transitionGui:SetAttribute("SanctuaryRescueTransitionVersion", VERSION)
workspace:SetAttribute("SanctuaryRescueTransitionVersion", VERSION)

local inputBlocker = transitionGui:FindFirstChild("SanctuaryRescueInputBlocker")
if inputBlocker and not inputBlocker:IsA("TextButton") then
	inputBlocker:Destroy()
	inputBlocker = nil
end
if not inputBlocker then
	inputBlocker = Instance.new("TextButton")
	inputBlocker.Name = "SanctuaryRescueInputBlocker"
	inputBlocker.Size = UDim2.fromScale(1, 1)
	inputBlocker.Position = UDim2.fromScale(0, 0)
	inputBlocker.BackgroundTransparency = 1
	inputBlocker.Text = ""
	inputBlocker.AutoButtonColor = false
	inputBlocker.Active = true
	inputBlocker.Selectable = false
	inputBlocker.Modal = true
	inputBlocker.Visible = false
	inputBlocker.ZIndex = 100
	inputBlocker.Parent = transitionGui
end

local token = 0
local rescueActive = false
local opening = false
local startedAt = 0
local lastState = "Idle"
local controlsBlocked = false

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function stateText(state)
	if state == "Searching" then
		return "PROCURANDO UM NOVO REFÚGIO"
	elseif state == "Teleporting" then
		return "VIAJANDO PARA UM PONTO SEGURO"
	elseif state == "Stabilizing" then
		return "CARREGANDO O REFÚGIO"
	end
	return "PREPARANDO O REFÚGIO"
end

local function sinkInput()
	return Enum.ContextActionResult.Sink
end

local function blockControls()
	if controlsBlocked then
		return
	end
	controlsBlocked = true
	inputBlocker.Visible = true
	ContextActionService:BindActionAtPriority(
		INPUT_ACTION,
		sinkInput,
		false,
		10000,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonL3,
		Enum.KeyCode.Thumbstick1
	)
end

local function releaseControls()
	if not controlsBlocked then
		return
	end
	controlsBlocked = false
	inputBlocker.Visible = false
	ContextActionService:UnbindAction(INPUT_ACTION)
end

local function respawnOwnsTransition()
	local respawnState = tostring(player:GetAttribute("RespawnState") or "Ready")
	local lifecycle = tostring(player:GetAttribute("PlayerLifecycleState") or "Playing")
	return respawnState ~= "Ready"
		or lifecycle == "Respawning"
		or lifecycle == "InitialSpawning"
		or lifecycle == "Failed"
end

local function resetClosedVisual(message)
	topCurtain.Position = UDim2.fromScale(0, 0)
	bottomCurtain.Position = UDim2.fromScale(0, 0.495)
	loadingGroup.GroupTransparency = 0
	loadingMark.Rotation = 45
	loadingText.Text = message
end

local function showTransition(state)
	if respawnOwnsTransition() then
		return
	end

	token += 1
	rescueActive = true
	opening = false
	startedAt = os.clock()
	lastState = state

	resetClosedVisual(stateText(state))
	transitionGui.Enabled = true
	transitionGui:SetAttribute("TransitionOwner", "SanctuaryRescue")
	transitionGui:SetAttribute("SanctuaryRescueState", state)
	player:SetAttribute("SanctuaryRescueTransitionClientState", "Showing:" .. state)
	player:SetAttribute("SanctuaryRescueTransitionStartedAt", serverTime())

	blockControls()

	local currentToken = token
	task.delay(SERVER_WATCHDOG_SECONDS, function()
		if currentToken ~= token or not rescueActive or opening then
			return
		end
		local currentState = tostring(player:GetAttribute("SanctuaryRescueState") or "Idle")
		if ACTIVE_STATES[currentState] then
			loadingText.Text = "FINALIZANDO O RESGATE"
			player:SetAttribute(
				"SanctuaryRescueTransitionClientState",
				"WaitingForServer:" .. currentState
			)
		end
	end)
end

local function updateActiveText(state)
	lastState = state
	transitionGui:SetAttribute("SanctuaryRescueState", state)
	if not opening then
		loadingText.Text = stateText(state)
	end
	player:SetAttribute("SanctuaryRescueTransitionClientState", "Showing:" .. state)
end

local function hasLoadedFloor(character, rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local hit = workspace:Raycast(
		rootPart.Position + Vector3.new(0, 2, 0),
		Vector3.new(0, -20, 0),
		params
	)

	return hit ~= nil
		and hit.Instance:IsA("BasePart")
		and hit.Instance.CanCollide
end

local function cameraIsReady(character, humanoid)
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local subject = camera.CameraSubject
	return subject == humanoid
		or (subject ~= nil and subject:IsDescendantOf(character))
end

local function finishTransition(currentToken)
	if currentToken ~= token then
		return
	end

	rescueActive = false
	opening = false
	transitionGui.Enabled = false
	transitionGui:SetAttribute("TransitionOwner", nil)
	transitionGui:SetAttribute("SanctuaryRescueState", nil)
	player:SetAttribute("SanctuaryRescueTransitionClientState", "Hidden")
	player:SetAttribute("SanctuaryRescueTransitionCompletedAt", serverTime())
	releaseControls()
end

local function yieldToRespawn()
	token += 1
	rescueActive = false
	opening = false
	transitionGui:SetAttribute("TransitionOwner", "Respawn")
	player:SetAttribute("SanctuaryRescueTransitionClientState", "YieldedToRespawn")
	releaseControls()
	-- Nao desliga a GUI. O DeathScreen passa a controlar a mesma transicao.
end

local function openTransition(failed)
	if opening or not rescueActive or not transitionGui.Enabled then
		return
	end
	if respawnOwnsTransition() then
		yieldToRespawn()
		return
	end

	opening = true
	local currentToken = token

	task.spawn(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not character or not humanoid or humanoid.Health <= 0 or not rootPart then
			if respawnOwnsTransition() then
				yieldToRespawn()
			else
				finishTransition(currentToken)
			end
			return
		end

		if failed then
			loadingText.Text = "NÃO FOI POSSÍVEL CONCLUIR O RESGATE"
			task.wait(0.65)
		else
			loadingText.Text = "CARREGANDO O REFÚGIO"

			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(rootPart.Position, 5)
				end)
			end)

			local stableFrames = 0
			local waitingSince = os.clock()
			local streamingDeadline = waitingSince + STREAMING_TIMEOUT_SECONDS
			local nextStreamingRequest = waitingSince + 4

			repeat
				RunService.Heartbeat:Wait()

				if currentToken ~= token then
					return
				end
				if respawnOwnsTransition() then
					yieldToRespawn()
					return
				end
				if player.Character ~= character or humanoid.Health <= 0 then
					finishTransition(currentToken)
					return
				end

				local ready = hasLoadedFloor(character, rootPart)
					and not rootPart.Anchored
					and cameraIsReady(character, humanoid)

				if ready then
					stableFrames += 1
				else
					stableFrames = 0
				end

				if os.clock() >= nextStreamingRequest then
					nextStreamingRequest = os.clock() + 4
					loadingText.Text = os.clock() - waitingSince >= 8
						and "FINALIZANDO O REFÚGIO"
						or "CARREGANDO O REFÚGIO"

					task.spawn(function()
						pcall(function()
							player:RequestStreamAroundAsync(rootPart.Position, 4)
						end)
					end)
				end
			until stableFrames >= STABLE_FRAME_GOAL
				or os.clock() >= streamingDeadline
		end

		if currentToken ~= token then
			return
		end
		if respawnOwnsTransition() then
			yieldToRespawn()
			return
		end

		loadingText.Text = failed and "RETORNANDO" or "PRONTO"
		task.wait(0.12)

		TweenService:Create(
			loadingGroup,
			TweenInfo.new(
				0.18,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{ GroupTransparency = 1 }
		):Play()

		local curtainInfo = TweenInfo.new(
			0.65,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.InOut
		)
		local topTween = TweenService:Create(
			topCurtain,
			curtainInfo,
			{ Position = UDim2.fromScale(0, -0.505) }
		)
		local bottomTween = TweenService:Create(
			bottomCurtain,
			curtainInfo,
			{ Position = UDim2.fromScale(0, 1) }
		)

		topTween:Play()
		bottomTween:Play()
		topTween.Completed:Wait()

		if currentToken == token then
			finishTransition(currentToken)
		end
	end)
end

local function handleStateChanged()
	local state = tostring(player:GetAttribute("SanctuaryRescueState") or "Idle")

	if ACTIVE_STATES[state] then
		if not rescueActive then
			showTransition(state)
		else
			updateActiveText(state)
		end
		return
	end

	if not rescueActive then
		lastState = state
		return
	end

	if FAILURE_STATES[state] then
		player:SetAttribute(
			"SanctuaryRescueTransitionClientState",
			"Failed:" .. state
		)
		openTransition(true)
	elseif SUCCESS_STATES[state] then
		player:SetAttribute(
			"SanctuaryRescueTransitionClientState",
			"Opening:" .. state
		)
		openTransition(false)
	end
end

player:GetAttributeChangedSignal("SanctuaryRescueState"):Connect(handleStateChanged)

player:GetAttributeChangedSignal("RespawnState"):Connect(function()
	if rescueActive and respawnOwnsTransition() then
		yieldToRespawn()
	end
end)

player.CharacterRemoving:Connect(function()
	if rescueActive then
		yieldToRespawn()
	end
end)

-- Recupera corretamente caso o LocalScript seja iniciado no meio de um resgate.
handleStateChanged()
