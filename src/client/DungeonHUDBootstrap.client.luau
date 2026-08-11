--[[
	Infinity Islands - DungeonHUDBootstrap V1

	Single responsibility:
	Guarantee the designer-authored StarterGui.DungeonHUD exists in PlayerGui
	before DungeonArtHUDController performs its binding.

	This script DOES NOT create visual elements.
	It only clones the complete authored ScreenGui if Roblox has not copied it yet.

	Expected Studio hierarchy:
	StarterGui
	└── DungeonHUD [ScreenGui]
	    ├── ObjectivePanel
	    ├── PlayerStatus
	    ├── MiniMap
	    └── MissionsPanel (optional)
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

-- Resolve immediately.
local hud = ensureHud()

-- StarterGui can arrive a few frames later in Studio/Rojo.
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

	print(
		"[DungeonHUDBootstrap] DungeonHUD pronto em PlayerGui. "
			.. "DungeonArtHUDController pode fazer o binding."
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

-- Prevent duplicate automatic StarterGui copy after character loading.
playerGui.ChildAdded:Connect(function(child)
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
