local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseConfig = require(ReplicatedStorage.Shared.Configs.PhaseConfig)
local RouletteConfig = require(ReplicatedStorage.Shared.Configs.RouletteConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Utilities.RemoteRegistry)
local PhaseSelectionService = require(script.Parent.PhaseSelectionService)
local LobbyRouletteService = require(script.Parent.LobbyRouletteService)
local LobbyEquipmentService = require(script.Parent.LobbyEquipmentService)

local LobbyInteractionService = {}
local notifications
local connections = setmetatable({}, { __mode = "k" })
local started = false

local function interactionPart(instance)
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function ensurePrompt(instance, actionText, objectText)
	local part = interactionPart(instance)
	if not part then
		warn("[Lobby] Objeto marcado sem BasePart: " .. instance:GetFullName())
		return nil
	end
	local prompt = part:FindFirstChild("LobbyInteractionPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LobbyInteractionPrompt"
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
	end
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	return prompt
end

local function bindPhasePortal(instance)
	local phaseId = instance:GetAttribute("PhaseId")
	local phase = PhaseConfig.Get(phaseId)
	if not phase then
		warn("[Lobby] PhasePortal com PhaseId invalido: " .. instance:GetFullName())
		return
	end
	local prompt = ensurePrompt(instance, "Ver fase", phase.DisplayName)
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			PhaseSelectionService.Open(player, phaseId)
		end)
	end
end

local function bindRoulette(instance)
	local wheelId = instance:GetAttribute("WheelId")
	local wheel = RouletteConfig[wheelId]
	if not wheel then
		warn("[Lobby] RouletteStation com WheelId invalido: " .. instance:GetFullName())
		return
	end
	local prompt = ensurePrompt(instance, "Girar", wheel.DisplayName)
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			LobbyRouletteService.Open(player, wheelId)
		end)
	end
end

local function bindEquipment(instance)
	local prompt = ensurePrompt(instance, "Equipar", "Equipamentos")
	if prompt then
		connections[instance] = prompt.Triggered:Connect(function(player)
			LobbyEquipmentService.Open(player)
		end)
	end
end

local function lobbySpawn()
	for _, tagged in ipairs(CollectionService:GetTagged("LobbySpawn")) do
		local part = interactionPart(tagged)
		if part then
			return part
		end
	end
	return nil
end

local function positionCharacter(character)
	local spawnPart = lobbySpawn()
	if spawnPart then
		character:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
	end
end

local function bindTagged(tag, callback)
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		callback(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		local connection = connections[instance]
		if connection then
			connection:Disconnect()
			connections[instance] = nil
		end
	end)
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(positionCharacter, character)
	end)
	if player.Character then
		task.defer(positionCharacter, player.Character)
	end
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if type(teleportData) == "table" and teleportData.ReturnReason then
		task.delay(1, function()
			if player.Parent == Players then
				notifications:FireClient(player, {
					Action = "ReturnToLobby",
					ReturnReason = teleportData.ReturnReason,
					PhaseId = teleportData.PhaseId,
				})
			end
		end)
	end
end

function LobbyInteractionService.Start()
	if started then
		return
	end
	started = true
	notifications = RemoteRegistry.Get("Notifications", "Lobby", "RemoteEvent")
	bindTagged("PhasePortal", bindPhasePortal)
	bindTagged("RouletteStation", bindRoulette)
	bindTagged("EquipmentStation", bindEquipment)
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
end

return LobbyInteractionService
