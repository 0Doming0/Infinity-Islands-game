-- Publica no ReplicatedStorage somente copias visuais dos modelos reais usados
-- pelo jogo. A StartScreen e um LocalScript e, por seguranca, nao pode acessar
-- diretamente ServerStorage/MVPAssets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local SlimeVariants = require(
	script.Parent.BlockParkour:WaitForChild("SlimeVariants")
)

local PREVIEW_ROOT_NAME = "StartScreenPreviewAssets"
local SWORDS_FOLDER_NAME = "Swords"
local COMPANIONS_FOLDER_NAME = "Companions"

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local previewRoot = ensureFolder(ReplicatedStorage, PREVIEW_ROOT_NAME)
local previewSwords = ensureFolder(previewRoot, SWORDS_FOLDER_NAME)
local previewCompanions = ensureFolder(previewRoot, COMPANIONS_FOLDER_NAME)

local function cloneSafely(template)
	local originalArchivable = template.Archivable
	template.Archivable = true
	local success, clone = pcall(template.Clone, template)
	template.Archivable = originalArchivable
	return success and clone or nil
end

local function sanitizeVisualClone(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		elseif
			descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
		then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

local function swordIdOf(template)
	local swordId = template:GetAttribute("SwordId")
	return type(swordId) == "string" and swordId ~= "" and swordId or template.Name
end

local function monsterIdOf(template)
	local monsterId = template:GetAttribute("MonsterId")
	return type(monsterId) == "string" and monsterId ~= "" and monsterId or template.Name
end

local function publishSwords(source)
	previewSwords:ClearAllChildren()
	local published = 0
	for _, template in ipairs(source:GetChildren()) do
		if not template:IsA("Tool") then
			continue
		end
		local clone = cloneSafely(template)
		if not clone then
			warn("[StartScreenPreviewAssets] Nao foi possivel clonar " .. template:GetFullName())
			continue
		end
		local swordId = swordIdOf(template)
		clone.Name = swordId
		clone:SetAttribute("SwordId", swordId)
		clone:SetAttribute("StartScreenPreviewAsset", true)
		sanitizeVisualClone(clone)
		clone.Parent = previewSwords
		published += 1
	end
	previewRoot:SetAttribute("SwordCount", published)
end

local function findMonsterTemplate(source, speciesId)
	local slimeFallback
	for _, template in ipairs(source:GetChildren()) do
		if not template:IsA("Model") then
			continue
		end
		local monsterId = monsterIdOf(template)
		if monsterId == speciesId or template.Name == speciesId then
			return template
		end
		if
			not slimeFallback
			and string.find(speciesId, "Slime$")
			and SlimeVariants.IsSlime(template)
		then
			slimeFallback = template
		end
	end
	return slimeFallback
end

local function publishCompanions(source)
	previewCompanions:ClearAllChildren()
	local published = 0
	for speciesId in pairs(CompanionCatalog.Entries) do
		local template = findMonsterTemplate(source, speciesId)
		if not template then
			warn(
				string.format(
					"[StartScreenPreviewAssets] Modelo real ausente para o companheiro %s.",
					speciesId
				)
			)
			continue
		end
		local clone = cloneSafely(template)
		if not clone or not clone:IsA("Model") then
			warn("[StartScreenPreviewAssets] Nao foi possivel clonar " .. template:GetFullName())
			continue
		end

		local variant = string.match(speciesId, "^(%a+)Slime$")
		if variant and SlimeVariants.IsSlime(clone) then
			SlimeVariants.ConfigureClone(clone, template, Random.new(1), variant)
		end

		local scale = math.clamp(
			tonumber(clone:GetAttribute("CompanionScale")) or 0.72,
			0.3,
			1.5
		)
		pcall(clone.ScaleTo, clone, scale)
		clone.Name = speciesId
		clone:SetAttribute("MonsterId", speciesId)
		clone:SetAttribute("StartScreenPreviewAsset", true)
		clone:SetAttribute("StartScreenPreviewScaled", true)
		sanitizeVisualClone(clone)
		clone.Parent = previewCompanions
		published += 1
	end
	previewRoot:SetAttribute("CompanionCount", published)
end

local sourceConnections = {}
local boundSwords
local boundMonsters
local syncQueued = false

local function disconnectSources()
	for _, connection in ipairs(sourceConnections) do
		connection:Disconnect()
	end
	table.clear(sourceConnections)
end

local function publishAll()
	if not boundSwords or not boundMonsters then
		return
	end
	publishSwords(boundSwords)
	publishCompanions(boundMonsters)
	previewRoot:SetAttribute("Ready", true)
	previewRoot:SetAttribute(
		"Revision",
		(tonumber(previewRoot:GetAttribute("Revision")) or 0) + 1
	)
end

local function queuePublish()
	if syncQueued then
		return
	end
	syncQueued = true
	task.delay(0.15, function()
		syncQueued = false
		publishAll()
	end)
end

local function bindSources(swords, monsters)
	if swords == boundSwords and monsters == boundMonsters then
		return
	end
	disconnectSources()
	boundSwords = swords
	boundMonsters = monsters
	for _, folder in ipairs({ swords, monsters }) do
		table.insert(sourceConnections, folder.ChildAdded:Connect(queuePublish))
		table.insert(sourceConnections, folder.ChildRemoved:Connect(queuePublish))
	end
	publishAll()
end

task.spawn(function()
	while true do
		local assets = ServerStorage:FindFirstChild("MVPAssets")
		local swords = assets and assets:FindFirstChild("Swords")
		local monsters = assets and assets:FindFirstChild("Monsters")
		if swords and swords:IsA("Folder") and monsters and monsters:IsA("Folder") then
			bindSources(swords, monsters)
			return
		end
		task.wait(0.25)
	end
end)
