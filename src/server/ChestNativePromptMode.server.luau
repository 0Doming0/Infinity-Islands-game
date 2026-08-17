-- ChestNativePromptMode
--
-- Politica hibrida de interacao de baus:
--   PC/gamepad: ProximityPrompt nativo do Roblox.
--   Mobile: MobileChestProximityUI troca o Style localmente para Custom e mostra
--   um BillboardGui tocavel acima do bau mais proximo quando o personagem entra
--   no alcance fisico.
--
-- Os servicos de bau continuam sendo a unica autoridade de recompensa/abertura.
-- Este script apenas garante uma configuracao base consistente dos prompts.

local VERSION = "ChestPromptBaseV3_NativeDesktopMobileDistanceBillboard"

local observed = setmetatable({}, { __mode = "k" })

local function isChestPrompt(prompt)
	return prompt
		and prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function applyBaseMode(prompt)
	if not isChestPrompt(prompt) or not prompt.Parent then
		return
	end

	-- O servidor publica Default como base para PC/gamepad. Em dispositivos
	-- touch, MobileChestProximityUI esconde esse visual localmente (Style=Custom)
	-- e desenha um BillboardGui acima do bau escolhido somente por distancia.
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false

	if prompt.ActionText == "" then
		prompt.ActionText = "Abrir"
	end

	prompt:SetAttribute("DungeonChestPromptBaseConfigured", true)
	prompt:SetAttribute("DungeonChestPromptBaseVersion", VERSION)
end

local function observePrompt(prompt)
	if not prompt:IsA("ProximityPrompt") or observed[prompt] then
		return
	end
	observed[prompt] = true

	applyBaseMode(prompt)

	-- Alguns sistemas marcam o prompt logo depois de parentear.
	prompt:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
		applyBaseMode(prompt)
	end)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		observePrompt(descendant)
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		observePrompt(descendant)
	end
end)

workspace:SetAttribute("DungeonChestInteractionVersion", VERSION)
workspace:SetAttribute("DungeonChestInteractionPolicy", "NativeDesktop_MobileDistanceBillboard")
workspace:SetAttribute("DungeonChestMobileCameraDependency", false)
workspace:SetAttribute("DungeonChestMobileProximityUIExpected", true)
workspace:SetAttribute("DungeonChestMobileFixedHUD", false)
