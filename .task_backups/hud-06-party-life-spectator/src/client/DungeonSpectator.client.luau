local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local shared = ReplicatedStorage:WaitForChild("Shared")
local lifeEvent = shared:WaitForChild("Remotes")
	:WaitForChild("Dungeon")
	:WaitForChild("LifeState")

local spectating = false
local currentTargetUserId
local lastTargetSearchAt = 0
local TARGET_SEARCH_INTERVAL = 0.35

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

local function chooseTarget()
	local candidates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if livingTarget(player) then
			table.insert(candidates, player)
		end
	end
	table.sort(candidates, function(left, right)
		return left.UserId < right.UserId
	end)
	if #candidates == 0 then
		currentTargetUserId = nil
		return nil
	end
	local currentIndex = 0
	for index, player in ipairs(candidates) do
		if player.UserId == currentTargetUserId then
			currentIndex = index
			break
		end
	end
	local target = candidates[currentIndex > 0 and currentIndex or 1]
	currentTargetUserId = target.UserId
	return livingTarget(target)
end

local function restoreLocalCamera()
	spectating = false
	currentTargetUserId = nil
	camera.CameraType = Enum.CameraType.Custom
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function startSpectating()
	spectating = true
	camera.CameraType = Enum.CameraType.Custom
	local subject = chooseTarget()
	if subject then
		camera.CameraSubject = subject
	end
end

local function synchronize()
	local state = localPlayer:GetAttribute("DungeonLifeState")
	local shouldSpectate = state == "Eliminated"
		or localPlayer:GetAttribute("DungeonSpectating") == true
	if shouldSpectate and not spectating then
		startSpectating()
	elseif not shouldSpectate and spectating then
		restoreLocalCamera()
	end
end

lifeEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
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
	if spectating then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end)

RunService.RenderStepped:Connect(function()
	if not spectating then
		return
	end
	local currentPlayer = currentTargetUserId and Players:GetPlayerByUserId(currentTargetUserId)
	local subject = livingTarget(currentPlayer)
	if subject then
		if camera.CameraSubject ~= subject then
			camera.CameraSubject = subject
		end
		return
	end
	if os.clock() - lastTargetSearchAt >= TARGET_SEARCH_INTERVAL then
		lastTargetSearchAt = os.clock()
		subject = chooseTarget()
		if subject then
			camera.CameraSubject = subject
		end
	end
end)

synchronize()
