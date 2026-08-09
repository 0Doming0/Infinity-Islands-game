--[[
	Infinity Islands - Recommended Level Sign Service V3

	Mudanca principal:
	- a placa NAO usa mais um canto arbitrario;
	- fica na entrada principal da ilha (GameplayMarkers.Entry);
	- fica alguns studs para dentro da ilha;
	- a frente da placa olha para fora da entrada, na direcao da ilha inferior;
	- LevelText continua recebendo SOMENTE O NUMERO.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("RecommendedLevelSignConfig")
)

local IslandProgressionConfig = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("IslandProgressionConfig")
)

local tracked = setmetatable({}, { __mode = "k" })
local warnedTemplates = {}
local warnedInvalid = {}

local function cleanLevel(value)
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function cleanIndex(value)
	local number = tonumber(value)

	if not number then
		return nil
	end

	number = math.floor(number)
	return number >= 1 and number or nil
end

local function resolveRecommendedLevel(island)
	local explicit = tonumber(island:GetAttribute("RecommendedLevel"))

	if explicit then
		return cleanLevel(explicit)
	end

	local islandLevel = tonumber(island:GetAttribute("IslandLevel"))

	if islandLevel then
		return cleanLevel(islandLevel)
	end

	local index = cleanIndex(
		island:GetAttribute("GlobalIslandIndex")
			or island:GetAttribute("ProgressionIslandIndex")
	)

	if index then
		return IslandProgressionConfig.GetRecommendedLevel(index)
	end

	return nil
end

local function templateRoot()
	local current = ServerStorage

	for _, name in ipairs(Config.TemplateRoot) do
		current = current:FindFirstChild(name)

		if not current then
			return nil
		end
	end

	return current
end

local function resolveFamily(island, level)
	local explicit =
		island:GetAttribute("MobFamily")
			or island:GetAttribute("RecommendedSignFamily")

	if type(explicit) == "string" and explicit ~= "" then
		return explicit
	end

	return Config.ResolveFamily(level)
end

local function findFloor(island)
	local floor = island:FindFirstChild("IslandFloor", true)

	if floor and floor:IsA("BasePart") then
		return floor
	end

	if island.PrimaryPart and island.PrimaryPart:IsA("BasePart") then
		return island.PrimaryPart
	end

	return island:FindFirstChildWhichIsA("BasePart", true)
end

local function findEntry(island)
	local markers = island:FindFirstChild("GameplayMarkers")

	if markers then
		local direct = markers:FindFirstChild("Entry")

		if direct and direct:IsA("BasePart") then
			return direct
		end

		local entries = markers:FindFirstChild("Entries")

		if entries then
			for _, child in ipairs(entries:GetChildren()) do
				if child:IsA("BasePart")
					and child:GetAttribute("MarkerType") == "Entry"
				then
					return child
				end
			end
		end
	end

	for _, descendant in ipairs(island:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant:GetAttribute("MarkerType") == "Entry"
		then
			return descendant
		end
	end

	return nil
end

local function existingSign(island)
	local direct = island:FindFirstChild(Config.SignName)

	if direct and direct:IsA("Model") then
		return direct
	end

	for _, child in ipairs(island:GetChildren()) do
		if child:IsA("Model")
			and child:GetAttribute("GeneratedRecommendedLevelSign") == true
		then
			return child
		end
	end

	return nil
end

local function setModelRuntimeSafe(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function primaryPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local named = model:FindFirstChild("SignPart", true)

	if named and named:IsA("BasePart") then
		model.PrimaryPart = named
		return named
	end

	local fallback = model:FindFirstChildWhichIsA("BasePart", true)

	if fallback then
		model.PrimaryPart = fallback
	end

	return fallback
end

local function findTextObject(sign, name)
	local object = sign:FindFirstChild(name, true)

	if object
		and (
			object:IsA("TextLabel")
			or object:IsA("TextButton")
			or object:IsA("TextBox")
		)
	then
		return object
	end

	return nil
end

local function updateText(sign, level)
	local numberText = tostring(cleanLevel(level))
	local levelText = findTextObject(sign, Config.LevelTextName)

	if not levelText then
		return false, "LevelTextMissing"
	end

	-- Regra final: apenas o numero.
	levelText.Text = numberText

	local shadow = findTextObject(sign, Config.LevelShadowName)

	if shadow then
		shadow.Text = numberText
	end

	return true
end

local function modelBottomOffset(sign)
	local pivot = sign:GetPivot()
	local boundsCFrame, boundsSize = sign:GetBoundingBox()

	local pivotToBoundsY =
		boundsCFrame.Position.Y - pivot.Position.Y

	return pivotToBoundsY - boundsSize.Y / 2
end

local function signCFrame(island, sign)
	local floor = findFloor(island)
	local entry = findEntry(island)
	local signPart = primaryPart(sign)

	if not floor or not signPart then
		return nil
	end

	local floorTopY =
		floor.Position.Y
		+ floor.Size.Y / 2
		+ (tonumber(Config.HeightAboveFloorStuds) or 0.15)

	local outward
	local entryPosition

	if entry then
		entryPosition = Vector3.new(
			entry.Position.X,
			floorTopY,
			entry.Position.Z
		)

		-- Outward aponta da ilha para a rota/ilha inferior.
		outward = Vector3.new(
			entry.Position.X - floor.Position.X,
			0,
			entry.Position.Z - floor.Position.Z
		)

		if outward.Magnitude < 0.001 then
			local look = entry.CFrame.LookVector
			outward = Vector3.new(-look.X, 0, -look.Z)
		end
	else
		entryPosition = Vector3.new(
			floor.Position.X,
			floorTopY,
			floor.Position.Z
		)
		outward = Vector3.new(0, 0, -1)
	end

	outward = outward.Magnitude > 0.001
		and outward.Unit
		or Vector3.new(0, 0, -1)

	-- Direcao que o jogador percebe como "direita" ao vir da ilha inferior
	-- e olhar para dentro desta ilha.
	local intoIsland = -outward
	local right =
		intoIsland:Cross(Vector3.new(0, 1, 0))

	right = right.Magnitude > 0.001
		and right.Unit
		or Vector3.new(1, 0, 0)

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2

	-- Distancia disponivel do centro ate a borda na direcao "right".
	local rightEdgeDistance =
		math.abs(right.X) * halfX
		+ math.abs(right.Z) * halfZ

	local cornerMargin =
		math.max(
			1,
			tonumber(Config.RightCornerMarginStuds) or 4
		)

	local rightOffset =
		math.max(
			0,
			rightEdgeDistance - cornerMargin
		)

	local inset =
		math.max(
			0,
			tonumber(Config.EntryInsetStuds) or 4
		)

	-- Entrada + para dentro da ilha + canto direito.
	local worldPosition =
		entryPosition
		- outward * inset
		+ right * rightOffset

	worldPosition += Vector3.new(
		0,
		-modelBottomOffset(sign),
		0
	)

	-- A frente da placa olha para quem vem da ilha inferior.
	local target =
		worldPosition + outward * 30

	local cf = CFrame.lookAt(
		worldPosition,
		target
	)

	local yaw =
		math.rad(
			tonumber(Config.YawOffsetDegrees) or 0
		)

	if math.abs(yaw) > 0.0001 then
		cf *= CFrame.Angles(0, yaw, 0)
	end

	return cf
end

local function applySign(island)
	if not island
		or not island.Parent
		or not island:IsA("Model")
		or island:GetAttribute("IsSkyIsland") ~= true
	then
		return false
	end

	if island:GetAttribute("IsSanctuary") == true
		or island:GetAttribute("IsBossSanctuary") == true
		or island:GetAttribute("IsRewardIsland") == true
	then
		local old = existingSign(island)

		if old then
			old:Destroy()
		end

		return false
	end

	local level = resolveRecommendedLevel(island)

	if not level then
		return false
	end

	local family = resolveFamily(island, level)
	local root = templateRoot()

	if not root then
		if not warnedTemplates.__root then
			warnedTemplates.__root = true
			warn(
				"[RecommendedLevelSign] "
					.. "ServerStorage.DungeonTemplates.RecommendedSigns nao encontrado."
			)
		end

		return false
	end

	local template = root:FindFirstChild(family)

	if not template or not template:IsA("Model") then
		if not warnedTemplates[family] then
			warnedTemplates[family] = true
			warn(
				"[RecommendedLevelSign] Template ausente: "
					.. tostring(family)
			)
		end

		return false
	end

	local sign = existingSign(island)

	if sign
		and sign:GetAttribute("RecommendedSignFamily") ~= family
	then
		sign:Destroy()
		sign = nil
	end

	if not sign then
		sign = template:Clone()
		sign.Name = Config.SignName

		sign:SetAttribute("GeneratedRecommendedLevelSign", true)
		sign:SetAttribute("RecommendedSignVersion", Config.Version)
		sign:SetAttribute("RecommendedSignFamily", family)

		setModelRuntimeSafe(sign)

		if not primaryPart(sign) then
			if not warnedInvalid[family] then
				warnedInvalid[family] = true
				warn(
					"[RecommendedLevelSign] "
						.. family
						.. " nao possui SignPart/BasePart."
				)
			end

			sign:Destroy()
			return false
		end

		sign.Parent = island
	end

	local ok, reason = updateText(sign, level)

	if not ok then
		local key = family .. ":" .. tostring(reason)

		if not warnedInvalid[key] then
			warnedInvalid[key] = true
			warn(
				"[RecommendedLevelSign] "
					.. family
					.. " sem LevelText valido."
			)
		end

		return false
	end

	local targetCFrame = signCFrame(island, sign)

	if targetCFrame then
		sign:PivotTo(targetCFrame)
	end

	sign:SetAttribute("RecommendedLevel", level)
	sign:SetAttribute("RecommendedSignFamily", family)
	sign:SetAttribute("RecommendedSignPlacement", "RightEntryCornerFacingLowerIsland")

	island:SetAttribute("RecommendedLevel", level)
	island:SetAttribute("RecommendedSignFamily", family)
	island:SetAttribute("RecommendedSignReady", true)
	island:SetAttribute("RecommendedSignVersion", Config.Version)
	island:SetAttribute("RecommendedSignPlacement", "RightEntryCornerFacingLowerIsland")

	return true
end

local function disconnectIsland(island)
	local record = tracked[island]

	if record then
		for _, connection in ipairs(record) do
			connection:Disconnect()
		end
	end

	tracked[island] = nil
end

local function trackIsland(island)
	if tracked[island]
		or not island:IsA("Model")
		or island:GetAttribute("IsSkyIsland") ~= true
	then
		return
	end

	local connections = {}
	tracked[island] = connections

	for _, attributeName in ipairs({
		"RecommendedLevel",
		"IslandLevel",
		"GlobalIslandIndex",
		"ProgressionIslandIndex",
		"MobFamily",
		"RecommendedSignFamily",
	}) do
		table.insert(
			connections,
			island:GetAttributeChangedSignal(attributeName):Connect(function()
				task.defer(applySign, island)
			end)
		)
	end

	table.insert(
		connections,
		island.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart")
				and descendant:GetAttribute("MarkerType") == "Entry"
			then
				task.defer(applySign, island)
			end
		end)
	)

	table.insert(
		connections,
		island.AncestryChanged:Connect(function(_, parent)
			if not parent then
				disconnectIsland(island)
			end
		end)
	)

	task.defer(applySign, island)
end

local function scan()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("IsSkyIsland") == true
		then
			trackIsland(descendant)
			applySign(descendant)
		end
	end
end

workspace.DescendantAdded:Connect(function(instance)
	if not instance:IsA("Model") then
		return
	end

	task.defer(function()
		for _ = 1, 20 do
			if not instance.Parent then
				return
			end

			if instance:GetAttribute("IsSkyIsland") == true then
				trackIsland(instance)
				return
			end

			task.wait(0.05)
		end
	end)
end)

scan()

task.spawn(function()
	while true do
		task.wait(1.5)

		for island in pairs(tracked) do
			if island.Parent then
				applySign(island)
			else
				disconnectIsland(island)
			end
		end
	end
end)

workspace:SetAttribute("RecommendedLevelSignServiceReady", true)
workspace:SetAttribute("RecommendedLevelSignServiceVersion", Config.Version)

print(
	"[RecommendedLevelSign] V2 ready - canto direito da entrada / ilha inferior."
)
