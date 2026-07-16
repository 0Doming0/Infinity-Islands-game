--[[
	Sky Dungeon - SwordService

	Clona espadas de ServerStorage > MVPAssets > Swords, valida ataques no
	servidor e informa ao ScoreService o multiplicador da espada equipada.
	O nome deste ModuleScript e permanente e nao deve receber numero de versao.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ScoreService = require(script.Parent.ScoreService_SkyDungeon_V10)

local CONFIG = {
	BASE_DAMAGE = 25,
	ATTACK_COOLDOWN = 0.65,
	HITBOX_SIZE = Vector3.new(6, 6, 7),
	HITBOX_FORWARD_OFFSET = 3.5,
	MAX_HIT_DISTANCE = 9,
}

local SwordService = {}
local started = false
local activeSword = {}
local connectedTools = setmetatable({}, { __mode = "k" })
local lastAttackAt = setmetatable({}, { __mode = "k" })
local warnedMissingTemplate = false

local function getSwordsFolder()
	local assets = ServerStorage:FindFirstChild("MVPAssets")
	return assets and assets:FindFirstChild("Swords")
end

local function isEnabledSwordTemplate(instance)
	return instance:IsA("Tool")
		and instance:GetAttribute("Enabled") ~= false
		and type(instance:GetAttribute("SwordId")) == "string"
		and instance:GetAttribute("SwordId") ~= ""
		and instance:FindFirstChild("Handle") ~= nil
		and instance.Handle:IsA("BasePart")
end

local function getStarterTemplate()
	local folder = getSwordsFolder()
	if not folder then
		return nil
	end
	local candidates = {}
	for _, child in ipairs(folder:GetChildren()) do
		if isEnabledSwordTemplate(child) then
			table.insert(candidates, child)
		end
	end
	table.sort(candidates, function(a, b)
		local priorityA = tonumber(a:GetAttribute("StarterPriority")) or 0
		local priorityB = tonumber(b:GetAttribute("StarterPriority")) or 0
		if priorityA == priorityB then
			return a.Name < b.Name
		end
		return priorityA > priorityB
	end)
	return candidates[1]
end

local function removeEmbeddedScripts(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
end

local function findMonsterFromPart(part)
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("IsSkyMonster") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function performAttack(player, tool)
	local character = player.Character
	if not character or tool.Parent ~= character or activeSword[player] ~= tool then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = workspace:GetServerTimeNow()
	if now - (lastAttackAt[tool] or 0) < CONFIG.ATTACK_COOLDOWN then
		return
	end
	lastAttackAt[tool] = now

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.MaxParts = 50

	local hitboxCFrame = rootPart.CFrame * CFrame.new(0, 0, -CONFIG.HITBOX_FORWARD_OFFSET)
	local parts = workspace:GetPartBoundsInBox(hitboxCFrame, CONFIG.HITBOX_SIZE, overlap)
	local seen = {}
	local closestMonster
	local closestDistance = math.huge

	for _, part in ipairs(parts) do
		local monster = findMonsterFromPart(part)
		if monster and not seen[monster] then
			seen[monster] = true
			local monsterHumanoid = monster:FindFirstChildOfClass("Humanoid")
			local monsterRoot = monster:FindFirstChild("HumanoidRootPart") or monster.PrimaryPart
			if monsterHumanoid and monsterRoot and monsterHumanoid.Health > 0 then
				local distance = (monsterRoot.Position - rootPart.Position).Magnitude
				if distance <= CONFIG.MAX_HIT_DISTANCE and distance < closestDistance then
					closestMonster = monster
					closestDistance = distance
				end
			end
		end
	end

	if not closestMonster then
		return
	end

	local monsterHumanoid = closestMonster:FindFirstChildOfClass("Humanoid")
	closestMonster:SetAttribute("LastHitUserId", player.UserId)
	closestMonster:SetAttribute("LastHitAt", now)
	closestMonster:SetAttribute("LastHitSwordId", tool:GetAttribute("SwordId"))
	monsterHumanoid:TakeDamage(CONFIG.BASE_DAMAGE)
end

local function connectSword(player, tool)
	if connectedTools[tool] or not tool:IsA("Tool") or tool:GetAttribute("ServerValidatedSword") ~= true then
		return
	end
	connectedTools[tool] = true
	tool.CanBeDropped = false

	tool.Equipped:Connect(function()
		if tool.Parent ~= player.Character then
			return
		end
		activeSword[player] = tool
		ScoreService.SetSwordMultiplier(player, tool:GetAttribute("ScoreMultiplier") or 1)
	end)

	tool.Unequipped:Connect(function()
		if activeSword[player] == tool then
			activeSword[player] = nil
			ScoreService.SetSwordMultiplier(player, 1)
		end
	end)

	tool.Activated:Connect(function()
		performAttack(player, tool)
	end)

	tool.Destroying:Connect(function()
		if activeSword[player] == tool then
			activeSword[player] = nil
			ScoreService.SetSwordMultiplier(player, 1)
		end
	end)
end

local function hasServerSword(player)
	local containers = { player:FindFirstChild("Backpack"), player.Character }
	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("ServerValidatedSword") == true then
					connectSword(player, child)
					return true
				end
			end
		end
	end
	return false
end

local function giveStarterSword(player)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack or hasServerSword(player) then
		return
	end

	local template = getStarterTemplate()
	if not template then
		if not warnedMissingTemplate then
			warn("[SkyDungeon] Nenhuma espada valida em ServerStorage > MVPAssets > Swords.")
			warnedMissingTemplate = true
		end
		return
	end

	local sword = template:Clone()
	removeEmbeddedScripts(sword)
	sword:SetAttribute("ServerValidatedSword", true)
	sword:SetAttribute("SwordId", template:GetAttribute("SwordId"))
	sword:SetAttribute("ScoreMultiplier", math.max(1, tonumber(template:GetAttribute("ScoreMultiplier")) or 1))
	sword.Parent = backpack
	connectSword(player, sword)
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function()
		activeSword[player] = nil
		ScoreService.SetSwordMultiplier(player, 1)
		task.delay(0.5, giveStarterSword, player)
	end)
	player.CharacterRemoving:Connect(function()
		activeSword[player] = nil
		ScoreService.SetSwordMultiplier(player, 1)
	end)
	if player.Character then
		task.delay(0.5, giveStarterSword, player)
	end
end

function SwordService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		activeSword[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
end

return SwordService
