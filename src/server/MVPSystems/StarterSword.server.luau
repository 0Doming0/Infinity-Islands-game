-- ServerScriptService/MVPSystems/StarterSword
-- Entrega a ClassicSword no primeiro spawn e em todos os respawns.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local SWORD_NAME = "ClassicSword"
local BACKPACK_TIMEOUT = 10

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
	if sword:GetAttribute("CoinMultiplier") == nil then
		sword:SetAttribute("CoinMultiplier", 1.0)
	end
	if sword:GetAttribute("RangeMultiplier") == nil then
		sword:SetAttribute("RangeMultiplier", 1.0)
	end
	if sword:GetAttribute("CriticalChance") == nil then
		sword:SetAttribute("CriticalChance", 0.03)
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
	local starterGear = player:FindFirstChild("StarterGear")
		or player:WaitForChild("StarterGear", BACKPACK_TIMEOUT)
	if not starterGear then
		warn("[StarterSword] StarterGear nao encontrado para " .. player.Name .. ".")
		return
	end
	if not findSword(starterGear) then
		cloneSword(template, starterGear)
	end
end

local function giveSwordForCharacter(player, character)
	local template = getSwordTemplate()
	if not template then
		return
	end

	-- O evento e ligado antes de qualquer espera. Isso impede perder o primeiro
	-- CharacterAdded dos jogadores que entram depois que o servidor ja iniciou.
	local backpack = player:WaitForChild("Backpack", BACKPACK_TIMEOUT)
	if not backpack then
		warn("[StarterSword] Backpack nao encontrado para " .. player.Name .. ".")
		return
	end

	-- Um Backpack antigo pode ser destruido enquanto o personagem esta nascendo.
	-- So entregamos a arma se ambos ainda pertencem ao spawn que iniciou a tarefa.
	if player.Parent ~= Players or player.Character ~= character or backpack.Parent ~= player then
		return
	end

	ensureStarterGear(player, template)

	if not findSword(backpack) and not findSword(character) then
		cloneSword(template, backpack)
	end

	print("[StarterSword] Espada inicial garantida para " .. player.Name .. ".")
end

local function setupPlayer(player)
	local function onCharacterAdded(character)
		task.spawn(giveSwordForCharacter, player, character)
	end

	-- Conecta primeiro; nunca deixe uma espera acontecer antes desta conexao.
	player.CharacterAdded:Connect(onCharacterAdded)

	-- Cobre jogadores cujo personagem nasceu antes deste script iniciar.
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

print("[StarterSword] Sistema iniciado; espada garantida por CharacterAdded.")
