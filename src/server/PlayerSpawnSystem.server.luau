--[[
	PlayerSpawnSystem.server.lua

	Sistema de spawn aleatorio para o jogo de exploracao nos ceus.
	Apos a geracao procedural inicial completar, teleporta cada jogador
	para uma plataforma aleatoria dentro da estrutura gerada.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- Espera a pasta de estruturas procedurais existir.
local generatedFolder = Workspace:FindFirstChild("ProceduralStructures")
while not generatedFolder do
	task.wait(0.5)
	generatedFolder = Workspace:FindFirstChild("ProceduralStructures")
end

-- Espera a geracao inicial completar.
while not generatedFolder:GetAttribute("InitialGenerationComplete") do
	task.wait(0.5)
end

-- Coleta as posicoes de spawn validas a partir das plataformas geradas.
local function getSpawnPosition()
	local platforms = CollectionService:GetTagged("ProceduralPlatform")
	if #platforms == 0 then
		return nil
	end

	-- Filtra apenas plataformas que ainda existem e nao sao obstaculos de passagem.
	local validPlatforms = {}
	for _, platform in platforms do
		if platform.Parent then
			local isPassage = platform:GetAttribute("IsPassageObstacle") or false
			if not isPassage then
				table.insert(validPlatforms, platform)
			end
		end
	end

	if #validPlatforms == 0 then
		return nil
	end

	local platform = validPlatforms[math.random(1, #validPlatforms)]
	local surfaceY = platform:GetAttribute("SurfaceY") or (platform.Position.Y + platform.Size.Y * 0.5)

	-- Posicao aleatoria dentro da plataforma (40% do raio para evitar bordas).
	local halfX = platform.Size.X * 0.4
	local halfZ = platform.Size.Z * 0.4
	local offsetX = math.random() * (halfX * 2) - halfX
	local offsetZ = math.random() * (halfZ * 2) - halfZ

	return Vector3.new(platform.Position.X + offsetX, surfaceY + 3, platform.Position.Z + offsetZ)
end

local function spawnPlayer(character)
	local position = getSpawnPosition()
	if not position then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(position)
	elseif character:IsA("Model") then
		character:PivotTo(CFrame.new(position))
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		-- Pequeno delay para garantir que o character esta totalmente carregado.
		task.wait(0.1)
		spawnPlayer(character)
	end)

	-- Se o character ja existe (caso raro).
	if player.Character then
		spawnPlayer(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end