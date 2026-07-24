-- Jogadores atravessam mobs, e mobs atravessam uns aos outros. O grupo Default
-- continua colidindo com ambos para manter personagens e inimigos sobre a ilha.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local PLAYER_GROUP = "MVPPlayers"
local MONSTER_GROUP = "MVPMonsters"
local ELITE_BOUNDARY_GROUP = "EliteIslandBoundary"

pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, PLAYER_GROUP)
pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, MONSTER_GROUP)
pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, ELITE_BOUNDARY_GROUP)
PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, MONSTER_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(MONSTER_GROUP, MONSTER_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(ELITE_BOUNDARY_GROUP, MONSTER_GROUP, true)
PhysicsService:CollisionGroupSetCollidable(ELITE_BOUNDARY_GROUP, PLAYER_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(ELITE_BOUNDARY_GROUP, ELITE_BOUNDARY_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(ELITE_BOUNDARY_GROUP, "Default", false)

local function applyGroup(instance, group)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = group
	end
end

local function bindModel(model, group)
	for _, descendant in ipairs(model:GetDescendants()) do
		applyGroup(descendant, group)
	end
	model.DescendantAdded:Connect(function(descendant)
		applyGroup(descendant, group)
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		bindModel(character, PLAYER_GROUP)
	end)
	if player.Character then
		bindModel(player.Character, PLAYER_GROUP)
	end
end

local function bindMonster(instance)
	if instance:IsA("Model") then
		bindModel(instance, MONSTER_GROUP)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(bindMonster)
for _, monster in ipairs(CollectionService:GetTagged("CombatTarget")) do
	bindMonster(monster)
end
