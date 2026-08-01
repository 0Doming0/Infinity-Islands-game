-- Classifica ilhas ja geradas e reserva conteudo especial antes de o modelo ser
-- publicado no Workspace. Nao troca geometria e nunca transforma santuarios
-- em desafios obrigatorios.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MonetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))

local IslandTypeService = {}
local GRASS_FACE_NAME = "NormalBiomeGrassTopFace"
local SOLO_MERCHANT_DECISION_VERSION = 2

local function setGrassColor(floor, grass, color)
	floor:SetAttribute("DistantGrassColor", color)
	if grass and grass:IsA("BasePart") then
		grass.Color = color
		grass:SetAttribute("DistantGrassColor", color)
	end
	local grassFace = floor:FindFirstChild(GRASS_FACE_NAME)
	if grassFace and grassFace:IsA("SurfaceGui") then
		local fallback = grassFace:FindFirstChild("GrassFallback")
		if fallback and fallback:IsA("Frame") then
			fallback.BackgroundColor3 = color
		end
		local texture = grassFace:FindFirstChild("GrassTexture")
		if texture and texture:IsA("ImageLabel") then
			texture.ImageColor3 = color
		end
	end
end

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

local function personalMonetizationMultiplier(userId, boostName, productId)
	local cleanUserId = math.floor(tonumber(userId) or 0)
	if cleanUserId <= 0 then
		return 1
	end
	local player = Players:GetPlayerByUserId(cleanUserId)
	if not player then
		return 1
	end
	local expiration = tonumber(player:GetAttribute(boostName .. "BoostUntil")) or 0
	if expiration <= os.time() then
		return 1
	end
	local definition = MonetizationCatalog.Get(productId)
	return math.max(1, tonumber(definition and definition.ChanceMultiplier) or 1)
end

local function styleIsland(island, islandType, tier)
	local floor = island:FindFirstChild("IslandFloor")
	if not floor or not floor:IsA("BasePart") then
		return
	end
	local grass = island:FindFirstChild("IslandGrassTop")
	if islandType == "Elite" then
		setGrassColor(floor, grass, Color3.fromRGB(108, 54, 56))
		-- Evita emojis compostos neste BillboardGui. Em alguns dispositivos eles
		-- sao renderizados como um quadrado branco em vez do icone esperado.
		addLabel(island, floor, string.format("ELITE  |  NIVEL %d", tier), Color3.fromRGB(255, 96, 78))
	elseif islandType == "Treasure" then
		setGrassColor(floor, grass, Color3.fromRGB(154, 126, 52))
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
	local generationOwnerUserId = tonumber(
		context.GenerationOwnerUserId
			or island:GetAttribute("GenerationOwnerUserId")
	) or 0
	local treasureMonetizationMultiplier = personalMonetizationMultiplier(
		generationOwnerUserId,
		"Treasure",
		"TreasureExpedition"
	)
	local eliteMonetizationMultiplier = personalMonetizationMultiplier(
		generationOwnerUserId,
		"Elite",
		"EliteExpedition"
	)
	island:SetAttribute("GenerationOwnerUserId", generationOwnerUserId > 0 and generationOwnerUserId or nil)
	island:SetAttribute("TreasureMonetizationChanceMultiplier", treasureMonetizationMultiplier)
	island:SetAttribute("EliteMonetizationChanceMultiplier", eliteMonetizationMultiplier)
	island:SetAttribute("IslandType", "Normal")
	island:SetAttribute("SoloMerchantDecisionVersion", SOLO_MERCHANT_DECISION_VERSION)
	island:SetAttribute("SoloMerchantReserved", false)
	island:SetAttribute("SoloMerchantRoll", nil)
	island:SetAttribute("SoloMerchantChance", nil)
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
		and random:NextNumber() <= math.clamp(
			MVPConfig.SpecialIslands.TreasureChance
				* specialChanceMultiplier
				* treasureMonetizationMultiplier,
			0,
			1
		)
	then
		island:SetAttribute("IslandType", "Treasure")
		island:SetAttribute("CanSpawnMonster", false)
		island:SetAttribute("CanSpawnItem", false)
		island:SetAttribute("RewardMultiplier", baseRewardMultiplier * 2)
		styleIsland(island, "Treasure", tier)
		return "Treasure"
	end

	if roundIndex >= MVPConfig.SpecialIslands.MinimumEliteRound
		and random:NextNumber() <= math.clamp(
			MVPConfig.SpecialIslands.EliteChance
				* specialChanceMultiplier
				* eliteMonetizationMultiplier,
			0,
			1
		)
	then
		island:SetAttribute("IslandType", "Elite")
		island:SetAttribute("CanSpawnMonster", true)
		island:SetAttribute("CanSpawnItem", false)
		island:SetAttribute("RewardMultiplier", baseRewardMultiplier * MVPConfig.Difficulty.EliteRewardMultiplier)
		styleIsland(island, "Elite", tier)
		return "Elite"
	end
	-- O Mercador do Ceu pessoal existe somente no cliente. Ilhas normais nunca
	-- sao reservadas para ele e conservam as regras comuns de mobs e itens.
	return "Normal"
end

return IslandTypeService
