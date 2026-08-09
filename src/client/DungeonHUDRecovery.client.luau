--[[
	Infinity Islands - Authored HUD Recovery V1

	Objetivo:
	- preservar o DungeonHUD desenhado manualmente em StarterGui;
	- copiar o HUD cedo para PlayerGui mesmo com CharacterAutoLoads=false;
	- permitir que DungeonArtHUDController encontre o HUD;
	- se o controller antigo ja tiver encerrado por timeout, executa uma unica
	  copia de recuperacao depois que o HUD existir.

	Este script NAO desenha HUD por codigo.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")

local activeHud
local recoveryStarted = false

local function validHud(instance)
	return instance
		and instance:IsA("ScreenGui")
		and instance.Name == "DungeonHUD"
end

local function configureHud(hud)
	if not validHud(hud) then
		return nil
	end

	hud.Enabled = true
	hud.ResetOnSpawn = false
	hud:SetAttribute("ResponsiveGenericOptOut", true)

	return hud
end

local function getStarterHud()
	local hud = StarterGui:FindFirstChild("DungeonHUD")
	return validHud(hud) and hud or nil
end

local function getPlayerHud()
	local hud = playerGui:FindFirstChild("DungeonHUD")
	return validHud(hud) and hud or nil
end

local function ensureHud()
	local existing = getPlayerHud()

	if existing then
		activeHud = configureHud(existing)
		return activeHud
	end

	local source = getStarterHud()

	if not source then
		return nil
	end

	local clone = source:Clone()
	clone.Name = "DungeonHUD"
	clone:SetAttribute("HUDRecoveryClone", true)
	configureHud(clone)
	clone.Parent = playerGui

	activeHud = clone

	player:SetAttribute("DungeonHUDRecoveryReady", true)
	player:SetAttribute("DungeonHUDRecoverySource", "StarterGui")

	return clone
end

local function runControllerRecovery()
	if recoveryStarted then
		return
	end

	if player:GetAttribute("DungeonArtHUDControllerReady") == true then
		return
	end

	local original = playerScripts:FindFirstChild("DungeonArtHUDController")

	if not original or not original:IsA("LocalScript") then
		warn("[HUDRecovery] DungeonArtHUDController nao encontrado em PlayerScripts.")
		return
	end

	recoveryStarted = true

	local retry = original:Clone()
	retry.Name = "DungeonArtHUDController_Recovery"
	retry:SetAttribute("HUDRecoveryRun", true)
	retry.Parent = playerScripts

	player:SetAttribute("DungeonHUDControllerRecoveryStarted", true)

	print("[HUDRecovery] HUD encontrado; controller reiniciado uma vez.")
end

-- Evita duas copias quando StarterGui for copiado automaticamente no LoadCharacter.
playerGui.ChildAdded:Connect(function(child)
	if not validHud(child) then
		return
	end

	if not activeHud or not activeHud.Parent then
		activeHud = configureHud(child)
		return
	end

	if child ~= activeHud then
		task.defer(function()
			if child.Parent == playerGui
				and activeHud
				and activeHud.Parent == playerGui
			then
				child:Destroy()
			end
		end)
	end
end)

task.spawn(function()
	local warned = false

	while not activeHud or not activeHud.Parent do
		local hud = ensureHud()

		if hud then
			break
		end

		if not warned and os.clock() > 8 then
			warned = true
			warn(
				"[HUDRecovery] Aguardando StarterGui.DungeonHUD. "
					.. "Nao remova o HUD manual do StarterGui."
			)
		end

		task.wait(0.10)
	end

	if not activeHud then
		return
	end

	-- Da ao controller original uma chance curta de concluir normalmente.
	local deadline = os.clock() + 2.0

	while os.clock() < deadline do
		if player:GetAttribute("DungeonArtHUDControllerReady") == true then
			return
		end

		if player:GetAttribute("DungeonArtHUDFailure")
			== "AuthoredDungeonHUDNotFound"
		then
			break
		end

		task.wait(0.10)
	end

	runControllerRecovery()
end)
