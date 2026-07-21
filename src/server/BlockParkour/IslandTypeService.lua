-- Classifica apenas ilhas laterais ja geradas. Nao troca geometria e nunca
-- transforma a rota principal, a vila ou os santuarios em desafios obrigatorios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))

local IslandTypeService = {}

local function normalizedSeed(value)
	local seed = math.floor(math.abs(tonumber(value) or 1)) % 2147483647
	return seed == 0 and 1 or seed
end

local function addLabel(island, floor, text, color)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SpecialIslandLabel"
	billboard.Adornee = floor
	billboard.Size = UDim2.fromOffset(150, 32)
	billboard.StudsOffset = Vector3.new(0, 4.6, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 28
	billboard.Parent = island
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	label.BackgroundTransparency = 0.38
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 7)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Transparency = 0.45
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
		-- Evita emojis compostos neste BillboardGui. Em alguns dispositivos eles
		-- sao renderizados como um quadrado branco em vez do icone esperado.
		addLabel(island, floor, string.format("ELITE  |  NIVEL %d", tier), Color3.fromRGB(255, 96, 78))
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
	local baseRewardMultiplier = math.max(0.1, tonumber(island:GetAttribute("RouteRewardMultiplier")) or 1)
	local specialChanceMultiplier = math.max(0, tonumber(island:GetAttribute("SpecialIslandChanceMultiplier")) or 1)
	island:SetAttribute("IslandType", "Normal")
	island:SetAttribute("DangerLevel", tier)
	island:SetAttribute("RewardMultiplier", baseRewardMultiplier)
	if string.find(role, "Sanctuary", 1, true) then
		return "Normal"
	end

	local random = Random.new(normalizedSeed(
		(island:GetAttribute("IslandSeed") or context.RoundSeed or 1) + MVPConfig.SpecialIslands.RandomSalt
	))
	local treasureGap = math.max(1, MVPConfig.SpecialIslands.MinimumTreasureRoundGap)
	local treasureWindow = roundIndex >= MVPConfig.SpecialIslands.MinimumTreasureRound
		and (roundIndex - MVPConfig.SpecialIslands.MinimumTreasureRound) % treasureGap == 0
	if treasureWindow
		and random:NextNumber() <= math.clamp(MVPConfig.SpecialIslands.TreasureChance * specialChanceMultiplier, 0, 1)
	then
		island:SetAttribute("IslandType", "Treasure")
		island:SetAttribute("CanSpawnMonster", false)
		island:SetAttribute("CanSpawnItem", false)
		island:SetAttribute("RewardMultiplier", baseRewardMultiplier * 2)
		styleIsland(island, "Treasure", tier)
		return "Treasure"
	end

	if roundIndex >= MVPConfig.SpecialIslands.MinimumEliteRound
		and random:NextNumber() <= math.clamp(MVPConfig.SpecialIslands.EliteChance * specialChanceMultiplier, 0, 1)
	then
		island:SetAttribute("IslandType", "Elite")
		island:SetAttribute("CanSpawnMonster", true)
		island:SetAttribute("CanSpawnItem", false)
		island:SetAttribute("RewardMultiplier", baseRewardMultiplier * MVPConfig.Difficulty.EliteRewardMultiplier)
		styleIsland(island, "Elite", tier)
		return "Elite"
	end
	return "Normal"
end

return IslandTypeService
