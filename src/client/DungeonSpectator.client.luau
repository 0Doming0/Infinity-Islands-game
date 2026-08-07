-- HUD-06 — espectador navegável
-- Mantém o comportamento anterior e adiciona próximo/anterior para HUD-06.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local shared = ReplicatedStorage:WaitForChild("Shared")
local lifeEvent = shared:WaitForChild("Remotes")
	:WaitForChild("Dungeon")
	:WaitForChild("LifeState")

local CONTROL_NAME = "DungeonSpectatorNavigate"
local spectating = false
local currentTargetUserId
local lastTargetSearchAt = 0
local TARGET_SEARCH_INTERVAL = 0.35

local control = playerGui:FindFirstChild("DungeonSpectatorControl")
if control and not control:IsA("BindableEvent") then
	control:Destroy()
	control = nil
end
if not control then
	control = Instance.new("BindableEvent")
	control.Name = "DungeonSpectatorControl"
	control.Parent = playerGui
end

local function livingTarget(player)
	if not player
		or player == localPlayer
		or player:GetAttribute("DungeonLifeState") ~= "Active"
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function candidates()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if livingTarget(player) then
			table.insert(result, player)
		end
	end
	table.sort(result, function(left, right)
		return left.UserId < right.UserId
	end)
	return result
end

local function publishTarget()
	localPlayer:SetAttribute("DungeonSpectatorTargetUserId", currentTargetUserId)
end

local function chooseRelative(direction)
	local list = candidates()
	if #list == 0 then
		currentTargetUserId = nil
		publishTarget()
		return nil
	end

	local currentIndex = 0
	for index, player in ipairs(list) do
		if player.UserId == currentTargetUserId then
			currentIndex = index
			break
		end
	end

	local targetIndex
	if currentIndex == 0 then
		targetIndex = 1
	elseif direction < 0 then
		targetIndex = ((currentIndex - 2) % #list) + 1
	else
		targetIndex = (currentIndex % #list) + 1
	end

	local target = list[targetIndex]
	currentTargetUserId = target.UserId
	publishTarget()
	return livingTarget(target)
end

local function chooseCurrentOrFirst()
	local current = currentTargetUserId and Players:GetPlayerByUserId(currentTargetUserId)
	local subject = livingTarget(current)
	if subject then
		publishTarget()
		return subject
	end
	return chooseRelative(1)
end

local function applySubject(subject)
	if subject then
		camera = workspace.CurrentCamera or camera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = subject
		end
	end
end

local function navigate(direction)
	if not spectating then return end
	applySubject(chooseRelative(direction))
end

control.Event:Connect(function(action)
	if action == "Previous" then
		navigate(-1)
	elseif action == "Next" then
		navigate(1)
	end
end)

local function spectatorAction(_, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if inputObject.KeyCode == Enum.KeyCode.ButtonL1
		or inputObject.KeyCode == Enum.KeyCode.LeftBracket
		or inputObject.KeyCode == Enum.KeyCode.DPadLeft
	then
		navigate(-1)
	else
		navigate(1)
	end
	return Enum.ContextActionResult.Sink
end

local function bindControls()
	ContextActionService:BindAction(
		CONTROL_NAME,
		spectatorAction,
		false,
		Enum.KeyCode.LeftBracket,
		Enum.KeyCode.RightBracket,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight
	)
end

local function unbindControls()
	ContextActionService:UnbindAction(CONTROL_NAME)
end

local function restoreLocalCamera()
	spectating = false
	currentTargetUserId = nil
	publishTarget()
	unbindControls()
	camera = workspace.CurrentCamera or camera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then camera.CameraSubject = humanoid end
	end
end

local function startSpectating()
	spectating = true
	bindControls()
	applySubject(chooseCurrentOrFirst())
end

local function synchronize()
	local state = localPlayer:GetAttribute("DungeonLifeState")
	local shouldSpectate = state == "Eliminated"
		or localPlayer:GetAttribute("DungeonSpectating") == true
	if shouldSpectate and not spectating then
		startSpectating()
	elseif not shouldSpectate and spectating then
		restoreLocalCamera()
	elseif shouldSpectate then
		applySubject(chooseCurrentOrFirst())
	end
end

lifeEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.Action == "ParticipantStateChanged"
		or payload.Action == "ReturnedAtRewardIsland"
		or payload.Action == "LifeSnapshot"
	then
		synchronize()
	end
end)

localPlayer:GetAttributeChangedSignal("DungeonLifeState"):Connect(synchronize)
localPlayer:GetAttributeChangedSignal("DungeonSpectating"):Connect(synchronize)
localPlayer.CharacterAdded:Connect(function(character)
	if spectating then return end
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then
		camera = workspace.CurrentCamera or camera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
	synchronize()
end)

RunService.RenderStepped:Connect(function()
	if not spectating then return end
	local currentPlayer = currentTargetUserId and Players:GetPlayerByUserId(currentTargetUserId)
	local subject = livingTarget(currentPlayer)
	if subject then
		camera = workspace.CurrentCamera or camera
		if camera and camera.CameraSubject ~= subject then
			camera.CameraSubject = subject
		end
		return
	end
	if os.clock() - lastTargetSearchAt >= TARGET_SEARCH_INTERVAL then
		lastTargetSearchAt = os.clock()
		applySubject(chooseRelative(1))
	end
end)

localPlayer:SetAttribute("DungeonSpectatorNavigationReady", true)
workspace:SetAttribute("DungeonSpectatorNavigationPolicy", "ManualCycleActiveParticipantsV1")
synchronize()
