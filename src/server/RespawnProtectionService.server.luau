-- Imunidade autoritativa apos cada nascimento/renascimento.
--
-- O WaterRiseSystem continua escolhendo e validando o ponto seguro. Este
-- servico inicia a janela somente quando RespawnState vira Ready, portanto o
-- tempo de protecao nao e consumido enquanto o personagem ainda esta ancorado
-- ou aguardando uma ilha de resgate.

local Players = game:GetService("Players")

local VERSION = "AuthoritativeRespawnImmunityV1"
local PROTECTION_SECONDS = 6
local FORCE_FIELD_NAME = "RespawnImmunityProtection"
local HIGHLIGHT_NAME = "RespawnProtectionHighlight"

local states = setmetatable({}, { __mode = "k" })

workspace:SetAttribute("RespawnProtectionSystemVersion", VERSION)
workspace:SetAttribute("RespawnProtectionDurationSeconds", PROTECTION_SECONDS)

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function clearVisuals(character)
	if not character then
		return
	end
	local forceField = character:FindFirstChild(FORCE_FIELD_NAME)
	if forceField then
		forceField:Destroy()
	end
	local highlight = character:FindFirstChild(HIGHLIGHT_NAME)
	if highlight then
		highlight:Destroy()
	end
	character:SetAttribute("RespawnProtectionActive", false)
	character:SetAttribute("RespawnProtectionUntil", nil)
end

local function clearPlayerAttributes(player, serial)
	if serial ~= nil and tonumber(player:GetAttribute("RespawnProtectionSerial")) ~= serial then
		return
	end
	player:SetAttribute("RespawnProtectionActive", false)
	player:SetAttribute("RespawnProtectionUntil", nil)
	player:SetAttribute("LastRespawnProtectionEndedAt", serverTime())
end

local function finishProtection(player, character, serial)
	local state = states[player]
	if not state
		or state.Serial ~= serial
		or state.Character ~= character
		or player.Character ~= character
	then
		return
	end
	clearVisuals(character)
	clearPlayerAttributes(player, serial)
	state.Until = 0
end

local function activateProtection(player, character)
	if not character or player.Character ~= character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	if player:GetAttribute("RespawnState") ~= "Ready"
		or character:GetAttribute("RespawnReady") ~= true
	then
		return false
	end

	local state = states[player]
	if not state then
		state = { Serial = 0, Character = nil, Until = 0 }
		states[player] = state
	end
	local now = serverTime()
	if state.Character == character and state.Until > now then
		return true
	end

	state.Serial += 1
	state.Character = character
	state.Until = now + PROTECTION_SECONDS
	local serial = state.Serial

	clearVisuals(character)

	local forceField = Instance.new("ForceField")
	forceField.Name = FORCE_FIELD_NAME
	forceField.Visible = false
	forceField.Parent = character

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(88, 207, 255)
	highlight.FillTransparency = 0.84
	highlight.OutlineColor = Color3.fromRGB(188, 239, 255)
	highlight.OutlineTransparency = 0.12
	highlight.Parent = character

	character:SetAttribute("RespawnProtectionActive", true)
	character:SetAttribute("RespawnProtectionUntil", state.Until)
	character:SetAttribute("RespawnProtectionSerial", serial)
	character:SetAttribute("RespawnProtectionVersion", VERSION)

	player:SetAttribute("RespawnProtectionActive", true)
	player:SetAttribute("RespawnProtectionUntil", state.Until)
	player:SetAttribute("RespawnProtectionDuration", PROTECTION_SECONDS)
	player:SetAttribute("RespawnProtectionSerial", serial)
	player:SetAttribute("RespawnProtectionVersion", VERSION)
	player:SetAttribute("LastRespawnProtectionStartedAt", now)

	task.delay(PROTECTION_SECONDS, function()
		finishProtection(player, character, serial)
	end)
	return true
end

local function tryActivate(player)
	local character = player.Character
	if not character then
		return
	end
	if activateProtection(player, character) then
		return
	end
	-- Em servidores carregados sob pressao, Humanoid/HRP podem chegar alguns
	-- frames depois de RespawnState. Pequenas tentativas cobrem essa corrida.
	task.spawn(function()
		for _ = 1, 20 do
			if player.Parent ~= Players or player.Character ~= character then
				return
			end
			if activateProtection(player, character) then
				return
			end
			task.wait(0.1)
		end
	end)
end

local function setupPlayer(player)
	if states[player] then
		return
	end
	states[player] = { Serial = 0, Character = player.Character, Until = 0 }
	player:SetAttribute("RespawnProtectionActive", false)
	player:SetAttribute("RespawnProtectionVersion", VERSION)

	player:GetAttributeChangedSignal("RespawnState"):Connect(function()
		if player:GetAttribute("RespawnState") == "Ready" then
			tryActivate(player)
		elseif player:GetAttribute("RespawnState") == "Failed" then
			local state = states[player]
			if state then
				state.Serial += 1
				state.Until = 0
			end
			clearVisuals(player.Character)
			clearPlayerAttributes(player)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		local state = states[player]
		if state then
			state.Serial += 1
			state.Character = character
			state.Until = 0
		end
		clearPlayerAttributes(player)
		character:GetAttributeChangedSignal("RespawnReady"):Connect(function()
			if character:GetAttribute("RespawnReady") == true then
				tryActivate(player)
			end
		end)
		if player:GetAttribute("RespawnState") == "Ready" then
			tryActivate(player)
		end
	end)

	player.CharacterRemoving:Connect(function(character)
		local state = states[player]
		if state then
			state.Serial += 1
			state.Until = 0
		end
		clearVisuals(character)
		clearPlayerAttributes(player)
	end)

	if player.Character and player:GetAttribute("RespawnState") == "Ready" then
		tryActivate(player)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
