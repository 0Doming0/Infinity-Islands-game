-- Corrida e agachamento validados pelo servidor.
-- Preserva melhorias de velocidade usando SprintBaseWalkSpeed em ambos os modos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SprintConfig = require(ReplicatedStorage:WaitForChild("SprintConfig"))

local remote = ReplicatedStorage:FindFirstChild("SprintRequest")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SprintRequest"
	remote.Parent = ReplicatedStorage
end

local sneakRemote = ReplicatedStorage:FindFirstChild("SneakRequest")
if not sneakRemote then
	sneakRemote = Instance.new("RemoteEvent")
	sneakRemote.Name = "SneakRequest"
	sneakRemote.Parent = ReplicatedStorage
end

local states = {}

local function getMaximumStamina(player)
	return SprintConfig.GetMaximumSprintDuration(player:GetAttribute("Stamina"))
end

local function publishStamina(state, force)
	local now = os.clock()
	if not force and now - state.LastStaminaPublishAt < SprintConfig.StaminaPublishInterval then
		return
	end
	state.LastStaminaPublishAt = now
	if state.Character.Parent then
		state.Character:SetAttribute("SprintStamina", state.Stamina)
		state.Character:SetAttribute("SprintStaminaMax", state.MaximumStamina)
	end
end

local function refreshMaximumStamina(state)
	local newMaximum = getMaximumStamina(state.Player)
	if math.abs(newMaximum - state.MaximumStamina) <= 0.001 then
		return
	end

	local previousMaximum = state.MaximumStamina
	state.MaximumStamina = newMaximum
	state.Stamina = math.clamp(state.Stamina + math.max(0, newMaximum - previousMaximum), 0, newMaximum)
	publishStamina(state, true)
end

local function setWalkSpeed(state, speed)
	if not state.Humanoid.Parent then
		return
	end
	state.WritingSpeed = true
	state.Humanoid.WalkSpeed = speed
	state.LastAppliedSpeed = speed
	state.WritingSpeed = false
end

local function clearSprintAttributes(state)
	local character = state.Character
	local humanoid = state.Humanoid
	if character.Parent then
		character:SetAttribute("Sprinting", nil)
		character:SetAttribute("Crouching", nil)
	end
	if humanoid.Parent then
		humanoid:SetAttribute("SprintBaseWalkSpeed", nil)
		humanoid:SetAttribute("SprintSpeedMultiplier", nil)
	end
end

local function stopMovementMode(state, restoreBaseSpeed)
	if not state.Sprinting and not state.Crouching then
		return
	end

	local wasSprinting = state.Sprinting
	state.Sprinting = false
	state.Crouching = false
	if wasSprinting then
		state.LastSprintEndedAt = os.clock()
	end
	local baseSpeed = state.BaseWalkSpeed
	clearSprintAttributes(state)

	if restoreBaseSpeed and state.Humanoid.Health > 0 and baseSpeed > 0 then
		setWalkSpeed(state, baseSpeed)
	end
end

local function applyMovementSpeed(state)
	if not state.Sprinting and not state.Crouching then
		return
	end

	if state.Crouching then
		setWalkSpeed(state, state.BaseWalkSpeed * SprintConfig.SneakSpeedMultiplier)
	else
		local sprintSpeed =
			math.min(state.BaseWalkSpeed * SprintConfig.SpeedMultiplier, SprintConfig.MaximumSprintSpeed)
		setWalkSpeed(state, sprintSpeed)
	end
end

local function canUseMovementMode(state)
	local humanoid = state.Humanoid
	local character = state.Character
	return character.Parent ~= nil
		and humanoid.Parent ~= nil
		and humanoid.Health > 0
		and humanoid.WalkSpeed > 0
		and humanoid.Sit == false
		and character:GetAttribute("CombatStunned") ~= true
end

local function startSprinting(state)
	if
		state.Sprinting
		or state.Crouching
		or state.ExhaustionLocked
		or state.Stamina <= 0
		or not canUseMovementMode(state)
	then
		return
	end

	state.BaseWalkSpeed = state.Humanoid.WalkSpeed
	state.Sprinting = true
	state.LastMovingAt = os.clock()

	state.Humanoid:SetAttribute("SprintBaseWalkSpeed", state.BaseWalkSpeed)
	state.Humanoid:SetAttribute("SprintSpeedMultiplier", SprintConfig.SpeedMultiplier)
	state.Character:SetAttribute("Sprinting", true)
	applyMovementSpeed(state)
end

local function startCrouching(state)
	if state.Crouching or not canUseMovementMode(state) then
		return
	end

	if state.Sprinting then
		stopMovementMode(state, true)
	end

	state.BaseWalkSpeed = state.Humanoid.WalkSpeed
	state.Crouching = true
	state.LastMovingAt = os.clock()

	state.Humanoid:SetAttribute("SprintBaseWalkSpeed", state.BaseWalkSpeed)
	state.Character:SetAttribute("Crouching", true)
	applyMovementSpeed(state)
end

local function bindCharacter(player, character)
	local oldState = states[player]
	if oldState then
		oldState.Destroyed = true
		for _, connection in ipairs(oldState.Connections) do
			connection:Disconnect()
		end
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local maximumStamina = getMaximumStamina(player)
	local state = {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		BaseWalkSpeed = humanoid.WalkSpeed,
		Sprinting = false,
		Crouching = false,
		WritingSpeed = false,
		LastAppliedSpeed = humanoid.WalkSpeed,
		LastMovingAt = os.clock(),
		Stamina = maximumStamina,
		MaximumStamina = maximumStamina,
		LastSprintEndedAt = -math.huge,
		LastStaminaPublishAt = -math.huge,
		ExhaustionLocked = false,
		Connections = {},
		Destroyed = false,
	}
	states[player] = state
	clearSprintAttributes(state)
	publishStamina(state, true)

	table.insert(
		state.Connections,
		player:GetAttributeChangedSignal("Stamina"):Connect(function()
			refreshMaximumStamina(state)
		end)
	)

	table.insert(
		state.Connections,
		humanoid:GetAttributeChangedSignal("SprintBaseWalkSpeed"):Connect(function()
			if state.WritingBaseAttribute or (not state.Sprinting and not state.Crouching) then
				return
			end
			local newBase = humanoid:GetAttribute("SprintBaseWalkSpeed")
			if typeof(newBase) == "number" and newBase > 0 then
				state.BaseWalkSpeed = newBase
				applyMovementSpeed(state)
			end
		end)
	)

	table.insert(
		state.Connections,
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if state.WritingSpeed or (not state.Sprinting and not state.Crouching) then
				return
			end

			local newSpeed = humanoid.WalkSpeed
			if newSpeed <= 0 then
				stopMovementMode(state, false)
				return
			end

			-- Compatibilidade com scripts legados que ainda somem diretamente
			-- em WalkSpeed durante a corrida.
			local delta = newSpeed - state.LastAppliedSpeed
			if math.abs(delta) > 0.001 then
				state.BaseWalkSpeed = math.max(0, state.BaseWalkSpeed + delta)
				state.WritingBaseAttribute = true
				humanoid:SetAttribute("SprintBaseWalkSpeed", state.BaseWalkSpeed)
				state.WritingBaseAttribute = false
				applyMovementSpeed(state)
			end
		end)
	)

	table.insert(
		state.Connections,
		character:GetAttributeChangedSignal("CombatStunned"):Connect(function()
			if character:GetAttribute("CombatStunned") == true then
				stopMovementMode(state, true)
			end
		end)
	)

	table.insert(
		state.Connections,
		humanoid.Died:Connect(function()
			stopMovementMode(state, false)
		end)
	)
end

remote.OnServerEvent:Connect(function(player, wantsSprint)
	if typeof(wantsSprint) ~= "boolean" then
		return
	end
	local state = states[player]
	if not state or state.Destroyed then
		return
	end
	if wantsSprint then
		startSprinting(state)
	else
		state.ExhaustionLocked = false
		if state.Sprinting then
			stopMovementMode(state, true)
		end
	end
end)

sneakRemote.OnServerEvent:Connect(function(player, wantsSneak)
	if typeof(wantsSneak) ~= "boolean" then
		return
	end
	local state = states[player]
	if not state or state.Destroyed then
		return
	end
	if wantsSneak then
		startCrouching(state)
	elseif state.Crouching then
		stopMovementMode(state, true)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()
	for _, state in pairs(states) do
		if state.Sprinting or state.Crouching then
			if not canUseMovementMode(state) then
				stopMovementMode(state, true)
			elseif state.Humanoid.MoveDirection.Magnitude > 0.05 then
				state.LastMovingAt = now
				if state.Sprinting then
					state.Stamina = math.max(0, state.Stamina - deltaTime)
					publishStamina(state, false)
					if state.Stamina <= 0 then
						state.ExhaustionLocked = true
						stopMovementMode(state, true)
						publishStamina(state, true)
					end
				end
			elseif state.Sprinting and now - state.LastMovingAt >= SprintConfig.IdleStopDelay then
				stopMovementMode(state, true)
			end
		end

		if
			not state.Sprinting
			and state.Stamina < state.MaximumStamina
			and now - state.LastSprintEndedAt >= SprintConfig.StaminaRegenDelay
		then
			local regenPerSecond = state.MaximumStamina / SprintConfig.StaminaRegenDuration
			state.Stamina = math.min(state.MaximumStamina, state.Stamina + regenPerSecond * deltaTime)
			publishStamina(state, state.Stamina >= state.MaximumStamina)
		end
	end
end)

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		task.spawn(bindCharacter, player, player.Character)
	end
end

Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state then
		state.Destroyed = true
		for _, connection in ipairs(state.Connections) do
			connection:Disconnect()
		end
		states[player] = nil
	end
end)

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
