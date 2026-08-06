-- Execute uma unica vez no Command Bar do Roblox Studio, fora do Play.
-- O backup permanece em ServerStorage/MVPAssets_LobbyMigrationBackup.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

assert(RunService:IsStudio() and not RunService:IsRunning(), "Execute fora do modo Play")

local function ensure(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function setDefaultAttribute(instance, name, value)
	if instance:GetAttribute(name) == nil then
		instance:SetAttribute(name, value)
	end
end

local function configurePhase(folder, values)
	for name, value in pairs(values) do
		setDefaultAttribute(folder, name, value)
	end
end

local legacy = ServerStorage:FindFirstChild("MVPAssets")
assert(legacy, "ServerStorage/MVPAssets nao foi encontrado")

if not ServerStorage:FindFirstChild("MVPAssets_LobbyMigrationBackup") then
	local backup = legacy:Clone()
	backup.Name = "MVPAssets_LobbyMigrationBackup"
	backup.Parent = ServerStorage
end

local gameContent = ensure(ServerStorage, "GameContent")
local phases = ensure(gameContent, "Phases")
local phase01 = ensure(phases, "Phase01")
local phase02 = ensure(phases, "Phase02")
local phaseTemplate = ensure(phases, "_PhaseTemplate")
local equipment = ensure(gameContent, "Equipment")
local sharedModels = ensure(gameContent, "SharedModels")

for _, phase in ipairs({ phase01, phase02, phaseTemplate }) do
	local islands = ensure(phase, "Islands")
	ensure(islands, "Common")
	ensure(islands, "Special")
	ensure(islands, "BossArena")
	ensure(phase, "Enemies")
	ensure(phase, "Bosses")
	ensure(phase, "Decorations")
end
for _, name in ipairs({ "Swords", "Wings", "Companions", "Abilities" }) do
	ensure(equipment, name)
end

local function copyChildren(source, destination)
	if not source then
		return
	end
	for _, child in ipairs(source:GetChildren()) do
		if not destination:FindFirstChild(child.Name) then
			child:Clone().Parent = destination
		end
	end
end

copyChildren(legacy:FindFirstChild("Monsters"), phase01.Enemies)
copyChildren(legacy:FindFirstChild("Decorations"), phase01.Decorations)
copyChildren(legacy:FindFirstChild("Bosses"), phase01.Bosses)
copyChildren(legacy:FindFirstChild("Swords"), equipment.Swords)

configurePhase(phase01, {
	PhaseId = "Phase01",
	DisplayName = "Fase 1",
	Enabled = true,
	RequiredLevel = 1,
	MaxPlayers = 4,
	MaximumIslandCount = 10,
	VictoryCoins = 250,
	BossId = "GiantBoss",
	ImageId = "",
	SortOrder = 1,
	IslandBlockColor = Color3.fromRGB(112, 78, 48),
	IslandBlockMaterial = "Ground",
	IslandBlockTextureId = "",
	TextureStudsPerTileU = 4,
	TextureStudsPerTileV = 4,
	MaximumActiveMonsters = 45,
	EliteReservedMonsterSlots = 3,
	DefaultMonsterSpawnChance = 0.72,
	DecorationSpawnChance = 0.7,
	AllowPrototypeContent = true,
})
configurePhase(phase02, {
	PhaseId = "Phase02",
	DisplayName = "Fase 2",
	Enabled = true,
	RequiredLevel = 1,
	MaxPlayers = 4,
	MaximumIslandCount = 12,
	VictoryCoins = 350,
	BossId = "GiantBoss",
	ImageId = "",
	SortOrder = 2,
	IslandBlockColor = Color3.fromRGB(88, 96, 112),
	IslandBlockMaterial = "Slate",
	IslandBlockTextureId = "",
	TextureStudsPerTileU = 4,
	TextureStudsPerTileV = 4,
	MaximumActiveMonsters = 50,
	EliteReservedMonsterSlots = 4,
	DefaultMonsterSpawnChance = 0.78,
	DecorationSpawnChance = 0.7,
	AllowPrototypeContent = true,
})
configurePhase(phaseTemplate, {
	PhaseId = "NewPhase",
	DisplayName = "Nova fase",
	Enabled = false,
	RequiredLevel = 1,
	MaxPlayers = 4,
	MaximumIslandCount = 10,
	VictoryCoins = 250,
	BossId = "PhaseBoss",
	ImageId = "",
	SortOrder = 99,
	IslandBlockColor = Color3.fromRGB(112, 78, 48),
	IslandBlockMaterial = "Ground",
	IslandBlockTextureId = "",
	TextureStudsPerTileU = 4,
	TextureStudsPerTileV = 4,
	MaximumActiveMonsters = 45,
	EliteReservedMonsterSlots = 3,
	DefaultMonsterSpawnChance = 0.72,
	DecorationSpawnChance = 0.7,
	AllowPrototypeContent = false,
})

for _, name in ipairs({
	"Atmosphere",
	"Chests",
	"Collectibles",
	"Grass",
	"Items",
	"Monetization",
	"Relics",
	"Village",
}) do
	local source = legacy:FindFirstChild(name)
	if source and not sharedModels:FindFirstChild(name) then
		local clone = source:Clone()
		clone.Parent = sharedModels
	end
end

local function cloneMissing(source, destination)
	for _, child in ipairs(source:GetChildren()) do
		if not destination:FindFirstChild(child.Name) then
			child:Clone().Parent = destination
		end
	end
end

cloneMissing(phase01.Enemies, phase02.Enemies)
cloneMissing(phase01.Decorations, phase02.Decorations)
cloneMissing(phase01.Bosses, phase02.Bosses)

for _, phase in ipairs({ phase01, phase02 }) do
	for _, model in ipairs(phase.Enemies:GetChildren()) do
		if model:IsA("Model") then
			setDefaultAttribute(model, "Enabled", true)
			setDefaultAttribute(model, "MonsterId", model.Name)
			setDefaultAttribute(model, "MinimumRound", 1)
			local root = model:FindFirstChild("HumanoidRootPart", true)
				or model:FindFirstChildWhichIsA("BasePart", true)
			if not model.PrimaryPart and root then
				model.PrimaryPart = root
			end
		end
	end
end

gameContent:SetAttribute("LobbyMvpMigrationVersion", 2)
print("[LobbyMVP] Migracao concluida. Salve e publique o Place de dungeon.")
