-- Mercador do Ceu individual e orientado por necessidade.
--
-- O servidor decide quando existe uma recomendacao valida. Este LocalScript
-- cria o NPC somente para o jogador destinatario e o posiciona de forma
-- deterministica na ilha para a qual ele demonstrou intencao de ir. Nenhum
-- produto ou ponto do mapa e sorteado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")
local monetizationEvent = ReplicatedStorage:WaitForChild("MonetizationEvent")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local MERCHANT_NAME = "PersonalSkyMerchant_" .. tostring(player.UserId)
local PATH_NAME = "PersonalSkyMerchantPath_" .. tostring(player.UserId)
local CHECK_SECONDS = 1
local activeMerchant
local activePrompt
local activePath
local activeIsland
local activeIslandKey
local activePlacementMode
local offerReadyObservedAt
local activeOfferSerial
local encounterState = "Inactive"
local encounterIsland
local relocationCount = 0
local promptVisibleSince
local nearbySince
local farAwaySince
local encounterReportInFlight = false
local updateQueued = false
local openRequestInFlight = false

local openEvent = playerGui:FindFirstChild("PersonalSkyMerchantOpen")
if not openEvent then
	openEvent = Instance.new("BindableEvent")
	openEvent.Name = "PersonalSkyMerchantOpen"
	openEvent.Parent = playerGui
end

local function getLivingRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function getSkyIsland(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("IsSkyIsland") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function surfaceIsSafe(hitPart, position)
	if not hitPart or hitPart.Name == "Water" or not getSkyIsland(hitPart) then
		return false
	end
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	return not surfaceY or position.Y > surfaceY + 2
end

local function getIslandKey(island)
	return island and tostring(island:GetAttribute("IslandNodeKey") or "") or ""
end

local function getVisibleBounds(model)
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

local function getIntendedIsland()
	local targetKey = player:GetAttribute("WorldIntentTargetIslandKey")
	local targetValue = player:FindFirstChild("WorldIntentTargetIsland")
	local island = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value or nil
	if typeof(targetKey) == "string"
		and targetKey ~= ""
		and (
			not island
			or not island:IsA("Model")
			or getIslandKey(island) ~= targetKey
		)
	then
		-- ObjectValue e atributos podem chegar em frames diferentes, sobretudo
		-- com StreamingEnabled. A chave logica resolve o mesmo alvo sem sorteio.
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("Model")
				and descendant:GetAttribute("IsSkyIsland") == true
				and getIslandKey(descendant) == targetKey
			then
				island = descendant
				break
			end
		end
	end
	if typeof(targetKey) ~= "string"
		or targetKey == ""
		or not island
		or not island:IsA("Model")
		or not island:IsDescendantOf(workspace)
		or island:GetAttribute("IsSkyIsland") ~= true
		or getIslandKey(island) ~= targetKey
	then
		return nil
	end
	return island
end

local function deterministicSide(island)
	local value = player.UserId
	for index = 1, #getIslandKey(island) do
		value += string.byte(getIslandKey(island), index) * index
	end
	return value % 2 == 0 and 1 or -1
end

local function placementBlockerCount(island, floor, position, footprint)
	local parameters = OverlapParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = {
		player.Character,
		activeMerchant,
		activePath,
	}
	parameters.RespectCanCollide = false
	local height = math.max(6, footprint.Y)
	local results = workspace:GetPartBoundsInBox(
		CFrame.new(position + Vector3.new(0, height / 2 + 0.2, 0)),
		Vector3.new(footprint.X + 3, height, footprint.Z + 3),
		parameters
	)
	local blockers = 0
	for _, candidate in ipairs(results) do
		if candidate ~= floor
			and candidate.CanCollide
			and candidate.Transparency < 0.95
			and getSkyIsland(candidate) == island
		then
			blockers += 1
		end
	end
	return blockers
end

local function findThematicPlacement(root, island, footprint)
	local floor = island and island:FindFirstChild("IslandFloor")
	if not floor or not floor:IsA("BasePart") then
		return nil
	end
	local edgeClearance = math.max(
		2,
		tonumber(MVPConfig.Village.PersonalSkyMerchantStandEdgeClearance) or 4
	)
	local footprintRadius = math.max(footprint.X, footprint.Z) / 2
	local usableX = math.max(0, floor.Size.X / 2 - footprintRadius - edgeClearance)
	local usableZ = math.max(0, floor.Size.Z / 2 - footprintRadius - edgeClearance)
	local localPlayer = floor.CFrame:PointToObjectSpace(root.Position)
	local approach = Vector2.new(localPlayer.X, localPlayer.Z)
	if approach.Magnitude < 0.1 then
		local localLook = floor.CFrame:VectorToObjectSpace(root.CFrame.LookVector)
		approach = -Vector2.new(localLook.X, localLook.Z)
	end
	if approach.Magnitude < 0.1 then
		approach = Vector2.new(0, 1)
	else
		approach = approach.Unit
	end
	local entryInset = math.max(
		2,
		tonumber(MVPConfig.Village.PersonalSkyMerchantPathEntryInset) or 3
	)
	local entryX = math.max(0, floor.Size.X / 2 - entryInset)
	local entryZ = math.max(0, floor.Size.Z / 2 - entryInset)
	local edgeScale = math.huge
	if math.abs(approach.X) > 0.001 then
		edgeScale = math.min(edgeScale, entryX / math.abs(approach.X))
	end
	if math.abs(approach.Y) > 0.001 then
		edgeScale = math.min(edgeScale, entryZ / math.abs(approach.Y))
	end
	if edgeScale == math.huge then
		edgeScale = 0
	end
	local entryLocal = approach * edgeScale
	local side = Vector2.new(-approach.Y, approach.X)
	local pathLength = math.max(
		8,
		tonumber(MVPConfig.Village.PersonalSkyMerchantPathLength) or 13
	)
	local sideOffset = math.max(
		6,
		tonumber(MVPConfig.Village.PersonalSkyMerchantStandSideOffset) or 8,
		footprintRadius * 0.7
	)
	local preferredSide = deterministicSide(island)
	local candidates = {}
	for _, sideSign in ipairs({ preferredSide, -preferredSide }) do
		for _, depthScale in ipairs({ 1, 0.78, 1.2 }) do
			local desired = entryLocal
				- approach * pathLength * depthScale
				+ side * sideOffset * sideSign
			local localPosition = Vector2.new(
				math.clamp(desired.X, -usableX, usableX),
				math.clamp(desired.Y, -usableZ, usableZ)
			)
			local position = floor.CFrame:PointToWorldSpace(Vector3.new(
				localPosition.X,
				floor.Size.Y / 2 + 0.05,
				localPosition.Y
			))
			if surfaceIsSafe(floor, position) then
				local blockerCount = placementBlockerCount(
					island,
					floor,
					position,
					footprint
				)
				local displacement = (localPosition - desired).Magnitude
				local routeSideDistance = math.abs((localPosition - entryLocal):Dot(side))
				local routePenalty = math.max(0, 5 - routeSideDistance) * 3
				table.insert(candidates, {
					Position = position,
					LocalPosition = localPosition,
					BlockerCount = blockerCount,
					Score = blockerCount * 100 + displacement + routePenalty,
					Side = sideSign,
				})
			end
		end
	end
	table.sort(candidates, function(left, right)
		if left.Score ~= right.Score then
			return left.Score < right.Score
		end
		return left.Side == preferredSide and right.Side ~= preferredSide
	end)
	local selected = candidates[1]
	if not selected then
		return nil
	end
	local entryPosition = floor.CFrame:PointToWorldSpace(Vector3.new(
		entryLocal.X,
		floor.Size.Y / 2 + 0.07,
		entryLocal.Y
	))
	return {
		Position = selected.Position,
		EntryPosition = entryPosition,
		Island = island,
		BlockerCount = selected.BlockerCount,
		Side = selected.Side,
	}
end

local function findCurrentIsland(root)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		player.Character,
		activeMerchant,
		activePath,
	}
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = false
	local result = workspace:Raycast(
		root.Position + Vector3.new(0, 4, 0),
		Vector3.new(0, -48, 0),
		raycastParams
	)
	local island = result and getSkyIsland(result.Instance)
	if island then
		return island
	end
	local currentKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
	if currentKey ~= "" then
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("Model")
				and descendant:GetAttribute("IsSkyIsland") == true
				and getIslandKey(descendant) == currentKey
			then
				return descendant
			end
		end
	end
	return nil
end

local function isReservedMerchantTemplate(model)
	local lowerName = string.lower(model.Name)
	return lowerName == "skymechant"
		or lowerName == "skymerchant"
		or model:GetAttribute("ReservedForSkyMerchant") == true
		or model:GetAttribute("ShopId") == "SkyMerchant"
end

local function isVisibleTemplate(model, allowReserved)
	if not model.Archivable
		or Players:GetPlayerFromCharacter(model)
		or (not allowReserved and isReservedMerchantTemplate(model))
	then
		return false
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Transparency < 1
			and descendant.Size.Magnitude > 0.1
		then
			return true
		end
	end
	return false
end

local function findDedicatedMerchantTemplate()
	local assets = ReplicatedStorage:FindFirstChild("PersonalSkyMerchantAssets")
	if assets then
		for _, name in ipairs({ "SkyMerchant", "SkyMechant" }) do
			local candidate = assets:FindFirstChild(name)
			if candidate
				and candidate:IsA("Model")
				and isVisibleTemplate(candidate, true)
			then
				return candidate
			end
		end
		for _, candidate in ipairs(assets:GetChildren()) do
			if candidate:IsA("Model") and isVisibleTemplate(candidate, true) then
				return candidate
			end
		end
	end
	local candidates = {}
	for sourcePriority, source in ipairs({ ReplicatedStorage, workspace }) do
		for _, candidate in ipairs(source:GetDescendants()) do
			if candidate:IsA("Model")
				and candidate ~= activeMerchant
				and isReservedMerchantTemplate(candidate)
				and candidate:GetAttribute("PersonalSkyMerchant") ~= true
				and isVisibleTemplate(candidate, true)
			then
				local lowerName = string.lower(candidate.Name)
				local namePriority = candidate.Name == "SkyMerchant" and 1
					or candidate.Name == "SkyMechant" and 2
					or lowerName == "skymerchant" and 3
					or lowerName == "skymechant" and 4
					or 5
				table.insert(candidates, {
					Model = candidate,
					Priority = sourcePriority * 10 + namePriority,
					Path = candidate:GetFullName(),
				})
			end
		end
	end
	table.sort(candidates, function(left, right)
		if left.Priority ~= right.Priority then
			return left.Priority < right.Priority
		end
		return left.Path < right.Path
	end)
	if candidates[1] then
		return candidates[1].Model
	end
	return nil
end

local function findNearestVillagerTemplate(root)
	local candidates = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("IsVillager") == true
			and isVisibleTemplate(descendant)
		then
			local pivotPosition = descendant:GetPivot().Position
			table.insert(candidates, {
				Model = descendant,
				Distance = (pivotPosition - root.Position).Magnitude,
				Name = descendant:GetFullName(),
			})
		end
	end
	table.sort(candidates, function(left, right)
		if left.Distance ~= right.Distance then
			return left.Distance < right.Distance
		end
		return left.Name < right.Name
	end)
	return candidates[1] and candidates[1].Model or nil
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

local function createFallbackVillager()
	local model = Instance.new("Model")
	model.Name = "SkyMerchantFallback"
	local origin = CFrame.new()
	local torso = part(
		model,
		"HumanoidRootPart",
		Vector3.new(2.5, 3, 1.4),
		Color3.fromRGB(40, 91, 132),
		origin * CFrame.new(0, 3.5, 0)
	)
	part(
		model,
		"Head",
		Vector3.new(1.8, 1.8, 1.8),
		Color3.fromRGB(224, 184, 145),
		origin * CFrame.new(0, 5.8, 0)
	)
	part(
		model,
		"Hat",
		Vector3.new(3.2, 0.45, 3.2),
		Color3.fromRGB(255, 206, 74),
		origin * CFrame.new(0, 6.75, 0)
	)
	part(
		model,
		"LeftArm",
		Vector3.new(0.75, 2.8, 0.75),
		Color3.fromRGB(224, 184, 145),
		origin * CFrame.new(-1.7, 3.6, 0)
	)
	part(
		model,
		"RightArm",
		Vector3.new(0.75, 2.8, 0.75),
		Color3.fromRGB(224, 184, 145),
		origin * CFrame.new(1.7, 3.6, 0)
	)
	part(
		model,
		"LeftLeg",
		Vector3.new(0.9, 2, 1),
		Color3.fromRGB(31, 46, 67),
		origin * CFrame.new(-0.65, 1, 0)
	)
	part(
		model,
		"RightLeg",
		Vector3.new(0.9, 2, 1),
		Color3.fromRGB(31, 46, 67),
		origin * CFrame.new(0.65, 1, 0)
	)
	model.PrimaryPart = torso
	model:SetAttribute("SourceVillagerTemplate", "GeneratedFallback")
	return model
end

local function sanitize(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("BillboardGui")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function alignToSurface(model, position, playerPosition)
	local lookAt = Vector3.new(playerPosition.X, position.Y, playerPosition.Z)
	if (lookAt - position).Magnitude < 0.1 then
		lookAt = position + Vector3.new(0, 0, -1)
	end
	model:PivotTo(CFrame.lookAt(position, lookAt))
	local boxCFrame, boxSize = getVisibleBounds(model)
	if not boxCFrame then
		return nil
	end
	model:PivotTo(model:GetPivot() + Vector3.new(
		position.X - boxCFrame.Position.X,
		position.Y - (boxCFrame.Position.Y - boxSize.Y / 2),
		position.Z - boxCFrame.Position.Z
	))
	boxCFrame, boxSize = getVisibleBounds(model)
	local forward = Vector3.new(lookAt.X - position.X, 0, lookAt.Z - position.Z)
	if forward.Magnitude < 0.1 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local frontDepth = math.abs(forward.X) * boxSize.X / 2
		+ math.abs(forward.Z) * boxSize.Z / 2
	return {
		BoundsCFrame = boxCFrame,
		BoundsSize = boxSize,
		InteractionPosition = Vector3.new(position.X, position.Y + 2.3, position.Z)
			+ forward * (frontDepth + 1.8),
	}
end

local function createPathPart(parent, name, size, color, material, cframe, transparency)
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.Color = color
	value.Material = material
	value.Transparency = transparency or 0
	value.CFrame = cframe
	value.Anchored = true
	value.CanCollide = false
	value.CanTouch = false
	value.CanQuery = false
	value.CastShadow = false
	value.Parent = parent
	return value
end

local function createThematicPath(placement, interactionPosition, footprint)
	local scene = Instance.new("Model")
	scene.Name = PATH_NAME
	scene:SetAttribute("PersonalSkyMerchantPath", true)
	scene:SetAttribute("OwnerUserId", player.UserId)

	local startPosition = placement.EntryPosition
	local finishPosition = Vector3.new(
		interactionPosition.X,
		startPosition.Y,
		interactionPosition.Z
	)
	local pathVector = finishPosition - startPosition
	local pathLength = pathVector.Magnitude
	if pathLength > 2 then
		local pathWidth = math.max(
			2.4,
			tonumber(MVPConfig.Village.PersonalSkyMerchantPathWidth) or 3.2
		)
		local paverCount = math.clamp(math.floor(pathLength / 2.7), 4, 10)
		for index = 1, paverCount do
			local alpha = index / (paverCount + 1)
			local position = startPosition:Lerp(finishPosition, alpha)
			local nextPosition = startPosition:Lerp(
				finishPosition,
				math.min(1, alpha + 0.05)
			)
			local facing = CFrame.lookAt(
				position + Vector3.new(0, 0.07, 0),
				nextPosition + Vector3.new(0, 0.07, 0)
			)
			createPathPart(
				scene,
				"CelestialPaver",
				Vector3.new(pathWidth, 0.14, 1.75),
				Color3.fromRGB(32, 60, 104),
				Enum.Material.Slate,
				facing,
				0.05
			)
			createPathPart(
				scene,
				"GoldenRune",
				Vector3.new(pathWidth * 0.58, 0.035, 0.22),
				Color3.fromRGB(255, 205, 82),
				Enum.Material.Neon,
				facing + Vector3.new(0, 0.09, 0),
				0.12
			)
		end
	end

	local platformDiameter = math.clamp(
		math.max(footprint.X, footprint.Z) + 2,
		6,
		18
	)
	createPathPart(
		scene,
		"MerchantSigil",
		Vector3.new(0.12, platformDiameter, platformDiameter),
		Color3.fromRGB(74, 166, 255),
		Enum.Material.Glass,
		CFrame.new(placement.Position + Vector3.new(0, 0.025, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		0.68
	)
	createPathPart(
		scene,
		"MerchantSigilCore",
		Vector3.new(0.06, platformDiameter * 0.68, platformDiameter * 0.68),
		Color3.fromRGB(255, 208, 86),
		Enum.Material.Neon,
		CFrame.new(placement.Position + Vector3.new(0, 0.09, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		0.84
	)

	if pathLength > 4 then
		local forward = pathVector.Unit
		local right = Vector3.new(-forward.Z, 0, forward.X)
		for _, sideSign in ipairs({ -1, 1 }) do
			local basePosition = finishPosition
				- forward * 1.4
				+ right * sideSign * 2.4
			createPathPart(
				scene,
				"GoldenMarker",
				Vector3.new(0.18, 1.35, 0.18),
				Color3.fromRGB(255, 203, 73),
				Enum.Material.Metal,
				CFrame.new(basePosition + Vector3.new(0, 0.7, 0)),
				0.08
			)
			local crystal = createPathPart(
				scene,
				"CelestialLight",
				Vector3.new(0.55, 0.55, 0.55),
				Color3.fromRGB(92, 210, 255),
				Enum.Material.Neon,
				CFrame.new(basePosition + Vector3.new(0, 1.55, 0)),
				0.05
			)
			crystal.Shape = Enum.PartType.Ball
		end
	end

	scene.Parent = workspace
	return scene
end

local function addPresentation(model, alignment)
	if not alignment then
		return nil
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Highlight")
			and descendant.Name == "PersonalMerchantHighlight"
		then
			descendant:Destroy()
		end
	end
	local root = Instance.new("Part")
	root.Name = "MerchantInteractionAnchor"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(alignment.InteractionPosition)
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model

	local highlight = Instance.new("Highlight")
	highlight.Name = "PersonalMerchantHighlight"
	-- Preserve the original colors and materials of the complete merchant stand.
	-- A colored fill affects every descendant, including weapons and mystic props.
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 213, 88)
	highlight.OutlineTransparency = 0.22
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PersonalMerchantLabel"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(240, 62)
	local labelHeight = math.max(
		3.8,
		alignment.BoundsCFrame.Position.Y
			+ alignment.BoundsSize.Y / 2
			- root.Position.Y
			+ 1.6
	)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, labelHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 31, 48)
	label.BackgroundTransparency = 0.12
	label.Text = "MERCADOR DO CEU\nTenho algo para a sua jornada"
	label.TextColor3 = Color3.fromRGB(255, 220, 105)
	label.TextStrokeTransparency = 0.45
	label.TextWrapped = true
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PersonalSkyMerchantPrompt"
	prompt.ActionText = "Ver recomendacoes"
	prompt.ObjectText = "Mercador do Ceu"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MVPConfig.Village.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	-- O Mercador pessoal nao deve perder o E para um bau, aliado caido ou
	-- outro prompt proximo. Ele existe somente neste cliente.
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Parent = root
	return prompt
end

local function presentationSeconds()
	return math.max(
		0.25,
		tonumber(MVPConfig.Village.PersonalSkyMerchantPromptPresentationSeconds) or 1.5
	)
end

local function beginOfferIfNeeded()
	local serial = math.max(
		0,
		math.floor(tonumber(player:GetAttribute("MerchantOffersShown")) or 0)
	)
	if activeOfferSerial == serial then
		return
	end
	activeOfferSerial = serial
	encounterState = "Unseen"
	encounterIsland = nil
	relocationCount = 0
	promptVisibleSince = nil
	nearbySince = nil
	farAwaySince = nil
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	player:SetAttribute("PersonalSkyMerchantRelocationCount", relocationCount)
end

local function syncEncounterState()
	if encounterReportInFlight then
		return
	end
	local serverState = player:GetAttribute("PersonalSkyMerchantEncounterState")
	if type(serverState) == "string" and serverState ~= "" then
		encounterState = serverState
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	end
end

local function reportEncounter(outcome)
	if encounterReportInFlight
		or activeOfferSerial == nil
		or player:GetAttribute("MerchantOfferReady") ~= true
	then
		return false
	end
	if outcome == "Presented" and encounterState ~= "Unseen" then
		return false
	end
	if outcome == "Ignored" and encounterState ~= "Presented" then
		return false
	end

	local previousState = encounterState
	local reportedOfferSerial = activeOfferSerial
	encounterState = outcome
	encounterReportInFlight = true
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", outcome)
	task.spawn(function()
		local success, result = pcall(
			request.InvokeServer,
			request,
			"PersonalMerchantEncounter",
			{
				Outcome = outcome,
				OfferSerial = reportedOfferSerial,
			}
		)
		encounterReportInFlight = false
		if success and type(result) == "table" and type(result.State) == "string" then
			encounterState = result.State
		elseif not success or type(result) ~= "table" or result.Success ~= true then
			encounterState = previousState
		end
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	end)
	return true
end

local function removeMerchant(state)
	if activeMerchant then
		activeMerchant:Destroy()
	end
	if activePath then
		activePath:Destroy()
	end
	activeMerchant = nil
	activePrompt = nil
	activePath = nil
	activeIsland = nil
	activeIslandKey = nil
	activePlacementMode = nil
	promptVisibleSince = nil
	nearbySince = nil
	farAwaySince = nil
	player:SetAttribute("PersonalSkyMerchantClientState", state or "Hidden")
end

local function openMerchant()
	if not activePrompt or openRequestInFlight then
		return
	end
	openRequestInFlight = true
	player:SetAttribute("PersonalSkyMerchantClientState", "Opening")
	player:SetAttribute("PersonalSkyMerchantLastOpenError", nil)
	activePrompt.Enabled = false
	local success, result = pcall(
		request.InvokeServer,
		request,
		"ActivatePersonalMerchant"
	)
	openRequestInFlight = false
	if activePrompt and activePrompt.Parent then
		activePrompt.Enabled = true
	end
	if success and type(result) == "table" and result.Success == true then
		encounterState = "Opened"
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
		player:SetAttribute("PersonalSkyMerchantClientState", "OpenAccepted")
		-- Fallback local. O servidor tambem envia OpenPersonalMerchant pela
		-- MonetizationEvent, eliminando a dependencia deste BindableEvent.
		openEvent:Fire(result.Store)
	else
		local message = type(result) == "table" and result.Message or result
		player:SetAttribute("PersonalSkyMerchantLastOpenError", tostring(message))
		player:SetAttribute(
			"PersonalSkyMerchantClientState",
			"OpenRejected:" .. tostring(message)
		)
	end
end

local function spawnMerchant(intendedIsland)
	local root = getLivingRoot()
	if not root then
		player:SetAttribute("PersonalSkyMerchantClientState", "WaitingForCharacter")
		return false
	end
	local template = findDedicatedMerchantTemplate() or findNearestVillagerTemplate(root)
	local model
	if template then
		local cloned, result = pcall(template.Clone, template)
		if cloned and result and result:IsA("Model") then
			model = result
			model:SetAttribute("SourceVillagerTemplate", template:GetFullName())
		end
	end
	model = model or createFallbackVillager()
	sanitize(model)
	local _, visibleSize = getVisibleBounds(model)
	if not visibleSize then
		model:Destroy()
		player:SetAttribute("PersonalSkyMerchantClientState", "InvalidVisibleModel")
		return false
	end
	local footprint = Vector3.new(
		math.max(4, visibleSize.X),
		math.max(5, visibleSize.Y),
		math.max(4, visibleSize.Z)
	)
	local placement
	local placementMode
	if intendedIsland then
		placement = findThematicPlacement(root, intendedIsland, footprint)
		placementMode = "TravelIntentThematicStand"
	end
	if not placement then
		local currentIsland = findCurrentIsland(root)
		placement = findThematicPlacement(root, currentIsland, footprint)
		placementMode = "CurrentIslandThematicFallback"
	end
	if not placement then
		model:Destroy()
		player:SetAttribute("PersonalSkyMerchantClientState", "WaitingForStandArea")
		return false
	end
	local spawnIsland = placement.Island
	model.Name = MERCHANT_NAME
	model:SetAttribute("PersonalSkyMerchant", true)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("SpawnIslandKey", getIslandKey(spawnIsland))
	model:SetAttribute("PlacementMode", placementMode)
	model:SetAttribute(
		"RecommendedProductIds",
		tostring(player:GetAttribute("MerchantRecommendedProductIds") or "")
	)
	model:SetAttribute("ThematicStand", true)
	model:SetAttribute("PlacementBlockerCount", placement.BlockerCount)
	model:SetAttribute(
		"VisualFootprint",
		string.format("%.1fx%.1f", footprint.X, footprint.Z)
	)
	local alignment = alignToSurface(
		model,
		placement.Position,
		placement.EntryPosition
	)
	local prompt = addPresentation(model, alignment)
	if not prompt then
		model:Destroy()
		player:SetAttribute("PersonalSkyMerchantClientState", "InvalidVillagerModel")
		return false
	end
	model.Parent = workspace
	local path = createThematicPath(
		placement,
		alignment.InteractionPosition,
		footprint
	)
	activeMerchant = model
	activePrompt = prompt
	activePath = path
	activeIsland = spawnIsland
	activeIslandKey = getIslandKey(spawnIsland)
	activePlacementMode = placementMode
	encounterIsland = spawnIsland
	promptVisibleSince = nil
	nearbySince = nil
	farAwaySince = nil
	prompt.PromptShown:Connect(function()
		local shownAt = workspace:GetServerTimeNow()
		promptVisibleSince = shownAt
		player:SetAttribute("PersonalSkyMerchantPromptState", "Visible")
		task.delay(presentationSeconds(), function()
			if activePrompt == prompt
				and promptVisibleSince == shownAt
				and encounterState == "Unseen"
			then
				reportEncounter("Presented")
			end
		end)
	end)
	prompt.PromptHidden:Connect(function()
		promptVisibleSince = nil
		player:SetAttribute("PersonalSkyMerchantPromptState", "Hidden")
	end)
	prompt.Triggered:Connect(openMerchant)
	player:SetAttribute("PersonalSkyMerchantClientState", "Spawned")
	player:SetAttribute(
		"PersonalSkyMerchantClientVersion",
		"EncounterMemoryV10"
	)
	player:SetAttribute("PersonalSkyMerchantColorTreatment", "OriginalAssetColors")
	player:SetAttribute("PersonalSkyMerchantPlacementMode", placementMode)
	player:SetAttribute("PersonalSkyMerchantSpawnIslandKey", activeIslandKey)
	player:SetAttribute(
		"PersonalSkyMerchantPlacementQuality",
		placement.BlockerCount == 0 and "Clear" or "BestAvailable"
	)
	player:SetAttribute("PersonalSkyMerchantPathState", path and "Created" or "Unavailable")
	player:SetAttribute("PersonalSkyMerchantRelocationCount", relocationCount)
	return true
end

local function update()
	updateQueued = false
	if player:GetAttribute("MerchantOfferReady") ~= true then
		offerReadyObservedAt = nil
		activeOfferSerial = nil
		encounterState = "Inactive"
		encounterIsland = nil
		relocationCount = 0
		removeMerchant("WaitingForRecommendation")
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
		return
	end
	beginOfferIfNeeded()
	syncEncounterState()
	if encounterState == "Ignored"
		or encounterState == "Dismissed"
		or encounterState == "Purchased"
	then
		removeMerchant("EncounterEnded:" .. encounterState)
		return
	end
	if not offerReadyObservedAt then
		offerReadyObservedAt = workspace:GetServerTimeNow()
	end
	local root = getLivingRoot()
	if not root then
		removeMerchant("WaitingForCharacter")
		return
	end
	local intendedIsland = getIntendedIsland()
	local intendedKey = getIslandKey(intendedIsland)
	if activeMerchant and activeMerchant.Parent then
		-- Nao remova nem reposicione o NPC enquanto o jogador estiver lendo
		-- ou comprando uma das ofertas.
		if player:GetAttribute("ShopOpen") == true
			and player:GetAttribute("ActiveShopId") == "SkyMerchant"
		then
			encounterState = "Opened"
			player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
			activeMerchant:SetAttribute(
				"RecommendedProductIds",
				tostring(player:GetAttribute("MerchantRecommendedProductIds") or "")
			)
			return
		end
		-- Se o NPC nasceu pelo fallback enquanto o jogador ainda escolhia a rota,
		-- transfere-o para a ilha de intencao antes que ele seja apresentado.
		if intendedIsland
			and intendedKey ~= activeIslandKey
			and activePlacementMode == "CurrentIslandThematicFallback"
			and encounterState == "Unseen"
			and relocationCount < math.max(
				0,
				math.floor(
					tonumber(MVPConfig.Village.PersonalSkyMerchantMaximumRelocations) or 1
				)
			)
		then
			removeMerchant("MovingAheadOfPlayer")
			relocationCount += 1
			player:SetAttribute("PersonalSkyMerchantRelocationCount", relocationCount)
			spawnMerchant(intendedIsland)
			return
		end
		local currentIslandKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
		local interactionAnchor = activeMerchant:FindFirstChild(
			"MerchantInteractionAnchor",
			true
		)
		local merchantPosition = interactionAnchor
			and interactionAnchor:IsA("BasePart")
			and interactionAnchor.Position
			or activeMerchant:GetPivot().Position
		local merchantDistance = (merchantPosition - root.Position).Magnitude

		if encounterState == "Unseen" then
			local nearbyDistance = math.max(
				MVPConfig.Village.PromptDistance,
				tonumber(MVPConfig.Village.PersonalSkyMerchantNearbyPresentationDistance) or 28
			)
			if currentIslandKey ~= ""
				and currentIslandKey == activeIslandKey
				and merchantDistance <= nearbyDistance
			then
				nearbySince = nearbySince or workspace:GetServerTimeNow()
				local nearbySeconds = math.max(
					0.5,
					tonumber(MVPConfig.Village.PersonalSkyMerchantNearbyPresentationSeconds) or 4
				)
				if workspace:GetServerTimeNow() - nearbySince >= nearbySeconds then
					reportEncounter("Presented")
				end
			else
				nearbySince = nil
			end
		end

		if encounterState == "Presented" then
			if currentIslandKey ~= ""
				and activeIslandKey ~= ""
				and currentIslandKey ~= activeIslandKey
			then
				reportEncounter("Ignored")
				removeMerchant("IgnoredOnAnotherIsland")
				return
			end
			local ignoreDistance = math.max(
				MVPConfig.Village.PromptDistance + 1,
				tonumber(MVPConfig.Village.PersonalSkyMerchantIgnoreDistance) or 65
			)
			if merchantDistance > ignoreDistance then
				farAwaySince = farAwaySince or workspace:GetServerTimeNow()
				local ignoreSeconds = math.max(
					0.5,
					tonumber(MVPConfig.Village.PersonalSkyMerchantIgnoreSeconds) or 3
				)
				if workspace:GetServerTimeNow() - farAwaySince >= ignoreSeconds then
					reportEncounter("Ignored")
					removeMerchant("IgnoredByDistance")
					return
				end
			else
				farAwaySince = nil
			end
		end

		if activeIsland
			and activeIsland:IsDescendantOf(workspace)
			and (activeIslandKey == intendedKey or activeIslandKey == currentIslandKey)
		then
			activeMerchant:SetAttribute(
				"RecommendedProductIds",
				tostring(player:GetAttribute("MerchantRecommendedProductIds") or "")
			)
			return
		end
		local relocateDistance = math.max(
			20,
			tonumber(MVPConfig.Village.PersonalSkyMerchantRelocateDistance) or 55
		)
		if merchantDistance <= relocateDistance then
			activeMerchant:SetAttribute(
				"RecommendedProductIds",
				tostring(player:GetAttribute("MerchantRecommendedProductIds") or "")
			)
			return
		end
		local maximumRelocations = math.max(
			0,
			math.floor(
				tonumber(MVPConfig.Village.PersonalSkyMerchantMaximumRelocations) or 1
			)
		)
		if encounterState ~= "Unseen"
			or relocationCount >= maximumRelocations
			or not intendedIsland
		then
			-- O encontro fica preso a esta ilha. Afastar-se depois de ver o
			-- Mercador encerra a oferta; antes disso, ele nao persegue para sempre.
			return
		end
		removeMerchant("RelocatingOnce")
		relocationCount += 1
		player:SetAttribute("PersonalSkyMerchantRelocationCount", relocationCount)
		spawnMerchant(intendedIsland)
		return
	end
	if encounterIsland
		and encounterIsland:IsDescendantOf(workspace)
		and encounterIsland:GetAttribute("IsSkyIsland") == true
	then
		spawnMerchant(encounterIsland)
		return
	end
	if intendedIsland then
		spawnMerchant(intendedIsland)
		return
	end
	local intentWaitSeconds = math.max(
		0,
		tonumber(MVPConfig.Village.PersonalSkyMerchantIntentWaitSeconds) or 10
	)
	if workspace:GetServerTimeNow() - offerReadyObservedAt < intentWaitSeconds then
		player:SetAttribute("PersonalSkyMerchantClientState", "WaitingForTravelIntent")
		return
	end
	spawnMerchant(nil)
end

local function queueUpdate()
	if updateQueued then
		return
	end
	updateQueued = true
	task.defer(update)
end

local old = workspace:FindFirstChild(MERCHANT_NAME)
if old then
	old:Destroy()
end
local oldPath = workspace:FindFirstChild(PATH_NAME)
if oldPath then
	oldPath:Destroy()
end

player:GetAttributeChangedSignal("MerchantOfferReady"):Connect(queueUpdate)
player:GetAttributeChangedSignal("MerchantOffersShown"):Connect(queueUpdate)
player:GetAttributeChangedSignal("MerchantRecommendedProductIds"):Connect(queueUpdate)
player:GetAttributeChangedSignal("PersonalSkyMerchantEncounterState"):Connect(queueUpdate)
player:GetAttributeChangedSignal("WorldIntentTargetIslandKey"):Connect(queueUpdate)
player:GetAttributeChangedSignal("CurrentIslandKey"):Connect(queueUpdate)
player.CharacterAdded:Connect(function()
	removeMerchant("CharacterRespawning")
	task.delay(1, queueUpdate)
end)
monetizationEvent.OnClientEvent:Connect(function(data)
	if type(data) == "table"
		and (
			data.Action == "OfferReady"
			or data.Action == "OfferEnded"
			or data.Action == "PurchaseGranted"
			or data.Action == "Entitlements"
		)
	then
		queueUpdate()
	end
end)

task.spawn(function()
	while true do
		task.wait(CHECK_SECONDS)
		queueUpdate()
	end
end)

queueUpdate()
