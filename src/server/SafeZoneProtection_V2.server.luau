-- SafeZoneProtection V24 - contagem antes da inundacao do santuario.
-- Servico independente: nao exige GetSafeZoneContext do ChunkManager.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CONFIG = MVPConfig.SafeZones or {}

local VERSION = "V24_SANCTUARY_FLOOD_COUNTDOWN"
local FORCE_FIELD_NAME = "SafeZoneProtection"
local FLOOD_COUNTDOWN_ATTRIBUTE = "SanctuaryFloodCountdownEnd"
local FLOODED_ISLAND_ATTRIBUTE = "FloodedSafeZoneIslandKey"
local CHECK_INTERVAL = math.max(0.05, tonumber(CONFIG.CheckIntervalSeconds) or 0.10)
local HORIZONTAL_PADDING = math.max(0, tonumber(CONFIG.HorizontalPaddingStuds) or 0.75)
local VERTICAL_PADDING = math.max(4, tonumber(CONFIG.VerticalPaddingStuds) or 12)
local WATER_CONTACT_FOOT_OFFSET = math.max(0, tonumber(CONFIG.WaterContactFootOffsetStuds) or 0.5)
local SPAWN_SEARCH_SECONDS = 4

local playerStates = setmetatable({}, { __mode = "k" })

local function findZoneModels(instance)
	local islandModel
	local nodeModel
	local current = instance

	while current and current ~= workspace do
		if current:IsA("Model") then
			if not islandModel and current:GetAttribute("IsSkyIsland") == true then
				islandModel = current
			end

			if not nodeModel
				and (
					CollectionService:HasTag(current, "SkyDungeonIslandNode")
					or current:GetAttribute("GenerationUnit") == "IslandNode"
				)
			then
				nodeModel = current
			end
		end
		current = current.Parent
	end

	return islandModel, nodeModel
end

local function getFloor(islandModel, nodeModel)
	local floor = islandModel and islandModel:FindFirstChild("IslandFloor")
	if floor and floor:IsA("BasePart") then
		return floor
	end

	floor = nodeModel and nodeModel:FindFirstChild("IslandFloor", true)
	if floor and floor:IsA("BasePart") then
		return floor
	end

	return nil
end

local function pointInsideFloor(floor, position)
	if not floor then
		return false
	end

	local localPoint = floor.CFrame:PointToObjectSpace(position)
	local halfSize = floor.Size * 0.5

	return math.abs(localPoint.X) <= halfSize.X + HORIZONTAL_PADDING
		and math.abs(localPoint.Z) <= halfSize.Z + HORIZONTAL_PADDING
		and localPoint.Y >= halfSize.Y - VERTICAL_PADDING
		and localPoint.Y <= halfSize.Y + VERTICAL_PADDING + 6
end

local function makeContext(islandModel, nodeModel, position)
	if not islandModel and not nodeModel then
		return nil
	end

	local isSanctuary = (islandModel and islandModel:GetAttribute("IsSanctuary") == true)
		or (nodeModel and nodeModel:GetAttribute("IsSanctuary") == true)
		or (islandModel and islandModel:GetAttribute("IsSocialSanctuary") == true)
		or (nodeModel and nodeModel:GetAttribute("IsSocialSanctuary") == true)

	local isVillage = (islandModel and islandModel:GetAttribute("VillageSpawned") == true)
		or (nodeModel and nodeModel:GetAttribute("VillageSpawned") == true)

	if not isSanctuary and not isVillage then
		return nil
	end

	local floor = getFloor(islandModel, nodeModel)
	if not pointInsideFloor(floor, position) then
		return nil
	end

	local zoneModel = nodeModel or islandModel
	return {
		IslandKey = (nodeModel and nodeModel:GetAttribute("IslandNodeKey"))
			or (islandModel and islandModel:GetAttribute("IslandNodeKey"))
			or (islandModel and islandModel:GetAttribute("IslandKey"))
			or zoneModel.Name,
		ZoneType = isVillage and "Village" or "Sanctuary",
	}
end

local function contextFromInstance(instance, position)
	if not instance then
		return nil
	end

	local islandModel, nodeModel = findZoneModels(instance)
	return makeContext(islandModel, nodeModel, position)
end

local function findContextByCurrentIsland(player, position)
	local currentIslandKey = player:GetAttribute("CurrentIslandKey")
	if typeof(currentIslandKey) ~= "string" then
		return nil
	end

	for _, nodeModel in ipairs(CollectionService:GetTagged("SkyDungeonIslandNode")) do
		if nodeModel:GetAttribute("IslandNodeKey") == currentIslandKey then
			local islandModel
			for _, descendant in ipairs(nodeModel:GetDescendants()) do
				if descendant:IsA("Model") and descendant:GetAttribute("IsSkyIsland") == true then
					islandModel = descendant
					break
				end
			end
			return makeContext(islandModel, nodeModel, position)
		end
	end

	return nil
end

local function getSafeZoneContext(player, character, root)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true

	-- A busca vertical reconhece o piso e tambem casas/decoracoes que sejam
	-- descendentes da ilha segura.
	local raycastResult = workspace:Raycast(
		root.Position + Vector3.new(0, 4, 0),
		Vector3.new(0, -(VERTICAL_PADDING * 2 + 20), 0),
		raycastParams
	)
	local context = raycastResult and contextFromInstance(raycastResult.Instance, root.Position)
	if context then
		return context
	end

	-- Fallback para o momento do teleporte/respawn, quando o raycast pode ocorrer
	-- antes de todas as pecas estarem replicadas na hierarquia definitiva.
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local nearbyParts = workspace:GetPartBoundsInBox(
		root.CFrame,
		Vector3.new(6, VERTICAL_PADDING * 2 + 16, 6),
		overlapParams
	)
	for _, part in ipairs(nearbyParts) do
		context = contextFromInstance(part, root.Position)
		if context then
			return context
		end
	end

	return findContextByCurrentIsland(player, root.Position)
end

local function getOrCreateForceField(character)
	local forceField = character:FindFirstChild(FORCE_FIELD_NAME)
	if forceField and not forceField:IsA("ForceField") then
		forceField:Destroy()
		forceField = nil
	end

	if not forceField then
		forceField = Instance.new("ForceField")
		forceField.Name = FORCE_FIELD_NAME
		forceField.Parent = character
	end

	forceField.Visible = CONFIG.ShieldVisible ~= false
	forceField:SetAttribute("SafeZoneProtectionVersion", VERSION)
	return forceField
end

local function applyProtection(player, character, context)
	getOrCreateForceField(character)

	local previous = playerStates[player]
	if previous
		and previous.Character == character
		and previous.IslandKey == context.IslandKey
		and previous.ZoneType == context.ZoneType
	then
		return
	end

	character:SetAttribute("SafeZoneProtected", true)
	character:SetAttribute("SafeZoneType", context.ZoneType)
	character:SetAttribute("SafeZoneProtectionVersion", VERSION)
	player:SetAttribute("InSafeZone", true)
	player:SetAttribute("SafeZoneType", context.ZoneType)
	player:SetAttribute("SafeZoneIslandKey", context.IslandKey)

	playerStates[player] = {
		Character = character,
		IslandKey = context.IslandKey,
		ZoneType = context.ZoneType,
	}
end

local function removeProtection(player, character)
	local forceField = character and character:FindFirstChild(FORCE_FIELD_NAME)
	if forceField then
		forceField:Destroy()
	end

	if character then
		character:SetAttribute("SafeZoneProtected", false)
		character:SetAttribute("SafeZoneType", nil)
	end

	player:SetAttribute("InSafeZone", false)
	player:SetAttribute("SafeZoneType", nil)
	player:SetAttribute("SafeZoneIslandKey", nil)
	playerStates[player] = nil
end

local function updatePlayer(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not character or not humanoid or humanoid.Health <= 0 or not root then
		removeProtection(player, character)
		return
	end

	local water = workspace:FindFirstChild("Water")
	local waterSurfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	local feetY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 + WATER_CONTACT_FOOT_OFFSET
	local countdownEnd = tonumber(player:GetAttribute(FLOOD_COUNTDOWN_ATTRIBUTE))
	local countdownActive = countdownEnd ~= nil and workspace:GetServerTimeNow() < countdownEnd
	if countdownActive then
		-- O WaterRiseSystem iniciou a tolerancia. O ForceField deve continuar
		-- existindo ate o servidor concluir oficialmente a contagem.
		return
	end

	local context = getSafeZoneContext(player, character, root)
	local floodedIslandKey = player:GetAttribute(FLOODED_ISLAND_ATTRIBUTE)
	if context
		and context.ZoneType == "Sanctuary"
		and floodedIslandKey ~= nil
		and floodedIslandKey == context.IslandKey
	then
		removeProtection(player, character)
		return
	end

	if player:GetAttribute("WaterContacting") == true
		or (waterSurfaceY and feetY <= waterSurfaceY)
	then
		removeProtection(player, character)
		return
	end

	if context then
		applyProtection(player, character, context)
	else
		removeProtection(player, character)
	end
end

local function bindCharacter(player, character)
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end

		local deadline = os.clock() + SPAWN_SEARCH_SECONDS
		repeat
			if player.Character ~= character or not character.Parent then
				return
			end

			updatePlayer(player)
			if player:GetAttribute("InSafeZone") == true then
				return
			end
			task.wait(0.05)
		until os.clock() >= deadline
	end)
end

local function bindPlayer(player)
	player:SetAttribute("InSafeZone", false)
	player.CharacterAdded:Connect(function(character)
		player:SetAttribute(FLOOD_COUNTDOWN_ATTRIBUTE, nil)
		player:SetAttribute(FLOODED_ISLAND_ATTRIBUTE, nil)
		bindCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		removeProtection(player, character)
	end)

	if player.Character then
		player:SetAttribute(FLOOD_COUNTDOWN_ATTRIBUTE, nil)
		player:SetAttribute(FLOODED_ISLAND_ATTRIBUTE, nil)
		bindCharacter(player, player.Character)
	end
end

if CONFIG.Enabled ~= false then
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			updatePlayer(player)
		end
		task.wait(CHECK_INTERVAL)
	end
end
