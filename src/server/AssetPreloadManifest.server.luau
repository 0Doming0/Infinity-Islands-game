--[[
	Sky Dungeon - manifesto leve de assets recorrentes.

	O servidor conhece os templates guardados em ServerStorage, mas o cliente nao.
	Este script publica somente os ContentIds usados por esses templates para que
	cada aparelho possa aquece-los gradualmente antes da primeira aparicao.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MANIFEST_NAME = "SkyDungeonAssetPreloadManifest"
local ASSET_FOLDER_NAME = "MVPAssets"

local CONTENT_PROPERTIES = {
	Animation = { "AnimationId" },
	Beam = { "Texture" },
	Decal = { "Texture" },
	ImageButton = { "Image", "HoverImage", "PressedImage" },
	ImageLabel = { "Image" },
	MeshPart = { "MeshId", "TextureID" },
	ParticleEmitter = { "Texture" },
	ShirtGraphic = { "Graphic" },
	Sound = { "SoundId" },
	SpecialMesh = { "MeshId", "TextureId" },
	SurfaceAppearance = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	Texture = { "Texture" },
	Trail = { "Texture" },
}

local function isUsableContentId(value)
	if typeof(value) ~= "string" or value == "" then
		return false
	end
	return value ~= "rbxassetid://0" and value ~= "0"
end

local function collectContentIds(root)
	local unique = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		local properties = CONTENT_PROPERTIES[descendant.ClassName]
		if properties then
			for _, propertyName in ipairs(properties) do
				local success, value = pcall(function()
					return descendant[propertyName]
				end)
				if success and isUsableContentId(value) then
					unique[value] = true
				end
			end
		end
	end
	local result = {}
	for contentId in pairs(unique) do
		table.insert(result, contentId)
	end
	table.sort(result)
	return result
end

local previous = ReplicatedStorage:FindFirstChild(MANIFEST_NAME)
if previous then
	previous:Destroy()
end

local manifest = Instance.new("Folder")
manifest.Name = MANIFEST_NAME
manifest:SetAttribute("Ready", false)
manifest.Parent = ReplicatedStorage

-- Da tempo para os servicos criarem seus prototipos de fallback quando o Studio
-- ainda nao possui todas as pastas de assets.
local assets = ServerStorage:FindFirstChild(ASSET_FOLDER_NAME) or ServerStorage:WaitForChild(ASSET_FOLDER_NAME, 5)
local contentIds = assets and collectContentIds(assets) or {}

for index, contentId in ipairs(contentIds) do
	local entry = Instance.new("StringValue")
	entry.Name = string.format("Asset_%04d", index)
	entry.Value = contentId
	entry.Parent = manifest
end

manifest:SetAttribute("AssetCount", #contentIds)
manifest:SetAttribute("Ready", true)
