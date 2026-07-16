-- ServerScriptService/MVPSystems/StarterSword
-- Entrega a ClassicSword ao jogador e a mantem disponivel nos respawns.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local SWORD_NAME = "ClassicSword"

local function getSwordTemplate()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	local swords = assets and assets:FindFirstChild("Swords")
	local template = swords and swords:FindFirstChild(SWORD_NAME)

	if not template then
		warn("[StarterSword] ServerStorage/MVPAssets/Swords/ClassicSword nao encontrada.")
		return nil
	end
	if not template:IsA("Tool") then
		warn("[StarterSword] ClassicSword precisa ser uma Tool, mas e " .. template.ClassName .. ".")
		return nil
	end
	if not template:FindFirstChild("Handle") then
		warn("[StarterSword] ClassicSword precisa possuir uma BasePart chamada Handle.")
		return nil
	end
	return template
end

local function findSword(container)
	if not container then
		return nil
	end
	local sword = container:FindFirstChild(SWORD_NAME)
	return sword and sword:IsA("Tool") and sword or nil
end

local function configureSword(sword)
	for _, descendant in sword:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = true
		end
	end

	-- Mantem atributos configurados manualmente e preenche apenas os ausentes.
	if sword:GetAttribute("IsSword") == nil then
		sword:SetAttribute("IsSword", true)
	end
	if sword:GetAttribute("WeaponType") == nil then
		sword:SetAttribute("WeaponType", "Sword")
	end
	if sword:GetAttribute("BaseDamage") == nil then
		sword:SetAttribute("BaseDamage", 20)
	end
	if sword:GetAttribute("AttackSpeed") == nil then
		sword:SetAttribute("AttackSpeed", 1.0)
	end
	if sword:GetAttribute("KnockbackMultiplier") == nil then
		sword:SetAttribute("KnockbackMultiplier", 1.0)
	end
	if sword:GetAttribute("ScoreMultiplier") == nil then
		sword:SetAttribute("ScoreMultiplier", 1.0)
	end
	sword.CanBeDropped = false
	return sword
end

local function cloneSword(template, parent)
	local sword = configureSword(template:Clone())
	sword.Parent = parent
	return sword
end

local function ensureStarterGear(player, template)
	local starterGear = player:WaitForChild("StarterGear")
	if not findSword(starterGear) then
		cloneSword(template, starterGear)
	end
end

local function ensureBackpackSword(player, template)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		warn("[StarterSword] Backpack nao encontrado para " .. player.Name .. ".")
		return
	end

	local character = player.Character
	if findSword(backpack) or findSword(character) then
		return
	end
	cloneSword(template, backpack)
end

local function setupPlayer(player)
	local template = getSwordTemplate()
	if not template then
		return
	end

	ensureStarterGear(player, template)
	ensureBackpackSword(player, template)

	player.CharacterAdded:Connect(function()
		-- O Roblox primeiro recria o Backpack e copia o StarterGear.
		task.delay(0.20, function()
			if player.Parent == Players then
				ensureStarterGear(player, template)
				ensureBackpackSword(player, template)
			end
		end)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

print("[StarterSword] Sistema iniciado; espada inicial: ClassicSword.")
