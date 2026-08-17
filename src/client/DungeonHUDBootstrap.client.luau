--[[
	Infinity Islands - DungeonHUDBootstrap

	Responsabilidades:
	1. garantir que o DungeonHUD autorado no Studio exista em PlayerGui;
	2. respeitar o atributo GUI `invisible = true` como override autoral;
	3. aplicar pequenos ajustes visuais globais em GUIs temporarias do gameplay;
	4. manter PlayerStatus.LevelText sincronizado com o nivel atual do jogador.

	Nenhum elemento visual e criado aqui alem do clone completo do DungeonHUD
	quando o Roblox ainda nao o copiou para PlayerGui.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local visibilityBindings = setmetatable({}, { __mode = "k" })
local levelTextBindings = setmetatable({}, { __mode = "k" })

local function isVisibilityObject(instance)
	return instance:IsA("GuiObject") or instance:IsA("LayerCollector")
end

local function isInitialAttackText(instance)
	if not instance:IsA("TextLabel") or instance.Name ~= "AttackText" then
		return false
	end

	local parent = instance.Parent
	while parent and parent ~= playerGui do
		if parent:IsA("ScreenGui") and parent.Name == "DungeonInitialAttackGuide" then
			return true
		end
		parent = parent.Parent
	end

	return false
end

local function applyTransportMessageStyle(label)
	-- Mesmo estilo visual de AssistedIslandTransportHUD.TransportMessage:
	-- texto limpo, sem painel, branco com contorno preto e escala responsiva.
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.25
	label.TextScaled = true

	local corner = label:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Destroy()
	end

	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not constraint then
		constraint = Instance.new("UITextSizeConstraint")
		constraint.Parent = label
	end
	constraint.MinTextSize = 16
	constraint.MaxTextSize = 30

	label:SetAttribute(
		"DungeonInitialAttackTextVisualPolicy",
		"TransportMessageStyle"
	)
	player:SetAttribute(
		"DungeonInitialAttackTextVisualPolicy",
		"TransportMessageStyle"
	)
end

local function normalizeGameplayGui(instance)
	if not instance or not instance.Parent then
		return
	end

	-- O guia da ilha inicial deve orientar sem dominar a tela.
	if instance:IsA("BillboardGui")
		and instance.Name == "DungeonInitialAttackSword"
	then
		instance.Size = UDim2.fromOffset(26, 26)
		instance.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
		instance.MaxDistance = 90
		player:SetAttribute(
			"DungeonInitialAttackSwordVisualPolicy",
			"Compact26px"
		)
	elseif isInitialAttackText(instance) then
		applyTransportMessageStyle(instance)
	end
end

local function forceInvisibleIfRequested(instance)
	if not instance or not instance.Parent or not isVisibilityObject(instance) then
		return
	end
	if instance:GetAttribute("invisible") ~= true then
		return
	end

	if instance:IsA("GuiObject") then
		if instance.Visible then
			instance.Visible = false
		end
	elseif instance:IsA("LayerCollector") then
		if instance.Enabled then
			instance.Enabled = false
		end
	end
end

local function bindVisibilityAttribute(instance)
	normalizeGameplayGui(instance)

	if not isVisibilityObject(instance) then
		return
	end

	if visibilityBindings[instance] then
		forceInvisibleIfRequested(instance)
		return
	end

	local connections = {}
	visibilityBindings[instance] = connections

	table.insert(connections, instance:GetAttributeChangedSignal("invisible"):Connect(function()
		forceInvisibleIfRequested(instance)
	end))

	if instance:IsA("GuiObject") then
		table.insert(connections, instance:GetPropertyChangedSignal("Visible"):Connect(function()
			forceInvisibleIfRequested(instance)
		end))
	elseif instance:IsA("LayerCollector") then
		table.insert(connections, instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			forceInvisibleIfRequested(instance)
		end))
	end

	forceInvisibleIfRequested(instance)
end

local function scanVisibilityAttributes(root)
	bindVisibilityAttribute(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		bindVisibilityAttribute(descendant)
	end
end

local function validHud(instance)
	return instance
		and instance:IsA("ScreenGui")
		and instance.Name == "DungeonHUD"
end

local function currentPlayerLevel()
	return math.max(
		1,
		math.floor(
			tonumber(player:GetAttribute("PlayerLevel"))
				or tonumber(player:GetAttribute("Level"))
				or 1
		)
	)
end

local function directPlayerStatusLevelText(hud)
	if not validHud(hud) then
		return nil
	end

	local playerStatus = hud:FindFirstChild("PlayerStatus", true)
	if not playerStatus or not playerStatus:IsA("GuiObject") then
		return nil
	end

	-- IMPORTANTE: FindFirstChild sem recursive=true. O LevelText autorado e filho
	-- direto de PlayerStatus; nao devemos capturar outro LevelText do Portrait,
	-- minimapa ou qualquer outro componente do HUD.
	local levelText = playerStatus:FindFirstChild("LevelText")
	if levelText and (
		levelText:IsA("TextLabel")
		or levelText:IsA("TextButton")
		or levelText:IsA("TextBox")
	) then
		return levelText
	end

	return nil
end

local function updatePlayerStatusLevelText(hud)
	local levelText = directPlayerStatusLevelText(hud)
	if not levelText then
		player:SetAttribute("DungeonPlayerStatusLevelTextBound", false)
		return false
	end

	levelText.Text = tostring(currentPlayerLevel())
	levelText:SetAttribute("DungeonLevelSource", "PlayerLevel")
	player:SetAttribute("DungeonPlayerStatusLevelTextBound", true)
	player:SetAttribute("DungeonPlayerStatusLevelTextValue", currentPlayerLevel())
	return true
end

local function bindPlayerStatusLevelText(hud)
	if not validHud(hud) then
		return
	end

	updatePlayerStatusLevelText(hud)
	if levelTextBindings[hud] then
		return
	end

	local connections = {}
	levelTextBindings[hud] = connections

	-- Se o LevelText/PlayerStatus chegar alguns frames depois por clone/sync,
	-- sincroniza assim que entrar no HUD.
	table.insert(connections, hud.DescendantAdded:Connect(function(instance)
		if instance.Name == "LevelText" or instance.Name == "PlayerStatus" then
			task.defer(updatePlayerStatusLevelText, hud)
		end
	end))
end

local function configure(hud)
	hud.Enabled = true
	hud.ResetOnSpawn = false
	hud:SetAttribute("ResponsiveGenericOptOut", true)
	hud:SetAttribute("DungeonHUDBootstrapReady", true)
	scanVisibilityAttributes(hud)
	bindPlayerStatusLevelText(hud)
	return hud
end

local function currentHud()
	local hud = playerGui:FindFirstChild("DungeonHUD")
	return validHud(hud) and hud or nil
end

local function starterHud()
	local direct = StarterGui:FindFirstChild("DungeonHUD")
	if validHud(direct) then
		return direct
	end

	for _, descendant in ipairs(StarterGui:GetDescendants()) do
		if validHud(descendant) then
			return descendant
		end
	end

	return nil
end

local function ensureHud()
	local existing = currentHud()
	if existing then
		player:SetAttribute("DungeonHUDSource", "PlayerGui")
		return configure(existing)
	end

	local source = starterHud()
	if not source then
		return nil
	end

	local clone = source:Clone()
	clone.Name = "DungeonHUD"
	clone:SetAttribute("ClonedByDungeonHUDBootstrap", true)
	configure(clone)
	clone.Parent = playerGui

	player:SetAttribute("DungeonHUDSource", "StarterGuiClone")
	return clone
end

-- Aplica a politica tambem a GUIs que nao pertencem ao DungeonHUD.
scanVisibilityAttributes(playerGui)
playerGui.DescendantAdded:Connect(function(instance)
	task.defer(bindVisibilityAttribute, instance)
end)

-- Resolve o HUD imediatamente.
local hud = ensureHud()

-- StarterGui pode chegar alguns frames depois no Studio/Rojo.
if not hud then
	local deadline = os.clock() + 30
	while not hud and os.clock() < deadline do
		task.wait(0.05)
		hud = ensureHud()
	end
end

if hud then
	player:SetAttribute("DungeonHUDBootstrapReady", true)
	player:SetAttribute("DungeonHUDBootstrapError", nil)
	player:SetAttribute("DungeonGUIInvisibleAttributePolicy", "invisible=true => hidden")
	updatePlayerStatusLevelText(hud)

	print(
		"[DungeonHUDBootstrap] DungeonHUD pronto; atributo invisible=true respeitado."
	)
else
	player:SetAttribute("DungeonHUDBootstrapReady", false)
	player:SetAttribute(
		"DungeonHUDBootstrapError",
		"StarterGui.DungeonHUDMissing"
	)

	warn(
		"[DungeonHUDBootstrap] StarterGui.DungeonHUD nao existe. "
			.. "O HUD precisa permanecer criado manualmente no StarterGui."
	)
end

-- PlayerLevel e a autoridade atual usada pelo fluxo de level-up. Level fica
-- somente como fallback de compatibilidade para dados/sistemas antigos.
player:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
	local activeHud = currentHud()
	if activeHud then
		updatePlayerStatusLevelText(activeHud)
	end
end)
player:GetAttributeChangedSignal("Level"):Connect(function()
	if player:GetAttribute("PlayerLevel") == nil then
		local activeHud = currentHud()
		if activeHud then
			updatePlayerStatusLevelText(activeHud)
		end
	end
end)

-- Evita uma segunda copia automatica do DungeonHUD apos o carregamento.
playerGui.ChildAdded:Connect(function(child)
	bindVisibilityAttribute(child)

	if not validHud(child) then
		return
	end

	local active = currentHud()
	if not active then
		configure(child)
		return
	end

	if child ~= active then
		task.defer(function()
			if child.Parent == playerGui
				and active.Parent == playerGui
			then
				child:Destroy()
			end
		end)
	end
end)
