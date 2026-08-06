-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

--[[
	SkyDungeon V9 - IA leve para NPCs em geral

	Reconhece NPCs de vilas, santuarios e outras areas seguras. Cada NPC
	patrulha somente perto do proprio ponto de origem e descansa entre destinos.
	Comerciantes param e olham para o jogador somente depois que ele ativa o
	prompt da loja e enquanto a loja permanece aberta. Inimigos, mimicos, baus
	e personagens dos jogadores sao ignorados.

	Formas recomendadas de identificar novos NPCs:
	- atributo IsNPC = true; ou
	- atributo IsVillager = true; ou
	- tag NPC, VillagerNPC ou SanctuaryNPC; ou
	- atributo AIEnabled = true para inclusao explicita.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local SHOP_TAG = MVPConfig.Village.ShopTag
local NPC_TAGS = {
	SHOP_TAG,
	"NPC",
	"VillagerNPC",
	"SanctuaryNPC",
}
local NPC_NAME_MARKERS = {
	"npc",
	"villager",
	"aldeao",
	"merchant",
	"comerciante",
	"blacksmith",
	"ferreiro",
	"guardian",
	"guardiao",
}
local SHOP_PROMPT_NAMES = {
	VillageShopPrompt = true,
	SwordShopPrompt = true,
}
local DEFAULT_VILLAGE_WANDER_RADIUS = 5.5
local DEFAULT_SANCTUARY_WANDER_RADIUS = 4.5
local DEFAULT_GENERAL_WANDER_RADIUS = 3.2
local DEFAULT_SOLO_WANDER_RADIUS = 1.8
local DEFAULT_MOVE_SPEED = 2.4
local DEFAULT_INTERACTION_DISTANCE = MVPConfig.Village.PromptDistance + 4
local MINIMUM_IDLE_SECONDS = 1.4
local MAXIMUM_IDLE_SECONDS = 3.8
local THINK_INTERVAL = 0.2
local ROTATION_SPEED = 7
local DESTINATION_ATTEMPTS = 10
local EDGE_MARGIN = 2
local ARRIVAL_DISTANCE = 0.12
local INTERACTION_GRACE_SECONDS = 0.75

local random = Random.new()
local npcs = setmetatable({}, { __mode = "k" })
local boundShopPrompts = setmetatable({}, { __mode = "k" })
local interactingNPCByPlayer = setmetatable({}, { __mode = "k" })

local function getRoot(model)
	local root = model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function findNavigationZone(model)
	local current = model.Parent
	local zoneType
	while current and current ~= workspace do
		if current:GetAttribute("ProceduralVillage") == true then
			return current, "Village"
		end
		if current:GetAttribute("ProceduralSoloMerchant") == true then
			zoneType = zoneType or "Solo"
		elseif
			current:GetAttribute("IsSanctuary") == true
			or current:GetAttribute("IsSocialSanctuary") == true
			or (current:IsA("Model") and CollectionService:HasTag(current, "SkyDungeonSanctuary"))
		then
			zoneType = zoneType or "Sanctuary"
		end
		if current:IsA("Model") and current:FindFirstChild("IslandFloor") then
			return current, zoneType or "General"
		end
		current = current.Parent
	end
	return nil, zoneType or "General"
end

local function findIslandAndFloor(model)
	local current = model.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			local floor = current:FindFirstChild("IslandFloor")
			if floor and floor:IsA("BasePart") then
				return current, floor
			end
		end
		current = current.Parent
	end
	return nil, nil
end

local function isPlayerCharacter(model)
	return Players:GetPlayerFromCharacter(model) ~= nil
end

local function isHostileOrNonNPC(model)
	if isPlayerCharacter(model) then
		return true
	end
	local current = model
	while current and current ~= workspace do
		if
			(current:IsA("Model") and isPlayerCharacter(current))
			or CollectionService:HasTag(current, "CombatTarget")
			or current:GetAttribute("RuntimeMonster") == true
			or current:GetAttribute("IsMonster") == true
			or current:GetAttribute("IsEnemy") == true
			or current:GetAttribute("IsMimic") == true
			or current:GetAttribute("IsTreasureChest") == true
			or current:GetAttribute("IsDormantMimicChest") == true
		then
			return true
		end
		current = current.Parent
	end
	return false
end

local function hasExplicitNPCMarker(model)
	if
		model:GetAttribute("AIEnabled") == true
		or model:GetAttribute("IsNPC") == true
		or model:GetAttribute("IsVillager") == true
		or model:GetAttribute("ShopId") ~= nil
		or model:GetAttribute("MerchantDisplayName") ~= nil
	then
		return true
	end
	for _, tag in ipairs(NPC_TAGS) do
		if CollectionService:HasTag(model, tag) then
			return true
		end
	end
	local lowerName = string.lower(model.Name)
	for _, marker in ipairs(NPC_NAME_MARKERS) do
		if string.find(lowerName, marker, 1, true) and model:FindFirstChildOfClass("Humanoid") then
			return true
		end
	end
	return false
end

local function hasDirectHumanoid(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0
end

local function isEligibleNPC(model)
	if
		not model:IsA("Model")
		or model:GetAttribute("AIEnabled") == false
		or isHostileOrNonNPC(model)
		or not getRoot(model)
	then
		return false
	end

	if hasExplicitNPCMarker(model) then
		return true
	end

	-- Rigs neutros colocados em vilas ou santuarios tambem sao aceitos.
	-- Exigir Humanoid direto evita registrar a ilha ou um container inteiro.
	local _, zoneType = findNavigationZone(model)
	return (zoneType == "Village" or zoneType == "Sanctuary") and hasDirectHumanoid(model)
end

local function hasControlledAncestor(model)
	local current = model.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and npcs[current] then
			return true
		end
		current = current.Parent
	end
	return false
end

local function prepareNPC(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
end

local function raycastGround(model, requestedPosition, expectedGroundY, island)
	local raycastParams = RaycastParams.new()
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	if island and island.Parent then
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = { island }
	else
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { model }
	end
	local originY = math.max(requestedPosition.Y, expectedGroundY) + 10
	local origin = Vector3.new(requestedPosition.X, originY, requestedPosition.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -24, 0), raycastParams)
	if not result or result.Normal.Y < 0.7 or math.abs(result.Position.Y - expectedGroundY) > 2 then
		return nil
	end
	return result
end

local function getLivingPlayerRoot(player)
	if not player or player.Parent ~= Players then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function facingCFrame(position, targetPosition)
	local flatDirection = Vector3.new(targetPosition.X - position.X, 0, targetPosition.Z - position.Z)
	if flatDirection.Magnitude < 0.05 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flatDirection.Unit)
end

local function randomIdleDuration()
	return random:NextNumber(MINIMUM_IDLE_SECONDS, MAXIMUM_IDLE_SECONDS)
end

local function setIdle(state, now, duration)
	local pivot = state.Model:GetPivot()
	state.TargetPivot = pivot
	state.NextDecisionAt = now + (duration or randomIdleDuration())
	state.Model:SetAttribute("AIState", "Idle")
end

local function clearShopInteraction(state, now)
	local player = state.ActiveShopPlayer
	if player and interactingNPCByPlayer[player] == state then
		interactingNPCByPlayer[player] = nil
	end
	state.ActiveShopPlayer = nil
	state.InteractionGraceUntil = 0
	if state.Model.Parent then
		setIdle(state, now or os.clock(), random:NextNumber(0.5, 1.2))
	end
end

local function beginShopInteraction(state, player)
	local playerRoot = getLivingPlayerRoot(player)
	if not playerRoot or not state.Model.Parent then
		return
	end

	local previousState = interactingNPCByPlayer[player]
	if previousState and previousState ~= state then
		clearShopInteraction(previousState, os.clock())
	end

	local currentPivot = state.Model:GetPivot()
	state.ActiveShopPlayer = player
	state.InteractionGraceUntil = os.clock() + INTERACTION_GRACE_SECONDS
	state.TargetPivot = facingCFrame(currentPivot.Position, playerRoot.Position)
	state.NextDecisionAt = math.huge
	state.Model:SetAttribute("AIState", "Interacting")
	interactingNPCByPlayer[player] = state
end

local function isShopPrompt(state, prompt)
	if not prompt:IsA("ProximityPrompt") or not prompt:IsDescendantOf(state.Model) then
		return false
	end
	return SHOP_PROMPT_NAMES[prompt.Name] == true or state.Model:GetAttribute("ShopId") ~= nil
end

local function bindShopPrompt(state, prompt)
	if boundShopPrompts[prompt] or not isShopPrompt(state, prompt) then
		return
	end
	boundShopPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		if npcs[state.Model] == state then
			beginShopInteraction(state, player)
		end
	end)
end

local function isInsideFloor(state, worldPosition)
	local floor = state.GroundPart
	if not floor or not floor.Parent then
		return false
	end
	local localPosition = floor.CFrame:PointToObjectSpace(worldPosition)
	return math.abs(localPosition.X) <= math.max(0, floor.Size.X / 2 - EDGE_MARGIN)
		and math.abs(localPosition.Z) <= math.max(0, floor.Size.Z / 2 - EDGE_MARGIN)
end

local function resolveGroundPosition(state, requestedPosition)
	local floor = state.GroundPart
	if floor and floor.Parent and isInsideFloor(state, requestedPosition) then
		local localPosition = floor.CFrame:PointToObjectSpace(requestedPosition)
		local surface = floor.CFrame:PointToWorldSpace(Vector3.new(localPosition.X, floor.Size.Y / 2, localPosition.Z))
		return surface + Vector3.new(0, state.PivotGroundOffset, 0)
	end

	local result = raycastGround(state.Model, requestedPosition, state.HomeGroundY, state.Island)
	if not result then
		return nil
	end
	return result.Position + Vector3.new(0, state.PivotGroundOffset, 0)
end

local function isDestinationClear(state, destination)
	local groundY = destination.Y - state.PivotGroundOffset
	local targetBox = CFrame.new(destination) * state.BoxRelativeToPivot
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { state.Model }
	overlapParams.MaxParts = 24

	local checkSize = Vector3.new(
		math.max(0.8, state.BoxSize.X * 0.72),
		math.max(1, state.BoxSize.Y * 0.88),
		math.max(0.8, state.BoxSize.Z * 0.72)
	)
	for _, part in ipairs(workspace:GetPartBoundsInBox(targetBox, checkSize, overlapParams)) do
		if part.CanCollide and part ~= state.GroundPart then
			local partTop = part.Position.Y + part.Size.Y / 2
			if partTop > groundY + 0.6 then
				return false
			end
		end
	end
	return true
end

local function isRouteClear(state, currentPosition, destination)
	local delta = destination - currentPosition
	local flatDelta = Vector3.new(delta.X, 0, delta.Z)
	if flatDelta.Magnitude < ARRIVAL_DISTANCE then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { state.Model }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	local currentGroundY = currentPosition.Y - state.PivotGroundOffset
	local origin = Vector3.new(currentPosition.X, currentGroundY + state.RouteCheckHeight, currentPosition.Z)
	local direction = Vector3.new(flatDelta.X, 0, flatDelta.Z)
	local result = workspace:Raycast(origin, direction, raycastParams)
	return result == nil
end

local function chooseWanderGoal(state, now)
	local currentPosition = state.Model:GetPivot().Position
	for _ = 1, DESTINATION_ATTEMPTS do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(math.min(1.2, state.WanderRadius), state.WanderRadius)
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local destination = resolveGroundPosition(state, state.HomePivot.Position + offset)
		if
			destination
			and isDestinationClear(state, destination)
			and isRouteClear(state, currentPosition, destination)
		then
			state.TargetPivot = facingCFrame(destination, destination + offset)
			state.NextDecisionAt = math.huge
			state.Model:SetAttribute("AIState", "Wandering")
			return true
		end
	end

	local home = resolveGroundPosition(state, state.HomePivot.Position)
	if
		home
		and (currentPosition - home).Magnitude > ARRIVAL_DISTANCE
		and isDestinationClear(state, home)
		and isRouteClear(state, currentPosition, home)
	then
		state.TargetPivot = facingCFrame(home, home)
		state.NextDecisionAt = math.huge
		state.Model:SetAttribute("AIState", "Returning")
		return true
	end

	setIdle(state, now, 1)
	return false
end

local function defaultRadiusForZone(zoneType)
	if zoneType == "Village" then
		return DEFAULT_VILLAGE_WANDER_RADIUS
	elseif zoneType == "Sanctuary" then
		return DEFAULT_SANCTUARY_WANDER_RADIUS
	elseif zoneType == "Solo" then
		return DEFAULT_SOLO_WANDER_RADIUS
	end
	return DEFAULT_GENERAL_WANDER_RADIUS
end

local function registerNPC(model)
	if npcs[model] or not isEligibleNPC(model) or hasControlledAncestor(model) then
		return
	end

	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local island, floor = findIslandAndFloor(model)
	local _, zoneType = findNavigationZone(model)
	local floorSurfaceY
	if floor then
		local localPivot = floor.CFrame:PointToObjectSpace(pivot.Position)
		floorSurfaceY = floor.CFrame:PointToWorldSpace(Vector3.new(localPivot.X, floor.Size.Y / 2, localPivot.Z)).Y
	else
		local expectedBottomY = boxCFrame.Position.Y - boxSize.Y / 2
		local ground = raycastGround(model, pivot.Position, expectedBottomY, nil)
		if not ground then
			warn("[NPCMovementAI] NPC sem piso seguro: " .. model:GetFullName())
			return
		end
		floorSurfaceY = ground.Position.Y
	end
	prepareNPC(model)
	local defaultRadius = defaultRadiusForZone(zoneType)
	local wanderRadius = math.clamp(tonumber(model:GetAttribute("WanderRadius")) or defaultRadius, 0, 10)
	local state = {
		Model = model,
		Island = island,
		GroundPart = floor,
		HomePivot = pivot,
		HomeGroundY = floorSurfaceY,
		PivotGroundOffset = pivot.Position.Y - floorSurfaceY,
		BoxRelativeToPivot = pivot:ToObjectSpace(boxCFrame),
		BoxSize = boxSize,
		RouteCheckHeight = math.clamp(boxSize.Y * 0.38, 1.2, 2.6),
		WanderRadius = wanderRadius,
		MoveSpeed = math.clamp(
			tonumber(model:GetAttribute("NPCMoveSpeed"))
				or tonumber(model:GetAttribute("VillagerMoveSpeed"))
				or DEFAULT_MOVE_SPEED,
			0.5,
			6
		),
		InteractionDistance = math.clamp(
			tonumber(model:GetAttribute("NPCInteractionDistance"))
				or tonumber(model:GetAttribute("NPCLookDistance"))
				or tonumber(model:GetAttribute("LookDistance"))
				or DEFAULT_INTERACTION_DISTANCE,
			3,
			30
		),
		ActiveShopPlayer = nil,
		InteractionGraceUntil = 0,
		TargetPivot = pivot,
		NextThinkAt = os.clock() + random:NextNumber(0, THINK_INTERVAL),
		NextDecisionAt = os.clock() + random:NextNumber(0.8, 2.5),
	}
	npcs[model] = state
	model:SetAttribute("AIState", "Idle")
	model:SetAttribute("AIWanderRadius", wanderRadius)
	model:SetAttribute("AIZoneType", zoneType)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			bindShopPrompt(state, descendant)
		end
	end
	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			task.defer(bindShopPrompt, state, descendant)
		end
	end)
	model.Destroying:Connect(function()
		if state.ActiveShopPlayer and interactingNPCByPlayer[state.ActiveShopPlayer] == state then
			interactingNPCByPlayer[state.ActiveShopPlayer] = nil
		end
		npcs[model] = nil
	end)
end

for _, tag in ipairs(NPC_TAGS) do
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		task.defer(registerNPC, model)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		task.defer(registerNPC, model)
	end)
end

-- A varredura cobre NPCs preexistentes dos santuarios que ainda nao usam tag.
for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Model") then
		task.defer(registerNPC, descendant)
	end
end

workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") then
		-- O pequeno atraso permite que atributos sejam aplicados logo apos Parent.
		task.delay(0.1, registerNPC, instance)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local safeDelta = math.min(dt, 0.1)
	for model, state in pairs(npcs) do
		if not model.Parent then
			npcs[model] = nil
			continue
		end
		if isHostileOrNonNPC(model) then
			npcs[model] = nil
			continue
		end

		local currentPivot = model:GetPivot()
		local interactionRoot
		local interactionPlayer = state.ActiveShopPlayer
		if interactionPlayer then
			local playerRoot = getLivingPlayerRoot(interactionPlayer)
			local shopIsOpen = interactionPlayer:GetAttribute("ShopOpen") == true or now <= state.InteractionGraceUntil
			local flatDistance = math.huge
			local verticalDistance = math.huge
			if playerRoot then
				local offset = playerRoot.Position - currentPivot.Position
				flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				verticalDistance = math.abs(offset.Y)
			end
			if playerRoot and shopIsOpen and flatDistance <= state.InteractionDistance and verticalDistance <= 12 then
				interactionRoot = playerRoot
				state.TargetPivot = facingCFrame(currentPivot.Position, playerRoot.Position)
				state.NextDecisionAt = math.huge
				model:SetAttribute("AIState", "Interacting")
			else
				clearShopInteraction(state, now)
			end
		end

		if not interactionRoot and now >= state.NextThinkAt then
			state.NextThinkAt = now + THINK_INTERVAL
			if now >= state.NextDecisionAt then
				chooseWanderGoal(state, now)
			end
		end

		local targetPivot = state.TargetPivot
		local delta = targetPivot.Position - currentPivot.Position
		local nextPosition = currentPivot.Position
		if delta.Magnitude > ARRIVAL_DISTANCE then
			local step = math.min(delta.Magnitude, state.MoveSpeed * safeDelta)
			nextPosition += delta.Unit * step
		elseif model:GetAttribute("AIState") == "Wandering" or model:GetAttribute("AIState") == "Returning" then
			setIdle(state, now)
			targetPivot = state.TargetPivot
		end

		local rotationAlpha = math.clamp(safeDelta * ROTATION_SPEED, 0, 1)
		local nextRotation = currentPivot.Rotation:Lerp(targetPivot.Rotation, rotationAlpha)
		if
			(nextPosition - currentPivot.Position).Magnitude > 0.001
			or currentPivot.LookVector:Dot(targetPivot.LookVector) < 0.9999
		then
			model:PivotTo(CFrame.new(nextPosition) * nextRotation)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local state = interactingNPCByPlayer[player]
	if state then
		clearShopInteraction(state, os.clock())
	end
end)

print("[NPCMovementAI] Patrulha geral V9 com interacao de loja iniciada.")
