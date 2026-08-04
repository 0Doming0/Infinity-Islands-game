-- Autoridade server-side para zonas de santuario, protecao, submersao e
-- resgate sem respawn. A deteccao usa os bounds reais das ilhas do ChunkManager.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local ChunkManager = require(script.Parent.BlockParkour:WaitForChild("ChunkManager_SkyDungeon_V10"))
local GameplayAnalytics = require(script.Parent:WaitForChild("GameplayAnalyticsService"))

local CONFIG = MVPConfig.SafeZones or {}
local SanctuaryService = {}
local started = false
local rescueSerial = 0
local transitionRemote
local fallbackContext
local states = setmetatable({}, { __mode = "k" })

local SAFE_FORCE_FIELD = "SafeZoneProtection"
local RESCUE_FORCE_FIELD = "SanctuaryRescueProtection"

local function debugLog(message)
	if CONFIG.DebugLogs == true then
		print("[SanctuaryService] " .. message)
	end
end

local function ensureRemote()
	local remote = ReplicatedStorage:FindFirstChild("SanctuaryRescueEvent")
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "SanctuaryRescueEvent"
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local function getWaterY()
	local water = workspace:FindFirstChild("Water")
	return water and tonumber(water:GetAttribute("SurfaceY"))
		or tonumber(MVPConfig.Water and MVPConfig.Water.StartSurfaceY)
		or -15
end

local function forceField(character, name, visible)
	local field = character and character:FindFirstChild(name)
	if field and not field:IsA("ForceField") then
		field:Destroy()
		field = nil
	end
	if not field and character then
		field = Instance.new("ForceField")
		field.Name = name
		field.Parent = character
	end
	if field then
		field.Visible = visible == true
	end
	return field
end

local function destroyForceField(character, name)
	local field = character and character:FindFirstChild(name)
	if field then
		field:Destroy()
	end
end

local function contextIsAlive(context)
	return context
		and context.Floor
		and context.Floor.Parent
		and context.Model
		and context.Model.Parent
end

local function contextIsSafe(context, waterY, clearance)
	return contextIsAlive(context)
		and context.IsSubmerged ~= true
		and context.Model:GetAttribute("SanctuarySubmerged") ~= true
		and context.SurfaceY >= waterY + math.max(0, tonumber(clearance) or 0)
end

local function pointInsideFloor(context, position, verticalPadding)
	if not context or not context.Floor or not context.Floor.Parent then
		return false
	end
	local localPoint = context.Floor.CFrame:PointToObjectSpace(position)
	local half = context.Floor.Size * 0.5
	return math.abs(localPoint.X) <= half.X + (tonumber(CONFIG.HorizontalPaddingStuds) or 0.75)
		and math.abs(localPoint.Z) <= half.Z + (tonumber(CONFIG.HorizontalPaddingStuds) or 0.75)
		and localPoint.Y >= half.Y - (verticalPadding or tonumber(CONFIG.VerticalPaddingStuds) or 12)
		and localPoint.Y <= half.Y + (verticalPadding or tonumber(CONFIG.VerticalPaddingStuds) or 12) + 6
end

local function fallbackAt(position)
	if fallbackContext and pointInsideFloor(fallbackContext, position, 18) then
		fallbackContext.SurfaceY = fallbackContext.Floor.Position.Y + fallbackContext.Floor.Size.Y / 2
		fallbackContext.CFrame = CFrame.new(
			fallbackContext.Floor.Position
				+ Vector3.new(0, fallbackContext.Floor.Size.Y / 2 + 3, 0)
		)
		return fallbackContext
	end
	return nil
end

local function contextAtPosition(position)
	local context = ChunkManager.GetSafeZoneContext(
		position,
		tonumber(CONFIG.HorizontalPaddingStuds) or 0.75,
		tonumber(CONFIG.VerticalPaddingStuds) or 12
	)
	return context or fallbackAt(position)
end

local function setPlayerProtectionAttributes(player, character, context)
	local zoneType = context.IsVillage and "Village" or "Sanctuary"
	player:SetAttribute("InSafeZone", true)
	player:SetAttribute("SafeZoneType", zoneType)
	player:SetAttribute("SafeZoneIslandKey", context.IslandKey)
	player:SetAttribute("SanctuaryProtected", context.IsSanctuary ~= false)
	character:SetAttribute("SafeZoneProtected", true)
	character:SetAttribute("SafeZoneType", zoneType)
	character:SetAttribute("SanctuaryProtected", context.IsSanctuary ~= false)
	forceField(character, SAFE_FORCE_FIELD, CONFIG.ShieldVisible ~= false)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
end

local function clearPlayerProtectionAttributes(player, character)
	player:SetAttribute("InSafeZone", false)
	player:SetAttribute("SafeZoneType", nil)
	player:SetAttribute("SafeZoneIslandKey", nil)
	player:SetAttribute("SanctuaryProtected", false)
	if character then
		character:SetAttribute("SafeZoneProtected", false)
		character:SetAttribute("SafeZoneType", nil)
		character:SetAttribute("SanctuaryProtected", false)
	end
	destroyForceField(character, SAFE_FORCE_FIELD)
end

local function setContext(player, state, context, isRescue)
	local previous = state.Context
	if previous and context and previous.IslandKey == context.IslandKey then
		state.Context = context
		return false
	end
	if previous and previous.IsSanctuary ~= false and not state.RescueInProgress then
		GameplayAnalytics.RecordSanctuaryExited(player, previous)
		debugLog(string.format("%s saiu do santuario %s", player.Name, previous.IslandKey))
	end
	state.Context = context
	state.EnteredAt = context and os.clock() or nil
	state.IdleSince = context and os.clock() or nil
	state.LastSafePosition = nil
	state.IdleSent = false
	if context then
		if context.IsSanctuary ~= false then
			player:SetAttribute("CurrentSanctuaryIndex", context.LogicalLevel or 0)
			GameplayAnalytics.RecordSanctuaryEntered(player, context, isRescue == true)
			debugLog(string.format("%s entrou no santuario %s", player.Name, context.IslandKey))
		end
	else
		local destinationKey = player:GetAttribute("SanctuaryRescueDestinationKey")
		if destinationKey and previous and destinationKey == previous.IslandKey then
			player:SetAttribute("SanctuaryRescueDestinationKey", nil)
		end
	end
	return true
end

local function createFallbackSanctuary(waterY, preferredPosition, logicalLevel)
	local clearance = math.clamp(
		tonumber(CONFIG.EmergencyWaterClearanceStuds) or 50,
		40,
		60
	)
	local folder = workspace:FindFirstChild("SanctuaryFallbacks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SanctuaryFallbacks"
		folder.Parent = workspace
	end
	local model = folder:FindFirstChild("GlobalEmergencySanctuary")
	local created = false
	if not model then
		created = true
		model = Instance.new("Model")
		model.Name = "GlobalEmergencySanctuary"
		model:SetAttribute("IsSanctuary", true)
		model:SetAttribute("IsEmergencySanctuary", true)
		model:SetAttribute("SanctuaryValid", true)
		CollectionService:AddTag(model, "SkyDungeonSanctuary")
		local floor = Instance.new("Part")
		floor.Name = "IslandFloor"
		floor.Size = Vector3.new(30, 2, 30)
		floor.Anchored = true
		floor.CanCollide = true
		floor.CanQuery = true
		floor.CanTouch = false
		floor.Material = Enum.Material.ForceField
		floor.Color = Color3.fromRGB(92, 190, 180)
		floor.Transparency = 0.18
		floor.Parent = model
		model.PrimaryPart = floor
		model.Parent = folder
	end
	local floor = model.PrimaryPart
	-- Depois de publicado, o fallback global so sobe. Nao o mova lateralmente
	-- sob jogadores resgatados por chamadas simultaneas.
	local x = created and preferredPosition and preferredPosition.X or floor.Position.X
	local z = created and preferredPosition and preferredPosition.Z or floor.Position.Z
	floor.Position = Vector3.new(x, waterY + clearance - floor.Size.Y / 2, z)
	local fallbackLevel = math.max(
		tonumber(model:GetAttribute("LogicalLevel")) or 0,
		logicalLevel or 0
	)
	model:SetAttribute("LogicalLevel", fallbackLevel)
	model:SetAttribute("EmergencyMinimumWaterY", waterY + clearance)
	fallbackContext = {
		IslandKey = "GlobalEmergencySanctuary",
		LogicalLevel = fallbackLevel,
		IsSanctuary = true,
		IsVillage = false,
		IsEmergency = true,
		IsSubmerged = false,
		SurfaceY = floor.Position.Y + floor.Size.Y / 2,
		CFrame = CFrame.new(floor.Position + Vector3.new(0, floor.Size.Y / 2 + 3, 0)),
		Floor = floor,
		Model = model,
		IslandModel = model,
	}
	return fallbackContext
end

local function ensureFallbackAboveWater(waterY)
	if not fallbackContext or not contextIsAlive(fallbackContext) then
		return
	end
	local clearance = math.clamp(
		tonumber(CONFIG.EmergencyWaterClearanceStuds) or 50,
		40,
		60
	)
	local requiredSurface = waterY + clearance
	local floor = fallbackContext.Floor
	local surface = floor.Position.Y + floor.Size.Y / 2
	if surface < requiredSurface then
		floor.Position += Vector3.new(0, requiredSurface - surface, 0)
	end
	fallbackContext.SurfaceY = floor.Position.Y + floor.Size.Y / 2
	fallbackContext.CFrame = CFrame.new(floor.Position + Vector3.new(0, floor.Size.Y / 2 + 3, 0))
end

local function synchronizeCompanions(player)
	local success, service = pcall(function()
		return require(script.Parent.MVPSystems:WaitForChild("CompanionService"))
	end)
	if success and service and type(service.SynchronizeAfterTeleport) == "function" then
		local synchronized, errorMessage = pcall(service.SynchronizeAfterTeleport, player)
		if not synchronized then
			warn("[SanctuaryService] Falha ao reposicionar companheiros: " .. tostring(errorMessage))
		end
	end
end

local function destinationStillValid(destination, waterY)
	if destination and destination.IslandKey == "GlobalEmergencySanctuary" then
		ensureFallbackAboveWater(waterY)
		return contextIsSafe(destination, waterY, 1)
	end
	local refreshed = destination and ChunkManager.GetSanctuaryByKey(destination.IslandKey, 3)
	if refreshed and contextIsSafe(
		refreshed,
		waterY,
		tonumber(CONFIG.ExistingSanctuaryClearanceStuds) or 4
	) then
		for key, value in pairs(refreshed) do
			destination[key] = value
		end
		return true
	end
	return false
end

local function chooseDestination(player, origin, waterY)
	local clearance = math.max(0, tonumber(CONFIG.ExistingSanctuaryClearanceStuds) or 4)
	local destination = ChunkManager.GetNextSafeSanctuary(
		origin and origin.IslandKey,
		waterY,
		clearance,
		3
	)
	if destination then
		return destination
	end
	local emergencyClearance = math.clamp(
		tonumber(CONFIG.EmergencyWaterClearanceStuds) or 50,
		40,
		60
	)
	local requested, reason = ChunkManager.RequestEmergencySanctuary(
		waterY,
		emergencyClearance,
		player.UserId
	)
	debugLog(string.format("geracao emergencial para %s: %s", player.Name, tostring(reason)))
	if requested then
		local deadline = os.clock() + math.max(1, tonumber(CONFIG.GenerationTimeoutSeconds) or 12)
		repeat
			if player.Parent ~= Players then
				return nil
			end
			task.wait(math.max(0.05, tonumber(CONFIG.GenerationPollSeconds) or 0.25))
			waterY = getWaterY()
			destination = ChunkManager.GetNextSafeSanctuary(
				origin and origin.IslandKey,
				waterY,
				emergencyClearance,
				3
			)
		until destination or os.clock() >= deadline
	end
	if destination then
		GameplayAnalytics.RecordEmergencySanctuaryCreated(player, destination)
		debugLog("santuario emergencial criado: " .. destination.IslandKey)
		return destination
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local level = math.max(
		(origin and origin.LogicalLevel or 0) + 1,
		tonumber(player:GetAttribute("CurrentLogicalLevel")) or 0
	)
	destination = createFallbackSanctuary(waterY, root and root.Position, level)
	GameplayAnalytics.RecordEmergencySanctuaryCreated(player, destination)
	debugLog("fallback global criado ou elevado: " .. destination.IslandKey)
	return destination
end

local function teleportCharacter(player, state, destination)
	local attempts = math.max(1, math.floor(tonumber(CONFIG.TeleportRetryCount) or 3))
	for attempt = 1, attempts do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local waterY = getWaterY()
		if not character or not humanoid or humanoid.Health <= 0 or not root then
			return false, "CharacterUnavailable"
		end
		if not destinationStillValid(destination, waterY) then
			return false, "DestinationInvalidated"
		end
		player:SetAttribute("SanctuaryRescueDestinationKey", destination.IslandKey)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(destination.CFrame)
		RunService.Heartbeat:Wait()
		if player.Character == character
			and (root.Position - destination.CFrame.Position).Magnitude <= 10
		then
			humanoid.Health = humanoid.MaxHealth
			synchronizeCompanions(player)
			return true
		end
		GameplayAnalytics.RecordRescueTeleportFailed(player, "PositionNotConfirmed", destination)
		debugLog(string.format(
			"teleporte de %s nao confirmado (tentativa %d/%d)",
			player.Name,
			attempt,
			attempts
		))
		task.wait(math.max(0.05, tonumber(CONFIG.TeleportRetrySeconds) or 0.15))
	end
	return false, "RetryLimit"
end

local function finishRescue(player, state, token, character, root, destination, success)
	if player.Parent ~= Players or state.RescueToken ~= token then
		if root and root.Parent then
			root.Anchored = false
		end
		return
	end
	local minimumEnd = state.RescueStartedAt
		+ math.max(0.25, tonumber(CONFIG.TransitionMinimumSeconds) or 1.25)
	local readyDeadline = os.clock()
		+ math.max(0.5, tonumber(CONFIG.DestinationReadyTimeoutSeconds) or 2.5)
	while os.clock() < minimumEnd do
		task.wait()
	end
	while not state.ClientReadyToken and os.clock() < readyDeadline and player.Parent == Players do
		task.wait(0.05)
	end
	if root and root.Parent then
		root.Anchored = false
	end
	local protectionUntil = workspace:GetServerTimeNow()
		+ math.max(0, tonumber(CONFIG.PostRescueProtectionSeconds) or 4)
	player:SetAttribute("SanctuaryRescueProtectionUntil", protectionUntil)
	player:SetAttribute("SanctuaryRescueState", success and "Ready" or "Failed")
	state.RescueInProgress = false
	state.RescueToken = nil
	state.ClientReadyToken = nil
	transitionRemote:FireClient(player, {
		Action = "Complete",
		Token = token,
		Success = success,
	})
	task.delay(math.max(0, tonumber(CONFIG.PostRescueProtectionSeconds) or 4), function()
		if player.Parent == Players and player.Character == character then
			destroyForceField(character, RESCUE_FORCE_FIELD)
			if workspace:GetServerTimeNow() >= (tonumber(player:GetAttribute("SanctuaryRescueProtectionUntil")) or 0) then
				player:SetAttribute("SanctuaryRescueProtectionUntil", nil)
			end
		end
	end)
end

local function rescuePlayer(player, origin)
	local state = states[player]
	if not state or state.RescueInProgress then
		return
	end
	state.RescueInProgress = true
	rescueSerial += 1
	local token = string.format("%d:%d", player.UserId, rescueSerial)
	state.RescueToken = token
	state.ClientReadyToken = nil
	state.RescueStartedAt = os.clock()
	player:SetAttribute("SanctuaryRescueState", "Searching")
	player:SetAttribute("SanctuaryRescueToken", token)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		state.RescueInProgress = false
		GameplayAnalytics.RecordRescueTeleportFailed(player, "CharacterUnavailable", nil)
		return
	end
	forceField(character, RESCUE_FORCE_FIELD, false)
	root.Anchored = true
	transitionRemote:FireClient(player, {
		Action = "Begin",
		Token = token,
		PrimaryText = tostring(CONFIG.RescuePrimaryText or "O santuario foi alcancado pela agua..."),
		SecondaryText = tostring(CONFIG.RescueSecondaryText or "Procurando um novo refugio nas alturas."),
	})
	task.spawn(function()
		local destination = chooseDestination(player, origin, getWaterY())
		if player.Parent ~= Players or state.RescueToken ~= token then
			return
		end
		if not destination then
			GameplayAnalytics.RecordRescueTeleportFailed(player, "NoDestination", nil)
			debugLog("teleporte de " .. player.Name .. " falhou: nenhum destino")
			finishRescue(player, state, token, character, root, nil, false)
			return
		end
		debugLog(string.format("destino de %s: %s", player.Name, destination.IslandKey))
		player:SetAttribute("SanctuaryRescueState", "Teleporting")
		local teleported, reason = teleportCharacter(player, state, destination)
		if not teleported and reason == "DestinationInvalidated" then
			destination = chooseDestination(player, origin, getWaterY())
			if destination then
				teleported, reason = teleportCharacter(player, state, destination)
			end
		end
		if not teleported then
			GameplayAnalytics.RecordRescueTeleportFailed(player, reason, destination)
			destination = createFallbackSanctuary(
				getWaterY(),
				root and root.Position,
				(origin and origin.LogicalLevel or 0) + 1
			)
			teleported, reason = teleportCharacter(player, state, destination)
		end
		if teleported then
			setContext(player, state, destination, true)
			GameplayAnalytics.RecordPlayerRescued(player, origin, destination)
			player:SetAttribute("SanctuaryRescueState", "Stabilizing")
			transitionRemote:FireClient(player, {
				Action = "Arrived",
				Token = token,
				Destination = destination.CFrame.Position,
			})
			debugLog(string.format("%s resgatado em %s", player.Name, destination.IslandKey))
		else
			GameplayAnalytics.RecordRescueTeleportFailed(player, reason or "FallbackFailed", destination)
			debugLog(string.format(
				"teleporte de %s falhou: %s",
				player.Name,
				tostring(reason or "FallbackFailed")
			))
		end
		finishRescue(player, state, token, character, root, destination, teleported)
	end)
end

function SanctuaryService.UpdateWaterLevel(waterY)
	if not started then
		return
	end
	waterY = tonumber(waterY) or getWaterY()
	ensureFallbackAboveWater(waterY)
	for _, context in ipairs(ChunkManager.GetSanctuaryContexts(3)) do
		if not context.IsSubmerged and context.SurfaceY <= waterY then
			ChunkManager.SetSanctuarySubmerged(context.IslandKey, true, waterY)
			context.IsSubmerged = true
			local affected = {}
			for player in pairs(states) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				-- O contexto cacheado pode estar um frame atrasado. O resgate exige
				-- posicao atual dentro dos bounds autoritativos do santuario.
				if root and pointInsideFloor(
					context,
					root.Position,
					tonumber(CONFIG.VerticalPaddingStuds) or 12
				) then
					table.insert(affected, player)
				end
			end
			GameplayAnalytics.RecordSanctuarySubmerged(affected, context)
			debugLog(string.format("santuario submerso: %s (%d jogador(es))", context.IslandKey, #affected))
			for _, player in ipairs(affected) do
				rescuePlayer(player, context)
			end
		end
	end
end

function SanctuaryService.IsPlayerProtectedFromWater(player)
	local state = states[player]
	if state and state.RescueInProgress then
		return true
	end
	local protectionUntil = tonumber(player:GetAttribute("SanctuaryRescueProtectionUntil")) or 0
	if workspace:GetServerTimeNow() < protectionUntil then
		return true
	end
	return player:GetAttribute("SanctuaryProtected") == true
		and player:GetAttribute("InSafeZone") == true
end

function SanctuaryService.IsPlayerProtectedFromEnemies(player)
	return SanctuaryService.IsPlayerProtectedFromWater(player)
end

local function updatePlayer(player)
	local state = states[player]
	if not state then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		if not state.RescueInProgress then
			clearPlayerProtectionAttributes(player, character)
			state.Context = nil
		end
		return
	end
	local waterY = getWaterY()
	local context = contextAtPosition(root.Position)
	local validContext = context and contextIsSafe(context, waterY, 0)
	if validContext then
		setContext(player, state, context, state.RescueInProgress)
		setPlayerProtectionAttributes(player, character, context)
		if not state.LastSafePosition
			or (root.Position - state.LastSafePosition).Magnitude > 2
		then
			state.LastSafePosition = root.Position
			state.IdleSince = os.clock()
			state.IdleSent = false
		end
		if state.IdleSince
			and not state.IdleSent
			and os.clock() - state.IdleSince >= math.max(5, tonumber(CONFIG.IdleEventSeconds) or 60)
		then
			state.IdleSent = true
			GameplayAnalytics.RecordSanctuaryIdle(player, context)
		end
	else
		-- Se o personagem atravessar acidentalmente o piso ainda dentro dos
		-- limites horizontais, restaura sua posicao sem morte ou penalidade.
		local previous = state.Context
		if previous and contextIsSafe(previous, waterY, 0) and pointInsideFloor(previous, root.Position, 40) then
			if root.Position.Y < previous.SurfaceY - 7 then
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(previous.CFrame)
				setPlayerProtectionAttributes(player, character, previous)
				return
			end
		end
		if not state.RescueInProgress then
			setContext(player, state, nil, false)
			clearPlayerProtectionAttributes(player, character)
		end
	end
	if state.RescueInProgress
		or workspace:GetServerTimeNow() < (tonumber(player:GetAttribute("SanctuaryRescueProtectionUntil")) or 0)
	then
		forceField(character, RESCUE_FORCE_FIELD, false)
	end
end

local function bindPlayer(player)
	states[player] = {
		Context = nil,
		EnteredAt = nil,
		IdleSince = nil,
		LastSafePosition = nil,
		IdleSent = false,
		RescueInProgress = false,
		RescueToken = nil,
		ClientReadyToken = nil,
	}
	player:SetAttribute("InSafeZone", false)
	player:SetAttribute("SanctuaryProtected", false)
	player:SetAttribute("SanctuaryRescueState", "Idle")
	player.CharacterAdded:Connect(function(character)
		local state = states[player]
		if not state then
			return
		end
		state.Context = nil
		state.EnteredAt = nil
		state.IdleSince = nil
		state.LastSafePosition = nil
		state.IdleSent = false
		state.RescueInProgress = false
		state.RescueToken = nil
		player:SetAttribute("SanctuaryRescueDestinationKey", nil)
		player:SetAttribute("SanctuaryRescueProtectionUntil", nil)
		character:SetAttribute("SanctuaryProtected", false)
	end)
end

function SanctuaryService.Start()
	if started or CONFIG.Enabled == false then
		return
	end
	started = true
	GameplayAnalytics.Start()
	if not ChunkManager.IsRunning() then
		ChunkManager.Start()
	end
	transitionRemote = ensureRemote()
	transitionRemote.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.Action ~= "ClientReady" then
			return
		end
		local state = states[player]
		if state and state.RescueInProgress and payload.Token == state.RescueToken then
			state.ClientReadyToken = payload.Token
		end
	end)
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	task.spawn(function()
		local interval = math.max(0.05, tonumber(CONFIG.CheckIntervalSeconds) or 0.1)
		while started do
			SanctuaryService.UpdateWaterLevel(getWaterY())
			for _, player in ipairs(Players:GetPlayers()) do
				updatePlayer(player)
			end
			task.wait(interval)
		end
	end)
end

return table.freeze(SanctuaryService)
