--[[
	SkyDungeon - Loja da vila

	Usa ProximityPrompt nativo (teclado, controle e celular) e valida todas as
	compras/equipamentos no servidor. A interface recebe somente o catalogo
	sanitizado do SwordProgressionService.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local SwordProgressionService = require(script.Parent.MVPSystems:WaitForChild("SwordProgressionService"))
local ScoreService = require(script.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))

local SHOP_TAG = MVPConfig.Village.ShopTag
local MAX_SESSION_DISTANCE = MVPConfig.Village.PromptDistance + 4
local activeVillagers = setmetatable({}, { __mode = "k" })
local playerSessions = {}

local villagerEvent = ReplicatedStorage:FindFirstChild("VillagerEvent")
if not villagerEvent then
	villagerEvent = Instance.new("RemoteEvent")
	villagerEvent.Name = "VillagerEvent"
	villagerEvent.Parent = ReplicatedStorage
end

SwordProgressionService.Start()

local function getRoot(model)
	local root = model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function ensureBillboard(model, root)
	if model:FindFirstChild("SwordShopLabel", true) then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SwordShopLabel"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(180, 48)
	billboard.StudsOffset = Vector3.new(0, 4.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 65
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 20, 34)
	label.BackgroundTransparency = 0.12
	label.Text = "⚔ LOJA DE ESPADAS"
	label.TextColor3 = Color3.fromRGB(255, 225, 120)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(160, 105, 255)
	stroke.Thickness = 2
	stroke.Parent = label
end

local function sendShop(player, message, success)
	villagerEvent:FireClient(player, {
		action = "showShop",
		inventory = SwordProgressionService.GetShopInventory(player),
		score = ScoreService.GetScore(player),
		equippedSword = player:GetAttribute("EquippedSword"),
		message = message,
		success = success,
	})
end

local function isSessionValid(player)
	local villager = playerSessions[player]
	if not villager or not villager.Parent or not activeVillagers[villager] then
		return false
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local villagerRoot = getRoot(villager)
	return playerRoot ~= nil
		and villagerRoot ~= nil
		and (playerRoot.Position - villagerRoot.Position).Magnitude <= MAX_SESSION_DISTANCE
end

local function registerVillager(model)
	if not model:IsA("Model") or activeVillagers[model] then
		return
	end
	local root = getRoot(model)
	if not root then
		warn("[VillageShop] Villager sem BasePart: " .. model:GetFullName())
		return
	end
	activeVillagers[model] = true
	ensureBillboard(model, root)

	local prompt = root:FindFirstChild("SwordShopPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SwordShopPrompt"
		prompt.ActionText = "Abrir Loja"
		prompt.ObjectText = "Mercador de Espadas"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = MVPConfig.Village.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
	end

	prompt.Triggered:Connect(function(player)
		if player.Parent ~= Players then
			return
		end
		playerSessions[player] = model
		sendShop(player)
	end)
	model.Destroying:Connect(function()
		activeVillagers[model] = nil
		for player, villager in pairs(playerSessions) do
			if villager == model then
				playerSessions[player] = nil
				villagerEvent:FireClient(player, { action = "closeShop" })
			end
		end
	end)
end

for _, model in ipairs(CollectionService:GetTagged(SHOP_TAG)) do
	task.defer(registerVillager, model)
end
CollectionService:GetInstanceAddedSignal(SHOP_TAG):Connect(function(model)
	task.defer(registerVillager, model)
end)

villagerEvent.OnServerEvent:Connect(function(player, data)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end
	if data.action == "closeShop" then
		playerSessions[player] = nil
		return
	end
	if not isSessionValid(player) then
		playerSessions[player] = nil
		villagerEvent:FireClient(player, {
			action = "shopError",
			message = "Aproxime-se novamente do mercador.",
		})
		return
	end

	local swordId = type(data.swordId) == "string" and data.swordId or ""
	if data.action == "purchaseSword" then
		local success, message = SwordProgressionService.Purchase(player, swordId)
		sendShop(player, message, success)
	elseif data.action == "equipSword" then
		local success, message = SwordProgressionService.Equip(player, swordId)
		sendShop(player, message, success)
	elseif data.action == "refreshShop" then
		sendShop(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerSessions[player] = nil
end)

print("[VillageShop] Loja de espadas iniciada com ProximityPrompt mobile.")
