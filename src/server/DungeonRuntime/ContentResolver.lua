local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)

local ContentResolver = {}

local CATEGORY_NAMES = {
	"Islands",
	"Enemies",
	"Bosses",
	"Decorations",
}

local EQUIPMENT_NAMES = {
	"Swords",
	"Wings",
	"Companions",
	"Abilities",
}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

function ContentResolver.EnsureStructure()
	local root = ensureFolder(ServerStorage, "GameContent")
	ensureFolder(root, "Phases")
	local equipment = ensureFolder(root, "Equipment")
	for _, category in ipairs(EQUIPMENT_NAMES) do
		ensureFolder(equipment, category)
	end
	ensureFolder(root, "SharedModels")
	return root
end

local function hasUsableChildren(folder)
	if not folder then
		return false
	end
	for _, descendant in ipairs(folder:GetDescendants()) do
		if not descendant:IsA("Folder") then
			return true
		end
	end
	return false
end

local function legacyFolder(name)
	local legacy = ServerStorage:FindFirstChild("MVPAssets")
	return legacy and legacy:FindFirstChild(name) or nil
end

function ContentResolver.GetPhase(phaseId)
	local phases = ContentResolver.EnsureStructure():WaitForChild("Phases")
	local definition = PhaseConfig.Get(phaseId)
	if not definition then
		return nil
	end
	return phases:FindFirstChild(definition.AssetFolder)
end

function ContentResolver.GetPhaseCategory(phaseId, category)
	if not table.find(CATEGORY_NAMES, category) then
		return nil
	end
	local phase = ContentResolver.GetPhase(phaseId)
	return phase and phase:FindFirstChild(category) or nil
end

function ContentResolver.GetEquipment(category)
	local configured = ContentResolver.EnsureStructure():WaitForChild("Equipment"):FindFirstChild(category)
	if hasUsableChildren(configured) then
		return configured
	end
	local legacyName = category == "Companions" and "Monsters" or category
	return legacyFolder(legacyName) or configured
end

function ContentResolver.GetSharedModels(category)
	local shared = ContentResolver.EnsureStructure():WaitForChild("SharedModels")
	local configured = shared:FindFirstChild(category)
	if hasUsableChildren(configured) then
		return configured
	end
	return legacyFolder(category) or configured
end

function ContentResolver.FindBossArena(phaseId)
	local islands = ContentResolver.GetPhaseCategory(phaseId, "Islands")
	local arenaFolder = islands and islands:FindFirstChild("BossArena")
	if not arenaFolder then
		return nil
	end
	return arenaFolder:FindFirstChildWhichIsA("Model")
		or arenaFolder:FindFirstChildWhichIsA("BasePart")
end

function ContentResolver.FindBoss(phaseId, bossId)
	local bosses = ContentResolver.GetPhaseCategory(phaseId, "Bosses")
	if not bosses then
		return nil
	end
	local exact = bosses:FindFirstChild(bossId, true)
	if exact then
		return exact
	end
	for _, candidate in ipairs(bosses:GetDescendants()) do
		if candidate:IsA("Model") and candidate:GetAttribute("BossId") == bossId then
			return candidate
		end
	end
	return nil
end

return ContentResolver
