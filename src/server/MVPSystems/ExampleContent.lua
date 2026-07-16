--[[
	BlockParkour MVP - conteudo de exemplo substituivel.

	Cria tres coletaveis simples somente quando os mesmos CollectibleIds ainda
	nao existem. Para retirar um exemplo, defina Enabled = false ou remova-o.
]]

local ServerStorage = game:GetService("ServerStorage")

local ExampleContent = {}

local EXAMPLE_COLLECTIBLES = {
	{
		Id = "BlueCrystal",
		Name = "Cristal azul",
		Color = Color3.fromRGB(48, 170, 255),
		Shape = Enum.PartType.Block,
		Score = 25,
		Coins = 3,
		Weight = 20,
		MaxPerIsland = 2,
		MinimumSize = "Small",
	},
	{
		Id = "GoldenOrb",
		Name = "Orbe dourado",
		Color = Color3.fromRGB(255, 196, 45),
		Shape = Enum.PartType.Ball,
		Score = 50,
		Coins = 6,
		Weight = 8,
		MaxPerIsland = 1,
		MinimumSize = "Medium",
	},
	{
		Id = "RubyShard",
		Name = "Fragmento rubi",
		Color = Color3.fromRGB(235, 55, 92),
		Shape = Enum.PartType.Block,
		Score = 100,
		Coins = 10,
		Weight = 3,
		MaxPerIsland = 1,
		MinimumSize = "Large",
	},
}

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), existing:GetFullName() .. " deve ser Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function findCollectibleById(folder, collectibleId)
	for _, child in ipairs(folder:GetChildren()) do
		if child:GetAttribute("CollectibleId") == collectibleId then
			return child
		end
	end
	return nil
end

local function createCollectible(folder, definition)
	local part = Instance.new("Part")
	part.Name = definition.Id
	part.Size = Vector3.new(2.4, 2.4, 2.4)
	part.Shape = definition.Shape
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Material = Enum.Material.Neon
	part.Color = definition.Color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("CollectibleId", definition.Id)
	part:SetAttribute("DisplayName", definition.Name)
	part:SetAttribute("ScoreValue", definition.Score)
	part:SetAttribute("CoinValue", definition.Coins)
	part:SetAttribute("SpawnWeight", definition.Weight)
	part:SetAttribute("BreakRadius", 7)
	part:SetAttribute("MaxPerIsland", definition.MaxPerIsland)
	part:SetAttribute("ParticleColor", definition.Color)
	part:SetAttribute("MinimumIslandSize", definition.MinimumSize)
	part:SetAttribute("CollectSoundId", "rbxasset://sounds/electronicpingshort.wav")
	part:SetAttribute("Enabled", true)
	part.Parent = folder
end

function ExampleContent.EnsureCollectibles()
	local assets = ensureFolder(ServerStorage, "MVPAssets")
	local folder = ensureFolder(assets, "Collectibles")
	for _, definition in ipairs(EXAMPLE_COLLECTIBLES) do
		if not findCollectibleById(folder, definition.Id) then
			createCollectible(folder, definition)
		end
	end
end

return ExampleContent
