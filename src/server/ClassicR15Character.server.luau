local Players = game:GetService("Players")

local function makeCharacterClassicR15(character)
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid then
		warn("Humanoid não encontrado em:", character:GetFullName())
		return
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("Personagem não está usando R15:", character:GetFullName())
		return
	end

	local description = humanoid:GetAppliedDescription()

	-- Mantém roupas, rosto, cabelo, acessórios e cores do jogador.
	-- Remove apenas as partes corporais personalizadas.
	description.Head = 0
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0

	-- Proporções clássicas e quadradas.
	description.BodyTypeScale = 0
	description.ProportionScale = 0

	-- Tamanho próximo do avatar clássico.
	description.HeightScale = 1
	description.WidthScale = 1
	description.HeadScale = 1
	description.DepthScale = 1

	local success, errorMessage = pcall(function()
		humanoid:ApplyDescription(description)
	end)

	if not success then
		warn("Não foi possível aplicar o corpo R15 clássico:", errorMessage)
	end
end

local function onPlayerAdded(player)
	player.CharacterAppearanceLoaded:Connect(function(character)
		makeCharacterClassicR15(character)
	end)

	if player.Character and player:HasAppearanceLoaded() then
		makeCharacterClassicR15(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end