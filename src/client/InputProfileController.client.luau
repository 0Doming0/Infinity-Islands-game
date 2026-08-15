-- Mobile Dungeon Mode — Task 01: input profile + orientation foundation.
--
-- A entrada ativa pode mudar durante a run, mas o modo de apresentacao da
-- Dungeon e decidido uma unica vez ao entrar. Isso evita rotacionar a tela no
-- meio do combate quando o jogador conecta um controle/teclado.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonInputProfileV1"

local function preferredInputName()
	local success, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if success and preferred ~= nil then
		local raw = tostring(preferred)
		local name = string.match(raw, "([^%.]+)$") or raw
		if name == "Touch" then
			return "Touch"
		elseif name == "Gamepad" then
			return "Gamepad"
		elseif name == "KeyboardAndMouse" then
			return "KeyboardMouse"
		end
	end

	-- Fallback conservador para ambientes onde PreferredInput ainda nao esteja
	-- disponivel (ou em alguns modos de emulacao do Studio).
	if UserInputService.TouchEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

local entryProfile = preferredInputName()
local mobileDungeonMode = entryProfile == "Touch"
local previousOrientation = playerGui.ScreenOrientation
local MOBILE_ORIENTATION = Enum.ScreenOrientation.LandscapeSensor

local function publishCurrentProfile()
	local current = preferredInputName()
	player:SetAttribute("DungeonCurrentInputProfile", current)
	playerGui:SetAttribute("DungeonCurrentInputProfile", current)
	return current
end

local function applyEntryPresentation()
	player:SetAttribute("DungeonEntryInputProfile", entryProfile)
	player:SetAttribute("DungeonMobileMode", mobileDungeonMode)
	player:SetAttribute("DungeonMobileLandscapeRequested", mobileDungeonMode)
	player:SetAttribute("DungeonInputProfileVersion", VERSION)

	playerGui:SetAttribute("DungeonEntryInputProfile", entryProfile)
	playerGui:SetAttribute("DungeonMobileMode", mobileDungeonMode)
	playerGui:SetAttribute("DungeonMobileLandscapeRequested", mobileDungeonMode)
	playerGui:SetAttribute("DungeonInputProfileVersion", VERSION)

	if mobileDungeonMode then
		local success, err = pcall(function()
			playerGui.ScreenOrientation = MOBILE_ORIENTATION
		end)
		player:SetAttribute("DungeonMobileLandscapeApplied", success)
		playerGui:SetAttribute("DungeonMobileLandscapeApplied", success)
		if not success then
			warn("[InputProfileController] Falha ao solicitar portrait: " .. tostring(err))
		end
	else
		-- Nao forca landscape em teclado/gamepad. Preserva a orientacao definida
		-- pela plataforma/experiencia para PC, console e dispositivos hibridos.
		player:SetAttribute("DungeonMobileLandscapeApplied", false)
		playerGui:SetAttribute("DungeonMobileLandscapeApplied", false)
	end
end

local function onPreferredInputChanged()
	-- Somente o perfil atual e atualizado. DungeonMobileMode e entryProfile
	-- permanecem imutaveis ate a proxima entrada na Dungeon.
	publishCurrentProfile()
end

applyEntryPresentation()
publishCurrentProfile()

local preferredChanged
local success = pcall(function()
	preferredChanged = UserInputService:GetPropertyChangedSignal("PreferredInput")
end)
if success and preferredChanged then
	preferredChanged:Connect(onPreferredInputChanged)
end

-- Diagnostico local para as proximas tarefas de camera/HUD/combate.
player:SetAttribute("DungeonInputProfileReady", true)
playerGui:SetAttribute("DungeonInputProfileReady", true)

script.Destroying:Connect(function()
	-- Normalmente a troca de Place recria PlayerGui. O restore existe para
	-- permitir testes/reload do script no Studio sem deixar a sessao travada.
	if mobileDungeonMode and playerGui.Parent then
		pcall(function()
			playerGui.ScreenOrientation = previousOrientation
		end)
	end
end)
