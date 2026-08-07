local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameContext = require(ReplicatedStorage.Shared.GameContext)
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PartyService = require(BlockParkour.PartyService)
local PlayerDataService = require(script.Parent.LobbyPlayerDataService)
local LobbyPhaseCatalogService = require(script.Parent.LobbyPhaseCatalogService)
local PhaseSelectionService = require(script.Parent.PhaseSelectionService)
local LobbyRouletteService = require(script.Parent.LobbyRouletteService)
local LobbyEquipmentService = require(script.Parent.LobbyEquipmentService)
local LobbyInteractionService = require(script.Parent.LobbyInteractionService)

GameContext.SetCurrentPlaceType("Lobby")
workspace:SetAttribute("GamePlaceType", "Lobby")
workspace:SetAttribute("LobbyRuntimeManaged", true)
workspace:SetAttribute("DungeonRuntimeManaged", false)
workspace:SetAttribute("LobbyRuntimeReady", false)
workspace:SetAttribute("LobbyRuntimeError", nil)

local function startService(name, callback)
	local ok, result = pcall(callback)
	if not ok then
		workspace:SetAttribute("LobbyRuntimeError", name .. ": " .. tostring(result))
		warn(string.format("[LobbyBootstrap] %s falhou: %s", name, tostring(result)))
		return false
	end
	return result ~= false
end

local servicesReady = true
servicesReady = startService("PhaseCatalog", LobbyPhaseCatalogService.Load) and servicesReady
servicesReady = startService("PartyService", PartyService.Start) and servicesReady
servicesReady = startService("PhaseSelection", PhaseSelectionService.Start) and servicesReady
servicesReady = startService("Roulette", LobbyRouletteService.Start) and servicesReady
servicesReady = startService("Equipment", LobbyEquipmentService.Start) and servicesReady
servicesReady = startService("Interactions", LobbyInteractionService.Start) and servicesReady

local function removeFunctionalTools(container)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			child:Destroy()
		end
	end)
end

local function setupPlayer(player)
	PlayerDataService.Load(player)
	player:SetAttribute("LobbyCombatDisabled", true)
	player:SetAttribute("CanFly", false)
	player:SetAttribute("AbilitiesDisabled", true)
	player:SetAttribute("CompanionCombatDisabled", true)
	player:SetAttribute("DungeonRuntimeManaged", false)
	removeFunctionalTools(player:WaitForChild("Backpack"))
	player.CharacterAdded:Connect(function(character)
		character:SetAttribute("LobbyCosmeticOnly", true)
		removeFunctionalTools(character)
	end)
	if player.Character then
		player.Character:SetAttribute("LobbyCosmeticOnly", true)
		removeFunctionalTools(player.Character)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)
Players.PlayerRemoving:Connect(function(player)
	PlayerDataService.Save(player, true)
	PlayerDataService.Release(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerDataService.Save(player, true)
	end
end)

workspace:SetAttribute("LobbyRuntimeReady", servicesReady)
