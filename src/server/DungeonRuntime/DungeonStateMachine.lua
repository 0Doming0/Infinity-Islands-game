local DungeonStateMachine = {}
DungeonStateMachine.__index = DungeonStateMachine

DungeonStateMachine.States = table.freeze({
	Initializing = "Initializing",
	Active = "Active",
	ObjectiveComplete = "ObjectiveComplete",
	Transitioning = "Transitioning",
	RoundReward = "RoundReward",
	BossPending = "BossPending",
	BossActive = "BossActive",
	WipePending = "WipePending",
	Victory = "Victory",
	Defeat = "Defeat",
	Returning = "Returning",
})

local VALID_STATES = {}
for _, state in pairs(DungeonStateMachine.States) do
	VALID_STATES[state] = true
end

local ALLOWED_TRANSITIONS = {
	Initializing = {
		Active = true,
		Defeat = true,
		Returning = true,
	},
	Active = {
		ObjectiveComplete = true,
		Transitioning = true,
		RoundReward = true,
		BossPending = true,
		WipePending = true,
		Victory = true,
		Defeat = true,
		Returning = true,
	},
	ObjectiveComplete = {
		Active = true,
		Transitioning = true,
		RoundReward = true,
		BossPending = true,
		Defeat = true,
		Returning = true,
	},
	Transitioning = {
		Active = true,
		RoundReward = true,
		BossPending = true,
		BossActive = true,
		WipePending = true,
		Defeat = true,
		Returning = true,
	},
	RoundReward = {
		Active = true,
		Transitioning = true,
		BossPending = true,
		WipePending = true,
		Defeat = true,
		Returning = true,
	},
	BossPending = {
		BossActive = true,
		WipePending = true,
		Defeat = true,
		Returning = true,
	},
	BossActive = {
		WipePending = true,
		Victory = true,
		Defeat = true,
		Returning = true,
	},
	WipePending = {
		Active = true,
		ObjectiveComplete = true,
		Transitioning = true,
		RoundReward = true,
		BossPending = true,
		BossActive = true,
		Defeat = true,
		Returning = true,
	},
	Victory = {
		Returning = true,
	},
	Defeat = {
		Returning = true,
	},
	Returning = {},
}

local function cloneContext(context)
	if type(context) ~= "table" then
		return {}
	end
	return table.clone(context)
end

function DungeonStateMachine.new(options)
	options = type(options) == "table" and options or {}
	local initialState = options.InitialState or DungeonStateMachine.States.Initializing
	assert(VALID_STATES[initialState], "Estado inicial invalido: " .. tostring(initialState))

	local changedEvent = Instance.new("BindableEvent")
	local now = workspace:GetServerTimeNow()
	local self = setmetatable({
		_state = initialState,
		_sequence = 0,
		_enteredAt = now,
		_history = {},
		_changedEvent = changedEvent,
		_onTransition = options.OnTransition,
		_destroyed = false,
	}, DungeonStateMachine)

	if self._onTransition then
		local ok, errorMessage = pcall(self._onTransition, {
			PreviousState = nil,
			State = initialState,
			Sequence = 0,
			EnteredAt = now,
			Context = { Reason = "Initialized" },
		})
		if not ok then
			warn("[DungeonStateMachine] OnTransition inicial falhou: " .. tostring(errorMessage))
		end
	end

	return self
end

function DungeonStateMachine:IsValidState(state)
	return VALID_STATES[state] == true
end

function DungeonStateMachine:GetState()
	return self._state
end

function DungeonStateMachine:GetSequence()
	return self._sequence
end

function DungeonStateMachine:GetEnteredAt()
	return self._enteredAt
end

function DungeonStateMachine:GetHistory()
	local result = {}
	for index, entry in ipairs(self._history) do
		result[index] = {
			PreviousState = entry.PreviousState,
			State = entry.State,
			Sequence = entry.Sequence,
			EnteredAt = entry.EnteredAt,
			Context = cloneContext(entry.Context),
		}
	end
	return result
end

function DungeonStateMachine:CanTransition(nextState)
	if self._destroyed then
		return false, "StateMachineDestroyed"
	end
	if not VALID_STATES[nextState] then
		return false, "InvalidState"
	end
	if nextState == self._state then
		return true
	end
	if ALLOWED_TRANSITIONS[self._state] and ALLOWED_TRANSITIONS[self._state][nextState] then
		return true
	end
	return false, string.format("InvalidTransition:%s->%s", tostring(self._state), tostring(nextState))
end

function DungeonStateMachine:Transition(nextState, context)
	context = cloneContext(context)
	local canTransition, errorCode = self:CanTransition(nextState)
	if not canTransition and context.Force ~= true then
		return false, errorCode
	end
	if nextState == self._state then
		return true, "AlreadyInState"
	end

	local previousState = self._state
	self._state = nextState
	self._sequence += 1
	self._enteredAt = workspace:GetServerTimeNow()
	local entry = {
		PreviousState = previousState,
		State = nextState,
		Sequence = self._sequence,
		EnteredAt = self._enteredAt,
		Context = context,
	}
	table.insert(self._history, entry)
	if #self._history > 32 then
		table.remove(self._history, 1)
	end

	self._changedEvent:Fire(entry)
	if self._onTransition then
		local ok, errorMessage = pcall(self._onTransition, entry)
		if not ok then
			warn("[DungeonStateMachine] OnTransition falhou: " .. tostring(errorMessage))
		end
	end
	return true
end

function DungeonStateMachine:PublishCurrent(context)
	if self._destroyed then
		return false, "StateMachineDestroyed"
	end
	local entry = {
		PreviousState = self._state,
		State = self._state,
		Sequence = self._sequence,
		EnteredAt = self._enteredAt,
		Context = cloneContext(context),
	}
	self._changedEvent:Fire(entry)
	if self._onTransition then
		local ok, errorMessage = pcall(self._onTransition, entry)
		if not ok then
			warn("[DungeonStateMachine] OnTransition de republicacao falhou: " .. tostring(errorMessage))
		end
	end
	return true
end

function DungeonStateMachine:Connect(callback)
	assert(type(callback) == "function", "Connect requer callback")
	return self._changedEvent.Event:Connect(callback)
end

function DungeonStateMachine:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._changedEvent:Destroy()
	self._history = {}
end

return DungeonStateMachine
