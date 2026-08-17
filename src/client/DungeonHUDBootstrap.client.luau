--[[
	Infinity Islands - DungeonHUDBootstrap

	Responsabilidades:
	1. garantir que o DungeonHUD autorado no Studio exista em PlayerGui;
	2. respeitar o atributo GUI `invisible = true` como override autoral.

	Nenhum elemento visual e criado aqui alem do clone completo do DungeonHUD
	quando o Roblox ainda nao o copiou para PlayerGui.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local visibilityBindings = setmetatable({}, { __mode = "k" })

local function isVisibilityObject(instance)
	return instance:IsA("GuiObject") or instance:IsA("LayerCollector")
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

local function configure(hud)
	hud.Enabled = true
	hud.ResetOnSpawn = false
	hud:SetAttribute("ResponsiveGenericOptOut", true)
	hud:SetAttribute("DungeonHUDBootstrapReady", true)
	scanVisibilityAttributes(hud)
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
