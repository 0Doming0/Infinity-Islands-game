-- Classifica apenas ilhas laterais ja geradas. Nao troca geometria e nunca
-- transforma a rota principal, a vila ou os santuarios em desafios obrigatorios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local IslandTypeService = {}
local lastTreasureRound = -math.huge

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % 2147483647
	return seed == 0 and 1 or seed
end

local function addLabel(island, floor, text, color)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SpecialIslandLabel"
	billboard.Adornee = floor
	billboard.Size = UDim2.fromOffset(220, 54)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 115
	billboard.Parent = island
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	label.BackgroundTransparency = 0.18
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = label
end

local function styleIsland(island, islandType, tier)
	local floor = island:FindFirstChild("IslandFloor")
	if not floor or not floor:IsA("BasePart") then
		return
	end
	local grass = island:FindFirstChild("IslandGrassTop")
	if islandType == "Elite" then
		if grass and grass:IsA("BasePart") then
			grass.Color = Color3.fromRGB(108, 54, 56)
		end
		addLabel(island, floor, string.format("ILHA ELITE  -  NIVEL %d", tier), Color3.fromRGB(255, 96, 78))
	elseif islandType == "Treasure" then
		if grass and grass:IsA("BasePart") then
			grass.Color = Color3.fromRGB(154, 126, 52)
		end
		addLabel(island, floor, "ILHA DO TESOURO", Color3.fromRGB(255, 220, 82))
	end
end

function IslandTypeService.Classify(island, context)
	context = context or {}
	local roundIndex = tonumber(context.RoundIndex or island:GetAttribute("RoundIndex")) or 1
	local role = tostring(island:GetAttribute("IslandRole") or "")
	local tier = math.clamp(
		math.floor((roundIndex - 1) / MVPConfig.Difficulty.RoundsPerTier) + 1,
		1,
		MVPConfig.Difficulty.MaximumTier
	)
	island:SetAttribute("IslandType", "Normal")
	island:SetAttribute("DangerLevel", tier)
	island:SetAttribute("RewardMultiplier", 1)
	if not string.find(role, "SideRoom", 1, true) then
		return "Normal"
	end

	local random = Random.new(normalizedSeed(
		(island:GetAttribute("IslandSeed") or context.RoundSeed or 1) + MVPConfig.SpecialIslands.RandomSalt
	))
	if roundIndex >= MVPConfig.SpecialIslands.MinimumTreasureRound
		and roundIndex - lastTreasureRound >= MVPConfig.SpecialIslands.MinimumTreasureRoundGap
		and random:NextNumber() <= MVPConfig.SpecialIslands.TreasureChance
	then
		lastTreasureRound = roundIndex
		island:SetAttribute("IslandType", "Treasure")
		island:SetAttribute("CanSpawnMonster", false)
		island:SetAttribute("CanSpawnItem", false)
		island:SetAttribute("RewardMultiplier", 2)
		styleIsland(island, "Treasure", tier)
		return "Treasure"
	end

	if roundIndex >= MVPConfig.SpecialIslands.MinimumEliteRound
		and random:NextNumber() <= MVPConfig.SpecialIslands.EliteChance
	then
		island:SetAttribute("IslandType", "Elite")
		island:SetAttribute("CanSpawnMonster", true)
		island:SetAttribute("CanSpawnItem", false)
		island:SetAttribute("RewardMultiplier", MVPConfig.Difficulty.EliteRewardMultiplier)
		styleIsland(island, "Elite", tier)
		return "Elite"
	end
	return "Normal"
end

return IslandTypeService
