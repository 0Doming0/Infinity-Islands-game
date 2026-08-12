--[[
	SkyDungeon - SlimeAnimator

	Ponte entre os estados do SlimeController e animacoes do modelo. Aproveita
	as configuracoes existentes dentro do Script Animate e usa animacoes R6
	classicas como fallback enquanto clips proprios dos slimes nao existirem.
]]

local SlimeAnimator = {}

local active = {}

local FALLBACKS = {
	Idle = "rbxassetid://125750544",
	Move = "rbxassetid://125749145",
	Attack = "rbxassetid://129967390",
	Shoot = "rbxassetid://129967390",
	Mortar = "rbxassetid://129967478",
	Teleport = "rbxassetid://125750702",
	Hit = "rbxassetid://125750759",
	Death = "rbxassetid://125750759",
}

local SEARCH_NAMES = {
	Idle = { "Idle", "idle" },
	Move = { "Move", "Walk", "Run", "walk", "run" },
	Attack = { "Attack", "Melee", "Slash", "toolslash" },
	Shoot = { "Shoot", "RangedAttack", "Attack", "toolslash" },
	Mortar = { "Mortar", "MortarAttack", "Lunge", "toollunge", "Attack" },
	Teleport = { "Teleport", "Jump", "jump" },
	Hit = { "Hit", "Damage", "Fall", "fall" },
	Death = { "Death", "Die", "Fall", "fall" },
}

local TRACK_SETTINGS = {
	Idle = { Looped = true, Priority = Enum.AnimationPriority.Idle },
	Move = { Looped = true, Priority = Enum.AnimationPriority.Movement },
	Attack = { Looped = false, Priority = Enum.AnimationPriority.Action },
	Shoot = { Looped = false, Priority = Enum.AnimationPriority.Action },
	Mortar = { Looped = false, Priority = Enum.AnimationPriority.Action },
	Teleport = { Looped = false, Priority = Enum.AnimationPriority.Action2 },
	Hit = { Looped = false, Priority = Enum.AnimationPriority.Action2 },
	Death = { Looped = false, Priority = Enum.AnimationPriority.Action4 },
}

local MOVING_STATES = {
	Wander = true,
	Chase = true,
	Approach = true,
	Hunt = true,
	Strafe = true,
	Retreat = true,
	Flee = true,
}

local ACTION_BY_STATE = {
	Melee = "Attack",
	RangedAttack = "Shoot",
	Mortar = "Mortar",
	Teleport = "Teleport",
}

local function findChildIgnoringCase(parent, wantedName)
	if not parent then
		return nil
	end
	local exact = parent:FindFirstChild(wantedName)
	if exact then
		return exact
	end
	local lowerName = string.lower(wantedName)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == lowerName then
			return child
		end
	end
	return nil
end

local function animationFromNode(node)
	if not node then
		return nil
	end
	if node:IsA("Animation") and node.AnimationId ~= "" then
		return node
	end
	local animation = node:FindFirstChildWhichIsA("Animation", true)
	if animation and animation.AnimationId ~= "" then
		return animation
	end
	return nil
end

local function findConfiguredAnimation(model, animateScript, slot)
	local containers = {
		model:FindFirstChild("Animations"),
		model:FindFirstChild("Animation"),
		animateScript,
	}
	for _, container in ipairs(containers) do
		if container then
			for _, name in ipairs(SEARCH_NAMES[slot]) do
				local animation = animationFromNode(findChildIgnoringCase(container, name))
				if animation then
					return animation
				end
			end
		end
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Animation") and descendant.AnimationId ~= "" then
			for _, name in ipairs(SEARCH_NAMES[slot]) do
				if string.lower(descendant.Name) == string.lower(name) then
					return descendant
				end
			end
		end
	end
	return nil
end

local function createFallback(slot)
	local animationId = FALLBACKS[slot]
	if not animationId then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = "Runtime" .. slot
	animation.AnimationId = animationId
	return animation
end

local function loadTrack(animator, animation, settings)
	if not animation then
		return nil
	end
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not success or not track then
		return nil
	end
	track.Looped = settings.Looped
	track.Priority = settings.Priority
	return track
end

local function stopTrack(track, fadeTime)
	if not track then
		return
	end
	pcall(function()
		track:Stop(fadeTime or 0.1)
	end)
end

local function stopCurrentLoop(state, fadeTime)
	if state.CurrentLoopTrack then
		stopTrack(state.CurrentLoopTrack, fadeTime)
	end
	state.CurrentLoopTrack = nil
	state.CurrentLoopSlot = nil
end

local function playLoop(state, slot, speed)
	local track = state.Tracks[slot]
	if not track then
		return
	end
	if state.CurrentLoopSlot ~= slot then
		stopCurrentLoop(state, 0.12)
		local success = pcall(function()
			track:Play(0.12, 1, speed or 1)
		end)
		if not success then
			return
		end
		state.CurrentLoopSlot = slot
		state.CurrentLoopTrack = track
	elseif track.IsPlaying then
		pcall(function()
			track:AdjustSpeed(speed or 1)
		end)
	else
		pcall(function()
			track:Play(0.1, 1, speed or 1)
		end)
	end
end

local function playAction(state, slot)
	local track = state.Tracks[slot]
	if not track then
		return
	end
	if state.CurrentActionTrack and state.CurrentActionTrack ~= track then
		stopTrack(state.CurrentActionTrack, 0.06)
	end
	pcall(function()
		track:Stop(0)
		track:Play(0.08, 1, 1)
	end)
	state.CurrentActionTrack = track
end

local function movementSpeed(state, aiState)
	local humanoidSpeed = state.Humanoid.WalkSpeed
	local speed = math.clamp(humanoidSpeed / 12, 0.55, 1.8)
	if aiState == "Wander" then
		return speed * 0.82
	elseif aiState == "Flee" or aiState == "Chase" or aiState == "Hunt" then
		return math.min(1.9, speed * 1.12)
	end
	return speed
end

local function applyAIState(state)
	if not state.Model.Parent or state.Humanoid.Health <= 0 then
		return
	end
	local aiState = state.Model:GetAttribute("AIState") or "Idle"
	if MOVING_STATES[aiState] or state.Model:GetAttribute("IsMoving") == true then
		playLoop(state, "Move", movementSpeed(state, aiState))
	else
		playLoop(state, "Idle", 1)
	end

	local actionSlot = ACTION_BY_STATE[aiState]
	if actionSlot and state.LastActionState ~= aiState then
		playAction(state, actionSlot)
	end
	state.LastActionState = actionSlot and aiState or nil
end

local function playDeath(state)
	stopCurrentLoop(state, 0.08)
	if state.CurrentActionTrack then
		stopTrack(state.CurrentActionTrack, 0.05)
	end
	playAction(state, "Death")
end

function SlimeAnimator.Start(model, humanoid)
	SlimeAnimator.Stop(model)
	if not model or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animateScript = model:FindFirstChild("Animate", true)
	local state = {
		Model = model,
		Humanoid = humanoid,
		Animator = animator,
		AnimateScript = animateScript,
		Tracks = {},
		OwnedAnimations = {},
		Connections = {},
		CurrentLoopTrack = nil,
		CurrentLoopSlot = nil,
		CurrentActionTrack = nil,
		LastActionState = nil,
	}

	for slot, settings in pairs(TRACK_SETTINGS) do
		local animation = findConfiguredAnimation(model, animateScript, slot)
		if not animation then
			animation = createFallback(slot)
			if animation then
				table.insert(state.OwnedAnimations, animation)
			end
		end
		state.Tracks[slot] = loadTrack(animator, animation, settings)
	end

	if not state.Tracks.Idle and not state.Tracks.Move then
		for _, animation in ipairs(state.OwnedAnimations) do
			animation:Destroy()
		end
		return false
	end

	-- O Animate antigo e desativado apenas depois que o substituto carregou.
	if animateScript and animateScript:IsA("BaseScript") then
		animateScript.Disabled = true
	end
	for _, playingTrack in ipairs(animator:GetPlayingAnimationTracks()) do
		stopTrack(playingTrack, 0.08)
	end

	active[model] = state
	table.insert(state.Connections, model:GetAttributeChangedSignal("AIState"):Connect(function()
		applyAIState(state)
	end))
	table.insert(state.Connections, model:GetAttributeChangedSignal("IsMoving"):Connect(function()
		applyAIState(state)
	end))
	table.insert(state.Connections, model:GetAttributeChangedSignal("CombatHitReactionSerial"):Connect(function()
		if active[model] == state and humanoid.Health > 0 then
			playAction(state, "Hit")
		end
	end))
	table.insert(state.Connections, humanoid.Running:Connect(function()
		if state.CurrentLoopSlot == "Move" then
			applyAIState(state)
		end
	end))
	table.insert(state.Connections, humanoid.Died:Connect(function()
		playDeath(state)
	end))
	applyAIState(state)
	return true
end

local function destroyState(state)
	for _, track in pairs(state.Tracks) do
		if track then
			stopTrack(track, 0.05)
			pcall(function()
				track:Destroy()
			end)
		end
	end
	for _, animation in ipairs(state.OwnedAnimations) do
		animation:Destroy()
	end
end

function SlimeAnimator.Stop(model)
	local state = active[model]
	if not state then
		return
	end
	active[model] = nil
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	if state.Humanoid.Health <= 0 and state.Model.Parent then
		playDeath(state)
		task.delay(0.65, function()
			destroyState(state)
		end)
		return
	end
	destroyState(state)
end

return table.freeze(SlimeAnimator)
