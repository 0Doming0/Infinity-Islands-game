-- Representacao compartilhada dos Mercadores do Ceu pessoais.
--
-- V8 garante que um encontro pronto produza um modelo visivel:
-- - remove modelos antigos quando a oferta termina;
-- - preserva ofertas ainda nao abertas quando a ilha e reciclada;
-- - solicita outro alvo quando um spawn falha;
-- - troca assets publicados vazios, invisiveis ou grandes demais pelo fallback;
-- - usa streaming persistente para o modelo nao desaparecer em ilhas distantes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MarketingOfferService = require(script.Parent.MVPSystems.MarketingOfferService)

local MODEL_PREFIX = "PersonalSkyMerchant_"
local UPDATE_SECONDS = 0.5
local SPAWN_RETRY_SECONDS = math.max(
	0.5,
	tonumber(MVPConfig.Village.PersonalSkyMerchantSpawnRetrySeconds) or 1.5
)
local TEMPLATE_FLOOR_RATIO = math.clamp(
	tonumber(MVPConfig.Village.PersonalSkyMerchantPublishedTemplateFloorRatio) or 0.72,
	0.35,
	0.9
)
local TEMPLATE_MAX_HEIGHT = math.max(
	10,
	tonumber(MVPConfig.Village.PersonalSkyMerchantPublishedTemplateMaxHeight) or 36
)
local WATER_CLEARANCE_STUDS = 8
local VERSION = "GuaranteedVisibleLifecycleV8"

local modelsByPlayer = setmetatable({}, { __mode = "k" })
local lifecycleByPlayer = setmetatable({}, { __mode = "k" })
local updateQueued = setmetatable({}, { __mode = "k" })

local function islandKey(island)
	return island and tostring(island:GetAttribute("IslandNodeKey") or "") or ""
end

local function findIsland(key)
	if type(key) ~= "string" or key == "" then
		return nil
	end
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("IsSkyIsland") == true
			and islandKey(descendant) == key
		then
			return descendant
		end
	end
	return nil
end

local function isVillageOrSanctuary(island)
	if not island or not island:IsA("Model") then
		return true
	end
	if island:GetAttribute("VillageSpawned") == true
		or island:GetAttribute("IsSocialSanctuary") == true
		or CollectionService:HasTag(island, "SkyDungeonSanctuary")
	then
		return true
	end
	local role = string.lower(tostring(island:GetAttribute("IslandRole") or ""))
	if string.find(role, "sanctuary", 1, true)
		or string.find(role, "village", 1, true)
	then
		return true
	end
	if island:FindFirstChild("MVPVillage") then
		return true
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:GetAttribute("ProceduralVillage") == true then
			return true
		end
	end
	return false
end

local function floorOf(island)
	local floor = island and island:FindFirstChild("IslandFloor")
	return floor and floor:IsA("BasePart") and floor or nil
end

local function isAboveWater(island)
	local floor = floorOf(island)
	if not floor then
		return false
	end
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	if not surfaceY then
		return true
	end
	return floor.Position.Y + floor.Size.Y / 2 > surfaceY + WATER_CLEARANCE_STUDS
end

local function isNormalMerchantIsland(island)
	return island
		and island:IsA("Model")
		and island:IsDescendantOf(workspace)
		and island:GetAttribute("IsSkyIsland") == true
		and tostring(island:GetAttribute("IslandType") or "Normal") == "Normal"
		and not isVillageOrSanctuary(island)
		and floorOf(island) ~= nil
		and isAboveWater(island)
end

local function selectedIsland(player)
	local key = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
	if key == "" then
		return nil
	end
	local targetValue = player:FindFirstChild("PersonalSkyMerchantTargetIsland")
	local island = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value or nil
	if isNormalMerchantIsland(island) and islandKey(island) == key then
		return island
	end
	island = findIsland(key)
	return isNormalMerchantIsland(island) and island or nil
end

local function attachedActiveIsland(model)
	if not model or not model.Parent or not model:IsDescendantOf(workspace) then
		return nil
	end
	local current = model.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("IsSkyIsland") == true then
			if islandKey(current) == tostring(model:GetAttribute("SpawnIslandKey") or "") then
				return current
			end
			return nil
		end
		current = current.Parent
	end
	return nil
end

local function visibleBounds(model)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Transparency < 0.99
			and descendant.Size.Magnitude > 0.1
		then
			local half = descendant.Size / 2
			for _, x in ipairs({ -half.X, half.X }) do
				for _, y in ipairs({ -half.Y, half.Y }) do
					for _, z in ipairs({ -half.Z, half.Z }) do
						local corner = descendant.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
						minimum = Vector3.new(
							math.min(minimum.X, corner.X),
							math.min(minimum.Y, corner.Y),
							math.min(minimum.Z, corner.Z)
						)
						maximum = Vector3.new(
							math.max(maximum.X, corner.X),
							math.max(maximum.Y, corner.Y),
							math.max(maximum.Z, corner.Z)
						)
						found = true
					end
				end
			end
		end
	end
	if not found then
		return nil
	end
	return CFrame.new((minimum + maximum) / 2), maximum - minimum
end

local function part(parent, name, size, color, cframe)
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.Color = color
	value.Material = Enum.Material.SmoothPlastic
	value.CFrame = cframe
	value.Anchored = true
	value.CanCollide = false
	value.CanTouch = false
	value.CanQuery = false
	value.Parent = parent
	return value
end

local function fallbackTemplate()
	local model = Instance.new("Model")
	model.Name = "SkyMerchantFallback"
	local torso = part(
		model,
		"HumanoidRootPart",
		Vector3.new(2.5, 3, 1.4),
		Color3.fromRGB(40, 91, 132),
		CFrame.new(0, 3.5, 0)
	)
	part(model, "Head", Vector3.new(1.8, 1.8, 1.8), Color3.fromRGB(224, 184, 145), CFrame.new(0, 5.8, 0))
	part(model, "Hat", Vector3.new(3.2, 0.45, 3.2), Color3.fromRGB(255, 206, 74), CFrame.new(0, 6.75, 0))
	part(model, "LeftArm", Vector3.new(0.75, 2.8, 0.75), Color3.fromRGB(224, 184, 145), CFrame.new(-1.7, 3.6, 0))
	part(model, "RightArm", Vector3.new(0.75, 2.8, 0.75), Color3.fromRGB(224, 184, 145), CFrame.new(1.7, 3.6, 0))
	part(model, "LeftLeg", Vector3.new(0.9, 2, 1), Color3.fromRGB(31, 46, 67), CFrame.new(-0.65, 1, 0))
	part(model, "RightLeg", Vector3.new(0.9, 2, 1), Color3.fromRGB(31, 46, 67), CFrame.new(0.65, 1, 0))
	model.PrimaryPart = torso
	return model
end

local function cloneTemplate()
	local assets = ReplicatedStorage:FindFirstChild("PersonalSkyMerchantAssets")
	if assets then
		local preferredName = assets:GetAttribute("PreferredTemplateName")
		local preferred = type(preferredName) == "string" and assets:FindFirstChild(preferredName) or nil
		if preferred and preferred:IsA("Model") and preferred.Archivable then
			local success, clone = pcall(preferred.Clone, preferred)
			if success and clone and clone:IsA("Model") then
				return clone, true, preferred.Name
			end
		end
		for _, candidate in ipairs(assets:GetChildren()) do
			if candidate:IsA("Model") and candidate.Archivable then
				local success, clone = pcall(candidate.Clone, candidate)
				if success and clone and clone:IsA("Model") then
					return clone, true, candidate.Name
				end
			end
		end
	end
	return fallbackTemplate(), false, "SkyMerchantFallback"
end

local function sanitize(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("Animator")
			or descendant:IsA("AnimationController")
			or descendant:IsA("BodyMover")
			or descendant:IsA("LinearVelocity")
			or descendant:IsA("AngularVelocity")
			or descendant:IsA("AlignPosition")
			or descendant:IsA("AlignOrientation")
			or descendant:IsA("VectorForce")
			or descendant:IsA("Torque")
		then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.AutoRotate = false
			descendant.WalkSpeed = 0
			descendant.JumpPower = 0
			descendant.JumpHeight = 0
			descendant.PlatformStand = true
			pcall(function()
				descendant.EvaluateStateMachine = false
			end)
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	model:SetAttribute("StaticStore", true)
	model:SetAttribute("MovementLocked", true)
	model:SetAttribute("RotationLocked", true)
end

local function templateFitsFloor(size, floor)
	if not size or not floor then
		return false
	end
	return size.X <= floor.Size.X * TEMPLATE_FLOOR_RATIO
		and size.Z <= floor.Size.Z * TEMPLATE_FLOOR_RATIO
		and size.Y <= TEMPLATE_MAX_HEIGHT
end

local function getPlacement(player, island, footprint)
	local floor = floorOf(island)
	if not floor then
		return nil, nil, "MissingIslandFloor"
	end
	local clearance = math.max(
		3,
		tonumber(MVPConfig.Village.PersonalSkyMerchantStandEdgeClearance) or 4
	)
	if footprint.X + clearance * 2 > floor.Size.X
		or footprint.Z + clearance * 2 > floor.Size.Z
	then
		return nil, nil, "TemplateDoesNotFitIsland"
	end
	local usableX = math.max(0, floor.Size.X / 2 - footprint.X / 2 - clearance)
	local usableZ = math.max(0, floor.Size.Z / 2 - footprint.Z / 2 - clearance)
	local angle = math.rad((math.abs(player.UserId) * 137.508) % 360)
	local radiusX = math.min(usableX, math.max(4, floor.Size.X * 0.24))
	local radiusZ = math.min(usableZ, math.max(4, floor.Size.Z * 0.24))
	local localPosition = Vector3.new(
		math.cos(angle) * radiusX,
		floor.Size.Y / 2 + 0.05,
		math.sin(angle) * radiusZ
	)
	local position = floor.CFrame:PointToWorldSpace(localPosition)
	local center = floor.CFrame:PointToWorldSpace(Vector3.new(0, floor.Size.Y / 2 + 0.05, 0))
	return position, center, nil
end

local function addSharedPresentation(model, player, interactionPosition, topOffset)
	local anchor = Instance.new("Part")
	anchor.Name = "MerchantInteractionAnchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(interactionPosition)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = true
	anchor.Parent = model

	local highlight = Instance.new("Highlight")
	highlight.Name = "SharedMerchantHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 213, 88)
	highlight.OutlineTransparency = 0.12
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SharedMerchantLabel"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(230, 56)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffset, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 130
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 31, 48)
	label.BackgroundTransparency = 0.08
	label.Text = string.format("MERCADOR DE %s\nOfertas pessoais", string.upper(player.DisplayName))
	label.TextColor3 = Color3.fromRGB(255, 220, 105)
	label.TextStrokeTransparency = 0.42
	label.TextWrapped = true
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)
end

local function lifecycle(player)
	local state = lifecycleByPlayer[player]
	if not state then
		state = {
			RetiredOfferSerial = -1,
			NextSpawnAttemptAt = 0,
			FailureCount = 0,
			OfferSerial = 0,
			IslandKey = nil,
		}
		lifecycleByPlayer[player] = state
	end
	return state
end

local function removeMerchantModel(player, resetLifecycle)
	local model = modelsByPlayer[player]
	if model and model.Parent then
		model:Destroy()
	end
	modelsByPlayer[player] = nil
	if resetLifecycle then
		lifecycleByPlayer[player] = nil
	end
end

local function isRetargetableEncounter(encounterState)
	return encounterState == "Unseen" or encounterState == "Presented"
end

local function requestRetarget(player, key, reason)
	if type(key) == "string" and key ~= "" then
		player:SetAttribute("PersonalSkyMerchantRejectedTargetIslandKey", key)
	end
	player:SetAttribute("PersonalSkyMerchantRetargetReason", reason)
	player:SetAttribute(
		"PersonalSkyMerchantRetargetRequestSerial",
		(tonumber(player:GetAttribute("PersonalSkyMerchantRetargetRequestSerial")) or 0) + 1
	)
end

local function retireWithIsland(player, missingKey)
	local state = lifecycle(player)
	local encounterState = tostring(player:GetAttribute("PersonalSkyMerchantEncounterState") or "Unseen")
	modelsByPlayer[player] = nil
	state.IslandKey = nil
	player:SetAttribute("PersonalSkyMerchantWorldIslandKey", nil)

	if player:GetAttribute("MerchantOfferReady") == true and isRetargetableEncounter(encounterState) then
		player:SetAttribute("PersonalSkyMerchantWorldState", "TargetLostRetargeting")
		requestRetarget(player, missingKey, "IslandRemovedBeforeOpen")
		return
	end

	local offerSerial = math.max(0, math.floor(tonumber(state.OfferSerial) or 0))
	state.RetiredOfferSerial = math.max(state.RetiredOfferSerial or -1, offerSerial)
	player:SetAttribute("PersonalSkyMerchantWorldState", "RetiredWithIsland")
	player:SetAttribute("PersonalSkyMerchantRetiredOfferSerial", state.RetiredOfferSerial)
	MarketingOfferService.ExpireEncounter(player, offerSerial)
end

local function prepareModelForIsland(island)
	local floor = floorOf(island)
	if not floor then
		return nil, false, nil, "MissingIslandFloor"
	end

	local model, usesPublishedTemplate, templateName = cloneTemplate()
	sanitize(model)
	local _, size = visibleBounds(model)
	local fallbackReason
	if not size then
		fallbackReason = "PublishedTemplateInvisibleOrEmpty"
	elseif usesPublishedTemplate and not templateFitsFloor(size, floor) then
		fallbackReason = "PublishedTemplateTooLarge"
	end

	if fallbackReason then
		model:Destroy()
		model = fallbackTemplate()
		usesPublishedTemplate = false
		templateName = "SkyMerchantFallback"
		sanitize(model)
		_, size = visibleBounds(model)
	end
	if not size then
		model:Destroy()
		return nil, false, templateName, "FallbackTemplateHasNoVisibleBounds"
	end
	if not templateFitsFloor(size, floor) then
		model:Destroy()
		return nil, false, templateName, "FallbackTemplateDoesNotFitIsland"
	end
	return model, usesPublishedTemplate, templateName, fallbackReason
end

local function spawnFor(player, island)
	if not isNormalMerchantIsland(island) then
		return nil, "InvalidTargetIsland"
	end
	local model, usesPublishedTemplate, templateName, fallbackReason = prepareModelForIsland(island)
	if not model then
		return nil, fallbackReason or "NoUsableTemplate"
	end

	local boundsCFrame, boundsSize = visibleBounds(model)
	if not boundsCFrame or not boundsSize then
		model:Destroy()
		return nil, "BoundsMissingBeforePlacement"
	end
	local footprint = Vector3.new(
		math.max(4, boundsSize.X),
		math.max(5, boundsSize.Y),
		math.max(4, boundsSize.Z)
	)
	local position, center, placementError = getPlacement(player, island, footprint)
	if not position then
		model:Destroy()
		return nil, placementError or "NoValidPlacement"
	end

	local originalPivot = model:GetPivot()
	model:PivotTo(originalPivot + Vector3.new(
		position.X - boundsCFrame.Position.X,
		position.Y - (boundsCFrame.Position.Y - boundsSize.Y / 2),
		position.Z - boundsCFrame.Position.Z
	))
	boundsCFrame, boundsSize = visibleBounds(model)
	if not boundsCFrame or not boundsSize then
		model:Destroy()
		return nil, "BoundsMissingAfterPlacement"
	end

	local towardCenter = Vector3.new(
		center.X - boundsCFrame.Position.X,
		0,
		center.Z - boundsCFrame.Position.Z
	)
	local forward = towardCenter.Magnitude < 0.1 and Vector3.new(0, 0, -1) or towardCenter.Unit
	local frontDepth = math.abs(forward.X) * boundsSize.X / 2
		+ math.abs(forward.Z) * boundsSize.Z / 2
	local interactionPosition = Vector3.new(
		boundsCFrame.Position.X,
		position.Y + math.clamp(boundsSize.Y * 0.35, 2, 3.5),
		boundsCFrame.Position.Z
	) + forward * (frontDepth + 1.25)

	model.Name = MODEL_PREFIX .. tostring(player.UserId)
	model:SetAttribute("PersonalSkyMerchant", true)
	model:SetAttribute("ServerManagedPersonalSkyMerchant", true)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerDisplayName", player.DisplayName)
	model:SetAttribute("SpawnIslandKey", islandKey(island))
	model:SetAttribute(
		"OfferSerial",
		tonumber(player:GetAttribute("PersonalSkyMerchantEncounterSerial")) or 0
	)
	model:SetAttribute("OffersArePrivate", true)
	model:SetAttribute("UsesPublishedTemplate", usesPublishedTemplate)
	model:SetAttribute("TemplateName", templateName)
	model:SetAttribute("TemplateFallbackReason", fallbackReason)
	model:SetAttribute("StaticStore", true)
	model:SetAttribute("MovementLocked", true)
	model:SetAttribute("RotationLocked", true)
	model:SetAttribute("SpawnPolicy", VERSION)
	addSharedPresentation(model, player, interactionPosition, math.max(4, boundsSize.Y + 0.8))

	if not island.Parent or not island:IsDescendantOf(workspace) then
		model:Destroy()
		return nil, "IslandRemovedBeforeParent"
	end
	model.Parent = island
	local streamingPersistent = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	model:SetAttribute("StreamingPersistent", streamingPersistent)
	player:SetAttribute("PersonalSkyMerchantWorldIslandKey", islandKey(island))
	player:SetAttribute("PersonalSkyMerchantTemplateName", templateName)
	player:SetAttribute("PersonalSkyMerchantUsedFallbackTemplate", not usesPublishedTemplate)
	player:SetAttribute("PersonalSkyMerchantTemplateFallbackReason", fallbackReason)
	return model, nil
end

local function encounterEnded(encounterState)
	return encounterState == "Ignored"
		or encounterState == "Dismissed"
		or encounterState == "Purchased"
		or encounterState == "ExpiredWithIsland"
end

local function updatePlayer(player)
	updateQueued[player] = nil
	if player.Parent ~= Players then
		return
	end

	local state = lifecycle(player)
	local offerReady = player:GetAttribute("MerchantOfferReady") == true
	local encounterState = tostring(player:GetAttribute("PersonalSkyMerchantEncounterState") or "Inactive")
	local existing = modelsByPlayer[player]

	-- Um modelo antigo nunca deve sobreviver ao fim da oferta. Na V7 ele podia
	-- continuar anexado e bloquear indefinidamente a proxima recomendacao.
	if existing and (not offerReady or encounterEnded(encounterState)) then
		removeMerchantModel(player, false)
		state.IslandKey = nil
		player:SetAttribute("PersonalSkyMerchantWorldIslandKey", nil)
		existing = nil
	end

	if existing then
		local island = attachedActiveIsland(existing)
		if island then
			local targetKey = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
			if not isNormalMerchantIsland(island)
				or targetKey == ""
				or islandKey(island) ~= targetKey
			then
				local oldKey = islandKey(island)
				removeMerchantModel(player, false)
				state.IslandKey = nil
				existing = nil
				if offerReady and isRetargetableEncounter(encounterState) then
					requestRetarget(player, oldKey, "ExistingMerchantTargetChanged")
				end
			else
				local serial = math.max(
					0,
					math.floor(tonumber(player:GetAttribute("PersonalSkyMerchantEncounterSerial")) or 0)
				)
				existing:SetAttribute("OfferSerial", serial)
				state.OfferSerial = serial
				player:SetAttribute("PersonalSkyMerchantWorldState", "AttachedToIsland")
				return
			end
		else
			local missingKey = tostring(existing:GetAttribute("SpawnIslandKey") or state.IslandKey or "")
			retireWithIsland(player, missingKey)
			existing = nil
		end
	end

	if not offerReady then
		player:SetAttribute("PersonalSkyMerchantWorldState", "WaitingForRecommendation")
		player:SetAttribute("PersonalSkyMerchantSpawnRetryWaitSeconds", nil)
		return
	end
	if encounterEnded(encounterState) then
		player:SetAttribute("PersonalSkyMerchantWorldState", "EncounterEnded:" .. encounterState)
		return
	end

	local serial = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("PersonalSkyMerchantEncounterSerial")) or 0)
	)
	if serial ~= state.OfferSerial then
		state.OfferSerial = serial
		state.FailureCount = 0
		state.NextSpawnAttemptAt = 0
	end
	if serial <= (state.RetiredOfferSerial or -1) then
		player:SetAttribute("PersonalSkyMerchantWorldState", "WaitingForNextOfferSerial")
		return
	end

	local island = selectedIsland(player)
	if not island then
		player:SetAttribute("PersonalSkyMerchantWorldState", "WaitingForAssignedSafeIsland")
		return
	end

	local timestamp = workspace:GetServerTimeNow()
	if timestamp < (state.NextSpawnAttemptAt or 0) then
		player:SetAttribute("PersonalSkyMerchantWorldState", "WaitingForSpawnRetry")
		player:SetAttribute(
			"PersonalSkyMerchantSpawnRetryWaitSeconds",
			math.ceil(state.NextSpawnAttemptAt - timestamp)
		)
		return
	end
	player:SetAttribute("PersonalSkyMerchantSpawnRetryWaitSeconds", nil)
	player:SetAttribute("PersonalSkyMerchantWorldState", "Spawning")
	player:SetAttribute(
		"PersonalSkyMerchantSpawnAttemptCount",
		(tonumber(player:GetAttribute("PersonalSkyMerchantSpawnAttemptCount")) or 0) + 1
	)

	local success, modelOrNil, spawnError = pcall(spawnFor, player, island)
	local model = success and modelOrNil or nil
	local errorMessage = success and spawnError or tostring(modelOrNil)
	modelsByPlayer[player] = model
	if model then
		state.IslandKey = islandKey(island)
		state.FailureCount = 0
		state.NextSpawnAttemptAt = 0
		player:SetAttribute("PersonalSkyMerchantLastSpawnError", nil)
		player:SetAttribute("PersonalSkyMerchantSpawnFailureCount", 0)
		player:SetAttribute("PersonalSkyMerchantRejectedTargetIslandKey", nil)
		player:SetAttribute("PersonalSkyMerchantWorldState", "AttachedToIsland")
	else
		errorMessage = errorMessage or "UnknownSpawnFailure"
		state.FailureCount += 1
		state.NextSpawnAttemptAt = timestamp + SPAWN_RETRY_SECONDS
		player:SetAttribute("PersonalSkyMerchantLastSpawnError", errorMessage)
		player:SetAttribute("PersonalSkyMerchantSpawnFailureCount", state.FailureCount)
		player:SetAttribute("PersonalSkyMerchantWorldState", "SpawnFailed:" .. errorMessage)
		requestRetarget(player, islandKey(island), errorMessage)
		warn(string.format(
			"[SkyMerchant V8] Spawn falhou para %s na ilha %s: %s",
			player.Name,
			islandKey(island),
			errorMessage
		))
	end
end

local function queueUpdate(player)
	if updateQueued[player] then
		return
	end
	updateQueued[player] = true
	task.defer(updatePlayer, player)
end

local function setup(player)
	lifecycle(player)
	player:SetAttribute("PersonalSkyMerchantWorldState", "WaitingForRecommendation")
	player:SetAttribute("PersonalSkyMerchantSpawnAttemptCount", 0)
	player:SetAttribute("PersonalSkyMerchantSpawnFailureCount", 0)
	for _, attribute in ipairs({
		"MerchantOfferReady",
		"PersonalSkyMerchantEncounterState",
		"PersonalSkyMerchantEncounterSerial",
		"PersonalSkyMerchantTargetIslandKey",
		"CurrentIslandKey",
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			queueUpdate(player)
		end)
	end
	queueUpdate(player)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Model")
		and descendant:GetAttribute("ServerManagedPersonalSkyMerchant") == true
	then
		descendant:Destroy()
	end
end

Players.PlayerAdded:Connect(setup)
Players.PlayerRemoving:Connect(function(player)
	removeMerchantModel(player, true)
	updateQueued[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	setup(player)
end

workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") and instance:GetAttribute("IsSkyIsland") == true then
		for _, player in ipairs(Players:GetPlayers()) do
			queueUpdate(player)
		end
	end
end)

workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("Model")
		and instance:GetAttribute("ServerManagedPersonalSkyMerchant") == true
	then
		local player = Players:GetPlayerByUserId(
			tonumber(instance:GetAttribute("OwnerUserId")) or 0
		)
		if player then
			queueUpdate(player)
		end
	elseif instance:IsA("Model") and instance:GetAttribute("IsSkyIsland") == true then
		for _, player in ipairs(Players:GetPlayers()) do
			queueUpdate(player)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(UPDATE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			queueUpdate(player)
		end
	end
end)

workspace:SetAttribute("PersonalSkyMerchantWorldVersion", VERSION)
