-- ChestNativePromptMode
--
-- Politica simples de interacao de baus para o MVP:
-- deixa o proprio ProximityPrompt do Roblox desenhar e processar a interface
-- correta para teclado, gamepad e touch. Nao existe UI customizada de bau aqui.
--
-- Os servicos de bau continuam sendo a unica autoridade de recompensa/abertura;
-- este script altera somente a apresentacao/input nativo dos prompts marcados.

local VERSION = "ChestNativePromptV1_RobloxDefault"

local observed = setmetatable({}, { __mode = "k" })

local function isChestPrompt(prompt)
	return prompt
		and prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute("UseSubtleChestPrompt") == true
end

local function applyNativeMode(prompt)
	if not isChestPrompt(prompt) or not prompt.Parent then
		return
	end

	-- Default delega toda a adaptacao de dispositivo ao engine do Roblox:
	-- PC mostra a tecla configurada, gamepad mostra o botao e mobile recebe
	-- a interface tocavel nativa do ProximityPrompt.
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false

	if prompt.ActionText == "" then
		prompt.ActionText = "Abrir"
	end

	prompt:SetAttribute("DungeonNativeChestPrompt", true)
	prompt:SetAttribute("DungeonNativeChestPromptVersion", VERSION)
end

local function observePrompt(prompt)
	if not prompt:IsA("ProximityPrompt") or observed[prompt] then
		return
	end
	observed[prompt] = true

	applyNativeMode(prompt)

	-- Alguns sistemas podem marcar o prompt logo depois de parentear. Este
	-- listener garante que ele ainda migre para o modo nativo sem polling.
	prompt:GetAttributeChangedSignal("UseSubtleChestPrompt"):Connect(function()
		applyNativeMode(prompt)
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
workspace:SetAttribute("DungeonChestInteractionPolicy", "RobloxNativeProximityPrompt")
workspace:SetAttribute("DungeonChestCustomClientUIEnabled", false)
