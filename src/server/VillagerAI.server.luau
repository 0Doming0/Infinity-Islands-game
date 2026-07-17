--[[
	SkyDungeon - IA simples dos aldeoes

	Controla modelos ancorados por PivotTo, portanto funciona tanto com rigs
	com Humanoid quanto com os aldeoes de exemplo criados por codigo.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local SHOP_TAG = MVPConfig.Village.ShopTag
local DEFAULT_WANDER_RADIUS = 2.2
local DEFAULT_MOVE_SPEED = 1.7
local DEFAULT_LOOK_DISTANCE = 15
local THINK_INTERVAL = 0.25
local ROTATION_SPEED = 5

local random = Random.new()
local villagers = setmetatable({}, { __mode = "k" })

local function getRoot(model)
	local root = model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function prepareVillager(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
end

local function nearestPlayer(position, maximumDistance)
	local nearestRoot
	local nearestDistance = maximumDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			local distance = (root.Position - position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestRoot = root
			end
		end
	end
	return nearestRoot
end

local function facingCFrame(position, targetPosition)
	local flatDirection = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z)
	if flatDirection.Magnitude < 0.05 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flatDirection.Unit)
end

local function chooseWanderGoal(state, now)
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(random:NextNumber()) * state.WanderRadius
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local destination = state.HomePivot.Position + offset
	state.TargetPivot = facingCFrame(destination, destination + offset)
	state.NextDecisionAt = now
		+ (state.Model:GetPivot().Position - destination).Magnitude / state.MoveSpeed
		+ random:NextNumber(1.2, 3.2)
	state.Model:SetAttribute("AIState", "Wandering")
end

local function registerVillager(model)
	if not model:IsA("Model") or villagers[model] or model:GetAttribute("AIEnabled") == false then
		return
	end
	if not getRoot(model) then
		warn("[VillagerAI] Aldeao sem BasePart: " .. model:GetFullName())
		return
	end

	prepareVillager(model)
	local pivot = model:GetPivot()
	villagers[model] = {
		Model = model,
		HomePivot = pivot,
		TargetPivot = pivot,
		WanderRadius = math.clamp(tonumber(model:GetAttribute("WanderRadius")) or DEFAULT_WANDER_RADIUS, 0, 5),
		MoveSpeed = math.clamp(tonumber(model:GetAttribute("VillagerMoveSpeed")) or DEFAULT_MOVE_SPEED, 0.5, 5),
		LookDistance = math.clamp(tonumber(model:GetAttribute("LookDistance")) or DEFAULT_LOOK_DISTANCE, 3, 30),
		NextThinkAt = 0,
		NextDecisionAt = os.clock() + random:NextNumber(1, 3),
	}
	model:SetAttribute("AIState", "Idle")
	model.Destroying:Connect(function()
		villagers[model] = nil
	end)
end

for _, model in ipairs(CollectionService:GetTagged(SHOP_TAG)) do
	task.defer(registerVillager, model)
end
CollectionService:GetInstanceAddedSignal(SHOP_TAG):Connect(function(model)
	task.defer(registerVillager, model)
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for model, state in pairs(villagers) do
		if not model.Parent then
			villagers[model] = nil
			continue
		end

		local currentPivot = model:GetPivot()
		if now >= state.NextThinkAt then
			state.NextThinkAt = now + THINK_INTERVAL
			local playerRoot = nearestPlayer(currentPivot.Position, state.LookDistance)
			if playerRoot then
				state.TargetPivot = facingCFrame(currentPivot.Position, playerRoot.Position)
				state.NextDecisionAt = now + random:NextNumber(1, 2)
				model:SetAttribute("AIState", "Watching")
			elseif now >= state.NextDecisionAt then
				if random:NextNumber() < 0.35 then
					state.TargetPivot = currentPivot
					state.NextDecisionAt = now + random:NextNumber(1.5, 4)
					model:SetAttribute("AIState", "Idle")
				else
					chooseWanderGoal(state, now)
				end
			end
		end

		local targetPivot = state.TargetPivot
		local delta = targetPivot.Position - currentPivot.Position
		local nextPosition = targetPivot.Position
		if delta.Magnitude > 0.01 then
			local step = math.min(delta.Magnitude, state.MoveSpeed * dt)
			nextPosition = currentPivot.Position + delta.Unit * step
		end
		local rotationAlpha = math.clamp(dt * ROTATION_SPEED, 0, 1)
		local nextRotation = currentPivot.Rotation:Lerp(targetPivot.Rotation, rotationAlpha)
		model:PivotTo(CFrame.new(nextPosition) * nextRotation)
	end
end)

print("[VillagerAI] Movimento e observacao dos aldeoes iniciados.")
