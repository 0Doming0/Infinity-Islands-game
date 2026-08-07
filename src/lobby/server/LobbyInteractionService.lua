local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local RouletteConfig = require(ReplicatedStorage.Shared.Configs.RouletteConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local PhaseSelectionService = require(script.Parent.PhaseSelectionService)
local LobbyRouletteService = require(script.Parent.LobbyRouletteService)
local LobbyEquipmentService = require(script.Parent.LobbyEquipmentService)

local LobbyInteractionService = {}
local notifications
local connections = setmetatable({}, { __mode = "k" })
local started = false

local function interactionPart(instance)
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function ensurePrompt(instance, actionText, objectText)
	local part = interactionPart(instance)
	if not part then
		warn("[Lobby] Objeto de interação sem BasePart: " .. instance:GetFullName())
		return nil
	end

	local prompt = part:FindFirstChild("LobbyInteractionPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LobbyInteractionPrompt"
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Parent = part
	end
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	return prompt
end

local function disconnect(instance)
	local connection = connections[instance]
	if connection then
		connection:Disconnect()
		connections[instance] = nil
	end
end

local function bindUniversePortal(instance)
	if connections[instance] then return end
	local universeId = instance:GetAttribute("UniverseId")
	local universe = PhaseConfig.GetUniverse(universeId)
	if not universe then
		warn("[Lobby] UniversePortal com UniverseId inválido: " .. instance:GetFullName())
		return
	end
	local prompt = ensurePrompt(instance, "Explorar", universe.DisplayName)
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			PhaseSelectionService.OpenUniverse(player, universeId)
		end)
	end
end

-- Compatibilidade: portais antigos de fase agora abrem o universo inteiro,
-- deixando o nível correspondente pré-selecionado.
local function bindPhasePortal(instance)
	if connections[instance] then return end
	local phaseId = instance:GetAttribute("PhaseId")
	local phase = PhaseConfig.Get(phaseId)
	if not phase then
		warn("[Lobby] PhasePortal com PhaseId inválido: " .. instance:GetFullName())
		return
	end
	local prompt = ensurePrompt(instance, "Explorar universo", phase.UniverseDisplayName)
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			PhaseSelectionService.OpenUniverse(player, phase.UniverseId, phaseId)
		end)
	end
end

local function bindRoulette(instance)
	if connections[instance] then return end
	local wheelId = instance:GetAttribute("WheelId")
	local wheel = RouletteConfig[wheelId]
	if not wheel then
		warn("[Lobby] RouletteStation com WheelId inválido: " .. instance:GetFullName())
		return
	end
	local prompt = ensurePrompt(instance, "Girar", wheel.DisplayName)
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			LobbyRouletteService.Open(player, wheelId)
		end)
	end
end

local function bindEquipment(instance)
	if connections[instance] then return end
	local prompt = ensurePrompt(instance, "Equipar", "Equipamentos")
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			LobbyEquipmentService.Open(player)
		end)
	end
end

local function normalizedName(instance)
	return string.lower(string.gsub(instance.Name, "[%s_%-]", ""))
end

local function inferPhaseId(instance)
	local existing = instance:GetAttribute("PhaseId")
	if type(existing) == "string" and existing ~= "" then
		return existing
	end
	local name = normalizedName(instance)
	if string.find(name, "phase01", 1, true)
		or string.find(name, "phase1", 1, true)
		or string.find(name, "fase01", 1, true)
		or string.find(name, "fase1", 1, true)
	then
		return "Phase01"
	elseif string.find(name, "phase02", 1, true)
		or string.find(name, "phase2", 1, true)
		or string.find(name, "fase02", 1, true)
		or string.find(name, "fase2", 1, true)
	then
		return "Phase02"
	end
	return nil
end

local function classifyExistingMapObject(instance)
	if not (instance:IsA("BasePart") or instance:IsA("Model")) then return end
	local name = normalizedName(instance)

	local universeId = instance:GetAttribute("UniverseId")
	if type(universeId) == "string" and PhaseConfig.GetUniverse(universeId) then
		if not CollectionService:HasTag(instance, "UniversePortal") then
			CollectionService:AddTag(instance, "UniversePortal")
		end
		return
	end

	local phaseId = inferPhaseId(instance)
	if phaseId and PhaseConfig.IsValid(phaseId) then
		instance:SetAttribute("PhaseId", phaseId)
		if not CollectionService:HasTag(instance, "PhasePortal") then
			CollectionService:AddTag(instance, "PhasePortal")
		end
		return
	end

	local wheelId = instance:GetAttribute("WheelId")
	local rouletteName = string.find(name, "roulette", 1, true)
		or string.find(name, "roleta", 1, true)
		or string.find(name, "luckywheel", 1, true)
	if RouletteConfig[wheelId] or rouletteName then
		if not RouletteConfig[wheelId] then instance:SetAttribute("WheelId", "BasicWheel") end
		if not CollectionService:HasTag(instance, "RouletteStation") then
			CollectionService:AddTag(instance, "RouletteStation")
		end
		return
	end

	local equipmentName = string.find(name, "equipment", 1, true)
		or string.find(name, "equipamento", 1, true)
		or string.find(name, "loadout", 1, true)
		or string.find(name, "arsenal", 1, true)
	if equipmentName and not CollectionService:HasTag(instance, "EquipmentStation") then
		CollectionService:AddTag(instance, "EquipmentStation")
		return
	end

	if instance:IsA("SpawnLocation") or name == "lobbyspawn" or name == "spawnlobby" then
		if not CollectionService:HasTag(instance, "LobbySpawn") then
			CollectionService:AddTag(instance, "LobbySpawn")
		end
	end
end

local function createFallbackPart(parent, name, position, color, labelText)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(12, 1, 12)
	part.Position = position
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.Neon
	part:SetAttribute("LobbyFallback", true)
	part.Parent = parent

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.AlwaysOnTop = true
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = surface
	return part
end

local function ensureFallbackStations()
	local hasWorldEntry = #CollectionService:GetTagged("UniversePortal") > 0
		or #CollectionService:GetTagged("PhasePortal") > 0
	local needUniverse = not hasWorldEntry
	local needRoulette = #CollectionService:GetTagged("RouletteStation") == 0
	local needEquipment = #CollectionService:GetTagged("EquipmentStation") == 0
	local needSpawn = #CollectionService:GetTagged("LobbySpawn") == 0
		and not workspace:FindFirstChildWhichIsA("SpawnLocation", true)

	if not (needUniverse or needRoulette or needEquipment or needSpawn) then
		workspace:SetAttribute("LobbyUsingFallbackStations", false)
		return
	end

	local folder = workspace:FindFirstChild("LobbyRuntimeFallbacks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LobbyRuntimeFallbacks"
		folder.Parent = workspace
	end

	if needSpawn then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Size = Vector3.new(10, 1, 10)
		spawn.Position = Vector3.new(0, 1, 0)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Transparency = 0.35
		spawn:SetAttribute("LobbyFallback", true)
		spawn.Parent = folder
		CollectionService:AddTag(spawn, "LobbySpawn")
	end

	if needUniverse then
		for index, universe in ipairs(PhaseConfig.GetUniversesSorted()) do
			local offset = (index - 1) * 20
			local portal = createFallbackPart(
				folder,
				universe.UniverseId .. "Portal",
				Vector3.new(-10 + offset, 1, 0),
				index % 2 == 0 and Color3.fromRGB(163, 98, 255) or Color3.fromRGB(73, 179, 255),
				string.upper(universe.DisplayName)
			)
			portal:SetAttribute("UniverseId", universe.UniverseId)
			CollectionService:AddTag(portal, "UniversePortal")
		end
	end

	if needRoulette then
		local roulette = createFallbackPart(
			folder, "RouletteStation", Vector3.new(0, 1, 18),
			Color3.fromRGB(255, 176, 55), "ROLETA"
		)
		roulette:SetAttribute("WheelId", "BasicWheel")
		CollectionService:AddTag(roulette, "RouletteStation")
	end

	if needEquipment then
		local equipment = createFallbackPart(
			folder, "EquipmentStation", Vector3.new(0, 1, -18),
			Color3.fromRGB(75, 220, 145), "EQUIPAMENTOS"
		)
		CollectionService:AddTag(equipment, "EquipmentStation")
	end

	workspace:SetAttribute("LobbyUsingFallbackStations", true)
end

local function lobbySpawn()
	for _, tagged in ipairs(CollectionService:GetTagged("LobbySpawn")) do
		local part = interactionPart(tagged)
		if part then return part end
	end
	return workspace:FindFirstChildWhichIsA("SpawnLocation", true)
end

local function positionCharacter(character)
	local spawnPart = lobbySpawn()
	if spawnPart then
		character:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
	end
end

local function bindTagged(tag, callback)
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do callback(instance) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(disconnect)
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(positionCharacter, character)
	end)
	if player.Character then task.defer(positionCharacter, player.Character) end

	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if type(teleportData) == "table" and (teleportData.ReturnReason or teleportData.DungeonResult) then
		task.delay(1, function()
			if player.Parent == Players then
				notifications:FireClient(player, {
					Action = "ReturnToLobby",
					ReturnReason = teleportData.ReturnReason or teleportData.DungeonResult,
					PhaseId = teleportData.PhaseId,
				})
			end
		end)
	end
end

function LobbyInteractionService.Start()
	if started then return true end
	started = true

	notifications = RemoteRegistry.Get("Notifications", "Lobby", "RemoteEvent")

	bindTagged("UniversePortal", bindUniversePortal)
	bindTagged("PhasePortal", bindPhasePortal)
	bindTagged("RouletteStation", bindRoulette)
	bindTagged("EquipmentStation", bindEquipment)

	for _, instance in ipairs(workspace:GetDescendants()) do
		classifyExistingMapObject(instance)
	end
	ensureFallbackStations()

	workspace.DescendantAdded:Connect(function(instance)
		task.defer(classifyExistingMapObject, instance)
	end)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end

	workspace:SetAttribute("LobbyUniversePortalCount", #CollectionService:GetTagged("UniversePortal"))
	workspace:SetAttribute("LobbyLegacyPhasePortalCount", #CollectionService:GetTagged("PhasePortal"))
	workspace:SetAttribute("LobbyRouletteStationCount", #CollectionService:GetTagged("RouletteStation"))
	workspace:SetAttribute("LobbyEquipmentStationCount", #CollectionService:GetTagged("EquipmentStation"))
	workspace:SetAttribute("LobbySpawnCount", #CollectionService:GetTagged("LobbySpawn"))
	workspace:SetAttribute("LobbyInteractionPolicy", "UniverseHubWorldStationsV1")
	return true
end

return LobbyInteractionService
