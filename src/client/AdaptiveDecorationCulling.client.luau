--[[
	VERSION: V3_ISLAND_GRASS_GUARANTEE

	Culling local de detalhes puramente visuais.

	Reduzido: oculta grama distante e decoracoes muito distantes.
	Extremo: oculta grama 3D e encurta a distancia dos detalhes.

	A camada plana das ilhas permanece visivel em qualquer distancia. Como cada
	ilha usa somente uma cobertura grande, oculta-la economizava pouco e podia
	revelar terra marrom quando a textura externa ainda nao estivesse carregada.
	Somente as muitas coberturas pequenas das pontes usam o LOD distante.
	Parts estruturais, baus, inimigos e itens nunca sao registrados aqui.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local tracked = setmetatable({}, { __mode = "k" })

local REDUCED_GRASS_DISTANCE = 105
local EXTREME_FLAT_GRASS_DISTANCE = 82
local REDUCED_DECORATION_DISTANCE = 145
local EXTREME_DECORATION_DISTANCE = 58
local REDUCED_UPDATE_SECONDS = 0.55
local EXTREME_UPDATE_SECONDS = 0.8
local DISTANT_TEXTURE_NAME = "DistantGrassTopLOD"
local DEFAULT_GRASS_TEXTURE_ID = "rbxassetid://7568838452"
local DEFAULT_GRASS_TILE_STUDS = 8

local function getKind(instance)
	if instance:IsA("BasePart") and instance:GetAttribute("HasFlatGrassTop") == true then
		return "GrassSource"
	elseif instance:GetAttribute("IsFlatGrassLayer") == true then
		return "FlatGrass"
	elseif instance:GetAttribute("IsSkyGrass") == true then
		return "Grass"
	elseif instance:GetAttribute("IsSkyDecoration") == true then
		return "Decoration"
	end
	return nil
end

local function getGrassSetting(instance, state, attributeName, fallback)
	local value = instance:GetAttribute(attributeName)
	if value ~= nil then
		return value
	end
	local source = state and state.SourcePart
	if source and source.Parent then
		value = source:GetAttribute(attributeName)
		if value ~= nil then
			return value
		end
	end
	return fallback
end

local function collectParts(instance)
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function findGrassSourcePart(instance)
	local parent = instance.Parent
	if not parent then
		return nil
	end

	-- Nos conectores o topo 3D e filho direto do proprio bloco.
	if parent:IsA("BasePart") then
		return parent
	end

	-- Nas ilhas o piso e o topo sao irmaos dentro do mesmo Model.
	local sourceName = instance:GetAttribute("GrassSourcePartName")
	if type(sourceName) == "string" and sourceName ~= "" then
		local source = parent:FindFirstChild(sourceName)
		if source and source:IsA("BasePart") then
			return source
		end
	end
	return nil
end

local function register(instance)
	if tracked[instance] then
		return
	end
	local kind = getKind(instance)
	if not kind then
		return
	end

	local parts = collectParts(instance)
	local original = {}
	for _, part in ipairs(parts) do
		original[part] = part.LocalTransparencyModifier
	end

	local sourcePart
	if kind == "GrassSource" then
		sourcePart = instance
	elseif kind == "FlatGrass" then
		sourcePart = findGrassSourcePart(instance)
	end

	tracked[instance] = {
		Kind = kind,
		Parts = parts,
		Original = original,
		SourcePart = sourcePart,
		DistantTexture = nil,
		Hidden = false,
	}
end

local function ensureDistantGrassTexture(instance, state)
	local source = state.SourcePart
	if not source or not source.Parent then
		source = findGrassSourcePart(instance)
		state.SourcePart = source
	end
	if not source then
		return nil
	end

	local texture = state.DistantTexture
	if texture and texture.Parent == source then
		return texture
	end

	local existing = source:FindFirstChild(DISTANT_TEXTURE_NAME)
	if existing and existing:IsA("Texture") then
		texture = existing
	else
		texture = Instance.new("Texture")
		texture.Name = DISTANT_TEXTURE_NAME
		texture.Face = Enum.NormalId.Top
		texture.Texture = getGrassSetting(
			instance,
			state,
			"DistantGrassTextureId",
			DEFAULT_GRASS_TEXTURE_ID
		)
		local tileStuds = tonumber(getGrassSetting(
			instance,
			state,
			"DistantGrassTextureTileStuds",
			DEFAULT_GRASS_TILE_STUDS
		))
		texture.StudsPerTileU = math.max(1, tileStuds)
		texture.StudsPerTileV = math.max(1, tileStuds)
		-- Fica permanentemente sob a camada 3D. Perto ela esta coberta; longe
		-- continua visivel mesmo se o Streaming remover a camada antes do piso.
		texture.Transparency = 0
		texture.Parent = source
	end

	local color = getGrassSetting(instance, state, "DistantGrassColor", nil)
	if typeof(color) == "Color3" then
		texture.Color3 = color
	elseif instance:IsA("BasePart") and state.Kind == "FlatGrass" then
		texture.Color3 = instance.Color
	end
	texture.Transparency = 0
	state.DistantTexture = texture
	return texture
end

local function setHidden(instance, state, hidden)
	if state.Hidden == hidden then
		if state.Kind == "FlatGrass" and state.DistantTexture then
			state.DistantTexture.Color3 = instance.Color
			state.DistantTexture.Transparency = 0
		end
		return
	end

	local distantTexture
	if state.Kind == "FlatGrass" or state.Kind == "GrassSource" then
		distantTexture = ensureDistantGrassTexture(instance, state)
		-- Nunca deixa o bloco marrom se a face distante nao puder ser criada.
		if state.Kind == "FlatGrass" and hidden and not distantTexture then
			hidden = false
		end
	end

	state.Hidden = hidden
	for _, part in ipairs(state.Parts) do
		if part.Parent then
			part.LocalTransparencyModifier = hidden
				and 1
				or (state.Original[part] or 0)
		end
	end

	if distantTexture and distantTexture.Parent then
		if state.Kind == "FlatGrass" then
			distantTexture.Color3 = instance.Color
		end
		distantTexture.Transparency = 0
	end
end

local function getPosition(instance, state)
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		local primary = instance.PrimaryPart
		if primary and primary.Parent then
			return primary.Position
		end
		local ok, pivot = pcall(instance.GetPivot, instance)
		if ok then
			return pivot.Position
		end
	end

	for _, part in ipairs(state.Parts) do
		if part.Parent then
			return part.Position
		end
	end
	return nil
end

local function isIslandFlatGrass(instance, state)
	if state.Kind ~= "FlatGrass" then
		return false
	end
	local coverage = instance:GetAttribute("GrassTopCoverage")
	if coverage == "Terrain" then
		return true
	end
	local source = state.SourcePart
	return source ~= nil and source:GetAttribute("BlockType") == "Terrain"
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	register(descendant)
end

Workspace.DescendantAdded:Connect(function(descendant)
	register(descendant)
	local state = tracked[descendant]
	if state and (state.Kind == "GrassSource" or state.Kind == "FlatGrass") then
		ensureDistantGrassTexture(descendant, state)
	end
end)

-- Cria imediatamente o acabamento nos pisos ja carregados. Ele nao depende do
-- nivel de desempenho nem da distancia para existir.
for instance, state in pairs(tracked) do
	if state.Kind == "GrassSource" or state.Kind == "FlatGrass" then
		ensureDistantGrassTexture(instance, state)
	end
end

local lastLevel = -1
while true do
	local level = tonumber(player:GetAttribute("PerformanceLevel")) or 0
	if level <= 0 and lastLevel == level then
		task.wait(1)
		continue
	end
	local camera = Workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position

	for instance, state in pairs(tracked) do
		if not instance:IsDescendantOf(Workspace) then
			tracked[instance] = nil
			continue
		end

		if level <= 0 then
			if lastLevel ~= level then
				setHidden(instance, state, false)
			end
			continue
		end

		if state.Kind == "GrassSource" then
			ensureDistantGrassTexture(instance, state)
			continue
		end

		local hidden = false
		if level >= 2 and state.Kind == "Grass" then
			hidden = true
		elseif cameraPosition then
			local position = getPosition(instance, state)
			if position then
				local distance = (position - cameraPosition).Magnitude
				if state.Kind == "Decoration" then
					local maxDistance = level >= 2
						and EXTREME_DECORATION_DISTANCE
						or REDUCED_DECORATION_DISTANCE
					hidden = distance > maxDistance
				elseif state.Kind == "FlatGrass" and not isIslandFlatGrass(instance, state) then
					local maxDistance = level >= 2
						and EXTREME_FLAT_GRASS_DISTANCE
						or REDUCED_GRASS_DISTANCE
					hidden = distance > maxDistance
				else
					hidden = distance > REDUCED_GRASS_DISTANCE
				end
			end
		end
		setHidden(instance, state, hidden)
	end

	lastLevel = level
	if level >= 2 then
		task.wait(EXTREME_UPDATE_SECONDS)
	elseif level >= 1 then
		task.wait(REDUCED_UPDATE_SECONDS)
	else
		task.wait(1)
	end
end
