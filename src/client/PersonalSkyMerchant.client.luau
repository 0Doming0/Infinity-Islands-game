-- Mercador do Ceu encontrado em uma ilha futura.
--
-- O servidor escolhe uma unica ilha ainda nao visitada a partir da intencao de
-- rota publicada pelo gerador. Este cliente apenas cria a cena nessa ilha.
-- Nao existe fallback na ilha atual, perseguicao ou teleporte entre rotas.
-- A loja inteira e estatica: preserva a rotacao criada no asset, nao olha para
-- o jogador, nao executa animacoes e nao se desloca em relacao a ilha.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local request = ReplicatedStorage:WaitForChild("MonetizationRequest")
local monetizationEvent = ReplicatedStorage:WaitForChild("MonetizationEvent")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local TARGET_VALUE_NAME = "PersonalSkyMerchantTargetIsland"
local SCENE_NAME = "PersonalSkyMerchantScene_" .. tostring(player.UserId)
local CHECK_SECONDS = 0.75
local VERSION = "FutureNormalIslandOffersVisibleV4"

local activeScene
local activeMerchant
local activePrompt
local activeInteractionHint
local activeIsland
local activeIslandKey
local activeOfferSerial
local activeStaticRelativePivot
local encounterState = "Inactive"
local promptVisibleSince
local nearbySince
local awaySince
local updateQueued = false
local openRequestInFlight = false
local encounterReportInFlight = false

-- Nao mantemos uma referencia fixa ao BindableEvent. Dois LocalScripts podem
-- inicializar no mesmo frame e criar eventos homonimos diferentes. Na abertura,
-- todas as instancias validas sao notificadas e a UI confirma que abriu.

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

local function getIslandKey(island)
	return island and tostring(island:GetAttribute("IslandNodeKey") or "") or ""
end

local function isVillageOrSanctuary(island)
	if not island or not island:IsA("Model") then
		return true
	end
	if island:GetAttribute("VillageSpawned") == true
		or island:GetAttribute("IsSocialSanctuary") == true
	then
		return true
	end
	local role = string.lower(tostring(island:GetAttribute("IslandRole") or ""))
	if string.find(role, "sanctuary", 1, true)
		or string.find(role, "village", 1, true)
	then
		return true
	end
	local village = island:FindFirstChild("MVPVillage")
	if village
		and (
			village:GetAttribute("ProceduralVillage") == true
			or village:IsA("Folder")
		)
	then
		return true
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:GetAttribute("ProceduralVillage") == true then
			return true
		end
	end
	return false
end

local function isNormalMerchantIsland(island)
	return island
		and island:IsA("Model")
		and island:IsDescendantOf(workspace)
		and island:GetAttribute("IsSkyIsland") == true
		and tostring(island:GetAttribute("IslandType") or "Normal") == "Normal"
		and not isVillageOrSanctuary(island)
end

local function resolveAssignedIsland()
	local key = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
	if key == "" then
		return nil
	end
	local value = player:FindFirstChild(TARGET_VALUE_NAME)
	local island = value and value:IsA("ObjectValue") and value.Value or nil
	if isNormalMerchantIsland(island)
		and getIslandKey(island) == key
	then
		return island
	end
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if isNormalMerchantIsland(descendant)
			and getIslandKey(descendant) == key
		then
			return descendant
		end
	end
	return nil
end

local function surfaceIsSafe(island, floor)
	if not island or not floor or not floor:IsA("BasePart") then
		return false
	end
	local water = workspace:FindFirstChild("Water")
	local surfaceY = water and tonumber(water:GetAttribute("SurfaceY"))
	return not surfaceY or floor.Position.Y + floor.Size.Y / 2 > surfaceY + 3
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

local function deterministicSide(island)
	local value = player.UserId
	local key = getIslandKey(island)
	for index = 1, #key do
		value += string.byte(key, index) * index
	end
	return value % 2 == 0 and 1 or -1
end

local function blockerCount(island, floor, position, footprint)
	local parameters = OverlapParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { player.Character, activeScene }
	parameters.RespectCanCollide = false
	local results = workspace:GetPartBoundsInBox(
		CFrame.new(position + Vector3.new(0, footprint.Y / 2 + 0.2, 0)),
		Vector3.new(footprint.X + 3, math.max(6, footprint.Y), footprint.Z + 3),
		parameters
	)
	local count = 0
	for _, part in ipairs(results) do
		if part ~= floor
			and part.CanCollide
			and part.Transparency < 0.95
			and getSkyIsland(part) == island
		then
			count += 1
		end
	end
	return count
end

local function findPlacement(root, island, footprint)
	local floor = island and island:FindFirstChild("IslandFloor")
	if not floor or not floor:IsA("BasePart") or not surfaceIsSafe(island, floor) then
		return nil
	end
	local edgeClearance = math.max(2, tonumber(MVPConfig.Village.PersonalSkyMerchantStandEdgeClearance) or 4)
	local radius = math.max(footprint.X, footprint.Z) / 2
	local usableX = math.max(0, floor.Size.X / 2 - radius - edgeClearance)
	local usableZ = math.max(0, floor.Size.Z / 2 - radius - edgeClearance)
	local localPlayer = floor.CFrame:PointToObjectSpace(root.Position)
	local approach = Vector2.new(localPlayer.X, localPlayer.Z)
	if approach.Magnitude < 0.1 then
		local seedSide = deterministicSide(island)
		approach = Vector2.new(seedSide, 1).Unit
	else
		approach = approach.Unit
	end
	local entryInset = math.max(2, tonumber(MVPConfig.Village.PersonalSkyMerchantPathEntryInset) or 3)
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
	local pathLength = math.max(8, tonumber(MVPConfig.Village.PersonalSkyMerchantPathLength) or 13)
	local sideOffset = math.max(
		6,
		tonumber(MVPConfig.Village.PersonalSkyMerchantStandSideOffset) or 8,
		radius * 0.7
	)
	local preferredSide = deterministicSide(island)
	local candidates = {}
	for _, sideSign in ipairs({ preferredSide, -preferredSide }) do
		for _, depthScale in ipairs({ 1, 0.78, 1.18 }) do
			local desired = entryLocal - approach * pathLength * depthScale + side * sideOffset * sideSign
			local localPosition = Vector2.new(
				math.clamp(desired.X, -usableX, usableX),
				math.clamp(desired.Y, -usableZ, usableZ)
			)
			local position = floor.CFrame:PointToWorldSpace(Vector3.new(
				localPosition.X,
				floor.Size.Y / 2 + 0.05,
				localPosition.Y
			))
			local blocked = blockerCount(island, floor, position, footprint)
			table.insert(candidates, {
				Position = position,
				Blocked = blocked,
				Score = blocked * 100 + (localPosition - desired).Magnitude,
				Side = sideSign,
			})
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
	return {
		Island = island,
		Floor = floor,
		Position = selected.Position,
		EntryPosition = floor.CFrame:PointToWorldSpace(Vector3.new(
			entryLocal.X,
			floor.Size.Y / 2 + 0.07,
			entryLocal.Y
		)),
		BlockerCount = selected.Blocked,
	}
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

local function findTemplate(root)
	local assets = ReplicatedStorage:FindFirstChild("PersonalSkyMerchantAssets")
	if assets then
		for _, name in ipairs({ "SkyMerchant", "SkyMechant" }) do
			local candidate = assets:FindFirstChild(name)
			if candidate and candidate:IsA("Model") and isVisibleTemplate(candidate, true) then
				return candidate
			end
		end
	end
	local dedicated = {}
	for sourcePriority, source in ipairs({ ReplicatedStorage, workspace }) do
		for _, candidate in ipairs(source:GetDescendants()) do
			if candidate:IsA("Model")
				and candidate ~= activeMerchant
				and candidate:GetAttribute("PersonalSkyMerchant") ~= true
				and isReservedMerchantTemplate(candidate)
				and isVisibleTemplate(candidate, true)
			then
				table.insert(dedicated, {
					Model = candidate,
					Priority = sourcePriority,
					Path = candidate:GetFullName(),
				})
			end
		end
	end
	table.sort(dedicated, function(left, right)
		if left.Priority ~= right.Priority then
			return left.Priority < right.Priority
		end
		return left.Path < right.Path
	end)
	if dedicated[1] then
		return dedicated[1].Model
	end
	local nearest
	local nearestDistance = math.huge
	for _, candidate in ipairs(workspace:GetDescendants()) do
		if candidate:IsA("Model")
			and candidate:GetAttribute("IsVillager") == true
			and isVisibleTemplate(candidate, false)
		then
			local distance = (candidate:GetPivot().Position - root.Position).Magnitude
			if distance < nearestDistance then
				nearest = candidate
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function createPart(parent, name, size, color, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = parent
	return part
end

local function createFallbackMerchant()
	local model = Instance.new("Model")
	model.Name = "SkyMerchantFallback"
	local torso = createPart(model, "HumanoidRootPart", Vector3.new(2.5, 3, 1.4), Color3.fromRGB(40, 91, 132), CFrame.new(0, 3.5, 0))
	createPart(model, "Head", Vector3.new(1.8, 1.8, 1.8), Color3.fromRGB(224, 184, 145), CFrame.new(0, 5.8, 0))
	createPart(model, "Hat", Vector3.new(3.2, 0.45, 3.2), Color3.fromRGB(255, 206, 74), CFrame.new(0, 6.75, 0))
	createPart(model, "LeftArm", Vector3.new(0.75, 2.8, 0.75), Color3.fromRGB(224, 184, 145), CFrame.new(-1.7, 3.6, 0))
	createPart(model, "RightArm", Vector3.new(0.75, 2.8, 0.75), Color3.fromRGB(224, 184, 145), CFrame.new(1.7, 3.6, 0))
	createPart(model, "LeftLeg", Vector3.new(0.9, 2, 1), Color3.fromRGB(31, 46, 67), CFrame.new(-0.65, 1, 0))
	createPart(model, "RightLeg", Vector3.new(0.9, 2, 1), Color3.fromRGB(31, 46, 67), CFrame.new(0.65, 1, 0))
	model.PrimaryPart = torso
	model:SetAttribute("SourceVillagerTemplate", "GeneratedFallback")
	return model
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
			pcall(function()
				for _, track in ipairs(descendant:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
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

local function alignToSurface(model, position, _entryPosition)
	-- Apenas translada a loja. A orientacao original criada no asset e mantida;
	-- ela nunca gira para acompanhar, encarar ou seguir o jogador.
	local originalPivot = model:GetPivot()
	local boxCFrame, boxSize = getVisibleBounds(model)
	if not boxCFrame then
		return nil
	end
	local translation = Vector3.new(
		position.X - boxCFrame.Position.X,
		position.Y - (boxCFrame.Position.Y - boxSize.Y / 2),
		position.Z - boxCFrame.Position.Z
	)
	model:PivotTo(originalPivot + translation)
	boxCFrame, boxSize = getVisibleBounds(model)
	-- O ponto de interacao fica do lado da trilha/entrada, mas a loja nao gira.
	local routeDirection = Vector3.new(
		_entryPosition.X - boxCFrame.Position.X,
		0,
		_entryPosition.Z - boxCFrame.Position.Z
	)
	local forward = routeDirection.Magnitude < 0.1
		and Vector3.new(0, 0, -1)
		or routeDirection.Unit
	local frontDepth = math.abs(forward.X) * boxSize.X / 2
		+ math.abs(forward.Z) * boxSize.Z / 2
	return {
		BoundsCFrame = boxCFrame,
		BoundsSize = boxSize,
		InteractionPosition = Vector3.new(
			boxCFrame.Position.X,
			position.Y + math.clamp(boxSize.Y * 0.35, 2, 3.5),
			boxCFrame.Position.Z
		) + forward * (frontDepth + 1.25),
	}
end

local function createPathPart(parent, name, size, color, material, cframe, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function createDiscoveryPath(scene, placement, interactionPosition, footprint)
	local startPosition = placement.EntryPosition
	local finishPosition = Vector3.new(interactionPosition.X, startPosition.Y, interactionPosition.Z)
	local pathVector = finishPosition - startPosition
	local pathLength = pathVector.Magnitude
	if pathLength > 2 then
		local width = math.max(2.4, tonumber(MVPConfig.Village.PersonalSkyMerchantPathWidth) or 3.2)
		local count = math.clamp(math.floor(pathLength / 2.7), 4, 10)
		for index = 1, count do
			local alpha = index / (count + 1)
			local position = startPosition:Lerp(finishPosition, alpha)
			local nextPosition = startPosition:Lerp(finishPosition, math.min(1, alpha + 0.05))
			local facing = CFrame.lookAt(position + Vector3.new(0, 0.07, 0), nextPosition + Vector3.new(0, 0.07, 0))
			createPathPart(scene, "CelestialPaver", Vector3.new(width, 0.14, 1.75), Color3.fromRGB(32, 60, 104), Enum.Material.Slate, facing, 0.05)
			createPathPart(scene, "GoldenRune", Vector3.new(width * 0.58, 0.035, 0.22), Color3.fromRGB(255, 205, 82), Enum.Material.Neon, facing + Vector3.new(0, 0.09, 0), 0.12)
		end
	end
	local diameter = math.clamp(math.max(footprint.X, footprint.Z) + 2, 6, 18)
	createPathPart(
		scene,
		"MerchantSigil",
		Vector3.new(0.12, diameter, diameter),
		Color3.fromRGB(74, 166, 255),
		Enum.Material.Glass,
		CFrame.new(placement.Position + Vector3.new(0, 0.025, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		0.68
	)
end

local function addPresentation(model, alignment)
	local promptDistance = math.max(
		10,
		tonumber(MVPConfig.Village.PromptDistance) or 13
	)

	local anchor = Instance.new("Part")
	anchor.Name = "MerchantInteractionAnchor"
	anchor.Size = Vector3.new(3, 4, 3)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(alignment.InteractionPosition)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	-- O ProximityPrompt usa esta peca para deteccao espacial. CanQuery=false
	-- podia impedir o UI/tecla E de ser considerado em alguns clientes.
	anchor.CanQuery = true
	anchor.Parent = model

	local attachment = Instance.new("Attachment")
	attachment.Name = "MerchantInteractionAttachment"
	attachment.Parent = anchor

	local highlight = Instance.new("Highlight")
	highlight.Name = "PersonalMerchantHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 213, 88)
	highlight.OutlineTransparency = 0.22
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PersonalMerchantLabel"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(220, 48)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, math.max(4, alignment.BoundsSize.Y + 1), 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 31, 48)
	label.BackgroundTransparency = 0.12
	label.Text = "MERCADOR DO CEU"
	label.TextColor3 = Color3.fromRGB(255, 220, 105)
	label.TextStrokeTransparency = 0.45
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)

	-- UI local controlado pelo proprio sistema. Ele nao depende do renderer
	-- padrao do ProximityPrompt e, portanto, aparece mesmo quando outro script
	-- da experiencia personaliza/oculta prompts globais.
	local hint = Instance.new("BillboardGui")
	hint.Name = "PersonalMerchantInteractionHint"
	hint.Adornee = anchor
	hint.Size = UDim2.fromOffset(250, 64)
	hint.StudsOffsetWorldSpace = Vector3.new(0, 0.6, 0)
	hint.AlwaysOnTop = true
	hint.MaxDistance = promptDistance + 6
	hint.Enabled = false
	hint.Active = true
	hint.Parent = model

	local hintButton = Instance.new("TextButton")
	hintButton.Name = "InteractButton"
	hintButton.Size = UDim2.fromScale(1, 1)
	hintButton.BackgroundColor3 = Color3.fromRGB(13, 25, 40)
	hintButton.BackgroundTransparency = 0.08
	hintButton.BorderSizePixel = 0
	hintButton.AutoButtonColor = true
	hintButton.Text = ""
	hintButton.Parent = hint
	Instance.new("UICorner", hintButton).CornerRadius = UDim.new(0, 12)
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = Color3.fromRGB(255, 210, 86)
	hintStroke.Transparency = 0.22
	hintStroke.Thickness = 1.5
	hintStroke.Parent = hintButton

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.Position = UDim2.new(0, 10, 0.5, 0)
	key.Size = UDim2.fromOffset(42, 42)
	key.BackgroundColor3 = Color3.fromRGB(255, 211, 88)
	key.BorderSizePixel = 0
	key.Text = "E"
	key.TextColor3 = Color3.fromRGB(21, 27, 35)
	key.Font = Enum.Font.GothamBlack
	key.TextSize = 22
	key.Parent = hintButton
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 9)

	local hintText = Instance.new("TextLabel")
	hintText.Name = "Action"
	hintText.Position = UDim2.fromOffset(62, 0)
	hintText.Size = UDim2.new(1, -72, 1, 0)
	hintText.BackgroundTransparency = 1
	hintText.Text = "Ver recomendações"
	hintText.TextColor3 = Color3.fromRGB(245, 249, 255)
	hintText.Font = Enum.Font.GothamBold
	hintText.TextSize = 16
	hintText.TextXAlignment = Enum.TextXAlignment.Left
	hintText.Parent = hintButton

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PersonalSkyMerchantPrompt"
	prompt.ActionText = "Ver recomendações"
	prompt.ObjectText = "Mercador do Céu"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = promptDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	-- O hint acima e a interface oficial deste encontro.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Enabled = true
	prompt.Parent = attachment

	return prompt, hint, hintButton
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
	local previous = encounterState
	encounterState = outcome
	encounterReportInFlight = true
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", outcome)
	task.spawn(function()
		local success, result = pcall(request.InvokeServer, request, "PersonalMerchantEncounter", {
			Outcome = outcome,
			OfferSerial = activeOfferSerial,
		})
		encounterReportInFlight = false
		if success and type(result) == "table" and type(result.State) == "string" then
			encounterState = result.State
		elseif not success or type(result) ~= "table" or result.Success ~= true then
			encounterState = previous
		end
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	end)
	return true
end

local function removeScene(state)
	if activeScene then
		activeScene:Destroy()
	end
	activeScene = nil
	activeMerchant = nil
	activePrompt = nil
	activeInteractionHint = nil
	activeIsland = nil
	activeIslandKey = nil
	activeStaticRelativePivot = nil
	promptVisibleSince = nil
	nearbySince = nil
	awaySince = nil
	player:SetAttribute("PersonalSkyMerchantClientState", state or "Hidden")
end

local fallbackGui
local fallbackStore
local fallbackIndex = 1

local function closeFallbackMerchant(notifyDismissed)
	if fallbackGui then
		fallbackGui:Destroy()
		fallbackGui = nil
	end
	fallbackStore = nil
	fallbackIndex = 1
	if notifyDismissed and activeOfferSerial then
		task.spawn(function()
			pcall(request.InvokeServer, request, "PersonalMerchantEncounter", {
				Outcome = "Dismissed",
				OfferSerial = activeOfferSerial,
			})
		end)
	end
end

local function showFallbackMerchant(store)
	if type(store) ~= "table" or type(store.Entries) ~= "table" or #store.Entries == 0 then
		player:SetAttribute("PersonalSkyMerchantUIState", "FallbackFailedNoOffers")
		return false
	end
	closeFallbackMerchant(false)
	fallbackStore = store
	fallbackIndex = 1

	local gui = Instance.new("ScreenGui")
	gui.Name = "PersonalSkyMerchantFallbackUI_V4"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	fallbackGui = gui

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(4, 8, 14)
	backdrop.BackgroundTransparency = 0.18
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.Modal = true
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 390)
	panel.BackgroundColor3 = Color3.fromRGB(16, 27, 42)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(300, 300)
	sizeConstraint.MaxSize = Vector2.new(620, 460)
	sizeConstraint.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Scale = math.clamp(math.min(workspace.CurrentCamera.ViewportSize.X / 620, workspace.CurrentCamera.ViewportSize.Y / 500), 0.72, 1)
	scale.Parent = panel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(24, 18)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.BackgroundTransparency = 1
	title.Text = "MERCADOR DO CÉU"
	title.TextColor3 = Color3.fromRGB(255, 215, 91)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -18, 0, 16)
	close.Size = UDim2.fromOffset(42, 38)
	close.BackgroundColor3 = Color3.fromRGB(75, 47, 56)
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(255,255,255)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(24, 75)
	name.Size = UDim2.new(1, -48, 0, 42)
	name.BackgroundTransparency = 1
	name.TextColor3 = Color3.fromRGB(244,249,255)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Font = Enum.Font.GothamBold
	name.TextSize = 22
	name.Parent = panel

	local reason = Instance.new("TextLabel")
	reason.Position = UDim2.fromOffset(24, 122)
	reason.Size = UDim2.new(1, -48, 0, 105)
	reason.BackgroundColor3 = Color3.fromRGB(27, 43, 61)
	reason.BackgroundTransparency = 0.08
	reason.TextColor3 = Color3.fromRGB(186, 207, 225)
	reason.TextWrapped = true
	reason.TextXAlignment = Enum.TextXAlignment.Left
	reason.TextYAlignment = Enum.TextYAlignment.Top
	reason.Font = Enum.Font.Gotham
	reason.TextSize = 15
	reason.Parent = panel
	Instance.new("UICorner", reason).CornerRadius = UDim.new(0, 12)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = reason

	local page = Instance.new("TextLabel")
	page.AnchorPoint = Vector2.new(0.5, 0)
	page.Position = UDim2.new(0.5, 0, 0, 242)
	page.Size = UDim2.fromOffset(120, 28)
	page.BackgroundTransparency = 1
	page.TextColor3 = Color3.fromRGB(173,194,211)
	page.Font = Enum.Font.GothamBold
	page.TextSize = 13
	page.Parent = panel

	local previous = Instance.new("TextButton")
	previous.Position = UDim2.fromOffset(24, 238)
	previous.Size = UDim2.fromOffset(120, 36)
	previous.BackgroundColor3 = Color3.fromRGB(35, 51, 70)
	previous.Text = "< ANTERIOR"
	previous.TextColor3 = Color3.fromRGB(244,249,255)
	previous.Font = Enum.Font.GothamBold
	previous.TextSize = 12
	previous.Parent = panel
	Instance.new("UICorner", previous).CornerRadius = UDim.new(0, 9)

	local nextButton = Instance.new("TextButton")
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.new(1, -24, 0, 238)
	nextButton.Size = UDim2.fromOffset(120, 36)
	nextButton.BackgroundColor3 = Color3.fromRGB(35, 51, 70)
	nextButton.Text = "PRÓXIMA >"
	nextButton.TextColor3 = Color3.fromRGB(244,249,255)
	nextButton.Font = Enum.Font.GothamBold
	nextButton.TextSize = 12
	nextButton.Parent = panel
	Instance.new("UICorner", nextButton).CornerRadius = UDim.new(0, 9)

	local buy = Instance.new("TextButton")
	buy.Position = UDim2.fromOffset(24, 294)
	buy.Size = UDim2.new(1, -48, 0, 66)
	buy.BackgroundColor3 = Color3.fromRGB(83, 205, 255)
	buy.TextColor3 = Color3.fromRGB(10, 48, 66)
	buy.TextWrapped = true
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 17
	buy.Parent = panel
	Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 13)

	local function render()
		local entries = fallbackStore and fallbackStore.Entries or {}
		fallbackIndex = math.clamp(fallbackIndex, 1, math.max(1, #entries))
		local entry = entries[fallbackIndex]
		if not entry then return end
		name.Text = string.upper(tostring(entry.DisplayName or "OFERTA"))
		reason.Text = tostring(entry.RecommendationReason or entry.Description or "Oferta selecionada para a sua jornada.")
		page.Text = string.format("%d / %d", fallbackIndex, #entries)
		buy.Text = entry.Available == false and tostring(entry.UnavailableReason or "OFERTA INDISPONÍVEL") or "VER OFERTA"
		buy.Active = entry.Available ~= false
		buy.AutoButtonColor = entry.Available ~= false
	end

	previous.Activated:Connect(function()
		local count = #fallbackStore.Entries
		fallbackIndex = ((fallbackIndex - 2) % count) + 1
		render()
	end)
	nextButton.Activated:Connect(function()
		local count = #fallbackStore.Entries
		fallbackIndex = (fallbackIndex % count) + 1
		render()
	end)
	buy.Activated:Connect(function()
		local entry = fallbackStore.Entries[fallbackIndex]
		if not entry or entry.Available == false then return end
		buy.Active = false
		local ok, result = pcall(request.InvokeServer, request, "Prompt", entry.Id)
		buy.Active = true
		if ok and type(result) == "table" and type(result.Store) == "table" then
			fallbackStore = result.Store
			fallbackIndex = math.min(fallbackIndex, math.max(1, #fallbackStore.Entries))
			render()
		end
	end)
	close.Activated:Connect(function() closeFallbackMerchant(true) end)
	backdrop.Activated:Connect(function() closeFallbackMerchant(true) end)
	render()
	player:SetAttribute("PersonalSkyMerchantUIState", "OpenFallbackV4")
	return true
end

local function broadcastStoreToMerchantUIs(store)
	local fired = 0
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.Name == "PersonalSkyMerchantOpen" and child:IsA("BindableEvent") then
			child:Fire(store)
			fired += 1
		end
	end
	player:SetAttribute("PersonalSkyMerchantBridgeEventCount", fired)
	return fired
end

local function ensureOffersVisible(store)
	broadcastStoreToMerchantUIs(store)
	task.delay(0.35, function()
		local state = tostring(player:GetAttribute("PersonalSkyMerchantUIState") or "")
		if string.find(state, "Open", 1, true) then
			return
		end
		broadcastStoreToMerchantUIs(store)
		task.delay(0.25, function()
			local retryState = tostring(player:GetAttribute("PersonalSkyMerchantUIState") or "")
			if not string.find(retryState, "Open", 1, true) then
				showFallbackMerchant(store)
			end
		end)
	end)
end

local function openMerchant()
	if not activePrompt or openRequestInFlight then
		return
	end
	openRequestInFlight = true
	activePrompt.Enabled = false
	if activeInteractionHint then
		activeInteractionHint.Enabled = false
	end
	player:SetAttribute("PersonalSkyMerchantClientState", "Opening")
	local success, result = pcall(request.InvokeServer, request, "ActivatePersonalMerchant")
	openRequestInFlight = false
	if activePrompt and activePrompt.Parent then
		activePrompt.Enabled = true
	end
	if success and type(result) == "table" and result.Success == true then
		encounterState = "Opened"
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
		player:SetAttribute("PersonalSkyMerchantClientState", "OpenAccepted")
		player:SetAttribute("PersonalSkyMerchantLastStoreEntryCount", type(result.Store) == "table" and type(result.Store.Entries) == "table" and #result.Store.Entries or 0)
		ensureOffersVisible(result.Store)
	else
		player:SetAttribute("PersonalSkyMerchantClientState", "OpenRejected")
		player:SetAttribute("PersonalSkyMerchantLastOpenError", tostring(type(result) == "table" and result.Message or result))
	end
end

local function spawnOnAssignedIsland(island)
	local root = getLivingRoot()
	if not root then
		player:SetAttribute("PersonalSkyMerchantClientState", "WaitingForCharacter")
		return false
	end
	local template = findTemplate(root)
	local model
	if template then
		local success, clone = pcall(template.Clone, template)
		if success and clone and clone:IsA("Model") then
			model = clone
			model:SetAttribute("SourceVillagerTemplate", template:GetFullName())
		end
	end
	model = model or createFallbackMerchant()
	sanitize(model)
	local _, visibleSize = getVisibleBounds(model)
	if not visibleSize then
		model:Destroy()
		player:SetAttribute("PersonalSkyMerchantClientState", "InvalidVisibleModel")
		return false
	end
	local footprint = Vector3.new(math.max(4, visibleSize.X), math.max(5, visibleSize.Y), math.max(4, visibleSize.Z))
	local placement = findPlacement(root, island, footprint)
	if not placement then
		model:Destroy()
		player:SetAttribute("PersonalSkyMerchantClientState", "WaitingForClearFutureIsland")
		return false
	end
	local alignment = alignToSurface(model, placement.Position, placement.EntryPosition)
	if not alignment then
		model:Destroy()
		return false
	end
	local scene = Instance.new("Model")
	scene.Name = SCENE_NAME
	scene:SetAttribute("PersonalSkyMerchantScene", true)
	scene:SetAttribute("OwnerUserId", player.UserId)
	scene:SetAttribute("SpawnIslandKey", getIslandKey(island))
	scene:SetAttribute("SpawnPolicy", VERSION)
	scene.Parent = island

	model.Name = "PersonalSkyMerchant"
	model:SetAttribute("PersonalSkyMerchant", true)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("SpawnIslandKey", getIslandKey(island))
	model:SetAttribute("RecommendedProductIds", tostring(player:GetAttribute("MerchantRecommendedProductIds") or ""))
	model:SetAttribute("StaticStore", true)
	model:SetAttribute("MovementLocked", true)
	model:SetAttribute("RotationLocked", true)
	model.Parent = scene
	activeStaticRelativePivot = island:GetPivot():ToObjectSpace(model:GetPivot())
	createDiscoveryPath(scene, placement, alignment.InteractionPosition, footprint)
	local prompt, interactionHint, interactionButton = addPresentation(model, alignment)

	activeScene = scene
	activeMerchant = model
	activePrompt = prompt
	activeInteractionHint = interactionHint
	activeIsland = island
	activeIslandKey = getIslandKey(island)
	promptVisibleSince = nil
	nearbySince = nil
	awaySince = nil

	prompt.PromptShown:Connect(function()
		if activeInteractionHint == interactionHint then
			interactionHint.Enabled = true
		end
		local shownAt = workspace:GetServerTimeNow()
		promptVisibleSince = shownAt
		task.delay(math.max(0.25, tonumber(MVPConfig.Village.PersonalSkyMerchantPromptPresentationSeconds) or 1.5), function()
			if activePrompt == prompt and promptVisibleSince == shownAt and encounterState == "Unseen" then
				reportEncounter("Presented")
			end
		end)
	end)
	prompt.PromptHidden:Connect(function()
		promptVisibleSince = nil
		if activeInteractionHint == interactionHint then
			interactionHint.Enabled = false
		end
	end)
	prompt.Triggered:Connect(openMerchant)
	interactionButton.Activated:Connect(openMerchant)
	scene.AncestryChanged:Connect(function(_, parent)
		if activeScene == scene and parent == nil then
			if encounterState == "Presented" then
				reportEncounter("Ignored")
			end
			removeScene("TargetIslandRemoved")
		end
	end)

	player:SetAttribute("PersonalSkyMerchantClientVersion", VERSION)
	player:SetAttribute("PersonalSkyMerchantClientState", "SpawnedOnFutureIsland")
	player:SetAttribute("PersonalSkyMerchantSpawnIslandKey", activeIslandKey)
	player:SetAttribute("PersonalSkyMerchantRelocationCount", 0)
	player:SetAttribute("PersonalSkyMerchantPlacementQuality", placement.BlockerCount == 0 and "Clear" or "BestAvailable")
	player:SetAttribute("PersonalSkyMerchantMotionMode", "StaticStore")
	player:SetAttribute("PersonalSkyMerchantRotationMode", "AuthoredAssetRotationLocked")
	player:SetAttribute("PersonalSkyMerchantPromptMode", "CustomHintAttachmentAndKeyboardFallback")
	return true
end

local function enforceStaticStoreTransform()
	if not activeMerchant
		or not activeMerchant.Parent
		or not activeIsland
		or not activeIsland.Parent
		or not activeStaticRelativePivot
	then
		return
	end
	local expectedPivot = activeIsland:GetPivot():ToWorldSpace(activeStaticRelativePivot)
	local currentPivot = activeMerchant:GetPivot()
	local positionError = (currentPivot.Position - expectedPivot.Position).Magnitude
	local rotationError = 1 - math.clamp(currentPivot.LookVector:Dot(expectedPivot.LookVector), -1, 1)
	if positionError > 0.001 or rotationError > 0.000001 then
		activeMerchant:PivotTo(expectedPivot)
	end
	for _, descendant in ipairs(activeMerchant:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		elseif descendant:IsA("Humanoid") then
			descendant.AutoRotate = false
			descendant.WalkSpeed = 0
			descendant.JumpPower = 0
			descendant.JumpHeight = 0
			descendant.PlatformStand = true
		end
	end
end

local function syncOffer()
	if player:GetAttribute("MerchantOfferReady") ~= true then
		activeOfferSerial = nil
		encounterState = "Inactive"
		removeScene("WaitingForRecommendation")
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
		return false
	end
	local serial = math.max(0, math.floor(tonumber(player:GetAttribute("MerchantOffersShown")) or 0))
	if activeOfferSerial ~= serial then
		activeOfferSerial = serial
		encounterState = "Unseen"
		removeScene("WaitingForFutureIsland")
	end
	local serverState = player:GetAttribute("PersonalSkyMerchantEncounterState")
	if type(serverState) == "string" and serverState ~= "" then
		encounterState = serverState
	end
	player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
	return true
end

local function update()
	updateQueued = false
	if not syncOffer() then
		return
	end
	if encounterState == "Ignored" or encounterState == "Dismissed" or encounterState == "Purchased" then
		removeScene("EncounterEnded:" .. encounterState)
		return
	end
	local assignedKey = tostring(player:GetAttribute("PersonalSkyMerchantTargetIslandKey") or "")
	if assignedKey == "" then
		if encounterState == "Presented" then
			reportEncounter("Ignored")
		end
		removeScene("WaitingForFutureIsland")
		return
	end
	local island = resolveAssignedIsland()
	if island and not isNormalMerchantIsland(island) then
		removeScene("RejectedVillageOrSanctuary")
		return
	end
	if not island then
		removeScene("WaitingForTargetStreaming")
		return
	end
	if activeScene and activeScene.Parent then
		if activeIslandKey ~= assignedKey or activeIsland ~= island then
			removeScene("AssignedFutureIslandChanged")
		else
			activeMerchant:SetAttribute("RecommendedProductIds", tostring(player:GetAttribute("MerchantRecommendedProductIds") or ""))
		end
	end
	if not activeScene then
		spawnOnAssignedIsland(island)
	end
	if not activeScene or not activeMerchant or not activeMerchant.Parent then
		return
	end
	enforceStaticStoreTransform()
	if player:GetAttribute("ShopOpen") == true and player:GetAttribute("ActiveShopId") == "SkyMerchant" then
		encounterState = "Opened"
		player:SetAttribute("PersonalSkyMerchantClientEncounterState", encounterState)
		return
	end
	local root = getLivingRoot()
	if not root then
		return
	end
	local anchor = activeMerchant:FindFirstChild("MerchantInteractionAnchor", true)
	local merchantPosition = anchor and anchor:IsA("BasePart") and anchor.Position or activeMerchant:GetPivot().Position
	local distance = (merchantPosition - root.Position).Magnitude
	local promptDistance = activePrompt and activePrompt.MaxActivationDistance
		or math.max(10, tonumber(MVPConfig.Village.PromptDistance) or 13)
	if activeInteractionHint then
		activeInteractionHint.Enabled = activePrompt ~= nil
			and activePrompt.Enabled
			and distance <= promptDistance + 0.5
			and encounterState ~= "Ignored"
			and encounterState ~= "Dismissed"
			and encounterState ~= "Purchased"
	end
	local currentKey = tostring(player:GetAttribute("CurrentIslandKey") or "")
	if encounterState == "Unseen" then
		local nearbyDistance = math.max(MVPConfig.Village.PromptDistance, tonumber(MVPConfig.Village.PersonalSkyMerchantNearbyPresentationDistance) or 28)
		if currentKey == activeIslandKey and distance <= nearbyDistance then
			nearbySince = nearbySince or workspace:GetServerTimeNow()
			if workspace:GetServerTimeNow() - nearbySince >= math.max(0.5, tonumber(MVPConfig.Village.PersonalSkyMerchantNearbyPresentationSeconds) or 4) then
				reportEncounter("Presented")
			end
		else
			nearbySince = nil
		end
	elseif encounterState == "Presented" then
		local leftTarget = currentKey ~= "" and currentKey ~= activeIslandKey
		local tooFar = distance > math.max(MVPConfig.Village.PromptDistance + 1, tonumber(MVPConfig.Village.PersonalSkyMerchantIgnoreDistance) or 65)
		if leftTarget or tooFar then
			awaySince = awaySince or workspace:GetServerTimeNow()
			if workspace:GetServerTimeNow() - awaySince >= math.max(0.5, tonumber(MVPConfig.Village.PersonalSkyMerchantIgnoreSeconds) or 3) then
				reportEncounter("Ignored")
				removeScene("IgnoredAfterDiscovery")
			end
		else
			awaySince = nil
		end
	end
end

local function queueUpdate()
	if updateQueued then
		return
	end
	updateQueued = true
	task.defer(update)
end

local function tryInteractFromInput(input, gameProcessed)
	if gameProcessed
		or UserInputService:GetFocusedTextBox()
		or not activePrompt
		or not activePrompt.Enabled
		or not activePrompt.Parent
	then
		return
	end
	local isKeyboardE = input.UserInputType == Enum.UserInputType.Keyboard
		and input.KeyCode == Enum.KeyCode.E
	local isGamepadX = input.KeyCode == Enum.KeyCode.ButtonX
	if not isKeyboardE and not isGamepadX then
		return
	end
	local root = getLivingRoot()
	local anchor = activeMerchant
		and activeMerchant:FindFirstChild("MerchantInteractionAnchor", true)
	if not root or not anchor or not anchor:IsA("BasePart") then
		return
	end
	if (anchor.Position - root.Position).Magnitude
		<= activePrompt.MaxActivationDistance + 1
	then
		openMerchant()
	end
end

UserInputService.InputBegan:Connect(tryInteractFromInput)

local old = workspace:FindFirstChild(SCENE_NAME, true)
if old then
	old:Destroy()
end

for _, attribute in ipairs({
	"MerchantOfferReady",
	"MerchantOffersShown",
	"MerchantRecommendedProductIds",
	"PersonalSkyMerchantEncounterState",
	"PersonalSkyMerchantTargetIslandKey",
	"CurrentIslandKey",
	"ShopOpen",
	"ActiveShopId",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(queueUpdate)
end
local targetValue = player:FindFirstChild(TARGET_VALUE_NAME)
if targetValue and targetValue:IsA("ObjectValue") then
	targetValue:GetPropertyChangedSignal("Value"):Connect(queueUpdate)
end
player.ChildAdded:Connect(function(child)
	if child.Name == TARGET_VALUE_NAME and child:IsA("ObjectValue") then
		child:GetPropertyChangedSignal("Value"):Connect(queueUpdate)
		queueUpdate()
	end
end)
player.CharacterAdded:Connect(function()
	removeScene("CharacterRespawning")
	task.delay(1, queueUpdate)
end)
monetizationEvent.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Action == "OpenPersonalMerchant" then
		closeFallbackMerchant(false)
	end
	if type(data) == "table"
		and (data.Action == "OfferReady"
			or data.Action == "OfferEnded"
			or data.Action == "PurchaseGranted"
			or data.Action == "Entitlements")
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
