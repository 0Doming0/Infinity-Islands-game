-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

-- Eventos raros, anunciados e nunca simultaneos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local MobEventModifiers = require(script.Parent.BlockParkour:WaitForChild("MobEventModifiers"))
local CURRENCY_SYMBOL = MVPConfig.Currency.Symbol
local eventRemote = ReplicatedStorage:FindFirstChild("WorldEvent") or Instance.new("RemoteEvent")
eventRemote.Name = "WorldEvent"
eventRemote.Parent = ReplicatedStorage

local random = Random.new()
local serial = 0
local lastEvent

local definitions = {
	{
		Id = "RisingTide",
		Title = "MARE FURIOSA",
		Message = "A agua vai subir muito mais rapido!",
		Color = Color3.fromRGB(100, 190, 255),
		Duration = MVPConfig.Events.RisingTideDurationSeconds,
		Start = function()
			workspace:SetAttribute(MVPConfig.Water.EventMultiplierAttribute, MVPConfig.Events.RisingTideMultiplier)
		end,
		Stop = function()
			workspace:SetAttribute(MVPConfig.Water.EventMultiplierAttribute, 1)
		end,
	},
	{
		Id = "CoinRush",
		Title = CURRENCY_SYMBOL .. " CHUVA DE MOEDAS",
		Message = CURRENCY_SYMBOL .. " Todas as recompensas de moeda estao dobradas!",
		Color = Color3.fromRGB(255, 211, 76),
		Duration = MVPConfig.Events.CoinRushDurationSeconds,
		Start = function()
			workspace:SetAttribute("CoinRewardMultiplier", MVPConfig.Events.CoinRushMultiplier)
		end,
		Stop = function()
			workspace:SetAttribute("CoinRewardMultiplier", 1)
		end,
	},
	{
		Id = "MonsterHunt",
		Title = "CACADA DOS MONSTROS",
		Message = "Inimigos hostis conseguem perceber voce de mais longe!",
		Color = Color3.fromRGB(255, 154, 78),
		Duration = MVPConfig.Events.MonsterHuntDurationSeconds,
		Start = function()
			workspace:SetAttribute("MonsterHuntActive", true)
		end,
		Stop = function()
			workspace:SetAttribute("MonsterHuntActive", false)
		end,
	},
	{
		Id = "WildFury",
		Title = "⚠ FURIA SELVAGEM",
		Message = "Ate as criaturas pacificas se tornaram hostis!",
		Color = Color3.fromRGB(255, 82, 82),
		Duration = MVPConfig.Events.WildFuryDurationSeconds,
		Start = function()
			workspace:SetAttribute("AllMobsAggressive", true)
		end,
		Stop = function()
			workspace:SetAttribute("AllMobsAggressive", false)
		end,
	},
}

workspace:SetAttribute(MVPConfig.Water.EventMultiplierAttribute, 1)
workspace:SetAttribute("CoinRewardMultiplier", 1)
workspace:SetAttribute("MonsterHuntActive", false)
workspace:SetAttribute("AllMobsAggressive", false)
MobEventModifiers.Start()

local function chooseEvent()
	local candidates = {}
	for _, definition in ipairs(definitions) do
		if definition.Id ~= lastEvent then
			table.insert(candidates, definition)
		end
	end
	return candidates[random:NextInteger(1, #candidates)]
end

local function runEvent(definition)
	serial += 1
	local token = serial
	lastEvent = definition.Id
	workspace:SetAttribute("ActiveWorldEvent", definition.Id)
	definition.Start()
	eventRemote:FireAllClients({
		Action = "Start",
		Id = definition.Id,
		Title = definition.Title,
		Message = definition.Message,
		Color = definition.Color,
		Duration = definition.Duration,
	})
	task.wait(definition.Duration)
	if token ~= serial then
		return
	end
	definition.Stop()
	workspace:SetAttribute("ActiveWorldEvent", nil)
	eventRemote:FireAllClients({ Action = "Stop", Id = definition.Id })
end

task.spawn(function()
	task.wait(MVPConfig.Events.FirstEventDelaySeconds)
	while true do
		if #Players:GetPlayers() > 0 then
			runEvent(chooseEvent())
			task.wait(random:NextNumber(
				MVPConfig.Events.MinimumIntervalSeconds,
				MVPConfig.Events.MaximumIntervalSeconds
			))
		else
			task.wait(15)
		end
	end
end)
