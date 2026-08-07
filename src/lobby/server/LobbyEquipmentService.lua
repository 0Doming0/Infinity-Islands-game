local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CompanionCatalog = require(ReplicatedStorage:WaitForChild("CompanionCatalog"))
local MonetizationCatalog = require(ReplicatedStorage:WaitForChild("MonetizationCatalog"))
local SwordCatalog = require(ReplicatedStorage:WaitForChild("SwordCatalog"))
local EquipmentConfig = require(ReplicatedStorage.Shared.Configs.EquipmentConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local BlockParkour = script.Parent.Parent:WaitForChild("BlockParkour")
local PlayerDataService = require(script.Parent.LobbyPlayerDataService)

local LobbyEquipmentService = {}
local request
local event
local started = false

local function syncOwnedWings(player)
	for wingId in pairs(EquipmentConfig.Wings) do
		local definition = MonetizationCatalog.Get(wingId)
		if definition and definition.ProductType == "GamePass" and (tonumber(definition.PassId) or 0) > 0 then
			local success, owns = pcall(
				MarketplaceService.UserOwnsGamePassAsync,
				MarketplaceService,
				player.UserId,
				definition.PassId
			)
			if success and owns then
				PlayerDataService.GrantWings(player, wingId)
			end
		end
	end
end

local function configuredEquipmentFolder(category)
	local gameContent = ServerStorage:FindFirstChild("GameContent")
	local equipment = gameContent and gameContent:FindFirstChild("Equipment")
	local configured = equipment and equipment:FindFirstChild(category)
	if configured and #configured:GetChildren() > 0 then
		return configured
	end
	local legacy = ServerStorage:FindFirstChild("MVPAssets")
	local legacyName = category == "Companions" and "Monsters" or category
	return legacy and legacy:FindFirstChild(legacyName) or configured
end

local function findAsset(category, equipmentId)
	local folder = configuredEquipmentFolder(category)
	if not folder then
		return nil
	end
	local exact = folder:FindFirstChild(equipmentId, true)
	if exact then
		return exact
	end
	local attributeName = category == "Swords" and "SwordId"
		or category == "Companions" and "MonsterId"
		or "EquipmentId"
	for _, candidate in ipairs(folder:GetDescendants()) do
		if candidate:GetAttribute(attributeName) == equipmentId then
			return candidate
		end
	end
	return nil
end

local function cleanVisualClone(template, visualName)
	if not template then
		return nil
	end
	local source = template:Clone()
	local model
	if source:IsA("Model") then
		model = source
	else
		model = Instance.new("Model")
		for _, child in ipairs(source:GetChildren()) do
			child.Parent = model
		end
		if source:IsA("BasePart") then
			source.Parent = model
		else
			source:Destroy()
		end
	end
	model.Name = visualName
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("Humanoid") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	local root = model:FindFirstChild("Handle", true)
		or model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root
	return model
end

local function weldModel(model, target, relativeCFrame)
	model:PivotTo(target.CFrame * relativeCFrame)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			local connected = false
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
					connected = true
					break
				end
			end
			if not connected then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = model.PrimaryPart
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	local attachment = Instance.new("WeldConstraint")
	attachment.Name = "LobbyCosmeticWeld"
	attachment.Part0 = target
	attachment.Part1 = model.PrimaryPart
	attachment.Parent = model.PrimaryPart
end

local function clearVisuals(character)
	local existing = character:FindFirstChild("LobbyEquipmentVisuals")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "LobbyEquipmentVisuals"
	folder.Parent = character
	return folder
end

local function applyCosmeticVisuals(player)
	local data = PlayerDataService.Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local visuals = clearVisuals(character)
	local sword = cleanVisualClone(findAsset("Swords", data.EquippedSword), "Sword")
	if sword then
		sword.Parent = visuals
		weldModel(sword, torso, CFrame.new(0.9, 0.2, 0.75) * CFrame.Angles(0, 0, math.rad(135)))
	end
	if data.EquippedWings then
		local wings = cleanVisualClone(findAsset("Wings", data.EquippedWings), "Wings")
		if wings then
			wings.Parent = visuals
			weldModel(wings, torso, CFrame.new(0, 0.2, 0.8) * CFrame.Angles(math.rad(90), 0, 0))
		end
	end
	local equippedCompanion = data.EquippedCompanions[1]
	local companionRecord = equippedCompanion and data.OwnedCompanions[equippedCompanion]
	if companionRecord then
		local companion = cleanVisualClone(
			findAsset("Companions", companionRecord.SpeciesId),
			"Companion"
		)
		if companion then
			pcall(companion.ScaleTo, companion, 0.35)
			companion.Parent = visuals
			weldModel(companion, torso, CFrame.new(-1.8, 1.6, 0))
		end
	end
	character:SetAttribute("LobbyCosmeticOnly", true)
end

local function dictionaryEntries(definitions, owned, equipped)
	local result = {}
	for equipmentId, definition in pairs(definitions) do
		table.insert(result, {
			EquipmentId = equipmentId,
			DisplayName = definition.DisplayName,
			Owned = owned[equipmentId] == true,
			Equipped = equipped == equipmentId,
		})
	end
	table.sort(result, function(left, right)
		return left.DisplayName < right.DisplayName
	end)
	return result
end

function LobbyEquipmentService.GetSnapshot(player)
	local data = PlayerDataService.Get(player) or PlayerDataService.Load(player)
	syncOwnedWings(player)
	data = PlayerDataService.Get(player) or data
	local swords = {}
	for _, definition in ipairs(SwordCatalog.GetAll()) do
		table.insert(swords, {
			EquipmentId = definition.SwordId,
			DisplayName = definition.DisplayName,
			Owned = data.OwnedSwords[definition.SwordId] == true,
			Equipped = data.EquippedSword == definition.SwordId,
		})
	end
	local companions = {}
	for instanceId, record in pairs(data.OwnedCompanions) do
		local definition = CompanionCatalog.Get(record.SpeciesId)
		table.insert(companions, {
			EquipmentId = instanceId,
			SpeciesId = record.SpeciesId,
			DisplayName = record.DisplayName or (definition and definition.DisplayName) or record.SpeciesId,
			Owned = true,
			Equipped = table.find(data.EquippedCompanions, instanceId) ~= nil,
		})
	end
	table.sort(companions, function(left, right)
		return left.DisplayName < right.DisplayName
	end)
	return {
		Swords = swords,
		Wings = dictionaryEntries(EquipmentConfig.Wings, data.OwnedWings, data.EquippedWings),
		Companions = companions,
		Abilities = dictionaryEntries(EquipmentConfig.Abilities, data.OwnedAbilities, data.EquippedAbility),
	}
end

local function setEquipment(player, category, equipmentId)
	local success = false
	if category == "Swords" then
		success = PlayerDataService.SetEquippedSword(player, equipmentId)
	elseif category == "Wings" then
		success = PlayerDataService.SetEquippedWings(player, equipmentId)
	elseif category == "Abilities" then
		success = PlayerDataService.SetEquippedAbility(player, equipmentId)
	elseif category == "Companions" then
		local _, equipped = PlayerDataService.GetCompanions(player)
		for _, current in ipairs(equipped) do
			PlayerDataService.SetCompanionEquipped(player, current, false)
		end
		success = PlayerDataService.SetCompanionEquipped(player, equipmentId, true)
	end
	if success then
		PlayerDataService.Save(player, false)
		applyCosmeticVisuals(player)
	end
	return success
end

function LobbyEquipmentService.Open(player)
	event:FireClient(player, { Action = "Open", Snapshot = LobbyEquipmentService.GetSnapshot(player) })
end

function LobbyEquipmentService.Start()
	if started then
		return
	end
	started = true
	request = RemoteRegistry.Get("Equipment", "Request", "RemoteFunction")
	event = RemoteRegistry.Get("Equipment", "Event", "RemoteEvent")
	request.OnServerInvoke = function(player, action, category, equipmentId)
		if action == "Get" then
			return { Success = true, Snapshot = LobbyEquipmentService.GetSnapshot(player) }
		elseif action == "Set" and type(category) == "string" and type(equipmentId) == "string" then
			local success = setEquipment(player, category, equipmentId)
			return {
				Success = success,
				Message = success and "Equipamento atualizado." or "Equipamento indisponivel.",
				Snapshot = LobbyEquipmentService.GetSnapshot(player),
			}
		end
		return { Success = false, Message = "Acao invalida." }
	end
	local function setup(player)
		player.CharacterAdded:Connect(function()
			task.defer(applyCosmeticVisuals, player)
		end)
		if player.Character then
			task.defer(applyCosmeticVisuals, player)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
end

return LobbyEquipmentService
