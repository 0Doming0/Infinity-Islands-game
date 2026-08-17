-- As ilhas do MVP sao arenas independentes. Os conectores fisicos continuam
-- existindo como metadado/logica de rota, mas nao devem aparecer nem permitir
-- travessia a pe. A progressao entre arenas usa AssistedIslandTransport.

local Workspace = game:GetService("Workspace")

local VERSION = "AutomaticIslandTransitConnectorSuppressionV1"

local function suppress(instance)
	if not instance:IsA("BasePart")
		or instance:GetAttribute("IsRoundConnector") ~= true
	then
		return
	end

	instance.Transparency = 1
	instance.CanCollide = false
	instance.CanTouch = false
	instance.CanQuery = false
	instance.CastShadow = false
	instance:SetAttribute("SuppressedForAutomaticIslandTransit", true)

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = false
		elseif descendant:IsA("GuiObject") then
			descendant.Visible = false
		end
	end
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	suppress(descendant)
end

Workspace.DescendantAdded:Connect(function(instance)
	-- O gerador pode configurar atributos alguns frames depois de parentear a
	-- Part. Fazemos uma checagem imediata e outra adiada sem interferir no
	-- processo de validacao da geometria.
	suppress(instance)
	task.defer(function()
		if instance.Parent then
			suppress(instance)
		end
	end)
end)

Workspace:SetAttribute("DungeonInterIslandConnectorSuppressionReady", true)
Workspace:SetAttribute("DungeonInterIslandConnectorSuppressionVersion", VERSION)
